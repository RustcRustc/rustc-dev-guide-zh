# rustc中的闭包扩展

这一节描述了rustc是如何处理闭包的。Rust中的闭包实际上沦为了来自其创建者栈帧的结构体，该结构体包含了他们使用的值（或使用值的引用）。rustc的工作是要弄清楚闭包使用了哪些值，以及是如何使用的，这样他就可以决定是通过共享引用，可变引用还是通过移动来捕获给定的变量。rustc也需要弄清楚闭包能够实现哪种闭包特征([`Fn`][fn]，[`FnMut`][fn_mut]，或[`FnOnce`][fn_once])。

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

假设上面是名为`immut.rs`文件的内容。如果我们用以下的命令来编译`immut.rs`，[`-Z dump-mir=all`][dump-mir]参数将会使`rustc`生成[MIR][mir]并将其转储到`mir_dump`目录中。
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

在第一行`_4 = &_1;`中，`mir_dump`告诉我们`x`作为不可变引用被借用了。这是我们希望的，因为我们的闭包需要读取`x`。

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

这一次，在第一行`_4 = &mut _1;`中，我们可以看到借用变成了可变借用。这是十分合理的，使得闭包可以将`x`加10。

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
这里, `x`直接被移入了闭包内，因此在闭包代码块之后将不允许访问这个变量了。

## 编译器中的推断

现在，让我们深入研究rustc的代码，看看编译器是如何完成所有这些推断的。

首先，我们先定义一个术语*upvar*，它在我们之后的讨论中会经常使用到。**upvar**是定义闭包的函数的本地变量。所以，在上述示例中，**x**对于闭包来说是一个upvar。它们有时也会被称为*空闲变量*以表示它们并未绑定到闭包的上下文中。[`compiler/rustc_middle/src/ty/query/mod.rs`][upvars]为此定义了一个被成为*upv.rs_mentioned*的查询。 

[upvars]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/query/queries/struct.upvars_mentioned.html

除了懒调用，另一个将闭包区别于普通函数的特征就是它可以从上下文中借用这些upvar；因此编译器必须确定upvar的借用类型。基于这个用途，编译器从分配一个不可变的借用类型开始，可以根据需要来减少限制（将它从**不可变**变成**可变**，再变成**移动**）。 在上述的示例1中，闭包仅仅将变量用于打印，而不以任何方式对其进行修改，因此在`mir_dump`中，我们发现借用类型的upvar变量`x`是不可变的。但是，在示例2中，闭包修改了`x`并将其加上了某个值。由于这种改变，编译器从将`x`分配为不可变的引用类型开始，必须将其调整为可变的引用。同样的，在示例3中，闭包释放了向量`x`，因此要求将变量`x`移入闭包内。依赖于借用类型，闭包需要实现合适的特征：`Fn`特征对应不可变借用, `FnMut`对应可变借用，`FnOnce`对应于移动语义。

大多数与闭包相关的代码在[`compiler/rustc_typeck/src/check/upvar.rs`][upvar]文件中，数据结构定义在[`compiler/rustc_middle/src/ty/mod.rs`][ty]文件中。

[upvar]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_typeck/check/upvar/index.html
[ty]:https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/index.html

在我们进一步深入之前，一起讨论下如何通过rustc代码库来检测控制流。对于闭包来说，像下面一样设置`RUST_LOG`环境变量并在文件中收集输出。

```console
> RUST_LOG=rustc_typeck::check::upvar rustc +stage1 -Z dump-mir=all \
    <.rs file to compile> 2> <file where the output will be dumped>
```

这里使用了stage1编译器，并为`rustc_typeck::check::upvar`模块启用了`debug!`日志。

另一种选择是使用lldb或gdb逐步执行代码。

1. `rust-lldb build/x86_64-apple-darwin/stage1/bin/rustc test.rs`
2. 在lldb中：
    1. `b upvar.rs:134`  // 在upvar.rs文件中的某行上设置断点
    2. `r`  // 一直运行程序直到打到了该断点上

让我们从[`upvar.rs`][upvar]开始. 这个文件有一个叫[`euv::ExprUseVisitor`]的结构，该结构遍历闭包的源码并为每一个被借用，被更改，被移动的upvar触发了一个回调。

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

在上面的示例中，我们的访问器将会调用两次，对于标记了1和2的代码行，一个用于共享借用，另一个用于可变借用。它还会告诉我们借用了什么。

通过实现[`Delegate`]特征来定义回调。[`InferBorrowKind`][ibk]类型实现了`Delegate`并维护了一个map来记录每个upvar需要哪种捕获方式。捕获的方式可以是`ByValue`（被移动）或者是`ByRef`（被借用）。对于`ByRef`借用，[`BorrowKind`]可能是定义在[`compiler/rustc_middle/src/ty/mod.rs`][middle_ty]中的`ImmBorrow`，`UniqueImmBorrow`，`MutBorrow`。

[`BorrowKind`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/enum.BorrowKind.html
[middle_ty]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/index.html

`Delegate`定义了一些不同的方法（不同的回调）：
**consume**方法用于*移动*变量，**borrow**方法用于某种（共享的或可变的）借用，而当我们看到某种事物的分配时，则调用**mutate**方法。

所有的这些回调都有一个共同的参数*cmt*，该参数代表类别，可变形和类型。他定义在[`compiler/rustc_middle/src/middle/mem_categorization.rs`][cmt]中。代码注释中写到：“`cmt`是一个值的完整分类，它指明了该值的起源和位置，以及存储该值的内存的可变性”。根据这些回调（consume，borrow等），我们将会调用相关的`adjust_upvar_borrow_kind_for_<something>`并传递`cmt`。一旦借用类型有了调整，我们将它存储在表中，基本上说明了每个闭包都借用了什么。

```rust,ignore
self.tables
    .borrow_mut()
    .upvar_capture_map
    .extend(delegate.adjust_upvar_captures);
```

[`Delegate`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_typeck/expr_use_visitor/trait.Delegate.html
[ibk]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_typeck/check/upvar/struct.InferBorrowKind.html
[cmt]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_typeck/mem_categorization/index.html
