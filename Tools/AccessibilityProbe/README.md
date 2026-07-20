# Accessibility 只读定位 POC

该工具验证 ThreadBeacon 能否在用户已授予 macOS Accessibility 权限后，通过任务 ID 定位
Codex App 中对应的 rename 标题、可操作任务行和输入框。

默认只读扫描，不切换任务、不聚焦输入框、不写入文字、不发送消息：

```bash
swift Tools/AccessibilityProbe/main.swift --thread-id <THREAD_ID>
```

只有同时提供两个确认参数，工具才会对唯一匹配的任务按钮执行一次 `AXPress`，随后重新确认
输入框是否存在：

```bash
swift Tools/AccessibilityProbe/main.swift \
  --thread-id <THREAD_ID> \
  --select \
  --confirm-select
```

仅启用任务切换时不会输入或发送消息。任务标题只在进程内用于精确匹配，不会输出到终端或
写入文件。若 rename 标题不唯一、任务不在当前侧边栏、Codex App 未运行或 Accessibility
未授权，工具会停止，不执行任务切换。

进一步的输入框验证要求同时通过任务切换和注入两组双确认：

```bash
swift Tools/AccessibilityProbe/main.swift \
  --thread-id <THREAD_ID> \
  --select \
  --confirm-select \
  --inject \
  --confirm-inject
```

该模式要求 rename 标题在本地索引中只对应一个任务，并在切换后唯一匹配 Codex 顶部标题栏。
只有输入框为空或只包含当前已验证的“随心输入”占位提示时，才会写入固定提示词，立即通过
`AXValue` 回读，然后清空并再次确认输入框为空。Chromium/ProseMirror 的 AX 值更新可能异步
完成，工具会在写入和清空后分别等待 200ms。其他内容一律拒绝覆盖。工具仍不查找或点击发送
按钮，也不模拟回车。

当前 POC 权限属于启动 `swift` 的宿主进程，不代表正式 ThreadBeacon App 已获得同一授权。正式
能力必须由用户单独授权 ThreadBeacon，并继续补齐目标任务二次身份确认、发送确认和 rollout
回读验证后，才可进入主 App。
