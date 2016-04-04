package MainConfig;

use strict;
use warnings;

use Carp qw(croak);

use Cwd 'abs_path';
use base qw(Exporter);

my %PARAMS = (
    # undef params are required
    FRONT_PORT      => 6000,
    DATA_PORT       => 6001,
    SESSION_PORT    => 6002,
    LOGIC_PORT      => 6003,
    FILES_PORT      => 6004,

    FRONT_HOST      => 'localhost',
    DATA_HOST       => 'localhost',
    SESSION_HOST    => 'localhost',
    LOGIC_HOST      => 'localhost',
    FILES_HOST      => 'localhost',

    FILES_URL       => 'unknown',

    ROOT_FILES_PATH => '.',
    PHOTOS_PATH     => '.',
    URL_404         => '/404.html',
    URL_401         => '/login.html',

    DB_HOST         => 'localhost',
    DB_PORT         => 3306,
    DB_NAME         => undef,
    DB_USER         => undef,
    DB_PASS         => undef,

    MEMC_HOST       => 'localhost',
    MEMC_PORT       => 11211,

    GENERAL_URL     => '',
    COOKIE_PATH     => '/',
    COOKIE_DOMAIN   => '',
    COOKIE_SECRET   => '',
    MEMC_KEY        => '',

    ALLOW_ORIGIN    => '',

    EXP_TIME        => 60 * 60 * 24,
);

our @EXPORT_OK = keys %PARAMS;
our %EXPORT_TAGS = ( all => [@EXPORT_OK], );

my $path = "/usr/local/apek-energo/etc/apek-energo.conf";

my %CFG;
my $f;

unless (open $f, '<', 'config') {
    open $f, '<', $path or croak "Can't open $path: $!\n";
}

while (<$f>) {
    chomp;
    s/#.*//;

    my ($name, $val) = /(\w*)\s*=\s*(.*)/;
    next unless $name;
    if ($val =~ /,/) {
        $val = [split ',', $val];
    }
    $CFG{$name} = $val;
}

$CFG{COOKIE_SECRET} = [$CFG{COOKIE_SECRET}] if ref($CFG{COOKIE_SECRET}) ne "ARRAY";

close $f;

sub make_sub {
    my ($sub_name) = @_;
    local $@;
    eval <<SUB;
        sub $sub_name() {
            croak "Can't locate $sub_name in config\\n" unless defined(\$CFG{$sub_name} || \$PARAMS{$sub_name});
            return \$CFG{$sub_name} || \$PARAMS{$sub_name};
        }
SUB
    croak "Can't make subs: $@\n" if $@;
}

for (keys %PARAMS) {
    croak "$_ config param is required\n" if !defined $PARAMS{$_} && !defined $CFG{$_};
    make_sub $_;
}

1;
