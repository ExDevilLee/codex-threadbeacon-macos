import SwiftUI

struct SoundSettingsView: View {
    @AppStorage(SoundPreferenceKeys.notificationsEnabled) private var enabled = true
    @AppStorage(SoundPreferenceKeys.doneEnabled) private var doneEnabled = true
    @AppStorage(SoundPreferenceKeys.selectedDoneSound)
    private var selectedDone = CompletionSound.chime.rawValue
    @AppStorage(SoundPreferenceKeys.warningEnabled) private var warningEnabled = true
    @AppStorage(SoundPreferenceKeys.selectedWarningSound)
    private var selectedWarning = CompletionSound.alert.rawValue

    let preview: (CompletionSound) -> Void

    var body: some View {
        Form {
            Toggle("启用提示音", isOn: $enabled)
            Toggle("任务完成", isOn: $doneEnabled)
                .disabled(!enabled)
            Picker("完成声音", selection: $selectedDone) {
                ForEach(CompletionSound.allCases) { sound in
                    Text(sound.displayName).tag(sound.rawValue)
                }
            }
            .disabled(!enabled || !doneEnabled)
            Button("试听完成声音") {
                preview(CompletionSound(rawValue: selectedDone) ?? .chime)
            }
            .disabled(!enabled || !doneEnabled)

            Divider()

            Toggle("429/503 服务异常", isOn: $warningEnabled)
                .disabled(!enabled)
            Picker("异常声音", selection: $selectedWarning) {
                ForEach(CompletionSound.allCases) { sound in
                    Text(sound.displayName).tag(sound.rawValue)
                }
            }
            .disabled(!enabled || !warningEnabled)
            Button("试听异常声音") {
                preview(CompletionSound(rawValue: selectedWarning) ?? .alert)
            }
            .disabled(!enabled || !warningEnabled)
        }
        .padding(16)
        .frame(width: 280)
    }
}
