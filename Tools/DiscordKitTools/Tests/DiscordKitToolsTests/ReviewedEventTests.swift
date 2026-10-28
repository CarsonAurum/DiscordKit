// File: Tools/DiscordKitTools/Tests/DiscordKitToolsTests/ReviewedEventTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordKitTools

/// Exercises explicit event relationships using synthetic IDs without claiming Discord event support.
///
/// The fixture graph owns a temporary checkout and uses real local declaration/test evidence.
/// Event metadata remains separate from Gateway delivery or runtime code generation.
@Suite("Reviewed event contracts")
struct ReviewedEventTests {
    /// Resolves typed payload and variant links across every known implementation status.
    ///
    /// All linked payload fields and enum variants are supported in the independent base
    /// fixture. A new event increases record counts without generating an event runtime.
    /// - Parameter status: Every supported inventory classification.
    /// - Throws: Unexpected fixture setup or validation errors fail the test.
    @Test(arguments: ["supported", "partial", "unsupported", "deprecated", "removed"])
    func validatesTypedPayloadAndVariantRelationships(status: String) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        fixture.addReviewedEvent(status: status, payloadModelID: "model", variantIDs: ["variant"])
        let report = try fixture.validate()
        #expect(report.definitions == 7)
        #expect(report.models == 1)
        #expect(report.events == 1)
        #expect(report == (try fixture.validate()))
        let decoded = try ReviewedInventoryValidator.load(reviewedData: fixture.data(fixture.reviewed))
        let event = try #require(decoded.definitions.first { $0.kind == "event" }?.event)
        #expect(event.payloadModelID == "model")
        #expect(event.variantIDs == ["variant"])
        let roundTrip = try ReviewedInventoryValidator.load(reviewedData: JSONEncoder().encode(decoded))
        #expect(roundTrip == decoded)
        #expect(try fixture.parityValidate().reviewedCounts.contains(ParityCount(kind: "event", status: status, count: 1)))
    }

    /// Allows explicitly unmodeled payloads while preventing supported typed-event claims.
    ///
    /// - Parameter status: Every known classification; supported requires a payload model,
    ///   while partial and nonimplemented records may explicitly use `none`.
    /// - Throws: Unexpected fixture setup/encoding failures fail the test.
    @Test(arguments: ["supported", "partial", "unsupported", "deprecated", "removed"])
    func classifiesUnmodeledPayloads(status: String) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        fixture.addReviewedEvent(status: status)
        if status == "supported" {
            #expect(throws: ReviewedInventoryFailure.self) { try fixture.validate() }
        } else {
            #expect(try fixture.validate().definitions == 7)
        }
    }

    /// Rejects broken event references, wrong target kinds and incomplete behavior metadata.
    ///
    /// - Parameter corruption: A payload, variant, source-kind or behavior invariant to break.
    ///   Each mutation starts from a complete supported event with real evidence.
    /// - Throws: Unexpected fixture setup/encoding failures fail the test.
    @Test(arguments: [
        "missingPayload", "wrongPayloadKind", "partialPayload", "missingVariant", "wrongVariantKind",
        "partialVariant", "duplicateVariant", "blankVariant", "wrongUpstreamKind", "blankBehavior",
    ])
    func rejectsInvalidEventRelationships(corruption: String) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        fixture.addReviewedEvent(status: "supported", payloadModelID: "model", variantIDs: ["variant"])
        switch corruption {
        case "partialPayload":
            fixture.change("model") { $0["status"] = "partial" }
            fixture.change("endpoint") { $0["status"] = "partial" }
        case "partialVariant":
            fixture.change("variant") { $0["status"] = "partial" }
            fixture.change("enum") { $0["status"] = "partial" }
        case "wrongUpstreamKind": fixture.change("event") { $0["upstreamIDs"] = ["up-manual"] }
        default:
            fixture.change("event") { value in
                var event = value["event"] as! [String: Any]
                switch corruption {
                case "missingPayload": event["payloadModelID"] = "missing"
                case "wrongPayloadKind": event["payloadModelID"] = "field"
                case "missingVariant": event["variantIDs"] = ["missing"]
                case "wrongVariantKind": event["variantIDs"] = ["field"]
                case "duplicateVariant": event["variantIDs"] = ["variant", "variant"]
                case "blankVariant": event["variantIDs"] = [" \n"]
                default: event["behavior"] = " \n\t"
                }
                value["event"] = event
            }
        }
        #expect(throws: ReviewedInventoryFailure.self) { try fixture.validate() }
    }

    /// Allows partial event links to partial models and variants without upgrading their status.
    ///
    /// Partial payload and enum projections are meaningful reviewed relationships. Supported
    /// event validation rejects them in the previous test; a partial event retains the limits.
    @Test
    func retainsPartialPayloadAndVariantClassifications() throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        fixture.addReviewedEvent(status: "partial", payloadModelID: "model", variantIDs: ["variant"])
        fixture.change("model") { $0["status"] = "partial" }
        fixture.change("endpoint") { $0["status"] = "partial" }
        fixture.change("enum") { $0["status"] = "partial" }
        fixture.change("variant") { $0["status"] = "partial" }
        #expect(try fixture.validate().definitions == 7)
    }

    /// Keeps event contract metadata closed, required and nonnullable before semantic review.
    ///
    /// - Parameter corruption: An unknown key, missing required relationship, explicit null,
    ///   or invalid container type must fail decoding rather than disappear from the record.
    /// - Throws: Unexpected fixture setup/encoding errors fail the test.
    @Test(arguments: ["unknown", "missingPayload", "missingVariants", "missingBehavior", "null", "wrongType"])
    func rejectsMalformedEventMetadata(corruption: String) throws {
        var fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        fixture.addReviewedEvent()
        fixture.change("event") { value in
            var event = value["event"] as! [String: Any]
            switch corruption {
            case "unknown": event["unclassified"] = true
            case "missingPayload": event.removeValue(forKey: "payloadModelID")
            case "missingVariants": event.removeValue(forKey: "variantIDs")
            case "missingBehavior": event.removeValue(forKey: "behavior")
            case "null": event["payloadModelID"] = NSNull()
            default: event["variantIDs"] = "variant"
            }
            value["event"] = event
        }
        #expect(throws: (any Error).self) { try fixture.validate() }
    }

    /// Rejects direct misuse of the event validator with a different definition kind.
    ///
    /// The enclosing validator dispatches only event contracts. This boundary assertion
    /// keeps the pure helper's documented failure behavior explicit for future callers.
    @Test
    func rejectsNonEventDefinition() throws {
        let fixture = try ReviewedFixture()
        defer { fixture.cleanup() }
        let reviewed = try ReviewedInventoryValidator.load(reviewedData: fixture.data(fixture.reviewed))
        let inventory = try JSONDecoder().decode(Inventory.self, from: fixture.data(fixture.inventory))
        let manual = try #require(reviewed.definitions.first { $0.kind == "manual" })
        #expect(throws: ReviewedInventoryFailure.self) {
            try ReviewedEventValidator.validate(
                manual, definitions: Dictionary(uniqueKeysWithValues: reviewed.definitions.map { ($0.id, $0) }),
                upstream: Dictionary(uniqueKeysWithValues: inventory.entries.map { ($0.id, $0) })
            )
        }
    }
}

/// Isolated event additions without changing the shared fixture's initial six-kind seed.
extension ReviewedFixture {
    /// Appends one synthetic event to both reviewed and source-discovery membership records.
    ///
    /// - Parameters:
    ///   - status: Known implementation classification; defaults to unsupported, so adding
    ///     an event relationship does not itself claim runtime coverage.
    ///   - payloadModelID: Reviewed payload model ID or `none`, which defaults to unmodeled.
    ///   - variantIDs: Reviewed enum variants related to the payload; defaults to no variants.
    ///     Tests may supply invalid IDs to exercise validation failures.
    /// This synchronous helper mutates only fixture dictionaries. Existing evidence files
    /// are reused without modification, and cleanup remains owned by the fixture caller.
    mutating func addReviewedEvent(
        status: String = "unsupported", payloadModelID: String = "none", variantIDs: [String] = []
    ) {
        var entries = inventory["entries"] as! [[String: Any]]
        entries.append([
            "id": "up-event", "kind": "event", "name": "SYNTHETIC_EVENT", "sourceID": "source",
            "locator": "L2", "context": "Synthetic event", "status": status, "condition": "public_protocol",
            "review": "reviewed", "evidence": ["Tests/SampleTests/SampleTests.swift"],
        ])
        inventory["entries"] = entries
        var sources = catalog["sources"] as! [[String: Any]]
        var entryIDs = sources[0]["entryIDs"] as! [String]
        entryIDs.append("up-event")
        sources[0]["entryIDs"] = entryIDs
        catalog["sources"] = sources
        var definitions = reviewed["definitions"] as! [[String: Any]]
        definitions.append([
            "id": "event", "kind": "event", "name": "SYNTHETIC_EVENT", "sourceID": "source",
            "upstreamIDs": ["up-event"], "status": status, "supportSince": "2026-10-15",
            "announcementDate": "unknown", "effectiveDate": "unknown", "symbolIDs": ["symbol"],
            "evidenceIDs": ["test"], "notes": "Synthetic event schema test; no Discord event coverage is claimed.",
            "event": ["payloadModelID": payloadModelID, "variantIDs": variantIDs,
                      "behavior": "Handwritten delivery, ordering and lifecycle semantics require separate evidence."],
        ])
        reviewed["definitions"] = definitions
    }
}
