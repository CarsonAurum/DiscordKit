// File: Tests/DiscordDAVETests/DAVERatchetTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordDAVE

/// Independent HMAC known answers and bounded-state tests for the DAVE sender ratchet.
@Suite struct DAVERatchetTests {
    /// Verifies initial sixteen-byte HKDF PRK behavior and the generation/label wire framing.
    /// Expected values were independently calculated with Python standard-library HMAC-SHA256
    /// over RFC 9420 KDFLabel bytes; no DiscordKit cryptographic helper supplied the answers.
    @Test func independentKnownAnswersAndErasure() throws {
        var ratchet = try DAVEKeyRatchet(baseSecret: Data(0..<16))
        let zero = try ratchet.key(for: 0)
        #expect(zero.map { String(format: "%02x", $0) }.joined() == "58fc013108dbf996ef651e3f01658bfb")
        #expect(try ratchet.key(for: 1).map { String(format: "%02x", $0) }.joined() == "9cddc08f0c8a7cfecabfe757dc33b039")
        #expect(try ratchet.key(for: 2).map { String(format: "%02x", $0) }.joined() == "ef2427778fb709d7d1e070846f920024")
        #expect(try ratchet.key(for: 0) == zero)
        #expect(ratchet.retainedKeyCount == 3)
        ratchet.erase(before: 0)
        #expect(ratchet.retainedKeyCount == 3)
        ratchet.erase(before: 2)
        #expect(ratchet.retainedKeyCount == 1)
        #expect(throws: DAVEError.generationExpired) { try ratchet.key(for: 0) }
        #expect(try ratchet.key(for: 2).count == 16)
        #expect(ratchet.description == ratchet.debugDescription)
        #expect(String(reflecting: ratchet).contains("redacted"))
        #expect(Mirror(reflecting: ratchet).children.count == 1)
        let padded = Data(repeating: 0xAA, count: 1024) + Data(0..<16)
        var sliced = try DAVEKeyRatchet(baseSecret: padded.suffix(16))
        #expect(try sliced.key(for: 0) == zero)
    }

    /// Checks transactional future-work rejection, automatic cache eviction, and sequential use.
    @Test func boundedForwardWorkAndCache() throws {
        var ratchet = try DAVEKeyRatchet(baseSecret: Data(count: 16), maximumForwardDistance: 2, maximumRetainedKeys: 2)
        #expect(throws: DAVEError.generationTooFarAhead) { try ratchet.key(for: 3) }
        #expect(ratchet.retainedKeyCount == 0)
        let key = try ratchet.key(for: 2)
        #expect(key.count == 16)
        #expect(ratchet.retainedKeyCount == 2)
        #expect(throws: DAVEError.generationExpired) { try ratchet.key(for: 0) }
        #expect(try ratchet.key(for: 1).count == 16)
        #expect(try ratchet.key(for: 3).count == 16)
        #expect(ratchet.retainedKeyCount == 2)
        var sequential = try DAVEKeyRatchet(baseSecret: Data(count: 16), maximumForwardDistance: 0)
        #expect(throws: DAVEError.generationTooFarAhead) { try sequential.key(for: 1) }
        #expect(try sequential.key(for: 0).count == 16)
        #expect(try sequential.key(for: 1).count == 16)
    }

    /// Rejects every secret-size and policy boundary before retaining any secret.
    @Test func invalidConstruction() {
        for count in [0, 15, 17, 32] {
            #expect(throws: DAVEError.invalidSecret) { try DAVEKeyRatchet(baseSecret: Data(count: count)) }
        }
        for value in [-1, 251, Int.max] {
            #expect(throws: DAVEError.invalidConfiguration) { try DAVEKeyRatchet(baseSecret: Data(count: 16), maximumForwardDistance: value) }
        }
        for value in [0, -1, 252, Int.max] {
            #expect(throws: DAVEError.invalidConfiguration) { try DAVEKeyRatchet(baseSecret: Data(count: 16), maximumRetainedKeys: value) }
        }
    }
}
