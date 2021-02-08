# 关于

本指南旨在记录rustc（Rust编译器）的工作方式，并帮助新的开发者参与到rustc的开发中来。

本指南分为六个部分:

1. [构建和调试 `rustc`][p1]: 包含有关构建，调试，性能分析等方面的有用信息，无论您以何种方式进行贡献。
2. [为 `rustc`做贡献][p1-5]: 包含有关贡献代码的步骤，稳定功能等方面有用的信息，无论您以何种方式进行贡献。
2. [编译器架构概要][p2]: 讨论编译器的高级架构和编译过程的各个阶段。
3. [源码表示][p3]: 描述了获取用户的代码，并将其转换为编译器可以使用的各种形式的过程。
4. [静态分析][p4]: 讨论编译器如何分析代码，从而能够检查代码的各种属性并告知编译过程的后续阶段（例如，类型检查）。
5. [从MIR到二进制][p5]: 如何连接生成的可执行机器码。
6. [附录][app]: 在本指南的结尾提供了一些有关的参考信息，如词汇表、推荐书目等。

[p1]: ./getting-started.md
[p1-5]: ./compiler-team.md
[p2]: ./part-2-intro.md
[p3]: ./part-3-intro.md
[p4]: ./part-4-intro.md
[p5]: ./part-5-intro.md
[app]: ./appendix/background.md

### 持续更新

请记住，这 `rustc` 是一种真正的生产质量管理工具，由大量的贡献者不断进行研究贡献。因此，它有相当一部分代码库变更和技术上的欠缺。此外，本指南中讨论的许多想法都是尚未完全实现的理想化设计。所有这些使本指南在所有方面都保持最新，这非常困难！

该指南本身当然也是开源的，可以在[GitHub存储库]中找到这些源(译者注: 这里的Github存储库为此文档的英文原文链接)。
如果您在指南中发现任何错误，请提出相关问题，甚至更好的是，打开带有更正的PR！

如果您想要为本指南(译者注: 指英文版)作出帮助，请参阅本指南中。
[有关编写文档的相应小节].

[有关编写文档的相应小节]: contributing.md#contributing-to-rustc-dev-guide

> “‘All conditioned things are impermanent’ — when one sees this with wisdom, one turns away from
> suffering.” _The Dhammapada, verse 277_

## 其他查找信息的网站

以下站点可能对你有所帮助：

- [rustc API docs] -- 编译器的rustdoc文档。
- [Forge] -- 包含有关Rust的补充文档。
- [compiler-team] -- rust编译器团队的主页，描述了了开发的过程，活动工作组，团队日历等。

[GitHub存储库]: https://github.com/rust-lang/rustc-dev-guide/
[rustc API docs]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/
[Forge]: https://forge.rust-lang.org/
[compiler-team]: https://github.com/rust-lang/compiler-team/
