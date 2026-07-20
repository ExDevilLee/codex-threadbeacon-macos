# Changelog

ThreadBeacon 的重要用户可见变更记录在此文件中。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循
[Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Added

- 检测到新的主任务终止型 HTTP 4xx/5xx（HTTP 503 除外）或模型容量异常 episode 后，记录固定恢复
  提示，但当前版本禁用不可见的外部 `codex exec resume` 自动发送；日志新增“未发送”状态，默认原因
  为需要 macOS Accessibility 授权。方案 A 的 Codex App 输入框注入仍处于 POC 研究阶段。
- 新增只读 `AccessibilityProbe`：可按任务 ID 匹配 rename 标题、唯一任务按钮和输入框；只有双确认
  参数才允许切换任务，默认和仅切换模式都不会输入或发送消息。
- 扩展 `AccessibilityProbe` 的受保护注入验证：要求索引标题和 Codex 顶部标题双重唯一，拒绝覆盖
  已有输入，只写入、回读并清空固定提示词，不触发发送或创建新 turn。
- Settings 的“自动恢复”页新增真实 Accessibility 授权状态和用户触发的授权／系统设置入口；
  不自动申请权限，也不启用恢复消息发送。
- 新增用户触发的 Codex Accessibility 只读诊断：只统计窗口、输入框和访问节点数量，不读取或
  显示任务标题与会话内容，不切换任务、不写输入框。正式 ThreadBeacon 进程已完成授权后实机验证。
- 新增用户触发的当前 Codex 输入框验证：只在输入框唯一且没有草稿时短暂写入固定提示词，
  回读后立即清空并再次确认；不查找发送按钮、不模拟回车，也不接入自动恢复主链路。
- 新增用户触发的目标任务验证与发送 POC：使用 `codex://threads/<thread-id>` 按 ID 打开任务，
  通过顶部 rename 标题和唯一输入框二次确认；明确确认后发送固定恢复提示，并要求目标 ID 对应
  rollout 出现严格匹配的新消息与 `task_started`。两个同名任务交换列表位置前后均验证仅命中指定 ID。
- 新增目标切换前的输入冲突保护：当前 Codex 输入框存在草稿或输入框数量不唯一时，在 deep link
  前停止；无人值守模式还会在 Codex 保持前台时停止。草稿阻断已完成正式 App 实机验证。

### Documentation

- 补充真实任务现场验证记录：HTTP 400 已确认可被正确关联并显示为红色服务失败状态；验证
  证据脱敏处理，不公开会话 ID、任务标题或日志正文。

## [0.1.2] - 2026-07-20

### Added

- 识别白名单结构化日志中的 HTTP 400 Bad Request，将其显示为红色失败状态并沿用服务异常
  提示音；不扫描会话正文或扩大日志 target 范围。

### Fixed

- About 窗口标题现在会随 App 语言即时切换，不再出现英文内容配中文窗口标题。

## [0.1.1] - 2026-07-20

### Added

- 识别 `codex_core::session::turn` 中明确记录的“所选模型容量已满”终止错误，显示红色失败
  状态并沿用服务异常提示音；不读取请求 transport 或会话正文。
- 启动后静默检查最新非 Draft GitHub Release（技术预览阶段包含 prerelease）；发现新版本时
  在主窗口底栏显示更新图标，About 支持手动检查、重试并打开对应下载页。该功能不自动
  下载或安装，失败不影响 Codex 任务监听和数据源健康状态。
- 原生 About 窗口展示 App 图标、运行时版本与构建号、项目说明，以及 GitHub、Releases、
  隐私、License 和外部项目支持入口；支持简体中文和英文。
- 新增中英双语 `SPONSOR.md`，第一版只提供 Star、分享、Issue 和贡献方式，不在 App 内
  嵌入支付渠道、付款二维码或功能解锁。
- 中英文 README 增加 macOS 14+ 系统要求、Release 徽章和 30 秒快速开始。
- 中英文故障排查覆盖首次打开、空列表、状态、提示音、升级、回滚、卸载和安全诊断范围。
- GitHub Bug/Feature Issue Forms、Pull Request 模板和贡献指南，反馈入口明确禁止上传 Codex
  数据文件、会话内容、本机路径或凭据。
- 启用 GitHub 私密漏洞报告，并为仓库添加 Codex、macOS、SwiftUI、开发工具和任务监控
  Topics。
- `v0.1.0` Release notes 增加英文功能摘要、系统要求、预览限制和英文上手入口。

## [0.1.0] - 2026-07-20

### Added

- 原生 macOS 状态窗口，集中展示 Codex Desktop 与 Codex CLI 主任务的红黄绿状态、rename
  后名称、持续时间和运行任务数。
- 会话累计 Token 概览及输入、缓存输入、输出、Reasoning、当前 turn 和缓存率详情。
- 直接 Subagent 数量和行内展开，展示 Agent 别名、状态、最近活动、模型、Reasoning 和
  Token 明细。
- 主任务收藏、仅显示收藏、任务置顶、临时忽略及恢复操作；收藏的归档任务仍可查看。
- 自动监听暂停与恢复、手动刷新，以及 `1 / 2 / 5 / 10 秒`刷新间隔和最大任务数设置。
- 窗口钉在最前面，并记忆窗口所在显示器、位置和尺寸。
- 主任务完成与 HTTP 429/503 服务异常的独立提示音；支持内置声音、自定义本地音频和试听。
- 原生 Settings，支持跟随系统、简体中文和 English，以及 System、Light 和 Dark 主题。
- 本机 Codex 数据源健康状态和不包含任务身份、路径或原始错误的诊断详情。
- 面向 Apple Silicon 和 Intel Mac 的 Universal App 技术预览构建及 SHA-256 校验文件。

### Security

- 以只读方式访问 `~/.codex` 中的 SQLite、session index、rollout 和白名单服务日志，不读取
  会话正文或 reasoning summary，不上传数据，也不请求 Accessibility 权限。
- 429/503 解析仅使用白名单日志 target，不读取完整请求、供应商 URL 或 request ID。

### Known Limitations

- Codex 的本机数据格式不是稳定公开 API，Codex 升级后可能需要适配。
- 授权等待没有可靠的只读数据源，当前不会从正文或静默状态猜测。
- 技术预览包使用 ad-hoc 签名，尚未取得 Developer ID Application 签名或 Apple 公证；
  macOS Gatekeeper 可能要求用户在首次打开时确认来源。
- 登录时启动已经实现，但在当前发布签名条件下不承诺可用。

[Unreleased]: https://github.com/ExDevilLee/codex-threadbeacon-macos/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/ExDevilLee/codex-threadbeacon-macos/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/ExDevilLee/codex-threadbeacon-macos/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/ExDevilLee/codex-threadbeacon-macos/releases/tag/v0.1.0
