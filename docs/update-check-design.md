# 检查更新功能设计

## 背景

ThreadBeacon 已经通过 Git Tag 和 GitHub Releases 发布可直接下载的 Universal App，但 App
本身无法判断是否存在新版本。用户必须主动打开仓库，才能发现并下载更新。

当前 `v0.1.0` 属于 GitHub prerelease。GitHub 的 `releases/latest` 接口只返回最新的非
Draft、非 prerelease 版本，因此技术预览阶段不能依赖该接口；第一版需要读取 Release
列表并自行选择最新的可用版本。

## 目标

- App 启动后静默检查一次 GitHub Releases。
- 技术预览阶段跟踪最新的非 Draft Release，包括 prerelease。
- 有新版本时在主窗口底栏显示低干扰的更新图标。
- 用户点击图标后，用默认浏览器打开该版本的 GitHub Release 页面。
- About 窗口提供“检查更新”手动入口，并明确显示检查结果。
- 更新检查与 Codex 数据读取、任务监听和数据源健康状态相互隔离。
- 中文、英文、浅色和深色主题下均保持清晰。

## 非目标

- 不自动下载、安装、替换或重启 App。
- 不集成 Sparkle 或其他自动更新框架。
- 不强制弹窗，不阻止用户继续使用旧版本。
- 不上传 Codex 任务、Token、路径、日志、设备标识或系统配置。
- 第一版不提供“稳定版／预览版”更新通道设置。

## 更新来源与版本规则

请求公开接口：

`GET https://api.github.com/repos/ExDevilLee/codex-threadbeacon-macos/releases?per_page=20`

请求包含 GitHub 推荐的 `Accept`、API 版本和可识别的 `User-Agent`。响应处理规则：

1. 忽略所有 Draft。
2. 技术预览阶段保留 prerelease。
3. 只接受可以解析为 SemVer 的 Tag，例如 `v0.2.0`、`0.2.0-beta.1`。
4. 不依赖 API 返回顺序，按 SemVer 选择最高版本。
5. 最高版本大于当前 `CFBundleShortVersionString` 时显示更新。
6. 相同或更旧版本视为当前已是最新版本。
7. 无法解析的 Tag 不阻塞其他 Release 的判断。

未来出现稳定 Release 后，可在 Settings 增加“稳定版／预览版”通道；在此之前不增加无效
配置。

## 自动检查交互

- 主窗口出现约 5 秒后发起检查，避免与首次 Codex 状态读取争抢启动时机。
- 每次 App 生命周期最多自动检查一次，不按 2 秒任务刷新周期重复请求。
- 检查期间不显示进度图标，不改变底栏任务刷新文案。
- 有新版本时，在右下角数据源健康按钮左侧显示 `arrow.down.circle.fill`。
- Tooltip 和无障碍标签显示“发现新版本 v0.2.0”。
- 点击后用默认浏览器打开该 Release 的 `html_url`。
- 更新图标与数据源健康按钮保持间距，避免误解为 Codex 数据异常。

## About 手动入口

About 在版本信息下方增加“检查更新”按钮：

- 未检查：显示“检查更新”。
- 检查中：按钮禁用并显示小型进度指示。
- 已是最新：显示“当前已是最新版本”。
- 有更新：显示“发现新版本 v0.2.0”，并提供“前往下载”按钮。
- 检查失败：显示“暂时无法检查更新，请稍后重试。”，允许再次检查。
- 当前 Bundle 版本缺失或不是 SemVer：不发起网络请求，显示无法确定当前版本。

自动检查失败不主动呈现错误；用户进入 About 并手动检查时才显示失败反馈。

## 技术结构

- `SemanticVersion`：解析和比较 SemVer，独立于 UI 和网络。
- `GitHubRelease` / `AvailableUpdate`：公开 Release 元数据和用户可用更新。
- `GitHubReleaseClient`：请求、解码和筛选 GitHub Releases。
- `UpdateCheckStore`：在主线程管理检查状态、每次启动一次的自动检查约束和手动重试。
- `ThreadBeaconApp`：创建共享 Store，并注入主窗口与 About。
- `ContentView`：负责延迟触发自动检查和展示更新图标。
- `ThreadBeaconAboutView`：负责手动检查状态与下载入口。

## 隐私与故障边界

更新检查会改变此前“只有点击链接才联网”的行为，因此必须同步隐私说明：

- App 启动后会向 `api.github.com` 请求公开 Release 元数据。
- 请求不包含 Codex 数据、用户设置、本机路径或设备标识。
- GitHub 仍可能按网络服务常规方式看到 IP、请求时间和 User-Agent。
- 响应只保留当前生命周期需要的版本号和 Release URL，不写入 Codex 数据库。
- 网络失败、HTTP 异常、解码失败或限流均不影响任务列表、监听、提示音和健康状态。

## 验收标准

- `0.1.0` 能正确识别 `v0.2.0` 为新版本，不能把 `v0.1.0` 识别为更新。
- SemVer 正确处理 prerelease 顺序，忽略无效 Tag 和 Draft。
- 每次 App 生命周期自动检查最多一次，手动检查可重复执行。
- 有更新时底栏显示图标，点击打开具体 Release 页面。
- About 能显示检查中、最新版、有更新、失败和当前版本无效状态。
- 自动检查失败不显示弹窗，不影响 Codex 数据源健康状态。
- 新文案具备简体中文和英文翻译。
- 单元测试、App 构建、Markdown lint、隐私扫描和差异检查通过。

## 后续演进

1. 出现稳定 Release 后增加“稳定版／预览版”更新通道。
2. 获得 Developer ID Application 签名并完成公证后，再评估 Sparkle 自动更新。
3. 有真实使用反馈后再考虑检查频率、忽略某版本或 Release notes 摘要。
