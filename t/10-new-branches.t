use Test2::V0;
use JSON::MaybeXS;
use File::Temp qw(tempdir);
use File::Spec;
use Jsonnet::XS;

my $dir = tempdir(CLEANUP => 1);

# Файл для jpath-импорта
my $libfile = File::Spec->catfile($dir, "lib.jsonnet");
open my $fh, ">", $libfile or die $!;
print $fh '{ k: "from-jpath-scalar" }';
close $fh;

my $J = JSON::MaybeXS->new(allow_nonref => 1);

# ---------- VM1: ветки jpathdir-скаляр + string_output + числовые опции ----------
my $vm1 = Jsonnet::XS->new(
    max_stack          => 1000,
    gc_min_objects     => 5,
    gc_growth_trigger  => 2.1,
    max_trace          => 3,

    string_output      => 0,   # exists-but-false ветка
    jpathdir           => $dir, # скалярная ветка (обёртка в ARRAY)

    ext_vars           => { foo => "bar" },
    ext_codes          => { num => "1+2" },
);

# string_output=0 должен оставлять кавычки
my $s = $vm1->evaluate_snippet("so0", '"hi"');
like $s, qr/^"hi"\n?$/, "string_output passed via new (0)";

# jpathdir (скаляром) реально работает
my $j = $vm1->evaluate_snippet("jp_scalar", q'
local lib = import "lib.jsonnet";
{ x: lib.k }
');
is $J->decode($j), { x => "from-jpath-scalar" }, "jpathdir scalar branch works";

# ---------- VM2: ветки import_callback + native_callbacks через new ----------
my $vm2 = Jsonnet::XS->new(
    import_callback    => sub {
        my ($base, $rel) = @_;
        return ("virtual.jsonnet", '{ z: 7 }') if $rel eq "virtual.jsonnet";
        return (undef, "no such import: $rel");
    },

    native_callbacks   => {
        echo => {
            cb     => sub { my ($x) = @_; return $x },
            params => [qw(x)],
        },
    },
);

my $i = $vm2->evaluate_snippet("imp_new", q'
local v = import "virtual.jsonnet";
{ z: v.z }
');
is $J->decode($i), { z => 7 }, "import_callback set via new works";

my $n = $vm2->evaluate_snippet("nat_new", q'std.native("echo")("hello")');
is $J->decode($n), "hello", "native_callbacks set via new works";

done_testing;
