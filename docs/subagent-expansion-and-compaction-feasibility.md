# Subagent 展开与压缩状态可行性调研

## 结论

Subagent 展开功能可以基于 ThreadBeacon 现有只读数据源实现 MVP。建议采用主任务行内展开，
每个直接 Subagent 只显示任务标题、推导状态、最近活动时间和累计 Token；昵称、角色、模型、
Reasoning 等字段放入按需详情，不恢复会话摘要，也不读取或展示子任务正文。

Codex 的压缩信息需要分成两类：

- rollout 可以可靠确认压缩已经完成，并提供完成时间、累计次数以及部分新格式中的窗口编号。
- 当前只读轮询无法可靠判断正在压缩，更无法获得百分比进度。
- app-server 协议存在 `contextCompaction` 的开始和完成事件，可准确表达“压缩中”和耗时，
  但没有进度值；当前独立 app-server 无法订阅 Codex Desktop 已加载任务，因此暂时不能直接使用。
- Codex 支持 `PreCompact` / `PostCompact` Hook，可作为以后可选的实时桥接 POC，但它需要修改
  用户配置并处理崩溃后的过期状态，不适合作为默认只读 MVP。

因此，不能仿造一个百分比进度条。若未来打通实时开始/完成信号，应使用不确定进度动画和
“压缩中 · 已用 12 秒”这类表达。

## 调研范围

本次在 2026-07-17 检查了以下数据源：

- 本机 `~/.codex/state_5.sqlite` 的 `threads` 与 `thread_spawn_edges`。
- 本机 Codex rollout 的结构化事件类型和字段形状。
- Codex Desktop 内置 `codex-cli 0.144.5` 生成的实验性 app-server TypeScript 协议。
- OpenAI 官方 `openai/codex` 仓库中的 app-server 与 compact Hook 实现。

本次只输出匿名数量和字段覆盖率，没有记录任务 ID、标题、工作目录、Git 信息、会话正文或
压缩摘要。SQLite、rollout 与实验性 app-server schema 都不是 ThreadBeacon 可依赖的稳定公开
兼容契约，Codex 升级后需要回归验证。

## Subagent 可获取信息

当前 121 条直接父子关系均能关联到独立子任务记录。字段覆盖情况如下：

| 信息 | 覆盖 | 可靠性与用途 |
| --- | ---: | --- |
| 子任务 ID 与父任务 ID | 121 / 121 | 可靠定位直接父子关系，不显示给用户 |
| rollout 路径 | 121 / 121 | 可复用现有状态、Token 和事件时间解析 |
| 累计 Token | 121 / 121 | 可显示子任务自身用量，不默认汇总到主任务 |
| Agent 昵称 | 121 / 121 | 标题缺失时可作为回退名称 |
| Agent 角色 | 106 / 121 | 可放入详情；当前包括 `explorer`、`worker`、`default` |
| 模型与 Reasoning effort | 121 / 121 | 适合 info 详情，不占默认展开行 |
| 工作目录与 Git 分支 | 121 / 121 | 适合诊断详情，默认隐藏以避免路径隐私和视觉噪声 |
| 子任务标题 | 118 / 121 | 首选显示名称；平均约 40 字，最长 468 字，必须截断 |
| 关系 `open` / `closed` | 121 / 121 | 不能解释为实时运行状态，不用于着色或排序 |

rollout 还能推导：

- 最近事件时间。
- 是否出现新的 turn。
- 是否已有 final / `task_complete`。
- 累计及当前 turn Token 明细。

这些状态沿用当前 ThreadBeacon 的启发式规则：事件超过新鲜度阈值后降级为“未知”，不能把
“没有 final”长期解释为“仍在运行”。当前解析器也尚不能从 rollout 稳定产生 Subagent 的
“需要操作”或具体错误状态。

## 展开后显示什么

### 推荐：行内紧凑展开

点击主任务的 Subagent 数量标记，在该主任务下展开直接子任务列表。每一行默认显示：

1. 小号状态灯与状态文字。
2. 子任务标题，单行截断；标题缺失时回退到 Agent 昵称。
3. 最近活动时间，例如“2 分钟前”。
4. 子任务累计 Token 的紧凑值。

按需详情显示：

- Agent 昵称与角色。
- 模型、Reasoning effort。
- Token 明细。
- 创建时间、最近事件时间。
- 工作目录与 Git 分支，但应避免默认暴露完整路径。

明确不显示：

- 子任务会话摘要、最后一条消息或 Reasoning 正文。
- `open` / `closed` 关系状态。
- 伪造的实时百分比。
- 默认的父子 Token 聚合总数。
- 第二层及更深任务树；当前样本也尚未出现这种关系。

### 备选方案

| 方案 | 优点 | 缺点 | 判断 |
| --- | --- | --- | --- |
| 主任务行内展开 | 上下文明确，可同时比较多个 Subagent | 会增加列表高度 | 推荐作为 MVP |
| 点击后 Popover | 保持主窗口高度稳定 | 容易遮挡，不能长时间对比 | 可作为 info 详情，不作为主展开 |
| 独立 Inspector | 可容纳任务树、日志和完整诊断 | 把状态灯 App 推向第二个 Codex 客户端 | 暂不采用 |

排序建议为：有新鲜运行迹象的子任务优先，其次刚完成、空闲、未知；同状态按最近事件倒序。
展开状态只保存在本次 App 生命周期即可，第一版不需要持久化。

## 压缩状态能获取到什么

### rollout：只能可靠看到完成

本机样本包含 478 个顶层 `compacted` 事件，以及 478 个紧随其后的
`event_msg.context_compacted`。两者通常只相差几毫秒：

```text
compacted -> context_compacted
```

`context_compacted` 只有事件类型，没有进度字段。`compacted` 可能包含压缩后的摘要、替代
历史和窗口标识；ThreadBeacon 不需要读取或展示摘要正文，只需记录时间和窗口编号。旧格式
还可能缺少窗口字段。

rollout 中没有可配对的通用“压缩开始”事件。手动独立压缩可能伴随 turn 开始，但自动压缩
也可发生在普通 turn 中途，因此不能把 `task_started` 当作压缩开始时间。

基于 rollout 现在可以展示：

- 历史压缩次数。
- 最近一次压缩完成时间。
- 存在时的最新窗口编号。

不能展示：

- 当前是否正在压缩。
- 压缩已经完成多少百分比。
- 可靠的压缩持续时间。

### app-server：有生命周期，没有进度

当前 app-server 协议把压缩暴露为 `contextCompaction` item，并提供通用的
`item/started` 与 `item/completed` 通知，通知中包含任务 ID、turn ID 和开始或完成时间。
旧的 `thread/compacted` 通知已标记为 deprecated。

这足以显示：

- “压缩中”的实时状态。
- 已持续时间。
- 完成后的真实耗时。

但 `contextCompaction` item 只有 ID，没有 `current`、`total`、百分比、阶段或增量事件，
因此依然无法绘制真实进度条。

现有 [app-server POC](app-server-integration-poc.md) 已验证：独立启动的 app-server 看不到
Codex Desktop 进程中已经加载的任务和实时状态。除非 Codex 提供共享 daemon、控制 socket
或正式只读订阅接口，否则不能把这个协议能力直接用于当前 ThreadBeacon。

### Hook：可选实时桥接

官方实现支持 `PreCompact` 与 `PostCompact` Hook，并向 Hook 提供 session ID、turn ID、模型、
触发方式、工作目录和 transcript 路径。理论上可以让两个 Hook 写入和清除一个本机状态标记，
ThreadBeacon 只读取该标记：

```text
PreCompact -> 写入“压缩中”标记 -> PostCompact -> 写入完成并清除活动标记
```

这个方案能提供开始、结束和耗时，但仍没有百分比。它还需要解决：

- 用户主动安装与配置 Hook。
- Codex 或 Hook 异常退出后的过期标记与 TTL。
- 多任务并发压缩时的任务隔离。
- 配置兼容、卸载和隐私说明。

因此只建议作为后续 opt-in POC，不应成为默认依赖。

## 产品建议

建议拆成两个独立迭代：

### Feature 6A：Subagent 行内展开

- 只展示直接 Subagent。
- 默认字段为状态、标题、最近活动和累计 Token。
- info 详情展示昵称、角色、模型、Reasoning 与 Token 明细。
- 不显示正文，不使用 `open` / `closed`，不做任务树 Token 汇总。

### Feature 6B：压缩可观测性

第一阶段先在详情中显示“压缩 N 次 · 最近于某时完成”，继续保持纯只读。

第二阶段单独验证 Hook 桥接或共享 app-server。只有拿到明确开始与完成事件后，才在主任务行
显示不确定进度动画：

```text
压缩中 · 12 秒
```

不要根据历史平均耗时估算百分比，也不要把 Token 接近自动压缩阈值解释成已经开始压缩。

## 官方依据

- [ContextCompactedNotification](https://github.com/openai/codex/blob/315195492c80fdade38e917c18f9584efd599304/codex-rs/app-server-protocol/schema/typescript/v2/ContextCompactedNotification.ts)
- [ThreadItem](https://github.com/openai/codex/blob/315195492c80fdade38e917c18f9584efd599304/codex-rs/app-server-protocol/schema/typescript/v2/ThreadItem.ts)
- [ItemStartedNotification](https://github.com/openai/codex/blob/315195492c80fdade38e917c18f9584efd599304/codex-rs/app-server-protocol/schema/typescript/v2/ItemStartedNotification.ts)
- [ItemCompletedNotification](https://github.com/openai/codex/blob/315195492c80fdade38e917c18f9584efd599304/codex-rs/app-server-protocol/schema/typescript/v2/ItemCompletedNotification.ts)
- [Compact Hook 实现](https://github.com/openai/codex/blob/315195492c80fdade38e917c18f9584efd599304/codex-rs/hooks/src/events/compact.rs)

## 推荐决策

建议先进入 Feature 6A 的交互设计，采用“主任务行内展开”方案。压缩历史信息可以与 6A 共用
详情数据模型，但不要把 Hook 或 app-server 实时接入塞进同一次开发；Feature 6B 先保留为
独立 POC，避免放大当前 MVP 的数据兼容风险。
