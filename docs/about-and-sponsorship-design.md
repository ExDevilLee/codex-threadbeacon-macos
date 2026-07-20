# About 与项目支持入口设计

## 背景

ThreadBeacon 已经具备公开仓库、版本号、变更记录、技术预览 Release、隐私说明和中英文
界面，但 App 内仍缺少统一的版本与项目入口。用户遇到问题、确认版本或希望支持项目时，
需要离开 App 自行查找仓库。

本设计增加原生 macOS About 入口，并为后续自愿赞助保留一个低干扰、可替换的外部入口。
About 负责建立产品身份和可信度，不承担支付流程，也不把主状态窗口变成宣传页面。

## 目标

- 在 App 菜单提供符合 macOS 使用习惯的“关于 ThreadBeacon”入口。
- 展示 App 图标、名称、运行时版本号与构建号、产品定位和项目归属说明。
- 提供 GitHub、版本记录、隐私说明、开源协议和项目支持入口。
- About 内容跟随 ThreadBeacon 当前语言设置，支持简体中文和英文。
- 赞助入口完全自愿，不解锁功能，不影响免费使用，也不读取或上传 Codex 数据。
- 支持渠道可通过公开页面更新，不要求重新构建和发布 App。

## 非目标

- 不在主任务窗口、首次启动流程或 README 顶部展示赞助广告。
- 不在 App 内嵌微信、支付宝或其他付款二维码。
- 不接入支付 SDK、账号体系、内购、订阅或赞助状态识别。
- 不提供赞助专属功能、优先支持、数字内容或其他回报。
- 第一版不预置真实收款地址；作者选择支付渠道并完成隐私与发布审核复核后，只需更新
  外部支持页面。
- 不在 Settings 中增加重复的 About Tab。

## 方案比较

### 方案 A：About + 外部支持页面（采用）

App 内保留一个视觉层级较低的“支持项目”按钮，打开仓库中的公开支持页面。支付渠道、
二维码或地区说明均留在网页侧维护。

优点：

- About 保持简洁，赞助不会抢占状态监控这一核心产品语义。
- 支持渠道可以独立调整，不必重新发布 App。
- 避免把个人收款信息固化进 App binary。
- GitHub 直接分发版与未来 Mac App Store 版可以使用不同发布策略。

### 方案 B：About 直接内嵌付款二维码（不采用）

国内用户付款路径更短，但会增加国际化、个人信息暴露、宣传观感和 App Store 审核解释
成本，也容易让 About 看起来像支付页面。

### 方案 C：仅提供 About（暂不采用）

风险最低，但项目支持仍缺少稳定入口，后续还需要再次调整菜单和 About 布局。

## 交互设计

### 菜单入口

- 使用 macOS App 菜单中的“关于 ThreadBeacon”原生位置。
- 替换系统默认 About 动作，打开单实例 About 窗口。
- 重复点击菜单时激活已有窗口，不创建多个 About 窗口。

### About 窗口

窗口采用紧凑、居中的纵向布局，内容依次为：

1. 当前 App 图标。
2. `ThreadBeacon`。
3. 版本和构建号，例如 `版本 0.1.0（构建 1）` / `Version 0.1.0 (Build 1)`。
4. 一句话说明：用于快速查看 Codex App 与 Codex CLI 任务状态的本地 macOS 工具。
5. 项目归属说明：独立开源项目，与 OpenAI 无隶属或官方认可关系。
6. 第一行链接：`GitHub`、`版本记录`、`隐私`、`MIT License`。
7. 底部次要按钮：`支持项目`。
8. `Copyright © 2026 ExDevilLee`。

About 不显示任务、Token、Subagent、系统路径或数据源诊断信息。窗口支持浅色、深色和
系统主题，不随主窗口置顶状态变成始终置顶。

### 外部链接

所有链接都由用户主动点击后交给默认浏览器打开：

- GitHub：`https://github.com/ExDevilLee/codex-threadbeacon-macos`
- 版本记录：`https://github.com/ExDevilLee/codex-threadbeacon-macos/releases`
- 隐私：`https://github.com/ExDevilLee/codex-threadbeacon-macos/blob/main/PRIVACY.md`
- 开源协议：`https://github.com/ExDevilLee/codex-threadbeacon-macos/blob/main/LICENSE`
- 支持项目：`https://github.com/ExDevilLee/codex-threadbeacon-macos/blob/main/SPONSOR.md`

`SPONSOR.md` 第一版提供 Star、分享、Issue 和贡献等非付费支持方式，并说明付费赞助渠道
尚未启用。以后即使加入 GitHub Sponsors、Buy Me a Coffee 或微信／支付宝二维码，也只
更新该页面。页面必须继续明确：赞助完全自愿，不解锁功能，不影响免费使用。

## 技术设计

### 场景与窗口

- 在 `ThreadBeaconApp` 增加一个有稳定 ID 的单实例 `Window` Scene。
- 使用 `CommandGroup(replacing: .appInfo)` 接管原生 About 菜单动作。
- About Scene 继续注入当前 `locale` 和主题，使运行时语言切换立即反映到窗口。

### 视图与数据

- 新建独立 `ThreadBeaconAboutView`，只负责布局和用户操作。
- App 图标读取当前运行中 App 的图标，不维护第二份视觉资源。
- 版本号读取 `CFBundleShortVersionString`，构建号读取 `CFBundleVersion`。
- 缺少任一 Bundle 字段时只隐藏缺失部分，不显示 `Optional`、空括号或内部错误。
- 项目 URL 使用集中定义的常量，避免视图中散落字符串。
- 外链使用系统 `openURL` / `NSWorkspace` 打开，不在 App 内加载网页或发起后台网络请求。

### 国际化

新增文案全部进入 `Localizable.xcstrings`，以简体中文为源语言并提供英文翻译。产品名、
GitHub、OpenAI、MIT License 和作者名保持原文。About 菜单和已打开窗口都跟随 App 当前
语言覆盖设置，而不只依赖系统语言。

## 隐私与发布边界

About 本身不新增数据源、持久化字段、权限或后台网络请求。只有用户点击外部链接时，系统
才会把目标 URL 交给默认浏览器。`PRIVACY.md` 需要补充这一行为。

Apple 当前审核规则允许 App 通过 In-App Purchase 接受 tip，也对完全自愿、无数字内容或
服务回报的个人赠与保留条件；但外部购买链接和地区政策会变化。未来准备 Mac App Store
版本时，必须重新核对当时的
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)，不能把
GitHub 分发版的外部赞助入口直接视为已通过审核。

## 异常处理

- Bundle 版本字段缺失：展示可用字段；两者都缺失时展示本地化的“版本未知”。
- 系统无法打开 URL：保持 About 可用，不影响主窗口和监听；在窗口内给出简短本地化错误。
- 支持页面暂时不存在或网络不可用：由浏览器呈现结果，App 不重试、不缓存页面。
- About 窗口已打开：再次触发菜单时只将其带到前台。

## 验收标准

- App 菜单存在本地化的“关于 ThreadBeacon”入口，且只打开一个 About 窗口。
- About 显示实际构建中的版本和构建号，不硬编码 `0.1.0 (1)`。
- 中文、英文以及运行时切换语言均正确。
- 浅色、深色和系统主题下内容清晰，窗口最小尺寸下无裁切。
- GitHub、版本记录、隐私、License 和支持项目链接目标正确。
- 支持入口视觉弱于项目与版本信息，主窗口和 Settings 不增加赞助元素。
- App 中没有支付二维码、支付 SDK、赞助状态或功能解锁逻辑。
- 单元测试、SwiftPM 测试、Xcode 构建验证、隐私扫描和 Markdown lint 通过。

## 后续演进

1. 作者确定实际赞助渠道后，仅更新 `SPONSOR.md`，并补充渠道、地区和隐私说明。
2. 准备 Mac App Store 版本时重新审核赞助入口；必要时在商店构建中隐藏外部支持按钮，或
   改用符合当时规则的 In-App Purchase tip。
3. 有真实用户反馈后，再评估是否把 About 入口同步到 Settings，而不是预先增加重复入口。
