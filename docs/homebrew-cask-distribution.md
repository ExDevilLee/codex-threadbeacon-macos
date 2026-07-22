# Homebrew Cask 分发

> 实现状态：MVP 已完成。项目自有 Tap 已公开，下载、校验、隔离安装、卸载、跨版本升级和
> 回滚模拟均已验证。当前仍是 ad-hoc、未公证的技术预览。

## 目标与边界

Homebrew Cask 为不想手工下载 ZIP、校验并拖入 `/Applications` 的用户提供一条命令式安装
路径。它复用 ThreadBeacon 已有的 GitHub Release Universal ZIP，不重新构建或镜像二进制。

Homebrew 不替代 Developer ID Application 签名和 Apple 公证，也不会关闭或绕过 Gatekeeper。
当前 ad-hoc 签名产物继续明确标记为技术预览版。

## 仓库与职责

- App 源码与 Release：
  [`ExDevilLee/codex-threadbeacon-macos`](https://github.com/ExDevilLee/codex-threadbeacon-macos)
- Cask 与分发 CI：
  [`ExDevilLee/homebrew-tap`](https://github.com/ExDevilLee/homebrew-tap)
- Cask token：`threadbeacon`
- 安装命令：`brew install --cask ExDevilLee/tap/threadbeacon`

两个仓库保持独立。App 仓库负责产生不可变 Release 资产；Tap 只固定版本、下载 URL、SHA-256、
最低系统版本、App artifact 和 `zap` 清理范围。

## 当前 Cask 契约

- 使用 ThreadBeacon GitHub Release 的 `ThreadBeacon-vX.Y.Z-macos-universal.zip`。
- `version` 与 Release Tag 去除 `v` 后一致。
- `sha256` 必须来自实际 ZIP，不能只信任文件名或 Release 描述。
- 最低系统版本为 macOS 14 Sonoma。
- 普通卸载只移除 App，保留用户设置。
- `--zap` 额外清理偏好文件和 `~/Library/Application Support/ThreadBeacon` 自动恢复日志。
- 不声明 `auto_updates true`：当前检查更新功能只打开 Release 页面，不会自动下载安装。
- Cask 使用 `caveats` 在安装结束后说明当前未公证边界，并给出“完成”、Control-click“打开”
  和“隐私与安全性 > 仍要打开”的安全处理路径；不建议用户绕过 Gatekeeper。

## 已完成验证

截至 `v0.1.6` 已完成：

1. `brew style --cask exdevillee/tap/threadbeacon`，无 offenses。
2. `brew audit --cask --strict --online` 能正常解析 Cask；因为当前 Release 是 prerelease，Homebrew
   按策略报告 `v0.1.6 is a GitHub pre-release`，这是发布渠道限制，不是 Cask 内容或 SHA 错误。
3. `brew upgrade --cask exdevillee/tap/threadbeacon` 将本机 Cask 从 `0.1.4` 升级到 `0.1.6`，下载
   SHA-256 校验通过。
4. 校验 App 版本 `0.1.6 (7)`、Bundle ID、`arm64 + x86_64` 架构和 ad-hoc 签名。
5. 升级前后语言、主题、刷新间隔、最大任务数、提示音、自定义声音、收藏/忽略和自动恢复规则
   均保留；窗口位置允许由 App 启动时正常重写。
6. 使用已发布的 `v0.1.5` ZIP 做本地回滚模拟，再通过 `brew upgrade` 回到 `v0.1.6`，设置语义保持。
7. App 启动进程正常；`spctl` 对未公证 ad-hoc 包的拒绝符合当前 README 的 Gatekeeper 说明。

完整限定命令会按 Homebrew 6 的 Tap Trust 规则只信任目标 Cask，不要求用户信任整个 Tap。

## 版本更新流程

首版采用人工更新，避免过早引入跨仓库写权限：

1. ThreadBeacon App 仓库完成版本、Changelog、Tag 和 Release。
2. 下载 Release ZIP，核对 App 版本、架构、签名与 SHA-256。
3. 在 Tap 仓库更新 `Casks/threadbeacon.rb` 的 `version` 和 `sha256`。
4. 通过 Pull Request 运行 Tap CI。
5. 合并后执行真实 `brew update` 和 `brew upgrade --cask threadbeacon`。
6. 确认设置保留、App 可启动，并执行卸载与维护者回滚演练。

验证两个连续版本后，可以让 App Release Workflow 使用最小权限的 GitHub App 或 fine-grained
token 向 Tap 创建更新 PR。自动化不应直接推送 Tap 的 `main`，也不应在 App Release 尚未成功时
提前更新 Cask。

## 回滚边界

Homebrew Cask 没有面向普通用户的通用 `brew rollback` 命令。当前用户回滚继续使用 GitHub
Releases 中的历史 ZIP；Tap 的“维护者回滚”指恢复上一个已验证 Cask 版本并重新运行 CI，而不是
承诺任意历史版本的一键安装。

## 官方 Homebrew Cask

当前不向官方 `homebrew/cask` 提交。正式评估需要至少满足：

- Developer ID Application 签名和 Apple 公证，不依赖绕过 Gatekeeper。
- 项目具备足够的公开使用证据和稳定维护周期。
- 最新 macOS、Apple Silicon 与 Intel 声明范围持续可验证。

达到这些条件前，项目自有 Tap 是范围更清楚、维护责任更明确的分发方式。
