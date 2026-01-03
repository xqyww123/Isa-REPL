# 发布检查清单

在提交到 OPAM 之前，请确保完成以下所有步骤：

## 📋 代码质量

- [x] 所有代码已提交到 Git
- [x] 代码通过 `dune build` 构建
- [x] 没有编译警告
- [x] 代码格式一致

## 🧪 测试

- [x] 单元测试通过（如果有）
- [x] 集成测试通过
  - [x] test_connection - 连接测试
  - [x] simple_test - 简单评估
  - [x] example_rollback - 状态管理
  - [x] example_lex - 词法分析
  - [x] example_context - 上下文检索
- [x] 服务器稳定性测试通过
- [x] 所有示例程序能正常运行

## 📚 文档

- [x] README.md 完整且最新
- [x] CHANGES.md 包含版本更新信息
- [x] LICENSE 文件存在
- [x] API 文档完整（.mli 文件）
- [x] 示例代码有注释
- [x] PUBLISH.md 说明发布流程
- [x] QUICK_PUBLISH.md 快速指南

## 📦 包配置

- [x] dune-project 配置正确
  - [x] 版本号: 0.13.0
  - [x] 包名: isa_repl
  - [x] 作者信息正确
  - [x] 许可证: LGPL-3.0-or-later
  - [x] 依赖列表完整
- [x] isa_repl.opam 文件生成
- [x] 所有依赖包在 OPAM 中可用
  - [x] msgpck >= 1.7
  - [x] re
  - [x] unix (标准库)
  - [x] str (标准库)

## 🔖 版本管理

- [ ] 版本号遵循语义化版本规范
- [ ] CHANGES.md 更新为新版本
- [ ] Git tag 已创建: `ocaml-client-v0.13.0`
- [ ] Tag 已推送到远程仓库

## 🚀 发布准备

### 本地测试

```bash
# 1. 清理构建
opam exec -- dune clean

# 2. 重新构建
opam exec -- dune build @install

# 3. 本地安装测试
opam install . --working-dir

# 4. 测试导入
ocaml -stdin <<EOF
#require "isa_repl";;
open Isa_repl;;
EOF

# 5. 卸载测试安装
opam remove isa_repl
```

测试结果：
- [ ] 构建成功
- [ ] 安装成功
- [ ] 导入成功
- [ ] 卸载成功

### GitHub Release

- [ ] 在 GitHub 上创建 release
- [ ] Release 标题: "OCaml Client v0.13.0"
- [ ] Release 说明完整
- [ ] 附带 tarball（如果手动创建）

### OPAM 提交

使用 dune-release：
```bash
opam exec -- dune-release tag        # 创建 tag
opam exec -- dune-release distrib    # 创建发布包
opam exec -- dune-release publish distrib  # 发布到 GitHub
opam exec -- dune-release opam pkg   # 准备 opam 文件
opam exec -- dune-release opam submit  # 提交到 opam-repository
```

或手动提交：
- [ ] Fork ocaml/opam-repository
- [ ] 创建包目录 `packages/isa_repl/isa_repl.0.13.0/`
- [ ] 复制并编辑 opam 文件
- [ ] 添加 URL 和 checksum
- [ ] 创建 PR 到 opam-repository
- [ ] PR 标题: `[new package] isa_repl.0.13.0`

## ✅ 发布后

- [ ] 监控 OPAM CI 状态
- [ ] 响应维护者反馈
- [ ] PR 合并
- [ ] 在各平台测试安装
  - [ ] Linux
  - [ ] macOS
  - [ ] Windows (如果支持)
- [ ] 更新项目文档链接
- [ ] 发布公告（如果需要）

## 📝 注意事项

### 必须检查的事项

1. **依赖版本约束**
   - 确保版本约束不会太严格
   - 使用 `>=` 而不是 `=` （除非有特殊原因）

2. **构建系统**
   - 确保 `dune build -p isa_repl` 能工作
   - 不要依赖项目特定的配置

3. **许可证兼容性**
   - LGPL-3.0 与依赖的许可证兼容
   - msgpck 使用 ISC 许可证 ✓
   - re 使用 LGPL ✓

4. **文档链接**
   - 所有链接使用绝对路径
   - GitHub 链接指向正确的 tag/release

### 常见错误

❌ **不要**：
- 包含 `_build/` 目录
- 使用硬编码的绝对路径
- 依赖未发布的包
- 忘记更新 CHANGES.md
- 提交未经测试的代码

✅ **要做**：
- 使用干净的构建环境测试
- 在 PR 中提供测试证据
- 及时响应维护者反馈
- 保持 opam 文件简洁

## 🆘 遇到问题？

1. **构建失败**：检查依赖版本和 dune 配置
2. **CI 失败**：查看 CI 日志，在本地复现
3. **Checksum 错误**：重新下载 tarball 并计算
4. **找不到包**：等待 opam 更新（可能需要几小时）

## 联系方式

如有问题：
- 📧 Email: xqyww123@gmail.com
- 🐛 Issues: https://github.com/xqyww123/Isa-REPL/issues
- 💬 OPAM Discuss: https://discuss.ocaml.org/

---

**当所有检查项都完成后，你就可以发布了！** 🎉
