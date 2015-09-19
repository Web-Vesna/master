package Files;
use Mojo::Base 'Mojolicious';

use MainConfig qw( URL_404 COOKIE_SECRET );

# This method will run once at server start
sub startup {
    my $self = shift;

    # Documentation browser under "/perldoc"
    $self->plugin('PODRenderer');
    $self->plugin('RenderFile');
    $self->secrets(COOKIE_SECRET);

    # Router
    my $r = $self->routes;

    # Normal route to controller
    $r->get('files')->to('files#list');
    $r->get('file')->to('files#get');

    $r->any('/*any' => { any => '' } => sub {
        my $self = shift;
       $self->redirect_to(URL_404);
    });
}

1;
