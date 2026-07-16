# Codex 红绿灯

简体中文 | [English](README-EN.md)

## 目标

这是一个独立的本地 macOS 小窗口，用于同时查看最近 Codex 主任务的状态。第一版验证的是“集中看状态是否比反复切回 Codex 更省注意力”，不包含 USB 小屏、Codex 控制或通知系统。

本项目是非官方社区工具，与 OpenAI 无隶属或背书关系。`Codex` 是其相应权利人的商标。

后续功能设想与验证顺序见 [`ROADMAP.md`](ROADMAP.md)。

## 运行

在本目录执行：

```bash
./script/build_and_run.sh --verify
```

脚本会构建并启动：

```text
dist/CodexThreadStatus.app
```

其他验证命令：

```bash
./script/test.sh
./script/probe.sh
```

`probe.sh` 只输出线程数和各状态数量，不输出任务标题或会话正文。

## App 图标

图标采用 `B1 Graphite / Code Beacon`：石墨黑圆角底板、白色代码括号和纵向红黄绿三灯。资源位置：

- `Resources/AppIcon-1024.png`：1024px PNG 母版。
- `Resources/AppIcon.icns`：App bundle 使用的标准 macOS 图标。

图标由本机 AppKit 确定性绘制，可重复生成：

```bash
./script/generate_app_icon.sh
```

`build_and_run.sh` 会把 `.icns` 复制到 App bundle，并写入 `CFBundleIconFile`。可单独验证：

```bash
./script/verify_app_icon.sh
```

## 界面

- 默认显示最近 8 个未归档 Codex 主任务，不显示 subagent 子线程。
- 每行显示状态灯、中文状态、任务标题和状态持续时间。
- 任务标题优先读取 `session_index.jsonl` 中该任务最后一次 rename 的名称；没有有效 rename 记录时回退 `threads.title`。
- 当前版本不读取或显示会话摘要与正文。
- 每 2 秒自动刷新，也可使用右上角刷新按钮手动刷新。
- 可使用右上角图钉按钮让窗口保持在其他 App 之前；选择会在重启后保留。
- 排序优先级为 `error`、`needsAction`、`running`、`justCompleted`、`idle`、`unknown`。

## 数据与隐私

App 只在本机读取：

- `~/.codex/state_5.sqlite`：以 SQLite read-only 模式读取任务元数据和 `rollout_path`。
- `~/.codex/session_index.jsonl`：只读匹配任务 ID，取最后一条有效 `thread_name` 作为 rename 后标题。
- rollout JSONL：每个任务最多读取文件末尾 2 MiB，只提取事件类型和时间戳，用于推导状态。

App 不提取 reasoning summary 或会话正文，不启动网络服务、不上传数据、不修改 Codex 数据，也不使用 Accessibility 权限。完整说明见 [`PRIVACY.md`](PRIVACY.md)。

## POC 边界

- `running` 来自“最新 turn 之后没有 `final` 或 `final_answer`，且 120 秒内仍有新事件”。
- 未闭合 turn 超过 120 秒没有新事件时降为 `unknown`，避免把中断线程长期误报为运行中。长时间无输出的工具调用也可能暂时被标为 `unknown`。
- `justCompleted` 保留 60 秒，之后派生为 `idle`。
- 第一版不从超时或静默推测 `error`、`needsAction`；只有未来获得明确证据时才显示。
- Codex 的 SQLite schema、session index 和 rollout 格式不是稳定公开 API，Codex 升级后可能需要适配。
- 为直接读取 `~/.codex`，POC 未启用 App Sandbox，也未做发布签名、公证或自动更新。
- 当前机器的 Command Line Tools 存在 SwiftPM Manifest/Test runtime 版本不一致；项目脚本通过临时、未跟踪的 `.build/swiftpm-libs/` 副本规避。请使用项目脚本，不要直接依赖 `swift test`。

## 卸载

停止进程并删除构建产物：

```bash
pkill -x CodexThreadStatus 2>/dev/null || true
rm -rf dist .build
```

本 POC 没有安装系统服务、登录项或全局配置。

## 开源与安全

- 本项目采用 [MIT License](LICENSE)。
- 安全问题报告方式见 [`SECURITY.md`](SECURITY.md)。
