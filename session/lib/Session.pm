package Session;
use Mojo::Base 'Mojolicious';

use MainConfig qw( COOKIE_SECRET );

# This method will run once at server start
sub startup {
    my $self = shift;

    # Documentation browser under "/perldoc"
    $self->plugin('PODRenderer');
    $self->secrets(COOKIE_SECRET);

    # Router
    my $r = $self->routes;

    # Normal route to controller
    $r->get('/session')->to('index#check_session');
    $r->get('/login')->to('index#login');
    $r->get('/logout')->to('index#logout');
    $r->get('/about')->to('index#about');
}

1;
