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
        color => 'white',
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
        color => 'white',
    },
    marked_building => {
        bold => 1,
    },
);

my @global_fields = (
    {
        mysql_name => 'contract_id',
        header_text => contract_id,
        style => 'integer',
        col_width => 10,
        only_in_header => 1,
        print_in_header => 1,
    }, {
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
        calc_type => 'amortization',
    }, {
        mysql_name => 'am_depreciation',
        header_text => amortization_depriciation,
        style => 'money',
        col_width => 50,
        calc_type => 'amortization',
    }, {
        mysql_name => 'am_total_depreciation',
        style => 'money',
        col_width => 50,
        only_in_header => 1,
        print_in_header => 1,
        merge_with => 'am_depreciation',
        calc_type => 'amortization',
    }, {
        header_text => maintenance_costs_of_labor,
        mysql_name => 'maintenance_costs_of_labor',
        style => 'money',
        col_width => 20,
        calc_type => 'maintenance',
    }, {
        header_text => maintenance_salary,
        mysql_name => 'maintenance_salary',
        style => 'money',
        col_width => 20,
        calc_type => 'maintenance',
    }, {
        header_text => maintenance_operating_machinery,
        mysql_name => 'maintenance_operating_machinery',
        style => 'money',
        col_width => 20,
        calc_type => 'maintenance',
    }, {
        header_text => maintenance_material_costs,
        mysql_name => 'maintenance_material_costs',
        style => 'money',
        col_width => 20,
        calc_type => 'maintenance',
    }, {
        header_text => maintenance_overhead_costs,
        mysql_name => 'maintenance_overhead_costs',
        style => 'money',
        col_width => 20,
        calc_type => 'maintenance',
    }, {
        header_text => maintenance_profit,
        mysql_name => 'maintenance_profit',
        style => 'money',
        col_width => 20,
        calc_type => 'maintenance',
    }, {
        header_text => maintenance_total_wo_VAT,
        mysql_name => 'maintenance_total_wo_VAT',
        style => 'money',
        col_width => 20,
        calc_type => 'maintenance',
    }, {
        header_text => maintenance_VAT,
        mysql_name => 'maintenance_VAT',
        style => 'money',
        col_width => 20,
        calc_type => 'maintenance',
    }, {
        header_text => maintenance_total,
        mysql_name => 'maintenance_total',
        style => 'money',
        col_width => 20,
        calc_type => 'maintenance',
    }, {
        merge_with => 'maintenance_costs_of_labor',
        mysql_name => 'maintenance_costs_of_labor_total',
        style => 'money',
        col_width => 20,
        calc_type => 'maintenance',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'maintenance_salary',
        mysql_name => 'maintenance_salary_total',
        style => 'money',
        col_width => 20,
        calc_type => 'maintenance',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'maintenance_operating_machinery',
        mysql_name => 'maintenance_operating_machinery_total',
        style => 'money',
        col_width => 20,
        calc_type => 'maintenance',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'maintenance_material_costs',
        mysql_name => 'maintenance_material_costs_total',
        style => 'money',
        col_width => 20,
        calc_type => 'maintenance',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'maintenance_overhead_costs',
        mysql_name => 'maintenance_overhead_costs_total',
        style => 'money',
        col_width => 20,
        calc_type => 'maintenance',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'maintenance_profit',
        mysql_name => 'maintenance_profit_total',
        style => 'money',
        col_width => 20,
        calc_type => 'maintenance',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'maintenance_total_wo_VAT',
        mysql_name => 'maintenance_total_wo_VAT_total',
        style => 'money',
        col_width => 20,
        calc_type => 'maintenance',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'maintenance_VAT',
        mysql_name => 'maintenance_VAT_total',
        style => 'money',
        col_width => 20,
        calc_type => 'maintenance',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'maintenance_total',
        mysql_name => 'maintenance_total_total',
        style => 'money',
        col_width => 20,
        calc_type => 'maintenance',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        header_text => diagnostic_costs_of_labor,
        mysql_name => 'diagnostic_costs_of_labor',
        style => 'money',
        col_width => 20,
        calc_type => 'diagnostic',
    }, {
        header_text => diagnostic_salary,
        mysql_name => 'diagnostic_salary',
        style => 'money',
        col_width => 20,
        calc_type => 'diagnostic',
    }, {
        header_text => diagnostic_operating_machinery,
        mysql_name => 'diagnostic_operating_machinery',
        style => 'money',
        col_width => 20,
        calc_type => 'diagnostic',
    }, {
        header_text => diagnostic_material_costs,
        mysql_name => 'diagnostic_material_costs',
        style => 'money',
        col_width => 20,
        calc_type => 'diagnostic',
    }, {
        header_text => diagnostic_overhead_costs,
        mysql_name => 'diagnostic_overhead_costs',
        style => 'money',
        col_width => 20,
        calc_type => 'diagnostic',
    }, {
        header_text => diagnostic_profit,
        mysql_name => 'diagnostic_profit',
        style => 'money',
        col_width => 20,
        calc_type => 'diagnostic',
    }, {
        header_text => diagnostic_total_wo_VAT,
        mysql_name => 'diagnostic_total_wo_VAT',
        style => 'money',
        col_width => 20,
        calc_type => 'diagnostic',
    }, {
        header_text => diagnostic_VAT,
        mysql_name => 'diagnostic_VAT',
        style => 'money',
        col_width => 20,
        calc_type => 'diagnostic',
    }, {
        header_text => diagnostic_total,
        mysql_name => 'diagnostic_total',
        style => 'money',
        col_width => 20,
        calc_type => 'diagnostic',
    }, {
        merge_with => 'diagnostic_costs_of_labor',
        mysql_name => 'diagnostic_costs_of_labor_total',
        style => 'money',
        col_width => 20,
        calc_type => 'diagnostic',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'diagnostic_salary',
        mysql_name => 'diagnostic_salary_total',
        style => 'money',
        col_width => 20,
        calc_type => 'diagnostic',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'diagnostic_operating_machinery',
        mysql_name => 'diagnostic_operating_machinery_total',
        style => 'money',
        col_width => 20,
        calc_type => 'diagnostic',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'diagnostic_material_costs',
        mysql_name => 'diagnostic_material_costs_total',
        style => 'money',
        col_width => 20,
        calc_type => 'diagnostic',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'diagnostic_overhead_costs',
        mysql_name => 'diagnostic_overhead_costs_total',
        style => 'money',
        col_width => 20,
        calc_type => 'diagnostic',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'diagnostic_profit',
        mysql_name => 'diagnostic_profit_total',
        style => 'money',
        col_width => 20,
        calc_type => 'diagnostic',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'diagnostic_total_wo_VAT',
        mysql_name => 'diagnostic_total_wo_VAT_total',
        style => 'money',
        col_width => 20,
        calc_type => 'diagnostic',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'diagnostic_VAT',
        mysql_name => 'diagnostic_VAT_total',
        style => 'money',
        col_width => 20,
        calc_type => 'diagnostic',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'diagnostic_total',
        mysql_name => 'diagnostic_total_total',
        style => 'money',
        col_width => 20,
        calc_type => 'diagnostic',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        header_text => renovation_costs_of_labor,
        mysql_name => 'renovation_costs_of_labor',
        style => 'money',
        col_width => 20,
        calc_type => 'renovation',
    }, {
        header_text => renovation_salary,
        mysql_name => 'renovation_salary',
        style => 'money',
        col_width => 20,
        calc_type => 'renovation',
    }, {
        header_text => renovation_operating_machinery,
        mysql_name => 'renovation_operating_machinery',
        style => 'money',
        col_width => 20,
        calc_type => 'renovation',
    }, {
        header_text => renovation_material_costs,
        mysql_name => 'renovation_material_costs',
        style => 'money',
        col_width => 20,
        calc_type => 'renovation',
    }, {
        header_text => renovation_overhead_costs,
        mysql_name => 'renovation_overhead_costs',
        style => 'money',
        col_width => 20,
        calc_type => 'renovation',
    }, {
        header_text => renovation_profit,
        mysql_name => 'renovation_profit',
        style => 'money',
        col_width => 20,
        calc_type => 'renovation',
    }, {
        header_text => renovation_total_wo_VAT,
        mysql_name => 'renovation_total_wo_VAT',
        style => 'money',
        col_width => 20,
        calc_type => 'renovation',
    }, {
        header_text => renovation_VAT,
        mysql_name => 'renovation_VAT',
        style => 'money',
        col_width => 20,
        calc_type => 'renovation',
    }, {
        header_text => renovation_total,
        mysql_name => 'renovation_total',
        style => 'money',
        col_width => 20,
        calc_type => 'renovation',
    }, {
        merge_with => 'renovation_costs_of_labor',
        mysql_name => 'renovation_costs_of_labor_total',
        style => 'money',
        col_width => 20,
        calc_type => 'renovation',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'renovation_salary',
        mysql_name => 'renovation_salary_total',
        style => 'money',
        col_width => 20,
        calc_type => 'renovation',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'renovation_operating_machinery',
        mysql_name => 'renovation_operating_machinery_total',
        style => 'money',
        col_width => 20,
        calc_type => 'renovation',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'renovation_material_costs',
        mysql_name => 'renovation_material_costs_total',
        style => 'money',
        col_width => 20,
        calc_type => 'renovation',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'renovation_overhead_costs',
        mysql_name => 'renovation_overhead_costs_total',
        style => 'money',
        col_width => 20,
        calc_type => 'renovation',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'renovation_profit',
        mysql_name => 'renovation_profit_total',
        style => 'money',
        col_width => 20,
        calc_type => 'renovation',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'renovation_total_wo_VAT',
        mysql_name => 'renovation_total_wo_VAT_total',
        style => 'money',
        col_width => 20,
        calc_type => 'renovation',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'renovation_VAT',
        mysql_name => 'renovation_VAT_total',
        style => 'money',
        col_width => 20,
        calc_type => 'renovation',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        merge_with => 'renovation_total',
        mysql_name => 'renovation_total_total',
        style => 'money',
        col_width => 20,
        calc_type => 'renovation',
        print_in_header => 1,
        only_in_header => 1,
    }, {
        mysql_name => 'wo_grouping_contract_id',
        header_text => contract_id,
        style => 'integer',
        col_width => 10,
        wo_grouping => 1,
    }, {
        mysql_name => 'wo_grouping_company_name',
        header_text => company_name,
        style => 'text',
        col_width => 50,
        wo_grouping => 1,
    }, {
        mysql_name => 'wo_grouping_address',
        header_text => address,
        style => 'text',
        col_width => 40,
        wo_grouping => 1,
    }, {
        mysql_name => 'wo_grouping_district',
        header_text => district,
        style => 'text',
        col_width => 10,
        wo_grouping => 1,
    }, {
        header_text => expl_costs_of_labor,
        mysql_name => 'expl_costs_of_labor',
        style => 'money',
        col_width => 20,
        calc_type => 'exploitation',
    }, {
        header_text => expl_costs_salary,
        mysql_name => 'expl_costs_salary',
        style => 'money',
        col_width => 20,
        calc_type => 'exploitation',
    }, {
        header_text => expl_costs_material_costs,
        mysql_name => 'expl_costs_material_costs',
        style => 'money',
        col_width => 20,
        calc_type => 'exploitation',
    }, {
        header_text => expl_costs_overhead_costs,
        mysql_name => 'expl_costs_overhead_costs',
        style => 'money',
        col_width => 20,
        calc_type => 'exploitation',
    }, {
        header_text => expl_costs_profit,
        mysql_name => 'expl_costs_profit',
        style => 'money',
        col_width => 20,
        calc_type => 'exploitation',
    }, {
        header_text => expl_costs_total_wo_VAT,
        mysql_name => 'expl_costs_total_wo_VAT',
        style => 'money',
        col_width => 20,
        calc_type => 'exploitation',
    }, {
        header_text => expl_costs_VAT,
        mysql_name => 'expl_costs_VAT',
        style => 'money',
        col_width => 20,
        calc_type => 'exploitation',
    }, {
        header_text => expl_costs_total,
        mysql_name => 'expl_costs_total',
        style => 'money',
        col_width => 20,
        calc_type => 'exploitation',
    }, {
        header_text => modern_costs_heat_load,
        mysql_name => 'modern_costs_heat_load',
        style => 'float',
        col_width => 20,
        calc_type => 'modernization',
    }, {
        header_text => modern_costs_salary,
        mysql_name => 'modern_costs_salary',
        style => 'money',
        col_width => 20,
        calc_type => 'modernization',
    }, {
        header_text => modern_costs_operating_machinery,
        mysql_name => 'modern_costs_operating_machinery',
        style => 'money',
        col_width => 20,
        calc_type => 'modernization',
    }, {
        header_text => modern_costs_material_costs,
        mysql_name => 'modern_costs_material_costs',
        style => 'money',
        col_width => 20,
        calc_type => 'modernization',
    }, {
        header_text => modern_costs_overhead_costs,
        mysql_name => 'modern_costs_overhead_costs',
        style => 'money',
        col_width => 20,
        calc_type => 'modernization',
    }, {
        header_text => modern_costs_profit,
        mysql_name => 'modern_costs_profit',
        style => 'money',
        col_width => 20,
        calc_type => 'modernization',
    }, {
        header_text => modern_costs_total_wo_VAT,
        mysql_name => 'modern_costs_total_wo_VAT',
        style => 'money',
        col_width => 20,
        calc_type => 'modernization',
    }, {
        header_text => modern_costs_VAT,
        mysql_name => 'modern_costs_VAT',
        style => 'money',
        col_width => 20,
        calc_type => 'modernization',
    }, {
        header_text => modern_costs_total,
        mysql_name => 'modern_costs_total',
        style => 'money',
        col_width => 20,
        calc_type => 'modernization',
    }
);

my $__styles_prepared = 0;
sub prepare_styles {
    my ($self, $workbook) = @_;

    my %colors = (
        building_splitter => $workbook->set_custom_color(10, 116, 141, 67),
        marked_building => $workbook->set_custom_color(11, 215, 227, 189),
    );
    $colors{header} = $colors{building_splitter};

    for (keys %colors) {
        $styles{$_}{bg_color} = $colors{$_};
    }

    unless ($__styles_prepared) {
        $__styles_prepared = 1;

        for (values %styles) {
            $_->{font} = "Myriad Pro";
        }
    }
}

sub render_xlsx {
    my ($self, $content, $workbook, $calc_type, $title, @__opts) = @_;
    my %opts = (
        disable_grouping => 0,
        @__opts,
    );

    $self->prepare_styles($workbook);

    # look at http://search.cpan.org/~jmcnamara/Excel-Writer-XLSX-0.15/lib/Excel/Writer/XLSX.pm to edit styles below
    my %styles_cache = map { $_ => $workbook->add_format(%general_style, %{$styles{$_}}) } keys %styles;
    my %splitter_styles_cache = map { $_ => $workbook->add_format(%general_style, %{$styles{$_}}, %{$styles{building_splitter}}) } keys %styles;
    my %marked_styles_cache = map { $_ => $workbook->add_format(%general_style, %{$styles{$_}}, %{$styles{marked_building}}) } keys %styles;
    my $general_style = $workbook->add_format(%general_style);
    my $numbers_style = $workbook->add_format(%general_style, valign => 'center', align => 'center', bold => 1);
    my $title_style = $workbook->add_format(bold => 1, valign => 'center', align => 'center');

    $calc_type = "" unless defined $calc_type;
    my @fields = grep { !$_->{calc_type} || $_->{calc_type} eq $calc_type } @global_fields;
    my %merges = map { my $v = $_->{merge_with}; $v => (grep { $_->{mysql_name} eq $v } @fields) } grep { $_->{merge_with} } @fields;
    my $i = 0;

    my @wo_grouping = map { $_->{mysql_name} } grep { $_->{wo_grouping} } @fields;
    my %to_remove_re = (
        "" => \@wo_grouping,
        amortization => [qw( category_name wear install_year reconstruction_year ), @wo_grouping ],
        maintenance => [qw( install_year category_name reconstruction_year wear cost building_cost usage_limit ), @wo_grouping ],
        diagnostic => [qw( isolation_type laying_method install_year reconstruction_year wear cost usage_limit category_name ), @wo_grouping ],
        renovation => [qw( category_name install_year reconstruction_year wear cost usage_limit ), @wo_grouping ],
        exploitation => [ map { $_->{mysql_name} } grep { !$_->{wo_grouping} && !$_->{calc_type} } @fields ],
        modernization => [ map { $_->{mysql_name} } grep { !$_->{wo_grouping} && !$_->{calc_type} } @fields ],
    );

    if ($to_remove_re{$calc_type}) {
        my $fields = join '|', @{$to_remove_re{$calc_type}};
        my $re = qr/^(?:$fields)$/;
        @fields = grep { $_->{mysql_name} !~ $re } @fields;
    }

    for (@fields) {
        # XXX: This modification modifies global object. Be careful!
        $_->{index} = $_->{merge_with} ? $merges{$_->{merge_with}}{index} : $i++;

        next unless $_->{merge_with};

        my $x = ($_->{col_width} //= 0);
        my $y = ($merges{$_->{merge_with}}{col_width} //= 0);

        $x = 20 if $x < 20;
        $y = 20 if $y < 20;

        $_->{col_width} = $merges{$_->{merge_with}}{col_width} = ($x, $y)[$x < $y];
    }

    my $worksheet = $workbook->add_worksheet();
    $worksheet->freeze_panes(3, 1);
    $worksheet->merge_range(0, 0, 0, $i - 1, $title, $title_style);
    $worksheet->set_zoom(60);

    my $last_building_id;
    my $xls_row = 1;

    for (my $i = -2; $i < @$content;) {
        my $row = $content->[$i] if $i >= 0;

        if ($row && $row->{object_name_new}) {
            $row->{object_name} = $row->{object_name_new};
            $row->{need_mark} = $row->{need_mark_new};
        }

        my $building_changed = 0;
        if ($row && (!defined($last_building_id) || $last_building_id != $row->{contract_id})) {
            $building_changed = !$opts{disable_grouping};
            $last_building_id = $row->{contract_id};
        }

        if (!$building_changed && $row && $row->{is_virtual}) {
            ++$i;
            next;
        }

        my $row_printed = 0;
        my %marked_cols_printed;
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
            } elsif ($building_changed && !$opts{disable_grouping}) {
                my $val = $row->{$rule->{mysql_name}} if $rule->{print_in_header};
                $worksheet->write($xls_row, $rule->{index}, $val, $splitter_styles_cache{$rule->{style}});
                $row_printed = 1;
            } elsif ($row->{need_mark} && !$opts{disable_grouping}) {
                if ($rule->{only_in_header}) {
                    # just add a style for this cell
                    $worksheet->write($xls_row, $rule->{index}, undef, $marked_styles_cache{$rule->{style}})
                        unless $marked_cols_printed{$rule->{index}};
                } else {
                    my $val = $rule->{only_in_header} ? undef : $row->{$rule->{mysql_name}};
                    $worksheet->write($xls_row, $rule->{index}, $val, $marked_styles_cache{$rule->{style}});
                    $marked_cols_printed{$rule->{index}} = 1;
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

my %calc_types = (
    # XXX: Hardcoded with calc_types table!!!
    amortization => {
        title  => amortization_title,
        select => qq#
            am_costs.rate_of_depreciation as am_rate_of_depreciation,
            am_costs.depreciation as am_depreciation,
            am_total_costs.cost as am_total_depreciation
        #,
        join   => qq#
            left outer join amortization_costs am_costs on am_costs.global_id = o.global_id
            left outer join (
                select js_objs.building as building, sum(js_costs.depreciation) as cost
                from objects js_objs
                join amortization_costs js_costs on js_costs.global_id = js_objs.global_id
                group by js_objs.building
            ) am_total_costs on am_total_costs.building = o.building
        #,
    },
    diagnostic => {
        title => diagnostic_title,
        select => qq#
            dia_costs.costs_of_labor as diagnostic_costs_of_labor,
            dia_costs.salary as diagnostic_salary,
            dia_costs.operating_machinery as diagnostic_operating_machinery,
            dia_costs.material_costs as diagnostic_material_costs,
            dia_costs.overhead_costs as diagnostic_overhead_costs,
            dia_costs.profit as diagnostic_profit,
            dia_costs.total_wo_VAT as diagnostic_total_wo_VAT,
            dia_costs.VAT as diagnostic_VAT,
            dia_costs.total as diagnostic_total,

            dia_total_costs.costs_of_labor as diagnostic_costs_of_labor_total,
            dia_total_costs.salary as diagnostic_salary_total,
            dia_total_costs.operating_machinery as diagnostic_operating_machinery_total,
            dia_total_costs.material_costs as diagnostic_material_costs_total,
            dia_total_costs.overhead_costs as diagnostic_overhead_costs_total,
            dia_total_costs.profit as diagnostic_profit_total,
            dia_total_costs.total_wo_VAT as diagnostic_total_wo_VAT_total,
            dia_total_costs.VAT as diagnostic_VAT_total,
            dia_total_costs.total as diagnostic_total_total
        #,
        join => qq#
            left outer join diagnostics_costs dia_costs on dia_costs.global_id = o.global_id
            left outer join (
                select
                    js_objs.building as building,
                    sum(js_costs.costs_of_labor) as costs_of_labor,
                    sum(js_costs.salary) as salary,
                    sum(js_costs.operating_machinery) as operating_machinery,
                    sum(js_costs.material_costs) as material_costs,
                    sum(js_costs.overhead_costs) as overhead_costs,
                    sum(js_costs.profit) as profit,
                    sum(js_costs.total_wo_VAT) as total_wo_VAT,
                    sum(js_costs.VAT) as VAT,
                    sum(js_costs.total) as total
                from objects js_objs
                join diagnostics_costs js_costs on js_costs.global_id = js_objs.global_id
                group by js_objs.building
            ) dia_total_costs on dia_total_costs.building = o.building
        #,
    },
    maintenance => {
        title  => maintenance_title,
        select => qq#
            ma.costs_of_labor as maintenance_costs_of_labor,
            ma.salary as maintenance_salary,
            ma.operating_machinery as maintenance_operating_machinery,
            ma.material_costs as maintenance_material_costs,
            ma.overhead_costs as maintenance_overhead_costs,
            ma.profit as maintenance_profit,
            ma.total_wo_VAT as maintenance_total_wo_VAT,
            ma.VAT as maintenance_VAT,
            ma.total as maintenance_total,

            ma_total_costs.costs_of_labor as maintenance_costs_of_labor_total,
            ma_total_costs.salary as maintenance_salary_total,
            ma_total_costs.operating_machinery as maintenance_operating_machinery_total,
            ma_total_costs.material_costs as maintenance_material_costs_total,
            ma_total_costs.overhead_costs as maintenance_overhead_costs_total,
            ma_total_costs.profit as maintenance_profit_total,
            ma_total_costs.total_wo_VAT as maintenance_total_wo_VAT_total,
            ma_total_costs.VAT as maintenance_VAT_total,
            ma_total_costs.total as maintenance_total_total
        #,
        join => qq#
            left outer join maintenance_costs as ma on ma.global_id = o.global_id
            left outer join (
                select
                    js_objs.building as building,
                    sum(js_costs.costs_of_labor) as costs_of_labor,
                    sum(js_costs.salary) as salary,
                    sum(js_costs.operating_machinery) as operating_machinery,
                    sum(js_costs.material_costs) as material_costs,
                    sum(js_costs.overhead_costs) as overhead_costs,
                    sum(js_costs.profit) as profit,
                    sum(js_costs.total_wo_VAT) as total_wo_VAT,
                    sum(js_costs.VAT) as VAT,
                    sum(js_costs.total) as total
                from objects js_objs
                join maintenance_costs js_costs on js_costs.global_id = js_objs.global_id
                group by js_objs.building
            ) ma_total_costs on ma_total_costs.building = o.building
        #,
    },
    renovation => {
        title  => renovation_title,
        select => qq#
            renov.costs_of_labor as renovation_costs_of_labor,
            renov.salary as renovation_salary,
            renov.operating_machinery as renovation_operating_machinery,
            renov.material_costs as renovation_material_costs,
            renov.overhead_costs as renovation_overhead_costs,
            renov.profit as renovation_profit,
            renov.total_wo_VAT as renovation_total_wo_VAT,
            renov.VAT as renovation_VAT,
            renov.total as renovation_total,

            renov_total_costs.costs_of_labor as renovation_costs_of_labor_total,
            renov_total_costs.salary as renovation_salary_total,
            renov_total_costs.operating_machinery as renovation_operating_machinery_total,
            renov_total_costs.material_costs as renovation_material_costs_total,
            renov_total_costs.overhead_costs as renovation_overhead_costs_total,
            renov_total_costs.profit as renovation_profit_total,
            renov_total_costs.total_wo_VAT as renovation_total_wo_VAT_total,
            renov_total_costs.VAT as renovation_VAT_total,
            renov_total_costs.total as renovation_total_total
        #,
        join => qq#
            left outer join renovation_costs as renov on renov.global_id = o.global_id
            left outer join (
                select
                    js_objs.building as building,
                    sum(js_costs.costs_of_labor) as costs_of_labor,
                    sum(js_costs.salary) as salary,
                    sum(js_costs.operating_machinery) as operating_machinery,
                    sum(js_costs.material_costs) as material_costs,
                    sum(js_costs.overhead_costs) as overhead_costs,
                    sum(js_costs.profit) as profit,
                    sum(js_costs.total_wo_VAT) as total_wo_VAT,
                    sum(js_costs.VAT) as VAT,
                    sum(js_costs.total) as total
                from objects js_objs
                join renovation_costs js_costs on js_costs.global_id = js_objs.global_id
                group by js_objs.building
            ) renov_total_costs on renov_total_costs.building = o.building
        #,
    },
    exploitation => {
        title => exploitation_title,
        select => qq#
            expl_costs.costs_of_labor as expl_costs_of_labor,
            expl_costs.salary as expl_costs_salary,
            expl_costs.material_costs as expl_costs_material_costs,
            expl_costs.overhead_costs as expl_costs_overhead_costs,
            expl_costs.profit as expl_costs_profit,
            expl_costs.total_wo_VAT as expl_costs_total_wo_VAT,
            expl_costs.VAT as expl_costs_VAT,
            expl_costs.total as expl_costs_total
        #,
        join => qq#
            left outer join exploitation_costs as expl_costs on expl_costs.object_id = b.id
        #,
    },
    modernization => {
        title => modernization_title,
        select => qq#
            modern_costs.salary as modern_costs_salary,
            modern_costs.operating_machinery as modern_costs_operating_machinery,
            modern_costs.material_costs as modern_costs_material_costs,
            modern_costs.overhead_costs as modern_costs_overhead_costs,
            modern_costs.profit as modern_costs_profit,
            modern_costs.total_wo_VAT as modern_costs_total_wo_VAT,
            modern_costs.VAT as modern_costs_VAT,
            modern_costs.total as modern_costs_total,
            bm.heat_load as modern_costs_heat_load
        #,
        join => qq#
            left outer join modernization_costs as modern_costs on modern_costs.object_id = b.id
            left outer join buildings_meta bm on bm.building_id = b.id
        #,
    },
);

my @sql_statements = (
    {
        keys => { map { $_ => 1 } qw( main amortization diagnostic maintenance renovation ) },
        main => qq#
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
                o.is_virtual as is_virtual,
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
        #,
        where => {
            district => 'where d.id = ?',
            company => 'where c.id = ?',
            company_multy => 'where c.id in ',
            building => 'where b.id = ?',
            object => 'where o.id = ?',
            region => 'where d.region = ?',
        },
    }, {
        keys => { map { $_ => 1 } qw( exploitation modernization ) },
        main => qq#
            select
                b.id as wo_grouping_contract_id,
                d.name as wo_grouping_district,
                c.name as wo_grouping_company_name,
                b.name as wo_grouping_address
                %s
            from buildings b
            join companies c on c.id = b.company_id
            join districts d on d.id = b.district_id
            %s %s
            order by b.id
        #,
        where => {
            district => 'where d.id = ?',
            company => 'where c.id = ?',
            company_multy => 'where c.id in ',
            building => 'where b.id = ?',
            object => 'where b.id = (select building from objects where id = ?)',
            region => 'where d.region = ?',
        },
        render_opts => {
            disable_grouping => 1,
        },
    },
);

sub build {
    my $self = shift;
    my $args = $self->req->params->to_hash;

    my $f = File::Temp->new(UNLINK => 1);
    my $workbook = Excel::Writer::XLSX->new($f->filename);

    my $calc_type = $args->{calc_type};
    $calc_type = undef if $calc_type && $calc_type eq "undef";

    if ($calc_type && !$calc_types{$calc_type}) {
        return $self->render(json => { status => 400, error => "calc_type is unknown" });
    }

    my $sql_stat = undef;
    my $render_opts => undef;
    my $where_statements;
    for (@sql_statements) {
        my $t = $calc_type // "main";
        if ($_->{keys}{$t}) {
            $sql_stat = $_->{main};
            $where_statements = $_->{where};
            $render_opts = $_->{render_opts};
            last;
        }
    }

    return $self->render(json => { status => 500, error => "Can't fetch data for given report type" })
        unless $sql_stat && $where_statements;

    my @order = qw( object building company district region );
    my $sql_part;
    my @sql_arg;

    for (@order) {
        if (defined $args->{$_}) {
            my $v = $args->{$_};
            if ($v =~ /,/ && $where_statements->{$_ . "_multy"}) {
                @sql_arg = split ',', $v;
                $sql_part = $where_statements->{$_ . "_multy"};
                $sql_part .= "(" . join(',', ('?') x (scalar @sql_arg)) . ")";
                last;
            }
            $sql_part = $where_statements->{$_};
            @sql_arg = ($v);
            last;
        }
    }

    unless (@sql_arg) {
        return $self->render(json => { status => 400, error => join(' or ', keys %$where_statements) . " not empty argument is required" });
    }

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
        title => $title,
        author => ($args->{name} || "") . " " . ($args->{lastname} || ""),
        # TODO: add other properties
        # http://search.cpan.org/~jmcnamara/Excel-Writer-XLSX-0.15/lib/Excel/Writer/XLSX.pm#add_format(_%properties_)
    );

    $self->render_xlsx($r, $workbook, $calc_type, $title, %{ $render_opts // {} });
    $workbook->close;

    my $file_name = $title;
    if ($args->{region}) {
        $file_name .= "_$args->{region}";
    } elsif ($args->{district}) {
        $r = select_all($self, qq/
            select name from districts where id = ?
        /, $args->{district});
        if ($r && @$r) {
            $file_name .= "_$r->[0]{name}";
        }
    } else {
        $r = select_all($self, qq/
            select
                f.path as name
                from files f
                join companies c on c.id = f.company_id
                join buildings b on b.company_id = f.company_id
                join objects o on o.building = b.id
                $sql_part
                limit 1
            /, @sql_arg);
        if ($r && @$r) {
            $file_name .=  "_$r->[0]{name}";
        }
    }
    $file_name =~ s/\s+/_/g;

    $f->unlink_on_destroy(0);
    return $self->render(json => { title => $file_name, filename => $f->filename });
}

1;
