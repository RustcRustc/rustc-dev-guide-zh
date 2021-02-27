# 命令行参数

命令行选项记录在[rustc书][cli-docs]中。所有*稳定*的（命令行）选项都应该记录在这里。 不稳定的选项都应该记录在【不稳定版本的rustc书】中。

如果你想了解添加新的命令行参数的详细过程，请查看【新（命令行）选项创建指南】。

## 指导方针

- 选项应该彼此正交（orthogonal）。举个例子：如果我们有多种触发json变体的行为（`foo`和`bar`），相对于选项`--foo-json`和`--bar-json`，`--json`是更好的选择。
- 避免使用带有`no-`前缀的选项。相反，应该像`-C embed-bitcode=no`一样使用【`parse_bool`】函数。
- 应该考虑选项是否会被传递多次的这种行为。在某些情况下，（命令按照选项处理后的）值应该按照（选项的）顺序进行累计。在其他情况下，后面的选项应该覆盖前面的选项（如：lint级别的选项）。而且当一些选项的含义太过于含糊（例如`-o`），则应该一个生成错误。
- 如果仅仅是为了编译器脚本更容易理解，请始终为选项提供长的描述性名称。
- `--verbose`选项可以给`rustc`输出增加额外的信息。例如：将`--verbose`和`--version`选项一起使用可以提供编译器代码散列的信息。
- 试验性的选项一定要放在`-Z`（代表不稳定的参数选项）的后面。

[cli-docs]: https://doc.rust-lang.org/rustc/command-line-arguments.html
[forge guide for new options]: https://forge.rust-lang.org/compiler/new_option.html
[unstable book]: https://doc.rust-lang.org/nightly/unstable-book/
[`parse_bool`]: https://github.com/rust-lang/rust/blob/e5335592e78354e33d798d20c04bcd677c1df62d/src/librustc_session/options.rs#L307-L313
