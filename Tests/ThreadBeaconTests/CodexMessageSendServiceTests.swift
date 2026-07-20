import Foundation
import ThreadBeaconCore

let codexMessageSendServiceTests = [
    TestCase(name: "message sender resumes the requested session with the fixed prompt") {
        let calls = CommandCallBox()
        let executable = URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        let service = CodexMessageSendService(
            resolveExecutable: { executable },
            environment: ["PATH": "/usr/bin"],
            runCommand: { url, arguments, environment in
                calls.append(executable: url, arguments: arguments, environment: environment)
                return CodexCommandResult(exitCode: 0, output: "")
            }
        )

        try await service.send(threadID: "thread-id", message: "刚才中断了，请继续未完成的任务")

        try expect(calls.values.count == 1, "message sender should execute exactly one command")
        try expect(
            calls.values.first?.arguments == [
                "exec", "resume", "thread-id", "刚才中断了，请继续未完成的任务", "--skip-git-repo-check"
            ],
            "message and thread ID must remain separate process arguments"
        )
        try expect(
            calls.values.first?.environment["PATH"] == "/opt/homebrew/bin:/usr/bin",
            "Codex executable directory should lead the child PATH"
        )
    },
    TestCase(name: "message sender maps missing CLI") {
        let service = CodexMessageSendService(
            resolveExecutable: { throw CodexCLIResolutionError.cliNotFound },
            runCommand: { _, _, _ in CodexCommandResult(exitCode: 0, output: "") }
        )

        do {
            try await service.send(threadID: "thread-id", message: "继续")
            throw TestFailure(description: "missing CLI should fail")
        } catch let error as CodexMessageSendError {
            try expect(error == .cliNotFound, "missing CLI should be reported")
        }
    },
    TestCase(name: "message sender sanitizes failed command output") {
        let service = CodexMessageSendService(
            resolveExecutable: { URL(fileURLWithPath: "/usr/local/bin/codex") },
            runCommand: { _, _, _ in
                CodexCommandResult(exitCode: 1, output: "failed\nwith details")
            }
        )

        do {
            try await service.send(threadID: "thread-id", message: "继续")
            throw TestFailure(description: "nonzero exit should fail")
        } catch let error as CodexMessageSendError {
            guard case let .executionFailed(message) = error else {
                throw TestFailure(description: "nonzero exit should produce executionFailed")
            }
            try expect(message == "failed with details", "error output should be sanitized")
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
