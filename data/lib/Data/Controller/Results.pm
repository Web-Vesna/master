package ExcelParser;

use strict;
use warnings;

sub new {
    my $class = shift;
    my $xls = shift;

    my $self = bless { }, $class;

    return $self->set_error('invalid filename') unless $xls;
    return $self->set_error('file not found') unless -f $xls;

    $self->{fname} = $xls unless $self->_init($xls);
    return $self;
}

sub set_error {
    my $self = shift;
    $self->{error} = shift;
    return $self;
}

sub last_error {
    my $self = shift;
    return $self->{error};
}

sub set_worksheet {
    my ($self, $s) = @_;
    $self->{sheet} = $s;
}

sub DESTROY {
    my $self = shift;
    unlink $self->{xls} if defined $self->{xls};
}

1;

package XLSParser;

use strict;
use warnings;

use Spreadsheet::ParseExcel;

use base "ExcelParser";

sub _init {
    my ($self, $fname) = @_;

    $self->{parser} = Spreadsheet::ParseExcel->new();
    return $self->set_error("ParseXLS: can't create parser: $@") unless $self->{parser};

    $self->{workbook} = $self->{parser}->parse($fname);
    return $self->set_error("ParseXLS: invalid file format") unless $self->{workbook};

    return 0;
}

sub worksheets {
    my $self = shift;
    return $self->{workbook}->worksheets;
}

sub row_range {
    my $self = shift;
    return $self->{sheet}->row_range;
}

sub col_range {
    my $self = shift;
    return $self->{sheet}->col_range;
}

sub cell {
    my ($self, $row, $col) = @_;
    return $self->{sheet}->get_cell($row, $col) && $self->{sheet}->get_cell($row, $col)->value;
}

1;

package XLSXParser;

use strict;
use warnings;

use Spreadsheet::XLSX;
use base "ExcelParser";

sub _init {
    my $self = shift;
    my $fname = shift;

    eval {
        $self->{parser} = Spreadsheet::XLSX->new($fname);
    };

    return $self->set_error("ParseXLSX: invalid file format: $@") if $@;
    return 0;
}

sub worksheets {
    my $self = shift;
    return @{ $self->{parser}->{Worksheet} };
}

sub col_range {
    my ($self) = @_;
    my $sheet = $self->{sheet};

    $sheet->{MaxCol} ||= $sheet->{MinCol};
    return ($sheet->{MinCol}, $sheet->{MaxCol});
}

sub row_range {
    my ($self) = @_;
    my $sheet = $self->{sheet};

    $sheet->{MaxRow} ||= $sheet->{MinRow};
    return ($sheet->{MinRow}, $sheet->{MaxRow});
}

sub cell {
    my ($self, $row, $col) = @_;
    return $self->{sheet}->{Cells}->[$row]->[$col]->{Val};
}

1;

package Data::Controller::Results;
use strict;
use warnings;
use utf8;

use Mojo::Base 'Mojolicious::Controller';

use MainConfig qw( :all );
use AccessDispatcher qw( send_request check_access );

use Excel::Writer::XLSX;
use File::Temp;

use Data::Dumper;

use DB qw( :all );
use Helpers qw( :all );

use Translation qw( :all );

sub parser {
    my ($self, $f) = @_;

    my $parser = XLSXParser->new($f);
    return ($parser) unless $parser->last_error;

    $self->app->log->warn($parser->last_error);
    $parser = XLSParser->new($f);
    return ($parser) unless $parser->last_error;

    $self->app->log->warn($parser->last_error);
    return (undef, "Can't create parser: " . $parser->last_error);
}

sub prepare_int {
    my $v = shift;
    $v =~ s/,//g if $v;
    return $v;
}

sub add_buildings {
    my $self = shift;

    $self->app->log->warn("TRYNG TO REQUEST DEPRECATED METHOD");

    my $args = $self->req->params->to_hash;
    return $self->render(json => { status => 400, error => "file not found" }) unless $args->{filename} or not -f $args->{filename};

    my ($parser, $error) = parser $self, $args->{filename};
    return $self->render(json => { status => 400, error => $error }) if $error;

    return $self->render(json => { status => 400, error => "Too many sheets found in document, maximum 1" })
        if scalar $parser->worksheets() > 1;

    my $districts = select_all $self, "select id, name from districts";
    $districts = { map { $_->{name} => { id => $_->{id}, companies => {} } } @$districts };

    my $companies = select_all $self, 'select c.id as id, c.name as name, d.name as district ' .
        'from companies c join districts d on d.id = c.district_id';

    my %buildings = map { $_->{id} => 1 } @{ select_all $self, "select id from buildings" };

    for (@$companies) {
        $districts->{$_->{district}}->{companies}->{$_->{name}} = $_->{id};
    }

    my @errors;
    my $fields_count = 8; # ;(

    my %fields = (
        0 => { sql_name => 'id', callback => sub {
            my ($line_no, $cur_id, @line) = @_;
            my $cell = $line[0];

            if ($buildings{$cell}) {
                push @errors, { line => $line_no, error => "building id $cell is already exists in db" };
                return undef;
            }

            $buildings{$cell} = 1;
            return $cell;
        }},
        1 => { sql_name => 'company_id', callback => sub {
            my ($line_no, $cur_id, @line) = @_;
            my $name = $line[1];
            my $district = $line[7];

            unless ($districts->{$district}) {
                execute_query($self, 'insert into districts(name) values (?)', $district);
                $districts->{$district}->{id} = last_id $self;
                $districts->{$district}->{companies} = {};
            }

            my $cmp = $districts->{$district}->{companies};
            unless ($cmp->{$name}) {
                execute_query($self, 'insert into companies(district_id, name) values (?, ?)', $districts->{$district}->{id}, $name);
                $cmp->{$name} = last_id $self;
            }

            return $cmp->{$name};
        }},
        2 => { sql_name => 'name', default => '', },
        3 => { sql_name => 'status', default => '', },
        4 => { sql_name => 'corpus', default => '' },
    );

    my $sql_fields = join ',', map { $fields{$_}->{sql_name} } sort keys %fields;
    my $sql_placeholders = '(' . join(',', map { '?' } (1 .. scalar keys %fields)) . ')';
    my $lines_per_req = 1;
    my @content;

    my $sql_line = 0;
    my $count = 0;
    my $_exec = sub {
        my $force = shift;
        ++$sql_line unless $force;
        ++$count unless $force;
        if (($force && $sql_line > 1) || $sql_line >= $lines_per_req) {
            execute_query($self, "insert into buildings ($sql_fields) values " .
                join(',', map { $sql_placeholders } (1 .. $sql_line)), @content);
            @content = ();
            $sql_line = 0;
        }
    };

    my $have_data = 0;
    for my $sheet ($parser->worksheets) {
        $have_data = 1;
        $parser->set_worksheet($sheet);
        my ($min_r, $max_r) = $parser->row_range;

        for my $row ($min_r .. $max_r) {
            my ($min_c, $max_c) = $parser->col_range;

            unless (defined $parser->cell($row, $min_c)) {
                next;
            }

            my $id = $parser->cell($row, $min_c);
            if ($id && $id !~ /^\d+$/) {
                utf8::decode $id;
                push @errors, { line => $row, error => "Id field is not numerical: $id" };
                $id = undef;
            }
            next unless $id;

            my @cells = map { $parser->cell($row, $_) } $min_c .. $max_c;
            my @new_content;
            for my $col ($min_c .. $max_c) {
                next unless defined $fields{$col};

                my $ref = $fields{$col};
                my $v = ((defined $ref->{callback} ? $ref->{callback}->($row, $col, @cells) : $cells[$col]) || $ref->{default});

                unless (defined $v) {
                    @new_content = ();
                    last;
                }
                push @new_content, $v;
            }

            next unless @new_content;

            push @content, @new_content;
            $_exec->();
        }
    }

    return $self->render(json => { error => "invalid file format" }) unless $have_data;

    $_exec->(1);

    return $self->render(json => { ok => 1, count => $count, errors => { count => scalar @errors, errors => \@errors } });
}

sub add_categories {
    my $self = shift;

    my $args = $self->req->params->to_hash;
    return $self->render(json => { status => 400, error => "file not found" }) unless $args->{filename} or not -f $args->{filename};

    my ($parser, $error) = parser $self, $args->{filename};
    return $self->render(json => { status => 400, error => $error }) if $error;

    return $self->render(json => { status => 400, error => "Too many sheets found in document, maximum 1" })
        if scalar $parser->worksheets() > 1;

    my %fields = (
        0 => 'object_name',
        1 => 'category_name',
    );

    my @keys = sort keys %fields;
    my %categories = map { my $v = $_->{name}; utf8::decode($v); $v => $_->{id} } @{ select_all $self, 'select name, id from categories_names' };
    my $q = 'insert into categories (' . join(',', @fields{@keys}) . ') values (' . join(',', map { '?' } @keys) . ')';
    my %objects_names = map { my $v = $_->{object_name}; utf8::decode($v); $v => $_->{id} }
        @{ select_all $self, 'select object_name, id from categories' };

    my $rows = 0;
    my @errors;
    for my $sheet ($parser->worksheets) {
        $parser->set_worksheet($sheet);
        my ($min_r, $max_r) = $parser->row_range;

        for my $row ($min_r + 1 .. $max_r) { # Skip first line
            my $e = -1;
            my @data = map { $parser->cell($row, $_) || ($e = $_) } @keys;
            utf8::decode($data[0]);
            if ($e > -1) {
                push @errors, { line => $row, error => "Cell $e is empty" };
            } elsif (defined $objects_names{$data[0]}) {
                push @errors, { line => $row, error => "Category $data[0] already exists" };
            } elsif (defined $categories{$data[1]}) {
                ++$rows;
                execute_query($self, $q, $data[0], $categories{$data[1]});
            } else {
                push @errors, { line => $row, error => "Category $data[1] not found in categories_names" };
            }
        }
    }
    return $self->render(json => { ok => 1, count => $rows, errors => { count => scalar @errors, errors => \@errors, }, });
}

sub add_buildings_meta {
    my $self = shift;

    my $args = $self->req->params->to_hash;

    my ($parser, $error) = parser $self, $args->{filename};
    return $self->render(json => { status => 400, error => $error }) if $error;

    return $self->render(json => { status => 400, error => "Too many sheets found in document, maximum 1" })
        if scalar $parser->worksheets() > 1;

    my %buildings = map { $_->{id} => 1 } @{ select_all $self, "select id from buildings" };
    my %existed = map { $_->{id} => 1 } @{ select_all $self, "select building_id as id from buildings_meta" };

    my @errors;
    my %fields = (
        0 => { sql_name => 'building_id', required => 1, action => sub {
            my ($val, $row) = @_;
            unless ($buildings{$val}) {
                push @errors, { line => $row, error => "Buildings $val not found in database" };
                return undef;
            }
            if (defined $existed{$val}) {
                push @errors, { line => $row, error => "Building $val already found in buildings_meta" };
                return undef;
            }
            return $val;
        }},
        2 => { sql_name => 'characteristic', required => 1, },
        3 => { sql_name => 'build_date', },
        4 => { sql_name => 'reconstruction_date', },
        5 => { sql_name => 'heat_load', },
        6 => { sql_name => 'cost', action => \&prepare_int },
    );

    my ($sheet) = $parser->worksheets;
    $parser->set_worksheet($sheet);

    my @keys = sort keys %fields;
    my $q = "insert into buildings_meta (" . (join ',', map { $fields{$_}->{sql_name} } @keys) .
        ") values (" . (join ',', map { '?' } @keys) . ')';

    my $count = 0;
    my ($min_r, $max_r) = $parser->row_range;
    for my $row ($min_r .. $max_r) {
        my @data;
        my $e = 1;
        for my $k (@keys) {
            my $v = $parser->cell($row, $k);
            if ($fields{$k}->{action}) {
                $v = $fields{$k}->{action}->($v, $row);
                if (not(defined $v) && $fields{$k}->{required}) {
                    $e = undef;
                    last;
                }
            }
            push @data, $v;
        }

        next unless $e;
        execute_query $self, $q, @data;
        ++$count;
    }

    return $self->render(json => { count => $count, ok => 1, errors => { count => scalar @errors, errors => \@errors } });
}

# TODO: remove this method
sub add_content {
    my $self = shift;
    my $args = $self->req->params->to_hash;

    my ($parser, $error) = parser $self, $args->{filename};
    return $self->render(json => { status => 400, error => $error }) if $error;

    return $self->render(json => { status => 400, error => "Too many sheets found in document, maximum 1" })
        if scalar $parser->worksheets() > 1;

    my ($sheet) = $parser->worksheets;
    $parser->set_worksheet($sheet);

    my $have_data = 0;

    my %content = map {
        my $t = $_;
        $t => { map { $_->{name} => $_->{id} } @{ select_all $self, "select name, id from $t" } }
    } qw( laying_methods isolations characteristics objects_subtypes );

    my $add_n_get = sub {
        my ($table_name, $v) = @_;
        return undef unless $v;
        unless (defined $content{$table_name}->{$v}) {
            execute_query $self, "insert into $table_name (name) values (?)", $v;
            $content{$table_name}->{$v} = last_id $self;
        }
        return $content{$table_name}->{$v};
    };

    my @errors;
    my %categories = map { $_->{object_name} => $_->{id} } @{ select_all $self, 'select object_name, id from categories' };
    my %buildings = map { $_->{id} => 1 } @{ select_all $self, "select id from buildings" };
    my %existed_objects = map { $_->{id} => 1 } @{ select_all $self, "select distinct building as id from objects" };

    my $deleted = 0;
    my %actions = (
        1  => { sql_name => 'building', required => 1, callback => sub {
            my $v = shift;
            return undef unless defined $v;
            unless (defined $buildings{$v}) {
                push @errors, { line => shift, error => "Building id '$v' is unknown" };
                return undef;
            }
            if ($existed_objects{$v}) {
                my $r = execute_query $self, "delete from objects where building = ?", $v;
                push @errors, { line => shift, error => "Objects for building $v was replaced" };
                $deleted += $r || 1;
                delete $existed_objects{$v};
            }
            return $v;
        }},
        5  => { sql_name => 'object_name', required => 1, callback => sub {
            my $v = shift;
            utf8::decode($v);
            if ($v) {
                $v =~ s/^\s+//;
                $v =~ s/\s+$//;
            }
            return $categories{$v} if defined $categories{$v};
            push @errors, { line => shift, error => "Category '$v' not found in database" };
            return undef;
        }},
        6  => { sql_name => 'characteristic', callback => sub { $add_n_get->('characteristics', shift); }},
        7  => { sql_name => 'characteristic_value', callback => \&prepare_int, },
        8  => { sql_name => 'size', callback => \&prepare_int },
        9  => { sql_name => 'isolation', callback => sub { $add_n_get->('isolations', shift); }},
        10 => { sql_name => 'laying_method', callback => sub { $add_n_get->('laying_methods', shift); }},
        11 => { sql_name => 'install_year', callback => \&prepare_int, },
        12 => { sql_name => 'reconstruction_year', callback => \&prepare_int, },
        14 => { sql_name => 'wear', callback => sub {
            my $v = shift;
            return 0 unless $v;
            $v =~ /([\d.]+)(%)?/;
            $v = $1 || 0;
            $v *= 100 unless $2;
            return $v;
        }},
        37 => { sql_name => 'cost', callback => \&prepare_int },
        39 => { sql_name => 'last_usage_limit', callback => \&prepare_int },
        41 => { sql_name => 'objects_subtype', callback => sub { $add_n_get->('objects_subtypes', shift); }},
    );

    my @fields_order = sort keys %actions;
    my $fields_names = join ',', map { $actions{$_}->{sql_name} || () } @fields_order;
    my $qqq = join ',', map { '?' } 1 .. scalar @fields_order;

    my $rows = 0;
    my ($min_r, $max_r) = $parser->row_range;

    for my $row ($min_r .. $max_r) {                    # skip first row
        next if $parser->cell($row, 0);

        my @query;
        my $e = 1;
        for my $col (@fields_order) {
            my $r = $parser->cell($row, $col);
            my $ref = $actions{$col};
            if (defined $ref->{callback}) {
                $r = $ref->{callback}->($r, $row);

                if (not(defined $r) && $ref->{required}) {
                    $e = 0;
                    last;
                }
            }
            push @query, $r;
        }
        next unless $e;

        execute_query $self, "insert into objects($fields_names) values ($qqq)", @query;
        ++$rows;
    }

    return $self->render(json => { ok => 1, count => $rows, deleted => $deleted, errors => { count => scalar @errors, errors => \@errors } });
}

sub rebuild_cache {
    my $self = shift;

    my @to_build = qw(
        build_amortization
        build_diagnostic
        build_expluatation
    );

    for my $f_name (@to_build) {
        execute_query $self, "call $f_name()";
    }

    return $self->render(json => { ok => 1 });
}

sub render_xlsx {
    my ($self, $content, $workbook, $calc_type, $title) = @_;

    my $header_bg_color = 'white';#$workbook->set_custom_color(9, 116, 141, 67);
    my $splitter_bg_color = $workbook->set_custom_color(10, 116, 141, 67);
    my $marked_bg_color = $workbook->set_custom_color(11, 215, 227, 189);

    # look at http://search.cpan.org/~jmcnamara/Excel-Writer-XLSX-0.15/lib/Excel/Writer/XLSX.pm to edit styles below
    my %general_style = (
        border => 1,
        border_color => 'black',
    );
    my %styles = (
        header => {
            text_wrap => 1,
            bold => 1,
            align => 'center',
            valign => 'vcenter',
            color => 'black',
            bg_color => $header_bg_color,
        },
        text => {
            text_wrap => 1,
            valign => 'vcenter',
        },
        integer => {
            shrink => 1,
            align => 'right',
            valign => 'vcenter',
            num_format => '# ### ##0',
        },
        float => {
            align => 'right',
            valign => 'vcenter',
            num_format => '#\ ###\ ##0.00',
        },
        year => {
            align => 'center',
            valign => 'vcenter',
            num_format => '0',
        },
        money => {
            align => 'right',
            valign => 'vcenter',
            num_format => '# ##0.00',
        },
        percent => {
            align => 'right',
            valign => 'vcenter',
            num_format => '#"%"',
        },
        building_splitter => {
            bold => 1,
            bg_color => $splitter_bg_color,
        },
        marked_building => {
            bold => 1,
            bg_color => $marked_bg_color,
        },
    );

    my %styles_cache = map { $_ => $workbook->add_format(%general_style, %{$styles{$_}}) } keys %styles;
    my %splitter_styles_cache = map { $_ => $workbook->add_format(%general_style, %{$styles{$_}}, %{$styles{building_splitter}}) } keys %styles;
    my %marked_styles_cache = map { $_ => $workbook->add_format(%general_style, %{$styles{$_}}, %{$styles{marked_building}}) } keys %styles;
    my $general_style = $workbook->add_format(%general_style);
    my $numbers_style = $workbook->add_format(%general_style, valign => 'center', align => 'center', bold => 1);
    my $title_style = $workbook->add_format(bold => 1, valign => 'center', align => 'center');

    my @fields = (
        {
            mysql_name => 'object_name',
            header_text => object_name,
            style => 'text',
            col_width => 50,
        }, {
            mysql_name => 'category_name',
            header_text => category,
            style => 'text',
            col_width => 30,
        }, {
            mysql_name => 'characteristic',
            header_text => characteristic,
            style => 'text',
            col_width => 30,
        }, {
            mysql_name => 'count',
            header_text => count,
            style => 'float',
            col_width => 10,
        }, {
            mysql_name => 'company_name',
            style => 'text',
            col_width => 50,
            print_in_header => 1,
            only_in_header => 1,
            merge_with => 'object_name',
        }, {
            mysql_name => 'address',
            style => 'text',
            col_width => 40,
            print_in_header => 1,
            only_in_header => 1,
            merge_with => 'characteristic',
        }, {
            mysql_name => 'district',
            style => 'text',
            col_width => 10,
            print_in_header => 1,
            only_in_header => 1,
            merge_with => 'count',
        }, {
            mysql_name => 'size',
            header_text => size,
            style => 'integer',
            col_width => 10,
        }, {
            mysql_name => 'isolation_type',
            header_text => isolation_type,
            style => 'text',
            col_width => 20,
        }, {
            mysql_name => 'laying_method',
            header_text => laying_method,
            style => 'text',
            col_width => 30,
        }, {
            mysql_name => 'install_year',
            header_text => install_year,
            style => 'year',
            col_width => 10,
        }, {
            mysql_name => 'buiding_build_date',
            style => 'year',
            print_in_header => 1,
            only_in_header => 1,
            merge_with => 'install_year',
        }, {
            mysql_name => 'reconstruction_year',
            header_text => reconstruction_year,
            style => 'year',
            col_width => 10,
        }, {
            mysql_name => 'bm_reconstruction_date',
            style => 'year',
            col_width => 10,
            only_in_header => 1,
            print_in_header => 1,
            merge_with => 'reconstruction_year',
        }, {
            mysql_name => 'wear',
            header_text => wear,
            style => 'percent',
            col_width => 10,
        }, {
            mysql_name => 'cost',
            header_text => cost,
            style => 'integer',
            col_width => 40,
        }, {
            mysql_name => 'building_cost',
            style => 'integer',
            print_in_header => 1,
            only_in_header => 1,
            merge_with => 'cost',
        }, {
            mysql_name => 'usage_limit',
            header_text => usage_limit,
            style => 'integer',
            col_width => 50,
        }, {
            mysql_name => 'am_rate_of_depreciation',
            header_text => amortization_rate_of_depriciation,
            style => 'percent',
            col_width => 50,
        }, {
            mysql_name => 'am_depreciation',
            header_text => amortization_depriciation,
            style => 'money',
            col_width => 50,
        }, {
            mysql_name => 'am_total_depreciation',
            style => 'money',
            col_width => 50,
            only_in_header => 1,
            print_in_header => 1,
            merge_with => 'am_depreciation',

        }, {
            header_text => diagnostic_diametr,
            mysql_name => 'dia_diametr',
            style => 'integer',
            col_width => 30,
            calc_type => 'diagnostic',
        }, {
            header_text => diagnostic_ztr,
            mysql_name => 'dia_ztr',
            style => 'float',
            col_width => 10,
            calc_type => 'diagnostic',
        }, {
            header_text => diagnostic_compensation,
            mysql_name => 'dia_compensation',
            style => 'float',
            col_width => 30,
            calc_type => 'diagnostic',
        }, {
            header_text => diagnostic_expluatation,
            mysql_name => 'dia_expluatation',
            style => 'float',
            col_width => 10,
            calc_type => 'diagnostic',
        }, {
            header_text => diagnostic_materials,
            mysql_name => 'dia_materials',
            style => 'float',
            col_width => 10,
            calc_type => 'diagnostic',
        }, {
            header_text => diagnostic_overhead_cost,
            mysql_name => 'dia_overhead_cost',
            style => 'float',
            col_width => 10,
            calc_type => 'diagnostic',
        }, {
            header_text => diagnostic_profit,
            mysql_name => 'dia_profit',
            style => 'float',
            col_width => 10,
            calc_type => 'diagnostic',
        }, {
            header_text => diagnostic_total,
            mysql_name => 'dia_total',
            style => 'money',
            col_width => 10,
            calc_type => 'diagnostic',
        }, {
            header_text => diagnostic_nds,
            mysql_name => 'dia_nds',
            style => 'money',
            col_width => 10,
            calc_type => 'diagnostic',
        }, {
            header_text => bux_econ_life,
            mysql_name => 'bux_life_limit',
            style => 'integer',
            col_width => 10,
            calc_type => 'bux_report',
        }, {
            header_text => bux_econ_life_limit,
            mysql_name => 'bux_usage_limit',
            style => 'integer',
            col_width => 10,
            calc_type => 'bux_report',
        }, {
            header_text => bux_expluatation_life,
            mysql_name => 'bux_econ_limit',
            style => 'integer',
            col_width => 10,
            calc_type => 'bux_report',
        }, {
            header_text => bux_expluatation_life_limit,
            mysql_name => 'bux_expl_limit',
            style => 'integer',
            col_width => 10,
            calc_type => 'bux_report',
        }, {
            header_text => diagnostic_tatal_nds,
            mysql_name => 'dia_total_nds',
            style => 'money',
            col_width => 10,
            calc_type => 'diagnostic',
        }, {
            header_text => expluatation_heat_load,
            mysql_name => 'exp_heat_load',
            style => 'float',
            col_width => 10,
            print_in_header => 1,
            only_in_header => 1,
            calc_type => 'expluatation',
        }, {
            header_text => diagnostic_ztr,
            mysql_name => 'exp_ztr',
            style => 'float',
            col_width => 10,
            print_in_header => 1,
            only_in_header => 1,
            calc_type => 'expluatation',
        }, {
            header_text => diagnostic_compensation,
            mysql_name => 'exp_compensation',
            style => 'float',
            col_width => 30,
            print_in_header => 1,
            only_in_header => 1,
            calc_type => 'expluatation',
        }, {
            header_text => diagnostic_materials,
            mysql_name => 'exp_materials',
            style => 'float',
            col_width => 10,
            print_in_header => 1,
            only_in_header => 1,
            calc_type => 'expluatation',
        }, {
            header_text => diagnostic_overhead_cost,
            mysql_name => 'exp_overhead_cost',
            style => 'float',
            col_width => 10,
            print_in_header => 1,
            only_in_header => 1,
            calc_type => 'expluatation',
        }, {
            header_text => diagnostic_profit,
            mysql_name => 'exp_profit',
            style => 'float',
            col_width => 10,
            print_in_header => 1,
            only_in_header => 1,
            calc_type => 'expluatation',
        }, {
            header_text => diagnostic_total,
            mysql_name => 'exp_total',
            style => 'money',
            col_width => 10,
            print_in_header => 1,
            only_in_header => 1,
            calc_type => 'expluatation',
        }, {
            header_text => diagnostic_nds,
            mysql_name => 'exp_nds',
            style => 'money',
            col_width => 10,
            print_in_header => 1,
            only_in_header => 1,
            calc_type => 'expluatation',
        }, {
            header_text => diagnostic_tatal_nds,
            mysql_name => 'exp_total_nds',
            style => 'money',
            col_width => 10,
            print_in_header => 1,
            only_in_header => 1,
            calc_type => 'expluatation',
        }
    );

    $calc_type = "" unless defined $calc_type;
    @fields = grep { !$_->{calc_type} || $_->{calc_type} eq $calc_type } @fields;

    my %merges = map { my $v = $_->{merge_with}; $v => (grep { $_->{mysql_name} eq $v } @fields) } grep { $_->{merge_with} } @fields;
    my $i = 0;

    if ($calc_type eq 'bux_report') {
        @fields = grep { $_->{mysql_name} !~ /^(?:install_year|reconstruction_year|wear|usage_limit)$/ } @fields;
    }

    if ($calc_type eq 'amortization') {
        @fields = grep { $_->{mysql_name} !~ /^(?:category_name|wear|install_year|reconstruction_year)$/ } @fields;
    }

    for (@fields) {
        $_->{index} = $_->{merge_with} ? $merges{$_->{merge_with}}->{index} : $i++;
    }

    if ($calc_type eq 'expluatation') {
        map { $_->{only_in_header} = 1 } @fields;
    }

    my $worksheet = $workbook->add_worksheet();
    $worksheet->freeze_panes(3, 1);
    $worksheet->merge_range(0, 0, 0, $i - 1, $title, $title_style);

    my $last_building_id = -100500;
    my $xls_row = 1;

    for (my $i = -2; $i < @$content;) {
        my $row = $content->[$i] if $i >= 0;

        if ($row && $row->{object_name_new}) {
            $row->{object_name} = $row->{object_name_new};
            $row->{need_mark} = $row->{need_mark_new};
        }

        my $building_changed = 0;
        if ($row && $last_building_id != $row->{contract_id}) {
            $building_changed = 1;
            $last_building_id = $row->{contract_id};
        }

        my $row_printed = 0;
        for my $col (0 .. @fields - 1) {
            my $rule = $fields[$col];
            if ($i == -2) {
                unless ($rule->{merge_with}) {
                    $worksheet->set_column($col, $col, $rule->{col_width});
                    $worksheet->write($xls_row, $rule->{index}, $rule->{header_text}, $styles_cache{header});
                    $row_printed = 1;
                }
            } elsif ($i == -1) {
                unless ($rule->{merge_with}) {
                    $worksheet->write($xls_row, $rule->{index}, $rule->{index} + 1, $numbers_style);
                    $row_printed = 1;
                }
            } elsif ($building_changed) {
                my $val = $row->{$rule->{mysql_name}} if $rule->{print_in_header};
                $worksheet->write($xls_row, $rule->{index}, $val, $splitter_styles_cache{$rule->{style}});
                $row_printed = 1;
            } elsif ($row->{need_mark}) {
                unless ($rule->{only_in_header}) {
                    my $val = $rule->{only_in_header} ? undef : $row->{$rule->{mysql_name}};
                    $worksheet->write($xls_row, $rule->{index}, $val, $marked_styles_cache{$rule->{style}});
                    $row_printed = 1;
                }
            } elsif ((not $rule->{only_in_header}) && not $rule->{dont_print_in_common}) {
                $worksheet->write($xls_row, $rule->{index}, $row->{$rule->{mysql_name}}, $styles_cache{$rule->{style}});
                $row_printed = 1;
            } elsif (not $rule->{only_in_header}) {
                $worksheet->write($xls_row, $rule->{index}, undef, $general_style);
            }
        }

        ++$xls_row if $row_printed;
        ++$i unless $building_changed;
    }
}

sub build {
    my $self = shift;

    my $f = File::Temp->new(UNLINK => 1);

    my $workbook = Excel::Writer::XLSX->new($f->filename);

    my %sql_statements = (
        district => 'where d.id = ?',
        company => 'where c.id = ?',
        company_multy => 'where c.id in ',
        building => 'where b.id = ?',
        object => 'where o.id = ?',
        region => 'where d.region = ?',
    );

    my @order = qw( object building company district region );
    my $args = $self->req->params->to_hash;

    my $sql_part;
    my @sql_arg;

    for (@order) {
        if (defined $args->{$_}) {
            my $v = $args->{$_};
            if ($v =~ /,/ && $sql_statements{$_ . "_multy"}) {
                @sql_arg = split ',', $v;
                $sql_part = $sql_statements{$_ . "_multy"};
                $sql_part .= "(" . join(',', ('?') x (scalar @sql_arg)) . ")";
                last;
            }
            $sql_part = $sql_statements{$_};
            @sql_arg = ($v);
            last;
        }
    }

    unless (@sql_arg) {
        return $self->render(json => { status => 400, error => join(' or ', keys %sql_statements) . " not empty argument is required" });
    }

    my $calc_type = $args->{calc_type};
    $calc_type = undef if $calc_type && $calc_type eq "undef";

    my %calc_types = (
        # XXX: Hardcoded with calc_types table!!!
        amortization => {
            select => 'am_costs.rate_of_depreciation as am_rate_of_depreciation, ' .
                      'am_costs.depreciation as am_depreciation, ' .
                      'am_total_costs.cost as am_total_depreciation',
            join   => 'left outer join amortization_costs am_costs on am_costs.global_id = o.global_id ' .
                      'left outer join (' .
                      '  select js_objs.building as building, sum(js_costs.depreciation) as cost ' .
                      '  from objects js_objs ' .
                      '  join amortization_costs js_costs on js_costs.global_id = js_objs.global_id ' .
                      '  group by js_objs.building' .
                      ') am_total_costs on am_total_costs.building = o.building',
            title  => amortization_title,
        },
        diagnostic => {
            select => 'calcs.ztr * o.characteristic_value as dia_ztr, ' .
                      'calcs_r.diametr as dia_diametr, ' .
                      'calcs.compensation * o.characteristic_value as dia_compensation, ' .
                      'calcs.expluatation * o.characteristic_value as dia_expluatation, ' .
                      'calcs.materials * o.characteristic_value as dia_materials, ' .
                      'calcs.overhead_cost * o.characteristic_value as dia_overhead_cost, ' .
                      'calcs.profit * o.characteristic_value as dia_profit, ' .
                      'calcs.total * o.characteristic_value as dia_total, ' .
                      'calcs.nds * o.characteristic_value as dia_nds,' .
                      '(calcs.nds + calcs.total) * o.characteristic_value as dia_total_nds',
            join   => 'left outer join diagnostic_calculations as calcs_r on calcs_r.object_id = o.id ' .
                      'left outer join diagnostic_indexes as calcs on calcs.id = calcs_r.index_id',
            title  => diagnostic_title,
        },
        expluatation => {
            select => 'calcs.ztr as exp_ztr, ' .
                      'calcs.heat_load as exp_heat_load, ' .
                      'calcs.compensation as exp_compensation, ' .
                      'calcs.materials as exp_materials, ' .
                      'calcs.overhead_cost as exp_overhead_cost, ' .
                      'calcs.profit as exp_profit, ' .
                      'calcs.total as exp_total, ' .
                      'calcs.nds as exp_nds,' .
                      '(calcs.nds + calcs.total) as exp_total_nds',
            join   => 'join expluatation_calculations calcs_r on calcs_r.building_id = b.id ' .
                      'left outer join expluatation_indexes as calcs on calcs.id = calcs_r.index_id',
            title  => expluatation_title,
        },
        service => {
            title  => service_title,
        },
        cur_repair => {
            title  => cur_repair_title,
        },
        glob_repair => {
            title  => glob_repair_title,
        },
        investment => {
            title  => investment_title,
        },
        bux_report => {
            select => 'calcs.value as bux_econ_limit, ' .
                      'o.last_usage_limit as bux_usage_limit, ' .
                      'calcs.bux_value as bux_life_limit, '.
                      'ROUND((o.last_usage_limit / calcs.bux_value) * calcs.value) as bux_expl_limit',
            join   => 'left outer join amortization_indexes calcs on calcs.category_id = cat_n.id',
            title  => bux_report_title,
        },
    );

    if ($calc_type && !$calc_types{$calc_type}) {
        return $self->render(json => { status => 400, error => "calc_type is unknown" });
    }

    my $sql_stat = <<SQL;
        select
            b.id as contract_id,
            bm.cost as building_cost,
            d.name as district,
            c.name as company_name,
            b.name as address,
            cat.object_name as object_name,
            o_names.name as object_name_new,
            cat_n.category_type = 'marked' as need_mark,
            o_names.group_id != 4 as need_mark_new,
            cat_n.name as category_name,
            o.characteristic as characteristic,
            o.size as size,
            o.characteristic_value as count,
            i.name as isolation_type,
            l.name as laying_method,
            o.install_year as install_year,
            o.reconstruction_year as reconstruction_year,
            o.wear as wear,
            o.cost as cost,
            bm.build_date as buiding_build_date,
            bm.reconstruction_date as bm_reconstruction_date,
            o.last_usage_limit as usage_limit
            %s
        from objects o
        join buildings b on b.id = o.building
        join companies c on c.id = b.company_id
        join districts d on d.id = b.district_id
        left outer join objects_names o_names on o_names.id = o.object_name_new
        left outer join categories cat on cat.id = o.object_name
        left outer join categories_names cat_n on cat.category_name = cat_n.id
        left outer join isolations i on i.id = o.isolation
        left outer join laying_methods l on l.id = o.laying_method
        left outer join buildings_meta bm on bm.building_id = b.id
        %s %s
        order by b.id, o.id
SQL
    my ($calc_stat, $calc_join, $title) = ('', '', general_title);
    if ($calc_type) {
        my $t = $calc_types{$calc_type};
        if ($t && $t->{select} && $t->{join}) {
            $calc_stat = ',' . $t->{select};
            $calc_join = $t->{join};
            $title = $t->{title};
        }
    }

    my $r = select_all($self, sprintf($sql_stat, $calc_stat, $calc_join, $sql_part), @sql_arg);

    $workbook->set_properties(
        title => xlsx_default_title,
        author => ($args->{name} || "") . " " . ($args->{lastname} || ""),
        # TODO: add other properties
        # http://search.cpan.org/~jmcnamara/Excel-Writer-XLSX-0.15/lib/Excel/Writer/XLSX.pm#add_format(_%properties_)
    );

    $self->render_xlsx($r, $workbook, $calc_type, $title);
    $workbook->close;

    $f->unlink_on_destroy(0);
    return $self->render(json => { filename => $f->filename });
}

1;
