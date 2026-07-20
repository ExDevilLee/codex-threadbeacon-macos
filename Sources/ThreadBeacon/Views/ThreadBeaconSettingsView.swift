import ThreadBeaconCore
import SwiftUI

struct ThreadBeaconSettingsView: View {
    @ObservedObject var languageStore: AppLanguageStore
    @ObservedObject var launchAtLoginStore: LaunchAtLoginStore
    let previewSound: (SoundSource) -> Void
    @ObservedObject var autoRecoveryLogStore: AutoRecoveryLogStore
    @ObservedObject var accessibilityPermissionStore: AccessibilityPermissionStore

    var body: some View {
        TabView {
            GeneralSettingsView(languageStore: languageStore, launchAtLoginStore: launchAtLoginStore)
                .tabItem {
                    Label("通用", systemImage: "gearshape")
                }

            SoundSettingsView(preview: previewSound)
                .tabItem {
                    Label("提示音", systemImage: "speaker.wave.2")
                }

            AutoRecoveryLogView(
                store: autoRecoveryLogStore,
                accessibilityPermissionStore: accessibilityPermissionStore
            )
                .tabItem {
                    Label("自动恢复", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                }
        }
        .frame(width: 460, height: 460)
        .scenePadding()
    }
}

private struct AutoRecoveryLogView: View {
    @ObservedObject var store: AutoRecoveryLogStore
    @ObservedObject var accessibilityPermissionStore: AccessibilityPermissionStore
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var targetThreadID = ""
    @State private var showingSendConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            accessibilityPermissionSection

            Divider()

            HStack {
                Text(localized("异常自动恢复记录"))
                    .font(.headline)
                Spacer()
                Button(localized("清空记录")) {
                    store.clear()
                }
                .disabled(store.entries.isEmpty)
            }

            if store.entries.isEmpty {
                ContentUnavailableView(
                    localized("暂无自动恢复记录"),
                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                    description: Text(localized("检测到新的异常后，处理结果会显示在这里。"))
                )
            } else {
                List(store.entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(entry.status.localizedTitle(locale: locale), systemImage: entry.status.systemImage)
                                .foregroundStyle(entry.status.color)
                            Spacer()
                            Text(entry.occurredAt, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(AppLocalization.formatted("会话 %@", locale: locale, entry.threadID))
                            .font(.caption.monospaced())
                        Text(entry.incident)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(entry.prompt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let detail = entry.detail {
                            Text(AppLocalization.userFacing(detail, locale: locale))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            accessibilityPermissionStore.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                accessibilityPermissionStore.refresh()
            }
        }
    }

    private var accessibilityPermissionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(localized("辅助功能权限"))
                    .font(.headline)
                Spacer()
                Label(
                    localized(accessibilityPermissionStore.isAuthorized ? "已授权" : "未授权"),
                    systemImage: accessibilityPermissionStore.isAuthorized
                        ? "checkmark.circle.fill"
                        : "hand.raised.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(accessibilityPermissionStore.isAuthorized ? .green : .secondary)
            }

            Text(localized(accessibilityPermissionStore.isAuthorized
                ? "已授权；当前仅用于继续验证，自动发送仍然关闭。"
                : "ThreadBeacon 只有在获得此权限后，才可能控制 Codex App 输入框。当前自动发送仍然关闭。"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if !accessibilityPermissionStore.isAuthorized {
                HStack {
                    Button(localized("请求授权")) {
                        accessibilityPermissionStore.requestAuthorization()
                    }
                    Button(localized("打开辅助功能设置")) {
                        accessibilityPermissionStore.openSystemSettings()
                    }
                }
            } else {
                HStack {
                    Button(localized("验证 Codex 只读访问")) {
                        accessibilityPermissionStore.runReadOnlyDiagnostic()
                    }
                    .disabled(accessibilityPermissionStore.isChecking)

                    if accessibilityPermissionStore.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let result = accessibilityPermissionStore.diagnosticResult {
                    Label(
                        diagnosticText(result),
                        systemImage: result.isReady
                            ? "checkmark.shield.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(result.isReady ? .green : .secondary)
                }

                if accessibilityPermissionStore.diagnosticResult?.isReady == true {
                    Button(localized("验证当前 Codex 输入框（不发送）")) {
                        accessibilityPermissionStore.runComposerValidation()
                    }
                    .disabled(accessibilityPermissionStore.isChecking)

                    Text(localized("会短暂写入固定提示词，回读后立即清空；已有草稿时拒绝执行。"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let result = accessibilityPermissionStore.composerValidationResult {
                        Label(
                            composerValidationText(result),
                            systemImage: result.isVerified
                                ? "checkmark.shield.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(result.isVerified ? .green : .secondary)
                    }

                    Divider()

                    TextField(localized("目标任务 ID"), text: $targetThreadID)
                        .textFieldStyle(.roundedBorder)

                    Button(localized("切换并验证目标任务（不发送）")) {
                        accessibilityPermissionStore.runTargetSelection(
                            threadID: targetThreadID
                        )
                    }
                    .disabled(
                        accessibilityPermissionStore.isChecking
                            || targetThreadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    Text(localized("使用任务 ID 打开目标任务，并在 Codex 标题栏核对 rename 名称；当前任务有草稿时会停止。"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let result = accessibilityPermissionStore.targetSelectionResult {
                        Label(
                            targetSelectionText(result),
                            systemImage: result.isSelected
                                ? "checkmark.shield.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(result.isSelected ? .green : .secondary)
                    }

                    Button(localized("发送恢复提示并验证（测试）")) {
                        showingSendConfirmation = true
                    }
                    .disabled(
                        accessibilityPermissionStore.isChecking
                            || !accessibilityPermissionStore.canSend(to: targetThreadID)
                    )
                    .confirmationDialog(
                        localized("确认向目标任务发送恢复提示？"),
                        isPresented: $showingSendConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button(localized("发送并验证"), role: .destructive) {
                            Task {
                                await accessibilityPermissionStore.runRecoverySend(
                                    threadID: targetThreadID
                                )
                            }
                        }
                        Button(localized("取消"), role: .cancel) {}
                    } message: {
                        Text(localized("将发送固定提示词“刚才中断了，请继续未完成的任务”。发送后不会自动重试。"))
                    }

                    if let result = accessibilityPermissionStore.recoverySendResult {
                        Label(
                            recoverySendText(result),
                            systemImage: result.isVerified
                                ? "checkmark.shield.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(result.isVerified ? .green : .orange)
                    }
                }
            }
        }
    }

    private func diagnosticText(_ result: AccessibilityDiagnosticResult) -> String {
        switch result {
        case .notAuthorized:
            localized("只读验证失败：尚未获得辅助功能权限。")
        case .codexNotRunning:
            localized("只读验证失败：Codex App 未运行。")
        case .scanFailed:
            localized("只读验证失败：无法读取 Codex App 的辅助功能结构。")
        case let .ready(windowCount, textAreaCount, visitedNodeCount):
            String(
                format: localized("只读验证通过：%lld 个窗口，%lld 个输入框，访问 %lld 个节点。"),
                Int64(windowCount),
                Int64(textAreaCount),
                Int64(visitedNodeCount)
            )
        }
    }

    private func composerValidationText(
        _ result: AccessibilityComposerValidationResult
    ) -> String {
        switch result {
        case .notAuthorized:
            localized("输入框验证失败：尚未获得辅助功能权限。")
        case .codexNotRunning:
            localized("输入框验证失败：Codex App 未运行。")
        case let .composerNotUnique(count):
            String(
                format: localized("输入框验证失败：找到 %lld 个输入框。"),
                Int64(count)
            )
        case .composerNotEmpty:
            localized("输入框验证已停止：检测到已有草稿。")
        case .composerNotSettable:
            localized("输入框验证失败：当前输入框不可写。")
        case .writeFailed:
            localized("输入框验证失败：无法写入固定提示词。")
        case .readbackFailed:
            localized("输入框验证失败：写入后的回读不一致，输入框已清空。")
        case .cleanupFailed:
            localized("输入框验证失败：无法确认输入框已清空。")
        case .verified:
            localized("输入框验证通过：写入、回读和清空均成功，未发送消息。")
        }
    }

    private func targetSelectionText(
        _ result: AccessibilityTargetSelectionResult
    ) -> String {
        switch result {
        case .notAuthorized:
            localized("目标任务验证失败：尚未获得辅助功能权限。")
        case .codexNotRunning:
            localized("目标任务验证失败：Codex App 未运行。")
        case .codexInteractionInProgress:
            localized("目标任务验证已停止：Codex 正在前台，可能存在用户输入。")
        case .invalidThreadID:
            localized("目标任务验证失败：任务 ID 为空。")
        case .sessionIndexUnavailable:
            localized("目标任务验证失败：无法读取 Codex 任务索引。")
        case .titleUnavailable:
            localized("目标任务验证失败：未找到该任务的 rename 标题。")
        case .sourceComposerNotEmpty:
            localized("目标任务验证已停止：当前 Codex 任务输入框已有草稿。")
        case let .sourceComposerNotUnique(count):
            String(
                format: localized("目标任务验证已停止：切换前找到 %lld 个输入框。"),
                Int64(count)
            )
        case .sourceComposerValueUnavailable:
            localized("目标任务验证已停止：无法确认当前 Codex 输入框是否为空。")
        case .selectionFailed:
            localized("目标任务验证失败：无法切换 Codex 任务。")
        case let .targetHeaderNotUnique(count):
            String(
                format: localized("目标任务验证失败：标题栏身份匹配数为 %lld。"),
                Int64(count)
            )
        case let .composerNotUnique(count):
            String(
                format: localized("目标任务验证失败：切换后找到 %lld 个输入框。"),
                Int64(count)
            )
        case .selected:
            localized("目标任务验证通过：已按 ID 打开并确认 rename 名称，未发送消息。")
        }
    }

    private func recoverySendText(_ result: AccessibilityRecoverySendResult) -> String {
        switch result {
        case let .targetSelectionFailed(selectionResult):
            targetSelectionText(selectionResult)
        case .rolloutUnavailable:
            localized("发送验证失败：无法读取目标任务 rollout。")
        case .composerNotEmpty:
            localized("发送验证已停止：目标输入框已有草稿。")
        case .composerNotSettable:
            localized("发送验证失败：目标输入框不可写。")
        case .writeFailed:
            localized("发送验证失败：无法写入固定提示词。")
        case .readbackFailed:
            localized("发送验证失败：提示词回读不一致，输入框已清空。")
        case .cleanupFailed:
            localized("发送验证失败：无法确认输入框已清空。")
        case let .sendButtonNotUnique(count):
            String(
                format: localized("发送验证失败：找到 %lld 个发送按钮候选，输入框已清空。"),
                Int64(count)
            )
        case .sendFailed:
            localized("发送验证失败：发送按钮执行失败，输入框已清空。")
        case .sentUnconfirmed:
            localized("已触发发送，但 rollout 未在时限内确认；不会自动重试。")
        case .verified:
            localized("发送验证通过：rollout 已出现新的用户消息和任务启动事件。")
        }
    }

    private func localized(_ source: String) -> String {
        AppLocalization.string(source, locale: locale)
    }
}

private extension AutoRecoveryLogStatus {
    var systemImage: String {
        switch self {
        case .sending: "arrow.triangle.2.circlepath"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .skipped: "hand.raised.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .sending: .orange
        case .succeeded: .green
        case .failed: .red
        case .skipped: .secondary
        }
    }

    func localizedTitle(locale: Locale) -> String {
        let source: String
        switch self {
        case .sending: source = "发送中"
        case .succeeded: source = "已发送"
        case .failed: source = "发送失败"
        case .skipped: source = "未发送"
        }
        return AppLocalization.string(source, locale: locale)
    }
}

private struct GeneralSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @AppStorage(DisplayPreferenceKeys.refreshIntervalSeconds)
    private var refreshIntervalSeconds = DisplaySettings.defaultRefreshIntervalSeconds
    @AppStorage(DisplayPreferenceKeys.maximumTaskCount)
    private var maximumTaskCount = DisplaySettings.defaultMaximumTaskCount
    @AppStorage(DisplayPreferenceKeys.appTheme)
    private var appThemeRawValue = AppTheme.defaultValue.rawValue
    @ObservedObject var languageStore: AppLanguageStore
    @ObservedObject var launchAtLoginStore: LaunchAtLoginStore

    var body: some View {
        Form {
            Section("语言") {
                Picker("App 语言", selection: languageBinding) {
                    Text("跟随系统").tag(AppLanguage.system.rawValue)
                    // Language names use their native spelling so the choice stays recognizable
                    // even when the surrounding Settings UI is displayed in English.
                    Text(verbatim: "简体中文").tag(AppLanguage.simplifiedChinese.rawValue)
                    Text("English").tag(AppLanguage.english.rawValue)
                }

                Text("系统语言不是中文或英文时，默认使用 English。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("外观") {
                Picker("主题", selection: $appThemeRawValue) {
                    Text("跟随系统").tag(AppTheme.system.rawValue)
                    Text("浅色").tag(AppTheme.light.rawValue)
                    Text("深色").tag(AppTheme.dark.rawValue)
                }
            }

            Section("任务监听") {
                Picker("刷新间隔", selection: $refreshIntervalSeconds) {
                    ForEach(DisplaySettings.supportedRefreshIntervalSeconds, id: \.self) { seconds in
                        Text(AppLocalization.formatted("%lld 秒", locale: locale, seconds)).tag(seconds)
                    }
                }

                Picker("最大显示任务数", selection: $maximumTaskCount) {
                    ForEach(DisplaySettings.supportedMaximumTaskCounts, id: \.self) { count in
                        Text(AppLocalization.formatted("%lld 个", locale: locale, count)).tag(count)
                    }
                }
            }

            Section("启动") {
                Toggle("登录时启动", isOn: launchAtLoginBinding)
                    .disabled(launchAtLoginStore.status == .notFound)

                launchAtLoginStatusDetail
            }

            Text("修改后立即生效；暂停监听时仍可手动刷新。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLoginStore.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                launchAtLoginStore.refresh()
            }
        }
        .alert("登录启动设置失败", isPresented: launchAtLoginErrorIsPresented) {
            Button("好") {
                launchAtLoginStore.dismissError()
            }
        } message: {
            Text(AppLocalization.userFacing(
                launchAtLoginStore.errorMessage ?? "未知错误",
                locale: locale
            ))
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginStore.status.isRegistered },
            set: { launchAtLoginStore.setEnabled($0) }
        )
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { languageStore.rawValue },
            set: { rawValue in
                languageStore.setLanguage(AppLanguage(rawValue: rawValue) ?? .system)
            }
        )
    }

    @ViewBuilder
    private var launchAtLoginStatusDetail: some View {
        switch launchAtLoginStore.status {
        case .notRegistered:
            Text("关闭。开启后，macOS 会在用户登录时启动当前 App bundle。")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .enabled:
            Label("已由 macOS 启用", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .requiresApproval:
            VStack(alignment: .leading, spacing: 8) {
                Label("需要在系统设置的“登录项”中允许", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("打开登录项设置") {
                    launchAtLoginStore.openSystemSettings()
                }
            }
        case .notFound:
            Label("当前 App bundle 无法注册为登录项", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }

        Text("开发版位于 dist 目录；移动、删除或重新签名 App 后，可能需要重新开启。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var launchAtLoginErrorIsPresented: Binding<Bool> {
        Binding(
            get: { launchAtLoginStore.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    launchAtLoginStore.dismissError()
                }
            }
        )
    }
}
