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
            SoundPreferenceKeys.selectedDoneSound: CompletionSound.beacon.rawValue
        ])
    }

    func play(_ event: SoundNotificationEvent) {
        guard event.category == .done,
              defaults.bool(forKey: SoundPreferenceKeys.notificationsEnabled),
              defaults.bool(forKey: SoundPreferenceKeys.doneEnabled) else {
            return
        }
        let raw = defaults.string(forKey: SoundPreferenceKeys.selectedDoneSound)
        play(CompletionSound(rawValue: raw ?? "") ?? .beacon)
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
