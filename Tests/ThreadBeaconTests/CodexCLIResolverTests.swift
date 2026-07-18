import Foundation
import ThreadBeaconCore

let codexCLIResolverTests = [
    TestCase(name: "Codex CLI resolver prefers current PATH") {
        let resolver = CodexCLIResolver(
            environment: ["PATH": "/custom/bin:/usr/bin"],
            homeDirectory: URL(fileURLWithPath: "/Users/test"),
            isExecutable: { $0.path == "/custom/bin/codex" },
            listDirectory: { _ in [] }
        )

        let resolved = try resolver.resolve()
        try expect(
            resolved.path == "/custom/bin/codex",
            "the first executable PATH candidate should win"
        )
    },
    TestCase(name: "Codex CLI resolver falls back to stable install paths") {
        let resolver = CodexCLIResolver(
            environment: ["PATH": "/usr/bin"],
            homeDirectory: URL(fileURLWithPath: "/Users/test"),
            isExecutable: { $0.path == "/opt/homebrew/bin/codex" },
            listDirectory: { _ in [] }
        )

        let resolved = try resolver.resolve()
        try expect(
            resolved.path == "/opt/homebrew/bin/codex",
            "Homebrew should be checked when PATH has no Codex executable"
        )
    },
    TestCase(name: "Codex CLI resolver selects highest NVM Node version") {
        let home = URL(fileURLWithPath: "/Users/test")
        let nvmRoot = home.appending(path: ".nvm/versions/node")
        let executable = nvmRoot.appending(path: "v22.22.0/bin/codex")
        let resolver = CodexCLIResolver(
            environment: [:],
            homeDirectory: home,
            isExecutable: { url in
                url.path == executable.path
                    || url.path == nvmRoot.appending(path: "v20.19.0/bin/codex").path
            },
            listDirectory: { url in
                guard url.path == nvmRoot.path else { return [] }
                return [
                    nvmRoot.appending(path: "not-a-version"),
                    nvmRoot.appending(path: "v20.19.0"),
                    nvmRoot.appending(path: "v22.22.0")
                ]
            }
        )

        let resolved = try resolver.resolve()
        try expect(
            resolved.path == executable.path,
            "the newest installed NVM Node version should win"
        )
    },
    TestCase(name: "Codex CLI resolver reports missing executable") {
        let resolver = CodexCLIResolver(
            environment: [:],
            homeDirectory: URL(fileURLWithPath: "/Users/test"),
            isExecutable: { _ in false },
            listDirectory: { _ in [] }
        )

        do {
            _ = try resolver.resolve()
            throw TestFailure(description: "missing Codex CLI should fail")
        } catch CodexCLIResolutionError.cliNotFound {
            // Expected.
        }
    }
]
