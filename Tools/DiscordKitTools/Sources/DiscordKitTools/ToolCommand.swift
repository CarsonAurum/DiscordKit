import Foundation

/// Explicit developer operations. Only `generateWrite` is allowed to change output files.
enum ToolAction: Equatable, Sendable {
    case inventoryValidate, generateCheck, generateWrite, parityCheck, documentationAudit
}

/// A usage error distinguished from a failed validation by the executable's exit status.
struct ToolUsageFailure: Error, CustomStringConvertible {
    let description: String
}

/// Parsed offline operation with a repository root and explicit audit date.
/// Parsing performs no filesystem or network access; execution validates repository evidence.
struct ToolCommand: Sendable {
    let action: ToolAction
    let repository: URL
    let asOf: String

    static let usage = """
    Usage:
      DiscordKitTools inventory validate --repository <directory> [--as-of YYYY-MM-DD]
      DiscordKitTools generate --check --repository <directory> [--as-of YYYY-MM-DD]
      DiscordKitTools generate --write --repository <directory> [--as-of YYYY-MM-DD]
      DiscordKitTools parity check --repository <directory> [--as-of YYYY-MM-DD]
      DiscordKitTools documentation audit --repository <directory> [--as-of YYYY-MM-DD]
    Validation and check commands never write files or access the network.
    """

    /// Parses a single supported operation without silently enabling generation writes.
    ///
    /// Options may follow the operation in any order, once each. `generate` requires an
    /// explicit mutually exclusive `--check` or `--write`. Future audit commands remain
    /// unsupported until implemented; misspelled commands and options fail with usage.
    /// - Parameters:
    ///   - arguments: Arguments after the executable name, including a nonempty repository path.
    ///   - currentDate: Clock injection for the default UTC audit day; defaults to the current date.
    ///     Historical `--as-of` dates select reproducible snapshot checks, not current certification.
    ///     Documentation audits always inspect current source bytes; their accepted date option
    ///     does not reconstruct historical files or establish semantic documentation coverage.
    /// - Returns: An immutable operation; relative repository paths resolve against the process directory.
    /// - Throws: `ToolUsageFailure` for absent, repeated, conflicting or unknown arguments, an
    ///   empty repository path, or an invalid calendar audit date. No repository state is changed.
    static func parse(arguments: [String], currentDate: Date = Date()) throws -> ToolCommand {
        var options = arguments
        let operation: String
        if Array(options.prefix(2)) == ["inventory", "validate"] {
            operation = "inventory"
            options.removeFirst(2)
        } else if Array(options.prefix(2)) == ["parity", "check"] {
            operation = "parity"
            options.removeFirst(2)
        } else if Array(options.prefix(2)) == ["documentation", "audit"] {
            operation = "documentation"
            options.removeFirst(2)
        } else if options.first == "generate" {
            operation = "generate"
            options.removeFirst()
        } else {
            throw ToolUsageFailure(description: usage)
        }
        var repositoryPath: String?
        var auditDate: String?
        var mode: ToolAction?
        var index = 0
        while index < options.count {
            let option = options[index]
            if option == "--repository" || option == "--as-of" {
                guard index + 1 < options.count, !options[index + 1].hasPrefix("--") else {
                    throw ToolUsageFailure(description: usage)
                }
                let value = options[index + 1]
                if option == "--repository", repositoryPath == nil,
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    repositoryPath = value
                } else if option == "--as-of", auditDate == nil, validDate(value) {
                    auditDate = value
                } else {
                    throw ToolUsageFailure(description: usage)
                }
                index += 2
            } else if operation == "generate", mode == nil, option == "--check" || option == "--write" {
                mode = option == "--check" ? .generateCheck : .generateWrite
                index += 1
            } else {
                throw ToolUsageFailure(description: usage)
            }
        }
        guard let repositoryPath, operation != "generate" || mode != nil else {
            throw ToolUsageFailure(description: usage)
        }
        let formatter = dateFormatter()
        return ToolCommand(
            action: mode ?? (operation == "inventory" ? .inventoryValidate :
                operation == "documentation" ? .documentationAudit : .parityCheck),
            repository: URL(fileURLWithPath: repositoryPath, isDirectory: true).standardizedFileURL,
            asOf: auditDate ?? formatter.string(from: currentDate)
        )
    }

    /// Executes a parsed operation using committed local inputs and independently validated evidence.
    ///
    /// Validation and check operations read repository files without changing them or
    /// their modification times. Explicit writes first render in memory and validate the
    /// proposed source declarations against real handwritten test evidence, so deleted
    /// generated outputs can be recreated. The writer then audits its fixed destination
    /// allowlist before changing any file. No operation contacts upstream services or
    /// invokes a compiler, test subprocess or consumer build plugin.
    /// - Returns: A newline-terminated human-readable report derived from validated records.
    /// Documentation audits inspect owned source without requiring parity metadata; absent
    /// comments and malformed Swift fail the operation. Documentation presence never establishes
    /// semantic completeness, correctness, parameter/error coverage or source compatibility.
    /// - Throws: Filesystem/JSON errors, inventory or parity validation errors,
    ///   `DocumentationAuditFailure` for malformed source or missing comments, and
    ///   `GenerationFailure` for stale outputs or unsafe destinations. Generation writes
    ///   may partially complete if an I/O error occurs; resolve it and rerun `--check`.
    func execute() throws -> String {
        if action == .documentationAudit {
            let report = try DocumentationAudit.audit(repository: repository)
            guard report.missing.isEmpty else {
                throw DocumentationAuditFailure(description: report.render())
            }
            return report.render()
        }
        let parityDirectory = repository.appending(path: "Docs/Parity", directoryHint: .isDirectory)
        let inventoryData = try Data(contentsOf: parityDirectory.appending(path: "inventory-v1.json"))
        let sourcesData = try Data(contentsOf: parityDirectory.appending(path: "sources-2026-10-15.json"))
        let reviewedData = try Data(contentsOf: parityDirectory.appending(path: "reviewed-v1.json"))
        let reviewed = try ReviewedInventoryValidator.load(reviewedData: reviewedData)
        let proposed = action == .generateWrite ? try Generator.render(reviewed) : []
        let overrides = Dictionary(uniqueKeysWithValues: proposed.map { ($0.path, $0.data) })
        let report = try ParityValidator.validate(
            reviewedData: reviewedData, inventoryData: inventoryData, sourcesData: sourcesData,
            repository: repository, asOf: asOf, generatedArtifacts: overrides
        )
        switch action {
        case .inventoryValidate:
            return """
            Valid inventory: \(report.discovery.entries) entries, \(report.discovery.sources) sources, 0 unclassified discovery IDs
            Implemented support: \(report.discovery.supported); pending semantic review: \(report.discovery.pendingReview)
            Reviewed definitions: \(report.reviewedDefinitions); mapped implemented endpoints: \(report.mappedImplementedEndpoints)
            Audit date: \(asOf). Structural evidence checks do not certify full API parity or platform qualification.

            """
        case .generateCheck:
            let generation = try Generator.run(repository: repository, reviewed: reviewed, check: true)
            return "Generated output is byte-identical: \(generation.artifacts) artifacts; audit date: \(asOf).\n"
        case .generateWrite:
            let generation = try Generator.apply(proposed, repository: repository, check: false)
            return "Generated \(generation.artifacts) artifacts; changed: \(generation.changedPaths.count). Audit date: \(asOf).\n"
        case .parityCheck:
            _ = try Generator.run(repository: repository, reviewed: reviewed, check: true)
            return "Audit date: \(asOf).\n\n" + report.renderMarkdown()
        case .documentationAudit:
            preconditionFailure("Documentation audits return before parity metadata loading.")
        }
    }

    /// Creates a Gregorian UTC formatter for locale-independent audit-day spelling.
    /// - Returns: A newly owned formatter with strict `yyyy-MM-dd` parsing; it shares no mutable state.
    private static func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }

    /// Rejects normalization and impossible calendar days in an explicit audit date.
    /// - Parameter value: Expected four-digit year in 0001...9999 and two-digit month/day.
    /// - Returns: Whether strict UTC Gregorian parsing round-trips the original ASCII spelling.
    ///   This pure synchronous check neither consults the clock nor changes repository state.
    private static func validDate(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) }),
              let year = Int(value.prefix(4)), year > 0 else { return false }
        let formatter = dateFormatter()
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }
}
