# Rustc 中的序列化

Rustc 需要在编译期 [序列化][serialize] 和反序列化各种数据。特别是:

- "Crate 元数据"，主要是查询输出，在编译 crate 时，以二进制格式序列化并输出到 `rlib` 和 `rmeta` 文件中，由依赖该库的 crate 将这些文件反序列化。
- 某些查询输出以二进制格式序列化为[持久化增量编译结果][persist incremental compilation results]。
- `-Z ast-json` 和 `-Z ast-json-noexpand` 标记以 json 格式序列化 [AST], 并将结果输出到标准输出。
- [`CrateInfo`]使用 `-Z no-link` 标记时被序列化到 json，使用 `-Z link-only` 标志时，从 json 反序列化。

## `Encodable` 和 `Decodable` trait

[`rustc_serialize`] crate 为可序列化类型定义了两个 trait:

```rust,ignore
pub trait Encodable<S: Encoder> {
    fn encode(&self, s: &mut S) -> Result<(), S::Error>;
}

pub trait Decodable<D: Decoder>: Sized {
    fn decode(d: &mut D) -> Result<Self, D::Error>;
}
```

还为整型，浮点型，`bool`，`char`，`str` 和各种通用标准库类型都定义了这两个 trait 的实现。

由这些类型组合成的类型，通常通过 [derives] 实现 `Encodable` 和 `Decodable`。这些生成的实现将结构体或枚举中的字段反序列化。对于一个结构体的实现像下面这样:

```rust,ignore
#![feature(rustc_private)]
extern crate rustc_serialize;
use rustc_serialize::{Decodable, Decoder, Encodable, Encoder};

struct MyStruct {
    int: u32,
    float: f32,
}

impl<E: Encoder> Encodable<E> for MyStruct {
    fn encode(&self, s: &mut E) -> Result<(), E::Error> {
        s.emit_struct("MyStruct", 2, |s| {
            s.emit_struct_field("int", 0, |s| self.int.encode(s))?;
            s.emit_struct_field("float", 1, |s| self.float.encode(s))
        })
    }
}
impl<D: Decoder> Decodable<D> for MyStruct {
    fn decode(s: &mut D) -> Result<MyStruct, D::Error> {
        s.read_struct("MyStruct", 2, |d| {
            let int = d.read_struct_field("int", 0, Decodable::decode)?;
            let float = d.read_struct_field("float", 1, Decodable::decode)?;

            Ok(MyStruct { int, float })
        })
    }
}
```

## 编码和解码 arena allocated 类型

Rustc 有许多 [arena allocated 类型][arena allocated types]。如果不访问分配这些类型的 arena 就无法反序列化这些类型。[`TyDecoder`] 和 [`TyEncoder`] trait 是允许访问 `TyCtxt` 的 `Decoder` 和 `Encoder` 的 super trait。

对于包含 arena allocated 类型的类型，则将实现这些 trait 的 `Encodable` 和 `Decodable` 的类型参数绑定在一起。例如

```rust,ignore
impl<'tcx, D: TyDecoder<'tcx>> Decodable<D> for MyStruct<'tcx> {
    /* ... */
}
```

`TyEncodable` 和 `TyDecodable` [derive 宏][derives] 将其扩展为这种实现。

解码实际的 arena allocated 类型比较困难，因为孤儿规则导致一些实现无法编写。为解决这个问题，`rustc_middle` 中的定义的 [`RefDecodable`] trait。可以给任意类型实现。`TyDecodable` 宏会调用 `RefDecodable` 去解码引用，但是对不同的泛型代码实际上需要特定的类型解码器 `Decodable`。

对 interned 类型而言，使用新的类型包装器，如 `ty::Predicate` 和手动实现 `Encodable` 和 `Decodable` 可能更简单，而不是手动实现 `RefDecodable`。

## Derive 宏

`rustc_macros` crate 定义各种 drive，帮助实现 `Decodable` 和 `Encodable`。

- `Encodable` 和 `Decodable` 宏会生成适用于所有 `Encoders` 和 `Decoders` 的实现。这些应该用在不依赖 `rustc_middle` 的 crate 中，或必须序列化但没有实现 `TyEncoder` 的类型。
- `MetadataEncodable` 和 `MetadataDecodable` 生成仅允许通过 [`rustc_metadata::rmeta::encoder::EncodeContext`] 和 [`rustc_metadata::rmeta::decoder::DecodeContext`] 解码的实现。这些用在包含 `rustc_metadata::rmeta::Lazy` 的类型中。
- `TyEncodable` 和 `TyDecoder` 生成适用于任意 `TyEncoder` 或 `TyDecoder` 的实现。这些仅用于 crate 元数据和/或增量缓存中序列化类型，`rustc_middle` 中大多数是可序列化类型。

## Shorthands

`Ty` 可以深度递归，如果每个 `Ty` 被编码会导致 crate 元数据变的非常大。为解决这个问题，每个 `TyEncoder` 的输出中都有序列化类型的位置缓存。如果要编码的类型在缓存中，则编码写入文件的字节偏移量，而不是像通常那样的序列化类型。类似的方案用于 `ty::Predicate`。

## `Lazy<T>`

在创建 `TyCtxt<'tcx>` 之前先加载 crate 元数据，因此一些反序列化需要推迟到元数据的初始化载入。[`Lazy<T>`] 类型将(相对)偏移量包装在了已序列化的 `T` 的 crate 元数据中。

`Lazy<[T]>` 和 `Lazy<Table<I, T>>` 类型提供了一些功能 `Lazy<Vec<T>>` 和 `Lazy<HashMap<I, T>>` :

- 可以直接从迭代器编码 `Lazy<[T]>`，无需事先收集到 `Vec<T>` 中。
- 索引到 `Lazy<Table<I, T>>` 不需要解码除正在读取条目以外的条目。

**注意**: 不缓存 `Lazy<T>` 第一次反序列化后的值。相反，查询系统是缓存这些结果的主要方式。

## Specialization

少数类型，特别是 `DefId`，针对不同的 `Encoder` 需要采用不同的实现。目前，这是通过 ad-hoc 专门处理:
`DefId` 有一个 `default` 实现 `Encodable<E>` 和一个专有的 `Encodable<CacheEncoder>`。

[arena allocated types]: memory.md
[AST]: the-parser.md
[derives]: #derive-macros
[persist incremental compilation results]: queries/incremental-compilation-in-detail.md#the-real-world-how-persistence-makes-everything-complicated
[serialize]: https://en.wikipedia.org/wiki/Serialization

[`CrateInfo`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_codegen_ssa/struct.CrateInfo.html
[`Lazy<T>`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_metadata/rmeta/struct.Lazy.html
[`RefDecodable`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/codec/trait.RefDecodable.html
[`rustc_metadata::rmeta::decoder::DecodeContext`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_metadata/rmeta/decoder/struct.DecodeContext.html
[`rustc_metadata::rmeta::encoder::EncodeContext`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_metadata/rmeta/encoder/struct.EncodeContext.html
[`rustc_serialize`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_serialize/index.html
[`TyDecoder`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/codec/trait.TyEncoder.html
[`TyEncoder`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/ty/codec/trait.TyDecoder.html