# Subagent 数量标记设计

## 状态

- 日期：2026-07-17
- 状态：已确认
- 对应 Roadmap：Feature 5，Subagent 数量标记
- 前置调研：[`../../subagent-count-feasibility.md`](../../subagent-count-feasibility.md)

## 目标

在不破坏 ThreadBeacon 紧凑状态视图的前提下，让用户一眼知道某个主任务是否创建过
Subagent，以及直接 Subagent 的数量。

本功能还要补强主任务过滤：对历史数据中缺少 `thread_source = 'subagent'` 标记、但
已经出现在父子关系表中的子任务，也不能显示为主任务。

## 非目标

第一版不实现：

- 判断或显示正在运行的 Subagent 数量。
- 使用 `thread_spawn_edges.status` 的 `open` / `closed` 推导实时状态。
- 点击数量标记后展开 Subagent 详情。
- 将 Subagent 状态提升为主任务状态灯。
- 汇总主任务与 Subagent 的 Token。
- 统计多层任务树的全部后代。

## 已确认交互

数量标记位于任务标题右侧、Token 概览左侧。它由 SF Symbol
`arrow.triangle.branch` 和十进制数字组成，使用中性色和紧凑字号，不使用胶囊背景，
避免与状态灯或错误提示竞争注意力。

显示规则：

- `subagentCount > 0` 时显示图标和数量。
- `subagentCount == 0` 时不渲染标记，也不保留空白占位。
- 悬浮提示和辅助功能标签使用“`N` 个 Subagent”。
- 标记不可点击，不提供上下文菜单。
- 标题仍优先占用剩余空间并保持单行截断，Token 概览和 info 按钮保持现有行为。

## 数据口径

第一版采用以下唯一定义：

```text
直接 Subagent 总数 = thread_spawn_edges 中 parent_thread_id 等于主任务 ID 的关系数量
```

所有直接关系均计入总数，不区分：

- `open` 或 `closed`。
- 子任务是否归档。
- 子任务 rollout 是否已有 final。

这是“该主任务记录了多少个直接 Subagent”的历史总数，不是实时活动数量。

## 数据访问设计

### 推荐方案

`SQLiteThreadRepository` 继续通过一次只读查询加载任务。查询使用聚合子查询按
`parent_thread_id` 统计直接 Subagent 数量，再通过 `LEFT JOIN` 合并到主任务记录。

主任务过滤同时满足：

1. `archived = 0`。
2. `thread_source` 不是 `subagent`。
3. 任务 ID 不出现在 `thread_spawn_edges.child_thread_id` 中。

第 3 条负责排除历史格式中 `thread_source` 为空的已知子任务。

### Schema 兼容回退

Codex SQLite 不是公开稳定 API。Repository 打开数据库后，先通过 `sqlite_master`
确认 `thread_spawn_edges` 是否存在：

- 表存在：执行关系感知查询，返回真实直接 Subagent 总数并补强子任务过滤。
- 表不存在：执行当前兼容查询，所有记录的 `subagentCount` 为 0。

关系表缺失不能导致整个任务列表加载失败。其他 SQLite 错误继续沿用当前错误处理，
显示在 App footer 中，不静默伪装成空列表。

## 模型与数据流

### `ThreadRecord`

增加：

```swift
public let subagentCount: Int
```

初始化默认值为 0，并拒绝将数据库负数传播到 UI；SQL 聚合结果按非负整数读取。

### `ThreadSnapshot`

增加相同的 `subagentCount` 字段，初始化默认值为 0。`ThreadStatusLoader` 只负责把
Repository 结果传递到 Snapshot，不参与关系状态推导。

### 数据流

```text
state_5.sqlite
  -> SQLiteThreadRepository 聚合直接子任务数量并过滤子任务
  -> ThreadRecord.subagentCount
  -> ThreadStatusLoader 原样传递
  -> ThreadSnapshot.subagentCount
  -> ThreadRowView 按数量条件渲染标记
```

这个边界让 SQLite 结构适配留在 Repository，UI 不需要知道关系表或关系状态。

## 错误与边界处理

- 关系表不存在：回退旧查询，数量为 0。
- 父任务没有关系：数量为 0，不显示标记。
- 关系表包含归档子任务：仍计入历史总数。
- `thread_source` 为空但任务是已知子任务：从主列表排除。
- 子任务记录缺失：关系仍可用于总数；主列表查询不读取其正文或标题。
- 数量较大：数字保持完整显示，不缩写成 `99+`；当前样本最大值为 23，MVP 不增加
  人为上限。
- 多层关系：只统计直接子任务，不递归。

## 隐私与安全

功能只读取关系表中的任务 ID，并在 SQL 中输出聚合数字。UI 不显示或记录子任务 ID、
名称、角色、路径和会话内容，也不修改 Codex 数据库。

## 测试设计

### Repository

- 主任务有 3 条直接关系时返回 `subagentCount == 3`。
- `open` 和 `closed` 关系都计入总数。
- 归档子任务仍计入总数。
- `thread_source` 为空、但出现在 `child_thread_id` 的子任务不进入主列表。
- `thread_source = 'subagent'` 的子任务继续被排除。
- 关系表不存在时回退旧查询，数量为 0。
- 限制条数和 recency 排序保持现有行为。

### Loader 与模型

- `ThreadRecord.subagentCount` 原样传递到 `ThreadSnapshot`。
- 状态排序、Token、标题 override 和完成提示音行为不受影响。

### UI 与集成

- 数量为 0 时任务行不显示 Subagent 标记。
- 数量大于 0 时标题右侧显示图标和完整数字。
- Tooltip 和 Accessibility label 包含准确数量。
- 执行完整单元测试和构建验证。
- 启动 App，确认标题、Subagent 数量、Token 和 info 按钮无重叠或异常换行。

## 验收标准

1. 当前真实数据中，包含 3 个直接 Subagent 的主任务显示 `3`。
2. 不包含 Subagent 的任务行与当前版本视觉密度一致。
3. 历史格式的已知子任务不再有机会混入主任务列表。
4. 标记不表达运行、完成、错误或授权状态。
5. 缺少关系表时 App 仍能显示主任务列表。
6. 单元测试、构建、Markdown lint 和差异检查通过。
