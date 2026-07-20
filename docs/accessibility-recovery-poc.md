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

这证明方案 A 已具备无固定坐标定位任务行与输入框的技术基础，但尚未验证正式 ThreadBeacon
进程的独立授权、目标任务切换后二次身份确认、固定文本注入、发送动作和 rollout 回读。因此仍
不能把自动点击或发送逻辑接入异常恢复主链路。

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
等待 rollout 出现新的 user_message 和 task_started
        ↓
记录“已注入 Codex App”与后续执行结果
```

## 安全约束

- 默认关闭，不在用户未明确开启时申请或使用 Accessibility 权限。
- 发送前必须完成目标会话匹配；匹配失败时只记录失败，不发送。
- 不使用固定屏幕坐标作为唯一定位依据。
- 不读取或保存会话正文；只注入固定提示词。
- 发送后必须通过 rollout 的新 `user_message` / `task_started` 做结果确认。
- 连续失败、窗口不可见、会话标题不唯一或 AX 树结构变化时自动停止。
- 保留 CLI 发送 POC 作为开发研究工具，但不作为主 App 的自动恢复路径；UI 中明确标注当前恢复消息未发送。

## 与当前实现的关系

当前自动恢复不会调用独立的 `codex exec resume`。日志中的“未发送”表示尚未获得并使用
macOS Accessibility 控制权；只有方案 A 完成目标会话定位、输入和回读确认后，才会记录“已注入 Codex App”。

Accessibility 方案只有在用户授权后，才有机会达到“Codex App 会话中可见并继续执行”的目标。
在 AX 内容控件定位和误操作防护完成前，不应把它作为默认自动恢复方式。
