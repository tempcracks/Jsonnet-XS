use Test2::V0;
use Jsonnet::XS;

my $vm = Jsonnet::XS->new();

ok lives { $vm->max_stack(1000) },           "max_stack";
ok lives { $vm->gc_min_objects(10) },       "gc_min_objects";
ok lives { $vm->gc_growth_trigger(2.5) },   "gc_growth_trigger";
ok lives { $vm->max_trace(20) },            "max_trace";

# string_output observable behavior:
# without string_output, top-level string becomes JSON string with quotes
my $a = $vm->evaluate_snippet("s1", '"hello"');
like $a, qr/^"hello"\n?$/, "default string_output=0 => JSON string";

$vm->string_output(1);
my $b = $vm->evaluate_snippet("s2", '"hello"');
like $b, qr/^hello\n?$/, "string_output=1 => raw string";

done_testing;
