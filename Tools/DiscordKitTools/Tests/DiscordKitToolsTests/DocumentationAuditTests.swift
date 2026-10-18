import Foundation
import Testing
@testable import DiscordKitTools

/// Exercises parser-derived presence evidence without network, compiler subprocesses or shared fixtures.
@Suite("Swift declaration documentation presence")
struct DocumentationAuditTests {
    /// Checks every callable syntax family, including protocol signatures and nested local functions.
    /// - Throws: Unexpected parsing errors fail the test; this source is deliberately type-unchecked.
    @Test func inventoriesCallableKinds() throws {
        let source = """
        protocol P {
            func required()
            init(value: Int)
            subscript(index: Int) -> Int { get set }
        }
        final class C {
            private init?() {}
            deinit {}
            static func +(lhs: C, rhs: C) -> C { lhs }
            func outer() { func inner() {} }
            var computed: Int { 1 }
            subscript(index: Int) -> Int { index }
            var observed: Int = 0 { willSet {} didSet {} }
            var explicit: Int { get { 1 } set {} }
            var borrowed: Int { _read { yield 1 } _modify { yield &observed } }
        }
        """
        let result = try DocumentationAudit.scan(source: source, path: "Fixture.swift")
        #expect(result.map(\.name) == [
            "required", "init", "subscript", "get", "set", "init?", "deinit", "+", "outer", "inner",
            "computed", "subscript", "subscript", "willSet", "didSet", "get", "set", "_read", "_modify",
        ])
        #expect(result.filter { $0.kind == "getter" }.count == 2)
        #expect(result.allSatisfy { !$0.documented && $0.path == "Fixture.swift" })
    }

    /// Ensures declaration access level never suppresses missing-comment evidence.
    /// - Parameter access: Each applicable Swift access spelling, plus default internal visibility.
    /// - Throws: Unexpected source parsing failures fail this deterministic parameterized test.
    @Test(arguments: ["", "private", "fileprivate", "internal", "package", "public", "open"])
    func includesEveryAccessLevel(access: String) throws {
        let result = try DocumentationAudit.scan(source: "\(access) func sample() {}", path: "Access.swift")
        #expect(result.count == 1)
        #expect(result.first?.documented == false)
    }

    /// Recognizes nonempty DocC forms before attributes while excluding comments, strings and closures.
    /// - Throws: Unexpected parse errors fail the test; type checking is intentionally unnecessary.
    @Test func recognizesDocumentationTriviaAndAttributes() throws {
        let source = #"""
        /// A documented test.
        @Test(arguments: [1, 2])
        private func test(value: Int) {}
        /** A documented initializer. */
        init() {}
        /// The shorthand property's getter.
        var computed: Int { 1 }
        let closure = { (value: Int) in value + 1 }
        let text = "func fake() {}"
        // func fakeComment() {}
        /* func fakeBlock() {} */
        """#
        let result = try DocumentationAudit.scan(source: source, path: "Comments.swift")
        #expect(result.map(\.name) == ["test", "init", "computed"])
        #expect(result.allSatisfy { $0.documented })
        #expect(result[0].line == 2)
        #expect(result[0].column == 1)
    }

    /// Rejects empty DocC trivia and ordinary comments instead of interpreting markers as content.
    /// - Parameter comment: A comment spelling with no documentation text or no DocC marker.
    /// - Throws: Unexpected source parsing errors fail the test.
    @Test(arguments: ["", "///", "///   ", "/** */", "// Ordinary", "/* Ordinary */"])
    func rejectsMissingOrEmptyComments(comment: String) throws {
        let result = try DocumentationAudit.scan(source: "\(comment)\nfunc sample() {}", path: "Empty.swift")
        #expect(result.count == 1)
        #expect(result.first?.documented == false)
    }

    /// Requires each explicit accessor's comment and prevents a prior declaration's docs leaking forward.
    /// - Throws: Unexpected source parsing errors fail this accessor ownership regression.
    @Test func preservesCommentOwnership() throws {
        let source = """
        /// Describes the property, not its explicit accessors.
        var property: Int {
            /// Reads the property.
            get { 1 }
            set {}
        }
        /// Describes only the stored property.
        var stored = 1
        func undocumented() {}
        /// Describes only the first function.
        func documented() {}
        func alsoUndocumented() {}
        """
        let result = try DocumentationAudit.scan(source: source, path: "Ownership.swift")
        #expect(result.map(\.documented) == [true, false, false, true, false])
        #expect(result.map(\.name) == ["get", "set", "undocumented", "documented", "alsoUndocumented"])
    }

    /// Visits both conditional branches without executing platform checks or expanding macros.
    /// - Throws: Unexpected parser errors fail the test; all branches are valid Swift syntax.
    @Test func includesInactiveBranchesAndRepeatedScans() throws {
        let source = """
        #if os(ImaginaryOS)
        private func hidden() {}
        #else
        /// Present in the other branch.
        func visible() {}
        #endif
        """
        let first = try DocumentationAudit.scan(source: source, path: "Conditional.swift")
        #expect(first.map(\.name) == ["hidden", "visible"])
        #expect(first.map(\.documented) == [false, true])
        #expect(try DocumentationAudit.scan(source: source, path: "Conditional.swift") == first)
        #expect(try DocumentationAudit.scan(source: "", path: "Empty.swift").isEmpty)
    }

    /// Refuses parser recovery as passing evidence for incomplete or malformed declarations.
    /// - Parameter source: Invalid Swift syntax that must fail before returning declaration evidence.
    @Test(arguments: ["func incomplete(", "struct MissingBrace {", "func f() { let = }"])
    func rejectsMalformedSource(source: String) {
        #expect(throws: DocumentationAuditFailure.self) {
            try DocumentationAudit.scan(source: source, path: "Malformed.swift")
        }
    }

    /// Tests recursive scope, deterministic ordering, generated-source inclusion and symlink exclusion.
    /// - Throws: Temporary-file, audit or parse failures fail this test; owned fixtures are always removed.
    @Test func auditsOwnedFilesWithoutChangingThem() throws {
        let fixture = try DocumentationFixture()
        defer { fixture.cleanup() }
        try fixture.write("Sources/Z.swift", "func missing() {}")
        try fixture.write("Sources/Generated/A.generated.swift", "/// Generated callable.\nfunc generated() {}")
        try fixture.write("Examples/Demo/Tests/Sample.swift", "/// Example test.\n@Test func sample() {}")
        for directory in DocumentationAudit.excludedDirectories {
            try fixture.write("\(directory)/Invalid.swift", "func incomplete(")
            try fixture.write("Nested/\(directory)/Invalid.swift", "func incomplete(")
        }
        let external = fixture.root.appendingPathComponent(".build/External.swift")
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appendingPathComponent("Linked.swift"), withDestinationURL: external
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appendingPathComponent("LinkedDirectory"),
            withDestinationURL: fixture.root.appendingPathComponent(".build")
        )
        let original = try Data(contentsOf: fixture.root.appendingPathComponent("Sources/Z.swift"))
        let report = try DocumentationAudit.audit(repository: fixture.root)
        #expect(report.files == 4)
        #expect(report.declarations.map(\.path) == [
            "Examples/Demo/Tests/Sample.swift", "Sources/Generated/A.generated.swift", "Sources/Z.swift",
        ])
        #expect(report.missing.count == 1)
        #expect(report.render().contains("Sources/Z.swift:1:1: missing documentation for function missing"))
        #expect(report.render().contains("semantic completeness and correctness require human review"))
        #expect(try DocumentationAudit.audit(repository: fixture.root) == report)
        #expect(try Data(contentsOf: fixture.root.appendingPathComponent("Sources/Z.swift")) == original)
    }

    /// Rejects absent package roots and malformed owned files; it never silently drops invalid evidence.
    /// - Throws: Fixture creation and unexpected filesystem errors fail the test.
    @Test func rejectsInvalidRepositoriesAndOwnedSources() throws {
        let fixture = try DocumentationFixture()
        defer { fixture.cleanup() }
        #expect(throws: (any Error).self) {
            try DocumentationAudit.audit(repository: fixture.root.appendingPathComponent("Absent"))
        }
        try fixture.write("Bad.swift", "func incomplete(")
        #expect(throws: DocumentationAuditFailure.self) { try DocumentationAudit.audit(repository: fixture.root) }
        try Data([0xFF]).write(to: fixture.root.appendingPathComponent("Bad.swift"))
        #expect(throws: (any Error).self) { try DocumentationAudit.audit(repository: fixture.root) }
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("Bad.swift"))
        let linkedRoot = fixture.root.appendingPathComponent("RootAlias")
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: fixture.root)
        #expect(throws: DocumentationAuditFailure.self) { try DocumentationAudit.audit(repository: linkedRoot) }
        try FileManager.default.removeItem(at: linkedRoot)
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("Package.swift"))
        #expect(throws: DocumentationAuditFailure.self) { try DocumentationAudit.audit(repository: fixture.root) }
    }

    /// Runs standalone CLI dispatch without parity metadata and verifies missing docs fail the command.
    /// - Throws: Unexpected fixture or command failures fail this no-subprocess integration test.
    @Test func commandUsesPresenceGateWithoutParityMetadata() throws {
        let fixture = try DocumentationFixture()
        defer { fixture.cleanup() }
        let command = try ToolCommand.parse(arguments: ["documentation", "audit", "--repository", fixture.root.path])
        #expect(try command.execute().contains("0 explicit callable declarations; 0 missing comments"))
        try fixture.write("Private.swift", "private func missing() {}")
        #expect(throws: DocumentationAuditFailure.self) { try command.execute() }
        try fixture.write("Private.swift", "/// Explains the private function.\nprivate func present() {}")
        #expect(try command.execute().contains("1 explicit callable declarations; 0 missing comments"))
    }
}

/// Isolated temporary package with no dependencies, credentials or shared mutable test state.
private struct DocumentationFixture {
    let root: URL

    /// Creates a unique directory and an empty manifest sufficient for source audit root validation.
    /// - Throws: Local temporary-directory or manifest-write errors; callers remove successful fixtures.
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DocumentationAudit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "// Empty synthetic manifest.\n".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    }

    /// Writes one owned fixture source, creating its parent directory as needed.
    /// - Parameters:
    ///   - path: Relative path supplied by trusted test code, never user input.
    ///   - source: Complete source bytes encoded as UTF-8 without modification.
    /// - Throws: Local directory creation or atomic write errors; no external path is touched.
    func write(_ path: String, _ source: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try source.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Removes the entire fixture after assertions; cleanup errors do not hide the original failure.
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
