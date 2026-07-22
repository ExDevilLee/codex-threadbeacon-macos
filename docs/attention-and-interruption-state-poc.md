# 等待输入、等待授权与任务中断状态 POC

## 结论

验证日期：2026-07-22。当前环境为 macOS、Codex CLI `0.144.1` 和 Codex Desktop 私有
`app-server --listen stdio://` 进程。

阶段结论分为三类：

| 目标状态 | 当前结论 | 正式接入建议 |
| --- | --- | --- |
| 等待用户输入 | rollout 存在 `request_user_input` 调用与 output 配对，但缺少真实 pending 样本 | 保留只读探针，取得真实样本后再决定 |
| 等待授权 | 协议有精确 active flag 和 request，但独立进程无法订阅 Desktop 运行时 | 暂不接入，不用超时或工具执行状态猜测 |
| Turn 已中断 | rollout 明确写入 `turn_aborted`，reason 为 `interrupted` | MVP 已实现，只显示“已中断”，等待真实 UI 复验 |

因此，`needsAction` 仍不能作为完整的正式状态上线；“已中断”已作为独立状态落地，不改变等待输入
与等待授权继续失败关闭的结论。

## 验证范围与隐私边界

本轮只做以下只读检查：

- 重新生成当前 CLI app-server JSON Schema；
- 运行现有独立 app-server 只读探针；
- 聚合最近 45 天 rollout 的事件类型、结构键和配对数量；
- 聚合 SQLite schema、日志 target、已知方法名称和记录数量；
- 不输出任务标题、任务 ID、cwd、问题内容、工具参数、消息正文或日志正文。

没有调用 `thread/resume`、`turn/start`、`turn/interrupt`、审批响应或任何 Codex 写接口。

## app-server 协议证据

当前 schema 提供理想的精确语义：

- `ThreadActiveFlag` 只有 `waitingOnApproval` 和 `waitingOnUserInput`；
- `thread/status/changed` 携带 `threadId` 和完整 `ThreadStatus`；
- command、file change、permissions approval request 均携带 `threadId`、`turnId`、`itemId`
  和开始时间；
- `item/tool/requestUserInput` 携带 `threadId`、`turnId`、`itemId`；
- `turn/interrupt` 需要 `threadId` 和 `turnId`；
- `turn/completed` 的 `TurnStatus` 支持 `completed`、`interrupted`、`failed` 和 `inProgress`。

如果 ThreadBeacon 能订阅 Codex Desktop 所属 app-server，这些字段足以精确实现等待输入、等待
授权和中断状态，并能可靠清除陈旧状态。

## 跨实例阻塞仍然存在

重新运行 [`AppServerProbe`](../Tools/AppServerProbe/README.md) 后，独立 app-server 仍然只能从
共享数据库列出 Desktop 任务，但：

- 所有任务状态仍为 `notLoaded`；
- `thread/loaded/list` 仍为空；
- `thread/read(includeTurns=false)` 仍无运行时 turn；
- 没有获得 Desktop app-server 的 approval、user input 或 turn 状态事件。

进程检查再次确认 Desktop 启动自己的 `app-server --listen stdio://`，没有公开共享 socket。
因此，schema 证明“协议具备能力”，不能证明“独立 ThreadBeacon 可以订阅”。

## SQLite 与日志证据

### `state_5.sqlite`

`threads.approval_mode` 只描述会话审批配置，例如 `never`、`on-request` 或 `untrusted`，不表示
某个 turn 当前正在等待授权。threads 表也没有当前 active flag 或 turn status 字段。

### `logs_2.sqlite`

`codex_app_server::outgoing_message` 能看到少量 `thread/status/changed` 和 `turn/completed` 方法级
记录，但当前形状主要记录方法名称与连接数量：

- `thread_id` 列为空；
- `turn/completed` 的现有记录不包含可关联 UUID；
- 没有观察到 approval request、user input request 或 `interrupted` status 的方法级记录；
- 没有持久化 `waitingOnApproval` / `waitingOnUserInput` active flag。

其他 target 对上述关键词的命中会混入模型请求内容和传输调试信息，不能作为结构化状态源。正式
实现不应扩大日志白名单或扫描正文猜测等待状态。

## 等待用户输入候选

最近 45 天 rollout 中观察到 8 次 `request_user_input` function call，全部存在相同 call ID 的
`function_call_output`，没有未配对历史样本。

候选状态规则是：

1. 当前 turn 已出现 `task_started`；
2. 出现 `request_user_input` function call；
3. 尚未出现同 call ID 的 output；
4. 尚未出现 `task_complete`、`turn_aborted` 或新的 `task_started`。

该规则语义比“长时间无输出”可靠，也不需要读取问题正文。但目前没有捕获到用户仍停留在提问框
时的真实 rollout，不能确认 function call 是否在等待期间立即落盘，以及 Codex App 回答或自动
超时后的精确顺序。

仓库新增 [`AttentionStateProbe`](../Tools/AttentionStateProbe/README.md) 观察该候选信号。正式接入
前必须用真实 pending 样本验证开始、保持、回答后清除、STOP 后清除和 App 重启五个场景。

## 等待授权不可从 Rollout 推导

rollout 没有独立 approval request 事件。把“exec / file change 调用已经出现但 output 尚未出现”
解释为等待授权会产生严重误报，因为同一结构也可能表示：

- 命令仍在正常执行；
- MCP 或其他工具仍在等待外部响应；
- App 刚写入调用，output 尚未来得及落盘；
- turn 已异常停止但尾部事件尚不完整。

因此等待授权继续失败关闭。除非获得 Desktop 共享只读订阅、稳定 hook，或另一个同时提供任务 ID、
请求开始与请求结束的明确数据源，否则不把它显示成 `needsAction`。

## 用户 STOP 与 `turn_aborted`

最近 45 天 rollout 聚合观察到 57 个 `turn_aborted`：

- reason 统一为 `interrupted`；
- 全部携带 turn ID、完成时间和耗时；
- 部分记录还携带开始时间；
- 在下一次 `task_started` 前均没有 `task_complete`；
- 部分中断随后出现 `thread_rolled_back`，不影响 turn 已中断这一事实。

这足以把 turn 生命周期从 `running` 结束为 `interrupted`，避免当前解析器在没有 final answer 时把
它长期显示为运行中。

但 payload 没有 initiator 或 source 字段。`turn_aborted(reason=interrupted)` 可能来自用户点击 STOP、
客户端调用 `turn/interrupt`、审批取消或其他中断路径。因此产品文案必须是“已中断”，不能写成
“用户已停止”。

2026-07-22 的真实 UI 复验首次暴露出字段兼容问题：用户 STOP 后，rollout 已写入
`turn_aborted(reason=interrupted)`，但 `completed_at` 与 `started_at` 是数值型 Unix 秒数；早期解析器
只接受 ISO8601 字符串，并因此跳过整条中断事件，界面继续误显示“运行中”。修复后以顶层
`timestamp` 作为可靠边界，可解析的字符串 `completed_at` 只用于补充较晚时间；数值型或 malformed
可选字段不再否定中断事实。自动化回归测试已覆盖该真实数据形状；新版 App 随后完成真实 STOP
复验，任务在刷新后正确显示为灰色`已中断`。

建议清理规则：

- `turn_aborted` 比同一 turn 更早的 `task_started` 优先，状态转为 `interrupted`；
- 更新状态时间使用事件 timestamp 或 `completed_at`；
- 新的 `task_started` 清除旧中断状态并恢复 `running`；
- 后续 `task_complete` 或 final answer 按真实时序覆盖；
- 不触发错误提示音和自动恢复，因为中断不等同于服务失败。

## POC 停止条件与落地状态

本轮已达到停止条件：没有可跨实例读取的授权等待证据，不继续尝试附加 Desktop 私有 stdio、接管
线程或扫描正文。

后续按三条独立路径推进：

1. **已完成并通过真实 UI 复验**：`turn_aborted(reason=interrupted)` 已接入 Core；
   数值型 `completed_at` 不再导致事件被丢弃。任务显示`已中断 / Interrupted`，新的任务开始和完成
   事件按时间覆盖旧中断。实现不保存 turn ID、reason 或消息内容，不播放提示音、不自动恢复。设计见
   [`interrupted-task-status-design.md`](interrupted-task-status-design.md)。
2. **继续观察**：使用只读探针捕获一个真实 `request_user_input` pending 样本，验证回答、STOP 和
   重启后的清除行为，再决定是否接入 `needsAction`。
3. **保持阻塞**：等待授权继续等待 Codex 提供共享只读 runtime 事件、稳定 hook 或等价公开接口。
