// File: Tests/DiscordGatewayTests/GatewayCommandTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordTransport
import Foundation
import Testing
@testable import DiscordGateway

/// Offline protocol-contract coverage; fixtures never open sockets or use Discord credentials.
@Suite("Gateway outgoing commands")
struct GatewayCommandTests {
    /// Checks every documented opcode independently and preserves unknown future values exactly.
    @Test func opcodeDefinitions() {
        let definitions: [(GatewayOpcode, Int)] = [
            (.dispatch, 0), (.heartbeat, 1), (.identify, 2), (.presenceUpdate, 3),
            (.voiceStateUpdate, 4), (.resume, 6), (.reconnect, 7), (.requestGuildMembers, 8),
            (.invalidSession, 9), (.hello, 10), (.heartbeatACK, 11),
            (.requestSoundboardSounds, 31), (.requestChannelInfo, 43)
        ]
        for (opcode, expected) in definitions { #expect(opcode.rawValue == expected) }
        #expect(GatewayOpcode(rawValue: 999).rawValue == 999)
        #expect(GatewayOpcode(rawValue: 999) != .hello)
        #expect(Set(definitions.map(\.0)).count == 13)
    }

    /// Covers all current intent bits, the three privileged bits, gaps, set operations and unknown-bit retention.
    @Test func intentAndCapabilityDefinitions() {
        let definitions: [(GatewayIntents, Int)] = [
            (.guilds, 0), (.guildMembers, 1), (.guildModeration, 2), (.guildExpressions, 3),
            (.guildIntegrations, 4), (.guildWebhooks, 5), (.guildInvites, 6), (.guildVoiceStates, 7),
            (.guildPresences, 8), (.guildMessages, 9), (.guildMessageReactions, 10), (.guildMessageTyping, 11),
            (.directMessages, 12), (.directMessageReactions, 13), (.directMessageTyping, 14),
            (.messageContent, 15), (.guildScheduledEvents, 16), (.autoModerationConfiguration, 20),
            (.autoModerationExecution, 21), (.guildMessagePolls, 24), (.directMessagePolls, 25)
        ]
        for (intent, bit) in definitions { #expect(intent.rawValue == UInt64(1) << bit) }
        #expect(GatewayIntents.known.rawValue == definitions.reduce(UInt64(0)) { $0 | $1.0.rawValue })
        #expect(GatewayIntents.privileged == [.guildMembers, .guildPresences, .messageContent])
        #expect(GatewayIntents.known.intersection(GatewayIntents(rawValue: 1 << 17)).isEmpty)
        let future = GatewayIntents(rawValue: UInt64.max)
        #expect(future.rawValue == UInt64.max)
        #expect(future.isSuperset(of: .known))
        #expect(GatewayCapabilities.channelObfuscation.rawValue == 1 << 15)
        #expect(GatewayCapabilities(rawValue: UInt64.max).rawValue == UInt64.max)
    }

    /// Verifies required activity fields, optional omission, supported bot fields and exact Unicode retention.
    /// - Parameter type: Each documented writable activity type, including streaming without an optional URL.
    @Test(arguments: GatewayActivityType.allCases)
    func activityFields(_ type: GatewayActivityType) throws {
        let activity = try GatewayActivity(name: "A 🐕", type: type)
        #expect(activity.name == "A 🐕")
        #expect(activity.type == type)
        #expect(activity.state == nil)
        #expect(activity.url == nil)
        #expect(activity.json == .object(["name": .string("A 🐕"), "type": gatewayNumber(type.rawValue)]))
        let state = try GatewayActivity(name: "", type: type, state: "", url: "https://youtube.com/watch?v=test")
        #expect(state.json == .object(["name": .string(""), "type": gatewayNumber(type.rawValue),
                                       "state": .string(""), "url": .string("https://youtube.com/watch?v=test")]))
        #expect(state != activity)
    }

    /// Accepts the two documented streaming providers and retains unvalidated URL text for other activity types.
    @Test func activityStreamingURLs() throws {
        for url in ["https://twitch.tv/channel", "https://youtube.com/watch?v=a",
                    "https://www.twitch.tv/channel", "https://www.youtube.com/watch?v=a"] {
            #expect(try GatewayActivity(name: "Stream", type: .streaming, url: url).url == url)
        }
        #expect(try GatewayActivity(name: "Test", url: "ignored text").url == "ignored text")
        for url in ["http://twitch.tv/test", "https://twitch.tv.evil.example/a", "https://example.com/a",
                    "https://secret@twitch.tv/a", "https://user:pass@youtube.com/a", "not a URL", ""] {
            #expect(throws: GatewayFailure.invalidPayload) { try GatewayActivity(name: "Test", type: .streaming, url: url) }
        }
    }

    /// Preserves every writable status and requires all four presence fields even with empty activities.
    /// - Parameter status: Each documented outgoing status, including invisible and offline.
    @Test(arguments: GatewayPresenceStatus.allCases)
    func presenceFields(_ status: GatewayPresenceStatus) throws {
        let presence = try GatewayPresence(status: status)
        #expect(presence.since == nil)
        #expect(presence.activities.isEmpty)
        #expect(presence.status == status)
        #expect(!presence.afk)
        #expect(presence.json == .object(["since": .null, "activities": .array([]),
                                        "status": .string(status.rawValue), "afk": .bool(false)]))
        let command = try GatewayCommand.updatePresence(presence)
        #expect(command.opcode == .presenceUpdate)
        #expect(command.kind == .presence)
        #expect(command.guildIDs.isEmpty)
        #expect(command.nonce == nil)
        #expect(command.requiredIntents.isEmpty)
        #expect(!command.requestsAllGuildMembers)
        #expect(command.data == presence.json)
        #expect(try JSONValue.parse(command.serialized()) == .object(["op": gatewayNumber(3), "d": presence.json]))
    }

    /// Exercises timestamp boundaries, activity ordering and explicit away state without assuming wall-clock time.
    @Test func presenceTimestampsAndActivities() throws {
        let first = try GatewayActivity(name: "First")
        let second = try GatewayActivity(name: "Second", type: .custom, state: "Available")
        for timestamp: Int64 in [0, Int64.max] {
            let presence = try GatewayPresence(since: timestamp, activities: [first, second], status: .idle, afk: true)
            #expect(presence.since == timestamp)
            #expect(presence.activities == [first, second])
            #expect(presence.afk)
            #expect(presence.json == .object(["since": gatewayNumber(timestamp),
                "activities": .array([first.json, second.json]), "status": .string("idle"), "afk": .bool(true)]))
        }
        #expect(throws: GatewayFailure.invalidPayload) { try GatewayPresence(since: -1) }
        #expect(throws: GatewayFailure.invalidPayload) { try GatewayPresence(since: Int64.min) }
    }

    /// Default Identify preserves the existing runtime shape with explicit intents, shard numbers and modern property names.
    @Test func defaultIdentify() throws {
        let token = try BotToken("offline-fixture-token")
        let shard = try ShardIdentity(botID: UserID(rawValue: 1), topologyGeneration: 9, index: 2, count: 3)
        let data = try GatewayIdentifyConfiguration.default.payload(token: token, intents: UInt64.max, shard: shard)
        #expect(data == .object(["token": .string("offline-fixture-token"), "intents": gatewayNumber(UInt64.max),
            "shard": .array([gatewayNumber(2), gatewayNumber(3)]),
            "properties": .object(["os": .string("portable"), "browser": .string("DiscordKit"), "device": .string("DiscordKit")])]))
        #expect(GatewayIdentifyConfiguration.default.operatingSystem == "portable")
        #expect(GatewayIdentifyConfiguration.default.browser == "DiscordKit")
        #expect(GatewayIdentifyConfiguration.default.device == "DiscordKit")
        #expect(GatewayIdentifyConfiguration.default.largeThreshold == nil)
        #expect(GatewayIdentifyConfiguration.default.presence == nil)
        #expect(GatewayIdentifyConfiguration.default.capabilities.isEmpty)
    }

    /// Encodes initial presence, inclusive threshold boundaries, custom properties and exact capability bits.
    @Test func configuredIdentify() throws {
        let token = try BotToken("offline-fixture-token")
        let shard = try ShardIdentity(botID: UserID(rawValue: UInt64.max), topologyGeneration: 0, index: 0, count: 1)
        let presence = try GatewayPresence(status: .dnd, afk: true)
        for threshold in [50, 250] {
            let config = GatewayIdentifyConfiguration(operatingSystem: "macOS", browser: "Bot", device: "Server",
                largeThreshold: threshold, presence: presence, capabilities: GatewayCapabilities(rawValue: UInt64.max))
            #expect(config.operatingSystem == "macOS")
            #expect(config.browser == "Bot")
            #expect(config.device == "Server")
            #expect(config.largeThreshold == threshold)
            #expect(config.presence == presence)
            #expect(config.capabilities.rawValue == UInt64.max)
            #expect(try config.payload(token: token, intents: 0, shard: shard) == .object([
                "token": .string("offline-fixture-token"), "intents": gatewayNumber(0),
                "shard": .array([gatewayNumber(0), gatewayNumber(1)]),
                "properties": .object(["os": .string("macOS"), "browser": .string("Bot"), "device": .string("Server")]),
                "large_threshold": gatewayNumber(threshold), "presence": presence.json,
                "capabilities": gatewayNumber(UInt64.max)]))
        }
    }

    /// Rejects malformed Identify options and oversized credential-bearing frames using closed errors only.
    @Test func invalidIdentify() throws {
        let token = try BotToken("offline-fixture-token")
        let shard = try ShardIdentity(botID: UserID(rawValue: 1), topologyGeneration: 0, index: 0, count: 1)
        let configurations = [GatewayIdentifyConfiguration(operatingSystem: ""), GatewayIdentifyConfiguration(browser: ""),
            GatewayIdentifyConfiguration(device: ""), GatewayIdentifyConfiguration(largeThreshold: 49),
            GatewayIdentifyConfiguration(largeThreshold: 251), GatewayIdentifyConfiguration(largeThreshold: Int.min),
            GatewayIdentifyConfiguration(largeThreshold: Int.max), GatewayIdentifyConfiguration(browser: String(repeating: "x", count: 4096))]
        for configuration in configurations {
            #expect(throws: GatewayFailure.invalidPayload) { try configuration.payload(token: token, intents: 0, shard: shard) }
        }
        let oversizedToken = try BotToken(String(repeating: "x", count: 4096))
        #expect(throws: GatewayFailure.invalidPayload) {
            try GatewayIdentifyConfiguration.default.payload(token: oversizedToken, intents: 0, shard: shard)
        }
    }

    /// Voice commands preserve full snowflakes and all mute/deaf combinations; disconnect always writes JSON null.
    /// - Parameters:
    ///   - mute: Explicit desired self-mute state.
    ///   - deaf: Explicit desired self-deafen state, independent of mute at the protocol level.
    @Test(arguments: [false, true], [false, true])
    func voiceState(_ mute: Bool, _ deaf: Bool) throws {
        let guild = GuildID(rawValue: UInt64.max)
        for channel in [nil, ChannelID(rawValue: UInt64.max)] {
            let command = try GatewayCommand.updateVoiceState(guildID: guild, channelID: channel, selfMute: mute, selfDeaf: deaf)
            #expect(command.kind == .voiceState)
            #expect(command.opcode == .voiceStateUpdate)
            #expect(command.guildIDs == [guild])
            #expect(command.nonce == nil)
            #expect(command.requiredIntents.isEmpty)
            #expect(command.data == .object(["guild_id": .string("18446744073709551615"),
                "channel_id": channel.map { .string($0.description) } ?? .null,
                "self_mute": .bool(mute), "self_deaf": .bool(deaf)]))
        }
        let defaults = try GatewayCommand.updateVoiceState(guildID: guild, channelID: nil)
        #expect(defaults.data == .object(["guild_id": .string(guild.description), "channel_id": .null,
                                         "self_mute": .bool(false), "self_deaf": .bool(false)]))
    }

    /// Query requests encode exclusive query/limit fields and derive the correct required-intent and rate metadata.
    @Test func memberQueries() throws {
        let guild = GuildID(rawValue: UInt64.max)
        for query in ["", "Test", "🐕"] {
            for limit in [1, 100] {
                let command = try GatewayCommand.requestGuildMembers(guildID: guild, query: query, limit: limit,
                    presences: true, nonce: "correlation")
                #expect(command.opcode == .requestGuildMembers)
                #expect(command.kind == .members)
                #expect(command.guildIDs == [guild])
                #expect(command.nonce == "correlation")
                #expect(!command.requestsAllGuildMembers)
                #expect(command.requiredIntents == (query.isEmpty ? [.guildMembers, .guildPresences] : .guildPresences))
                #expect(command.data == .object(["guild_id": .string(guild.description), "query": .string(query),
                    "limit": gatewayNumber(limit), "presences": .bool(true), "nonce": .string("correlation")]))
            }
        }
        let full = try GatewayCommand.requestGuildMembers(guildID: guild, query: "", limit: 0)
        #expect(full.nonce == nil)
        #expect(full.requestsAllGuildMembers)
        #expect(full.requiredIntents == .guildMembers)
        #expect(full.data == .object(["guild_id": .string(guild.description), "query": .string(""),
                                     "limit": gatewayNumber(0), "presences": .bool(false)]))
        #expect(!(try GatewayCommand.requestGuildMembers(guildID: guild, query: "", limit: Int.max).requestsAllGuildMembers))
        #expect(try GatewayCommand.requestGuildMembers(guildID: guild, query: "T", limit: 1).requiredIntents.isEmpty)
    }

    /// Invalid prefix limits fail before send; a valid empty-query zero limit remains the documented full-list form.
    @Test func invalidMemberQueries() {
        let guild = GuildID(rawValue: 1)
        for limit in [Int.min, -1] {
            #expect(throws: GatewayFailure.invalidPayload) { try GatewayCommand.requestGuildMembers(guildID: guild, query: "", limit: limit) }
        }
        for limit in [Int.min, -1, 0, 101, Int.max] {
            #expect(throws: GatewayFailure.invalidPayload) { try GatewayCommand.requestGuildMembers(guildID: guild, query: "prefix", limit: limit) }
        }
        #expect(throws: GatewayFailure.invalidPayload) {
            try GatewayCommand.requestGuildMembers(guildID: guild, query: String(repeating: "x", count: 4096), limit: 1)
        }
    }

    /// Exact-user queries omit query/limit, preserve ordering and full IDs, and exercise inclusive user-count bounds.
    @Test func memberUserIDs() throws {
        let guild = GuildID(rawValue: 1)
        for users in [[UserID(rawValue: UInt64.max)], (1...100).map { UserID(rawValue: UInt64($0)) }] {
            for presences in [false, true] {
                let command = try GatewayCommand.requestGuildMembers(guildID: guild, userIDs: users,
                    presences: presences, nonce: "")
                #expect(command.kind == .members)
                #expect(command.opcode == .requestGuildMembers)
                #expect(command.nonce == "")
                #expect(command.guildIDs == [guild])
                #expect(!command.requestsAllGuildMembers)
                #expect(command.requiredIntents == (presences ? .guildPresences : []))
                #expect(command.data == .object(["guild_id": .string("1"),
                    "user_ids": .array(users.map { .string($0.description) }),
                    "presences": .bool(presences), "nonce": .string("")]))
            }
        }
        let defaults = try GatewayCommand.requestGuildMembers(guildID: guild, userIDs: [UserID(rawValue: 1)])
        #expect(defaults.nonce == nil)
        #expect(defaults.requiredIntents.isEmpty)
    }

    /// Rejects empty, duplicate and over-100 exact-user lists without dispatching partial requests.
    @Test func invalidMemberUserIDs() {
        let guild = GuildID(rawValue: 1)
        for users in [[], [UserID(rawValue: 1), UserID(rawValue: 1)],
                      (1...101).map { UserID(rawValue: UInt64($0)) }] {
            #expect(throws: GatewayFailure.invalidPayload) { try GatewayCommand.requestGuildMembers(guildID: guild, userIDs: users) }
        }
    }

    /// Both member factories enforce a UTF-8 nonce bound rather than a Swift character-count bound.
    @Test func memberNonceBytes() throws {
        let guild = GuildID(rawValue: 1)
        for nonce in [nil, "", String(repeating: "x", count: 32), String(repeating: "🐕", count: 8)] {
            #expect(try GatewayCommand.requestGuildMembers(guildID: guild, query: "", limit: 0, nonce: nonce).nonce == nonce)
            #expect(try GatewayCommand.requestGuildMembers(guildID: guild, userIDs: [UserID(rawValue: 1)], nonce: nonce).nonce == nonce)
        }
        for nonce in [String(repeating: "x", count: 33), String(repeating: "🐕", count: 9)] {
            #expect(throws: GatewayFailure.invalidPayload) { try GatewayCommand.requestGuildMembers(guildID: guild, query: "", limit: 0, nonce: nonce) }
            #expect(throws: GatewayFailure.invalidPayload) { try GatewayCommand.requestGuildMembers(guildID: guild, userIDs: [UserID(rawValue: 1)], nonce: nonce) }
        }
    }

    /// Soundboard requests preserve ordered unique guild IDs and expose no nonexistent protocol nonce.
    @Test func soundboardRequests() throws {
        let guilds = [GuildID(rawValue: UInt64.max), GuildID(rawValue: 1)]
        let command = try GatewayCommand.requestSoundboardSounds(guildIDs: guilds)
        #expect(command.kind == .soundboardSounds)
        #expect(command.opcode.rawValue == 31)
        #expect(command.guildIDs == guilds)
        #expect(command.nonce == nil)
        #expect(command.requiredIntents.isEmpty)
        #expect(command.data == .object(["guild_ids": .array([.string("18446744073709551615"), .string("1")])]))
        #expect(try GatewayCommand.requestSoundboardSounds(guildIDs: [guilds[0]]).guildIDs == [guilds[0]])
        #expect(throws: GatewayFailure.invalidPayload) { try GatewayCommand.requestSoundboardSounds(guildIDs: []) }
        #expect(throws: GatewayFailure.invalidPayload) { try GatewayCommand.requestSoundboardSounds(guildIDs: [guilds[0], guilds[0]]) }
        #expect(throws: GatewayFailure.invalidPayload) {
            try GatewayCommand.requestSoundboardSounds(guildIDs: (1...1000).map { GuildID(rawValue: UInt64($0)) })
        }
    }

    /// Channel-info accepts both reviewed ephemeral fields in caller order, defaults to both and never invents a nonce.
    @Test func channelInfoRequests() throws {
        let guild = GuildID(rawValue: UInt64.max)
        #expect(GatewayChannelInfoField.allCases.map(\.rawValue) == ["status", "voice_start_time"])
        for fields: [GatewayChannelInfoField] in [[.status], [.voiceStartTime], [.voiceStartTime, .status]] {
            let command = try GatewayCommand.requestChannelInfo(guildID: guild, fields: fields)
            #expect(command.kind == .channelInfo)
            #expect(command.opcode == .requestChannelInfo)
            #expect(command.guildIDs == [guild])
            #expect(command.nonce == nil)
            #expect(command.requiredIntents.isEmpty)
            #expect(command.data == .object(["guild_id": .string(guild.description), "fields": .array(fields.map { .string($0.rawValue) })]))
        }
        #expect(try GatewayCommand.requestChannelInfo(guildID: guild).data == .object([
            "guild_id": .string(guild.description), "fields": .array([.string("status"), .string("voice_start_time")])]))
        #expect(throws: GatewayFailure.invalidPayload) { try GatewayCommand.requestChannelInfo(guildID: guild, fields: []) }
        #expect(throws: GatewayFailure.invalidPayload) { try GatewayCommand.requestChannelInfo(guildID: guild, fields: [.status, .status]) }
    }

    /// The complete envelope accepts exactly 4096 UTF-8 bytes and rejects one more byte, including escaping overhead.
    @Test func exactOutboundByteLimit() throws {
        let baseline = try GatewayCommand.updatePresence(GatewayPresence())
        let activity = try GatewayActivity(name: "")
        let emptyActivity = try GatewayCommand.updatePresence(GatewayPresence(activities: [activity]))
        #expect(baseline.serialized().utf8.count < emptyActivity.serialized().utf8.count)
        let remaining = 4096 - emptyActivity.serialized().utf8.count
        let exact = try GatewayCommand.updatePresence(GatewayPresence(activities: [GatewayActivity(name: String(repeating: "x", count: remaining))]))
        #expect(exact.serialized().utf8.count == 4096)
        #expect(try JSONValue.parse(exact.serialized()) == .object(["op": gatewayNumber(3), "d": exact.data]))
        #expect(throws: GatewayFailure.invalidPayload) {
            try GatewayCommand.updatePresence(GatewayPresence(activities: [GatewayActivity(name: String(repeating: "x", count: remaining + 1))]))
        }
        #expect(throws: GatewayFailure.invalidPayload) {
            try GatewayCommand.updatePresence(GatewayPresence(activities: [GatewayActivity(name: String(repeating: "🐕", count: remaining / 4 + 1))]))
        }
        #expect(throws: GatewayFailure.invalidPayload) {
            try GatewayCommand.updatePresence(GatewayPresence(activities: [GatewayActivity(name: String(repeating: "\"", count: remaining))]))
        }
    }

    /// The shared encoder covers runtime control frames and fails closed without including sensitive payload contents.
    @Test func controlEncodingAndRedaction() throws {
        #expect(try JSONValue.parse(gatewayCommandText(opcode: .heartbeat, data: .null)) ==
            .object(["op": gatewayNumber(1), "d": .null]))
        #expect(try JSONValue.parse(gatewayCommandText(opcode: .resume, data: .object(["seq": gatewayNumber(Int64.max)]))) ==
            .object(["op": gatewayNumber(6), "d": .object(["seq": gatewayNumber(Int64.max)])]))
        #expect(throws: GatewayFailure.invalidPayload) { try gatewayCommandText(opcode: .identify, data: .string(String(repeating: "secret", count: 1000))) }
        let command = try GatewayCommand.requestGuildMembers(guildID: GuildID(rawValue: 123), query: "private", limit: 1, nonce: "private-nonce")
        #expect(command.description == "GatewayCommand(redacted)")
        #expect(String(describing: command) == "GatewayCommand(redacted)")
        #expect(!String(reflecting: command).contains("private"))
        let mirror = command.customMirror
        #expect(mirror.children.count == 1)
        #expect(mirror.children.first?.label == "redacted")
        #expect(mirror.children.first?.value as? Bool == true)
        #expect(command.serialized() == command.serialized())
    }
}
