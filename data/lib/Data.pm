package Data;
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
    $r->get('/roles')->to('users#roles');
    $r->get('/users_list')->to('users#list');
    $r->get('/user/register')->to('users#add');
    $r->get('/user/remove')->to('users#remove');
    $r->get('/user/edit')->to('users#change');

    $r->get('/districts')->to('data#districts');
    $r->get('/companies')->to('data#companies');
    $r->get('/company')->to('data#company_info');
    $r->get('/buildings')->to('data#buildings');
    $r->get('/building/edit')->to('data#edit_building');
    $r->get('/objects')->to('data#objects');
    $r->get('/objects/filter')->to('data#filter_objects');
    $r->get('/objects/names')->to('data#objects_names');
    $r->get('/object/name/add')->to('data#objects_names_add');
    $r->get('/object/name/edit')->to('data#objects_names_edit');
    $r->get('/object/name/remove')->to('data#objects_names_remove');
    $r->get('/objects/add-edit')->to('data#objects_add_edit');
    $r->get('/objects/remove')->to('data#remove_object');
    $r->get('/calc_types')->to('data#calc_types');
    $r->get('/conn_types')->to('data#conn_types');

    $r->get('/isolation_types')->to('data#isolation_types');
    $r->get('/laying_methods')->to('data#laying_methods');

    $r->get('/build')->to('results#build');
    $r->get('/rebuild_cache')->to('results#rebuild_cache');
    $r->post('/add_buildings')->to('results#add_buildings');
    $r->post('/add_categories')->to('results#add_categories');
    $r->post('/add_content')->to('results#add_content');
    $r->post('/add_buildings_meta')->to('results#add_buildings_meta');

    $r->get('/geolocation/objects')->to('geolocation#objects');
    $r->get('/geolocation/status')->to('geolocation#status');
    $r->get('/geolocation/start')->to('geolocation#start_geolocation');
    $r->post('/geolocation/save')->to('geolocation#save_changes');
}

1;
