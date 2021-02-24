# rustc中的闭包扩展

这一节描述了rustc是如何处理闭包的。Rust中的闭包实际上沦为了来自其创建者栈帧的结构体，该结构体包含了他们使用的值（或使用值的引用）。rustc的工作是要弄清楚闭包使用了哪些值，以及是如何使用的，这样他就可以决定是通过共享引用，可变引用还是通过转移所有权来捕获给定的变量。rustc也需要弄清楚闭包能够实现哪种闭包特征([`Fn`][fn]，[`FnMut`][fn_mut]，或[`FnOnce`][fn_once])。

[fn]: https://doc.rust-lang.org/std/ops/trait.Fn.html
[fn_mut]:https://doc.rust-lang.org/std/ops/trait.FnMut.html
[fn_once]: https://doc.rust-lang.org/std/ops/trait.FnOnce.html

让我们来从一个小例子开始:

### 示例 1

首先，让我们来看一下以下示例中的闭包是如何实现的：

```rust
fn closure(f: impl Fn()) {
    f();
}

fn main() {
    let x: i32 = 10;
    closure(|| println!("Hi {}", x));  // 闭包仅仅读取了x变量.
    println!("Value of x after return {}", x);
}
```

假设上面是名为`immut.rs`文件的内容。如果我们用以下的命令来编译`immut.rs`，[`-Z dump-mir=all`][dump-mir]将导致`rustc`生成[MIR][mir]并将其转储到`mir_dump`目录中。
```console
> rustc +stage1 immut.rs -Z dump-mir=all
```

[mir]: ./mir/index.md
[dump-mir]: ./mir/passes.md

在我们执行了这个命令之后，我们将会看到在当前的工作目录下生成了一个名为`mir_dump`的新目录，其中包含了多个文件，如果我们打开`rustc.main.-------.mir_map.0.mir`文件将会发现，除了其他内容外，还包括此行：

```rust,ignore
_4 = &_1;
_3 = [closure@immut.rs:7:13: 7:36] { x: move _4 };
```

请注意在这节的MIR示例中，`_1`就是`x`。

这里是第一行：`_4 = &_1;`，`mir_dump`告诉我们`x`作为不可变引用被借用了。这是我们希望的，因为我们的闭包需要读取`x`。

### 示例 2

这里是另一个示例：

```rust
fn closure(mut f: impl FnMut()) {
    f();
}

fn main() {
    let mut x: i32 = 10;
    closure(|| {
        x += 10;  // The closure mutates the value of x
        println!("Hi {}", x)
    });
    println!("Value of x after return {}", x);
}
```

```rust,ignore
_4 = &mut _1;
_3 = [closure@mut.rs:7:13: 10:6] { x: move _4 };
```

这一次，在第一行（`_4 = &mut _1;`）中，我们可以看到借用变成了可变借用。这是十分合理的，使得闭包可以将`x`加10。

### 示例 3

又一个示例：

```rust
fn closure(f: impl FnOnce()) {
    f();
}

fn main() {
    let x = vec![21];
    closure(|| {
        drop(x);  // 在这之后使x不可用
    });
    // println!("Value of x after return {:?}", x);
}
```

```rust,ignore
_6 = [closure@move.rs:7:13: 9:6] { x: move _1 }; // bb16[3]: scope 1 at move.rs:7:13: 9:6
```
这里, `x`的所有权直接被转移到了闭包内，因此在闭包代码块之后将不允许访问这个变量了。

## 编译器中的推论

现在，让我们深入研究rustc的代码，看看编译器是如何完成所有这些推断的。

Let's start with defining a term that we will be using quite a bit in the rest of the discussion -
*upvar*. An **upvar** is a variable that is local to the function where the closure is defined. So,
in the above examples, **x** will be an upvar to the closure. They are also sometimes referred to as
the *free variables* meaning they are not bound to the context of the closure.
[`compiler/rustc_middle/src/ty/query/mod.rs`][upvars] defines a query called *upv.rs_mentioned*
for this purpose.

[upvars]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/query/queries/struct.upvars_mentioned.html

Other than lazy invocation, one other thing that distinguishes a closure from a
normal function is that it can use the upvars. It borrows these upvars from its surrounding
context; therefore the compiler has to determine the upvar's borrow type. The compiler starts with
assigning an immutable borrow type and lowers the restriction (that is, changes it from
**immutable** to **mutable** to **move**) as needed, based on the usage. In the Example 1 above, the
closure only uses the variable for printing but does not modify it in any way and therefore, in the
`mir_dump`, we find the borrow type for the upvar `x` to be immutable.  In example 2, however, the
closure modifies `x` and increments it by some value.  Because of this mutation, the compiler, which
started off assigning `x` as an immutable reference type, has to adjust it as a mutable reference.
Likewise in the third example, the closure drops the vector and therefore this requires the variable
`x` to be moved into the closure. Depending on the borrow kind, the closure has to implement the
appropriate trait: `Fn` trait for immutable borrow, `FnMut` for mutable borrow,
and `FnOnce` for move semantics.

Most of the code related to the closure is in the
[`compiler/rustc_typeck/src/check/upvar.rs`][upvar] file and the data structures are
declared in the file [`compiler/rustc_middle/src/ty/mod.rs`][ty].

[upvar]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_typeck/check/upvar/index.html
[ty]:https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/index.html

Before we go any further, let's discuss how we can examine the flow of control through the rustc
codebase. For closures specifically, set the `RUST_LOG` env variable as below and collect the
output in a file:

```console
> RUST_LOG=rustc_typeck::check::upvar rustc +stage1 -Z dump-mir=all \
    <.rs file to compile> 2> <file where the output will be dumped>
```

This uses the stage1 compiler and enables `debug!` logging for the
`rustc_typeck::check::upvar` module.

The other option is to step through the code using lldb or gdb.

1. `rust-lldb build/x86_64-apple-darwin/stage1/bin/rustc test.rs`
2. In lldb:
    1. `b upvar.rs:134`  // Setting the breakpoint on a certain line in the upvar.rs file`
    2. `r`  // Run the program until it hits the breakpoint

Let's start with [`upvar.rs`][upvar]. This file has something called
the [`euv::ExprUseVisitor`] which walks the source of the closure and
invokes a callbackfor each upvar that is borrowed, mutated, or moved.

[`euv::ExprUseVisitor`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_typeck/expr_use_visitor/struct.ExprUseVisitor.html

```rust
fn main() {
    let mut x = vec![21];
    let _cl = || {
        let y = x[0];  // 1.
        x[0] += 1;  // 2.
    };
}
```

In the above example, our visitor will be called twice, for the lines marked 1 and 2, once for a
shared borrow and another one for a mutable borrow. It will also tell us what was borrowed.

The callbacks are defined by implementing the [`Delegate`] trait. The
[`InferBorrowKind`][ibk] type implements `Delegate` and keeps a map that
records for each upvar which mode of capture was required. The modes of capture
can be `ByValue` (moved) or `ByRef` (borrowed). For `ByRef` borrows, the possible
[`BorrowKind`]s are `ImmBorrow`, `UniqueImmBorrow`, `MutBorrow` as defined in the
[`compiler/rustc_middle/src/ty/mod.rs`][middle_ty].

[`BorrowKind`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/enum.BorrowKind.html
[middle_ty]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/index.html

`Delegate` defines a few different methods (the different callbacks):
**consume** for *move* of a variable, **borrow** for a *borrow* of some kind
(shared or mutable), and **mutate** when we see an *assignment* of something.

All of these callbacks have a common argument *cmt* which stands for Category,
Mutability and Type and is defined in
[`compiler/rustc_middle/src/middle/mem_categorization.rs`][cmt]. Borrowing from the code
comments, "`cmt` is a complete categorization of a value indicating where it
originated and how it is located, as well as the mutability of the memory in
which the value is stored". Based on the callback (consume, borrow etc.), we
will call the relevant *adjust_upvar_borrow_kind_for_<something>* and pass the
`cmt` along. Once the borrow type is adjusted, we store it in the table, which
basically says what borrows were made for each closure.

```rust,ignore
self.tables
    .borrow_mut()
    .upvar_capture_map
    .extend(delegate.adjust_upvar_captures);
```

[`Delegate`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_typeck/expr_use_visitor/trait.Delegate.html
[ibk]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_typeck/check/upvar/struct.InferBorrowKind.html
[cmt]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_typeck/mem_categorization/index.html