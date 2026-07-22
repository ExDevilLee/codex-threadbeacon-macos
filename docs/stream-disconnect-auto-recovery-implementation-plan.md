# ThreadBeacon 连接中断自动恢复实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在同一 turn 的重新连接 5/5 最终失败后，将任务标记为连接中断并进入可配置的自动恢复链路。

**Architecture:** `LogEventRepository` 只纳入精确的最终断流日志，`LogEventParser` 组合重试耗尽与最终错误生成独立 `streamDisconnected` 事件。现有 `ThreadStatusStore` 继续只消费终止型事件；`AutoRecoverySettings` 和 SwiftUI 设置页增加一条独立规则。

**Tech Stack:** Swift 6、SwiftUI、SQLite read-only、Swift Package Manager、自定义测试 Runner、Apple String Catalog。

---

## Task 1: 日志读取与终止判定

**Files:**

- Modify: `Tests/ThreadBeaconTests/LogEventParserTests.swift`
- Modify: `Tests/ThreadBeaconTests/LogEventRepositoryTests.swift`
- Modify: `Sources/ThreadBeaconCore/Models/ServiceIncident.swift`
- Modify: `Sources/ThreadBeaconCore/Services/LogEventParser.swift`
- Modify: `Sources/ThreadBeaconCore/Services/LogEventRepository.swift`

- [x] **Step 1: 写失败测试**

新增三个 Parser 场景：只有 `5/5` 仍为 `retrying`；同 turn 的 `5/5` 加最终断流错误变为
`streamDisconnected + failed`；缺少重试耗尽的断流文本不产生终止事件。Repository fixture
增加精确最终断流日志，并断言可以读取为终止事件。

- [x] **Step 2: 运行测试并确认 RED**

Run: `./script/test.sh`

Expected: 因 `ServiceIncidentKind.streamDisconnected` 不存在或 Repository 未读取最终日志而失败。

- [x] **Step 3: 添加最小实现**

新增 `streamDisconnected` kind。Repository 的 `session::turn` 白名单增加精确
`Turn error: stream disconnected before completion:` 条件；Parser 只在同 episode 已
`retryAttempt == retryLimit` 时把该最终错误记录为 `failed`。

- [x] **Step 4: 运行测试并确认 GREEN**

Run: `./script/test.sh`

Expected: 全部测试通过。

## Task 2: 自动恢复规则与迁移

**Files:**

- Modify: `Tests/ThreadBeaconTests/AutoRecoverySettingsTests.swift`
- Modify: `Tests/ThreadBeaconTests/ThreadStatusStoreTests.swift`
- Modify: `Sources/ThreadBeaconCore/Models/AutoRecoverySettings.swift`
- Modify: `Sources/ThreadBeaconCore/Stores/ThreadStatusStore.swift`

- [x] **Step 1: 写失败测试**

断言新类型默认规则开启、中英文默认提示词稳定、旧载荷自动补齐、
`ServiceIncidentKind.streamDisconnected` 映射正确，以及最终断流只产生一次恢复候选。

- [x] **Step 2: 运行测试并确认 RED**

Run: `./script/test.sh`

Expected: 因 `AutoRecoveryIncidentType.streamDisconnected` 缺失而编译失败。

- [x] **Step 3: 添加最小实现**

新增自动恢复类型、默认提示词、默认开启规则和日志标签“连接中断”。保持总开关默认关闭，
沿用现有 `normalizeRules` 为旧设置补齐规则。

- [x] **Step 4: 运行测试并确认 GREEN**

Run: `./script/test.sh`

Expected: 全部测试通过。

## Task 3: UI 与本地化

**Files:**

- Modify: `Sources/ThreadBeacon/Views/ThreadRowView.swift`
- Modify: `Sources/ThreadBeacon/Views/AutoRecoverySettingsView.swift`
- Modify: `Resources/Localizable.xcstrings`

- [x] **Step 1: 展示连接中断详情**

最终断流行显示“服务失败 ｜ 连接中断 ｜ 重试 5/5”，活跃重试保持现有黄色文案。

- [x] **Step 2: 增加设置规则文案**

自动恢复页新增“连接中断 / Connection interrupted”规则和耗尽说明，复用现有开关、提示词
编辑与恢复默认交互。

- [x] **Step 3: 构建并验证 String Catalog**

Run: `swift build`

Run: `jq empty Resources/Localizable.xcstrings`

Expected: Debug 构建和 JSON 解析通过。

## Task 4: 文档、真实样本与发布前验证

**Files:**

- Modify: `README.md`
- Modify: `README-EN.md`
- Modify: `ROADMAP.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/service-incident-monitoring.md`

- [x] **Step 1: 同步用户文档**

记录连接中断状态、自动恢复规则、只在最终错误后触发以及不保存 URL 的隐私边界。

- [x] **Step 2: 用真实会话数据只读验证**

调用现有只读 Repository 或 probe，确认真实样本被解析为 `failed + streamDisconnected + 5/5`，
输出只包含状态字段，不输出标题、URL 或完整日志正文。

验证结果：设计阶段已用真实日志确认同一 turn 的 `5/5` 与最终断流顺序；实现后复验时，滚动
日志已淘汰这两条记录，因此当前数据库无法再次生成 incident。测试 fixture 继续覆盖相同结构，
不把会话 ID、URL、标题或完整正文写入仓库。

- [x] **Step 3: 完成 UI 验收**

使用仓库 `dist/ThreadBeacon.app` 验证中英文、浅色与深色、主任务失败详情和自动恢复设置页，
不覆盖 `/Applications/ThreadBeacon.app`。

- [x] **Step 4: 运行最终验证**

Run: `./script/test.sh`

Run: `THREADBEACON_CONFIGURATION=Release ./script/build_and_run.sh --verify`

Run: `npm run lint:md -- <本次修改的 Markdown 文件>`

Run: `git diff --check`

Expected: 所有命令退出码为 0，无私人路径、会话 ID、URL 或日志正文进入提交。

- [ ] **Step 5: 提交并推送**

```bash
git add Sources Tests Resources README.md README-EN.md ROADMAP.md CHANGELOG.md docs
git commit -m "feat(recovery): handle exhausted stream disconnects"
git push origin main
```
