# 编译器概览

<!-- toc -->

这一章是关于编译程序时的总体过程 —— 所有东西是如何组合起来的。

rust的编译器在两方面独具特色：首先它会对你的代码进行别的编译器不会进行的操作（比如借用检查），并且有许多非常规的实现选择（比如查询）。
我们将会在这一章中逐一讨论这些，并且在指南接下来的部分，我们会更深入细节的审视所有单独的部分。

## 编译器对你的代码做了什么

首先，我们来看看编译器对你的代码做了些什么。现在，除非必须，我们会避免提及编译器是如何实现这些步骤的；我们之后才会讨论这些。

- 编译步骤从用户编写Rust程序文本并且使用 `rustc` 编译器对其进行处理开始。命令行参数指明了编译器需要做的工作。
  举个例子，我们可以启用开发版特性（`-Z` 标识），执行 `check`——仅执行构建，或者得到LLVM-IR而不是可执行机器码。
  通过使用 `cargo`，`rustc` 的执行可能是不直接的。
- 命令行参数解析在 [`rustc_driver`] 中发生。这个 crate 定义了用户请求的编译配置
  并且将其作为一个 [`rustc_interface::Config`] 传给接下来的编译过程。
- 原始的 Rust 源文本被位于 [`rustc_lexer`] 的底层词法分析器分析。在这个阶段，源文本被转化成被称为 _tokens_ 的
  原子源码单位序列。 词法分析器支持 Unicode 字符编码。
- token 序列传给了位于 [`rustc_parse`] 的高层词法分析器以为编译流程的下一个阶段做准备。
  [`StringReader`] 结构体在这个阶段被用于执行一系列的验证工作并且将字符串转化为驻留符号（稍后便会讨论 _驻留_）。
  [字符串驻留] 是一种将多个相同的不可变字符串只存储一次的技术。

- 词法分析器有小的接口并且不直接依赖于`rustc`中的诊断基础设施。反之，它提供在`rustc_parse::lexer::mod`中被发送为真实诊断
  的作为普通数据的诊断。
- 词法分析器为 IDE 以及 过程宏 保留有全保真度的信息。
- 解析器 [将从词法分析器中得到的token序列转化为抽象语法树（AST）][parser]。它使用递归下降（自上而下）的方式来进行语法解析。
  解析器的 crate 入口为`rustc_parse::parser::item`中的`Parser::parse_crate_mod()`以及`Parser::parse_mod()`函数。
  外部模块解析入口为`rustc_expand::module::parse_external_mod`。
  以及宏解析入口为[`Parser::parse_nonterminal()`][parse_nonterminal]。
- 解析经由一系列 `Parser` 工具函数执行，包括`fn bump`，`fn check`，`fn eat`，`fn expect`，`fn look_ahead`。
- 解析是由要被解析的语义构造所组织的。分离的`parse_*`方法可以在`rustc_parse` `parser`文件夹中找到。
  源文件的名字和构造名相同。举个例子，在解析器中能找到以下的文件：
    - `expr.rs`
    - `pat.rs`
    - `ty.rs`
    - `stmt.rs`
- 这种命名方案被广泛地应用于编译器的各个阶段。你会发现有文件或者文件夹在解析、降低、类型检查、THIR降低、以及MIR源构建。
- 宏展开、AST验证、命名解析、以及程序错误检查都在编译过程的这个阶段进行。
- 解析器使用标准 `DiagnosticBuilder` API 来进行错误处理，但是我们希望在一个错误发生时，
  尝试恢复、解析Rust语法的一个超集。
- `rustc_ast::ast::{Crate, Mod, Expr, Pat, ...}` AST节点从解析器中被返回。
- 我们接下来拿到AST并且[将其转化为高级中间标识（HIR）][hir]。这是一种编译器友好的AST表示方法。
  这包括到很多如循环、`async fn`之类的去语法糖的东西。
- 我们使用 HIR 来进行[类型推导]。 这是对于一个表达式，自动检测其类型的过程。
- **TODO：也许在这里还有其他事情被完成了？我认为初始化类型检查在这里进行了？以及 trait 解析？**
- HIR之后 [被降低为中级中间标识（MIR）][mir]。
  - 同时，我们构造 THIR ，THIR是去更多语法糖的的 HIR。THIR被用于模式和详尽性检验。
    同时，它相较于 HIR 更容易被转化为MIR。
- MIR被用于[借用检查]。
- 我们（想要）[在 MIR 上做许多优化][mir-opt]因为它仍然是通用的，
  并且这样能改进我们接下来生成的代码，同时也能加快编译速度。
  - MIR 是高级（并且通用的）表示形式，所以在 MIR 层做优化要相较于在 LLVM-IR 层更容易。
    举个例子，LLVM看起来是无法优化 [`simplify_try`] 这样的模式，而mir优化则可以。
- Rust 代码是 _单态化_ 的，这意味着对于所有所有通用代码进行带被具体类型替换的类型参数的拷贝。
  要做到这一点，我们要生成一个列表来存储需要为什么具体类型生成代码。这被称为 _单态集合_。
- 我们接下来开始进行被依稀称作 _代码生成_ 或者 _codegen_。
  - [代码生成（codegen）][codegen]是将高等级源表示转化为可执行二进制码的过程。
    `rustc`使用LLVM来进行代码生成。第一步就是将 MIR 转化为 LLVM 中间表示（LLVM IR）。
    这是 MIR 依据我们由上一步生成的列表来真正被单态化的时候。
  - LLVM IR 被传给 LLVM，并且由其进行更多的优化。之后它产生机器码，
    这基本就是添加了附加底层类型以及注解的汇编代码。（比如一个 ELF 对象或者 wasm）。
  - 不同的库/二进制内容被链接以产生最终的二进制内容。

[String interning]: https://en.wikipedia.org/wiki/String_interning
[`rustc_lexer`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_lexer/index.html
[`rustc_driver`]: https://rustc-dev-guide.rust-lang.org/rustc-driver.html
[`rustc_interface::Config`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_interface/interface/struct.Config.html
[lex]: https://rustc-dev-guide.rust-lang.org/the-parser.html
[`StringReader`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_parse/lexer/struct.StringReader.html
[`rustc_parse`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_parse/index.html
[parser]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_parse/index.html
[hir]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_hir/index.html
[type inference]: https://rustc-dev-guide.rust-lang.org/type-inference.html
[mir]: https://rustc-dev-guide.rust-lang.org/mir/index.html
[borrow checking]: https://rustc-dev-guide.rust-lang.org/borrow_check.html
[mir-opt]: https://rustc-dev-guide.rust-lang.org/mir/optimizations.html
[`simplify_try`]: https://github.com/rust-lang/rust/pull/66282
[codegen]: https://rustc-dev-guide.rust-lang.org/backend/codegen.html
[parse_nonterminal]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_parse/parser/struct.Parser.html#method.parse_nonterminal

## 编译器是怎么做的

好，我们现在已经从高层视角看了编译器对你的代码做了什么，那让我们再从高层视角看看编译器是 _怎么_ 做到这些的。
这里有很多编译器需要满足/优化的限制以及冲突目标。举个例子，

- 编译速度：编译一份程序有多快。更多/好的编译时分析通常意味着编译会更慢。
  - 与此同时，我们想要支持增量编译，因此我们需要将其纳入考虑。
    我们怎样才能衡量哪些工作需要被重做，以及当用户修改程序时哪些东西能被重用？
    - 与此同时，我们不能在增量缓存中存储太多东西，因为这样会花费很多时间来从磁盘上加载
      并且会占用很多用户的系统空间……
- 编译器内存占用：当编译一份程序时，我们不希望使用多余的内存。
- 程序运行速度：编译出来的程序运行得有多快。更多/好的编译时分析通常意味着编译器可以做更好的优化。
- 程序大小：编译出来的二进制程序有多大？和前一个点类似。
- 编译器编译速度：编译这个编译器要花多长的时间？这影响着贡献者和编译器的维护。
- 实现复杂度：制造一个编译器是一个人/组能做到的最困难的事之一，并且 Rust 不是一门非常简单的语言，
  那么我们应该如何让编译器的代码基础便于管理？
- 编译正确性：编译器创建的二进制程序应该完成输入程序告诉要做的事，
  并且应该不论后面持续发生的大量变化持续进行。
- 整合工作：编译器需要对以不同方式使用编译器的其他工具（比如 cargo，clippy，miri，RLS）提供支持。
- 编译器稳定性：发布在 stable channel 上的编译器不应该无故崩溃或者出故障。
- Rust 稳定性：编译器必须遵守 Rust 的稳定性承诺，保证之前能够编译的程序不会因为编译器的实现的许多变化
  而无法编译。
- 其他工具的限制：rustc 在后端使用了 LLVM ，一方面我们希望借助 LLVM 的一些好处来优化编译器，
  另一方面我们需要针对它的一些限制/坏处做一些处理。

总之，当你阅读指南的接下来的部分的时候，好好记住这些事。他们将通常会指引我们作出选择。

### Intermediate representations

As with most compilers, `rustc` uses some intermediate representations (IRs) to
facilitate computations. In general, working directly with the source code is
extremely inconvenient and error-prone. Source code is designed to be human-friendly while at
the same time being unambiguous, but it's less convenient for doing something
like, say, type checking.

Instead most compilers, including `rustc`, build some sort of IR out of the
source code which is easier to analyze. `rustc` has a few IRs, each optimized
for different purposes:

- Token stream: the lexer produces a stream of tokens directly from the source
  code. This stream of tokens is easier for the parser to deal with than raw
  text.
- Abstract Syntax Tree (AST): the abstract syntax tree is built from the stream
  of tokens produced by the lexer. It represents
  pretty much exactly what the user wrote. It helps to do some syntactic sanity
  checking (e.g. checking that a type is expected where the user wrote one).
- High-level IR (HIR): This is a sort of desugared AST. It's still close
  to what the user wrote syntactically, but it includes some implicit things
  such as some elided lifetimes, etc. This IR is amenable to type checking.
- Typed HIR (THIR): This is an intermediate between HIR and MIR, and used to be called
  High-level Abstract IR (HAIR). It is like the HIR but it is fully typed and a bit
  more desugared (e.g. method calls and implicit dereferences are made fully explicit).
  Moreover, it is easier to lower to MIR from THIR than from HIR.
- Middle-level IR (MIR): This IR is basically a Control-Flow Graph (CFG). A CFG
  is a type of diagram that shows the basic blocks of a program and how control
  flow can go between them. Likewise, MIR also has a bunch of basic blocks with
  simple typed statements inside them (e.g. assignment, simple computations,
  etc) and control flow edges to other basic blocks (e.g., calls, dropping
  values). MIR is used for borrow checking and other
  important dataflow-based checks, such as checking for uninitialized values.
  It is also used for a series of optimizations and for constant evaluation (via
  MIRI). Because MIR is still generic, we can do a lot of analyses here more
  efficiently than after monomorphization.
- LLVM IR: This is the standard form of all input to the LLVM compiler. LLVM IR
  is a sort of typed assembly language with lots of annotations. It's
  a standard format that is used by all compilers that use LLVM (e.g. the clang
  C compiler also outputs LLVM IR). LLVM IR is designed to be easy for other
  compilers to emit and also rich enough for LLVM to run a bunch of
  optimizations on it.

One other thing to note is that many values in the compiler are _interned_.
This is a performance and memory optimization in which we allocate the values
in a special allocator called an _arena_. Then, we pass around references to
the values allocated in the arena. This allows us to make sure that identical
values (e.g. types in your program) are only allocated once and can be compared
cheaply by comparing pointers. Many of the intermediate representations are
interned.

### Queries

The first big implementation choice is the _query_ system. The rust compiler
uses a query system which is unlike most textbook compilers, which are
organized as a series of passes over the code that execute sequentially. The
compiler does this to make incremental compilation possible -- that is, if the
user makes a change to their program and recompiles, we want to do as little
redundant work as possible to produce the new binary.

In `rustc`, all the major steps above are organized as a bunch of queries that
call each other. For example, there is a query to ask for the type of something
and another to ask for the optimized MIR of a function. These
queries can call each other and are all tracked through the query system.
The results of the queries are cached on disk so that we can tell which
queries' results changed from the last compilation and only redo those. This is
how incremental compilation works.

In principle, for the query-fied steps, we do each of the above for each item
individually. For example, we will take the HIR for a function and use queries
to ask for the LLVM IR for that HIR. This drives the generation of optimized
MIR, which drives the borrow checker, which drives the generation of MIR, and
so on.

... except that this is very over-simplified. In fact, some queries are not
cached on disk, and some parts of the compiler have to run for all code anyway
for correctness even if the code is dead code (e.g. the borrow checker). For
example, [currently the `mir_borrowck` query is first executed on all functions
of a crate.][passes] Then the codegen backend invokes the
`collect_and_partition_mono_items` query, which first recursively requests the
`optimized_mir` for all reachable functions, which in turn runs `mir_borrowck`
for that function and then creates codegen units. This kind of split will need
to remain to ensure that unreachable functions still have their errors emitted.

[passes]: https://github.com/rust-lang/rust/blob/45ebd5808afd3df7ba842797c0fcd4447ddf30fb/src/librustc_interface/passes.rs#L824

Moreover, the compiler wasn't originally built to use a query system; the query
system has been retrofitted into the compiler, so parts of it are not
query-fied yet. Also, LLVM isn't our code, so that isn't querified
either. The plan is to eventually query-fy all of the steps listed in the
previous section, but as of this writing, only the steps between HIR and
LLVM-IR are query-fied. That is, lexing and parsing are done all at once for
the whole program.

One other thing to mention here is the all-important "typing context",
[`TyCtxt`], which is a giant struct that is at the center of all things.
(Note that the name is mostly historic. This is _not_ a "typing context" in the
sense of `Γ` or `Δ` from type theory. The name is retained because that's what
the name of the struct is in the source code.) All
queries are defined as methods on the [`TyCtxt`] type, and the in-memory query
cache is stored there too. In the code, there is usually a variable called
`tcx` which is a handle on the typing context. You will also see lifetimes with
the name `'tcx`, which means that something is tied to the lifetime of the
`TyCtxt` (usually it is stored or interned there).

[`TyCtxt`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/struct.TyCtxt.html

### `ty::Ty`

Types are really important in Rust, and they form the core of a lot of compiler
analyses. The main type (in the compiler) that represents types (in the user's
program) is [`rustc_middle::ty::Ty`][ty]. This is so important that we have a whole chapter
on [`ty::Ty`][ty], but for now, we just want to mention that it exists and is the way
`rustc` represents types!

Also note that the `rustc_middle::ty` module defines the `TyCtxt` struct we mentioned before.

[ty]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/type.Ty.html

### Parallelism

Compiler performance is a problem that we would like to improve on
(and are always working on). One aspect of that is parallelizing
`rustc` itself.

Currently, there is only one part of rustc that is already parallel: codegen.
During monomorphization, the compiler will split up all the code to be
generated into smaller chunks called _codegen units_. These are then generated
by independent instances of LLVM. Since they are independent, we can run them
in parallel. At the end, the linker is run to combine all the codegen units
together into one binary.

However, the rest of the compiler is still not yet parallel. There have been
lots of efforts spent on this, but it is generally a hard problem. The current
approach is to turn `RefCell`s into `Mutex`s -- that is, we
switch to thread-safe internal mutability. However, there are ongoing
challenges with lock contention, maintaining query-system invariants under
concurrency, and the complexity of the code base. One can try out the current
work by enabling parallel compilation in `config.toml`. It's still early days,
but there are already some promising performance improvements.

### Bootstrapping

`rustc` itself is written in Rust. So how do we compile the compiler? We use an
older compiler to compile the newer compiler. This is called [_bootstrapping_].

Bootstrapping has a lot of interesting implications. For example, it means
that one of the major users of Rust is the Rust compiler, so we are
constantly testing our own software ("eating our own dogfood").

For more details on bootstrapping, see
[the bootstrapping section of the guide][rustc-bootstrap].

[_bootstrapping_]: https://en.wikipedia.org/wiki/Bootstrapping_(compilers)
[rustc-bootstrap]: building/bootstrapping.md

# Unresolved Questions

- Does LLVM ever do optimizations in debug builds?
- How do I explore phases of the compile process in my own sources (lexer,
  parser, HIR, etc)? - e.g., `cargo rustc -- -Z unpretty=hir-tree` allows you to
  view HIR representation
- What is the main source entry point for `X`?
- Where do phases diverge for cross-compilation to machine code across
  different platforms?

# References

- Command line parsing
  - Guide: [The Rustc Driver and Interface](https://rustc-dev-guide.rust-lang.org/rustc-driver.html)
  - Driver definition: [`rustc_driver`](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_driver/)
  - Main entry point: [`rustc_session::config::build_session_options`](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_session/config/fn.build_session_options.html)
- Lexical Analysis: Lex the user program to a stream of tokens
  - Guide: [Lexing and Parsing](https://rustc-dev-guide.rust-lang.org/the-parser.html)
  - Lexer definition: [`rustc_lexer`](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_lexer/index.html)
  - Main entry point: [`rustc_lexer::first_token`](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_lexer/fn.first_token.html)
- Parsing: Parse the stream of tokens to an Abstract Syntax Tree (AST)
  - Guide: [Lexing and Parsing](https://rustc-dev-guide.rust-lang.org/the-parser.html)
  - Parser definition: [`rustc_parse`](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_parse/index.html)
  - Main entry points:
    - [Entry point for first file in crate](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_interface/passes/fn.parse.html)
    - [Entry point for outline module parsing](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/module/fn.parse_external_mod.html)
    - [Entry point for macro fragments][parse_nonterminal]
  - AST definition: [`rustc_ast`](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_ast/ast/index.html)
  - Expansion: **TODO**
  - Name Resolution: **TODO**
  - Feature gating: **TODO**
  - Early linting: **TODO**
- The High Level Intermediate Representation (HIR)
  - Guide: [The HIR](https://rustc-dev-guide.rust-lang.org/hir.html)
  - Guide: [Identifiers in the HIR](https://rustc-dev-guide.rust-lang.org/hir.html#identifiers-in-the-hir)
  - Guide: [The HIR Map](https://rustc-dev-guide.rust-lang.org/hir.html#the-hir-map)
  - Guide: [Lowering AST to HIR](https://rustc-dev-guide.rust-lang.org/lowering.html)
  - How to view HIR representation for your code `cargo rustc -- -Z unpretty=hir-tree`
  - Rustc HIR definition: [`rustc_hir`](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_hir/index.html)
  - Main entry point: **TODO**
  - Late linting: **TODO**
- Type Inference
  - Guide: [Type Inference](https://rustc-dev-guide.rust-lang.org/type-inference.html)
  - Guide: [The ty Module: Representing Types](https://rustc-dev-guide.rust-lang.org/ty.html) (semantics)
  - Main entry point (type inference): [`InferCtxtBuilder::enter`](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_infer/infer/struct.InferCtxtBuilder.html#method.enter)
  - Main entry point (type checking bodies): [the `typeck` query](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/struct.TyCtxt.html#method.typeck)
    - These two functions can't be decoupled.
- The Mid Level Intermediate Representation (MIR)
  - Guide: [The MIR (Mid level IR)](https://rustc-dev-guide.rust-lang.org/mir/index.html)
  - Definition: [`rustc_middle/src/mir`](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/mir/index.html)
  - Definition of source that manipulates the MIR: [`rustc_mir`](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_mir/index.html)
- The Borrow Checker
  - Guide: [MIR Borrow Check](https://rustc-dev-guide.rust-lang.org/borrow_check.html)
  - Definition: [`rustc_mir/borrow_check`](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_mir/borrow_check/index.html)
  - Main entry point: [`mir_borrowck` query](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_mir/borrow_check/fn.mir_borrowck.html)
- MIR Optimizations
  - Guide: [MIR Optimizations](https://rustc-dev-guide.rust-lang.org/mir/optimizations.html)
  - Definition: [`rustc_mir/transform`](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_mir/transform/index.html)
  - Main entry point: [`optimized_mir` query](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_mir/transform/fn.optimized_mir.html)
- Code Generation
  - Guide: [Code Generation](https://rustc-dev-guide.rust-lang.org/backend/codegen.html)
  - Generating Machine Code from LLVM IR with LLVM - **TODO: reference?**
  - Main entry point: [`rustc_codegen_ssa::base::codegen_crate`](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_codegen_ssa/base/fn.codegen_crate.html)
    - This monomorphizes and produces LLVM IR for one codegen unit. It then
      starts a background thread to run LLVM, which must be joined later.
    - Monomorphization happens lazily via [`FunctionCx::monomorphize`](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_codegen_ssa/mir/struct.FunctionCx.html#method.monomorphize) and [`rustc_codegen_ssa::base::codegen_instance `](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_codegen_ssa/base/fn.codegen_instance.html)