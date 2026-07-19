import Foundation

public struct WindowPlacementRepository {
    public static let storageKey = "mainWindowPlacement"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> WindowPlacement? {
        guard let data = defaults.data(forKey: Self.storageKey) else { return nil }
        return try? decoder.decode(WindowPlacement.self, from: data)
    }

    public func save(_ placement: WindowPlacement) {
        guard let data = try? encoder.encode(placement) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
