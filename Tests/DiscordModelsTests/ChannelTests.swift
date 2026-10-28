// File: Tests/DiscordModelsTests/ChannelTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Exercises the complete documented Channel-owned response schemas with local, credential-free JSON.
/// Fixtures independently describe required/nullable contracts, typed values and future data retention.
@Suite struct ChannelTests {
    /// Covers every modeled field's presence, nullability and wire type, plus exact unknown JSON and redaction.
    /// - Parameter fixture: Complete response fixture and independently recorded official field contracts.
    /// - Throws: Unexpected JSON/schema or required-fixture assertion errors fail the test; expected invalid payloads are asserted locally.
    @Test(arguments: ChannelResponseFixture.cases)
    fileprivate func schemaContractsAndUnknownRetention(fixture: ChannelResponseFixture) throws {
        var fields = try fixture.fields()
        let future = try JSONNumber(rawValue: "1.23000000000000000000001e1000")
        fields["future_secret"] = .number(future)
        fields["future_container"] = .object(["secret": .array([.object(["deeper": .bool(true)])])])
        let body = try JSONValue.object(fields).serialized()
        let decoded = try fixture.decode(body)
        #expect(decoded.rawFields == fields)
        #expect(decoded.jsonValue() == .object(fields))
        #expect(decoded.description.hasSuffix("(redacted)"))
        #expect(!decoded.description.contains("secret text"))
        #expect(!decoded.debugDescription.contains("secret text"))
        #expect(!String(reflecting: decoded).contains("secret text"))
        #expect(decoded.customMirror.children.count == 1)
        for field in fixture.contracts {
            var altered = fields
            altered.removeValue(forKey: field.name)
            if field.required {
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try fixture.decode(JSONValue.object(altered).serialized())
                }
            } else {
                #expect(try fixture.decode(JSONValue.object(altered).serialized()).rawFields[field.name] == nil)
            }
            altered = fields
            altered[field.name] = .null
            if fixture.name == "DefaultReaction" {
                // Each required nullable key is valid with its alternative populated.
                altered[field.name == "emoji_id" ? "emoji_name" : "emoji_id"] = .string(field.name == "emoji_id" ? "😀" : "5")
            }
            if field.nullable {
                #expect(try fixture.decode(JSONValue.object(altered).serialized()).rawFields[field.name] == .null)
            } else {
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try fixture.decode(JSONValue.object(altered).serialized())
                }
            }
            altered = fields
            altered[field.name] = field.array ? .bool(false) : .array([])
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try fixture.decode(JSONValue.object(altered).serialized())
            }
        }
        #expect(throws: JSONValueError.maximumBytesExceeded) {
            try fixture.decode(body, limits: JSONLimits(maximumBytes: 1))
        }
        #expect(throws: JSONValueError.maximumDepthExceeded) {
            try fixture.decode(body, limits: JSONLimits(maximumDepth: 1))
        }
        #expect(throws: JSONValueError.maximumNodesExceeded) {
            try fixture.decode(body, limits: JSONLimits(maximumNodes: 1))
        }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.decode(Data("[]".utf8)) }
        #expect(throws: JSONValueError.self) { try fixture.decode(Data("{".utf8)) }
    }

    /// Asserts all Channel scalar projections, large IDs, ordered typed arrays and future enum variants.
    /// - Throws: Unexpected JSON/schema or required-fixture assertion errors fail the test; expected invalid payloads are asserted locally.
    @Test func completeChannelTypedValues() throws {
        let channel = try Channel(data: ChannelResponseFixture.channelData())
        #expect(channel.id.rawValue == UInt64.max)
        #expect(channel.type == RawValue(.guildForum))
        #expect(channel.guildID == .value(GuildID(rawValue: UInt64.max)))
        #expect(channel.position == .value(2))
        #expect(channel.name == .value("secret text"))
        #expect(channel.topic == .value("secret text"))
        #expect(channel.nsfw == .value(false))
        #expect(channel.lastMessageID == .value(MessageID(rawValue: UInt64.max)))
        #expect(channel.bitrate == .value(64000))
        #expect(channel.userLimit == .value(0))
        #expect(channel.rateLimitPerUser == .value(21600))
        #expect(channel.icon == .value("secret text"))
        #expect(channel.ownerID == .value(UserID(rawValue: UInt64.max)))
        #expect(channel.applicationID == .value(ApplicationID(rawValue: UInt64.max)))
        #expect(channel.managed == .value(true))
        #expect(channel.parentID == .value(ChannelID(rawValue: UInt64.max)))
        #expect(channel.lastPinTimestamp == .value(try DiscordTimestamp(rawValue: "2026-10-16T17:00:00.123456Z")))
        #expect(channel.rtcRegion == .value("automatic-test"))
        #expect(channel.videoQualityMode == .value(RawValue(rawValue: 99)))
        #expect(channel.messageCount == .value(1000))
        #expect(channel.memberCount == .value(50))
        #expect(channel.defaultAutoArchiveDuration == .value(10080))
        #expect(channel.permissions == .value("000184467440737095516160000"))
        #expect(channel.appPermissions == .value("184467440737095516160001"))
        #expect(channel.flags == .value(UInt64.max))
        #expect(channel.totalMessageSent == .value(2000))
        #expect(channel.appliedTags == .value([ForumTagID(rawValue: UInt64.max), ForumTagID(rawValue: 1)]))
        #expect(channel.defaultThreadRateLimitPerUser == .value(0))
        #expect(channel.defaultSortOrder == .value(RawValue(rawValue: 99)))
        #expect(channel.defaultForumLayout == .value(RawValue(rawValue: 99)))
        #expect(channel.isObfuscated)
        guard case .value(let overwrites) = channel.permissionOverwrites,
              case .value(let recipients) = channel.recipients,
              case .value(let tags) = channel.availableTags,
              case .value(let reaction) = channel.defaultReactionEmoji,
              case .value(let metadata) = channel.threadMetadata,
              case .value(let member) = channel.member,
              case .value(let message) = channel.message
        else { Issue.record("Missing documented Channel nested values"); return }
        #expect(overwrites.count == 1)
        #expect(overwrites.first?.id.rawValue == UInt64.max)
        #expect(overwrites.first?.type == RawValue(.member))
        #expect(overwrites.first?.allow == "184467440737095516160000")
        #expect(overwrites.first?.deny == "0000")
        #expect(recipients.first?.id.rawValue == UInt64.max)
        #expect(recipients.first?.username == .value("secret text"))
        #expect(tags.first?.id.rawValue == UInt64.max)
        #expect(tags.first?.name == "secret text")
        #expect(tags.first?.moderated == true)
        #expect(tags.first?.emojiID == .null)
        #expect(tags.first?.emojiName == .null)
        #expect(reaction.emojiID == .value(EmojiID(rawValue: UInt64.max)))
        #expect(reaction.emojiName == .null)
        #expect(metadata.archived)
        #expect(metadata.autoArchiveDuration == 1440)
        #expect(metadata.archiveTimestamp.rawValue == "2026-10-16T17:00:00.123456Z")
        #expect(metadata.locked)
        #expect(metadata.invitable == .value(false))
        #expect(metadata.createTimestamp == .null)
        #expect(member.id == .value(ChannelID(rawValue: UInt64.max)))
        #expect(member.userID == .value(UserID(rawValue: UInt64.max)))
        #expect(member.joinTimestamp.rawValue == "2026-10-16T17:00:00.123456Z")
        #expect(member.flags == UInt64.max)
        #expect(message.id.rawValue == UInt64.max)
        #expect(message.content == "secret text")
        #expect(channel == (try Channel(data: ChannelResponseFixture.channelData())))
    }

    /// Checks typed values on related partial projections and ensures unmodeled family fields survive exactly.
    /// - Throws: Unexpected JSON/schema or required-fixture assertion errors fail the test; expected invalid payloads are asserted locally.
    @Test func relatedResourcesAndMembershipStates() throws {
        let recipient = try ChannelRecipient(data: ChannelResponseFixture.named("ChannelRecipient").data)
        #expect(recipient.id.rawValue == UInt64.max)
        #expect(recipient.username == .value("secret text"))
        #expect(recipient.discriminator == .value("0"))
        #expect(recipient.globalName == .null)
        #expect(recipient.avatar == .null)
        #expect(recipient.bot == .value(true))
        #expect(recipient.rawFields["collectibles"] == .object(["future": .number(try JSONNumber(rawValue: "1.00000000000000000001"))]))
        let details = try ThreadGuildMember(data: ChannelResponseFixture.named("ThreadGuildMember").data)
        #expect(details.nick == .value("secret text"))
        #expect(details.avatar == .null)
        #expect(details.roles == .value([RoleID(rawValue: UInt64.max)]))
        #expect(details.joinedAt == .value(try DiscordTimestamp(rawValue: "2026-10-16T17:00:00.123456Z")))
        #expect(details.premiumSince == .null)
        #expect(details.deaf == .value(false))
        #expect(details.mute == .value(true))
        #expect(details.flags == .value(UInt64.max))
        #expect(details.pending == .value(false))
        #expect(details.permissions == .value("184467440737095516160000"))
        #expect(details.communicationDisabledUntil == .null)
        guard case .value(let user) = details.user else { Issue.record("Missing nested user"); return }
        #expect(user.id.rawValue == UInt64.max)
        let minimal = try ThreadMember(data: Data(#"{"join_timestamp":"2026-10-16T00:00:00Z","flags":0}"#.utf8))
        #expect(minimal.id == .absent)
        #expect(minimal.userID == .absent)
        #expect(minimal.member == .absent)
        #expect(minimal.flags == 0)
        #expect(try ThreadGuildMember(data: Data("{}".utf8)).user == .absent)
        let followed = try FollowedChannel(data: ChannelResponseFixture.named("FollowedChannel").data)
        #expect(followed.channelID.rawValue == UInt64.max)
        #expect(followed.webhookID.rawValue == UInt64.max)
        #expect(followed == (try FollowedChannel(data: ChannelResponseFixture.named("FollowedChannel").data)))
    }

    /// Detects only the explicit obfuscation bit, including missing metadata and placeholder names.
    /// - Parameter flags: Omitted, zero, known-other, future-only and obfuscation combinations.
    /// - Throws: Unexpected JSON/schema or required-fixture assertion errors fail the test; expected invalid payloads are asserted locally.
    @Test(arguments: [nil, UInt64(0), UInt64(2), UInt64(1) << 63, UInt64(1) << 17, UInt64.max])
    func explicitObfuscationState(flags: UInt64?) throws {
        var fields: [String: JSONValue] = ["id": .string("5"), "type": .number(try JSONNumber(rawValue: "0"))]
        if let flags { fields["flags"] = .number(try JSONNumber(rawValue: String(flags))) }
        let expected = flags.map { $0 & (1 << 17) != 0 } ?? false
        for name in [JSONValue.null, .string(""), .string("hidden"), .string("secret text")] {
            fields["name"] = name
            let channel = try Channel(data: JSONValue.object(fields).serialized())
            #expect(channel.isObfuscated == expected)
            #expect(channel.position == .absent)
            #expect(channel.parentID == .absent)
        }
        fields.removeValue(forKey: "name")
        #expect(try Channel(data: JSONValue.object(fields).serialized()).isObfuscated == expected)
    }

    /// Distinguishes nullable Channel fields from omitted fields without defaulting server values.
    /// - Throws: Unexpected JSON/schema or required-fixture assertion errors fail the test; expected invalid payloads are asserted locally.
    @Test func optionalAndNullableTypedStates() throws {
        let absent = try Channel(data: Data(#"{"id":"5","type":999}"#.utf8))
        #expect(absent.type.rawValue == 999)
        #expect(absent.type.knownValue == nil)
        #expect(absent.name == .absent)
        #expect(absent.applicationID == .absent)
        #expect(absent.parentID == .absent)
        #expect(absent.defaultSortOrder == .absent)
        #expect(absent.defaultReactionEmoji == .absent)
        let null = try Channel(data: Data(#"{"id":"5","type":999,"name":null,"topic":null,"last_message_id":null,"icon":null,"application_id":null,"parent_id":null,"last_pin_timestamp":null,"rtc_region":null,"default_sort_order":null,"default_reaction_emoji":null}"#.utf8))
        #expect(null.name == .null)
        #expect(null.topic == .null)
        #expect(null.lastMessageID == .null)
        #expect(null.icon == .null)
        #expect(null.applicationID == .null)
        #expect(null.parentID == .null)
        #expect(null.lastPinTimestamp == .null)
        #expect(null.rtcRegion == .null)
        #expect(null.defaultSortOrder == .null)
        #expect(null.defaultReactionEmoji == .null)
    }

    /// Enforces exactly-one default reaction and at-most-one forum-tag emoji without converting null to omission.
    /// - Throws: Unexpected JSON/schema or required-fixture assertion errors fail the test; expected invalid payloads are asserted locally.
    @Test func emojiAlternativesAndFutureMetadata() throws {
        let unicode = try DefaultReaction(data: Data(#"{"emoji_id":null,"emoji_name":"😀"}"#.utf8))
        #expect(unicode.emojiID == .null)
        #expect(unicode.emojiName == .value("😀"))
        for body in [#"{"emoji_id":null,"emoji_name":null}"#, #"{"emoji_id":"5","emoji_name":"😀"}"#] {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try DefaultReaction(data: Data(body.utf8)) }
        }
        for (id, name) in [("null", "null"), ("\"5\"", "null"), ("null", "\"😀\"")] {
            let body = "{\"id\":\"5\",\"name\":\"\",\"moderated\":false,\"emoji_id\":\(id),\"emoji_name\":\(name)}"
            #expect(try ForumTag(data: Data(body.utf8)).name.isEmpty)
        }
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try ForumTag(data: Data(#"{"id":"5","name":"tag","moderated":false,"emoji_id":"5","emoji_name":"😀"}"#.utf8))
        }
        let future = try ThreadMetadata(data: Data(#"{"archived":false,"auto_archive_duration":99999,"archive_timestamp":"2026-10-16T00:00:00Z","locked":false,"create_timestamp":"2026-10-15T00:00:00Z"}"#.utf8))
        #expect(future.autoArchiveDuration == 99999)
        #expect(future.invitable == .absent)
        #expect(future.createTimestamp == .value(try DiscordTimestamp(rawValue: "2026-10-15T00:00:00Z")))
    }

    /// Retains page order, incomplete membership and explicit continuation state, including empty pages with has_more.
    /// - Throws: Unexpected JSON/schema or required-fixture assertion errors fail the test; expected invalid payloads are asserted locally.
    @Test func archivedAndActiveEnvelopes() throws {
        let archive = try ArchivedThreads(data: ChannelResponseFixture.named("ArchivedThreads").data)
        #expect(archive.threads.map(\.id.rawValue) == [9, 3])
        #expect(archive.members.count == 1)
        #expect(archive.members.first?.id == .value(ChannelID(rawValue: 3)))
        #expect(archive.hasMore)
        let empty = try ArchivedThreads(data: Data(#"{"threads":[],"members":[],"has_more":true}"#.utf8))
        #expect(empty.threads.isEmpty)
        #expect(empty.members.isEmpty)
        #expect(empty.hasMore)
        let end = try ArchivedThreads(data: Data(#"{"threads":[],"members":[],"has_more":false}"#.utf8))
        #expect(!end.hasMore)
        let active = try ActiveThreads(data: Data(#"{"threads":[],"members":[]}"#.utf8))
        #expect(active.threads.isEmpty)
        #expect(active.members.isEmpty)
        #expect(active.hasMore == .absent)
        #expect(try ActiveThreads(data: Data(#"{"threads":[],"members":[],"has_more":false}"#.utf8)).hasMore == .value(false))
        #expect(try ActiveThreads(data: Data(#"{"threads":[],"members":[],"has_more":true}"#.utf8)).hasMore == .value(true))
    }

    /// Rejects mistyped objects anywhere within typed arrays instead of silently discarding malformed entries.
    /// - Parameter key: Channel wire key whose values are projected recursively.
    /// - Throws: Unexpected JSON/schema or required-fixture assertion errors fail the test; expected invalid payloads are asserted locally.
    @Test(arguments: ["permission_overwrites", "recipients", "available_tags"])
    func malformedChannelArrayElements(key: String) throws {
        for bad in [JSONValue.null, .bool(false), .array([]), .object([:])] {
            var fields = try ChannelResponseFixture.named("Channel").fields()
            fields[key] = .array([bad])
            #expect(throws: DiscordError.transport(.invalidResponse)) { try Channel(data: JSONValue.object(fields).serialized()) }
        }
    }

    /// Validates exact numeric lexemes, native ranges, decimal snowflakes and timestamps on all relevant scalar paths.
    /// - Parameter patch: A deliberately invalid replacement in an otherwise valid Channel response.
    /// - Throws: Unexpected JSON/schema or required-fixture assertion errors fail the test; expected invalid payloads are asserted locally.
    @Test(arguments: [#""id":1"#, #""id":"18446744073709551616""#, #""type":1.00000000000000000001"#,
                      #""type":1e0"#, #""flags":-1"#, #""flags":18446744073709551616"#,
                      #""position":1.5"#, #""position":9223372036854775808"#, #""video_quality_mode":1e0"#,
                      #""default_sort_order":0.0"#, #""default_forum_layout":1.2"#,
                      #""application_id":"-1""#, #""applied_tags":["18446744073709551616"]"#,
                      #""last_pin_timestamp":"2026-02-30T00:00:00Z""#, #""thread_metadata":[]"#, #""message":{}"#])
    func malformedChannelScalars(patch: String) throws {
        var fields = try ChannelResponseFixture.named("Channel").fields()
        guard case .object(let replacement) = try JSONValue.parse("{" + patch + "}") else { return }
        fields.merge(replacement) { _, updated in updated }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try Channel(data: JSONValue.object(fields).serialized()) }
    }

    /// Rejects invalid permission syntax in Channel, overwrite and related guild-member projections while retaining wide digits.
    /// - Parameter value: Invalid permission decimal syntax, including non-ASCII and whitespace edge cases.
    /// - Throws: Unexpected JSON/schema or required-fixture assertion errors fail the test; expected invalid payloads are asserted locally.
    @Test(arguments: ["", " ", "-1", "+1", "1e3", "1.0", "１２", "123\n", "0xFF"])
    func malformedPermissionBits(value: String) throws {
        for (fixtureName, key) in [("Channel", "permissions"), ("Channel", "app_permissions"),
                                   ("ChannelOverwrite", "allow"), ("ChannelOverwrite", "deny"),
                                   ("ThreadGuildMember", "permissions")] {
            let fixture = ChannelResponseFixture.named(fixtureName)
            var fields = try fixture.fields()
            fields[key] = .string(value)
            #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.decode(JSONValue.object(fields).serialized()) }
        }
    }

    /// Confirms every documented enum constant and channel flag bit while retaining future raw variants and unknown bits.
    /// - Throws: Unexpected JSON/schema or required-fixture assertion errors fail the test; expected invalid payloads are asserted locally.
    @Test func documentedVariantsAndFlags() throws {
        let channelTypes: [(ChannelType, Int)] = [(.guildText, 0), (.dm, 1), (.guildVoice, 2), (.groupDM, 3),
            (.guildCategory, 4), (.guildAnnouncement, 5), (.announcementThread, 10), (.publicThread, 11),
            (.privateThread, 12), (.guildStageVoice, 13), (.guildDirectory, 14), (.guildForum, 15), (.guildMedia, 16)]
        for (value, raw) in channelTypes { #expect(value.rawValue == raw); #expect(RawValue<ChannelType>(rawValue: raw).knownValue == value) }
        #expect(ChannelVideoQualityMode.auto.rawValue == 1)
        #expect(ChannelVideoQualityMode.full.rawValue == 2)
        #expect(ChannelSortOrder.latestActivity.rawValue == 0)
        #expect(ChannelSortOrder.creationDate.rawValue == 1)
        #expect(ChannelForumLayout.notSet.rawValue == 0)
        #expect(ChannelForumLayout.listView.rawValue == 1)
        #expect(ChannelForumLayout.galleryView.rawValue == 2)
        #expect(ChannelOverwriteType.role.rawValue == 0)
        #expect(ChannelOverwriteType.member.rawValue == 1)
        #expect(RawValue<ChannelVideoQualityMode>(rawValue: 99).knownValue == nil)
        #expect(RawValue<ChannelSortOrder>(rawValue: 99).knownValue == nil)
        #expect(RawValue<ChannelForumLayout>(rawValue: 99).knownValue == nil)
        let bits: [(ChannelFlags, UInt64)] = [(.pinned, 1 << 1), (.requireTag, 1 << 4),
            (.hideMediaDownloadOptions, 1 << 15), (.channelObfuscated, 1 << 17), (.isSpoilerChannel, 1 << 21)]
        var combined = ChannelFlags(rawValue: 1 << 63)
        for (flag, bit) in bits { #expect(flag.rawValue == bit); combined.insert(flag) }
        #expect(combined.rawValue & (1 << 63) != 0)
        #expect(combined.contains(.channelObfuscated))
        #expect(ChannelFlags(rawValue: 0).isEmpty)
        let overwrite = try ChannelOverwrite(data: Data(#"{"id":"5","type":99,"allow":"0","deny":"184467440737095516160000"}"#.utf8))
        #expect(overwrite.type.rawValue == 99)
        #expect(overwrite.type.knownValue == nil)
    }

    /// Retains exact future numeric lexemes in typed nested values, including recursively modeled forum messages.
    /// - Throws: Unexpected JSON/schema or required-fixture assertion errors fail the test; expected invalid payloads are asserted locally.
    @Test func nestedUnknownDataAndBounds() throws {
        var fields = try ChannelResponseFixture.named("Channel").fields()
        let secret = JSONValue.number(try JSONNumber(rawValue: "-123.00000000000000000000001e999"))
        for key in ["thread_metadata", "member", "default_reaction_emoji", "message"] {
            guard case .object(var nested) = fields[key] else { Issue.record("Missing nested fixture"); return }
            nested["future_secret"] = secret
            fields[key] = .object(nested)
        }
        let channel = try Channel(data: JSONValue.object(fields).serialized())
        guard case .value(let metadata) = channel.threadMetadata,
              case .value(let member) = channel.member,
              case .value(let reaction) = channel.defaultReactionEmoji,
              case .value(let message) = channel.message
        else { Issue.record("Missing typed nested value"); return }
        #expect(metadata.rawFields["future_secret"] == secret)
        #expect(member.rawFields["future_secret"] == secret)
        #expect(reaction.rawFields["future_secret"] == secret)
        #expect(message.rawFields["future_secret"] == secret)
        #expect(!String(reflecting: channel).contains("123"))
        let body = try JSONValue.object(fields).serialized()
        #expect(throws: JSONValueError.maximumDepthExceeded) {
            try Channel(data: body, limits: JSONLimits(maximumDepth: 2))
        }
        for fixtureName in ["ArchivedThreads", "ActiveThreads"] {
            let fixture = ChannelResponseFixture.named(fixtureName)
            for key in ["threads", "members"] {
                for bad in [JSONValue.null, .bool(false), .array([]), .object([:])] {
                    var page = try fixture.fields()
                    page[key] = .array([bad])
                    #expect(throws: DiscordError.transport(.invalidResponse)) {
                        try fixture.decode(JSONValue.object(page).serialized())
                    }
                }
            }
        }
    }

    /// Rejects malformed nested scalar values before returning any partial response projection.
    /// - Parameter pair: Fixture type and invalid field replacement encoded as a trusted local fragment.
    /// - Throws: Unexpected JSON/schema or required-fixture assertion errors fail the test; expected invalid payloads are asserted locally.
    @Test(arguments: [
        ["ThreadMetadata", #""auto_archive_duration":1e0"#],
        ["ThreadMetadata", #""archive_timestamp":"2026-02-30T00:00:00Z""#],
        ["ThreadMetadata", #""create_timestamp":"invalid""#],
        ["ThreadMember", #""flags":-1"#],
        ["ThreadMember", #""flags":1.0000000000000000001"#],
        ["ThreadMember", #""join_timestamp":"invalid""#],
        ["ThreadMember", #""user_id":5"#],
        ["ThreadMember", #""member":{"roles":[5]}"#],
        ["ForumTag", #""emoji_id":"18446744073709551616""#],
        ["DefaultReaction", #""emoji_id":5"#],
        ["ChannelOverwrite", #""type":0.00000000000000000001"#],
        ["ChannelOverwrite", #""id":"-1""#],
        ["FollowedChannel", #""webhook_id":"18446744073709551616""#],
        ["ChannelRecipient", #""id":"18446744073709551616""#],
    ])
    func malformedNestedScalars(pair: [String]) throws {
        let fixture = ChannelResponseFixture.named(pair[0])
        var fields = try fixture.fields()
        guard case .object(let replacement) = try JSONValue.parse("{" + pair[1] + "}") else { return }
        fields.merge(replacement) { _, updated in updated }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.decode(JSONValue.object(fields).serialized()) }
    }
}

/// Independent fixture metadata; exclamation marks denote required keys and question marks denote nullable values.
private struct ChannelResponseFixture: Sendable {
    let name: String
    let data: Data
    let contracts: [ChannelFieldContract]

    /// Builds an immutable local fixture without performing schema or payload decoding.
    /// - Parameters:
    ///   - name: Exact response type name selected by decode.
    ///   - json: Complete trusted fixture JSON, encoded as UTF-8.
    ///   - fields: Space-separated official contracts; suffix ! means required, ? means nullable, [] means array.
    init(_ name: String, _ json: String, _ fields: String) {
        self.name = name
        data = Data(json.utf8)
        contracts = fields.split(separator: " ").map { token in
            ChannelFieldContract(name: token.replacingOccurrences(of: "!", with: "").replacingOccurrences(of: "?", with: "").replacingOccurrences(of: "[]", with: ""),
                required: token.contains("!"), nullable: token.contains("?"), array: token.contains("[]"))
        }
    }

    /// Looks up a trusted fixture by exact type name; a missing entry is a programmer failure.
    /// - Parameter name: Fixture type name already listed in cases.
    /// - Returns: The immutable fixture with matching metadata.
    static func named(_ name: String) -> Self { cases.first { $0.name == name }! }

    /// Returns the complete Channel fixture bytes for concrete typed assertions.
    /// - Returns: Bounded, trusted local fixture bytes; no network operation occurs.
    static func channelData() -> Data { named("Channel").data }

    /// Decodes the trusted fixture root into exact mutable test fields.
    /// - Returns: All object keys, including deliberately unmodeled family fields.
    /// - Throws: A parser error for invalid fixture syntax; fixtures always use object roots.
    func fields() throws -> [String: JSONValue] {
        guard case .object(let fields) = try JSONValue.parse(data) else { return [:] }
        return fields
    }

    /// Invokes each public data initializer, exercising its internal subtree initializer transitively.
    /// - Parameters:
    ///   - data: Complete candidate response JSON, including mutations for negative tests.
    ///   - limits: Whole-document limits; defaults to production bounds.
    /// - Returns: The redacted response protocol projection for contract and raw-data assertions.
    /// - Throws: Public syntax, bounds or invalid-response errors from the selected model.
    func decode(_ data: Data, limits: JSONLimits = .default) throws -> any MessageResponseValue {
        switch name {
        case "Channel": try Channel(data: data, limits: limits)
        case "ChannelOverwrite": try ChannelOverwrite(data: data, limits: limits)
        case "ThreadMetadata": try ThreadMetadata(data: data, limits: limits)
        case "ChannelRecipient": try ChannelRecipient(data: data, limits: limits)
        case "ThreadGuildMember": try ThreadGuildMember(data: data, limits: limits)
        case "ThreadMember": try ThreadMember(data: data, limits: limits)
        case "DefaultReaction": try DefaultReaction(data: data, limits: limits)
        case "ForumTag": try ForumTag(data: data, limits: limits)
        case "FollowedChannel": try FollowedChannel(data: data, limits: limits)
        case "ArchivedThreads": try ArchivedThreads(data: data, limits: limits)
        default: try ActiveThreads(data: data, limits: limits)
        }
    }

    static let cases: [Self] = [
        Self("Channel", channelJSON,
            "id! type! guild_id position permission_overwrites[] name? topic? nsfw last_message_id? bitrate user_limit rate_limit_per_user recipients[] icon? owner_id application_id? managed parent_id? last_pin_timestamp? rtc_region? video_quality_mode message_count member_count thread_metadata member default_auto_archive_duration permissions app_permissions flags total_message_sent available_tags[] applied_tags[] default_reaction_emoji? default_thread_rate_limit_per_user default_sort_order? default_forum_layout message"),
        Self("ChannelOverwrite", #"{"id":"18446744073709551615","type":1,"allow":"184467440737095516160000","deny":"0000"}"#, "id! type! allow! deny!"),
        Self("ThreadMetadata", #"{"archived":true,"auto_archive_duration":1440,"archive_timestamp":"2026-10-16T17:00:00.123456Z","locked":true,"invitable":false,"create_timestamp":null}"#, "archived! auto_archive_duration! archive_timestamp! locked! invitable create_timestamp?"),
        Self("ChannelRecipient", #"{"id":"18446744073709551615","username":"secret text","discriminator":"0","global_name":null,"avatar":null,"bot":true,"collectibles":{"future":1.00000000000000000001}}"#, "id! username discriminator global_name? avatar? bot"),
        Self("ThreadGuildMember", #"{"user":{"id":"18446744073709551615"},"nick":"secret text","avatar":null,"roles":["18446744073709551615"],"joined_at":"2026-10-16T17:00:00.123456Z","premium_since":null,"deaf":false,"mute":true,"flags":18446744073709551615,"pending":false,"permissions":"184467440737095516160000","communication_disabled_until":null}"#, "user nick? avatar? roles[] joined_at premium_since? deaf mute flags pending permissions communication_disabled_until?"),
        Self("ThreadMember", #"{"id":"18446744073709551615","user_id":"18446744073709551615","join_timestamp":"2026-10-16T17:00:00.123456Z","flags":18446744073709551615,"member":{}}"#, "id user_id join_timestamp! flags! member"),
        Self("DefaultReaction", #"{"emoji_id":"18446744073709551615","emoji_name":null}"#, "emoji_id!? emoji_name!?"),
        Self("ForumTag", #"{"id":"18446744073709551615","name":"secret text","moderated":true,"emoji_id":null,"emoji_name":null}"#, "id! name! moderated! emoji_id!? emoji_name!?"),
        Self("FollowedChannel", #"{"channel_id":"18446744073709551615","webhook_id":"18446744073709551615"}"#, "channel_id! webhook_id!"),
        Self("ArchivedThreads", #"{"threads":[{"id":"9","type":11},{"id":"3","type":12}],"members":[{"id":"3","join_timestamp":"2026-10-16T00:00:00Z","flags":0}],"has_more":true}"#, "threads![] members![] has_more!"),
        Self("ActiveThreads", #"{"threads":[],"members":[],"has_more":false}"#, "threads![] members![] has_more"),
    ]

    static let channelJSON = #"""
    {"id":"18446744073709551615","type":15,"guild_id":"18446744073709551615","position":2,
     "permission_overwrites":[{"id":"18446744073709551615","type":1,"allow":"184467440737095516160000","deny":"0000"}],
     "name":"secret text","topic":"secret text","nsfw":false,"last_message_id":"18446744073709551615",
     "bitrate":64000,"user_limit":0,"rate_limit_per_user":21600,"recipients":[{"id":"18446744073709551615","username":"secret text"}],
     "icon":"secret text","owner_id":"18446744073709551615","application_id":"18446744073709551615","managed":true,
     "parent_id":"18446744073709551615","last_pin_timestamp":"2026-10-16T17:00:00.123456Z","rtc_region":"automatic-test",
     "video_quality_mode":99,"message_count":1000,"member_count":50,
     "thread_metadata":{"archived":true,"auto_archive_duration":1440,"archive_timestamp":"2026-10-16T17:00:00.123456Z","locked":true,"invitable":false,"create_timestamp":null},
     "member":{"id":"18446744073709551615","user_id":"18446744073709551615","join_timestamp":"2026-10-16T17:00:00.123456Z","flags":18446744073709551615,"member":{}},
     "default_auto_archive_duration":10080,"permissions":"000184467440737095516160000","app_permissions":"184467440737095516160001",
     "flags":18446744073709551615,"total_message_sent":2000,
     "available_tags":[{"id":"18446744073709551615","name":"secret text","moderated":true,"emoji_id":null,"emoji_name":null}],
     "applied_tags":["18446744073709551615","1"],"default_reaction_emoji":{"emoji_id":"18446744073709551615","emoji_name":null},
     "default_thread_rate_limit_per_user":0,"default_sort_order":99,"default_forum_layout":99,
     "message":{"id":"18446744073709551615","channel_id":"18446744073709551615","author":{"id":"5","username":"user","avatar":null},
                "content":"secret text","timestamp":"2026-10-16T00:00:00Z","edited_timestamp":null,"tts":false,"mention_everyone":false,
                "mentions":[],"mention_roles":[],"attachments":[],"embeds":[],"pinned":false,"type":0}}
    """#
}

/// One independently recorded official wire contract; array controls the incompatible-type mutation.
private struct ChannelFieldContract: Sendable {
    let name: String
    let required: Bool
    let nullable: Bool
    let array: Bool
}
