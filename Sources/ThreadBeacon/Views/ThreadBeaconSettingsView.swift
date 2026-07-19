import ThreadBeaconCore
import SwiftUI

struct ThreadBeaconSettingsView: View {
    let previewSound: (CompletionSound) -> Void

    var body: some View {
        TabView {
            GeneralSettingsView()
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
    @AppStorage(DisplayPreferenceKeys.refreshIntervalSeconds)
    private var refreshIntervalSeconds = DisplaySettings.defaultRefreshIntervalSeconds
    @AppStorage(DisplayPreferenceKeys.maximumTaskCount)
    private var maximumTaskCount = DisplaySettings.defaultMaximumTaskCount

    var body: some View {
        Form {
            Section("任务监听") {
                Picker("刷新间隔", selection: $refreshIntervalSeconds) {
                    ForEach(DisplaySettings.supportedRefreshIntervalSeconds, id: \.self) { seconds in
                        Text("\(seconds) 秒").tag(seconds)
                    }
                }

                Picker("最大显示任务数", selection: $maximumTaskCount) {
                    ForEach(DisplaySettings.supportedMaximumTaskCounts, id: \.self) { count in
                        Text("\(count) 个").tag(count)
                    }
                }
            }

            Text("修改后立即生效；暂停监听时仍可手动刷新。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
