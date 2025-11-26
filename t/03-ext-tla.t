use Test2::V0;
use JSON::MaybeXS qw(decode_json);
use Jsonnet::XS;

my $vm = Jsonnet::XS->new(
    ext_vars   => { foo => "bar" },
    ext_codes  => { num => "1+2" },
    tla_vars   => { env => "prod" },
    tla_codes  => { cfg => '{ replicas: 3 }' },
);

my $txt = $vm->evaluate_snippet("exttla", q'
function(env, cfg)
{
  a: std.extVar("foo"),
  b: std.extVar("num"),
  c: env,
  d: cfg.replicas,
}
');

is decode_json($txt),
   { a => "bar", b => 3, c => "prod", d => 3 },
   "ext vars via std.extVar + TLA args via top-level function";

done_testing;
