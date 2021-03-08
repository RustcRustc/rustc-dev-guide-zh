# 名称解析

<!-- toc -->

在上一个章节，我们看到了如何在展开所有宏的情况下构建 AST。这个过程需要用名称解析（name resolution）来解析导入和宏的名字。在本章中，我们将展示这是如何实现的。

事实上，我们在展开宏的过程中并不做完全的名称解析 -- 我们只解析导入和宏在这个过程中。这要求知道什么是需要展开。在这之后，在获得整个 AST 之后，我们将执行全名解析来解析 crate 中的所有名称。这发生在 [`rustc_resolve::late`][late] 中。与宏展开不同，在这个后期展开中，我们只需要尝试解析一个名称一次，因为没有新增的名字，如果失败了，那么将抛出一个编译错误。

名称解析可能很复杂。这里有几个不同的命名空间（例如，宏，值，类型，生命周期）和名称可能在不同（嵌套的）范围。此外，针对不同类型的名称解析，其解析失败的原因也可能会不同。例如，在一个模块的作用域内，模块中存在尚未展开的宏和未解析的 glob 导入会导致解析失败。另一方面，在函数内，在我们所在的 block 中，外部作用域和全局作用域中都没有该名称会导致解析失败。

[late]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_resolve/late/index.html

## 基础

在我们的程序中，我们可以通过给一个变量名，来引用 变量，类型，函数等等。这些名字并不总是唯一的。例如，下面是一个有效 Rust 程序：

```rust
type x = u32;
let x: x = 1;
let y: x = 2;
```

我们是如何知道 第三行 `x` 是一个类型 (u32) 还是 数值 (1)。这个冲突将在名称解析中被解析。在这个特殊栗子中，名称解析定义 类型名称（type names） 和 变量名称（variable names） 在独立的命名空间，所以他们可以共存。

Rust 中的名称解析分为两个阶段。在第一阶段，将运行宏展开，我们将构建一个模块的书结构和解析导入。宏展开和名字解析通过[`ResolverAstLowering`] 特性（trait）来通信。

输入的第二阶段的输入是语法树，它通过解析输入文件和展开宏。这个阶段将
从链接源文件中所有的名称到相关关联的地方（即名称被引用的地方）。它还会生成有用的错误信息，如输入错误建议，要导入的特性（trait）或 lints 关于未使用的项。（or lints about
unused items）

成功运行第二阶段（[`Resolver::resolve_crate`]) 将创建一个索引，剩余的编译部分可以使用它来查询当前的名称（通过  `hir::lowering::Resolver` 接口）

名称解析在 `rustc_resolve` crate 中，部分内容位于 `lib.rs` 中，其他模块中有一些帮助程序或 symbol-type logic 。

[`Resolver::resolve_crate`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_resolve/struct.Resolver.html#method.resolve_crate
[`ResolverAstLowering`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_ast_lowering/trait.ResolverAstLowering.html

## 命名空间

不同类型的符号存在于在不同的命名空间中。例如 类型的名称 不与 变量的名称 冲突。这通常不会发生，因为变量以小写字母开头，而类型以大写字母开头。但这仅仅是一种约定。以下 Rust 代码是合法的，并通过编译（带有 warnings）：

```rust
type x = u32;
let x: x = 1;
let y: x = 2; // See? x is still a type here.
```

为了应对这种情况，并使用这些名称的作用域规则少有不同，解析起将它们分开，并为他们创建不同的机构。

也就是说，当（code）代码谈到命名空间，它并不代表模块的结构层次，它是 类型 vs 值 vs 宏。

## 作用域和 ribs

名称只在源代码的特定区域可见。这形成了一个层次结构，但不一定是简单的-如果一个作用域是另一个作用域的一部分，这不意味在外部可见的名称也是在内部可见的，或指的是同一样内容。

为了处理这种情况，编译器引入一个 Ribs 概念。这是一种抽象作用域。每每次可见名称可能发生变化时，一个新的 rib 被推入栈中。可能发生这种情况的地方包括：
* 明显的地方 - 花括号包围块，函数边界，模块。
* 通过 let 绑定引入 - shodow 另一个同名变量。
* 宏展开边缘 - 因对宏的卫生（hygiene）

ribs 栈会由内到外的搜索名称。这有助于找到名称最近的意思（这个名称不会被其他任何东西覆盖）。向外过渡 rib 也可能会改则未使用名称的规则 - 如果这里又一个嵌套的函数（非闭包），内层作用域内不能访问参数和进行本地绑定外层作用域的内容，即使他们在常规作用域规则中应该可见。一个例子：


```rust
fn do_something<T: Default>(val: T) { // <- New rib in both types and values (1)
    // `val` is accessible, as is the helper function
    // `T` is accessible
    let helper = || { // New rib on `helper` (2) and another on the block (3)
        // `val` is accessible here
    }; // End of (3)
    // `val` is accessible, `helper` variable shadows `helper` function
    fn helper() { // <- New rib in both types and values (4)
        // `val` is not accessible here, (4) is not transparent for locals)
        // `T` is not accessible here
    } // End of (4)
    let val = T::default(); // New rib (5)
    // `val` is the variable, not the parameter here
} // End of (5), (2) and (1)
```

因为对于不同作用域的规则有所不同，每个作用域会有他自己独立的与命名空间并行构造的 rib 栈。此外，也有对于那些没有完整命名空间的 local lables 也有一个 rib 栈（例如 loops 或者 blocks 的名称）。

## 总体策略

为了执行整个 crate 的名称解析，自上而下的遍历语法树，并解析每个遇到的名称。这适用于大多数类型的名称，因为在使用名称时，已经在 Rib 层次结构中引入了该名称。

这里有一些例外，一些会有些棘手，因为它们甚至可以在遇到之前就可以使用 - 因此需要扫描每一个项去填满 Rib。

其他甚至更有问题的导入，需要递归的定点解析和宏，需要在处理剩下代码之前进行解析和展开。

因此，名称解析是在多个阶段执行的。

## Speculative crate loading

为了给出有用的错误，rustc 建议将未找到的路径导入作用域中。它是怎么做到的呢？他会检查每一个 crate 的每一个模块，并寻找可能的匹配项。这甚至包括还没有加载的 crate。

为尚未加载的导入的提供导入建议被称为_speculative crate loading_，因为不应报告任何遇到的错误：决定去加载这些导入的并非用户。执行此功能的函数是在 `rustc_resolve/src/diagnostics.rs` 中的`lookup_import_candidates`。

为了 speculative loads 和用户的加载，解析通过传递一个  `record_used` 参数，当 speculative loads 时候，值为 false。

## TODO:

这是第一遍学习代码的结果。绝对是不完整的，不够详细的。在某系地方也可能不准确。不过，它可能在将来能提供有用的帮助。

* 它究竟链接到什么？后续的编译阶段如何发布和使用该链接？
谁调用它以及如何实际使用它。
* 它是通过，然后仅使用结果，还是可以递增计算（例如，对于RLS）？
* 总体策略描述有点模糊。
* Rib这个名字来自哪里？
* 这东西有自己的测试，还是仅作为某些端到端测试的一部分进行测试？
