use Test2::V0;
use JSON::MaybeXS qw(decode_json);
use File::Temp qw(tempfile);
use Jsonnet::XS;

my $vm = Jsonnet::XS->new();

# snippet
my $json_text = $vm->evaluate_snippet("snippet", '{ x: 1 + 2 }');
is decode_json($json_text), { x => 3 }, "evaluate_snippet works";

# file
my ($fh, $fname) = tempfile(SUFFIX => ".jsonnet");
print $fh '{ y: std.length([1,2,3]) }';
close $fh;

my $json_file = $vm->evaluate_file($fname);
is decode_json($json_file), { y => 3 }, "evaluate_file works";

done_testing;
