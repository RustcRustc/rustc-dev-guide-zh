# Rustc Driver 和 Rustc Interface

[`rustc_driver`] 本质上是 `rustc` 的 `main()` 函数。它使用 [`rustc_interface`] crate 中定义的接口，按正确顺序运行编译器各个阶段。

`rustc_interface` crate 为外部用户提供了一个（不稳定的）API，用于在编译过程中的特定时间运行代码，从而允许第三方有效地使用 `rustc` 的内部代码作为库来分析 crate 或在进程中模拟编译器（例如 RLS 或 rustdoc ）。

对于那些将 `rustc` 作为库使用的用户，[`rustc_interface::run_compiler()`][i_rc] 函数是编译器的主要入口点。它接受一个编译器配置参数，以及一个接受 [`Compiler`] 参数的闭包。`run_compiler` 从配置中创建一个 `Compiler` 并将其传递给闭包。在闭包内部，您可以使用 `Compiler` 来驱动查询以编译 crate 并获取结果。这也是 `rustc_driver` 所做的。您可以在[这里][example]中看到有关如何使用 `rustc_interface` 的最小示例。

您可以通过 rustdocs 查看 [`Compiler`] 当前可用的查询。您可以通过查看 `rustc_driver` 的实现，特别是 [`rustc_driver::run_compiler` 函数][rd_rc]（不要与 [`rustc_interface::run_compiler`][i_rc] 混淆）来查看如何使用它们的示例。`rustc_driver::run_compiler` 函数接受一堆命令行参数和一些其他配置，并推动编译完成。

`rustc_driver::run_compiler` 还接受一个 [`Callbacks`][cb]，一个允许自定义编译器配置以及允许一些自定义代码在编译的不同阶段之后运行的 trait 。

> **警告：** 本质来说，编译器内部 API 总是不稳定的，但是我们会尽力避免不必要的破坏。

[cb]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_driver/trait.Callbacks.html
[rd_rc]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_driver/fn.run_compiler.html
[i_rc]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_interface/interface/fn.run_compiler.html
[example]: https://github.com/rust-lang/rustc-dev-guide/blob/master/examples/rustc-driver-example.rs
[`rustc_interface`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_interface/index.html
[`rustc_driver`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_driver/
[`Compiler`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_interface/interface/struct.Compiler.html
[`Session`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_session/struct.Session.html
[`TyCtxt`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/struct.TyCtxt.html
[`SourceMap`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_span/source_map/struct.SourceMap.html
[stupid-stats]: https://github.com/nrc/stupid-stats
[Appendix A]: appendix/stupid-stats.html
