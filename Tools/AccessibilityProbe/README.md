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

即使启用任务切换，该 POC 也没有输入或发送消息的代码路径。任务标题只在进程内用于精确匹配，
不会输出到终端或写入文件。若 rename 标题不唯一、任务不在当前侧边栏、Codex App 未运行或
Accessibility 未授权，工具会停止，不执行任务切换。

当前 POC 权限属于启动 `swift` 的宿主进程，不代表正式 ThreadBeacon App 已获得同一授权。正式
能力必须由用户单独授权 ThreadBeacon，并继续补齐目标任务二次校验、输入框唯一性、固定提示词
注入、发送确认和 rollout 回读验证后，才可进入主 App。
