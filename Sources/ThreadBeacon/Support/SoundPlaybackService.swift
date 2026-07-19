import AppKit
import ThreadBeaconCore

@MainActor
final class SoundPlaybackService {
    private var activeSound: NSSound?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            SoundPreferenceKeys.notificationsEnabled: true,
            SoundPreferenceKeys.doneEnabled: true,
            SoundPreferenceKeys.selectedDoneSound: CompletionSound.chime.rawValue,
            SoundPreferenceKeys.customDoneSoundURL: "",
            SoundPreferenceKeys.warningEnabled: true,
            SoundPreferenceKeys.selectedWarningSound: CompletionSound.alert.rawValue,
            SoundPreferenceKeys.customWarningSoundURL: ""
        ])
    }

    func play(_ event: SoundNotificationEvent) {
        guard defaults.bool(forKey: SoundPreferenceKeys.notificationsEnabled) else {
            return
        }
        switch event.category {
        case .done:
            guard defaults.bool(forKey: SoundPreferenceKeys.doneEnabled) else { return }
            let raw = defaults.string(forKey: SoundPreferenceKeys.selectedDoneSound)
            play(preferredSource(
                customKey: SoundPreferenceKeys.customDoneSoundURL,
                fallback: .builtIn(CompletionSound(rawValue: raw ?? "") ?? .chime)
            ))
        case .warning, .failure:
            guard defaults.bool(forKey: SoundPreferenceKeys.warningEnabled) else { return }
            let raw = defaults.string(forKey: SoundPreferenceKeys.selectedWarningSound)
            play(preferredSource(
                customKey: SoundPreferenceKeys.customWarningSoundURL,
                fallback: .builtIn(CompletionSound(rawValue: raw ?? "") ?? .alert)
            ))
        case .attention, .interrupted:
            return
        }
    }

    func preview(_ source: SoundSource) {
        play(source)
    }

    private func preferredSource(customKey: String, fallback: SoundSource) -> SoundSource {
        guard let path = defaults.string(forKey: customKey), !path.isEmpty else {
            return fallback
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.isReadableFile(atPath: url.path),
              NSSound(contentsOf: url, byReference: false) != nil else {
            return fallback
        }
        return .custom(url)
    }

    private func play(_ source: SoundSource) {
        let url: URL
        switch source {
        case .builtIn(let sound):
            guard let base = Bundle.main.resourceURL else { return }
            url = base.appendingPathComponent("Sounds/\(sound.fileName).wav")
        case .custom(let customURL):
            url = customURL
        }
        activeSound?.stop()
        activeSound = NSSound(contentsOf: url, byReference: false)
        activeSound?.play()
    }
}
