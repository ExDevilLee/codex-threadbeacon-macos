# 暂停与恢复监听实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox
> (`- [ ]`) syntax for tracking.

**Goal:** 在 ThreadBeacon 标题栏增加全局暂停/恢复监听控制，暂停每两秒自动刷新，同时
保留手动刷新并提供明确 Footer 状态。

**Architecture:** Core 层用小型 `MonitoringMode` 值类型锁定 active/paused 语义；
`ContentView` 使用 view-local `@State` 驱动 `.task(id:)` 生命周期、标题栏图标和 Footer。
暂停状态不持久化，不进入 store，也不改变现有只读数据管线。

**Tech Stack:** Swift 6.1、SwiftUI、SwiftPM、自定义轻量测试运行器。

---

## Task 1: 可测试的监听模式

**Files:**

- Create: `Sources/ThreadBeaconCore/Models/MonitoringMode.swift`
- Create: `Tests/ThreadBeaconTests/MonitoringModeTests.swift`
- Modify: `Tests/ThreadBeaconTests/TestRunner.swift`

- [ ] **Step 1: 写入模式切换的失败测试**

```swift
import ThreadBeaconCore

let monitoringModeTests = [
    TestCase(name: "monitoring mode toggles automatic refresh") {
        var mode = MonitoringMode.active
        try expect(mode.shouldAutoRefresh, "active mode should refresh automatically")

        mode.toggle()
        try expect(mode == .paused, "first toggle should pause monitoring")
        try expect(!mode.shouldAutoRefresh, "paused mode must stop automatic refresh")

        mode.toggle()
        try expect(mode == .active, "second toggle should resume monitoring")
    }
]
```

将 `monitoringModeTests` 注册到 `TestRunner`。

- [ ] **Step 2: 运行测试并确认 RED**

Run: `./script/test.sh`

Expected: 编译失败，指出 `MonitoringMode` 不存在。

- [ ] **Step 3: 实现最小值类型**

```swift
public enum MonitoringMode: Equatable, Sendable {
    case active
    case paused

    public var shouldAutoRefresh: Bool { self == .active }

    public mutating func toggle() {
        self = self == .active ? .paused : .active
    }
}
```

- [ ] **Step 4: 验证 GREEN 并提交**

Run: `./script/test.sh`

Expected: 26/26 tests passed。

```bash
git add Sources/ThreadBeaconCore/Models/MonitoringMode.swift \
  Tests/ThreadBeaconTests/MonitoringModeTests.swift \
  Tests/ThreadBeaconTests/TestRunner.swift
git diff --cached --check
git commit -m "feat(monitoring): model pause and resume state"
```

## Task 2: 标题栏控制与刷新生命周期

**Files:**

- Modify: `Sources/ThreadBeacon/Views/ContentView.swift`

- [ ] **Step 1: 添加非持久化 view-local 状态**

在 `ContentView` 中增加：

```swift
@State private var monitoringMode = MonitoringMode.active
```

不得使用 `@AppStorage`，保证 App 重启后恢复 active。

- [ ] **Step 2: 让自动任务响应暂停状态**

将现有 `.task` 改为：

```swift
.task(id: monitoringMode) {
    guard monitoringMode.shouldAutoRefresh else { return }
    while !Task.isCancelled {
        await store.refresh()
        do {
            try await Task.sleep(for: .seconds(2))
        } catch {
            return
        }
    }
}
```

恢复时新 task 会立即调用一次 `refresh()`，然后进入两秒循环。

- [ ] **Step 3: 在图钉和刷新之间增加控制按钮**

```swift
Button {
    monitoringMode.toggle()
} label: {
    Image(systemName: monitoringMode == .active ? "pause.fill" : "play.fill")
        .foregroundStyle(monitoringMode == .paused ? Color.accentColor : Color.secondary)
        .frame(width: 18, height: 18)
}
.buttonStyle(.borderless)
.help(monitoringMode == .active ? "暂停监听" : "恢复监听")
.accessibilityLabel(monitoringMode == .active ? "暂停监听" : "恢复监听")
```

手动刷新按钮不增加暂停条件，仍只在 `store.isRefreshing` 时 disabled。

- [ ] **Step 4: 添加暂停 Footer**

错误信息保持最高优先级。没有错误且 mode 为 paused 时显示
`pause.circle.fill` 和：

```swift
if let refreshedAt = store.lastRefreshedAt {
    Text("监听已暂停 · 上次更新 \(refreshedAt.formatted(date: .omitted, time: .standard))")
} else {
    Text("监听已暂停 · 尚未更新")
}
```

active 时保持现有刷新、成功和初次加载分支。

- [ ] **Step 5: 构建并提交 UI checkpoint**

Run: `./script/swiftpm.sh build`

Expected: `Build complete!`，无 Swift 6 诊断。

```bash
git add Sources/ThreadBeacon/Views/ContentView.swift
git diff --cached --check
git commit -m "feat(monitoring): add pause and resume control"
```

## Task 3: 文档与真实计时验收

**Files:**

- Modify: `README.md`
- Modify: `README-EN.md`
- Modify: `ROADMAP.md`

- [ ] **Step 1: 同步用户文档**

README 中说明标题栏暂停/恢复、暂停期间手动刷新可用、重启后恢复监听；英文 README
同步。ROADMAP 将暂停/恢复监听加入“已完成”。

- [ ] **Step 2: 运行 Markdown lint**

从 `/Users/songlinli/Downloads/CodexClawProj` 运行：

```bash
npm run lint:md -- \
  poc/codex-thread-status-macos/README.md \
  poc/codex-thread-status-macos/README-EN.md \
  poc/codex-thread-status-macos/ROADMAP.md
```

Expected: `Summary: 0 error(s)`。

- [ ] **Step 3: 运行完整自动验证**

```bash
./script/test.sh
./script/swiftpm.sh build -c release
./script/build_and_run.sh --verify
```

Expected: 26/26 tests passed；release build 成功；App 保持运行。

- [ ] **Step 4: 真实 App 计时验收**

1. 记录 Footer 更新时间。
2. 点击暂停并等待至少五秒，确认 Footer 保持“监听已暂停”，更新时间不自动变化。
3. 点击手动刷新，确认时间只前进一次，再等待至少三秒确认不继续变化。
4. 点击恢复，确认立即刷新；继续等待至少三秒确认自动更新时间继续前进。
5. 重启 App，确认按钮显示“暂停监听”，证明默认 active。

- [ ] **Step 5: 提交文档**

```bash
git add README.md README-EN.md ROADMAP.md
git diff --cached --check
git commit -m "docs(monitoring): document pause control"
```
