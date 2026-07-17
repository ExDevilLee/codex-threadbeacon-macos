# Subagent Count Badge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the direct Subagent count beside each main task title and reliably exclude known child tasks from the main list.

**Architecture:** Extend the read-only SQLite repository with a relationship-aware aggregate query and a legacy-schema fallback. Carry one nonnegative `subagentCount` value through `ThreadRecord` and `ThreadSnapshot`, then render a neutral conditional badge in a focused SwiftUI view.

**Tech Stack:** Swift 6, SwiftUI, AppKit, SQLite C API, SwiftPM executable tests, macOS 14+

---

## File Map

- Modify `Sources/ThreadBeaconCore/Models/ThreadModels.swift`: add the count to record and snapshot contracts.
- Modify `Sources/ThreadBeaconCore/Services/SQLiteThreadRepository.swift`: detect the relationship table, aggregate direct children, and exclude known child tasks.
- Modify `Sources/ThreadBeaconCore/Services/ThreadStatusLoader.swift`: pass the count into display snapshots.
- Create `Sources/ThreadBeacon/Views/SubagentCountBadge.swift`: render the neutral icon-and-number marker.
- Modify `Sources/ThreadBeacon/Views/ThreadRowView.swift`: position the marker between title and Token information.
- Modify `Tests/ThreadBeaconTests/SQLiteThreadRepositoryTests.swift`: cover counts, filtering, archived children, statuses, and schema fallback.
- Modify `Tests/ThreadBeaconTests/ThreadStatusLoaderTests.swift`: cover count propagation.
- Modify `README.md`, `README-EN.md`, and `ROADMAP.md`: document shipped behavior and retained limits.

### Task 1: Relationship-Aware Repository

**Files:**

- Modify: `Sources/ThreadBeaconCore/Models/ThreadModels.swift`
- Modify: `Sources/ThreadBeaconCore/Services/SQLiteThreadRepository.swift`
- Modify: `Tests/ThreadBeaconTests/SQLiteThreadRepositoryTests.swift`

- [ ] **Step 1: Add failing repository expectations**

Extend the SQLite fixture with `thread_spawn_edges` and three children for `new-thread`:

```swift
CREATE TABLE thread_spawn_edges (
    parent_thread_id TEXT NOT NULL,
    child_thread_id TEXT NOT NULL PRIMARY KEY,
    status TEXT NOT NULL
);
INSERT INTO threads VALUES
    ('legacy-child', 'Legacy Child', '/tmp/legacy.jsonl', 310, 310000, 510000, 0, NULL, 4),
    ('archived-child', 'Archived Child', '/tmp/archived-child.jsonl', 320, 320000, 520000, 1, NULL, 5);
INSERT INTO thread_spawn_edges VALUES
    ('new-thread', 'subagent-thread', 'open'),
    ('new-thread', 'legacy-child', 'closed'),
    ('new-thread', 'archived-child', 'closed');
```

Add assertions:

```swift
try expect(records.map(\.id) == ["new-thread", "older-thread"], "known children should be excluded")
try expect(records.first?.subagentCount == 3, "all direct child relationships should be counted")
```

Add a legacy fixture without `thread_spawn_edges` and assert:

```swift
let records = try SQLiteThreadRepository(databaseURL: databaseURL).loadRecent(limit: 8)
try expect(records.first?.subagentCount == 0, "missing relationship table should fall back to zero")
```

- [ ] **Step 2: Run tests and verify the new contract fails**

Run:

```bash
./script/test.sh
```

Expected: compilation fails because `ThreadRecord` has no `subagentCount`.

- [ ] **Step 3: Add `ThreadRecord.subagentCount`**

Add the stored property and defaulted initializer argument:

```swift
public let subagentCount: Int

public init(
    id: String,
    title: String,
    rolloutPath: String,
    updatedAt: Date,
    tokensUsed: Int64 = 0,
    subagentCount: Int = 0
) {
    self.id = id
    self.title = title
    self.rolloutPath = rolloutPath
    self.updatedAt = updatedAt
    self.tokensUsed = tokensUsed
    self.subagentCount = max(0, subagentCount)
}
```

- [ ] **Step 4: Implement relationship-table detection and query selection**

Add a prepared `sqlite_master` lookup. The table name is an internal constant, so the query does
not interpolate user input:

```swift
private func hasSpawnEdgesTable(in database: OpaquePointer) throws -> Bool {
    let sql = """
    SELECT 1
    FROM sqlite_master
    WHERE type = 'table' AND name = 'thread_spawn_edges'
    LIMIT 1
    """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw SQLiteThreadRepositoryError.database(databaseMessage(database))
    }
    defer { sqlite3_finalize(statement) }

    return sqlite3_step(statement) == SQLITE_ROW
}
```

Select one of these query shapes:

```sql
SELECT t.id, t.title, t.rollout_path,
       COALESCE(t.updated_at_ms, t.updated_at * 1000),
       t.tokens_used,
       COALESCE(children.child_count, 0)
FROM threads AS t
LEFT JOIN (
    SELECT parent_thread_id, COUNT(*) AS child_count
    FROM thread_spawn_edges
    GROUP BY parent_thread_id
) AS children ON children.parent_thread_id = t.id
WHERE t.archived = 0
  AND COALESCE(t.thread_source, '') <> 'subagent'
  AND NOT EXISTS (
      SELECT 1 FROM thread_spawn_edges AS edge
      WHERE edge.child_thread_id = t.id
  )
ORDER BY t.recency_at_ms DESC, t.id DESC
LIMIT ?
```

```sql
SELECT id, title, rollout_path,
       COALESCE(updated_at_ms, updated_at * 1000),
       tokens_used,
       0
FROM threads
WHERE archived = 0
  AND COALESCE(thread_source, '') <> 'subagent'
ORDER BY recency_at_ms DESC, id DESC
LIMIT ?
```

Read column 5 as a nonnegative exact `Int`; throw `.invalidRow` if conversion fails.

- [ ] **Step 5: Run the repository tests**

Run:

```bash
./script/test.sh
```

Expected: all tests pass, including relationship counts and legacy fallback.

- [ ] **Step 6: Commit the repository slice**

```bash
git add Sources/ThreadBeaconCore/Models/ThreadModels.swift \
  Sources/ThreadBeaconCore/Services/SQLiteThreadRepository.swift \
  Tests/ThreadBeaconTests/SQLiteThreadRepositoryTests.swift
git diff --cached --check
git commit -m "feat(subagent): load direct child counts"
```

### Task 2: Snapshot Propagation

**Files:**

- Modify: `Sources/ThreadBeaconCore/Models/ThreadModels.swift`
- Modify: `Sources/ThreadBeaconCore/Services/ThreadStatusLoader.swift`
- Modify: `Tests/ThreadBeaconTests/ThreadStatusLoaderTests.swift`

- [ ] **Step 1: Write the failing propagation test**

Add a loader test with a count-bearing record:

```swift
TestCase(name: "loader retains direct subagent count") {
    let now = Date(timeIntervalSince1970: 6_500)
    let loader = ThreadStatusLoader(
        loadRecords: { _ in
            [ThreadRecord(
                id: "parent",
                title: "Parent",
                rolloutPath: "/tmp/parent",
                updatedAt: now,
                subagentCount: 3
            )]
        },
        observe: { _ in RolloutObservation() },
        now: { now }
    )

    let snapshots = try await loader.load(limit: 8)

    try expect(snapshots.first?.subagentCount == 3, "loader should pass direct child count")
}
```

- [ ] **Step 2: Run tests and verify the snapshot contract fails**

Run:

```bash
./script/test.sh
```

Expected: compilation fails because `ThreadSnapshot` has no `subagentCount`.

- [ ] **Step 3: Add and propagate `ThreadSnapshot.subagentCount`**

Add the property and defaulted initializer argument:

```swift
public let subagentCount: Int

public init(
    id: String,
    title: String,
    status: ThreadDisplayStatus,
    statusChangedAt: Date,
    updatedAt: Date,
    latestEventAt: Date?,
    completionEventAt: Date? = nil,
    tokenUsage: TokenUsageSnapshot? = nil,
    subagentCount: Int = 0
) {
    self.id = id
    self.title = title
    self.status = status
    self.statusChangedAt = statusChangedAt
    self.updatedAt = updatedAt
    self.latestEventAt = latestEventAt
    self.completionEventAt = completionEventAt
    self.tokenUsage = tokenUsage
    self.subagentCount = max(0, subagentCount)
}
```

Pass the repository value when creating each snapshot:

```swift
subagentCount: record.subagentCount
```

- [ ] **Step 4: Run the full test suite**

Run:

```bash
./script/test.sh
```

Expected: all tests pass and existing sorting, Token, title, and sound tests remain green.

- [ ] **Step 5: Commit the model propagation slice**

```bash
git add Sources/ThreadBeaconCore/Models/ThreadModels.swift \
  Sources/ThreadBeaconCore/Services/ThreadStatusLoader.swift \
  Tests/ThreadBeaconTests/ThreadStatusLoaderTests.swift
git diff --cached --check
git commit -m "feat(subagent): propagate counts to snapshots"
```

### Task 3: Neutral Count Badge

**Files:**

- Create: `Sources/ThreadBeacon/Views/SubagentCountBadge.swift`
- Modify: `Sources/ThreadBeacon/Views/ThreadRowView.swift`

- [ ] **Step 1: Create the focused badge view**

```swift
import SwiftUI

struct SubagentCountBadge: View {
    let count: Int

    private var label: String {
        "\(count) 个 Subagent"
    }

    var body: some View {
        Label {
            Text("\(count)")
                .monospacedDigit()
        } icon: {
            Image(systemName: "arrow.triangle.branch")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize()
        .help(label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}
```

- [ ] **Step 2: Insert the badge in the confirmed A position**

In the title `HStack`, after the title and before Token information:

```swift
if snapshot.subagentCount > 0 {
    SubagentCountBadge(count: snapshot.subagentCount)
}

if let tokenUsage = snapshot.tokenUsage {
    // Keep the existing Token text and info button.
}
```

The conditional keeps zero-count rows unchanged and prevents empty layout space.

- [ ] **Step 3: Build and run all tests**

Run:

```bash
./script/test.sh
./script/swiftpm.sh build
```

Expected: tests pass and the app target builds without SwiftUI or SF Symbol errors.

- [ ] **Step 4: Commit the UI slice**

```bash
git add Sources/ThreadBeacon/Views/SubagentCountBadge.swift \
  Sources/ThreadBeacon/Views/ThreadRowView.swift
git diff --cached --check
git commit -m "feat(ui): show subagent count badge"
```

### Task 4: Documentation and Real-Data Verification

**Files:**

- Modify: `README.md`
- Modify: `README-EN.md`
- Modify: `ROADMAP.md`

- [ ] **Step 1: Document the shipped count semantics**

Add this bullet to the Chinese interface section:

```markdown
- 创建过 Subagent 的主任务会在标题右侧显示直接 Subagent 总数；这是历史关系数量，
  不代表当前正在运行的数量，也不读取或显示子任务内容。
```

Add the equivalent bullet to the English interface section:

```markdown
- A primary task that created Subagents shows its direct Subagent count beside the title. This is
  a historical relationship count, not a live running count, and no child-task content is read or
  displayed.
```

Add the shipped capability to `已完成`:

```markdown
- 主任务行显示直接 Subagent 总数，并使用父子关系表补强子任务过滤；数量不表示实时
  运行状态。
```

Replace the research item with this retained boundary:

```markdown
- `Subagent 展开详情与实时状态`：总数标记只表达历史直接子任务数量；展开详情、活动
  数量、状态颜色和任务树 Token 聚合继续保留为后续候选。
```

- [ ] **Step 2: Run documentation and source verification**

Run:

```bash
npm run lint:md -- \
  poc/codex-thread-status-macos/README.md \
  poc/codex-thread-status-macos/README-EN.md \
  poc/codex-thread-status-macos/ROADMAP.md
./script/test.sh
./script/build_and_run.sh --verify
git diff --check
```

Expected: Markdown has zero errors, tests pass, and `ThreadBeacon is running` is printed.

- [ ] **Step 3: Verify the live UI against current SQLite data**

Confirm visually on macOS:

- A current parent with 3 direct children displays the branch icon and `3`.
- Rows without children have no badge or extra gap.
- Title, badge, Token text, and info button do not overlap at the app's default width.
- No child task appears as a main-list row.

- [ ] **Step 4: Commit documentation**

```bash
git add README.md README-EN.md ROADMAP.md
git diff --cached --check
git commit -m "docs(subagent): document count badge semantics"
```

- [ ] **Step 5: Final repository check**

```bash
git status --short --branch
git log -5 --oneline
```

Expected: no uncommitted files from Feature 5; the branch contains the repository, propagation, UI,
and documentation commits after the design checkpoint.
