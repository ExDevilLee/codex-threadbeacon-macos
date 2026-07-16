import Foundation

public struct SessionIndexTitleRepository: Sendable {
    public let indexURL: URL

    public init(indexURL: URL) {
        self.indexURL = indexURL
    }

    public func loadLatestTitles() throws -> [String: String] {
        let data = try Data(contentsOf: indexURL)
        let decoder = JSONDecoder()
        var titles: [String: String] = [:]

        for line in data.split(separator: 0x0A) {
            guard let entry = try? decoder.decode(SessionIndexEntry.self, from: Data(line)) else {
                continue
            }
            let title = entry.threadName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entry.id.isEmpty, !title.isEmpty else {
                continue
            }
            titles[entry.id] = title
        }

        return titles
    }
}

private struct SessionIndexEntry: Decodable {
    let id: String
    let threadName: String

    private enum CodingKeys: String, CodingKey {
        case id
        case threadName = "thread_name"
    }
}
