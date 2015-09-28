#!/usr/bin/perl

use strict;
use warnings;
use utf8;

# XXX: FILL COORDINATES

my $fname = '/tmp/address list.txt';

open my $f, '<', $fname or die "can't open: $!\n";

use lib qw( /root/repo/master/lib );
use DB qw( :all );

DB::execute_query(undef, "SET NAMES UTF8");
my $d = DB::select_all(undef, 'select id, name from districts');

my %districts = map { utf8::encode($_->{name}); lc($_->{name}) => $_->{id} } @$d;

my %data;
my $id = 0;
while (<$f>) {
    ++$id;
    chomp;
    my @row = split "\t";
    unless (defined $districts{lc $row[2]}) {
        warn "Unknown district found: $row[2] (row $id). Ignore\n";
        next;
    }
    push @{$data{$row[0]}}, { id => 2000 + $id, addr => $row[1], district => $districts{lc $row[2]} };
}

my $select = DB::prepare_query(undef, "select id from companies where name = ?");
my $insert = DB::prepare_query(undef, "insert into companies(name) values (?)");
for (keys %data) {
    if (DB::execute_prepared(undef, $select, $_) eq '0E0') {
        DB::execute_prepared(undef, $insert, $_);
        DB::execute_prepared(undef, $select, $_);
    }
    my ($id) = $select->fetchrow_array;
    map { $_->{company} = $id } @{ $data{$_} };
}

$insert = DB::prepare_query(undef, qq/insert into buildings(id, company_id, status, name, corpus, district_id, flags) values
    (?, ?, '', ?, '', ?, 'editable')/);

for my $c (values %data) {
    for (@$c) {
        DB::execute_prepared(undef, $insert, @$_{qw( id company addr district )});
    }
}
