import ThreadBeaconCore
import SwiftUI

struct ThreadBeaconSettingsView: View {
    @ObservedObject var languageStore: AppLanguageStore
    @ObservedObject var launchAtLoginStore: LaunchAtLoginStore
    let previewSound: (CompletionSound) -> Void

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
        }
        .frame(width: 440, height: 320)
        .scenePadding()
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
