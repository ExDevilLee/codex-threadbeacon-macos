# Interrupted Task Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 rollout 的明确中断事件转换为 ThreadBeacon 可见、可排序且不会误触发声音或自动恢复的`已中断 / Interrupted`状态。

**Architecture:** `RolloutTailParser` 只提取最近运行、完成和中断边界并按时间归约为状态，不在模型中保留事件 payload。`ThreadDisplayStatus` 承担排序契约，SwiftUI 现有状态灯和状态文本扩展负责自适应展示；声音和自动恢复继续只消费各自已有的完成与服务异常证据。

**Tech Stack:** Swift 6、Swift Package Manager、SwiftUI、Foundation JSON、String Catalog、自定义轻量测试运行器。

---

## Task 1: 锁定 rollout 生命周期契约

**Files:**

- Modify: `Tests/ThreadBeaconTests/RolloutTailParserTests.swift`
- Modify: `Sources/ThreadBeaconCore/Services/RolloutTailParser.swift`

- [x] **Step 1: Write the failing lifecycle tests**

  新增测试覆盖 `task_started -> turn_aborted`、新任务开始清除中断、完成覆盖中断、非法 abort 被忽略，以及解析结果不保存 abort payload 字段。

- [x] **Step 2: Run tests to verify RED**

  Run: `./script/test.sh`

  Expected: 编译或断言因缺少 `ThreadDisplayStatus.interrupted` 与中断解析逻辑而失败。

- [x] **Step 3: Implement the minimum lifecycle reducer**

  在 `RolloutTailParser.parse(lines:)` 中维护最近运行、完成和合法中断时间：

  ```swift
  let latestRunningAt = [latestTurn, latestTaskStartedAt].compactMap { $0 }.max()
  let latestCompletedAt = [latestFinal, latestCompletionEventAt].compactMap { $0 }.max()
  ```

  仅当 `payload.type == "turn_aborted"` 且 `payload.reason == "interrupted"` 时记录中断边界，随后按完成、中断、运行的时间优先级生成状态。

- [x] **Step 4: Run tests to verify GREEN**

  Run: `./script/test.sh`

  Expected: rollout 生命周期测试通过，既有完成和 Token 测试不回归。

## Task 2: 增加状态排序和图标契约

**Files:**

- Modify: `Tests/ThreadBeaconTests/ThreadStatusTests.swift`
- Modify: `Tests/ThreadBeaconTests/StatusIndicatorPresentationTests.swift`
- Modify: `Sources/ThreadBeaconCore/Models/ThreadModels.swift`
- Modify: `Sources/ThreadBeaconCore/Models/StatusIndicatorPresentation.swift`

- [x] **Step 1: Write failing ordering and symbol tests**

  断言 `warning < interrupted < running`，并要求色盲安全符号为 `stop.circle.fill` 且与其他状态不重复。

- [x] **Step 2: Run tests to verify RED**

  Run: `./script/test.sh`

  Expected: 因 `interrupted` 状态或图标映射缺失而失败。

- [x] **Step 3: Implement status and presentation contracts**

  在 `ThreadDisplayStatus` 中增加 `case interrupted`，调整后续排序值；在图标映射中增加：

  ```swift
  case .interrupted:
      "stop.circle.fill"
  ```

- [x] **Step 4: Run tests to verify GREEN**

  Run: `./script/test.sh`

  Expected: 排序与图标测试通过，所有 exhaustive switch 均已处理新状态。

## Task 3: 接入 SwiftUI 文案与自适应视觉

**Files:**

- Modify: `Sources/ThreadBeacon/Views/ThreadRowView.swift`
- Modify: `Resources/Localizable.xcstrings`

- [x] **Step 1: Add the status display mapping**

  在 `displayName` 中映射为`已中断`，在 `color` 中使用 `.secondary`。现有 `StatusDotView` 会自动复用该颜色和 Core 中的色盲安全图标。

- [x] **Step 2: Add English localization**

  在 String Catalog 为`已中断`添加 `Interrupted`，不改变其他语言 fallback。

- [x] **Step 3: Build the app**

  Run: `./script/build_and_run.sh --verify`

  Expected: SwiftUI target 成功编译，String Catalog 可被资源处理。

## Task 4: 验证非触发边界并同步文档

**Files:**

- Modify: `Tests/ThreadBeaconTests/SoundNotificationTests.swift`（仅在现有覆盖不足时）
- Modify: `Tests/ThreadBeaconTests/ThreadStatusStoreTests.swift`（仅在现有覆盖不足时）
- Modify: `ROADMAP.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/attention-and-interruption-state-poc.md`

- [x] **Step 1: Verify sound and recovery inputs remain absent**

  中断 observation 不设置 `completionEventAt` 或 `serviceIncident`；使用现有测试或最小新增测试确认不会生成声音事件或自动恢复候选。

- [x] **Step 2: Update product documentation**

  将 Roadmap 中断状态标为 MVP 已实现、真实 UI 待验证；在 Changelog 的 Unreleased 记录用户可见变更；在 POC 文档记录落地结果。

- [x] **Step 3: Run the complete verification suite**

  Run:

  ```bash
  ./script/test.sh
  ./script/build_and_run.sh --verify
  /Users/songlinli/Downloads/CodexClawProj/node_modules/.bin/markdownlint-cli2 \
    --config /Users/songlinli/Downloads/CodexClawProj/.markdownlint-cli2.jsonc \
    --no-globs \
    ':CHANGELOG.md' \
    ':ROADMAP.md' \
    ':docs/attention-and-interruption-state-poc.md' \
    ':docs/interrupted-task-status-design.md' \
    ':docs/interrupted-task-status-implementation-plan.md' \
    ':Tools/AttentionStateProbe/README.md'
  git diff --check
  ```

  Expected: 全部测试、构建、Markdown lint 和 whitespace 检查通过。

- [x] **Step 4: Leave the work uncommitted**

  本轮只交付可供 Lee 检查的工作树，不安装到 `/Applications`，不创建 commit、tag 或 push。
