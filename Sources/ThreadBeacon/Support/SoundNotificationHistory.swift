import Foundation

struct SoundNotificationHistory {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [String] {
        Array((defaults.stringArray(forKey: SoundPreferenceKeys.seenEventIDs) ?? []).suffix(256))
    }

    func save(_ eventIDs: [String]) {
        defaults.set(Array(eventIDs.suffix(256)), forKey: SoundPreferenceKeys.seenEventIDs)
    }
}
