# 已中断任务状态设计

## 目标

当 Codex rollout 写入 `turn_aborted` 且 `reason=interrupted` 时，ThreadBeacon 将对应主任务或
Subagent 显示为`已中断`；英文界面显示 `Interrupted`。该状态只描述 turn 已结束，不推断是谁或
什么操作触发了中断。

## 证据边界

- 只读取 rollout 中结构化的 `event_msg`。
- 只接受 `payload.type=turn_aborted` 且 `payload.reason=interrupted`。
- 使用事件顶层 `timestamp`；当 payload 中存在可解析的 ISO8601 `completed_at` 时，使用两者中较晚的
  时间。真实 rollout 也可能写入数值型 Unix 秒数；无法解析的可选 `completed_at` 必须回退到顶层
  `timestamp`，不能丢弃整个中断事件。
- 不保存 turn ID、reason、消息正文或其他 payload 内容。
- 缺少 reason、reason 不匹配或顶层时间无效的事件不改变任务状态。

## 生命周期优先级

解析器分别记录最近一次运行、完成和中断边界，再按时间选择最新状态：

1. 最新边界是 `turn_aborted(reason=interrupted)`：`interrupted`。
2. 最新边界是 `task_started` 或 `turn_context`：`running`。
3. 最新边界是 `task_complete` 或 assistant final：`justCompleted`。
4. 没有上述证据：`unknown`。

相同时间戳采用保守优先级：完成覆盖中断，中断覆盖运行，避免把已经结束的 turn 继续显示为运行中。

## 展示与排序

- 中文文案：`已中断`
- 英文文案：`Interrupted`
- 常规状态灯：系统 `secondary` 颜色
- 色盲安全符号：`stop.circle.fill`
- 排序位置：`running` 之后、`justCompleted` 和 `idle` 之前
- 状态持续时间：沿用 `statusChangedAt`

灰色与停止符号共同表达“已停止但不是故障”。正在执行的任务更需要持续关注，因此运行中排在
已中断之前；已中断仍排在刚完成和空闲之前，但不抢占错误、需要操作和服务异常。

## 行为边界

- 不播放完成提示音或服务异常提示音。
- 不生成自动恢复候选。
- 不改变服务异常的覆盖规则；真实服务失败仍优先显示 `error` 或 `warning`。
- 不接入等待授权识别。
- 不接入尚未获得真实 pending 样本的等待输入候选。
- 不改变双击打开任务、Accessibility 自动恢复或 Codex App 操作链路。

## 验收场景

- `task_started -> turn_aborted` 显示`已中断`。
- `turn_aborted -> task_started` 恢复为`运行中`。
- `turn_aborted -> task_complete/final` 显示`刚完成`。
- 数值型或 malformed `completed_at` 回退顶层事件时间，仍显示`已中断`。
- 缺少 reason 或其他 reason 的 abort 不改变状态。
- 中断事件不会进入声音通知和自动恢复链路。
- 浅色、深色和色盲安全模式均使用系统自适应颜色与合法 SF Symbol。
