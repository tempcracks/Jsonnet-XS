# Jsonnet::XS

[![CPAN version](https://badge.fury.io/pl/Jsonnet-XS.svg)](https://metacpan.org/pod/Jsonnet::XS)
[![CPAN testers](https://cpantesters.org/distro/J/Jsonnet-XS.svg)](https://cpantesters.org/distro/J/Jsonnet-XS)
[![License](https://img.shields.io/badge/license-Perl%205-blue.svg)](https://dev.perl.org/licenses/)
[![Perl](https://img.shields.io/badge/perl-5.30%2B-blue.svg)](https://www.perl.org/)
[![CI](https://github.com/neo1ite/Jsonnet-XS/actions/workflows/ci.yml/badge.svg)](https://github.com/neo1ite/Jsonnet-XS/actions/workflows/ci.yml)

libjsonnet（Google Jsonnet C/C++ API）的 Perl XS 绑定。

本模块提供了对官方 Jsonnet 虚拟机的一个轻量级、底层接口。你可以从 Perl 代码中评估 Jsonnet 代码片段/文件，使用多重/流式输出，并注册自定义的导入和原生函数回调。
系统要求

本发行版需要依赖 libjsonnet（开发头文件和共享库）。

你需要：

 -  libjsonnet.h

 -  libjsonnet.so（或等效文件）

 -  用于链接的 C++ 标准库（libstdc++）

建议使用 Jsonnet 0.21.x 或更高版本。

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

从源码编译（如果包管理器不可用）
```bash
git clone https://github.com/google/jsonnet.git
cd jsonnet
make libjsonnet.so
sudo cp include/libjsonnet.h /usr/local/include/
sudo cp libjsonnet.so /usr/local/lib/
sudo ldconfig   # on Linux
```

---

安装
标准 CPAN 安装

```bash
cpanm Jsonnet::XS
```
如果 libjsonnet 安装在非标准路径

设置环境变量 JSONNET_PREFIX，以便构建过程能找到头文件和库：

```bash
JSONNET_PREFIX=/opt/jsonnet cpanm Jsonnet::XS
```

或者从源码仓库中构建：
```bash
JSONNET_PREFIX=/opt/jsonnet perl Makefile.PL
make
make test
make install
```

在可用的情况下，构建过程也会自动尝试 pkg-config libjsonnet。
使用方法
基本求值
---

```perl
use Jsonnet::XS;

my $vm = Jsonnet::XS->new(
    ext_vars => { foo => "bar" },
);

my $json = $vm->evaluate_snippet("snippet", '{ x: std.extVar("foo") }');
print $json;
```

求值文件

```perl
my $json = $vm->evaluate_file("main.jsonnet");
print $json;
```

多重输出模式

多重模式返回一个哈希引用，键为输出文件名：


```perl
my $out = $vm->evaluate_file_multi("multi.jsonnet");

for my $name (sort keys %$out) {
    print "== $name ==\n";
    print $out->{$name};
}
```

### 流式输出模式

流式模式返回一个 JSON 文本数组引用：

```perl
my $items = $vm->evaluate_snippet_stream("s", '[{a:1},{b:2}]');

for my $j (@$items) {
    print $j;
}
```

### 导入回调函数

注册一个自定义的导入器。回调函数必须返回：

   * 成功：`($found_here, $content)`

   *  失败：`(undef, $error_text)`


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

注意：一旦设置了 import_callback，它将替换默认的导入器。如果你还需要文件系统导入功能，请在回调中自行实现。
### 原生函数回调（std.native）

```perl
$vm->native_callback(
    "add",
    sub { my ($a, $b) = @_; $a + $b },
    [qw(a b)],
);

print $vm->evaluate_snippet("n", 'std.native("add")(2, 3)');
```

原生函数接收原始的 Jsonnet 值（字符串/数字/布尔值/null）。返回值可以是标量、数组引用、哈希引用或 undef。
 ### 虚拟机配置选项

你可以通过构造函数或后续方法设置调优参数：

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

### 故障排除
### 加载模块时出现 undefined symbol: jsonnet_make

你的 Jsonnet.so 在构建时没有链接到 libjsonnet。

解决方法：安装 libjsonnet-dev 或使用正确的路径前缀重新构建：

```bash
JSONNET_PREFIX=/path/to/jsonnet perl Makefile.PL
make clean
make
make test
```

### 构建过程找不到 libjsonnet.h

安装开发包（libjsonnet-dev、jsonnet-devel）或指定 JSONNET_PREFIX。
设置 import_callback 后出现导入错误

### 设置了导入回调函数会替换默认的导入器。如果需要文件系统导入功能，请自行在回调函数中处理。

### 许可证

本库是免费软件；你可以按照与 Perl 本身相同的许可条款重新分发和/或修改它。

### 作者

Sergey Kovalev info@neolite.ru
