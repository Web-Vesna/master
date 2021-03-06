package Data::Controller::Users;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw( encode_json );

use MainConfig qw( :all );
use AccessDispatcher qw( send_request check_access _session );

use Data::Dumper;

use DB qw( :all );
use Helpers qw( :all );

sub add {
    my $self = shift;

    my $params = check_params $self, qw( login password role );
    return unless $params;

    my $r = select_all($self, "select id, name from roles");
    my $role_id = $params->{role};

    return $self->render(status => 400, json => { error => "invalid", description => "invalid email" })
        unless $params->{email} =~ /^[^@]+@[^@]+$/;

    return $self->render(status => 400, json => { error => "invalid", description => "invalid role" })
        if $role_id =~ /\D/;

    $r = select_row($self, "select id from users where login = ?", $params->{login});
    return $self->render(status => 409, json => { error => 'User already exists' }) if $r;

    $r = execute_query($self, "insert into users(role, login, pass, name, lastname, email) values (?, ?, ?, ?, ?, ?)",
        $role_id, map { $_ // "" } @$params{qw(login password name lastname email)});

    return return_500 $self unless $r;

    $r = send_request($self,
        method => 'get',
        url => 'login',
        port => SESSION_PORT,
        check_session => 0,
        args => {
            login => $params->{login},
            password => $params->{password},
            user_agent => $self->req->headers->user_agent,
        });

    return return_500 $self unless $r;
    return $self->render(status => 401, json => { error => "internal", description => "session: " . $r->{error} }) if !$r or $r->{error};

    _session($self, $r->{session_id}); # TODO: proxy on session service
    return $self->render(json => { ok => 1 });
}

sub remove {
    my $self = shift;
    my $params = check_params $self, 'login';
    return unless $params;

    execute_query($self, "delete from users where login = ?", $params->{login});
    return $self->render(json => { ok => 1 }); # XXX: user can be looged in
}

sub change {
    my $self = shift;
    my $params = check_params $self, qw( login password role );
    return unless $params;

    execute_query $self, "update users set role = ?, pass = ?, name = ?, lastname = ?, email = ? where login = ?",
        map { $_ // "" } @$params{qw( role password name lastname email login )};

    return $self->render(json => { ok => 1 });
}

sub roles {
    my $self = shift;

    my $r = select_all($self, "select id, name, text from roles order by name");
    return $self->render(json => { ok => 1, roles => $r, count => scalar @$r }) if $r;
    return return_500 $self;
}

sub list {
    my $self = shift;

    my $r = select_all($self, 'select r.name as role, u.pass as password, u.login as login, u.name as name, ' .
        'u.lastname as lastname, u.email as email from users u join roles r on r.id = u.role order by r.id, u.login');
    return return_500 $self unless $r;
    return $self->render(json => { ok => 1, count => scalar @$r, users => $r });
}

1;
