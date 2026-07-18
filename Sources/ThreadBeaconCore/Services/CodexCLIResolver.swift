import Foundation

public enum CodexCLIResolutionError: Error, Equatable, Sendable {
    case cliNotFound
}

public struct CodexCLIResolver: Sendable {
    private let environment: [String: String]
    private let homeDirectory: URL
    private let isExecutable: @Sendable (URL) -> Bool
    private let listDirectory: @Sendable (URL) -> [URL]

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        isExecutable: @escaping @Sendable (URL) -> Bool = {
            FileManager.default.isExecutableFile(atPath: $0.path)
        },
        listDirectory: @escaping @Sendable (URL) -> [URL] = {
            (try? FileManager.default.contentsOfDirectory(
                at: $0,
                includingPropertiesForKeys: nil
            )) ?? []
        }
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.isExecutable = isExecutable
        self.listDirectory = listDirectory
    }

    public func resolve() throws -> URL {
        var candidates = pathCandidates()
        candidates.append(contentsOf: stableCandidates())
        candidates.append(contentsOf: nvmCandidates())

        var visitedPaths: Set<String> = []
        for candidate in candidates {
            let normalized = candidate.standardizedFileURL
            guard visitedPaths.insert(normalized.path).inserted else { continue }
            if isExecutable(normalized) {
                return normalized
            }
        }
        throw CodexCLIResolutionError.cliNotFound
    }

    private func pathCandidates() -> [URL] {
        (environment["PATH"] ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map { URL(fileURLWithPath: String($0)).appending(path: "codex") }
    }

    private func stableCandidates() -> [URL] {
        [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            homeDirectory.appending(path: ".local/bin/codex")
        ]
    }

    private func nvmCandidates() -> [URL] {
        let root = homeDirectory.appending(path: ".nvm/versions/node")
        return listDirectory(root)
            .compactMap { directory -> (url: URL, version: [Int])? in
                guard let version = Self.nodeVersion(directory.lastPathComponent) else {
                    return nil
                }
                return (directory.appending(path: "bin/codex"), version)
            }
            .sorted { Self.versionIsGreater($0.version, than: $1.version) }
            .map(\.url)
    }

    private static func nodeVersion(_ name: String) -> [Int]? {
        let rawVersion = name.hasPrefix("v") ? String(name.dropFirst()) : name
        let components = rawVersion.split(separator: ".")
        guard !components.isEmpty else { return nil }
        let version = components.compactMap { Int($0) }
        return version.count == components.count ? version : nil
    }

    private static func versionIsGreater(_ lhs: [Int], than rhs: [Int]) -> Bool {
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }
}
