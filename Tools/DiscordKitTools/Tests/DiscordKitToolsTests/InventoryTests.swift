import Foundation
import Testing
@testable import DiscordKitTools

/// Exercises the offline validator through its public-to-the-tool validation operation.
///
/// Every case starts from independent synthetic JSON documents. The fixtures contain no
/// credentials, upstream responses, network access, clocks, or shared mutable state.
@Suite("Parity inventory validation")
struct InventoryTests {
    /// Confirms a reviewed supported definition produces exact, stable report counts.
    ///
    /// Repeated validation of identical in-memory documents must have the same result;
    /// neither input is consumed or mutated by the validator.
    @Test
    func validatesSupportedFixtureRepeatedly() throws {
        let fixture = InventoryFixture.valid()
        let expected = InventoryReport(entries: 1, sources: 1, supported: 1, pendingReview: 0)
        #expect(try fixture.validate() == expected)
        #expect(try fixture.validate() == expected)
    }

    /// Verifies each documented definition kind can carry every implementation status.
    ///
    /// - Parameters:
    ///   - kind: One of the independently enumerated schema-v1 definition kinds.
    ///   - status: A supported, partial, unsupported, deprecated, or removed state.
    ///
    /// All fixtures are reviewed and have synthetic evidence, so classification alone
    /// determines whether the supported count is one or zero.
    @Test(arguments: [
        "page", "section", "endpoint", "model", "field", "enum_value", "permission",
        "intent", "opcode", "close_code", "event", "sdk_method", "protocol_state", "table_row",
    ], ["supported", "partial", "unsupported", "deprecated", "removed"])
    func acceptsEveryKindAndStatus(kind: String, status: String) throws {
        var fixture = InventoryFixture.valid()
        fixture.mutateEntries { entries in
            entries[0]["kind"] = kind
            entries[0]["status"] = status
        }
        let report = try fixture.validate()
        #expect(report.entries == 1)
        #expect(report.sources == 1)
        #expect(report.supported == (status == "supported" ? 1 : 0))
        #expect(report.pendingReview == 0)
    }

    /// Confirms access/protocol conditions remain independent of implementation status.
    ///
    /// - Parameter condition: Each schema-v1 condition, including host/access restrictions
    ///   and the explicit not-applicable classification.
    @Test(arguments: [
        "public_protocol", "approval_required", "portal_only", "unavailable_upstream",
        "undocumented_protocol", "unavailable_host", "not_applicable",
    ])
    func acceptsEveryCondition(condition: String) throws {
        var fixture = InventoryFixture.valid()
        fixture.mutateEntries { $0[0]["condition"] = condition }
        #expect(try fixture.validate().entries == 1)
    }

    /// Checks source protocol and authority vocabularies without inferring wire support.
    ///
    /// - Parameters:
    ///   - version: A baseline protocol version or explicit unversioned/not-applicable value.
    ///   - authority: A written, preview, SDK-reference, or discovery-index source category.
    @Test(arguments: ["10", "8", "unversioned", "not_applicable"], [
        "written_docs", "preview_spec", "sdk_reference", "discovery_index",
    ])
    func acceptsEverySourceClassification(version: String, authority: String) throws {
        var fixture = InventoryFixture.valid()
        fixture.mutateSources { sources in
            sources[0]["protocolVersion"] = version
            sources[0]["authority"] = authority
        }
        #expect(try fixture.validate().sources == 1)
    }

    /// Verifies supported, partial and pending-review counts remain separate.
    ///
    /// The additional definition is discovered and unsupported with no test evidence;
    /// it is valid discovery work and increments pending review, not supported coverage.
    @Test
    func countsPendingDiscoverySeparately() throws {
        var fixture = InventoryFixture.valid()
        fixture.mutateEntries { entries in
            var partial = entries[0]
            partial["id"] = "definition.partial"
            partial["status"] = "partial"
            entries.append(partial)
            var discovered = entries[0]
            discovered["id"] = "definition.discovered"
            discovered["status"] = "unsupported"
            discovered["review"] = "discovered"
            discovered["evidence"] = [String]()
            entries.append(discovered)
        }
        fixture.mutateSources { $0[0]["entryIDs"] = [
            "definition.example", "definition.partial", "definition.discovered",
        ] }
        #expect(try fixture.validate() == InventoryReport(
            entries: 3, sources: 1, supported: 1, pendingReview: 1
        ))
    }

    /// Requires both review and evidence for any complete or partial support claim.
    ///
    /// - Parameters:
    ///   - status: The claim requiring proof.
    ///   - omission: Removes review, evidence, or both while leaving valid JSON structure.
    @Test(arguments: ["supported", "partial"], ["review", "evidence", "both"])
    func rejectsUnprovenSupport(status: String, omission: String) throws {
        var fixture = InventoryFixture.valid()
        fixture.mutateEntries { entries in
            entries[0]["status"] = status
            if omission != "evidence" { entries[0]["review"] = "discovered" }
            if omission != "review" { entries[0]["evidence"] = [String]() }
        }
        #expect(throws: InventoryFailure.self) { try fixture.validate() }
    }

    /// Rejects blank evidence identifiers even when the evidence array itself is nonempty.
    ///
    /// - Parameter evidence: Empty, spaces-only, or line-break-only text that cannot name
    ///   a real verification artifact. This regresses accidentally accepting `[""]`.
    @Test(arguments: ["", " ", "\n\t"])
    func rejectsBlankSupportEvidence(evidence: String) throws {
        var fixture = InventoryFixture.valid()
        fixture.mutateEntries { $0[0]["evidence"] = ["test:valid", evidence] }
        #expect(throws: InventoryFailure.self) { try fixture.validate() }
    }

    /// Accepts discovery-only unsupported/deprecated/removed records without test evidence.
    ///
    /// - Parameters:
    ///   - status: A state that makes no current implementation support claim.
    ///   - review: Either discovery or completed semantic review, independent of support.
    @Test(arguments: ["unsupported", "deprecated", "removed"], ["discovered", "reviewed"])
    func acceptsUnimplementedDiscovery(status: String, review: String) throws {
        var fixture = InventoryFixture.valid()
        fixture.mutateEntries { entries in
            entries[0]["status"] = status
            entries[0]["review"] = review
            entries[0]["evidence"] = [String]()
        }
        let report = try fixture.validate()
        #expect(report.supported == 0)
        #expect(report.pendingReview == (review == "discovered" ? 1 : 0))
    }

    /// Rejects unknown classification strings instead of silently counting them.
    ///
    /// - Parameters:
    ///   - field: The entry vocabulary being corrupted.
    ///   - value: Empty, unknown, or incorrectly cased text outside that vocabulary.
    @Test(arguments: ["kind", "status", "condition", "review"], ["", "invented", "SUPPORTED"])
    func rejectsUnclassifiedEntries(field: String, value: String) throws {
        var fixture = InventoryFixture.valid()
        fixture.mutateEntries { $0[0][field] = value }
        #expect(throws: InventoryFailure.self) { try fixture.validate() }
    }

    /// Requires nonempty identity, human context, source linkage and locator fields.
    ///
    /// - Parameters:
    ///   - field: A required entry string whose blank value must fail structural validation.
    ///   - value: Empty or whitespace-only content, with the correct JSON string type.
    @Test(arguments: ["id", "name", "sourceID", "locator", "context"], ["", " ", "\t\n"])
    func rejectsEmptyEntryMetadata(field: String, value: String) throws {
        var fixture = InventoryFixture.valid()
        fixture.mutateEntries { $0[0][field] = value }
        #expect(throws: InventoryFailure.self) { try fixture.validate() }
    }

    /// Rejects invalid schema versions in either document independently.
    ///
    /// - Parameters:
    ///   - version: Zero, negative, future, or extreme integral schema version.
    ///   - document: Selects the inventory or source catalog; the other remains valid.
    @Test(arguments: [0, -1, 2, Int.max], ["inventory", "catalog"])
    func rejectsUnsupportedSchema(version: Int, document: String) throws {
        var fixture = InventoryFixture.valid()
        if document == "inventory" { fixture.inventory["schemaVersion"] = version }
        else { fixture.catalog["schemaVersion"] = version }
        #expect(throws: InventoryFailure.self) { try fixture.validate() }
    }

    /// Requires exact REST, Gateway and voice baseline version declarations.
    ///
    /// - Parameter versions: Missing, extra, incorrect, or incorrectly cased protocol keys.
    @Test(arguments: [
        [String: String](), ["rest": "10", "gateway": "10"],
        ["rest": "9", "gateway": "10", "voice": "8"],
        ["rest": "10", "gateway": "9", "voice": "8"],
        ["rest": "10", "gateway": "10", "voice": "7"],
        ["rest": "10", "gateway": "10", "voice": "8", "rpc": "1"],
        ["REST": "10", "gateway": "10", "voice": "8"],
    ])
    func rejectsIncorrectBaselineProtocols(versions: [String: String]) throws {
        var fixture = InventoryFixture.valid()
        fixture.inventory["protocolVersions"] = versions
        #expect(throws: InventoryFailure.self) { try fixture.validate() }
    }

    /// Exercises Gregorian leap-year and month-boundary rules through all dated records.
    ///
    /// - Parameter date: An exact calendar date including year limits and century leaps.
    ///   All three verification dates must agree, while announcement/effective dates can
    ///   independently use real Gregorian dates.
    @Test(arguments: [
        "0001-01-01", "9999-12-31", "2000-02-29", "2400-02-29", "2024-02-29",
        "1900-02-28", "2026-04-30", "2026-01-31", "2026-12-31",
    ])
    func acceptsExactGregorianDates(date: String) throws {
        var fixture = InventoryFixture.valid()
        fixture.inventory["verifiedOn"] = date
        fixture.catalog["verifiedOn"] = date
        fixture.mutateSources { sources in
            sources[0]["verifiedOn"] = date
            sources[0]["announcementDate"] = date
            sources[0]["effectiveDate"] = date
        }
        #expect(try fixture.validate().entries == 1)
    }

    /// Prevents date normalization, permissive ISO parsing and invalid Gregorian days.
    ///
    /// - Parameter date: Malformed format, zero/out-of-range components, invalid leap
    ///   days, non-ASCII digits, extra time-zone data, or disallowed unknown verification.
    @Test(arguments: [
        "", "unknown", "2026-1-01", "2026-01-1", "26-01-01", "10000-01-01",
        "0000-01-01", "2026-00-01", "2026-13-01", "2026-01-00", "2026-01-32",
        "2026-04-31", "2026-02-29", "1900-02-29", "2100-02-29", "2000-02-30",
        "2026/01/01", "２０２６-01-01", "2026-01-01Z", " 2026-01-01", "2026-01-01\n",
    ])
    func rejectsInvalidVerificationDates(date: String) throws {
        var fixture = InventoryFixture.valid()
        fixture.inventory["verifiedOn"] = date
        fixture.catalog["verifiedOn"] = date
        fixture.mutateSources { $0[0]["verifiedOn"] = date }
        #expect(throws: InventoryFailure.self) { try fixture.validate() }
    }

    /// Keeps explicitly unknown upstream dates separate from mandatory verification dates.
    ///
    /// - Parameter field: The announcement or effective date, where literal `unknown`
    ///   is accepted; case variations and malformed dates remain invalid.
    @Test(arguments: ["announcementDate", "effectiveDate"])
    func validatesOptionalUpstreamDates(field: String) throws {
        var fixture = InventoryFixture.valid()
        fixture.mutateSources { $0[0][field] = "unknown" }
        #expect(try fixture.validate().sources == 1)
        for invalid in ["Unknown", "UNKNOWN", "", "2026-02-29", "2026-01-32"] {
            fixture.mutateSources { $0[0][field] = invalid }
            #expect(throws: InventoryFailure.self) { try fixture.validate() }
        }
    }

    /// Requires the catalog, inventory and individual source verification dates to match.
    ///
    /// - Parameter document: Selects the independently stale catalog or source record.
    @Test(arguments: ["catalog", "source"])
    func rejectsMismatchedVerificationDates(document: String) throws {
        var fixture = InventoryFixture.valid()
        if document == "catalog" { fixture.catalog["verifiedOn"] = "2026-10-14" }
        else { fixture.mutateSources { $0[0]["verifiedOn"] = "2026-10-14" } }
        #expect(throws: InventoryFailure.self) { try fixture.validate() }
    }

    /// Independently rejects malformed source verification dates after valid root dates.
    ///
    /// - Parameter date: A source date that cannot serve as verification provenance even
    ///   though both enclosing documents retain their complete valid baseline date.
    @Test(arguments: ["unknown", "", "2026-02-29", "2026-10-15T00:00:00Z"])
    func rejectsInvalidSourceVerificationDate(date: String) throws {
        var fixture = InventoryFixture.valid()
        fixture.mutateSources { $0[0]["verifiedOn"] = date }
        #expect(throws: InventoryFailure.self) { try fixture.validate() }
    }

    /// Rejects empty inventories/catalogs instead of producing misleading zero-count success.
    ///
    /// - Parameter collection: Selects entries, sources, or a source's discovery membership.
    @Test(arguments: ["entries", "sources", "entryIDs"])
    func rejectsEmptyCollections(collection: String) throws {
        var fixture = InventoryFixture.valid()
        switch collection {
        case "entries": fixture.inventory["entries"] = [[String: Any]]()
        case "sources": fixture.catalog["sources"] = [[String: Any]]()
        default: fixture.mutateSources { $0[0]["entryIDs"] = [String]() }
        }
        #expect(throws: InventoryFailure.self) { try fixture.validate() }
    }

    /// Detects duplicate source identities, entry identities and discovery identities.
    ///
    /// - Parameter location: Duplicates a source, inventory entry, ID inside one source,
    ///   or ID across distinct sources. Global discovery IDs must be unique in all cases.
    @Test(arguments: ["source", "entry", "withinSource", "acrossSources"])
    func rejectsDuplicateIdentities(location: String) throws {
        var fixture = InventoryFixture.valid()
        switch location {
        case "source": fixture.mutateSources { $0.append($0[0]) }
        case "entry": fixture.mutateEntries { $0.append($0[0]) }
        case "withinSource": fixture.mutateSources {
            $0[0]["entryIDs"] = ["definition.example", "definition.example"]
        }
        default: fixture.mutateSources { sources in
            var duplicate = sources[0]
            duplicate["id"] = "source.other"
            sources.append(duplicate)
        }
        }
        #expect(throws: InventoryFailure.self) { try fixture.validate() }
    }

    /// Requires nonblank discovery IDs before membership comparison.
    ///
    /// - Parameter id: Empty or whitespace-only text that cannot identify a definition.
    @Test(arguments: ["", " ", "\t\n"])
    func rejectsEmptyDiscoveryID(id: String) throws {
        var fixture = InventoryFixture.valid()
        fixture.mutateSources { $0[0]["entryIDs"] = [id] }
        #expect(throws: InventoryFailure.self) { try fixture.validate() }
    }

    /// Checks both directions of exact pinned discovery membership.
    ///
    /// - Parameter mismatch: Adds an unrepresented discovered ID, an unpinned inventory
    ///   entry, or a reference to a nonexistent source. No mismatch may count as parity.
    @Test(arguments: ["missingEntry", "extraEntry", "unknownSource"])
    func rejectsMembershipMismatch(mismatch: String) throws {
        var fixture = InventoryFixture.valid()
        switch mismatch {
        case "missingEntry": fixture.mutateSources {
            $0[0]["entryIDs"] = ["definition.example", "definition.missing"]
        }
        case "extraEntry": fixture.mutateEntries { entries in
            var extra = entries[0]
            extra["id"] = "definition.extra"
            entries.append(extra)
        }
        default: fixture.mutateEntries { $0[0]["sourceID"] = "source.missing" }
        }
        #expect(throws: InventoryFailure.self) { try fixture.validate() }
    }

    /// Rejects a real source ID when that source did not discover the referenced entry.
    ///
    /// Two sources have disjoint valid membership, but the first entry points to the
    /// second source. A global ID-set comparison alone would miss this provenance error.
    @Test
    func rejectsEntryLinkedToWrongExistingSource() throws {
        var fixture = InventoryFixture.valid()
        fixture.mutateSources { sources in
            var second = sources[0]
            second["id"] = "source.other"
            second["entryIDs"] = ["definition.other"]
            sources.append(second)
        }
        fixture.mutateEntries { entries in
            var second = entries[0]
            second["id"] = "definition.other"
            second["sourceID"] = "source.other"
            entries.append(second)
            entries[0]["sourceID"] = "source.other"
        }
        #expect(throws: InventoryFailure.self) { try fixture.validate() }
    }

    /// Demonstrates independent sources and entries validate without relying on array order.
    ///
    /// Both source memberships are unique and the entries are reversed. Counts must use
    /// identities and links rather than index correspondence.
    @Test
    func acceptsMultipleSourcesInDifferentOrder() throws {
        var fixture = InventoryFixture.valid()
        fixture.mutateSources { sources in
            var second = sources[0]
            second["id"] = "source.other"
            second["entryIDs"] = ["definition.other"]
            sources.append(second)
        }
        fixture.mutateEntries { entries in
            var second = entries[0]
            second["id"] = "definition.other"
            second["sourceID"] = "source.other"
            entries.insert(second, at: 0)
        }
        #expect(try fixture.validate() == InventoryReport(
            entries: 2, sources: 2, supported: 2, pendingReview: 0
        ))
    }

    /// Rejects non-HTTPS or hostless provenance URLs without making network requests.
    ///
    /// - Parameter url: An empty, relative, non-HTTPS, or missing-host source location.
    @Test(arguments: ["", "not a URL", "/relative/page", "http://example.com", "file:///tmp/page", "https://"])
    func rejectsInvalidSourceURLs(url: String) throws {
        var fixture = InventoryFixture.valid()
        fixture.mutateSources { $0[0]["url"] = url }
        #expect(throws: InventoryFailure.self) { try fixture.validate() }
    }

    /// Enforces an exact lowercase 64-digit SHA-256 representation.
    ///
    /// - Parameter digest: Empty, short, long, uppercase, nonhexadecimal, whitespace, or
    ///   non-ASCII text that must not pass the source provenance check.
    @Test(arguments: [
        "", String(repeating: "a", count: 63), String(repeating: "a", count: 65),
        String(repeating: "A", count: 64), String(repeating: "g", count: 64),
        String(repeating: " ", count: 64), String(repeating: "é", count: 64),
    ])
    func rejectsInvalidSourceDigests(digest: String) throws {
        var fixture = InventoryFixture.valid()
        fixture.mutateSources { $0[0]["sha256"] = digest }
        #expect(throws: InventoryFailure.self) { try fixture.validate() }
    }

    /// Rejects unsupported source vocabularies and missing provenance/context strings.
    ///
    /// - Parameters:
    ///   - field: A source identity, revision, access/platform description, version or
    ///     authority. Each blank field must fail despite being present in JSON.
    ///   - value: Empty or whitespace-only string content with no usable provenance.
    @Test(arguments: [
        "id", "revision", "accessPrerequisites", "platformAvailability", "protocolVersion", "authority",
    ], ["", " ", "\t\n"])
    func rejectsEmptySourceMetadata(field: String, value: String) throws {
        var fixture = InventoryFixture.valid()
        fixture.mutateSources { $0[0][field] = value }
        #expect(throws: InventoryFailure.self) { try fixture.validate() }
    }

    /// Rejects source protocol/authority values outside the fixed schema vocabulary.
    ///
    /// - Parameters:
    ///   - field: Selects protocolVersion or authority.
    ///   - value: Unknown or differently cased text; valid classifications are covered above.
    @Test(arguments: ["protocolVersion", "authority"], ["9", "11", "WRITTEN_DOCS", "invented"])
    func rejectsUnknownSourceClassification(field: String, value: String) throws {
        var fixture = InventoryFixture.valid()
        fixture.mutateSources { $0[0][field] = value }
        #expect(throws: InventoryFailure.self) { try fixture.validate() }
    }

    /// Preserves normal JSON decoding failures for malformed roots in either input.
    ///
    /// - Parameters:
    ///   - malformed: Empty/truncated JSON or a structurally incompatible JSON root.
    ///   - document: The corrupted input; the other remains a valid complete fixture.
    @Test(arguments: ["", "{", "[]", "null", "{}", "42", "\"text\""], ["inventory", "catalog"])
    func rejectsMalformedJSON(malformed: String, document: String) throws {
        let fixture = InventoryFixture.valid()
        let inventory = try JSONSerialization.data(withJSONObject: fixture.inventory)
        let catalog = try JSONSerialization.data(withJSONObject: fixture.catalog)
        #expect(throws: DecodingError.self) {
            try InventoryValidator.validate(
                inventoryData: document == "inventory" ? Data(malformed.utf8) : inventory,
                sourcesData: document == "catalog" ? Data(malformed.utf8) : catalog
            )
        }
    }

    /// Ensures missing required top-level keys produce decoding errors rather than defaults.
    ///
    /// - Parameter field: A required inventory key, removed independently from valid JSON.
    @Test(arguments: ["schemaVersion", "verifiedOn", "protocolVersions", "entries"])
    func rejectsMissingInventoryFields(field: String) throws {
        var fixture = InventoryFixture.valid()
        fixture.inventory.removeValue(forKey: field)
        #expect(throws: DecodingError.self) { try fixture.validate() }
    }

    /// Ensures source catalog keys are mandatory even when the inventory is complete.
    ///
    /// - Parameter field: A required catalog key removed from otherwise valid input.
    @Test(arguments: ["schemaVersion", "verifiedOn", "sources"])
    func rejectsMissingCatalogFields(field: String) throws {
        var fixture = InventoryFixture.valid()
        fixture.catalog.removeValue(forKey: field)
        #expect(throws: DecodingError.self) { try fixture.validate() }
    }

    /// Requires all entry fields, including empty-but-required evidence arrays.
    ///
    /// - Parameter field: A required definition key removed from the first fixture entry.
    @Test(arguments: [
        "id", "kind", "name", "sourceID", "locator", "context", "status", "condition", "review", "evidence",
    ])
    func rejectsMissingEntryFields(field: String) throws {
        var fixture = InventoryFixture.valid()
        fixture.mutateEntries { $0[0].removeValue(forKey: field) }
        #expect(throws: DecodingError.self) { try fixture.validate() }
    }

    /// Requires all source fields so provenance cannot be silently omitted.
    ///
    /// - Parameter field: A required source key removed independently; unknown upstream
    ///   dates must still be represented explicitly rather than omitting their keys.
    @Test(arguments: [
        "id", "url", "revision", "sha256", "verifiedOn", "announcementDate", "effectiveDate",
        "protocolVersion", "authority", "accessPrerequisites", "platformAvailability", "entryIDs",
    ])
    func rejectsMissingSourceFields(field: String) throws {
        var fixture = InventoryFixture.valid()
        fixture.mutateSources { $0[0].removeValue(forKey: field) }
        #expect(throws: DecodingError.self) { try fixture.validate() }
    }

    /// Rejects JSON null in mandatory values instead of interpreting it as omission.
    ///
    /// - Parameter location: Corrupts an inventory field, source field, entry field,
    ///   evidence element, or discovery ID with a JSON null at the expected type boundary.
    @Test(arguments: ["inventory", "source", "entry", "evidence", "entryIDs"])
    func rejectsNullRequiredValues(location: String) throws {
        var fixture = InventoryFixture.valid()
        switch location {
        case "inventory": fixture.inventory["schemaVersion"] = NSNull()
        case "source": fixture.mutateSources { $0[0]["revision"] = NSNull() }
        case "entry": fixture.mutateEntries { $0[0]["name"] = NSNull() }
        case "evidence": fixture.mutateEntries { $0[0]["evidence"] = [NSNull()] }
        default: fixture.mutateSources { $0[0]["entryIDs"] = [NSNull()] }
        }
        #expect(throws: DecodingError.self) { try fixture.validate() }
    }

    /// Rejects incorrectly typed JSON values at top-level and nested boundaries.
    ///
    /// - Parameter location: Selects an integer, object, collection, string, evidence
    ///   element, or discovery-ID element replaced by an incompatible JSON type.
    @Test(arguments: ["schema", "protocols", "entries", "sources", "entryName", "evidence", "entryIDs"])
    func rejectsWrongJSONTypes(location: String) throws {
        var fixture = InventoryFixture.valid()
        switch location {
        case "schema": fixture.inventory["schemaVersion"] = "1"
        case "protocols": fixture.inventory["protocolVersions"] = ["rest": 10]
        case "entries": fixture.inventory["entries"] = "entry"
        case "sources": fixture.catalog["sources"] = "source"
        case "entryName": fixture.mutateEntries { $0[0]["name"] = 42 }
        case "evidence": fixture.mutateEntries { $0[0]["evidence"] = [42] }
        default: fixture.mutateSources { $0[0]["entryIDs"] = [42] }
        }
        #expect(throws: DecodingError.self) { try fixture.validate() }
    }

    /// Allows forward-compatible extra JSON fields without losing validated known fields.
    ///
    /// Unknown keys are intentionally ignored by Decodable. This does not make unknown
    /// classification values valid or establish coverage of their upstream definitions.
    @Test
    func ignoresUnknownJSONFields() throws {
        var fixture = InventoryFixture.valid()
        fixture.inventory["future"] = ["enabled": true]
        fixture.catalog["future"] = ["enabled": true]
        fixture.mutateEntries { $0[0]["future"] = ["enabled": true] }
        fixture.mutateSources { $0[0]["future"] = ["enabled": true] }
        #expect(try fixture.validate().entries == 1)
    }
}

/// Mutable JSON-only fixtures that isolate tests from checked-in baseline size and contents.
private struct InventoryFixture {
    var inventory: [String: Any]
    var catalog: [String: Any]

    /// Creates a complete schema-v1 pair containing one pinned, reviewed supported entry.
    ///
    /// The digest is syntactically valid synthetic provenance; validation deliberately
    /// checks document structure without fetching or hashing upstream content. Unknown
    /// upstream dates remain literal strings, and no secret or live resource is involved.
    ///
    /// - Returns: Fresh value dictionaries safe to mutate independently in parallel tests.
    static func valid() -> InventoryFixture {
        InventoryFixture(
            inventory: [
                "schemaVersion": 1,
                "verifiedOn": "2026-10-15",
                "protocolVersions": ["rest": "10", "gateway": "10", "voice": "8"],
                "entries": [[
                    "id": "definition.example", "kind": "endpoint", "name": "Example endpoint",
                    "sourceID": "source.example", "locator": "GET /example", "context": "Example context",
                    "status": "supported", "condition": "public_protocol", "review": "reviewed",
                    "evidence": ["test:example"],
                ]],
            ],
            catalog: [
                "schemaVersion": 1,
                "verifiedOn": "2026-10-15",
                "sources": [[
                    "id": "source.example", "url": "https://docs.discord.com/developers/reference",
                    "revision": "synthetic-snapshot-1", "sha256": String(repeating: "0123456789abcdef", count: 4),
                    "verifiedOn": "2026-10-15", "announcementDate": "unknown", "effectiveDate": "unknown",
                    "protocolVersion": "10", "authority": "written_docs",
                    "accessPrerequisites": "Documented authentication", "platformAvailability": "Portable HTTP",
                    "entryIDs": ["definition.example"],
                ]],
            ]
        )
    }

    /// Applies an isolated mutation to fixture entry dictionaries before re-encoding JSON.
    ///
    /// - Parameter mutation: A synchronous, nonescaping mutation. The fixture must retain
    ///   an array of dictionaries before this helper is called; tests may then corrupt
    ///   individual keys or replace the complete collection afterward. No I/O occurs.
    mutating func mutateEntries(_ mutation: (inout [[String: Any]]) -> Void) {
        var entries = inventory["entries"] as! [[String: Any]]
        mutation(&entries)
        inventory["entries"] = entries
    }

    /// Applies an isolated mutation to pinned source dictionaries before JSON encoding.
    ///
    /// - Parameter mutation: A synchronous, nonescaping mutation. The catalog must still
    ///   contain its original dictionary-array shape on entry; contained values may be
    ///   made invalid to exercise decoding or validation. No shared state is accessed.
    mutating func mutateSources(_ mutation: (inout [[String: Any]]) -> Void) {
        var sources = catalog["sources"] as! [[String: Any]]
        mutation(&sources)
        catalog["sources"] = sources
    }

    /// Encodes current dictionaries and runs the production audit without filesystem I/O.
    ///
    /// - Returns: The validator's report for the current fixture, without altering it.
    /// - Throws: JSON serialization errors if a test inserted a non-JSON value;
    ///   `DecodingError` or `InventoryFailure` from the production validator otherwise.
    ///   Fixtures use only JSON-compatible values, so serialization failure indicates a
    ///   test setup defect. This synchronous helper has no suspension/cancellation points.
    func validate() throws -> InventoryReport {
        try InventoryValidator.validate(
            inventoryData: JSONSerialization.data(withJSONObject: inventory),
            sourcesData: JSONSerialization.data(withJSONObject: catalog)
        )
    }
}
