# `#[test]` 属性

<!-- toc -->

今天，Rust 程序员依赖于称为 `#[test]` 的内置属性。您需要做的只是将一个函数标记为测试（test），并包含一些 断言（asserts），如下所示：

```rust,ignore
#[test]
fn my_test() {
    assert!(2+2 == 4);
}
```

当程序使用 `rustc --test` 或 `cargo test` 命令进行编译的时候，它将生成可运行该程序及其他测试函数的可执行文件。这种测试方式允许所有测试于代码并存。你甚至可以将测试放入到私有模块中：

```rust,ignore
mod my_priv_mod {
    fn my_priv_func() -> bool {}

    #[test]
    fn test_priv_func() {
        assert!(my_priv_func());
    }
}
```

此外，可以很容易的测试私有项目，而不用担心如何将它们导出给任何类型的外部测试设备。这是 Rust 中 工效（ergonomics）测试的关键。然而从语法上讲，这是相当奇怪的。如果这些函数是不可见的（private）的，主函数如何调用他们呢？`rustc --test` 是怎么做到的？

编译器中的 [`rustc_ast` crate][rustc_ast] 为 `#[test]` 实现了语法转译。本质上这是一个 fancy 的宏，它通过三个步骤重写了 crate。

## Step 1: 重新导出（Re-Exporting）

如前所述，测试可以存在于私有模块内部，因此我们需要一种在不破坏现有代码的情况下将其暴露给主函数。因此 `rustc_ast` 将创建一个名为 `__test_reexports`  的本地模块，该模块递归地重复导出（Re-Exporting）测试。此扩展的代码示例转换为：

```rust,ignore
mod my_priv_mod {
    fn my_priv_func() -> bool {}

    pub fn test_priv_func() {
        assert!(my_priv_func());
    }

    pub mod __test_reexports {
        pub use super::test_priv_func;
    }
}
```

现在，可以通过 `my_priv_mod::__test_reexports::test_priv_func` 访问我们的测试。对于更深的模块结构，`__test_reexports` 讲重新导出包含测试模块，因此位于 `a::b::my_test` 将变成 `a::__test_reexports::b::__test_reexports::my_test`。尽管此过程看起来很安全，但是如果当前已存在 `__test_reexports` 模块会怎么样？答案：并不要紧。

为了解释，我们需要了解 AST 如何表示标识符（[how the AST represents
identifiers][Ident]）。每个函数，变量，模块的名称都不直接存储为 string，而是存储为不透明的 [Symbol][Symbol]，它本质是每个标识符的 ID 号。编译器保留一个独立的哈希表，使我们可以在必要时（例如在打印语法错误时）恢复人类可读的 Symbol 名称。当编译器生成 `__test_reexports` 模块是，它会为标识符生成一个新的符号，因此尽管编译器生成的`__test_reexports`  可能与您创建的包共享一个名称，但不会共享一个 Symbol 。此技术可以防止在代码生成过程中发生名称冲突，这是 Rust 宏卫生（hygiene）的基础

## Step 2: Harness Generation

现在我们可以从 crate 根目录访问我们的测试，我们需要对它们进行一些操作。 `rustc_ast` 生成如下模块：

```rust,ignore
#[main]
pub fn main() {
    extern crate test;
    test::test_main_static(&[&path::to::test1, /*...*/]);
}
```

其中 `path::to::test1` 是类型 `test::TestDescAndFn` 的常量。

尽管这种转换很简单，但它使我们对测试的实际运行方式有很多了解。将测试汇总到一个数组中，然后传递给名称为 `test_main_static` 的测试运行器。我们将返回到 `TestDescAndFn` 到底是什么，但是现在，关键点是有一个名为 [`test`][test] crate，它是 Rust Core 的一部分，他实现了测试所有运行时，`test` 接口是不稳定的，所以与它交互的唯一方式是通过 `#[test]` 宏。

## Step 3: Test Object Generation

如果您以前用 Rust 编写过测试，那么您可能熟悉一些测试函数上可用的一些可选属性。例如，如果我们预测测试会 panic ，可以用 `#[should_panic]` 来注释测试。看起来是如下的：

```rust,ignore
#[test]
#[should_panic]
fn foo() {
    panic!("intentional");
}
```

这意味着我们的测试不仅仅是简单的函数，它们也有配置信息。`test` 将这个配置数据编码到一个名为 [`TestDesc`][TestDesc] 的结构体中。对于 crate 中的每一个测试函数，`rustc_ast` 将解析其属性并生成 `TestDesc` 实例。然后它将 `TestDesc` 和 test 函数组合到可预测名称的 `TestDescAndFn`  结构体中，`test_main_static` 对其进行操作。对于给定的测试，生成 `TestDescAndFn` 实例如下：

```rust,ignore
self::test::TestDescAndFn{
  desc: self::test::TestDesc{
    name: self::test::StaticTestName("foo"),
    ignore: false,
    should_panic: self::test::ShouldPanic::Yes,
    allow_fail: false,
  },
  testfn: self::test::StaticTestFn(||
    self::test::assert_test_result(::crate::__test_reexports::foo())),
}
```

一旦我们构建了这些测试对象的数组，它们就会通过步骤2中生成的管理传递给测试运行器。

## 检查生成的代码

在 nightly rust 中，有一个不稳定的标签叫做 `unpretty` ，你可以使用它在宏展开后打印出模块的源代码：

```bash
$ rustc my_mod.rs -Z unpretty=hir
```

[test]: https://doc.rust-lang.org/test/index.html
[TestDesc]: https://doc.rust-lang.org/test/struct.TestDesc.html
[Symbol]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/symbol/struct.Symbol.html
[Ident]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/symbol/struct.Ident.html
[eRFC]: https://github.com/rust-lang/rfcs/blob/master/text/2318-custom-test-frameworks.md
[rustc_ast]: https://github.com/rust-lang/rust/tree/master/compiler/rustc_ast
