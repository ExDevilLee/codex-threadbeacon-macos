# 压缩状态可观测性实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**实施状态（2026-07-23）：代码与自动化阶段已完成。** 历史扫描、Hook Helper、安全配置管理、
状态合并和 UI 均已落地，下方实施步骤同步为执行记录；文末真实 Codex 手工与自动压缩门槛仍未关闭。

**Goal:** 在 ThreadBeacon 中以默认只读方式展示任务累计压缩次数，并在用户明确安装 Codex Hook 后展示实时“压缩中”阶段。

**Architecture:** `CompactionHistoryRepository` 增量扫描 rollout，`CompactionActivityRepository` 读取 Hook Helper 写入的每任务活动标记，`ThreadStatusLoader` 将两者合并进任务快照。独立 `ThreadBeaconHookBridge` target 处理 `PreCompact/PostCompact`；Settings 通过结构化 JSON 安装器安全管理用户级 `hooks.json`。

**Tech Stack:** Swift 6、Foundation、SwiftUI、Swift Package Manager、Xcode macOS targets、JSONL、Codex lifecycle hooks。

---

## 文件结构

新增核心文件：

- `Sources/ThreadBeaconCore/Models/CompactionModels.swift`：历史、活动阶段与 Hook 配置状态模型。
- `Sources/ThreadBeaconCore/Services/CompactionHistoryRepository.swift`：rollout 全量首次扫描与增量追加。
- `Sources/ThreadBeaconCore/Services/CompactionActivityRepository.swift`：活动标记读取、TTL 和完成证据失效。
- `Sources/ThreadBeaconCore/Services/CompactionHookConfigurationManager.swift`：Helper 安装及 `hooks.json` 合并、检查和卸载。
- `Sources/ThreadBeaconCore/Stores/CompactionHookSettingsStore.swift`：Settings 可观察状态和用户操作。
- `Sources/ThreadBeaconHookBridge/main.swift`：Hook stdin 入口。
- `Sources/ThreadBeacon/Views/CompactionHookSettingsSection.swift`：明确披露配置修改的设置区域。

修改现有文件：

- `Package.swift`、`ThreadBeacon.xcodeproj/project.pbxproj`：新增 Helper target 并嵌入 App。
- `RolloutObservation.swift`、`ThreadModels.swift`、`ThreadStatusLoader.swift`：承载压缩信息并合并状态。
- `ThreadBeaconApp.swift`、`ThreadBeaconSettingsView.swift`：注入设置 Store。
- `ThreadRowView.swift`、`TokenDetailPopoverView.swift`：显示实时阶段和历史统计。
- `Resources/Localizable.xcstrings`：补齐中英文。
- `Tests/ThreadBeaconTests/TestRunner.swift`：注册新增测试集合。

## Task 1：压缩历史统计

**Files:**

- Create: `Sources/ThreadBeaconCore/Models/CompactionModels.swift`
- Create: `Sources/ThreadBeaconCore/Services/CompactionHistoryRepository.swift`
- Create: `Tests/ThreadBeaconTests/CompactionHistoryRepositoryTests.swift`
- Modify: `Tests/ThreadBeaconTests/TestRunner.swift`

- [x] **Step 1：添加失败测试**

测试必须覆盖成对事件去重、单事件旧格式、损坏行、追加读取和文件截断：

```swift
let history = try repository.history(for: rolloutURL)
try expect(history.completionCount == 2, "paired compact events count once")
try expect(history.lastCompletedAt == expectedDate, "latest completion is retained")
```

- [x] **Step 2：运行定向测试并确认失败**

Run: `./script/test.sh`

Expected: 编译失败，提示 `CompactionHistoryRepository` 或 `CompactionHistory` 不存在。

- [x] **Step 3：实现最小增量扫描器**

模型固定为：

```swift
public struct CompactionHistory: Equatable, Sendable {
    public let completionCount: Int
    public let lastCompletedAt: Date?
}
```

Repository 为同步、加锁的可发送引用类型，缓存文件 identity、offset、未配对事件和累计值。
识别顶层 `compacted` 与 `event_msg.context_compacted`，异类事件在两秒内配对时只计一次；文件
截断或 identity 改变时清空缓存并重新扫描。只提取顶层时间和事件类型。

- [x] **Step 4：运行测试并确认通过**

Run: `./script/test.sh`

Expected: 新增历史测试全部 PASS，原测试无回归。

- [x] **Step 5：提交**

```bash
git add Sources/ThreadBeaconCore/Models/CompactionModels.swift \
  Sources/ThreadBeaconCore/Services/CompactionHistoryRepository.swift \
  Tests/ThreadBeaconTests/CompactionHistoryRepositoryTests.swift \
  Tests/ThreadBeaconTests/TestRunner.swift
git commit -m "feat(compaction): track rollout compression history"
```

## Task 2：活动标记与 Hook Helper

**Files:**

- Create: `Sources/ThreadBeaconCore/Services/CompactionActivityRepository.swift`
- Create: `Sources/ThreadBeaconCore/Services/CompactionHookEventHandler.swift`
- Create: `Sources/ThreadBeaconHookBridge/main.swift`
- Create: `Tests/ThreadBeaconTests/CompactionActivityRepositoryTests.swift`
- Create: `Tests/ThreadBeaconTests/CompactionHookEventHandlerTests.swift`
- Modify: `Package.swift`
- Modify: `Tests/ThreadBeaconTests/TestRunner.swift`

- [x] **Step 1：添加活动标记失败测试**

覆盖 Pre 写入、Post 相同 turn 删除、不同 turn 保留、并发 session、15 分钟 TTL、完成/中断
证据、未来时间和非法 UUID：

```swift
try handler.handle(preCompactJSON)
try expect(repository.activity(for: sessionID, now: now) != nil, "PreCompact creates marker")
try handler.handle(postCompactJSON)
try expect(repository.activity(for: sessionID, now: now) == nil, "matching PostCompact clears marker")
```

- [x] **Step 2：运行测试并确认失败**

Run: `./script/test.sh`

Expected: 编译失败，提示活动 Repository 或 Handler 不存在。

- [x] **Step 3：实现白名单事件处理**

`CompactionHookEventHandler` 只接受 `PreCompact`、`PostCompact`、合法 UUID、`manual|auto`；
`startedAt` 使用注入的 `now()`。标记使用 `Codable`、临时文件和原子替换，Post 只清除相同
`sessionID + turnID`。错误写入最小诊断文件，但命令行入口捕获错误后仍返回 `0`，不阻断 Codex。

- [x] **Step 4：实现只读活动解析与清理**

```swift
public func activity(
    for sessionID: String,
    completionEvidenceAt: Date?,
    interruptionEvidenceAt: Date?,
    now: Date
) -> CompactionActivity?
```

超过 15 分钟、完成/中断证据更新、未来时间或损坏标记均返回 `nil` 并尽力删除文件。

- [x] **Step 5：新增 Helper executable target 并验证 stdin**

`main.swift` 读取标准输入，将数据交给 Handler；无论 Handler 成功或失败都不输出 Hook JSON，
避免改变 Codex 行为。通过临时 `HOME` 和 fixture JSON 验证 Pre/Post 文件变化。

- [x] **Step 6：运行测试并确认通过**

Run: `./script/test.sh`

Expected: 活动和 Hook Handler 测试 PASS。

- [x] **Step 7：提交**

```bash
git add Package.swift Sources/ThreadBeaconCore/Services/CompactionActivityRepository.swift \
  Sources/ThreadBeaconCore/Services/CompactionHookEventHandler.swift \
  Sources/ThreadBeaconHookBridge/main.swift Tests/ThreadBeaconTests
git commit -m "feat(compaction): add lifecycle hook bridge"
```

## Task 3：Hook 配置安装器

**Files:**

- Create: `Sources/ThreadBeaconCore/Services/CompactionHookConfigurationManager.swift`
- Create: `Sources/ThreadBeaconCore/Stores/CompactionHookSettingsStore.swift`
- Create: `Tests/ThreadBeaconTests/CompactionHookConfigurationManagerTests.swift`
- Modify: `Tests/ThreadBeaconTests/TestRunner.swift`

- [x] **Step 1：添加配置管理失败测试**

覆盖新建、保留已有 Hook、幂等安装、精确卸载、备份、非法 JSON、符号链接、并发摘要变化和
检测内联 TOML Hook：

```swift
let result = try manager.install(helperSourceURL: helperURL)
try expect(result == .configured, "valid config installs")
try expect(existingHandlerIsPreserved(hooksURL), "existing hooks remain")
```

- [x] **Step 2：运行测试并确认失败**

Run: `./script/test.sh`

Expected: 编译失败，提示配置 Manager 不存在。

- [x] **Step 3：实现安全安装与卸载**

使用 `JSONSerialization` 保留未知字段。Handler command 使用 shell 安全引用后的稳定路径：

```text
~/Library/Application Support/ThreadBeacon/hooks/v1/ThreadBeaconHookBridge
```

安装流程必须先备份、复制 Helper、验证 JSON，再比较原始摘要并原子替换。备份和配置临时文件
权限为 `0600`，Helper 权限为 `0700`。卸载只删除 command 与 Helper 路径准确匹配的两个
handler，不用备份覆盖当前文件。

- [x] **Step 4：实现可观察 Store**

Store 暴露 `notConfigured`、`configured`、`externallyModified`、`failed(message)`，以及
`refresh()`、`install()`、`uninstall()`。不声称读取到 Codex trust 状态。

- [x] **Step 5：运行测试并确认通过**

Run: `./script/test.sh`

Expected: 配置管理测试 PASS，已有配置 fixture 未被破坏。

- [x] **Step 6：提交**

```bash
git add Sources/ThreadBeaconCore/Services/CompactionHookConfigurationManager.swift \
  Sources/ThreadBeaconCore/Stores/CompactionHookSettingsStore.swift \
  Tests/ThreadBeaconTests/CompactionHookConfigurationManagerTests.swift \
  Tests/ThreadBeaconTests/TestRunner.swift
git commit -m "feat(compaction): manage opt-in Codex hooks"
```

## Task 4：合并任务状态与历史详情

**Files:**

- Modify: `Sources/ThreadBeaconCore/Models/RolloutObservation.swift`
- Modify: `Sources/ThreadBeaconCore/Models/ThreadModels.swift`
- Modify: `Sources/ThreadBeaconCore/Services/RolloutTailParser.swift`
- Modify: `Sources/ThreadBeaconCore/Services/ThreadStatusLoader.swift`
- Modify: `Tests/ThreadBeaconTests/RolloutTailParserTests.swift`
- Modify: `Tests/ThreadBeaconTests/ThreadStatusLoaderTests.swift`

- [x] **Step 1：添加状态合并失败测试**

覆盖压缩阶段按运行中排序、错误/需操作/服务异常覆盖压缩、归档忽略压缩、完成/中断证据清理
和历史字段透传：

```swift
try expect(snapshot.compaction?.isActive == true, "fresh hook marker exposes compacting")
try expect(snapshot.compaction?.history.completionCount == 3, "history reaches details")
```

- [x] **Step 2：运行测试并确认失败**

Run: `./script/test.sh`

Expected: 编译失败，提示 `ThreadSnapshot.compaction` 不存在。

- [x] **Step 3：扩展观察与快照模型**

`RolloutObservation` 增加最新中断证据时间；`ThreadSnapshot` 增加：

```swift
public let compaction: CompactionSnapshot
```

`CompactionSnapshot` 包含历史、可选活动开始时间和 trigger，不复制 Hook 原始 JSON。

- [x] **Step 4：在 Loader 合并数据源**

生产初始化注入共享的历史 Repository 和活动 Repository。记录已归档或存在 error、
needsAction、warning 时保留历史但不暴露活动阶段；其他有效活动按运行中排序。活动状态不触发
完成提示音或自动恢复。

- [x] **Step 5：运行测试并确认通过**

Run: `./script/test.sh`

Expected: Loader、排序、通知和自动恢复回归测试全部 PASS。

- [x] **Step 6：提交**

```bash
git add Sources/ThreadBeaconCore/Models Sources/ThreadBeaconCore/Services \
  Tests/ThreadBeaconTests/RolloutTailParserTests.swift \
  Tests/ThreadBeaconTests/ThreadStatusLoaderTests.swift
git commit -m "feat(compaction): merge live and historical status"
```

## Task 5：Settings 与任务列表 UI

**Files:**

- Create: `Sources/ThreadBeacon/Views/CompactionHookSettingsSection.swift`
- Modify: `Sources/ThreadBeacon/App/ThreadBeaconApp.swift`
- Modify: `Sources/ThreadBeacon/Views/ThreadBeaconSettingsView.swift`
- Modify: `Sources/ThreadBeacon/Views/ThreadRowView.swift`
- Modify: `Sources/ThreadBeacon/Views/TokenDetailPopoverView.swift`
- Modify: `Resources/Localizable.xcstrings`
- Modify: `Tests/ThreadBeaconTests/CompactionPresentationTests.swift`
- Modify: `Tests/ThreadBeaconTests/TestRunner.swift`

- [x] **Step 1：添加纯展示规则失败测试**

将主状态文案和持续时间选择提取为 Core presentation，测试中英文键、错误覆盖、归档覆盖和
无活动回退。

- [x] **Step 2：运行测试并确认失败**

Run: `./script/test.sh`

Expected: 编译失败，提示 presentation 不存在。

- [x] **Step 3：实现 Settings 区域**

区域始终显示目标文件路径、会创建备份、会保留现有 Hook、需要在 Codex 审核信任、不会保存
正文等说明。安装按钮显示确认弹窗；已配置状态提供“检查配置”和“停用”。失败信息必须经过
本地化的用户可读映射。

- [x] **Step 4：实现任务行和详情**

任务行有效活动显示`压缩中 · n 秒`，继续使用蓝色运行灯；Token 详情新增“压缩次数”和
“最近压缩”。窗口宽度和现有 Token/Subagent 列不改变。

- [x] **Step 5：补齐中英文资源并检查动态切换**

所有新增可见文本进入 `Localizable.xcstrings`。简体中文显示中文，English 及其他系统语言
回退英文；切换语言无需重启。

- [x] **Step 6：运行完整测试并构建 Debug App**

Run: `./script/test.sh`

Expected: 全部测试 PASS。

Run:

```bash
xcodebuild -project ThreadBeacon.xcodeproj -scheme ThreadBeacon \
  -configuration Debug -destination platform=macOS \
  -derivedDataPath .build/xcode-compaction CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- build
```

Expected: `** BUILD SUCCEEDED **`，App 内包含可执行 Hook Helper。

- [x] **Step 7：提交**

```bash
git add Sources/ThreadBeacon Resources/Localizable.xcstrings \
  Tests/ThreadBeaconTests ThreadBeacon.xcodeproj/project.pbxproj
git commit -m "feat(compaction): expose live status and hook settings"
```

## Task 6：文档、隐私与集成验收

**Files:**

- Modify: `ROADMAP.md`
- Modify: `PRIVACY.md`
- Modify: `README.md`
- Modify: `README-EN.md`
- Modify: `docs/compaction-observability-design.md`

- [x] **Step 1：同步功能与隐私文档**

记录默认只读历史统计、opt-in 配置修改、备份路径、Hook trust、停用和卸载步骤。ROADMAP 将
压缩 MVP 标为已实现、待真实手工和自动压缩验证；不得把未出现的自动压缩写成已验证。

- [x] **Step 2：执行文档检查**

Run:

```bash
npm run lint:md -- ROADMAP.md PRIVACY.md README.md README-EN.md \
  docs/compaction-observability-design.md \
  docs/compaction-observability-implementation-plan.md
```

Expected: `Summary: 0 error(s)`。

- [x] **Step 3：执行完整回归**

Run: `./script/test.sh`

Expected: 全部测试 PASS。

Run: `git diff --check`

Expected: 无输出。

- [x] **Step 4：执行隔离 HOME 的 Hook POC**

用临时 HOME 安装 Hook，分别向 Helper 输入 Pre/Post fixture，验证配置保留、活动文件创建和
清理；不得修改真实 `~/.codex/hooks.json`。

- [x] **Step 5：构建但不安装 App**

Run: `THREADBEACON_CONFIGURATION=Debug ./script/build_and_run.sh --verify`

Expected: App 构建并短暂运行验证成功。完成后关闭 dist 构建，不替换 `/Applications` 中的版本。

- [x] **Step 6：提交文档与收尾**

```bash
git add ROADMAP.md PRIVACY.md README.md README-EN.md \
  docs/compaction-observability-design.md \
  docs/compaction-observability-implementation-plan.md
git commit -m "docs(compaction): document opt-in status tracking"
```

## 实机验证门槛

Coding 完成后仍需 Lee 在真实 Codex 中完成以下人工门槛：

1. 在 ThreadBeacon Settings 点击启用并确认文件修改披露清晰。
2. 在 Codex Hooks 设置或 CLI `/hooks` 中审核并信任两个 Hook。
3. 对指定任务执行 `/compact`，确认两秒内出现“压缩中”。
4. 确认压缩完成后状态消失，累计次数增加。
5. 后续自然出现自动压缩时，再验证 `trigger=auto`。

在上述人工门槛完成前，可以声称代码、自动化和隔离 POC 通过，但不能声称真实 Codex Hook
集成已经完成验证。
