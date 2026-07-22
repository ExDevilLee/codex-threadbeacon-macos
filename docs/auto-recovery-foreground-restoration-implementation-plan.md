# 自动恢复后恢复原前台 App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 无人值守自动恢复结束后，仅在用户没有主动切换应用时安全恢复操作前的原前台 App。

**Architecture:** `ThreadBeaconCore` 提供基于模式、bundle ID 和 PID 的纯值恢复策略；App 层新增窄 AppKit 会话，负责捕获和激活 `NSRunningApplication`。`AccessibilityPermissionStore` 只在 `.unattended` 调用链外包裹该会话，现有发送器、Debug 操作和双击任务保持不变。

**Tech Stack:** Swift 6.1、AppKit `NSWorkspace` / `NSRunningApplication`、现有自定义 Swift 测试运行器。

---

## 文件结构

- `Sources/ThreadBeaconCore/Models/AccessibilityForegroundRestorationPolicy.swift`：纯值进程身份、恢复决策和安全策略。
- `Sources/ThreadBeacon/Services/SystemAccessibilityForegroundSession.swift`：捕获前台状态并按策略恢复 App。
- `Sources/ThreadBeacon/Support/AccessibilityPermissionStore.swift`：只在无人值守发送调用前后使用前台会话。
- `Tests/ThreadBeaconTests/AccessibilityDiagnosticTests.swift`：覆盖允许恢复和所有失败关闭分支。
- `ROADMAP.md`：把“恢复原前台 App”更新为已实现、待实机观察。
- `CHANGELOG.md`：记录未发布的用户可见焦点恢复行为。
- `docs/auto-recovery-settings-design.md`、`docs/accessibility-recovery-poc.md`：同步能力边界。

### Task 1：Core 恢复策略

**Files:**

- Create: `Sources/ThreadBeaconCore/Models/AccessibilityForegroundRestorationPolicy.swift`
- Modify: `Tests/ThreadBeaconTests/AccessibilityDiagnosticTests.swift`

- [x] **Step 1：写失败测试**

增加七组断言：安全无人值守场景返回 `.restore`；第三个 App、用户主动模式、原 App 是 Codex、
原 App 已退出、原 App 缺失，以及相同 bundle ID 但不同 Codex PID 都返回对应跳过决策。

- [x] **Step 2：运行测试确认 RED**

Run: `./script/test.sh`

Expected: 编译失败，提示找不到 `AccessibilityForegroundRestorationPolicy`。

- [x] **Step 3：实现最小纯值策略**

新增 `AccessibilityApplicationIdentity`、`AccessibilityForegroundRestorationDecision` 和
`AccessibilityForegroundRestorationPolicy.evaluate(...)`。策略先拒绝非无人值守模式和无效原 App，
再拒绝原 Codex、已退出及当前前台非目标 Codex，最后返回 `.restore`。

- [x] **Step 4：运行测试确认 GREEN**

Run: `./script/test.sh`

Expected: 全部测试通过。

### Task 2：AppKit 前台会话接入

**Files:**

- Create: `Sources/ThreadBeacon/Services/SystemAccessibilityForegroundSession.swift`
- Modify: `Sources/ThreadBeacon/Support/AccessibilityPermissionStore.swift`

- [x] **Step 1：建立调用点并确认编译失败**

在 `runAutomaticRecovery` 引用尚未实现的 `SystemAccessibilityForegroundSession.capture()` 和
`restoreIfSafe()`；Debug `runRecoverySend` 不增加调用。

- [x] **Step 2：运行测试确认 RED**

Run: `./script/test.sh`

Expected: App 目标编译失败，提示找不到 `SystemAccessibilityForegroundSession`。

- [x] **Step 3：实现 AppKit 窄桥**

捕获原前台和当前 Codex 身份。发送返回后重新读取前台身份并调用 Core 策略；只有 `.restore` 时
按原 PID 重新取得运行中 App，确认未退出后激活。恢复结果不改变
`AccessibilityRecoverySendResult`。

- [x] **Step 4：运行测试和构建确认 GREEN**

Run: `./script/test.sh`

Expected: 全部测试通过。

Run: `xcodebuild -project ThreadBeacon.xcodeproj -scheme ThreadBeacon -configuration Debug -destination 'platform=macOS' build`

Expected: `BUILD SUCCEEDED`。

### Task 3：文档同步与完整验证

**Files:**

- Modify: `ROADMAP.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/auto-recovery-settings-design.md`
- Modify: `docs/accessibility-recovery-poc.md`

- [x] **Step 1：同步实现状态**

记录该能力只作用于无人值守自动恢复，第三个 App 前台时不抢焦点，Debug 和双击任务不恢复焦点；
标记自动测试完成、真实异常场景仍需持续观察。

- [x] **Step 2：运行 Markdown 检查**

Run: `/Users/songlinli/Downloads/CodexClawProj/node_modules/.bin/markdownlint-cli2 --config /Users/songlinli/Downloads/CodexClawProj/.markdownlint-cli2.jsonc --no-globs ':ROADMAP.md' ':docs/auto-recovery-settings-design.md' ':docs/accessibility-recovery-poc.md' ':docs/auto-recovery-foreground-restoration-design.md' ':docs/auto-recovery-foreground-restoration-implementation-plan.md'`

Expected: 0 errors。

- [x] **Step 3：运行完整验证**

Run: `./script/test.sh`

Expected: 全部测试通过。

Run: `./script/build_and_run.sh --verify`

Expected: App 构建、启动且进程验证通过；只生成 `dist/ThreadBeacon.app`，不安装到 `/Applications`。

- [x] **Step 4：检查变更范围**

Run: `git diff --check && git status --short`

Expected: 只包含本功能的 Core、AppKit、测试和文档文件，无安装或发布操作。
