# 代码生成

代码生成或"codegen"是编译器生成可执行二进制文件的一部分。通常，rustc 使用 LLVM 来生成代码; 它也支持 [Cranelift]。关键是 rustc 本身并不实现 codegen。但是值得注意的是，在 rust 源代码中，后端的许多部分在名称中都有 `codegen` (没有严格的界限)。

[Cranelift]: https://github.com/bytecodealliance/wasmtime/tree/HEAD/cranelift

> 注意: 如果您正在寻找关于如何调试代码生成错误的提示，请参阅[调试章节的这一部分][debugging]。

[debugging]: ./debugging.md

## LLVM 是什么?

[LLVM](https://llvm.org) 是“模块化和可重用的编译器和工具链技术的集合”。特别是，LLVM 项目包含一个可插拔的编译器后端(也称为"LLVM") ，许多编译器项目都使用它，包括 `clang` C 编译器和我们心爱的 `rustc`。

LLVM 接受 LLVM IR 的形式输入。它基本上是带有附加的低级类型和注释的汇编代码。这些注释有助于对 LLVM IR 和输出的机器代码进行优化。所有这一切的最终结果是(最终)一些可执行的东西(例如一个 ELF 对象、一个 EXE 或者一个 wasm)。

使用 LLVM 有几个好处:

- 不需要编写一个完整的编译器后端，减少了实现和维护的负担。
- 从 LLVM 项目收集的大量高级优化套件中受益。
- 可以自动将 Rust 编译到 LLVM 支持的任何平台上。例如，一旦 LLVM 添加了对 wasm 的支持，瞧！Rustc，clang，和一堆其他语言都能编译成 wasm！(嗯，还有一些额外的工作要做，但我们已经完成了90%)。
- 我们和其他编译器项目互相受益. 例如, 当[Spectre 和 Meltdown 安全漏洞][spectre]被发现，只需要修补 LLVM。

[spectre]: https://meltdownattack.com/

## 运行 LLVM, 链接和元数据生成

一旦建立了所有函数和静态等的 LLVM IR，就可以开始运行 LLVM 并进行优化。LLVM IR 分为“模块”。可以同时编写多个“模块”，以帮助实现多核使用。这些“模块”就是我们所说的 _codegen
units_。这些单元是在单态化收集阶段建立起来的。

一旦 LLVM 从这些模块生成对象，这些对象就会被传递给链接器，还可以选择生成元数据对象和归档文件或可执行文件。

运行优化的不一定是上面描述的代码原阶段。对于某些类型的 LTO，优化可能发生在链路时间。在将对象传递到链接器之前还可能进行一些优化，而在链接过程中也可能进行一些优化。

这些都发生在编译的最后阶段。代码可以在 [`rustc_codegen_ssa::back`][ssaback] 和 [`rustc_codegen_llvm::back`][llvmback] 中找到。遗憾的是，这段代码与 LLVM 相关的代码并没有很好地分离; [`rustc_codegen_ssa`][ssa] 包含了大量特定于 LLVM 后端的代码。

一旦这些组件完成了它们的工作，您的文件系统中就会出现许多与您所请求的输出相对应的文件。

[ssa]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_codegen_ssa/index.html
[ssaback]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_codegen_ssa/back/index.html
[llvmback]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_codegen_llvm/back/index.html