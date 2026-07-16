# Token 消耗概览实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox
> (`- [ ]`) syntax for tracking.

**Goal:** 在 ThreadBeacon 主任务行显示紧凑 Token 总量，并通过支持悬浮和点击保持的
popover 展示会话累计与当前 turn 明细。

**Architecture:** SQLite 提供稳定累计总量，rollout 尾部的累计 `token_count` 提供明细
与当前 turn 差分。Core 层用独立值类型承载数据和格式化规则；SwiftUI 行视图只负责
紧凑总量与 popover 交互，不参与 Token 计算。

**Tech Stack:** Swift 6.1、SwiftUI、AppKit、SQLite、SwiftPM、自定义轻量测试运行器。

---

## 文件结构

- Create: `Sources/ThreadBeaconCore/Models/TokenUsage.swift`
  - 定义累计、当前 turn 和回退总量的数据契约。
- Modify: `Sources/ThreadBeaconCore/Models/RolloutObservation.swift`
  - 携带 rollout 解析出的可选 Token 快照。
- Modify: `Sources/ThreadBeaconCore/Models/ThreadModels.swift`
  - 将 SQLite 总量传入 loader，并将最终快照传给 UI。
- Modify: `Sources/ThreadBeaconCore/Services/RolloutTailParser.swift`
  - 解析累计 Token 事件并用累计值差分当前 turn。
- Modify: `Sources/ThreadBeaconCore/Services/SQLiteThreadRepository.swift`
  - 读取 `threads.tokens_used`。
- Modify: `Sources/ThreadBeaconCore/Services/ThreadStatusLoader.swift`
  - 合并 rollout 明细和 SQLite 总量回退。
- Create: `Sources/ThreadBeaconCore/Support/TokenCountFormatter.swift`
  - 统一 `K`、`M` 和百分比格式。
- Create: `Sources/ThreadBeacon/Views/TokenDetailPopoverView.swift`
  - 展示完整 Token 指标。
- Create: `Sources/ThreadBeacon/Views/TokenInfoButton.swift`
  - 管理 300 毫秒悬浮和点击保持交互。
- Modify: `Sources/ThreadBeacon/Views/ThreadRowView.swift`
  - 添加紧凑总量和 info 入口。
- Modify: `Tests/ThreadBeaconTests/TestRunner.swift`
  - 注册新增 formatter 测试。

### Task 1: Token 模型与 rollout 累计差分

**Files:**

- Create: `Sources/ThreadBeaconCore/Models/TokenUsage.swift`
- Modify: `Sources/ThreadBeaconCore/Models/RolloutObservation.swift`
- Modify: `Sources/ThreadBeaconCore/Services/RolloutTailParser.swift`
- Modify: `Tests/ThreadBeaconTests/RolloutTailParserTests.swift`

- [ ] **Step 1: 写入完整累计值和当前 turn 差分的失败测试**

在 `rolloutTailParserTests` 中增加两条测试。事件只包含数字字段，不包含正文：

```swift
TestCase(name: "token events expose cumulative usage and current turn delta") {
    let lines = [
        tokenEvent(timestamp: "2026-07-16T01:00:00Z", input: 900, cached: 400,
                   output: 100, reasoning: 30, total: 1_000),
        #"{"timestamp":"2026-07-16T01:01:00Z","type":"event_msg","payload":{"type":"task_started"}}"#,
        tokenEvent(timestamp: "2026-07-16T01:02:00Z", input: 1_350, cached: 650,
                   output: 150, reasoning: 40, total: 1_500)
    ]

    let result = RolloutTailParser().parse(lines: lines)

    try expect(result.tokenUsage?.totalTokens == 1_500, "latest cumulative total should be retained")
    try expect(result.tokenUsage?.currentTurn?.inputTokens == 450, "turn input should use cumulative delta")
    try expect(result.tokenUsage?.currentTurn?.cachedInputTokens == 250, "turn cache should use cumulative delta")
    try expect(result.tokenUsage?.currentTurn?.outputTokens == 50, "turn output should use cumulative delta")
}
```

```swift
TestCase(name: "token delta is absent without a reliable baseline") {
    let lines = [
        #"{"timestamp":"2026-07-16T01:01:00Z","type":"event_msg","payload":{"type":"task_started"}}"#,
        tokenEvent(timestamp: "2026-07-16T01:02:00Z", input: 1_350, cached: 650,
                   output: 150, reasoning: 40, total: 1_500)
    ]

    let result = RolloutTailParser().parse(lines: lines)

    try expect(result.tokenUsage?.totalTokens == 1_500, "cumulative total should still be available")
    try expect(result.tokenUsage?.currentTurn == nil, "missing baseline must not invent a turn total")
}
```

文件末尾增加生成完整事件的私有 helper：

```swift
private func tokenEvent(
    timestamp: String,
    input: Int64,
    cached: Int64,
    output: Int64,
    reasoning: Int64,
    total: Int64
) -> String {
    """
    {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output),"reasoning_output_tokens":\(reasoning),"total_tokens":\(total)}}}}
    """
}
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `./script/test.sh`

Expected: 编译失败，指出 `RolloutObservation` 没有 `tokenUsage`。

- [ ] **Step 3: 添加最小 Token 值类型**

创建 `TokenUsage.swift`：

```swift
import Foundation

public struct TokenUsage: Equatable, Sendable {
    public let inputTokens: Int64
    public let cachedInputTokens: Int64
    public let outputTokens: Int64
    public let reasoningOutputTokens: Int64
    public let totalTokens: Int64

    public var uncachedInputTokens: Int64 { inputTokens - cachedInputTokens }
    public var cacheRatio: Double? {
        inputTokens > 0 ? Double(cachedInputTokens) / Double(inputTokens) : nil
    }

    public func subtracting(_ baseline: TokenUsage) -> TokenUsage? {
        let values = (
            inputTokens - baseline.inputTokens,
            cachedInputTokens - baseline.cachedInputTokens,
            outputTokens - baseline.outputTokens,
            reasoningOutputTokens - baseline.reasoningOutputTokens,
            totalTokens - baseline.totalTokens
        )
        guard values.0 >= 0, values.1 >= 0, values.2 >= 0, values.3 >= 0, values.4 >= 0 else {
            return nil
        }
        return TokenUsage(
            inputTokens: values.0,
            cachedInputTokens: values.1,
            outputTokens: values.2,
            reasoningOutputTokens: values.3,
            totalTokens: values.4
        )
    }
}

public struct TokenUsageSnapshot: Equatable, Sendable {
    public let totalTokens: Int64
    public let cumulative: TokenUsage?
    public let currentTurn: TokenUsage?
    public let updatedAt: Date?
}
```

为两个结构补充逐字段 public initializer。给 `RolloutObservation` 增加
`public var tokenUsage: TokenUsageSnapshot?`，并在 initializer 提供默认值 `nil`。

- [ ] **Step 4: 在 parser 中只解析累计字段**

在 `parse(lines:)` 中维护：

```swift
var latestTokenUsage: TokenUsage?
var latestTokenEventAt: Date?
var currentTurnBaseline: TokenUsage?
```

当事件为 `event_msg/task_started` 时执行：

```swift
currentTurnBaseline = latestTokenUsage
```

当事件为 `event_msg/token_count` 时，从
`payload.info.total_token_usage` 读取五个非负 `Int64` 字段；字段不完整时忽略该事件。
最后构造：

```swift
let tokenSnapshot = latestTokenUsage.map { usage in
    TokenUsageSnapshot(
        totalTokens: usage.totalTokens,
        cumulative: usage,
        currentTurn: currentTurnBaseline.flatMap(usage.subtracting),
        updatedAt: latestTokenEventAt
    )
}
```

`RolloutObservation` 返回原状态字段和 `tokenUsage: tokenSnapshot`。不得读取
`last_token_usage`、message content 或 reasoning summary。

- [ ] **Step 5: 补充重复累计和倒退差分测试**

增加测试：重复累计事件只保留最后累计；当前累计任一字段小于基线时
`currentTurn == nil`。运行 `./script/test.sh`，Expected: 全部测试 PASS。

- [ ] **Step 6: 提交 parser checkpoint**

```bash
git add Sources/ThreadBeaconCore/Models/TokenUsage.swift \
  Sources/ThreadBeaconCore/Models/RolloutObservation.swift \
  Sources/ThreadBeaconCore/Services/RolloutTailParser.swift \
  Tests/ThreadBeaconTests/RolloutTailParserTests.swift
git diff --cached --check
git commit -m "feat(token): parse cumulative rollout usage"
```

### Task 2: SQLite 总量和 loader 回退

**Files:**

- Modify: `Sources/ThreadBeaconCore/Models/ThreadModels.swift`
- Modify: `Sources/ThreadBeaconCore/Services/SQLiteThreadRepository.swift`
- Modify: `Sources/ThreadBeaconCore/Services/ThreadStatusLoader.swift`
- Modify: `Tests/ThreadBeaconTests/SQLiteThreadRepositoryTests.swift`
- Modify: `Tests/ThreadBeaconTests/ThreadStatusLoaderTests.swift`

- [ ] **Step 1: 写入 SQLite `tokens_used` 的失败测试**

给测试数据库 schema 增加 `tokens_used INTEGER NOT NULL DEFAULT 0`，为
`new-thread` 写入 `70808875`，并断言：

```swift
try expect(records.first?.tokensUsed == 70_808_875, "repository should retain token total")
```

Run: `./script/test.sh`

Expected: 编译失败，指出 `ThreadRecord` 没有 `tokensUsed`。

- [ ] **Step 2: 添加模型字段并读取 SQLite**

给 `ThreadRecord` 增加 `tokensUsed: Int64`，initializer 默认值设为 `0`，避免破坏现有
测试 fixture。SQL 改为：

```sql
SELECT id, title, rollout_path,
       COALESCE(updated_at_ms, updated_at * 1000),
       tokens_used
```

从 column 4 读取 `sqlite3_column_int64` 并传入 record。

- [ ] **Step 3: 写入 loader 明细优先和 SQLite 回退的失败测试**

增加两条测试：

```swift
try expect(snapshots.first?.tokenUsage?.cumulative?.outputTokens == 200,
           "loader should retain rollout token details")
```

```swift
let snapshot = snapshots.first
try expect(snapshot?.tokenUsage?.totalTokens == 42_000,
           "SQLite total should remain available when rollout details are missing")
try expect(snapshot?.tokenUsage?.cumulative == nil,
           "fallback total must not invent breakdown fields")
```

Run: `./script/test.sh`

Expected: 编译失败，指出 `ThreadSnapshot` 没有 `tokenUsage`。

- [ ] **Step 4: 在 loader 合并数据**

给 `ThreadSnapshot` 增加 `tokenUsage: TokenUsageSnapshot?`，initializer 默认 `nil`。
loader 使用：

```swift
let tokenUsage = observation.tokenUsage ?? (record.tokensUsed > 0
    ? TokenUsageSnapshot(
        totalTokens: record.tokensUsed,
        cumulative: nil,
        currentTurn: nil,
        updatedAt: nil
    )
    : nil)
```

将其传给 `ThreadSnapshot`。Run: `./script/test.sh`，Expected: 全部测试 PASS。

- [ ] **Step 5: 提交数据管线 checkpoint**

```bash
git add Sources/ThreadBeaconCore/Models/ThreadModels.swift \
  Sources/ThreadBeaconCore/Services/SQLiteThreadRepository.swift \
  Sources/ThreadBeaconCore/Services/ThreadStatusLoader.swift \
  Tests/ThreadBeaconTests/SQLiteThreadRepositoryTests.swift \
  Tests/ThreadBeaconTests/ThreadStatusLoaderTests.swift
git diff --cached --check
git commit -m "feat(token): carry usage into task snapshots"
```

### Task 3: Token 数字格式

**Files:**

- Create: `Sources/ThreadBeaconCore/Support/TokenCountFormatter.swift`
- Create: `Tests/ThreadBeaconTests/TokenCountFormatterTests.swift`
- Modify: `Tests/ThreadBeaconTests/TestRunner.swift`

- [ ] **Step 1: 写入失败测试并注册**

```swift
import ThreadBeaconCore

let tokenCountFormatterTests = [
    TestCase(name: "token counts use compact deterministic units") {
        try expect(TokenCountFormatter.string(for: 999) == "999", "small values should stay exact")
        try expect(TokenCountFormatter.string(for: 1_200) == "1.2K", "thousands should use K")
        try expect(TokenCountFormatter.string(for: 70_808_875) == "70.8M", "millions should use M")
    },
    TestCase(name: "token cache ratio uses one decimal percent") {
        try expect(TokenCountFormatter.percent(0.931432) == "93.1%", "ratio should use one decimal")
    }
]
```

将 `tokenCountFormatterTests` 加入 `TestRunner`。Run: `./script/test.sh`。

Expected: 编译失败，指出 `TokenCountFormatter` 不存在。

- [ ] **Step 2: 实现确定性 formatter**

创建无共享可变状态的 `TokenCountFormatter`：小于 `1_000` 原样显示，千和百万保留
一位小数并去掉 `.0`，百分比固定一位。使用 `Locale(identifier: "en_US_POSIX")`
确保测试不受系统语言影响。

- [ ] **Step 3: 运行测试并提交**

Run: `./script/test.sh`

Expected: 全部测试 PASS。

```bash
git add Sources/ThreadBeaconCore/Support/TokenCountFormatter.swift \
  Tests/ThreadBeaconTests/TokenCountFormatterTests.swift \
  Tests/ThreadBeaconTests/TestRunner.swift
git diff --cached --check
git commit -m "feat(token): format compact usage values"
```

### Task 4: 紧凑行和 Token popover

**Files:**

- Create: `Sources/ThreadBeacon/Views/TokenDetailPopoverView.swift`
- Create: `Sources/ThreadBeacon/Views/TokenInfoButton.swift`
- Modify: `Sources/ThreadBeacon/Views/ThreadRowView.swift`

- [ ] **Step 1: 创建详情视图**

`TokenDetailPopoverView` 接收 `TokenUsageSnapshot`，用两列 `Grid` 展示设计文档中的
八项指标和更新时间。累计明细或当前 turn 缺失时显示 `—`。底部加入说明：

```swift
Text("缓存输入已包含在输入中；Reasoning 已包含在输出中。")
    .font(.caption2)
    .foregroundStyle(.tertiary)
```

popover 宽度固定在约 260 点，数字使用 `.monospacedDigit()`。

- [ ] **Step 2: 创建支持悬浮和点击保持的 info 入口**

`TokenInfoButton` 使用三个 view-local 状态：

```swift
@State private var isHoverPresented = false
@State private var isPinned = false
@State private var hoverTask: Task<Void, Never>?
```

`onHover(true)` 启动 300 毫秒延迟任务；`onHover(false)` 取消任务，并在未点击保持时
关闭。Button 点击切换 `isPinned`。popover 的 Binding 在系统外部关闭时同时清理两个
状态。添加 `.help("查看 Token 详情")` 和同名 accessibility label。

- [ ] **Step 3: 将总量和 info 接入任务行**

在标题行右侧、现有 `VStack` 内增加：

```swift
if let tokenUsage = snapshot.tokenUsage {
    Text(TokenCountFormatter.string(for: tokenUsage.totalTokens))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    TokenInfoButton(snapshot: tokenUsage)
}
```

保持标题 `.lineLimit(1)`，Token 区域不换行；没有 Token 数据时布局与当前版本一致。

- [ ] **Step 4: 构建并修复 Swift 6 / SwiftUI 诊断**

Run: `./script/swiftpm.sh build`

Expected: `Build complete!`，没有 error。

- [ ] **Step 5: 提交 UI checkpoint**

```bash
git add Sources/ThreadBeacon/Views/TokenDetailPopoverView.swift \
  Sources/ThreadBeacon/Views/TokenInfoButton.swift \
  Sources/ThreadBeacon/Views/ThreadRowView.swift
git diff --cached --check
git commit -m "feat(token): add compact usage popover"
```

### Task 5: 文档同步和真实数据验收

**Files:**

- Modify: `README.md`
- Modify: `README-EN.md`
- Modify: `ROADMAP.md`

- [ ] **Step 1: 更新用户文档**

README 中补充紧凑 Token 总量、info 详情和只读口径；README-EN 同步英文说明。
ROADMAP 将 Token 条目从“待验证”改为“首版已实现”，保留费用、趋势、subagent 汇总等
后续边界。

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
./script/probe.sh
```

Expected: 所有测试通过；release build 成功；App 进程保持运行；probe 只读输出主任务，
不输出会话正文。

- [ ] **Step 4: 做真实界面验收**

检查：主行仅增加总量和 info；悬浮约 300 毫秒显示；移开关闭；点击后保持；popover
八项指标与只读 rollout 最新累计值一致；没有 Token 的 fixture 不出现空白占位。

- [ ] **Step 5: 提交文档并做最终工作树检查**

```bash
git add README.md README-EN.md ROADMAP.md
git diff --cached --check
git commit -m "docs(token): document usage overview"
git status --short --branch
```

Expected: 工作树干净，分支只包含本功能的计划、实现、测试和文档提交。
