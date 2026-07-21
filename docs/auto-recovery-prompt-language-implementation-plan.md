# 自动恢复默认提示词语言 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让自动恢复的内置提示词跟随 ThreadBeacon App 语言，同时保证用户主动保存的提示词永不被语言切换覆盖。

**Architecture:** `ThreadBeaconCore` 持久化提示词来源并负责 v1 到 v2 迁移、语言默认值和同步规则；App 层把已解析的 `AppLanguage` 传给 Store，并在运行期语言变化时触发同步；SwiftUI 编辑器只同步未被用户修改的草稿。

**Tech Stack:** Swift 6.1、SwiftUI、Combine、UserDefaults、Codable、现有自定义 Swift 测试运行器。

---

## Task 1: 配置模型、双语默认值与 v1 迁移

**Files:**

- Modify: `Sources/ThreadBeaconCore/Models/AutoRecoverySettings.swift`
- Modify: `Tests/ThreadBeaconTests/AutoRecoverySettingsTests.swift`

- [x] **Step 1: 写双语默认值和来源迁移失败测试**

新增测试，要求 `defaultValue(promptLanguage:)` 为五类异常生成对应语言文本与
`.defaultValue` 来源；版本 `1` 的历史中文默认值迁移为 `.defaultValue`，其他文本迁移为
`.custom`。

```swift
let english = AutoRecoverySettings.defaultValue(promptLanguage: .english)
try expect(
    english.rule(for: .http400).prompt
        == "The previous request was interrupted by an error. Please continue the unfinished task.",
    "English should use the English HTTP 400 default"
)
try expect(
    english.rule(for: .http400).promptSource == .defaultValue,
    "built-in prompts should retain their source"
)
```

- [x] **Step 2: 运行测试并确认 RED**

运行：`./script/test.sh`

预期：编译失败，缺少 `AutoRecoveryPromptLanguage`、`AutoRecoveryPromptSource` 和带语言参数的
默认配置 API。

- [x] **Step 3: 实现 v2 模型与迁移**

新增稳定枚举并把配置版本提升为 `2`：

```swift
public enum AutoRecoveryPromptLanguage: String, Codable, Sendable {
    case simplifiedChinese
    case english

    public init(localeIdentifier: String) {
        self = localeIdentifier.lowercased().hasPrefix("zh") ? .simplifiedChinese : .english
    }
}

public enum AutoRecoveryPromptSource: String, Codable, Sendable {
    case defaultValue
    case custom
}
```

`AutoRecoveryRule` 增加 `promptSource`；内置规则标记为 `.defaultValue`，现有公开初始化器默认把
调用方传入文本视为 `.custom`。`AutoRecoverySettings.init(from:)` 在读取版本 `1` 时，对每种异常
精确匹配历史中文默认值；匹配则迁移为默认来源，否则保留为自定义来源。新增
`synchronizeDefaultPrompts(to:)`，只替换默认来源规则。

- [x] **Step 4: 运行测试并确认 GREEN**

运行：`./script/test.sh`

预期：双语默认值、来源与 v1 迁移测试通过，既有默认开关和异常策略测试保持通过。

## Task 2: Store 持久化与运行期语言同步

**Files:**

- Modify: `Sources/ThreadBeaconCore/Stores/AutoRecoverySettingsStore.swift`
- Modify: `Sources/ThreadBeacon/App/ThreadBeaconApp.swift`
- Modify: `Tests/ThreadBeaconTests/AutoRecoverySettingsTests.swift`

- [x] **Step 1: 写 Store 行为失败测试**

测试以下公开行为：

```swift
store.setPromptLanguage(.english)
try expect(
    store.settings.rule(for: .http400).promptSource == .defaultValue,
    "language sync should keep default provenance"
)

_ = store.savePrompt(for: .http429, prompt: "my custom retry prompt")
store.setPromptLanguage(.simplifiedChinese)
try expect(
    store.settings.rule(for: .http429).prompt == "my custom retry prompt",
    "custom prompts must survive language changes"
)

store.setRuleEnabled(false, for: .http429)
try expect(
    store.settings.rule(for: .http429).promptSource == .custom,
    "toggling a rule must not change prompt provenance"
)
```

同时验证 `resetRule(for:)` 使用 Store 当前语言，并验证 repository round trip 写出版本 `2`。

- [x] **Step 2: 运行测试并确认 RED**

运行：`./script/test.sh`

预期：编译失败，缺少 `setPromptLanguage`、`savePrompt` 和 `setRuleEnabled`。

- [x] **Step 3: 实现 Store API 与 App 接线**

Store 持有当前 `AutoRecoveryPromptLanguage`，初始化时调用
`repository.load(promptLanguage:)` 并把迁移后的 v2 配置保存。拆分三个意图明确的方法：

```swift
public func setRuleEnabled(_ isEnabled: Bool, for type: AutoRecoveryIncidentType)

@discardableResult
public func savePrompt(
    for type: AutoRecoveryIncidentType,
    prompt: String
) -> AutoRecoveryPromptValidation

public func resetRule(for type: AutoRecoveryIncidentType)
```

`ThreadBeaconApp.init()` 先创建 `AppLanguageStore`，用其 resolved locale 初始化恢复 Store。主窗口
监听 `appLanguageStore.locale.identifier`，变化时调用：

```swift
autoRecoverySettingsStore.setPromptLanguage(
    AutoRecoveryPromptLanguage(localeIdentifier: identifier)
)
```

- [x] **Step 4: 运行测试并确认 GREEN**

运行：`./script/test.sh`

预期：Store 切换、保存、开关、恢复默认和持久化测试全部通过。

## Task 3: Settings 草稿保护与默认值即时刷新

**Files:**

- Modify: `Sources/ThreadBeacon/Views/AutoRecoverySettingsView.swift`

- [x] **Step 1: 拆分 Toggle 与保存意图**

规则 Toggle 改为调用 `setRuleEnabled(_:for:)`，避免复用保存提示词 API 后把默认文本误标为自定义。

- [x] **Step 2: 保护未保存草稿**

`AutoRecoveryRuleEditor` 增加 `isDraftDirty`。TextEditor 的自定义 Binding 在用户输入时置为
`true`；监听持久化 `storedPrompt` 变化时只在草稿未修改时更新编辑框：

```swift
.onChange(of: storedPrompt) { _, newPrompt in
    guard !isDraftDirty else { return }
    draftPrompt = newPrompt
}
```

保存成功或恢复默认后将 `isDraftDirty` 设为 `false`。因此切换语言不会覆盖正在输入但尚未保存的
内容，而未编辑的默认提示词会即时刷新。

- [x] **Step 3: 构建验证**

运行：

```bash
swift build --product ThreadBeacon
swift build -c release --product ThreadBeacon
```

预期：Debug 与 Release 构建成功。

## Task 4: 文档与最终质量检查

**Files:**

- Modify: `CHANGELOG.md`
- Modify: `README.md`
- Modify: `README-EN.md`
- Modify: `ROADMAP.md`
- Modify: `docs/auto-recovery-prompt-language-design.md`
- Modify: `docs/auto-recovery-prompt-language-implementation-plan.md`

- [x] **Step 1: 同步用户可见行为**

记录默认提示词跟随 App 语言、自定义提示词保持不变、旧配置迁移规则和未保存草稿保护；不把该
功能描述为真实异常端到端验证完成。

- [x] **Step 2: 运行完整验证**

运行：

```bash
./script/test.sh
swift build --product ThreadBeacon
swift build -c release --product ThreadBeacon
```

对本轮 Markdown 运行仓库锁定的 `markdownlint-cli2`，并运行 `jq empty
Resources/Localizable.xcstrings`、`git diff --check` 与敏感信息扫描。

预期：测试全部通过、两种构建成功、文档与结构化资源检查无错误。

- [x] **Step 3: 本地提交但不自动 PUSH 或安装**

只暂存本计划涉及的代码、测试和文档，复核 `git diff --cached` 后提交：

```bash
git commit -m "feat(recovery): localize default prompts"
```

安装、PUSH、Tag 和 Release 均等待 Lee 在验收后单独确认。
