import Foundation

/// One validated kind/status combination, counted without merging unrelated source records.
struct ParityCount: Equatable, Sendable {
    let kind: String
    let status: String
    let count: Int
}

/// An offline parity audit that keeps discovery records separate from reviewed definitions.
///
/// Discovery counts include independently inventoried written, preview and SDK-reference
/// records. They are not unique API operations and cannot be added to reviewed-definition
/// counts. Reviewed definitions classify only the explicitly reviewed implementation seed.
struct ParityReport: Equatable, Sendable {
    let discovery: InventoryReport
    let discoveryCounts: [ParityCount]
    let reviewedCounts: [ParityCount]
    let reviewedDefinitions: Int
    let mappedImplementedEndpoints: Int

    /// Renders deterministic Markdown tables for the two independently validated record sets.
    ///
    /// This is a pure formatting operation: it performs no I/O, reads no clock and does
    /// not claim that discovery, semantic review or runtime platform qualification is
    /// complete. Stable kind ordering and a fixed status vocabulary make repeated output
    /// byte-identical. Empty combinations are displayed as zero rather than omitted.
    ///
    /// - Returns: UTF-8-compatible Markdown ending in one newline. Discovery records and
    ///   reviewed definitions have separate tables and an explicit duplicate-record caveat.
    func renderMarkdown() -> String {
        var lines = [
            "# Validated parity records", "",
            "Counts derive from validated records. They do not certify full Discord API parity or runtime platform qualification.", "",
            "Discovery records: \(discovery.entries); pinned sources: \(discovery.sources); pending semantic review: \(discovery.pendingReview).",
            "Reviewed definitions: \(reviewedDefinitions); implemented discovery endpoints linked to reviewed definitions: \(mappedImplementedEndpoints).", "",
            "Discovery includes separate written-reference, preview-specification and SDK records for overlapping concepts. These records are not unique API operations; reviewed definitions are a separate set and must not be added to discovery totals.", "",
            "## Discovery records", "",
        ]
        lines += table(discoveryCounts)
        lines += ["", "## Reviewed definitions", ""]
        lines += table(reviewedCounts)
        return lines.joined(separator: "\n") + "\n"
    }

    /// Formats kind/status counts using a fixed column order and sorted kind names.
    ///
    /// - Parameter counts: Validated, unique kind/status combinations, all with positive
    ///   counts. Only kinds represented in the record set are emitted.
    /// - Returns: A Markdown table including per-kind totals and an overall total. This
    ///   helper is synchronous, deterministic and has no side effects.
    private func table(_ counts: [ParityCount]) -> [String] {
        let statuses = ["supported", "partial", "unsupported", "deprecated", "removed"]
        var lines = [
            "| Kind | Supported | Partial | Unsupported | Deprecated | Removed | Total |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
        ]
        for kind in Set(counts.map(\.kind)).sorted() {
            let row = counts.filter { $0.kind == kind }
            let values = statuses.map { status in row.first { $0.status == status }?.count ?? 0 }
            lines.append("| \(kind) | \(values.map(String.init).joined(separator: " | ")) | \(values.reduce(0, +)) |")
        }
        let totals = statuses.map { status in counts.filter { $0.status == status }.reduce(0) { $0 + $1.count } }
        lines.append("| Total | \(totals.map(String.init).joined(separator: " | ")) | \(totals.reduce(0, +)) |")
        return lines
    }
}

/// An evidence-linking failure after discovery and reviewed schemas have been validated.
struct ParityFailure: Error, CustomStringConvertible {
    let description: String
}

/// Joins discovery and reviewed inventories without fetching sources or modifying the repository.
enum ParityValidator {
    /// Validates both record sets and requires implemented endpoints to agree across them.
    ///
    /// The discovery audit checks pinned-source membership and classifications; the
    /// reviewed audit checks typed schemas, references, implementation symbols and evidence.
    /// Every supported or partial discovery endpoint must map to exactly one reviewed
    /// endpoint or handwritten contract with the same status and nonempty evidence references.
    /// Implemented endpoint contracts, including handwritten contracts that refer to endpoints,
    /// must retain their discovery status rather than expanding implementation claims as a
    /// side effect of schema tooling. Multiple source
    /// records may describe the same upstream operation; their independent discovery IDs
    /// remain separate counts. The operation performs bounded local reads through the
    /// reviewed validator, performs no writes or network access, and has no suspension
    /// points. It does not establish complete upstream coverage or platform qualification.
    ///
    /// - Parameters:
    ///   - reviewedData: Reviewed schema JSON, with a nonempty classified definition seed.
    ///   - inventoryData: Discovery schema-v1 JSON; every source discovery ID must occur.
    ///   - sourcesData: Pinned source-catalog JSON corresponding to `inventoryData`.
    ///   - repository: Repository root used to resolve symbol, test and fixture evidence.
    ///   - asOf: Explicit `YYYY-MM-DD` audit date used by reviewed verification-age checks;
    ///     no current time is read implicitly.
    ///   - generatedArtifacts: Optional deterministic generated Swift source bytes keyed
    ///     by repository-relative output path; defaults to no overrides. The write command
    ///     may validate these projected declarations before materializing missing outputs.
    ///     Handwritten test and fixture evidence still comes from repository files.
    /// - Returns: Separate deterministic per-kind/status counts and the number of
    ///   implemented discovery endpoints linked to reviewed definitions.
    /// - Throws: Decoding, filesystem, `InventoryFailure`, or reviewed-validation failures
    ///   propagate unchanged. `ParityFailure` identifies missing, ambiguous or conflicting
    ///   reviewed endpoint mappings; correct the records and rerun this nonwriting check.
    static func validate(
        reviewedData: Data, inventoryData: Data, sourcesData: Data, repository: URL, asOf: String,
        generatedArtifacts: [String: Data] = [:]
    ) throws -> ParityReport {
        let discovery = try InventoryValidator.validate(inventoryData: inventoryData, sourcesData: sourcesData)
        _ = try ReviewedInventoryValidator.validate(
            reviewedData: reviewedData, inventoryData: inventoryData, sourcesData: sourcesData,
            repository: repository, asOf: asOf, generatedArtifacts: generatedArtifacts
        )
        let inventory = try JSONDecoder().decode(Inventory.self, from: inventoryData)
        let reviewed = try ReviewedInventoryValidator.load(reviewedData: reviewedData)
        let implementedEndpoints = inventory.entries.filter {
            $0.kind == "endpoint" && ["supported", "partial"].contains($0.status)
        }
        let upstream = Dictionary(uniqueKeysWithValues: inventory.entries.map { ($0.id, $0) })
        var endpointMappings: [String: [ReviewedDefinition]] = [:]
        for definition in reviewed.definitions where ["endpoint", "manual"].contains(definition.kind) {
            for upstreamID in definition.upstreamIDs {
                endpointMappings[upstreamID, default: []].append(definition)
            }
            if ["supported", "partial"].contains(definition.status) {
                let endpointIDs = definition.upstreamIDs.filter { upstream[$0]?.kind == "endpoint" }
                guard (definition.kind != "endpoint" || endpointIDs.count == definition.upstreamIDs.count),
                      endpointIDs.allSatisfy({ upstream[$0]?.status == definition.status }) else {
                    throw ParityFailure(description: "Reviewed endpoint cannot expand discovery support: \(definition.id)")
                }
            }
        }
        for endpoint in implementedEndpoints {
            let mappings = endpointMappings[endpoint.id] ?? []
            guard mappings.count == 1, let definition = mappings.first else {
                throw ParityFailure(description: "Implemented discovery endpoint requires exactly one reviewed endpoint: \(endpoint.id)")
            }
            guard definition.status == endpoint.status, !definition.evidenceIDs.isEmpty else {
                throw ParityFailure(description: "Reviewed endpoint status or evidence differs from discovery: \(endpoint.id)")
            }
        }
        return ParityReport(
            discovery: discovery,
            discoveryCounts: counts(inventory.entries.map { ($0.kind, $0.status) }),
            reviewedCounts: counts(reviewed.definitions.map { ($0.kind, $0.status) }),
            reviewedDefinitions: reviewed.definitions.count,
            mappedImplementedEndpoints: implementedEndpoints.count
        )
    }

    /// Counts classified records by kind and status without collapsing overlapping concepts.
    ///
    /// - Parameter records: One pair for each validated record. Repeated pairs contribute
    ///   to the count; stable record IDs were already checked separately by each validator.
    /// - Returns: Nonzero combinations sorted lexically by kind and then status. Space is
    ///   bounded by the finite kind/status vocabulary; this pure helper performs no I/O.
    private static func counts(_ records: [(String, String)]) -> [ParityCount] {
        var grouped: [String: [String: Int]] = [:]
        for (kind, status) in records { grouped[kind, default: [:]][status, default: 0] += 1 }
        return grouped.keys.sorted().flatMap { kind in
            grouped[kind]!.keys.sorted().map { status in
                ParityCount(kind: kind, status: status, count: grouped[kind]![status]!)
            }
        }
    }
}
