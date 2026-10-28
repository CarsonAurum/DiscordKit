// File: Tests/DiscordGatewayTests/GatewayRequestTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordTransport
import DiscordTestSupport
import Foundation
import Testing
@testable import DiscordGateway

/// Deterministic request-correlation and per-bot command-admission contracts, without live Discord requests.
@Suite("Gateway requests and shared command admission")
struct GatewayRequestTests {
    /// Raw request sends retire correlatable nonces and nonce-less scopes before a later response can be misattributed.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func rawSendCorrelationFences() throws {
        var registry = makeRequestRegistry(maximumRetiredKeys: 3)
        try registry.fenceUncorrelated(GatewayCommand.updatePresence(GatewayPresence()))
        try registry.fenceUncorrelated(GatewayCommand.updateVoiceState(guildID: GuildID(rawValue: 1), channelID: nil))
        try registry.fenceUncorrelated(GatewayCommand.requestGuildMembers(guildID: GuildID(rawValue: 1), query: "", limit: 0))
        try registry.fenceUncorrelated(GatewayCommand.requestGuildMembers(guildID: GuildID(rawValue: 1), query: "", limit: 0, nonce: ""))
        let member = try memberRequest()
        let soundboard = try GatewayCommand.requestSoundboardSounds(guildIDs: [GuildID(rawValue: 1)])
        let channelInfo = try GatewayCommand.requestChannelInfo(guildID: GuildID(rawValue: 1))
        for command in [member, soundboard, channelInfo] { try registry.fenceUncorrelated(command) }
        #expect(registry.pending.isEmpty)
        // Once all reserved key capacity is retired, further potentially correlatable requests fail closed.
        #expect(throws: GatewayFailure.commandCapacityExceeded) {
            try registry.fenceUncorrelated(memberRequest(nonce: "new"))
        }
        registry.reset()
        for command in [member, soundboard, channelInfo] {
            try registry.fenceUncorrelated(command)
            registry.reset()
        }
        var conflicts = makeRequestRegistry()
        let id = UUID()
        _ = try conflicts.register(id: id, command: member)
        #expect(throws: GatewayFailure.requestConflict) { try conflicts.fenceUncorrelated(member) }
        conflicts.remove(id)
        #expect(throws: GatewayFailure.requestConflict) { try conflicts.fenceUncorrelated(member) }
        try conflicts.fenceUncorrelated(soundboard)
        #expect(throws: GatewayFailure.requestConflict) { try conflicts.register(id: UUID(), command: soundboard) }
        try conflicts.fenceUncorrelated(channelInfo)
        #expect(throws: GatewayFailure.requestConflict) { try conflicts.register(id: UUID(), command: channelInfo) }
        conflicts.reset()
    }

    /// Out-of-order member chunks complete once in chunk order; duplicate chunks retain the first observation.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func orderedMemberChunks() async throws {
        var registry = makeRequestRegistry()
        let id = UUID()
        let command = try GatewayCommand.requestGuildMembers(guildID: GuildID(rawValue: 1), query: "", limit: 0, nonce: "private-nonce")
        let stream = try registry.register(id: id, command: command)
        let last = try memberChunk(index: 1, count: 2, sequence: 2)
        registry.ingest(last)
        registry.ingest(try memberChunk(index: 1, count: 2, sequence: 3))
        #expect(registry.partial(id).map(\.sequence) == [2])
        registry.ingest(try memberChunk(index: 0, count: 2, sequence: 4))
        #expect(registry.pending.isEmpty)
        #expect(registry.partial(id).isEmpty)
        var iterator = stream.makeAsyncIterator()
        let result = try #require(try await iterator.next())
        #expect(result.events.map(\.sequence) == [4, 2])
        #expect(try await iterator.next() == nil)
        #expect(result.description == "GatewayRequestResult(redacted)")
        #expect(!String(reflecting: result).contains("private-nonce"))
        #expect(result.customMirror.children.count == 1)
        #expect(result.customMirror.children.first?.value as? Bool == true)
        #expect(throws: GatewayFailure.requestConflict) { try registry.register(id: UUID(), command: command) }
    }

    /// Exact nonce, guild and event-family checks ignore unrelated responses and malformed snowflake spellings.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func memberCorrelationFilters() async throws {
        var registry = makeRequestRegistry()
        let id = UUID()
        let command = try GatewayCommand.requestGuildMembers(guildID: GuildID(rawValue: 1), userIDs: [UserID(rawValue: 1)], nonce: "private-nonce")
        let stream = try registry.register(id: id, command: command)
        for event in [
            try memberChunk(guild: "2"), try memberChunk(guild: "+1"), try memberChunk(guild: " 1"),
            try memberChunk(guild: "18446744073709551616"), try memberChunk(nonce: "other"),
            try requestEvent(name: "OTHER", data: .object(["guild_id": .string("1"), "nonce": .string("private-nonce")])),
            try requestEvent(name: "GUILD_MEMBERS_CHUNK", data: .null),
            try requestEvent(name: "GUILD_MEMBERS_CHUNK", data: .object(["guild_id": gatewayNumber(1)])),
            try requestEvent(name: "GUILD_MEMBERS_CHUNK", data: .object(["guild_id": .string("1")])),
            try requestEvent(name: "GUILD_MEMBERS_CHUNK", data: .object(["guild_id": .string("1"), "nonce": .null]))
        ] { registry.ingest(event) }
        #expect(registry.pending.count == 1)
        #expect(registry.partial(id).isEmpty)
        registry.ingest(try memberChunk(sequence: 99))
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next()?.events.map(\.sequence) == [99])
    }

    /// Malformed member chunk fields fail the matching request explicitly rather than hanging or accepting partial shape.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func malformedMemberChunks() async throws {
        let mutations: [[String: JSONValue]] = [
            ["chunk_index": gatewayNumber(-1)], ["chunk_index": gatewayNumber(2)],
            ["chunk_index": .string("0")], ["chunk_index": .null],
            ["chunk_count": gatewayNumber(0)], ["chunk_count": gatewayNumber(-1)],
            ["chunk_count": .number(try JSONNumber(rawValue: "1.5"))],
            ["chunk_count": gatewayNumber(UInt64.max)], ["members": .object([:])], ["members": .null]
        ]
        for mutation in mutations {
            var registry = makeRequestRegistry()
            let id = UUID()
            let stream = try registry.register(id: id, command: memberRequest())
            var data: [String: JSONValue] = ["guild_id": .string("1"), "nonce": .string("private-nonce"),
                "chunk_index": gatewayNumber(0), "chunk_count": gatewayNumber(2), "members": .array([])]
            data.merge(mutation) { _, replacement in replacement }
            registry.ingest(try requestEvent(name: "GUILD_MEMBERS_CHUNK", data: .object(data)))
            let failure = try await requestFailure(stream)
            #expect(failure.reason == .invalidResponse)
            #expect(failure.partialEvents.isEmpty)
            #expect(failure.retryAfter == nil)
            #expect(registry.pending.isEmpty)
        }
    }

    /// Inconsistent chunk counts terminate with the already observed bounded partial result, including duplicate indices.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func inconsistentMemberCounts() async throws {
        for index in [0, 1] {
            var registry = makeRequestRegistry()
            let stream = try registry.register(id: UUID(), command: memberRequest())
            registry.ingest(try memberChunk(index: 0, count: 2, sequence: 10))
            registry.ingest(try memberChunk(index: index, count: 3, sequence: 20))
            let failure = try await requestFailure(stream)
            #expect(failure.reason == .invalidResponse)
            #expect(failure.partialEvents.map(\.sequence) == [10])
            #expect(registry.pending.isEmpty)
        }
    }

    /// Soundboard multi-guild requests finish in requested-guild order, ignoring duplicate and wrong-family replies.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func soundboardGuildOrdering() async throws {
        var registry = makeRequestRegistry()
        let id = UUID()
        let command = try GatewayCommand.requestSoundboardSounds(guildIDs: [GuildID(rawValue: 2), GuildID(rawValue: 1)])
        let stream = try registry.register(id: id, command: command)
        registry.ingest(try soundboardEvent(guild: "1", sequence: 1))
        registry.ingest(try soundboardEvent(guild: "1", sequence: 2))
        registry.ingest(try soundboardEvent(guild: "3", sequence: 3))
        registry.ingest(try channelInfoEvent(guild: "2", sequence: 4))
        #expect(registry.partial(id).map(\.sequence) == [1])
        registry.ingest(try soundboardEvent(guild: "2", sequence: 5))
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next()?.events.map(\.sequence) == [5, 1])
        #expect(try await iterator.next() == nil)
        // Successful nonce-less completion permits a later intentional request on the same socket.
        _ = try registry.register(id: UUID(), command: command)
        registry.reset()
    }

    /// Channel-info matches one guild and requires an array payload; empty arrays are valid complete responses.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func channelInfoCompletionAndMalformedResponse() async throws {
        let command = try GatewayCommand.requestChannelInfo(guildID: GuildID(rawValue: 1))
        var registry = makeRequestRegistry()
        let stream = try registry.register(id: UUID(), command: command)
        registry.ingest(try channelInfoEvent(guild: "2"))
        #expect(registry.pending.count == 1)
        registry.ingest(try channelInfoEvent(sequence: 17))
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next()?.events.map(\.sequence) == [17])
        for (name, command, field) in [("CHANNEL_INFO", command, "channels"),
            ("SOUNDBOARD_SOUNDS", try GatewayCommand.requestSoundboardSounds(guildIDs: [GuildID(rawValue: 1)]), "soundboard_sounds")] {
            var registry = makeRequestRegistry()
            let stream = try registry.register(id: UUID(), command: command)
            registry.ingest(try requestEvent(name: name, data: .object(["guild_id": .string("1"), field: .null])))
            #expect(try await requestFailure(stream).reason == .invalidResponse)
        }
    }

    /// Pending IDs, member nonces and overlapping nonce-less scopes cannot be registered twice; independent families coexist.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func registrationConflicts() throws {
        var registry = makeRequestRegistry()
        let id = UUID()
        let first = try memberRequest()
        _ = try registry.register(id: id, command: first)
        #expect(throws: GatewayFailure.requestConflict) { try registry.register(id: id, command: memberRequest(nonce: "different")) }
        #expect(throws: GatewayFailure.requestConflict) { try registry.register(id: UUID(), command: first) }
        _ = try registry.register(id: UUID(), command: memberRequest(nonce: "different"))
        let soundboard = try GatewayCommand.requestSoundboardSounds(guildIDs: [GuildID(rawValue: 1), GuildID(rawValue: 2)])
        _ = try registry.register(id: UUID(), command: soundboard)
        #expect(throws: GatewayFailure.requestConflict) {
            try registry.register(id: UUID(), command: GatewayCommand.requestSoundboardSounds(guildIDs: [GuildID(rawValue: 2), GuildID(rawValue: 3)]))
        }
        _ = try registry.register(id: UUID(), command: GatewayCommand.requestChannelInfo(guildID: GuildID(rawValue: 1)))
        #expect(throws: GatewayFailure.requestConflict) {
            try registry.register(id: UUID(), command: GatewayCommand.requestChannelInfo(guildID: GuildID(rawValue: 1)))
        }
        #expect(registry.pending.count == 4)
        registry.reset()
    }

    /// Presence, voice and uncorrelatable member requests fail before retaining waiters or scope metadata.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func invalidRequestFamiliesAndNonces() throws {
        var registry = makeRequestRegistry()
        let commands = [try GatewayCommand.updatePresence(GatewayPresence()),
            try GatewayCommand.updateVoiceState(guildID: GuildID(rawValue: 1), channelID: nil),
            try GatewayCommand.requestGuildMembers(guildID: GuildID(rawValue: 1), query: "", limit: 0),
            try GatewayCommand.requestGuildMembers(guildID: GuildID(rawValue: 1), query: "", limit: 0, nonce: "")]
        for command in commands {
            #expect(throws: GatewayFailure.invalidConfiguration) { try registry.register(id: UUID(), command: command) }
        }
        #expect(registry.pending.isEmpty)
    }

    /// Request count and future tombstone reservations are finite, including each guild in a soundboard request.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func registrationCapacity() throws {
        var countRegistry = makeRequestRegistry(maximumRequests: 1)
        let id = UUID()
        _ = try countRegistry.register(id: id, command: memberRequest())
        #expect(throws: GatewayFailure.commandCapacityExceeded) {
            try countRegistry.register(id: UUID(), command: memberRequest(nonce: "next"))
        }
        countRegistry.remove(id)
        _ = try countRegistry.register(id: UUID(), command: memberRequest(nonce: "next"))
        countRegistry.reset()
        var metadataRegistry = makeRequestRegistry(maximumRetiredKeys: 2)
        #expect(throws: GatewayFailure.commandCapacityExceeded) {
            try metadataRegistry.register(id: UUID(), command: GatewayCommand.requestSoundboardSounds(
                guildIDs: [GuildID(rawValue: 1), GuildID(rawValue: 2), GuildID(rawValue: 3)]))
        }
        _ = try metadataRegistry.register(id: UUID(), command: GatewayCommand.requestSoundboardSounds(
            guildIDs: [GuildID(rawValue: 1), GuildID(rawValue: 2)]))
        #expect(throws: GatewayFailure.commandCapacityExceeded) {
            try metadataRegistry.register(id: UUID(), command: GatewayCommand.requestChannelInfo(guildID: GuildID(rawValue: 3)))
        }
        metadataRegistry.reset()
        _ = try metadataRegistry.register(id: UUID(), command: memberRequest())
        metadataRegistry.reset()
    }

    /// Event-count and aggregate retained-wire-byte caps fail with partial observations and release accounting for other requests.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func responseCapacityAndAccountingRelease() async throws {
        var countRegistry = makeRequestRegistry(maximumEvents: 1)
        let countStream = try countRegistry.register(id: UUID(), command: memberRequest())
        countRegistry.ingest(try memberChunk(index: 0, count: 2))
        let countFailure = try await requestFailure(countStream)
        #expect(countFailure.reason == .responseCapacityExceeded)
        #expect(countFailure.partialEvents.isEmpty)
        let first = try memberChunk(index: 0, count: 2, sequence: 1)
        let second = try memberChunk(index: 1, count: 2, sequence: 2)
        var bytesRegistry = makeRequestRegistry(maximumBytes: first.byteCount + second.byteCount - 1)
        let id = UUID()
        let bytesStream = try bytesRegistry.register(id: id, command: memberRequest())
        bytesRegistry.ingest(first)
        #expect(bytesRegistry.partial(id).count == 1)
        bytesRegistry.ingest(second)
        let byteFailure = try await requestFailure(bytesStream)
        #expect(byteFailure.reason == .responseCapacityExceeded)
        #expect(byteFailure.partialEvents.map(\.sequence) == [1])
        #expect(bytesRegistry.pending.isEmpty)
        let replacement = try bytesRegistry.register(id: UUID(), command: memberRequest(nonce: "replacement"))
        bytesRegistry.ingest(try memberChunk(nonce: "replacement", sequence: 3))
        var iterator = replacement.makeAsyncIterator()
        #expect(try await iterator.next()?.events.count == 1)
    }

    /// Wire bytes are bounded across concurrent requests, rather than independently per request.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func aggregateResponseByteCapacity() async throws {
        let first = try memberChunk(index: 0, count: 2, sequence: 1)
        var registry = makeRequestRegistry(maximumBytes: first.byteCount)
        let firstID = UUID()
        let firstStream = try registry.register(id: firstID, command: memberRequest())
        let secondStream = try registry.register(id: UUID(), command: memberRequest(nonce: "second"))
        registry.ingest(first)
        registry.ingest(try memberChunk(nonce: "second"))
        #expect(try await requestFailure(secondStream).reason == .responseCapacityExceeded)
        #expect(registry.partial(firstID).count == 1)
        registry.reset()
        let firstFailure = try await requestFailure(firstStream)
        #expect(firstFailure.reason == .disconnected)
        #expect(firstFailure.partialEvents.map(\.sequence) == [1])
    }

    /// Removed member nonces reject reuse and late chunks; ambiguous nonce-less scopes remain fenced until socket reset.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func lateResponseFencingAndReset() async throws {
        var registry = makeRequestRegistry()
        let id = UUID()
        let command = try memberRequest()
        let stream = try registry.register(id: id, command: command)
        registry.remove(id)
        registry.remove(id)
        registry.ingest(try memberChunk())
        #expect(registry.pending.isEmpty)
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == nil)
        #expect(throws: GatewayFailure.requestConflict) { try registry.register(id: UUID(), command: command) }
        let soundboard = try GatewayCommand.requestSoundboardSounds(guildIDs: [GuildID(rawValue: 1), GuildID(rawValue: 2)])
        let soundID = UUID()
        _ = try registry.register(id: soundID, command: soundboard)
        registry.remove(soundID)
        for guild in [GuildID(rawValue: 1), GuildID(rawValue: 2)] {
            #expect(throws: GatewayFailure.requestConflict) {
                try registry.register(id: UUID(), command: GatewayCommand.requestSoundboardSounds(guildIDs: [guild]))
            }
        }
        _ = try registry.register(id: UUID(), command: GatewayCommand.requestChannelInfo(guildID: GuildID(rawValue: 1)))
        registry.reset()
        registry.reset()
        _ = try registry.register(id: UUID(), command: command)
        _ = try registry.register(id: UUID(), command: soundboard)
        registry.reset()
    }

    /// RATE_LIMITED selects opcode, guild and nonce precisely, returns bounded partials, and poisons ambiguous scopes.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func scopedRateLimitFailures() async throws {
        var registry = makeRequestRegistry()
        let firstID = UUID()
        let firstStream = try registry.register(id: firstID, command: memberRequest())
        let secondStream = try registry.register(id: UUID(), command: memberRequest(nonce: "other"))
        let soundCommand = try GatewayCommand.requestSoundboardSounds(guildIDs: [GuildID(rawValue: 1)])
        let soundStream = try registry.register(id: UUID(), command: soundCommand)
        registry.ingest(try memberChunk(index: 1, count: 2, sequence: 21))
        registry.rateLimited(opcode: 8, guild: GuildID(rawValue: 2), nonce: nil, retryAfter: .seconds(4))
        registry.rateLimited(opcode: 8, guild: GuildID(rawValue: 1), nonce: "unknown", retryAfter: .seconds(4))
        #expect(registry.pending.count == 3)
        registry.rateLimited(opcode: 8, guild: GuildID(rawValue: 1), nonce: "private-nonce", retryAfter: .milliseconds(1500))
        let failure = try await requestFailure(firstStream)
        #expect(failure.reason == .rateLimited)
        #expect(failure.retryAfter == .milliseconds(1500))
        #expect(failure.partialEvents.map(\.sequence) == [21])
        #expect(failure.description == "GatewayRequestFailure(rateLimited)")
        #expect(!String(reflecting: failure).contains("private-nonce"))
        #expect(failure.customMirror.children.count == 1)
        #expect(failure.customMirror.children.first?.label == "reason")
        #expect(failure.customMirror.children.first?.value as? GatewayRequestFailureReason == .rateLimited)
        #expect(registry.partial(firstID).isEmpty)
        registry.rateLimited(opcode: 8, guild: nil, nonce: nil, retryAfter: .seconds(2))
        #expect(try await requestFailure(secondStream).reason == .rateLimited)
        #expect(registry.pending.count == 1)
        registry.rateLimited(opcode: 31, guild: nil, nonce: nil, retryAfter: .seconds(3))
        #expect(try await requestFailure(soundStream).retryAfter == .seconds(3))
        #expect(registry.pending.isEmpty)
        #expect(throws: GatewayFailure.requestConflict) { try registry.register(id: UUID(), command: soundCommand) }
    }

    /// Concurrent owners and topology generations share exactly one full-member allowance for the same bot and guild.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func concurrentSharedFullMemberAdmission() async throws {
        let clock = ManualClock()
        let coordinator = try InProcessGatewayCommandCoordinator(botID: UserID(rawValue: 1), clock: clock)
        let command = try memberRequest()
        let admitted = try await withThrowingTaskGroup(of: Bool.self) { group in
            for generation in 0..<100 {
                group.addTask {
                    try await coordinator.reserve(command, for: requestShard(generation: UInt64(generation))) == .admitted
                }
            }
            var count = 0
            for try await result in group { if result { count += 1 } }
            return count
        }
        #expect(admitted == 1)
        #expect(await coordinator.retainedEntryCount() == 1)
        #expect(try await coordinator.reserve(command, for: requestShard()) == .limited(retryAfter: .seconds(30)))
        try clock.advance(by: .seconds(29))
        #expect(try await coordinator.reserve(command, for: requestShard()) == .limited(retryAfter: .seconds(1)))
        try clock.advance(by: .seconds(1))
        #expect(await coordinator.retainedEntryCount() == 0)
        #expect(try await coordinator.reserve(command, for: requestShard(generation: 100)) == .admitted)
    }

    /// The local full-list cooldown leaves targeted requests and other guilds/families eligible.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func localMemberCooldownScope() async throws {
        let clock = ManualClock()
        let coordinator = try InProcessGatewayCommandCoordinator(botID: UserID(rawValue: 1), clock: clock)
        let shard = try requestShard()
        #expect(try await coordinator.reserve(memberRequest(), for: shard) == .admitted)
        let targeted = try GatewayCommand.requestGuildMembers(guildID: GuildID(rawValue: 1), userIDs: [UserID(rawValue: 1)])
        let prefix = try GatewayCommand.requestGuildMembers(guildID: GuildID(rawValue: 1), query: "a", limit: 1)
        let boundedEmpty = try GatewayCommand.requestGuildMembers(guildID: GuildID(rawValue: 1), query: "", limit: 10)
        let otherGuild = try GatewayCommand.requestGuildMembers(guildID: GuildID(rawValue: 2), query: "", limit: 0)
        let presence = try GatewayCommand.updatePresence(GatewayPresence())
        for command in [targeted, prefix, boundedEmpty, otherGuild, presence] {
            #expect(try await coordinator.reserve(command, for: shard) == .admitted)
        }
        #expect(await coordinator.retainedEntryCount() == 2)
        #expect(try await coordinator.reserve(targeted, for: shard) == .admitted)
    }

    /// Server cooldowns compose by maximum delay, do not shorten, expire inclusively and apply only to matching scopes.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func serverCooldownScopesAndExpiry() async throws {
        let clock = ManualClock()
        let coordinator = try InProcessGatewayCommandCoordinator(botID: UserID(rawValue: 1), clock: clock)
        let shard = try requestShard()
        let one = try GatewayCommand.requestSoundboardSounds(guildIDs: [GuildID(rawValue: 1)])
        let two = try GatewayCommand.requestSoundboardSounds(guildIDs: [GuildID(rawValue: 2)])
        let both = try GatewayCommand.requestSoundboardSounds(guildIDs: [GuildID(rawValue: 1), GuildID(rawValue: 2)])
        try await coordinator.recordLimit(opcode: .requestSoundboardSounds, guildID: nil, retryAfter: .seconds(10))
        try await coordinator.recordLimit(opcode: .requestSoundboardSounds, guildID: GuildID(rawValue: 2), retryAfter: .seconds(20))
        try await coordinator.recordLimit(opcode: .requestSoundboardSounds, guildID: GuildID(rawValue: 2), retryAfter: .seconds(1))
        #expect(try await coordinator.reserve(one, for: shard) == .limited(retryAfter: .seconds(10)))
        #expect(try await coordinator.reserve(two, for: shard) == .limited(retryAfter: .seconds(20)))
        #expect(try await coordinator.reserve(both, for: shard) == .limited(retryAfter: .seconds(20)))
        #expect(try await coordinator.reserve(GatewayCommand.requestChannelInfo(guildID: GuildID(rawValue: 2)), for: shard) == .admitted)
        try clock.advance(by: .seconds(10))
        #expect(await coordinator.retainedEntryCount() == 1)
        #expect(try await coordinator.reserve(one, for: shard) == .admitted)
        #expect(try await coordinator.reserve(two, for: shard) == .limited(retryAfter: .seconds(10)))
        try clock.advance(by: .seconds(10))
        #expect(try await coordinator.reserve(both, for: shard) == .admitted)
        #expect(await coordinator.retainedEntryCount() == 0)
    }

    /// Finite cooldown metadata fails closed, allows in-place extensions, validates delay bounds and reuses expired capacity.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func coordinatorMetadataCapacityAndValidation() async throws {
        let clock = ManualClock()
        #expect(throws: GatewayFailure.invalidConfiguration) {
            try InProcessGatewayCommandCoordinator(botID: UserID(rawValue: 1), clock: clock, maximumEntries: 0)
        }
        let coordinator = try InProcessGatewayCommandCoordinator(botID: UserID(rawValue: 1), clock: clock, maximumEntries: 1)
        let shard = try requestShard()
        for delay: Duration in [.zero, .seconds(-1), .seconds(86_401)] {
            await #expect(throws: GatewayFailure.invalidPayload) {
                try await coordinator.recordLimit(opcode: .requestChannelInfo, guildID: nil, retryAfter: delay)
            }
        }
        try await coordinator.recordLimit(opcode: GatewayOpcode(rawValue: 999), guildID: nil, retryAfter: .seconds(1))
        #expect(await coordinator.retainedEntryCount() == 1)
        try await coordinator.recordLimit(opcode: GatewayOpcode(rawValue: 999), guildID: nil, retryAfter: .seconds(2))
        await #expect(throws: GatewayFailure.commandCapacityExceeded) { try await coordinator.reserve(memberRequest(), for: shard) }
        await #expect(throws: GatewayFailure.commandCapacityExceeded) {
            try await coordinator.recordLimit(opcode: .requestChannelInfo, guildID: nil, retryAfter: .seconds(1))
        }
        #expect(await coordinator.retainedEntryCount() == 1)
        try clock.advance(by: .seconds(2))
        try await coordinator.recordLimit(opcode: .requestChannelInfo, guildID: nil, retryAfter: .seconds(86_400))
        #expect(try await coordinator.reserve(GatewayCommand.requestChannelInfo(guildID: GuildID(rawValue: 1)), for: shard)
            == .limited(retryAfter: .seconds(86_400)))
    }

    /// Wrong bot identities and shard routes fail before mutating shared admission metadata.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func coordinatorBotAndRoutingValidation() async throws {
        let clock = ManualClock()
        let coordinator = try InProcessGatewayCommandCoordinator(botID: UserID(rawValue: 1), clock: clock)
        let wrongBot = try ShardIdentity(botID: UserID(rawValue: 2), topologyGeneration: 0, index: 0, count: 1)
        let wrongShard = try ShardIdentity(botID: UserID(rawValue: 1), topologyGeneration: 0, index: 1, count: 2)
        let command = try memberRequest()
        await #expect(throws: GatewayFailure.invalidConfiguration) { try await coordinator.reserve(command, for: wrongBot) }
        await #expect(throws: GatewayFailure.invalidConfiguration) { try await coordinator.reserve(command, for: wrongShard) }
        #expect(await coordinator.retainedEntryCount() == 0)
        #expect(try await coordinator.reserve(command, for: requestShard()) == .admitted)
    }

    /// Cancellation before admission or a server-limit update never consumes finite cooldown metadata.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func coordinatorCancellation() async throws {
        let clock = ManualClock()
        let coordinator = try InProcessGatewayCommandCoordinator(botID: UserID(rawValue: 1), clock: clock)
        let shard = try requestShard()
        let command = try memberRequest()
        let reservation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try await coordinator.reserve(command, for: shard)
        }
        await #expect(throws: CancellationError.self) { try await reservation.value }
        let recording = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await coordinator.recordLimit(opcode: .requestGuildMembers, guildID: nil, retryAfter: .seconds(1))
        }
        await #expect(throws: CancellationError.self) { try await recording.value }
        #expect(await coordinator.retainedEntryCount() == 0)
        #expect(try await coordinator.reserve(command, for: shard) == .admitted)
    }
}

/// Constructs an isolated finite response registry for deterministic direct reducer testing.
/// - Parameters:
///   - maximumRequests: Concurrent waiter bound, default eight.
///   - maximumEvents: Per-request distinct response bound, default eight.
///   - maximumBytes: Aggregate retained wire bytes, default 65536.
///   - maximumRetiredKeys: Generation-local future and retired correlation metadata bound, default 64.
/// - Returns: Empty registry with no tasks, sockets, continuations or retained payloads.
private func makeRequestRegistry(maximumRequests: Int = 8, maximumEvents: Int = 8,
                                 maximumBytes: Int = 65_536, maximumRetiredKeys: Int = 64) -> GatewayRequestRegistry {
    GatewayRequestRegistry(maximumRequests: maximumRequests, maximumEvents: maximumEvents,
                           maximumBytes: maximumBytes, maximumRetiredKeys: maximumRetiredKeys)
}

/// Builds a one-shard test identity so all positive fixture guild IDs route to the owner.
/// - Parameter generation: Independently varied topology generation, default zero.
/// - Returns: A validated bot-one, shard-zero identity with one total shard.
/// - Throws: Fixture validation failures; no real Discord identity is implied.
private func requestShard(generation: UInt64 = 0) throws -> ShardIdentity {
    try ShardIdentity(botID: UserID(rawValue: 1), topologyGeneration: generation, index: 0, count: 1)
}

/// Creates the standard complete-list request fixture with an explicit response nonce.
/// - Parameter nonce: Correlation string, defaulting to a distinctive value used in redaction checks.
/// - Returns: Reviewed opcode-8 empty-query, zero-limit command for guild one.
/// - Throws: Local command validation or encoding errors.
private func memberRequest(nonce: String = "private-nonce") throws -> GatewayCommand {
    try GatewayCommand.requestGuildMembers(guildID: GuildID(rawValue: 1), query: "", limit: 0, nonce: nonce)
}

/// Constructs a bounded raw dispatch preserving the same wire-size accounting as runtime ingestion.
/// - Parameters:
///   - name: Dispatch name to correlate or deliberately ignore.
///   - data: Complete dispatch data, including malformed payload fixtures when testing rejection.
///   - sequence: Nonnegative fixture sequence, default one.
/// - Returns: Parsed event for the standard test shard with exact serialized UTF-8 byte accounting.
/// - Throws: JSON, envelope or fixture shard validation errors.
private func requestEvent(name: String, data: JSONValue, sequence: Int64 = 1) throws -> GatewayEvent {
    let bytes = try JSONValue.object(["op": gatewayNumber(0), "t": .string(name), "s": gatewayNumber(sequence), "d": data]).serialized()
    let envelope = try GatewayEnvelope(.text(String(decoding: bytes, as: UTF8.self)), maximumBytes: 65_536)
    return try GatewayEvent(shard: requestShard(), envelope: envelope)
}

/// Builds a minimal realistic Guild Members Chunk with explicit nonce and chunk metadata.
/// - Parameters:
///   - guild: Wire guild spelling, default one; malformed strings support correlation-regression tests.
///   - nonce: Exact response correlation string, default private-nonce.
///   - index: Zero-based chunk index, default zero.
///   - count: Positive total chunk count, default one.
///   - sequence: Dispatch sequence, default one.
/// - Returns: Bounded members dispatch with an empty member array and harmless unknown future field.
/// - Throws: JSON, envelope or fixture validation errors.
private func memberChunk(guild: String = "1", nonce: String = "private-nonce", index: Int = 0,
                         count: Int = 1, sequence: Int64 = 1) throws -> GatewayEvent {
    try requestEvent(name: "GUILD_MEMBERS_CHUNK", data: .object(["guild_id": .string(guild), "nonce": .string(nonce),
        "chunk_index": gatewayNumber(index), "chunk_count": gatewayNumber(count), "members": .array([]),
        "future": .null]), sequence: sequence)
}

/// Builds a minimal soundboard response for one guild without an invented nonce.
/// - Parameters:
///   - guild: Wire guild string, default one.
///   - sequence: Dispatch sequence, default one.
/// - Returns: Bounded response with an empty sound list, which is a valid completed guild observation.
/// - Throws: Fixture encoding or envelope validation errors.
private func soundboardEvent(guild: String = "1", sequence: Int64 = 1) throws -> GatewayEvent {
    try requestEvent(name: "SOUNDBOARD_SOUNDS", data: .object(["guild_id": .string(guild), "soundboard_sounds": .array([])]), sequence: sequence)
}

/// Builds a minimal channel-info response for one guild without an invented nonce.
/// - Parameters:
///   - guild: Wire guild string, default one.
///   - sequence: Dispatch sequence, default one.
/// - Returns: Bounded response with an empty channels array, completing the requested guild observation.
/// - Throws: Fixture encoding or envelope validation errors.
private func channelInfoEvent(guild: String = "1", sequence: Int64 = 1) throws -> GatewayEvent {
    try requestEvent(name: "CHANNEL_INFO", data: .object(["guild_id": .string(guild), "channels": .array([])]), sequence: sequence)
}

/// Awaits an already-terminated fixture stream and extracts its typed bounded failure.
/// - Parameter stream: Stream whose matching registry entry has synchronously failed before this call.
/// - Returns: The exact typed request failure including partial evidence and optional server delay.
/// - Throws: Any unexpected stream error, or invalidPayload after recording an unexpected normal completion.
private func requestFailure(_ stream: AsyncThrowingStream<GatewayRequestResult, any Error>) async throws -> GatewayRequestFailure {
    var iterator = stream.makeAsyncIterator()
    do { _ = try await iterator.next() }
    catch let failure as GatewayRequestFailure { return failure }
    Issue.record("Expected a terminated request stream to throw GatewayRequestFailure")
    throw GatewayFailure.invalidPayload
}

extension GatewayRequestTests {
    /// The documented server opcode-eight limit, with and without a guild scope, applies
    /// only to empty-query/zero-limit full-list requests; targeted/prefix requests remain eligible.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func serverFullMemberCooldownScope() async throws {
        for guild: GuildID? in [GuildID(rawValue: 1), nil] {
            let clock = ManualClock()
            let coordinator = try InProcessGatewayCommandCoordinator(botID: UserID(rawValue: 1), clock: clock)
            let shard = try requestShard()
            try await coordinator.recordLimit(opcode: .requestGuildMembers, guildID: guild, retryAfter: .seconds(40))
            let full = try GatewayCommand.requestGuildMembers(guildID: GuildID(rawValue: 1), query: "", limit: 0)
            #expect(try await coordinator.reserve(full, for: shard) == .limited(retryAfter: .seconds(40)))
            for command in [
                try GatewayCommand.requestGuildMembers(guildID: GuildID(rawValue: 1), userIDs: [UserID(rawValue: 1)]),
                try GatewayCommand.requestGuildMembers(guildID: GuildID(rawValue: 1), query: "a", limit: 1),
                try GatewayCommand.requestGuildMembers(guildID: GuildID(rawValue: 1), query: "", limit: 10)
            ] { #expect(try await coordinator.reserve(command, for: shard) == .admitted) }
            try clock.advance(by: .seconds(40))
            #expect(try await coordinator.reserve(full, for: shard) == .admitted)
        }
    }

    /// A full-list rate event without a nonce cannot fail an unrelated targeted member request.
    /// An exact nonce continues to correlate unexpected server failures conservatively.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func serverFullMemberFailureScope() async throws {
        var registry = makeRequestRegistry()
        let full = try memberRequest()
        let targeted = try GatewayCommand.requestGuildMembers(guildID: GuildID(rawValue: 1), userIDs: [UserID(rawValue: 1)], nonce: "targeted")
        let fullStream = try registry.register(id: UUID(), command: full)
        let targetedID = UUID(), targetedStream = try registry.register(id: targetedID, command: targeted)
        registry.rateLimited(opcode: 8, guild: GuildID(rawValue: 1), nonce: nil, retryAfter: .seconds(1))
        #expect(try await requestFailure(fullStream).reason == .rateLimited)
        #expect(registry.pending.count == 1)
        #expect(registry.pending[targetedID]?.command.nonce == "targeted")
        registry.ingest(try memberChunk(nonce: "targeted", sequence: 9))
        var iterator = targetedStream.makeAsyncIterator()
        #expect(try await iterator.next()?.events.map(\.sequence) == [9])
        #expect(registry.pending.isEmpty)
    }
}
