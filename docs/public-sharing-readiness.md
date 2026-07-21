# 公开分享前检查表

本文记录 ThreadBeacon 从“自己使用的 POC”走向 GitHub 公开源码和更多用户试用前的收口项。
它不等同于 App Store 发布计划；当前目标是让技术用户能够理解边界、完成构建并安全试用。

## 当前结论

当前仓库可以公开源码，也具备由 Git Tag 自动生成的 Universal App 技术预览下载包。用户
不再必须安装 Xcode 或自行构建，但它仍未达到正式分发 ready，原因有两项：

1. 还没有 Developer ID Application 签名和 Apple 公证，首次启动仍有 Gatekeeper 摩擦。
2. 登录时启动在当前免费 Personal Team / Apple Development 环境下实测返回 `notFound`，
   需要 Developer ID 条件具备后重新验证。

当前 Release 应明确标记为技术预览，不代替下面的正式分发 P0 条件。

## P0：不完成就不建议发布安装包

- [ ] 使用 Developer ID Application 签名构建稳定 `.app`。
- [ ] 完成公证、Gatekeeper 验证和可重复下载校验。
- [ ] 在 `/Applications` 安装后验证启动、升级、卸载和回滚。
- [ ] 重新验证 `SMAppService.mainApp`：注册、`requiresApproval`、系统设置批准、登录
      重启、注销和重复安装。
- [ ] 检查发布包和 Git 历史，不包含 Team ID、邮箱、私钥、真实任务标题、SQLite 数据、
      rollout、日志、本机绝对路径或个人配置。

## P1：建议在邀请更多用户前完成

- [x] 简体中文和英文界面完整覆盖；默认跟随系统语言，Settings 可覆盖。
- [x] README 首页放置脱敏截图：主列表、红绿灯状态、Subagent 展开、Token 详情、Settings
      和异常提示音设置。
- [x] README 已提供静态产品截图；暂不制作演示 GIF 或短视频，避免维护额外宣传素材。
- [x] README 明确说明数据来源是本机 `~/.codex`，只读范围、非官方关系、数据格式兼容
      风险和当前不支持的能力。
- [x] 提供 Release 下载、SHA-256 校验、安装、升级、回滚、卸载、首次打开、空列表、
      常见错误和从源码构建说明。
- [x] 增加变更日志和安全问题报告入口。
- [x] 增加隐私安全的 Bug/Feature Issue Forms、PR 模板和贡献指南。

## P2：公开后逐步补齐

- [x] GitHub Releases 自动生成 Universal App ZIP、SHA-256 和版本说明。
- [x] 项目自有 Homebrew Tap 提供固定版本和 SHA-256 的 Cask，并验证下载、隔离安装与卸载；
      未公证构建仍明确标记为技术预览，不把 Homebrew 描述为绕过 Gatekeeper 的方式。
- [ ] 下一个版本发布时验证 Homebrew 跨版本升级和维护者回滚，再决定是否自动创建 Cask 更新 PR。
- [ ] 根据真实反馈决定是否加入主题、更多状态、压缩历史、CLI 长周期兼容和副屏支持。
- [ ] Windows 版本继续使用独立仓库和独立发布流程，不与 macOS 源码混合。

## 当前推荐顺序

1. 继续邀请少量技术用户验证 GitHub Release 和 Homebrew Cask 技术预览安装路径。
2. 下一个版本发布时验证 Homebrew 跨版本升级与维护者回滚。
3. 补充色盲安全设计。
4. 拿到 Developer ID 后加入签名、公证和 Staple，并重新验证 Gatekeeper。
5. 在正式签名环境复验登录启动，并把结果更新到 Roadmap。
