#!/usr/bin/perl

use strict;
use warnings;

use lib qw( /root/repo/master/lib );

use DB qw( :all );

for my $table_name (qw( laying_methods isolations )) {
    my %distincts;

    my $r = select_all undef, "select id, name from $table_name order by name";
    for (@$r) {
        $_->{name} =~ s/^\s+|\s+$//;
        $_->{name} =~ s/\s+/ /;
        push @{$distincts{$_->{name}}}, $_->{id};
    }

    my %col_names = ( laying_methods => 'laying_method', isolations => 'isolation' );
    my $id = 1;
    for (keys %distincts) {
        execute_query undef, sprintf("update objects set $col_names{$table_name} = ? where $col_names{$table_name} in (%s)",
            join ',', (map { '?' } @{$distincts{$_}})), $id, @{$distincts{$_}};

        execute_query undef, "update $table_name set name = ? where id = ?", $_, $id++;
    }

    execute_query undef, "delete from $table_name where id >= $id";
}
