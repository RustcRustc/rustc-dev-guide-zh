# Syntax and the AST
直接使用源代码（source code）是非常不舒服和容易出错的，因此在我们做任何事之前，我们需要将源代码（raw source code）转换成抽象语法树（AST）。事实证明，即使我们这样这样做，仍需要做大量的工作，包括包括词法分析（lexing），解析（parsing），宏扩展（macro expansion），名称解析（name resolution），条件编译（conditional compilation），功能门检查（feature-gate checking）和抽象语法树的验证（validation of the AST）。

值得注意的是，这些工作之间并不总是有明确顺序的。例如，宏扩展（macro expansion）依赖于名称解析（name resolution）来解析宏的名称和导入的名称。且解析（parsing）需要宏扩展（macro expansion），这又可能需要解析宏的输出（output of the macro）。