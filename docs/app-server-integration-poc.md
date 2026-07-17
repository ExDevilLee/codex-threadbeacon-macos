# Codex app-server 集成 POC

## 结论

验证日期：2026-07-17

结论为：**部分可用，但当前不适合作为 ThreadBeacon 的 Desktop 实时状态事件源**。

独立启动的 `codex app-server` 可以从共享状态数据库列出 Codex Desktop 已有任务，
但不能访问 Desktop app-server 实例中已经加载的线程，也没有收到 Desktop 任务的实时
状态、完成、错误或审批事件。因此，现阶段不能据此实现可靠的 `attention`、`warning`
和 `failure` 提示音。

这项结论只否定“独立 app-server 跨实例订阅”路线。后续验证发现，本机
`~/.codex/logs_2.sqlite` 的白名单结构化日志可只读识别 HTTP 429/503 的自动重试和最终
失败，现已作为独立数据源实现；它仍不能识别授权等待。详见
[`service-incident-monitoring.md`](service-incident-monitoring.md)。

本次验证达到预先设定的停止条件后，没有调用 `thread/resume`、`turn/start`、审批响应
或其他可能改变任务运行时的接口，也没有将错误文本扫描作为替代方案。

## 验证问题与结果

| 验证问题 | 结果 | 判定 |
| --- | --- | --- |
| 独立进程能否获得 Desktop 主任务 ID | 能；`thread/list` 返回的近期 ID 与 SQLite 和当前 Desktop 任务一致 | 可用 |
| 能否获得 Desktop 当前运行状态 | 不能；全部返回 `notLoaded` | 不可用 |
| 能否看到 Desktop 已加载线程 | 不能；`thread/loaded/list` 返回空数组 | 不可用 |
| `thread/read` 能否补足运行状态 | 不能；当前任务仍为 `notLoaded`，且不读取 turns 时 turn 数为 0 | 不可用 |
| 能否收到 Desktop 实时事件 | 不能；30 秒活动窗口内没有线程、turn、错误或审批事件 | 不可用 |
| 是否存在可连接的共享 daemon socket | 不存在；默认 control socket 路径没有文件 | 不可用 |
| 协议是否定义目标事件 | 是；本机生成的 schema 包含完成、错误和多类审批事件 | 协议具备，实例不共享 |

## 环境

- macOS。
- `codex-cli 0.144.1`。
- Codex Desktop 使用其 App bundle 内置的 `codex` 启动 app-server。
- Desktop 启动参数为 app-server 默认 stdio 传输，没有公开 Unix socket 或 WebSocket。
- 本机没有运行受管 app-server daemon，`daemon version` 无法连接默认 control socket。

版本和协议均属于当前机器快照，未来 Codex 版本可能改变结论。

## 证据链

### 1. Desktop app-server 是私有 stdio 子进程

进程检查显示 Codex Desktop 的主进程启动了自己的 app-server 子进程。该进程的
stdin、stdout 和 stderr 是与父进程相连的匿名 Unix FD，没有文件系统 socket 路径可供
ThreadBeacon 连接。

这排除了“ThreadBeacon 直接附加到 Desktop 当前 app-server socket”的路径。

### 2. 协议具备结构化事件

使用当前 CLI 生成 JSON Schema 和 TypeScript bindings 后，确认协议包含：

- `thread/status/changed`
- `turn/completed`
- 带 `threadId`、`turnId`、`willRetry` 和结构化错误信息的 error notification
- 命令执行、文件修改和额外权限 approval request
- 实验性的用户输入 request

协议能力本身成立，但 schema 不代表多个 app-server 进程共享运行时订阅。

### 3. 持久化任务可共享，运行时不可共享

只读探针完成初始化后调用：

```text
thread/list
thread/loaded/list
thread/read(includeTurns=false)
```

结果显示：

- `thread/list` 能列出近期 Desktop 和 CLI 任务，当前 Desktop 主任务位于结果首位。
- 返回任务均为 `notLoaded`。
- `thread/loaded/list` 为空。
- 对当前任务执行 `thread/read` 后，状态仍为 `notLoaded`。

这说明独立进程能够读取共享磁盘数据，但没有加入 Desktop app-server 的内存运行时。

### 4. 真实活动窗口没有跨实例通知

探针持续监听 30 秒。在同一时间窗口内：

- 当前 Desktop 线程的 SQLite `updated_at` 前进，证明任务仍有活动。
- 独立 app-server 只产生自身的配置警告和 remote-control 状态通知。
- 没有收到 `thread/status/changed`、`turn/completed`、error notification、approval
  request 或其他当前 Desktop 线程事件。

这个对照排除了“只要保持独立 app-server 连接，就会自动广播所有 Desktop 事件”的
假设。

## 未执行的高风险实验

没有对当前 Desktop 任务调用 `thread/resume`。协议说明该操作会把线程加载或重新加入
调用方 app-server 的运行时，还可以改变审批路由、Sandbox 和模型配置。它不属于只读
观察，可能造成双实例竞争或改变任务行为。

也没有启动或 bootstrap 受管 daemon。即使创建新的 daemon socket，当前 Desktop 仍在
使用自己的 stdio app-server；除非 Codex Desktop 官方支持切换到同一受管实例，否则它
不能证明现有任务事件会共享。

## 对产品设计的影响

### 可以保留

- 当前 rollout + SQLite 的只读主任务列表。
- 基于 `task_complete` 的可靠 `done` 提示音。
- app-server schema 中的事件分类可继续作为未来数据契约参考。

### 当前不能实现

- 通过独立 app-server 实时识别 Codex Desktop 的授权等待。
- 根据 `willRetry` 区分自动重试和重试耗尽。
- 通过 `turn/completed.failed` 或结构化错误生成可靠失败音。

以上限制针对独立 app-server。ThreadBeacon 当前改由白名单日志证据识别 429/503，不把
该实现描述成 app-server 能力，也不据此扩展到授权或其他错误。

### 不采用的回退

- 不扫描会话正文猜测 `429`、`503` 或授权状态；429/503 只接受白名单 target 中已经验证
  的结构化日志形状。
- 不让 ThreadBeacon `resume` Desktop 任务来换取订阅。
- 不要求用户把全部 Codex 任务迁移到 ThreadBeacon 自己启动的 app-server。

## 后续选择

推荐暂时关闭 app-server 正式集成路线，等待以下任一条件出现后重新验证：

1. Codex Desktop 提供受支持的共享 daemon、control socket 或只读订阅接口。
2. app-server 增加跨实例只读 runtime status/event API。
3. Codex 提供稳定 hook，能在不读取正文、不接管任务的情况下输出完成、授权和错误事件。

近期产品开发回到低风险的日常使用闭环：任务级置顶、忽略与恢复，以及状态数据源健康
诊断。它们不依赖未公开的跨实例运行时。

## 复现

探针位于 `Tools/AppServerProbe/`，仅输出必要元数据：

```bash
node Tools/AppServerProbe/probe.mjs
node Tools/AppServerProbe/probe.mjs --watch-seconds 30
```

探针不输出任务标题、cwd、消息正文、turn items 或工具参数。

## 来源边界

本次证据来自当前 CLI 自生成 schema、当前机器进程与 FD、SQLite 更新时间和探针输出。
官方 Codex 手册与页面在验证时返回 HTTP 403；官方 Developer Docs MCP 已加入本机配置，
但需要新线程或重启后才能在 Codex App 中暴露，因此本报告没有把未读取的官方网页当作
证据。GitHub raw 同期也不可达，未完成 prior-art 源码交叉检查。
