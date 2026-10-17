import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Audit-specific regression cases protect presence semantics, upstream exceptions and response ordering.
/// All requests remain offline; snapshots carry no authorization, completeness or resource-liveness inference.
@Suite struct AuditLogValueTests {
    /// Every current written-reference/official-preview action constant resolves without remapping its numeric code.
    /// - Parameter fixture: One explicitly reviewed constant and its independently specified wire integer.
    /// - Throws: Unexpected JSON or model decoding errors fail the test.
    @Test(arguments: AuditLogEventFixture.all)
    fileprivate func knownEvents(fixture: AuditLogEventFixture) throws {
        let model = try AuditLogEntry(data: Data("{\"id\":\"1\",\"target_id\":null,\"user_id\":null,\"action_type\":\(fixture.rawValue)}".utf8))
        #expect(model.actionType.rawValue == fixture.rawValue)
        #expect(model.actionType.knownValue == fixture.event)
        #expect(AuditLogEvent(rawValue: fixture.rawValue) == fixture.event)
        #expect(RawValue(fixture.event).rawValue == fixture.rawValue)
        #expect(AuditLogEvent.allCases.count == AuditLogEventFixture.all.count)
    }

    /// Unknown action codes at both native integer boundaries remain exact and never resolve to a guessed case.
    /// Negative codes are retained as future raw values rather than silently converted to unsigned values.
    /// - Parameter raw: A currently unknown exact integral action discriminator.
    /// - Throws: Unexpected bounded parsing fails the test.
    @Test(arguments: [Int.min, -1, 0, 9999, Int.max])
    func unknownEvents(raw: Int) throws {
        let model = try AuditLogEntry(data: Data("{\"id\":\"18446744073709551615\",\"target_id\":null,\"user_id\":null,\"action_type\":\(raw)}".utf8))
        #expect(model.id.rawValue == UInt64.max)
        #expect(model.actionType.rawValue == raw)
        #expect(model.actionType.knownValue == nil)
        #expect(model.targetID == .null)
        #expect(model.userID == .null)
        #expect(model.changes == .absent)
        #expect(model.options == .absent)
        #expect(model.reason == .absent)
    }

    /// Change keys are opaque, covering role additions/removals and command-permission entity identifiers.
    /// Their values cover every JSON kind, with explicit null kept separate from missing old/new values.
    /// - Parameters:
    ///   - key: A documented exception, a large command-permission target or a future object field.
    ///   - source: Exact arbitrary JSON subtree; numeric spelling must not pass through Codable.
    /// - Throws: Unexpected exact tree parsing or projection fails the test.
    @Test(arguments: ["$add", "$remove", "channel_id", "avatar_hash", "18446744073709551615", "future_field"], ["null", "false", "true", #""private-value""#, "1.230000000000000000001e1000", #"[{"id":"18446744073709551615","name":"private-role"}]"#, #"{"id":"18446744073709551615","type":999,"permission":true}"#])
    func heterogeneousChangeValues(key: String, source: String) throws {
        let value = try JSONValue.parse(source)
        for oldPresent in [false, true] {
            for newPresent in [false, true] {
                var fields: [String: JSONValue] = ["key": .string(key)]
                if oldPresent { fields["old_value"] = value }
                if newPresent { fields["new_value"] = value }
                let model = try AuditLogChange(data: JSONValue.object(fields).serialized())
                #expect(model.key == .value(key))
                let expected: Field<JSONValue> = value == .null ? .null : .value(value)
                #expect(model.oldValue == (oldPresent ? expected : .absent))
                #expect(model.newValue == (newPresent ? expected : .absent))
                #expect(model.jsonValue() == .object(fields))
            }
        }
    }

    /// A null change key is a required-key compatibility case from Discord's official preview, not an omitted key.
    /// Explicit null new/old values remain null and removing the required key still fails deterministically.
    /// - Throws: Unexpected valid-fixture parsing fails the test.
    @Test func nullableChangeKeyAndResetSemantics() throws {
        let nullKey = try AuditLogChange(data: Data(#"{"key":null,"old_value":null,"new_value":null}"#.utf8))
        #expect(nullKey.key == .null)
        #expect(nullKey.oldValue == .null)
        #expect(nullKey.newValue == .null)
        let reset = try AuditLogChange(data: Data(#"{"key":"name","old_value":"private-old"}"#.utf8))
        #expect(reset.oldValue == .value(.string("private-old")))
        #expect(reset.newValue == .absent)
        let create = try AuditLogChange(data: Data(#"{"key":"name","new_value":"private-new"}"#.utf8))
        #expect(create.oldValue == .absent)
        #expect(create.newValue == .value(.string("private-new")))
        #expect(throws: DiscordError.transport(.invalidResponse)) { try AuditLogChange(data: Data(#"{"old_value":null}"#.utf8)) }
    }

    /// Audit target IDs preserve arbitrary text rather than incorrectly imposing snowflake assumptions.
    /// Empty options/reasons remain distinct from omission; UTF-8 response text is not truncated or normalized.
    /// - Throws: Unexpected model parsing or exact tree serialization fails the test.
    @Test func opaqueTargetsAndUnmodifiedText() throws {
        let reason = "private-" + String(repeating: "🛠️", count: 600)
        let fields: [String: JSONValue] = ["id": .string("0"), "target_id": .string("provider/opaque:target"),
                                          "user_id": .null, "action_type": .number(try JSONNumber(rawValue: "1")),
                                          "options": .object([:]), "changes": .array([]), "reason": .string(reason)]
        let model = try AuditLogEntry(data: JSONValue.object(fields).serialized())
        #expect(model.id.rawValue == 0)
        #expect(model.targetID == .value("provider/opaque:target"))
        #expect(model.changes == .value([]))
        #expect(model.options.auditLogRegressionValue?.rawFields.isEmpty == true)
        #expect(model.reason == .value(reason))
        #expect(!String(reflecting: model).contains(reason))
        #expect(model.jsonValue() == .object(fields))
    }

    /// String-valued options are kept exactly, including future types and counts wider than native integers.
    /// Unknown fields can carry arbitrary bounded JSON without a closed-schema assumption or payload leakage.
    /// - Throws: Unexpected bounded parsing fails the test.
    @Test func stringOptionsAndFutureShapes() throws {
        let model = try AuditLogEntryOptions(data: Data(#"{"count":"1844674407370955161518446744073709551615","type":"future-overwrite","auto_moderation_rule_trigger_type":"future-trigger","status":"private-status","future":{"secret":"private-secret","number":9.999999999999999999e9999}}"#.utf8))
        #expect(model.count == .value("1844674407370955161518446744073709551615"))
        #expect(model.type == .value("future-overwrite"))
        #expect(model.autoModerationRuleTriggerType == .value("future-trigger"))
        #expect(model.status == .value("private-status"))
        #expect(model.rawFields["future"] == (try JSONValue.parse(#"{"secret":"private-secret","number":9.999999999999999999e9999}"#)))
        #expect(!String(reflecting: model).contains("private-"))
        #expect(model.applicationID == .absent)
    }

    /// Both wire directions and duplicate entries survive projection unchanged, and null referenced rules retain position.
    /// No sorting, deduplication or assumption that a short page is exhausted is introduced by the response model.
    /// - Parameter ids: Ascending/descending entry IDs and a repeated ID, as independent server-provided orderings.
    /// - Throws: Unexpected fixture projection or serialization fails the test.
    @Test(arguments: [["2", "1"], ["1", "2"], ["2", "2"]])
    func envelopePreservesOrder(ids: [String]) throws {
        let entries = try ids.map { id in
            try JSONValue.parse("{\"id\":\"\(id)\",\"target_id\":null,\"user_id\":null,\"action_type\":1}")
        }
        let fields: [String: JSONValue] = ["audit_log_entries": .array(entries), "application_commands": .array([]),
                                          "auto_moderation_rules": .array([.null]), "guild_scheduled_events": .array([]),
                                          "integrations": .array([]), "threads": .array([]), "users": .array([]), "webhooks": .array([])]
        let model = try AuditLog(data: JSONValue.object(fields).serialized())
        #expect(model.auditLogEntries.map { $0.id.description } == ids)
        #expect(model.autoModerationRules == [.null])
        #expect(model.applicationCommands.isEmpty && model.guildScheduledEvents.isEmpty)
        #expect(model.integrations.isEmpty && model.threads.isEmpty && model.users.isEmpty && model.webhooks.isEmpty)
        #expect(model.jsonValue() == .object(fields))
    }

    /// Audit integrations expose only their documented partial shape and retain nullable names and provider accounts.
    /// Known and future provider variants accept absent or present application IDs without guessing association.
    /// - Parameters:
    ///   - type: Written/preview known provider variants and one future provider string.
    ///   - application: Whether an explicit application_id is supplied.
    /// - Throws: Unexpected fixture parsing fails the test.
    @Test(arguments: ["discord", "twitch", "youtube", "guild_subscription", "future-provider"], [false, true])
    func partialIntegrationVariants(type: String, application: Bool) throws {
        var fields: [String: JSONValue] = ["id": .string("18446744073709551615"), "name": .null,
                                          "type": .string(type), "account": .object(["id": .string("external:provider"), "name": .string("private-name")])]
        if application { fields["application_id"] = .string("18446744073709551615") }
        let model = try AuditLogIntegration(data: JSONValue.object(fields).serialized())
        #expect(model.id.rawValue == UInt64.max)
        #expect(model.name == .null)
        #expect(model.type.rawValue == type)
        #expect(model.type.knownValue == GuildIntegrationType(rawValue: type))
        #expect(model.account.id == "external:provider")
        #expect(model.account.name == "private-name")
        #expect(model.applicationID == (application ? .value(ApplicationID(rawValue: UInt64.max)) : .absent))
    }
}

/// Explicitly reviewed action code mapping, including the documented-preview-only variants.
private struct AuditLogEventFixture: Sendable {
    let event: AuditLogEvent
    let rawValue: Int

    static let all: [Self] = [
        .init(event: .guildUpdate, rawValue: 1),
        .init(event: .channelCreate, rawValue: 10),
        .init(event: .channelUpdate, rawValue: 11),
        .init(event: .channelDelete, rawValue: 12),
        .init(event: .channelOverwriteCreate, rawValue: 13),
        .init(event: .channelOverwriteUpdate, rawValue: 14),
        .init(event: .channelOverwriteDelete, rawValue: 15),
        .init(event: .memberKick, rawValue: 20),
        .init(event: .memberPrune, rawValue: 21),
        .init(event: .memberBanAdd, rawValue: 22),
        .init(event: .memberBanRemove, rawValue: 23),
        .init(event: .memberUpdate, rawValue: 24),
        .init(event: .memberRoleUpdate, rawValue: 25),
        .init(event: .memberMove, rawValue: 26),
        .init(event: .memberDisconnect, rawValue: 27),
        .init(event: .botAdd, rawValue: 28),
        .init(event: .roleCreate, rawValue: 30),
        .init(event: .roleUpdate, rawValue: 31),
        .init(event: .roleDelete, rawValue: 32),
        .init(event: .inviteCreate, rawValue: 40),
        .init(event: .inviteUpdate, rawValue: 41),
        .init(event: .inviteDelete, rawValue: 42),
        .init(event: .webhookCreate, rawValue: 50),
        .init(event: .webhookUpdate, rawValue: 51),
        .init(event: .webhookDelete, rawValue: 52),
        .init(event: .emojiCreate, rawValue: 60),
        .init(event: .emojiUpdate, rawValue: 61),
        .init(event: .emojiDelete, rawValue: 62),
        .init(event: .messageDelete, rawValue: 72),
        .init(event: .messageBulkDelete, rawValue: 73),
        .init(event: .messagePin, rawValue: 74),
        .init(event: .messageUnpin, rawValue: 75),
        .init(event: .integrationCreate, rawValue: 80),
        .init(event: .integrationUpdate, rawValue: 81),
        .init(event: .integrationDelete, rawValue: 82),
        .init(event: .stageInstanceCreate, rawValue: 83),
        .init(event: .stageInstanceUpdate, rawValue: 84),
        .init(event: .stageInstanceDelete, rawValue: 85),
        .init(event: .stickerCreate, rawValue: 90),
        .init(event: .stickerUpdate, rawValue: 91),
        .init(event: .stickerDelete, rawValue: 92),
        .init(event: .guildScheduledEventCreate, rawValue: 100),
        .init(event: .guildScheduledEventUpdate, rawValue: 101),
        .init(event: .guildScheduledEventDelete, rawValue: 102),
        .init(event: .threadCreate, rawValue: 110),
        .init(event: .threadUpdate, rawValue: 111),
        .init(event: .threadDelete, rawValue: 112),
        .init(event: .applicationCommandPermissionUpdate, rawValue: 121),
        .init(event: .soundboardSoundCreate, rawValue: 130),
        .init(event: .soundboardSoundUpdate, rawValue: 131),
        .init(event: .soundboardSoundDelete, rawValue: 132),
        .init(event: .autoModerationRuleCreate, rawValue: 140),
        .init(event: .autoModerationRuleUpdate, rawValue: 141),
        .init(event: .autoModerationRuleDelete, rawValue: 142),
        .init(event: .autoModerationBlockMessage, rawValue: 143),
        .init(event: .autoModerationFlagToChannel, rawValue: 144),
        .init(event: .autoModerationUserCommunicationDisabled, rawValue: 145),
        .init(event: .autoModerationQuarantineUser, rawValue: 146),
        .init(event: .creatorMonetizationRequestCreated, rawValue: 150),
        .init(event: .creatorMonetizationTermsAccepted, rawValue: 151),
        .init(event: .onboardingPromptCreate, rawValue: 163),
        .init(event: .onboardingPromptUpdate, rawValue: 164),
        .init(event: .onboardingPromptDelete, rawValue: 165),
        .init(event: .onboardingCreate, rawValue: 166),
        .init(event: .onboardingUpdate, rawValue: 167),
        .init(event: .guildHomeFeatureItem, rawValue: 171),
        .init(event: .guildHomeRemoveItem, rawValue: 172),
        .init(event: .harmfulLinksBlockedMessage, rawValue: 180),
        .init(event: .homeSettingsCreate, rawValue: 190),
        .init(event: .homeSettingsUpdate, rawValue: 191),
        .init(event: .voiceChannelStatusCreate, rawValue: 192),
        .init(event: .voiceChannelStatusDelete, rawValue: 193),
        .init(event: .guildScheduledEventExceptionCreate, rawValue: 200),
        .init(event: .guildScheduledEventExceptionUpdate, rawValue: 201),
        .init(event: .guildScheduledEventExceptionDelete, rawValue: 202),
        .init(event: .guildProfileUpdate, rawValue: 211),
    ]
}

private extension Field {
    /// Extracts present nested options for explicit value-presence regression assertions.
    /// - Returns: The associated value or nil for absent/null, without changing the original presence.
    var auditLogRegressionValue: Value? {
        if case .value(let value) = self { return value }
        return nil
    }
}
