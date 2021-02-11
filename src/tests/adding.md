# 添加新测试

<!-- toc -->

**总体而言，我们希望每个修复rustc错误的PR都能够有一些相应的回归测试** 。这些测试在修复之前是错误的但是在PR之后应该是通过的。这些测试能有效的防止我们重复过去的错误。

为了添加新测试，通常要做的第一件事是创建一个文件，往往是Rust源文件。测试文件有特定的结构：


- 它们应该包含一些[解释测试内容的注释](#explanatory_comment);
- 接下来，它们应该有一个或多个[头部命令](#header_commands)，这些头部命令是能够让测试解释器知道如何解释特殊的注释，。
- 最后，它们应该有Rust源码。源码可能包含不同的[错误注释](#error_annotation)，这些错误指示预期的编译错误或警告。


根据测试套件的不同，可能还其它一些需要注意的细节：

- 对于[`ui`测试套件](#ui)，您需要生成参考输出文件。

## 我应该添加哪种测试
知道该使用哪种测试是十分困难的。这里有一些粗略的启发：
- 一些测试特殊的需求
  - 需要运行gdb或者lldb?使用`debuginfo`测试套件
  - 需要检查LLVM IR或者MIR IR?使用`codegen`或者`mir-opt`测试套件
  - 需要运行rustdoc?首选`rustdoc`或者`rustdoc-ui`测试，有时，您也需要`rustc-js`
  - 需要以某种方式检查生成的二进制文件？请使用`use-make`
- 库测试应该放在`library/${crate}/tests`中(其中的`${crate}`通常是`core`，`alloc`，`std`)。库测试应该包括：
  - API是否正常运行，包括接受各种类型或者具有某些运行时行为的测试
  - 是否存在任何与测试不相关的编译器警告的测试
  - 当使用一个API时给出的错误与它真正的错误无关时的测试。这些测试在代码块中应该有一个[错误编号](`EOXXX`)，用于确保它是正确的错误信息。
- 对于剩余的大多数，首选[`ui`（或者`ui-fulldeps`）测试](#ui)
  - [`ui`](#ui)测试同时包含`run-pass`，`compile-fail`，和`parse=fail`测试
  - 在警告或错误的情况下，`ui`测试会捕获全部输出，这使得评审变得更容易，同时也有助于防止输出中的"隐藏"回归

[错误编号]: https://doc.rust-lang.org/rustdoc/unstable-features.html#error-numbers-for-compile-fail-doctests



## 命名您的测试
传统上，对于测试名字，我们并没有太多的结构。并且，在很长一段时间中，rustc测试运行程序不支持子目录(现在可以了)，所以测试套件譬如[`src/test/ui`]中有很多文件。这并不是一个理想的设置。

[`src/test/ui`]: https://github.com/rust-lang/rust/tree/master/src/test/ui/

对于回归测试-基本上，一些随机的来自于互联网上的代码片段-我们经常用问题（issue）加上简短的说明来命名这些测试。理想情况下，应该将测试添加到目录中，这样能够帮助我们确定哪段代码正在被测试(例如`src/test/ui/borrowck/issue-54597-reject-move-out-of-borrow-via-pat.rs`)如果您已经尝试过但是找不到更相关的地方，这个测试可以被添加到`src/test/ui/issues/`。同样，**请在某处添加上问题编号(issue numbeer)**。但是，请尽量避免把您的测试放在那，因为这样会使目录中的测试过多，造成语义组织不佳。
当在编写一个新特性时候时，**请创建一个子目录用于存放您的测试**。例如，如果您要实现RFC1234("Widgets")，那么最好将测试放在类似`src/test/ui/rfc1234-widgets`的目录。

在其它情况下，可能已经存在合适的目录。(被正确使用的目录结构实际上是一个活跃的讨论区)


<a name="explanatory_comment"></a>


## 注释说明测试内容
当您在创建测试文件时，请在文件的开头添加总结测试要点的注释。注释应该突出显示哪一部分测试更为重要，以及这个测试正在解决什么问题。引用问题编号通常非常有帮助。

该注释不必过于广泛，类似"Regression test for #18060： match arms were matching in the wrong order."的注释就已经足够了。

以后当您的测试崩溃时，这些注释对其他人非常有用，因为它们通常已经突出显示了问题所在。当出于某些原因测试需要重构时，这些注释也同样有用，因为它能让其他人知道哪一部分的测试是重要的(通常，必须重写测试，因为它不再测试它曾经被用于测试的内容，所以知道测试曾经的含义是十分有用的)


<a name="header_commands"></a>

## 头部指令： 配置rustc
头部指令是一种特殊的注释，它让测试运行程序知道如何解释。在测试中，它们必须出现在Rust源代码之前。它们通常被放在段注释后，这些注释用来解释本测试的关键点。例如，这个测试使用了`//compile-flags`指令，该指令在编译测试时给rustc指定了自定义的标志。

```rust，ignore
// Test the behavior of `0 - 1` when overflow checks are disabled.

// compile-flags： -C overflow-checks=off

fn main() {
    let x = 0 - 1;
    ...
}
```

### 忽略测试
下列是用于在某些情况下忽略测试，这意味着测试不会被编译或者运行
* `ignore-X` 其中X是会忽略相应测试的目标细节或阶段(见下文)
* `only-X`和`ignore-X`相似，不过*只*会在那个目标或阶段下运行测试
* `ignore-pretty`将不会编译打印美化的测试(这样做是为了测试打印美化器，但它并不总是有效)
* `ignore-test`总是忽略测试
* `ignore-lldb`和`ignore-gdb`会跳过调试器的调试信息
* `ignore-gdb-version`当使用某些gdb版本时，可以使用它来忽略测试

一些关于`ignore-X`中`X`的例子：

* 架构： `aarch64`， `arm`， `asmjs`， `mips`， `wasm32`， `x86_64`，`x86`， ...
* OS： `android`， `emscripten`， `freebsd`， `ios`， `linux`， `macos`， `windows`， ...
* 环境(即目标三元组("target-triple")的第四个词)：`gnu`， `msvc`， `musl`.
* 指针宽度： `32bit`， `64bit`.
* 阶段： `stage0`， `stage1`， `stage2`.
* 当交叉编译时： `compare-mode-nll`
* 当使用远程测试时： `remote`
* 当启用调试断言时： `debug`
* 当测试特定的调试器时：  `cdb`， `gdb`， `lldb`
* 特定比较模式时： `compare-mode-nll`， `compare-mode-polonius`

### 其它头部指令
这是一份关于其它头部指令的列表。该表并不详尽，您通常可以通过浏览来自compiletest源的[`header.rs`]中的`TestProps`找到头部命令。
* `run-rustfix` ，该命令是用于UI测试，表示测试产生结构化建议。测试编写者应该创建一个`.fixed`文件，其中包含应用了建议的源码。当运行测试时，compiletest 首先检查正确的lint/warning是否产生。然后，它应用建议并且与`.fixed`(两者必须匹配)比较。最后，fixed源码被编译，并且此次编译必须成功。`.fixed`文件可以通过`bless`选项自动生成，在[本节](bless)进行了介绍
* `min-gdb-version`指定了本测试所需的最低gdb版本。
* `min-lldb-version`指定了本测试所需的最低lldb版本。
* `no-system-llvm`，如果使用系统llvm，该命令会导致测试被忽略
* `min-system-llvm-version`指定最低的系统llvm版本;如果系统llvm被使用并且未达到所需的最低版本，那么本测试会被忽略。当一个llvm功能被反向移植到rust-llvm时，这条命令十分有效。
* `ignore-llvm-version`，当特定的LLVM版本被使用时，该命令可以用于跳过测试。它需要一个或两个参数。第一个参数是第一个被忽略的版本，如果没有第二个参数，那么后续版本都会被忽略;否则，第二个参数就是被忽略的最后一个版本。
* `build-pass`适用于UI测试，该命令表示测试应该成功编译和链接，与此相反的是默认情况下测试应该会出错。
* `compile-flags`将额外的命令行参数传递给编译器，例如`compile-flags -g`会强制启用debuginfo
* `edition`控制测试应该使用的版本(默认为2014)。用法示例`// edition：2018`。
* `should-fail`表示测试应该失败;被用于元测试("meta testing")，该测试是我们测试compiletest程序本身是否能够在适当的情况下产生错误。在格式美化测试中该头部命令会被忽略。
* `gate-test-X`中的`X`是一个特性，该命令把测试标记为对于特性X的"门控测试"("gate test")。此类测试应该确保当尝试使用门控功能而没有正确的`#![feature(X)]`标签时，编译器会发生错误。每个不稳定的语言特性都需要一个门测试。
* `needs-profiler-support`－需要profiler运行时，例如，rustc的`config.toml`中的`profiler=true`。
* `needs-sanitizer-support`－需要sanitizer运行时，例如，rustc的`config.toml`中的`sanitizers = true`。
* `needs-sanitizer-{address，leak，memory，thread}`-表示该测试需要一个目标分别支持AddressSanitizer， LeakSanitizer，MemorySanitizer 或者 ThreadSanitizer。
* `error-pattern`像`ERROR`注释一样检查诊断，而不指定错误行。当错误没有给出任何范围时，这个命令十分有用。
  
[`header.rs`]： https：//github.com/rust-lang/rust/tree/master/src/tools/compiletest/src/header.rs
[bless]： ./running.md#editing-and-updating-the-reference-files

<a name="error_annotations"></a>

### 错误注释示例
这是一些UI测试源上不同的错误注释示例。

#### 置于错误行上
使用`//~ERROR`语法
```rust，ignore
fn main() {
    let x = (1， 2， 3);
    match x {
        (_a， _x @ ..) => {} //~ ERROR `_x @` is not allowed in a tuple
        _ => {}
    }
}
```
#### 置于错误行下
使用`//~^`语法，字符串中插入号(`^`)的数量表示上方的行数。在下面这个例子中，错误行在错误注释行的上四行位置，因此注释中有四个插入号。

```rust，ignore
fn main() {
    let x = (1， 2， 3);
    match x {
        (_a， _x @ ..) => {}  // <- the error is on this line
        _ => {}
    }
}
//~^^^^ ERROR `_x @` is not allowed in a tuple
```

#### 使用与上面错误注释行相同的错误行
使用`//~|`语法定义与上面错误注释行相同的错误行
```rust，ignore
struct Binder(i32， i32， i32);

fn main() {
    let x = Binder(1， 2， 3);
    match x {
        Binder(_a， _x @ ..) => {}  // <- the error is on this line
        _ => {}
    }
}
//~^^^^ ERROR `_x @` is not allowed in a tuple struct
//~| ERROR this pattern has 1 field， but the corresponding tuple struct has 3 fields [E0023]
```

#### 无法指定错误行时
让我们思考一下这个测试
```rust，ignore
fn main() {
    let a: *const [_] = &[1， 2， 3];
    unsafe {
        let _b = (*a)[3];
    }
}
```
我们想要确保它显示"超出索引范围"("index out of bounds")，但是我们不能使用`ERROR`注释，因为这个错误没有范围。那么是时候使用`error-pattern`：
```rust，ignore
// error-pattern: index out of bounds
fn main() {
    let a: *const [_] = &[1， 2， 3];
    unsafe {
        let _b = (*a)[3];
    }
}
```
但是对于严格测试，请尽量使用`ERROR`注释。
#### 错误等级
您可以拥有的错误等级是：
1. `ERROR`
2. `WARNING`
3. `NOTE`
4. `HELP` and `SUGGESTION`*
 
\* **注意**： `SUGGESTION`必须紧随`HELP`之后


## 版本
某些测试类支持"版本"("revision")(截至本文撰写之时，这包括编译失败，运行失败和增量测试，虽然增量测试有些差异)。版本允许将一个测试文件用于多个测试。这通过在文件顶部添加一个特殊的头部来完成：
```rust
// revisions: foo bar baz
```
这会导致测试被编译(和测试)三次，一次使用`--cfg foo`，一次使用`--cfg bar`，一次使用`--cfg baz`。因此您可以在测试中使用`#[cfg(foo)]`等来调整每个结果。

您也可以将头部和期望的错误信息来自定义为特定的修订。为此，您需要在`//`注释后添加`[foo]`(或者`bar`，`baz`等)，如下所示
```rust
// A flag to pass in only for cfg `foo`:
//[foo]compile-flags: -Z verbose

#[cfg(foo)]
fn test_foo() {
    let x: usize = 32_u32; //[foo]~ ERROR mismatched types
}
```
请注意，并非所有的头部在被自定义为版本时都有意义。例如，`ignore-test`头部(和所有的`ignore`头部)目前只适用于整个测试而不适用于特定的版本。当被自定义为版本时，唯一真正起作用的头部只有错误模式(error patterns)和编译器标志(compiler flags)。

<a name="ui"></a>

## UI测试指南
UI测试旨在抓取编译器完整的输出，这样我们可以测试可以测试表现的各个方面。它们通过编译文件(例如[`ui/hello_world/main.rs`](hw-main))，捕获输出，然后进行一些标准化(参见下文)。然后将标准化的结果与名为`ui/hello_world/main.stderr`和`ui/hello_world/main.stdout`的参考文件进行比较。如果其中任意一文件不存在，那么输出必须为空(实际上是[该特定测试][hw]的实例)。如果测试运行失败，我们将打印出当前输出，但是输出也被保存在`build/<target-triple>/test/ui/hello_world/main.stdout`(这个路径会被当作测试失败信息的一部分而打印出来)，这样你就可以通过运行`diff`等命令来比较。

[hw-main]: https://github.com/rust-lang/rust/blob/master/src/test/ui/hello_world/main.rs
[hw]: https://github.com/rust-lang/rust/blob/master/src/test/ui/hello_world/

现在我们有大量的UI测试并且一些目录中的条目过多。这是一个问题，因为它对editor/IDE是不友好的并且GitHub UI也不会显示超过1000个的目录。为了解决这个问题并组织语义结构，我们有一个整洁检查(tidy check)，用以确保条目数小于1000，我们为每个目录设置了不同的上限。所以，请避免将新测试放在这，并且尝试去寻找更相关的位置。例如，你的测试和闭包相关，你应该把它放在`src/test/ui/closures`。如果你不确定哪里最佳的位置.添加到`src/test/ui/issues/`也是可以的。当到达上限时，你可以通过调整[这][ui test tidy]来增加上限。

[ui test tidy]: https://github.com/rust-lang/rust/blob/master/src/tools/tidy/src/ui_tests.rs

### 不会导致编译错误的测试
默认情况下，预期UI测试**不会编译**(在这种情况下，应该至少包含一个`//~ERROR`注释)。但是，您也可以在期望编译成功的地方进行UI测试，甚至还可以运行生成的程序。只需要添加任意下列[头部命令](#header_commands)：
* `// check-pass`-编译应该成功，但是跳过代码生成(它的代价是昂贵的，在大部分情况下不应该失败)
* `// build-pass`-编译和链接应该成功但是不运行生成的二进制文件
* `// run-pass` -编译应该成功并且我们应该运行生成的二进制文件


### 标准化
编译器的输出被标准化以消除不同平台输出的差异，主要和文件名相关。

下面的字符串会被替换成相应的值：
* `$DIR`：被定义为测试的目录
  * 例如：`/path/to/rust/src/test/ui/error-codes`
* `$SRC_DIR`：源码根目录
  * 例如：`/path/to/rust/src`
* `$TEST_BUILD_DIR`：测试输出所在的基本目录
  * 例如：`/path/to/rust/build/x86_64-unknown-linux-gnu/test/ui`

此外，会进行以下更改：
* `$SRC_DIR`中的行号和列号被`LL:CC`代替。例如，`/path/to/rust/library/core/src/clone.rs:122:8` 被替代为`$SRC_DIR/core/src/clone.rs:LL:COL`。
  
  注意：指向测试的`-->`行的行号和列号是*未*规范的，并保持原样。这确保编译器继续指向正确的位置并且保持stderr文件的可读性。理想情况下，所有行和列的信息都被保留，但是源的小变化会造成巨大的差异，更为频繁的合并冲突和测试错误。另请参见下面的`-Z ui-testing`，它适用于附加的行号规范化。
* `\t`被替换为实际的制表符
* 错误行注释例如`// ~Error some messgage`被移除
* 反斜杠（`\`）在路径内转换为正斜杠（`/`）（使用启发式）。这有助于规范Windows样式路径的差异。
* CRLF换行符被转换为LF。

此外，编译器使用`-Z ui-testing`标志运行，这导致编译器本身对诊断输出进行一些修改以使其更适合于UI测试。例如，它将匿名化输出中的行好(每行源代码前的行号会被替换为`LL`)。在极少数情况下，可以使用头部命令`// compile-flags: -Z ui-testing=no`来禁用此模式。


有时，这些内置的规范化并不够。在这种情况下，你可以提供通过头部命令自定义的规范规则，例如
```rust
// normalize-stdout-test: "foo" -> "bar"
// normalize-stderr-32bit: "fn\(\) \(32 bits\)" -> "fn\(\) \($$PTR bits\)"
// normalize-stderr-64bit: "fn\(\) \(64 bits\)" -> "fn\(\) \($$PTR bits\)"
```
这告诉测试，在32位平台上，只要编译器将`fn() (32 bits)`写入stderr时，都应该被标准化为读取`fn() ($PTR bits)`。64位同样如此。替换是由正则表达式完成，它使用由`regex`crate提供的默认正则风格。

相应的参考文件将使用规范化的输出来测试32位和64位平台：
```text
...
   |
   = note: source type: fn() ($PTR bits)
   = note: target type: u16 (16 bits)
...
```
请参阅[`ui/transmute/main.rs`][mrs]和 [`main.stderr`][]了解具体的用法示例。
[mrs]: https://github.com/rust-lang/rust/blob/master/src/test/ui/transmute/main.rs
[`main.stderr`]: https://github.com/rust-lang/rust/blob/master/src/test/ui/transmute/main.stderr

除了`normalize-stderr-32bit`和`-64bit`，在这里也可以使用 [`ignore-X`](#ignoring-tests) 支持的任何目标信息或阶段(例如`normalize-stderr-windows` 或简单地使用`normalize-stderr-test` 进行无条件替代)