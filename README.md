# Jsonnet::XS

[![CPAN version](https://badge.fury.io/pl/Jsonnet-XS.svg)](https://metacpan.org/pod/Jsonnet::XS)
[![CPAN testers](https://cpantesters.org/distro/J/Jsonnet-XS.svg)](https://cpantesters.org/distro/J/Jsonnet-XS)
[![License](https://img.shields.io/badge/license-Perl%205-blue.svg)](https://dev.perl.org/licenses/)
[![Perl](https://img.shields.io/badge/perl-5.30%2B-blue.svg)](https://www.perl.org/)
[![CI](https://github.com/neo1ite/Jsonnet-XS/actions/workflows/ci.yml/badge.svg)](https://github.com/neo1ite/Jsonnet-XS/actions/workflows/ci.yml)
[![ZH](https://img.shields.io/badge/Language-Chinese.svg)](https://github.com/tempcracks/Jsonnet-XS/blob/main/doc/README.zh.md)

Perl XS bindings to **libjsonnet** (Google Jsonnet C/C++ API).

This module provides a thin, low-level interface to the official Jsonnet VM.
You can evaluate Jsonnet snippets/files, use multi/stream outputs, and register
custom import and native callbacks from Perl.

---

## Requirements

This distribution **requires libjsonnet (development headers and shared library)**.

You need:

- `libjsonnet.h`
- `libjsonnet.so` (or equivalent)
- C++ standard library for linking (`libstdc++`)

Jsonnet version **0.21.x or newer is recommended**.

### Debian / Ubuntu

```bash
sudo apt install libjsonnet-dev jsonnet
````

### Fedora

```bash
sudo dnf install jsonnet jsonnet-devel
```

### Arch

```bash
sudo pacman -S jsonnet
```

### macOS (Homebrew)

```bash
brew install jsonnet
```

### From source (if packages are unavailable)

```bash
git clone https://github.com/google/jsonnet.git
cd jsonnet
make libjsonnet.so
sudo cp include/libjsonnet.h /usr/local/include/
sudo cp libjsonnet.so /usr/local/lib/
sudo ldconfig   # on Linux
```

---

## Installation
Before need install `cpanm`
### Debian / Ubuntu

```bash
sudo apt install cpanm
````

### Fedora

```bash
sudo dnf install cpanm
```

### Arch

```bash
sudo pacman -S cpanm
```

### macOS (Homebrew)

```bash
brew install cpanm
```
---

### Standard CPAN install

```bash
cpanm Jsonnet::XS
```

### If libjsonnet is in a non-standard prefix

Set `JSONNET_PREFIX` so the build can find headers and library:

```bash
JSONNET_PREFIX=/opt/jsonnet cpanm Jsonnet::XS
```

or when building from the repo:

```bash
JSONNET_PREFIX=/opt/jsonnet perl Makefile.PL
make
make test
make install
```

The build will also try `pkg-config libjsonnet` automatically when available.

---

## Usage

### Basic evaluation

```perl
use Jsonnet::XS;

my $vm = Jsonnet::XS->new(
    ext_vars => { foo => "bar" },
);

my $json = $vm->evaluate_snippet("snippet", '{ x: std.extVar("foo") }');
print $json;
```

### Evaluate a file

```perl
my $json = $vm->evaluate_file("main.jsonnet");
print $json;
```

### Multi output

Multi mode returns a hashref where keys are output filenames:

```perl
my $out = $vm->evaluate_file_multi("multi.jsonnet");

for my $name (sort keys %$out) {
    print "== $name ==\n";
    print $out->{$name};
}
```

### Stream output

Stream mode returns an arrayref of JSON texts:

```perl
my $items = $vm->evaluate_snippet_stream("s", '[{a:1},{b:2}]');

for my $j (@$items) {
    print $j;
}
```

### Import callback

Register a custom importer. The callback must return:

* `($found_here, $content)` on success
* `(undef, $error_text)` on failure

```perl
$vm->import_callback(sub {
    my ($base, $rel) = @_;

    # Example: virtual import
    return ("virtual.jsonnet", '{ z: 42 }')
        if $rel eq "virtual.jsonnet";

    return (undef, "no such import: $rel");
});

my $json = $vm->evaluate_snippet("x", q'
local v = import "virtual.jsonnet";
{ z: v.z }
');
print $json;
```

Note: once you set `import_callback`, it replaces the default importer.
If you want filesystem imports too, implement them in your callback.

### Native callbacks (std.native)

```perl
$vm->native_callback(
    "add",
    sub { my ($a, $b) = @_; $a + $b },
    [qw(a b)],
);

print $vm->evaluate_snippet("n", 'std.native("add")(2, 3)');
```

Native callbacks accept primitive Jsonnet values (string/number/bool/null).
Return values can be scalars, arrayrefs, hashrefs, or undef.

---

## VM Options

You can set tuning parameters either via constructor or later:

```perl
my $vm = Jsonnet::XS->new(
    max_stack         => 1000,
    gc_min_objects    => 10,
    gc_growth_trigger => 2.5,
    max_trace         => 20,
    string_output     => 0,
);

$vm->jpath_add("./libsonnet");
$vm->ext_var("env", "prod");
$vm->tla_var("cfg", "value");
```

`string_output => 1` makes top-level Jsonnet strings return without JSON quotes.

---

## Troubleshooting

### `undefined symbol: jsonnet_make` when loading the module

Your `Jsonnet.so` was built without linking to `libjsonnet`.

Fix by installing `libjsonnet-dev` or rebuilding with a correct prefix:

```bash
JSONNET_PREFIX=/path/to/jsonnet perl Makefile.PL
make clean
make
make test
```

### Build cannot find `libjsonnet.h`

Install the development package (`libjsonnet-dev`, `jsonnet-devel`) or
provide `JSONNET_PREFIX`.

### Import errors after setting `import_callback`

Setting an import callback replaces default imports. Handle filesystem
imports yourself if needed.

---

## License

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

---

## Author

Sergey Kovalev info@neolite.ru
