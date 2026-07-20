import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SoundSettingsView: View {
    @Environment(\.locale) private var locale
    @AppStorage(SoundPreferenceKeys.notificationsEnabled) private var enabled = true
    @AppStorage(SoundPreferenceKeys.doneEnabled) private var doneEnabled = true
    @AppStorage(SoundPreferenceKeys.selectedDoneSound)
    private var selectedDone = CompletionSound.chime.rawValue
    @AppStorage(SoundPreferenceKeys.customDoneSoundURL)
    private var customDoneSoundURL = ""
    @AppStorage(SoundPreferenceKeys.warningEnabled) private var warningEnabled = true
    @AppStorage(SoundPreferenceKeys.selectedWarningSound)
    private var selectedWarning = CompletionSound.alert.rawValue
    @AppStorage(SoundPreferenceKeys.customWarningSoundURL)
    private var customWarningSoundURL = ""

    let preview: (SoundSource) -> Void

    var body: some View {
        Form {
            Section("全局") {
                Toggle("启用提示音", isOn: $enabled)
            }

            Section("任务完成") {
                Toggle("播放完成提示音", isOn: $doneEnabled)
                    .disabled(!enabled)
                Picker("完成声音", selection: $selectedDone) {
                    ForEach(CompletionSound.allCases) { sound in
                        Text(sound.displayName).tag(sound.rawValue)
                    }
                }
                .disabled(!enabled || !doneEnabled)
                customSoundControls(path: $customDoneSoundURL)
                    .disabled(!enabled || !doneEnabled)
                HStack {
                    Spacer()
                    Button("试听完成声音") {
                        preview(doneSource)
                    }
                    Spacer()
                }
                .disabled(!enabled || !doneEnabled)
            }

            Section("服务异常") {
                Toggle("播放服务异常提示音", isOn: $warningEnabled)
                    .disabled(!enabled)
                Picker("异常声音", selection: $selectedWarning) {
                    ForEach(CompletionSound.allCases) { sound in
                        Text(sound.displayName).tag(sound.rawValue)
                    }
                }
                .disabled(!enabled || !warningEnabled)
                customSoundControls(path: $customWarningSoundURL)
                    .disabled(!enabled || !warningEnabled)
                HStack {
                    Spacer()
                    Button("试听异常声音") {
                        preview(warningSource)
                    }
                    Spacer()
                }
                .disabled(!enabled || !warningEnabled)
            }
            Text("Fupicat Notification 和 Bassguitar Notification 来自 Freesound，采用 CC0 许可，仅作为可选声音，不是默认提示音。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var doneSource: SoundSource {
        validCustomURL(customDoneSoundURL).map(SoundSource.custom)
            ?? .builtIn(CompletionSound(rawValue: selectedDone) ?? .chime)
    }

    private var warningSource: SoundSource {
        validCustomURL(customWarningSoundURL).map(SoundSource.custom)
            ?? .builtIn(CompletionSound(rawValue: selectedWarning) ?? .alert)
    }

    @ViewBuilder
    private func customSoundControls(path: Binding<String>) -> some View {
        HStack(spacing: 8) {
            if let url = validCustomURL(path.wrappedValue) {
                Text(url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(url.path)

                Button {
                    preview(.custom(url))
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .help("试听自定义声音")
                .accessibilityLabel("试听自定义声音")
            } else if path.wrappedValue.isEmpty {
                Text("未选择自定义声音")
                    .foregroundStyle(.secondary)
            } else {
                Text("自定义文件不可用或格式不受支持，将回退内置声音")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !path.wrappedValue.isEmpty {
                Button {
                    path.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("清除")
                .accessibilityLabel("清除")
            }

            Spacer(minLength: 4)

            Button {
                chooseAudio(path: path)
            } label: {
                Label("选择音频…", systemImage: "folder")
            }
        }
        .font(.caption)
    }

    private func validCustomURL(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.isReadableFile(atPath: url.path),
              NSSound(contentsOf: url, byReference: false) != nil else {
            return nil
        }
        return url
    }

    private func chooseAudio(path: Binding<String>) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = AppLocalization.string("选择", locale: locale)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path.wrappedValue = url.path
    }
}
