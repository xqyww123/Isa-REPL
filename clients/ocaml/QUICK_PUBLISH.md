# 快速发布指南

## 准备工作（只需一次）

```bash
# 1. 安装 dune-release
opam install dune-release -y

# 2. 配置 GitHub token（用于自动创建 PR）
# 访问 https://github.com/settings/tokens
# 创建一个 token，权限勾选 "public_repo"
# 然后设置环境变量：
export GITHUB_TOKEN="your_token_here"
```

## 发布步骤

### 1. 最终检查

```bash
cd /path/to/Isa-REPL/clients/ocaml

# 确保所有文件都已提交
git status

# 确保构建成功
opam exec -- dune clean
opam exec -- dune build @install

# 运行测试
./test_with_server.sh

# 本地安装测试
opam install . --working-dir
```

### 2. 使用 dune-release 发布（推荐）

```bash
# 2.1 创建 tag（如果还没有）
opam exec -- dune-release tag

# 2.2 创建 tarball
opam exec -- dune-release distrib

# 2.3 发布到 GitHub（创建 release）
opam exec -- dune-release publish distrib

# 2.4 提交到 opam-repository
opam exec -- dune-release opam pkg
opam exec -- dune-release opam submit
```

### 3. 手动发布（备选方案）

如果 dune-release 有问题，可以手动操作：

#### 3.1 创建 GitHub Release

```bash
# 在 Isa-REPL 根目录
cd /path/to/Isa-REPL

# 创建 tag
git tag -a ocaml-client-v0.13.0 -m "OCaml client v0.13.0"
git push origin ocaml-client-v0.13.0
```

然后访问 https://github.com/xqyww123/Isa-REPL/releases/new 创建 release。

#### 3.2 手动提交到 OPAM

```bash
# Fork opam-repository
git clone git@github.com:YOUR_USERNAME/opam-repository.git
cd opam-repository

# 创建包目录
mkdir -p packages/isa_repl/isa_repl.0.13.0
cd packages/isa_repl/isa_repl.0.13.0

# 复制 opam 文件
cp /path/to/clients/ocaml/isa_repl.opam ./opam

# 添加 URL 部分（在 opam 文件末尾）
cat >> opam << 'EOF'

url {
  src: "https://github.com/xqyww123/Isa-REPL/releases/download/ocaml-client-v0.13.0/isa_repl-0.13.0.tbz"
  checksum: [
    "sha256=REPLACE_WITH_ACTUAL_CHECKSUM"
    "sha512=REPLACE_WITH_ACTUAL_CHECKSUM"
  ]
}
EOF

# 计算 checksum
wget https://github.com/xqyww123/Isa-REPL/releases/download/ocaml-client-v0.13.0/isa_repl-0.13.0.tbz
sha256sum isa_repl-0.13.0.tbz
sha512sum isa_repl-0.13.0.tbz

# 将结果填入 opam 文件

# 提交 PR
git checkout -b isa_repl.0.13.0
git add packages/isa_repl/isa_repl.0.13.0/opam
git commit -m "[new package] isa_repl.0.13.0"
git push origin isa_repl.0.13.0
```

然后访问 GitHub 创建 PR 到 ocaml/opam-repository。

## 发布后

1. 等待 OPAM CI 测试通过
2. 响应维护者的反馈
3. PR 合并后，包会在几小时内可用

## 测试安装

```bash
# 更新 opam
opam update

# 安装包
opam install isa_repl

# 测试
ocaml
# #require "isa_repl";;
# open Isa_repl;;
```

## 常见问题

### Q: dune-release 失败了怎么办？

可能的原因：
1. Git 仓库不干净：确保所有更改都已提交
2. 没有配置 GitHub token：按照上面的步骤配置
3. 网络问题：使用手动方式

### Q: 如何更新已发布的包？

1. 修复问题
2. 更新版本号（在 dune-project 中）
3. 更新 CHANGES.md
4. 重复发布步骤

### Q: tarball 应该包含什么？

tarball 应该只包含必要的源代码文件，不包括：
- `_build/` 目录
- `.git/` 目录
- 测试临时文件
- IDE 配置文件

dune-release 会自动处理这些。

## 最小化手动步骤

最简单的发布命令序列：

```bash
cd clients/ocaml
opam exec -- dune-release tag
opam exec -- dune-release distrib
opam exec -- dune-release publish distrib
opam exec -- dune-release opam pkg
opam exec -- dune-release opam submit
```

然后等待 OPAM 维护者审核即可！

## 帮助

如果遇到问题：
- 查看 `PUBLISH.md` 的详细说明
- 访问 https://opam.ocaml.org/doc/Packaging.html
- 在 Isa-REPL 仓库开 issue
