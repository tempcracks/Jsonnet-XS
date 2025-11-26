use strict;
use warnings;
use ExtUtils::MakeMaker;

use Getopt::Long;
use Devel::CheckLib;
# perl Makefile.PL -d to enable -g flag for gdb.
Getopt::Long::Configure('pass_through');
GetOptions(
    'd'                => \my $DEBUG,
    'jsonnet-prefix=s' => \my $JSONNET_PREFIX,
) or die "Error in command line arguments\n";

my $prefix = $ENV{JSONNET_PREFIX};

my $inc  = '';
my $libs = '-ljsonnet -lstdc++';

if ($prefix) {
    $inc  = "-I$prefix/include";
    $libs = "-L$prefix/lib $libs";
}
else {
    my $pc_libs   = `pkg-config --libs libjsonnet 2>/dev/null`;
    my $pc_cflags = `pkg-config --cflags libjsonnet 2>/dev/null`;
    chomp($pc_libs, $pc_cflags);
    $inc  = $pc_cflags if $pc_cflags;
    $libs = $pc_libs   if $pc_libs;
}

WriteMakefile(
    NAME               => 'Jsonnet::XS',
    VERSION_FROM       => 'lib/Jsonnet/XS.pm',
    ABSTRACT_FROM      => 'lib/Jsonnet/XS.pm',
    AUTHOR             => 'Sergey Kovalev <info@neolite.ru>',
    LICENSE            => 'perl_5',

    MIN_PERL_VERSION   => '5.30.0',

    LIBS               => [$libs],
    INC                => $inc,
    XS                 => { 'Jsonnet.xs' => 'Jsonnet.c' },

    TYPEMAPS           => ['typemap'],

    clean              => { FILES => 'Jsonnet.c Jsonnet.o cover_db MYMETA.*' },

    PREREQ_PM          => {
        'JSON::MaybeXS' => 0,
        'Test2::V0'     => 0,
    },

    OBJECT             => '$(O_FILES)',
    OPTIMIZE           => $DEBUG ? '-g' : '-O2',
    CONFIGURE_REQUIRES => {
        'Devel::CheckLib' => 0,
    },

    META_MERGE => {
        'meta-spec' => { version => 2 },  # CPAN Meta Spec v2 :contentReference[oaicite:1]{index=1}
        resources => {
            license    => ['https://dev.perl.org/licenses/'],
            repository => {
                type => 'git',
                url  => 'https://github.com/neo1ite/Jsonnet-XS.git',
                web  => 'https://github.com/neo1ite/Jsonnet-XS',
            },
            bugtracker => {
                web => 'https://github.com/neo1ite/Jsonnet-XS/issues',
            },
        },
        prereqs => {
            configure => {
                requires => {
                    'ExtUtils::MakeMaker' => 0,
                },
            },
        },
    },

    TEST_REQUIRES => {
        'Test::Pod'            => 0,
        'Test::Pod::Coverage'  => 0,
        'Test::CPAN::Meta'     => 0,
    },
);
