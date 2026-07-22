# Attention State 只读探针

该探针用于验证 Codex rollout 是否存在可供 ThreadBeacon 使用的“等待输入”和“已中断”证据，
不属于正式 App 运行时。

探针只读取指定 rollout 尾部，输出三个稳定字段：

- `lifecycle`：`unknown`、`running`、`completed` 或 `interrupted`；
- `pendingUserInputCandidate`：当前 turn 是否存在尚未配对 output 的 `request_user_input` 调用；
- `explicitApprovalEvidenceAvailable`：rollout 是否存在明确授权等待证据；当前固定为 `false`。

输出不包含任务 ID、标题、路径、提示问题、工具参数、消息正文或 call ID。

## 自测

```bash
swift Tools/AttentionStateProbe/main.swift --self-test
```

## 检查单个 Rollout

```bash
swift Tools/AttentionStateProbe/main.swift --rollout <rollout-path>
```

`pendingUserInputCandidate` 仍属于待真实样本验证的候选信号，不能直接接入正式状态灯。未配对调用
还必须结合当前 turn 未结束、后续 `task_complete` / `turn_aborted` 清理和尾部截断边界判断。

`turn_aborted` 可以明确表示 turn 已中断，但现有 payload 不记录发起方。因此正式产品只能显示
“已中断”，不能声称用户一定点击了 STOP。
