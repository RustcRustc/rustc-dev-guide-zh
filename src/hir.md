# HIR

<!-- toc -->

HIR ——“高级中间表示” ——是大多数 rustc 组件中使用的主要IR。
它是抽象语法树（AST）的对编译器更为友好的表示形式，该结构在语法分析，宏展开和名称解析之后生成（有关如何创建HIR，请参见[Lowering](./lowering.html)）。
HIR 的许多部分都非常类似于普通 Rust 的语法，但是 Rust 中的的某些表达式已被“脱糖”。
例如，`for` 循环将转换为了 `loop`，因此在HIR中不会出现 `for` 。 这使HIR比普通AST更易于分析。

本章介绍了HIR的主要概念。

您可以通过给 rustc 传递 `-Zunpretty=hir-tree` 标志来查看代码的 HIR 表示形式：

```bash
cargo rustc -- -Zunpretty=hir-tree
```

### Out-of-band 存储和`Crate`类型

HIR中的顶层数据结构是 [`Crate`]，它存储当前正在编译的 crate 的内容（我们从来就只为当前 crate 构造 HIR）。
在 AST 中，crate 数据结构基本上只包含根模块，而 HIR `Crate` 结构则包含许多map 和其他用于组织 crate 内容以便于访问的数据。

[`Crate`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_hir/struct.Crate.html

例如，HIR 中单个项目（例如模块、函数、trait、impl等）的内容不能在其父级中直接访问。
因此，例如，如果有一个包含函数 `bar()` 的模块 `foo`：

```rust
mod foo {
    fn bar() { }
}
```

那么在模块 `foo` 的HIR中表示（[`Mod`] 结构）中将只有`bar()`的**`ItemId`** `I`。
要获取函数 `bar()` 的详细信息，我们将在 `items` 映射中查找 `I`。

[`Mod`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_hir/struct.Mod.html

这种表示形式的一个好处是，可以通过遍历这些映射中的键值对来遍历 crate 中的所有项目（而无需遍历整个HIR）。
对于 trait 项和 impl 项以及“实体”（如下所述）也有类似的map。

使用这种表示形式的另一个原因是为了更好地与增量编译集成。
这样，如果您访问 [`&rustc_hir::Item`]（例如mod `foo`），不会同时立即去访问函数`bar()`的内容。
相反，您只能访问 `bar()` 的**id**，必须将 id 传入某些函数来查找 `bar` 的内容。 这使编译器有机会观察到您访问了`bar()`的数据，然后记录依赖。

[`&rustc_hir::Item`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_hir/struct.Item.html

<a name="hir-id"></a>

### HIR 中的标识符

有许多不同的标识符可以引用HIR中的其他节点或定义：
简单来说有：

- [`DefId`] 表示对任何其他 crate 中的一个*定义*的引用。
- [`LocalDefId`] 表示当前正在编译的 crate 中的一个*定义*的引用。
- [`HirId`] 表示对 HIR 中任何节点的引用。

更多详细信息，请查看[有关标识符的章节][ids]。 

[`DefId`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_hir/def_id/struct.DefId.html
[`LocalDefId`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_hir/def_id/struct.LocalDefId.html
[`HirId`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_hir/hir_id/struct.HirId.html
[ids]: ./identifiers.md#in-the-hir

### HIR Map

在大多数情况下，当您使用HIR时，您将通过 **HIR Map** 进行操作，该map可通过[`tcx.hir()`] 在tcx中访问（它在[`hir::map`]模块中定义）。
[HIR map] 包含[多个方法]，用于在各种 ID 之间进行转换并查找与 HIR 节点关联的数据。

[`tcx.hir()`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/struct.TyCtxt.html#method.hir
[`hir::map`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/hir/map/index.html
[HIR map]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/hir/map/struct.Map.html
[多个方法]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/hir/map/struct.Map.html#methods

例如，如果您有一个 [`DefId`]，并且想将其转换为 [`NodeId`]，则可以使用 [`tcx.hir().as_local_node_id(def_id)`][as_local_node_id]。
这将返回一个 `Option<NodeId>` —— 如果 def-id 引用了当前 crate 之外的内容（因为这种内容没有HIR节点），则将为`None`；
否则这个函数将返回 `Some(n)`，其中 `n` 是定义对应的节点ID。

[`NodeId`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_ast/node_id/struct.NodeId.html
[as_local_node_id]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/hir/map/struct.Map.html#method.as_local_node_id

同样，您可以使用[`tcx.hir().find(n)`][find]在节点上查找[`NodeId`]。
这将返回一个`Option<Node<'tcx>>`，其中[`Node`]是在map中定义的枚举。

通过对此枚举进行 match ，您可以找出 node-id 所指的节点类型，并获得指向数据本身的指针。
一般来说，您已经事先知道了节点 `n` 是哪种类型——例如，如果您已经知道了 `n` 肯定是某个 HIR 表达式，
则可以执行[`tcx.hir().expect_expr(n)`][expect_expr]，它将试图提取并返回[`&hir::Expr`][Expr]，此时如果`n`实际上不是一个表达式，那么会程序会 panic。

[find]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/hir/map/struct.Map.html#method.find
[`Node`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_hir/enum.Node.html
[expect_expr]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/hir/map/struct.Map.html#method.expect_expr
[Expr]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_hir/struct.Expr.html

最后，您可以通过 [`tcx.hir().get_parent_node(n)`][get_parent_node] 之类的调用，使用HIR map来查找节点的父节点。

[get_parent_node]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/hir/map/struct.Map.html#method.get_parent_node

### HIR Bodies

[`rustc_hir::Body`] 代表某种可以执行的代码，例如函数/闭包的函数体或常量的定义。
body 与一个**所有者**相关联，“所有者”通常是某种Item（例如，`fn()`或`const`），但也可以是闭包表达式（例如， `|x, y| x + y`）。
您可以使用 HIR 映射来查找与给定 def-id（[`maybe_body_owned_by`]）关联的body，或找到 body 的所有者（[`body_owner_def_id`]）。

[`rustc_hir::Body`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_hir/struct.Body.html
[`maybe_body_owned_by`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/hir/map/struct.Map.html#method.maybe_body_owned_by
[`body_owner_def_id`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/hir/map/struct.Map.html#method.body_owner_def_id
