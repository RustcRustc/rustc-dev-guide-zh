# Rustdoc 内部工作原理

<!-- toc -->

本页介绍了 rustdoc 的 pass 和模式。有关rustdoc的概述，
请参阅[“Rustdoc概述”一章](./rustdoc.md)。

## 从 crate 到 clean

在 core.rs 中有两个主要项目：`DocContext` 结构和 `run_core` 函数。
后者会让 `rustdoc` 调用 `rustc` 将 crate  编译到 `rustdoc` 可以接手的地步。
前者是状态容器，用于在 crate 中爬取信息时收集其文档。

crate 爬取的主要过程是通过几个在 `clean/mod.rs` 中的 `Clean` trait 实现完成的。
`Clean` trait 是一个转换 trait，它定义了一个方法：

```rust,ignore
pub trait Clean<T> {
    fn clean(&self, cx: &DocContext) -> T;
}
```

`clean/mod.rs` 还定义了稍后用于渲染文档页面的 “clean 过的” AST 类型。
通常，对于每个 `Clean` 的实现，都会从 rustc 中获取一些 AST 或 HIR 类型，
并将其转换为适当的“clean 过的”的类型。
更“大型”的构造（例如模块或相关项目）可能会在其 `Clean` 实现中进行一些额外的处理，
但是在大多数情况下，这些实现都是直接的转换。
该模块的入口是 `impl Clean<Crate> for visit_ast::RustdocVisitor`，由上面的 `run_core` 调用。

您看，我实际上前面撒了一点小谎：
在 `clean/mod.rs` 中的事件发生之前，还有另一个AST转换。
在 `visit_ast.rs` 中的 `RustdocVisitor` 类型*实际上*抓取了一个
`rustc_hir::Crate` 以获取第一个中间表示形式，
该中间表示形式在 `doctree.rs` 中定义。
此过程主要是为了获得有关 HIR 类型的一些中间包装，并处理可见性和内联。
这是处理 `#[doc(inline)]`、 `#[doc(no_inline)]` 和 `#[doc(hidden)]` 的地方，
以及决定 pub use 是否应该渲染为一整页还是模块页面中的“Reexport”行。

在 `clean/mod.rs` 中发生的另一件主要事情是将 doc 注释和 `#[doc=""]` 属性收集到 Attributes 结构的单独字段中，
这个字段出现在任何需要手写文档的地方。这使得之后容易收集此文档。

该过程的主要输出是一个 `clean::Crate`，其中有一个项目树描述了目标 crate 中有公开文档的项目。

### Hot potato

在继续进行下一步之前，在文档会上有一些重要的“pass”。
这些操作包括将单独的“属性”组合为单个字符串并去除前导空格，
以使文档能更容易地被 markdown 解析器解析，
或者删除未公开的项目或使用 `#[doc(hidden)]` 故意隐藏的项目。
这些都在 `passes/` 目录中实现，每文件一个 pass。
默认情况下，所有这些 pass 都会在 crate 进行，
但是与私有/隐藏的条目有关的 pass 可以通过将 `--document-private-items` 传入 rustdoc来绕过。
请注意，与之前的 AST 转换组不同，这些 pass 是在 _cleaned_ crate 上运行的。

（严格来说，您可以微调 pass 甚至添加自己的pass，但是[我们正在尝试 deprecate 这种行为][44136]。
如果您需要对这些 pass 进行更细粒度的控制，请告诉我们！）

[44136]: https://github.com/rust-lang/rust/issues/44136

以下是截至 <!-- date: 2021-02 --> 2021年2月的 pass 列表：

- `calculate-doc-coverage` 计算 `--show-coverage` 使用的信息。

- `check-code-block-syntax` 验证 Rust 代码块的语法
  （`` ```rust ``）

- `check-invalid-html-tags` 检测 doc comments 中的不合法 HTML（如没有被正确关闭的 `<span>`）。

- `check-non-autolinks` 检测可以或者应该使用尖括号写的链接 （这些代码应该由 nightly-only<!-- date: 2021-02 --> 的 lint 选项 `non_autolinks` 开启）。

- `collapse-docs` 将所有文档 attributes 拼接成一个文档 attribute。
  这是必须的，因为每行文档注释都是单独的文档 attribute，`collapse-docs` 会将它们合并成单独的一个字符串，其中每个 attribute 之间都有换行符连接。

- `collect-intra-doc-links` 解析 [intra-doc links](https://doc.rust-lang.org/rustdoc/linking-to-items-by-name.html)。

- `collect-trait-impls` 为 crate 中的每个项目收集 trait 提示。
  例如，如果我们定义一个实现 trait 的结构，则此过程将注意到该结构实现了该 trait。

- `doc-test-lints` 在 doctests 上运行各种 lint。

- `propagate-doc-cfg` 将 `#[doc(cfg(...))]` 传递给子 item。

- `strip-priv-imports` 删去所有私有导入语句（`use`、 `extern crate`）。
  这是必需的，因为 rustdoc 将通过将项目的文档内联到模块中或创建带有导入的 “Reexport” 部分来处理 *公有* 导入。
  这个 pass 保证了这些导入能反应在文档上。

- `strip-hidden` 和 `strip-private` 从输出中删除所有 `doc(hidden)` 和 私有 item。
  `strip-private` 包含了 `strip-priv-imports`。基本上，目标就是移除和公共文档无关的 item。

- `unindent-comments` 移除了注释中多余的缩进，以使得 Markdown 能被正确地解析。
  这是必需的，因为编写文档的约定是在 `///` 或 `//!` 标记与文档文本之间空一格，但是 Markdown 对空格敏感。
  例如，具有四个空格缩进的文本块会被解析为代码块，因此如果我们不移除注释中的缩进，这些列表项

  ```rust,ignore
  /// A list:
  ///
  ///    - Foo
  ///    - Bar
  ```
  
  会被违反用户期望地解析为代码块。

`passes/` 中也有一个 `stripper` 模块，但其中是一些 `strip-*` pass 使用的工具函数，它并非是一个 pass。

## 从 clean 到 crate

这是 rustdoc 中“第二阶段”开始的地方。
这个阶段主要位于 `html/` 文件夹中，并且以 `html/render.rs` 中的 `run()` 开始。
该代码在渲染这个 crate 的所有文档前会负责设置渲染期间使用的 `Context`、`SharedContext` 和 `Cache`，
并复制每个渲染文档集中的静态文件（字体，CSS 和 JavaScript 等保存在 `html/static/` 中的文件），
创建搜索索引并打印出源代码渲染。

直接在 `Context` 上实现的几个函数接受 `clean::Crate` 参数，
并在渲染项或其递归模块子项之间建立某种状态。
从这里开始，通过 `html/layout.rs` 中的巨大 `write!()` 调用，开始进行“页面渲染”。
从项目和文档中实际生成HTML的部分发生在一系列 `std::fmt::Display` 实现和接受 `&mut std::fmt::Formatter` 的函数中。
写出页面正文的顶层实现是 `html/render.rs` 中的 `impl <'a> fmt::Display for Item <'a>`，
它会基于被渲染的 `Item` 调用多个 `item_*` 之一。

根据您要查找的渲染代码的类型，您可能会在 `html/render.rs` 中找到主要项目，
例如 “结构体页面应如何渲染” 或者对于较小的组件，对应项目可能在 `html/format.rs` 中，
如“我应该如何将 where 子句作为其他项目的一部分进行打印”。

每当 rustdoc 遇到应在其上打印手写文档的项目时，
它就会调用 `html/markdown.rs` 中的与 Markdown 部分的接口。
其中暴露了一系列包装了字符串 Markdown 的类型，
并了实现 `fmt::Display` 以输出 HTML 文本。
在运行 Markdown 解析器之前，要特别注意启用某些功能（如脚注和表格）并在 Rust 代码块中添加语法高亮显示（通过 `html/highlight.rs`）。
这里还有一个函数（`find_testable_code`），
该函数专门扫描Rust代码块，以便测试运行程序代码可以在 crate 中找到所有 doctest。

### 从 soup 到 nuts

(另一个标题： ["An unbroken thread that stretches from those first `Cell`s to us"][video])

[video]: https://www.youtube.com/watch?v=hOLAGYmUQV0

重要的是要注意，AST 清理可以向编译器询问信息
（至关重要的是，`DocContext` 包含 `TyCtxt`），
但是页面渲染则不能。在 `run_core` 中创建的 `clean::Crate` 在传递给
`html::render::run` 之前传递到编译器上下文之外。
这意味着，在项目定义内无法立即获得的许多“补充数据”，
例如哪个 trait 是语言使用的 `Deref` trait，需要在清理过程中收集并存储在 `DocContext` 中，
并在 HTML 渲染期间传递给 `SharedContext`。
这表现为一堆共享状态，上下文变量和 `RefCell`。

还要注意的是，某些来自“请求编译器”的项不会直接进入 `DocContext` 中 —— 
例如，当从外部 crate 中加载项时，
rustdoc 会询问 trait 实现并基于该信息生成新的 `Item`。
它直接进入返回的 `Crate`，而不是通过 `DocContext`。
这样，就可以在呈现 HTML 之前将这些实现与其他实现一起收集。 

## 其他技巧

所有这些都描述了从 Rust crate 生成HTML文档的过程，
但是 rustdoc 可以以其他几种主要模式运行。
它也可以在独立的 Markdown 文件上运行，也可以在 Rust 代码或独立的 Markdown 文件上运行 doctest。
对于前者，它直接调用 `html/markdown.rs`，可以通过选项将目录插入到输出 HTML 的模式。

对于后者，rustdoc 运行类似的部分编译以获取在 `test.rs` 中的文档的相关信息。 
但是它并不经过完整的清理和渲染过程，而是运行了一个简单得多的 crate walk，仅抓取手写的文档。
与上述 `html/markdown.rs` 中的 `find_testable_code` 结合，它会建立一组要运行的测试，然后再将其交给测试运行器。
`test.rs` 中一个值得注意的的位置是函数 `make_test`，在该函数中，手写 `doctest` 被转换为可以执行的东西。

可以[在这里](https://quietmisdreavus.net/code/2018/02/23/how-the-doctests-get-made/)找到一些关于 `make_test` 的更多信息。

## Dotting i's and crossing t's

所以简而言之，这就是rustdoc的代码，但是 repo 中还有很多事情要处理。
由于我们手头有完整的 `compiletest` 套件，因此在 `src/test/rustdoc` 中有一组测试可以确保最终的 HTML 符合我们在各种情况下的期望。
这些测试还使用了补充脚本 `src/etc/htmldocck.py`，
该脚本允许它使用 XPath 表示法浏览最终的 HTML，以精确查看输出结果。
rustdoc测试可用的所有命令的完整说明（例如 [`@has`] 和 [`@matches`]）位于 [`htmldocck.py`] 中。

要在 rustdoc 测试中使用多个 crate，请添加 `// aux-build:filename.rs`
到测试文件的顶部。应该将 `filename.rs` 放置在相对于带有注释的测试文件的 `auxiliary` 目录中。
如果您需要为辅助文件构建文档，请使用 `// build-aux-docs`。

此外，还有针对搜索索引和 rustdoc 查询它的能力的独立测试 。
`src/test/rustdoc-js` 中的文件每个都包含一个不同的搜索查询和预期结果（按“搜索”标签细分）。
这些文件由 `src/tools/rustdoc-js` 和 Node.js 运行时中的脚本处理。
这些测试没有详尽的描述，但是可以在 `basic.js` 中找到一个包含所有选项卡结果的宽泛示例。
基本思想是，将给定的 `QUERY` 与一组 `EXPECTED` 结果相匹配，并附上每个 item 的完整路径。

[`htmldocck.py`]: https://github.com/rust-lang/rust/blob/master/src/etc/htmldocck.py
[`@has`]: https://github.com/rust-lang/rust/blob/master/src/etc/htmldocck.py#L39
[`@matches`]: https://github.com/rust-lang/rust/blob/master/src/etc/htmldocck.py#L44

## 本地测试

生成的 HTML 文档的某些功能可能需要跨页面使用本地存储，如果没有 HTTP 服务器，这将无法正常工作。
要在本地测试这些功能，可以运行本地 HTTP 服务器，如下所示： 

```bash
$ ./x.py doc library/std --stage 1
# The documentation has been generated into `build/[YOUR ARCH]/doc`.
$ python3 -m http.server -d build/[YOUR ARCH]/doc
```

现在，您可以像浏览 Internet 上的文档一样浏览本地文档。 例如，`std` 的网址将是 `/std/`。

## See also

- [`rustdoc` api docs]
- [An overview of `rustdoc`](./rustdoc.md)
- [The rustdoc user guide]

[`rustdoc` api docs]: https://doc.rust-lang.org/nightly/nightly-rustc/rustdoc/
[The rustdoc user guide]: https://doc.rust-lang.org/nightly/rustdoc/