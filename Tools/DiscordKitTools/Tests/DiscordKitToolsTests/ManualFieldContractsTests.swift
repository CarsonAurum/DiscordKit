// File: Tools/DiscordKitTools/Tests/DiscordKitToolsTests/ManualFieldContractsTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordKitTools

/// Audits handwritten field semantics without changing the finite source generator's vocabulary.
/// Each test owns an isolated checkout with real declaration/evidence files and pinned discovery IDs.
@Suite("Handwritten field contracts")
struct ManualFieldContractsTests {
    /// Existing behavior-only documents decode unchanged, and explicit construction defaults fields to nil.
    /// - Throws: Unexpected fixture setup, decoding or validation errors fail the test.
    @Test func behaviorOnlyCompatibility() throws {
        let fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        let value = try ReviewedInventoryValidator.load(reviewedData: fixture.data(fixture.reviewed))
        let manual = try #require(value.definitions.first { $0.kind == "manual" }?.manual)
        #expect(manual.fields == nil)
        #expect(ReviewedManual(behavior: manual.behavior) == manual)
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(manual)) as? [String: Any])
        #expect(Set(encoded.keys) == ["behavior"])
        #expect(try fixture.validate().manual == 1)
    }

    /// Field contracts preserve independent absent/null rules and accept semantic types outside generated enums.
    /// - Parameters:
    ///   - optional: Whether the wire key may be absent, independently of explicit JSON null.
    ///   - nullable: Whether a present value may be null, independently of key absence.
    /// - Throws: Unexpected setup, provenance, encoding or validation errors fail the test.
    @Test(arguments: [false, true], [false, true])
    func validatesSemanticFields(optional: Bool, nullable: Bool) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        try fixture.addManualFieldContracts()
        fixture.changeManualField { field in
            field["optional"] = optional
            field["nullable"] = nullable
            field["valueType"] = "Field<[RawValue<FutureSemanticType>]>"
        }
        let report = try fixture.validate()
        #expect(report.manual == 1)
        #expect(report.fields == 1)
        #expect(report.symbols == 2)
        #expect(try fixture.validate() == report)
        let decoded = try ReviewedInventoryValidator.load(reviewedData: fixture.data(fixture.reviewed))
        let field = try #require(decoded.definitions.first { $0.kind == "manual" }?.manual?.fields?.first)
        #expect(field.optional == optional)
        #expect(field.nullable == nullable)
        #expect(field.wireName == "id")
        #expect(field.swiftName == "identifier")
        #expect(field.valueType == "Field<[RawValue<FutureSemanticType>]>")
        #expect(field.upstreamIDs == ["up-field"])
        #expect(field.symbolID == "field-symbol")
        #expect(try ReviewedInventoryValidator.load(reviewedData: JSONEncoder().encode(decoded)) == decoded)
    }

    /// New metadata cannot silently admit typos, missing values, nullable records or mistyped containers.
    /// - Parameter corruption: One closed-shape, required-field or JSON-type invariant to violate.
    /// - Throws: Unexpected fixture setup/encoding errors fail the test; each validation must throw.
    @Test(arguments: ["unknownManual", "unknownField", "missing", "nullArray", "wrongArray", "nullField",
                      "scalarField", "nullValue", "wrongBoolean", "wrongConstraints", "wrongUpstream", "wrongSymbol"])
    func rejectsMalformedShapes(corruption: String) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        try fixture.addManualFieldContracts()
        if ["unknownManual", "nullArray", "wrongArray", "nullField", "scalarField"].contains(corruption) {
            fixture.change("manual") { definition in
                var manual = definition["manual"] as! [String: Any]
                switch corruption {
                case "unknownManual": manual["future"] = true
                case "nullArray": manual["fields"] = NSNull()
                case "wrongArray": manual["fields"] = ["wireName": "id"]
                case "nullField": manual["fields"] = [NSNull()]
                default: manual["fields"] = ["not-an-object"]
                }
                definition["manual"] = manual
            }
        } else {
            fixture.changeManualField { field in
                switch corruption {
                case "unknownField": field["future"] = true
                case "missing": field.removeValue(forKey: "access")
                case "nullValue": field["valueType"] = NSNull()
                case "wrongBoolean": field["optional"] = "false"
                case "wrongConstraints": field["constraints"] = "nonempty"
                case "wrongUpstream": field["upstreamIDs"] = [1]
                default: field["symbolID"] = 7
                }
            }
        }
        #expect(throws: (any Error).self) { try fixture.validate() }
    }

    /// Every descriptive scalar is nonblank and single-line, while Swift names use the existing identifier grammar.
    /// - Parameter key: Field metadata property to replace with blank text, a control, or a line separator.
    /// - Throws: Unexpected setup/encoding failures fail the test; invalid metadata must be rejected.
    @Test(arguments: ["wireName", "swiftName", "valueType", "defaultBehavior", "access", "unknownValueBehavior"])
    func rejectsUnsafeMetadata(key: String) throws {
        for replacement in [" \t", "a\nb", "a\u{0000}b", "a\u{2028}b", "a\u{2029}b"] {
            var fixture = try ReviewedFixture()
            defer { fixture.cleanup() }
            try fixture.addManualFieldContracts()
            fixture.changeManualField { $0[key] = replacement }
            #expect(throws: ReviewedInventoryFailure.self) { try fixture.validate() }
        }
        if key == "swiftName" {
            var fixture = try ReviewedFixture()
            defer { fixture.cleanup() }
            try fixture.addManualFieldContracts()
            fixture.changeManualField { $0[key] = "bad-name" }
            #expect(throws: ReviewedInventoryFailure.self) { try fixture.validate() }
        }
    }

    /// Semantic link validation requires nonempty unique contracts and exact parent-owned field/symbol evidence.
    /// - Parameter corruption: Name, constraint, discovery or symbol relationship to invalidate.
    /// - Throws: Unexpected fixture setup/encoding failures fail the test; semantic audits must throw.
    @Test(arguments: ["empty", "duplicateWire", "duplicateSwift", "duplicateConstraint", "blankConstraint",
                      "controlConstraint", "emptyUpstream", "duplicateUpstream", "missingUpstream", "unlinkedUpstream",
                      "wrongKind", "missingSymbol", "unlinkedSymbol", "missingDeclaration", "wrongSource"])
    func rejectsBrokenRelationships(corruption: String) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        try fixture.addManualFieldContracts()
        switch corruption {
        case "empty", "duplicateWire", "duplicateSwift":
            fixture.change("manual") { definition in
                var manual = definition["manual"] as! [String: Any]
                var fields = manual["fields"] as! [[String: Any]]
                if corruption == "empty" { fields = [] }
                else {
                    var second = fields[0]
                    second[corruption == "duplicateWire" ? "swiftName" : "wireName"] = "different"
                    fields.append(second)
                }
                manual["fields"] = fields
                definition["manual"] = manual
            }
        case "unlinkedUpstream": fixture.change("manual") { $0["upstreamIDs"] = ["up-manual"] }
        case "unlinkedSymbol": fixture.change("manual") { $0["symbolIDs"] = ["symbol"] }
        case "missingDeclaration":
            try "public struct Different {}\n".write(to: fixture.repository.appendingPathComponent("Sources/Sample/Fields.swift"), atomically: true, encoding: .utf8)
        case "wrongSource":
            var sources = fixture.catalog["sources"] as! [[String: Any]]
            var other = sources[0]
            other["id"] = "other-source"
            other["entryIDs"] = ["other-field"]
            sources.append(other)
            fixture.catalog["sources"] = sources
            var entries = fixture.inventory["entries"] as! [[String: Any]]
            var otherField = entries.first { $0["id"] as? String == "up-field" }!
            otherField["id"] = "other-field"; otherField["sourceID"] = "other-source"
            entries.append(otherField)
            fixture.inventory["entries"] = entries
            fixture.change("manual") { $0["upstreamIDs"] = ["up-manual", "up-field", "other-field"] }
            fixture.changeManualField { $0["upstreamIDs"] = ["other-field"] }
        default:
            if corruption == "wrongKind" {
                fixture.change("manual") { $0["upstreamIDs"] = ["up-manual", "up-field", "up-model"] }
            }
            fixture.changeManualField { field in
                switch corruption {
                case "duplicateConstraint": field["constraints"] = ["exact", "exact"]
                case "blankConstraint": field["constraints"] = [" "]
                case "controlConstraint": field["constraints"] = ["a\nb"]
                case "emptyUpstream": field["upstreamIDs"] = [String]()
                case "duplicateUpstream": field["upstreamIDs"] = ["up-field", "up-field"]
                case "missingUpstream": field["upstreamIDs"] = ["missing"]
                case "wrongKind": field["upstreamIDs"] = ["up-model"]
                default: field["symbolID"] = "missing"
                }
            }
        }
        #expect(throws: ReviewedInventoryFailure.self) { try fixture.validate() }
    }

    /// Generator artifacts remain byte-identical because handwritten field types never enter emitted source.
    /// - Throws: Unexpected fixture, reviewed decoding or generation failures fail the test.
    @Test func handwrittenFieldsDoNotGenerateDeclarations() throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        try fixture.addManualFieldContracts()
        fixture.change("enum") { $0["name"] = "SampleEnum" }
        let withFields = try ReviewedInventoryValidator.load(reviewedData: fixture.data(fixture.reviewed))
        fixture.change("manual") { definition in
            var manual = definition["manual"] as! [String: Any]
            manual.removeValue(forKey: "fields")
            definition["manual"] = manual
        }
        let withoutFields = try ReviewedInventoryValidator.load(reviewedData: fixture.data(fixture.reviewed))
        #expect(try Generator.render(withFields) == Generator.render(withoutFields))
    }
}

extension ReviewedFixture {
    /// Adds one realistic handwritten field linked to existing discovery and an actual Swift property.
    /// - Throws: File-system errors while creating the production declaration fixture.
    mutating func addManualFieldContracts() throws {
        try "public struct Payload {\n    public let identifier: String\n}\n".write(
            to: repository.appendingPathComponent("Sources/Sample/Fields.swift"), atomically: true, encoding: .utf8)
        var symbols = reviewed["symbols"] as! [[String: Any]]
        symbols.append(["id": "field-symbol", "path": "Sources/Sample/Fields.swift", "declaration": "public let identifier: String"])
        reviewed["symbols"] = symbols
        change("manual") { definition in
            definition["upstreamIDs"] = ["up-manual", "up-field"]
            definition["symbolIDs"] = ["symbol", "field-symbol"]
            definition["manual"] = ["behavior": "Handwritten semantic payload, bounded by its custom decoder.", "fields": [[
                "wireName": "id", "swiftName": "identifier", "valueType": "MessageID", "optional": false,
                "nullable": false, "defaultBehavior": "rejectMissing", "constraints": ["decimalStringUInt64"],
                "access": "bot", "unknownValueBehavior": "rejectTypeMismatch", "upstreamIDs": ["up-field"],
                "symbolID": "field-symbol",
            ]]]
        }
    }

    /// Mutates the first handwritten field in this test's isolated reviewed document.
    /// - Parameter mutation: Synchronous edit of field metadata; callers deliberately create valid or invalid cases.
    mutating func changeManualField(_ mutation: (inout [String: Any]) -> Void) {
        change("manual") { definition in
            var manual = definition["manual"] as! [String: Any]
            var fields = manual["fields"] as! [[String: Any]]
            mutation(&fields[0])
            manual["fields"] = fields
            definition["manual"] = manual
        }
    }
}
