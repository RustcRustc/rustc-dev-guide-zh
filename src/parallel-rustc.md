# 并行编译

大多数编译器都不是并行的，这是一个提高编译器性能的机会。

截止<!-- date: 2021-01 --> 2021 年 1 月，用于显式并行化编译器的工作已停止。有很多设计和正确性的工作需要完成。

可以在 `config.toml` 中启用它来尝试当前的并行编译器工作。

这项工作有一些基本思路：

- 编译器中有很多循环，它们只是迭代一个 crate 中的所有项，。这些都可能可以并行化。
- 我们可以使用(一个自定义分支) [`rayon`] 并行运行任务。自定义分支允许执行 DAG 任务，而不仅仅是树。
- 目前有许多全局数据结构需要设置为线程安全的。这里的一个关键策略是将内部可变的数据结构(如: Cell) 转换为与它们同级的线程安全结构(如: Mutex)。

[`rayon`]: https://crates.io/crates/rayon

截至<!-- date: 2021-02 --> 2021 年 2 月，由于人力不足，大部分这方面的努力被搁置。我们有一个可以正常工作的原型，在许多情况下都有很好的性能收益。然而，有两个障碍：

- 目前尚不清楚哪些并发需要保持不变的不变性。审核工作正在进行中，但似乎已停滞不前。

- 有很多锁竞争，随着线程数增加到 4 以上，实际上会降低性能。

这里有一些可以用来学习更多的资源(注意其中一些有点过时了)：

- [Zoxc 的 IRLO 线程，这项工作的先驱之一][irlo0]
- [nikomatsakis 在编译器中列出的内部可变性][imlist]
- [alexchricton 关于 IRLO 线程的性能][irlo1]
- [跟踪该问题][tracking]

[irlo0]: https://internals.rust-lang.org/t/parallelizing-rustc-using-rayon/6606
[imlist]: https://github.com/nikomatsakis/rustc-parallelization/blob/master/interior-mutability-list.md
[irlo1]: https://internals.rust-lang.org/t/help-test-parallel-rustc/11503
[tracking]: https://github.com/rust-lang/rust/issues/48685