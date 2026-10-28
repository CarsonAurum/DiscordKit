// File: Tools/DiscordKitTools/Tests/DiscordKitToolsTests/ReviewedInventoryTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordKitTools

/// Isolated reviewed/discovery JSON and real source/test files shared by offline tool suites.
///
/// Each instance owns a UUID-named temporary checkout. Tests must call `cleanup` in a
/// defer statement so parallel execution never shares repository files or mutable metadata.
struct ReviewedFixture {
    var reviewed: [String: Any]
    var inventory: [String: Any]
    var catalog: [String: Any]
    let repository: URL

    /// Creates an independent complete graph covering every reviewed definition kind.
    ///
    /// The synthetic source pins have no network meaning, while source/test files contain
    /// real Swift declarations and named test functions. One discovery ID corresponds to
    /// each reviewed entity; all are supported and dated within the default freshness window.
    /// - Throws: File-system errors while creating the isolated checkout or evidence files.
    init() throws {
        repository = FileManager.default.temporaryDirectory.appendingPathComponent("discordkit-review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repository.appendingPathComponent("Sources/Sample"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repository.appendingPathComponent("Tests/SampleTests"), withIntermediateDirectories: true)
        try "public struct Sample {}\n".write(to: repository.appendingPathComponent("Sources/Sample/Sample.swift"), atomically: true, encoding: .utf8)
        try "import Testing\n@Test\nfunc sampleContract() {}\n".write(to: repository.appendingPathComponent("Tests/SampleTests/SampleTests.swift"), atomically: true, encoding: .utf8)
        let ids = ["up-model", "up-field", "up-enum", "up-variant", "up-endpoint", "up-manual"]
        let kinds = ["model", "field", "model", "enum_value", "endpoint", "protocol_state"]
        let entries: [[String: Any]] = zip(ids, kinds).map { id, kind in [
            "id": id, "kind": kind, "name": id, "sourceID": "source", "locator": "L1",
            "context": "synthetic", "status": "supported", "condition": "public_protocol",
            "review": "reviewed", "evidence": ["Tests/SampleTests/SampleTests.swift"],
        ] }
        inventory = ["schemaVersion": 1, "verifiedOn": "2026-10-15", "protocolVersions": ["rest": "10", "gateway": "10", "voice": "8"], "entries": entries]
        catalog = ["schemaVersion": 1, "verifiedOn": "2026-10-15", "sources": [[
            "id": "source", "url": "https://docs.discord.com/developers/resources/user", "revision": "revision",
            "sha256": String(repeating: "a", count: 64), "verifiedOn": "2026-10-15",
            "announcementDate": "unknown", "effectiveDate": "unknown", "protocolVersion": "10",
            "authority": "written_docs", "accessPrerequisites": "synthetic", "platformAvailability": "all",
            "entryIDs": ids,
        ]]]
        var definitions: [[String: Any]] = []
        for (id, kind) in zip(["model", "field", "enum", "variant", "endpoint", "manual"], ["model", "field", "enum", "variant", "endpoint", "manual"]) {
            definitions.append([
                "id": id, "kind": kind, "name": id, "sourceID": "source", "upstreamIDs": ["up-\(id)"],
                "status": "supported", "supportSince": "2026-10-15", "announcementDate": "unknown", "effectiveDate": "unknown",
                "symbolIDs": ["symbol"], "evidenceIDs": ["test"], "notes": "Synthetic \(kind) contract.",
            ])
        }
        definitions[0]["model"] = ["fieldIDs": ["field"], "omittedUpstreamIDs": [String](), "unknownFields": "preserveExact"]
        definitions[1]["field"] = ["modelID": "model", "wireName": "id", "swiftName": "id", "valueType": "String", "optional": false, "nullable": false, "defaultBehavior": "rejectMissing", "constraints": [String](), "access": "bot", "unknownValueBehavior": "rejectWrongType"]
        definitions[2]["enum"] = ["variantIDs": ["variant"], "unknownValueBehavior": "preserveRaw"]
        definitions[3]["variant"] = ["enumID": "enum", "swiftName": "none", "rawValue": 0]
        definitions[4]["endpoint"] = ["swiftName": "currentSample", "method": "GET", "path": "/sample/@me", "authentication": "bot", "requestModelID": "none", "responseModelID": "model", "successStatuses": [200], "errorStatuses": [401, 429, 500], "rateLimit": "credential authority", "retry": "safe", "pagination": "none"]
        definitions[5]["manual"] = ["behavior": "Handwritten state machine with bounded queues."]
        reviewed = [
            "schemaVersion": 1, "verifiedOn": "2026-10-16", "maxAgeDays": 30,
            "sources": [["id": "source", "revision": "revision", "sha256": String(repeating: "a", count: 64)]],
            "definitions": definitions,
            "symbols": [["id": "symbol", "path": "Sources/Sample/Sample.swift", "declaration": "public struct Sample {}"]],
            "evidence": [["id": "test", "path": "Tests/SampleTests/SampleTests.swift", "anchor": "sampleContract"]],
        ]
    }

    /// Serializes a mutable synthetic document to deterministic UTF-8 JSON for validation.
    /// - Parameter value: JSON-compatible dictionary; unsupported values fail encoding.
    /// - Returns: Sorted-key JSON data without changing the supplied dictionary.
    /// - Throws: `JSONSerialization` errors for non-JSON values.
    func data(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    /// Audits the current mutable fixture against its owned repository and explicit clock date.
    /// - Parameters:
    ///   - asOf: Strict review date; defaults to the fixture's current date.
    ///   - generatedArtifacts: Optional rendered source overrides for bootstrap regression tests.
    /// - Returns: The tool's complete successful report.
    /// - Throws: Encoding, file or validation errors, asserted by individual test cases.
    func validate(asOf: String = "2026-10-16", generatedArtifacts: [String: Data] = [:]) throws -> ReviewedInventoryReport {
        try ReviewedInventoryValidator.validate(
            reviewedData: data(reviewed), inventoryData: data(inventory), sourcesData: data(catalog),
            repository: repository, asOf: asOf, generatedArtifacts: generatedArtifacts
        )
    }

    /// Mutates one kind's reviewed contract without exposing unsafe shared fixture state.
    /// - Parameters:
    ///   - kind: Existing synthetic kind to select; the fixture has exactly one of each.
    ///   - mutation: Synchronous in-place edit of the selected JSON definition.
    mutating func change(_ kind: String, _ mutation: (inout [String: Any]) -> Void) {
        var definitions = reviewed["definitions"] as! [[String: Any]]
        let index = definitions.firstIndex { $0["kind"] as? String == kind }!
        mutation(&definitions[index])
        reviewed["definitions"] = definitions
    }

    /// Releases the isolated temporary checkout after each test, including failing assertions.
    ///
    /// Cleanup errors are ignored because no persistent project files are owned by this fixture;
    /// test validation assertions retain their primary failure rather than masking it.
    func cleanup() {
        try? FileManager.default.removeItem(at: repository)
    }
}

/// Exercises closed schema decoding, graph semantics, provenance, freshness and real evidence.
@Suite("Reviewed inventory contracts")
struct ReviewedInventoryTests {
    /// Confirms every kind is counted and repeated offline validation is pure and stable.
    /// - Throws: Unexpected fixture setup or audit failures fail the test.
    @Test
    func validatesCompleteGraphRepeatedly() throws {
        let fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        let report = try fixture.validate()
        #expect(report == ReviewedInventoryReport(definitions: 6, sources: 1, symbols: 1, evidence: 1, models: 1, fields: 1, enums: 1, variants: 1, endpoints: 1, manual: 1, events: 0))
        #expect(try fixture.validate() == report)
        let decoded = try ReviewedInventoryValidator.load(reviewedData: fixture.data(fixture.reviewed))
        #expect(decoded.definitions.count == 6)
        #expect(decoded.definitions.first { $0.kind == "field" }?.field?.optional == false)
        #expect(try ReviewedInventoryValidator.load(reviewedData: JSONEncoder().encode(decoded)) == decoded)
    }

    /// Rejects unknown properties at every schema object boundary and misplaced union contracts.
    /// - Parameter location: Root, reference, definition or kind-specific contract to corrupt.
    /// - Throws: Unexpected fixture setup/encoding errors fail the test.
    @Test(arguments: ["root", "source", "symbol", "evidence", "definition", "model", "field", "enum", "variant", "endpoint", "manual", "wrongContract"])
    func rejectsUnknownKeys(location: String) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        if location == "root" { fixture.reviewed["typo"] = true }
        else if ["source", "symbol", "evidence"].contains(location) {
            let key = location == "source" ? "sources" : location == "symbol" ? "symbols" : "evidence"
            var values = fixture.reviewed[key] as! [[String: Any]]
            values[0]["typo"] = true
            fixture.reviewed[key] = values
        } else {
            fixture.change(location == "definition" || location == "wrongContract" ? "model" : location) { value in
                if location == "definition" { value["typo"] = true }
                else if location == "wrongContract" { value["manual"] = ["behavior": "wrong"] }
                else {
                    var metadata = value[location] as! [String: Any]
                    metadata["typo"] = true
                    value[location] = metadata
                }
            }
        }
        #expect(throws: ReviewedInventoryFailure.self) { try fixture.validate() }
    }

    /// Ensures missing/null/type errors cannot become defaulted or inferred review metadata.
    /// - Parameter corruption: Required field, optional-null, root or scalar shape to corrupt.
    /// - Throws: Unexpected setup/encoding errors fail the test.
    @Test(arguments: ["missingRoot", "nullRoot", "arrayRoot", "emptyJSON", "wrongBoolean", "nullCodec", "nullDirection", "missingField", "unknownKind"])
    func rejectsMalformedShapes(corruption: String) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        switch corruption {
        case "missingRoot": fixture.reviewed.removeValue(forKey: "verifiedOn")
        case "nullRoot": fixture.reviewed["verifiedOn"] = NSNull()
        case "wrongBoolean": fixture.change("field") { value in var field = value["field"] as! [String: Any]; field["optional"] = "false"; value["field"] = field }
        case "nullCodec", "nullDirection": fixture.change("model") { value in var model = value["model"] as! [String: Any]; model[corruption == "nullCodec" ? "codec" : "direction"] = NSNull(); value["model"] = model }
        case "missingField": fixture.change("field") { value in var field = value["field"] as! [String: Any]; field.removeValue(forKey: "nullable"); value["field"] = field }
        case "unknownKind": fixture.change("model") { $0["kind"] = "future" }
        case "arrayRoot":
            #expect(throws: (any Error).self) { try ReviewedInventoryValidator.load(reviewedData: Data("[]".utf8)) }
            return
        default:
            #expect(throws: (any Error).self) { try ReviewedInventoryValidator.load(reviewedData: Data()) }
            return
        }
        #expect(throws: (any Error).self) { try fixture.validate() }
    }

    /// Audits every explicit presence combination without conflating absence with JSON null.
    /// - Parameters:
    ///   - optional: Whether the field may be absent.
    ///   - nullable: Whether an explicitly present field may be null.
    /// - Throws: Unexpected fixture setup/validation errors fail the test.
    @Test(arguments: [false, true], [false, true])
    func acceptsIndependentPresenceRules(optional: Bool, nullable: Bool) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        fixture.change("field") { value in var field = value["field"] as! [String: Any]; field["optional"] = optional; field["nullable"] = nullable; value["field"] = field }
        #expect(try fixture.validate().fields == 1)
    }

    /// Rejects unsupported classification vocabularies and incomplete behavioral contracts.
    /// - Parameter corruption: Contract invariant deliberately violated by one mutation.
    /// - Throws: Unexpected fixture setup/encoding errors fail the test.
    @Test(arguments: ["schema", "empty", "status", "notes", "type", "swiftName", "default", "access", "unknownValue", "constraints", "unknownFields", "codec", "direction", "enumUnknown", "method", "path", "auth", "request", "response", "success", "error", "duplicateStatus", "retry", "pagination", "rateLimit", "manual"])
    func rejectsUnclassifiedOrIncompleteContracts(corruption: String) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        switch corruption {
        case "schema": fixture.reviewed["schemaVersion"] = 2
        case "empty": fixture.reviewed["definitions"] = [[String: Any]]()
        case "status": fixture.change("field") { $0["status"] = "unknown" }
        case "notes": fixture.change("field") { $0["notes"] = "  " }
        case "type", "swiftName", "default", "access", "unknownValue", "constraints":
            fixture.change("field") { value in
                var field = value["field"] as! [String: Any]
                let keys = ["type": "valueType", "swiftName": "swiftName", "default": "defaultBehavior", "access": "access", "unknownValue": "unknownValueBehavior", "constraints": "constraints"]
                field[keys[corruption]!] = corruption == "constraints" ? ["duplicate", "duplicate"] : corruption == "type" ? "Future" : corruption == "swiftName" ? "bad-name" : " "
                value["field"] = field
            }
        case "unknownFields", "codec", "direction": fixture.change("model") { value in var metadata = value["model"] as! [String: Any]; metadata[corruption] = "future"; value["model"] = metadata }
        case "enumUnknown": fixture.change("enum") { value in var metadata = value["enum"] as! [String: Any]; metadata["unknownValueBehavior"] = " "; value["enum"] = metadata }
        case "manual": fixture.change("manual") { $0["manual"] = ["behavior": " "] }
        default:
            fixture.change("endpoint") { value in
                var endpoint = value["endpoint"] as! [String: Any]
                let keys = ["method": "method", "path": "path", "auth": "authentication", "request": "requestModelID", "response": "responseModelID", "success": "successStatuses", "error": "errorStatuses", "duplicateStatus": "successStatuses", "retry": "retry", "pagination": "pagination", "rateLimit": "rateLimit"]
                let replacements: [String: Any] = ["method": "TRACE", "path": "relative", "auth": "future", "request": "missing", "response": "missing", "success": [400], "error": [200], "duplicateStatus": [200, 200], "retry": " ", "pagination": " ", "rateLimit": " "]
                endpoint[keys[corruption]!] = replacements[corruption]!
                value["endpoint"] = endpoint
            }
        }
        #expect(throws: ReviewedInventoryFailure.self) { try fixture.validate() }
    }

    /// Rejects missing references, orphan resources and duplicate global or relationship IDs.
    /// - Parameter corruption: Identity/link invariant deliberately violated.
    /// - Throws: Unexpected fixture setup/encoding errors fail the test.
    @Test(arguments: ["definitionID", "symbolID", "evidenceID", "crossID", "upstream", "source", "duplicateUpstream", "modelFields", "fieldParent", "enumVariants", "variantParent", "orphanSymbol", "orphanEvidence", "missingSymbol", "missingEvidence", "omitted", "overlap", "supportedOmission", "partialChild", "partialVariant", "partialResponse"])
    func rejectsBrokenGraph(corruption: String) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        switch corruption {
        case "definitionID": fixture.change("field") { $0["id"] = "model" }
        case "symbolID", "evidenceID":
            let key = corruption == "symbolID" ? "symbols" : "evidence"
            let values = fixture.reviewed[key] as! [[String: Any]]
            fixture.reviewed[key] = values + values
        case "crossID": fixture.change("manual") { $0["id"] = "symbol" }
        case "upstream": fixture.change("field") { $0["upstreamIDs"] = ["missing"] }
        case "source": fixture.change("field") { $0["sourceID"] = "missing" }
        case "duplicateUpstream": fixture.change("field") { $0["upstreamIDs"] = ["up-field", "up-field"] }
        case "modelFields": fixture.change("model") { $0["model"] = ["fieldIDs": ["missing"], "omittedUpstreamIDs": [String](), "unknownFields": "preserveExact"] }
        case "fieldParent": fixture.change("field") { value in var metadata = value["field"] as! [String: Any]; metadata["modelID"] = "missing"; value["field"] = metadata }
        case "enumVariants": fixture.change("enum") { $0["enum"] = ["variantIDs": ["missing"], "unknownValueBehavior": "preserveRaw"] }
        case "variantParent": fixture.change("variant") { value in var metadata = value["variant"] as! [String: Any]; metadata["enumID"] = "missing"; value["variant"] = metadata }
        case "orphanSymbol": var values = fixture.reviewed["symbols"] as! [[String: Any]]; var extra = values[0]; extra["id"] = "unused"; values.append(extra); fixture.reviewed["symbols"] = values
        case "orphanEvidence": var values = fixture.reviewed["evidence"] as! [[String: Any]]; var extra = values[0]; extra["id"] = "unused"; values.append(extra); fixture.reviewed["evidence"] = values
        case "missingSymbol": fixture.change("manual") { $0["symbolIDs"] = [String]() }
        case "missingEvidence": fixture.change("manual") { $0["evidenceIDs"] = [String]() }
        case "partialChild": fixture.change("field") { $0["status"] = "partial" }
        case "partialVariant": fixture.change("variant") { $0["status"] = "partial" }
        case "partialResponse": fixture.change("model") { $0["status"] = "partial" }
        default: fixture.change("model") { value in var model = value["model"] as! [String: Any]; model["omittedUpstreamIDs"] = [corruption == "omitted" ? "missing" : corruption == "overlap" ? "up-field" : "up-manual"]; value["model"] = model }
        }
        #expect(throws: ReviewedInventoryFailure.self) { try fixture.validate() }
    }

    /// Keeps unknown upstream dates independent from known local support chronology.
    /// - Parameter corruption: Invalid upstream/local date, including impossible Gregorian days.
    /// - Throws: Unexpected fixture setup/encoding errors fail the test.
    @Test(arguments: ["supportUnknown", "futureSupport", "invalidLeap", "invalidAnnouncement", "invalidEffective"])
    func rejectsInvalidSupportChronology(corruption: String) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        fixture.change("manual") { value in
            switch corruption {
            case "supportUnknown": value["supportSince"] = "unknown"
            case "futureSupport": value["supportSince"] = "2026-10-17"
            case "invalidLeap": value["supportSince"] = "2025-02-29"
            case "invalidAnnouncement": value["announcementDate"] = "2026-02-30"
            default: value["effectiveDate"] = "2026-1-01"
            }
        }
        #expect(throws: ReviewedInventoryFailure.self) { try fixture.validate() }
    }

    /// Tests deterministic freshness boundaries, malformed dates and exact source hash/revision pins.
    /// - Parameter corruption: Clock, source pin or freshness-budget invariant to break.
    /// - Throws: Unexpected setup/encoding errors fail the test.
    @Test(arguments: ["stale", "future", "invalidAsOf", "invalidVerified", "budgetZero", "budgetExtreme", "revision", "hash", "pinID", "duplicatePin"])
    func rejectsStaleOrChangedSources(corruption: String) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        var asOf = "2026-10-16"
        switch corruption {
        case "stale": asOf = "2026-11-16"
        case "future": asOf = "2026-10-14"
        case "invalidAsOf": asOf = "2026-02-30"
        case "invalidVerified": fixture.reviewed["verifiedOn"] = "0000-01-01"
        case "budgetZero": fixture.reviewed["maxAgeDays"] = 0
        case "budgetExtreme": fixture.reviewed["maxAgeDays"] = Int.max
        default:
            var pins = fixture.reviewed["sources"] as! [[String: Any]]
            if corruption == "duplicatePin" { pins += pins }
            else { pins[0][corruption == "pinID" ? "id" : corruption == "hash" ? "sha256" : "revision"] = "changed" }
            fixture.reviewed["sources"] = pins
        }
        #expect(throws: ReviewedInventoryFailure.self) { try fixture.validate(asOf: asOf) }
    }

    /// Accepts the inclusive source-age boundary while refusing one day past that budget.
    /// - Throws: Unexpected setup/validation failures fail the test.
    @Test
    func freshnessBoundaryIsInclusive() throws {
        let fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        #expect(try fixture.validate(asOf: "2026-11-14").definitions == 6)
        #expect(throws: ReviewedInventoryFailure.self) { try fixture.validate(asOf: "2026-11-15") }
    }

    /// Rejects fake declaration/evidence strings and every unsafe filesystem path form.
    /// - Parameter corruption: Real-file or containment invariant to violate.
    /// - Throws: Unexpected fixture setup/encoding errors fail the test.
    @Test(arguments: ["symbol", "test", "commentTest", "absolute", "traversal", "directory", "sourceSymlink", "testSymlink", "outsideEvidence", "nonDeclaration", "missingFile"])
    func requiresRealContainedEvidence(corruption: String) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        var symbols = fixture.reviewed["symbols"] as! [[String: Any]]
        var evidence = fixture.reviewed["evidence"] as! [[String: Any]]
        switch corruption {
        case "symbol": symbols[0]["declaration"] = "public struct Missing {}"
        case "test": evidence[0]["anchor"] = "missingContract"
        case "commentTest": try "// func sampleContract() {}\n".write(to: fixture.repository.appendingPathComponent("Tests/SampleTests/SampleTests.swift"), atomically: true, encoding: .utf8)
        case "absolute": symbols[0]["path"] = "/tmp/file.swift"
        case "traversal": symbols[0]["path"] = "Sources/../Sample.swift"
        case "directory": symbols[0]["path"] = "Sources/Sample.swift"; try FileManager.default.createDirectory(at: fixture.repository.appendingPathComponent("Sources/Sample.swift"), withIntermediateDirectories: true)
        case "sourceSymlink": symbols[0]["path"] = "Sources/Outside.swift"; try FileManager.default.createSymbolicLink(at: fixture.repository.appendingPathComponent("Sources/Outside.swift"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        case "testSymlink": evidence[0]["path"] = "Tests/Outside.swift"; try FileManager.default.createSymbolicLink(at: fixture.repository.appendingPathComponent("Tests/Outside.swift"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        case "outsideEvidence": evidence[0]["path"] = "Sources/Sample/Sample.swift"
        case "nonDeclaration": symbols[0]["declaration"] = "import Foundation"
        default: symbols[0]["path"] = "Sources/Missing.swift"
        }
        fixture.reviewed["symbols"] = symbols; fixture.reviewed["evidence"] = evidence
        #expect(throws: (any Error).self) { try fixture.validate() }
    }

    /// Resolves fixture case IDs structurally, ignoring accidental matching strings elsewhere.
    /// - Parameter scenario: Exact ID, unrelated text, duplicate ID or malformed fixture input.
    /// - Throws: Unexpected fixture setup/file/encoding errors fail the test.
    @Test(arguments: ["valid", "unrelated", "duplicate", "malformed"])
    func checksStructuredFixtureAnchors(scenario: String) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        let path = fixture.repository.appendingPathComponent("Tests/SampleTests/cases.json")
        let payload: String
        switch scenario {
        case "valid": payload = #"{"cases":[{"id":"sample-case"}]}"#
        case "unrelated": payload = #"{"notes":"sample-case","cases":[{"id":"other"}]}"#
        case "duplicate": payload = #"{"cases":[{"id":"sample-case"},{"id":"sample-case"}]}"#
        default: payload = "[]"
        }
        try payload.write(to: path, atomically: true, encoding: .utf8)
        fixture.reviewed["evidence"] = [["id": "test", "path": "Tests/SampleTests/cases.json", "anchor": "sample-case"]]
        if scenario == "valid" { #expect(try fixture.validate().evidence == 1) }
        else { #expect(throws: ReviewedInventoryFailure.self) { try fixture.validate() } }
    }

    /// Allows deterministic generation to restore missing Swift outputs while requiring disk tests.
    /// - Throws: Unexpected fixture setup, deletion or validation failures fail the test.
    @Test
    func bootstrapUsesRenderedSourcesButNeverFabricatesEvidence() throws {
        let fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        try FileManager.default.removeItem(at: fixture.repository.appendingPathComponent("Sources/Sample/Sample.swift"))
        #expect(throws: (any Error).self) { try fixture.validate() }
        let artifacts = ["Sources/Sample/Sample.swift": Data("public struct Sample {}\n".utf8)]
        #expect(try fixture.validate(generatedArtifacts: artifacts).symbols == 1)
        try FileManager.default.removeItem(at: fixture.repository.appendingPathComponent("Tests/SampleTests/SampleTests.swift"))
        #expect(throws: (any Error).self) { try fixture.validate(generatedArtifacts: artifacts) }
    }

    /// Recognizes real Swift Testing attributes on either the function line or preceding lines.
    ///
    /// Same-line actor isolation, parameterized attributes and stacked availability are common
    /// in the runtime suites. An unannotated helper and comments must not establish support.
    /// - Parameter form: Conventional source declaration shape to validate or reject.
    /// - Throws: Unexpected isolated fixture setup, file writing or audit errors fail the test.
    @Test(arguments: ["sameLine", "stacked", "actor", "arguments", "helper", "comment", "attributeText"])
    func resolvesOnlyActualSwiftTestingFunctions(form: String) throws {
        let fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        let source: String
        switch form {
        case "sameLine": source = "@Test func sampleContract() {}"
        case "stacked": source = "@available(macOS 15, *)\n@Test\nfunc sampleContract() {}"
        case "actor": source = "@MainActor @Test func sampleContract() {}"
        case "arguments": source = "@Test(arguments: [1, 2])\nfunc sampleContract(value: Int) {}"
        case "helper": source = "func sampleContract() {}"
        case "attributeText": source = "@Other(\" @Test \") func sampleContract() {}"
        default: source = "// @Test func sampleContract() {}"
        }
        try source.write(to: fixture.repository.appendingPathComponent("Tests/SampleTests/SampleTests.swift"), atomically: true, encoding: .utf8)
        if ["helper", "comment", "attributeText"].contains(form) {
            #expect(throws: ReviewedInventoryFailure.self) { try fixture.validate() }
        } else { #expect(try fixture.validate().evidence == 1) }
    }

    /// Requires exhaustive classified membership within a model's precise upstream field group.
    ///
    /// A newly discovered field must be deliberately implemented or explicitly omitted. Nested
    /// and unrelated field groups remain separate projections even when their source is shared.
    /// - Parameter scenario: New field omitted, acknowledged, unrelated or mismatched upstream kind.
    /// - Throws: Unexpected setup, JSON mutation or validation failures fail the test.
    @Test(arguments: ["unclassified", "omitted", "unrelated", "wrongKind", "wrongFieldKind", "mixedContext"])
    func classifiesEveryFieldInTheReviewedModelGroup(scenario: String) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        if scenario == "wrongKind" || scenario == "wrongFieldKind" {
            var entries = fixture.inventory["entries"] as! [[String: Any]]
            let index = entries.firstIndex { $0["id"] as? String == (scenario == "wrongKind" ? "up-model" : "up-field") }!
            entries[index]["kind"] = "endpoint"
            fixture.inventory["entries"] = entries
            #expect(throws: ReviewedInventoryFailure.self) { try fixture.validate() }
            return
        }
        var entries = fixture.inventory["entries"] as! [[String: Any]]
        var added = entries.first { $0["kind"] as? String == "field" }!
        added["id"] = "up-new-field"
        added["context"] = scenario == "unrelated" ? "synthetic > Nested Object" : "synthetic"
        entries.append(added)
        fixture.inventory["entries"] = entries
        var sources = fixture.catalog["sources"] as! [[String: Any]]
        var ids = sources[0]["entryIDs"] as! [String]
        ids.append("up-new-field"); sources[0]["entryIDs"] = ids; fixture.catalog["sources"] = sources
        if scenario == "omitted" {
            fixture.change("model") { definition in
                definition["status"] = "partial"
                var model = definition["model"] as! [String: Any]
                model["omittedUpstreamIDs"] = ["up-new-field"]
                definition["model"] = model
            }
            fixture.change("endpoint") { $0["status"] = "partial" }
        }
        if scenario == "mixedContext" {
            fixture.change("field") { $0["upstreamIDs"] = ["up-field", "up-new-field"] }
            entries[entries.count - 1]["context"] = "other field group"
            fixture.inventory["entries"] = entries
        }
        if scenario == "omitted" || scenario == "unrelated" { #expect(try fixture.validate().models == 1) }
        else { #expect(throws: ReviewedInventoryFailure.self) { try fixture.validate() } }
    }

    /// Permits only codec policies actually implemented by the corresponding generation strategy.
    /// - Parameters:
    ///   - codec: Bounded raw-preserving decoding or ordinary Codable generation.
    ///   - policy: Requested unknown-field behavior, including deliberately incompatible choices.
    /// - Throws: Unexpected fixture setup or audit failures fail the test.
    @Test(arguments: ["boundedJSON", "codable"], ["preserveExact", "ignore", "discard", "reject"])
    func requiresCodecAndUnknownFieldBehaviorToAgree(codec: String, policy: String) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        fixture.change("model") { definition in
            var model = definition["model"] as! [String: Any]
            model["codec"] = codec; model["unknownFields"] = policy
            definition["model"] = model
        }
        let valid = codec == "boundedJSON" ? policy == "preserveExact" : ["ignore", "discard"].contains(policy)
        if valid { #expect(try fixture.validate().models == 1) }
        else { #expect(throws: ReviewedInventoryFailure.self) { try fixture.validate() } }
    }

    /// Accepts real leap dates without replacing explicit unknown upstream chronology.
    /// - Throws: Unexpected setup/validation failures fail the test.
    @Test
    func acceptsKnownGregorianLeapDatesAndUnknownDatesIndependently() throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        fixture.change("manual") { $0["announcementDate"] = "2000-02-29"; $0["effectiveDate"] = "2024-02-29" }
        #expect(try fixture.validate().manual == 1)
    }

}
