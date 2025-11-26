use Test2::V0;
use Jsonnet::XS;

my $vm = Jsonnet::XS->new();

$vm->import_callback(sub {
    die "import boom from perl";
});

like dies {
    $vm->evaluate_snippet("die_import", q'import "anything.jsonnet"');
}, qr/import boom from perl/i,
  "die inside import_callback propagates as eval error";

done_testing;
