use Test2::V0;
use Jsonnet::XS;

my $vm = Jsonnet::XS->new();

like dies {
    $vm->evaluate_snippet("bad", '{ x: }')
}, qr/(STATIC|RUNTIME) ERROR/i, "syntax error croaks";

like dies {
    $vm->evaluate_snippet("bad2", '1/0')
}, qr/(STATIC|RUNTIME) ERROR/i, "runtime error croaks";

done_testing;
