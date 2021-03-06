package Front::Controller::Builder;
use Mojo::Base 'Mojolicious::Controller';

use AccessDispatcher qw( send_request );
use MainConfig qw( DATA_PORT );

sub index {
    my $self = shift;

    my $r = send_request($self,
        url => 'districts',
        port => DATA_PORT,
    );
    return $self->render(template => 'base/internal_err') unless $r;

    my $c = send_request($self,
        url => 'calc_types',
        port => DATA_PORT,
    );
    return $self->render(template => 'base/internal_err') unless $c;

    $self->stash(calc_types => $c);
    $self->stash(districts => $r);
    $self->render(template => 'base/index');
}

sub report_v2 {
    my $self = shift;

    my $r = send_request($self,
        url => 'districts',
        port => DATA_PORT,
    );
    return $self->render(template => 'base/internal_err') unless $r;

    my $c = send_request($self,
        url => 'calc_types',
        port => DATA_PORT,
    );
    return $self->render(template => 'base/internal_err') unless $c;

    $self->stash(calc_types => $c);
    $self->stash(districts => $r);
    $self->render(template => 'base/index_2');
}

sub objects {
    my $self = shift;

    my $r = send_request($self,
        url => 'districts',
        port => DATA_PORT,
    );
    return $self->render(template => 'base/internal_err') unless $r;

    $self->stash(districts => $r);
    $self->render(template => 'base/objects');
}

sub main_content {
    my $self = shift;

    my $r = send_request($self,
        url => 'roles',
        port => DATA_PORT,
    );
    return $self->render(template => 'base/internal_err') unless $r;

    $self->stash(roles => $r->{roles});
    return $self->render(template => 'base/main_content');
}

sub catalogue {
    my $self = shift;

    my $r = send_request($self,
        url => 'districts',
        port => DATA_PORT,
    );
    return $self->render(template => 'base/internal_err') unless $r;

    $self->stash(districts => $r);

    $r = send_request($self,
        url => 'companies',
        port => DATA_PORT,
        args => {
            region => 'Москва',
        }
    );
    return $self->render(template => 'base/internal_err') unless $r && $r->{companies};
    $self->stash(companies => $r->{companies});

    $r = send_request($self,
        url => 'conn_types',
        port => DATA_PORT,
    );
    return $self->render(template => 'base/internal_err') unless $r && $r->{conn_types};
    $self->stash(conn_types => $r->{conn_types});

    $r = send_request($self,
        url => 'objects/names',
        port => DATA_PORT,
    );
    return $self->render(template => 'base/internal_err') unless $r && $r->{objects};
    $self->stash(objects_names => $r->{objects});

    $r = send_request($self,
        url => 'laying_methods',
        port => DATA_PORT,
    );
    return $self->render(template => 'base/internal_err') unless $r && $r->{methods};
    $self->stash(laying_methods => $r->{methods});

    $r = send_request($self,
        url => 'isolation_types',
        port => DATA_PORT,
    );
    return $self->render(template => 'base/internal_err') unless $r && $r->{isolations};
    $self->stash(isolation_types => $r->{isolations});

    return $self->render(template => 'base/catalogue');
}

sub maps {
    my $self = shift;

    my $r = send_request($self,
        url => 'districts',
        port => DATA_PORT,
    );
    return $self->render(template => 'base/internal_err') unless $r;
    $self->stash(districts => $r);

    $r = send_request($self,
        url => 'companies',
        port => DATA_PORT,
        args => {
            region => 'Москва',
            heads_only => 1,
        }
    );
    return $self->render(template => 'base/internal_err') unless $r && $r->{companies};
    $self->stash(companies => $r->{companies});

    $r = send_request($self,
        url => 'geolocation/objects',
        port => DATA_PORT,
    );
    return $self->render(template => 'base/internal_err') unless $r;

    my %characteristics;
    for (@$r) {
        $_->{characteristic} ||= "unknown";
        $characteristics{$_->{characteristic}} = 1;
    }

    my %placemarks_indexes;
    my $i = 0;
    for (sort keys %characteristics) {
        next if $_ eq 'unknown';
        $placemarks_indexes{$_} = $i++;
    }

    $placemarks_indexes{unknown} = $placemarks_indexes{ТВ}; # TODO: remove 'unknown' placemarks

    $self->stash(geoobjects => [ map {
        my $o = $_;
        $o ? {
            (map { $_ => $o->{$_} } qw( name coordinates id company_id district )),
            placemark_id => $placemarks_indexes{$o->{characteristic}},
        } : {}
    } @$r ]);
    $self->stash(objects_types => [ sort keys %characteristics ]);
    $self->stash(placemarks_indexes => [ map {{ i => $placemarks_indexes{$_}, t => $_ }} sort keys %placemarks_indexes ]);

    return $self->render(template => 'base/maps');
}

sub start_geolocation {
    my $self = shift;

    my $r = send_request($self,
        url => 'geolocation/start',
        port => DATA_PORT,
    );

    return $self->render(template => 'base/internal_err') unless $r && ($r->{status} || "") eq '200';

    $self->stash(db_data => $r->{objects});
    $self->stash(req_id => $r->{req_id});
    return $self->render(template => 'base/coordinates');
}

1;
