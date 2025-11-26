use Test2::V0;
use Jsonnet::XS;

my $vm = Jsonnet::XS->new();

like dies {
    $vm->native_callback("bad1", "not_a_coderef", []);
}, qr/native_callback expects a coderef/i,
  "native_callback croaks if coderef is not coderef";

like dies {
    $vm->native_callback("bad2", sub { 1 }, "not_an_arrayref");
}, qr/native_callback expects params as arrayref/i,
  "native_callback croaks if params is not arrayref";

like dies {
    $vm->native_callback("bad3", sub { 1 }, [undef]);
}, qr/params\[0\] is undefined/i,
  "native_callback croaks if params contain undef";

done_testing;
