import Foundation
import Testing
@testable import DiscordKitTools

/// Verifies command intent, nonwriting defaults and date parsing without running subprocesses.
@Suite("Offline tool commands")
struct ToolCommandTests {
    /// Accepts each explicit operation and preserves an injected audit day and repository path.
    /// - Parameters:
    ///   - prefix: One implemented command and its required generation mode if applicable.
    ///   - expected: The operation expected from that prefix.
    /// - Throws: Unexpected parser errors fail this test; no files are touched.
    @Test(arguments: [
        (["inventory", "validate"], ToolAction.inventoryValidate),
        (["generate", "--check"], ToolAction.generateCheck),
        (["generate", "--write"], ToolAction.generateWrite),
        (["parity", "check"], ToolAction.parityCheck),
        (["documentation", "audit"], ToolAction.documentationAudit),
    ])
    func parsesExplicitOperations(prefix: [String], expected: ToolAction) throws {
        let command = try ToolCommand.parse(arguments: prefix + ["--repository", ".", "--as-of", "2026-10-16"])
        #expect(command.action == expected)
        #expect(command.asOf == "2026-10-16")
        #expect(command.repository.isFileURL)
        #expect(command.repository.path == URL(fileURLWithPath: ".", isDirectory: true).standardizedFileURL.path)
    }

    /// Defaults audits to the supplied UTC day and supports space-containing paths and option reordering.
    /// - Throws: Unexpected parsing errors fail this test; paths are interpreted, never opened or created.
    @Test func parsesOptionsAndInjectedClock() throws {
        let command = try ToolCommand.parse(
            arguments: ["generate", "--repository", "a path", "--check"],
            currentDate: Date(timeIntervalSince1970: 0)
        )
        #expect(command.action == .generateCheck)
        #expect(command.asOf == "1970-01-01")
        #expect(command.repository.lastPathComponent == "a path")
        let reordered = try ToolCommand.parse(arguments: [
            "parity", "check", "--as-of", "2024-02-29", "--repository", ".",
        ])
        #expect(reordered.action == .parityCheck)
        #expect(reordered.asOf == "2024-02-29")
    }

    /// Rejects unsupported operations, surprising writes, missing values and ambiguous repeated options.
    /// - Parameter arguments: A malformed CLI invocation; each must fail before accessing repository files.
    /// - Throws: An unexpected error type fails the assertion.
    @Test(arguments: [
        [String](), ["inventory"], ["inventory", "validate"], ["parity", "check"],
        ["documentation", "audit", "--repository", ".", "--write"],
        ["dependencies", "audit", "--repository", "."],
        ["generate", "--repository", "."],
        ["generate", "--check", "--write", "--repository", "."],
        ["generate", "--check", "--check", "--repository", "."],
        ["inventory", "validate", "--write", "--repository", "."],
        ["inventory", "validate", "--repository", ""],
        ["inventory", "validate", "--repository", " \n"],
        ["inventory", "validate", "--repository"],
        ["inventory", "validate", "--repository", "--as-of", "2026-10-16"],
        ["inventory", "validate", "--repository", ".", "--repository", "."],
        ["inventory", "validate", "--repository", ".", "--as-of"],
        ["inventory", "validate", "--repository", ".", "--as-of", "2026-10-16", "--as-of", "2026-10-16"],
        ["inventory", "validate", "--repository", ".", "--unknown"],
        ["parity", "check", "--repository", ".", "extra"],
    ])
    func rejectsAmbiguousArguments(arguments: [String]) {
        #expect(throws: ToolUsageFailure.self) { try ToolCommand.parse(arguments: arguments) }
    }

    /// Rejects malformed, normalized, non-Gregorian or zero-year audit dates.
    /// - Parameter value: A date spelling outside the documented CLI contract.
    /// - Throws: An unexpected error type fails the assertion; no current clock is needed.
    @Test(arguments: ["", "unknown", "0000-01-01", "2026-02-29", "1900-02-29", "2026-04-31",
                      "2026-1-01", "2026-01-1", "2026-10-16Z", " 2026-10-16", "2026-13-01"])
    func rejectsInvalidAuditDates(value: String) {
        #expect(throws: ToolUsageFailure.self) {
            try ToolCommand.parse(arguments: ["inventory", "validate", "--repository", ".", "--as-of", value])
        }
    }

    /// Executes generation bootstrap and all nonwriting commands against one isolated reviewed checkout.
    ///
    /// Generated files start absent. Explicit writes must create them after evidence
    /// validation; subsequent writes must preserve identical bytes and modification times.
    /// Inventory, generation and parity checks must report validated counts without changing
    /// any output. No compiled runtime code, network or wall-clock timing is required.
    /// - Throws: Unexpected fixture, command, rendering or filesystem failures fail the test.
    @Test func executesOfflineCommandsAndRestoresMissingOutput() throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        fixture.change("model") { $0["name"] = "Sample" }
        fixture.change("enum") { $0["name"] = "SampleEnum" }
        try install(fixture)
        let write = command(.generateWrite, fixture: fixture)
        let result = try write.execute()
        #expect(result.contains("Generated 5 artifacts; changed: 5"))
        let before = try outputSnapshot(fixture.repository)
        #expect(try command(.inventoryValidate, fixture: fixture).execute().contains("Reviewed definitions: 6"))
        #expect(try command(.generateCheck, fixture: fixture).execute().contains("byte-identical: 5 artifacts"))
        #expect(try command(.parityCheck, fixture: fixture).execute().contains("# Validated parity records"))
        #expect(try write.execute().contains("changed: 0"))
        #expect(try outputSnapshot(fixture.repository) == before)
        let path = "Sources/DiscordModels/Generated/HTTPResources.generated.swift"
        try FileManager.default.removeItem(at: fixture.repository.appendingPathComponent(path))
        #expect(throws: GenerationFailure.self) { try command(.generateCheck, fixture: fixture).execute() }
        #expect(try write.execute().contains("changed: 1"))
        #expect(try Data(contentsOf: fixture.repository.appendingPathComponent(path)) == before[path]?.data)
    }

    /// Prevents explicit regeneration from writing anything when handwritten evidence is missing.
    /// - Throws: Unexpected fixture installation or filesystem errors fail this test. The
    ///   validation error is asserted locally and the absent output directory stays absent.
    @Test func refusesWritesBeforeEvidenceValidation() throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        fixture.change("model") { $0["name"] = "Sample" }
        fixture.change("enum") { $0["name"] = "SampleEnum" }
        try install(fixture)
        try FileManager.default.removeItem(at: fixture.repository.appendingPathComponent("Tests/SampleTests/SampleTests.swift"))
        #expect(throws: (any Error).self) { try command(.generateWrite, fixture: fixture).execute() }
        for path in Generator.outputPaths {
            #expect(!FileManager.default.fileExists(atPath: fixture.repository.appendingPathComponent(path).path))
        }
    }

    /// Refuses stale verification before either a nonwriting report or an explicit write succeeds.
    /// - Parameter action: Every supported CLI dispatch branch shares the same validation gate.
    /// - Throws: Unexpected fixture setup/parsing failures fail this test.
    @Test(arguments: [ToolAction.inventoryValidate, .generateCheck, .generateWrite, .parityCheck])
    func rejectsStaleCommandInputs(action: ToolAction) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        fixture.change("model") { $0["name"] = "Sample" }
        fixture.change("enum") { $0["name"] = "SampleEnum" }
        try install(fixture)
        let operation = ToolCommand(action: action, repository: fixture.repository, asOf: "2026-11-16")
        #expect(throws: ReviewedInventoryFailure.self) { try operation.execute() }
    }

    /// Writes only synthetic input metadata needed by the CLI's fixed repository layout.
    /// - Parameter fixture: Independent source/test fixture whose graph is serialized as-is.
    /// - Throws: JSON serialization or local temporary-file errors. No project file is modified.
    private func install(_ fixture: ReviewedFixture) throws {
        let directory = fixture.repository.appendingPathComponent("Docs/Parity")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try fixture.data(fixture.reviewed).write(to: directory.appendingPathComponent("reviewed-v1.json"))
        try fixture.data(fixture.inventory).write(to: directory.appendingPathComponent("inventory-v1.json"))
        try fixture.data(fixture.catalog).write(to: directory.appendingPathComponent("sources-2026-10-15.json"))
    }

    /// Constructs an executable operation using the fixture's deterministic audit day.
    /// - Parameters:
    ///   - action: One implemented command action; write intent is explicit at each caller.
    ///   - fixture: Isolated temporary repository containing the expected metadata layout.
    /// - Returns: A command targeting only the fixture's owned directory.
    private func command(_ action: ToolAction, fixture: ReviewedFixture) -> ToolCommand {
        ToolCommand(action: action, repository: fixture.repository, asOf: "2026-10-16")
    }

    /// Captures output bytes and modification times to prove checks perform no hidden writes.
    /// - Parameter repository: Existing synthetic checkout with all allowlisted outputs present.
    /// - Returns: One immutable snapshot per owned path; dictionary ordering is irrelevant.
    /// - Throws: File or attribute-read errors if fixture output is absent or unreadable.
    private func outputSnapshot(_ repository: URL) throws -> [String: ToolOutputSnapshot] {
        var result: [String: ToolOutputSnapshot] = [:]
        for path in Generator.outputPaths {
            let url = repository.appendingPathComponent(path)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            result[path] = ToolOutputSnapshot(data: try Data(contentsOf: url), modified: attributes[.modificationDate] as? Date)
        }
        return result
    }
}

/// Output identity includes modification time so same-byte rewrites are observable in tests.
private struct ToolOutputSnapshot: Equatable {
    let data: Data
    let modified: Date?
}
