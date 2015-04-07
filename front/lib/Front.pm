package Front;
use Mojo::Base 'Mojolicious';

use MainConfig qw( :all );
use AccessDispatcher qw( check_access send_request );

use File::Temp;
use Data::Dumper;

use Mojo::JSON qw(decode_json encode_json);
use utf8;

sub check_params {
    my $self = shift;

    my %params;
    my $p = $self->req->params->to_hash;
    for (@_) {
        $params{$_} = $p->{$_};
        return $self->render(status => 400, json => { error => sprintf "%s field is required", ucfirst }) && undef unless $params{$_};
    }

    return \%params;
}

# This method will run once at server start
sub startup {
    my $self = shift;

    # Documentation browser under "/perldoc"
    $self->plugin('PODRenderer');
    $self->secrets([qw( 0i+hE8eWI0pG4DOH55Kt2TSV/CJnXD+gF90wy6O0U0k= )]);

    $self->routes->get('/login' => sub {
        my $self = shift;

        my $params = check_params $self, qw( login password );
        return unless $params;

        my $r = send_request($self,
            method => 'get',
            url => 'login',
            port => SESSION_PORT,
            args => {
                login => $params->{login},
                password => $params->{password},
                user_agent => $self->req->headers->user_agent,
            });

        return _i_err $self unless $r;
        return $self->render(status => 401, json => { error => "internal", description => $r->{error} }) if !$r or $r->{error};

        $self->session(session => $r->{session_id}, expires => time + EXP_TIME);
        return $self->render(json => { ok => 1 });
    });

    my $auth = $self->routes->under('/' => sub {
        my $self = shift;
        my $r = $self->req;

        my $url = $r->url;
        $url =~ m#^/([^?]*)#;

        my $res = check_access $self, method => lc($r->method), url => $1;
        return $self->render(status => 401, json => { error => 'unauthorized', description => $res->{error} }) && undef if $res->{error};

        $self->stash(uid => $res->{uid}, role => $res->{role});
        return $res->{granted} && $res->{granted} == 1;
    });

    $auth->get('/logout' => sub {
        my $self = shift;

        my $r = send_request($self,
            method => 'get',
            url => 'logout',
            port => SESSION_PORT,
            args => {
                user_agent => $self->req->headers->user_agent,
                session_id => $self->session('session'),
            });

        $self->session(expires => 1);
        return $self->render(json => { ok => 1 }) if $r && not $r->{error};
        return $self->_i_err unless $r;
        return $self->render(status => 400, json => { error => "invalid", description => $r->{error} });
    });

    $auth->post('/xls/:method' => sub {
        my $self = shift;
        my $fh = File::Temp->new(UNLINK => 0);

        my $upload = $self->req->upload('file');

        my %expected_headers = map { $_ => 1 } qw (
            vnd.ms-excel
            msexcel
            x-msexcel
            x-ms-excel
            x-excel
            x-dos_ms_excel
            xls
            x-xls
            vnd.openxmlformats-officedocument.spreadsheetml.sheet
        );

        if ($upload->headers->content_type !~ m#application/(\S+)#i || not defined $expected_headers{lc $1}) {
            return $self->render(status => 400, json => { error => 'bad request', description => 'unexpected content type' });
        }

        $self->req->upload('file')->move_to($fh->filename);

        my $response = send_request($self,
            method => $self->req->method,
            url => $self->stash('method'),
            port => DATA_PORT,
            args => { filename => $fh->filename },
        );
        return $self->render(status => 500, json => { error => 'internal' }) unless $response;

        my $status = $response->{status} || 200;
        delete $response->{status};
        return $self->render(status => $status, json => $response);
    });

    $auth->any('/*any' => { any => '' } => sub {
        my $self = shift;
        my $page_name = $self->param('any');

        $self->app->log->debug(length $self->req->body);

        my $response = send_request($self,
            method => $self->req->method,
            url => $page_name,
            port => DATA_PORT,
            args => $self->req->params->to_hash,
            data => $self->req->body,
        );

        return $self->render(status => 500, json => { error => 'internal' }) unless $response;

        my $status = $response->{status} || 200;
        delete $response->{status};
        my $v = encode_json($response);
        utf8::decode($v);
        return $self->render(status => $status, data => $v, format => 'json');
    });
}

1;
