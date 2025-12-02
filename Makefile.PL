use strict;
use warnings;
use ExtUtils::MakeMaker;
use Getopt::Long;
use Devel::CheckLib;

Getopt::Long::Configure('pass_through');
# perl Makefile.PL -d to enable -g flag for gdb.
# perl Makefile.PL --jsonnet-prefix=/opt/jsonnet
GetOptions(
    'd'                => \my $DEBUG,
    'jsonnet-prefix=s' => \my $opt_prefix,
) or die "Error in command line arguments\n";

# CLI > ENV
my $prefix = defined $opt_prefix ? $opt_prefix : $ENV{JSONNET_PREFIX};

my $inc_flags  = '';
my $lib_flags  = '-ljsonnet';
my %CHECKLIB_ARGS;

if ($prefix) {
    # Explicit prefix
    $inc_flags = "-I$prefix/include";
    $lib_flags = "-L$prefix $lib_flags";

    %CHECKLIB_ARGS = (
        header => 'libjsonnet.h',
        INC    => $inc_flags,
        LIBS   => $lib_flags,
    );
}
else {
    # Let's try pkg-config
    my $pc_libs   = `pkg-config --libs libjsonnet 2>/dev/null`;
    my $pc_cflags = `pkg-config --cflags libjsonnet 2>/dev/null`;
    chomp($pc_libs, $pc_cflags);

    if ($pc_libs || $pc_cflags) {
        $inc_flags = $pc_cflags if $pc_cflags;
        $lib_flags = $pc_libs   if $pc_libs;

        %CHECKLIB_ARGS = (
            header => 'libjsonnet.h',
            INC    => $inc_flags,
            LIBS   => $lib_flags,
        );
    }
    else {
        # A completely bare case: relying on the default compiler paths
        %CHECKLIB_ARGS = (
            header => 'libjsonnet.h',
            LIBS   => $lib_flags,
        );
    }
}

my $JSONNET_MIN_VERSION = '0.21.0';

# Hard check for the presence of libjsonnet: header + linker.
# If libjsonnet is not installed, this will be a neat "NA" for testers,
# instead of the cryptic "libjsonnet.h: No such file or directory"
check_lib_or_exit(%CHECKLIB_ARGS);


# Check that the jsonnet version >= 0.21.0
my $have_required_version = check_lib(
    %CHECKLIB_ARGS,
    function => <<'END_JSONNET_VERSION_CHECK',
        /* If the binary and header don't match, we consider it an error */
        if (strcmp(jsonnet_version(), LIB_JSONNET_VERSION) != 0) {
            return 1;
        }

        const char *v = jsonnet_version();
        int major = 0, minor = 0, patch = 0;

        /* expected format "X.Y[.Z]" */
        if (sscanf(v, "v%d.%d.%d", &major, &minor, &patch) < 3) {
            /* couldn't parse - we think the version is not suitable */
            return 1;
        }

        /* Requires >= 0.21.x:
         * - anything with major > 0 is automatically ok (1.0.0, 2.3.4, ...)
         * - or 0.minor, where minor >= 21
         */
        if (major > 0 || (major == 0 && minor >= 21)) {
            return 0; /* OK */
        }

        /* version is too old */
        return 1;
END_JSONNET_VERSION_CHECK
);

unless ($have_required_version != 1) {
    warn <<"END_MSG";
*** Jsonnet::XS: found libjsonnet, but its version is too old.
*** Required libjsonnet version: >= $JSONNET_MIN_VERSION
*** Please upgrade libjsonnet and re-run perl Makefile.PL.
END_MSG
    # Important: exit 0 so that CPAN testers will treat this as NA and not FAIL
    exit 0;
}

WriteMakefile(
    NAME               => 'Jsonnet::XS',
    VERSION_FROM       => 'lib/Jsonnet/XS.pm',
    ABSTRACT_FROM      => 'lib/Jsonnet/XS.pm',
    AUTHOR             => 'Sergey Kovalev <info@neolite.ru>',
    LICENSE            => 'perl_5',

    MIN_PERL_VERSION   => '5.30.0',

    LIBS               => [ $lib_flags ],
    INC                => $inc_flags,
    XS                 => { 'Jsonnet.xs' => 'Jsonnet.c' },

    TYPEMAPS           => [ 'typemap' ],

    clean              => { FILES => 'Jsonnet.c Jsonnet.o cover_db MYMETA.*' },

    PREREQ_PM          => {
        'JSON::MaybeXS' => 0,
        'Test2::V0'     => 0,
    },

    OBJECT             => '$(O_FILES)',
    OPTIMIZE           => $DEBUG ? '-g' : '-O2',

    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
        'Devel::CheckLib'     => 0,
    },

    META_MERGE => {
        'meta-spec' => { version => 2 },  # CPAN Meta Spec v2 :contentReference[oaicite:1]{index=1}
        resources => {
            license    => [ 'https://dev.perl.org/licenses/' ],
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
                    'Devel::CheckLib'     => 0,
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
