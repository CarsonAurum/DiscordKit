// File: Tests/DiscordModelsTests/MessageTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Runs schema matrices against every message-owned projection with independent complete JSON fixtures.
/// All inputs are local, bounded and credential-free. Tests assert wire presence, nullability,
/// malformed types, exact future numbers, redaction and whole-document parser bounds.
@Suite struct MessageTests {
    /// Decodes every field of every projection, retains unknown numbers and checks diagnostic concealment.
    /// - Parameter fixture: A complete independently encoded example and its exact field-contract matrix.
    @Test(arguments: MessageFixture.cases)
    func completeProjectionAndFieldContracts(fixture: MessageFixture) throws {
        var fields = try fixture.fields()
        fields["future_secret"] = .number(try JSONNumber(rawValue: "1.23000000000000000001e1000"))
        fields["future_container"] = .array([.object(["deep": .array([])])])
        let value = try fixture.decode(JSONValue.object(fields).serialized())
        #expect(value.rawFields == fields)
        #expect(value.jsonValue() == .object(fields))
        #expect(!value.description.contains("secret text"))
        #expect(!value.debugDescription.contains("secret text"))
        #expect(value.customMirror.children.count == 1)
        #expect(value.description.hasSuffix("(redacted)"))
        for contract in fixture.contracts {
            var altered = fields
            altered.removeValue(forKey: contract.wireName)
            if contract.required {
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try fixture.decode(JSONValue.object(altered).serialized())
                }
            } else {
                let absent = try fixture.decode(JSONValue.object(altered).serialized())
                #expect(absent.rawFields[contract.wireName] == nil)
            }
            altered = fields
            altered[contract.wireName] = .null
            if contract.nullable {
                #expect(try fixture.decode(JSONValue.object(altered).serialized()).rawFields[contract.wireName] == .null)
            } else {
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try fixture.decode(JSONValue.object(altered).serialized())
                }
            }
            altered[contract.wireName] = contract.array ? .bool(false) : .array([])
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try fixture.decode(JSONValue.object(altered).serialized())
            }
        }
        #expect(throws: JSONValueError.maximumBytesExceeded) {
            try fixture.decodeBounded(JSONValue.object(fields).serialized(), JSONLimits(maximumBytes: 1))
        }
        #expect(throws: JSONValueError.maximumDepthExceeded) {
            try fixture.decodeBounded(JSONValue.object(fields).serialized(), JSONLimits(maximumDepth: 1))
        }
        #expect(throws: JSONValueError.maximumNodesExceeded) {
            try fixture.decodeBounded(JSONValue.object(fields).serialized(), JSONLimits(maximumNodes: 1))
        }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.decode(Data("[]".utf8)) }
        #expect(throws: JSONValueError.self) { try fixture.decode(Data("{".utf8)) }
    }

    /// Asserts concrete typed values, webhook-compatible author state and all referenced-message presence alternatives.
    @Test func messageValuesAndReferenceStates() throws {
        var fields = try MessageFixture.named("Message").fields()
        fields["id"] = .string("18446744073709551615")
        fields["author"] = .object(["id": .string("5"), "username": .string("webhook"), "avatar": .null])
        fields["webhook_id"] = .string("5")
        fields["type"] = .number(try JSONNumber(rawValue: "999"))
        fields["nonce"] = .number(try JSONNumber(rawValue: "123456789012345678901234567890"))
        fields.removeValue(forKey: "referenced_message")
        let message = try Message(data: JSONValue.object(fields).serialized())
        #expect(message.id.rawValue == UInt64.max)
        #expect(message.author.discriminator == .absent)
        #expect(message.author.globalName == .absent)
        #expect(message.webhookID == .value(WebhookID(rawValue: 5)))
        #expect(message.type.rawValue == 999)
        #expect(message.type.knownValue == nil)
        #expect(message.referencedMessage == .absent)
        #expect(message.nonce == .value(.integer(try JSONNumber(rawValue: "123456789012345678901234567890"))))
        fields["referenced_message"] = .null
        #expect(try Message(data: JSONValue.object(fields).serialized()).referencedMessage == .null)
        var nested = fields
        nested.removeValue(forKey: "referenced_message")
        nested["content"] = .string("referenced")
        fields["referenced_message"] = .object(nested)
        let populated = try Message(data: JSONValue.object(fields).serialized())
        guard case .value(let reference) = populated.referencedMessage else { Issue.record("Missing reference"); return }
        #expect(reference.content == "referenced")
        #expect(reference.referencedMessage == .absent)
        #expect(populated == (try Message(data: JSONValue.object(fields).serialized())))
    }

    /// Asserts nested attachment, embed, reaction, activity and snapshot values through typed accessors.
    @Test func nestedTypedValues() throws {
        let fixture = try MessageFixture.named("Message").fields()
        let message = try Message(data: JSONValue.object(fixture).serialized())
        #expect(message.channelID.rawValue == UInt64.max)
        #expect(message.content == "secret text")
        #expect(message.timestamp.rawValue == "2026-10-16T17:00:00.123456Z")
        #expect(message.editedTimestamp == .null)
        #expect(message.tts)
        #expect(message.mentionEveryone)
        #expect(message.mentions.first?.id.rawValue == UInt64.max)
        #expect(message.mentionRoles.first?.rawValue == UInt64.max)
        #expect(message.pinned)
        let attachment = try #require(message.attachments.first)
        #expect(attachment.id.rawValue == UInt64.max)
        #expect(attachment.filename == "secret text")
        #expect(attachment.size == 1)
        #expect(attachment.height == .value(1))
        #expect(attachment.width == .value(1))
        #expect(attachment.durationSeconds == .value(0.25))
        #expect(attachment.clipParticipants != .absent)
        let embed = try #require(message.embeds.first)
        #expect(embed.type == .value(RawValue(rawValue: "future-kind")))
        #expect(embed.embedDescription == .value("secret text"))
        #expect(embed.title == .value("secret text"))
        #expect(embed.flags == .value(1))
        guard case .value(let footer) = embed.footer, case .value(let image) = embed.image,
              case .value(let video) = embed.video, case .value(let provider) = embed.provider,
              case .value(let author) = embed.author, case .value(let rows) = embed.fields,
              case .value(let reactions) = message.reactions, case .value(let activity) = message.activity,
              case .value(let channels) = message.mentionChannels, case .value(let snapshots) = message.messageSnapshots,
              case .value(let stickers) = message.stickerItems, case .value(let subscription) = message.roleSubscriptionData,
              case .value(let call) = message.call, case .value(let theme) = message.sharedClientTheme
        else { Issue.record("Missing modeled nested response value"); return }
        #expect(footer.text == "secret text")
        #expect(footer.iconURL == .value("secret text"))
        #expect(image.url == "secret text")
        #expect(image.placeholderVersion == .value(1))
        #expect(video.url == .value("secret text"))
        #expect(provider.name == .value("secret text"))
        #expect(author.name == "secret text")
        #expect(rows.first?.name == "secret text")
        #expect(rows.first?.value == "secret text")
        #expect(rows.first?.inline == .value(true))
        #expect(reactions.first?.count == 1)
        #expect(reactions.first?.countDetails.burst == 1)
        #expect(reactions.first?.countDetails.normal == 1)
        #expect(reactions.first?.me == true)
        #expect(reactions.first?.meBurst == true)
        #expect(reactions.first?.emoji.name == .value("😀"))
        #expect(reactions.first?.burstColors == ["secret text"])
        #expect(activity.type.rawValue == 999)
        #expect(activity.partyID == .value("secret text"))
        #expect(channels.first?.guildID.rawValue == UInt64.max)
        #expect(channels.first?.name == "secret text")
        #expect(snapshots.first?.message.content == "secret text")
        #expect(snapshots.first?.message.mentions.first?.username == "secret text")
        #expect(stickers.first?.id.rawValue == UInt64.max)
        #expect(stickers.first?.formatType.rawValue == 999)
        #expect(subscription.roleSubscriptionListingID.rawValue == UInt64.max)
        #expect(subscription.totalMonthsSubscribed == 1)
        #expect(subscription.isRenewal)
        #expect(call.participants.first?.rawValue == UInt64.max)
        #expect(call.endedTimestamp != .absent)
        #expect(theme.colors == ["secret text"])
        #expect(theme.gradientAngle == 1)
        #expect(theme.baseMix == 1)
        #expect(theme.baseTheme == .value(RawValue(rawValue: 999)))
    }

    /// Exact integer fields never accept fractional/exponent coercions or overflow; nonce tokens have explicit rules.
    /// - Parameter patch: A replacement Message field with an invalid typed wire representation.
    @Test(arguments: ["\"id\":1", "\"id\":\"18446744073709551616\"", "\"type\":1.00000000000000001",
                      "\"type\":1e0", "\"flags\":-1", "\"nonce\":1e3", "\"nonce\":1.5", "\"nonce\":null",
                      "\"timestamp\":\"2026-02-30T00:00:00Z\"", "\"referenced_message\":[]"])
    func malformedMessageScalars(patch: String) throws {
        var fields = try MessageFixture.named("Message").fields()
        guard case .object(let replacement) = try JSONValue.parse("{" + patch + "}") else { return }
        fields.merge(replacement) { _, updated in updated }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try Message(data: JSONValue.object(fields).serialized()) }
    }

    /// Embed builders preserve typed nested objects and count Unicode scalars across every aggregate text field.
    @Test func embedConstructionAndAggregateCount() throws {
        let footer = try MessageEmbedFooter(data: Data("{\"text\":\"footer\",\"icon_url\":\"attachment://icon.png\"}".utf8))
        let author = try MessageEmbedAuthor(data: Data("{\"name\":\"author\",\"url\":\"https://example.test\"}".utf8))
        let image = try MessageEmbedImage(data: Data("{\"url\":\"attachment://image.png\"}".utf8))
        let row = try MessageEmbedField(data: Data("{\"name\":\"name\",\"value\":\"value\",\"inline\":false}".utf8))
        let embed = try MessageEmbed(title: "title", description: "👩‍💻", url: "https://example.test",
            timestamp: "2026-10-16T17:00:00Z", color: 0xFFFFFF, footer: footer, image: image,
            thumbnail: image, author: author, fields: [row])
        #expect(embed.contentCharacterCount == 5 + 3 + 6 + 6 + 4 + 5)
        #expect(embed.title == .value("title"))
        #expect(embed.footer == .value(footer))
        #expect(embed.fields == .value([row]))
        #expect(embed.color == .value(0xFFFFFF))
        #expect(try MessageEmbed().rawFields.isEmpty)
        #expect(try MessageEmbed(title: "x").contentCharacterCount == 1)
        #expect(throws: DiscordError.transport(.invalidResponse)) { try MessageEmbed(timestamp: "invalid") }
    }

    /// Names every documented response bit and retains a future bit when combining known flags.
    /// The response wire property remains UInt64; wrapping it must neither discard nor authorize unknown state.
    @Test func completeMessageFlags() throws {
        let documented: [(MessageFlags, UInt64)] = [
            (.crossposted, 1 << 0), (.isCrosspost, 1 << 1), (.suppressEmbeds, 1 << 2),
            (.sourceMessageDeleted, 1 << 3), (.urgent, 1 << 4), (.hasThread, 1 << 5),
            (.ephemeral, 1 << 6), (.loading, 1 << 7), (.failedToMentionSomeRolesInThread, 1 << 8),
            (.suppressNotifications, 1 << 12), (.isVoiceMessage, 1 << 13),
            (.hasSnapshot, 1 << 14), (.isComponentsV2, 1 << 15)
        ]
        #expect(Set(documented.map { $0.0.rawValue }).count == 13)
        for (flag, expected) in documented {
            #expect(flag.rawValue == expected)
            #expect(MessageFlags(rawValue: expected).contains(flag))
        }
        #expect(MessageFlags(rawValue: 0).isEmpty)
        let unknown: UInt64 = 1 << 63
        let combined = MessageFlags(rawValue: unknown).union([.ephemeral, .isComponentsV2])
        #expect(combined.rawValue == unknown | (1 << 6) | (1 << 15))
        #expect(combined.contains(.ephemeral))
        #expect(combined.contains(.isComponentsV2))
        #expect(!combined.contains(.crossposted))
        var fields = try MessageFixture.named("Message").fields()
        fields["flags"] = .number(try JSONNumber(rawValue: String(combined.rawValue)))
        let message = try Message(data: JSONValue.object(fields).serialized())
        guard case .value(let raw) = message.flags else { Issue.record("Missing response flags"); return }
        #expect(MessageFlags(rawValue: raw) == combined)
        #expect(MessageFlags(rawValue: UInt64.max).rawValue == UInt64.max)
        #expect(MessageEmbedFlags.isContentInventoryEntry.rawValue == 1 << 5)
        #expect(MessageEmbedMediaFlags.isAnimated.rawValue == 1 << 5)
        #expect(MessageEmbedFlags(rawValue: 0).isEmpty)
        #expect(MessageEmbedMediaFlags(rawValue: 0).isEmpty)
        #expect(MessageEmbedFlags(rawValue: unknown | (1 << 5)).contains(.isContentInventoryEntry))
        #expect(MessageEmbedMediaFlags(rawValue: unknown | (1 << 5)).contains(.isAnimated))
        #expect(MessageEmbedFlags(rawValue: unknown).rawValue == unknown)
        #expect(MessageEmbedMediaFlags(rawValue: unknown).rawValue == unknown)
        let attachmentFlags: [(MessageAttachmentFlags, UInt64)] = [
            (.isClip, 1 << 0), (.isThumbnail, 1 << 1), (.isRemix, 1 << 2),
            (.isSpoiler, 1 << 3), (.isAnimated, 1 << 5)
        ]
        #expect(MessageAttachmentFlags(rawValue: 0).isEmpty)
        for (flag, expected) in attachmentFlags {
            #expect(flag.rawValue == expected)
            #expect(MessageAttachmentFlags(rawValue: unknown | expected).contains(flag))
        }
        #expect(MessageAttachmentFlags(rawValue: unknown).rawValue == unknown)

    }

    /// Checks every documented enum variant against its exact wire representation and preserves future values.
    /// Tables name every public case explicitly, providing declaration-level parity evidence independent of parsing fixtures.
    @Test func documentedMessageEnumVariants() {
        let messageTypeValues: [(MessageType, Int)] = [
            (.`default`, 0),
            (.recipientAdd, 1),
            (.recipientRemove, 2),
            (.call, 3),
            (.channelNameChange, 4),
            (.channelIconChange, 5),
            (.channelPinnedMessage, 6),
            (.userJoin, 7),
            (.guildBoost, 8),
            (.guildBoostTier1, 9),
            (.guildBoostTier2, 10),
            (.guildBoostTier3, 11),
            (.channelFollowAdd, 12),
            (.guildDiscoveryDisqualified, 14),
            (.guildDiscoveryRequalified, 15),
            (.guildDiscoveryGracePeriodInitialWarning, 16),
            (.guildDiscoveryGracePeriodFinalWarning, 17),
            (.threadCreated, 18),
            (.reply, 19),
            (.chatInputCommand, 20),
            (.threadStarterMessage, 21),
            (.guildInviteReminder, 22),
            (.contextMenuCommand, 23),
            (.autoModerationAction, 24),
            (.roleSubscriptionPurchase, 25),
            (.interactionPremiumUpsell, 26),
            (.stageStart, 27),
            (.stageEnd, 28),
            (.stageSpeaker, 29),
            (.stageTopic, 31),
            (.guildApplicationPremiumSubscription, 32),
            (.guildIncidentAlertModeEnabled, 36),
            (.guildIncidentAlertModeDisabled, 37),
            (.guildIncidentReportRaid, 38),
            (.guildIncidentReportFalseAlarm, 39),
            (.purchaseNotification, 44),
            (.pollResult, 46),
        ]
        #expect(messageTypeValues.count == 37)
        for (variant, expected) in messageTypeValues {
            #expect(variant.rawValue == expected)
            #expect(MessageType(rawValue: expected) == variant)
            #expect(RawValue(variant).knownValue == variant)
        }
        #expect(RawValue<MessageType>(rawValue: 999).knownValue == nil)
        let messageActivityTypeValues: [(MessageActivityType, Int)] = [
            (.join, 1),
            (.spectate, 2),
            (.listen, 3),
            (.joinRequest, 5),
            (.streamRequest, 6),
        ]
        #expect(messageActivityTypeValues.count == 5)
        for (variant, expected) in messageActivityTypeValues {
            #expect(variant.rawValue == expected)
            #expect(MessageActivityType(rawValue: expected) == variant)
            #expect(RawValue(variant).knownValue == variant)
        }
        #expect(RawValue<MessageActivityType>(rawValue: 999).knownValue == nil)
        let messageReferenceTypeValues: [(MessageReferenceType, Int)] = [
            (.`default`, 0),
            (.forward, 1),
        ]
        #expect(messageReferenceTypeValues.count == 2)
        for (variant, expected) in messageReferenceTypeValues {
            #expect(variant.rawValue == expected)
            #expect(MessageReferenceType(rawValue: expected) == variant)
            #expect(RawValue(variant).knownValue == variant)
        }
        #expect(RawValue<MessageReferenceType>(rawValue: 999).knownValue == nil)
        let messageStickerFormatTypeValues: [(MessageStickerFormatType, Int)] = [
            (.png, 1),
            (.apng, 2),
            (.lottie, 3),
            (.gif, 4),
        ]
        #expect(messageStickerFormatTypeValues.count == 4)
        for (variant, expected) in messageStickerFormatTypeValues {
            #expect(variant.rawValue == expected)
            #expect(MessageStickerFormatType(rawValue: expected) == variant)
            #expect(RawValue(variant).knownValue == variant)
        }
        #expect(RawValue<MessageStickerFormatType>(rawValue: 999).knownValue == nil)
        let messageBaseThemeValues: [(MessageBaseTheme, Int)] = [
            (.unset, 0),
            (.dark, 1),
            (.light, 2),
            (.darker, 3),
            (.midnight, 4),
        ]
        #expect(messageBaseThemeValues.count == 5)
        for (variant, expected) in messageBaseThemeValues {
            #expect(variant.rawValue == expected)
            #expect(MessageBaseTheme(rawValue: expected) == variant)
            #expect(RawValue(variant).knownValue == variant)
        }
        #expect(RawValue<MessageBaseTheme>(rawValue: 999).knownValue == nil)
        let messageEmbedTypeValues: [(MessageEmbedType, String)] = [
            (.rich, "rich"),
            (.image, "image"),
            (.video, "video"),
            (.gifv, "gifv"),
            (.article, "article"),
            (.link, "link"),
            (.poll_result, "poll_result"),
            (.components, "components"),
        ]
        #expect(messageEmbedTypeValues.count == 8)
        for (variant, expected) in messageEmbedTypeValues {
            #expect(variant.rawValue == expected)
            #expect(MessageEmbedType(rawValue: expected) == variant)
            #expect(RawValue(variant).knownValue == variant)
        }
        #expect(RawValue<MessageEmbedType>(rawValue: "future-kind").knownValue == nil)
    }

    /// Reference constructors preserve selected forwarding semantics and omitted defaults in exact JSON.
    @Test func referenceConstruction() throws {
        let reference = try MessageReference(type: .forward, messageID: MessageID(rawValue: 1),
            channelID: ChannelID(rawValue: 2), guildID: GuildID(rawValue: 3), failIfNotExists: false)
        #expect(reference.type == .value(RawValue(.forward)))
        #expect(reference.messageID == .value(MessageID(rawValue: 1)))
        #expect(reference.channelID == .value(ChannelID(rawValue: 2)))
        #expect(reference.guildID == .value(GuildID(rawValue: 3)))
        #expect(reference.failIfNotExists == .value(false))
        let minimal = try MessageReference()
        #expect(minimal.type == .value(RawValue(.default)))
        #expect(minimal.messageID == .absent)
        #expect(minimal.failIfNotExists == .absent)
    }

    /// Search distinguishes HTTP-202-shaped indexing from real empty results and preserves nested groups.
    @Test func searchResponsesAndPins() throws {
        let indexing = try MessageSearchResponse(data: Data("{\"code\":110000,\"message\":\"secret indexing\",\"documents_indexed\":0,\"retry_after\":0.25}".utf8))
        guard case .indexing(let pending) = indexing else { Issue.record("Expected indexing"); return }
        #expect(pending.retryAfter == 0.25)
        #expect(pending.documentsIndexed == .value(0))
        #expect(!indexing.description.contains("secret"))
        #expect(indexing.customMirror.children.count == 1)
        let message = try MessageFixture.named("Message").fields()
        let completed = try MessageSearchResponse(data: JSONValue.object([
            "doing_deep_historical_index": .bool(false), "total_results": .number(try JSONNumber(rawValue: "2")),
            "messages": .array([.array([.object(message)]), .array([])])]).serialized())
        guard case .results(let result) = completed else { Issue.record("Expected results"); return }
        #expect(result.totalResults == 2)
        #expect(!result.doingDeepHistoricalIndex)
        #expect(result.messages.count == 2)
        #expect(result.messages[0].count == 1)
        #expect(result.messages[1].isEmpty)
        let pins = try MessagePins(data: Data("{\"items\":[],\"has_more\":true}".utf8))
        #expect(pins.items.isEmpty)
        #expect(pins.hasMore)
        #expect(completed == (try MessageSearchResponse(data: JSONValue.object(result.rawFields).serialized())))
        #expect(!completed.debugDescription.contains("secret"))
    }

    /// Indexing requires the known code, a finite nonnegative delay and correctly typed required fields.
    /// - Parameter patch: An invalid indexing object supplied independently of result decoding.
    @Test(arguments: ["{}", "{\"code\":110000,\"message\":\"x\",\"retry_after\":-1}",
                      "{\"code\":110000,\"message\":\"x\",\"retry_after\":1e1000}",
                      "{\"code\":110001,\"message\":\"x\",\"retry_after\":0}",
                      "{\"code\":110000,\"message\":\"x\",\"retry_after\":null}"])
    func malformedIndexing(patch: String) throws {
        #expect(throws: DiscordError.transport(.invalidResponse)) { try MessageSearchIndexing(data: Data(patch.utf8)) }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try MessageSearchResponse(data: Data(patch.utf8)) }
    }

    /// Interaction alternatives enforce their own source keys and preserve recursively triggering metadata.
    @Test func interactionAlternativesAndResolvedMaps() throws {
        var metadata = try MessageFixture.named("MessageInteractionMetadata").fields()
        metadata["type"] = .number(try JSONNumber(rawValue: "3"))
        #expect(throws: DiscordError.transport(.invalidResponse)) { try MessageInteractionMetadata(data: JSONValue.object(metadata).serialized()) }
        metadata["interacted_message_id"] = .string("2")
        let component = try MessageInteractionMetadata(data: JSONValue.object(metadata).serialized())
        #expect(component.interactedMessageID == .value(MessageID(rawValue: 2)))
        #expect(component.triggeringInteractionMetadata == .absent)
        var modal = metadata
        modal["type"] = .number(try JSONNumber(rawValue: "5"))
        #expect(throws: DiscordError.transport(.invalidResponse)) { try MessageInteractionMetadata(data: JSONValue.object(modal).serialized()) }
        modal["triggering_interaction_metadata"] = .object(metadata)
        let value = try MessageInteractionMetadata(data: JSONValue.object(modal).serialized())
        #expect(value.triggeringInteractionMetadata == .value(component))
        metadata["authorizing_integration_owners"] = .object(["0": .string("18446744073709551616")])
        #expect(throws: DiscordError.transport(.invalidResponse)) { try MessageInteractionMetadata(data: JSONValue.object(metadata).serialized()) }
        let resolved = try MessageResolvedData(data: Data("{\"users\":{\"1\":{\"id\":\"1\",\"username\":\"u\",\"avatar\":null}},\"messages\":{}}".utf8))
        guard case .value(let users) = resolved.users else { Issue.record("Expected users"); return }
        #expect(users["1"]?.username == "u")
        #expect(resolved.messages == .value([:]))
        #expect(resolved.roles == .absent)
        #expect(throws: DiscordError.transport(.invalidResponse)) { try MessageResolvedData(data: Data("{\"users\":{\"bad\":{}}}".utf8)) }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try MessageResolvedData(data: Data("{\"users\":[]}".utf8)) }
    }
}

/// One response fixture and its independently declared field presence rules; closures keep concrete decoding observable.
struct MessageFixture: Sendable, CustomStringConvertible {
    /// Reports only the model name when parameterized tests describe this fixture.
    var description: String { name }
    let name: String
    let json: String
    let contracts: [MessageFieldContract]
    let decode: @Sendable (Data) throws -> any MessageResponseValue
    let decodeBounded: @Sendable (Data, JSONLimits) throws -> any MessageResponseValue

    /// Parses the independently written fixture object for one-field mutation tests.
    /// - Returns: The complete object; nonobject fixtures indicate invalid test setup.
    /// - Throws: Bounded parser errors or safe invalid-response errors for setup mistakes.
    func fields() throws -> [String: JSONValue] {
        guard case .object(let fields) = try JSONValue.parse(json) else { throw DiscordError.transport(.invalidResponse) }
        return fields
    }

    /// Resolves a fixture by an explicit known model name without reading production source.
    /// - Parameter name: An existing fixture model name; tests call only fixed names in cases.
    /// - Returns: The matching independently declared fixture.
    /// - Throws: Safe invalid-response errors for a missing test fixture.
    static func named(_ name: String) throws -> Self {
        guard let value = cases.first(where: { $0.name == name }) else { throw DiscordError.transport(.invalidResponse) }
        return value
    }

    static let cases: [Self] = [
        MessageFixture(name: "MessageAuthor", json: #"{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}}"#,
            contracts: [MessageFieldContract(wireName: "id", required: true, nullable: false, array: false), MessageFieldContract(wireName: "username", required: true, nullable: false, array: false), MessageFieldContract(wireName: "avatar", required: true, nullable: true, array: false), MessageFieldContract(wireName: "discriminator", required: false, nullable: false, array: false), MessageFieldContract(wireName: "global_name", required: false, nullable: true, array: false), MessageFieldContract(wireName: "bot", required: false, nullable: false, array: false), MessageFieldContract(wireName: "system", required: false, nullable: false, array: false), MessageFieldContract(wireName: "mfa_enabled", required: false, nullable: false, array: false), MessageFieldContract(wireName: "banner", required: false, nullable: true, array: false), MessageFieldContract(wireName: "accent_color", required: false, nullable: true, array: false), MessageFieldContract(wireName: "locale", required: false, nullable: false, array: false), MessageFieldContract(wireName: "verified", required: false, nullable: false, array: false), MessageFieldContract(wireName: "email", required: false, nullable: true, array: false), MessageFieldContract(wireName: "flags", required: false, nullable: false, array: false), MessageFieldContract(wireName: "public_flags", required: false, nullable: false, array: false), MessageFieldContract(wireName: "premium_type", required: false, nullable: false, array: false), MessageFieldContract(wireName: "avatar_decoration_data", required: false, nullable: true, array: false), MessageFieldContract(wireName: "collectibles", required: false, nullable: true, array: false), MessageFieldContract(wireName: "primary_guild", required: false, nullable: true, array: false), MessageFieldContract(wireName: "member", required: false, nullable: false, array: false)],
            decode: { try MessageAuthor(data: $0) }, decodeBounded: { try MessageAuthor(data: $0, limits: $1) }),
        MessageFixture(name: "MessageRelatedResource", json: #"{"id":"secret text","name":"secret text","type":1}"#,
            contracts: [MessageFieldContract(wireName: "id", required: false, nullable: false, array: false), MessageFieldContract(wireName: "name", required: false, nullable: false, array: false), MessageFieldContract(wireName: "type", required: false, nullable: false, array: false)],
            decode: { try MessageRelatedResource(data: $0) }, decodeBounded: { try MessageRelatedResource(data: $0, limits: $1) }),
        MessageFixture(name: "MessageAttachment", json: #"{"id":"18446744073709551615","filename":"secret text","title":"secret text","description":"secret text","content_type":"secret text","size":1,"url":"secret text","proxy_url":"secret text","height":1,"width":1,"placeholder":"secret text","placeholder_version":1,"ephemeral":true,"duration_secs":0.25,"waveform":"secret text","flags":1,"clip_participants":[{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}}],"clip_created_at":"2026-10-16T17:00:00.123456Z","application":{"id":"secret text","name":"secret text","type":1}}"#,
            contracts: [MessageFieldContract(wireName: "id", required: true, nullable: false, array: false), MessageFieldContract(wireName: "filename", required: true, nullable: false, array: false), MessageFieldContract(wireName: "title", required: false, nullable: false, array: false), MessageFieldContract(wireName: "description", required: false, nullable: false, array: false), MessageFieldContract(wireName: "content_type", required: false, nullable: false, array: false), MessageFieldContract(wireName: "size", required: true, nullable: false, array: false), MessageFieldContract(wireName: "url", required: true, nullable: false, array: false), MessageFieldContract(wireName: "proxy_url", required: true, nullable: false, array: false), MessageFieldContract(wireName: "height", required: false, nullable: true, array: false), MessageFieldContract(wireName: "width", required: false, nullable: true, array: false), MessageFieldContract(wireName: "placeholder", required: false, nullable: false, array: false), MessageFieldContract(wireName: "placeholder_version", required: false, nullable: false, array: false), MessageFieldContract(wireName: "ephemeral", required: false, nullable: false, array: false), MessageFieldContract(wireName: "duration_secs", required: false, nullable: false, array: false), MessageFieldContract(wireName: "waveform", required: false, nullable: false, array: false), MessageFieldContract(wireName: "flags", required: false, nullable: false, array: false), MessageFieldContract(wireName: "clip_participants", required: false, nullable: false, array: true), MessageFieldContract(wireName: "clip_created_at", required: false, nullable: false, array: false), MessageFieldContract(wireName: "application", required: false, nullable: true, array: false)],
            decode: { try MessageAttachment(data: $0) }, decodeBounded: { try MessageAttachment(data: $0, limits: $1) }),
        MessageFixture(name: "MessageEmbedFooter", json: #"{"text":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"}"#,
            contracts: [MessageFieldContract(wireName: "text", required: true, nullable: false, array: false), MessageFieldContract(wireName: "icon_url", required: false, nullable: false, array: false), MessageFieldContract(wireName: "proxy_icon_url", required: false, nullable: false, array: false)],
            decode: { try MessageEmbedFooter(data: $0) }, decodeBounded: { try MessageEmbedFooter(data: $0, limits: $1) }),
        MessageFixture(name: "MessageEmbedImage", json: #"{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1}"#,
            contracts: [MessageFieldContract(wireName: "url", required: true, nullable: false, array: false), MessageFieldContract(wireName: "proxy_url", required: false, nullable: false, array: false), MessageFieldContract(wireName: "height", required: false, nullable: false, array: false), MessageFieldContract(wireName: "width", required: false, nullable: false, array: false), MessageFieldContract(wireName: "content_type", required: false, nullable: false, array: false), MessageFieldContract(wireName: "placeholder", required: false, nullable: false, array: false), MessageFieldContract(wireName: "placeholder_version", required: false, nullable: false, array: false), MessageFieldContract(wireName: "description", required: false, nullable: false, array: false), MessageFieldContract(wireName: "flags", required: false, nullable: false, array: false)],
            decode: { try MessageEmbedImage(data: $0) }, decodeBounded: { try MessageEmbedImage(data: $0, limits: $1) }),
        MessageFixture(name: "MessageEmbedVideo", json: #"{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1}"#,
            contracts: [MessageFieldContract(wireName: "url", required: false, nullable: false, array: false), MessageFieldContract(wireName: "proxy_url", required: false, nullable: false, array: false), MessageFieldContract(wireName: "height", required: false, nullable: false, array: false), MessageFieldContract(wireName: "width", required: false, nullable: false, array: false), MessageFieldContract(wireName: "content_type", required: false, nullable: false, array: false), MessageFieldContract(wireName: "placeholder", required: false, nullable: false, array: false), MessageFieldContract(wireName: "placeholder_version", required: false, nullable: false, array: false), MessageFieldContract(wireName: "description", required: false, nullable: false, array: false), MessageFieldContract(wireName: "flags", required: false, nullable: false, array: false)],
            decode: { try MessageEmbedVideo(data: $0) }, decodeBounded: { try MessageEmbedVideo(data: $0, limits: $1) }),
        MessageFixture(name: "MessageEmbedProvider", json: #"{"name":"secret text","url":"secret text"}"#,
            contracts: [MessageFieldContract(wireName: "name", required: false, nullable: false, array: false), MessageFieldContract(wireName: "url", required: false, nullable: false, array: false)],
            decode: { try MessageEmbedProvider(data: $0) }, decodeBounded: { try MessageEmbedProvider(data: $0, limits: $1) }),
        MessageFixture(name: "MessageEmbedAuthor", json: #"{"name":"secret text","url":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"}"#,
            contracts: [MessageFieldContract(wireName: "name", required: true, nullable: false, array: false), MessageFieldContract(wireName: "url", required: false, nullable: false, array: false), MessageFieldContract(wireName: "icon_url", required: false, nullable: false, array: false), MessageFieldContract(wireName: "proxy_icon_url", required: false, nullable: false, array: false)],
            decode: { try MessageEmbedAuthor(data: $0) }, decodeBounded: { try MessageEmbedAuthor(data: $0, limits: $1) }),
        MessageFixture(name: "MessageEmbedField", json: #"{"name":"secret text","value":"secret text","inline":true}"#,
            contracts: [MessageFieldContract(wireName: "name", required: true, nullable: false, array: false), MessageFieldContract(wireName: "value", required: true, nullable: false, array: false), MessageFieldContract(wireName: "inline", required: false, nullable: false, array: false)],
            decode: { try MessageEmbedField(data: $0) }, decodeBounded: { try MessageEmbedField(data: $0, limits: $1) }),
        MessageFixture(name: "MessageEmbed", json: #"{"title":"secret text","type":"future-kind","description":"secret text","url":"secret text","timestamp":"2026-10-16T17:00:00.123456Z","color":1,"footer":{"text":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"image":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"thumbnail":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"video":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"provider":{"name":"secret text","url":"secret text"},"author":{"name":"secret text","url":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"fields":[{"name":"secret text","value":"secret text","inline":true}],"components":[{"type":10,"content":"component text"}],"flags":1}"#,
            contracts: [MessageFieldContract(wireName: "title", required: false, nullable: false, array: false), MessageFieldContract(wireName: "type", required: false, nullable: false, array: false), MessageFieldContract(wireName: "description", required: false, nullable: false, array: false), MessageFieldContract(wireName: "url", required: false, nullable: false, array: false), MessageFieldContract(wireName: "timestamp", required: false, nullable: false, array: false), MessageFieldContract(wireName: "color", required: false, nullable: false, array: false), MessageFieldContract(wireName: "footer", required: false, nullable: false, array: false), MessageFieldContract(wireName: "image", required: false, nullable: false, array: false), MessageFieldContract(wireName: "thumbnail", required: false, nullable: false, array: false), MessageFieldContract(wireName: "video", required: false, nullable: false, array: false), MessageFieldContract(wireName: "provider", required: false, nullable: false, array: false), MessageFieldContract(wireName: "author", required: false, nullable: false, array: false), MessageFieldContract(wireName: "fields", required: false, nullable: false, array: true), MessageFieldContract(wireName: "components", required: false, nullable: false, array: true), MessageFieldContract(wireName: "flags", required: false, nullable: false, array: false)],
            decode: { try MessageEmbed(data: $0) }, decodeBounded: { try MessageEmbed(data: $0, limits: $1) }),
        MessageFixture(name: "MessageActivity", json: #"{"type":999,"party_id":"secret text"}"#,
            contracts: [MessageFieldContract(wireName: "type", required: true, nullable: false, array: false), MessageFieldContract(wireName: "party_id", required: false, nullable: false, array: false)],
            decode: { try MessageActivity(data: $0) }, decodeBounded: { try MessageActivity(data: $0, limits: $1) }),
        MessageFixture(name: "MessageChannelMention", json: #"{"id":"18446744073709551615","guild_id":"18446744073709551615","type":1,"name":"secret text"}"#,
            contracts: [MessageFieldContract(wireName: "id", required: true, nullable: false, array: false), MessageFieldContract(wireName: "guild_id", required: true, nullable: false, array: false), MessageFieldContract(wireName: "type", required: true, nullable: false, array: false), MessageFieldContract(wireName: "name", required: true, nullable: false, array: false)],
            decode: { try MessageChannelMention(data: $0) }, decodeBounded: { try MessageChannelMention(data: $0, limits: $1) }),
        MessageFixture(name: "MessageReactionCounts", json: #"{"burst":1,"normal":1}"#,
            contracts: [MessageFieldContract(wireName: "burst", required: true, nullable: false, array: false), MessageFieldContract(wireName: "normal", required: true, nullable: false, array: false)],
            decode: { try MessageReactionCounts(data: $0) }, decodeBounded: { try MessageReactionCounts(data: $0, limits: $1) }),
        MessageFixture(name: "MessageReaction", json: #"{"count":1,"count_details":{"burst":1,"normal":1},"me":true,"me_burst":true,"emoji":{"id":null,"name":"😀","animated":true},"burst_colors":["secret text"]}"#,
            contracts: [MessageFieldContract(wireName: "count", required: true, nullable: false, array: false), MessageFieldContract(wireName: "count_details", required: true, nullable: false, array: false), MessageFieldContract(wireName: "me", required: true, nullable: false, array: false), MessageFieldContract(wireName: "me_burst", required: true, nullable: false, array: false), MessageFieldContract(wireName: "emoji", required: true, nullable: false, array: false), MessageFieldContract(wireName: "burst_colors", required: true, nullable: false, array: true)],
            decode: { try MessageReaction(data: $0) }, decodeBounded: { try MessageReaction(data: $0, limits: $1) }),
        MessageFixture(name: "MessageReference", json: #"{"type":999,"message_id":"18446744073709551615","channel_id":"18446744073709551615","guild_id":"18446744073709551615","fail_if_not_exists":true}"#,
            contracts: [MessageFieldContract(wireName: "type", required: false, nullable: false, array: false), MessageFieldContract(wireName: "message_id", required: false, nullable: false, array: false), MessageFieldContract(wireName: "channel_id", required: false, nullable: false, array: false), MessageFieldContract(wireName: "guild_id", required: false, nullable: false, array: false), MessageFieldContract(wireName: "fail_if_not_exists", required: false, nullable: false, array: false)],
            decode: { try MessageReference(data: $0) }, decodeBounded: { try MessageReference(data: $0, limits: $1) }),
        MessageFixture(name: "MessageStickerItem", json: #"{"id":"18446744073709551615","name":"secret text","format_type":999}"#,
            contracts: [MessageFieldContract(wireName: "id", required: true, nullable: false, array: false), MessageFieldContract(wireName: "name", required: true, nullable: false, array: false), MessageFieldContract(wireName: "format_type", required: true, nullable: false, array: false)],
            decode: { try MessageStickerItem(data: $0) }, decodeBounded: { try MessageStickerItem(data: $0, limits: $1) }),
        MessageFixture(name: "MessageRoleSubscriptionData", json: #"{"role_subscription_listing_id":"18446744073709551615","tier_name":"secret text","total_months_subscribed":1,"is_renewal":true}"#,
            contracts: [MessageFieldContract(wireName: "role_subscription_listing_id", required: true, nullable: false, array: false), MessageFieldContract(wireName: "tier_name", required: true, nullable: false, array: false), MessageFieldContract(wireName: "total_months_subscribed", required: true, nullable: false, array: false), MessageFieldContract(wireName: "is_renewal", required: true, nullable: false, array: false)],
            decode: { try MessageRoleSubscriptionData(data: $0) }, decodeBounded: { try MessageRoleSubscriptionData(data: $0, limits: $1) }),
        MessageFixture(name: "MessageCall", json: #"{"participants":["18446744073709551615"],"ended_timestamp":"2026-10-16T17:00:00.123456Z"}"#,
            contracts: [MessageFieldContract(wireName: "participants", required: true, nullable: false, array: true), MessageFieldContract(wireName: "ended_timestamp", required: false, nullable: true, array: false)],
            decode: { try MessageCall(data: $0) }, decodeBounded: { try MessageCall(data: $0, limits: $1) }),
        MessageFixture(name: "MessageSharedClientTheme", json: #"{"colors":["secret text"],"gradient_angle":1,"base_mix":1,"base_theme":999}"#,
            contracts: [MessageFieldContract(wireName: "colors", required: true, nullable: false, array: true), MessageFieldContract(wireName: "gradient_angle", required: true, nullable: false, array: false), MessageFieldContract(wireName: "base_mix", required: true, nullable: false, array: false), MessageFieldContract(wireName: "base_theme", required: false, nullable: true, array: false)],
            decode: { try MessageSharedClientTheme(data: $0) }, decodeBounded: { try MessageSharedClientTheme(data: $0, limits: $1) }),
        MessageFixture(name: "MessageLegacyInteraction", json: #"{"id":"18446744073709551615","type":1,"name":"secret text","user":{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}},"member":{"id":"secret text","name":"secret text","type":1}}"#,
            contracts: [MessageFieldContract(wireName: "id", required: true, nullable: false, array: false), MessageFieldContract(wireName: "type", required: true, nullable: false, array: false), MessageFieldContract(wireName: "name", required: true, nullable: false, array: false), MessageFieldContract(wireName: "user", required: true, nullable: false, array: false), MessageFieldContract(wireName: "member", required: false, nullable: false, array: false)],
            decode: { try MessageLegacyInteraction(data: $0) }, decodeBounded: { try MessageLegacyInteraction(data: $0, limits: $1) }),
        MessageFixture(name: "MessagePin", json: #"{"pinned_at":"2026-10-16T17:00:00.123456Z","message":{"id":"18446744073709551615","channel_id":"18446744073709551615","author":{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}},"content":"secret text","timestamp":"2026-10-16T17:00:00.123456Z","edited_timestamp":null,"tts":true,"mention_everyone":true,"mentions":[{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}}],"mention_roles":["18446744073709551615"],"mention_channels":[{"id":"18446744073709551615","guild_id":"18446744073709551615","type":1,"name":"secret text"}],"attachments":[{"id":"18446744073709551615","filename":"secret text","title":"secret text","description":"secret text","content_type":"secret text","size":1,"url":"secret text","proxy_url":"secret text","height":1,"width":1,"placeholder":"secret text","placeholder_version":1,"ephemeral":true,"duration_secs":0.25,"waveform":"secret text","flags":1,"clip_participants":[{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}}],"clip_created_at":"2026-10-16T17:00:00.123456Z","application":{"id":"secret text","name":"secret text","type":1}}],"embeds":[{"title":"secret text","type":"future-kind","description":"secret text","url":"secret text","timestamp":"2026-10-16T17:00:00.123456Z","color":1,"footer":{"text":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"image":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"thumbnail":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"video":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"provider":{"name":"secret text","url":"secret text"},"author":{"name":"secret text","url":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"fields":[{"name":"secret text","value":"secret text","inline":true}],"components":[{"type":10,"content":"component text"}],"flags":1}],"reactions":[{"count":1,"count_details":{"burst":1,"normal":1},"me":true,"me_burst":true,"emoji":{"id":null,"name":"😀","animated":true},"burst_colors":["secret text"]}],"pinned":true,"webhook_id":"18446744073709551615","type":999,"activity":{"type":999,"party_id":"secret text"},"application":{"id":"secret text","name":"secret text","type":1},"application_id":"18446744073709551615","flags":1,"message_reference":{"type":999,"message_id":"18446744073709551615","channel_id":"18446744073709551615","guild_id":"18446744073709551615","fail_if_not_exists":true},"message_snapshots":[{"message":{"type":999,"content":"secret text","embeds":[{"title":"secret text","type":"future-kind","description":"secret text","url":"secret text","timestamp":"2026-10-16T17:00:00.123456Z","color":1,"footer":{"text":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"image":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"thumbnail":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"video":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"provider":{"name":"secret text","url":"secret text"},"author":{"name":"secret text","url":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"fields":[{"name":"secret text","value":"secret text","inline":true}],"components":[{"type":10,"content":"component text"}],"flags":1}],"attachments":[{"id":"18446744073709551615","filename":"secret text","title":"secret text","description":"secret text","content_type":"secret text","size":1,"url":"secret text","proxy_url":"secret text","height":1,"width":1,"placeholder":"secret text","placeholder_version":1,"ephemeral":true,"duration_secs":0.25,"waveform":"secret text","flags":1,"clip_participants":[{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}}],"clip_created_at":"2026-10-16T17:00:00.123456Z","application":{"id":"secret text","name":"secret text","type":1}}],"timestamp":"2026-10-16T17:00:00.123456Z","edited_timestamp":null,"flags":1,"mentions":[{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}}],"mention_roles":["18446744073709551615"],"stickers":[{"id":"secret text","name":"secret text","type":1}],"sticker_items":[{"id":"18446744073709551615","name":"secret text","format_type":999}],"components":[{"type":10,"content":"component text"}],"message_snapshots":[]}}],"interaction_metadata":{"id":"18446744073709551615","type":2,"user":{"id":"1","username":"user","avatar":null},"authorizing_integration_owners":{"0":"18446744073709551615"}},"interaction":{"id":"18446744073709551615","type":1,"name":"secret text","user":{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}},"member":{"id":"secret text","name":"secret text","type":1}},"thread":{"id":"secret text","name":"secret text","type":1},"components":[{"type":10,"content":"component text"}],"sticker_items":[{"id":"18446744073709551615","name":"secret text","format_type":999}],"stickers":[{"id":"secret text","name":"secret text","type":1}],"position":1,"role_subscription_data":{"role_subscription_listing_id":"18446744073709551615","tier_name":"secret text","total_months_subscribed":1,"is_renewal":true},"resolved":{"users":{"1":{"id":"1","username":"user","avatar":null}},"members":{"1":{}},"roles":{"2":{}},"channels":{"3":{}},"messages":{},"attachments":{}},"poll":{"question":{"text":"question"},"answers":[{"answer_id":1,"poll_media":{"text":"answer"}}],"expiry":null,"allow_multiselect":true,"layout_type":1},"call":{"participants":["18446744073709551615"],"ended_timestamp":"2026-10-16T17:00:00.123456Z"},"shared_client_theme":{"colors":["secret text"],"gradient_angle":1,"base_mix":1,"base_theme":999},"nonce":"exact nonce","referenced_message":null}}"#,
            contracts: [MessageFieldContract(wireName: "pinned_at", required: true, nullable: false, array: false), MessageFieldContract(wireName: "message", required: true, nullable: false, array: false)],
            decode: { try MessagePin(data: $0) }, decodeBounded: { try MessagePin(data: $0, limits: $1) }),
        MessageFixture(name: "MessagePins", json: #"{"items":[{"pinned_at":"2026-10-16T17:00:00.123456Z","message":{"id":"18446744073709551615","channel_id":"18446744073709551615","author":{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}},"content":"secret text","timestamp":"2026-10-16T17:00:00.123456Z","edited_timestamp":null,"tts":true,"mention_everyone":true,"mentions":[{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}}],"mention_roles":["18446744073709551615"],"mention_channels":[{"id":"18446744073709551615","guild_id":"18446744073709551615","type":1,"name":"secret text"}],"attachments":[{"id":"18446744073709551615","filename":"secret text","title":"secret text","description":"secret text","content_type":"secret text","size":1,"url":"secret text","proxy_url":"secret text","height":1,"width":1,"placeholder":"secret text","placeholder_version":1,"ephemeral":true,"duration_secs":0.25,"waveform":"secret text","flags":1,"clip_participants":[{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}}],"clip_created_at":"2026-10-16T17:00:00.123456Z","application":{"id":"secret text","name":"secret text","type":1}}],"embeds":[{"title":"secret text","type":"future-kind","description":"secret text","url":"secret text","timestamp":"2026-10-16T17:00:00.123456Z","color":1,"footer":{"text":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"image":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"thumbnail":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"video":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"provider":{"name":"secret text","url":"secret text"},"author":{"name":"secret text","url":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"fields":[{"name":"secret text","value":"secret text","inline":true}],"components":[{"type":10,"content":"component text"}],"flags":1}],"reactions":[{"count":1,"count_details":{"burst":1,"normal":1},"me":true,"me_burst":true,"emoji":{"id":null,"name":"😀","animated":true},"burst_colors":["secret text"]}],"pinned":true,"webhook_id":"18446744073709551615","type":999,"activity":{"type":999,"party_id":"secret text"},"application":{"id":"secret text","name":"secret text","type":1},"application_id":"18446744073709551615","flags":1,"message_reference":{"type":999,"message_id":"18446744073709551615","channel_id":"18446744073709551615","guild_id":"18446744073709551615","fail_if_not_exists":true},"message_snapshots":[{"message":{"type":999,"content":"secret text","embeds":[{"title":"secret text","type":"future-kind","description":"secret text","url":"secret text","timestamp":"2026-10-16T17:00:00.123456Z","color":1,"footer":{"text":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"image":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"thumbnail":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"video":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"provider":{"name":"secret text","url":"secret text"},"author":{"name":"secret text","url":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"fields":[{"name":"secret text","value":"secret text","inline":true}],"components":[{"type":10,"content":"component text"}],"flags":1}],"attachments":[{"id":"18446744073709551615","filename":"secret text","title":"secret text","description":"secret text","content_type":"secret text","size":1,"url":"secret text","proxy_url":"secret text","height":1,"width":1,"placeholder":"secret text","placeholder_version":1,"ephemeral":true,"duration_secs":0.25,"waveform":"secret text","flags":1,"clip_participants":[{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}}],"clip_created_at":"2026-10-16T17:00:00.123456Z","application":{"id":"secret text","name":"secret text","type":1}}],"timestamp":"2026-10-16T17:00:00.123456Z","edited_timestamp":null,"flags":1,"mentions":[{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}}],"mention_roles":["18446744073709551615"],"stickers":[{"id":"secret text","name":"secret text","type":1}],"sticker_items":[{"id":"18446744073709551615","name":"secret text","format_type":999}],"components":[{"type":10,"content":"component text"}],"message_snapshots":[]}}],"interaction_metadata":{"id":"18446744073709551615","type":2,"user":{"id":"1","username":"user","avatar":null},"authorizing_integration_owners":{"0":"18446744073709551615"}},"interaction":{"id":"18446744073709551615","type":1,"name":"secret text","user":{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}},"member":{"id":"secret text","name":"secret text","type":1}},"thread":{"id":"secret text","name":"secret text","type":1},"components":[{"type":10,"content":"component text"}],"sticker_items":[{"id":"18446744073709551615","name":"secret text","format_type":999}],"stickers":[{"id":"secret text","name":"secret text","type":1}],"position":1,"role_subscription_data":{"role_subscription_listing_id":"18446744073709551615","tier_name":"secret text","total_months_subscribed":1,"is_renewal":true},"resolved":{"users":{"1":{"id":"1","username":"user","avatar":null}},"members":{"1":{}},"roles":{"2":{}},"channels":{"3":{}},"messages":{},"attachments":{}},"poll":{"question":{"text":"question"},"answers":[{"answer_id":1,"poll_media":{"text":"answer"}}],"expiry":null,"allow_multiselect":true,"layout_type":1},"call":{"participants":["18446744073709551615"],"ended_timestamp":"2026-10-16T17:00:00.123456Z"},"shared_client_theme":{"colors":["secret text"],"gradient_angle":1,"base_mix":1,"base_theme":999},"nonce":"exact nonce","referenced_message":null}}],"has_more":true}"#,
            contracts: [MessageFieldContract(wireName: "items", required: true, nullable: false, array: true), MessageFieldContract(wireName: "has_more", required: true, nullable: false, array: false)],
            decode: { try MessagePins(data: $0) }, decodeBounded: { try MessagePins(data: $0, limits: $1) }),
        MessageFixture(name: "MessageSnapshotContent", json: #"{"type":999,"content":"secret text","embeds":[{"title":"secret text","type":"future-kind","description":"secret text","url":"secret text","timestamp":"2026-10-16T17:00:00.123456Z","color":1,"footer":{"text":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"image":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"thumbnail":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"video":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"provider":{"name":"secret text","url":"secret text"},"author":{"name":"secret text","url":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"fields":[{"name":"secret text","value":"secret text","inline":true}],"components":[{"type":10,"content":"component text"}],"flags":1}],"attachments":[{"id":"18446744073709551615","filename":"secret text","title":"secret text","description":"secret text","content_type":"secret text","size":1,"url":"secret text","proxy_url":"secret text","height":1,"width":1,"placeholder":"secret text","placeholder_version":1,"ephemeral":true,"duration_secs":0.25,"waveform":"secret text","flags":1,"clip_participants":[{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}}],"clip_created_at":"2026-10-16T17:00:00.123456Z","application":{"id":"secret text","name":"secret text","type":1}}],"timestamp":"2026-10-16T17:00:00.123456Z","edited_timestamp":null,"flags":1,"mentions":[{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}}],"mention_roles":["18446744073709551615"],"stickers":[{"id":"secret text","name":"secret text","type":1}],"sticker_items":[{"id":"18446744073709551615","name":"secret text","format_type":999}],"components":[{"type":10,"content":"component text"}],"message_snapshots":[]}"#,
            contracts: [MessageFieldContract(wireName: "type", required: true, nullable: false, array: false), MessageFieldContract(wireName: "content", required: true, nullable: false, array: false), MessageFieldContract(wireName: "embeds", required: true, nullable: false, array: true), MessageFieldContract(wireName: "attachments", required: true, nullable: false, array: true), MessageFieldContract(wireName: "timestamp", required: true, nullable: false, array: false), MessageFieldContract(wireName: "edited_timestamp", required: true, nullable: true, array: false), MessageFieldContract(wireName: "flags", required: false, nullable: false, array: false), MessageFieldContract(wireName: "mentions", required: true, nullable: false, array: true), MessageFieldContract(wireName: "mention_roles", required: true, nullable: false, array: true), MessageFieldContract(wireName: "stickers", required: false, nullable: false, array: true), MessageFieldContract(wireName: "sticker_items", required: false, nullable: false, array: true), MessageFieldContract(wireName: "components", required: false, nullable: false, array: true), MessageFieldContract(wireName: "message_snapshots", required: false, nullable: false, array: true)],
            decode: { try MessageSnapshotContent(data: $0) }, decodeBounded: { try MessageSnapshotContent(data: $0, limits: $1) }),
        MessageFixture(name: "MessageSnapshot", json: #"{"message":{"type":999,"content":"secret text","embeds":[{"title":"secret text","type":"future-kind","description":"secret text","url":"secret text","timestamp":"2026-10-16T17:00:00.123456Z","color":1,"footer":{"text":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"image":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"thumbnail":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"video":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"provider":{"name":"secret text","url":"secret text"},"author":{"name":"secret text","url":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"fields":[{"name":"secret text","value":"secret text","inline":true}],"components":[{"type":10,"content":"component text"}],"flags":1}],"attachments":[{"id":"18446744073709551615","filename":"secret text","title":"secret text","description":"secret text","content_type":"secret text","size":1,"url":"secret text","proxy_url":"secret text","height":1,"width":1,"placeholder":"secret text","placeholder_version":1,"ephemeral":true,"duration_secs":0.25,"waveform":"secret text","flags":1,"clip_participants":[{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}}],"clip_created_at":"2026-10-16T17:00:00.123456Z","application":{"id":"secret text","name":"secret text","type":1}}],"timestamp":"2026-10-16T17:00:00.123456Z","edited_timestamp":null,"flags":1,"mentions":[{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}}],"mention_roles":["18446744073709551615"],"stickers":[{"id":"secret text","name":"secret text","type":1}],"sticker_items":[{"id":"18446744073709551615","name":"secret text","format_type":999}],"components":[{"type":10,"content":"component text"}],"message_snapshots":[]}}"#,
            contracts: [MessageFieldContract(wireName: "message", required: true, nullable: false, array: false)],
            decode: { try MessageSnapshot(data: $0) }, decodeBounded: { try MessageSnapshot(data: $0, limits: $1) }),
        MessageFixture(name: "MessageSearchResults", json: #"{"doing_deep_historical_index":true,"documents_indexed":1,"total_results":1,"threads":[{"id":"secret text","name":"secret text","type":1}],"members":[{"id":"secret text","name":"secret text","type":1}],"analytics_id":"secret text","messages":[]}"#,
            contracts: [MessageFieldContract(wireName: "doing_deep_historical_index", required: true, nullable: false, array: false), MessageFieldContract(wireName: "documents_indexed", required: false, nullable: false, array: false), MessageFieldContract(wireName: "total_results", required: true, nullable: false, array: false), MessageFieldContract(wireName: "threads", required: false, nullable: false, array: true), MessageFieldContract(wireName: "members", required: false, nullable: false, array: true), MessageFieldContract(wireName: "analytics_id", required: false, nullable: false, array: false)],
            decode: { try MessageSearchResults(data: $0) }, decodeBounded: { try MessageSearchResults(data: $0, limits: $1) }),
        MessageFixture(name: "Message", json: #"{"id":"18446744073709551615","channel_id":"18446744073709551615","author":{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}},"content":"secret text","timestamp":"2026-10-16T17:00:00.123456Z","edited_timestamp":null,"tts":true,"mention_everyone":true,"mentions":[{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}}],"mention_roles":["18446744073709551615"],"mention_channels":[{"id":"18446744073709551615","guild_id":"18446744073709551615","type":1,"name":"secret text"}],"attachments":[{"id":"18446744073709551615","filename":"secret text","title":"secret text","description":"secret text","content_type":"secret text","size":1,"url":"secret text","proxy_url":"secret text","height":1,"width":1,"placeholder":"secret text","placeholder_version":1,"ephemeral":true,"duration_secs":0.25,"waveform":"secret text","flags":1,"clip_participants":[{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}}],"clip_created_at":"2026-10-16T17:00:00.123456Z","application":{"id":"secret text","name":"secret text","type":1}}],"embeds":[{"title":"secret text","type":"future-kind","description":"secret text","url":"secret text","timestamp":"2026-10-16T17:00:00.123456Z","color":1,"footer":{"text":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"image":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"thumbnail":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"video":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"provider":{"name":"secret text","url":"secret text"},"author":{"name":"secret text","url":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"fields":[{"name":"secret text","value":"secret text","inline":true}],"components":[{"type":10,"content":"component text"}],"flags":1}],"reactions":[{"count":1,"count_details":{"burst":1,"normal":1},"me":true,"me_burst":true,"emoji":{"id":null,"name":"😀","animated":true},"burst_colors":["secret text"]}],"pinned":true,"webhook_id":"18446744073709551615","type":999,"activity":{"type":999,"party_id":"secret text"},"application":{"id":"secret text","name":"secret text","type":1},"application_id":"18446744073709551615","flags":1,"message_reference":{"type":999,"message_id":"18446744073709551615","channel_id":"18446744073709551615","guild_id":"18446744073709551615","fail_if_not_exists":true},"message_snapshots":[{"message":{"type":999,"content":"secret text","embeds":[{"title":"secret text","type":"future-kind","description":"secret text","url":"secret text","timestamp":"2026-10-16T17:00:00.123456Z","color":1,"footer":{"text":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"image":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"thumbnail":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"video":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"provider":{"name":"secret text","url":"secret text"},"author":{"name":"secret text","url":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"fields":[{"name":"secret text","value":"secret text","inline":true}],"components":[{"type":10,"content":"component text"}],"flags":1}],"attachments":[{"id":"18446744073709551615","filename":"secret text","title":"secret text","description":"secret text","content_type":"secret text","size":1,"url":"secret text","proxy_url":"secret text","height":1,"width":1,"placeholder":"secret text","placeholder_version":1,"ephemeral":true,"duration_secs":0.25,"waveform":"secret text","flags":1,"clip_participants":[{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}}],"clip_created_at":"2026-10-16T17:00:00.123456Z","application":{"id":"secret text","name":"secret text","type":1}}],"timestamp":"2026-10-16T17:00:00.123456Z","edited_timestamp":null,"flags":1,"mentions":[{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}}],"mention_roles":["18446744073709551615"],"stickers":[{"id":"secret text","name":"secret text","type":1}],"sticker_items":[{"id":"18446744073709551615","name":"secret text","format_type":999}],"components":[{"type":10,"content":"component text"}],"message_snapshots":[]}}],"interaction_metadata":{"id":"18446744073709551615","type":2,"user":{"id":"1","username":"user","avatar":null},"authorizing_integration_owners":{"0":"18446744073709551615"}},"interaction":{"id":"18446744073709551615","type":1,"name":"secret text","user":{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}},"member":{"id":"secret text","name":"secret text","type":1}},"thread":{"id":"secret text","name":"secret text","type":1},"components":[{"type":10,"content":"component text"}],"sticker_items":[{"id":"18446744073709551615","name":"secret text","format_type":999}],"stickers":[{"id":"secret text","name":"secret text","type":1}],"position":1,"role_subscription_data":{"role_subscription_listing_id":"18446744073709551615","tier_name":"secret text","total_months_subscribed":1,"is_renewal":true},"resolved":{"users":{"1":{"id":"1","username":"user","avatar":null}},"members":{"1":{}},"roles":{"2":{}},"channels":{"3":{}},"messages":{},"attachments":{}},"poll":{"question":{"text":"question"},"answers":[{"answer_id":1,"poll_media":{"text":"answer"}}],"expiry":null,"allow_multiselect":true,"layout_type":1},"call":{"participants":["18446744073709551615"],"ended_timestamp":"2026-10-16T17:00:00.123456Z"},"shared_client_theme":{"colors":["secret text"],"gradient_angle":1,"base_mix":1,"base_theme":999},"nonce":"exact nonce","referenced_message":null}"#,
            contracts: [MessageFieldContract(wireName: "id", required: true, nullable: false, array: false), MessageFieldContract(wireName: "channel_id", required: true, nullable: false, array: false), MessageFieldContract(wireName: "author", required: true, nullable: false, array: false), MessageFieldContract(wireName: "content", required: true, nullable: false, array: false), MessageFieldContract(wireName: "timestamp", required: true, nullable: false, array: false), MessageFieldContract(wireName: "edited_timestamp", required: true, nullable: true, array: false), MessageFieldContract(wireName: "tts", required: true, nullable: false, array: false), MessageFieldContract(wireName: "mention_everyone", required: true, nullable: false, array: false), MessageFieldContract(wireName: "mentions", required: true, nullable: false, array: true), MessageFieldContract(wireName: "mention_roles", required: true, nullable: false, array: true), MessageFieldContract(wireName: "mention_channels", required: false, nullable: false, array: true), MessageFieldContract(wireName: "attachments", required: true, nullable: false, array: true), MessageFieldContract(wireName: "embeds", required: true, nullable: false, array: true), MessageFieldContract(wireName: "reactions", required: false, nullable: false, array: true), MessageFieldContract(wireName: "pinned", required: true, nullable: false, array: false), MessageFieldContract(wireName: "webhook_id", required: false, nullable: false, array: false), MessageFieldContract(wireName: "type", required: true, nullable: false, array: false), MessageFieldContract(wireName: "activity", required: false, nullable: false, array: false), MessageFieldContract(wireName: "application", required: false, nullable: false, array: false), MessageFieldContract(wireName: "application_id", required: false, nullable: false, array: false), MessageFieldContract(wireName: "flags", required: false, nullable: false, array: false), MessageFieldContract(wireName: "message_reference", required: false, nullable: false, array: false), MessageFieldContract(wireName: "message_snapshots", required: false, nullable: false, array: true), MessageFieldContract(wireName: "interaction_metadata", required: false, nullable: false, array: false), MessageFieldContract(wireName: "interaction", required: false, nullable: false, array: false), MessageFieldContract(wireName: "thread", required: false, nullable: false, array: false), MessageFieldContract(wireName: "components", required: false, nullable: false, array: true), MessageFieldContract(wireName: "sticker_items", required: false, nullable: false, array: true), MessageFieldContract(wireName: "stickers", required: false, nullable: false, array: true), MessageFieldContract(wireName: "position", required: false, nullable: false, array: false), MessageFieldContract(wireName: "role_subscription_data", required: false, nullable: false, array: false), MessageFieldContract(wireName: "resolved", required: false, nullable: false, array: false), MessageFieldContract(wireName: "poll", required: false, nullable: false, array: false), MessageFieldContract(wireName: "call", required: false, nullable: false, array: false), MessageFieldContract(wireName: "shared_client_theme", required: false, nullable: false, array: false)],
            decode: { try Message(data: $0) }, decodeBounded: { try Message(data: $0, limits: $1) }),
        MessageFixture(name: "MessageComponent", json: #"{"type":10,"content":"component text"}"#,
            contracts: [],
            decode: { try MessageComponent(data: $0) }, decodeBounded: { try MessageComponent(data: $0, limits: $1) }),
        MessageFixture(name: "MessageInteractionMetadata", json: #"{"id":"18446744073709551615","type":2,"user":{"id":"1","username":"user","avatar":null},"authorizing_integration_owners":{"0":"18446744073709551615"}}"#,
            contracts: [],
            decode: { try MessageInteractionMetadata(data: $0) }, decodeBounded: { try MessageInteractionMetadata(data: $0, limits: $1) }),
        MessageFixture(name: "MessageResolvedData", json: #"{"users":{"1":{"id":"1","username":"user","avatar":null}},"members":{"1":{}},"roles":{"2":{}},"channels":{"3":{}},"messages":{},"attachments":{}}"#,
            contracts: [],
            decode: { try MessageResolvedData(data: $0) }, decodeBounded: { try MessageResolvedData(data: $0, limits: $1) }),
        MessageFixture(name: "MessageSearchIndexing", json: #"{"code":110000,"message":"Indexing secret","documents_indexed":0,"retry_after":0.25}"#,
            contracts: [],
            decode: { try MessageSearchIndexing(data: $0) }, decodeBounded: { try MessageSearchIndexing(data: $0, limits: $1) }),
    ]
}

/// Independent wire presence metadata used solely to formulate mutation test expectations.
struct MessageFieldContract: Sendable {
    let wireName: String
    let required: Bool
    let nullable: Bool
    let array: Bool
}
