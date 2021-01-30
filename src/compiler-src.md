# 编译器源代码概览

<!-- toc -->

> **注意**：代码仓库的结构正在经历许多转变。特别是，我们希望最终顶层目录下具有编译器、构建系统、标准库等的单独目录，而不是一个庞大的 `src/` 目录。 自2021年 1月起，标准库已移至 `library/`，构成 `rustc` 编译器本身的 crate 已移至 `compiler/`。

现在，我们已经[大体了解了编译器的工作](./overview.md)，让我们看一下 rust-lang/rust 仓库内容的结构。 

## Workspace 结构

`rust-lang/rust` 存储库由一个大型cargo workspace组成，该 Workspace 包含编译器，标准库（`core`、 `alloc`、 `std`、 `proc_macro`等）和 `rustdoc`，以及构建系统以及用于构建完整 Rust 发行版的一些工具和子模块。 在撰写本文时，此结构正在逐步进行一些转换，以使其变得不再是一个巨大的代码仓库且更易于理解，尤其是对于新手。 该存储库由三个主要目录组成： 

- `compiler/` 包含了 `rustc` 的源代码。它包含了组成编译器的一系列crate。
- `library/` 包含标准库 （`core`、 `alloc`、 `std`、
  `proc_macro`、 `test`）以及 Rust 运行时（`backtrace`、 `rtstartup`、
  `lang_start`）
- `src/` 包含 `rustdoc`、`clippy`、`cargo`、 构建系统、语言文档等等。

## 标准库

标准库 crate 都在 `library/`中。它们的名称都非常直观，如 `std`、`core`、`alloc`等。还有 `proc_macro`，`test` 和其他运行时库。这些代码和其他 Rust crate 非常相似，区别在于它们必须以特殊的方式构建，因为其中可以使用不稳定的功能。

## 编译器

>建议先阅读[概述章节](./overview.md)，它概述了编译器的工作方式。 
>
>本节中提到的 crate 组成了整个编译器，它们位于 `compiler/` 中。 

`compiler/` 下的 crate 们的名称均以`rustc_ *`开头。这里有大约 50 个或大或小，相互依赖的 crate。 还有一个 `rustc` crate，它是实际的二进制文件入口点（即 `main` 函数）所在之处； 除了调用`rustc_driver`crate之外，`rustc` crate实际上并不做任何事情，`rustc_driver` crate 会驱动其他 crate 中的各个部分来进行编译。

这些 crate 之间的依赖关系很复杂，但大体来说：

-  `rustc` （二进制文件入口点）调用 [`rustc_driver::main`][main]
  - [`rustc_driver`] 依赖许多其他 crate，其中最主要的是 [`rustc_interface`]。
    - [`rustc_interface`] 依赖于大多数其他编译器 crate。它是用于驱动整个编译的相当通用的接口。
      - 大部分其他 `rustc_*` crates 依赖于 [`rustc_middle`]，[`rustc_middle`] 中定义了编译器中的许多核心数据结构
        
        - [`rustc_middle`] 和编译器中大多数其他部分都依赖一些代表了编译中更早的阶段的 crate（例如 parser），基础数据结构（如[`Span`]），或者错误报告相关的内容：[`rustc_data_structures`]，[`rustc_span`]，[`rustc_errors`]，等等

[main]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_driver/fn.main.html
[`rustc_driver`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_driver/index.html
[`rustc_interface`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_interface/index.html
[`rustc_middle`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/index.html
[`rustc_data_structures`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_data_structures/index.html
[`rustc_span`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/index.html
[`Span`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/struct.Span.html
[`rustc_errors`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_errors/index.html

您可以通过读取各个 crate 的 `Cargo.toml` 来查看确切的依赖关系，就像普通的Rust crate一样。

最后一件事：[`src/llvm-project`] 是指向我们自己的 LLVM fork的子模块。 在bootstrap过程中，将会构建LLVM， [`compiler/rustc_llvm`] 是LLVM（用C++编写）的 Rust 包装，以便编译器可以与其交互。 本书的大部分内容是关于 Rust 编译器的，因此在这里我们将不对这些 crate 做任何进一步的解释。 

[`src/llvm-project`]: https://github.com/rust-lang/rust/tree/master/src/
[`compiler/rustc_llvm`]: https://github.com/rust-lang/rust/tree/master/compiler/rustc_llvm

## Big Picture

这种由多个 crate 互相依赖的代码结构受两个主要因素的强烈影响： 

1. 组织。编译器是一个 _巨大的_ 代码库；将其放在一整个大 crate 中是不可能的。依赖关系结构部分反映了编译器的代码结构。
2. 编译时间。通过将编译器分成多个 crate，我们可以更好地利用 cargo 进行增量/并行编译。特别是，我们尝试使板条箱之间的依赖关系尽可能少，这样，如果您更改一个 crate，我们就不必重新构建大量的 crate。

在依赖关系树的最底部是整个编译器使用的少数 crate（例如 [`rustc_span`]）。编译过程中的非常早期的部分（例如，parsing 和 AST）仅取决于这些。

构建AST之后不久，编译器的 [查询系统][query] 就建立好了。查询系统是使用函数指针以巧妙的方式设置的。这使我们可以打破 crate 之间的依赖关系，从而可以并行地进行更多编译。 但是，由于查询系统是在 [`rustc_middle`] 中定义的，编译器的几乎所有后续部分都依赖于此 crate。这是一个非常大的 crate，导致其编译时间极长。我们已经做出了一些努力来将内容从其中移出，但效果有限。另一个不幸的副作用是，有时相关功能分散在不同的 crate 中。例如，linting 功能分散在板条箱的较早部分 [`rustc_lint`]，[`rustc_middle`] 和其他地方。 

[`rustc_lint`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_lint/index.html

一般而言，在理想世界中，应当使用更少的，更内聚的板条箱，使用增量和并行编译确保编译时间保持合理。 但是，我们的增量和并行编译暂时还没有那么好用，所以目前为止我们的解决方案只能是东西分进单独的 crate。

在依赖树的顶部是 [`rustc_interface`] 和 [`rustc_driver`]板条箱。

 [`rustc_interface`] 是一个不稳定的查询系统的包装，用于帮助推动编译的各个阶段。 

其他编译器中的的消费者（例如 `rustdoc` 或者甚至是 rust-analyzer）可以以不同的方式使用此接口。 

[`rustc_driver`] crate 首先解析命令行参数，然后使[`rustc_interface`]驱动编译完成。

[query]: ./query.md

[orgch]: ./overview.md

## rustdoc

`rustdoc` 的大部分位于 [`librustdoc`] 中。 但是，`rustdoc`二进制文件本身 [`src/tools/rustdoc`]，除了调用 [`rustdoc::main`]外，它什么都不做。 在 [`src/tools/ rustdoc-js`] 和 [`src/tools/rustdoc-themes`] 中，还有 rustdocs 的 javascript 和 CSS。 您可以在[本章][rustdocch]中阅读有关 rustdoc 的更多信息。 

[`librustdoc`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustdoc/index.html
[`rustdoc::main`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustdoc/fn.main.html
[`src/tools/rustdoc`]:  https://github.com/rust-lang/rust/tree/master/src/tools/rustdoc
[`src/tools/rustdoc-js`]: https://github.com/rust-lang/rust/tree/master/src/tools/rustdoc-js
[`src/tools/rustdoc-themes`]: https://github.com/rust-lang/rust/tree/master/src/tools/rustdoc-themes

[rustdocch]: ./rustdoc.md

## 测试

以上所有内容的测试套件都在 [`src/test/`] 中。 您可以在[本章][testsch]中了解有关测试套件的更多信息。 测试工具本身在 [`src/tools/compiletest`] 中。 

[testsch]: ./tests/intro.md

[`src/test/`]: https://github.com/rust-lang/rust/tree/master/src/test
[`src/tools/compiletest`]: https://github.com/rust-lang/rust/tree/master/src/tools/compiletest

## 构建系统

代码仓库中有许多工具，可用于构建编译器，标准库，rustdoc，以及进行测试，构建完整的 Rust 发行版等。 主要工具之一是 [`src/bootstrap`]。 您可以[在这一章][bootstch]中了解有关 bootstrap的更多信息。 构建过程重还可能使用 `src/tools/`中的其他工具，例如 [tidy] 或 [compiletest]。 

[`src/bootstrap`]: https://github.com/rust-lang/rust/tree/master/src/bootstrap
[`tidy`]: https://github.com/rust-lang/rust/tree/master/src/tools/tidy
[`compiletest`]: https://github.com/rust-lang/rust/tree/master/src/tools/compiletest

[bootstch]: ./building/bootstrapping.md

## 其他

在 `rust-lang/rust` 仓库中还有很多其他与构建完整 Rust 发行版有关的东西。 大多数时候，您无需关心它们。 这些包括：

- [`src/ci`]：CI配置。 这里的代码实际上相当多，因为我们在许多平台上运行了许多测试。 
- [`src/doc`]：各种文档，包括指向几本书的submodule。 
- [`src/etc`]：其他实用程序。
- [`src/tools/rustc-workspace-hack`]，以及其他：各种变通方法以使 cargo 在bootstrapping 过程中运行。 
- 以及更多……