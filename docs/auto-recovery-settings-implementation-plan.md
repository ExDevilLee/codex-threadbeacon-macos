# 自动恢复设置 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Accessibility 恢复 POC 接入可持久化、按异常类型配置的正式自动恢复功能，同时从 Release 界面移除开发测试控件。

**Architecture:** `ThreadBeaconCore` 负责稳定的异常分类、设置模型、持久化和候选规则判定；App 层持有设置状态并在获得 Accessibility 授权时调用参数化发送器；SwiftUI Settings 显示正式配置和历史记录，仅在 Debug 构建中挂载开发者诊断区。

**Tech Stack:** Swift 6.1、SwiftUI、AppKit Accessibility、UserDefaults、现有自定义 Swift 测试运行器。

---

## Task 1: 自动恢复配置模型与持久化

**Files:**

- Create: `Sources/ThreadBeaconCore/Models/AutoRecoverySettings.swift`
- Create: `Sources/ThreadBeaconCore/Stores/AutoRecoverySettingsStore.swift`
- Create: `Tests/ThreadBeaconTests/AutoRecoverySettingsTests.swift`
- Modify: `Tests/ThreadBeaconTests/TestRunner.swift`

- [ ] **Step 1: 写失败测试**

  覆盖五种规则的默认值、503 默认关闭、总开关默认关闭、提示词长度与空值校验、UserDefaults
  round trip、缺失规则回填以及损坏数据回退。

- [ ] **Step 2: 验证 RED**

  运行 `./script/test.sh`，确认因为 `AutoRecoverySettings`、repository 和 store 尚不存在而编译失败。

- [ ] **Step 3: 实现最小模型与 store**

  定义 `AutoRecoveryIncidentType: String, Codable, CaseIterable`、`AutoRecoveryRule`、
  `AutoRecoverySettings`、`AutoRecoveryPromptValidation`、`AutoRecoverySettingsRepository` 和
  `@MainActor AutoRecoverySettingsStore`。repository 使用单个版本化 Codable payload 写入
  `UserDefaults`；decode 失败回退 `.defaultValue`。

- [ ] **Step 4: 验证 GREEN**

  运行 `./script/test.sh`，确认新增配置测试和全部既有测试通过。

## Task 2: 异常分类与规则判定

**Files:**

- Modify: `Sources/ThreadBeaconCore/Models/AutoRecoverySettings.swift`
- Modify: `Sources/ThreadBeaconCore/Stores/ThreadStatusStore.swift`
- Modify: `Tests/ThreadBeaconTests/AutoRecoverySettingsTests.swift`
- Modify: `Tests/ThreadBeaconTests/ThreadStatusStoreTests.swift`

- [ ] **Step 1: 写失败测试**

  覆盖 `badRequest -> http400`、`httpRateLimit -> http429`、`serviceUnavailable -> http503`、
  任意其他 HTTP code -> `otherHTTP`、`modelCapacity -> modelCapacity`；同时验证 retrying 不产生
  候选、failed 503 可以成为候选，且回调收到结构化异常而不是硬编码提示词。

- [ ] **Step 2: 验证 RED**

  运行 `./script/test.sh`，确认失败来自缺少异常映射或回调签名不匹配。

- [ ] **Step 3: 实现结构化候选**

  为 `ServiceIncident` 提供稳定分类和公开日志标签。将 `ThreadStatusStore.onAutoRecovery` 改为传递
  `AutoRecoveryCandidate`，保留 `.failed`、启动基线和 episode 去重，不再在 Core 中硬编码提示词
  或排除 503。

- [ ] **Step 4: 验证 GREEN**

  运行 `./script/test.sh`，确认分类和候选测试通过，原有 503 测试更新为“产生候选但由默认规则
  禁用”。

## Task 3: 参数化 Accessibility 发送与 App 编排

**Files:**

- Modify: `Sources/ThreadBeacon/Services/SystemAccessibilityRecoverySender.swift`
- Modify: `Sources/ThreadBeacon/Support/AccessibilityPermissionStore.swift`
- Modify: `Sources/ThreadBeacon/App/ThreadBeaconApp.swift`
- Modify: `Sources/ThreadBeaconCore/Models/AutoRecoveryLog.swift`
- Modify: `Sources/ThreadBeaconCore/Stores/AutoRecoveryLogStore.swift`
- Modify: `Tests/ThreadBeaconTests/AccessibilityDiagnosticTests.swift`
- Modify: `Tests/ThreadBeaconTests/AutoRecoveryLogStoreTests.swift`
- Modify: `Tests/ThreadBeaconTests/AutoRecoverySettingsTests.swift`

- [ ] **Step 1: 写失败测试**

  覆盖自定义提示词校验、规则关闭、总开关关闭、未授权跳过、503 默认跳过和已授权时形成发送动作；
  更新 rollout checkpoint 测试，确保确认解析器使用传入提示词。

- [ ] **Step 2: 验证 RED**

  运行 `./script/test.sh`，确认固定提示词发送器与缺少决策器导致测试失败。

- [ ] **Step 3: 实现 App 层决策与发送**

  `SystemAccessibilityRecoverySender.send` 接收 `prompt` 参数，并将该值同时用于输入框写入、回读和
  rollout 确认。App 初始化 `AutoRecoverySettingsStore`；新候选到达时按总开关和类型规则过滤，
  未授权记录 skipped，已授权使用 `.unattended` 调用发送器并记录 verified、failed 或 unconfirmed。
  禁止外部 CLI 回退。

- [ ] **Step 4: 验证 GREEN**

  运行 `./script/test.sh`，确认发送参数化、规则决策和日志测试全部通过。

## Task 4: 正式 Settings 与 Debug 诊断隔离

**Files:**

- Create: `Sources/ThreadBeacon/Views/AutoRecoverySettingsView.swift`
- Create: `Sources/ThreadBeacon/Views/AutoRecoveryDiagnosticsView.swift`
- Modify: `Sources/ThreadBeacon/Views/ThreadBeaconSettingsView.swift`
- Modify: `Sources/ThreadBeacon/App/ThreadBeaconApp.swift`
- Modify: `Resources/Localizable.xcstrings`

- [ ] **Step 1: 拆分正式界面和诊断界面**

  将正式自动恢复配置、权限状态和记录放入 `AutoRecoverySettingsView`；把现有只读诊断、输入框验证、
  任务 ID、切换验证和测试发送迁入 `AutoRecoveryDiagnosticsView`。

- [ ] **Step 2: 使用编译条件隔离**

  在 `AutoRecoverySettingsView` 中仅通过 `#if DEBUG` 挂载“开发者诊断”折叠区。Release 分支不创建
  诊断 view；正式配置在 Debug/Release 均显示。

- [ ] **Step 3: 完成双语文案和紧凑布局**

  为总开关、五类异常、默认状态、提示词、恢复默认、校验错误、权限说明和开发者诊断标题添加
  简体中文/英文 String Catalog 条目。每个规则使用原生 Section/DisclosureGroup，不嵌套卡片。

- [ ] **Step 4: 验证构建**

  运行 `swift build --product ThreadBeacon`、`swift build -c release --product ThreadBeacon` 和
  `./script/test.sh`。预期 Debug、Release 构建均成功且测试全绿。

## Task 5: 文档、质量检查与本地验证产物

**Files:**

- Modify: `README.md`
- Modify: `README-EN.md`
- Modify: `ROADMAP.md`
- Modify: `docs/accessibility-recovery-poc.md`
- Modify: `docs/auto-recovery-settings-design.md`

- [ ] **Step 1: 同步行为文档**

  记录正式配置、默认关闭、503 默认关闭、Release/Debug 边界、Accessibility 授权要求以及“恢复原
  前台 App”仍未实现。

- [ ] **Step 2: 运行质量检查**

  对修改的 Markdown 文件运行仓库锁定的 `markdownlint-cli2`，再运行 `git diff --check`、凭据扫描和
  `./script/test.sh`。

- [ ] **Step 3: 构建可验证 App**

  使用现有 Xcode/脚本构建流程生成本地最新 App，但不安装、不 PUSH。确认签名和 Release 产物可打开
  所需的静态检查通过。

- [ ] **Step 4: 创建本地提交**

  仅暂存本计划涉及的文件，复核 `git diff --cached` 后使用 Conventional Commit 提交；保持远端不变。
