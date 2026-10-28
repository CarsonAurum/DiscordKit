// File: Tests/DiscordKitTests/DiscordKitTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordKit

/// Checks the umbrella product exposes usable foundations without network adapters.
@Suite struct DiscordKitTests {
    /// Exercises large IDs, unknown JSON numbers and redacted credentials through
    /// only the public umbrella import, replacing the original empty scaffold.
    @Test func portableConsumer() throws {
        let id = try #require(UserID("18446744073709551615"))
        #expect(id.rawValue == UInt64.max)
        #expect(try JSONEncoder().encode(id) == Data("\"18446744073709551615\"".utf8))
        let tree = try JSONValue.parse(Data("{\"future\":1.2300e999}".utf8))
        #expect(try JSONValue.parse(tree.serialized()) == tree)
        let credential = Credential.bot(try BotToken("consumer-sentinel-secret"))
        #expect(!String(describing: credential).contains("consumer-sentinel-secret"))
        let field: Field<String> = .absent
        #expect(field == .absent)
        let nullable: Nullable<String> = .null
        #expect(nullable == .null)
        #expect(try DiscordTimestamp(rawValue: "2026-10-15T00:00:00.123456789Z").rawValue.hasSuffix("123456789Z"))
    }

    /// Confirms synchronous Sendable values remain callable from a UI-owned actor.
    /// No executor transition, task lifetime or networking is introduced by these APIs.
    @MainActor @Test func mainActorConsumer() throws {
        #expect(ChannelID(rawValue: 42).description == "42")
        #expect(GuildID(rawValue: 42).rawValue == MessageID(rawValue: 42).rawValue)
        #expect(ApplicationID(rawValue: 42).rawValue == 42)
        let id: Snowflake<LocalTag> = Snowflake(rawValue: 1)
        #expect(id.description == "1")
        let number = try JSONNumber(rawValue: "9007199254740993")
        #expect(JSONValue.number(number) == (try JSONValue.parse(Data(number.rawValue.utf8), limits: JSONLimits())))
    }

    /// The umbrella's consumer aliases construct explicit runtime configuration and an idle
    /// broadcast hub from MainActor without an adapter, token, network operation or hidden task.
    @MainActor @Test func runtimeConsumerAliases() async throws {
        let configuration = try BotConfiguration(intents: [])
        #expect(configuration.intents.isEmpty)
        let hub = EventHub(configuration: try .init(maximumSubscriptions: 1))
        let subscription = try await hub.subscribe()
        #expect(await hub.snapshot().subscriptions == 1)
        await hub.finish()
        var iterator = subscription.makeAsyncIterator()
        #expect(try await iterator.next() == nil)
        #expect(await hub.snapshot().subscriptions == 0)
    }
}

/// A consumer-defined marker proving the umbrella preserves generic identifier tags.
private enum LocalTag: Sendable {}
