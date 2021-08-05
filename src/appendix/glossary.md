# 附录 B: Glossary

# Glossary

<!-- &nbsp;s are a workaround for https://github.com/badboy/mdbook-toc/issues/19 -->
术语                                                  | 中文 | 意义 
------------------------------------------------------|--------|--------
<span id="arena">arena/arena allocation</span> &nbsp; | <span id="arena">竞技场分配</span> &nbsp;  | arena 是一个大内存缓冲区，从中可以进行其他内存分配，这种分配方式称为竞技场分配。 
<span id="ast">AST</span>                      &nbsp; | <span id="ast">抽象语法树</span>  | 由`rustc_ast` crate 产生的抽象语法树。
<span id="binder">binder</span>                &nbsp; |  <span id="binder">绑定器</span> | 绑定器是声明变量和类型的地方。例如，`<T>` 是`fn foo<T>(..)`中泛型类型参数 `T`的绑定器，以及 \|`a`\|` ...`  是 参数`a`的绑定器。
<span id="body-id">BodyId</span>               &nbsp; | <span id="body-id"> 主体ID</span> |  一个标识符，指的是crate 中的一个特定主体（函数或常量的定义）。
<span id="bound-var">bound variable</span>     &nbsp; |  <span id="bound-var">绑定变量</span>     &nbsp; | "绑定变量 "是在表达式/术语中声明的变量。例如，变量`a`被绑定在闭包表达式中\|`a`\|` a * 2`。
<span id="codegen">codegen</span>              &nbsp; |  <span id="codegen">代码生成</span>              &nbsp; |由 MIR 转译为 LLVM IR。
<span id="codegen-unit">codegen unit</span>    &nbsp; |  <span id="codegen-unit">代码生成单元</span>    &nbsp; |  当生成LLVM IR时，编译器将Rust代码分成若干个代码生成单元（有时缩写为CGU）。这些单元中的每一个都是由LLVM独立处理的，实现了并行化。它们也是增量编译的单位。
<span id="completeness">completeness</span>    &nbsp; | <span id="completeness">完整性</span>    &nbsp; |  类型理论中的一个技术术语，它意味着每个类型安全的程序也会进行类型检查。同时拥有健全性（soundness）和完整性（completeness）是非常困难的，而且通常健全性（soundness）更重要。
<span id="cfg">control-flow graph</span>       &nbsp; | <span id="cfg">控制流图</span>       &nbsp; |  程序的控制流表示。
<span id="ctfe">CTFE</span>                    &nbsp; |  <span id="ctfe">编译时函数求值</span>                    &nbsp; |   编译时函数求值（Compile-Time Function Evaluation）的简称，是指编译器在编译时计算 "const fn "的能力。这是编译器常量计算系统的一部分。
<span id="cx">cx</span>                        &nbsp; |  <span id="cx">上下文</span>                        &nbsp; |  Rust 编译器内倾向于使用 "cx "作为上下文的缩写。另见 "tcx"、"infcx "等。
<span id="ctxt">ctxt</span>                    &nbsp; |  <span id="ctxt">上下文（另一个缩写）</span>                    &nbsp; |  我们也使用 "ctxt "作为上下文的缩写，例如， [`TyCtxt`](#TyCtxt)，以及 [cx](#cx) 或 [tcx](#tcx)。
<span id="dag">DAG</span>                      &nbsp; |  <span id="dag">有向无环图</span>                      &nbsp; |  在编译过程中，一个有向无环图被用来跟踪查询之间的依赖关系
<span id="data-flow">data-flow analysis</span> &nbsp; | <span id="data-flow">数据流分析</span> &nbsp; |  静态分析，找出程序控制流中每一个点的属性。
<span id="debruijn">DeBruijn Index</span>      &nbsp; | <span id="debruijn">德布鲁因索引</span>      &nbsp; |  一种只用整数来描述一个变量被绑定的绑定器的技术。它的好处是，在变量重命名下，它是不变的。
<span id="def-id">DefId</span>                 &nbsp; | <span id="def-id">定义Id</span>                 &nbsp; |   一个识别定义的索引（见`rustc_middle/src/hir/def_id.rs`）。`DefPath`的唯一标识。
<span id="discriminant">discriminant</span>    &nbsp; |  <span id="discriminant">判别式</span>    &nbsp; |  与枚举变体或生成器状态相关的基础值，以表明它是 "激活的（avtive）"（但不要与它的["变体索引"](#variant-idx)混淆）。在运行时，激活变体的判别值被编码在[tag](#tag)中。
<span id="double-ptr">double pointer</span>    &nbsp; | <span id="double-ptr">双指针</span>    &nbsp; |  一个带有额外元数据的指针。同指「胖指针」。
<span id="drop-glue">drop glue</span>          &nbsp; | <span id="drop-glue">drop胶水</span>          &nbsp; |  (内部）编译器生成的指令，处理调用数据类型的析构器（`Drop`）。
<span id="dst">DST</span>                      &nbsp; | <span id="dst">DST</span>                      &nbsp; | Dynamically-Sized Type的缩写，这是一种编译器无法静态知道内存大小的类型（例如：`str'或`[u8]`）。这种类型没有实现`Sized`，不能在栈中分配。它们只能作为结构中的最后一个字段出现。它们只能在指针后面使用（例如：`&str`或`&[u8]`）。
<span id="ebl">early-bound lifetime</span>     &nbsp; |  <span id="ebl">早绑定生存期</span>     &nbsp; |  一个在其定义处被替换的生存期区域（region）。绑定在一个项目的`Generics'中，并使用`Substs'进行替换。与**late-bound lifetime**形成对比。
<span id="empty-type">empty type</span>        &nbsp; | <span id="empty-type">空类型</span>        &nbsp; |  参考 "uninhabited type".
<span id="fat-ptr">fat pointer</span>          &nbsp; |<span id="fat-ptr">胖指针</span>          &nbsp; |  一个两字（word）的值，携带着一些值的地址，以及一些使用该值所需的进一步信息。Rust包括两种 "胖指针"：对切片（slice）的引用和特质（trait）对象。对切片的引用带有切片的起始地址和它的长度。特质对象携带一个值的地址和一个指向适合该值的特质实现的指针。"胖指针 "也被称为 "宽指针"，和 "双指针"。
<span id="free-var">free variable</span>       &nbsp; | <span id="free-var">自由变量</span>       &nbsp; | 自由变量 是指没有被绑定在表达式或术语中的变量；
<span id="generics">generics</span>            &nbsp; | <span id="generics">泛型</span>            &nbsp; |  通用类型参数集。
<span id="hir">HIR</span>                      &nbsp; |  <span id="hir">高级中间语言</span>                      &nbsp; | 高级中间语言，通过对AST进行降级（lowering）和去糖（desugaring）而创建。
<span id="hir-id">HirId</span>                 &nbsp; |  <span id="hir-id">HirId</span>                 &nbsp; |  通过结合“def-id”和 "intra-definition offset"来识别HIR中的一个特定节点。
<span id="hir-map">HIR map</span>              &nbsp; |<span id="hir-map">HIR map</span>              &nbsp; |  通过`tcx.hir()`访问的HIR Map，可以让你快速浏览HIR并在各种形式的标识符之间进行转换。
<span id="ice">ICE</span>                      &nbsp; | <span id="ice">ICE</span>                      &nbsp; |  内部编译器错误的简称，这是指编译器崩溃的情况。
<span id="ich">ICH</span>                      &nbsp; |  <span id="ich">ICH</span>                      &nbsp; | 增量编译哈希值的简称，它们被用作HIR和crate metadata等的指纹，以检查是否有变化。这在增量编译中是很有用的，可以查看crate的一部分是否发生了变化，应该重新编译。
<span id="infcx">infcx</span>                  &nbsp; |  <span id="infcx">类型推导上下文</span>                  &nbsp; |  类型推导上下文（`InferCtxt`）。
<span id="inf-var">inference variable</span>   &nbsp; |  <span id="inf-var">推导变量</span>   &nbsp; |  在进行类型或区域推理时，"推导变量 "是一种特殊的类型/区域，代表你试图推理的内容。想想代数中的X。例如，如果我们试图推断一个程序中某个变量的类型，我们就创建一个推导变量来代表这个未知的类型。
<span id="intern">intern</span>                &nbsp; |<span id="intern">intern</span>                &nbsp; | intern是指存储某些经常使用的常量数据，如字符串，然后用一个标识符（如`符号'）而不是数据本身来引用这些数据，以减少内存的使用和分配的次数。
<span id="intrinsic">intrinsic</span>          &nbsp; |  <span id="intrinsic">内部函数</span>          &nbsp; |  内部函数是在编译器本身中实现的特殊功能，但向用户暴露（通常是不稳定的）。它们可以做神奇而危险的事情。
<span id="ir">IR</span>                        &nbsp; | <span id="ir">IR</span>                        &nbsp; |  Intermediate Representation的简称，是编译器中的一个通用术语。在编译过程中，代码被从原始源码（ASCII文本）转换为各种IR。在Rust中，这些主要是HIR、MIR和LLVM IR。每种IR都适合于某些计算集。例如，MIR非常适用于借用检查器，LLVM IR非常适用于codegen，因为LLVM接受它。
<span id="irlo">IRLO</span>                    &nbsp; | <span id="irlo">IRLO</span>                    &nbsp; |   `IRLO`或`irlo`有时被用作[internals.rust-lang.org](https://internals.rust-lang.org)的缩写。
<span id="item">item</span>                    &nbsp; | <span id="item">语法项</span>                    &nbsp; | 语言中的一种 "定义"，如静态、常量、使用语句、模块、结构等。具体来说，这对应于 "item"类型。
<span id="lang-item">lang item</span>          &nbsp; |  <span id="lang-item">语言项</span>          &nbsp; |  代表语言本身固有的概念的项目，如特殊的内置特质，如`同步`和`发送`；或代表操作的特质，如`添加`；或由编译器调用的函数。
<span id="lbl">late-bound lifetime</span>      &nbsp; | <span id="lbl">晚绑定生存期</span>      &nbsp; |  一个在其调用位置被替换的生存期区域。绑定在HRTB中，由编译器中的特定函数替代，如`liberate_late_bound_regions`。与**早绑定的生存期**形成对比。
<span id="local-crate">local crate</span>      &nbsp; | <span id="local-crate">本地crate</span>      &nbsp; |  目前正在编译的crate。这与 "上游crate"相反，后者指的是本地crate的依赖关系。
<span id="lto">[LTO]</span>                      &nbsp; | <span id="lto">[LTO]</span>                      &nbsp; | 链接时优化（Link-Time Optimizations）的简称，这是LLVM提供的一套优化，在最终二进制文件被链接之前进行。这些优化包括删除最终程序中从未使用的函数，例如。_[ThinLTO]_是LTO的一个变种，旨在提高可扩展性和效率，但可能牺牲了一些优化。
<span id="llvm">[LLVM]</span>                  &nbsp; |  <span id="llvm">[LLVM]</span>                  &nbsp; |  (实际上不是一个缩写 :P) 一个开源的编译器后端。它接受LLVM IR并输出本地二进制文件。然后，各种语言（例如Rust）可以实现一个编译器前端，输出LLVM IR，并使用LLVM编译到所有LLVM支持的平台。
<span id="memoization">memoization</span>      &nbsp; |  <span id="memoization">memoization</span>      &nbsp; |  储存（纯）计算结果（如纯函数调用）的过程，以避免在未来重复计算。这通常是执行速度和内存使用之间的权衡。
<span id="mir">MIR</span>                      &nbsp; | <span id="mir">中级中间语言</span>                      &nbsp; | 在类型检查后创建的中级中间语言，供borrowck和codegen使用。
<span id="miri">miri</span>                    &nbsp; | <span id="miri">mir解释器</span>                    &nbsp; |  MIR的一个解释器，用于常量计算。
<span id="mono">monomorphization</span>        &nbsp; |  <span id="mono">单态化</span>        &nbsp; |  采取类型和函数的通用实现并将其与具体类型实例化的过程。例如，在代码中可能有`Vec<T>`，但在最终的可执行文件中，将为程序中使用的每个具体类型有一个`Vec`代码的副本（例如，`Vec<usize>`的副本，`Vec<MyStruct>`的副本，等等）。
<span id="normalize">normalize</span>          &nbsp; |<span id="normalize">归一化</span>          &nbsp; | 转换为更标准的形式的一般术语，但在rustc的情况下，通常指的是关联类型归一化。
<span id="newtype">newtype</span>              &nbsp; | <span id="newtype">newtype</span>              &nbsp; | 对其他类型的封装（例如，`struct Foo(T)`是`T`的一个 "新类型"）。这在Rust中通常被用来为索引提供一个更强大的类型。
<span id="niche">niche</span>                  &nbsp; |  <span id="niche">利基</span>                  &nbsp; |  一个类型的无效位模式*可用于*布局优化。有些类型不能有某些位模式。例如，"非零*"整数或引用"&T "不能用0比特串表示。这意味着编译器可以通过利用无效的 "利基值 "来进行布局优化。这方面的一个应用实例是[*Discriminant elision on `Option`-like enums*](https://rust-lang.github.io/unsafe-code-guidelines/layout/enums.html#discriminant-elision-on-option-like-enums)，它允许使用一个类型的niche作为一个`enum`的["标签"](#tag)，而不需要一个单独的字段。
<span id="nll">NLL</span>                      &nbsp; |  <span id="nll">NLL</span>                      &nbsp; |  这是非词法作用域生存期的简称，它是对Rust的借用系统的扩展，使其基于控制流图。
<span id="node-id">node-id or NodeId</span>    &nbsp; |  <span id="node-id">node-id or NodeId</span>    &nbsp; |  识别AST或HIR中特定节点的索引；逐渐被淘汰，被`HirId`取代。
<span id="obligation">obligation</span>        &nbsp; | <span id="obligation">obligation</span>        &nbsp; |  必须由特质系统证明的东西。
<span id="placeholder">placeholder</span>      &nbsp; | <span id="placeholder">placeholder</span>      &nbsp; |  **注意：skolemization被placeholder废弃**一种处理围绕 "for-all "类型的子类型的方法（例如，`for<'a> fn(&'a u32)`），以及解决更高等级的trait边界（例如，`for<'a> T: Trait<'a>`）。
<span id="point">point</span>                  &nbsp; | <span id="point">point</span>                  &nbsp; | 在NLL分析中用来指代MIR中的某个特定位置；通常用来指代控制流图中的一个节点。
<span id="polymorphize">polymorphize</span>    &nbsp; | <span id="polymorphize">多态化</span>    &nbsp; | 一种避免不必要的单态化的优化。
<span id="projection">projection</span>        &nbsp; | <span id="projection">投影</span>        &nbsp; | 一个 "相对路径 "的一般术语，例如，`x.f`是一个 "字段投影"，而`T::Item`是一个"关联类型投影"
<span id="pc">promoted constants</span>        &nbsp; |  <span id="pc">常量提升</span>        &nbsp; |  从函数中提取的常量，并提升到静态范围
<span id="provider">provider</span>            &nbsp; | <span id="provider">provider</span>            &nbsp; | 执行查询的函数。
<span id="quantified">quantified</span>        &nbsp; |  <span id="quantified">量化</span>        &nbsp; |在数学或逻辑学中，存在量词和普遍量词被用来提出诸如 "是否有任何类型的T是真的？"或 "这对所有类型的T都是真的吗？"这样的问题
<span id="query">query</span>                  &nbsp; |  <span id="query">查询</span>                  &nbsp; |  编译过程中的一个子计算。查询结果可以缓存在当前会话中，也可以缓存到磁盘上，用于增量编译。
<span id="recovery">recovery</span>            &nbsp; | <span id="recovery">恢复</span>            &nbsp; | 恢复是指在解析过程中处理无效的语法（例如，缺少逗号），并继续解析AST。这可以避免向用户显示虚假的错误（例如，当结构定义包含错误时，显示 "缺少字段 "的错误）。
<span id="region">region</span>                &nbsp; |  <span id="region">区域</span>                &nbsp; |  和生存期精彩使用的另一个术语。
<span id="rib">rib</span>                      &nbsp; | <span id="rib">rib</span>                      &nbsp; |  名称解析器中的一个数据结构，用于跟踪名称的单一范围。
<span id="scrutinee">scrutinee</div>           &nbsp; | <span id="scrutinee">审查对象</div>           &nbsp; | 审查对象是在`match`表达式和类似模式匹配结构中被匹配的表达式。例如，在`match x { A => 1, B => 2 }`中，表达式`x`是被审查者。
<span id="sess">sess</span>                    &nbsp; | <span id="sess">sess</span>                    &nbsp; |  编译器会话，它存储了整个编译过程中使用的全局数据
<span id="side-tables">side tables</span>      &nbsp; | <span id="side-tables">side tables</span>      &nbsp; | 由于AST和HIR一旦创建就不可改变，我们经常以哈希表的形式携带关于它们的额外信息，并以特定节点的ID为索引。
<span id="sigil">sigil</span>                  &nbsp; |  <span id="sigil">符号</span>                  &nbsp; |  就像一个关键词，但完全由非字母数字的标记组成。例如，`&`是引用的标志。
<span id="soundness">soundness</span>          &nbsp; | <span id="soundness">健全性</span>          &nbsp; | 类型理论中的一个技术术语。粗略的说，如果一个类型系统是健全的，那么一个进行类型检查的程序就是类型安全的。也就是说，人们永远不可能（在安全的Rust中）把一个值强加到一个错误类型的变量中。
<span id="span">span</span>                    &nbsp; | <span id="span">span</span>                    &nbsp; | 用户的源代码中的一个位置，主要用于错误报告。这就像一个文件名/行号/列的立体元组：它们携带一个开始/结束点，也跟踪宏的扩展和编译器去糖。所有这些都被装在几个字节里（实际上，它是一个表的索引）。
<span id="substs">substs</span>                &nbsp; |  <span id="substs">替换</span>                &nbsp; | 给定的通用类型或项目的替换（例如，`HashMap<i32, u32>`中的`i32'、`u32'）。
<span id="sysroot">sysroot</span>              &nbsp; |  <span id="sysroot">sysroot</span>              &nbsp; |  用于编译器在运行时加载的构建工件的目录。
<span id="tag">tag</span>                      &nbsp; |  <span id="tag">tag</span>                      &nbsp; |  枚举/生成器的 "标签 "编码激活变体/状态的判别式(discriminant)。 标签可以是 "直接的"（简单地将判别式存储在一个字段中）或使用"利基"。
<span id="tcx">tcx</span>                      &nbsp; | <span id="tcx">tcx</span>                      &nbsp; | "类型化上下文"（`TyCtxt`），编译器的主要数据结构。
<span id="lifetime-tcx">`'tcx`</span>          &nbsp; | <span id="lifetime-tcx">`'tcx`</span>          &nbsp; | `TyCtxt'所使用的分配区域的生存期。在编译过程中，大多数数据都会使用这个生存期，但HIR数据除外，它使用`'hir`生存期。
<span id="token">token</span>                  &nbsp; | <span id="token">词条</span>                  &nbsp; | 解析的最小单位。词条是在词法运算后产生的
<span id="tls">[TLS]</span>                    &nbsp; | <span id="tls">[TLS]</span>                    &nbsp; | 线程本地存储。变量可以被定义为每个线程都有自己的副本（而不是所有线程都共享该变量）。这与LLVM有一些相互作用。并非所有平台都支持TLS。
<span id="trait-ref">trait reference</span>    &nbsp; | <span id="trait-ref">trait 引用</span>    &nbsp; |  一个特质的名称，以及一组合适的输入类型/生存期。
<span id="trans">trans</span>                  &nbsp; | <span id="trans">trans</span>                  &nbsp; | 是 "转译"的简称，是将MIR转译成LLVM IR的代码。已经重命名为codegen。
<span id="ty">`Ty`</span>                      &nbsp; |  <span id="ty">`Ty`</span>                      &nbsp; |  一个类型的内部表示。
<span id="tyctxt">TyCtxt</span>                &nbsp; |  <span id="tyctxt">TyCtxt</span>                &nbsp; |  在代码中经常被称为tcx的数据结构，它提供对会话数据和查询系统的访问。
<span id="ufcs">UFCS</span>                    &nbsp; | <span id="ufcs">UFCS</span>                    &nbsp; | 通用函数调用语法（Universal Function Call Syntax）的简称，这是一种调用方法的明确语法。
<span id="ut">uninhabited type</span>          &nbsp; |  <span id="ut">孤类型</span>          &nbsp; |  一个没有值的类型。这与ZST不同，ZST正好有一个值。一个孤类型的例子是`enum Foo {}`，它没有变体，所以，永远不能被创建。编译器可以将处理孤类型的代码视为死代码，因为没有这样的值可以操作。`！`（从未出现过的类型）是一个孤类型。孤类型也被称为 "空类型"。
<span id="upvar">upvar</span>                  &nbsp; | <span id="upvar">upvar</span>                  &nbsp; | 一个闭合体从闭合体外部捕获的变量
<span id="variance">variance</span>            &nbsp; |  <span id="variance">型变</span>            &nbsp; |  确定通用类型/寿命参数的变化如何影响子类型；例如，如果`T`是`U`的子类型，那么`Vec<T>`是`Vec<U>`的子类型，因为`Vec`在其通用参数中是协变的。
<span id="variant-idx">variant index</span>    &nbsp; |<span id="variant-idx">变体索引</span>    &nbsp; | 在一个枚举中，通过给它们分配从0开始的索引来识别一个变体。这纯粹是内部的，不要与"判别式"相混淆，后者可以被用户覆盖（例如，`enum Bool { True = 42, False = 0 }`）。
<span id="wide-ptr">wide pointer</span>        &nbsp; |<span id="wide-ptr">宽指针</span>        &nbsp; |一个带有额外元数据的指针。
<span id="zst">ZST</span>                      &nbsp; | <span id="zst">ZST</span>                      &nbsp; |   零大小类型。这种类型，其值的大小为0字节。由于`2^0 = 1`，这种类型正好有一个值。例如，`()`（单位）是一个ZST。`struct Foo;`也是一个ZST。编译器可以围绕ZST做一些很好的优化。

[LLVM]: https://llvm.org/
[LTO]: https://llvm.org/docs/LinkTimeOptimization.html
[ThinLTO]: https://clang.llvm.org/docs/ThinLTO.html
[TLS]: https://llvm.org/docs/LangRef.html#thread-local-storage-models