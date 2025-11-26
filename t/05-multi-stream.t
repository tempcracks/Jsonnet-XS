use Test2::V0;
use JSON::MaybeXS;
use File::Temp qw(tempfile);
use Jsonnet::XS;

my $vm = Jsonnet::XS->new();
my $J  = JSON::MaybeXS->new(allow_nonref => 1);

# multi from snippet
my $multi = $vm->evaluate_snippet_multi("m", q'
{
  "a.json": { x: 1 },
  "b.json": { y: 2 },
}
');
is [sort keys %$multi], [qw(a.json b.json)], "multi keys";
is $J->decode($multi->{"a.json"}), { x => 1 }, "multi a.json";
is $J->decode($multi->{"b.json"}), { y => 2 }, "multi b.json";

# multi from file
my ($fh, $fname) = tempfile(SUFFIX => ".jsonnet");
print $fh q'
{
  "c.json": { z: 3 },
}
';
close $fh;

my $multi_f = $vm->evaluate_file_multi($fname);
is $J->decode($multi_f->{"c.json"}), { z => 3 }, "file_multi works";

# stream from snippet
my $stream = $vm->evaluate_snippet_stream("s", q'
[
  { a: 1 },
  { b: 2 },
]
');
is scalar(@$stream), 2, "stream count";
is $J->decode($stream->[0]), { a => 1 }, "stream item 0";
is $J->decode($stream->[1]), { b => 2 }, "stream item 1";

# stream from file with scalar items
my ($fh2, $fname2) = tempfile(SUFFIX => ".jsonnet");
print $fh2 q'[1,2,3]';
close $fh2;

my $stream_f = $vm->evaluate_file_stream($fname2);
is [ map { $J->decode($_) } @$stream_f ], [1,2,3], "file_stream works";

done_testing;
