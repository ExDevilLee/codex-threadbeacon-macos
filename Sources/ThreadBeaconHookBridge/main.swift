import Foundation
import ThreadBeaconCore

let repository = CompactionActivityRepository()
let handler = CompactionHookEventHandler(repository: repository)
let data = FileHandle.standardInput.readDataToEndOfFile()

do {
    try handler.handle(data: data)
} catch let error as CompactionHookEventError {
    repository.recordDiagnostic(code: error.diagnosticCode)
} catch {
    repository.recordDiagnostic(code: "write_failed")
}
