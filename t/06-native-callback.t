use Test2::V0;
use JSON::MaybeXS;
use Jsonnet::XS;

my $vm = Jsonnet::XS->new();
my $J  = JSON::MaybeXS->new(allow_nonref => 1);

$vm->native_callback(
    "add",
    sub { my ($a, $b) = @_; return $a + $b },
    [qw(a b)],
);

my $txt = $vm->evaluate_snippet("add", q'std.native("add")(2, 3)');
is $J->decode($txt), 5, "native add with params";

$vm->native_callback(
    "mk",
    sub {
        return {
            foo   => "bar",
            n     => 2,
            arr   => [1,2],
            nullv => undef,
        };
    },
    [],
);

my $txt2 = $vm->evaluate_snippet("mk", q'std.native("mk")()');
is $J->decode($txt2),
   { foo => "bar", n => 2, arr => [1,2], nullv => undef },
   "native return complex structure";

$vm->native_callback(
    "boom",
    sub { die "boom from perl" },
    [],
);

like dies {
    $vm->evaluate_snippet("boom", q'std.native("boom")()')
}, qr/boom from perl/i, "native error propagates";

done_testing;
