package Session::Controller::Index;
use Mojo::Base 'Mojolicious::Controller';

use DB qw( :all );
use MainConfig qw( :all );
use Digest::MD5 qw( md5_hex );

use Data::Dumper::OneLine;
use Cache::Memcached;

sub _memc_key() { MEMC_KEY }

sub open_memc {
    my $self = shift;
    $self->{memc} = Cache::Memcached->new({
        servers => [ MEMC_HOST . ':' . MEMC_PORT ],
    }) unless defined $self->{memc};

    $self->app->log->error("Can't open connection to Memcached") unless $self->{memc};
}

sub check_session {
    my $self = shift;

    $self->open_memc;

    return $self->render(json => { error => 'session_id not specified' }) unless $self->param('session_id');
    return $self->render(json => { error => 'user_agent not specified' }) unless $self->param('user_agent');

    my $r = $self->{memc}->get(_memc_key . $self->param('session_id'));
    return $self->render(json => { error => 'unauthorized' })
        unless $r and $r->{user_id} and ($r->{user_agent} eq md5_hex($self->param('user_agent')));

    $self->_restore_session($self->param('session_id'), $r);
    return $self->render(json => { ok => 1, uid => $r->{user_id}, role => $r->{role}, name => $r->{name}, lastname => $r->{lastname} });
}

sub about {
    my $self = shift;
    $self->open_memc;

    return $self->render(json => { error => 'session_id not specified' }) unless $self->param('session_id');
    return $self->render(json => { error => 'user_agent not specified' }) unless $self->param('user_agent');

    my $r = $self->{memc}->get(_memc_key . $self->param('session_id'));
    return $self->render(json => { error => 'unauthorized' })
        unless $r and $r->{user_id} and ($r->{user_agent} eq md5_hex($self->param('user_agent')));

    $self->_restore_session($self->param('session_id'), $r);
    $r = select_row($self, 'select u.id as uid, u.name as name, u.lastname as lastname, u.login as login, u.email as email, ' .
        'r.name as role from users u join roles r on r.id = u.role where u.id = ?', $r->{user_id});

    my $objects_count = select_row($self, "select count(id) as count from objects");
    $r->{objects_count} = $objects_count->{count};

    return $self->render(json => { status => 500, error => 'db' }) unless $r;
    return $self->render(json => $r);
}

sub _restore_session {
    my ($self, $id, $data) = @_;
    $self->{memc}->set(_memc_key . "$id", $data, EXP_TIME);
}

sub login {
    my $self = shift;

    $self->open_memc;
    my $came = $self->req->params->to_hash;

    my ($login, $pass, $ua) = @$came{qw( login password user_agent )};
    return $self->render(json => { error => 'login or password or user_agent is not specified' }) unless $login and $pass and $ua;

    my $r = select_row($self, 'select u.id as id, u.pass as pass, u.name as name, u.lastname as lastname, u.email as email, ' .
        'r.name as role from users u join roles r on r.id = u.role where u.login = ?', $login);
    return $self->render(json => { error => 'invalid login or password' }) if not $r or $r->{pass} ne $pass;

    my $sum = md5_hex("$r->{id}" . time . rand(100500) . "$ua");

    $self->_restore_session($sum, {
            user_id => $r->{id}, user_agent => md5_hex($ua), role => $r->{role}, name => $r->{name}, lastname => $r->{lastname} });

    return $self->render(json => { session_id => $sum });
}

sub logout {
    my $self = shift;

    $self->open_memc;
    my $came = $self->req->params->to_hash;
    return $self->render(json => { error => 'session_id not specified' }) unless $came->{session_id};

    $self->{memc}->delete(_memc_key . "$came->{session_id}");

    return $self->render(json => { ok => 1 });
}

1;
