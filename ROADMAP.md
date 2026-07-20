# ThreadBeacon Roadmap

## 用途

本文用于记录产品想法、验证顺序和实现状态。除“已完成”项目外，其余内容均为候选方向，不代表已经承诺交付；每项功能进入开发前，仍需结合真实使用反馈确认优先级和最小范围。

状态说明：

- `已完成`：当前版本已经具备并通过验证。
- `近期`：下一阶段优先验证，目标是改善日常可用性。
- `研究`：需要先确认数据来源、交互价值或技术可行性。
- `后续`：方向成立，但不进入近期开发范围。

## 产品原则

- 保持“一眼看懂任务状态”的核心，不把窗口做成另一个完整 Codex 客户端。
- 默认界面保持紧凑；新增信息应支持按需显示或折叠。
- 优先使用本机只读数据，明确标注非公开数据格式带来的兼容风险。
- 先通过 macOS 真实使用验证需求，再投入跨平台和外接小屏适配。

## 已完成

- macOS 独立小窗口，集中显示最近 Codex 主任务及状态灯。
- 使用 Codex App rename 后的任务名称，并过滤 subagent 子线程。
- 每 2 秒自动刷新，支持手动刷新。
- 支持临时暂停和恢复自动监听；暂停期间保留手动刷新，重启后默认恢复监听。
- 窗口可钉在最前面，并持久化选择。
- 不显示会话摘要，保持状态视图简洁。
- 接入 `B1 Graphite / Code Beacon` App 图标。
- 主列表紧凑显示会话累计 Token，并通过 info popover 按需展示输入、缓存、输出、
  Reasoning、当前 turn 和缓存率；默认不聚合 subagent。
- 主任务行显示直接 Subagent 总数，并使用父子关系表补强子任务过滤；数量不表示实时
  运行状态。
- **已完成（Feature 6A）**：点击数量标记可行内展开直接 Subagent，默认以
  `Agent 别名 ｜ 标题` 显示名称，并显示状态、最近活动和自身累计 Token；info 详情显示
  昵称、角色、模型、Reasoning 和 Token 明细。
- **已完成（Feature 6A）**：只为已展开且当前可见的主任务批量读取子任务，展开状态仅
  在本次 App 生命周期保留；不读取正文、不显示更深任务树、不聚合父子 Token。
- **POC 已验证**：Codex CLI 创建并 rename 的真实任务可进入现有列表；状态、rename 后
  标题、rollout 事件和 Token 数据均可由当前只读数据链路获取。验证边界见
  [`docs/codex-cli-compatibility.md`](docs/codex-cli-compatibility.md)。
- **已完成**：底部提供状态数据源健康入口，区分`正常`、`部分降级`和`不可用`；详情按需
  展示任务数据库、Rename 索引、Rollout、服务日志、最后成功刷新时间和 Rollout 读取计数。
  诊断只使用稳定类别和数量，不显示原始错误、路径或任务身份。设计见
  [`docs/data-source-health-diagnostics-design.md`](docs/data-source-health-diagnostics-design.md)。

## 近期：日常操作闭环

### 任务右键菜单

- **已完成（阶段一）**：右键主任务可置顶或取消置顶；状态优先级高于置顶，同状态内
  置顶任务优先。这是任务级置顶，与窗口“钉在最前面”分开。
- **已完成（阶段一）**：右键可临时忽略任务；新 turn 自动恢复，工具栏支持单项恢复与
  全部恢复。
- **已完成（阶段一）**：置顶和忽略规则只保存任务 ID、忽略时间与规则类型，不修改
  Codex App 中的任务数据。
- `永久忽略`、按标题/状态/项目匹配和用户自定义忽略规则保留为后续候选，进入开发前先
  根据临时忽略的真实使用反馈确定配置模型。

### 收藏会话与归档管理

- **已完成（阶段一）**：主任务右键支持`收藏会话`和`取消收藏`；收藏与现有置顶是两种
  独立语义：置顶只影响当前列表排序，收藏用于形成长期关注集合和筛选范围。
- **已完成（阶段一）**：工具栏支持在`全部会话`与`仅显示收藏`之间切换；筛选状态会持久化，
  并提供清晰的空状态和一键返回全部会话入口。
- **已完成（阶段一）**：收藏信息只保存稳定任务 ID，不保存标题、正文或会话内容；会话
  rename 后继续沿用 Codex 的最新名称。
- **已完成（阶段一）**：已收藏会话即使在 Codex 中归档，也继续出现在收藏列表，并明确
  显示`已归档`标记；归档状态不应被显示成运行中，也不触发完成或异常提示音。
- **研究（阶段一）**：验证已归档会话能否继续可靠读取 rename 后标题、最近状态、Token
  和 Subagent 信息；数据缺失时保留收藏记录，并显示降级状态而不是静默消失。
- **POC 已验证，UI 暂时隐藏（阶段二）**：底层实现可调用官方
  `codex unarchive <SESSION>` 取消归档；成功后保留收藏并刷新 SQLite 真实状态。实现支持
  `PATH`、Homebrew、常见用户目录和 NVM 路径，能区分 CLI 缺失、版本不支持与执行失败，
  不直接修改 Codex SQLite。
- **上游限制（阶段二）**：当前 `codex unarchive` 不更新侧边栏使用的 `recency_at_ms`；
  Codex App `26.715.21425` 的 `codex://threads/<thread-id>` 对实测恢复旧会话提示找不到。
  因此右键`恢复为激活状态`入口暂时隐藏。在 OpenAI 提供能可靠恢复侧边栏并打开任务的
  公开接口前，不重新启用；不直接修改 SQLite 排序字段，也不调用 Codex App 私有 IPC。
- **后续**：收藏管理可扩展为批量取消收藏、按项目分组、收藏排序和收藏会话数量提示；
  是否支持“收藏后自动置顶”应作为显式设置，默认不耦合两种行为。手动指定 Codex CLI
  路径可在最小 Settings 中作为诊断和兼容性候选。

### 完成与状态提示音

- **已完成（阶段一）**：主任务收到新的 `task_complete` 事件时播放一次 `done` 提示音。
- **已完成（阶段一）**：默认避免重复播放；App 重启、手动刷新、暂停和恢复监听不会把
  旧任务误判为新完成。
- **已完成（阶段一）**：提示音设置支持总开关、完成开关、八个内置声音和试听；默认
  完成音为 Chime，服务异常音为 Alert。Fupicat Notification 和 Bassguitar
  Notification 是仓库内提供的 CC0 可选素材，不作为默认声音；已有用户保存的声音选择保持不变。
- **POC 已完成（阶段二）**：独立 app-server 能列出 Desktop 任务 ID，但所有状态均为
  `notLoaded`，无法看到 Desktop 已加载线程或接收其实时事件；详见
  [`docs/app-server-integration-poc.md`](docs/app-server-integration-poc.md)。
- **已完成（阶段三）**：通过只读 `logs_2.sqlite` 的三个白名单 target 识别 HTTP
  400/429/503 与明确的模型容量错误。429/503 自动重试显示黄色 `warning`，HTTP 400、
  重试耗尽和模型容量错误显示红色 `error`；新 turn 和同 turn
  后续成功会清除旧 warning。
- **真实验证已完成（2026-07-20）**：使用真实 Codex 任务确认 HTTP 400 能在列表中正确显示
  为红色 `Service failed · HTTP 400`，并保留异常持续时间；原始会话 ID、任务标题和日志正文
  不进入公开文档。
- **已完成（阶段三）**：每个异常 episode 只播放一次独立警告音；最终失败覆盖 rollout
  的误导性完成状态，不播放错误的完成音。详见
  [`docs/service-incident-monitoring.md`](docs/service-incident-monitoring.md)。
- **仍受阻**：`attention` / 授权等待没有可靠只读数据源；等待共享 daemon、只读订阅
  接口或稳定 hook 后再验证，不从会话正文猜测。
- **已完成（自定义提示音 MVP）**：完成与服务异常可分别选择本地音频、试听和清除；
  自定义文件优先，文件被移动、删除或格式不受支持时自动回退各自选定的内置声音。
  当前 App 未启用 Sandbox，因此只在本机偏好中保存所选文件路径，不申请额外权限；
  后续若启用 App Sandbox，需要改用安全书签或复制到 App 管理目录。

### 最小 Settings

- **已完成（阶段一）**：使用原生 macOS Settings 窗口统一管理通用设置和提示音；主窗口
  齿轮按钮与系统 App 菜单均可打开。
- **已完成（阶段一）**：刷新间隔支持 `1 / 2 / 5 / 10 秒`，默认 `2 秒`；最大显示任务数
  支持 `4 / 8 / 12 / 20`，默认 `8`。修改后立即生效并持久化，暂停监听时仍可手动刷新。
- **已完成（阶段一）**：完成提示音和服务异常提示音已整合进 Settings；两类声音仍可
  分别关闭、试听和选择。
- **已完成实现，等待签名条件复验（登录启动 MVP）**：使用官方 `SMAppService.mainApp`
  注册或注销主 App，开关直接反映 macOS 系统状态；`requiresApproval` 保持开启并提供
  系统登录项设置入口，失败会给出明确反馈。正式 Xcode App target、Apple Development
  签名和 `/Applications` 安装均已验证，但当前免费 Personal Team 仍返回 `notFound`。
  该功能暂不继续推进，等获得 Developer ID Application 签名后再做注册、审批、重启登录
  和注销的端到端复验。
- 管理已忽略任务，并支持恢复。
- **已完成（P1 国际化 MVP）**：界面支持`跟随系统`、`简体中文`和`English`三档，切换后立即
  生效并持久化。跟随系统时，中文系统映射为简体中文；英文及其他系统语言统一回退为
  English，避免出现未翻译或混合语言界面。
- **已完成（P1 主题设置 MVP）**：配置主题颜色，支持 `System`、`Light` 和 `Dark`，默认跟随系统；切换后主窗口和 Settings 立即生效并持久化。
- **已完成（About MVP）**：App 菜单提供单实例 About 窗口，展示图标、运行时版本与构建号、
  项目定位、非官方说明和 GitHub、Releases、隐私、License 链接；支持简体中文和英文。
- **已完成（项目支持入口 MVP）**：About 提供低干扰的外部支持入口，第一版支持页面仅列出
  Star、分享、Issue 和贡献方式。App 内不嵌付款二维码或支付 SDK，不以赞助解锁功能；
  后续启用真实渠道前需要复核隐私、宣传观感和届时适用的 Mac App Store 规则。
- **已完成（检查更新 MVP）**：启动后静默检查一次 GitHub Releases，技术预览阶段跟踪
  最新非 Draft Release（包含 prerelease）；发现新版本时在底栏显示更新图标，About 支持
  手动检查和重试，点击后打开对应 Release 下载页。网络失败不影响任务监听和数据源健康
  状态；第一版不自动下载或安装。稳定版发布后再评估更新通道设置。
- 为后续的显示列和 subagent 选项保留统一入口。

## 研究：信息增强与数据适配

### 更多状态与数据

- `状态颜色`：保留现有红黄绿灯的主语义，补充 `needsAction`、`error`、`unknown` 时避免只依赖颜色表达。
- `Subagent 后续增强`：直接 Subagent 行内展开已完成；可靠的实时活动数量、异常提示、
  更深任务树和任务树 Token 聚合继续保留为后续候选。可行性边界见
  [`docs/subagent-count-feasibility.md`](docs/subagent-count-feasibility.md) 和
  [`docs/subagent-expansion-and-compaction-feasibility.md`](docs/subagent-expansion-and-compaction-feasibility.md)。
- `压缩可观测性`：rollout 可显示历史压缩次数和最近完成时间，但不能判断实时压缩状态或
  百分比进度；共享 app-server 或可选 `PreCompact` / `PostCompact` Hook 可提供开始、完成和
  耗时，但仍只能使用不确定进度动画。作为独立 POC 评估，不与 Subagent 展开首版绑定。
- **MVP 已完成（异常记录）**：检测到新的主任务终止型 400、429 或模型容量异常 episode 后，
  ThreadBeacon 记录固定恢复提示，但当前版本禁用不可见的外部 `codex exec resume` 自动发送；
  日志会明确记录“未发送：需要 macOS Accessibility 授权”。503 明确排除，启动时的历史异常只登记
  不发送，同一 episode 每次运行只记录一次。后续再通过 Settings 配置状态到动作、重试次数、冷却时间
  和人工确认策略。发送链路和独立 app-server 的跨进程限制见
  [`docs/app-server-integration-poc.md`](docs/app-server-integration-poc.md)。
- **研究（Codex App 内可见恢复）**：如果希望恢复消息真正出现在 Codex App 对应会话中，
  需要通过 macOS Accessibility 控制 Codex App 输入框并发送；用户必须单独授予辅助功能权限。
  未授权时只读监控并记录未发送，不使用外部 CLI 恢复。AX 树检查和安全约束见
  [`docs/accessibility-recovery-poc.md`](docs/accessibility-recovery-poc.md)。
- **POC 进行中（Accessibility）**：已验证按任务 ID deep link 打开目标任务、顶部 rename 标题
  二次确认、固定提示词写入／回读／清空；Settings 已增加真实授权状态和用户触发
  的授权入口。正式 App 已完成授权后的 Codex AX 只读访问验证，只输出窗口、输入框和节点计数。
  正式 App 已完成当前任务输入框的固定提示词写入／回读／清理，以及用户确认后的真实发送。
  两个同名活跃任务在交换列表位置前后各完成一次指定 ID 发送，只有目标 ID 的 rollout 新增严格
  匹配的固定提示词、`task_started` 与 `task_complete`，另一个同名任务保持不变。
- **当前边界（Accessibility）**：AX 树不暴露任务 ID；当前依赖版本敏感的
  `codex://threads/<thread-id>` 按 ID 导航，再以 rename 标题和目标 rollout 回读确认。切换 Codex
  当前任务可能干扰用户同时编辑的其他任务，因此无人值守自动发送仍保持关闭，下一阶段必须增加
  前台输入冲突保护与安全停止策略。
- 所有新增列默认可隐藏，避免破坏小窗口和未来小屏场景。

### Codex CLI 适配

- **POC 已验证**：当前真实 CLI 样本写入 ThreadBeacon 使用的 SQLite、session index 和
  rollout 数据源，无需新增数据源即可显示任务、rename 后标题、状态和 Token。
- 当前结论基于 macOS 和 `codex-cli 0.144.1` 的单个真实样本，不等同于完整兼容承诺。
- 后续验证 CLI 任务的归档、resume、跨版本升级和长生命周期行为；若数据格式或生命
  周期出现差异，再评估统一的只读任务快照层。

## 后续：覆盖范围

### 多显示器与窗口位置

- **已完成（阶段一）**：主窗口自动记住最后所在显示器、位置和尺寸，重新启动后恢复；
  Settings 窗口使用独立生命周期，不会覆盖主窗口记录。
- **已完成（阶段一）**：保存的显示器不可用时回退到当前主显示器，并把窗口约束在可见区域；
  保存尺寸大于当前显示器可见区域时自动缩小，避免窗口出现在屏幕外。
- **当前边界**：只在启动时恢复，不在运行期间响应显示器热插拔，也不提供显式显示器
  选择器。当前机器只有内置显示器，主窗口移动、缩放和重启恢复已真实验证；副屏恢复由
  纯逻辑测试覆盖，仍需接入真实副屏复验。

### 国际化

- **已完成（P1 MVP）**：首批界面文案已接入 Apple String Catalog，覆盖 Settings、主窗口常用
  操作、状态和诊断入口；支持简体中文与英文，默认跟随系统并允许在 Settings 中覆盖。
- **后续**：继续增加更多语言。新增语言需同步补充 String Catalog、系统语言映射、排版长度
  和状态灯/无障碍文案验证，不改变任务标题、Agent 别名、模型名和日志原文。

### 主题颜色

- **已完成（P1 MVP）**：支持 `Light` 和 `Dark` 两种明确主题。
- **已完成（P1 MVP）**：默认使用 `System` 跟随 macOS 外观，并允许在 Settings 中固定选择；切换立即生效并持久化。
- **已完成（P1 MVP）**：主窗口、Settings 和 Popover 使用系统自适应颜色，状态灯保留独立颜色语义，不只依赖背景颜色区分状态。

### Windows 版本

- 先验证 Windows 上 Codex 数据文件的位置、锁机制和格式是否一致。
- 状态推导逻辑尽量复用，窗口管理、提示音和打包使用平台实现。
- macOS 版本形成稳定使用习惯和数据契约前，不启动完整移植。

## 公开分享前检查

当前版本已具备可下载的 ad-hoc 签名 Universal App 技术预览包，但尚未达到 Developer ID
签名、公证和普通用户无障碍安装的正式分发标准。公开分享继续按下面优先级收口：

- **已完成（技术预览发布 MVP）**：使用 SemVer、`CHANGELOG.md` 和 `v*` Git Tag 管理版本；
  Tag 触发 GitHub Actions 测试、构建 `arm64 + x86_64` Universal App、验证身份/版本/架构/
  ad-hoc 签名，并上传 ZIP、SHA-256 和 Release notes。
- **已完成（技术预览发布 MVP）**：中英文 README 提供 GitHub Releases 下载、校验、安装和
  Gatekeeper 首次打开说明；不建议关闭系统安全保护。

- `P0`：准备固定安装包流程，使用 Developer ID Application 签名并完成公证；同时复验
  登录启动功能。当前免费 Personal Team 的 `Apple Development` 结果已记录为
  `notFound`，不能把它当作已支持。
- `P0`：检查公开仓库中不包含 Team ID、邮箱、钥匙串导出、真实任务标题、SQLite/rollout
  数据、日志和本机路径；示例配置只使用占位符。
- **已完成（P1）**：README 使用脱敏截图覆盖主列表、状态灯、Subagent 展开、Token 详情
  和 Settings；暂不规划演示 GIF。
- **已完成（P1）**：简体中文和英文界面国际化，默认跟随系统语言，并在 Settings 中提供
  覆盖；README 保持中文主文档与英文入口同步。
- **已完成（P1 上手包 v1）**：中英文 README 提供系统要求和 30 秒快速开始；中英文故障
  排查覆盖首次打开、空列表、状态、提示音、升级、回滚、卸载和隐私安全诊断范围。
- **已完成（P1 上手包 v1）**：提供 Bug/Feature Issue Forms、PR 模板和贡献指南，反馈入口
  明确禁止上传 Codex 数据文件、会话内容、本机路径或凭据。
- `P2`：GitHub Releases、变更日志与安全问题报告入口已具备；继续评估 Homebrew Cask 或
  其他分发渠道。

详细检查表见 [`docs/public-sharing-readiness.md`](docs/public-sharing-readiness.md)。

## 待验证问题

- “状态优先、同状态内置顶优先”是否既能保留异常可见性，又能帮助用户稳定找到重点任务？
- 临时忽略在新 turn 时自动恢复是否符合真实使用预期，还是需要增加永久忽略和自定义规则？
- 收藏与置顶的独立语义是否足够清晰，用户是否真的需要长期收藏集合？
- `仅显示收藏`应作为持久筛选模式，还是每次启动默认回到全部会话？
- 已归档收藏会话需要保留哪些状态详情，才能在信息价值与读取成本之间取得平衡？
- 当前 CLI 自动发现范围是否覆盖足够多的安装方式，还是需要在 Settings 中允许手动选择？
- 当前紧凑 Token 概览能否帮助决策，还是仍会增加状态窗负担？
- 当前 Subagent 行内展开是否帮助判断并行任务进度，还是增加了列表滚动负担？
- Codex 后续是否会提供可供独立 App 使用的只读实时事件接口？
- Codex CLI 的归档、resume 和跨版本升级是否始终保持当前任务身份、rename 与状态语义？

## 建议顺序

1. 创建并验证第一版 GitHub Release，邀请少量技术用户试用技术预览包。
2. 通过检查更新 MVP 验证技术预览用户能否及时发现并打开后续 Release。
3. 获得 Developer ID Application 后补齐正式签名、公证，并完成登录启动端到端验证。
4. 补充色盲安全设计；根据真实反馈决定是否启用外部付费赞助渠道。
5. 真实副屏恢复复验，并根据反馈决定是否增加显式显示器选择器。
6. Codex CLI 长生命周期、归档、resume 与跨版本兼容性验证。
7. 扩展状态、压缩历史、Token 与 Subagent 后续增强可行性验证。
8. 外接小屏和 Windows 版本扩展。
