# Done 提示音 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 ThreadBeacon 增加可靠且不重复的主任务完成提示音，并提供总开关、完成音开关、三个内置声音和试听入口。

**Architecture:** rollout parser 只提取最新 `task_complete` 时间戳，Store 内的纯 Swift tracker 将它转换为有界、可持久化的 `done` 事件；首次启动、手动刷新和恢复监听只建立水位，自动监听后续刷新才允许发声。AppKit 播放服务读取 App 内置 WAV，SwiftUI popover 负责最小设置；状态 UI 的 `justCompleted` 保留逻辑不参与声音去重。

**Tech Stack:** Swift 6.1、SwiftPM、SwiftUI、AppKit `NSSound`、`UserDefaults`、项目自定义异步测试 runner、Bash/Swift 资源生成脚本。

---

## 文件结构

- `Sources/ThreadBeaconCore/Models/RolloutObservation.swift`：携带 rollout 中最新完成事件时间。
- `Sources/ThreadBeaconCore/Models/ThreadModels.swift`：把完成事件证据传到最终任务快照。
- `Sources/ThreadBeaconCore/Models/SoundNotification.swift`：定义通知类别、刷新策略和纯状态去重 tracker。
- `Sources/ThreadBeaconCore/Services/RolloutTailParser.swift`：只解析 `task_complete` 类型和时间戳。
- `Sources/ThreadBeaconCore/Services/ThreadStatusLoader.swift`：把完成事件证据传给快照。
- `Sources/ThreadBeaconCore/Stores/ThreadStatusStore.swift`：刷新成功后调用 tracker，并把新事件交给 App。
- `Sources/ThreadBeacon/Support/CompletionSound.swift`：三个内置完成音的稳定 ID、显示名和文件名。
- `Sources/ThreadBeacon/Support/SoundNotificationHistory.swift`：用 `UserDefaults` 保存有界事件 ID。
- `Sources/ThreadBeacon/Support/SoundPlaybackService.swift`：加载、试听和播放 App 内 WAV。
- `Sources/ThreadBeacon/Views/SoundSettingsView.swift`：最小声音设置 popover。
- `Sources/ThreadBeacon/Views/ContentView.swift`：区分基线刷新和可通知的自动刷新，并提供设置入口。
- `Sources/ThreadBeacon/App/ThreadBeaconApp.swift`：组装 tracker、历史存储和播放服务。
- `Resources/Sounds/`：三个确定性生成、许可清晰的完成音 WAV。
- `script/render_sound_assets.swift`：使用 PCM 波形生成三个声音源文件。
- `script/generate_sound_assets.sh`：生成声音资源。
- `script/verify_sound_assets.sh`：验证源资源和 App bundle 资源。
- `script/build_and_run.sh`：把声音资源复制到 App bundle。
- `Tests/ThreadBeaconTests/SoundNotificationTests.swift`：完成事件去重、基线和批量合并测试。
- `Tests/ThreadBeaconTests/TestRunner.swift`：注册新增测试。
- `Tests/ThreadBeaconTests/RolloutTailParserTests.swift`、`ThreadStatusLoaderTests.swift`、
  `ThreadStatusStoreTests.swift`：覆盖事件证据传递和回调。
- `README.md`、`README-EN.md`、`PRIVACY.md`、`ROADMAP.md`：同步真实行为与隐私边界。

### Task 1: 从 rollout 提取稳定的完成事件证据

**Files:**

- Modify: `Sources/ThreadBeaconCore/Models/RolloutObservation.swift`
- Modify: `Sources/ThreadBeaconCore/Models/ThreadModels.swift`
- Modify: `Sources/ThreadBeaconCore/Services/RolloutTailParser.swift`
- Modify: `Sources/ThreadBeaconCore/Services/ThreadStatusLoader.swift`
- Test: `Tests/ThreadBeaconTests/RolloutTailParserTests.swift`
- Test: `Tests/ThreadBeaconTests/ThreadStatusLoaderTests.swift`

- [ ] **Step 1: 写 parser 失败测试**

在 `rolloutTailParserTests` 加入包含两个 `task_complete` 的样本，并断言只保留最新时间：

```swift
TestCase(name: "task complete exposes latest completion event without message text") {
    let lines = [
        #"{"timestamp":"2026-07-16T01:02:00Z","type":"event_msg","payload":{"type":"task_complete","last_agent_message":"private"}}"#,
        #"{"timestamp":"2026-07-16T01:04:00Z","type":"event_msg","payload":{"type":"task_complete","last_agent_message":"new private"}}"#
    ]

    let result = RolloutTailParser().parse(lines: lines)
    let expected = ISO8601DateFormatter().date(from: "2026-07-16T01:04:00Z")

    try expect(result.completionEventAt == expected, "latest task_complete should identify the done event")
    try expect(
        !Mirror(reflecting: result).children.compactMap(\.label).contains("lastAgentMessage"),
        "completion evidence must not retain message text"
    )
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `./script/test.sh`

Expected: 编译失败，提示 `RolloutObservation` 没有 `completionEventAt`。

- [ ] **Step 3: 增加完成事件字段和最小解析**

给 `RolloutObservation` 和 `ThreadSnapshot` 增加 `completionEventAt: Date?`，构造器默认值
为 `nil`。在 parser 的 event loop 中加入：

```swift
var latestCompletionEventAt: Date?

if eventType == "task_complete" {
    latestCompletionEventAt = max(latestCompletionEventAt ?? .distantPast, date)
}
```

返回 observation 时传入：

```swift
completionEventAt: latestCompletionEventAt
```

在 `ThreadStatusLoader` 创建快照时原样传递：

```swift
completionEventAt: observation.completionEventAt
```

不得读取或保存 `last_agent_message`。

- [ ] **Step 4: 写 loader 传递测试并运行**

在 `threadStatusLoaderTests` 构造带 `completionEventAt` 的 observation，断言最终快照时间
完全相同。Run: `./script/test.sh`

Expected: 全部测试通过，新增 parser 和 loader 测试显示 `PASS`。

- [ ] **Step 5: 提交完成证据管线**

```bash
git add Sources/ThreadBeaconCore/Models/RolloutObservation.swift \
  Sources/ThreadBeaconCore/Models/ThreadModels.swift \
  Sources/ThreadBeaconCore/Services/RolloutTailParser.swift \
  Sources/ThreadBeaconCore/Services/ThreadStatusLoader.swift \
  Tests/ThreadBeaconTests/RolloutTailParserTests.swift \
  Tests/ThreadBeaconTests/ThreadStatusLoaderTests.swift
git diff --cached --check
git commit -m "feat(sound): expose rollout completion events"
```

### Task 2: 建立基线、去重和批量合并模型

**Files:**

- Create: `Sources/ThreadBeaconCore/Models/SoundNotification.swift`
- Create: `Tests/ThreadBeaconTests/SoundNotificationTests.swift`
- Modify: `Tests/ThreadBeaconTests/TestRunner.swift`

- [ ] **Step 1: 写 tracker 失败测试**

新增四组测试：首次 observation 只建立基线；后续新完成产生一次事件；重复 observation
不再产生事件；同一批多个新完成只返回一个声音事件但把全部 ID 标为已见。

测试使用固定时间创建快照：

```swift
private func completedSnapshot(id: String, second: TimeInterval) -> ThreadSnapshot {
    let date = Date(timeIntervalSince1970: second)
    return ThreadSnapshot(
        id: id,
        title: id,
        status: .justCompleted,
        statusChangedAt: date,
        updatedAt: date,
        latestEventAt: date,
        completionEventAt: date
    )
}
```

核心断言：

```swift
var tracker = SoundNotificationTracker()
try expect(tracker.observe([completedSnapshot(id: "a", second: 10)], policy: .baseline).isEmpty,
           "baseline must stay silent")
let events = tracker.observe([completedSnapshot(id: "a", second: 20)], policy: .notify)
try expect(events.map(\.category) == [.done], "new completion should emit done")
try expect(tracker.observe([completedSnapshot(id: "a", second: 20)], policy: .notify).isEmpty,
           "same completion must not replay")
```

- [ ] **Step 2: 运行测试确认失败**

先把 `soundNotificationTests` 注册到 `TestRunner`，运行 `./script/test.sh`。

Expected: 编译失败，提示 `SoundNotificationTracker` 未定义。

- [ ] **Step 3: 实现纯 Swift 通知模型**

在新文件定义：

```swift
import Foundation

public enum SoundNotificationCategory: String, Equatable, Sendable {
    case done
    case attention
    case warning
    case failure
    case interrupted
}

public enum RefreshNotificationPolicy: Equatable, Sendable {
    case baseline
    case notify
}

public struct SoundNotificationEvent: Equatable, Sendable {
    public let id: String
    public let threadID: String
    public let category: SoundNotificationCategory
}

public struct SoundNotificationTracker: Sendable {
    public private(set) var seenEventIDs: [String]
    private let maximumHistoryCount: Int

    public init(initialSeenEventIDs: [String] = [], maximumHistoryCount: Int = 256) {
        self.maximumHistoryCount = max(1, maximumHistoryCount)
        self.seenEventIDs = Array(initialSeenEventIDs.suffix(self.maximumHistoryCount))
    }

    public mutating func observe(
        _ snapshots: [ThreadSnapshot],
        policy: RefreshNotificationPolicy
    ) -> [SoundNotificationEvent] {
        let seen = Set(seenEventIDs)
        let candidates = snapshots.compactMap { snapshot -> SoundNotificationEvent? in
            guard let completedAt = snapshot.completionEventAt else { return nil }
            let milliseconds = Int64((completedAt.timeIntervalSince1970 * 1_000).rounded())
            return SoundNotificationEvent(
                id: "done:\(snapshot.id):\(milliseconds)",
                threadID: snapshot.id,
                category: .done
            )
        }
        let newEvents = candidates.filter { !seen.contains($0.id) }
        seenEventIDs.append(contentsOf: newEvents.map(\.id))
        var uniqueIDs: [String] = []
        var uniqueSet = Set<String>()
        for id in seenEventIDs where uniqueSet.insert(id).inserted {
            uniqueIDs.append(id)
        }
        seenEventIDs = Array(uniqueIDs.suffix(maximumHistoryCount))
        guard policy == .notify, let first = newEvents.first else { return [] }
        return [first]
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `./script/test.sh`

Expected: tracker 的四组测试和原有测试全部通过。

- [ ] **Step 5: 提交通知模型**

```bash
git add Sources/ThreadBeaconCore/Models/SoundNotification.swift \
  Tests/ThreadBeaconTests/SoundNotificationTests.swift \
  Tests/ThreadBeaconTests/TestRunner.swift
git diff --cached --check
git commit -m "feat(sound): add completion notification tracker"
```

### Task 3: 把通知 tracker 接入 Store 和刷新语义

**Files:**

- Modify: `Sources/ThreadBeaconCore/Stores/ThreadStatusStore.swift`
- Modify: `Sources/ThreadBeacon/Views/ContentView.swift`
- Modify: `Tests/ThreadBeaconTests/ThreadStatusStoreTests.swift`

- [ ] **Step 1: 写 Store 失败测试**

使用两次可控 load，第一次返回完成时间 10，第二次返回完成时间 20。注入数组回调收集
事件和历史记录，依次调用 `.baseline`、`.notify`、`.notify`，断言只收到一次 `done`，
历史回调至少包含两个不同事件 ID。

```swift
await store.refresh(notificationPolicy: .baseline)
await store.refresh(notificationPolicy: .notify)
await store.refresh(notificationPolicy: .notify)
try expect(receivedEvents.count == 1, "only the new automatic completion should notify")
try expect(receivedEvents.first?.category == .done, "completion should use done category")
```

- [ ] **Step 2: 运行测试确认失败**

Run: `./script/test.sh`

Expected: 编译失败，提示 `refresh(notificationPolicy:)` 不存在。

- [ ] **Step 3: 接入 Store**

给 `ThreadStatusStore` 增加以下依赖和状态：

```swift
private var notificationTracker: SoundNotificationTracker
private let onNotification: @MainActor (SoundNotificationEvent) -> Void
private let onNotificationHistoryChange: @MainActor ([String]) -> Void
```

构造器提供保持旧调用兼容的默认值：

```swift
notificationTracker: SoundNotificationTracker = SoundNotificationTracker(),
onNotification: @escaping @MainActor (SoundNotificationEvent) -> Void = { _ in },
onNotificationHistoryChange: @escaping @MainActor ([String]) -> Void = { _ in }
```

把刷新签名改为：

```swift
public func refresh(notificationPolicy: RefreshNotificationPolicy = .baseline) async
```

成功加载且准备发布快照时执行：

```swift
let previousHistory = notificationTracker.seenEventIDs
let events = notificationTracker.observe(nextSnapshots, policy: notificationPolicy)
if notificationTracker.seenEventIDs != previousHistory {
    onNotificationHistoryChange(notificationTracker.seenEventIDs)
}
events.forEach(onNotification)
```

- [ ] **Step 4: 明确 ContentView 的刷新来源**

自动任务每次进入 active 状态时先基线刷新；两秒后的刷新才允许通知：

```swift
await store.refresh(notificationPolicy: .baseline)
while !Task.isCancelled {
    do { try await Task.sleep(for: .seconds(2)) } catch { return }
    await store.refresh(notificationPolicy: .notify)
}
```

手动刷新保持静音并推进水位：

```swift
Task { await store.refresh(notificationPolicy: .baseline) }
```

这同时保证 App 启动、恢复监听和暂停期间手动刷新都不会补播。

- [ ] **Step 5: 运行测试并提交**

Run: `./script/test.sh`

Expected: Store 回调测试、暂停模式测试和全部回归测试通过。

```bash
git add Sources/ThreadBeaconCore/Stores/ThreadStatusStore.swift \
  Sources/ThreadBeacon/Views/ContentView.swift \
  Tests/ThreadBeaconTests/ThreadStatusStoreTests.swift
git diff --cached --check
git commit -m "feat(sound): notify only on new automatic completions"
```

### Task 4: 生成并打包三个原创完成音

**Files:**

- Create: `Resources/Sounds/Done-Beacon.wav`
- Create: `Resources/Sounds/Done-Chime.wav`
- Create: `Resources/Sounds/Done-Pulse.wav`
- Create: `script/render_sound_assets.swift`
- Create: `script/generate_sound_assets.sh`
- Create: `script/verify_sound_assets.sh`
- Modify: `script/build_and_run.sh`

- [ ] **Step 1: 写资源验证脚本并确认失败**

`verify_sound_assets.sh` 应检查三个源文件和 App bundle 文件均存在、非空，并使用
`afinfo` 验证格式：

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for name in Done-Beacon Done-Chime Done-Pulse; do
    test -s "$ROOT/Resources/Sounds/$name.wav"
    test -s "$ROOT/dist/ThreadBeacon.app/Contents/Resources/Sounds/$name.wav"
    afinfo "$ROOT/Resources/Sounds/$name.wav" | rg -q "sample rate: 44100"
done
echo "Sound asset verification passed"
```

Run: `chmod +x script/verify_sound_assets.sh && ./script/verify_sound_assets.sh`

Expected: 因资源尚未生成而失败。

- [ ] **Step 2: 创建确定性 PCM 生成器**

`render_sound_assets.swift` 输出单声道、44.1 kHz、16-bit PCM WAV，并用短 attack/release
包络避免爆音。三个声音使用以下音符和时长，峰值不超过 0.28：

```swift
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: render_sound_assets.swift <output-directory>\n", stderr)
    exit(2)
}

let sampleRate = 44_100
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let designs: [(fileName: String, segments: [(frequency: Double, duration: Double)])] = [
    ("Done-Beacon.wav", [(659.25, 0.11), (987.77, 0.18)]),
    ("Done-Chime.wav", [(523.25, 0.10), (659.25, 0.10), (783.99, 0.20)]),
    ("Done-Pulse.wav", [(783.99, 0.08), (0, 0.04), (1046.50, 0.16)])
]

func appendASCII(_ value: String, to data: inout Data) {
    data.append(value.data(using: .ascii)!)
}

func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
}

for design in designs {
    var samples: [Int16] = []
    for segment in design.segments {
        let count = Int((segment.duration * Double(sampleRate)).rounded())
        for index in 0..<count {
            let elapsed = Double(index) / Double(sampleRate)
            let remaining = Double(count - index - 1) / Double(sampleRate)
            let attack = min(1, elapsed / 0.012)
            let release = min(1, remaining / 0.035)
            let envelope = max(0, min(attack, release))
            let wave = segment.frequency == 0
                ? 0
                : sin(2 * .pi * segment.frequency * elapsed) * envelope * 0.28
            samples.append(Int16((wave * Double(Int16.max)).rounded()))
        }
    }

    let payloadSize = UInt32(samples.count * MemoryLayout<Int16>.size)
    var wav = Data()
    appendASCII("RIFF", to: &wav)
    appendLittleEndian(UInt32(36) + payloadSize, to: &wav)
    appendASCII("WAVE", to: &wav)
    appendASCII("fmt ", to: &wav)
    appendLittleEndian(UInt32(16), to: &wav)
    appendLittleEndian(UInt16(1), to: &wav)
    appendLittleEndian(UInt16(1), to: &wav)
    appendLittleEndian(UInt32(sampleRate), to: &wav)
    appendLittleEndian(UInt32(sampleRate * 2), to: &wav)
    appendLittleEndian(UInt16(2), to: &wav)
    appendLittleEndian(UInt16(16), to: &wav)
    appendASCII("data", to: &wav)
    appendLittleEndian(payloadSize, to: &wav)
    for sample in samples {
        appendLittleEndian(sample, to: &wav)
    }
    try wav.write(to: outputDirectory.appendingPathComponent(design.fileName), options: .atomic)
}
```

`generate_sound_assets.sh` 使用以下内容：

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$ROOT/Resources/Sounds"
mkdir -p "$OUTPUT"
swift "$ROOT/script/render_sound_assets.swift" "$OUTPUT"
echo "Generated ThreadBeacon sound assets"
```

- [ ] **Step 3: 生成资源并加入 App bundle 构建**

Run: `chmod +x script/generate_sound_assets.sh && ./script/generate_sound_assets.sh`

在 `build_and_run.sh` 复制图标后加入：

```bash
SOUNDS="$ROOT/Resources/Sounds"
test -d "$SOUNDS"
mkdir -p "$RESOURCES/Sounds"
cp "$SOUNDS"/*.wav "$RESOURCES/Sounds/"
```

- [ ] **Step 4: 构建并验证资源**

Run: `./script/build_and_run.sh --verify && ./script/verify_sound_assets.sh`

Expected: App 保持运行，三个源 WAV 和 bundle WAV 均通过 44.1 kHz 校验。

- [ ] **Step 5: 提交声音资源管线**

```bash
git add Resources/Sounds script/render_sound_assets.swift \
  script/generate_sound_assets.sh script/verify_sound_assets.sh script/build_and_run.sh
git diff --cached --check
git commit -m "feat(sound): bundle original completion tones"
```

### Task 5: 播放服务、持久化设置和设置 popover

**Files:**

- Create: `Sources/ThreadBeacon/Support/CompletionSound.swift`
- Create: `Sources/ThreadBeacon/Support/SoundNotificationHistory.swift`
- Create: `Sources/ThreadBeacon/Support/SoundPlaybackService.swift`
- Create: `Sources/ThreadBeacon/Views/SoundSettingsView.swift`
- Modify: `Sources/ThreadBeacon/App/ThreadBeaconApp.swift`
- Modify: `Sources/ThreadBeacon/Views/ContentView.swift`

- [ ] **Step 1: 定义稳定偏好键和声音选项**

```swift
enum SoundPreferenceKeys {
    static let notificationsEnabled = "soundNotificationsEnabled"
    static let doneEnabled = "doneSoundEnabled"
    static let selectedDoneSound = "selectedDoneSound"
    static let seenEventIDs = "seenSoundNotificationEventIDs"
}

enum CompletionSound: String, CaseIterable, Identifiable {
    case beacon
    case chime
    case pulse

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .beacon: "Beacon"
        case .chime: "Chime"
        case .pulse: "Pulse"
        }
    }
    var fileName: String { "Done-\(displayName)" }
}
```

- [ ] **Step 2: 实现历史存储和播放器**

`SoundNotificationHistory` 只读写最多 256 个 ID 到 `UserDefaults`：

```swift
import Foundation

struct SoundNotificationHistory {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [String] {
        Array((defaults.stringArray(forKey: SoundPreferenceKeys.seenEventIDs) ?? []).suffix(256))
    }

    func save(_ eventIDs: [String]) {
        defaults.set(Array(eventIDs.suffix(256)), forKey: SoundPreferenceKeys.seenEventIDs)
    }
}
```

播放器保持当前 `NSSound` 强引用，并从
`Bundle.main.resourceURL/Sounds/<name>.wav` 加载：

```swift
@MainActor
final class SoundPlaybackService {
    private var activeSound: NSSound?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            SoundPreferenceKeys.notificationsEnabled: true,
            SoundPreferenceKeys.doneEnabled: true,
            SoundPreferenceKeys.selectedDoneSound: CompletionSound.beacon.rawValue
        ])
    }

    func play(_ event: SoundNotificationEvent) {
        guard event.category == .done,
              defaults.bool(forKey: SoundPreferenceKeys.notificationsEnabled),
              defaults.bool(forKey: SoundPreferenceKeys.doneEnabled) else { return }
        let raw = defaults.string(forKey: SoundPreferenceKeys.selectedDoneSound)
        play(CompletionSound(rawValue: raw ?? "") ?? .beacon)
    }

    func preview(_ sound: CompletionSound) { play(sound) }

    private func play(_ sound: CompletionSound) {
        guard let base = Bundle.main.resourceURL else { return }
        let url = base.appendingPathComponent("Sounds/\(sound.fileName).wav")
        activeSound?.stop()
        activeSound = NSSound(contentsOf: url, byReference: false)
        activeSound?.play()
    }
}
```

- [ ] **Step 3: 创建最小设置 popover**

`SoundSettingsView` 使用三个 `@AppStorage`，提供总开关、完成音开关、Picker 和试听：

```swift
struct SoundSettingsView: View {
    @AppStorage(SoundPreferenceKeys.notificationsEnabled) private var enabled = true
    @AppStorage(SoundPreferenceKeys.doneEnabled) private var doneEnabled = true
    @AppStorage(SoundPreferenceKeys.selectedDoneSound) private var selected = CompletionSound.beacon.rawValue
    let preview: (CompletionSound) -> Void

    var body: some View {
        Form {
            Toggle("启用提示音", isOn: $enabled)
            Toggle("任务完成", isOn: $doneEnabled).disabled(!enabled)
            Picker("完成声音", selection: $selected) {
                ForEach(CompletionSound.allCases) { sound in
                    Text(sound.displayName).tag(sound.rawValue)
                }
            }.disabled(!enabled || !doneEnabled)
            Button("试听") {
                preview(CompletionSound(rawValue: selected) ?? .beacon)
            }.disabled(!enabled || !doneEnabled)
        }
        .padding(16)
        .frame(width: 260)
    }
}
```

`ContentView` 增加齿轮按钮和 `@State private var isShowingSoundSettings = false`，用
`.popover(isPresented:)` 展示设置，不改变任务行高度。

- [ ] **Step 4: 在 App composition root 组装依赖**

`ThreadBeaconApp.init()` 创建 history 和 player，以已保存 ID 初始化 tracker；Store
历史变化时立即保存，事件出现时调用播放器。`ContentView` 获得 `previewSound` closure。

```swift
let history = SoundNotificationHistory()
let player = SoundPlaybackService()
let tracker = SoundNotificationTracker(initialSeenEventIDs: history.load())
_store = StateObject(wrappedValue: ThreadStatusStore(
    load: { try await loader.load(limit: 8) },
    notificationTracker: tracker,
    onNotification: { event in player.play(event) },
    onNotificationHistoryChange: { ids in history.save(ids) }
))
```

- [ ] **Step 5: 验证设置和播放**

Run: `./script/test.sh && ./script/build_and_run.sh --verify`

手工验收：三个声音均可试听；关闭总开关或完成开关后自动完成不发声；重启 App 保留
选择；重启面对既有完成事件不发声；暂停后完成的任务在恢复时不补播。

- [ ] **Step 6: 提交 App 集成**

```bash
git add Sources/ThreadBeacon/Support/CompletionSound.swift \
  Sources/ThreadBeacon/Support/SoundNotificationHistory.swift \
  Sources/ThreadBeacon/Support/SoundPlaybackService.swift \
  Sources/ThreadBeacon/Views/SoundSettingsView.swift \
  Sources/ThreadBeacon/App/ThreadBeaconApp.swift \
  Sources/ThreadBeacon/Views/ContentView.swift
git diff --cached --check
git commit -m "feat(sound): play configurable done notifications"
```

### Task 6: 同步文档并完成全量验收

**Files:**

- Modify: `README.md`
- Modify: `README-EN.md`
- Modify: `PRIVACY.md`
- Modify: `ROADMAP.md`

- [ ] **Step 1: 更新中英文 README**

明确写出：只通知主任务；自动重试、错误和授权声音尚未启用；启动、手动刷新和恢复监听
不补播；设置 popover 可关闭、选音和试听；三个 WAV 为项目确定性生成资源。

- [ ] **Step 2: 更新隐私与 Roadmap**

`PRIVACY.md` 增加本地持久化的声音偏好和最多 256 个不含标题/正文的事件 ID；
`ROADMAP.md` 把可靠 Done 提示标记为已完成，把 app-server POC 和其他三类声音保留为研究。

- [ ] **Step 3: 运行全部自动检查**

```bash
./script/test.sh
./script/build_and_run.sh --verify
./script/verify_sound_assets.sh
./script/verify_app_icon.sh
./script/verify_app_identity.sh
git diff --check
```

Expected: 全部测试通过；App、图标、身份和声音资源验证通过；diff 无空白错误。

- [ ] **Step 4: 运行 Markdown lint**

从父仓库 `/Users/songlinli/Downloads/CodexClawProj` 运行：

```bash
npm run lint:md -- \
  poc/codex-thread-status-macos/README.md \
  poc/codex-thread-status-macos/README-EN.md \
  poc/codex-thread-status-macos/PRIVACY.md \
  poc/codex-thread-status-macos/ROADMAP.md
```

Expected: `Summary: 0 error(s)`。

- [ ] **Step 5: 提交文档 checkpoint**

```bash
git add README.md README-EN.md PRIVACY.md ROADMAP.md
git diff --cached --check
git commit -m "docs(sound): document done notifications"
```

- [ ] **Step 6: 最终工作树检查**

Run: `git status --short --branch`

Expected: 工作树无未提交变更；只显示本地 `main` 相对 `origin/main` 的 ahead 数量。不要
push，除非 Lee 另行明确要求。
