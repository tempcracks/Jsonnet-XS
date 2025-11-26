use Test2::V0;
use Jsonnet::XS;

my $vm = Jsonnet::XS->new(
    string_output => 1,   # ветка exists + true
);

my $out = $vm->evaluate_snippet("so1", '"hi"');
like $out, qr/^hi\n?$/, "string_output=>1 via new (true branch)";

done_testing;
