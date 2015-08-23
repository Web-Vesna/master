package Files;
use Mojo::Base 'Mojolicious';

use MainConfig qw( URL_404 );

# This method will run once at server start
sub startup {
    my $self = shift;

    # Documentation browser under "/perldoc"
    $self->plugin('PODRenderer');
    $self->plugin('RenderFile');
    $self->secrets([qw( 0i+hE8eWI0pG4DOH55Kt2TSV/CJnXD+gF90wy6O0U0k= )]);

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
