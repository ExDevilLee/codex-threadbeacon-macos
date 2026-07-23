# “刚完成”状态保留时间 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让用户在 Settings 中选择任务完成状态保留 `1～5 分钟`，并在修改后立即以基线刷新应用到主任务和 Subagent。

**Architecture:** 配置继续归属 `DisplaySettings` 和 `UserDefaults`。当前值进入 `ThreadStatusStore` 的加载请求，由 App 层作为秒数传给 `ThreadStatusLoader`，避免重建独立计时器；设置变化只触发一次 `.baseline` 刷新，因此不会补播完成提示音。

**Tech Stack:** Swift 6、SwiftUI、Combine、Foundation `UserDefaults`、现有自定义测试运行器。

---

### Task 1: 扩展显示设置模型和持久化

**Files:**

- Modify: `Sources/ThreadBeaconCore/Models/DisplaySettings.swift`
- Modify: `Sources/ThreadBeaconCore/Stores/DisplaySettingsRepository.swift`
- Test: `Tests/ThreadBeaconTests/DisplaySettingsTests.swift`

- [ ] **Step 1: 编写失败测试**

在 `DisplaySettingsTests.swift` 增加合法值、非法值回退、默认一分钟和 Repository round trip：

```swift
let settings = DisplaySettings(
    refreshIntervalSeconds: 2,
    maximumTaskCount: 8,
    justCompletedRetentionMinutes: 5
)
try expect(settings.justCompletedRetentionMinutes == 5, "supported retention should be retained")

let invalid = DisplaySettings(
    refreshIntervalSeconds: 2,
    maximumTaskCount: 8,
    justCompletedRetentionMinutes: 0
)
try expect(
    invalid.justCompletedRetentionMinutes == DisplaySettings.defaultJustCompletedRetentionMinutes,
    "invalid retention should fall back to one minute"
)
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `swift run ThreadBeaconTests`

Expected: 编译失败，提示 `justCompletedRetentionMinutes` 参数或属性不存在。

- [ ] **Step 3: 实现最小配置模型**

在 `DisplaySettings` 增加：

```swift
public static let supportedJustCompletedRetentionMinutes = [1, 2, 3, 4, 5]
public static let defaultJustCompletedRetentionMinutes = 1
public let justCompletedRetentionMinutes: Int
```

构造器验证合法值；在 `DisplayPreferenceKeys` 增加
`justCompletedRetentionMinutes = "displayJustCompletedRetentionMinutes"`，Repository 的 `load()` 和
`save(_:)` 读写该键。缺失键得到 `0`，再由模型回退为一分钟。

- [ ] **Step 4: 运行测试并确认通过**

Run: `swift run ThreadBeaconTests`

Expected: 所有测试通过。

### Task 2: 让加载请求携带动态保留时间

**Files:**

- Modify: `Sources/ThreadBeaconCore/Stores/ThreadStatusStore.swift`
- Modify: `Sources/ThreadBeaconCore/Services/ThreadStatusLoader.swift`
- Modify: `Sources/ThreadBeacon/App/ThreadBeaconApp.swift`
- Test: `Tests/ThreadBeaconTests/ThreadStatusStoreTests.swift`
- Test: `Tests/ThreadBeaconTests/ThreadStatusLoaderTests.swift`

- [ ] **Step 1: 编写失败测试**

为 `ThreadLoadRequest` 和 Store 增加断言，确认默认一分钟、更新为五分钟后下一次请求携带 `300` 秒；
Loader 增加 `completedRetention: 300` 的边界测试，确认两分钟前完成的主任务和 Subagent 仍为
`.justCompleted`。

```swift
try expect(request.completedRetentionSeconds == 300, "request should carry five minutes")
try expect(snapshot.status == .justCompleted, "five-minute retention should keep recent completion")
try expect(snapshot.subagents.first?.status == .justCompleted, "subagent should share retention")
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `swift run ThreadBeaconTests`

Expected: 编译失败，提示请求字段、Store 更新方法或 Loader 参数不存在。

- [ ] **Step 3: 实现动态数据流**

给 `ThreadLoadRequest` 增加 `completedRetentionSeconds: TimeInterval`。`ThreadStatusStore` 构造器接收
`justCompletedRetentionMinutes`，内部规范化为 `1～5`，并提供：

```swift
public func updateJustCompletedRetention(minutes: Int) {
    let normalized = DisplaySettings(
        refreshIntervalSeconds: DisplaySettings.defaultRefreshIntervalSeconds,
        maximumTaskCount: DisplaySettings.defaultMaximumTaskCount,
        justCompletedRetentionMinutes: minutes
    ).justCompletedRetentionMinutes
    completedRetentionSeconds = TimeInterval(normalized * 60)
}
```

`loadRequest()` 写入秒数。`ThreadStatusLoader.loadResult(...)` 增加
`completedRetention: TimeInterval? = nil`，本次加载使用覆盖值或构造器默认值，并把同一值传给主任务和
Subagent 的 `displayState`。`ThreadBeaconApp` 从请求读取该秒数传给 Loader。

- [ ] **Step 4: 运行测试并确认通过**

Run: `swift run ThreadBeaconTests`

Expected: 所有测试通过，原有默认 60 秒行为不变。

### Task 3: 增加 Settings Picker 和即时基线刷新

**Files:**

- Modify: `Sources/ThreadBeacon/Views/ThreadBeaconSettingsView.swift`
- Modify: `Sources/ThreadBeacon/Views/ContentView.swift`
- Modify: `Resources/Localizable.xcstrings`

- [ ] **Step 1: 接入设置控件**

在 `GeneralSettingsView` 增加对应 `@AppStorage`，并在“任务监听”Section 加入：

```swift
Picker("刚完成保留时间", selection: $justCompletedRetentionMinutes) {
    ForEach(DisplaySettings.supportedJustCompletedRetentionMinutes, id: \.self) { minutes in
        Text(AppLocalization.formatted("%lld 分钟", locale: locale, minutes)).tag(minutes)
    }
}
```

在 `Localizable.xcstrings` 增加英文 `Just completed retention` 和 `%lld min`。

- [ ] **Step 2: 接入即时刷新**

`ContentView` 增加相同 `@AppStorage`，在值变化时规范化设置、调用
`store.updateJustCompletedRetention(minutes:)`，随后：

```swift
Task { await store.refresh(notificationPolicy: .baseline) }
```

App 启动构造 Store 时传入持久化配置，保证首次加载即采用用户设置。

- [ ] **Step 3: 编译验证**

Run: `swift build -c release`

Expected: Release 构建成功，无缺失本地化资源或 Swift 并发错误。

### Task 4: 同步公开文档并做完整回归

**Files:**

- Modify: `README.md`
- Modify: `README-EN.md`
- Modify: `ROADMAP.md`
- Modify: `docs/just-completed-retention-design.md`

- [ ] **Step 1: 更新文档**

把固定“60 秒”改为默认一分钟且可在 Settings 选择 `1～5 分钟`；设计文档状态标记为已实现，Roadmap
记录功能完成，不改变其他状态说明。

- [ ] **Step 2: 完整验证**

Run:

```bash
swift run ThreadBeaconTests
swift build -c release
git diff --check
```

Expected: 所有测试通过、Release 构建成功、无空白错误。

- [ ] **Step 3: 检查工作树**

Run: `git status --short && git diff --stat`

Expected: 只包含本计划列出的实现、测试和文档文件；不包含构建产物或其他会话文件。
