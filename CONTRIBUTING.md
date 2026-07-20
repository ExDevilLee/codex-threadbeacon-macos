# 参与 ThreadBeacon 开发

感谢你愿意改进 ThreadBeacon。项目当前优先保持状态窗口紧凑、只读、本地运行和隐私最小化，
不会为了功能数量把它扩展成另一个完整 Codex 客户端。

English contributions are welcome. Issues and pull requests may be written in English.

## 开始之前

- Bug 请先阅读中英文故障排查：
  [`中文`](docs/troubleshooting.md) / [`English`](docs/troubleshooting-en.md)。
- 功能建议应先描述真实使用问题、“一眼看状态”的价值和尝试过的替代方案。
- 安全漏洞遵循 [`SECURITY.md`](SECURITY.md)，不要提交公开 Issue。
- 不要提交真实任务标题、任务 ID、会话内容、SQLite、rollout、日志、本机绝对路径或凭据。

## 本地开发

要求：

- macOS 14 或更高版本。
- Xcode 与 Swift tools 6.1 或更高版本。
- 本机安装 Codex Desktop 或 Codex CLI，可用于自愿的真实数据验证。

运行测试：

```bash
./script/test.sh
```

构建并启动 App：

```bash
./script/build_and_run.sh --verify
```

请使用项目脚本；部分机器的 Command Line Tools 与 SwiftPM runtime 可能不一致，直接运行
`swift test` 不一定能代表项目验证结果。

## 修改原则

- 默认只读 `~/.codex`，不直接修改 Codex SQLite。
- 新数据源必须说明读取范围、稳定性、失败回退和隐私边界。
- 不从会话正文、静默或超时猜测状态。
- 不新增网络、写入、Accessibility 或其他系统权限，除非需求、风险和替代方案已经讨论清楚。
- 主界面保持一眼可读，诊断和详细信息放在按需入口。
- macOS 与 Windows 独立实现；共享状态语义和测试场景，不建立源码依赖。

## 文档与测试

代码修改至少运行：

```bash
./script/test.sh
git diff --check
```

修改 Markdown 后，从 `CodexClawProj` 根目录运行项目锁定版本的 markdownlint，例如：

```bash
npm run lint:md -- poc/codex-thread-status-macos/README.md
```

UI 变化需要验证浅色、深色、最小窗口宽度和中英文界面。涉及状态、Token、Subagent、声音、
窗口或数据源的修改，应增加或更新对应自动测试，并说明无法自动覆盖的人工验证。

## Commit 与 Pull Request

- 使用聚焦的 Conventional Commits，例如 `feat(settings): ...`、`fix(status): ...`、
  `docs(readme): ...`。
- 一个 Commit 只处理一个清晰主题，不顺带格式化或整理无关文件。
- Pull Request 使用仓库模板填写验证证据、隐私影响和兼容性边界。
- UI 截图必须脱敏，不得包含真实任务、桌面内容或本机身份信息。
