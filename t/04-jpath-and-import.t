use Test2::V0;
use JSON::MaybeXS qw(decode_json);
use File::Temp qw(tempdir);
use File::Spec;
use Jsonnet::XS;

my $dir = tempdir(CLEANUP => 1);
my $libfile = File::Spec->catfile($dir, "lib.jsonnet");
open my $fh, ">", $libfile or die $!;
print $fh '{ k: "v-from-jpath" }';
close $fh;

my $vm = Jsonnet::XS->new( jpathdir => [$dir] );

my $txt = $vm->evaluate_snippet("use_jpath", q'
local lib = import "lib.jsonnet";
{ x: lib.k }
');
is decode_json($txt), { x => "v-from-jpath" }, "import via jpath works";

# now import_callback, overriding import resolution
my $called = 0;
$vm->import_callback(sub {
    my ($base, $rel) = @_;
    $called++;

    if ($rel eq "virtual.jsonnet") {
        return ("virtual.jsonnet", '{ z: 42 }');
    }
    return (undef, "no such import: $rel");
});

my $txt2 = $vm->evaluate_snippet("use_import_cb", q'
local v = import "virtual.jsonnet";
{ z: v.z }
');

is decode_json($txt2), { z => 42 }, "import_callback success path";
ok $called >= 1, "import_callback was called";

# import failure => croak
like dies {
    $vm->evaluate_snippet("bad_import", 'import "nope.jsonnet"')
}, qr/no such import/i, "import_callback failure croaks";

done_testing;
