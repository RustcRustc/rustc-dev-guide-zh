# 分析（lexing）和解析（parsing）

 <!-- date: 2021-01 --> 2021年一月，词法分析器（lexer）和解析器（parser）正在进行重构， 以允许将它们提取到库（libraries）中。

编译器要做的第一件事是将程序（Unicode字符）转换为比字符串更方便编译器使用的内容。这发生在词法分析（lexing）和解析（parsing）阶段。

词法分析（lexing）接受字符串并将其转换成  [tokens] 流（streams of tokens）。例如，
`a.b + c` 会被转换成 tokens `a`, `.`, `b`, `+`, `c` 。该词法分析器（lexer）位于 
[`rustc_lexer`] 中。

[tokens]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_ast/token/index.html
[lexer]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_lexer/index.html

解析（Parsing）接受 [tokens] 流（streams of tokens）并将其装换位结构化的形式，这对于编译器来说更加容易使用，通常成为抽象语法树([*Abstract
Syntax Tree*][ast],AST)。AST 镜像内存中的Rust 程序的结构（structure），使用 `Span` 将特定的 AST 节点链接（link）回其源文本。

在 [`rustc_ast`][rustc_ast] 中定义了 AST ,此外还有一些关于 tokens 和 tokens 流（tokens and token streams）的定义，用于变异的（mutating） ASTs 数据结构/特征（traits），以及用于编译器的其他 AST 相关部分的共享定义（如词法分析器和宏扩张）。

解析器（parser）是在 [`rustc_parse`][rustc_parse] 中定义的，以及词法分析器（lexer）的高级接口和在宏展开后运行的一些验证例行程序。特别是，[`rustc_parse::parser`][parser] 包含了解析器（parser）的实现

解析器的主入口是通过各种在 [parser crate][parser_lib] 中的`parse_*`函数和其他函数。它们允许你将[`SourceFile`][sourcefile]（例如单个文件的源文件）转换为 token 流（token stream ），从 token 流（token stream ）创建解析器（parser），然后执行解析器（parser）去获得一个`Crate`（AST 的 root 节点）

为了减少复制的次数，`StringReader` 和 `Parser` 的生命周期都绑定到父节点 `ParseSess`。它包含了解析时所需要的所有信息以及 `SourceMap` 本身。

注意，在解析时，我们可能遇到宏定义或调用，我们把这些放在一旁以进行展开 (见 [本章](./macro-expansion.md))。展开本身可能需要解析宏的输出，这可能会涉及到更多需要展开的宏，等等。

## 更多源于词法分析（Lexical Analysis）
词法分析的代码被分为两个箱子（crates）：
- `rustc_lexer` crate 负责将 `&str` 分解为组成标记的块。将分析器（lexer）作为生成的有限状态机来实现是很流行的，但`rustc_lexer`重的分析器（lexer）是手写的。

- 来自于 [`rustc_ast`][rustc_ast] 的 [`StringReader`] 将 `rustc_lexer` 与 `rustc` 详细的数据结构集成在一起。具体来说，它将 `Span` 信息添加到  `rustc_lexer` 和 interns 标识符返回的 tokens 中。


[rustc_ast]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_ast/index.html
[rustc_errors]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_errors/index.html
[ast]: https://en.wikipedia.org/wiki/Abstract_syntax_tree
[`SourceMap`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/source_map/struct.SourceMap.html
[ast module]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_ast/ast/index.html
[rustc_parse]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_parse/index.html
[parser_lib]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_parse/index.html
[parser]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_parse/parser/index.html
[`Parser`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_ast/parse/parser/struct.Parser.html
[`StringReader`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_parse/lexer/struct.StringReader.html
[visit module]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_ast/visit/index.html
[sourcefile]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/struct.SourceFile.html
