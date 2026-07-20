# About 与项目支持入口实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 ThreadBeacon 增加原生 macOS About 窗口和低干扰外部“支持项目”入口。

**Architecture:** 使用单实例 SwiftUI `Window` Scene 和替换后的 `.appInfo` Command 提供原生
菜单入口。可测试的 Bundle 版本解析放入 `ThreadBeaconCore`，About 视图只负责展示和打开
集中定义的项目链接；赞助渠道留在仓库 `SPONSOR.md`，App 不承载支付信息。

**Tech Stack:** Swift 6、SwiftUI、AppKit、String Catalog、SwiftPM 自定义测试运行器、
Xcode macOS App target。

---

## 文件结构

- `Sources/ThreadBeaconCore/Models/AboutAppInfo.swift`：解析并格式化 App 版本元数据。
- `Tests/ThreadBeaconTests/AboutAppInfoTests.swift`：覆盖完整、部分和缺失 Bundle 字段。
- `Tests/ThreadBeaconTests/TestRunner.swift`：注册新增测试。
- `Sources/ThreadBeacon/Support/ProjectLinks.swift`：集中维护公开项目 URL。
- `Sources/ThreadBeacon/Views/ThreadBeaconAboutView.swift`：About 布局与外链错误反馈。
- `Sources/ThreadBeacon/App/ThreadBeaconApp.swift`：注册 About Scene 和原生菜单命令。
- `Resources/Localizable.xcstrings`：新增中英文 About 文案。
- `SPONSOR.md`：公开项目支持页面，第一版不含真实支付方式。
- `PRIVACY.md`、`ROADMAP.md`、`CHANGELOG.md`：同步用户可见行为和路线图状态。

### Task 1：可测试的 App 版本信息

**Files:**

- Create: `Sources/ThreadBeaconCore/Models/AboutAppInfo.swift`
- Create: `Tests/ThreadBeaconTests/AboutAppInfoTests.swift`
- Modify: `Tests/ThreadBeaconTests/TestRunner.swift`

- [x] **Step 1：写失败测试**

```swift
import ThreadBeaconCore

let aboutAppInfoTests = [
    TestCase(name: "about info reads version and build") {
        let info = AboutAppInfo(infoDictionary: [
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "1"
        ])
        try expect(info.version == "0.1.0", "version should be read")
        try expect(info.build == "1", "build should be read")
    },
    TestCase(name: "about info trims empty values") {
        let info = AboutAppInfo(infoDictionary: [
            "CFBundleShortVersionString": "  ",
            "CFBundleVersion": "7"
        ])
        try expect(info.version == nil, "empty version should be absent")
        try expect(info.build == "7", "build should remain available")
    }
]
```

并在 `TestRunner` 的测试数组中加入 `aboutAppInfoTests`。

- [x] **Step 2：运行测试并确认失败**

Run: `./script/test.sh`

Expected: 编译失败，提示找不到 `AboutAppInfo`。

- [x] **Step 3：实现最小版本模型**

```swift
import Foundation

public struct AboutAppInfo: Equatable, Sendable {
    public let version: String?
    public let build: String?

    public init(infoDictionary: [String: Any]?) {
        version = Self.value(for: "CFBundleShortVersionString", in: infoDictionary)
        build = Self.value(for: "CFBundleVersion", in: infoDictionary)
    }

    private static func value(for key: String, in dictionary: [String: Any]?) -> String? {
        guard let rawValue = dictionary?[key] as? String else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
```

- [x] **Step 4：运行测试并确认通过**

Run: `./script/test.sh`

Expected: 全部测试通过，测试总数增加 3。

### Task 2：About 视图和原生菜单入口

**Files:**

- Create: `Sources/ThreadBeacon/Support/ProjectLinks.swift`
- Create: `Sources/ThreadBeacon/Views/ThreadBeaconAboutView.swift`
- Modify: `Sources/ThreadBeacon/App/ThreadBeaconApp.swift`
- Modify: `Resources/Localizable.xcstrings`

- [x] **Step 1：集中定义项目链接**

```swift
import Foundation

enum ProjectLinks {
    static let repository = URL(string: "https://github.com/ExDevilLee/codex-threadbeacon-macos")!
    static let releases = repository.appending(path: "releases")
    static let privacy = repository.appending(path: "blob/main/PRIVACY.md")
    static let license = repository.appending(path: "blob/main/LICENSE")
    static let sponsor = repository.appending(path: "blob/main/SPONSOR.md")
}
```

- [x] **Step 2：实现紧凑 About 视图**

`ThreadBeaconAboutView` 使用 `NSApplication.shared.applicationIconImage`、
`AboutAppInfo(infoDictionary: Bundle.main.infoDictionary)` 和 `NSWorkspace.shared.open`。
窗口内容按设计顺序展示；版本文本根据字段组合：

```swift
private var versionText: String {
    switch (appInfo.version, appInfo.build) {
    case let (.some(version), .some(build)):
        AppLocalization.formatted("版本 %@（构建 %@）", locale: locale, version, build)
    case let (.some(version), nil):
        AppLocalization.formatted("版本 %@", locale: locale, version)
    case let (nil, .some(build)):
        AppLocalization.formatted("构建 %@", locale: locale, build)
    case (nil, nil):
        AppLocalization.string("版本未知", locale: locale)
    }
}
```

项目链接采用一行 `.buttonStyle(.link)` 的 `Button`，支持项目采用独立次要 `Button`。
`NSWorkspace.shared.open` 返回失败时设置本地状态并显示 `alert("无法打开链接", ...)`，
不影响其他入口。

- [x] **Step 3：注册单实例 Scene 与菜单 Command**

在 `ThreadBeaconApp.body` 增加：

```swift
Window("关于 ThreadBeacon", id: "about") {
    ThreadBeaconAboutView()
        .environment(\.locale, appLanguageStore.locale)
        .environmentObject(appLanguageStore)
        .preferredColorScheme(selectedTheme.colorScheme)
}
.windowResizability(.contentSize)
```

主 `WindowGroup` 增加 `.commands { ThreadBeaconAboutCommands() }`。Commands 使用
`@Environment(\.openWindow)`，以 `CommandGroup(replacing: .appInfo)` 创建本地化按钮并调用
`openWindow(id: "about")`。

- [x] **Step 4：补全中英文 String Catalog**

至少新增：`关于 ThreadBeacon`、版本组合文案、产品简介、非官方说明、`版本记录`、`隐私`、
`支持项目`、`无法打开链接`、`版本未知`。每个源字符串都提供英文值，并保持
`ThreadBeacon`、`OpenAI`、`GitHub` 和 `MIT License` 原文。

- [x] **Step 5：构建验证**

Run: `./script/test.sh && ./script/build_and_run.sh --verify`

Expected: 测试全部通过，Xcode 构建成功，ThreadBeacon 进程保持运行。

### Task 3：支持页面与公开文档同步

**Files:**

- Create: `SPONSOR.md`
- Modify: `PRIVACY.md`
- Modify: `ROADMAP.md`
- Modify: `CHANGELOG.md`

- [x] **Step 1：创建中英双语支持页面**

`SPONSOR.md` 明确免费和自愿原则，并提供 Star、分享项目、提交隐私安全 Issue、贡献代码／
文档四种方式。付费部分明确写为“尚未启用”，不放二维码、账号或支付链接。

- [x] **Step 2：同步隐私与 Roadmap**

`PRIVACY.md` 补充 About 只在用户点击时把公开 URL 交给默认浏览器，不在后台联网。
`ROADMAP.md` 将 App 内版本/About 入口标记为已完成，并记录后续付费渠道与 Mac App Store
审核复核。

- [x] **Step 3：记录变更**

在 `CHANGELOG.md` 的 `Unreleased` 下记录 About、版本信息、公开项目链接和外部支持页面。

- [x] **Step 4：校验文档**

Run:

```bash
npm run lint:md -- \
  poc/codex-thread-status-macos/docs/about-and-sponsorship-implementation-plan.md \
  poc/codex-thread-status-macos/SPONSOR.md \
  poc/codex-thread-status-macos/PRIVACY.md \
  poc/codex-thread-status-macos/ROADMAP.md \
  poc/codex-thread-status-macos/CHANGELOG.md
```

Expected: `0 error(s)`。

### Task 4：完整回归与交付

**Files:**

- Verify: 本计划列出的全部文件

- [x] **Step 1：运行自动验证**

Run:

```bash
./script/test.sh
./script/build_and_run.sh --verify
git diff --check
```

Expected: 测试、构建、进程检查和 Git 空白检查全部通过。

- [x] **Step 2：检查隐私和支付边界**

Run:

```bash
rg -n -i 'alipay|wechat pay|paypal|buy me a coffee|收款|付款|二维码' \
  Sources Resources SPONSOR.md
```

Expected: App 源码和资源中没有支付渠道或二维码；只允许 `SPONSOR.md` 出现解释性文字。

- [x] **Step 3：人工验收清单**

- 中文和英文菜单均能打开单实例 About。
- About 显示实际 `0.1.0` 和构建 `1`。
- 运行时切换语言、浅色和深色主题后内容同步变化。
- GitHub、Releases、Privacy、License 和 Support 五个链接能交给默认浏览器。
- 主窗口与 Settings 没有新增赞助广告。

- [x] **Step 4：提交实现**

只暂存本计划涉及的文件，检查 `git diff --cached --check`，使用 Conventional Commit：

```bash
git commit -m "feat(about): add project information window"
```
