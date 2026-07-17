# Codex CLI 兼容性 POC

## 结论

验证日期：2026-07-17

结论为：**Codex CLI 任务的基础跟踪链路已通过真实样本验证**。

在 macOS 本机使用 Codex CLI 创建任务并 rename 后，ThreadBeacon 可以在现有主列表中
显示该任务，无需增加 CLI 专用数据源或修改当前读取逻辑。只读检查进一步确认，CLI
任务具备 ThreadBeacon 当前依赖的 SQLite 元数据、rename 索引、rollout 状态事件和
Token 数据。

本次只验证一个真实 CLI 任务，不把结果扩大为“所有 CLI 版本和生命周期均已完整兼容”。

## 验证结果

| 验证项 | 结果 | 当前判定 |
| --- | --- | --- |
| UI 列表 | CLI 任务可在 ThreadBeacon 主列表显示 | 已验证 |
| 来源识别 | SQLite 将任务明确记录为 CLI 来源 | 已验证 |
| rename 后标题 | `session_index.jsonl` 保存 rename 后名称，UI 可复用现有优先级 | 已验证 |
| 状态数据 | rollout 包含 turn 开始、完成等现有状态推导所需事件 | 已验证 |
| Token 数据 | SQLite 有累计 Token，rollout 有 `token_count` 事件 | 已验证 |
| Subagent 过滤 | 当前样本没有覆盖 CLI 创建 Subagent 的情况 | 待验证 |
| 归档与 resume | 当前样本没有覆盖归档、恢复和重复 resume | 待验证 |
| 跨版本行为 | 只验证当前 CLI 版本 | 待验证 |

## 环境与证据边界

- macOS。
- `codex-cli 0.144.1`。
- 单个由 Codex CLI 创建并由用户 rename 的真实任务。
- UI 观察与本机只读数据检查相互印证。
- 检查过程不记录任务 ID、cwd、会话正文、Token 数值或其他本机隐私信息。

版本、SQLite schema、session index 和 rollout 格式均属于当前机器快照，Codex 后续
升级可能改变结论。

## 数据链路

### SQLite

CLI 任务写入 ThreadBeacon 当前使用的 `~/.codex/state_5.sqlite`。样本具备：

- 明确的 CLI 来源标记和 CLI 版本；
- 未归档状态；
- 有效的 rollout 路径；
- 累计 Token 数据；
- 最近更新时间。

这说明基础任务发现和列表排序不需要 CLI 专用查询入口。

### rename 索引

`~/.codex/session_index.jsonl` 中存在该任务的记录，`thread_name` 为用户 rename 后的
标题。ThreadBeacon 现有的“session index 优先、SQLite 标题回退”规则可直接用于 CLI
任务。

### rollout

样本 rollout 包含 ThreadBeacon 当前会读取的结构：

- `turn_context`；
- `task_started`；
- `token_count`；
- `task_complete`。

因此，现有状态推导、完成提示音和 Token 详情具备可复用的数据基础。本次验证只检查
事件类型和数字字段是否存在，没有读取或输出会话正文。

## 产品状态更新

Codex CLI 兼容性从“尚未确认数据源”更新为“基础 POC 已验证”。当前无需为 CLI 单独
设计任务快照层，也不需要在 UI 中区分 Desktop 和 CLI 才能完成基础状态查看。

后续工作聚焦于兼容性边界，而不是重复实现基础接入：

1. 验证 CLI 任务归档和 resume 后的身份、标题与状态变化。
2. 验证 CLI 创建 Subagent 时，父子关系和主任务过滤是否与 Desktop 一致。
3. 在 Codex CLI 升级后做小样本回归，确认 schema 与事件类型没有破坏性变化。
4. 只有真实差异出现时，再引入 CLI 专用适配或统一只读任务快照层。
