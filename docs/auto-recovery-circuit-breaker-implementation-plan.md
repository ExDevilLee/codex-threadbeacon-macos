# 自动恢复连续失败熔断 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为六种自动恢复异常增加按任务、按类型持久化的可配置连续失败熔断，默认三次并支持不限次数。

**Architecture:** 在 `ThreadBeaconCore` 中扩展版本化规则配置，并新增独立的
`AutoRecoveryCircuitBreakerStore` 保存任务级连续次数。App 层在 Accessibility 操作真正获得执行锁后
登记尝试；`ThreadStatusStore` 将新的完成时间回传给熔断 Store 清零。Settings 只消费结构化配置与
当前熔断状态，不参与业务判断。

**Tech Stack:** Swift 6、SwiftUI、Combine、Foundation Codable、现有 SwiftPM 自定义测试运行器、
Apple String Catalog。

---

## Task 1: 扩展异常规则配置与迁移

**Files:**

- Modify: `Sources/ThreadBeaconCore/Models/AutoRecoverySettings.swift`
- Modify: `Sources/ThreadBeaconCore/Stores/AutoRecoverySettingsStore.swift`
- Test: `Tests/ThreadBeaconTests/AutoRecoverySettingsTests.swift`

- [x] **Step 1: 写入失败测试**

新增断言，要求默认规则包含开启的熔断和 `3` 次上限；v1/v2 JSON 迁移后保留提示词并补齐默认值；
越界次数归一化为 `3`；Store 能独立修改开关和次数。

```swift
try expect(rule.isCircuitBreakerEnabled, "circuit breaker should default on")
try expect(rule.maximumConsecutiveAttempts == 3, "default limit should be three")
store.setCircuitBreakerEnabled(false, for: .http400)
store.setMaximumConsecutiveAttempts(8, for: .http400)
```

- [x] **Step 2: 运行测试并确认 RED**

Run: `./script/test.sh`

Expected: 编译失败，提示 `AutoRecoveryRule` 缺少熔断字段和 Store 更新方法。

- [x] **Step 3: 实现最小配置模型**

`AutoRecoveryRule` 增加默认值与归一化：

```swift
public static let defaultMaximumConsecutiveAttempts = 3
public static let allowedMaximumConsecutiveAttempts = 1...20
public var isCircuitBreakerEnabled: Bool
public var maximumConsecutiveAttempts: Int
```

`AutoRecoverySettings.currentVersion` 递增为 `3`，自定义 Codable 对缺失字段补默认值，所有重建规则的
路径保留新字段。Store 增加两个定向更新方法并立即持久化。

- [x] **Step 4: 运行测试并确认 GREEN**

Run: `./script/test.sh`

Expected: 全部测试通过。

## Task 2: 实现持久化熔断状态

**Files:**

- Create: `Sources/ThreadBeaconCore/Models/AutoRecoveryCircuitBreaker.swift`
- Create: `Sources/ThreadBeaconCore/Stores/AutoRecoveryCircuitBreakerStore.swift`
- Create: `Tests/ThreadBeaconTests/AutoRecoveryCircuitBreakerStoreTests.swift`
- Modify: `Tests/ThreadBeaconTests/TestRunner.swift`

- [x] **Step 1: 写入失败测试**

测试首次登记、同任务同类型累加、任务和类型隔离、重启持久化、完成时间清零、旧完成事件不清零、
单项手动解除以及损坏文件回退。

```swift
let first = store.recordAttempt(candidate: candidate, at: attemptAt)
try expect(first.attemptCount == 1, "first attempt should be recorded")
store.observeCompletion(threadID: candidate.threadID, completedAt: attemptAt.addingTimeInterval(1))
try expect(store.state(for: candidate) == nil, "new completion should reset the task")
```

- [x] **Step 2: 运行测试并确认 RED**

Run: `./script/test.sh`

Expected: 编译失败，提示熔断模型和 Store 不存在。

- [x] **Step 3: 实现模型和原子持久化 Store**

```swift
public struct AutoRecoveryCircuitState: Identifiable, Codable, Equatable, Sendable {
    public let threadID: String
    public let incidentType: AutoRecoveryIncidentType
    public var attemptCount: Int
    public var lastEpisodeID: String
    public var lastAttemptAt: Date
    public var id: String { "\(threadID):\(incidentType.rawValue)" }
}
```

Store 使用 `[AutoRecoveryCircuitState]` 编码到 Application Support，内存用稳定 ID 索引。登记尝试时
立即持久化；完成事件仅删除 `completedAt > lastAttemptAt` 的同任务状态；`reset(threadID:type:)` 只删除
一个键。

- [x] **Step 4: 运行测试并确认 GREEN**

Run: `./script/test.sh`

Expected: 全部测试通过。

## Task 3: 接入策略、发送锁与完成事件

**Files:**

- Modify: `Sources/ThreadBeaconCore/Models/AutoRecoverySettings.swift`
- Modify: `Sources/ThreadBeaconCore/Stores/ThreadStatusStore.swift`
- Modify: `Sources/ThreadBeacon/Support/AccessibilityPermissionStore.swift`
- Modify: `Sources/ThreadBeacon/App/ThreadBeaconApp.swift`
- Test: `Tests/ThreadBeaconTests/AutoRecoverySettingsTests.swift`
- Test: `Tests/ThreadBeaconTests/ThreadStatusStoreTests.swift`

- [x] **Step 1: 写入失败测试**

策略测试要求前三次允许、已有三次时返回熔断、不限模式忽略上限；Store 测试要求每次刷新把全部主任务
的完成时间回调，而不是只处理第一个提示音事件。

```swift
let decision = AutoRecoveryPolicy.evaluate(
    candidate: candidate,
    settings: settings,
    isAccessibilityAuthorized: true,
    consecutiveAttempts: 3
)
try expect(decision == .circuitOpen(prompt: prompt, attemptCount: 3, limit: 3), "fourth attempt should stop")
```

- [x] **Step 2: 运行测试并确认 RED**

Run: `./script/test.sh`

Expected: 编译失败，提示策略签名、熔断决策和完成回调不存在。

- [x] **Step 3: 实现最小链路改动**

`AutoRecoveryDecision` 增加结构化 `circuitOpen`。`ThreadStatusStore` 增加
`onTaskCompletion(threadID:completedAt:)`，每次成功刷新对所有候选快照调用。`runAutomaticRecovery`
增加 `onStart` 闭包，在授权和 `isChecking` 锁通过、设置 `isChecking = true` 后调用，从而只对真正
获得执行资格的尝试计数。

App 初始化独立 Circuit Store：策略读取当前次数；熔断时写熔断日志；允许发送时通过 `onStart`
登记；完成回调交给 Store 清零。

- [x] **Step 4: 运行测试并确认 GREEN**

Run: `./script/test.sh`

Expected: 全部测试通过。

## Task 4: 扩展日志和 Settings UI

**Files:**

- Modify: `Sources/ThreadBeaconCore/Models/AutoRecoveryLog.swift`
- Modify: `Sources/ThreadBeaconCore/Stores/AutoRecoveryLogStore.swift`
- Modify: `Sources/ThreadBeacon/Views/ThreadBeaconSettingsView.swift`
- Modify: `Sources/ThreadBeacon/Views/AutoRecoverySettingsView.swift`
- Modify: `Sources/ThreadBeacon/App/ThreadBeaconApp.swift`
- Modify: `Resources/Localizable.xcstrings`
- Test: `Tests/ThreadBeaconTests/AutoRecoveryLogStoreTests.swift`

- [x] **Step 1: 写入失败测试**

新增日志测试，要求熔断记录持久化为 `.circuitOpen`，包含稳定说明；清空日志后 Circuit Store 状态不受
影响由 Store 测试覆盖。

```swift
let id = store.recordCircuitOpen(
    threadID: "thread-id",
    episodeID: "episode-id",
    incident: "HTTP 429",
    prompt: "continue",
    attemptCount: 3,
    limit: 3
)
try expect(store.entries.first?.status == .circuitOpen, "blocked attempt should be explicit")
```

- [x] **Step 2: 运行测试并确认 RED**

Run: `./script/test.sh`

Expected: 编译失败，提示日志状态和记录方法不存在。

- [x] **Step 3: 实现日志、规则编辑和当前熔断列表**

日志状态增加 `circuitOpen` 并使用 `pause.octagon.fill`。规则展开区在同一行显示 Toggle、次数标签和
`1...20` 数字输入框；数值越界时夹取到边界，空值或非数字恢复上一次有效值。关闭时在同一行显示
无限制说明。存在达到当前规则上限的 Circuit State 时显示“当前熔断”区域，每行提供单项解除按钮。
所有新增用户可见文本写入 String Catalog 的简体中文源字符串和英文翻译。

- [x] **Step 4: 运行测试和构建并确认 GREEN**

Run: `./script/test.sh`

Run: `xcodebuild -project ThreadBeacon.xcodeproj -scheme ThreadBeacon -configuration Debug -destination platform=macOS -derivedDataPath .build/xcode-circuit-breaker CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- build`

Expected: 测试和 Debug App 构建均成功。

## Task 5: 同步文档并完成发布前验证

**Files:**

- Modify: `ROADMAP.md`
- Modify: `docs/auto-recovery-circuit-breaker-design.md`

- [x] **Step 1: 更新实现状态和真实验证边界**

将 ROADMAP 的“更完整连续失败熔断仍待验证”更新为 MVP 已实现，并明确真实异常连续三次、完成清零和
不限模式仍需持续观察。设计文档顶部补实现状态，不把未发生的真实场景写成已验证。

- [x] **Step 2: 运行完整验证**

Run: `./script/test.sh`

Run: `xcodebuild -project ThreadBeacon.xcodeproj -scheme ThreadBeacon -configuration Debug -destination platform=macOS -derivedDataPath .build/xcode-circuit-breaker CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- build`

Run: `npm run lint:md -- poc/codex-thread-status-macos/ROADMAP.md poc/codex-thread-status-macos/docs/auto-recovery-circuit-breaker-design.md poc/codex-thread-status-macos/docs/auto-recovery-circuit-breaker-implementation-plan.md`

Run: `git diff --check`

Expected: 所有命令退出码为 `0`，测试汇总无失败。

- [x] **Step 3: 检查范围**

Run: `git status --short`

Run: `git diff --stat`

Expected: 只包含本计划列出的熔断功能、测试、国际化和文档文件；不提交、不 PUSH，等待 Lee 实机验证。
