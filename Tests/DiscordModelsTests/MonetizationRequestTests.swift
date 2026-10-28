// File: Tests/DiscordModelsTests/MonetizationRequestTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Typed test-entitlement owners prevent mismatched ID domains/discriminators before any network operation.
@Suite struct MonetizationRequestTests {
    /// Both owner variants preserve boundary IDs and emit exactly the written three-field JSON body.
    /// Repeated serialization remains stable and ordinary diagnostics conceal recipient/offering data.
    /// - Parameter raw: Boundary or above-Double-precision snowflake retained as exact decimal text.
    /// - Throws: Unexpected request or numeric/serialization construction errors fail the test.
    @Test(arguments: [UInt64(0), 9_007_199_254_740_993, UInt64.max]) func typedOwners(raw: UInt64) throws {
        for (owner, discriminator) in [(TestEntitlementOwner.guild(.init(rawValue: raw)), 1),
                                       (.user(.init(rawValue: raw)), 2)] {
            let request = try CreateTestEntitlementRequest(skuID: .init(rawValue: .max), owner: owner)
            let expected = JSONValue.object(["sku_id": .string("18446744073709551615"),
                "owner_id": .string(String(raw)), "owner_type": .number(try JSONNumber(rawValue: String(discriminator)))])
            #expect(request.jsonValue() == expected)
            #expect(try JSONValue.parse(request.jsonValue().serialized()) == expected)
            #expect(!String(describing: request).contains(String(raw)))
            #expect(!String(reflecting: request).contains("18446744073709551615"))
            #expect(request.customMirror.children.count == 1)
        }
        #expect(TestEntitlementOwner.guild(.init(rawValue: raw)) != .user(.init(rawValue: raw)))
    }
}
