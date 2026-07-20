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
