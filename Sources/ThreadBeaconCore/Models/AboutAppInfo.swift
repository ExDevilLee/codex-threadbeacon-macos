import Foundation

public struct AboutAppInfo: Equatable, Sendable {
    public let version: String?
    public let build: String?

    public init(infoDictionary: [String: Any]?) {
        version = Self.value(for: "CFBundleShortVersionString", in: infoDictionary)
        build = Self.value(for: "CFBundleVersion", in: infoDictionary)
    }

    private static func value(for key: String, in dictionary: [String: Any]?) -> String? {
        guard let rawValue = dictionary?[key] as? String else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
