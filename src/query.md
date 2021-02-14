# 查询: 需求驱动的编译

如[编译器高级概述][hl]中所述，Rust编译器当前（2021年1月 <!-- date: 2021-01 -->）仍然正在从传统的“基于 pass”的编译过程过渡到“需求驱动”的编译过程。**编译器查询系统是我们新的需求驱动型编译过程的关键。**背后的想法很简单。 您可以使用各种查询来计算某一输入的相关信息 – 例如，有一个名为`type_of(def_id)`的查询，传入某项的 [def-id] ，它将计算该项的类型并将其返回给您。

[def-id]: appendix/glossary.md#def-id
[hl]: ./compiler-src.md

查询执行是**记忆化**的 —— 因此，第一次调用查询时，它将进行实际的计算，但是下一次，结果将从哈希表中返回。
此外，查询执行非常适合“**增量计算**”； 大致的想法是，当您执行查询时，**可能**会通过从磁盘加载存储的数据来将结果返回给您（这是一个单独的主题，我们将不在此处进一步讨论）。

总体上我们希望最终整个编译器控制流将由查询驱动。由一个顶层的查询（"compile"）来驱动一个crate上的编译；这会依次要求这个crate的各种信息。例如：

- 此 "compile" 查询可能需要获取代码生成单元列表（即需要由LLVM编译的模块）。
- 但是计算代码生成单元列表将调用一些子查询，该子查询返回 Rust 源代码中定义的所有模块的列表。
- 这些子查询会要求查询HIR。
- 就这样越推越远，直到我们完成实际的 parsing。

这一愿景尚未完全实现。尽管如此，编译器的大量代码（例如生成MIR）已经完全像这样工作了。

### 增量编译的详细说明

[增量编译的详细说明][query-model]一章提供了关于什么是查询及其工作方式的深入描述。
如果您打算编写自己的查询，那么可以读一读这一章节。

### 调用查询

调用查询很简单。 `tcx`（“类型上下文”）为每个定义好的查询都提供了一种方法。 因此，例如，要调用`type_of`查询，只需执行以下操作：

```rust,ignore
let ty = tcx.type_of(some_def_id);
```

### 编译器如何执行查询

您可能想知道调用查询方法时会发生什么。
答案是，对于每个查询，编译器都会将结果缓存——如果您的查询已经执行过，那么我们将简单地从缓存中复制上一次的返回值并将其返回（因此，您应尝试确保查询的返回类型可以低成本的克隆；如有必要，请使用`Rc`）。

#### Providers

但是，如果查询不在缓存中，则编译器将尝试找到合适的 **provider**。
provider 是已定义并链接到编译器的某个函数，其包含用于计算查询结果的代码。

**Provider是按crate定义的。**
编译器（至少在概念上）在内部维护每个 crate 的 provider 表。
目前，实际上 provider 分为了两组：用于查询“**本crate**”的 provider（即正在编译的crate）和用于查询“**外部crate**”（即正在编译的crate的依赖） 的 provider。
请注意，确定查询所在的crate的类型不是查询的*类型*，而是*键*。
例如，当您调用 `tcx.type_of(def_id)` 时，它可以是本地查询，也可以是外部查询，
这取决于`def_id`所指的crate（请参阅[`self::keys::Key`][Key] trait 以获取有关其工作原理的更多信息）。

Provider 始终具有相同的函数签名：

```rust,ignore
fn provider<'tcx>(
    tcx: TyCtxt<'tcx>,
    key: QUERY_KEY,
) -> QUERY_RESULT {
    ...
}
```

Provider 接受两个参数：`tcx` 和查询键，并返回查询结果。

#### 如何初始化 provider

创建 tcx 时，它的创建者会使用[`Providers`][providers_struct]结构为它提供provider。
此结构是由此处的宏生成的，但基本上就是一大堆函数指针：

[providers_struct]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/query/struct.Providers.html

```rust,ignore
struct Providers {
    type_of: for<'tcx> fn(TyCtxt<'tcx>, DefId) -> Ty<'tcx>,
    ...
}
```

目前，我们为本地 crate 和所有外部 crate 各提供一份该结构的副本，最终计划是为每个crate提供一份。

这些 `Provider` 结构最终是由 `librustc_driver` 创建并填充的，它通过调用各种[`provide`][provide_fn]函数，将工作分配给其他`rustc_*` crate。这些函数看起来像这样：

[provide_fn]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/hir/fn.provide.html

```rust,ignore
pub fn provide(providers: &mut Providers) {
    *providers = Providers {
        type_of,
        ..*providers
    };
}
```

也就是说，他们接收一个  `&mut Providers`  并对其进行原地修改。
通常我们使用上面的写法只是因为它看起来比较漂亮，但是您也可以 `providers.type_of = type_of`，这是等效的。
（在这里，`type_of` 将是一个顶层函数，如我们之前看到的那样定义。）
因此，如果我们想为其他查询添加 provider，比如向前面的 crate 添加一个 `fubar`，我们可以这样修改 `provide` 函数：

```rust,ignore
pub fn provide(providers: &mut Providers) {
    *providers = Providers {
        type_of,
        fubar,
        ..*providers
    };
}

fn fubar<'tcx>(tcx: TyCtxt<'tcx>, key: DefId) -> Fubar<'tcx> { ... }
```

注意：大多数 `rustc_*` crate仅提供 **本crate provider**。
几乎所有的**外部 provider** 都会通过 [`rustc_metadata` crate][rustc_metadata] 进行处理，后者会从 crate 元数据中加载信息。
但是在某些情况下，某些crate可以既提供本地也提供外部crate查询，在这种情况下，他们通过[`provide_both`][ext_provide_both] 定义了 `provide` 和 `provide_extern` 函数，供`rustc_driver` 调用。 

[rustc_metadata]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_metadata/index.html
[ext_provide_both]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_codegen_llvm/attributes/fn.provide_both.html


### 添加一种新的查询

假设您想添加一种新的查询，您该怎么做？
定义查询分为两个步骤：

1. 首先，必须指定查询名称和参数； 然后，
2. 您必须在需要的地方提供查询提供程序。

要指定查询名称和参数，您只需将条目添加到
[`compiler/rustc_middle/src/query/mod.rs`][query-mod] 中的大型宏调用之中，类似于：

[query-mod]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/query/index.html

```rust,ignore
rustc_queries! {
    Other {
        /// Records the type of every item.
        query type_of(key: DefId) -> Ty<'tcx> {
            cache { key.is_local() }
        }
    }

    ...
}
```

查询分为几类（`Other`，`Codegn`，`TypeChecking`等）。
每组包含一个或多个查询。 每个查询的定义都是这样分解的：

```rust,ignore
query type_of(key: DefId) -> Ty<'tcx> { ... }
^^    ^^^^^^^      ^^^^^     ^^^^^^^^   ^^^
|     |            |         |          |
|     |            |         |          查询修饰符
|     |            |         查询的结果类型
|     |            查询的 key 的类型
|     查询名称
query 关键字
```

让我们一一介绍它们：

- **query关键字：** 表示查询定义的开始。

- **查询名称：**查询方法的名称（`tcx.type_of(..)`）。也用作生成的表示此查询的结构体的名称（`ty::queries::type_of`）。

- **查询的 key 的类型：**此查询的参数类型。此类型必须实现 [`ty::query::keys::Key`][Key] trait，该trait定义了如何将其映射到 crate 等等。

- **查询的结果类型：** 此查询产生的类型。
这种类型应该

  （a）不使用 `RefCell` 等内部可变性模式，并且
  （b）可以廉价地克隆。对于非平凡的数据类型，建议使用 Interning 方法或使用`Rc`或`Arc`。
  
  - 一个例外是`ty::steal::Steal`类型，该类型用于廉价地修改MIR。有关更多详细信息，请参见`Steal`的定义。不应该在不警告`@rust-lang/compiler`的情况下添加对`Steal`的新的使用。
  
- **查询修饰符：** 用于自定义查询处理方式的各种标志和选项（主要用于[增量编译][incrcomp]）。

[Key]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/query/keys/trait.Key.html
[incrcomp]: queries/incremental-compilation-in-detail.html#query-modifiers

因此，要添加查询：

- 使用上述格式在 `rustc_queries!` 中添加一个条目。
- 通过修改适当的 `provide` 方法建立和 provider 的关联； 或根据需要添加一个新文件，并确保`rustc_driver` 会调用它。

#### 查询结构体和查询描述

对于每种类型，`rustc_queries` 宏都会生成一个以查询名字命名的“查询结构体”。
此结构体是描述查询的一种占位符。 每个这样的结构都要实现[`self::config::QueryConfig`][QueryConfig] trait，
该 trait 上有该特定查询的 键/值 的关联类型。
基本上，生成的代码如下所示：

```rust,ignore
// Dummy struct representing a particular kind of query:
pub struct type_of<'tcx> { data: PhantomData<&'tcx ()> }

impl<'tcx> QueryConfig for type_of<'tcx> {
  type Key = DefId;
  type Value = Ty<'tcx>;

  const NAME: QueryName = QueryName::type_of;
  const CATEGORY: ProfileCategory = ProfileCategory::Other;
}
```

您可能希望实现一个额外的trait，称为 [`self::config::QueryDescription`][QueryDescription]。
这个 trait 在发生循环引用错误时会被使用，为查询提供一个“人类可读”的名称，以便我们可以探明循环引用发生的情况。
如果查询键是 `DefId`，则可以不实现这个 trait，但是如果*不*实现它，则会得到一个相当普遍的错误（“processing `foo` ...”）。
您可以将新的 impl 放入`config`模块中。 像这样：

[QueryConfig]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/query/trait.QueryConfig.html
[QueryDescription]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_query_system/query/config/trait.QueryDescription.html

```rust,ignore
impl<'tcx> QueryDescription for queries::type_of<'tcx> {
    fn describe(tcx: TyCtxt, key: DefId) -> String {
        format!("computing the type of `{}`", tcx.def_path_str(key))
    }
}
```

另一个选择是添加`desc`修饰符：

```rust,ignore
rustc_queries! {
    Other {
        /// Records the type of every item.
        query type_of(key: DefId) -> Ty<'tcx> {
            desc { |tcx| "computing the type of `{}`", tcx.def_path_str(key) }
        }
    }
}
```

`rustc_queries` 宏会自动生成合适的 `impl`。

[query-model]: queries/incremental-compilation-in-detail.md