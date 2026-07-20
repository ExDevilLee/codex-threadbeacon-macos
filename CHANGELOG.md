# Changelog

ThreadBeacon 的重要用户可见变更记录在此文件中。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循
[Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Added

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

[Unreleased]: https://github.com/ExDevilLee/codex-threadbeacon-macos/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ExDevilLee/codex-threadbeacon-macos/releases/tag/v0.1.0
