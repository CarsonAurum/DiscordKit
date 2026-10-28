// File: Tests/DiscordModelsTests/MonetizationModelTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Offline API v10 monetization projections preserve complete written fields, unknown wire data,
/// exact identifiers and partial test responses without deriving premium access from billing status.
@Suite struct MonetizationModelTests {
    /// Complete SKU metadata retains full-width IDs/flags, all unknown fields and exact round-trip numbers.
    /// - Throws: Unexpected projection or independently authored JSON fixture failures fail the test.
    @Test func completeSKUAndFlags() throws {
        let value = try SKU(data: Self.bytes(kind: "sku"))
        #expect(value.id.rawValue == .max)
        #expect(value.applicationID.rawValue == 9_007_199_254_740_993)
        #expect(value.type.knownValue == .subscription)
        #expect(value.name == "Private premium")
        #expect(value.slug == "private-premium")
        #expect(value.flags == .max)
        #expect(value.rawFields["future"] == .number(try JSONNumber(rawValue: "12345678901234567890.123456789")))
        #expect(try value.jsonValue() == JSONValue.parse(Self.bytes(kind: "sku")))
        let flags = SKUFlags(rawValue: value.flags)
        #expect(flags.contains(.available))
        #expect(flags.contains(.guildSubscription))
        #expect(flags.contains(.userSubscription))
        #expect(flags.rawValue == UInt64.max)
        #expect(SKUFlags.available.rawValue == 4)
        #expect(SKUFlags.guildSubscription.rawValue == 128)
        #expect(SKUFlags.userSubscription.rawValue == 256)
        let unknown = SKUFlags(rawValue: 1 << 63)
        let expectedUnion: UInt64 = (1 << 63) | 4
        #expect(unknown.union(.available).rawValue == expectedUnion)
        #expect(!unknown.contains(.available))
        #expect(SKUFlags(rawValue: 0).isEmpty)
        #expect(!String(describing: value).contains("Private premium"))
        #expect(!String(reflecting: value).contains("18446744073709551615"))
        #expect(value.customMirror.children.count == 1)
    }

    /// Every written offering kind resolves, while unknown and negative integral discriminators remain preserved.
    /// Response names/slugs are not subjected to nonexistent outgoing mutation constraints.
    /// - Parameter raw: A known or future wire offering kind.
    /// - Throws: Unexpected fixture or response parsing failures fail the test.
    @Test(arguments: [2, 3, 5, 6, 99, -1]) func skuKinds(raw: Int) throws {
        var fields = try Self.fields(kind: "sku")
        fields["type"] = .number(try JSONNumber(rawValue: String(raw)))
        fields["name"] = .string(""); fields["slug"] = .string("")
        fields["flags"] = .number(try JSONNumber(rawValue: "0"))
        let value = try SKU(data: JSONValue.object(fields).serialized())
        #expect(value.type.rawValue == raw)
        #expect(value.type.knownValue == SKUType(rawValue: raw))
        #expect(value.name.isEmpty && value.slug.isEmpty && value.flags == 0)
        #expect(SKUType.allCases.map(\.rawValue) == [2, 3, 5, 6])
    }

    /// Full entitlement snapshots project the written fields plus the example's additive subscription ID.
    /// Deleted/consumed flags are retained without granting or rejecting access during response parsing.
    /// - Throws: Unexpected projection or independently authored fixture failures fail the test.
    @Test func completeEntitlement() throws {
        let value = try Entitlement(data: Self.bytes(kind: "entitlement"))
        #expect(value.id.rawValue == .max)
        #expect(value.skuID.rawValue == 9_007_199_254_740_993)
        #expect(value.applicationID.rawValue == 3)
        #expect(value.userID == .value(.init(rawValue: .max)))
        #expect(value.type.knownValue == .applicationSubscription)
        #expect(value.deleted)
        #expect(value.guildID == .value(.init(rawValue: 0)))
        #expect(value.consumed == .value(true))
        #expect(value.subscriptionID == .value(.init(rawValue: .max)))
        #expect(value.startsAt == .value(try DiscordTimestamp(rawValue: "2024-08-27T19:48:44.406602+00:00")))
        #expect(value.endsAt == .value(try DiscordTimestamp(rawValue: "2024-09-27T19:48:44.406602+00:00")))
        #expect(value.rawFields["promotion_id"] == .null)
        #expect(try value.jsonValue() == JSONValue.parse(Self.bytes(kind: "entitlement")))
        #expect(!String(describing: value).contains("18446744073709551615"))
        #expect(!String(reflecting: value).contains("promotion_id"))
        #expect(value.customMirror.children.count == 1)
    }

    /// Test-created perpetual entitlements preserve absent lifecycle values separately from null and timestamps.
    /// Optional owner, consumption and subscription properties stay absent rather than receiving guessed defaults.
    /// - Throws: Unexpected fixture/projection failures fail the test.
    @Test func partialTestEntitlementAndPresence() throws {
        var fields = try Self.fields(kind: "entitlement")
        for name in ["user_id", "guild_id", "consumed", "subscription_id", "starts_at", "ends_at"] {
            fields.removeValue(forKey: name)
        }
        let partial = try Entitlement(data: JSONValue.object(fields).serialized())
        #expect(partial.startsAt == .absent && partial.endsAt == .absent)
        #expect(partial.userID == .absent && partial.guildID == .absent)
        #expect(partial.consumed == .absent && partial.subscriptionID == .absent)
        fields["starts_at"] = .null; fields["ends_at"] = .null; fields["consumed"] = .bool(false)
        fields["guild_id"] = .null
        let nulls = try Entitlement(data: JSONValue.object(fields).serialized())
        #expect(nulls.startsAt == .null && nulls.endsAt == .null)
        #expect(nulls.consumed == .value(false))
        #expect(nulls.guildID == .null)
        #expect(nulls.jsonValue() != partial.jsonValue())
        #expect(try Entitlement(data: JSONValue.object(fields).serialized()) == nulls)
    }

    /// All eight written entitlement origins and future integral values survive response parsing unchanged.
    /// - Parameter raw: Written or future origin discriminator.
    /// - Throws: Unexpected fixture/projection failures fail the test.
    @Test(arguments: [1, 2, 3, 4, 5, 6, 7, 8, 99, -1]) func entitlementKinds(raw: Int) throws {
        var fields = try Self.fields(kind: "entitlement")
        fields["type"] = .number(try JSONNumber(rawValue: String(raw)))
        let value = try Entitlement(data: JSONValue.object(fields).serialized())
        #expect(value.type.rawValue == raw)
        #expect(value.type.knownValue == EntitlementType(rawValue: raw))
        #expect(EntitlementType.allCases.map(\.rawValue) == Array(1...8))
    }

    /// Every optional entitlement scalar rejects wrong JSON types. Lifecycle times and the official preview's
    /// guild owner may be null, while written nonnull owner/consumption/subscription values reject null.
    /// - Parameter name: Optional owner, consumption, lifecycle or additive subscription key.
    /// - Throws: Unexpected fixture failures fail the test; malformed known data must produce safe errors.
    @Test(arguments: ["user_id", "guild_id", "consumed", "subscription_id", "starts_at", "ends_at"])
    func entitlementOptionalFields(name: String) throws {
        var fields = try Self.fields(kind: "entitlement")
        for invalid in [JSONValue.object([:]), .array([]), .string("malformed")] {
            fields[name] = invalid
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try Entitlement(data: JSONValue.object(fields).serialized())
            }
        }
        fields[name] = .null
        if name != "starts_at" && name != "ends_at" && name != "guild_id" {
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try Entitlement(data: JSONValue.object(fields).serialized())
            }
        }
    }

    /// Complete subscriptions preserve every written lifecycle/renewal field, country presence and ordered exact IDs.
    /// - Throws: Unexpected fixture/projection failures fail the test.
    @Test func completeSubscription() throws {
        let value = try Subscription(data: Self.bytes(kind: "subscription"))
        #expect(value.id.rawValue == .max)
        #expect(value.userID.rawValue == 9_007_199_254_740_993)
        #expect(value.skuIDs == [.init(rawValue: .max), .init(rawValue: 0)])
        #expect(value.entitlementIDs == [.init(rawValue: 3)])
        #expect(value.renewalSKUIDs == .value([.init(rawValue: .max)]))
        #expect(value.currentPeriodStart == (try DiscordTimestamp(rawValue: "2024-08-27T19:48:44.406602+00:00")))
        #expect(value.currentPeriodEnd == (try DiscordTimestamp(rawValue: "2024-09-27T19:48:44.406602+00:00")))
        #expect(value.status.knownValue == .ending)
        #expect(value.canceledAt == .value(try DiscordTimestamp(rawValue: "2024-08-28T00:00:00Z")))
        #expect(value.country == .value("US"))
        #expect(try value.jsonValue() == JSONValue.parse(Self.bytes(kind: "subscription")))
        #expect(!String(describing: value).contains("18446744073709551615"))
        #expect(!String(reflecting: value).contains("2024-08-28"))
        #expect(value.customMirror.children.count == 1)
    }

    /// Written and future billing states accept all period/cancellation combinations without access inference.
    /// Empty/null renewal lists and absent private-scope country remain distinct from populated values.
    /// - Parameter raw: Known or future integral subscription status.
    /// - Throws: Unexpected fixture/projection failures fail the test.
    @Test(arguments: [0, 1, 2, 99, -1]) func subscriptionStatusesAndPresence(raw: Int) throws {
        var fields = try Self.fields(kind: "subscription")
        fields["status"] = .number(try JSONNumber(rawValue: String(raw)))
        fields["current_period_start"] = .string("2025-01-01T00:00:00Z")
        fields["current_period_end"] = .string("2024-01-01T00:00:00Z")
        fields["country"] = nil; fields["canceled_at"] = .null; fields["renewal_sku_ids"] = .null
        fields["sku_ids"] = .array([]); fields["entitlement_ids"] = .array([])
        let value = try Subscription(data: JSONValue.object(fields).serialized())
        #expect(value.status.rawValue == raw)
        #expect(value.status.knownValue == SubscriptionStatus(rawValue: raw))
        #expect(value.renewalSKUIDs == .null && value.canceledAt == .null)
        #expect(value.skuIDs.isEmpty && value.entitlementIDs.isEmpty)
        #expect(value.country == .absent)
        fields["renewal_sku_ids"] = .array([])
        let emptyRenewal = try Subscription(data: JSONValue.object(fields).serialized())
        #expect(emptyRenewal.renewalSKUIDs == .value([]))
        #expect(emptyRenewal.jsonValue() != value.jsonValue())
        #expect(SubscriptionStatus.allCases.map(\.rawValue) == [0, 1, 2])
        fields["country"] = .null
        #expect(try Subscription(data: JSONValue.object(fields).serialized()).country == .null)
        for invalid in [JSONValue.number(try JSONNumber(rawValue: "1")), .object([:])] {
            fields["country"] = invalid
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try Subscription(data: JSONValue.object(fields).serialized())
            }
        }
    }

    /// Required fields reject omission, forbidden null, wrong roots and incompatible object values for every model.
    /// Nullable subscription fields remain required while still accepting explicit null, checked separately above.
    /// - Parameter kind: SKU, entitlement or subscription fixture family.
    /// - Throws: Unexpected valid fixture failures fail the test; malformed fields must yield sanitized errors.
    @Test(arguments: ["sku", "entitlement", "subscription"]) func requiredFields(kind: String) throws {
        let names: [String]
        switch kind {
        case "sku": names = ["id", "type", "application_id", "name", "slug", "flags"]
        case "entitlement": names = ["id", "sku_id", "application_id", "type", "deleted"]
        default: names = ["id", "user_id", "sku_ids", "entitlement_ids", "renewal_sku_ids",
            "current_period_start", "current_period_end", "status", "canceled_at"]
        }
        for name in names {
            for invalid: JSONValue? in [nil, .null, .object([:])] {
                if invalid == .null && (name == "renewal_sku_ids" || name == "canceled_at") { continue }
                var fields = try Self.fields(kind: kind); fields[name] = invalid
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try Self.parse(kind: kind, data: JSONValue.object(fields).serialized())
                }
            }
        }
        for root in [JSONValue.null, .array([]), .bool(false), .string("private")] {
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try Self.parse(kind: kind, data: root.serialized())
            }
        }
    }

    /// Snowflake strings reject overflow/nondecimal/numeric forms, and exact enum/flag integers reject rounding.
    /// - Parameter kind: Fixture family whose required ID and integral kind are exercised.
    /// - Throws: Unexpected fixture/numeric construction failures fail the test.
    @Test(arguments: ["sku", "entitlement", "subscription"]) func exactIdentifiersAndNumbers(kind: String) throws {
        for invalid in [JSONValue.string("18446744073709551616"), .string(""), .string("-1"),
                        .string("1.5"), .string("0x10"), .number(try JSONNumber(rawValue: "1"))] {
            var fields = try Self.fields(kind: kind); fields["id"] = invalid
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try Self.parse(kind: kind, data: JSONValue.object(fields).serialized())
            }
        }
        for invalid in ["1.0", "1e0", "1.0000000000000000001", "18446744073709551616"] {
            var fields = try Self.fields(kind: kind)
            fields[kind == "subscription" ? "status" : "type"] = .number(try JSONNumber(rawValue: invalid))
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try Self.parse(kind: kind, data: JSONValue.object(fields).serialized())
            }
            if kind == "sku" {
                fields = try Self.fields(kind: kind); fields["flags"] = .number(try JSONNumber(rawValue: invalid))
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try Self.parse(kind: kind, data: JSONValue.object(fields).serialized())
                }
            }
        }
        if kind == "sku" {
            var fields = try Self.fields(kind: kind); fields["flags"] = .number(try JSONNumber(rawValue: "-1"))
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try Self.parse(kind: kind, data: JSONValue.object(fields).serialized())
            }
        }
    }

    /// Subscription arrays validate every ID and timestamp scalars reject malformed/nonstring values safely.
    /// - Throws: Unexpected fixture/serialization failures fail the test.
    @Test func subscriptionMalformedArraysAndTimes() throws {
        for name in ["sku_ids", "entitlement_ids", "renewal_sku_ids"] {
            for invalid in [JSONValue.string("1"), .array([.null]), .array([.string("18446744073709551616")]),
                            .array([.number(try JSONNumber(rawValue: "1"))]), .array([.bool(false)])] {
                var fields = try Self.fields(kind: "subscription"); fields[name] = invalid
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try Subscription(data: JSONValue.object(fields).serialized())
                }
            }
        }
        for name in ["current_period_start", "current_period_end", "canceled_at"] {
            for invalid in [JSONValue.string("invalid-date"), .string("2024-13-40T99:99:99Z"), .bool(false)] {
                var fields = try Self.fields(kind: "subscription"); fields[name] = invalid
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try Subscription(data: JSONValue.object(fields).serialized())
                }
            }
        }
    }

    /// Document bounds cover unknown trees for every projection, while duplicate/trailing JSON cannot be hidden.
    /// The same bounded subtree initialization path yields the identical exact semantic object.
    /// - Parameter kind: Fixture family whose public and internal constructors are exercised.
    /// - Throws: Unexpected fixture failures fail the test; parser errors and projection equality are asserted.
    @Test(arguments: ["sku", "entitlement", "subscription"]) func boundedParsing(kind: String) throws {
        let bytes = Self.bytes(kind: kind)
        #expect(throws: JSONValueError.maximumBytesExceeded) {
            try Self.parse(kind: kind, data: bytes, limits: .init(maximumBytes: bytes.count - 1))
        }
        #expect(throws: JSONValueError.maximumNodesExceeded) {
            try Self.parse(kind: kind, data: bytes, limits: .init(maximumNodes: 2))
        }
        var fields = try Self.fields(kind: kind); fields["unknown_nested"] = .object(["deep": .object([:])])
        #expect(throws: JSONValueError.maximumDepthExceeded) {
            try Self.parse(kind: kind, data: JSONValue.object(fields).serialized(), limits: .init(maximumDepth: 1))
        }
        #expect(throws: JSONValueError.self) {
            try Self.parse(kind: kind, data: Data(#"{"id":"1","id":"2"}"#.utf8))
        }
        #expect(throws: JSONValueError.self) { try Self.parse(kind: kind, data: bytes + Data(" {}".utf8)) }
        #expect(throws: JSONValueError.invalidLimits) {
            try Self.parse(kind: kind, data: bytes, limits: .init(maximumDepth: 129))
        }
        let root = try JSONValue.parse(bytes)
        switch kind {
        case "sku": #expect(try SKU(value: root, limits: .default) == SKU(data: bytes))
        case "entitlement": #expect(try Entitlement(value: root, limits: .default) == Entitlement(data: bytes))
        default: #expect(try Subscription(value: root, limits: .default) == Subscription(data: bytes))
        }
    }

    /// Produces independent exact API v10 fixture bytes, including example-only and future numeric data.
    /// - Parameter kind: The SKU, entitlement or subscription resource family.
    /// - Returns: A complete UTF-8 object with full-width identifiers and all written response fields.
    private static func bytes(kind: String) -> Data {
        switch kind {
        case "sku": return Data(#"{"id":"18446744073709551615","application_id":"9007199254740993","type":5,"name":"Private premium","slug":"private-premium","flags":18446744073709551615,"dependent_sku_id":null,"future":12345678901234567890.123456789}"#.utf8)
        case "entitlement": return Data(#"{"id":"18446744073709551615","sku_id":"9007199254740993","application_id":"3","user_id":"18446744073709551615","type":8,"deleted":true,"starts_at":"2024-08-27T19:48:44.406602+00:00","ends_at":"2024-09-27T19:48:44.406602+00:00","guild_id":"0","consumed":true,"subscription_id":"18446744073709551615","promotion_id":null,"future":12345678901234567890.123456789}"#.utf8)
        default: return Data(#"{"id":"18446744073709551615","user_id":"9007199254740993","sku_ids":["18446744073709551615","0"],"entitlement_ids":["3"],"renewal_sku_ids":["18446744073709551615"],"current_period_start":"2024-08-27T19:48:44.406602+00:00","current_period_end":"2024-09-27T19:48:44.406602+00:00","status":2,"canceled_at":"2024-08-28T00:00:00Z","country":"US","future":12345678901234567890.123456789}"#.utf8)
        }
    }

    /// Extracts independently authored fixture keys for one-field mutation tests without Foundation normalization.
    /// - Parameter kind: Resource family accepted by `bytes(kind:)`.
    /// - Returns: Exact original object fields, including numeric lexemes.
    /// - Throws: JSON fixture parsing errors or invalid-response if a fixture is accidentally made nonobject.
    private static func fields(kind: String) throws -> [String: JSONValue] {
        guard case .object(let fields) = try JSONValue.parse(bytes(kind: kind))
        else { throw DiscordError.transport(.invalidResponse) }
        return fields
    }

    /// Executes each public resource parser through a common negative-test boundary without external I/O.
    /// - Parameters:
    ///   - kind: SKU, entitlement or subscription family.
    ///   - data: Complete deliberately valid or invalid JSON fixture.
    ///   - limits: Whole-document test limits, defaulting to production bounds.
    /// - Throws: The selected parser's JSON or sanitized schema errors, asserted by callers.
    private static func parse(kind: String, data: Data, limits: JSONLimits = .default) throws {
        switch kind {
        case "sku": _ = try SKU(data: data, limits: limits)
        case "entitlement": _ = try Entitlement(data: data, limits: limits)
        default: _ = try Subscription(data: data, limits: limits)
        }
    }
}
