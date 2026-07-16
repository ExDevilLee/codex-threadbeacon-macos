# Token 消耗概览设计

## 目标

在不破坏 ThreadBeacon 小窗口扫视效率的前提下，为每个 Codex 主任务提供 Token
消耗概览。主列表只展示格式化后的会话累计总量；用户需要时，通过 info 图标查看
完整指标。

本阶段只统计 Codex 本地数据中已经明确提供的 Token 数字，不估算费用，也不把累计
Token 解释为当前上下文长度。

## 已确认的交互

- 每个有 Token 数据的任务行右侧显示紧凑总量，例如 `70.8M`。
- 总量旁显示 info 图标。
- 鼠标在 info 图标上停留约 300 毫秒后打开详情。
- 鼠标移开自动关闭详情。
- 点击 info 图标后，详情保持打开，直到用户点击外部区域关闭。
- 详情使用 macOS 原生 popover，不改变任务行高度，避免列表跳动。
- 没有 Token 数据时不显示总量和 info 图标，不占用额外空间。

## 展示指标

详情展示以下字段：

| 指标 | 定义 |
| --- | --- |
| 会话总量 | 最新 `total_token_usage.total_tokens`；SQLite 值作为总量回退 |
| 输入 | `total_token_usage.input_tokens` |
| 缓存输入 | `total_token_usage.cached_input_tokens`，是输入的子集 |
| 非缓存输入 | 输入减去缓存输入 |
| 输出 | `total_token_usage.output_tokens` |
| Reasoning | `total_token_usage.reasoning_output_tokens`，是输出的子集 |
| 当前 turn | 最新累计总量减去最近一次 `task_started` 前的累计总量 |
| 缓存率 | 缓存输入除以输入；输入为零时不显示 |
| 更新时间 | 产生当前 Token 快照的最新 `token_count` 事件时间 |

界面需要明确表达缓存输入已经包含在输入中，Reasoning 已经包含在输出中，避免用户
把这些数字重复相加。

## 数据来源与计算

### SQLite 总量

`threads.tokens_used` 与 rollout 最新累计 `total_tokens` 已在真实会话中验证一致。
`SQLiteThreadRepository` 将该字段随 `ThreadRecord` 一起读取，为主列表总量提供稳定
回退。

### Rollout 明细

`RolloutTailParser` 继续只读取 rollout 尾部，新增处理
`event_msg.payload.type == token_count`：

1. 保存最新的 `total_token_usage` 作为会话明细。
2. 找到最近一次 `task_started`。
3. 找到该事件之前最后一个完整累计快照作为当前 turn 基线。
4. 使用最新累计字段减去基线字段，得到当前 turn 消耗。

不得累加 `last_token_usage`。同一个累计值可能重复出现，context compaction 也可能
产生无法按字段直接相加的 `last_token_usage`。

如果 rollout 尾部不包含可靠基线，当前 turn 显示 `—`，不能把最新单次调用误当成
整个 turn。会话总量仍可回退到 SQLite。

## 模型边界

新增独立值类型承载 Token 数据，避免让状态推导和展示格式互相耦合：

- `TokenUsage`：累计输入、缓存输入、输出、Reasoning、总量。
- `TokenUsageSnapshot`：会话累计、可选当前 turn、更新时间。
- `RolloutObservation`：在现有状态字段之外携带可选 Token 快照。
- `ThreadSnapshot`：向视图提供最终 Token 快照；如果 rollout 明细不可用，只保留
  SQLite 总量回退。

所有 Token 计数使用 `Int64`，解析负数或累计倒退时放弃对应差分，避免输出错误值。

## 子代理边界

默认仍只显示主任务。子代理在 SQLite 和 rollout 中拥有独立任务记录，因此本阶段：

- 不把子代理 Token 合并到父任务。
- 不在详情中展示子代理数量或消耗。
- 不改变现有主任务过滤行为。

后续如要提供子代理汇总，必须明确区分“主任务自身消耗”和“任务树总消耗”。

## 错误与兼容策略

- SQLite 没有 Token 字段或查询失败：沿用现有加载错误处理，不崩溃。
- rollout 缺失或 JSON 格式变化：状态灯继续按现有规则工作，Token 详情缺失。
- 明细字段部分缺失：只展示可以证明正确的字段，其余显示 `—`。
- 最新 rollout 累计值与 SQLite 总量不一致：优先使用时间更新的 rollout 明细；
  SQLite 仅作为总量回退，不拼接两个时间点的数据。
- Token 事件尚未落盘：维持上一次刷新结果；ThreadBeacon 当前每两秒刷新一次。

## 测试与验收

按 TDD 顺序补充以下测试：

1. parser 能读取完整累计 Token 指标，且不保留消息正文或 reasoning summary。
2. parser 通过累计值差分得到当前 turn 指标。
3. 重复累计事件不会造成重复统计。
4. 缺少 turn 基线、字段缺失或累计倒退时不产生错误差分。
5. loader 能传递 rollout 明细，并在明细缺失时使用 SQLite 总量回退。
6. 数字格式化覆盖小于一千、`K`、`M` 和零值。
7. 全部 Swift 测试和 release 构建通过。
8. 使用真实只读 Codex 数据验证：主列表总量、popover 全部字段、悬浮延迟、点击
   保持和外部点击关闭均符合设计。

## 本阶段不做

- Token 费用估算或模型价格适配。
- 剩余上下文窗口计算。
- 子代理 Token 聚合。
- Token 历史趋势图或持久化采样。
- Settings 中的 Token 显示开关。
- Windows 或 Codex CLI 的额外适配。
