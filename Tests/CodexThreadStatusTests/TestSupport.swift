import Foundation

struct TestCase: Sendable {
    let name: String
    let body: @Sendable () async throws -> Void
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard condition() else {
        throw TestFailure(description: "\(file):\(line): \(message)")
    }
}
