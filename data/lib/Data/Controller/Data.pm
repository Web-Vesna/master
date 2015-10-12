package Data::Controller::Data;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw( encode_json );

use MainConfig qw( :all );
use AccessDispatcher qw( send_request check_access );

use List::Util;

use Data::Dumper;

use DB qw( :all );
use Helpers qw( :all );

sub districts {
    my $self = shift;

    my $args = $self->req->params->to_hash;
    my $q = defined $args && $args->{q} || undef;
    $q = "%$q%" if $q;

    my @args = ($self, "select id, name, region from districts" . (defined $q ? " where name like ? order by name" : ""));
    push @args, $q if defined $q;
    my $r = select_all @args;

    return return_500 $self unless $r;

    return $self->render(json => { ok => 1, count => scalar @$r, districts => $r });
}

sub conn_types {
    my $self = shift;

    my $r = select_all($self, 'select distinct(characteristic) from buildings_meta where characteristic != "" order by characteristic');
    return return_500 $self unless $r;
    return $self->render(json => { ok => 1, count => scalar @$r, conn_types => $r });
}

sub companies {
    my $self = shift;

    my $args = $self->req->params->to_hash;
    my $q = defined $args && $args->{q} || undef;
    my $d = defined $args && $args->{district} || undef;
    my $region = defined $args && $args->{region} || undef;
    my $filter_heads = defined $args && $args->{heads_only} || undef;
    $q = "%$q%" if $q;

    return $self->render(json => { status => 400, error => "invalid district" }) if defined $d && $d !~ /^\d+$/;

    my @args = ($self, qq/select b.company_id as id, c.name as name, d.name as district from buildings b join
        districts d on d.id = b.district_id join companies c on b.company_id = c.id/ .
        ($filter_heads ? " where b.status = 'Голова'" : "") .
        (defined $q ? ($filter_heads ? " and" : " where") . " c.name like ?" : "") .
        (defined $d ? (defined $q || $filter_heads ? " and" : " where") . " b.district_id = ?" : "") .
        (defined $region ? (defined $q || defined $d || $filter_heads ? " and" : " where") . " d.region = ?" : "") .
        " group by b.company_id order by c.name");

    push @args, $q if defined $q;
    push @args, $d if defined $d;
    push @args, $region if defined $region;
    my $r = select_all @args;

    return return_500 $self unless $r;

    return $self->render(json => { ok => 1, count => scalar @$r, companies => $r });
}

sub isolation_types {
    my $self = shift;

    my $r = select_all $self, "select id, name from isolations group by name order by name";
    return return_500 $self unless $r;
    return $self->render(json => { ok => 1, count => scalar @$r, isolations => $r });
}

sub laying_methods {
    my $self = shift;

    my $r = select_all $self, "select id, name from laying_methods group by name order by name";
    return return_500 $self unless $r;
    return $self->render(json => { ok => 1, count => scalar @$r, methods => $r });
}

sub select_building {
    my $self = shift;
    my $args = shift // {};

    my $id_found = defined $args->{company} || defined $args->{district};
    my @args = (sprintf qq/
            select
                b.id as id,
                b.name as name,
                d.name as district,
                c.name as company,
                c.id as company_id,
                b.flags as flags,
                bm.characteristic as characteristic,
                bm.build_date as build_date,
                bm.reconstruction_date as reconstruction_date,
                bm.heat_load as heat_load
            from buildings b
            join companies c on c.id = b.company_id
            join districts d on d.id = b.district_id
            left outer join buildings_meta bm on bm.building_id = b.id
            %s %s %s %s order by b.name
        /,
        (defined $args->{id} ? "where b.id = ?" : ""),
        (defined $args->{company} ? (defined $args->{id} ? "and" : "where") . " c.id = ?" : ""),
        (!defined($args->{company}) && defined $args->{district} ? (defined $args->{id} ? "and" : "where") . " d.id = ?" : ""),
        (defined $args->{q} ? (defined $args->{id} || $id_found ? "and" : "where") . " b.name like ?" : "")
    );

    push @args, $args->{id} if defined $args->{id};
    push @args, $args->{company} || $args->{district} if $id_found;

    my $q = "%$args->{q}%" if $args->{q};
    push @args, $q if defined $q;

    return select_all $self, @args;
}

sub edit_building {
    my $self = shift;
    my $args = $self->req->params->to_hash;

    return $self->render(json => { status => 400, error => "invalid id" }) if !defined $args->{id} || $args->{id} =~ /\D/;

    my @not_found_key = grep { !defined $args->{$_} || $args->{$_} eq "" } qw( conn_type heat_load );
    unless (@not_found_key) {
        @not_found_key = grep { !defined $args->{$_} || $args->{$_} eq "" } qw( repair_date build_date );
        if (scalar(@not_found_key) != 2) {
            $args->{repair_date} ||= undef;
            $args->{build_date} ||= undef;
            @not_found_key = ();
        }
    }
    return $self->render(json => { status => 400, error => join(', ', @not_found_key) . " is not found in request" }) if @not_found_key;

    execute_query $self, qq/
        insert into buildings_meta (building_id, characteristic, build_date, reconstruction_date, heat_load)
        values (?, ?, ?, ?, ?)
        on duplicate key
        update
            characteristic = ?,
            build_date = ?,
            reconstruction_date = ?,
            heat_load = ?
    /, @$args{qw( id conn_type build_date repair_date heat_load conn_type build_date repair_date heat_load )};

    my $r = select_building $self, { id => $args->{id} };
    return return_500 $self unless $r;
    return $self->render(json => { ok => 1, count => scalar @$r, buildings => $r });
}

sub buildings {
    my $self = shift;

    my $args = $self->req->params->to_hash;
    delete $args->{district} if defined $args->{company};

    return $self->render(json => { status => 400, error => "invalid district" }) if defined $args->{district} && $args->{district} !~ /^\d+$/;
    return $self->render(json => { status => 400, error => "invalid company" }) if defined $args->{company} && $args->{company} !~ /^\d+$/;

    my $r = select_building $self, $args;
    return return_500 $self unless $r;

    map { $_->{flags} = { map { $_ => 1 } split ',', $_->{flags} } } @$r;
    return $self->render(json => { ok => 1, count => scalar @$r, buildings => $r });
}

sub objects {
    my $self = shift;

    my $args = $self->req->params->to_hash;

    for (qw( building )) { # TODO: add other cases (district && company)
        return $self->render(json => { status => 400, error => "invalid $_" }) if defined $args->{$_} && $args->{$_} !~ /^\d+$/;
    }

    my @args = (
        sprintf(qq/
            select
                o.id as id,
                o.characteristic as characteristic,
                o.characteristic_value as count,
                o.size as diametr,
                i.name as isolation,
                i.id as isolation_type_id,
                l.name as laying_method,
                l.id as laying_method_id,
                o.install_year as install_year,
                o.reconstruction_year as reconstruction_year,
                o.wear as wear,
                cat.object_name as name,
                new_o.name as new_name,
                new_o.id as new_name_id,
                new_o.group_id as new_group,
                oo.id as parent_id
            from objects o
            left outer join isolations i on i.id = o.isolation
            left outer join laying_methods l on l.id = o.laying_method
            left outer join objects oo on oo.id = o.parent_object
            left outer join objects_names new_o on new_o.id = o.object_name_new
            left outer join categories cat on o.object_name = cat.id %s
            order by cat.object_name/,
        (defined $args->{building} ? "where o.building = ?" : "")),
    );

    push @args, $args->{building} if defined $args->{building};

    my $r = select_all $self, @args;
    return return_500 $self unless $r;

    my $current_group = -1;
    my %tree = map {
        $current_group = $_->{new_group}
            if defined $_->{new_group} && $_->{new_group} > $current_group;
        $_->{id} => $_
    } @$r;

    while ($current_group > 1) {
        for (keys %tree) {
            if (defined($tree{$_}{parent_id}) && $tree{$_}{new_group} == $current_group) {
                push @{$tree{$tree{$_}{parent_id}}{children}}, $tree{$_};
                delete $tree{$_};
            }
        }
        --$current_group;
    }

    my @to_return;
    my $_add = sub {
        my ($_add, $o) = @_;
        my $children = $o->{children} // [];
        delete $o->{children};
        push @to_return, $o;

        $_add->($_add, $_) for sort {
            $a->{new_group} <=> $b->{new_group}
        } @$children;
    };

    my @tail; # objects without group;
    for (keys %tree) {
        if (defined $tree{$_}{children}) {
            $_add->($_add, $tree{$_});
        } else {
            push @tail, $tree{$_};
        }
    }

    return $self->render(json => {
        ok => 1,
        count => scalar @$r,
        objects => [ @to_return, @tail ],
    });
}

sub objects_add_edit {
    my $self = shift;
    my $args = $self->req->params->to_hash;

    return $self->render(json => { status => 400, error => "building id is required" }) unless $args->{building};

    my $req;
    if (defined $args->{id}) {
        $req = qq/
            update objects set
                size = ?,
                isolation = ?,
                laying_method = ?,
                install_year = ?,
                reconstruction_year = ?,
                object_name_new = ?,
                characteristic = ?,
                characteristic_value = ?,
                wear = ?,
                parent_object = ?,
                building = ?
            where id = ?
        /;
    } else {
        $req = qq/
            insert into objects (
                size,
                isolation,
                laying_method,
                install_year,
                reconstruction_year,
                object_name_new,
                characteristic,
                characteristic_value,
                wear,
                parent_object,
                building
            ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        /;
    }

    my $r = execute_query $self, $req, map { $_ || undef } @$args{qw(
        diametr isolation_type laying_method install_year reconstruction_year
        object_name characteristic count wear parent_object building id)};
    return $self->render(json => { status => 400, error => "request failed" }) unless $r;

    return $self->render(json => { status => 200, desription => 'saved', ok => 1});
}

sub remove_object {
    my $self = shift;
    my $args = $self->req->params->to_hash;

    return $self->render(json => { status => 400, error => 'object id is required' }) unless $args->{id};

    my $r = execute_query $self, "delete from objects where id = ?", $args->{id};
    return $self->render(json => { status => 400, error => "request failed" }) unless $r;

    return $self->render(json => { status => 200, description => 'removed', ok => 1 });
}

sub objects_names {
    my $self = shift;

    my $r = select_all $self, "select id, name, group_id from objects_names order by id";

    return return_500 $self unless $r;
    return $self->render(json => { ok => 1, count => scalar @$r, objects => $r });
}

sub filter_objects {
    my $self = shift;

    my $bounds = sub {
        my $a = $self->param('start');
        my $b = $self->param('end');

        die "invalid bounds\n" unless defined($a) && defined($b);

        $a ||= 0;
        $b ||= 0;

        if ($a > $b) {
            ($a, $b) = ($b, $a);
        }

        ($a, $b);
    };

    my $types_param = sub {
        my $arg = $self->param('types');
        die "types are required\n" unless defined $arg;
        split ',', $arg;
    };

    my %cases = (
        company => {
            req => "select id from buildings where company_id = ?",
            args => sub {
                my $arg = $self->param("company");
                die "company id is required\n" unless defined $arg;
                $arg;
            },
        },
        cost => {
            req => q/
                SELECT building_id as id
                FROM buildings_meta
                JOIN buildings b ON building_id = b.id
                WHERE b.company_id IN (
                    SELECT company_id
                    FROM buildings
                    JOIN buildings_meta bm ON bm.building_id = id
                    GROUP BY company_id
                    HAVING SUM(bm.cost) BETWEEN ? AND ?
                )
            /,
            args => $bounds,
        },
        repair => {
            req => q/
                SELECT building_id as id
                FROM buildings_meta bm
                JOIN buildings b ON b.id = building_id
                WHERE b.company_id in (
                    SELECT company_id
                    FROM buildings
                    JOIN buildings_meta bm ON bm.building_id = id
                    WHERE (reconstruction_date IS NOT NULL AND reconstruction_date BETWEEN ? AND ?)
                       OR (reconstruction_date IS NULL AND build_date BETWEEN ? AND ?)
                    GROUP BY company_id
                )
            /,
            args => sub { $bounds->(), $bounds->() },
        },
        type => {
            req => q/
                SELECT building_id as id
                FROM buildings_meta bm
                JOIN buildings b on b.id = building_id
                WHERE b.company_id IN (
                    SELECT company_id
                    FROM buildings
                    JOIN buildings_meta bm ON bm.building_id = id
                    WHERE bm.characteristic IN (%s) GROUP BY company_id
                );
            /,
            post => sub {
                join ',', map { '?' } (1 .. (scalar $types_param->()))
            },
            args => $types_param,
        },
    );

    my ($req, @args);
    eval {
        for my $type (keys %cases) {
            if ($self->param('type') eq $type) {
                $req = sprintf $cases{$type}->{req}, ($cases{$type}->{post} || sub {})->();
                @args = $cases{$type}->{args}->();
            }
        }
    };

    return $self->render(json => { status => 400, error => "$@" }) if $@;

    my $r = select_all($self, $req, @args);
    return $self->render(json => { status => 500, error => "db_error" }) unless defined $r;

    return $self->render(json => { status => 200, count => scalar(@$r), data => $r });
}

sub calc_types {
    my $self = shift;

    my $r = select_all $self, "select id, name from calc_types order by order_index";
    return $self->render(json => { ok => 1, count => scalar @$r, types => $r });
}

sub company_info {
    my $self = shift;

    my $obj_id = $self->param('obj_id');
    return $self->render(json => { status => 400, error => 'obj_id is undefined' }) unless defined $obj_id;

    my $r = select_all $self, "select c.id as company_id, c.name as company_name, b.name as addr " .
        "from buildings b join companies c on c.id = b.company_id where b.id = ?", $obj_id;

    return $self->render(json => { status => 500, error => 'db error' }) unless defined $r;
    return $self->render(json => { status => 200, error => 'object not found' }) unless @$r;

    $r = $r->[0];
    my $c_id = $r->{company_id};
    my %to_return = (
        company => $r->{company_name},
        addr => $r->{addr},
    );

    $r = select_all $self, "select status, name as addr, corpus, id, status = 'Голова' as is_primary, bm.characteristic as type, " .
        "bm.reconstruction_date as reconstruction_date, bm.build_date as build_date, " .
        "cast(bm.cost as signed) as cost, bm.heat_load as heat_load from buildings join buildings_meta bm on bm.building_id = id " .
        "where company_id = ? order by addr", $c_id;
    return $self->render(json => { status => 500, error => 'db_error' }) unless defined $r;

    $to_return{buildings} = $r;
    $to_return{count} = scalar @$r;
    return $self->render(json => \%to_return);
}

1;
