# MIR优化

MIR优化是指在代码生成之前，为了产生更好的MIR指令而执行的优化。
这些优化十分重要，体现在两个方面：
首先，它使得最终生成的可执行代码的质量更好；其次，这意味着LLVM需要的工作量更少，编译速度更快。
请注意，由于MIR是通用的（不是[monomorphized] [monomorph]）所以这些优化特别有效，我们可以优化通用代码，使得所有代码的特化版本同样受益！ 

[mir]: https://rustc-dev-guide.rust-lang.org/mir/index.html
[monomorph]: https://rustc-dev-guide.rust-lang.org/appendix/glossary.html#mono

MIR的优化执行在借用检查之后。通过执行一系列的pass不断优化MIR。
一些pass需要执行在全量的代码上，一些pass则不执行实际的优化操作只进行代码检查，还有些pass只在`release`模式下适用。

调用[`optimized_mir`][optmir] 来 [查询][query]为给定的[`DefId`][defid]生成优化的MIR，该查询确保借用检查器已运行并且已经进行了一些校验。
然后，[窃取][steal]MIR，执行优化后，返回被优化后的MIR。 

[optmir]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_mir/transform/fn.optimized_mir.html
[query]: ../query.md
[defid]: https://rustc-dev-guide.rust-lang.org/appendix/glossary.html#def-id
[steal]: https://rustc-dev-guide.rust-lang.org/mir/passes.html?highlight=steal#stealing

## 定义优化Passes

优化pass的声明和执行顺序由[`run_optimization_passes`][rop]函数定义。
它包含了一组待执行的pass，其中的每个pass都是一个实现了[`MirPass`] trait的结构体。通过一个元素类型为`&dyn MirPass`的数组实现。
这些pass通常在[`rustc_mir::transform`][trans]模块下完成自己的实现。

[rop]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_mir/transform/fn.run_optimization_passes.html
[`MirPass`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_mir/transform/trait.MirPass.html
[trans]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_mir/transform/index.html

下面有一些pass的示例：
- `CleanupNonCodegenStatements`: 清理那些只用于分析而不用于代码生成的信息；
- `ConstProp`: [常量传播][constprop]。

您可以查看[关于`MirPass`实现的相关章节][impl]中的更多示例。

[impl]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_mir/transform/trait.MirPass.html#implementors
[constprop]: https://en.wikipedia.org/wiki/Constant_folding#Constant_propagation

## MIR优化 levels

MIR优化有不同程度的行为。
实验性的优化可能会导致错误编译或增加编译时间。
这样的pass包含在`nightly`版本中，以收集反馈并修改。要启用这些缓慢的或实验性的优化，可以指定`-Z mir-opt-level`调试标志。
您可以在[compiler MCP]中找到这些级别的定义。
如果您正在开发MIR优化pass，并且想查询您的优化是否应该运行，可以使用`tcx.sess.opts.debugging_opts.mir_opt_level`检查输入的级别。 

[compiler MCP]: https://github.com/rust-lang/compiler-team/issues/319

## 优化参数`fuel`

`fuel`是一个编译器选项 (`-Z fuel=<crate>=<value>`)，可以精细地控制在编译过程中的优化情况：每次优化将`fuel`减少1，当`fuel`达到0时不再进行任何优化。
`fuel`的主要用途是调试那些可能不正确或使用不当的优化。通过更改选项，您可以通过二分法定位到发生错误的优化。 

一般来讲，MIR优化执行过程中会通过调用[`tcx.consider_optimizing`][consideroptimizing]来检查`fuel`，如果`fuel`为空则跳过优化。
有如下注意事项：

 1. 如果认为一个优化行为是有保证的（即，为了结果的正确性每次编译都要执行），那么`fuel`是可以跳过的，比如`PromoteTemps`。
 2. 在某些情况下，需要执行一个初始pass来收集候选，然后对他们迭代执行以达到优化的目的。在这种情况下，我们应该让初始pass对`fuel`的值尽可能地突变。
    这可以获得最佳的调试体验，因为可以确定候选列表中的某个优化pass可能未正确调用。 例如`InstCombine`和`ConstantPropagation`。 

[consideroptimizing]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/context/struct.TyCtxt.html#method.consider_optimizing

