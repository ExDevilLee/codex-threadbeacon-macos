import Foundation

enum SoundPreferenceKeys {
    static let notificationsEnabled = "soundNotificationsEnabled"
    static let doneEnabled = "doneSoundEnabled"
    static let selectedDoneSound = "selectedDoneSound"
    static let warningEnabled = "warningSoundEnabled"
    static let selectedWarningSound = "selectedWarningSound"
    static let seenEventIDs = "seenSoundNotificationEventIDs"
}

enum CompletionSound: String, CaseIterable, Identifiable {
    case beacon
    case chime
    case pulse

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beacon: "Beacon"
        case .chime: "Chime"
        case .pulse: "Pulse"
        }
    }

    var fileName: String {
        "Done-\(displayName)"
    }
}
