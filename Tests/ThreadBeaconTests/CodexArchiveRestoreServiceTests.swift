import Foundation
import ThreadBeaconCore

let codexArchiveRestoreServiceTests = [
    TestCase(name: "archive restore passes unarchive and session as separate arguments") {
        let calls = CommandCallBox()
        let executable = URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        let service = CodexArchiveRestoreService(
            resolveExecutable: { executable },
            environment: ["PATH": "/usr/bin"],
            runCommand: { url, arguments, environment in
                calls.append(executable: url, arguments: arguments, environment: environment)
                return CodexCommandResult(exitCode: 0, output: "")
            }
        )

        try await service.restore(threadID: "session-id")

        try expect(calls.values.count == 1, "restore should execute exactly one command")
        try expect(calls.values.first?.executable == executable, "restore should use resolved executable")
        try expect(
            calls.values.first?.arguments == ["unarchive", "session-id"],
            "subcommand and session ID must remain separate process arguments"
        )
        try expect(
            calls.values.first?.environment["PATH"] == "/opt/homebrew/bin:/usr/bin",
            "Codex executable directory should lead the child PATH for env-based Node shebangs"
        )
    },
    TestCase(name: "archive restore maps missing CLI") {
        let service = CodexArchiveRestoreService(
            resolveExecutable: { throw CodexCLIResolutionError.cliNotFound },
            runCommand: { _, _, _ in CodexCommandResult(exitCode: 0, output: "") }
        )

        do {
            try await service.restore(threadID: "session-id")
            throw TestFailure(description: "missing CLI should fail")
        } catch let error as ArchiveRestoreError {
            try expect(error == .cliNotFound, "resolution failure should become cliNotFound")
        }
    },
    TestCase(name: "archive restore detects unsupported command") {
        let service = CodexArchiveRestoreService(
            resolveExecutable: { URL(fileURLWithPath: "/usr/local/bin/codex") },
            runCommand: { _, _, _ in
                CodexCommandResult(exitCode: 2, output: "error: unknown subcommand 'unarchive'")
            }
        )

        do {
            try await service.restore(threadID: "session-id")
            throw TestFailure(description: "unsupported command should fail")
        } catch let error as ArchiveRestoreError {
            try expect(error == .unsupportedCommand, "old CLI should produce unsupportedCommand")
        }
    },
    TestCase(name: "archive restore sanitizes failed command output") {
        let longDetail = String(repeating: "detail ", count: 100)
        let service = CodexArchiveRestoreService(
            resolveExecutable: { URL(fileURLWithPath: "/usr/local/bin/codex") },
            runCommand: { _, _, _ in
                CodexCommandResult(exitCode: 1, output: "  failed\n\(longDetail)  ")
            }
        )

        do {
            try await service.restore(threadID: "session-id")
            throw TestFailure(description: "nonzero exit should fail")
        } catch let error as ArchiveRestoreError {
            guard case let .executionFailed(message) = error else {
                throw TestFailure(description: "nonzero exit should produce executionFailed")
            }
            try expect(message?.hasPrefix("failed detail") == true, "error output should be trimmed")
            try expect(message?.contains("\n") == false, "error output should be one line")
            try expect((message?.count ?? 0) <= 500, "error output should be bounded")
        }
    }
]

private final class CommandCallBox: @unchecked Sendable {
    struct Call {
        let executable: URL
        let arguments: [String]
        let environment: [String: String]
    }

    private let lock = NSLock()
    private var storage: [Call] = []

    var values: [Call] {
        lock.withLock { storage }
    }

    func append(executable: URL, arguments: [String], environment: [String: String]) {
        lock.withLock {
            storage.append(Call(executable: executable, arguments: arguments, environment: environment))
        }
    }
}
