# 隐私说明

## 数据范围

ThreadBeacon 只在本机读取以下 Codex 数据：

- `~/.codex/state_5.sqlite` 中近期未归档主任务及已收藏归档主任务的 ID、标题、更新时间、
  归档状态、累计 Token、rollout 路径和直接父子关系。用户展开主任务时，还会读取其直接 Subagent 的标题、昵称、角色、
  模型、Reasoning effort、更新时间、累计 Token 和 rollout 路径。
- `~/.codex/session_index.jsonl` 中与主任务或已展开直接 Subagent ID 对应的最新 rename
  名称。
- rollout JSONL 尾部的事件类型、时间戳和 Token 数字字段，用于判断状态并计算会话
  累计与当前 turn 概览。
- `~/.codex/logs_2.sqlite` 中当前可见主任务的少量结构化日志。查询仅允许
  `codex_http_client::default_client`、`codex_core::responses_retry` 和
  `codex_core::session::turn` 三个 target，并只提取 turn ID、HTTP 400/429/503、重试次数、
  明确的模型容量错误类别和最终失败时间。

App 明确不读取 `codex_http_client::transport`，因为该 target 可能包含完整请求上下文。
App 不提取 reasoning summary、用户消息、助手回复正文、完整请求、供应商 URL 或
request ID，也不读取第二层及更深子任务。原始白名单日志行只在当前刷新过程内用于解析，
不会进入任务快照、界面、偏好设置或事件历史。

## 数据处理

- 数据只在当前进程内存中用于生成界面状态。
- 数据源健康报告也只保存在当前进程内存中，包含稳定状态类别、Rollout 成功／失败数量和
  最后成功刷新时间；不保存原始错误、本机路径、任务标题、任务 ID 或日志正文，也不新增
  文件读取范围。
- App 不上传 Codex 数据，不启动网络服务，也不直接写入或修改 Codex SQLite。自动恢复总开关默认
  关闭；用户可按 HTTP 400、HTTP 429、HTTP 503、其他终止型 HTTP 错误和模型容量异常配置规则与
  提示词，HTTP 503 默认关闭。规则启用后只通过用户授权的 macOS Accessibility 控制 Codex App，
  不会调用外部 Codex CLI，也不读取或拼接会话正文。启动时历史异常不补发，同一 episode 每次运行
  只处理一次。
- App 启动后会向 `api.github.com` 请求一次公开 GitHub Release 元数据，用于比较当前版本；
  用户也可以在 About 中手动触发检查。请求包含 GitHub REST API 所需 Header 和
  `ThreadBeacon` User-Agent，不包含 Codex 数据、任务身份、本机路径、用户设置或设备标识。
  GitHub 仍可能按网络服务的常规方式处理 IP 地址、请求时间和 User-Agent。App 只在当前
  生命周期内保留可用版本号和 Release URL，不缓存 Release 响应或保存检查历史。
- About 窗口展示运行中 App 的版本和公开项目链接，不读取 Codex 数据。用户主动点击
  GitHub、版本记录、隐私、License、支持项目或新版本下载入口时，App 才把对应公开 URL
  交给 macOS 默认浏览器；除前述 Release 元数据检查外，App 不在后台加载、重试或缓存
  这些页面，也不保存点击记录。
- “登录时启动”通过 macOS 官方 `SMAppService.mainApp` 注册或注销当前 App bundle。开关读取
  系统返回的注册状态，不把登录项状态复制到 App 偏好设置，也不安装独立 helper、daemon
  或 LaunchAgent。打开登录项设置只跳转到 macOS 系统设置。
- 当前公开 UI 不提供归档恢复入口，因此正常使用不会执行 `codex unarchive` 或修改 Codex
  归档状态。仓库保留了已验证的底层恢复 POC，待 Codex App 提供可靠恢复侧边栏并打开任务
  的公开接口后再重新评估；该 POC 不直接写入 Codex SQLite，也不调用 Codex App 私有 IPC。
- 当前版本不使用通讯录、位置、相机或麦克风权限。Settings 的“自动恢复”页会读取当前 App 的
  Accessibility 授权状态；只有用户主动点击“请求授权”时才请求 macOS 辅助功能权限，也可由用户
  显式打开系统设置。Release 构建不显示手工诊断、任务 ID 和测试发送控件；这些入口只保留在本地
  Debug 构建。Debug 只读诊断遍历 Codex App 的 Accessibility 结构，并只在内存中统计窗口、输入框
  和访问节点数量；不读取、显示或保存元素标题、值与会话内容，也不切换任务。只读诊断通过后，
  用户可单独点击当前输入框验证：App 只在输入框
  唯一、为空或仅包含已验证占位值时，短暂写入固定提示词，回读后立即清空并再次确认；检测到草稿
  时拒绝覆盖。该验证不查找发送按钮、不模拟回车，也不保存输入框值。
  用户也可输入目标任务 ID 手动验证任务切换：App 使用 `codex://threads/<thread-id>` 按 ID 打开
  目标；打开前只在内存中检查当前输入框数量和值，检测到草稿、多个输入框或值不可读时立即停止，不保存
  输入框内容。通过预检后，App 在内存中读取对应 rename 标题，并通过 Codex 顶部标题栏和唯一输入框再次
  确认。用户明确确认后，可发送固定恢复提示；App 只检查目标 ID 对应 rollout 是否新增严格匹配的固定提示词和
  `task_started`，不保存消息正文，也不会自动重试。两个同名任务的实测已确认只有指定 ID 的 rollout
  发生变化；带草稿的实测已确认动作在 deep link 前停止。正式自动恢复复用同一安全链路，并在
  Codex 保持前台、检测到草稿、目标身份不唯一或已有恢复操作执行时失败关闭。上述操作不会修改
  Codex SQLite。
- App 只在本地持久化窗口是否钉在最前面、主窗口显示器标识与 frame、刷新间隔、最大
  显示任务数、提示音开关与选择、自定义提示音文件路径、自动恢复总开关和每类规则的启用状态与
  提示词，以及最多 256 个通知事件 ID。
  自定义音频不会复制、上传或写入仓库；路径仅用于本机播放，文件不可用时自动回退内置
  声音。显示器记录不包含显示器
  名称或屏幕内容；frame 只包含位置和尺寸。事件 ID 只包含主任务 ID、完成时间或异常
  episode ID 与事件类别，不包含任务标题、HTTP 状态、消息正文、reasoning、命令、URL、
  request ID 或文件内容。
- 自动恢复日志写入 `~/Library/Application Support/ThreadBeacon/auto-recovery-log.json`，最多保留
  200 条，包含会话 ID、异常 episode ID、异常类型、实际采用的提示词快照、时间和脱敏后的发送结果；不会写入任务标题、
  会话正文、日志原文或命令输出。日志可在 Settings 的“自动恢复”页查看和清空。
- 任务级收藏、置顶与忽略规则只持久化任务 ID、收藏筛选开关、忽略时间和规则类型。
  App 不把任务标题写入偏好设置；普通忽略在检测到更晚的 `task_started` 后自动删除。

## 已知边界

Codex 本地文件格式不是稳定公开 API，未来版本可能改变字段或路径。读取失败时 App 会
通过数据源健康入口标记部分降级或不可用，并使用既有安全回退；不会尝试修复或改写源数据。
`logs_2.sqlite` 是滚动
日志，历史异常可能随日志轮转消失；该数据源支持白名单结构化形态中的 400/429/503 和明确
模型容量错误，
不代表可以识别授权等待或所有错误类型。底层归档恢复 POC 依赖本机 Codex CLI 和受支持的
`unarchive` 子命令，但当前没有用户可触发入口。音频播放失败不会影响状态读取。登录时启动要求系统
识别并接受当前 App bundle；开发目录中的 ad hoc 签名构建可能返回 `notFound`，此时 App
会禁用开关，不会尝试绕过系统状态或回退到自建 LaunchAgent。当前 App 未启用 App
Sandbox；如果后续启用，需要重新评估自定义音频的安全书签或受管理副本方案。
更新检查失败、GitHub API 限流或离线不会改变 Codex 数据源健康状态，也不会阻止任务监听；
App 只在 About 的手动检查结果中显示通用失败信息，不保存原始网络错误或响应正文。
