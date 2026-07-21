# 双击打开 Codex 任务 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 允许用户双击未归档主任务，通过现有受保护的 Accessibility 链路在 Codex App 中打开准确任务，并获得本地化失败反馈。

**Architecture:** `ThreadBeaconCore` 新增纯值打开策略和共享结果文案键，App 层的 `AccessibilityPermissionStore` 负责串行化用户主动打开操作并调用现有 `SystemAccessibilityTargetSelector`。`ContentView` 绑定双击和 Alert，`ThreadRowView` 只提供事件入口与可访问性提示，不承担 AppKit 逻辑。

**Tech Stack:** Swift 6.1、SwiftUI、AppKit Accessibility、Apple String Catalog、现有自定义 Swift 测试运行器。

---

## 文件结构

- `Sources/ThreadBeaconCore/Models/TaskOpenPolicy.swift`：纯值判断主任务能否发起打开，并定义操作结果。
- `Sources/ThreadBeacon/Support/AccessibilityTargetSelectionPresentation.swift`：共享选择失败的本地化展示。
- `Sources/ThreadBeacon/Support/AccessibilityPermissionStore.swift`：执行并串行化发布版任务打开。
- `Sources/ThreadBeacon/Views/ContentView.swift`：发起打开、展示失败 Alert 和设置入口。
- `Sources/ThreadBeacon/Views/ThreadRowView.swift`：接收双击回调和是否可打开状态。
- `Sources/ThreadBeacon/App/ThreadBeaconApp.swift`：向主窗口注入共享 Accessibility store。
- `Resources/Localizable.xcstrings`：增加中英文 Tooltip、Alert 和权限反馈。
- `Tests/ThreadBeaconTests/TaskOpenPolicyTests.swift`：覆盖归档、授权和并发决策。
- `Tests/ThreadBeaconTests/TestRunner.swift`：注册新增测试。
- `ROADMAP.md`、`CHANGELOG.md`：同步实现状态和未发布变更。

### Task 1：Core 打开策略与结果模型

**Files:**

- Create: `Sources/ThreadBeaconCore/Models/TaskOpenPolicy.swift`
- Create: `Tests/ThreadBeaconTests/TaskOpenPolicyTests.swift`
- Modify: `Tests/ThreadBeaconTests/TestRunner.swift`

- [ ] **Step 1：先写失败测试**

新增测试，断言活跃且已授权的任务允许打开，归档任务、未授权和并发操作分别返回稳定决策；
同时断言 `TaskOpenResult.opened` 是成功结果，其他结果都不是成功。

- [ ] **Step 2：运行测试确认 RED**

Run: `./script/test.sh`

Expected: 编译失败，提示找不到 `TaskOpenRequestPolicy` 或 `TaskOpenResult`。

- [ ] **Step 3：实现最小 Core 逻辑**

新增纯值模型：

```swift
public enum TaskOpenRequestDecision: Equatable, Sendable {
    case allowed
    case archived
    case notAuthorized
    case interactionInProgress
}

public enum TaskOpenRequestPolicy {
    public static func evaluate(
        isArchived: Bool,
        isAuthorized: Bool,
        isInteractionInProgress: Bool
    ) -> TaskOpenRequestDecision {
        if isArchived { return .archived }
        if !isAuthorized { return .notAuthorized }
        if isInteractionInProgress { return .interactionInProgress }
        return .allowed
    }
}

public enum TaskOpenResult: Equatable, Sendable {
    case opened
    case archived
    case notAuthorized
    case interactionInProgress
    case selectionFailed(AccessibilityTargetSelectionResult)

    public var isOpened: Bool { self == .opened }
}
```

- [ ] **Step 4：运行测试确认 GREEN**

Run: `./script/test.sh`

Expected: 全部测试通过。

- [ ] **Step 5：提交 Core 策略**

```bash
git add Sources/ThreadBeaconCore/Models/TaskOpenPolicy.swift \
  Tests/ThreadBeaconTests/TaskOpenPolicyTests.swift Tests/ThreadBeaconTests/TestRunner.swift
git commit -m "feat(tasks): define guarded task opening policy"
```

### Task 2：发布版打开操作编排

**Files:**

- Modify: `Sources/ThreadBeacon/Support/AccessibilityPermissionStore.swift`
- Create: `Sources/ThreadBeacon/Support/AccessibilityTargetSelectionPresentation.swift`

- [ ] **Step 1：先写失败测试**

在 Store 调用点先引用尚不存在的 `openTask(threadID:isArchived:)` 和 `taskOpenResult`，确认 App
目标因缺少接口而不能编译。

- [ ] **Step 2：运行测试确认 RED**

Run: `./script/test.sh`

Expected: 编译失败，提示 `AccessibilityPermissionStore` 没有 `openTask` 或 `taskOpenResult`。

- [ ] **Step 3：实现请求决策和 Store 入口**

在 `AccessibilityPermissionStore` 增加发布版 `openTask(threadID:)`：刷新授权、执行请求策略、
设置 `isChecking`、调用 `SystemAccessibilityTargetSelector.select`、保存 `TaskOpenResult` 并在结束后
释放锁。成功结果不触发发送资格，不复用 Debug 的 `selectedTargetThreadID`。

新增 `AccessibilityTargetSelectionPresentation`，把现有 Debug `targetSelectionText` 的完整 switch
迁移为共享方法；Debug 设置页和主窗口使用同一个错误映射。

- [ ] **Step 4：运行测试确认 GREEN**

Run: `./script/test.sh`

Expected: 全部测试通过。

- [ ] **Step 5：提交打开编排**

```bash
git add Sources/ThreadBeacon/Support/AccessibilityPermissionStore.swift \
  Sources/ThreadBeacon/Support/AccessibilityTargetSelectionPresentation.swift \
  Sources/ThreadBeacon/Views/ThreadBeaconSettingsView.swift
git commit -m "feat(tasks): coordinate safe Codex task opening"
```

### Task 3：主列表双击与本地化反馈

**Files:**

- Modify: `Sources/ThreadBeacon/App/ThreadBeaconApp.swift`
- Modify: `Sources/ThreadBeacon/Views/ContentView.swift`
- Modify: `Sources/ThreadBeacon/Views/ThreadRowView.swift`
- Modify: `Resources/Localizable.xcstrings`

- [ ] **Step 1：先建立编译失败的调用点**

让 `ContentView` 要求 `AccessibilityPermissionStore` 参数，让 `ThreadRowView` 要求
`canOpenInCodex` 与 `openInCodex`；运行测试应因调用方尚未更新而失败。

- [ ] **Step 2：运行测试确认 RED**

Run: `./script/test.sh`

Expected: 编译失败，指出缺少新增初始化参数。

- [ ] **Step 3：接入双击和 Alert**

- `ThreadBeaconApp` 把现有共享 store 注入 `ContentView`。
- `ThreadRowView` 在 `canOpenInCodex` 时使用双击手势调用 `openInCodex`，并加入“双击在 Codex App 中打开”帮助文本。
- `ContentView` 仅对未归档行启用；双击调用 `openTask(threadID:)`。
- 失败结果弹出 Alert；未授权 Alert 提供“打开辅助功能设置”，其他结果只有“好”。
- `.selected` 不显示成功弹窗；归档行和 Subagent 行不绑定打开动作。
- String Catalog 增加所有新文案的英文翻译。

- [ ] **Step 4：运行测试和构建确认 GREEN**

Run: `./script/test.sh`

Expected: 全部测试通过。

Run: `xcodebuild -project ThreadBeacon.xcodeproj -scheme ThreadBeacon -configuration Debug -destination 'platform=macOS' build`

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 5：提交主列表交互**

```bash
git add Sources/ThreadBeacon/App/ThreadBeaconApp.swift Sources/ThreadBeacon/Views/ContentView.swift \
  Sources/ThreadBeacon/Views/ThreadRowView.swift Resources/Localizable.xcstrings
git commit -m "feat(tasks): open Codex tasks on double click"
```

### Task 4：文档、回归与可运行产物验证

**Files:**

- Modify: `ROADMAP.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1：更新实现状态**

将“双击打开 Codex 任务”标为 MVP 已完成，记录未授权、草稿、归档和 Subagent 边界；在
`CHANGELOG.md` 的 `[Unreleased]` 增加该功能。

- [ ] **Step 2：运行文档检查**

Run: `npm run lint:md -- poc/codex-thread-status-macos/docs/double-click-open-task-design.md poc/codex-thread-status-macos/docs/double-click-open-task-implementation-plan.md poc/codex-thread-status-macos/ROADMAP.md poc/codex-thread-status-macos/CHANGELOG.md`

Expected: 0 errors。

- [ ] **Step 3：运行完整验证**

Run: `./script/test.sh`

Expected: 全部测试通过。

Run: `./script/build_and_run.sh --verify`

Expected: App 构建、启动且进程验证通过。本步骤只生成并运行 `dist/ThreadBeacon.app`，不安装到 `/Applications`。

- [ ] **Step 4：检查变更范围**

Run: `git diff --check && git status --short`

Expected: 仅包含本功能计划内文件，无构建产物和无关修改。

- [ ] **Step 5：提交文档状态**

```bash
git add ROADMAP.md CHANGELOG.md docs/double-click-open-task-implementation-plan.md
git commit -m "docs(tasks): record double-click opening MVP"
```
