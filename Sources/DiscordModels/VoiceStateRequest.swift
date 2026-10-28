// File: Sources/DiscordModels/VoiceStateRequest.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore

/// API v10 PATCH /guilds/{guild.id}/voice-states/@me, for an already joined Stage channel.
/// See https://docs.discord.com/developers/resources/voice#modify-current-user-voice-state.
/// Discord verifies membership, MUTE_MEMBERS when unsuppressing and REQUEST_TO_SPEAK when requesting.
public struct CurrentUserVoiceStateModify: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates presence/null semantics without reading membership, permissions or the current clock.
    /// - Parameters:
    ///   - channelID: Optional currently joined Stage channel; omitted by default and null is forbidden.
    ///   - suppress: Optional suppression change; omitted by default and null is forbidden.
    ///   - requestToSpeakTimestamp: Omitted by default; null clears the request. A value preserves its exact
    ///     timestamp spelling. Discord requires a present/future instant at execution; no local clock race is introduced.
    /// - Throws: Sanitized invalid-value errors for a null channel or suppression flag before any I/O.
    /// Empty changes remain an explicit empty PATCH body. No channel join or permission request is implied.
    public init(channelID: Field<ChannelID> = .absent, suppress: Field<Bool> = .absent,
                requestToSpeakTimestamp: Field<DiscordTimestamp> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(channelID, name: "channel_id", into: &result) { .string($0.description) }
        try guildRequestField(suppress, name: "suppress", into: &result) { .bool($0) }
        try guildRequestField(requestToSpeakTimestamp, name: "request_to_speak_timestamp", nullable: true,
                              into: &result) { .string($0.rawValue) }
        fields = result
    }

    /// Returns only explicitly selected changes, retaining omission and request clearing independently.
    /// - Returns: Exact validated JSON object; callers explicitly accessing it own safe-logging responsibility.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 PATCH /guilds/{guild.id}/voice-states/{user.id}; requires MUTE_MEMBERS.
/// The target must already be in the supplied Stage channel. Unsuppressing a non-bot requests to speak
/// at the server's current time; suppressing clears that request. No outgoing timestamp field is supported.
public struct UserVoiceStateModify: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates explicit changes without fetching the target or inferring current channel/permission state.
    /// - Parameters:
    ///   - channelID: Currently joined Stage channel, omitted by default; explicit null is forbidden.
    ///   - suppress: Desired suppression flag, omitted by default; explicit null is forbidden.
    /// - Throws: Sanitized invalid-value errors for forbidden nulls. Empty changes are valid local PATCH
    ///   objects; Discord checks eligibility and current permissions at execution. No I/O or tasks begin here.
    public init(channelID: Field<ChannelID> = .absent, suppress: Field<Bool> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(channelID, name: "channel_id", into: &result) { .string($0.description) }
        try guildRequestField(suppress, name: "suppress", into: &result) { .bool($0) }
        fields = result
    }

    /// Returns the immutable validated PATCH object without adding current-user-only timestamp fields.
    /// - Returns: Exact explicit changes, including an empty object when all parameters were omitted.
    public func jsonValue() -> JSONValue { .object(fields) }
}
