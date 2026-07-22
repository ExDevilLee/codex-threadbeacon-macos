# 自动恢复后恢复原前台 App：设计

## 背景

ThreadBeacon 的无人值守自动恢复会通过 `codex://threads/<thread-id>` 激活 Codex App，定位目标
任务并提交恢复提示词。发送完成后，Codex 会继续留在前台，打断用户在其他 App 中的工作。

本功能只补齐自动恢复链路的焦点收尾：记录操作前的原前台 App，并在确认用户没有主动切换焦点
时恢复它。

## 目标

- 仅在 `.unattended` 自动恢复开始前记录原前台 App。
- 自动恢复结束后，如果当前前台仍是本次激活的 Codex 进程，则恢复原 App。
- 发送成功、发送未确认和发送失败都执行同一安全判断，避免失败后把用户留在 Codex。
- 用户在自动恢复期间主动切换到第三个 App 时，不抢回焦点。
- 原 App 已退出、无法识别或本来就是 Codex 时静默跳过。

## 非目标

- 不改变双击打开任务后的前台行为。
- 不改变 Debug 手工目标选择和测试发送行为。
- 不增加设置项、通知或用户可见日志字段。
- 不改变异常检测、恢复规则、提示词、发送确认和重试逻辑。
- 不尝试恢复 Codex 内部原任务，只恢复 macOS 前台应用。

## 方案

### Core 安全策略

`ThreadBeaconCore` 新增纯值策略，输入交互模式、原 App、当前前台 App、本次 Codex 进程和原 App
是否已退出，输出恢复或跳过原因。

进程身份同时保留 bundle ID 和 PID：

- 判断“原 App 是 Codex”使用 bundle ID，避免把另一个 Codex 实例当作可恢复目标。
- 判断“当前仍是本次 Codex”同时使用 bundle ID 和 PID，避免同 bundle 多进程或 PID 被复用时误判。
- 只有 `.unattended`、三个身份都有效、原 App 未退出且当前身份等于本次 Codex 身份时才允许恢复。

### AppKit 前台会话

App 层新增轻量 `SystemAccessibilityForegroundSession`：

1. 自动恢复调用发送器前，通过 `NSWorkspace.shared.frontmostApplication` 记录原 App 身份。
2. 同时记录当前运行的 Codex PID。
3. 发送器返回后重新查询当前前台 App。
4. 调用 Core 策略；仅 `.restore` 时按原 PID 重新取得 `NSRunningApplication`。
5. 再次确认进程未退出后调用 `activate(options:)`。

会话只保存值类型身份，不长期持有 `NSRunningApplication`，不持久化任何应用信息。

## 数据流

```text
自动恢复候选
  -> 捕获原前台 App + Codex PID
  -> 现有 Accessibility 选择与发送链路
  -> rollout 确认或发送失败
  -> 读取当前前台 App
  -> 当前仍是同一 Codex PID？
       -> 是：原 App 仍运行则恢复
       -> 否：视为用户主动切换，保持现状
```

## 失败与安全边界

- 捕获不到原 App 或 Codex：跳过恢复，不影响原发送结果。
- 原 App 是 Codex：跳过恢复。
- 原 App 已退出或按 PID 无法重新取得：跳过恢复。
- 当前前台为空、不是本次 Codex PID 或已切换到第三个 App：跳过恢复。
- 激活原 App 失败：静默保持现状，不把焦点恢复失败改写成消息发送失败。
- 发送链路抛出或提前返回时，调用方仍在拿到结果后执行安全恢复判断。

## 测试与验收

自动测试覆盖：

- 无人值守、原 App 有效且当前仍为同一 Codex PID时允许恢复。
- 当前前台是第三个 App 时跳过。
- 用户主动模式跳过。
- 原 App 是 Codex、已退出或缺失时跳过。
- 当前 Codex PID 不同，即使 bundle ID相同也跳过。

手工验收：

1. 在其他 App 前台等待一次真实异常自动恢复，确认消息发送后回到原 App。
2. 自动恢复切到 Codex 后手动切换到第三个 App，确认 ThreadBeacon 不再抢焦点。
3. 验证 Debug 测试发送仍停留在 Codex，双击任务仍打开并停留在 Codex。
4. 验证发送失败路径不会无条件激活已退出或非原始 App。
