import Foundation
import Testing
@testable import DiscordKitTools

/// Audits cross-inventory evidence links and deterministic counts with isolated local fixtures.
///
/// Fixtures contain only synthetic metadata and temporary source/test files. No Discord
/// request, credential, wall-clock lookup or committed repository mutation is involved.
@Suite("Validated parity reporting")
struct ParityValidatorTests {
    /// Counts every validated classification without conflating source records and definitions.
    ///
    /// The synthetic fixture has one record of each reviewed kind. All statuses are
    /// exercised independently, including states that make no implemented-endpoint claim.
    /// Repeated validation must preserve counts and the exact input byte sequences.
    /// - Parameter status: Every implementation status admitted by discovery schema v1.
    /// - Throws: Unexpected fixture creation, encoding or validation errors fail the test.
    @Test(arguments: ["supported", "partial", "unsupported", "deprecated", "removed"])
    func countsValidatedKindsAndStatuses(status: String) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        var definitions = fixture.reviewed["definitions"] as! [[String: Any]]
        for index in definitions.indices { definitions[index]["status"] = status }
        fixture.reviewed["definitions"] = definitions
        var entries = fixture.inventory["entries"] as! [[String: Any]]
        for index in entries.indices { entries[index]["status"] = status }
        fixture.inventory["entries"] = entries
        let reviewedBefore = try JSONSerialization.data(withJSONObject: fixture.reviewed, options: .sortedKeys)
        let report = try fixture.parityValidate()
        #expect(report == (try fixture.parityValidate()))
        #expect(report.reviewedDefinitions == definitions.count)
        #expect(report.discovery.entries == entries.count)
        #expect(report.reviewedCounts.reduce(0) { $0 + $1.count } == definitions.count)
        #expect(report.discoveryCounts.reduce(0) { $0 + $1.count } == entries.count)
        #expect(report.reviewedCounts.allSatisfy { $0.status == status })
        #expect(report.discoveryCounts.allSatisfy { $0.status == status })
        #expect(report.mappedImplementedEndpoints == (["supported", "partial"].contains(status) ? 1 : 0))
        #expect(report.reviewedCounts.map(\.kind) == report.reviewedCounts.map(\.kind).sorted())
        #expect(try JSONSerialization.data(withJSONObject: fixture.reviewed, options: .sortedKeys) == reviewedBefore)
    }

    /// Accepts the handwritten mapping used by Gateway endpoint execution.
    ///
    /// Converting the fixture endpoint into a manual contract retains the same stable
    /// discovery reference, implementation status and real evidence. Generation is not
    /// required to own the Gateway runtime in order for parity links to remain valid.
    @Test
    func acceptsHandwrittenImplementedEndpoint() throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        fixture.mutateParityEndpoint { endpoint in
            endpoint["kind"] = "manual"
            endpoint.removeValue(forKey: "endpoint")
            endpoint["manual"] = ["behavior": "Handwritten endpoint lifecycle with real local evidence."]
        }
        #expect(try fixture.parityValidate().mappedImplementedEndpoints == 1)
    }

    /// Rejects a supported discovery endpoint with no corresponding reviewed contract.
    ///
    /// All references remain structurally valid; changing the reviewed contract's upstream
    /// reference to a model isolates the cross-inventory coverage gate from schema failures.
    @Test
    func rejectsMissingImplementedEndpointMapping() throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        let entries = fixture.inventory["entries"] as! [[String: Any]]
        let modelID = entries.first { $0["kind"] as? String == "model" }!["id"] as! String
        fixture.mutateParityEndpoint { endpoint in
            endpoint["kind"] = "manual"
            endpoint["upstreamIDs"] = [modelID]
            endpoint.removeValue(forKey: "endpoint")
            endpoint["manual"] = ["behavior": "Unrelated handwritten model behavior."]
        }
        #expect(throws: ParityFailure.self) { try fixture.parityValidate() }
    }

    /// Requires one canonical reviewed implementation mapping for each supported discovery ID.
    ///
    /// Duplicate upstream concepts may exist in discovery; two reviewed definitions claiming
    /// the identical implemented discovery record are ambiguous even with distinct stable IDs.
    @Test
    func rejectsAmbiguousImplementedEndpointMappings() throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        var definitions = fixture.reviewed["definitions"] as! [[String: Any]]
        var duplicate = definitions.first { $0["kind"] as? String == "endpoint" }!
        duplicate["id"] = "endpoint.duplicate"
        definitions.append(duplicate)
        fixture.reviewed["definitions"] = definitions
        #expect(throws: ParityFailure.self) { try fixture.parityValidate() }
    }

    /// Rejects incompatible support classifications even when a handwritten mapping exists.
    ///
    /// The manual contract has complete symbol/evidence links and a valid partial status;
    /// its legacy discovery record remains supported, which must not silently disagree.
    @Test
    func rejectsConflictingHandwrittenEndpointStatus() throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        fixture.mutateParityEndpoint { endpoint in
            endpoint["kind"] = "manual"
            endpoint["status"] = "partial"
            endpoint.removeValue(forKey: "endpoint")
            endpoint["manual"] = ["behavior": "Partially implemented handwritten lifecycle."]
        }
        #expect(throws: ParityFailure.self) { try fixture.parityValidate() }
    }

    /// Prevents a schema-only update from promoting an unsupported discovery endpoint.
    ///
    /// The reviewed endpoint retains valid supported implementation metadata while its
    /// discovery counterpart is explicitly unsupported. Updating one record cannot widen
    /// the implementation claim across inventories without deliberate matching review.
    /// - Parameters:
    ///   - handwritten: Whether the reviewed endpoint is generated or represented by a
    ///     handwritten contract; both must preserve the same discovery classification.
    ///   - status: Each implemented classification, including partial projections.
    @Test(arguments: [false, true], ["supported", "partial"])
    func rejectsReviewedEndpointThatExpandsDiscoverySupport(handwritten: Bool, status: String) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        fixture.mutateParityEndpoint { $0["status"] = status }
        if handwritten {
            fixture.mutateParityEndpoint { endpoint in
                endpoint["kind"] = "manual"
                endpoint.removeValue(forKey: "endpoint")
                endpoint["manual"] = ["behavior": "Handwritten endpoint lifecycle."]
            }
        }
        var entries = fixture.inventory["entries"] as! [[String: Any]]
        let index = entries.firstIndex { $0["kind"] as? String == "endpoint" }!
        entries[index]["status"] = "unsupported"
        fixture.inventory["entries"] = entries
        #expect(throws: ParityFailure.self) { try fixture.parityValidate() }
    }

    /// Preserves independent overlapping discovery records when only one has been implemented.
    ///
    /// A second source-discovery ID for the same operation remains unsupported. Validated
    /// counts must include both source records while the canonical reviewed mapping counts
    /// the single implemented discovery record once.
    @Test
    func countsOverlappingDiscoveryRecordsIndependently() throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        var entries = fixture.inventory["entries"] as! [[String: Any]]
        var duplicate = entries.first { $0["kind"] as? String == "endpoint" }!
        duplicate["id"] = "upstream.endpoint.overlap"
        duplicate["status"] = "unsupported"
        duplicate["review"] = "discovered"
        duplicate["evidence"] = []
        entries.append(duplicate)
        fixture.inventory["entries"] = entries
        var sources = fixture.catalog["sources"] as! [[String: Any]]
        var ids = sources[0]["entryIDs"] as! [String]
        ids.append("upstream.endpoint.overlap")
        sources[0]["entryIDs"] = ids
        fixture.catalog["sources"] = sources
        let report = try fixture.parityValidate()
        #expect(report.discovery.entries == entries.count)
        #expect(report.discovery.pendingReview == 1)
        #expect(report.mappedImplementedEndpoints == 1)
        #expect(report.discoveryCounts.contains(ParityCount(kind: "endpoint", status: "unsupported", count: 1)))
        #expect(report.reviewedCounts.filter { $0.kind == "endpoint" }.reduce(0) { $0 + $1.count } == 1)
    }

    /// Validates projected generated declarations without materializing missing source files.
    ///
    /// Ordinary checks fail after a source is removed. The write command can supply the
    /// exact rendered bytes to validate their declarations before writing; parity validation
    /// must forward them and must leave the deleted source absent.
    @Test
    func forwardsGeneratedSourceOverridesWithoutWriting() throws {
        let fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        let symbols = fixture.reviewed["symbols"] as! [[String: Any]]
        let path = symbols[0]["path"] as! String
        let source = fixture.repository.appendingPathComponent(path)
        let data = try Data(contentsOf: source)
        try FileManager.default.removeItem(at: source)
        #expect(throws: (any Error).self) { try fixture.parityValidate() }
        #expect(try fixture.parityValidate(generatedArtifacts: [path: data]).reviewedDefinitions > 0)
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    /// Propagates missing evidence and malformed discovery metadata before producing counts.
    ///
    /// - Parameter invalid: Selects missing evidence references or an unclassified discovery
    ///   field. A failed audit must not return a partial report that could imply support.
    @Test(arguments: ["evidence", "discovery"])
    func rejectsUnvalidatedInputs(invalid: String) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        if invalid == "evidence" {
            fixture.mutateParityEndpoint { $0["evidenceIDs"] = [] }
            #expect(throws: ReviewedInventoryFailure.self) { try fixture.parityValidate() }
        } else {
            fixture.inventory["unclassified"] = true
            #expect(throws: InventoryFailure.self) { try fixture.parityValidate() }
        }
    }

    /// Confirms Markdown keeps source discoveries separate from reviewed canonical records.
    ///
    /// Counts deliberately include multiple statuses for one kind and missing combinations
    /// for another; stable row/column ordering and total arithmetic must survive repeated
    /// formatting without depending on the original input ordering.
    @Test
    func rendersDeterministicSeparateCounts() {
        let report = ParityReport(
            discovery: InventoryReport(entries: 10, sources: 2, supported: 1, pendingReview: 6),
            discoveryCounts: [
                ParityCount(kind: "field", status: "removed", count: 1),
                ParityCount(kind: "endpoint", status: "unsupported", count: 3),
                ParityCount(kind: "field", status: "supported", count: 1),
                ParityCount(kind: "field", status: "partial", count: 2),
                ParityCount(kind: "field", status: "deprecated", count: 3),
            ],
            reviewedCounts: [ParityCount(kind: "endpoint", status: "partial", count: 2)],
            reviewedDefinitions: 2, mappedImplementedEndpoints: 2
        )
        let output = report.renderMarkdown()
        #expect(output == report.renderMarkdown())
        #expect(output.contains("Discovery records: 10; pinned sources: 2; pending semantic review: 6."))
        #expect(output.contains("Reviewed definitions: 2; implemented discovery endpoints linked to reviewed definitions: 2."))
        #expect(output.contains("| endpoint | 0 | 0 | 3 | 0 | 0 | 3 |\n| field | 1 | 2 | 0 | 3 | 1 | 7 |"))
        #expect(output.contains("| Total | 1 | 2 | 3 | 3 | 1 | 10 |"))
        #expect(output.contains("## Reviewed definitions\n\n| Kind |"))
        #expect(output.contains("| endpoint | 0 | 2 | 0 | 0 | 0 | 2 |"))
        #expect(output.contains("These records are not unique API operations"))
        #expect(output.contains("do not certify full Discord API parity"))
        #expect(output.hasSuffix("\n"))
        #expect(!output.hasSuffix("\n\n"))
    }

    /// Shows absent record groups explicitly rather than inventing supported percentages.
    ///
    /// Validators require nonempty production record sets; this direct formatting boundary
    /// test verifies zero values remain well-defined if a future caller renders a filtered set.
    @Test
    func rendersEmptyCountsAsZeroTotals() {
        let report = ParityReport(
            discovery: InventoryReport(entries: 0, sources: 0, supported: 0, pendingReview: 0),
            discoveryCounts: [], reviewedCounts: [], reviewedDefinitions: 0, mappedImplementedEndpoints: 0
        )
        let output = report.renderMarkdown()
        #expect(output.components(separatedBy: "| Total | 0 | 0 | 0 | 0 | 0 | 0 |").count == 3)
    }
}

/// Shared-fixture adapters specific to cross-inventory reporting tests.
extension ReviewedFixture {
    /// Runs the complete parity gate against the current isolated metadata dictionaries.
    ///
    /// - Parameter generatedArtifacts: Optional rendered source overrides; defaults to disk
    ///   evidence. Test/fixture evidence is always read from the temporary repository.
    /// - Returns: Counts only after discovery, reviewed and cross-inventory gates pass.
    /// - Throws: JSON encoding, filesystem or production validation failures unchanged.
    func parityValidate(generatedArtifacts: [String: Data] = [:]) throws -> ParityReport {
        try ParityValidator.validate(
            reviewedData: JSONSerialization.data(withJSONObject: reviewed),
            inventoryData: JSONSerialization.data(withJSONObject: inventory),
            sourcesData: JSONSerialization.data(withJSONObject: catalog),
            repository: repository, asOf: "2026-10-16", generatedArtifacts: generatedArtifacts
        )
    }

    /// Applies a focused mutation to the fixture's one reviewed endpoint definition.
    ///
    /// - Parameter mutation: Synchronous mutation of an initially valid endpoint object.
    ///   The fixture must contain exactly one endpoint before this helper is invoked.
    ///   Metadata is replaced locally; no files or shared state are modified.
    mutating func mutateParityEndpoint(_ mutation: (inout [String: Any]) -> Void) {
        var definitions = reviewed["definitions"] as! [[String: Any]]
        let index = definitions.firstIndex { $0["kind"] as? String == "endpoint" }!
        mutation(&definitions[index])
        reviewed["definitions"] = definitions
    }
}
