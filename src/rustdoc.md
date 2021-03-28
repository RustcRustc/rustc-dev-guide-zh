# Rustdoc 概述

Rustdoc 实际上直接使用了 rustc 的内部功能。
它与编译器和标准库一起存在于代码树中。
本章是关于它如何工作的。
有关Rustdoc功能及其使用方法的信息，请参见 [Rustdoc book](https://doc.rust-lang.org/nightly/rustdoc/)。
有关rustdoc如何工作的更多详细信息，请参见 [“Rustdoc 内部工作原理” 一章]。

[“Rustdoc 内部工作原理” 一章]：./rustdoc-internals.md

Rustdoc 完全在 [`librustdoc`][rd] crate 中实现。
它可以运行编译器来获取 crate 的内部表示（HIR），
以及查询项目类型的一些信息。
[HIR] 和 [查询] 在相应的章节中进行了讨论。

[HIR]: ./hir.md
[queries]: ./query.md
[rd]: https://github.com/rust-lang/rust/tree/master/src/librustdoc

`librustdoc` 主要执行两个步骤来渲染一组文档：

* 将 AST “清理”为更适合于创建文档的形式（并且稍微更耐编译器中的“搅动”）。
* 使用此清理后的 AST 一次渲染一个 crate 的文档。

当然实际上并不仅限于此，这样描述简化了许多细节，但这只是一个高层次的概述。

（注意：`librustdoc` 是一个库 crate！
"rustdoc" 二进制文件是使用 [`src/tools/rustdoc`][bin] 
中的项目创建的。注意所有上述操作都是在 `librustdoc` crate 的 `lib.rs` 中的 `main` 函数中执行的。）

[bin]: https://github.com/rust-lang/rust/tree/master/src/tools/rustdoc

## Cheat sheet

* 使用 `./x.py build` 制作一个可以在其他项目上运行的 rustdoc。
  * 添加 `library/test` 之后才能使用 `rustdoc --test`。
  * 如果您以前使用过 `rustup toolchain link local /path/to/build/$TARGET/stage1`，则在执行上一个构建命令后，`cargo +local doc` 将可以正常工作。
    
* 使用 `./x.py doc --stage 1 library/std` 来用这个 rustdoc 来生成标准库文档。
  * 生成的文档位于 `build/$TARGET/doc/std`, 但这个生成出来的 bundle 期望你将其从 `doc` 文件夹拷贝到一个 web 服务器上，以便首页和 CSS/JS 可以正常加载。
    
* 使用 `x.py test src/test/rustdoc*` 来用 stage1 rustdoc 运行测试。
  * 参见 [“Rustdoc 内部工作原理” 一章] 来了解更多和测试有关的信息。

* 大多数 HTML 打印代码位于 `html/format.rs` 和 `html/render.rs`中。
  它主要由一堆 `fmt::Display` 实现和补充函数构成。
  
* 上面实现了 `Display` 的类型是在 `clean/mod.rs` 中定义的，
  就在自定义 `Clean` trait 旁边，该 trait 用于将这些类型的对象从 rustc HIR 中提取出来。

* 使用 rustdoc 进行测试的代码在 `test.rs` 中。

* Markdown 渲染器位于 `html/markdown.rs` 中，包括用于从给定的 Markdown 块中提取文档测试的功能。

* rustdoc *输出* 上的测试位于 `src/test/rustdoc` 中，由 rustbuild 的测试运行器和补充脚本 `src/etc/htmldocck.py` 处理。

* 搜索索引生成的测试位于 `src/test/rustdoc-js` 中，是一系列 JavaScript 文件，用于对标准库搜索索引和预期结果的查询进行编码。 