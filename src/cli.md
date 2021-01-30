# 命令行参数

命令行参数记录在 [rustc book][cli-docs] 中。 所有*稳定的*参数都应在此处记录。不稳定的参数应记录在 [unstable book] 中。

有关添加新命令行参数的*过程*的详细信息，请参见 [forge guide for new options] 。

## 指南

- 参数应彼此正交。例如，如果我们有多个操作，如 `foo` 和 `bar` ，具有生成 json 的变体，则添加额外的 `--json` 参数比添加 `--foo-json` 和 `--bar-json` 更好。
- 避免使用带有 `no-` 前缀的参数。相反，使用 [`parse_bool`] 函数，比如 `-C embed-bitcode=no` 。
- 考虑参数被多次传递时的行为。在某些情况下，应该（按顺序）累积值。在另一些情况下，后面的参数应覆盖前面的参数（例如，lint-level 参数）。如果多个参数的含义太模糊，那么一些参数（比如 `-o` ）应该生成一个错误。
- 如果仅为了编译器脚本更易于理解，请始终为选项提供长的描述性名称。
- `--verbose` 参数用于向 rustc 的输出中添加详细信息。例如，将其与 `--version` 参数一起使用可提供有关编译器代码哈希值的信息。
- 实验性参数和选项必须放在 `-Z unstable-options` 后面。

[cli-docs]: https://doc.rust-lang.org/rustc/command-line-arguments.html
[forge guide for new options]: https://forge.rust-lang.org/compiler/new_option.html
[unstable book]: https://doc.rust-lang.org/nightly/unstable-book/
[`parse_bool`]: https://github.com/rust-lang/rust/blob/e5335592e78354e33d798d20c04bcd677c1df62d/src/librustc_session/options.rs#L307-L313
