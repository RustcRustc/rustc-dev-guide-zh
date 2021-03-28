# 类型检查

[`rustc_typeck`][typeck] crate 包含"类型收集"和"类型检查"的源代码，和其它一些相关功能。(它很大程度依赖于[type inference]和[trait solving]。)

[typeck]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_typeck/index.html
[type inference]: ./type-inference.md
[trait solving]: ./traits/resolution.md

## 类型收集

类型"收集"是将用户写入的语法内容 HIR(`hir::Ty`) 中的类型转化为编译器使用的**内部表示**(`Ty<'tcx>`)的过程 – 对 where 子句和函数签名的其他位也进行类似的转换。

为了尝试并感受到这种差异，请考虑下面的函数:

```rust,ignore
struct Foo { }
fn foo(x: Foo, y: self::Foo) { ... }
//        ^^^     ^^^^^^^^^
```

这两个参数 `x` 和 `y` 有相同的类型: 但他们是不懂的 `hir::Ty` 节点。这些节点有不同的 span，当然它们的编码路径也有所不同。但它们一旦"被收集"到 `Ty<'tcx>` 节点，它们会使用完全相同的内部类型。

集合被定义为计算关于正在编译的 crate 中的各种函数、特性和其他项的信息的一组[查询][queries]。请注意，每个查询都与*过程间*事物有关——例如，对于函数定义，集合将计算出函数的类型和签名，但它不会以任何方式访问*函数体*，也不会检查局部变量的类型注释(这是类型*检查*的工作)。

更多有关详细信息，请参阅 [`collect`][collect] 模块。

[queries]: ./query.md
[collect]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_typeck/collect/

**TODO**: 实际上谈到类型检查...