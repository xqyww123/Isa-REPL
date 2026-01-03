# Publishing to OPAM Repository

本指南说明如何将 `isa_repl` 包发布到 OPAM 官方仓库。

## 前提条件

### 1. 安装必要工具

```bash
# 安装 dune-release (用于自动化发布流程)
opam install dune-release -y

# 确保你有 GitHub 账号并配置了 SSH keys
```

### 2. 准备 GitHub 仓库

这个包应该发布在 Isa-REPL 的官方仓库中：
- 仓库: https://github.com/xqyww123/Isa-REPL
- 子目录: `clients/ocaml`

## 发布步骤

### 步骤 1: 准备发布

```bash
cd /path/to/Isa-REPL/clients/ocaml

# 确保所有更改都已提交
git status

# 确保构建成功
opam exec -- dune build @install

# 运行测试
./test_with_server.sh
```

### 步骤 2: 创建 Git Tag

```bash
# 在 Isa-REPL 根目录创建 tag
cd /path/to/Isa-REPL
git tag -a ocaml-client-v0.13.0 -m "OCaml client version 0.13.0"
git push origin ocaml-client-v0.13.0
```

### 步骤 3: 创建 GitHub Release

1. 访问 https://github.com/xqyww123/Isa-REPL/releases/new
2. 选择 tag: `ocaml-client-v0.13.0`
3. 标题: "OCaml Client v0.13.0"
4. 描述:

```markdown
# OCaml Client for Isabelle REPL v0.13.0

First public release of the OCaml client library.

## Features
- Complete OCaml translation of Python IsaREPL client
- Full REPL functionality (eval, lex, state management)
- Plugin system support
- Unicode/ASCII symbol conversion
- MessagePack-based communication
- Comprehensive examples and documentation

## Installation

\`\`\`bash
opam install isa_repl
\`\`\`

## Quick Start

\`\`\`ocaml
open Isa_repl

let () =
  let client = create "localhost:9000" "HOL" in
  let result = eval client "theory Test imports Main begin end" in
  close client
\`\`\`

## Documentation
- [README](clients/ocaml/README.md)
- [Examples](clients/ocaml/examples/)
- [Implementation Notes](clients/ocaml/IMPLEMENTATION_NOTES.md)

## Compatibility
- OCaml >= 4.14
- Compatible with Isabelle REPL server v0.13.0
```

5. 点击 "Publish release"

### 步骤 4: 准备 OPAM 包

```bash
cd clients/ocaml

# 使用 dune-release 创建发布
opam exec -- dune-release tag
opam exec -- dune-release distrib

# 这会创建一个 tarball
```

### 步骤 5: 提交到 OPAM Repository

有两种方式提交到 OPAM：

#### 方式 A: 使用 dune-release (推荐)

```bash
# 自动创建 opam-repository PR
opam exec -- dune-release opam pkg
opam exec -- dune-release opam submit
```

#### 方式 B: 手动提交

1. **Fork opam-repository**:
   ```bash
   # 访问 https://github.com/ocaml/opam-repository
   # 点击 "Fork"

   # Clone your fork
   git clone git@github.com:YOUR_USERNAME/opam-repository.git
   cd opam-repository
   ```

2. **创建包目录**:
   ```bash
   mkdir -p packages/isa_repl/isa_repl.0.13.0
   cd packages/isa_repl/isa_repl.0.13.0
   ```

3. **创建 opam 文件**:
   ```bash
   cp /path/to/clients/ocaml/isa_repl.opam ./opam
   ```

4. **编辑 opam 文件，添加 URL 信息**:
   ```opam
   opam-version: "2.0"
   name: "isa_repl"
   version: "0.13.0"
   synopsis: "OCaml client for Isabelle REPL"
   description: """
   A client library for connecting to and interacting with Isabelle REPL servers.
   Provides full functionality for code evaluation, lexing, state management,
   and plugin system integration.
   """
   maintainer: "Qiyuan Xu <xqyww123@gmail.com>"
   authors: "Qiyuan Xu <xqyww123@gmail.com>"
   license: "LGPL-3.0-or-later"
   homepage: "https://github.com/xqyww123/Isa-REPL"
   bug-reports: "https://github.com/xqyww123/Isa-REPL/issues"
   dev-repo: "git+https://github.com/xqyww123/Isa-REPL.git"

   depends: [
     "ocaml" {>= "4.14"}
     "dune" {>= "3.0"}
     "msgpck" {>= "1.7"}
     "re"
   ]

   build: [
     ["dune" "subst"] {dev}
     ["dune" "build" "-p" name "-j" jobs "@install"]
   ]

   url {
     src: "https://github.com/xqyww123/Isa-REPL/archive/ocaml-client-v0.13.0.tar.gz"
     checksum: "sha256=CHECKSUM_HERE"
   }
   ```

5. **计算 checksum**:
   ```bash
   # 下载 release tarball
   wget https://github.com/xqyww123/Isa-REPL/archive/ocaml-client-v0.13.0.tar.gz

   # 计算 sha256
   sha256sum ocaml-client-v0.13.0.tar.gz

   # 将结果填入 opam 文件的 checksum 字段
   ```

6. **提交 PR**:
   ```bash
   git checkout -b isa_repl.0.13.0
   git add packages/isa_repl/isa_repl.0.13.0/opam
   git commit -m "New package: isa_repl.0.13.0"
   git push origin isa_repl.0.13.0

   # 访问 GitHub 创建 PR
   ```

### 步骤 6: 等待审核

OPAM 维护者会审核你的 PR：
- 检查包是否能正确构建
- 验证依赖关系
- 检查元数据

通常需要几天到一周时间。

## 发布检查清单

- [ ] 所有测试通过
- [ ] 文档完整（README, CHANGES, etc.）
- [ ] LICENSE 文件存在
- [ ] dune-project 配置正确
- [ ] 版本号正确
- [ ] Git tag 已创建
- [ ] GitHub release 已发布
- [ ] opam 文件生成正确
- [ ] URL 和 checksum 正确
- [ ] 在本地测试安装: `opam install .`

## 本地测试

在提交到 opam-repository 之前，本地测试：

```bash
# 在包目录中
opam install .

# 测试是否能正确安装和使用
ocaml
# OCaml toplevel
# #require "isa_repl";;
# open Isa_repl;;
```

## 更新包

发布新版本时：

1. 更新 `dune-project` 中的版本号
2. 更新 `CHANGES.md`
3. 创建新的 git tag
4. 重复上述发布步骤

## 常见问题

### Q: 包名应该是什么？
A: 使用 `isa_repl`（下划线），这是 OCaml 约定。

### Q: 如何处理 monorepo？
A: 可以使用 git tag 来标识特定子项目的版本，如 `ocaml-client-v0.13.0`。

### Q: 构建失败怎么办？
A: 确保：
- 所有依赖都在 opam 中可用
- dune 文件配置正确
- 在干净环境中能构建

### Q: 如何处理依赖冲突？
A: 在 opam 文件中明确指定版本约束。

## 参考资源

- [OPAM 官方文档](https://opam.ocaml.org/doc/)
- [dune-release 文档](https://github.com/ocamllabs/dune-release)
- [OPAM 包发布指南](https://opam.ocaml.org/doc/Packaging.html)
- [opam-repository](https://github.com/ocaml/opam-repository)

## 联系方式

如有问题，请联系：
- 邮件: xqyww123@gmail.com
- GitHub Issues: https://github.com/xqyww123/Isa-REPL/issues
