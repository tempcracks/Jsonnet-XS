package Jsonnet::XS;

use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Jsonnet::XS ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(

) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(

);

our $VERSION = '0.00_03';
our $XS_VERSION = $VERSION;
$VERSION = eval $VERSION;  # see L<perlmodstyle>

require XSLoader;
XSLoader::load(__PACKAGE__, $VERSION);

# Небольшой sugar-OO поверх XS:
sub new {
    my ($class, %opt) = @_;
    my $self = _new();
    bless $self, $class;

    $self->max_stack($opt{max_stack})                 if defined $opt{max_stack};
    $self->gc_min_objects($opt{gc_min_objects})       if defined $opt{gc_min_objects};
    $self->gc_growth_trigger($opt{gc_growth_trigger}) if defined $opt{gc_growth_trigger};
    $self->max_trace($opt{max_trace})                 if defined $opt{max_trace};
    $self->string_output($opt{string_output} ? 1 : 0) if exists  $opt{string_output};

    if (my $jp = $opt{jpathdir}) {
        $jp = [$jp] unless ref $jp eq 'ARRAY';
        $self->jpath_add($_) for @$jp;
    }

    if (my $ev = $opt{ext_vars})  { $self->ext_var($_,  $ev->{$_}) for keys %$ev }
    if (my $ec = $opt{ext_codes}) { $self->ext_code($_, $ec->{$_}) for keys %$ec }
    if (my $tv = $opt{tla_vars})  { $self->tla_var($_,  $tv->{$_}) for keys %$tv }
    if (my $tc = $opt{tla_codes}) { $self->tla_code($_, $tc->{$_}) for keys %$tc }

    if (my $icb = $opt{import_callback}) {
        $self->import_callback($icb);
    }

    if (my $ncb = $opt{native_callbacks}) {
        # { name => { cb => sub{...}, params => [qw(a b)] }, ... }
        for my $name (keys %$ncb) {
            $self->native_callback($name, $ncb->{$name}{cb}, $ncb->{$name}{params});
        }
    }

    return $self;
}

1;

=pod

=head1 NAME

Jsonnet::XS - XS bindings to libjsonnet (C++ Jsonnet)

=head1 SYNOPSIS

  use Jsonnet::XS;

  my $vm = Jsonnet::XS->new(
      jpathdir => ["./libsonnet"],
      ext_vars => { ENV => "prod" },
      tla_vars => { env => "prod" },
  );

  my $json = $vm->evaluate_snippet("snippet", '{ x: 1 }');
  print $json;

=head1 DESCRIPTION

This module provides a thin XS interface to the official Jsonnet C API
(libjsonnet). It lets you evaluate Jsonnet snippets/files, use multi/stream
outputs, and register import and native callbacks from Perl.

=head1 METHODS

=head2 new(%options)

Create a new Jsonnet VM.

All options are optional:

=over 4

=item * max_stack, gc_min_objects, gc_growth_trigger, max_trace

VM tuning parameters.

=item * string_output => 0|1

If true, a top-level Jsonnet string is returned as raw text without JSON quotes.

=item * jpathdir => $dir | \@dirs

Import search paths (like Jsonnet C<-J>).

=item * ext_vars / ext_codes

External variables/codes (available via C<std.extVar()>).

=item * tla_vars / tla_codes

Top-level arguments (TLA). In Jsonnet they are passed as parameters
to the top-level function.

=item * import_callback => sub { ... }

Custom importer. Must return:

  ( $found_here, $content )   # success
  ( undef, $error_text )      # failure

=item * native_callbacks => { name => { cb => sub{...}, params => \@p }, ... }

Register C<std.native(...)> callbacks.

=back

=head2 evaluate_snippet($filename, $snippet)

Evaluate a Jsonnet snippet and return resulting JSON text (pretty-printed by
libjsonnet). On error this method throws an exception with the Jsonnet error
message.

=head2 evaluate_file($filename)

Evaluate a Jsonnet file and return resulting JSON text. Dies on Jsonnet errors.

=head2 evaluate_snippet_multi($filename, $snippet)

Evaluate a snippet in "multi" mode. Returns a hashref:

  { "file1.json" => $json_text, "file2.json" => $json_text, ... }

Dies on Jsonnet errors.

=head2 evaluate_file_multi($filename)

Same as C<evaluate_snippet_multi>, but evaluates a file.

=head2 evaluate_snippet_stream($filename, $snippet)

Evaluate a snippet in "stream" mode. Returns an arrayref of JSON texts,
one per element in the top-level array. Dies on Jsonnet errors.

=head2 evaluate_file_stream($filename)

Same as C<evaluate_snippet_stream>, but evaluates a file.

=head2 ext_var($key, $value)

Set an external variable for C<std.extVar($key)>.

=head2 ext_code($key, $code)

Set an external code snippet for C<std.extVar($key)>.

=head2 tla_var($key, $value)

Set a top-level argument (TLA) variable. TLAs are passed as parameters
to the top-level function.

=head2 tla_code($key, $code)

Set a top-level argument (TLA) code snippet.

=head2 jpath_add($dir)

Add an import search directory (like Jsonnet C<-J>).

=head2 import_callback($coderef)

Register a custom importer. The callback is called as:

  my ($base, $rel) = @_;
  return ($found_here, $content);   # success
  return (undef, $error_text);      # failure

If the callback dies, evaluation fails with that error.

=head2 native_callback($name, $coderef, \@params)

Register a C<std.native($name)> callback.

C<@params> is the list of parameter names as used by Jsonnet.

=head2 max_stack($n)

=head2 gc_min_objects($n)

=head2 gc_growth_trigger($factor)

=head2 max_trace($n)

=head2 string_output($bool)

VM tuning options. See libjsonnet documentation for details.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 AUTHOR

Sergey Kovalev E<lt>info@neolite.ruE<gt>

=cut
