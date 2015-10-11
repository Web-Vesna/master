package DB;

use strict;
use warnings;

use DBI;
use Carp;

use MainConfig qw( :all );

use base qw(Exporter);

our @EXPORT_OK = qw(
    select_row
    select_all
    execute_query
    prepare_query
    execute_prepared
    last_err
    last_id
);

our %EXPORT_TAGS = (
    all => [@EXPORT_OK],
);

my $dbh;
my %prepared;

BEGIN {
    $dbh = DBI->connect(
        'dbi:mysql:database=' . DB_NAME . ':host=' . DB_HOST . ':port=' . DB_PORT,
        DB_USER, DB_PASS,
        {
            AutoCommit => 1,
            RaiseError => 0,
            mysql_enable_utf8 => 1,
            mysql_auto_reconnect => 1,
        }
    ) or croak "Can't connect to '" . DB_NAME . "' database: " . DBI::errstr();
}

sub last_err {
    my $ctl = shift;
    return $dbh->errstr;
}

sub select_row {
    my ($ctl, $query, @args) = @_;

    $ctl->app->log->debug(sprintf "SQL query: '%s'. [args: %s]", $query, join(',', map { $_ // "undef" } @args)) if $ctl;
    my $sth = $dbh->prepare($query);
    $sth->execute(@args) or return $ctl->app->log->warn($dbh->errstr) and undef;

    return $sth->fetchrow_hashref();
}

sub select_all {
    my ($ctl, $query, @args) = @_;
    $ctl->app->log->debug(sprintf "SQL query: '%s'. [args: %s]", $query, join(',', map { $_ // "undef" } @args)) if $ctl;
    return $dbh->selectall_arrayref($query, { Slice => {} }, @args) or ($ctl->app->log->warn($dbh->errstr) and undef);
}

sub execute_query {
    my ($ctl, $query, @args) = @_;
    $ctl->app->log->debug(sprintf "SQL query: '%s'. [args: %s]", $query, join(',', map { $_ // "undef" } @args)) if $ctl;
    return $dbh->do($query, undef, @args) or ($ctl->app->log->warn($dbh->errstr) and undef);
}

sub prepare_query {
    my ($ctl, $query) = @_;
    $ctl->app->log->debug("Preparing SQL query: '$query'") if $ctl;
    my $sth = $dbh->prepare($query);
    $prepared{$sth} = $query;
    return $sth;
}

sub execute_prepared {
    my ($ctl, $sth, @args) = @_;
    $ctl->app->log->debug(sprintf "Executing prepared query: '%s' [args: %s]",
        ($prepared{$sth} || ''), join(',', map { defined $_ ? $_ : "undef" } @args)) if $ctl;
    return $sth->execute(@args);
}

sub last_id {
    my $ctl = shift;
    my $row = select_row $ctl, 'select last_insert_id() as id';
    return $row && $row->{id};
}

1;
