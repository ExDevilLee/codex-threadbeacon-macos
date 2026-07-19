# 公开分享前检查表

本文记录 ThreadBeacon 从“自己使用的 POC”走向 GitHub 公开源码和更多用户试用前的收口项。
它不等同于 App Store 发布计划；当前目标是让技术用户能够理解边界、完成构建并安全试用。

## 当前结论

当前仓库可以公开源码，也可以让熟悉 Xcode 的用户自行构建。普通用户直接下载后运行仍未
达到 ready，原因有三项：

1. 还没有 Developer ID Application 签名、公证和稳定安装包。
2. 登录时启动在当前免费 Personal Team / Apple Development 环境下实测返回 `notFound`，
   需要 Developer ID 条件具备后重新验证。
3. README 还缺少面向新用户的宣传截图、安装演示和完整国际化体验。

## P0：不完成就不建议发布安装包

- [ ] 使用 Developer ID Application 签名构建稳定 `.app`。
- [ ] 完成公证、Gatekeeper 验证和可重复下载校验。
- [ ] 在 `/Applications` 安装后验证启动、升级、卸载和回滚。
- [ ] 重新验证 `SMAppService.mainApp`：注册、`requiresApproval`、系统设置批准、登录
      重启、注销和重复安装。
- [ ] 检查发布包和 Git 历史，不包含 Team ID、邮箱、私钥、真实任务标题、SQLite 数据、
      rollout、日志、本机绝对路径或个人配置。

## P1：建议在邀请更多用户前完成

- [ ] 简体中文和英文界面完整覆盖；默认跟随系统语言，Settings 可覆盖。
- [ ] README 首页放置脱敏截图：主列表、红绿灯状态、Subagent 展开、Token 详情、Settings
      和异常提示音设置。
- [ ] 提供一段 20～40 秒 GIF 或短视频，展示“启动 App → 状态刷新 → 完成/异常提示”。
- [ ] README 明确说明数据来源是本机 `~/.codex`，只读范围、非官方关系、数据格式兼容
      风险和当前不支持的能力。
- [ ] 提供从源码构建、安装、升级、卸载、常见错误和权限排查说明。
- [ ] 增加 GitHub Issue 模板、贡献指南、变更日志和安全问题报告入口。

## P2：公开后逐步补齐

- [ ] GitHub Releases 自动生成产物和校验文件。
- [ ] 评估 Homebrew Cask 等分发方式，不把未公证构建作为默认推荐路径。
- [ ] 根据真实反馈决定是否加入主题、更多状态、压缩历史、CLI 长周期兼容和副屏支持。
- [ ] Windows 版本继续使用独立仓库和独立发布流程，不与 macOS 源码混合。

## 当前推荐顺序

1. 先完成国际化和宣传素材，提升技术用户试用时的理解成本。
2. 再准备 Developer ID、公证和安装包流水线。
3. 拿到签名条件后复验登录启动，并把结果更新到 Roadmap。
4. 最后创建第一版 GitHub Release，邀请少量技术用户试用并收集兼容性反馈。
