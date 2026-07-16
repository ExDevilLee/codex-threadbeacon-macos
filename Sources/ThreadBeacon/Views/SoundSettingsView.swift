import SwiftUI

struct SoundSettingsView: View {
    @AppStorage(SoundPreferenceKeys.notificationsEnabled) private var enabled = true
    @AppStorage(SoundPreferenceKeys.doneEnabled) private var doneEnabled = true
    @AppStorage(SoundPreferenceKeys.selectedDoneSound)
    private var selected = CompletionSound.beacon.rawValue

    let preview: (CompletionSound) -> Void

    var body: some View {
        Form {
            Toggle("启用提示音", isOn: $enabled)
            Toggle("任务完成", isOn: $doneEnabled)
                .disabled(!enabled)
            Picker("完成声音", selection: $selected) {
                ForEach(CompletionSound.allCases) { sound in
                    Text(sound.displayName).tag(sound.rawValue)
                }
            }
            .disabled(!enabled || !doneEnabled)
            Button("试听") {
                preview(CompletionSound(rawValue: selected) ?? .beacon)
            }
            .disabled(!enabled || !doneEnabled)
        }
        .padding(16)
        .frame(width: 260)
    }
}
