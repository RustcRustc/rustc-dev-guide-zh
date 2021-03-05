# 运行测试

您可以使用x.py来运行测试。这是最基本的命令-您几乎永远不想使用它！–如下：
```
./x.py test
```
这将构建第1阶段的编译器，然后运行整个测试套件。 您可能不想经常执行此操作，因为这需要很长时间，并且无论如何bors/GitHub Actions都会为您执行此操作。（通常，在打开我认为已完成的PR后，我会在后台运行此命令，但很少这样做。-nmatsakis）

测试结果将被缓存，并且在测试过程中以前成功的测试将被`忽略`。stdout/stderr内容以及每个测试的时间戳文件都可以在build/ARCH/test/下找到。要强制重新运行测试（例如，如果测试运行程序未能注意到更改），您只需删除时间戳文件即可。

请注意，某些测试需要启用支持Python的gdb。您可以通过在gdb中使用`python`命令来测试gdb安装是否支持Python。调用后，您可以输入一些Python代码（例如`print（"hi"）`），然后返回，然后再按CTRL + D执行它。如果要从源代码构建gdb，则需要使用`--with-python = <path-to-python-binary>`进行配置。

## 运行部分测试套件
在特定PR上工作时，您通常将需要运行少量测试。例如，可以在修改rustc之后使用一个好的“冒烟测试”，以查看事物是否正常运行，如下所示：
```bash
./x.py test src/test/{ui,compile-fail}
```

这将运行`ui`和`compile-fail`测试套件。当然，测试套件的选择有些随意，并且可能不适合您正在执行的任务。例如，如果您正在使用debuginfo进行调试，那么使用debuginfo测试套件可能会更好：
```bash
./x.py test src/test/debuginfo
```

如果您只需要为任何给定的测试套件测试特定的测试子目录，则可以将该目录传递给`x.py test`：
```bash
./x.py test src/test/ui/const-generics
```
同样，您可以通过传递单个文件的路径来测试该文件：
```bash
./x.py test src/test/ui/const-generics/const-test.rs
```

### 只运行整洁测试脚本
```bash
./x.py test tidy
```
### 在标准库上运行测试
```bash
./x.py test --stage 0 library/std
```
### 运行整洁测试脚本并且在标准库上运行测试
```bash
./x.py test --stage 0 tidy library/std
```
### 使用阶段1编译器在标准库上运行测试
```bash
./x.py test library/std
```

通过列出要运行的测试套件，可以避免为根本没有更改的组件运行测试。

**警告：**请注意，bors仅在完整的第2阶段构建中运行测试；因此，尽管测试在第1阶段**通常**可以正常进行，但仍有一些局限。

## 运行单个测试

人们想要做的另一件事是运行**单个测试**，通常是他们试图修复的测试。如前所述，您可以传递完整的文件路径来实现这一目标，或者可以使用`--test-args`选项调用`x.py`：
```bash
./x.py test src/test/ui --test-args issue-1234
```
在后台，测试运行程序调用标准rust测试运行程序（与您在`#[test]`中获得的运行程序相同），因此此命令将最终筛选出名称中包含`issue-1234`的测试。（因此，`--test-args`是运行相关测试集合的好方法。）

## 编辑和更新参考文件
如果您有意更改了编译器的输出，或者正在进行新的测试，那么您可以将`--bless`传递给test子命令。例如，如果`src/test/ui`中的某些测试失败，则可以运行
```bash
./x.py test src/test/ui --bless
```
来自动调整`.stderr`，`.stdout`或者`.fixed`文件中的所有测试。当然，您也可以使用`--test-args your_test_name`标志来定位特定的测试，就像运行测试时一样。


## 传递`--pass $mode`

通过UI测试现在具有三种模式：`check-pass`， `build-pass` 和`run-pass`。当传递`--pass $mode`时，这些测试将被强制在给定的`$mode`下运行，除非指令测试文件存在指令`//ignore-pass`。您可以将`src/test/ui`中的所有测试作为`check-pass`运行：
```bash
./x.py test src/test/ui --pass check
```
通过传递`--pass $mode`，可以减少测试时间。对于每种模式，请参见[此处][mode]。

[mode]:./adding.md#不会导致编译错误的测试 

## 使用增量编译

您可以进一步启用`--incremental`标志，以在以后的重建中节省更多时间：
```bash
./x.py test src/test/ui --incremental --test-args issue-1234
```
如果您不想在每个命令中都包含该标志，则可以在`config.toml`中启用它：
```toml
[rust]
incremental = true
```
请注意，增量编译将使用比平常更多的磁盘空间。如果您担心磁盘空间，则可能需要不时地检查`build`目录的大小。

## 使用不同的“比较模式”运行测试
UI测试可能会有不同的输出，具体取决于编译器所处的特定“模式”。例如，当处于“非词法作用域生命周期”（"non-lexical liftimes",NLL）模式时，测试`foo.rs`将首先在`foo.nll.stderr`中寻找期望的输出，如果没有找到，则回到寻常的`foo.stderr`。要以NLL模式运行UI测试套件，可以使用以下命令：
```bash
./x.py test src/test/ui --compare-mode=nll
```
其它比较模式的示例是"noopt"，"migrat"和[revisions](./adding.html#版本)。

## 手动运行测试 
有时候，手动进行测试会更容易，更快捷。 大多数测试只是`rs`文件，因此您可以执行操作类似
```bash
rustc +stage1 src/test/ui/issue-1234.rs
```
这要快得多，但并不总是有效。例如，某些测试包含指定特定的编译器标志或依赖于其它crate的指令，并且如果没有这些选项，它们可能无法以相同的方式运行。