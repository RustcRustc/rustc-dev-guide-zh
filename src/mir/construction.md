# MIR 的构建

从 [HIR] lower到 [MIR] 的过程会在下面（可能不完整）这些item上进行：

* 函数体和闭包体
* `static` 和 `const` 的初始化
* 枚举 discriminant 的初始化
* 任何类型的胶水和补充代码
    * Tuple 结构体的初始化函数
    * Drop 代码 （即没有手动调用的 `Drop::drop` 函数的对象的 `drop`）
    * 没有显式实现 `Drop` 的对象的 `drop`

Lowering 是通过调用 [`mir_built`] 查询触发的。
MIR 构建器实际上并不使用 HIR，而是对 [THIR] 中的表达式进行递归处理。

Lowering会为函数签名中指定的每个参数创建局部变量。
接下来，它为指定的每个绑定创建局部变量（例如， `(a, b): (i32, String)`）产生3个绑定，一个用于参数，两个用于绑定。
接下来，它生成字段访问，该访问从参数读取字段并将其值写入绑定变量。

在解决了初始化之后，lowering为函数体递归生成 MIR（ `Block` 表达式）并将结果写入 `RETURN_PLACE`。

## `unpack!` 所有东西

生成 MIR 的函数有两种模式。
第一种情况，如果该函数仅生成语句，则它将以基本块作为参数，这些语句应放入该基本块。
然后可以正常返回结果：

```rust,ignore
fn generate_some_mir(&mut self, block: BasicBlock) -> ResultType {
   ...
}
```

但是还有其他一些函数会生成新的基本块。
例如，lowering 像 `if foo { 22 } else { 44 }` 这样的表达式需要生成一个小的“菱形图”。
在这种情况下，函数将在其代码开始处使用一个基本块，并在代码生成结束时返回一个（可能是）新的基本块。
`BlockAnd` 类型用于表示此类情况：

```rust,ignore
fn generate_more_mir(&mut self, block: BasicBlock) -> BlockAnd<ResultType> {
    ...
}
```

当您调用这些函数时，通常有一个局部变量 `block`，它实际上是一个“光标”。 它代表了我们要添加新的MIR的位置。
当调用 `generate_more_mir` 时，您会想要更新该光标。
您可以手动执行此操作，但这很繁琐：

```rust,ignore
let mut block;
let v = match self.generate_more_mir(..) {
    BlockAnd { block: new_block, value: v } => {
        block = new_block;
        v
    }
};
```

因此，我们提供了一个宏，可让您通过如下方式完成更新：
`let v = unpack!(block = self.generate_more_mir(...))`。
它简单地提取新的块并覆盖在 `unpack!` 中指明的变量 `block`。

## 将表达式 Lowering 到 MIR

本质上一个表达式可以有四种表示形式：

* `Place` 指一个（或一部分）已经存在的内存地址（本地，静态，或者提升过的）
* `Rvalue` 是可以给一个 `Place` 赋值的东西
* `Operand` 是一个给像 `+` 这样的运算符或者一个函数调用的参数
* 一个存放了一个值的拷贝的临时变量

下图简要描绘了这些表示形式之间的交互：

<img src="https://raw.githubusercontent.com/rust-lang/rustc-dev-guide/master/src/mir/mir_overview.svg">

[点此看更为详细的交互图](https://raw.githubusercontent.com/rust-lang/rustc-dev-guide/9a676ee3a4bc9d8d054efd1ff57fc15ce19c00bd/src/mir/mir_detailed.svg)

我们首先将函数体 lowering 到一个 `Rvalue`，这样我们就可以为 `RETURN_PLACE` 创建一个赋值，
这个 `Rvalue` 的 lowering 反过来会触发其参数的 `Operand` lowering（如果有的话）
lowering `Operand` 会产生一个 `const` 操作数，或者移动/复制出 `Place`，从而触发 `Place` lowering。
如果 lowering 的表达式包含操作，则 lowering 到 `Place` 的表达式可以触发创建一个临时变量。
这是蛇咬自己的尾巴的地方，我们需要触发 `Rvalue` lowering，以将表达式的值写入本地变量。

## Operator lowering

内置类型的运算符不会 lower 为函数调用（这将导致无限递归调用，因为这些 trait 实现包含了操作本身）。
相反，对于这些类型已经存在了用于二元和一元运算符和索引运算的 `Rvalue`。
这些 `Rvalue` 稍后将生成为 llvm 基本操作或 llvm 内部函数。

所有其他类型的运算符都被 lower 为对运算符对应 trait 的实现中的的函数调用。

无论采用哪种 lower 方式，运算符的参数都会 lower 为`Operand`。
这意味着所有参数都是常量或者引用局部或静态位置中已经存在的值。

## 方法调用的 lowering

方法调用被降低到与一般函数调用相同的`TerminatorKind`。
在[MIR]中，方法调用和一般函数调用之间不再存在差异。

## 条件

不带字段变量的 `enum` 的 `if` 条件判断和 `match` 语句都会被lower为 `TerminatorKind::SwitchInt`。
每个可能的值（如果为 `if` 条件判断，则对应的值为 `0` 和 `1`）都有一个对应的 `BasicBlock`。
分支的参数是表示if条件值的 `Operand`。

### 模式匹配

具有字段的 `enum` 上的 `match` 语句也被 lower 为 `TerminatorKind::SwitchInt`，但是其 `Operand` 是一个 `Place`，可以在其中找到该值的判别式。
这通常涉及将判别式读取为新的临时变量。

## 聚合构造

任何类型的聚合值（例如结构或元组）都是通过 `Rvalue::Aggregate` 建立的。
所有字段都 lower 为 `Operator`。
从本质上讲，这等效于对每个聚合上的字段都会有一个赋值语句，如果必要的话还会再加上一个对 `enum` 的判别式的赋值。

[MIR]: ./index.html
[HIR]: ../hir.html
[THIR]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_mir_build/thir/index.html

[MIR]: ./index.html
[HIR]: ../hir.html
[THIR]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_mir_build/thir/index.html

[`rustc_mir_build::thir::cx::expr`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_mir_build/thir/cx/expr/index.html
[`mir_built`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_mir_build/build/fn.mir_built.html
