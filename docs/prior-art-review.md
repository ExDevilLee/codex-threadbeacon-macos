# GitHub 同类项目与 Prior Art 核查

## 结论

查询日期：2026-07-16

当前命名决定：产品名称为 `ThreadBeacon for Codex`，App 显示名为
`ThreadBeacon`，macOS 平台仓库为 `codex-threadbeacon-macos`。下文保留检索时使用的
旧项目名和旧仓库 URL，作为 prior-art 结论与开发时间线证据。

本次核查采用 `small prior-art scan`：通过 GitHub repository search、code
search、项目 README、关键源码和相关文件的提交历史，选取 8 个代表性项目进行
对比。它不是对 GitHub 的穷尽检索，项目功能也可能在本次查询后继续变化。

结论分为四点：

1. “同时监控多个 AI 编程任务，以红黄绿状态展示，并让窗口保持可见”已经有
   明确 prior art，不能把这个产品概念宣称为本项目原创。
2. 读取 Codex 的 rollout JSONL、`state_5.sqlite` 和
   `session_index.jsonl` 也已有多个项目采用，不能将这些数据源本身作为独创点。
3. 本项目当前仍有清晰定位差异：专注 Codex App 的多条主任务列表，优先使用
   rename 后标题，默认过滤 subagent，只读取推导状态所需的最小本地数据，不安装
   hooks，也不把状态窗扩展成完整 Codex 客户端。
4. 公开前更需要处理的是名称辨识度，而不是代码雷同：GitHub 已存在多个使用
   `Codex Traffic Light`、`codex-traffic-light` 和“Codex 红绿灯”的项目。

当前仓库的首个独立提交为
[`45675ef`](https://github.com/ExDevilLee/codex-traffic-light/commit/45675ef0b5d7dfa8eb35018095a81ae428249c7f)，
提交时间为 2026-07-16 15:55:46 +08:00；本次 prior-art 检索在该提交和首次私有
推送完成后开展。该时间线能证明本次横向检索没有先于第一版 POC，并为独立开发
过程保留同时期证据；但它不能证明开发者此前从未接触任何同类想法，也不能据此
主张产品概念或通用技术路径的原创性。

## 代表项目对比

下表中的功能描述来自各项目自己的 README 和源码，只能证明项目如何描述或实现
自己，不能视为第三方独立评价。

| 项目 | 与本项目相同或接近 | 主要实现路径 | 关键差异 |
| --- | --- | --- | --- |
| [CodeIsland](https://github.com/wxtsky/CodeIsland) | 多任务状态、Codex App、rename 标题、rollout、本地 SQLite、置顶状态面板 | hooks + Unix socket；Codex App 额外启动 `codex app-server`；也读取 `state_5.sqlite`、`session_index.jsonl` 和 rollout | 面向 13 种工具，Dynamic Island、权限审批、问题回答、终端跳转、移动端伴侣，产品范围远大于本项目 |
| [agent-signaller](https://github.com/Jasjah/agent-signaller) | 多会话、红黄绿、始终置顶、一眼查看状态 | Codex/Claude hooks 写入本地 session JSON，App 约每 0.4 秒轮询 | 面向 CLI；一个会话一个点；可跳转终端、切换样式、色盲配色、完成提示音 |
| [agent-traffic-light](https://github.com/stars1324/agent-traffic-light) | 多会话卡片、红黄绿、置顶窗口 | hook/命令通过 UDP 上报，并用 PID 检查进程存活 | Python/Tk，面向 Claude Code 和 Codex CLI，需要显式接入命令或 hooks |
| [codex-honglvdeng-traffic-light](https://github.com/st44464322/codex-honglvdeng-traffic-light) | 中文“Codex 红绿灯”名称、悬浮窗口、状态灯、提示音 | 命令、脚本或 hooks 写入自己的 `state.json` | 主要表达单一聚合状态，不读取 Codex App 主任务列表；名称和视觉概念最容易造成混淆 |
| [CodexDynamicIsland](https://github.com/maxbogo/CodexDynamicIsland) | Codex App/CLI、多 session、状态、rename 标题 | 扫描 `~/.codex/sessions` rollout，并读取 `session_index.jsonl` | Dynamic Island/自由定位；显示会话聊天历史，可选等待审批提醒和颜色 |
| [AI Light](https://github.com/LeoKemp223/ai-light) | 多 Codex 会话、红黄绿、置顶、rollout 文件监听 | Tauri/Rust；Claude hooks + 本地 HTTP，Codex rollout watcher + 进程扫描 | 按项目聚合，跨 Windows/macOS，支持 SSH/LAN 远程转发和诊断菜单 |
| [CodexStatusLight](https://github.com/Huoyuan461/codex-status-light-macos) | macOS 原生状态灯；只读 SQLite + rollout；不要求 hooks | 只读最新 `state_*.sqlite`，查询最近任务并解析 rollout 尾部 | 只显示最近一个 session，菜单栏/悬浮单灯，不读取 rename index；2026-07-14 创建 |
| [CodexMonitor](https://github.com/Dimillian/CodexMonitor) | 多 Codex task、运行/未读状态 | 每个 workspace 启动 `codex app-server` | 是完整 Codex 编排客户端，包含对话、worktree、Git、终端、远程 daemon 等，不是轻量状态窗 |

## 关键实现证据

### CodeIsland

- [`SessionTitleStore.swift`](https://github.com/wxtsky/CodeIsland/blob/3e2aec7fa87c56b0f5129d7ba11d0dc3699dd500/Sources/CodeIsland/SessionTitleStore.swift)
  读取 `~/.codex/session_index.jsonl` 并按 session ID 解析标题。
- [`AppState.swift`](https://github.com/wxtsky/CodeIsland/blob/3e2aec7fa87c56b0f5129d7ba11d0dc3699dd500/Sources/CodeIsland/AppState.swift)
  使用 `state_5.sqlite` 查找 rollout，并包含 rollout 文件发现逻辑。
- [`AppState+CodexAppServer.swift`](https://github.com/wxtsky/CodeIsland/blob/3e2aec7fa87c56b0f5129d7ba11d0dc3699dd500/Sources/CodeIsland/AppState%2BCodexAppServer.swift)
  在 Codex App 运行时启动 `codex app-server`，接收
  `thread/status/changed` 等 JSON-RPC 事件。
- 标题支持最早可追溯到
  [`2cd9441c`](https://github.com/wxtsky/CodeIsland/commit/2cd9441cea5292c4c328599dfced603be4837d34)，
  Codex App Server 支持最早可追溯到
  [`0a6ab924`](https://github.com/wxtsky/CodeIsland/commit/0a6ab924e32cdc3cc49a2625f0fa4f6014e4eae0)。

### CodexDynamicIsland 与 AI Light

- [`CodexSessionMonitor.swift`](https://github.com/maxbogo/CodexDynamicIsland/blob/222e60952ca9b65c59011997a3f5af27712605ed/CodexDynamicIsland/Services/Session/CodexSessionMonitor.swift)
  扫描 `~/.codex/sessions` 下的 rollout JSONL；
  [`CodexSessionStore.swift`](https://github.com/maxbogo/CodexDynamicIsland/blob/222e60952ca9b65c59011997a3f5af27712605ed/CodexDynamicIsland/Services/State/CodexSessionStore.swift)
  读取 `session_index.jsonl`。
- [AI Light README](https://github.com/LeoKemp223/ai-light/blob/a406c52d14f08400929e73f3845cc0744dcfb258/README.md)
  说明其 Codex 路径无需 hooks，而是监听本地 rollout；对应 watcher 最早可追溯到
  [`bd172d4b`](https://github.com/LeoKemp223/ai-light/commit/bd172d4bd361bd840805bc0b9a8757fcb880b773)。

### CodexStatusLight

- [`CodexSessionMonitor.swift`](https://github.com/Huoyuan461/codex-status-light-macos/blob/9c36a8e3ac7770d6df478f480df3667d2615ae28/CodexStatusLight/Monitoring/CodexSessionMonitor.swift)
  以 read-only 模式打开最新的 `state_*.sqlite`，查询最近一条未归档任务，并读取
  rollout 尾部推导状态。
- 该实现最早可追溯到初始提交
  [`9a55840d`](https://github.com/Huoyuan461/codex-status-light-macos/commit/9a55840da51c3cc6ae666e6b58866f81aff7145c)。

## 本项目可保留的差异化边界

下列内容应被描述为当前产品定位和功能组合，不应使用“首创”“唯一”或“独家实现”
等措辞：

- **任务列表优先**：一屏显示多个 Codex App 主任务，而不是单一聚合灯或一个 session
  一个无标题圆点。
- **Codex App 语义优先**：列表名称跟随 Codex App rename 后标题，保留归档和主任务
  语义。
- **默认隔离 subagent 噪音**：只展示主任务，未来即使加入 subagent，也优先做主任务
  上的数量或异常摘要。
- **最小读取原则**：不读取或展示对话正文、reasoning summary，不上传数据，不修改
  Codex 配置。
- **零接入 POC**：当前不安装 hooks、不启动本地服务，打开 App 即可读取现有 Codex
  本地状态。
- **小窗口与小屏延展**：当前先验证桌面 glanceability，未来才评估 USB 副屏或小型
  扩展屏，不把主窗口扩成完整 Codex 客户端。

## 值得参考的功能候选

这些候选来自横向对比中的优点，但尚未自动进入 ROADMAP。后续若采用，应重新写需求、
交互和代码，并在对应 issue/提交中注明“功能灵感来自公开同类产品调研”，不要复制对方
源码、素材、文案、动画或独特视觉布局。

| 候选功能 | 参考项目 | 用户价值 | 与当前方向 | 建议 |
| --- | --- | --- | --- | --- |
| 完成/需操作提示音，可分别关闭并防止重复播放 | agent-signaller、CodeIsland、codex-honglvdeng | 不看窗口也能知道状态变化 | 高 | `近期`，已在 ROADMAP；优先系统音和本地设置 |
| 色盲安全模式，同时使用颜色、形状或文字 | agent-signaller | 避免只依赖红绿区分状态 | 高 | `近期候选`，应与主题设置一起设计 |
| 点击任务跳回 Codex App 对应任务 | CodeIsland 的 jump、agent-signaller 的 terminal focus | 从发现状态到处理任务形成闭环 | 高 | `研究`，先确认 Codex App 是否有稳定 deep link 或可定位 API |
| `needsAction` 的明确事件源 | CodeIsland 的 `codex app-server` | 比超时推断更准确地识别审批和提问 | 高 | `研究优先`，评估只读监听、进程生命周期和协议兼容性 |
| 状态数据源健康诊断 | AI Light | 格式变化时能说明“为什么状态不准” | 高 | `近期候选`，提供最后刷新、数据源和解析错误，不显示隐私内容 |
| 菜单栏聚合状态或折叠模式 | CodexStatusLight、CodexDynamicIsland | 窗口隐藏时仍可一眼看到异常或完成 | 中 | `后续候选`，不能替代主任务列表 |
| 可选择显示器、记忆窗口位置 | CodeIsland、CodexStatusLight、agent-signaller | 适合副屏和多显示器工作流 | 高 | `近期候选`，也为未来 USB 小屏验证打基础 |
| 登录时启动 | CodeIsland、agent-signaller、codex-honglvdeng | 降低日常使用摩擦 | 中 | `后续候选`，需明确可关闭且不偷偷安装服务 |
| 刷新间隔和低功耗策略 | agent-signaller、多个 watcher 项目 | 平衡状态及时性、CPU 和磁盘读取 | 高 | `近期`，已在 Settings 规划；可考虑文件变化触发 + 低频兜底 |
| 远程机器状态汇总 | AI Light、CodexMonitor | 一台 Mac 查看远端 agent | 低到中 | `后续研究`，涉及认证、网络暴露和隐私，不进入近期版本 |
| 手机/手表/外接设备伴侣 | CodeIsland | 离开电脑或使用专用小屏时仍能查看 | 中 | `远期研究`，先验证桌面窗口真实使用频率 |
| Token/额度显示 | CodexMonitor、CodeIsland | 帮助判断上下文和额度风险 | 中 | `研究`，已在 ROADMAP；应默认隐藏，避免状态窗信息过载 |

## 暂不建议参考的方向

- **直接在状态窗审批、回答问题或控制 Codex**：会把只读工具变成控制面，扩大权限、
  协议兼容和误操作风险。
- **宠物、像素角色或 Dynamic Island 独特视觉**：已有项目形成鲜明识别，不符合当前
  紧凑任务列表定位，也容易产生视觉模仿观感。
- **完成 streak、成就和复杂统计**：与“降低查看成本”的核心需求关系较弱。
- **一次支持大量 AI 工具**：会稀释 Codex App rename、主任务和 subagent 过滤这些
  当前最有价值的语义。
- **复制 hooks 配置或安装脚本**：当前零接入、只读的使用方式本身是重要边界。

## 名称与公开发布建议

GitHub 搜索已经出现以下命名模式：

- `codex-traffic-light`
- `CodexTrafficLight`
- `Codex 红绿灯`
- `codex-honglvdeng-traffic-light`

因此，“Codex 红绿灯”只保留为中文功能类比，正式产品名采用
`ThreadBeacon for Codex`，macOS 仓库采用 `codex-threadbeacon-macos`。项目继续保留
“非官方社区工具”声明。

## 后续避免雷同争议的执行规则

1. 保留本文件、首个 POC 提交和后续设计决策的 Git 时间线。
2. 新增来自同类产品启发的功能时，先写自己的使用场景和验收标准，再独立实现。
3. 不复制外部项目的源码、测试、图标、截图、文案、动画、音效包或独特页面布局。
4. 如果必须复用开源代码，先核对许可证、版权声明和 attribution 要求，并在提交前
   单独记录来源；不能只因为项目标有 MIT 就直接复制而不保留声明。
5. README 对定位使用可验证的窄表述，不宣称通用概念、数据文件或红绿灯语义为原创。
6. 公开前再次做一次名称搜索和相似项目增量扫描，因为这个类别目前更新很快。

## 来源清单

- [CodeIsland README](https://github.com/wxtsky/CodeIsland/blob/3e2aec7fa87c56b0f5129d7ba11d0dc3699dd500/README.md)
- [agent-signaller README](https://github.com/Jasjah/agent-signaller/blob/17ea7f1ca7db1d8762202f1d382619ab543aa1c4/README.md)
- [agent-traffic-light README](https://github.com/stars1324/agent-traffic-light/blob/dc84d196596a594c5070ab12145cb4ae38fb25c3/README.md)
- [codex-honglvdeng-traffic-light README](https://github.com/st44464322/codex-honglvdeng-traffic-light/blob/00c5f007cf1849bcac7e9d7c585fce1f0bc67a66/README.md)
- [CodexDynamicIsland README](https://github.com/maxbogo/CodexDynamicIsland/blob/222e60952ca9b65c59011997a3f5af27712605ed/README.md)
- [AI Light README](https://github.com/LeoKemp223/ai-light/blob/a406c52d14f08400929e73f3845cc0744dcfb258/README.md)
- [CodexStatusLight README](https://github.com/Huoyuan461/codex-status-light-macos/blob/9c36a8e3ac7770d6df478f480df3667d2615ae28/README.md)
- [CodexMonitor README](https://github.com/Dimillian/CodexMonitor/blob/dd61b9abd37de5ded86e82b9fe8a83fd49d46fa5/README.md)
