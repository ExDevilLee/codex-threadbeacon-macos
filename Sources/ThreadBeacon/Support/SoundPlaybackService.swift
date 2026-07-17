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
            SoundPreferenceKeys.selectedDoneSound: CompletionSound.beacon.rawValue,
            SoundPreferenceKeys.warningEnabled: true,
            SoundPreferenceKeys.selectedWarningSound: CompletionSound.chime.rawValue
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
            play(CompletionSound(rawValue: raw ?? "") ?? .beacon)
        case .warning, .failure:
            guard defaults.bool(forKey: SoundPreferenceKeys.warningEnabled) else { return }
            let raw = defaults.string(forKey: SoundPreferenceKeys.selectedWarningSound)
            play(CompletionSound(rawValue: raw ?? "") ?? .chime)
        case .attention, .interrupted:
            return
        }
    }

    func preview(_ sound: CompletionSound) {
        play(sound)
    }

    private func play(_ sound: CompletionSound) {
        guard let base = Bundle.main.resourceURL else { return }
        let url = base.appendingPathComponent("Sounds/\(sound.fileName).wav")
        activeSound?.stop()
        activeSound = NSSound(contentsOf: url, byReference: false)
        activeSound?.play()
    }
}
