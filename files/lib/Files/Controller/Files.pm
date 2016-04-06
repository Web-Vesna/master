package Files::Controller::Files;
use Mojo::Base 'Mojolicious::Controller';

use strict;
use warnings;

use Cache::Memcached;
use MIME::Base64 qw( encode_base64url decode_base64url );
use Encode qw( decode );
use File::stat;

use DB qw( :all );
use AccessDispatcher qw( check_session _session redirect_to_login );
use MainConfig qw( :all );

sub open_memc {
    my $self = shift;
    $self->{memc} = Cache::Memcached->new({
        servers => [ MEMC_HOST . ':' . MEMC_PORT ],
    }) unless defined $self->{memc};

    $self->app->log->error("Can't open connection to Memcached") unless $self->{memc};
}

sub load_paths {
    my $self = shift;
    $self->open_memc;

    unless ($self->{memc}->get('files_cache_expire_flag')) {
        my $r = select_all($self, 'select f.id as id, f.path as path, d.name as district, d.id as district_id, ' .
            'c.id as company_id, c.name as company from files f ' .
            'join districts d on d.id = f.district_id join companies c on c.id = f.company_id');

        return $self->app->log->error("Can't fetch files from DB") unless $r;

        for my $row (@$r) {
            $self->{memc}->set('files_paths_cache_' . $row->{district_id} . '_' . $row->{company_id}, $row, EXP_TIME);
        }

        $r = select_all($self, 'select id, company_id, district_id from buildings order by company_id');
        return $self->app->log->error("Can't fetch buildings from DB") unless $r;

        my @company;
        my $last_comp = "";
        for my $row (@$r) {
            my $new_comp = $row->{district_id} . "_" . $row->{company_id};
            if ($last_comp ne $new_comp) {
                $self->{memc}->set("photos_paths_cache_$last_comp", \@company, EXP_TIME)
                if @company;
                @company = ();
            }

            $last_comp = $new_comp;
            push @company, $row->{id};
        }

        $self->{memc}->set('files_cache_expire_flag', 1, EXP_TIME) if @$r;
    }
}

sub add_headers {
    my $self = shift;
    $self->res->headers->header('Access-Control-Allow-Origin' => ALLOW_ORIGIN);
    $self->res->headers->header('Access-Control-Allow-Credentials' => 'true');
}

sub list {
    my $self = shift;

    $self->add_headers;
    my $ret = check_session $self;

    _session($self, { expired => 1 }) if $ret->{error};
    return redirect_to_login($self) if $ret->{error} && $ret->{error} eq 'unauthorized';

    $self->load_paths;

    my ($district_id, $company_id) = map { $self->param($_) } qw( district company );
    return $self->render(json => { error => "district and company args are required" })
        unless defined $district_id and defined $company_id;

    my $data;
    my $i = 0;
    while (not $data and $i < 2) {
        $data = $self->{memc}->get("files_paths_cache_$district_id" . "_$company_id");
        $self->load_paths unless $data;
        ++$i;
    }

    return $self->render(json => { error => "invalid district or company" }) unless $data;

    my $addresses = ($self->{memc}->get("photos_paths_cache_$district_id" . "_$company_id") // []);

    my $dir;
    my $path = ROOT_FILES_PATH . "/$data->{path}";
    opendir $dir, $path;
    my @files = readdir $dir;
    closedir $dir;

    my @content;

    $i = 0;
    for my $f (sort @files) {
        my $fname = decode('utf8', $f);

        next if $fname =~ /^\.\.?$/;
        my $s = stat "$path/$fname";

        my $data = encode_base64url pack "iiiiii", $district_id, $company_id, $i, $s->size, $s->mtime, 0;
        push @content, {
            name => $fname,
            size => $s->size,
            url => GENERAL_URL . "/file?f=$data",
        };
        $i++;
    }

    my %photos;
    for my $id (@$addresses) {
        $path = PHOTOS_PATH . "/$id";

        opendir $dir, $path
            or next;

        my @files = readdir $dir;
        closedir $dir;

        my @res;
        my $i = 0;
        for my $f (sort @files) {
            my $fname = decode('utf8', $f);

            next if $fname =~ /^\.\.?$/;
            my $s = stat "$path/$fname";

            my $data = encode_base64url pack "iiiiii", $district_id, $company_id, $i, $s->size, $s->mtime, $id;
            push @res, { href => GENERAL_URL . "/file?p=$data", title => $fname };
            $i++;
        }

        $photos{$id} = \@res;
    }

    return $self->render(json => { photos => \%photos, files => \@content, count => scalar @content });
}

sub render_photo {
    my ($self, $district_id, $company_id, $index, $size, $mtime, $building_id) = @_;
    my $data = $self->{memc}->get("photos_paths_cache_$district_id" . "_$company_id");

    return $self->render(json => { error => "invalid photo" }) unless $data;

    my $dir;
    my $path = PHOTOS_PATH . "/$building_id";
    opendir $dir, $path;
    my @files = grep { not /^\.\.?$/ } sort readdir $dir;
    closedir $dir;

    $path = "$path/" . decode('utf8', $files[$index]);
    my $s = stat $path;

    return $self->redirect_to(URL_404) unless $s;

    if ($s->size != $size or $s->mtime != $mtime) {
        $self->app->log->error("File outdated");
        return $self->redirect_to(URL_404);
    }

    my ($ext) = $files[$index] =~ /\.(\S+)$/;
    $self->render_file(filepath => $path, filename => $files[$index], format => ($ext || 'jpg'), 'content_disposition' => 'inline',);
    return $self->rendered(200);
}

sub get {
    my $self = shift;

    $self->add_headers;
    $self->load_paths;

    my $ret = check_session $self;

    _session($self, { expired => 1 }) if $ret->{error};
    return redirect_to_login($self) if $ret->{error} && $ret->{error} eq 'unauthorized';

    my $f_info = $self->param('f') // "";
    my $p_info = $self->param('p') // "";
    return $self->redirect_to(URL_404) unless $f_info || $p_info;

    my ($district_id, $company_id, $index, $size, $mtime, $building_id) = unpack 'iiiiii', decode_base64url($f_info || $p_info);
    unless (defined $district_id and defined $company_id and defined $index and defined $size and defined $mtime) {
        $self->app->log->error("Invalid f or p hash came: f='$f_info', p='$p_info'");
        return $self->redirect_to(URL_404);
    }

    unless ($f_info) {
        return render_photo($self, $district_id, $company_id, $index, $size, $mtime, $building_id);
    }

    my $data;
    my $i = 0;
    while (not $data and $i < 2) {
        $data = $self->{memc}->get("files_paths_cache_$district_id" . "_$company_id");
        $self->load_paths unless $data;
        ++$i;
    }

    return $self->render(json => { error => "invalid district or company" }) unless $data;

    my $dir;
    my $path = ROOT_FILES_PATH . "/$data->{path}";
    opendir $dir, $path;
    my @files = grep { not /^\.\.?$/ } sort readdir $dir;
    closedir $dir;

    $path = "$path/" . decode('utf8', $files[$index]);
    my $s = stat $path;

    return $self->redirect_to(URL_404) unless $s;

    if ($s->size != $size or $s->mtime != $mtime) {
        $self->app->log->error("File outdated");
        return $self->redirect_to(URL_404);
    }

    $self->render_file(filepath => $path, filename => $files[$index], format => 'pdf', 'content_disposition' => 'inline',);
    return $self->rendered(200);
}

1;
