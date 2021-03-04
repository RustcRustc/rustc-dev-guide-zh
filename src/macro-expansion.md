# 宏展开

<!-- toc -->

> `rustc_ast`, `rustc_expand`, 和 `rustc_builtin_macros` 都在重构中，所以本章节中的部分链接可能会打不开。

Rust 有一个非常强大的宏系统。在之前的章节中，我们了解了解析器（parser）如何预留要展开的宏（使用临时的[占位符][placeholders] ）。这个章节将介绍迭代地展开这些宏的过程，直到我们的 crate 会有一个完整的 AST，且没有任何未展开的宏（或编译错误）。

[placeholders]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/placeholders/index.html

首先，我们将讨论宏展开和集成并输出到 ASTs 中的算法。随后，我们将看到健全的（hygiene）数据是如何被收集的。最后，我们将研究展开不同种类宏的细节。

非常多的算法和数据结构都在 [`rustc_expand`] 中，基础数据结构在 [`rustc_expand::base`][base] 中。

还要注意的是，`cfg` 和 `cfg_attr` 是其他宏中被特殊处理的，并在 [`rustc_expand::config`][cfg] 中处理。

[`rustc_expand`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/index.html
[base]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/base/index.html
[cfg]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/config/index.html

## 展开和 AST 集成

首先，展开是发生在 crate 层面。给定一个 crate 的原始代码，编译器将生成一个包含所有宏展开、所有模块内联、等的巨大的 AST。这个过程的主要入口是在  [`MacroExpander::fully_expand_fragment`][fef] 方法中。除了少数例外情况，我们整个 crate 上都使用这个方法（获得更详细的关于边缘案例的扩展的讨论，请参考 ["eager-expansion"](#eager-expansion)，）。

[`rustc_builtin_macros`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_builtin_macros/index.html
[reb]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/build/index.html


在更高层次上，[`fully_expand_fragment`][fef] 在迭代（反复）运行的，我们将保留一个未解析的宏调用队列（即尚未找到定义的宏）。我们反复地在队列中选择一个宏，对其进行解析，扩展，并将其集成回去。如果我们无法在迭代中取得进展，这代表着存在编译错误。算法如下 [algorithm][original]:

[fef]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/expand/struct.MacroExpander.html#method.fully_expand_fragment
[original]: https://github.com/rust-lang/rust/pull/53778#issuecomment-419224049

0. 初始化一个队列（`queue`）用于保存未解析的宏调用。
1. 反复直到队列（`queue`）晴空（或者没有任何进展，即有错误）
    0. 尽可能地在我们已部分构建的 create 中[解析（Resolve）](./name-resolution.md)  导入（imports）。
    1. 从我们部分已构建的  crate （类似方法、属性、派生）中尽可能多得收集宏[`调用`][inv]，并将它们添加到队列中。
    2. 将第一元素从队列中取出，并尝试解析它。
    3. 如果它被成功解析：
        0. 运行宏扩展器（macro's expander）函数，该函数消费（consumes）一个 [`TokenStream`] 或 AST 并生成一个 [`TokenStream`]或 [`AstFragment`] (取决于宏的种类). (`TokenStream`是一个[`TokenTree`s][tt] 的集合，
        每一个都是一个 token （标点、标识符或文字）或被分隔的组合（在`()`/`[]`/`{}`中的任何内容）
        现在，我们以及知道了宏本身的一切，并且可以调用 `set_expn_data` 去填满全局数据重的属性；这是与 `ExpnId` 相关的 hygiene data 。（见[下文"hygiene"章节][hybelow]）
        1. 将 AST 集成到一个现有的大型的 AST 中。从本质上讲，这是“类似 token 的块” 变成适当的固定的 AST 并带有 side-tables。
        它的发生过程如下：
            - 如果宏产生 tokens（例如 proc macro），我们将其解析为 AST ，这可能会产生解析错误。
            - 在展开的过程中，我们构建  `SyntaxContext`s (hierarchy 2). （见[下文"hygiene"章节][hybelow]）
            - 这三个过程在每个刚从宏展开的 AST 片段上依次地发生：
                - [`NodeId`]s 由[`InvocationCollector`] 分配的。这还会从新的 AST 片段中收集新的宏调用，并将它们添加到队列中。
                - ["Def paths"][defpath] 被创建，同时 [`DefId`]s 由
                  [`DefCollector`] 分配的。
                - 名字由 [`BuildReducedGraphVisitor`] 放入模块中（从解析器（resolver's）的角度来看）。
        
        2. 在展开单个宏并集成输出后，继续执行
        [`fully_expand_fragment`][fef] 的下一个迭代。
    4. 如果它没有被成功解析：
        0. 将宏放回队列中
        1. 继续下一个迭代。

[defpath]: https://rustc-dev-guide.rust-lang.org/hir.html?highlight=def,path#identifiers-in-the-hir
[`NodeId`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_ast/node_id/struct.NodeId.html
[`InvocationCollector`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/expand/struct.InvocationCollector.html
[`DefId`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_hir/def_id/struct.DefId.html
[`DefCollector`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_resolve/def_collector/struct.DefCollector.html
[`BuildReducedGraphVisitor`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_resolve/build_reduced_graph/struct.BuildReducedGraphVisitor.html
[hybelow]: #hygiene-and-hierarchies
[tt]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_ast/tokenstream/enum.TokenTree.html
[`TokenStream`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_ast/tokenstream/struct.TokenStream.html
[inv]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/expand/struct.Invocation.html
[`AstFragment`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/expand/enum.AstFragment.html

### 错误恢复

如果我们在一次迭代中没有取得任何进展，那么我们就遇到了编译错误(例如一个未定义的宏或导入)。为了进行诊断，我们尝试从错误(未解析的宏或导入)中恢复。这允许编译在第一个错误之后继续进行，这样我们就可以一次报告更多错误。恢复不能使得编译通过。我们知道在这一节点上它会失败。恢复是通过将未成功解析的宏展开为 [`ExprKind::Err`][err] 来实现的。

[err]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_ast/ast/enum.ExprKind.html#variant.Err

### 名称解析

注意，这里涉及到名称解析：我们需要解析上述算法中的导入和宏名。这在 [`rustc_resolve::macros`][mresolve] 中完成，它解析宏路径，验证这些解析，并报告各种错误(例如:“未找到”或“找到了，但它不稳定（unstable）”或“预期的x，但发现的y”)。但是，我们还没有尝试解析其他名称。这将在后面发生，我们将在[下一章](./name-resolution.md)中看到。

[mresolve]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_resolve/macros/index.html

### Eager Expansion

_Eager expansion_ 代表着我们在展开宏调用之前，先展开宏调用的参数。这仅对少数需要文字的特殊内置宏实现；首先对其中的一些宏展开参数可以获得更流畅的用户体验。作为一个例子，请考虑下属情况：

```rust,ignore
macro bar($i: ident) { $i }
macro foo($i: ident) { $i }

foo!(bar!(baz));
```

lazy expansion 会首先扩展 `foo!` ，eager expansion 会扩展 `bar!`。

Eager expansion 不是一个普遍的（通用的） Rust 特性（feature）。实现更加普遍的 eager expansion 是具有挑战性的，但是为了用户体验，我们为一些内置宏实现了它（eager expansion）。内置宏是在 [`rustc_builtin_macros`] 实现，还有一些其他早期的代码生成工具，例如注入标准库的导入或生成测试的工具。在 [`rustc_expand::build`] 有一些额外的帮助工具来构建 AST 片段（fragments）。Eager expansion 通常执行 lazy (normal) expansion 来展开子集。它是通过只在一个部分的 crate 的上来调用 [`fully_expand_fragment`][fef] 来完成的。（与我们通常使用整个 crate 来调用相反）。

### 其他数据结构

以下是涉及到扩展和扩展的其他重要数据结构
- [`ResolverExpand`] - 一个用来阻隔（break）crate 的依赖的 trait。这允许解析服务在 [`rustc_ast`] 中使用，虽然 [`rustc_resolve`] 和 几乎所有其他的东西都依赖于 [`rustc_ast`] 。
- [`ExtCtxt`]/[`ExpansionData`] - 用来保存在处理过程中各种中间数据。
- [`Annotatable`] - 可以作为属性目标的 AST 片段。几乎和 AstFragment 相同，除了类型和可以由宏生成但不能用属性注释。
- [`MacResult`] - 一个“多态的” AST 片段，可以根据他的 [`AstFragmentKind`]（item、expression、pattern）转换成不同的 `AstFragment`。


[`rustc_ast`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_ast/index.html
[`rustc_resolve`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_resolve/index.html
[`ResolverExpand`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/base/trait.ResolverExpand.html
[`ExtCtxt`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/base/struct.ExtCtxt.html
[`ExpansionData`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/base/struct.ExpansionData.html
[`Annotatable`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/base/enum.Annotatable.html
[`MacResult`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/base/trait.MacResult.html
[`AstFragmentKind`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/expand/enum.AstFragmentKind.html

## hygiene 和结构层次

如果您曾使用过 C/C++  预处理器宏，就会知道有一些烦人的、难以调试的陷阱！例如，考虑以下代码：

```c
#define DEFINE_FOO struct Bar {int x;}; struct Foo {Bar bar;};

// Then, somewhere else
struct Bar {
    ...
};

DEFINE_FOO
```

大多数人都避免这样写 C - 因为他无法通过编译。宏定义的 `struct Bar` 与代码中的结构 `struct Bar` 定义冲突。请再考虑以下代码：


```c
#define DO_FOO(x) {\
    int y = 0;\
    foo(x, y);\
    }

// Then elsewhere
int y = 22;
DO_FOO(y);
```

你看到任何问题了吗？我们想去生成调用  `foo(22, 0)` 但是我们得到了 `foo(0, 0)` ，因为在宏中已经定义了 `y`! 

这两个都是 _macro hygiene_ 问题的例子。 _Hygiene_  关于如何处理名字定义在宏中。特别是，一个健康的宏系统可以防止由于宏中引入的名称而产生的错误。Rust 宏是卫生的（hygienic），因为不允许编写上述的 bugs。

在更高层次上，rust 编译器的卫生（hygiene）性是通过跟踪定义（引入）和使用名称的上下文来保证的。然后我们可以根据上下文消除名字的歧义。宏系统未来的迭代将允许宏的编写者更好地控制该上下文。例如宏的编写者可能想在宏调用的上下文中定义（引入）一个新的名称。另一种情况是，宏的编写者只在宏的作用域内使用变量（也就是说在宏的外部不可见）。


[code_dir]: https://github.com/rust-lang/rust/tree/master/compiler/rustc_expand/src/mbe
[code_mp]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/mbe/macro_parser
[code_mr]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/mbe/macro_rules
[code_parse_int]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/mbe/macro_parser/fn.parse_tt.html
[parsing]: ./the-parser.html

上下文被添加到 AST 节点。所有由宏生成的 AST 节点都附加了上下文。此外，可能还有些具有上下文的节点，例如一些解析语法糖（非宏展开节点被认为只有 root 上下文，将在后面阐述）。这个编译器，我们使用 [`rustc_span::Span`s][span] 定位代码的位置。这个结构同样有卫生（hygiene）性信息，我们将在后面看到。

[span]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/struct.Span.html

因为宏调用和定义可以是嵌套的，所以节点的语法上下文也必须是有层次的。比如说，如果我们扩展一个宏，有一个宏调用或者定义在生成的输出中，那么语法上下文应该反映出嵌套。

然而，事实证明，出于不同目的，我们实际上需要跟踪一些类型的上下文。因此一个 crate 的卫生（hygiene）信息不只是由一个而是由三个扩展层次构成的。

所有层次结构都需要某种 "macro ID" 来标识展开链中的单个元素。这个 ID 是 [`ExpnId`]。所有的宏收到一个整数 ID ，当我们发现新的宏调用时，从 0 开始自增。所有层次结构都是从 [`ExpnId::root()`][rootid] 开始的（当前层次的父节点）。

[`rustc_span::hygiene`][hy] 包含了所有卫生（hygiene）相关的算法（[`Resolver::resolve_crate_root`][hacks] 中的一些 hacks 在除外）和卫生（hygiene）相关的数据结构，这些结构都保存在全局数据中。

实际的层次结构存储在 [`HygieneData`][hd] 中。这是一个全局数据，包含将装修和展开信息，可以从任意的 [`Ident`] 访问，无需任何上下文。

[`ExpnId`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/hygiene/struct.ExpnId.html
[rootid]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/hygiene/struct.ExpnId.html#method.root
[hd]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/hygiene/struct.HygieneData.html
[hy]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/hygiene/index.html
[hacks]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_resolve/struct.Resolver.html#method.resolve_crate_root
[`Ident`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/symbol/struct.Ident.html

### 展开顺序层次结构

第一，层次结构将跟踪展开的顺序，即宏调用出现在另一个宏的输出中。

在这里，层次结构中的子元素将被标记为“最内层的”，[`ExpnData`] 结构自身包含宏定义和宏调用的属性子集，这些属性是全局可用的。[`ExpnData::parent`][edp] 在当前层次结构中，跟踪 子节点 -> 父节点的链接。


[`ExpnData`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/hygiene/struct.ExpnData.html
[edp]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/hygiene/struct.ExpnData.html#structfield.parent

例如

```rust,ignore
macro_rules! foo { () => { println!(); } }

fn main() { foo!(); }
```

在代码中，AST 节点最终会生成以下层次结构。

```
root
    expn_id_foo
        expn_id_println
```

### 宏定义的结构层次

第二，层次结构将跟踪宏定义的顺序。即我们展开一个宏，在其输出中出现另一个宏定义。这个层次结构比其他两个结构层次更复杂，更棘手。

[`SyntaxContext`][sc]  通过 ID 表示此层次结构中的整个链。[`SyntaxContextData`][scd] 包含了与给定的 
`SyntaxContext` 相关的数据；大多数情况下，它是一个缓存，用于以不同方式过滤该链的结果。[`SyntaxContextData::parent`][scdp] 是此处 子节点-> 父节点 的链接，[`SyntaxContextData::outer_expns`][scdoe] 是链中的各个元素。“链接运算符”在编译器代码中是[`SyntaxContext::apply_mark`][am]。

上述提到的 [`Span`][span] 实际上只是代码位置和 `SyntaxContext` 的紧凑表现。同样的，[`Ident`] 只是
[`Symbol`] + `Span`（即一个被替换的字符串+健全性数据）


[`Symbol`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/symbol/struct.Symbol.html
[scd]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/hygiene/struct.SyntaxContextData.html
[scdp]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/hygiene/struct.SyntaxContextData.html#structfield.parent
[sc]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/hygiene/struct.SyntaxContext.html
[scdoe]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/hygiene/struct.SyntaxContextData.html#structfield.outer_expn
[am]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/hygiene/struct.SyntaxContext.html#method.apply_mark

对于内置宏，我们使用 `SyntaxContext::empty().apply_mark(expn_id)` 上下文，这样的宏是被认为是定义在 root 层次结构纸上。我们为 proc-macros 做一样的事，因为我们还没有实现跨 crate 并保证其卫生（hygiene）。

如果 token 在宏生成之前有上下文 `X` ，那么在宏生成后上下文会有 `X -> macro_id`。以下是一些例子：

Example 0:

```rust,ignore
macro m() { ident }

m!();
```
这里 `ident` 有最初的上下文 [`SyntaxContext::root()`][scr]。在 `m` 生成后，`ident` 会有上下文 `ROOT -> id(m)`。

[scr]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/hygiene/struct.SyntaxContext.html#method.root


Example 1:

```rust,ignore
macro m() { macro n() { ident } }

m!();
n!();
```

这个例子中，`ident` 有最初的 `ROOT`  ，在第一个宏被展开后上下文变为 ` ROOT -> id(m)` ，继续展开后得到上下文 `ROOT -> id(m) -> id(n)`。

Example 2:

注意，这些链并不完全由他们最后的一个元素决定，换句话来说 `ExpnId` 和 `SyntaxContext` 不是同构的。

```rust,ignore
macro m($i: ident) { macro n() { ($i, bar) } }

m!(foo);
```

在所有展开后，`foo` 有上下文 `ROOT -> id(n)` ，`bar` 有上下文
`ROOT -> id(m) -> id(n)`。

最后要提的一点是，目前的结构层次受限于 ["context transplantation hack"][hack] 。基本上，更现代（实现性的）宏（`macro`） 比旧的 MBE 系统有更强的卫生（hygiene）性，但这可能导致两者之间奇怪的交互。这种 hack 实现是为了让所有事暂时“正常工作”。

[hack]: https://github.com/rust-lang/rust/pull/51762#issuecomment-401400732

### 调用的结构层次

第三也是最后一个，结构层次是跟踪宏调用的位置。

在结构层次 [`ExpnData::call_site`][callsite] 中是 子节点 -> 父节点 的链接。

[callsite]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/hygiene/struct.ExpnData.html#structfield.call_site

这里有一个例子：

```rust,ignore
macro bar($i: ident) { $i }
macro foo($i: ident) { $i }

foo!(bar!(baz));
```

对于 `baz` AST 节点是最后输出的，第一个结构层次是 `ROOT ->
id(foo) -> id(bar) -> baz` ，而第三结构层次是 `ROOT -> baz`。

### 宏回溯

在 [`rustc_span`] 中实现了宏回溯，其使用了 [`rustc_span::hygiene`][hy] 的健全机制。

[`rustc_span`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/index.html

## 产生宏输出

上述内容中我们看到了中的宏的输出如何被集成到用于 crate 的 AST 中，我们还看到了如何为一个 crate 生成卫生（hygiene）数据。但是我们如何实际产生一个宏的输出呢？这将取决于宏的类型。

Rust 中有两种类型的宏：`macro_rules!` 类型（或称 示例宏（ Macros By Example,MBE））和过程宏（procedural macros）（或 proc macros;包括自定义派生）。在解析阶段，正常的 Rust 解析器将保留宏及其调用内容。稍后将使用这部分代码将宏展开。

这里有一些重要的数结构和接口：
- [`SyntaxExtension`] - 一个更底层的宏表示，包含了它扩展函数，他将一个 token 流（`TokenStream`）或 AST 转换成另一个 `TokenStream` 或 AST 加上一些额外信息，例如稳定性，或在宏内允许使用的不稳定特性的列表。
- [`SyntaxExtensionKind`] - 展开方法可能会有很多不同的函数签名（接受一个 token 流，或者两个；或者接受一部分 AST 等等）。这是一个列出他们的枚举。
- [`ProcMacro`]/[`TTMacroExpander`]/[`AttrProcMacro`]/[`MultiItemModifier`] - traits 用于标识展开函数的签名

[`SyntaxExtension`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/base/struct.SyntaxExtension.html
[`SyntaxExtensionKind`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/base/enum.SyntaxExtensionKind.html
[`ProcMacro`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/base/trait.ProcMacro.html
[`TTMacroExpander`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/base/trait.TTMacroExpander.html
[`AttrProcMacro`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/base/trait.AttrProcMacro.html
[`MultiItemModifier`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/base/trait.MultiItemModifier.html

## 示例宏（Macros By Example）

MBEs 有自己等等解析器，不同于普通的 Rust 解析器。当宏展开时，我们可以调用 MBE 解析器去解析和展开宏。反过来，MBE 解析器在解析宏调用的内容时需要绑定元变量（例如`$my_expr`），这可能会调用普通的 Rust 解析器。宏展开的代码在 [`compiler/rustc_expand/src/mbe/`][code_dir]

### 示例

有个例子供参考提供是有助的。在本章的其他部分，每当我们提到 "示例 _定义_" 时，我们指得失以下内容：

```rust,ignore
macro_rules! printer {
    (print $mvar:ident) => {
        println!("{}", $mvar);
    };
    (print twice $mvar:ident) => {
        println!("{}", $mvar);
        println!("{}", $mvar);
    };
}
```

`$mvar` 是一个 _元变量_ 。与正常的变量不同，元变量不是绑定到计算中的值，而是在 _编译时_ 绑定到 _tokens_ 树。 _token_ 是一个单独的语法“单元”，例如标识符（例 `foo`）或者标点符号（例 `=>`）。还有其他特殊的 tokens，例如  `EOF` 他表示没有其他更多的 tokens。Token 树由类似成对的圆括号的字符(`(`...`)`,
`[`...`]`, 和 `{`...`}`) - 他们包括了 open 和 close，以及它们之间的所有标记（我们确实要求类似括号的字符需要保持要平衡）。让宏展开操作 token 流而不是源文件的原始字节，从而减少复杂性。宏扩展器（以及编译器的其余大多数）实际上并不十分在乎代码中某些语法构造的确切行和列。它只关心代码中使用了哪些构造。使用 tokens 使得我们可以关心 _什么_ 而不必担心在 _哪里_ ，关于 tokens 跟多内容，可以参考本书 [Parsing][parsing] 一章。

当我们提到 “示例 _调用_” ，我们指以下代码片段：

```rust,ignore
printer!(print foo); // Assume `foo` is a variable defined somewhere else...
```

将宏调用展开为语法树的过程 `println!("{}", foo)` ，然后展开成 
`Display::fmt` 调用成为 _宏展开_ ，是本章的主题。

###  示例宏 （MBE） 解析器

MBE 展开包括两个部分：解析定义和解析调用。有趣的是，两者都是由宏解析器完成的。

基本上，MBE 解析器类似于基于 NFA 的正则解析器。它使用的算法本质上类似于 [Earley parsing
algorithm](https://en.wikipedia.org/wiki/Earley_parser) 。 宏解析器定义在 [`compiler/rustc_expand/src/mbe/macro_parser.rs`][code_mp]。

宏解析器的接口如下（稍作简化）：

```rust,ignore
fn parse_tt(
    parser: &mut Cow<Parser>,
    ms: &[TokenTree],
) -> NamedParseResult
```

我们在宏解析器中使用这些项：
- `parser` 是一个对普通 Rust 解析器的引用，包括了 token 流和解析会话（parsing session）。Token 流是我们将请求 MBE 解析器解析的内容。我们将使用原始的 token 流，将元变量绑定到对应的 token 树。解析会话（parsing session）可用于报告解析器错误。
- `ms` 是一个 _匹配器_ 。这是一个 token 树序列，我们希望以此来匹配 token 树。

类似于正则解析器，token 流是输入，我们将其与 pattern `ms` 匹配。使用我们的示例，token 流可以是包含示例 _调用_ `print foo` 内部的 token 流，`ms` 可以是 token（树）`print $mvar:ident`。

解析器的输出是 `NamedParseResult`，它指示发生了三种情况中的哪一种：
- 成功：token 流匹配给定的匹配器 `ms`，并且我们已经产生了从元变量到响应令牌树的绑定。
- 失败：token 流与 `ms` 不匹配。浙江导致出现错误消息，例：“No rule expected token _blah_”
- 错误： 解析器中发生了一些致命的错误。例如，如果存在多个模式匹配，则会发生这种情况，因为这表明宏不明确。

所有的接口定义在 [这里][code_parse_int]。

宏解析器的工作与普通的正则解析器几乎相同，只有一个例外：为了解析不通的元变量，例如`ident`, `block`, `expr` 等，宏解析器有时候必须回调到普通的 Rust 解析器。

如上所述，宏的定义和调用都使用宏解析器进行解析。这是非常不直观和自引用的。
解析宏的代码定义在 [`compiler/rustc_expand/src/mbe/macro_rules.rs`][code_mr] 中。它定义用于匹配宏定义模式为 `$( $lhs:tt => $rhs:tt );+` 。换句话说，一个 `macro_rules` 定义在其主体中应最少出现一个 token 树，后面跟着 `=>`，然后是另一个 token 树。当编译器遇到 `macro_rules` 定义时，它使用这个模式来匹配定义中每个规则的两个 token 树， _并使用宏解析器本身_ 。在示例定义中，元变量 `$lhs` 将会匹配 partten `(print $mvar:ident)` 和 `(print twice $mvar:ident)`。 `$rhs` 将匹配 `{ println!("{}", $mvar); }` 和 `{
println!("{}", $mvar); println!("{}", $mvar); }` partten 的主体。解析器将保留这些内容，以便在需要展开宏调用时使用。

当编译器遇到宏调用时，它会使用上述基于 NFA 的宏解析器解析该调用。但是，使用的匹配器是从宏定义的 arms 中提取的第一个 token 树（`$lhs` ），使用我们的示例，我们尝试匹配 token 流中的 `print foo` （来自匹配器的） `print $mvar:ident` 和从前面定义中提取的 `print twice $mvar:ident`。算法是完全相同的，但是当宏解析器在当前匹配其中需要匹配非 _non-terminal_  (例如 `$mvar:ident`) 时，它会回调正常的 Rust 解析器以获取该非终结符的内容。这种情况下，Rust 会寻找一个 `ident` token，它会找到 `foo` 并返回给宏解析器。然后，宏解析器照常进行解析。另外，请注意来自于不同 arms 的匹配器应该恰好有一个匹配调用；如果有多个匹配项，则该解析有二义性，而如果根本没有匹配项，则存在语法错误。

跟多关于解析器实现的信息请参考 [`compiler/rustc_expand/src/mbe/macro_parser.rs`][code_mp]

### `macro`s and Macros 2.0

改进 MBE 系统，为它提供更多与卫生（hygiene）性相关的功能，更好的范围和可见性规则等，这是一个古老的，几乎没有文献记载的工作。不幸的是，最近在这方面还没有进行很多工作。 在内部，宏使用与当今的 MBE 相同的机制。 它们只是具有附加的语法糖，并且允许在名称空间中使用。

## 过程（Procedural）宏

如上所述，过程宏也在解析过程中进行了扩展。 但是，它们使用了一种完全不同的机制。 过程宏不是作为编译器中的解析器，而是作为自定义的第三方 crate 实现的。 编译器将在其中编译 proc macro crate 和带有特殊注释的函数（即 proc macro 本身），并向它们传递 tokens 流。

然后 proc macro 可以转换 token 流和输出新的 token 流，该 token 流被合称为 AST。

值得注意的是，proc macros 使用的 token 流类型是 _稳定的_ ，因此`rustc` 不在内部使用它（因为内部数据结构是不稳定的）。 像以前一样，编译器的 token 流为 [`rustc_ast::tokenstream::TokenStream`][rustcts]。 这将转换为稳定的 [`proc_macro::TokenStream`][stablets] 并返回 [`rustc_expand::proc_macro`][pm] 和[`rustc_expand::proc_macro_server`][pms] 。 因为 Rust ABI 不稳定，所以我们使用 C ABI 进行转换。


[tsmod]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_ast/tokenstream/index.html
[rustcts]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_ast/tokenstream/struct.TokenStream.html
[stablets]: https://doc.rust-lang.org/proc_macro/struct.TokenStream.html
[pm]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/proc_macro/index.html
[pms]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_expand/proc_macro_server/index.html

TODO: more here.

### Custom Derive

自定义派生是 proc macro 的一种特殊类型。 

TODO: more?
