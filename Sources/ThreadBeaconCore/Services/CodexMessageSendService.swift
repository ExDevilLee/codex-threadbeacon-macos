import Foundation

public enum CodexMessageSendError: LocalizedError, Equatable, Sendable {
    case cliNotFound
    case executionFailed(String?)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cliNotFound:
            "未找到 Codex CLI，无法发送恢复提示。"
        case let .executionFailed(message):
            message.map { "发送恢复提示失败：\($0)" } ?? "发送恢复提示失败。"
        case let .launchFailed(message):
            "无法启动 Codex CLI：\(message)"
        }
    }

    public var logDescription: String {
        switch self {
        case .cliNotFound: "未找到 Codex CLI"
        case .executionFailed: "Codex CLI 执行失败"
        case .launchFailed: "无法启动 Codex CLI"
        }
    }
}

/// Sends a follow-up prompt to an existing Codex session through the supported CLI resume path.
/// The caller is responsible for deciding which incident is eligible and for de-duplication.
public struct CodexMessageSendService: Sendable {
    private let resolveExecutable: @Sendable () throws -> URL
    private let environment: [String: String]
    private let runCommand: @Sendable (URL, [String], [String: String]) throws -> CodexCommandResult

    public init(
        resolver: CodexCLIResolver = CodexCLIResolver(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        resolveExecutable = { try resolver.resolve() }
        self.environment = environment
        runCommand = CodexArchiveRestoreService.executeCommand
    }

    public init(
        resolveExecutable: @escaping @Sendable () throws -> URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        runCommand: @escaping @Sendable (URL, [String], [String: String]) throws -> CodexCommandResult
    ) {
        self.resolveExecutable = resolveExecutable
        self.environment = environment
        self.runCommand = runCommand
    }

    public func send(threadID: String, message: String) async throws {
        guard !threadID.isEmpty, !message.isEmpty else {
            throw CodexMessageSendError.executionFailed(nil)
        }

        let executable: URL
        do {
            executable = try resolveExecutable()
        } catch CodexCLIResolutionError.cliNotFound {
            throw CodexMessageSendError.cliNotFound
        } catch {
            throw CodexMessageSendError.launchFailed(Self.sanitized(error.localizedDescription) ?? "未知错误")
        }

        let result: CodexCommandResult
        do {
            let operation = runCommand
            let commandEnvironment = commandEnvironment(for: executable)
            result = try await Task.detached(priority: .utility) {
                try operation(
                    executable,
                    ["exec", "resume", threadID, message, "--skip-git-repo-check"],
                    commandEnvironment
                )
            }.value
        } catch {
            throw CodexMessageSendError.launchFailed(Self.sanitized(error.localizedDescription) ?? "未知错误")
        }

        guard result.exitCode == 0 else {
            throw CodexMessageSendError.executionFailed(Self.sanitized(result.output))
        }
    }

    private func commandEnvironment(for executable: URL) -> [String: String] {
        var commandEnvironment = environment
        let executableDirectory = executable.deletingLastPathComponent().path
        var pathComponents = (environment["PATH"] ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0 != executableDirectory }
        pathComponents.insert(executableDirectory, at: 0)
        commandEnvironment["PATH"] = pathComponents.joined(separator: ":")
        return commandEnvironment
    }

    private static func sanitized(_ output: String) -> String? {
        let singleLine = output
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !singleLine.isEmpty else { return nil }
        return String(singleLine.prefix(300))
    }
}
