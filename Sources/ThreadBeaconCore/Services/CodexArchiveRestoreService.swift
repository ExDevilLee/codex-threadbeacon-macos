import Foundation

public struct CodexCommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let output: String

    public init(exitCode: Int32, output: String) {
        self.exitCode = exitCode
        self.output = output
    }
}

public enum ArchiveRestoreError: LocalizedError, Equatable, Sendable {
    case cliNotFound
    case unsupportedCommand
    case executionFailed(String?)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cliNotFound:
            "未找到 Codex CLI，请先安装 Codex CLI，或确认它位于受支持的安装目录。"
        case .unsupportedCommand:
            "当前 Codex CLI 不支持恢复归档任务，请升级 Codex CLI 后重试。"
        case let .executionFailed(message):
            message.map { "恢复失败：\($0)" } ?? "Codex CLI 未能恢复该任务。"
        case let .launchFailed(message):
            "无法启动 Codex CLI：\(message)"
        }
    }
}

public struct CodexArchiveRestoreService: Sendable {
    private let resolveExecutable: @Sendable () throws -> URL
    private let environment: [String: String]
    private let runCommand: @Sendable (URL, [String], [String: String]) throws -> CodexCommandResult

    public init(
        resolver: CodexCLIResolver = CodexCLIResolver(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        resolveExecutable = { try resolver.resolve() }
        self.environment = environment
        runCommand = Self.execute
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

    public func restore(threadID: String) async throws {
        let executable: URL
        do {
            executable = try resolveExecutable()
        } catch CodexCLIResolutionError.cliNotFound {
            throw ArchiveRestoreError.cliNotFound
        } catch {
            throw ArchiveRestoreError.launchFailed(Self.sanitized(error.localizedDescription) ?? "未知错误")
        }

        let result: CodexCommandResult
        do {
            let operation = runCommand
            let commandEnvironment = commandEnvironment(for: executable)
            result = try await Task.detached(priority: .utility) {
                try operation(executable, ["unarchive", threadID], commandEnvironment)
            }.value
        } catch {
            throw ArchiveRestoreError.launchFailed(Self.sanitized(error.localizedDescription) ?? "未知错误")
        }

        guard result.exitCode != 0 else { return }
        let output = Self.sanitized(result.output)
        let normalized = output?.lowercased() ?? ""
        if normalized.contains("unknown subcommand")
            || normalized.contains("unrecognized subcommand")
            || normalized.contains("unexpected argument 'unarchive'") {
            throw ArchiveRestoreError.unsupportedCommand
        }
        throw ArchiveRestoreError.executionFailed(output)
    }

    private static func execute(
        executable: URL,
        arguments: [String],
        environment: [String: String]
    ) throws -> CodexCommandResult {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CodexCommandResult(
            exitCode: process.terminationStatus,
            output: String(decoding: data, as: UTF8.self)
        )
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
        return String(singleLine.prefix(500))
    }
}
