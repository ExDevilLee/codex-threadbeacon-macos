# Subagent 活跃数量设计

## 状态

- 日期：2026-07-22
- 状态：已实现并完成真实 UI 复验
- 目标界面：主任务标题右侧的 Subagent 数量徽标
- 真实样本：已使用脱敏的多 Subagent 主任务完成`2/27`、刷新和展开一致性复验
- 实现提交：`d3b8c84`、`6687f53`、`a8d76bc`，后续归档边界修复为`7865e54`

## 背景与目标

现有徽标只显示某个主任务创建过的直接 Subagent 总数，例如 `27`。当用户同时运行多个
任务时，总数不能说明当前还有多少 Subagent 正在执行。

本功能将徽标改为 `活跃数/总数`，例如 `2/27`。分子帮助用户判断当前并行执行规模，
分母继续保留该主任务的直接 Subagent 历史总量。

## 已确认口径

```text
活跃数 = 当前显示状态为 .running 的直接 Subagent 数量
总数   = thread_spawn_edges 中属于该主任务的直接 Subagent 数量
```

- 只统计直接 Subagent，不递归统计更深层后代。
- `.warning`、`.error`、`.needsAction`、`.justCompleted`、`.idle` 和 `.unknown` 均不计入
  活跃数。
- `thread_spawn_edges.status` 不参与活跃状态判断。真实样本中的 27 条关系均为 `open`，
  该字段不能表达实时运行状态。
- `.running` 继续遵循现有 120 秒新鲜度规则：超过 120 秒没有新事件时降级为
  `.unknown`，不再计入活跃数。
- rollout 无法读取或无法确认状态时，不推测为运行中，只统计已确认的 `.running`。

## 交互设计

### 徽标

- 有直接 Subagent 时始终显示 `活跃数/总数`，例如 `2/27`、`0/27`。
- 没有直接 Subagent 时隐藏徽标，不保留空白占位。
- 保留现有 chevron、Agent 图标、展开旋转行为、`.secondary` 颜色和紧凑布局。
- 数字使用等宽数字，刷新时宽度变化不影响标题、Token、持续时间等既有列宽。
- 展开状态继续由现有父任务 ID 集合维护，刷新后不自动收起。

### Tooltip 与无障碍

折叠时显示：

```text
运行中 2 个，共 27 个 Subagent；点击展开
```

展开时将末尾动作改为“点击收起”。中文与英文均通过现有本地化设施输出，不在 View 中
拼接固定中文句子。

## 数据访问设计

### 为什么不能每两秒解析全部 Subagent

`RolloutTailParser` 单次最多读取一个 rollout 尾部 2 MiB。若每两秒解析 27 个历史
Subagent，单个父任务一轮最坏读取约 54 MiB；多个父任务同时存在时成本会继续线性增长。
因此活跃数量不能简单复用“遍历全部 Subagent 并解析”的方案。

### 活跃候选查询

`SQLiteThreadRepository` 增加只读的活跃候选查询。输入为当前可见父任务 ID 集合和
新鲜度截止时间，输出每个父任务最近 120 秒内更新的直接 Subagent：

- 父任务 ID。
- 子任务 ID。
- rollout 路径。
- 更新时间。

查询通过 `thread_spawn_edges` 连接 `threads`，并使用
`COALESCE(updated_at_ms, updated_at * 1000)` 过滤候选。它不读取标题、Token、模型、
Reasoning 等活跃计数不需要的字段。

候选查询覆盖所有当前可见的父任务，与是否展开无关。这样折叠状态下徽标也能每两秒
更新，同时避免读取长期无活动的历史 rollout。

### 展开数据复用

展开父任务时，现有 `loadDirectSubagents` 仍负责加载完整详情。`ThreadStatusLoader` 在
单轮刷新中维护按子任务 ID 缓存的 `RolloutObservation`：

1. 解析活跃候选并缓存 observation。
2. 只把经过现有 `displayState` 判定为 `.running` 的候选计入分子。
3. 构建展开列表时优先复用缓存；只为尚未解析的历史子任务读取 rollout。

缓存只在本轮刷新内存在，不跨轮保存，避免展示陈旧状态。

## 模型与组件变更

### `ThreadSnapshot`

增加：

```swift
public let activeSubagentCount: Int
```

初始化时将负数归零，并保证 UI 使用时不超过 `subagentCount`。现有 `subagentCount`
继续表达直接 Subagent 总数。

### `SubagentCountFormatter`

格式化入口接收活跃数和总数，生成：

- 可见文本：`active/total`。
- 活跃数与总数的结构化值，供 Tooltip 和无障碍文案使用。

Formatter 对负数归零，并将活跃数限制在总数以内。总数为 0 时返回 `nil`。

### `SubagentCountBadge`

Badge 不再从显示文本反向解析整数，而是直接使用 Formatter 提供的结构化计数生成
本地化 Tooltip 和无障碍标签。其他视觉资源和交互不变。

### 数据流

```text
state_5.sqlite
  -> 查询直接 Subagent 总数
  -> 查询最近 120 秒内的活跃候选
  -> RolloutTailParser 解析候选
  -> 现有 displayState 应用运行新鲜度规则
  -> ThreadSnapshot(activeSubagentCount, subagentCount)
  -> SubagentCountBadge 显示 2/27
```

## 错误与边界处理

- 关系表不存在：沿用兼容回退，总数为 0，徽标隐藏。
- 候选查询失败：任务列表仍按现有任务数据库错误路径报告失败，不展示未经确认的活跃数。
- 单个候选 rollout 读取失败：记录到现有 rollout 健康统计，该候选不计入活跃数。
- 候选更新时间很新但 rollout 状态不是 `.running`：不计入活跃数。
- 活跃数大于总数：模型和 Formatter 均限制为总数，避免异常数据污染 UI。
- 父任务已展开：分子与展开列表使用相同 observation 和状态判定，结果保持一致。
- 计数从两位数变为一位数：徽标保持紧凑，不为最大位数预留固定宽度。

## 非目标

本次不实现：

- 按 Subagent 层级递归汇总。
- 将异常、等待授权或刚完成的 Subagent 计入分子。
- 单独显示异常 Subagent 数量。
- 修改主任务状态灯或排序规则。
- 调整 Subagent 展开列表内容、图标或交互。
- 使用 `thread_spawn_edges.status` 替代 rollout 状态。
- 引入跨刷新持久缓存或新的后台定时器。

## 测试设计

实现遵循测试先行，先增加失败测试，再修改生产代码。

### Repository

- 只返回指定父任务最近 120 秒内更新的直接 Subagent 候选。
- 排除截止时间之前更新的历史 Subagent。
- 多个父任务的候选按父任务正确分组。
- 关系表不存在时返回空结果。
- 空父任务集合不访问数据库并返回空结果。

### Loader 与模型

- 两个候选状态为 `.running`、总数为 27 时输出 `activeSubagentCount == 2`。
- `.running` 候选超过新鲜度后按 `.unknown` 处理，不计入分子。
- `.justCompleted`、`.idle`、`.unknown` 和解析失败的候选不计入分子。
- 父任务未展开时仍计算活跃数。
- 父任务展开时复用候选 observation，不重复调用 parser。
- 活跃数不会超过总数。
- 现有 Subagent 展开排序和详情内容不变。

### Formatter 与 UI

- `2, 27` 格式化为 `2/27`。
- `0, 27` 格式化为 `0/27`。
- 总数为 0 时不显示徽标。
- 非法负数和活跃数大于总数时输出安全值。
- Tooltip 和无障碍标签在中英文下包含活跃数、总数及展开或收起动作。
- 浅色、深色、最小窗口宽度和不同位数下不出现遮挡。

## 验收标准

1. 真实样本有 2 个正在运行的直接 Subagent 时，主任务徽标显示 `2/27`。
2. 活跃 Subagent 完成或超过 120 秒无新事件后，分子在下一次刷新时减少。
3. 父任务保持折叠时，活跃数量仍按当前两秒刷新机制更新。
4. 展开父任务后，分子等于展开列表中状态为“运行中”的直接 Subagent 数量。
5. 没有 Subagent 的任务行视觉与当前版本一致。
6. 不使用 `thread_spawn_edges.status` 推导实时状态。
7. 单元测试、完整构建、Markdown lint 和差异检查通过。
