# 编译器测试框架
 <!-- toc -->
Rust项目可以运行各种不同的测试，（它们）由构建系统（`x.py test`）编排。测试编译器本身的主要测试工具是一个叫做compiletest的工具（位于[`src/tools/compiletest`]目录）。本节简要介绍如何设置测试框架，然后将会详细介绍[如何运行测试](./running.html)和[如果添加新测试](./adding.html)


[`src/tools/compiletest`]: https://github.com/rust-lang/rust/tree/master/src/tools/compiletest


## Compiletest测试套件
compiletest测试位于[`src/test`]的目录树中。您会在其中看见一系列的子目录（例如`ui`，`run-make`等）。每一个这样的目录都被称为**测试套件**-它们包含一组以不同模式运行的测试。

[`src/test`]: https://github.com/rust-lang/rust/tree/master/src/test 

下列是一个对于测试套件及其含义的简要概述。在某些情况下，测试套件会连接到手册的各部分，以提供更多信息细节。
- [`ui`]((./adding.html#ui))-从编译和/或运行测试中检查正确的stdout/stderr的测试
- `run-pass-valgrind`-应该与valgrind一起运行的测试
- `pretty`-针对Rust的“打印美化器”进行测试，从AST生成有效的Rust代码
- `debuginfo`-在gdb或lldb中运行并查找调试信息的测试
- `codegen`-编译然后测试生成的LLVM代码，以确保我们预期的优化生效的测试。欲了解如何编写此类测试的信息，请参见[LLVM docs](https://llvm.org/docs/CommandGuide/FileCheck.html)
- `codegen-units`-有关[单态化](../backend/monomorph.md)和CGU分区的测试
- `assembly`-与`codegen`测试类似，但会验证程序集输出以确保LLVM目标后端可以处理提供的代码。
- `mir-opt`-检查部分生成的MIR，以确保我们在正确构建事物并且正在进行我们期望的优化的测试。
- `incremental`-针对增量编译的测试，检查当执行某些特定修改后，我们能否重用以前的编译结果
- `run-make`-基本上只执行`Makefile`的测试，非常的灵活但是编写起来也会非常麻烦。
- `rustdoc`-针对rustdoc的测试，确保生成的文件中含有期望的文档内容。
- `rustfix`-应用了 [diagnostic suggestions](../diagnostics.md#suggestions)和[`rustfix`](https://github.com/rust-lang/rustfix/) crate的测试
- `*-fulldeps`-与上述相同，单表示测试依赖除`std`有以外的东西（因此必须构建这些东西）

## 其它测试
<!-- Tidy 是否翻译 -->
Rust构建系统可以处理其它的各种测试，包括：
- **Tidy**-这是一个自定义的工具，用于验证源代码风格和编码规范，例如拒绝长行。在[关于编码规范部分](../conventions.html#formatting）有更多的信息。

范例：`./x.py test tidy`

- **格式**-Rustfmt与构建系统集成在一起，用以在整个编译器中实施统一的样式。在CI中，我们检查格式是否正确。 格式检查也可以通过上述Tidy工具自动运行。
- **单元测试**-Rust标准库和许多Rust软件包都包含典型的Rust`#[test]`单元测试。在后台，`x.py`将对每个软件包运行`cargo test`来运行所有测试。

范例：`./x.py test library/std`

- **文档测试**-嵌入在Rust文档中的示例代码是通过`rustdoc --test`执行的。例如：

`./x.py test src/doc`-对所有在`src/doc`中的运行`rustdoc --test`。

`./x.py test --doc library/std` -在标准库上运行`rustdoc --test`。

- **链接检查**-一个用于验证文档中的`href`链接的小工具。
- **分发检查**-用于验证由构建系统创建的源代码分发压缩包的解压、构建和运行所有测试。

范例：`./x.py test distcheck`

- **工具测试**-Rust随附的软件包也都可以正常运行（通常通过在目录中运行`cargo test`）。这包括诸如cargo，clippy，rustfmt，rls，miri，bootstrap（测试Rust构建系统本身）之类的东西。

- **Cargo测试**- 这是一个小型的工具，它在一些重要项目（如`servo`，`ripgrep`，`tokei`等）上运行`cargo test`，以确保没有他们没有任何显著回归。

范例：- `./x.py test src/tools/cargotest`

## 测试基础架构
当GitHub上一个提交请求（Pull Request）被打开之后,[GitHub Actions]将自动启动一个构建，这个构建会在某些配置（x86_64-gnu-llvm-8 linux. x86_64-gnu-tools linux, mingw-check linux）下运行所有测试。本质上，在每个配置构建之后，它会运行`./x.py test`。

集成机器人[bors]用于协调主分支的合并，当一个PR被批准后，它将会进入一个[队列]，在这里将会使用GitHub Actions在一组广泛的平台上一个个地测试这些合并。由于并行作业数量的限制，除PR外，我们在[rust-lang-ci]组织下运行CI。大多数平台仅仅运行构建步骤，一些平台会运行一组受限的测试，只有一个子集可以运行全套的测试（参见 Rust的[platform tiers]）

[GitHub Actions]: https://github.com/rust-lang/rust/actions
[rust-lang-ci]: https://github.com/rust-lang-ci/rust/actions
[bors]: https://github.com/servo/homu
[queue]: https://bors.rust-lang.org/queue/rust
[platform tiers]: https://forge.rust-lang.org/release/platform-support.html#rust-platform-support

## 使用Docker镜像进行测试
Rust树包含[`src/ci/docker`]中GitHub Actions所使用的平台的[Docker]镜像定义。[`src/ci/docker/run.sh`]被用于构建、运行Docker镜像，在镜像中构建Rust，然后运行测试。

您可以在本地开发计算机上运行这些映像。这对于测试与本地系统不同的环境可能会有所帮助。首先，您需要在Linux，Windows或macOS系统上安装Docker（通常Linux将比Windows或macOS快得多，因为稍后将使用虚拟机来模拟Linux环境）。想要在容器中启动bash shell进入交互模式，请运行`src/ci/docker/run.sh --dev <IMAGE>`，其中`<IMAGE>`是`src/ci/docker`中目录名称之一（例如`x86_64-gnu`是一个相当标准的Ubuntu环境）。


docker脚本将以只读模式挂载本地rust源树，以读写模式挂载`obj`目录。所有的编译器工件都将被存储在`obj`目录中。shell将会从`obj`目录开始。从那里，您可以运行`../src/ci/run.sh`，这将运行镜像定义的构建。

另外，您可以运行单个命令来执行特定的任务。例如，您可以运行`python3 ../x.py test src/test/ui`来仅运行UI测试。请注意[`src / ci / run.sh`]脚本中有一些配置可能需要重新创建。特别是，在您的`config.toml`中设置`submodules=false`，以便它不会尝试修改只读目录。

有关使用Docker镜像的一些其他说明：
- 一些std测试需要IPv6的支持。Linux上的Docker似乎默认禁用了它。在创建容器之前，运行[`enable-docker-ipv6.sh`]中的命令以启用IPv6。这仅需要执行一次。

- 当您退出shell之后，容器将自动删除，但是构建工件仍然保留在`obj`目录中。如果您在不同的Docker映像之间切换，则存储在`obj`目录中的先前环境中的工件可能会混淆构建系统。有时候在容器内构建之前，您需要删除部分或全部`obj`目录。
- 容器是一个只有最小数量的包的准系统，您可能需要安装`apt install less vim`之类的东西。
- 您可以在容器内打开多个shell。首先您需要知道容器的名字（一个简短的哈希），它显示在shell的提示符中，或者您可以在容器外部运行`docker container ls`列出可用的容器。使用容器名称运行`docker exec -it <CONTAINER> /bin/bash`，其中`<CONTAINER>`是例如`4ba195e95cef`的容器名称。


[Docker]: https://www.docker.com/
[`src/ci/docker`]: https://github.com/rust-lang/rust/tree/master/src/ci/docker
[`src/ci/docker/run.sh`]: https://github.com/rust-lang/rust/blob/master/src/ci/docker/run.sh
[`src/ci/run.sh`]: https://github.com/rust-lang/rust/blob/master/src/ci/run.sh
[`enable-docker-ipv6.sh`]: https://github.com/rust-lang/rust/blob/master/src/ci/scripts/enable-docker-ipv6.sh

## 在远程计算机上运行测试

测试可以在远程计算机上运行（例如：针对不同的架构测试构建）。这通过使用构建计算机上的`remote-test-client`向`remote-test-server`发送测试程序并在远程计算机上运行实现。`remote-test-server`执行测试程序并且将结果返回给构建计算机。`remote-test-server`提供*未经身份验证的远程代码执行*，所以在使用它的时候请务必小心。

为此，首先为远程计算机构建`remote-test-server`，例如，用RISC-V

```sh
./x.py build src/tools/remote-test-server --target riscv64gc-unknown-linux-gnu
```
二进制文件将在`./build/$HOST_ARCH/stage2-tools/$TARGET_ARCH/release/remote-test-server`被创建。将该文件复制到远程计算机。

在远程计算机上，运行带有`remote`参数的`remote-test-server`（以及可选的-v表示详细输出）。 输出应如下所示：

```sh
$ ./remote-test-server -v remote
starting test server
listening on 0.0.0.0:12345!
```
您可以通过连接到远程测试服务器并发送`ping\n`来测试其是否正常工作。 它应该回复`pong`：
```sh
$ nc $REMOTE_IP 12345
ping
pong
```
要使用远程运行程序运行测试，请设置`TEST_DEVICE_ADDR`环境变量，然后照常使用`x.py`。例如，要对IP地址为`1.2.3.4`的RISC-V计算机运行`ui`测试，请使用
```sh
export TEST_DEVICE_ADDR="1.2.3.4:12345"
./x.py test src/test/ui --target riscv64gc-unknown-linux-gnu
```
如果`remote-test-server`是使用详细标志运行的，则测试计算机上的输出可能类似于
```
[...]
run "/tmp/work/test1007/a"
run "/tmp/work/test1008/a"
run "/tmp/work/test1009/a"
run "/tmp/work/test1010/a"
run "/tmp/work/test1011/a"
run "/tmp/work/test1012/a"
run "/tmp/work/test1013/a"
run "/tmp/work/test1014/a"
run "/tmp/work/test1015/a"
run "/tmp/work/test1016/a"
run "/tmp/work/test1017/a"
run "/tmp/work/test1018/a"
[...]
```
测试实在运行`x.py`的计算机上构建的而不是在远程计算机上。意外构建错误的测试可能会失败，并且将无需在远程计算机上运行。

## 在模拟器上测试

某些平台已通过仿真器针对尚不可用的体系结构进行了测试。对于良好支持标准库和宿主系统支持TCP/IP网络的体系结构，请参见上述有关在远程计算机上测试的说明（在这种情况下将模拟远程计算机）


这是一组用于在仿真环境中协调运行测试的工具。设置了诸如 `arm-android` 和`arm-unknown-linux-gnueabihf`之类的平台，以在GitHub Actions的仿真下自动运行测试。接下来我们将窥探一下如何在仿真下运行目标测试。

[armhf-gnu]的Docker镜像包含[QEMU]来模拟ARM CPU架构.Rust树中包含的工具[remote-test-client]和[remote-test-server]是将测试程序和库发送到仿真计算机，并在仿真计算机中运行测试并读取结果的程序。Docker被设置为启动`remote-test-server` ，并且用`remote-test-server`来构建工具与服务器通信以协调正在运行的测试。（请参阅[src/bootstrap/test.rs]）

> TODO:
> 是否支持使用IOS模拟器？
>
> 同时我也也不清楚wasm或asm.js测试如何运行

[armhf-gnu]: https://github.com/rust-lang/rust/tree/master/src/ci/docker/host-x86_64/armhf-gnu/Dockerfile
[QEMU]: https://www.qemu.org/
[remote-test-client]: https://github.com/rust-lang/rust/tree/master/src/tools/remote-test-client
[remote-test-server]: https://github.com/rust-lang/rust/tree/master/src/tools/remote-test-server
[src/bootstrap/test.rs]: https://github.com/rust-lang/rust/tree/master/src/bootstrap/test.rs


## Crater
[Crater](https://github.com/rust-lang/crater)是一个为[crates.io](https://crates.io)中的*每个*测试进行编译和运行的工具。它主要用于当实施潜在的重要更改时，检查破坏的程度，并且通过运行beta和stable编译器版本来确保没有破坏。

### 何时运行Crater

如果您的PR对编译器造成了很大更改或者可能导致损坏，那么您应该运行crater。如果您不确定，请随时询问您的PR审阅者。

### 要求运行Crater

rust小组维护了一些机器，这些机器可以用来PR引入修改下运行crater。如果您的PR需要运行cater，请在PR线中为会审小组留下评论。请告知团队是否需要运行`check-only`crater，运行`build-only`crater或者运行`build-and-test`crater。区别主要时间。保守选项（如果您不确定）是运行build-and-test。如果您的修改仅在编译时（例如，实现新trait）起作用，那么您只需要check run。

会审小组会将您的PR入队，并且在结果准备好时将结果发布。check run大约需要3~4天，其它两个平均需要5~6天。

尽管crater非常有用，但注意一些注意事项也很重要：

- 并非所有代码都在crates.io上！ 也有很多代码在GitHub和其它地方的仓库中。此外，公司可能不希望发布其代码。因此，crater运行成功并不是万无一失的神奇绿灯。您仍然需要小心。
- Crater仅在x86_64上运行Linux构建。 因此，其它体系结构和平台没有测试。最重要的是，这包括Windows。
- 许多crate未经测试。许多crate未经测试。这可能有很多原因，包括crate不再编译（例如使用的旧的nightly特性），测试失败或不稳定，需要网络访问或其他原因。
- 在crater运行之前，必须先使用`@bors try`来成功构建工件。这意味着，如果您的代码无法编译，则无法运行crater。


## 性能运行
为了改善编译器的性能并防止性能下降，需要进行大量工作。“性能运行”用于比较大量流行crate在不同配置下编译器的性能。不同的配置包括“新构建”，带有增量编译的构建等。

性能运行的结果是两个版本的编译器之间的比较（通过它们的提交哈希（commit hash））。

如果您的PR可能会影响性能，尤其是可能对性能产生不利影响，则应请求进行性能测试。

## 进一步阅读

以下博客文章也可能会引起您的兴趣：
- brson的经典文章[“如何测试Rust”] [howtest]

[howtest]: https://brson.github.io/2017/07/10/how-rust-is-tested


