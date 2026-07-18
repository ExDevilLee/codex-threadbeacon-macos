# 已归档收藏恢复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为已归档收藏提供经过确认的 `codex unarchive <SESSION_ID>` 恢复操作，成功后保留收藏并刷新真实状态。

**Architecture:** 在 `ThreadBeaconCore` 中分离 CLI 路径解析、命令执行和 Store 状态编排；SwiftUI 只负责右键入口、确认和结果展示。所有外部进程参数均通过 `Process.arguments` 传递，不拼接 Shell 命令，不直接写 Codex SQLite。

**Tech Stack:** Swift 6.1、Foundation `Process`、SwiftUI、现有自定义异步测试运行器。

> **2026-07-18 状态更新：** 底层取消归档 POC 已完成真实验证，但 Codex App 无法可靠地
> 把恢复后的旧任务重新加入侧边栏并通过深链打开。右键入口已通过可测试的
> `ArchiveRestoreAvailability` 暂时隐藏；底层实现保留，待官方公开接口满足完整验收条件后
> 再重新启用。不直接修改 `recency_at_ms`，不调用 Codex App 私有 IPC。

---

## 文件结构

- 新建 `Sources/ThreadBeaconCore/Services/CodexCLIResolver.swift`：发现可执行的 Codex CLI。
- 新建 `Sources/ThreadBeaconCore/Services/CodexArchiveRestoreService.swift`：参数化执行恢复命令并映射错误。
- 新建 `Sources/ThreadBeaconCore/Models/ArchiveRestoreFeedback.swift`：Store 与 UI 共用的恢复结果模型。
- 新建 `Sources/ThreadBeaconCore/Models/ArchiveRestoreAvailability.swift`：记录 UI 暂停开放及
  上游原因。
- 修改 `Sources/ThreadBeaconCore/Stores/ThreadStatusStore.swift`：恢复中、重复保护、结果和刷新编排。
- 修改 `Sources/ThreadBeacon/App/ThreadBeaconApp.swift`：注入生产恢复服务。
- 修改 `Sources/ThreadBeacon/Views/ContentView.swift`：右键入口、确认和结果提示。
- 修改 `Sources/ThreadBeacon/Views/ThreadRowView.swift`：显示任务正在恢复。
- 新建 `Tests/ThreadBeaconTests/CodexCLIResolverTests.swift`：路径优先级与 NVM 版本测试。
- 新建 `Tests/ThreadBeaconTests/CodexArchiveRestoreServiceTests.swift`：参数和错误映射测试。
- 新建 `Tests/ThreadBeaconTests/ArchiveRestoreAvailabilityTests.swift`：锁定入口隐藏契约与原因。
- 修改 `Tests/ThreadBeaconTests/ThreadStatusStoreTests.swift`：成功、失败和重复执行测试。
- 修改 `Tests/ThreadBeaconTests/TestRunner.swift`：注册新增测试组。
- 修改 `README.md`、`README-EN.md`、`PRIVACY.md`、`ROADMAP.md`：同步行为和边界。

### Task 1: Codex CLI 解析器

**Files:**

- Create: `Sources/ThreadBeaconCore/Services/CodexCLIResolver.swift`
- Create: `Tests/ThreadBeaconTests/CodexCLIResolverTests.swift`
- Modify: `Tests/ThreadBeaconTests/TestRunner.swift`

- [x] **Step 1: 写 PATH、稳定目录、NVM 与未找到的失败测试**

测试通过注入的 `isExecutable` 和 `listDirectory` 闭包构造虚拟文件系统，并明确断言：

```swift
let resolver = CodexCLIResolver(
    environment: ["PATH": "/custom/bin:/usr/bin"],
    homeDirectory: URL(fileURLWithPath: "/Users/test"),
    isExecutable: { $0.path == "/custom/bin/codex" },
    listDirectory: { _ in [] }
)
try expect(try resolver.resolve().path == "/custom/bin/codex", "PATH candidate should win")
```

NVM 测试返回 `v20.19.0`、`v22.22.0` 和无效目录，断言选择
`v22.22.0/bin/codex`。未找到测试断言抛出 `.cliNotFound`。

- [x] **Step 2: 运行测试并确认 RED**

Run: `./script/test.sh`

Expected: 编译失败，提示找不到 `CodexCLIResolver`。

- [x] **Step 3: 实现最小解析器**

实现公开 API：

```swift
public struct CodexCLIResolver: Sendable {
    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        isExecutable: @escaping @Sendable (URL) -> Bool = CodexCLIResolver.defaultIsExecutable,
        listDirectory: @escaping @Sendable (URL) -> [URL] = CodexCLIResolver.defaultListDirectory
    )

    public func resolve() throws -> URL
}
```

候选顺序固定为：当前 `PATH`、`/opt/homebrew/bin/codex`、
`/usr/local/bin/codex`、`~/.local/bin/codex`、按语义版本倒序排列的
`~/.nvm/versions/node/*/bin/codex`。候选必须存在且可执行，并按标准化路径去重。

- [x] **Step 4: 运行测试并确认 GREEN**

Run: `./script/test.sh`

Expected: 新增解析器测试全部通过，既有 `77/77` 测试无回归。

### Task 2: 归档恢复执行服务

**Files:**

- Create: `Sources/ThreadBeaconCore/Services/CodexArchiveRestoreService.swift`
- Create: `Tests/ThreadBeaconTests/CodexArchiveRestoreServiceTests.swift`
- Modify: `Tests/ThreadBeaconTests/TestRunner.swift`

- [x] **Step 1: 写命令参数与错误分类的失败测试**

用注入闭包捕获执行参数：

```swift
let service = CodexArchiveRestoreService(
    resolveExecutable: { URL(fileURLWithPath: "/opt/homebrew/bin/codex") },
    environment: ["PATH": "/usr/bin"],
    runCommand: { executable, arguments, environment in
        calls.append((executable, arguments, environment))
        return CodexCommandResult(exitCode: 0, output: "")
    }
)
try await service.restore(threadID: "session-id")
try expect(calls.first?.1 == ["unarchive", "session-id"], "arguments must not use shell joining")
try expect(calls.first?.2["PATH"] == "/opt/homebrew/bin:/usr/bin", "child PATH should find Node")
```

另写测试断言包含 `unknown subcommand` 的非零结果映射为 `.unsupportedCommand`，普通非零
结果映射为 `.executionFailed`，输出被清理并限制长度。

- [x] **Step 2: 运行测试并确认 RED**

Run: `./script/test.sh`

Expected: 编译失败，提示恢复服务和命令结果类型不存在。

- [x] **Step 3: 实现命令结果、稳定错误和生产执行器**

公开接口：

```swift
public struct CodexCommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let output: String
}

public enum ArchiveRestoreError: LocalizedError, Equatable, Sendable {
    case cliNotFound
    case unsupportedCommand
    case executionFailed(String?)
    case launchFailed(String)
}

public struct CodexArchiveRestoreService: Sendable {
    public func restore(threadID: String) async throws
}
```

生产 `runCommand` 使用 `Process.executableURL` 和 `Process.arguments`，把可执行文件目录
放到子进程 `PATH` 首位，合并捕获标准输出与标准错误，并在 utility detached task 中等待
退出。只保留清理后的前 500 个字符；空输出使用统一错误文案。

- [x] **Step 4: 运行测试并确认 GREEN**

Run: `./script/test.sh`

Expected: 参数、unsupported 和普通失败测试全部通过。

### Task 3: Store 恢复状态与重复保护

**Files:**

- Create: `Sources/ThreadBeaconCore/Models/ArchiveRestoreFeedback.swift`
- Modify: `Sources/ThreadBeaconCore/Stores/ThreadStatusStore.swift`
- Modify: `Tests/ThreadBeaconTests/ThreadStatusStoreTests.swift`

- [x] **Step 1: 写成功、失败和并发重复调用的失败测试**

成功测试以归档收藏作为初始快照，注入恢复闭包和两段 load 序列，断言：

```swift
await store.restoreArchivedFavorite("archived")
let result = await MainActor.run {
    (store.isFavorite("archived"), store.archiveRestoreFeedback, store.restoringThreadIDs)
}
try expect(result.0, "successful restore must retain favorite")
try expect(result.1 == .success(threadID: "archived"), "success feedback should publish")
try expect(result.2.isEmpty, "restoring state should clear")
```

失败测试断言收藏、置顶和忽略规则均不变化；并发测试使用 gate 暂停第一次调用，第二次调用
同一 ID 时恢复闭包仍只收到一次调用。

- [x] **Step 2: 运行测试并确认 RED**

Run: `./script/test.sh`

Expected: 编译失败，提示 Store 没有恢复 API 和恢复状态。

- [x] **Step 3: 实现最小 Store 编排**

新增：

```swift
@Published public private(set) var restoringThreadIDs: Set<String> = []
@Published public private(set) var archiveRestoreFeedback: ArchiveRestoreFeedback?

public func isRestoringArchive(_ threadID: String) -> Bool
public func restoreArchivedFavorite(_ threadID: String) async
public func dismissArchiveRestoreFeedback()
```

`restoreArchivedFavorite` 必须验证任务仍是收藏且当前快照为归档；同一 ID 已在集合中时直接
返回。成功只发布反馈并调用一次 `.baseline` 刷新，不修改 `ThreadListPreferences`；失败只
发布结构化错误反馈。

- [x] **Step 4: 运行测试并确认 GREEN**

Run: `./script/test.sh`

Expected: Store 新增测试通过，既有偏好测试无回归。

### Task 4: SwiftUI 确认、恢复中与结果反馈

**Files:**

- Modify: `Sources/ThreadBeacon/App/ThreadBeaconApp.swift`
- Modify: `Sources/ThreadBeacon/Views/ContentView.swift`
- Modify: `Sources/ThreadBeacon/Views/ThreadRowView.swift`

- [x] **Step 1: 注入生产恢复服务**

在 App 初始化中创建 `CodexArchiveRestoreService`，向 Store 注入：

```swift
restoreArchive: { threadID in
    try await archiveRestoreService.restore(threadID: threadID)
}
```

- [x] **Step 2: 增加只对归档收藏可见的右键操作**

`ContentView` 保存待确认快照：

```swift
@State private var pendingArchiveRestore: ThreadSnapshot?
```

仅在 `snapshot.isArchived && store.isFavorite(snapshot.id)` 时显示
`恢复为激活状态`；恢复期间禁用该按钮。

- [x] **Step 3: 增加确认和结果展示**

使用 `confirmationDialog` 展示任务标题、`恢复`和`取消`。确认后调用
`await store.restoreArchivedFavorite(snapshot.id)`。使用独立 `alert` 展示成功或失败反馈，
关闭时调用 `dismissArchiveRestoreFeedback()`。

- [x] **Step 4: 显示行内恢复状态**

向 `ThreadRowView` 传入 `isRestoringArchive`。恢复期间显示 mini `ProgressView`，主状态文字
使用`正在恢复`；恢复完成后继续完全由 SQLite 快照决定显示`已归档`或正常状态。

- [x] **Step 5: 构建并修复编译错误**

Run: `./script/build_and_run.sh --verify`

Expected: `ThreadBeacon is running`。

### Task 5: 文档、完整验证与 UI 验收

**Files:**

- Modify: `README.md`
- Modify: `README-EN.md`
- Modify: `PRIVACY.md`
- Modify: `ROADMAP.md`

- [x] **Step 1: 同步公开行为和隐私边界**

README 说明归档收藏可经确认调用官方 CLI 恢复；PRIVACY 明确任务 ID 仅作为本机进程参数、
不记录命令输出；ROADMAP 将阶段二标为完成，并保留批量恢复和手动 CLI 路径配置为后续项。

- [x] **Step 2: 运行全量自动验证**

Run:

```bash
./script/test.sh
./script/build_and_run.sh --verify
npm run lint:md -- \
  poc/codex-thread-status-macos/README.md \
  poc/codex-thread-status-macos/README-EN.md \
  poc/codex-thread-status-macos/PRIVACY.md \
  poc/codex-thread-status-macos/ROADMAP.md \
  poc/codex-thread-status-macos/docs/archive-restore-design.md \
  poc/codex-thread-status-macos/docs/archive-restore-implementation-plan.md
git diff --check
```

Expected: 所有测试通过、App 正在运行、Markdown `0 error`、diff check 无输出。

- [x] **Step 3: 使用实际 UI 验收非破坏路径**

已确认正常收藏不会误显示恢复入口，并在检查后恢复全部任务视图。后续使用 Lee 明确授权的
测试会话完成 CLI 与 Codex App 索引对照，并通过真实 UI 确认右键入口、确认对话框和恢复
动作。测试结束后将授权会话恢复为未归档。

- [x] **Step 4: 检查公开安全性和最终 diff**

确认 diff 中没有用户绝对路径、真实任务标题、凭据、完整环境变量或调试输出；确认工作树只
包含本功能文件。

### Task 6: 调研恢复后在 Codex App 中打开

- [x] **Step 1: 使用授权测试会话对照 CLI 与 Codex App 索引行为**

确认 CLI 与 Codex App 的归档 API 会产生一致的本地归档状态；取消归档后 App 内部索引可
重新读取会话。测试结束后将授权会话恢复为未归档。

- [x] **Step 2: 验证官方任务深链**

通过 `codex://threads/<thread-id>` 请求打开恢复后的真实旧会话，Codex App
`26.715.21425` 提示找不到会话；系统只能确认 URL Scheme 已分发，无法确认会话成功加载。

- [x] **Step 3: 排除 CLI 版本错配**

分别使用外部 CLI `0.144.1` 和 Codex App 内置 CLI `0.145.0-alpha.18` 对授权测试会话执行
恢复，结果一致：内部索引可读取，但侧边栏近期排序和任务深链不能可靠打开。

- [x] **Step 4: 移除不可靠的自动打开与误导提示**

保留取消归档和真实状态刷新；不修改 `recency_at_ms`，不调用 Codex App 私有 IPC。文档将
自动打开标记为上游限制，待 OpenAI 提供可靠公开接口后再实现。

- [x] **Step 5: 暂时隐藏恢复入口**

真实验收表明“取消归档成功”仍无法满足“回到 Codex App 侧边栏并打开”的产品目标，因此
通过 `ArchiveRestoreAvailability.current.isEnabled` 隐藏右键入口，并把上游限制保留为
可测试原因。底层 CLI、Store 与测试继续保留，避免未来重新验证时重复实现。
