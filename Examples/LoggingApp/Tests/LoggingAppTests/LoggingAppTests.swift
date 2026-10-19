import Foundation
import Testing
@testable import LoggingApp

/// Tests bounded example-output inspection without process-global logging changes.
struct LoggingAppTests {
    /// Reads exact NDJSON objects and rejects nonobjects and malformed JSON.
    @Test func outputInspection() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{\"level\":\"info\"}\n{\"level\":\"notice\"}\n".utf8).write(to: url)
        #expect(try LoggingApp.readRecords(from: url).compactMap { $0["level"] as? String } == ["info", "notice"])
        try Data("[]\n".utf8).write(to: url)
        #expect(throws: ExampleFailure.missingOutput) { try LoggingApp.readRecords(from: url) }
        try Data("{\n".utf8).write(to: url)
        #expect(throws: (any Error).self) { try LoggingApp.readRecords(from: url) }
        try Data().write(to: url)
        #expect(try LoggingApp.readRecords(from: url).isEmpty)
    }
}
