# Rustc 中的内存管理

Rustc 在内存管理方面相当谨慎。编译器在整个编译过程中需要分配 _大量_ 的数据结构，如果我们不够谨慎，这将会耗费大量时间和空间。

使用 arenas 和 interning 是编译器管理内存的主要方式之一。

## Arenas 和 Interning

在编译期间我们需要创建大量的数据结构。出于对性能的考虑，我们通常从全局内存池中分配这些数据结构; 每个数据结构都从一个长期 *arena* 中分配一次。这就是所谓的 _arena allocation_。这个系统减少了内存的分配/释放。它还允许简单地比较类型是否相等: 对每个 interned 类型 `X` 实现了 [`X` 的 `PartialEq`][peqimpl]，因此我们只比较指针就可以判断是否相等。 [`CtxtInterners`] 类型包含一系列 interned 类型和 arena 本身的映射。

[peqimpl]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/struct.TyS.html#implementations
[`CtxtInterners`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/struct.CtxtInterners.html#structfield.arena

### 例: `ty::TyS`

以 [`ty::TyS`] 为例，它表示编译器中的类型(在[这里](./ty.md)了解更多)。每当我们想要构造一个类型时，编译器都不会傻乎乎地直接从缓冲区分配。相反，编译器检查是否构造过该类型。如果构造过的话，只需要获取一个指向之前构造个的类型的指针，否则，就会创建一个新的指针。对于这个设计，如果想知道两种类型是否相同，只需要比较两个指针。`TyS` 是精心设计的，所以你永远无法在栈上构造 `TyS`。你只能从这个 arena 分配并 intern `TyS`，所以它是独一无二的。

在编译开始时，我们会创建一个缓冲区，每当需要分配一个类型时，就从缓冲区中使用这些类型。如果用完了，就会再创建一个。缓冲区的生命周期为 `'tcx` 。我们的类型绑定到该生命周期，因此当编译完成时，与该缓冲区相关的所有内存都被释放，`'tcx` 的引用将无效。

除了类型之外，还可以分配很多其它的 arena-allocated 数据结构，这些数据结构可以在该模块中找到。以下是一些例子:

- [`Substs`][subst]，分配给 `mk_substs` – 这会 intern 一个切片类型，通常用于指定要替换泛型的值(例如 `HashMap<i32, u32>` 将被表示为切片 `&'tcx [tcx.types.i32, tcx.types.u32]`)。
- [`TraitRef`]，通常通过值传递 – 一个 **trait 引用** 包含一个引用的 trait 及其各种类型参数(包括 `Self`)，如 `i32: Display` (这里 def-id 会引用 `Display` trait，并且子类型包含 `i32`)。 注意 `def-id` 的定义及讨论在 `AdtDef and DefId` 部分。
- [`Predicate`] 定义 trait 系统要保证的东西 (见 `traits` 模块)。

[subst]: ./generic_arguments.html#subst
[`TraitRef`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/struct.TraitRef.html
[`Predicate`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/struct.Predicate.html

[`ty::TyS`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/struct.TyS.html

## tcx 和怎样使用生命周期

`tcx`(“typing context”)是编译器中的中枢数据结构。它是用于执行各种查询的上下文。 `TyCtxt` 结构体定义了对这个共享上下文的引用:

```rust,ignore
tcx: TyCtxt<'tcx>
//          ----
//          |
//          arena lifetime
```

如你所见，`TyCtxt` 类型使用生命周期参数。当你看到类似 `'tcx` 生命周期的引用时，你就知道它指的是 arena-allocated 的数据(或者说，数据的生命周期至少与 arenas 一样长)。

### 关于生命周期

Rust 编译器是一个相当大的程序，包含大量的大数据结构(如 AST、 HIR 和类型系统)，因此非常依赖于 arenas 和引用(references)来减少不必要的内存使用。这体现在使用插入编译器(例如 [driver](./rustc-driver.md))的方式上，倾向于使用“push”风格(回调)的 API ，而不是 Rust-ic 风格的“pull”风格(考虑 `Iterator` trait)。

编译器通过大量使用线程本地存储和 interning 来减少复制，同时也避免了无处不在的生命期而导致的用户不友好。[`rustc_middle::ty::tls`][tls] 模块用于访问这些线程局部变量，尽管你很少需要接触。

[tls]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/tls/index.html