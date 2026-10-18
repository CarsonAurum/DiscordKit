import Foundation
import SwiftParser
import SwiftSyntax

/// One explicitly authored callable declaration, including private and inactive-branch code.
/// Locations use one-based UTF-8 columns, matching SwiftSyntax's source-location convention.
struct DocumentationDeclaration: Equatable, Sendable {
    let path: String
    let line: Int
    let column: Int
    let kind: String
    let name: String
    let documented: Bool
}

/// Deterministic presence evidence; documentation accuracy and completeness require review.
struct DocumentationAuditReport: Equatable, Sendable {
    let files: Int
    let declarations: [DocumentationDeclaration]

    /// Returns declarations lacking a nonempty adjacent Swift documentation comment.
    /// This synchronous value projection performs no filesystem access or semantic review.
    var missing: [DocumentationDeclaration] { declarations.filter { !$0.documented } }

    /// Renders all missing declarations with compiler-style locations and bounded claims.
    /// - Returns: A newline-terminated, stable report; success establishes presence only,
    ///   never sufficient parameter, error, lifecycle, concurrency or behavior documentation.
    func render() -> String {
        let failures = missing.map {
            "\($0.path):\($0.line):\($0.column): missing documentation for \($0.kind) \($0.name)"
        }
        return ([
            "Documentation presence audit: \(files) Swift files; \(declarations.count) explicit callable declarations; \(missing.count) missing comments.",
            "Scope includes functions, macro declarations, operators, initializers, deinitializers, subscripts, explicit accessors, shorthand getters, protocol requirements and tests at every access level.",
            "Owned separate packages, including Packages/DiscordDSLMacros authoring, plugin and test source, are audited recursively; fetched and build directories are excluded.",
            "Presence is syntactic evidence only; semantic completeness and correctness require human review.",
        ] + failures).joined(separator: "\n") + "\n"
    }
}

/// A failed source scan or missing-comment report; the CLI exits unsuccessfully for either.
struct DocumentationAuditFailure: Error, CustomStringConvertible {
    let description: String
}

/// Offline, source-accurate audit over owned Swift files with no compiler or network calls.
enum DocumentationAudit {
    /// Directory names excluded anywhere in the tree because they contain fetched, generated
    /// build/IDE or external dependency data. Authored `Generated` source remains in scope.
    static let excludedDirectories: Set<String> = [
        ".git", ".build", ".swiftpm", ".idea", ".air", "node_modules", "DerivedData",
    ]

    /// Parses one source file and inventories every explicitly authored callable declaration.
    ///
    /// The parser visits inactive conditional branches and nested local functions. Closures,
    /// synthesized memberwise initializers and stored properties have no authored callable
    /// declaration and are excluded. A shorthand computed property is an explicit getter
    /// whose documentation is attached to its enclosing property. An explicit accessor must
    /// carry its own documentation; documentation on the property/subscript does not cover it.
    /// Both `///` and `/** ... */` DocC comments are recognized, including before attributes;
    /// empty comments and ordinary comments do not establish documentation presence.
    /// - Parameters:
    ///   - source: Complete UTF-8 Swift source, retained only during this synchronous scan.
    ///   - path: Repository-relative diagnostic path; it is never opened or interpreted.
    /// - Returns: Source-ordered declarations with stable one-based line/column locations.
    /// - Throws: `DocumentationAuditFailure` when SwiftParser reports malformed source;
    ///   partial recovered syntax must not produce a misleading passing audit.
    static func scan(source: String, path: String) throws -> [DocumentationDeclaration] {
        let syntax = Parser.parse(source: source)
        guard !syntax.hasError else {
            throw DocumentationAuditFailure(description: "Cannot audit malformed Swift source: \(path)")
        }
        let visitor = DocumentationVisitor(path: path, tree: syntax)
        visitor.walk(syntax)
        return visitor.declarations
    }

    /// Audits owned Swift files recursively without following symbolic links or writing files.
    ///
    /// The root must contain a package manifest. Build/cache/VCS/dependency directories are
    /// excluded by exact directory name; checked-in generated Swift and separate example,
    /// tooling, test and fixture packages remain in scope, including the separate
    /// `Packages/DiscordDSLMacros` authoring library, compiler plugin and tests. Any unreadable file, traversal
    /// failure, invalid UTF-8 or parse error fails the operation instead of skipping evidence.
    /// - Parameter repository: Existing file URL of the repository root, not a symlink.
    /// - Returns: Path-sorted file results, with source order retained within each file.
    ///   An empty package manifest is valid and produces zero declarations.
    /// - Throws: `DocumentationAuditFailure` for invalid roots or traversal errors; filesystem,
    ///   decoding and parser errors propagate. Missing comments are returned for reporting.
    static func audit(repository: URL) throws -> DocumentationAuditReport {
        let requestedRoot = repository.standardizedFileURL
        let manager = FileManager.default
        guard requestedRoot.isFileURL,
              try requestedRoot.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory == true,
              try requestedRoot.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
              manager.fileExists(atPath: requestedRoot.appendingPathComponent("Package.swift").path) else {
            throw DocumentationAuditFailure(description: "Documentation audit requires an existing package repository root.")
        }
        // Preserve relative components while walking: Foundation may canonicalize /var
        // URLs to /private/var without doing so for the caller's root URL in a sandbox.
        var pending: [(url: URL, path: String)] = [(requestedRoot, "")]
        var files: [(url: URL, path: String)] = []
        while let directory = pending.popLast() {
            let children = try manager.contentsOfDirectory(
                at: directory.url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey]
            )
            for url in children {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
                guard values.isSymbolicLink != true else { continue }
                let path = directory.path + url.lastPathComponent
                if values.isDirectory == true {
                    if !excludedDirectories.contains(url.lastPathComponent) {
                        pending.append((url, path + "/"))
                    }
                } else if values.isRegularFile == true && url.pathExtension == "swift" {
                    files.append((url, path))
                }
            }
        }
        var declarations: [DocumentationDeclaration] = []
        for file in files.sorted(by: { $0.path < $1.path }) {
            let source = try String(contentsOf: file.url, encoding: .utf8)
            declarations += try scan(source: source, path: file.path)
        }
        return DocumentationAuditReport(files: files.count, declarations: declarations)
    }
}

/// Local synchronous syntax visitor; no mutable state escapes the owning audit invocation.
private final class DocumentationVisitor: SyntaxVisitor {
    let path: String
    let locations: SourceLocationConverter
    var declarations: [DocumentationDeclaration] = []

    /// Creates a source-accurate visitor including inactive `#if` syntax and nested declarations.
    /// - Parameters:
    ///   - path: Diagnostic path included verbatim in each result.
    ///   - tree: Parsed source retained by the source-location converter for UTF-8 positions.
    init(path: String, tree: SourceFileSyntax) {
        self.path = path
        locations = SourceLocationConverter(fileName: path, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    /// Records ordinary, protocol-required, nested and operator function declarations.
    /// - Parameter node: Authored function including attributes and access modifiers.
    /// - Returns: Child traversal, preserving nested local functions and accessors.
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node, kind: "function", name: node.name.text)
        return .visitChildren
    }

    /// Records public authoring macros without expanding them or invoking their compiler plugin.
    /// - Parameter node: Explicit attached or freestanding macro declaration at any access level.
    /// - Returns: Child traversal, retaining source-accurate diagnostics and declaration order.
    override func visit(_ node: MacroDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node, kind: "macro", name: node.name.text)
        return .visitChildren
    }

    /// Records designated, convenience, failable and protocol-required initializer declarations.
    /// - Parameter node: Authored initializer, including its optional/failable marker.
    /// - Returns: Child traversal so local callable declarations are also audited.
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node, kind: "initializer", name: "init" + (node.optionalMark?.text ?? ""))
        return .visitChildren
    }

    /// Records authored deinitializers regardless of access or isolation modifiers.
    /// - Parameter node: Explicit resource-lifetime cleanup declaration.
    /// - Returns: Child traversal for any nested callable syntax.
    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node, kind: "deinitializer", name: "deinit")
        return .visitChildren
    }

    /// Records subscript signatures separately from their explicitly authored accessors.
    /// - Parameter node: Subscript implementation or protocol requirement.
    /// - Returns: Child traversal, including getter and setter declarations.
    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node, kind: "subscript", name: "subscript")
        return .visitChildren
    }

    /// Records get/set/read/modify/init and property observer declarations individually.
    /// - Parameter node: Explicit accessor keyword with its own adjacent comment trivia.
    /// - Returns: Child traversal, retaining local functions in accessor bodies.
    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node, kind: "accessor", name: node.accessorSpecifier.text)
        return .visitChildren
    }

    /// Records shorthand property getters using the enclosing declaration's documentation.
    /// - Parameter node: Accessor block whose getter form has no `get` keyword.
    /// - Returns: Child traversal; explicit accessor lists are handled by their own visitor.
    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        if case .getter = node.accessors {
            if let binding = node.parent?.as(PatternBindingSyntax.self),
               let variable = binding.parent?.parent?.as(VariableDeclSyntax.self) {
                record(variable, kind: "getter", name: binding.pattern.trimmedDescription)
            } else if let subscriptNode = node.parent?.as(SubscriptDeclSyntax.self) {
                record(subscriptNode, kind: "getter", name: "subscript")
            }
        }
        return .visitChildren
    }

    /// Appends one declaration with a parser-derived location and nonempty comment evidence.
    /// - Parameters:
    ///   - node: Declaration whose leading trivia owns its documentation; attribute trivia counts.
    ///   - kind: Stable human-readable callable category.
    ///   - name: Short authored name, preserving operator spelling and pattern structure.
    /// The operation is synchronous, source ordered and does not infer semantic adequacy.
    private func record(_ node: some SyntaxProtocol, kind: String, name: String) {
        let location = locations.location(for: node.positionAfterSkippingLeadingTrivia)
        declarations.append(DocumentationDeclaration(
            path: path, line: location.line, column: location.column,
            kind: kind, name: name,
            documented: !(node.leadingTrivia.docCommentValue ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ))
    }
}
