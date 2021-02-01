# 如何构建并运行编译器

编译器是使用 `x.py` 工具进行构建。需要安装Python才能运行它。在此之前，如果您打算修改 `rustc` 的代码，则需要调整编译器的配置。默认配置面向的是编译器用户而非开发人员。有关如何安装 Python 和其他依赖，请参阅[下一章](./prerequisites.md)。 

## 获取源代码

修改`rustc`的第一步是 clone 其代码仓库： 

```bash
git clone https://github.com/rust-lang/rust.git
cd rust
```

## 创建一个 config.toml

首先先将 [`config.toml.example`] 复制为 `config.toml`:

[`config.toml.example`]: https://github.com/rust-lang/rust/blob/master/config.toml.example

```bash
cp config.toml.example config.toml
```

然后，您将需要打开这个文件并修改以下配置（根据需求不同可能也要修改其他的配置，例如`llvm.ccache`）：

```toml
[llvm]
# Indicates whether the LLVM assertions are enabled or not
assertions = true

[rust]
# Whether or not to leave debug! and trace! calls in the rust binary.
# Overrides the `debug-assertions` option, if defined.
#
# Defaults to rust.debug-assertions value
#
# If you see a message from `tracing` saying
# `max_level_info` is enabled and means logging won't be shown,
# set this value to `true`.
debug-logging = true

# Whether to always use incremental compilation when building rustc
incremental = true
```

如果您已经构建过了`rustc`，那么您可能必须执行`rm -rf build`才能使配置更改生效。 
请注意，`./x.py clean` 不会导致重新构建LLVM。
因此，如果您的配置更改影响LLVM，则在重新构建之前，您将需要手动`rm -rf build /`。

## `x.py`是什么？

 `x.py` 是用于编排 `rustc` 代码仓库中的工具的脚本。 它可以构建文档，运行测试以及编译 `rustc` 的脚本。现在它替代了以前的makefile，是构建`rustc`的首选方法。下面将会介绍使用`x.py`来有效处理常见任务的不同方式。

注意本章将侧重于如何把 `x.py` 用起来，因此介绍的内容比较基础。如果您想了解有关 `x.py` 的更多信息，请阅读[其README.md](https://github.com/rust-lang/rust/blob/master/src/bootstrap/README.md)。 要了解有关引导过程以及为什么需要使用 `x.py` 的更多信息，请[阅读这一章][bootstrap]。 

### 更方便地运行`x.py`

在 `src/tools/x` 中有一个 `x.py` 的二进制封装。它只是调用 `x.py` ，但是它可以直接在整个操作系统范围内安装并可以从任何子目录运行。 它还会查找并使用适当版本的 `python`。

您可以使用 `cargo install --path src/tools/x` 安装它。

[bootstrap]: ./bootstrapping.md

## 构建编译器

要完整构建编译器，请运行 `./x.py build`。这将构建包括 `rustdoc` 在内的 stage1 编译器，并根据您签出的源代码生成可用的编译器工具链。 

请注意，构建将需要相对大量的存储空间。推荐预留 10 到 15 GB 以上的可用空间来构建编译器。 

 `x.py` 有很多选项，这些选项可以帮助你减少编译时间或者适应你对其他内容的修改：

 ```txt
Options:
    -v, --verbose       use verbose output (-vv for very verbose)
    -i, --incremental   use incremental compilation
        --config FILE   TOML configuration file for build
        --build BUILD   build target of the stage0 compiler
        --host HOST     host targets to build
        --target TARGET target targets to build
        --on-fail CMD   command to run on failure
        --stage N       stage to build
        --keep-stage N  stage to keep without recompiling
        --src DIR       path to the root of the rust checkout
    -j, --jobs JOBS     number of jobs to run in parallel
    -h, --help          print this help message
 ```

如果你只是在 hacking 编译器，则通常构建stage 1编译器就足够了，但是对于最终测试和发布，则需要使用stage 2编译器。

`./x.py check` 可以快速构建 rust 编译器。 当您在执行某种“基于类型的重构”（例如重命名方法或更改某些函数的签名）时，它特别有用。

创建`config.toml`之后，就可以运行`x.py`了。 虽然 `x.py` 有很多选项，但让我们从本地构建 rust 的最佳“一键式”命令开始： 

```bash
./x.py build -i library/std
```

*看起来*好像这只会构建`std`，但事实并非如此。

该命令的实际作用如下：

- 使用 stage0 编译器构建 `std`（增量构建）
- 使用 stage0 编译器构建 `rustc`（增量构建）
  - 产生的编译器即为 stage1 编译器
- 使用 stage1 编译器构建 `std`（不能增量构建）

最终产品 (stage1编译器 + 使用该编译器构建的库）是构建其他 rust 程序所需要的（除非使用`#![no_std]`或`#![no_core]`）。

该命令自动启用 `-i` 选项，该选项启用增量编译。这会加快该过程的前两个步骤：如果您的修改比较小，我们应该能够使用您上一次编译的结果来更快地生成stage1编译器。

不幸的是，stage1 库的构建不能使用增量编译来加速。这是因为增量编译仅在连续运行*同一*编译器两次时才起作用。
由于我们每次都会构建一个 *新的 stage1 编译器* ，旧的增量结果可能不适用。
**因此您可能会发现构建 stage1 `std` 对您的工作效率来说是一个瓶颈** —— 但不要担心，这有一个（hacky的）解决方法。请参阅下面[“推荐的工作流程”](./suggested.md)部分。

请注意，这整个命令只是为您提供完整 rustc 构建的一部分。**完整**的 rustc 构建（即 `./x.py build
--stage 2 compiler/rustc` 命令）还有几个步骤：

- 使用 stage1编译器构建 rustc。
  - 此处生成的编译器为 stage2 编译器。
- 使用 stage2 编译器构建 `std`。
- 使用 stage2 编译器构建 `librustdoc` 和其他内容。

<a name=toolchain></a>

## 构建特定组件

- 只构建 core 库

```bash
./x.py build library/core
```

- 只构建 core 库和 `proc_macro` 库

```bash
./x.py build library/core library/proc_macro
```

有时您可能只想测试您正在处理的部分是否可以编译。
使用这些命令，您可以在进行较为完整的构建之前进行测试。
如前所示，您还可以在命令的最后传递选项，例如 `--stage`。

## 创建一个rustup工具链

成功构建rustc之后，您在构建目录中已经创建了一堆文件。为了实际运行生成的`rustc`，我们建议创建两个rustup工具链。 第一个将运行stage1编译器（上面构建的结果）。第二个将执行stage2编译器（我们尚未构建这个编译器，但是您可能需要在某个时候构建它；例如，如果您想运行整个测试套件）。

```bash
rustup toolchain link stage1 build/<host-triple>/stage1
rustup toolchain link stage2 build/<host-triple>/stage2
```

 `<host-triple>` 一般来说是以下三者之一:

- Linux: `x86_64-unknown-linux-gnu`
- Mac: `x86_64-apple-darwin`
- Windows: `x86_64-pc-windows-msvc`

现在，您可以运行构建出的`rustc`。 如果使用`-vV`运行，则应该可以看到以`-dev`结尾的版本号，表示从本地环境构建的版本：

```bash
$ rustc +stage1 -vV
rustc 1.48.0-dev
binary: rustc
commit-hash: unknown
commit-date: unknown
host: x86_64-unknown-linux-gnu
release: 1.48.0-dev
LLVM version: 11.0
```

## 其他 `x.py` 命令

这是其他一些有用的`x.py`命令。其中一部分我们将在其他章节中详细介绍：

- 构建:
  - `./x.py build --stage 1` – 使用stage 1 编译器构建所有东西，不止是 `std`
  - `./x.py build` – 构建 stage2 编译器
- 运行测试 （见 [运行测试](../tests/running.html) 章节）:
  - `./x.py test --stage 1 src/libstd` – 为`libstd`运行 `#[test]` 测试

  - `./x.py test --stage 1 src/test/ui` – 运行 `ui` 测试套件

  - `./x.py test --stage 1 src/test/ui/const-generics` - 运行`ui` 测试套件下的 `const-generics/` 子文件夹中的测试

  - `./x.py test --stage 1 src/test/ui/const-generics/const-types.rs` 

    - 运行`ui`测试组下的 `const-types.rs` 中的测试

### 清理构建文件夹

有时您可能会想要清理掉一切构建的产物并重新开始，一般情况下这么做并没有必要，如果你想要这么做的原因是 `rustbuild`无法正确执行，你应该报告一个 bug 来告知我们什么出错了。
如果确实需要清理所有内容，则只需运行一个命令！

```bash
./x.py clean
```

`rm -rf build` 也能达到效果，但这也会导致接下来你要重新构建LLVM，即使在相对快的计算机上这也会花费比较长的时间。