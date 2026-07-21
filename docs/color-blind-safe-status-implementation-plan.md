# ThreadBeacon 色盲安全状态标识实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 macOS ThreadBeacon 增加默认关闭、即时生效的色盲安全状态标识，在不改变列表布局的前提下用颜色、形状和文字共同表达状态。

**Architecture:** `ThreadBeaconCore` 负责设置值持久化和状态到 SF Symbol 名称的稳定映射，不依赖 SwiftUI。`ThreadBeacon` 通过 `@AppStorage` 将设置传到主任务与 Subagent 行，并让 `StatusDotView` 在固定槽位内选择圆点或符号。

**Tech Stack:** Swift 6、SwiftUI、Swift Package Manager、XCTest、自定义 JSON string catalog 本地化。

---

## Task 1: 设置模型与持久化

**Files:**

- Modify: `Tests/ThreadBeaconTests/DisplaySettingsTests.swift`
- Modify: `Sources/ThreadBeaconCore/Models/DisplaySettings.swift`
- Modify: `Sources/ThreadBeaconCore/Stores/DisplaySettingsRepository.swift`

- [ ] **Step 1: 写失败测试**

在 `DisplaySettingsTests` 中断言新设置默认为 `false`、显式值会保留，Repository 保存后可重新读取：

```swift
func colorBlindSafeStatusIndicatorsDefaultsToFalse() {
    #expect(DisplaySettings().colorBlindSafeStatusIndicators == false)
}

func repositoryPersistsColorBlindSafeStatusIndicators() {
    let defaults = isolatedDefaults()
    let repository = DisplaySettingsRepository(defaults: defaults)
    repository.save(DisplaySettings(colorBlindSafeStatusIndicators: true))
    #expect(repository.load().colorBlindSafeStatusIndicators == true)
}
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `./script/test.sh`

Expected: 编译失败，提示 `DisplaySettings` 尚无 `colorBlindSafeStatusIndicators`。

- [ ] **Step 3: 添加最小生产实现**

在模型中增加默认 `false` 的 Bool，在 `DisplayPreferenceKeys` 增加 `displayColorBlindSafeStatusIndicators`，Repository 按现有模式读写该键。

- [ ] **Step 4: 运行测试并确认 GREEN**

Run: `./script/test.sh`

Expected: 全部测试通过。

## Task 2: 状态符号语义

**Files:**

- Create: `Tests/ThreadBeaconTests/StatusIndicatorPresentationTests.swift`
- Create: `Sources/ThreadBeaconCore/Models/StatusIndicatorPresentation.swift`
- Modify: `Tests/ThreadBeaconTests/TestRunner.swift`

- [ ] **Step 1: 写失败测试并注册**

覆盖七种 `ThreadDisplayStatus`，断言符号分别为：

```swift
[
    .error: "xmark.octagon.fill",
    .needsAction: "exclamationmark.square.fill",
    .warning: "exclamationmark.triangle.fill",
    .running: "play.circle.fill",
    .justCompleted: "checkmark.circle.fill",
    .idle: "minus.circle.fill",
    .unknown: "questionmark.circle.fill",
]
```

同时断言七个名称互不重复。

- [ ] **Step 2: 运行测试并确认 RED**

Run: `./script/test.sh`

Expected: 编译失败，提示 `colorBlindSafeSymbolName` 不存在。

- [ ] **Step 3: 添加纯 Core 映射**

为 `ThreadDisplayStatus` 增加只读 `colorBlindSafeSymbolName`，不导入 SwiftUI。

- [ ] **Step 4: 运行测试并确认 GREEN**

Run: `./script/test.sh`

Expected: 全部测试通过。

## Task 3: SwiftUI 展示与设置入口

**Files:**

- Modify: `Sources/ThreadBeacon/Views/StatusDotView.swift`
- Modify: `Sources/ThreadBeacon/Views/ThreadRowView.swift`
- Modify: `Sources/ThreadBeacon/Views/SubagentRowView.swift`
- Modify: `Sources/ThreadBeacon/Views/ContentView.swift`
- Modify: `Sources/ThreadBeacon/Views/ThreadBeaconSettingsView.swift`
- Modify: `Resources/Localizable.xcstrings`

- [ ] **Step 1: 在 ContentView 读取偏好**

使用 `@AppStorage(DisplayPreferenceKeys.colorBlindSafeStatusIndicators)` 读取 Bool，并传给主任务和 Subagent 行。

- [ ] **Step 2: 保持固定状态槽位**

`StatusDotView` 新增 `usesColorBlindSafeIndicators` 参数；关闭时保持现有圆点，开启时在同一个 `18 x 18` 槽位显示约 `12 x 12` 的映射 Symbol。两种模式都保留 Tooltip 和隐藏的图形无障碍节点。

- [ ] **Step 3: 添加本地化设置项**

在外观 Section 的主题设置后增加 Toggle 和说明，并为中英文 string catalog 添加：

```text
色盲安全状态标识 / Color-blind-safe status indicators
同时使用颜色、形状和文字区分任务状态。 / Distinguish task status with color, shape, and text.
```

- [ ] **Step 4: 运行单元测试和 Debug 构建**

Run: `./script/test.sh`

Run: `swift build`

Expected: 测试与 Debug 构建均成功。

## Task 4: UI 验收与文档同步

**Files:**

- Modify: `README.md`
- Modify: `README-EN.md`
- Modify: `ROADMAP.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: 构建独立 Release 产物**

Run: `./script/build_app.sh`

Expected: 仓库 `dist/` 中生成可运行 App，不覆盖 `/Applications/ThreadBeacon.app`。

- [ ] **Step 2: 完成 UI 验收**

验证中文和英文、设置开关即时生效、标准和安全模式、浅色和深色、最小窗口宽度、主任务与 Subagent，以及底部数据源健康图标。截图检查不得出现裁切、列宽漂移或空白窗口。

- [ ] **Step 3: 同步用户文档**

中英文 README 记录可选色盲安全标识；ROADMAP 标记完成；CHANGELOG 在 Unreleased 下记录功能。

- [ ] **Step 4: 运行最终验证**

Run: `./script/test.sh`

Run: `swift build -c release`

Run: `npm run lint:md -- README.md README-EN.md ROADMAP.md CHANGELOG.md docs/color-blind-safe-status-design.md docs/color-blind-safe-status-implementation-plan.md`

Run: `git diff --check`

Expected: 所有命令退出码为 0。

- [ ] **Step 5: 提交并推送**

```bash
git add Sources Tests Resources README.md README-EN.md ROADMAP.md CHANGELOG.md docs/color-blind-safe-status-implementation-plan.md
git commit -m "feat(accessibility): add color-blind-safe status indicators"
git push origin main
```
