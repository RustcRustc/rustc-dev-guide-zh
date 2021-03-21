# rust 中的 panic

<!-- toc -->

## 步骤1: 调用 `panic!` 宏

实际上有两个 panic 宏 - 一个定义在 `core` 中，一个定义在 `std` 中。这是因为 `core` 中的代码可能 panic。`core` 是在 `std` 之前构建的，但不管是 `core` 或 `std` 中的 panic，我们希望运行时使用相同的机制。

### core 中 panic! 的定义

`core` `panic!` 宏最终调用如下 (在 `library/core/src/panicking.rs`):

```rust
// 注意 这个函数永远不会越过 FFI 边界; 这是一个 Rust 到 Rust 的调用
extern "Rust" {
    #[lang = "panic_impl"]
    fn panic_impl(pi: &PanicInfo<'_>) -> !;
}

let pi = PanicInfo::internal_constructor(Some(&fmt), location);
unsafe { panic_impl(&pi) }
```

实际上解决该问题需要通过几个间接层:

1. 在 `compiler/rustc_middle/src/middle/weak_lang_items.rs` 中，`panic_impl` 用 `rust_begin_unwind` 声明标记为 '弱 lang 项'。在 `rustc_typeck/src/collect.rs` 中将实际符号名设置为 `rust_begin_unwind`。

   注意 `panic_impl` 被声明在一个 `extern "Rust"` 块中，这意味着 core 将尝试调用一个名为 `rust_begin_unwind` 的外部符号(在链接时解决)

2. 在 `library/std/src/panicking.rs` 中，我们有这样的定义:

```rust
/// core crate panic 的进入点。
#[cfg(not(test))]
#[panic_handler]
#[unwind(allowed)]
pub fn begin_panic_handler(info: &PanicInfo<'_>) -> ! {
    ...
}
```

特殊 `panic_handler` 属性是通过 `compiler/rustc_middle/src/middle/lang_items` 解析。`extract` 函数将 `panic_handler` 属性转换一个 `panic_impl` lang 项。

现在，我们在 `std` 中有一个匹配的 `panic_handler` lang 项。这个函数与定义在 `core` 中的 `extern { fn panic_impl }` 经过相同的过程，最终得到一个名为 `rust_begin_unwind` 的符号。在链接时，`core` 中的符号引用将被解析为 `std` 中的定义(Rust 源中调用 `begin_panic_handler`)。

因此，控制流将在运行时从 core 传递到 std。 这允许来自 core 的 panic 使用和其它 panic 相同的基础结构(panic 钩子，unwinding 等)

### std 中 panic! 的实现

这就是真正的 panic 相关逻辑开始的地方。在 `library/std/src/panicking.rs`，控制传递给 `rust_panic_with_hook`。这个方法负责调用全局 panic 钩子，并检查是否出现双重 panic。最后，调用由 panic 运行时提供的 `__rust_start_panic`。

对 `__rust_start_panic` 的调用非常奇怪 - 它被传递给 `*mut &mut dyn BoxMeUp`，转换成一个 `usize`。一起分解一下这种类型:

1. `BoxMeUp` 是一个内部 trait。它是给 `PanicPayload`
(用户提供的有效负载类型的包装器)实现的，并且有一个方法`fn box_me_up(&mut self) -> *mut (dyn Any + Send)`。这个方法获取用户提供的有效负载 (`T: Any + Send`)，将其打包，并将其转换为一个原始指针。

2. 当我们调用 `__rust_start_panic` 时，会得到一个 `&mut dyn BoxMeUp`。但是，这是一个胖指针 (是 `usize` 的两倍大)。为了跨 FFI 边界上将其传递给 panic 运行时，我们对*的可变引用* (`&mut &mut dyn BoxMeUp`)进行可变引用，并将其转换为原始指针(`*mut &mut dyn BoxMeUp`)。外部的原始指针是一个瘦指针，它指向一个 `Sized` 类型 (一个可变引用)。因此，可以将这个瘦指针转换为一个 `usize`，它适用于跨 FFI 边界传递。

最后，调用使用 `usize` 调用 `__rust_start_panic` 。现在进入 panic 运行时。

## 步骤 2: panic 运行时

Rust 提供两个 panic 运行时: `panic_abort` 和 `panic_unwind`。用户可以在构建时通过 `Cargo.toml` 在它们之间进行选择

`panic_abort` 非常简单: 正如你所期望的那样，它实现 `__rust_start_panic` 只为中断。

`panic_unwind` 是更有趣的情况。

在它的实现 `__rust_start_panic` 中，我们使用 `usize`，将其转换回 `*mut &mut dyn BoxMeUp`，解引用它，并调用 `&mut dyn BoxMeUp` 上的  `box_me_up`。在这个指针中，我们有一个指向负载本身的原始指针 (一个 `*mut (dyn Send + Any)`): 即一个指向调用 `panic!` 的用户提供真实值的原始指针。

至此，与平台无关的代码结束。现在，我们现在调用特定于平台的展开逻辑 (例如 `unwind`)。这个代码负责展开栈，运行与每个帧(当前，运行析构函数)相关联的所有 'landing pads'，并将控制权转移到 `catch_unwind` 帧。

请注意，所有 panic 要么中止进程，要么被调用的 `catch_unwind` 捕获: 在 `library/std/src/rt.rs` 中，调用用户提供的
`main` 函数是包装在 `catch_unwind` 中。