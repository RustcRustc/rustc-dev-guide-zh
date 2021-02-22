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
  解析器的 crate 入为`rustc_parse::parser::item`中的`Parser::parse_crate_mod()`以及`Parser::parse_mod()`函数。
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
  这包括到很多如循环、`async fn`之类的解糖化的东西。
- 我们使用 HIR 来进行[类型推导]。 这是对于一个表达式，自动检测其类型的过程。
- **TODO：也许在这里还有其他事情被完成了？我认为初始化类型检查在这里进行了？以及 trait 解析？**
- HIR之后 [被降低为中级中间标识（MIR）][mir]。
  - 同时，我们构造 THIR ，THIR是更解糖化的 HIR。THIR被用于模式和详尽性检验。
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

### 中间形式表示

和大多数编译器一样，`rustc`使用了某种中间表示（IRs）来简化计算。通常，
直接用源代码来进行我们的工作是极度不方便并且容易出错的。源代码通常被设计的对人类友好，有复意的，
但是当做一些工作，比如类型检查的时候会较为不方便。

因此大多数编译器，包括`rustc`，根据源代码创建某种便于分析的 IR 。`rust` 有一些 IRs，
其各自根据不同的目的做了优化：

- Token 序列：词法分析器根据源代码直接生成了一个 token 序列。这个 token 序列相较于原始文本
  更便于解析器处理。
- 抽象语法树（AST）：抽象语法树根据词法分析器生成的 token 序列创建。它几乎表示的就是用户所写的。
  它帮助进行句法健全性检查（比如检查用户是否在正确的位置写了所期望的类型）。
- 高级 IR（HIR）：它是一些解糖的 AST。从句法的角度上，它仍然接近于用户所写的内容，
  但是它包含了一些诸如省略了的生命周期之类的信息。这种 IR 可以被用于类型检查。
- 类型化的 HIR（THIR）：这是介于 HIR 与 MIR 之间的中间形式，曾被称为高级抽象 IR （HAIR）。
  它类似于 HIR 但是它完整地类型化了并且稍微更加地解糖化（比如方法调用以及隐式解引用在这里被完全地显式化）。
  此外，相较于HIR，THIR更容易降低化到 MIR。
- 中级 IR（MIR）：这种 IR 基本属于控制流程图（CFG）。控制流程图是一种展示程序基础块以及控制流是如何在其间流通的图表。
  同时，MIR 也有一些带有简单类型化语句的基础块（比如赋值语句、简单计算语句等等）以及链接其他基础块的控制流边
  （比如调用语句、丢弃值等等）。MIR 被用于借用检查和其他重要的基于数据流的检查，比如检查未初始化的值。
  它同样被用来做一系列优化以及常值评估（通过 MIRI）。因为 MIR 仍然是普通形式，比起在单态化之后我们在这里可以做更多分析。
- LLVM IR：这是 LLVM 编译器所有输入的标准形式。LLVM IR 是一些带有许多注解的类型化的汇编语言。
  它是所有使用 LLVM 的编译器的标准格式（比如 C 编译器 clang 同样输出 LLVM IR）。

另一件要注意的事是，许多在编译器中的值被 _驻留_ 了。这是一种性能和内存优化手段，
我们将值收集到一个特殊的被称作 _arena_ 的收集器中。之后，我们将引用逐个对应到 arena 中收集的值上。
这使得我们可以保证相同的值（比如你程序中的类型）只被收集一次并且可以廉价地使用指针进行比较。
许多内部表示都被驻留了。

### 查询

第一个主要的选择是 _查询_ 系统。rust 编译器使用了一种不同于大多数书本上的所写编译器的查询系统，
后者是按顺序执行的一系列代码传递组织的。而 rust 编译器这样做是为了能够做到增量编译 ── 即，
当用户对其程序作出修改并且重新编译，我们希望尽可能少地做（与上一次编译所做的）相重复的工作来创建新的二进制文件。

在`rustc`中，所有以上这些主要步骤被组织为互相调用的一些查询。举个例子。假如有一条查询负责询问某个东西的类型，
而另一条查询负责询问某个函数的优化后的 MIR。这些查询可以相互调用并且由查询系统所跟踪。
查询的角果被缓存于硬盘上，这样我们就可以分辨相较于上次编译，哪些查询的结果改变了，并且仅重做这些查询。
这就是增量编译是如何工作的。

理论上讲，对于查询化步骤，我们独立完成上述每一项工作。举个例子，我们会将 HIR 带入一个函数
并且使用查询来请求该 HIR 的 LLVM IR。这驱动了优化 MIR 的生成，MIR 驱动了借用检查器，借用
检查器又驱动了 MIR 的生成，等等。

……除了那以外，这是非常过于简化的。事实上，有些查询并不是缓存于磁盘上的，并且编译器的某些部分
需要对所有代码运行正确性检查，即便是代码是无效的（比如借用检查器）。举个例子，[目前对于一个crate的所有函数`mir_borrowck`查询是第一个运行的。][passes]
之后代码生成器后端触发`collect_and_partition_mono_items`查询，它首先递归地对所有可达函数
请求`optimized_mir`，而接下来对函数运行`mir_borrowck`并且之后创建代码生成单元。
这种分割将需要保留下来以保证不可达的函数仍然将他们的错误发送出来。

[passes]: https://github.com/rust-lang/rust/blob/45ebd5808afd3df7ba842797c0fcd4447ddf30fb/src/librustc_interface/passes.rs#L824

此外，编译器建造之初是不使用查询系统的；查询系统是被加装到编译器中的，所以它有些部分还没被查询化。
同时，LLVM不是我们的代码，所以它也不是查询化的。计划是将前些部分所列举的步骤最终全部查询化，
但是对于本文，只有介于 HIR 和 LLVM-IR 之间的步骤是被查询化了的。这意味着对于整个程序，
词法分析以及解析都是被一次性完成的。

另一件这里要提到的事是非常重要的“类型上下文”，[`TyCtxt`]，它是一个相当巨大的结构体，
是所有东西的中心。（注意它的名字极其有历史性。这 _不_ 是指类型理论中的`Γ`或`Δ`一类的东西。
这个名字被保留下来是因为它就是源代码中结构体的名称。）所有查询都被定义为在[`TyCtxt`]类型上
的方法，并且内存中的查询缓存也同样被存储在此。在代码中，通常会有一个名为`tcx`变量，它是
类型上下文上的一个句柄。有同样会见到名为`'tcx`的生命周期，这意味着有东西被和`TyCtxt`的
生命周期绑定在了一起（通常它会被存储或者被驻留化）。

[`TyCtxt`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/struct.TyCtxt.html

### `ty::Ty`

类型在 Rust 中相当重要，并且他们形成了许多编译器分析的核心。用于表示类型（在用户程序中）的
主要类型（在编译器中）是 [`rustc_middle::ty::Ty`][ty]。它是如此的重要以至于我们为其
设置了一整章[`ty::Ty`][ty]，但是对于现在而言，我们只想提到它存在并且是`rustc`用来表示类型的方法！

同样注意到`rustc_middle::ty`模块定义了我们之前提到的`TyCtxt`结构体。

[ty]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/type.Ty.html

### 并行性

编译器表现是我们希望改进的一个问题（并且一直为之努力）。一个方面便是将 `rustc` 自身并行化。

目前，rustc 只有一个部分已经实现了并行化：代码生成。在单态化的过程中，编译器会将所有的代码
分割生成为叫做 _代码生成单元_ 的小块。它们之后由独立的 LLVM 实例生成。由于它们都是独立的，
我们可以并行地运行它们。最后，运行链接器来组合所有地代码生成单元成为一个二进制文件。

但是，编译器余下的部分仍然是未并行化的。我们已经为此付出了很多努力，但是它始终是一个难题。
目前的方法是把 `RefCell`s 转化为一些 `Mutex`s —— 那代表着我们转换到了线程安全的内部可变性。
但是仍然有许多在途的挑战比如锁争夺、维护并发下的查询系统不变量以及代码库的复杂性。
你可以通过在`config.toml`中启用并行编译来尝试并行工作。它仍处于早期阶段，但是有一些
有保障的性能改进。

### 自举

`rustc`自身是由 Rust 编写的。所以我们如何编译编译器？我们使用一个较老的编译器来编译
更新的编译器。这被称作 [_自举_]。

自举有许多有趣的含义。举个例子，它意味着 Rust 一个主要用户是 Rust 编译器，所以我们
持续的测试我们自己的软件（“吃我们自己的狗粮”）。

对于更多关于自举的细节，详见[这份指导书的自举部分][rustc-bootstrap]。

[_自举_]: https://en.wikipedia.org/wiki/Bootstrapping_(compilers)
[rustc-bootstrap]: building/bootstrapping.md

# 未被解决的问题

- LLVM 在 debug 建造的时候做优化了吗？
- 我如何在我自己的资源下浏览编译的各个过程（词法分析器、解析器、HIR 等等）？—— 比如，`cargo rustc -- -Z unpretty=hir-tree` 允许你查看 HIR 表示
- 什么是`X`的主要入口点？
- 交叉翻译到不同平台的机器码时，哪个阶段发生了分歧?

# 参考

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