# ThreadBeacon 版本管理与发布设计

## 背景

ThreadBeacon 已有原生 Xcode App target、公开 README 和可用的 ad-hoc 本地构建，但还没有
正式的版本记录、Git Tag 或可供普通用户下载的 GitHub Release。当前工程版本为
`0.1.0 (1)`，也尚未取得 `Developer ID Application` 证书，因此第一阶段目标是建立一个
可重复验证的技术预览版发布闭环，而不是宣称已经达到正式公证分发标准。

## 目标

- 使用语义化版本号管理公开版本。
- 为每个公开版本维护可读的变更记录。
- 通过 Git Tag 触发可重复的 GitHub Actions 构建。
- 生成同时包含 Apple Silicon 和 Intel 架构的 `.app` 压缩包。
- 为下载产物生成 SHA-256 校验文件。
- 自动创建 GitHub Release，让用户无需自行构建即可下载。
- 在构建和上传前验证版本、架构、App 身份及代码签名。

## 非目标

第一阶段不包含：

- Developer ID Application 签名、公证和 Staple。
- DMG、PKG、Homebrew Cask 或 Mac App Store 分发。
- App 内自动更新。
- 登录时启动功能的发布环境复验或修复。
- 自动决定版本号，或根据 Commit 信息自动修改 `CHANGELOG.md`。

## 版本约定

公开版本使用 [Semantic Versioning](https://semver.org/)：

- Git Tag：`v<major>.<minor>.<patch>`，例如 `v0.1.0`。
- `CFBundleShortVersionString`：不带 `v` 的版本号，例如 `0.1.0`。
- `CFBundleVersion`：单调递增的整数构建号，例如 `1`。

Xcode 工程中的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION` 继续作为 App 版本事实
来源，避免首版额外引入配置层。发布校验脚本负责确认：

1. Tag 符合 `vX.Y.Z` 格式。
2. Tag 去掉 `v` 后与 App 的 `CFBundleShortVersionString` 完全一致。
3. `CFBundleVersion` 是正整数。
4. Debug 和 Release 配置的版本值一致。

版本升级采用显式操作：发布者先更新 Xcode 版本和构建号，再更新变更日志并提交，最后创建
Tag。自动化只验证一致性，不在 Tag 构建期间回写仓库。

## 变更记录

根目录新增 `CHANGELOG.md`，结构参考 Keep a Changelog：

- 顶部保留 `Unreleased`。
- 每个版本包含发布日期。
- 变更按 `Added`、`Changed`、`Fixed`、`Removed`、`Security` 等必要类别组织。
- 只记录对用户、兼容性或发布流程有意义的变化，不复制完整 Git Log。

创建版本前，将本次内容从 `Unreleased` 移入对应版本章节。GitHub Release notes 以该版本
章节为主要内容，并可附加 GitHub 自动生成的 Commit/PR 比较链接。

## 发布架构

发布流程由三个边界清晰的组件组成：

1. **版本与发布说明**：Xcode 版本字段和 `CHANGELOG.md` 保存人工确认的版本事实。
2. **本地发布脚本**：统一完成 Release 构建、Universal 架构、ad-hoc 签名、压缩、校验和
   产物命名；本机和 CI 使用同一入口。
3. **GitHub Actions Workflow**：监听 `v*` Tag，调用项目测试与本地发布脚本，然后创建
   GitHub Release 并上传产物。

数据流如下：

```text
版本提交 + CHANGELOG
        |
        v
     v0.1.0 Tag
        |
        v
测试 -> Release/Universal 构建 -> 身份、版本、架构、签名校验
        |
        v
ZIP + SHA-256 -> GitHub Release
```

## 构建产物

首版生成：

```text
ThreadBeacon-v0.1.0-macos-universal.zip
ThreadBeacon-v0.1.0-macos-universal.zip.sha256
```

ZIP 根目录直接包含 `ThreadBeacon.app`，用户解压后可移动到 `/Applications`。构建明确指定：

- `Release` 配置。
- `ARCHS="arm64 x86_64"`。
- `ONLY_ACTIVE_ARCH=NO`。
- ad-hoc 签名 `CODE_SIGN_IDENTITY=-`。

压缩使用 macOS 原生 `ditto`，保留 App bundle 的资源、权限和扩展属性。校验文件仅针对最终
ZIP，便于用户验证下载内容。

## 自动化流程

`.github/workflows/release.yml` 仅在推送符合 `v*` 的 Tag 时触发。失败后可以在 GitHub 页面
重新运行同一次 Workflow，但不额外提供绕过 Tag 的手动发布入口。Job 使用 GitHub 托管
macOS runner，并赋予最小的 `contents: write` 权限。

执行顺序：

1. Checkout Tag 对应 Commit。
2. 运行 `./script/test.sh`。
3. 校验 Tag、工程版本和变更日志版本章节。
4. 构建 Universal Release App。
5. 校验 App bundle 身份、版本、构建号、双架构和 ad-hoc 签名。
6. 生成 ZIP 与 SHA-256。
7. 使用 GitHub 官方 CLI 创建 Release，并上传两个产物。

尽量使用 runner 自带的 Xcode、系统工具和 `gh`，避免引入负责发布的第三方 Action。首次
实现使用 `macos-15`，其默认 Xcode 16.4 满足 Swift tools 6.1 要求；后续升级 runner 前
需要重新验证 Xcode 和最低系统兼容性。

## 失败保护

任何一项失败都终止发布，不创建不完整的 Release：

- Tag 与 App 版本不一致。
- `CHANGELOG.md` 缺少当前版本章节。
- 测试失败。
- App bundle 身份或 Bundle ID 不符合预期。
- 二进制缺少 `arm64` 或 `x86_64`。
- `codesign --verify --deep --strict` 失败。
- 压缩包或校验文件为空。

如果 Release 已存在，Workflow 不覆盖现有公开产物。需要修复时使用新的构建号和版本 Tag，
或由维护者明确删除尚未公开使用的失败 Release 后重新运行，避免同一版本对应不同二进制。

## 安装边界

`v0.1.0` 定位为 ad-hoc 签名技术预览版。README 和 Release 页面必须明确：

- 当前产物未使用 Developer ID Application 签名，也未经过 Apple 公证。
- macOS Gatekeeper 可能阻止首次直接启动，用户需要通过 Finder 的“打开”流程确认来源。
- 当前发布包不承诺登录时启动功能可用。
- 项目不会建议用户执行来源不明或大范围关闭系统安全机制的命令。

这些说明是当前分发条件的事实披露，不属于本阶段要新增或修复的 App 功能。

## 验证策略

自动验证覆盖：

- Core 测试全部通过。
- Release App 身份与 Bundle ID 正确。
- App 版本等于 Tag，构建号有效。
- 主可执行文件同时包含 `arm64` 和 `x86_64`。
- App 的 ad-hoc 签名结构有效。
- ZIP 可解压，解压后的 App 再次通过身份和签名校验。
- SHA-256 文件能反向验证 ZIP。

首次 Release 还需要人工验证：

1. 从 GitHub Release 下载 ZIP，而不是使用本地原始产物。
2. 校验 SHA-256。
3. 解压并移动到 `/Applications`。
4. 按未公证 App 的正常 Gatekeeper 流程首次打开。
5. 验证主窗口、Settings、状态刷新、Subagent 展开和提示音基本功能。
6. 验证 README 与 Release 的安装说明和真实行为一致。

## 后续演进

取得 `Developer ID Application` 后，保持版本、Tag、CHANGELOG 和产物命名规则不变，在现有
发布脚本中增加 Hardened Runtime、Developer ID 签名、公证、Staple 和 Gatekeeper 验证。
完成该阶段后，再评估登录时启动、DMG、Homebrew Cask 和自动更新。
