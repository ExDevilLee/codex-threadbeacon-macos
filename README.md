# ThreadBeacon for Codex

简体中文 | [English](README-EN.md)

## 目标

ThreadBeacon 是一个用于集中查看 Codex Desktop 与 Codex CLI 主任务状态的原生 macOS
小窗口。第一版验证的是“集中看状态是否比反复切回 Codex 更省注意力”，不包含 USB
小屏或 Codex 控制。
当前版本可提示可靠识别的主任务完成事件，以及本机日志中明确记录的 HTTP 429/503
服务重试与最终失败；授权等待仍没有可靠的只读数据源。

本项目是非官方社区工具，与 OpenAI 无隶属或背书关系。`Codex` 是其相应权利人的商标。

后续功能设想与验证顺序见 [`ROADMAP.md`](ROADMAP.md)。

GitHub 同类项目、实现差异、命名风险与可参考功能候选见
[`docs/prior-art-review.md`](docs/prior-art-review.md)。

独立 app-server 对 Codex Desktop 实时状态的验证结果见
[`docs/app-server-integration-poc.md`](docs/app-server-integration-poc.md)。

429/503 服务异常的数据源、状态规则和隐私边界见
[`docs/service-incident-monitoring.md`](docs/service-incident-monitoring.md)。

Codex CLI 任务兼容性 POC 的验证结果与当前边界见
[`docs/codex-cli-compatibility.md`](docs/codex-cli-compatibility.md)。

## 运行

在本目录执行：

```bash
./script/build_and_run.sh --verify
```

脚本会构建并启动：

```text
dist/ThreadBeacon.app
```

其他验证命令：

```bash
./script/test.sh
./script/probe.sh
```

`probe.sh` 只输出线程数和各状态数量，不输出任务标题或会话正文。

## App 图标

<img src="Resources/AppIcon-1024.png" alt="ThreadBeacon App 图标" width="256">

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

## 提示音资源

Beacon、Chime、Pulse、Alert、Resolve 和 Knock 是项目脚本确定性生成的短音效，不来自
第三方音效包。任务完成默认使用 Chime，429/503 服务异常默认使用下降警示音
Alert；两类通知都可自由选择六种声音。可重复生成并验证：

```bash
./script/generate_sound_assets.sh
./script/verify_sound_assets.sh
```

## 界面

- 默认显示最近 8 个未归档 Codex Desktop 与 Codex CLI 主任务，不显示 subagent 子线程；
  已收藏的归档主任务可在收藏筛选中继续显示。
- 每行显示状态灯、中文状态、任务标题和状态持续时间。
- 创建过 Subagent 的主任务会在标题右侧显示直接 Subagent 总数；这是历史关系数量，
  不代表当前正在运行的数量。
- 点击 Subagent 数量可在主任务下展开直接子任务，以 `Agent 别名 ｜ 标题` 显示名称，
  并显示状态、最近活动和自身累计 Token；悬浮或点击 info 可查看昵称、角色、模型、
  Reasoning 和 Token 明细。只在展开时读取对应子任务，不读取会话正文，也不显示第二层
  任务树。
- 每行右侧紧凑显示会话累计 Token；悬浮 info 图标可查看输入、缓存输入、非缓存
  输入、输出、Reasoning、当前 turn、缓存率和更新时间，点击可保持详情打开。
- 任务标题优先读取 `session_index.jsonl` 中该任务最后一次 rename 的名称；没有有效 rename 记录时回退 `threads.title`。
- 当前版本不读取或显示会话摘要与正文。
- 每 2 秒自动刷新，也可使用右上角刷新按钮手动刷新。
- 标题栏可暂停或恢复自动监听；暂停期间仍可手动刷新，重新启动 App 后默认恢复监听。
- 可使用右上角图钉按钮让窗口保持在其他 App 之前；选择会在重启后保留。
- 右键主任务可收藏、置顶或忽略。收藏形成独立的长期关注集合，不改变排序；标题栏
  星标按钮可在全部任务与仅收藏之间切换，筛选状态会在重启后保留。
- 已归档收藏显示灰色`已归档`状态，保留可读取的 rename 标题和 Token，不显示为运行中，
  也不触发完成或异常提示音。
- 状态优先级始终高于置顶，同一状态内置顶任务优先；普通忽略会在该任务出现新 turn 时
  自动恢复。
- 存在已忽略任务时，标题栏显示 `eye.slash` 管理按钮，可逐项恢复或全部恢复。
- 标题栏扬声器按钮打开提示音设置；完成与 429/503 服务异常可分别关闭、从六种内置
  声音中选择并试听。启动、手动刷新和恢复监听不会补播历史事件。
- 429/503 自动重试显示黄色 `warning`，重试耗尽显示红色 `error`；同一异常 episode
  只播放一次警告音，失败不会误播完成音。
- 排序优先级为 `error`、`needsAction`、`warning`、`running`、`justCompleted`、`idle`、
  `unknown`。

## 数据与隐私

App 只在本机读取：

- `~/.codex/state_5.sqlite`：以 SQLite read-only 模式读取近期未归档任务及已收藏归档任务
  的元数据、`rollout_path`、归档状态、
  累计 `tokens_used`、父子任务关系，以及已展开直接 Subagent 的昵称、角色、模型和
  Reasoning effort。
- `~/.codex/session_index.jsonl`：只读匹配任务 ID，取最后一条有效 `thread_name` 作为 rename 后标题。
- rollout JSONL：每个任务最多读取文件末尾 2 MiB，只提取事件类型、时间戳和 Token
  数字字段，用于推导状态、Token 明细和 `task_complete` 完成事件。
- `~/.codex/logs_2.sqlite`：以 SQLite read-only 模式只读取当前可见任务的三个白名单
  target，从结构化日志中提取 turn ID、HTTP 429/503、重试次数和最终失败时间。

App 不读取 `codex_http_client::transport`，不提取 reasoning summary、会话正文、完整请求、
供应商 URL 或 request ID；不启动网络服务、不上传数据、不修改 Codex 数据，也不使用
Accessibility 权限。完整说明见 [`PRIVACY.md`](PRIVACY.md)。

## POC 边界

- `running` 来自“最新 turn 之后没有 `final` 或 `final_answer`，且 120 秒内仍有新事件”。
- 未闭合 turn 超过 120 秒没有新事件时降为 `unknown`，避免把中断线程长期误报为运行中。长时间无输出的工具调用也可能暂时被标为 `unknown`。
- `justCompleted` 保留 60 秒，之后派生为 `idle`。
- 当前 turn 通过两个累计 Token 快照做差；尾部缺少可靠基线时显示 `—`，不会使用
  单次调用数据猜测。
- 累计 Token 是模型历次调用处理量，不代表当前上下文长度，也不提供费用估算。
- 当前对新的 `task_complete` 播放一次完成音；对新的 429/503 episode 播放一次异常音。
  自动重试恢复后会清除 warning，重试耗尽的 error 会覆盖 rollout 中误导性的
  `task_complete`。
- 不从超时、静默或会话正文猜测 `error`、`warning`、`needsAction`。当前 `error` 和
  `warning` 只来自白名单日志中的 429/503 证据，授权状态仍未实现。
- Codex 的 SQLite schema、session index 和 rollout 格式不是稳定公开 API，Codex 升级后可能需要适配。
- 为直接读取 `~/.codex`，POC 未启用 App Sandbox，也未做发布签名、公证或自动更新。
- 当前机器的 Command Line Tools 存在 SwiftPM Manifest/Test runtime 版本不一致；项目脚本通过临时、未跟踪的 `.build/swiftpm-libs/` 副本规避。请使用项目脚本，不要直接依赖 `swift test`。

## 卸载

停止进程并删除构建产物：

```bash
pkill -x ThreadBeacon 2>/dev/null || true
rm -rf dist .build
```

本 POC 没有安装系统服务、登录项或全局配置。

## 开源与安全

- 本项目采用 [MIT License](LICENSE)。
- 安全问题报告方式见 [`SECURITY.md`](SECURITY.md)。

## 平台仓库

ThreadBeacon 的平台实现使用独立仓库维护。当前仓库只包含原生 macOS App；其他平台
实现使用各自仓库独立开发和发布。

Related projects：

- [Codex ThreadBeacon for Windows](https://github.com/ExDevilLee/codex-threadbeacon-windows)
