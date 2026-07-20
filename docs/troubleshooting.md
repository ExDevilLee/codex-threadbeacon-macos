# ThreadBeacon 故障排查

[English](troubleshooting-en.md)

本文适用于从 GitHub Releases 下载的 ThreadBeacon macOS 技术预览版。开始前请确认系统为
macOS 14 或更高版本，并且 Codex Desktop 或 Codex CLI 已经运行过至少一个任务。

## macOS 阻止打开 App

当前技术预览包使用 ad-hoc 签名，尚未经过 Apple 公证。首次打开可能被 Gatekeeper 拦截：

1. 把 `ThreadBeacon.app` 移入 `/Applications`。
2. 在 Finder 中按住 Control 点击 App，选择“打开”。
3. 如果仍被拦截，前往“系统设置 > 隐私与安全性”，处理与 ThreadBeacon 对应的提示。

不要关闭 Gatekeeper，也不要执行来源不明的 `xattr` 或系统安全绕过命令。

## 窗口中没有任务

按顺序检查：

1. 在 Codex Desktop 或 Codex CLI 中创建并运行一个真实主任务。
2. 确认 ThreadBeacon 标题栏没有开启“仅显示收藏”。
3. 如果标题栏出现忽略管理按钮，检查任务是否被临时忽略。
4. 确认自动监听没有暂停，或点击手动刷新。
5. 点击窗口右下角的数据源健康入口，检查“任务数据库”是否正常。

ThreadBeacon 默认只显示最近的主任务，不把 Subagent 作为独立主行。Settings 可将最大任务数
设置为 `4 / 8 / 12 / 20`。如果任务数据库显示不可用，请确认当前 macOS 用户的
`~/.codex/state_5.sqlite` 存在；不要编辑或替换这个文件。

## 任务名称不是 Codex 中的最新名称

ThreadBeacon 优先读取 `~/.codex/session_index.jsonl` 中最后一次有效 rename。Rename 索引
不可用时会安全回退到任务数据库中的原始标题，并在数据源健康入口显示降级。请先刷新并
检查 Rename 索引状态，不要手工修改 Codex 数据文件。

## 状态长期显示 unknown 或没有及时变化

- 未闭合的 turn 超过 120 秒没有新事件时会显示 `unknown`，避免把中断任务一直误报为运行中。
- 长时间没有输出的工具调用也可能暂时显示 `unknown`。
- `justCompleted` 只保留 60 秒，随后变为 `idle`。
- 暂停监听期间状态不会自动刷新，但手动刷新仍可用。

如果 Rollout 数据源显示降级或不可用，请记录健康状态类别和成功／失败计数后提交 Issue；
不要附加 rollout 文件本身。

## 没有出现服务异常警告

服务异常识别只读取当前可见主任务在三个白名单日志 target 中的结构化 429/503 证据，
以及 `codex_core::session::turn` 中明确的所选模型容量错误。
日志可能轮转，旧异常不保证永久保留。ThreadBeacon 不从静默、正文或普通超时猜测异常，
也尚不能可靠识别授权等待。

## 提示音没有播放

1. 在 Settings 的“提示音”页确认总开关和对应事件开关已开启。
2. 使用“试听”验证 App 与系统输出音量。
3. 自定义声音被移动、删除或格式不受支持时，App 会回退到选定的内置声音。
4. 启动 App、手动刷新或恢复监听不会补播历史完成或异常事件。
5. 已归档收藏不会触发完成或异常提示音。

## Subagent 数量或详情不符合预期

数量表示主任务历史上创建的直接 Subagent 关系，不代表当前正在运行的数量。只有展开主任务
时才读取直接子任务详情；当前不显示第二层及更深任务树，也不聚合父子 Token。

## 登录时启动不可用

登录时启动依赖 macOS 接受稳定签名的 App bundle。当前技术预览包尚无 Developer ID
Application 签名和公证，因此不承诺该功能可用。请不要使用自建 LaunchAgent 绕过系统
状态；取得正式签名条件后项目会重新验证。

## 升级、回滚与卸载

ThreadBeacon 启动后会静默检查一次 GitHub Releases，About 中也可手动检查。发现新版本时，
底栏会显示更新图标；点击后由默认浏览器打开对应 Release 页面。如果检查失败，请确认网络
可以访问 `api.github.com`，或稍后在 About 中重试。检查失败不会影响任务监听，也不会显示
为 Codex 数据源异常。

升级前退出 ThreadBeacon，下载新版本并用新的 `ThreadBeacon.app` 替换
`/Applications` 中的旧版本。当前只有更新提醒，不会自动下载或安装。

需要回滚时，从 GitHub Releases 下载旧版本，退出当前 App 后进行替换。设置通常保留在
当前 macOS 用户偏好中；不同版本之间不承诺所有设置向后兼容。

卸载时先在 Settings 中关闭登录时启动（如果此前成功启用），退出 App，然后删除
`/Applications/ThreadBeacon.app`。ThreadBeacon 不安装独立 daemon 或系统服务。

## 提交 Issue 前

可以安全提供：

- ThreadBeacon Release 版本，例如 `v0.1.0`。
- macOS 大版本和 Mac 架构，例如 `macOS 15 / Apple Silicon`。
- Codex Desktop 或 Codex CLI 版本。
- 数据源健康入口显示的状态类别、Rollout 成功／失败计数。
- 已脱敏、可以从空白环境复现的操作步骤。

请勿公开提供：

- 任务标题、任务 ID、会话正文或 reasoning。
- `state_5.sqlite`、`logs_2.sqlite`、`session_index.jsonl` 或 rollout 文件。
- 本机用户名、绝对路径、request ID、供应商 URL、Token、Cookie 或凭据。
- 未脱敏的完整桌面截图或终端日志。

安全漏洞请遵循 [`SECURITY.md`](../SECURITY.md)，不要使用普通公开 Issue 报告敏感细节。
