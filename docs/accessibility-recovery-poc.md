# Codex App 会话恢复：Accessibility 方案研究

## 结论

如果目标是让恢复消息出现在 Codex App 当前会话中，并由 Codex App 自己创建后续 turn，
恢复动作必须通过 Codex App 的输入框提交。当前没有可复用的 Desktop app-server attach 接口，
因此 macOS 上最现实的方案是 Accessibility 自动化。

这意味着用户必须在“系统设置 → 隐私与安全性 → 辅助功能”中，明确授权 ThreadBeacon
控制 Codex App。没有该授权时，ThreadBeacon 只提供只读监控并记录“未发送”，不会使用用户不可见的
`codex exec resume` 外部 CLI 恢复尝试。

## 本机只读可行性检查

2026-07-20 使用 `System Events` 检查当前 Codex App 窗口：

- 可以发现 ChatGPT/Codex App 进程和主窗口。
- 当前 Accessibility 树只暴露窗口组和关闭、最小化、全屏按钮。
- 没有稳定暴露会话列表、会话标题、输入框或发送按钮等内容控件。

2026-07-21 进一步改用原生 `AXUIElement` API 检查同一窗口，确认 `System Events` 的结果是
远程 Web 内容子树未展开造成的假阴性。原生 AX 树可以识别：

- 一个 `AXWebArea`；
- 当前界面唯一的 `AXTextArea`；
- rename 后任务标题对应的可执行 `AXPress` 任务按钮。

仓库新增
[`Tools/AccessibilityProbe/`](../Tools/AccessibilityProbe/README.md) 作为只读定位 POC。
它默认只检查标题匹配、可操作任务行和输入框数量；只有同时提供 `--select` 与
`--confirm-select` 才允许切换唯一匹配的任务，并且没有输入或发送消息的代码路径。

这证明方案 A 已具备无固定坐标定位任务行与输入框的技术基础，但当时尚未验证正式
ThreadBeacon 进程的独立授权、目标任务切换后二次身份确认、固定文本注入、发送动作和 rollout
回读。因此仍不能把自动点击或发送逻辑接入异常恢复主链路。

下一阶段 POC 增加独立的注入双确认：仅当目标任务按钮和输入框都唯一、输入框原本为空时，
写入固定提示词并立即回读，随后清空并再次确认。该阶段仍不查找发送按钮、不模拟回车，也不
产生新的 Codex turn。

验证中发现 Codex 当前中文界面的 ProseMirror 会把“随心输入”占位提示暴露为 `AXValue`，而
`AXPlaceholderValue` 仍为空。后续实机还复现了父输入框 `AXValue` 比可见占位文本多一个字符的
情况。POC 因此不再只做字符串精确匹配：只有输入框内部同时存在带 `placeholder` DOM class 的
子树和 `AXStaticText` 时，才把陈旧的非空值视为空输入；普通非空值和不可读值仍拒绝覆盖。任务
切换还增加两层身份校验：rename 标题必须在本地索引中唯一，并且切换后必须唯一出现
在带 `app-header-tint` 语义的 Codex 顶部标题栏中。该 class 属于当前 Codex 内部实现，后续版本
变化时必须失败关闭并重新验证。

2026-07-21 使用当前真实任务完成注入与清理验证：

- 本地 session index 中 rename 标题只对应一个任务 ID；
- AX 树中只有一个可操作任务行，切换后目标标题只在 Codex 顶部标题栏匹配一次；
- 当前界面只有一个 `AXTextArea`；
- 写入固定提示词后等待 200ms，`AXValue` 可以原样回读；
- 清空后等待 200ms，输入框恢复为“随心输入”占位状态；
- 验证前后 rollout 的 `user_message` 数量不变，确认没有发送消息或创建用户 turn。

这证明“任务定位 → 二次身份确认 → 固定文本注入 → 回读 → 清理”链路可行。尚未验证的是正式
ThreadBeacon App 自身的目标任务注入／清理、发送按钮或回车动作、发送后的新 `user_message` /
`task_started` 回读，以及失败时是否能稳定恢复输入框。因此自动恢复仍保持禁用。

正式 App 的下一层 POC 已增加到 Settings 的“自动恢复”页：页面只读取真实
`AXIsProcessTrusted()` 状态，并且仅在用户点击“请求授权”时调用带系统提示的
`AXIsProcessTrustedWithOptions`。未授权时可显式打开 macOS 辅助功能设置。该入口不会自动请求
权限，也不会启用恢复消息发送；授权后的当前用途仍只是继续验证 ThreadBeacon App 自身的 AX
访问能力。

2026-07-21 已完成正式 ThreadBeacon 进程的授权与只读访问验证：

- 开发版使用本机现有 Apple Development 身份签名；
- 用户明确授权后，Settings 正确显示“已授权”；
- 用户主动执行“验证 Codex 只读访问”后，正式 App 读取到 1 个 Codex 窗口、1 个输入框，
  共访问 1063 个 AX 节点；
- 诊断结果只保留上述结构计数，不读取、显示或持久化元素标题、值与会话内容；
- 该验证不切换任务、不写输入框、不发送消息。

验证过程中确认，同一台机器若同时存在 `/Applications`、Xcode Debug 和 `dist` 三个同 bundle ID
副本，ad-hoc 签名会让系统设置中的同名授权与当前运行副本错配。开发验证应对实际运行的
`dist/ThreadBeacon.app` 使用稳定的 Apple Development 身份签名，再由该进程主动请求授权。
公开分发仍需要 Developer ID Application 和公证；开发证书不能替代发布签名。

同日继续完成正式 ThreadBeacon 进程的当前输入框验证：

- 只读前置检查再次确认 1 个 Codex 窗口、1 个输入框和 1063 个 AX 节点；
- 只有只读检查通过后，Settings 才显示“验证当前 Codex 输入框（不发送）”；
- 输入框必须唯一，且当前值为空或存在已验证的 `placeholder + AXStaticText` 子树；检测到普通
  非空值或不可读值时拒绝覆盖；
- 正式 App 写入固定提示词，等待 200ms 后原样回读，再清空并等待 200ms 确认恢复为空输入；
- 验证前后 rollout 均为 `user_message=247`、`task_started=229`、`task_complete=215`，确认没有
  创建新用户消息或新 turn；
- 代码不查找发送按钮、不模拟回车，且该服务没有接入自动恢复主链路。

这证明正式 ThreadBeacon 进程具备“当前输入框写入 → 回读 → 清理”的受保护能力。该阶段完成时
仍待验证按异常任务 ID 切换和二次身份确认，以及在独立测试任务中执行真实发送和 rollout 回读。

同日继续完成正式 ThreadBeacon 进程的目标任务切换验证：

- Settings 增加仅用于 POC 的目标任务 ID 输入框和“不发送”验证按钮；
- 正式 App 从本地 session index 解析该 ID 的 rename 标题，并要求标题在所有任务中唯一；
- AX 树只允许一个匹配标题的可操作任务行，执行一次 `AXPress` 后等待 800ms；
- 切换后必须在带 `app-header-tint` 语义的顶部标题栏中唯一匹配目标标题，同时仍只有一个
  `AXTextArea`，否则失败关闭；
- 先对当前开发任务完成定位验证，再跨任务切换到另一个近期任务，最后成功切回当前开发任务；
  三次均返回“已切换并确认任务身份，未发送消息”；
- 当前开发任务 rollout 计数保持 `user_message=248`、`task_started=230`、`task_complete=216`，
  跨任务目标 rollout 计数保持 `242/238/228`，最近事件均早于切换操作，确认没有创建新 turn；
- 对另一个较旧任务的验证返回 0 个可操作任务行并安全停止，证明本地索引存在
  不代表任务行已在当前 Codex AX 树中渲染；侧边栏虚拟化或未加载任务仍是后续自动恢复的阻塞点；
- 本阶段没有读取会话正文、写入输入框、查找发送按钮或模拟回车，目标 ID 和标题也不写入日志。

因此正式 App 的“任务 ID → 唯一 rename 标题 → 唯一任务行 → AXPress → 顶部标题二次确认”链路
已通过实机验证。下一阶段只剩在独立测试任务中执行真实发送，并以新增 `user_message` 和
`task_started` 回读确认结果；在完成该独立验证前，自动发送继续保持关闭。

同日完成真实发送与同名任务验证，取代上述基于唯一标题任务行的目标选择路径：

- Codex 注册的 `codex://threads/<thread-id>` 可按 ID 打开活跃任务，随后以 session index 中该 ID
  对应的 rename 标题在顶部标题栏做二次确认；
- AX 树本身不暴露任务 ID、DOM id 或 URL，因此名称不能单独作为目标身份；
- 用户明确确认后，正式 App 写入固定提示词，只匹配唯一 enabled 发送按钮并执行一次 `AXPress`；
- rollout 回读会规范化 Codex 补充的尾部换行，并且只接受与固定提示词严格匹配的新
  `user_message` 和新的 `task_started`，其他并发用户消息不能产生成功结果；
- 两个同名活跃任务在交换列表位置前后各完成一次指定 ID 发送，只有指定 ID 的 rollout 新增
  固定提示词和完整 turn，另一个同名任务两次均保持不变；
- 发送后不会自动重试；10 秒内没有严格确认时返回“已触发但未确认”。

该结果证明同名和列表顺序不再决定目标，但还不能启用无人值守自动恢复。实测中，ThreadBeacon
切换 Codex 当前任务时，用户同时在另一个任务输入的内容可能落入被切换后的任务。

随后完成第一层输入冲突保护：

- 目标选择前读取当前 Codex 输入框数量和值；存在草稿、多个输入框或值不可读时，在 deep link 前失败关闭；
- 用户主动点击与无人值守模式分开建模。手动测试允许 Codex 浮动窗口仍保持 active，但继续执行草稿
  检查；无人值守模式在 Codex 保持前台时直接停止；
- 正式 App 实机验证中，在非目标同名任务保留草稿后请求切换指定 ID，UI 返回“当前 Codex 任务
  输入框已有草稿”，发送按钮保持禁用，选择流程未进入 deep link；
- 2026-07-21 复现视觉输入框为空但父 `AXValue` 非空的占位符误判；修复后同一目标 ID 的定位验证
  通过，发送按钮恢复启用，用户确认后的单次固定提示词发送由 rollout 新 `user_message`、
  `task_started` 和 `task_complete` 完整确认；
- 无人值守前台保护目前由纯策略单测覆盖，尚未接入自动异常恢复主链路。

该保护解决了已复现的草稿覆盖风险，但跳转期间用户重新输入的竞态、完成后是否恢复原任务、连续
失败熔断仍需单独验证，因此自动发送继续保持关闭。

## 目标流程

```text
检测到新的终止型异常
        ↓
确认 ThreadBeacon 已获得 Accessibility 授权
        ↓
定位 Codex App 窗口和目标会话
        ↓
标题 / 会话 ID 二次校验
        ↓
聚焦输入框并注入固定提示词
        ↓
模拟发送
        ↓
等待目标 ID 的 rollout 出现严格匹配的 user_message 和 task_started
        ↓
记录“已注入 Codex App”与后续执行结果
```

## 安全约束

- 默认关闭，不在用户未明确开启时申请或使用 Accessibility 权限。
- 发送前必须完成目标会话匹配；匹配失败时只记录失败，不发送。
- 不使用固定屏幕坐标作为唯一定位依据。
- 不读取或保存会话正文；只注入固定提示词。
- deep link 前检查当前输入框数量和草稿；冲突时停止，不覆盖或迁移草稿。
- 无人值守操作在 Codex 保持前台时停止；用户主动测试仍需明确确认。
- 发送后必须通过 rollout 的新 `user_message` / `task_started` 做结果确认。
- 连续失败、窗口不可见、ID 导航失败、rename 标题不匹配或 AX 树结构变化时自动停止。
- 保留 CLI 发送 POC 作为开发研究工具，但不作为主 App 的自动恢复路径；UI 中明确标注当前恢复消息未发送。

## 与当前实现的关系

当前自动恢复不会调用独立的 `codex exec resume`。日志中的“未发送”表示尚未获得并使用
macOS Accessibility 控制权；只有方案 A 完成目标会话定位、输入和回读确认后，才会记录“已注入 Codex App”。

Accessibility 方案只有在用户授权后，才有机会达到“Codex App 会话中可见并继续执行”的目标。
在 AX 内容控件定位和误操作防护完成前，不应把它作为默认自动恢复方式。
