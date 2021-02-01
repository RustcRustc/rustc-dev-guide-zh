# 示例：通过 `rustc_interface` 进行类型检查

`rustc_interface` 允许您在编译的各个阶段与 Rust 代码交互。

## 获取表达式的类型

```rust
// 完整程序见 https://github.com/rust-lang/rustc-dev-guide/blob/master/examples/rustc-driver-interacting-with-the-ast.rs 。
let config = rustc_interface::Config {
    input: config::Input::Str {
        name: source_map::FileName::Custom("main.rs".to_string()),
        input: "fn main() { let message = \"Hello, world!\"; println!(\"{}\", message); }"
            .to_string(),
    },
    /* 其他配置 */
};
rustc_interface::run_compiler(config, |compiler| {
    compiler.enter(|queries| {
        // 分析 crate 并检查光标下的类型。
        queries.global_ctxt().unwrap().take().enter(|tcx| {
            // 每次编译包含一个单独的 crate 。
            let krate = tcx.hir().krate();
            // 遍历 crate 中的顶层项，寻找 main 函数。
            for (_, item) in &krate.items {
                // 使用模式匹配在 main 函数中查找特定节点。
                if let rustc_hir::ItemKind::Fn(_, _, body_id) = item.kind {
                    let expr = &tcx.hir().body(body_id).value;
                    if let rustc_hir::ExprKind::Block(block, _) = expr.kind {
                        if let rustc_hir::StmtKind::Local(local) = block.stmts[0].kind {
                            if let Some(expr) = local.init {
                                let hir_id = expr.hir_id; // hir_id 标识字符串 "Hello, world!"
                                let def_id = tcx.hir().local_def_id(item.hir_id); // def_id 标识 main 函数
                                let ty = tcx.typeck(def_id).node_type(hir_id);
                                println!("{:?}: {:?}", expr, ty); // 打印出 expr(HirId { owner: DefIndex(3), local_id: 4 }: "Hello, world!"): &'static str
                            }
                        }
                    }
                }
            }
        })
    });
});
```
