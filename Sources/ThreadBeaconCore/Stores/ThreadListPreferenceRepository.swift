import Foundation

public struct ThreadListPreferenceRepository {
    public static let storageKey = "threadListPreferences.v1"

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func load() -> ThreadListPreferences {
        guard let data = defaults.data(forKey: Self.storageKey),
              let preferences = try? decoder.decode(ThreadListPreferences.self, from: data) else {
            return .empty
        }
        return preferences
    }

    public func save(_ preferences: ThreadListPreferences) {
        guard let data = try? encoder.encode(preferences) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}
