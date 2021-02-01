# 示例：通过 `rustc_interface` 获取诊断信息

`rustc_interface` 允许您拦截将被打印到 stderr 的诊断信息。

## 获取诊断信息

要从编译器获取诊断信息，请配置 `rustc_interface::Config` 将诊断信息输出到一个缓冲区，然后运行 `TyCtxt.analysis` ：

```rust
// 完整程序见 https://github.com/rust-lang/rustc-dev-guide/blob/master/examples/rustc-driver-getting-diagnostics.rs 。
let buffer = sync::Arc::new(sync::Mutex::new(Vec::new()));
let config = rustc_interface::Config {
    opts: config::Options {
        // 将编译器配置为以紧凑的JSON格式发出诊断信息。
        error_format: config::ErrorOutputType::Json {
            pretty: false,
            json_rendered: rustc_errors::emitter::HumanReadableErrorType::Default(
                rustc_errors::emitter::ColorConfig::Never,
            ),
        },
        /* 其他配置 */
    },
    // 重定向编译器的诊断信息输出到一个缓冲区。
    diagnostic_output: rustc_session::DiagnosticOutput::Raw(Box::from(DiagnosticSink(
        buffer.clone(),
    ))),
    /* 其他配置 */
};
rustc_interface::run_compiler(config, |compiler| {
    compiler.enter(|queries| {
        queries.global_ctxt().unwrap().take().enter(|tcx| {
            // 在本地 crate 上运行分析阶段以触发类型错误。
            tcx.analysis(rustc_hir::def_id::LOCAL_CRATE);
        });
    });
});
// 读取缓冲区中的诊断信息。
let diagnostics = String::from_utf8(buffer.lock().unwrap().clone()).unwrap();
```
