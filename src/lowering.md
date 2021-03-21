# Lowering

Lowering 步骤将 AST 转换为 [HIR](hir.html)。 
这意味着许多在类型分析或类似的语法无关分析中没有用的代码在这一阶段被删除了。
这种结构的例子包括但不限于

* 括号
    * 无需替换，直接删除，树结构本身就能明确运算顺序
* `for` 循环和 `while (let)` 循环
    * 转换为 `loop` + `match` 和一些 `let` binding
* `if let`
    * 转换为 `match`
* Universal `impl Trait`
    * 转换成范型参数（会添加flag来标志这些参数不是由用户写的）
* Existential `impl Trait`
    * 转换为虚拟的 `existential type` 声明

Lowering 需要遵守几点，否则就会违反 `src/librustc_middle/hir/map/hir_id_validator.rs` 中的制定的检查规则：

1. 如果创建了一个`HirId`，那就必须使用它。
   因此，如果您使用了 `lower_node_id`，则*必须*使用生成的 `NodeId` 或 `HirId`（两个都可以，因为检查 `HIR` 中的 `NodeId` 时也会检查是否存在现有的 `HirId`）
2. Lowering `HirId` 必须在对 item 有所有权的作用域内完成。
   这意味着如果要创建除当前正在 Lower 的 item 之外的其他 item，则需要使用 `with_hir_id_owner`。
   例如，在lower existential的 `impl Trait` 时会发生这种情况.
3. 即使其 `HirId` 未使用，要放入HIR结构中的 `NodeId` 也必须被 lower。
   此时一个合理的方案是调用 `let _ = self.lower_node_id(node_id);`。
4. 如果要创建在 `AST` 中不存在的新节点，则*必须*通过调用 `next_id` 方法为它们创建新的 ID。
   该方法会生成一个新的 `NodeId` 并自动为您 lowering 它，以便您获得 `HirId`。

如果您要创建新的 `DefId` ，由于每个 `DefId` 需要具有一个对应的 `NodeId`，建议将这些 `NodeId` 添加到 `AST` 中，这样您就不必在lowering时生成新的`DefId`。
这样做的好处是创建了一种通过 `NodeId` 查找某物的 `DefID` 的方法。
如果 lower 操作需要在多个位置使用该 `DefId`，则不能在所有这些位置生成一个新的 `NodeId`，因为那样的话，您将获得多余的的 `DefId`。
而对于来自AST的`NodeId`来说，这些就都不是问题了。

有一个 `NodeId` 也使得 `DefCollector` 可以生成 `DefId`，而不需要立即进行操作。
将 `DefId` 的生成集中在一个地方可以使重构和理解变得更加容易。