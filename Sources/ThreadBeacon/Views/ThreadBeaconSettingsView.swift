import ThreadBeaconCore
import SwiftUI

struct ThreadBeaconSettingsView: View {
    @ObservedObject var languageStore: AppLanguageStore
    @ObservedObject var launchAtLoginStore: LaunchAtLoginStore
    let previewSound: (SoundSource) -> Void
    @ObservedObject var autoRecoveryLogStore: AutoRecoveryLogStore
    @ObservedObject var autoRecoverySettingsStore: AutoRecoverySettingsStore
    @ObservedObject var accessibilityPermissionStore: AccessibilityPermissionStore
    @ObservedObject var compactionHookSettingsStore: CompactionHookSettingsStore

    var body: some View {
        TabView {
            GeneralSettingsView(
                languageStore: languageStore,
                launchAtLoginStore: launchAtLoginStore,
                compactionHookSettingsStore: compactionHookSettingsStore
            )
                .tabItem {
                    Label("通用", systemImage: "gearshape")
                }

            SoundSettingsView(preview: previewSound)
                .tabItem {
                    Label("提示音", systemImage: "speaker.wave.2")
                }

            AutoRecoverySettingsView(
                settingsStore: autoRecoverySettingsStore,
                logStore: autoRecoveryLogStore,
                accessibilityPermissionStore: accessibilityPermissionStore
            )
                .tabItem {
                    Label("自动恢复", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                }
        }
        .frame(width: 500, height: 560)
        .scenePadding()
    }
}

#if DEBUG
struct AutoRecoveryDiagnosticsView: View {
    @ObservedObject var accessibilityPermissionStore: AccessibilityPermissionStore
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var targetThreadID = ""
    @State private var showingSendConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            accessibilityPermissionSection
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

            Text(localized("以下诊断功能仅用于本地开发验证，不会出现在 Release 构建中。"))
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
                            AccessibilityTargetSelectionPresentation.message(
                                for: result,
                                locale: locale
                            ),
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

    private func recoverySendText(_ result: AccessibilityRecoverySendResult) -> String {
        switch result {
        case let .targetSelectionFailed(selectionResult):
            AccessibilityTargetSelectionPresentation.message(
                for: selectionResult,
                locale: locale
            )
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
#endif

private struct GeneralSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @AppStorage(DisplayPreferenceKeys.refreshIntervalSeconds)
    private var refreshIntervalSeconds = DisplaySettings.defaultRefreshIntervalSeconds
    @AppStorage(DisplayPreferenceKeys.maximumTaskCount)
    private var maximumTaskCount = DisplaySettings.defaultMaximumTaskCount
    @AppStorage(DisplayPreferenceKeys.appTheme)
    private var appThemeRawValue = AppTheme.defaultValue.rawValue
    @AppStorage(DisplayPreferenceKeys.colorBlindSafeStatusIndicators)
    private var usesColorBlindSafeStatusIndicators = DisplaySettings.defaultColorBlindSafeStatusIndicators
    @ObservedObject var languageStore: AppLanguageStore
    @ObservedObject var launchAtLoginStore: LaunchAtLoginStore
    @ObservedObject var compactionHookSettingsStore: CompactionHookSettingsStore

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

                Toggle(
                    "色盲安全状态标识",
                    isOn: $usesColorBlindSafeStatusIndicators
                )

                Text("同时使用颜色、形状和文字区分任务状态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            CompactionHookSettingsSection(store: compactionHookSettingsStore)

            Text("修改后立即生效；暂停监听时仍可手动刷新。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLoginStore.refresh()
            compactionHookSettingsStore.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                launchAtLoginStore.refresh()
                compactionHookSettingsStore.refresh()
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
