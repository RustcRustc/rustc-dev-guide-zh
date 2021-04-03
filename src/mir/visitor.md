# MIR visitor

MIR visitor 是遍历 MIR 并查找事物或对其进行更改的便捷工具。Visitor trait 是在 [the `rustc_middle::mir::visit` module][m-v] 中定义的-其中有两个是通过单个宏生成的：`Visitor`（工作于 `&Mir` 之上，返回共享引用）和 `MutVisitor`（工作于 `&mut Mir`之上，并返回可变引用）。

[m-v]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/mir/visit/index.html

要实现 Visitor，您必须创建一个代表您的 Visitor 的类型。
通常，此类型希望在处理 MIR 时“挂”到您需要的任何状态上：

```rust,ignore
struct MyVisitor<...> {
    tcx: TyCtxt<'tcx>,
    ...
}
```

然后为该类型实现 `Visitor` 或 `MutVisitor`：

```rust,ignore
impl<'tcx> MutVisitor<'tcx> for NoLandingPads {
    fn visit_foo(&mut self, ...) {
        ...
        self.super_foo(...);
    }
}
```

如上所示，在实现过程中，您可以覆盖任何 `visit_foo` 方法（例如，`visit_terminator`），以便编写一些代码，这些代码将在遇到`foo` 时执行。如果要递归遍历foo的内容，则可以调用 `super_foo` 方法。 （注意：您永远都不应该覆盖 `super_foo`）

一个非常简单的 Visitor 示例可以在 [`NoLandingPads`] 中找到。该 Visitor 甚至不需要任何状态：它仅访问所有终止符并删除其“展开”的后继者。

[`NoLandingPads`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_mir/transform/no_landing_pads/struct.NoLandingPads.html

## 遍历

除了 Visitor 之外，[`rustc_middle::mir::traversal` 模块][t] 也包含一些有用的函数，用于以[不同的标准顺序][traversal]（例如，前序，反向后序，依此类推）遍历 MIR CFG。

[t]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/mir/traversal/index.html
[traversal]: https://en.wikipedia.org/wiki/Tree_traversal