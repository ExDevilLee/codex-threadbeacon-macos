# 状态数据源健康诊断 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不增加新的读取范围和默认列表噪音的前提下，让用户判断任务数据库、rename 索引、rollout 与服务日志是否健康。

**Architecture:** `ThreadStatusLoader` 在生成任务快照的同一次刷新中收集结构化健康报告，`ThreadStatusStore` 原子发布快照与报告并保留最后成功时间。SwiftUI 只在底部提供紧凑入口，通过 popover 按需展示稳定、脱敏的诊断信息。

**Tech Stack:** Swift 6.1、SwiftUI、Foundation、现有 SQLite/JSONL 只读服务、自定义异步测试运行器。

---

## 文件结构

- 新建 `Sources/ThreadBeaconCore/Models/DataSourceHealth.swift`：健康状态、四类数据源报告、加载结果和结构化失败。
- 修改 `Sources/ThreadBeaconCore/Services/ThreadStatusLoader.swift`：在现有回退路径中采集健康结果。
- 修改 `Sources/ThreadBeaconCore/Stores/ThreadStatusStore.swift`：发布报告和最后成功刷新时间。
- 新建 `Sources/ThreadBeacon/Views/DataSourceHealthPopoverView.swift`：健康入口和详情 popover。
- 修改 `Sources/ThreadBeacon/Views/ContentView.swift`：在底部接入健康入口。
- 修改 `Sources/ThreadBeacon/App/ThreadBeaconApp.swift`：生产环境改用携带健康报告的加载入口。
- 新建 `Tests/ThreadBeaconTests/DataSourceHealthTests.swift`：整体状态与稳定说明测试。
- 修改 `Tests/ThreadBeaconTests/ThreadStatusLoaderTests.swift`：可选源降级、rollout 计数与核心失败测试。
- 修改 `Tests/ThreadBeaconTests/ThreadStatusStoreTests.swift`：成功、失败与旧快照保留测试。
- 修改 `Tests/ThreadBeaconTests/TestRunner.swift`：注册新增测试组。
- 修改 `README.md`、`README-EN.md`、`PRIVACY.md`、`ROADMAP.md`：同步功能、隐私和 backlog 状态。

### Task 1：健康状态模型

**Files:**

- Create: `Sources/ThreadBeaconCore/Models/DataSourceHealth.swift`
- Create: `Tests/ThreadBeaconTests/DataSourceHealthTests.swift`
- Modify: `Tests/ThreadBeaconTests/TestRunner.swift`

- [x] **Step 1：写整体状态派生失败测试**

测试构造全部正常、一个可选源降级和核心不可用三份报告，断言整体状态分别为 `.healthy`、
`.degraded` 和 `.unavailable`；同时断言公开说明不包含 `/Users/`、任务 ID 或原始错误。

```swift
let report = DataSourceHealthReport(
    taskDatabase: .healthy,
    renameIndex: .degraded("Rename 索引不可用，已回退原始标题"),
    rollout: .healthy,
    serviceLogs: .healthy,
    rolloutSuccessCount: 2,
    rolloutFailureCount: 0,
    lastSuccessfulRefreshAt: nil
)
try expect(report.overallStatus == .degraded, "optional failure should degrade the report")
```

- [x] **Step 2：运行测试确认 RED**

Run: `./script/test.sh`

Expected: 编译失败，提示 `DataSourceHealthReport` 不存在。

- [x] **Step 3：实现最小模型**

定义：

```swift
public enum DataSourceHealthStatus: Equatable, Sendable {
    case healthy
    case degraded(String)
    case unavailable(String)
    case notUsed
}

public enum OverallDataSourceHealth: Equatable, Sendable {
    case healthy
    case degraded
    case unavailable
}

public struct DataSourceHealthReport: Equatable, Sendable {
    public let taskDatabase: DataSourceHealthStatus
    public let renameIndex: DataSourceHealthStatus
    public let rollout: DataSourceHealthStatus
    public let serviceLogs: DataSourceHealthStatus
    public let rolloutSuccessCount: Int
    public let rolloutFailureCount: Int
    public let lastSuccessfulRefreshAt: Date?

    public var overallStatus: OverallDataSourceHealth
    public var summary: String
    public func recordingSuccessfulRefresh(at date: Date) -> Self
}

public struct ThreadStatusLoadResult: Equatable, Sendable {
    public let snapshots: [ThreadSnapshot]
    public let health: DataSourceHealthReport
}

public struct ThreadStatusLoadFailure: Error, LocalizedError, Sendable {
    public let health: DataSourceHealthReport
    public var errorDescription: String? { "Codex 任务数据库不可用" }
}
```

整体状态优先级为核心 `.unavailable` > 任一 `.degraded` 或 `.unavailable` > `.healthy`；
`.notUsed` 不导致降级。

- [x] **Step 4：运行测试确认 GREEN**

Run: `./script/test.sh`

Expected: 新增模型测试通过，既有测试不回归。

### Task 2：Loader 同步生成健康报告

**Files:**

- Modify: `Sources/ThreadBeaconCore/Services/ThreadStatusLoader.swift`
- Modify: `Tests/ThreadBeaconTests/ThreadStatusLoaderTests.swift`

- [x] **Step 1：写可选数据源降级失败测试**

使用现有依赖注入 initializer，让 rename 与服务日志闭包抛出错误，调用
`loadResult(...)`，断言任务快照仍返回且对应健康项为 `.degraded`。

```swift
let result = try await loader.loadResult(
    limit: 8,
    includedThreadIDs: [],
    favoriteThreadIDs: [],
    expandedThreadIDs: []
)
try expect(result.snapshots.count == 1, "optional failures must preserve snapshots")
try expect(result.health.overallStatus == .degraded, "optional failures should be visible")
```

- [x] **Step 2：写 rollout 计数和核心失败测试**

构造两个主任务，一个 rollout 成功、一个抛错，断言成功／失败数量为 `1/1`。让
`loadRecords` 抛错，断言收到 `ThreadStatusLoadFailure`，其中任务数据库为 `.unavailable`，
其他未执行数据源为 `.notUsed`。

- [x] **Step 3：运行测试确认 RED**

Run: `./script/test.sh`

Expected: 编译失败，提示 `loadResult` 不存在。

- [x] **Step 4：实现健康采集**

新增完整参数入口：

```swift
public func loadResult(
    limit: Int,
    includedThreadIDs: Set<String>,
    favoriteThreadIDs: Set<String>,
    expandedThreadIDs: Set<String>
) async throws -> ThreadStatusLoadResult
```

实现规则：

- 核心 SQLite 查询失败时抛出 `ThreadStatusLoadFailure`，只使用稳定文案。
- rename 失败时使用空 overrides 并记录降级。
- 没有活动任务时服务日志为 `.notUsed`；否则失败时使用空 incidents 并记录降级。
- 主任务和已展开直接 Subagent 的每次 rollout 解析都计入成功或失败；失败继续使用空
  `RolloutObservation`。
- rollout 总数为零时状态是 `.notUsed`；失败数大于零时是 `.degraded`。
- 现有返回 `[ThreadSnapshot]` 的 `load(...)` 委托给 `loadResult(...).snapshots`，保持兼容。

- [x] **Step 5：运行测试确认 GREEN**

Run: `./script/test.sh`

Expected: Loader 新旧测试全部通过。

### Task 3：Store 发布健康状态

**Files:**

- Modify: `Sources/ThreadBeaconCore/Stores/ThreadStatusStore.swift`
- Modify: `Tests/ThreadBeaconTests/ThreadStatusStoreTests.swift`

- [x] **Step 1：写成功和失败状态测试**

使用新的 `loadResult:` initializer：第一次返回一条任务和健康报告，第二次抛出带不可用报告
的 `ThreadStatusLoadFailure`。断言第一次设置 `lastRefreshedAt` 和健康报告；第二次保留第一次
快照和最后成功时间，但把 `dataSourceHealth` 更新为不可用。

- [x] **Step 2：运行测试确认 RED**

Run: `./script/test.sh`

Expected: 编译失败，提示 `loadResult` initializer 或 `dataSourceHealth` 不存在。

- [x] **Step 3：实现 Store 兼容入口**

新增：

```swift
@Published public private(set) var dataSourceHealth: DataSourceHealthReport?

public init(
    loadResult: @escaping @Sendable (ThreadLoadRequest) async throws -> ThreadStatusLoadResult,
    ...
)
```

保留现有 `load:` initializer，并把快照包装为一份全部未使用的兼容报告，避免批量改写既有
Store 测试。生产 App 使用 `loadResult:`。成功刷新时用同一个 `now()` 值更新报告和
`lastRefreshedAt`；捕获 `ThreadStatusLoadFailure` 时保留旧快照，发布错误中的健康报告并
保留上次成功时间。

- [x] **Step 4：运行测试确认 GREEN**

Run: `./script/test.sh`

Expected: Store 全部测试通过，通知行为不变。

### Task 4：底部健康入口与详情

**Files:**

- Create: `Sources/ThreadBeacon/Views/DataSourceHealthPopoverView.swift`
- Modify: `Sources/ThreadBeacon/Views/ContentView.swift`
- Modify: `Sources/ThreadBeacon/App/ThreadBeaconApp.swift`

- [x] **Step 1：切换生产加载入口**

`ThreadBeaconApp` 的 Store 初始化改用 `loadResult:`，闭包调用 Loader 的完整
`loadResult(...)`。不改变刷新周期、通知策略或读取路径。

- [x] **Step 2：实现紧凑入口**

新 View 接收 `DataSourceHealthReport`，使用：

- 正常：`checkmark.shield` + secondary。
- 部分降级：`exclamationmark.triangle.fill` + yellow。
- 不可用：`xmark.octagon.fill` + red。

按钮设置 `.help(report.summary)` 和中文 accessibility label，点击展示 popover。

- [x] **Step 3：实现详情 popover**

popover 固定约 300pt 宽，顶部显示`数据源健康`与最后成功刷新时间，下面依次显示：

- `任务数据库`
- `Rename 索引`
- `Rollout`
- `服务日志`

每行同时使用图标、状态文字和颜色；若有稳定说明则显示第二行 secondary 文本。rollout 行
显示成功／失败数量，不展示任务身份。

- [x] **Step 4：接入 footer**

`ContentView.footer` 在 `Spacer()` 之后仅在 `store.dataSourceHealth != nil` 时显示入口，
避免 App 首次加载前产生误导状态。入口不改变 footer 高度和任务列表布局。

- [x] **Step 5：构建验证**

Run: `./script/build_and_run.sh --verify`

Expected: `Build complete!` 且 `ThreadBeacon is running`。

### Task 5：文档同步与最终验证

**Files:**

- Modify: `README.md`
- Modify: `README-EN.md`
- Modify: `PRIVACY.md`
- Modify: `ROADMAP.md`
- Modify: `docs/data-source-health-diagnostics-design.md`
- Modify: `docs/data-source-health-diagnostics-implementation-plan.md`

- [x] **Step 1：同步公开功能说明**

README 中说明底部入口、三档整体状态和四类数据源；PRIVACY 明确健康报告只保存在内存、只含
稳定类别和数量、不新增读取范围；ROADMAP 将健康诊断标记完成，并把建议顺序更新为最小
Settings。

- [x] **Step 2：检查隐私内容**

Run:

```bash
git diff | rg -n "(/Users/[^ ]+|019[0-9a-f-]{20,}|reasoning summary|request ID)"
```

Expected: 只允许文档中的抽象隐私边界描述，不出现真实用户名、任务 ID 或调试样本。

- [x] **Step 3：运行完整验证**

Run:

```bash
./script/test.sh
./script/build_and_run.sh --verify
```

Expected: 全量测试零失败，App 构建并运行。

- [x] **Step 4：运行文档与差异检查**

从父仓库运行：

```bash
npm run lint:md -- \
  poc/codex-thread-status-macos/README.md \
  poc/codex-thread-status-macos/README-EN.md \
  poc/codex-thread-status-macos/PRIVACY.md \
  poc/codex-thread-status-macos/ROADMAP.md \
  poc/codex-thread-status-macos/docs/data-source-health-diagnostics-design.md \
  poc/codex-thread-status-macos/docs/data-source-health-diagnostics-implementation-plan.md
git -C poc/codex-thread-status-macos diff --check
```

Expected: Markdown `0 error(s)`，diff check 无输出。

- [x] **Step 5：停在实机验收 checkpoint**

保持 App 运行，向 Lee 说明健康入口位置和正常状态下应看到的四项结果。本轮不自动提交或
PUSH，等待实机确认后再形成提交检查点。
