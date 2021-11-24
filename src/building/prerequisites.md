# 前置准备

## 依赖

在构建编译器之前，您需要安装以下内容:

* `python` 3 或者 2.7 (需要以 `python`名字。 `python2` 或者 `python3` 都将会不工作)
* `curl`
* `git`
* `ssl` 在 `libssl-dev` 或者 `openssl-devel` 中
* `pkg-config` 如果你在Linux中编译并且面向Linux

如果 构建 LLVM from source (the default),你需要补充以下工具:

* `g++` 5.1 或更新版本, `clang++` 3.5 或更新版本, 或 MSVC 2017 或更新版本.
* `ninja`, 或者 GNU `make` 3.81 或更新版本 (ninja 更加推荐, 特别是在 Windows 操作系统中)
* `cmake` 3.13.4 或更新版本

否则, 你需要安装 LLVM 并且 `llvm-config` 在路径中.
看 [这一章节获取更多信息][sysllvm].

[sysllvm]: ./suggested.md#skipping-llvm-build

### Windows

* 安装 [winget](https://github.com/microsoft/winget-cli)

`winget` 是一个 WIndows 下的包管理器.它将会使包的安装在 Windows 下更加简单

在终端运行以下命令：

```powershell
winget install python
winget install cmake
```

如果其中任何一个已经安装，winget 将会检测到它。
然后编辑系统的 `PATH` 变量并且添加 `C:\Program Files\CMake\bin`.

有关在WIndows下编译的更多信息看 [the `rust-lang/rust` README](https://github.com/rust-lang/rust#building-on-windows).

## 硬件

这些与其说是要求，不如说是要求 _推荐_:

* ~15GB 的空闲磁盘 (或更多，如果要做额外的构建，~25GB).
* \>= 8GB RAM
* \>= 2 cores
* 网络连接

性能好的电脑将会编译的更加快。如果你的电脑性能不是非常好，一个
常见的策略是只使用 `./x.py check` 在你的本地几期
并且当你推送一个PR分支的时候，让 CI 打包测试你的改动

## `rustc` 和工具链的安装

按照 [Rust book][install] 中给出的安装步骤安装
`rustc` 和平台上必要的C/++工具链。

[install]: https://doc.rust-lang.org/book/ch01-01-installation.html
