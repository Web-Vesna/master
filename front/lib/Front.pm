package Front;
use Mojo::Base 'Mojolicious';

use AccessDispatcher qw( send_request role_less_then redirect_to_login _session );
use MainConfig qw( FILES_HOST GENERAL_URL SESSION_PORT COOKIE_SECRET );

my %access_rules = (
    '/'          => 'user',
    '/report_v2' => 'user',
    '/login'     => 'user',
    '/objects'   => 'manager',
    '/users'     => 'admin',
    '/maps'      => 'user',
    '/catalogue' => 'manager',
    '/geolocation'          => 'admin',
    '/404.html'  => 'user',
);

# This method will run once at server start
sub startup {
    my $self = shift;

    # Documentation browser under "/perldoc"
    $self->plugin('PODRenderer');
    $self->secrets(COOKIE_SECRET);

    $self->routes->get('/login')->to(cb => sub {
        my $self = shift;

        $self->stash(return_url => ($self->param('return_url') // GENERAL_URL));
        $self->stash(general_url => GENERAL_URL);

        if (my $sid = $self->signed_cookie('session')) {
            my $res = send_request($self,
                method => 'get',
                url => 'about',
                port => SESSION_PORT,
                args => {
                    user_agent => $self->req->headers->user_agent,
                    session_id => $sid,
                },
            );
            return $self->render(status => 500) && undef unless $res;

            if ($res && !$res->{error}) {
                return $self->redirect_to($self->param('return_url') // GENERAL_URL) && undef;
            }
        }

        _session($self, { expired => 1 });
        $self->render(template => 'base/login');
    });

    my $auth = $self->routes->under('/' => sub {
        my $self = shift;
        my $r = $self->req;

        my $res = send_request($self,
            method => 'get',
            url => 'about',
            port => SESSION_PORT,
            args => {
                user_agent => $self->req->headers->user_agent,
                session_id => $self->signed_cookie('session'),
            },
        );
        return $self->render(status => 500) && undef unless $res;

        my $url = $self->url_for('current');

        if (defined $res->{status}) {
            return $self->render(template => 'base/login') && undef if $res->{status} == 401;
            return $self->render(status => $res->{status}) && undef;
        }

        if ($res->{error}) {
            _session($self, { expired => 1 });
            return redirect_to_login($self) && undef;
        }

        $self->stash(general_url => GENERAL_URL, url => $url);
        $self->stash(files_url => FILES_HOST);
        $self->stash(%$res); # login name lastname role uid email objects_count

        if (!role_less_then $res->{role}, $access_rules{$url} || 'admin') {
            $self->app->log->warn("Access to $url ($access_rules{$url} is needed) denied for $res->{login} ($res->{role})");
            $self->render(template => 'base/not_found');
            return undef;
        }

        return 1;
    });

    $auth->get('/')->to("builder#index");
    $auth->get('/objects')->to("builder#objects");
    $auth->get('/main_content')->to("builder#main_content");
    $auth->get('/report_v2')->to("builder#report_v2");
    $auth->get('/maps')->to("builder#maps");
    $auth->get('/catalogue')->to("builder#catalogue");
    $auth->get('/geolocation')->to("builder#start_geolocation");

    $auth->any('/*any' => { any => '' } => sub {
        my $self = shift;
        if ($self->param('any') ne 'login') {
            $self->render(template => 'base/not_found');
        }
    });
}

1;
