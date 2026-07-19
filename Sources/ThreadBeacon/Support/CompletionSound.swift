import Foundation

enum SoundPreferenceKeys {
    static let notificationsEnabled = "soundNotificationsEnabled"
    static let doneEnabled = "doneSoundEnabled"
    static let selectedDoneSound = "selectedDoneSound"
    static let customDoneSoundURL = "customDoneSoundURL"
    static let warningEnabled = "warningSoundEnabled"
    static let selectedWarningSound = "selectedWarningSound"
    static let customWarningSoundURL = "customWarningSoundURL"
    static let seenEventIDs = "seenSoundNotificationEventIDs"
}

enum SoundSource {
    case builtIn(CompletionSound)
    case custom(URL)
}

enum CompletionSound: String, CaseIterable, Identifiable {
    case fupicatNotification
    case bassguitarNotification
    case beacon
    case chime
    case pulse
    case alert
    case resolve
    case knock

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fupicatNotification: "Fupicat Notification"
        case .bassguitarNotification: "Bassguitar Notification"
        case .beacon: "Beacon"
        case .chime: "Chime"
        case .pulse: "Pulse"
        case .alert: "Alert"
        case .resolve: "Resolve"
        case .knock: "Knock"
        }
    }

    var fileName: String {
        "Done-\(displayName)"
    }
}
