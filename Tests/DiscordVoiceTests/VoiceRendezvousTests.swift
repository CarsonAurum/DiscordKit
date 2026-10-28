// File: Tests/DiscordVoiceTests/VoiceRendezvousTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import Foundation
import Testing
@testable import DiscordVoice

/// Builds realistic immutable model fixtures through their public bounded parsers.
@Suite("Voice join rendezvous")
struct VoiceRendezvousTests {
    /// Produces one complete voice-state snapshot with configurable scope and nullable channel.
    /// - Parameters:
    ///   - guild: Guild decimal spelling; nil omits the optional guild field.
    ///   - user: User decimal spelling, default the joining account.
    ///   - channel: Channel decimal spelling; nil represents a self leave.
    ///   - session: Session identifier retained exactly after JSON serialization.
    /// - Returns: Parsed immutable snapshot with all documented required flags present.
    /// - Throws: Fixture serialization/model errors; no network or credentials are used.
    private func state(guild: String? = "1", user: String = "2", channel: String? = "3",
                       session: String = "session") throws -> VoiceState {
        var object: [String: JSONValue] = ["user_id": .string(user), "channel_id": channel.map(JSONValue.string) ?? .null,
            "session_id": .string(session), "deaf": .bool(false), "mute": .bool(false), "self_deaf": .bool(false),
            "self_mute": .bool(false), "self_video": .bool(false), "suppress": .bool(false),
            "request_to_speak_timestamp": .null]
        if let guild { object["guild_id"] = .string(guild) }
        return try VoiceState(data: JSONValue.object(object).serialized())
    }

    /// Produces one voice-server event, preserving explicit null endpoints for invalidation tests.
    /// - Parameters:
    ///   - guild: Guild decimal spelling, default the scoped guild.
    ///   - token: Opaque synthetic credential; never a real bot or voice token.
    ///   - endpoint: Opaque server endpoint; nil represents temporary server unavailability.
    /// - Returns: Parsed immutable main-Gateway event projection.
    /// - Throws: Fixture serialization/model errors before the rendezvous is called.
    private func server(guild: String = "1", token: String = "token", endpoint: String? = "voice.discord.media") throws
        -> GatewayVoiceServerUpdate {
        try GatewayVoiceServerUpdate(data: JSONValue.object(["guild_id": .string(guild), "token": .string(token),
            "endpoint": endpoint.map(JSONValue.string) ?? .null]).serialized())
    }

    /// Creates a fresh scoped coordinator with explicit policy bounds and no I/O.
    /// - Parameter bound: Positive per-field UTF-8 retention bound, default 4,096.
    /// - Returns: A generation-zero rendezvous for guild 1, user 2, and channel 3.
    /// - Throws: Configuration errors for invalid bounds.
    private func rendezvous(bound: Int = 4_096) throws -> VoiceJoinRendezvous {
        try VoiceJoinRendezvous(guildID: GuildID(rawValue: 1), userID: UserID(rawValue: 2),
            channelID: ChannelID(rawValue: 3), maximumCredentialFieldBytes: bound)
    }

    /// Both event orders produce identical credentials once; duplicate frames do not request reconnects.
    /// - Parameter serverFirst: Whether server information arrives before the self state.
    @Test(arguments: [false, true])
    func eitherOrderAndDuplicates(serverFirst: Bool) throws {
        var value = try rendezvous()
        let state = try state(), server = try server()
        let first = serverFirst ? try value.receive(server: server, generation: 0) : try value.receive(state: state, generation: 0)
        #expect(first == nil)
        let credentials = serverFirst ? try value.receive(state: state, generation: 0) : try value.receive(server: server, generation: 0)
        let result = try #require(credentials)
        #expect(result.guildID.rawValue == 1 && result.userID.rawValue == 2 && result.channelID.rawValue == 3)
        #expect(result.sessionID == "session" && result.token == "token" && result.endpoint == "voice.discord.media")
        #expect(result.generation == 0)
        #expect(try value.receive(state: state, generation: 0) == nil)
        #expect(try value.receive(server: server, generation: 0) == nil)
        #expect(!String(reflecting: result).contains("voice.discord.media"))
        #expect(result.description == "VoiceConnectionCredentials(redacted)")
        #expect(result.customMirror.children.count == 1)
        #expect(value.description == "VoiceJoinRendezvous(redacted)")
        #expect(value.customMirror.children.count == 1)
    }

    /// Ignores unrelated guild/member/unguilded events without clearing the matching half.
    @Test func unrelatedScopes() throws {
        var value = try rendezvous()
        #expect(try value.receive(state: state(user: "99", channel: nil), generation: 0) == nil)
        #expect(try value.receive(state: state(guild: "99"), generation: 0) == nil)
        #expect(try value.receive(state: state(guild: nil), generation: 0) == nil)
        #expect(try value.receive(server: server(guild: "99"), generation: 0) == nil)
        #expect(!value.isInvalidated)
        #expect(try value.receive(state: state(), generation: 0) == nil)
        #expect(try value.receive(server: server(), generation: 0) != nil)
    }

    /// Replacement fences old inputs and clears both credentials even when the endpoint repeats.
    @Test func replacementAndStaleGeneration() throws {
        var value = try rendezvous()
        _ = try value.receive(state: state(), generation: 0)
        _ = try value.receive(server: server(), generation: 0)
        #expect(try value.replace(channelID: ChannelID(rawValue: 4)) == 1)
        #expect(value.channelID.rawValue == 4 && value.generation == 1)
        #expect(throws: VoiceControlFailure.staleGeneration) { try value.receive(state: state(), generation: 0) }
        #expect(throws: VoiceControlFailure.staleGeneration) { try value.receive(server: server(), generation: 0) }
        #expect(try value.receive(server: server(token: "new-token"), generation: 1) == nil)
        let completed = try value.receive(state: state(channel: "4", session: "new-session"), generation: 1)
        let credentials = try #require(completed)
        #expect(credentials.sessionID == "new-session" && credentials.token == "new-token" && credentials.generation == 1)
    }

    /// A null endpoint clears both halves and requires fresh state plus server information.
    @Test func nullEndpoint() throws {
        var value = try rendezvous()
        _ = try value.receive(state: state(), generation: 0)
        _ = try value.receive(server: server(), generation: 0)
        #expect(try value.receive(server: server(endpoint: nil), generation: 0) == nil)
        #expect(try value.receive(server: server(token: "replacement"), generation: 0) == nil)
        #expect(try value.receive(state: state(session: "fresh"), generation: 0)?.sessionID == "fresh")
    }

    /// Self leave and unsolicited channel moves invalidate until explicit replacement.
    /// - Parameter channel: Nil for leave, or another channel for a move not initiated by this generation.
    @Test(arguments: [Optional<String>.none, "4"])
    func leaveAndMove(channel: String?) throws {
        var value = try rendezvous()
        _ = try value.receive(server: server(), generation: 0)
        #expect(try value.receive(state: state(channel: channel), generation: 0) == nil)
        #expect(value.isInvalidated)
        #expect(throws: VoiceControlFailure.closed) { try value.receive(state: state(), generation: 0) }
        #expect(throws: VoiceControlFailure.closed) { try value.receive(server: server(), generation: 0) }
        value.invalidate(); value.invalidate()
        _ = try value.replace(channelID: ChannelID(rawValue: 3))
        #expect(!value.isInvalidated)
        #expect(try value.receive(state: state(), generation: 1) == nil)
        #expect(try value.receive(server: server(), generation: 1) != nil)
    }

    /// Changed completed server/session halves cannot pair with the previous counterpart.
    /// - Parameter stateFirst: Which half changes first after the initial pair was emitted.
    @Test(arguments: [false, true])
    func changedCompletedHalf(stateFirst: Bool) throws {
        var value = try rendezvous()
        _ = try value.receive(state: state(), generation: 0)
        _ = try value.receive(server: server(), generation: 0)
        if stateFirst {
            #expect(try value.receive(state: state(session: "new-session"), generation: 0) == nil)
            #expect(try value.receive(server: server(token: "new-token"), generation: 0)?.sessionID == "new-session")
        } else {
            #expect(try value.receive(server: server(token: "new-token"), generation: 0) == nil)
            #expect(try value.receive(state: state(session: "new-session"), generation: 0)?.token == "new-token")
        }
    }

    /// Rejects empty and oversized sensitive fields without losing a previously admitted valid half.
    @Test func retentionBoundsAndEmptyFields() throws {
        #expect(throws: VoiceControlFailure.invalidConfiguration) { try rendezvous(bound: 0) }
        var value = try rendezvous(bound: 5)
        for session in ["", "123456", "ééé"] {
            #expect(throws: VoiceControlFailure.invalidPayload) { try value.receive(state: state(session: session), generation: 0) }
        }
        _ = try value.receive(state: state(session: "12345"), generation: 0)
        for (token, endpoint) in [("", "host"), ("123456", "host"), ("token", ""), ("token", "123456")] {
            #expect(throws: VoiceControlFailure.invalidPayload) {
                try value.receive(server: server(token: token, endpoint: endpoint), generation: 0)
            }
        }
        #expect(try value.receive(server: server(token: "12345", endpoint: "12345"), generation: 0)?.sessionID == "12345")
    }
}
