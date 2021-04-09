# 降级 MIR 到 Codegen IR

现在我们有了一个要从收集器生成的符号列表，我们需要生成某种类型的代码 codegen IR。在本章中，我们将假设是 LLVM IR，因为这是 rustc 常用的。实际的单态化是在我们翻译的过程中进行的。

回想一下，后端是由 [`rustc_codegen_ssa::base::codegen_crate`][codegen1] 开始的。最终到达 [`rustc_codegen_ssa::mir::codegen_mir`][codegen2]，从 MIR 降级到 LLVM IR。

[codegen1]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_codegen_ssa/base/fn.codegen_crate.html
[codegen2]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_codegen_ssa/mir/fn.codegen_mir.html

该代码被分成处理特定 MIR 原语的模块:

- [`rustc_codegen_ssa::mir::block`][mirblk] 将处理翻译块及其终结符。这个模块做的最复杂也是最有趣的事情是为函数调用生成代码，包括必要的展开处理 IR。
- [`rustc_codegen_ssa::mir::statement`][mirst] 翻译 MIR 语句。
- [`rustc_codegen_ssa::mir::operand`][mirop] 翻译 MIR 操作。
- [`rustc_codegen_ssa::mir::place`][mirpl] 翻译 MIR 位置参考。
- [`rustc_codegen_ssa::mir::rvalue`][mirrv] 翻译 MIR 右值。

[mirblk]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_codegen_ssa/mir/block/index.html
[mirst]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_codegen_ssa/mir/statement/index.html
[mirop]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_codegen_ssa/mir/operand/index.html
[mirpl]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_codegen_ssa/mir/place/index.html
[mirrv]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_codegen_ssa/mir/rvalue/index.html

在转换一个函数之前，将运行一些简单的和基本的分析步骤以帮助我们生成更简单、更有效的 LLVM IR。这种分析方法的一个例子是找出哪些变量类似于 SSA，这样我们就可以直接将它们转换为 SSA，而不必依赖 LLVM 的 `mem2reg` 来处理这些变量。分析可以在 [`rustc_codegen_ssa::mir::analyze`][mirana] 中找到。

[mirana]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_codegen_ssa/mir/analyze/index.html

通常一个 MIR 基本块会映射到一个 LLVM 基本块，除了极少数的例外: 内部调用或函数调用以及较少的基本的像 `assert` 这样 MIR 语句可能会产生多个基本块。这是对代码生成中不可移植的 LLVM 特定部分的完美诠释。内部生成是相当容易理解的，因为它涉及的抽象级别很低，可以在[`rustc_codegen_llvm::intrinsic`][llvmint] 中找到。

[llvmint]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_codegen_llvm/intrinsic/index.html

其他的都将使用[builder interface][builder]，这是在 [`rustc_codegen_ssa::mir::*`][ssamir] 模块中调用的代码。

[builder]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_codegen_llvm/builder/index.html
[ssamir]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_codegen_ssa/mir/index.html

> TODO: 讨论常量是如何生成的