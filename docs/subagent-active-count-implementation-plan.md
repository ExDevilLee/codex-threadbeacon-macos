# Subagent Active Count Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将主任务的 Subagent 徽标从历史总数改为实时的“活跃数/总数”，例如 `2/27`。

**Architecture:** Repository 只查询最近 120 秒内更新的直接 Subagent 候选，Loader 使用现有 rollout 状态机确认 `.running` 并在单轮刷新内复用解析结果。Snapshot 保存结构化计数，Formatter 和 SwiftUI Badge 负责紧凑文本、本地化 Tooltip 与无障碍输出。

**Tech Stack:** Swift 6.1、SwiftUI、SQLite C API、Swift Package Manager、现有自定义 Swift 测试运行器。

---

## 文件结构

- `Sources/ThreadBeaconCore/Models/ThreadModels.swift`：新增轻量候选模型和 Snapshot 活跃数量。
- `Sources/ThreadBeaconCore/Services/SQLiteThreadRepository.swift`：按父任务和截止时间查询候选。
- `Sources/ThreadBeaconCore/Services/ThreadStatusLoader.swift`：计算活跃数量并复用 rollout observation。
- `Sources/ThreadBeaconCore/Support/SubagentCountFormatter.swift`：生成 `active/total` 及结构化计数。
- `Sources/ThreadBeacon/Views/SubagentCountBadge.swift`：显示计数并生成本地化说明。
- `Sources/ThreadBeacon/Views/ThreadRowView.swift`：传递 Snapshot 中的两个计数。
- `Resources/Localizable.xcstrings`：增加中英文展开、收起说明。
- `Tests/ThreadBeaconTests/SQLiteThreadRepositoryTests.swift`：覆盖候选过滤、分组与兼容回退。
- `Tests/ThreadBeaconTests/ThreadStatusLoaderTests.swift`：覆盖折叠计数、新鲜度和解析复用。
- `Tests/ThreadBeaconTests/SubagentCountFormatterTests.swift`：覆盖显示格式和非法输入收敛。

## Task 1: 轻量活跃候选查询

**Files:**

- Modify: `Sources/ThreadBeaconCore/Models/ThreadModels.swift`
- Modify: `Sources/ThreadBeaconCore/Services/SQLiteThreadRepository.swift`
- Modify: `Tests/ThreadBeaconTests/SQLiteThreadRepositoryTests.swift`

- [ ] **Step 1: 写候选过滤和兼容回退失败测试**

在测试数据库中把三个直接子任务更新时间固定为 `300`、`310`、`320` 秒，然后增加：

```swift
TestCase(name: "repository loads only fresh subagent activity candidates") {
    let databaseURL = try makeTemporaryThreadDatabase()
    defer { try? FileManager.default.removeItem(at: databaseURL) }

    let recordsByParent = try SQLiteThreadRepository(databaseURL: databaseURL)
        .loadRecentSubagentCandidates(
            parentIDs: ["new-thread"],
            updatedAfter: Date(timeIntervalSince1970: 305)
        )

    try expect(
        recordsByParent["new-thread"]?.map(\.id) == ["archived-child", "legacy-child"],
        "only children at or after the activity cutoff should load"
    )
},
TestCase(name: "repository returns no activity candidates without spawn edges") {
    let databaseURL = try makeTemporaryThreadDatabase(includeSpawnEdges: false)
    defer { try? FileManager.default.removeItem(at: databaseURL) }

    let records = try SQLiteThreadRepository(databaseURL: databaseURL)
        .loadRecentSubagentCandidates(
            parentIDs: ["new-thread"],
            updatedAfter: .distantPast
        )

    try expect(records.isEmpty, "missing relationship table should return no candidates")
}
```

再增加空父任务集合测试，要求直接返回空字典。

- [ ] **Step 2: 运行测试并确认 RED**

运行：`./script/test.sh`

预期：编译失败，提示 `SQLiteThreadRepository` 没有
`loadRecentSubagentCandidates(parentIDs:updatedAfter:)`。

- [ ] **Step 3: 增加候选模型和最小查询实现**

在 `ThreadModels.swift` 增加：

```swift
public struct SubagentActivityCandidate: Identifiable, Equatable, Sendable {
    public let id: String
    public let parentID: String
    public let rolloutPath: String
    public let updatedAt: Date

    public init(id: String, parentID: String, rolloutPath: String, updatedAt: Date) {
        self.id = id
        self.parentID = parentID
        self.rolloutPath = rolloutPath
        self.updatedAt = updatedAt
    }
}
```

在 Repository 增加只读查询。空父任务集合或关系表不存在时返回 `[:]`；其他数据库错误继续
抛出。SQL 只选择活跃计数需要的四个字段：

```sql
SELECT edge.parent_thread_id,
       child.id,
       child.rollout_path,
       COALESCE(child.updated_at_ms, child.updated_at * 1000)
FROM thread_spawn_edges AS edge
JOIN threads AS child ON child.id = edge.child_thread_id
WHERE edge.parent_thread_id IN (?, ...)
  AND COALESCE(child.updated_at_ms, child.updated_at * 1000) >= ?
ORDER BY edge.parent_thread_id,
         COALESCE(child.updated_at_ms, child.updated_at * 1000) DESC,
         child.id DESC
```

截止时间以毫秒绑定，结果按 `parentID` 分组为
`[String: [SubagentActivityCandidate]]`。

- [ ] **Step 4: 运行测试并确认 GREEN**

运行：`./script/test.sh`

预期：新增 Repository 测试和现有完整测试全部通过。

- [ ] **Step 5: 提交候选查询**

```bash
git add Sources/ThreadBeaconCore/Models/ThreadModels.swift \
  Sources/ThreadBeaconCore/Services/SQLiteThreadRepository.swift \
  Tests/ThreadBeaconTests/SQLiteThreadRepositoryTests.swift
git commit -m "feat(subagents): query recent activity candidates"
```

## Task 2: Loader 活跃计数与 observation 复用

**Files:**

- Modify: `Sources/ThreadBeaconCore/Models/ThreadModels.swift`
- Modify: `Sources/ThreadBeaconCore/Services/ThreadStatusLoader.swift`
- Modify: `Tests/ThreadBeaconTests/ThreadStatusLoaderTests.swift`

- [ ] **Step 1: 写折叠状态活跃计数失败测试**

构造总数为 27、两个新鲜 `.running` 候选和一个 `.justCompleted` 候选，不传
`expandedThreadIDs`：

```swift
let loader = ThreadStatusLoader(
    loadRecords: { _ in [ThreadRecord(
        id: "parent",
        title: "Parent",
        rolloutPath: "/tmp/parent",
        updatedAt: now,
        subagentCount: 27
    )] },
    loadActiveSubagentCandidates: { parentIDs, cutoff in
        try expect(parentIDs == ["parent"], "visible parents should request candidates")
        try expect(cutoff == now.addingTimeInterval(-120), "cutoff should match freshness")
        return ["parent": [
            SubagentActivityCandidate(
                id: "running-a", parentID: "parent",
                rolloutPath: "/tmp/running-a", updatedAt: now
            ),
            SubagentActivityCandidate(
                id: "running-b", parentID: "parent",
                rolloutPath: "/tmp/running-b", updatedAt: now
            ),
            SubagentActivityCandidate(
                id: "completed", parentID: "parent",
                rolloutPath: "/tmp/completed", updatedAt: now
            )
        ]]
    },
    observe: { url in
        RolloutObservation(
            status: url.lastPathComponent == "completed" ? .justCompleted : .running,
            statusChangedAt: now,
            latestEventAt: now
        )
    },
    now: { now }
)

let snapshots = try await loader.load(limit: 8)
try expect(snapshots.first?.activeSubagentCount == 2, "two running children should be active")
```

- [ ] **Step 2: 写新鲜度、上限和解析复用失败测试**

增加三项断言：

- observation 虽为 `.running`，但 `latestEventAt` 超过 120 秒时不计入活跃数。
- 已确认 `.running` 数量大于 `subagentCount` 时，Snapshot 分子限制为总数。
- 同一个候选同时出现在展开详情中时，`observe` 对该 rollout 只调用一次。

复用测试使用线程安全计数盒：

```swift
private final class StringIntCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Int] = [:]

    func increment(_ key: String) { lock.withLock { storage[key, default: 0] += 1 } }
    func value(for key: String) -> Int { lock.withLock { storage[key, default: 0] } }
}
```

- [ ] **Step 3: 运行测试并确认 RED**

运行：`./script/test.sh`

预期：编译失败，缺少 `activeSubagentCount` 和
`loadActiveSubagentCandidates` 初始化参数。

- [ ] **Step 4: 实现 Snapshot 字段和 Loader 数据流**

`ThreadSnapshot` 增加默认值为 0 的字段，并在初始化时收敛范围：

```swift
self.subagentCount = max(0, subagentCount)
self.activeSubagentCount = min(
    max(0, activeSubagentCount),
    self.subagentCount
)
```

Loader 增加候选闭包，Repository 初始化器接到 Task 1 的查询：

```swift
loadActiveSubagentCandidates: { parentIDs, updatedAfter in
    try repository.loadRecentSubagentCandidates(
        parentIDs: Array(parentIDs),
        updatedAfter: updatedAfter
    )
}
```

在每轮 `loadResult` 中使用：

```swift
let activityCutoff = currentDate.addingTimeInterval(-runningFreshness)
let candidatesByParent = visibleThreadIDs.isEmpty
    ? [:]
    : try loadActiveSubagentCandidates(visibleThreadIDs, activityCutoff)
```

把 `readObservation` 改为按 rollout 路径缓存；缓存命中不重复增加成功或失败统计：

```swift
var observationsByPath: [String: RolloutObservation] = [:]
func readObservation(at path: String) -> RolloutObservation {
    if let cached = observationsByPath[path] { return cached }
    let observation: RolloutObservation
    do {
        observation = try observe(URL(fileURLWithPath: path))
        rolloutSuccessCount += 1
    } catch {
        observation = RolloutObservation()
        rolloutFailureCount += 1
    }
    observationsByPath[path] = observation
    return observation
}
```

对每个父任务候选调用现有 `displayState`，只统计 `.running`，再传入 Snapshot。

- [ ] **Step 5: 运行测试并确认 GREEN**

运行：`./script/test.sh`

预期：折叠计数、新鲜度、计数上限、解析复用及既有展开排序测试全部通过。

- [ ] **Step 6: 提交 Loader 计数**

```bash
git add Sources/ThreadBeaconCore/Models/ThreadModels.swift \
  Sources/ThreadBeaconCore/Services/ThreadStatusLoader.swift \
  Tests/ThreadBeaconTests/ThreadStatusLoaderTests.swift
git commit -m "feat(subagents): derive active count from rollout state"
```

## Task 3: Formatter、徽标和本地化

**Files:**

- Modify: `Sources/ThreadBeaconCore/Support/SubagentCountFormatter.swift`
- Modify: `Sources/ThreadBeacon/Views/SubagentCountBadge.swift`
- Modify: `Sources/ThreadBeacon/Views/ThreadRowView.swift`
- Modify: `Resources/Localizable.xcstrings`
- Modify: `Tests/ThreadBeaconTests/SubagentCountFormatterTests.swift`

- [ ] **Step 1: 写 `active/total` Formatter 失败测试**

将现有测试改为：

```swift
TestCase(name: "subagent count formatter hides zero total") {
    try expect(
        SubagentCountFormatter.label(activeCount: 0, totalCount: 0) == nil,
        "zero total should not reserve badge space"
    )
},
TestCase(name: "subagent count formatter exposes active and total counts") {
    let label = SubagentCountFormatter.label(activeCount: 2, totalCount: 27)

    try expect(label?.countText == "2/27", "badge should show active over total")
    try expect(label?.activeCount == 2, "label should retain active count")
    try expect(label?.totalCount == 27, "label should retain total count")
},
TestCase(name: "subagent count formatter normalizes invalid counts") {
    let label = SubagentCountFormatter.label(activeCount: 8, totalCount: 3)
    try expect(label?.countText == "3/3", "active count should not exceed total")
}
```

- [ ] **Step 2: 运行测试并确认 RED**

运行：`./script/test.sh`

预期：编译失败，旧 Formatter 不接受 `activeCount` 和 `totalCount`。

- [ ] **Step 3: 实现结构化 Formatter**

`SubagentCountLabel` 保存 `countText`、`activeCount` 和 `totalCount`；删除不再使用的固定中文
`accessibilityLabel`。入口实现为：

```swift
public static func label(activeCount: Int, totalCount: Int) -> SubagentCountLabel? {
    let total = max(0, totalCount)
    guard total > 0 else { return nil }
    let active = min(max(0, activeCount), total)
    return SubagentCountLabel(
        countText: "\(active)/\(total)",
        activeCount: active,
        totalCount: total
    )
}
```

- [ ] **Step 4: 接入 Badge 和本地化说明**

`ThreadRowView` 改为：

```swift
if let label = SubagentCountFormatter.label(
    activeCount: snapshot.activeSubagentCount,
    totalCount: snapshot.subagentCount
) {
    SubagentCountBadge(...)
}
```

`SubagentCountBadge` 不再从 `countText` 解析整数，统一使用两个结构化计数：

```swift
private var actionLabel: String {
    AppLocalization.formatted(
        isExpanded
            ? "运行中 %lld 个，共 %lld 个 Subagent；点击收起"
            : "运行中 %lld 个，共 %lld 个 Subagent；点击展开",
        locale: locale,
        label.activeCount,
        label.totalCount
    )
}
```

在 `Localizable.xcstrings` 增加英文翻译：

```text
运行中 %lld 个，共 %lld 个 Subagent；点击展开
%lld running, %lld Subagents total; click to expand

运行中 %lld 个，共 %lld 个 Subagent；点击收起
%lld running, %lld Subagents total; click to collapse
```

保留 chevron、Agent 图标、旋转、`.secondary`、`.fixedSize()`、Tooltip 和无障碍调用。

- [ ] **Step 5: 运行测试并确认 GREEN**

运行：`./script/test.sh`

预期：Formatter 新测试和完整测试全部通过。

- [ ] **Step 6: 构建 App**

运行：`./script/swiftpm.sh build`

预期：`ThreadBeacon`、`ThreadBeaconCore` 和资源目录编译成功，无 Swift 6 并发错误。

- [ ] **Step 7: 提交 UI 接入**

```bash
git add Sources/ThreadBeaconCore/Support/SubagentCountFormatter.swift \
  Sources/ThreadBeacon/Views/SubagentCountBadge.swift \
  Sources/ThreadBeacon/Views/ThreadRowView.swift \
  Resources/Localizable.xcstrings \
  Tests/ThreadBeaconTests/SubagentCountFormatterTests.swift
git commit -m "feat(ui): show active and total subagent counts"
```

## Task 4: 完整回归与真实数据验收

**Files:**

- Modify only if validation exposes a defect in files already listed above.

- [ ] **Step 1: 运行完整自动化测试**

运行：`./script/test.sh`

预期：所有测试通过，输出 `N/N tests passed` 且进程退出码为 0。

- [ ] **Step 2: 运行构建和差异检查**

```bash
./script/swiftpm.sh build
git diff --check
git status --short
```

预期：构建成功，`git diff --check` 无输出；工作区只包含本计划明确允许的文件。

- [ ] **Step 3: 本地运行并检查真实样本**

运行：`./script/build_and_run.sh`

检查任务 `019f7afe-d1a4-7ed0-a394-ffa9ae3c99a4`：

- 两个直接 Subagent 为 `.running` 时显示 `2/27`。
- 其中一个完成后，下一轮两秒刷新显示 `1/27`。
- 收起时仍更新，展开后分子等于列表中“运行中”的直接 Subagent 数量。
- 悬浮说明在中文和 English 下分别正确。
- 浅色、深色和最小窗口宽度下不遮挡标题、Token 或 info 按钮。

- [ ] **Step 4: 记录最终验证结果**

若无需修复，不创建额外提交；在交付汇总中记录测试数量、构建结果和真实样本结果。若验证发现
本功能缺陷，只修改本计划列出的文件，重新运行 Task 4 的全部检查后再提交最小修复。
