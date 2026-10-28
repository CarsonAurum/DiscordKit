// File: Tests/DiscordModelsTests/AuditLogModelTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Deterministic bounded audit snapshots; no live requests, credentials, clocks or timing assumptions.
/// Related catalogs are exercised only through their explicitly partial audit projections.
@Suite struct AuditLogModelTests {
    /// Every public data initializer and internal bounded-tree initializer preserves exact known/unknown trees.
    /// Diagnostic formatting and reflection must conceal moderation reasons, tokens and future payload values.
    /// - Parameter fixture: A valid minimal and fully populated audit-owned object contract.
    /// - Throws: Unexpected parsing, projection or serialization failures fail the test.
    @Test(arguments: AuditLogModelFixture.all)
    fileprivate func exactTreesAndRedaction(fixture: AuditLogModelFixture) throws {
        for source in [fixture.minimal, fixture.populated] {
            let expected = try JSONValue.parse(source)
            let parsed = try fixture.parse(Data(source.utf8), .default)
            let projected = try fixture.project(expected, .default)
            #expect(parsed.jsonValue() == expected)
            #expect(projected.jsonValue() == expected)
            #expect(try parsed.jsonValue().serialized() == expected.serialized())
            #expect(!parsed.description.contains("private-"))
            #expect(!parsed.debugDescription.contains("private-"))
            #expect(!String(reflecting: parsed).contains("private-"))
            #expect(parsed.customMirror.children.count == 1)
            #expect(Mirror(reflecting: parsed).children.count == 1)
        }
    }

    /// Every modeled field distinguishes omission, permitted explicit null and present wrong-type values.
    /// Each malformed nested element must fail the entire projection through both public and subtree entry points.
    /// - Parameter fixture: One independent object with explicit optional/nullable/malformed field contracts.
    /// - Throws: Unexpected fixture transformations fail the test; known invalid-response errors are asserted.
    @Test(arguments: AuditLogModelFixture.all)
    fileprivate func presenceAndMalformedFields(fixture: AuditLogModelFixture) throws {
        let original = try #require(try JSONValue.parse(fixture.populated).auditLogObject)
        for field in fixture.fields {
            var changed = original
            changed[field.name] = nil
            if field.optional {
                #expect(try fixture.parse(JSONValue.object(changed).serialized(), .default).rawFields[field.name] == nil)
                #expect(try fixture.project(.object(changed), .default).rawFields[field.name] == nil)
            } else {
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try fixture.parse(JSONValue.object(changed).serialized(), .default)
                }
                #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.project(.object(changed), .default) }
            }
            changed[field.name] = .null
            if field.nullable {
                #expect(try fixture.parse(JSONValue.object(changed).serialized(), .default).rawFields[field.name] == .null)
                #expect(try fixture.project(.object(changed), .default).rawFields[field.name] == .null)
            } else {
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try fixture.parse(JSONValue.object(changed).serialized(), .default)
                }
                #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.project(.object(changed), .default) }
            }
            for invalid in field.invalid {
                changed[field.name] = try JSONValue.parse(invalid)
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try fixture.parse(JSONValue.object(changed).serialized(), .default)
                }
                #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.project(.object(changed), .default) }
            }
        }
    }

    /// Byte, depth and node limits cover every unknown subtree; invalid limits and malformed roots fail safely.
    /// Duplicate keys and trailing documents are rejected before projection, preventing ambiguous moderation data.
    /// - Parameter fixture: A populated object containing exact unknown numeric and string content.
    /// - Throws: Unexpected fixture failures fail the test; parser and schema failures are asserted.
    @Test(arguments: AuditLogModelFixture.all)
    fileprivate func parserBoundsSyntaxAndRoots(fixture: AuditLogModelFixture) throws {
        let bytes = Data(fixture.populated.utf8)
        #expect(throws: JSONValueError.maximumBytesExceeded) { try fixture.parse(bytes, JSONLimits(maximumBytes: 1)) }
        #expect(throws: JSONValueError.maximumDepthExceeded) { try fixture.parse(bytes, JSONLimits(maximumDepth: 1)) }
        #expect(throws: JSONValueError.maximumNodesExceeded) { try fixture.parse(bytes, JSONLimits(maximumNodes: 1)) }
        #expect(throws: JSONValueError.invalidLimits) { try fixture.parse(bytes, JSONLimits(maximumBytes: 0)) }
        for invalid in ["{", "{\"key\":1,\"key\":2}", fixture.minimal + " {}"] {
            #expect(throws: JSONValueError.self) { try fixture.parse(Data(invalid.utf8), .default) }
        }
        for invalid in ["[]", "null", "true", "1", #""private-root""#] {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.parse(Data(invalid.utf8), .default) }
            #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.project(JSONValue.parse(invalid), .default) }
        }
    }

    /// Typed AuditLogChange properties expose the populated wire values rather than normalized or inferred defaults.
    /// Unknown action/provider/type variants, exact identifiers and partial nested snapshots remain available.
    /// - Throws: Unexpected fixture parsing fails the test; every projected property is asserted.
    @Test func auditLogChangeTypedProperties() throws {
        let model = try AuditLogChange(data: Data(AuditLogModelFixture.all[0].populated.utf8))
        #expect(model.key == .value("private-key"))
        #expect(model.newValue == .value(try JSONValue.parse(#"{"number":1.230000000000000000001e1000,"text":"private-future"}"#)))
        #expect(model.oldValue == .value(try JSONValue.parse(#"{"number":1.230000000000000000001e1000,"text":"private-future"}"#)))
    }

    /// Typed AuditLogEntryOptions properties expose the populated wire values rather than normalized or inferred defaults.
    /// Unknown action/provider/type variants, exact identifiers and partial nested snapshots remain available.
    /// - Throws: Unexpected fixture parsing fails the test; every projected property is asserted.
    @Test func auditLogEntryOptionsTypedProperties() throws {
        let model = try AuditLogEntryOptions(data: Data(AuditLogModelFixture.all[1].populated.utf8))
        #expect(model.applicationID == .value(ApplicationID(rawValue: UInt64.max)))
        #expect(model.autoModerationRuleName == .value("private-auto_moderation_rule_name"))
        #expect(model.autoModerationRuleTriggerType == .value("private-auto_moderation_rule_trigger_type"))
        #expect(model.channelID == .value(ChannelID(rawValue: UInt64.max)))
        #expect(model.count == .value("1844674407370955161518446744073709551615"))
        #expect(model.deleteMemberDays == .value("1844674407370955161518446744073709551615"))
        #expect(model.id == .value(ChannelOverwriteTargetID(rawValue: UInt64.max)))
        #expect(model.membersRemoved == .value("1844674407370955161518446744073709551615"))
        #expect(model.messageID == .value(MessageID(rawValue: UInt64.max)))
        #expect(model.roleName == .value("private-role_name"))
        #expect(model.type == .value("private-type"))
        #expect(model.integrationType == .value("private-integration_type"))
        #expect(model.status == .value("private-status"))
    }

    /// Typed AuditLogEntry properties expose the populated wire values rather than normalized or inferred defaults.
    /// Unknown action/provider/type variants, exact identifiers and partial nested snapshots remain available.
    /// - Throws: Unexpected fixture parsing fails the test; every projected property is asserted.
    @Test func auditLogEntryTypedProperties() throws {
        let model = try AuditLogEntry(data: Data(AuditLogModelFixture.all[2].populated.utf8))
        #expect(model.targetID == .value("opaque:non-snowflake/target"))
        let changes = try #require(model.changes.auditLogValue)
        #expect(changes.count == 1)
        #expect(changes.first?.jsonValue() == model.rawFields["changes"]?.auditLogArray?.first)
        #expect(model.userID == .value(UserID(rawValue: UInt64.max)))
        #expect(model.id == AuditLogEntryID(rawValue: UInt64.max))
        #expect(model.actionType == RawValue(rawValue: 9876))
        #expect(model.options.auditLogValue?.jsonValue() == model.rawFields["options"])
        #expect(model.reason == .value("private-reason"))
    }

    /// Typed AuditLogIntegration properties expose the populated wire values rather than normalized or inferred defaults.
    /// Unknown action/provider/type variants, exact identifiers and partial nested snapshots remain available.
    /// - Throws: Unexpected fixture parsing fails the test; every projected property is asserted.
    @Test func auditLogIntegrationTypedProperties() throws {
        let model = try AuditLogIntegration(data: Data(AuditLogModelFixture.all[3].populated.utf8))
        #expect(model.id == GuildIntegrationID(rawValue: UInt64.max))
        #expect(model.name == .value("private-name"))
        #expect(model.type == RawValue(rawValue: "FUTURE_PROVIDER"))
        #expect(model.account.jsonValue() == model.rawFields["account"])
        #expect(model.applicationID == .value(ApplicationID(rawValue: UInt64.max)))
    }

    /// Typed AuditLogApplicationCommand properties expose the populated wire values rather than normalized or inferred defaults.
    /// Unknown action/provider/type variants, exact identifiers and partial nested snapshots remain available.
    /// - Throws: Unexpected fixture parsing fails the test; every projected property is asserted.
    @Test func auditLogApplicationCommandTypedProperties() throws {
        let model = try AuditLogApplicationCommand(data: Data(AuditLogModelFixture.all[4].populated.utf8))
        #expect(model.id == ApplicationCommandID(rawValue: UInt64.max))
        #expect(model.applicationID == .value(ApplicationID(rawValue: UInt64.max)))
        #expect(model.guildID == .value(GuildID(rawValue: UInt64.max)))
        #expect(model.name == .value("private-name"))
        #expect(model.type == .value(9876))
        #expect(model.commandDescription == .value("private-description"))
    }

    /// Typed AuditLogScheduledEvent properties expose the populated wire values rather than normalized or inferred defaults.
    /// Unknown action/provider/type variants, exact identifiers and partial nested snapshots remain available.
    /// - Throws: Unexpected fixture parsing fails the test; every projected property is asserted.
    @Test func auditLogScheduledEventTypedProperties() throws {
        let model = try AuditLogScheduledEvent(data: Data(AuditLogModelFixture.all[5].populated.utf8))
        #expect(model.id == GuildScheduledEventID(rawValue: UInt64.max))
        #expect(model.guildID == .value(GuildID(rawValue: UInt64.max)))
        #expect(model.channelID == .value(ChannelID(rawValue: UInt64.max)))
        #expect(model.name == .value("private-name"))
        #expect(model.entityType == .value(9876))
        #expect(model.status == .value(9876))
    }

    /// Typed AuditLogWebhook properties expose the populated wire values rather than normalized or inferred defaults.
    /// Unknown action/provider/type variants, exact identifiers and partial nested snapshots remain available.
    /// - Throws: Unexpected fixture parsing fails the test; every projected property is asserted.
    @Test func auditLogWebhookTypedProperties() throws {
        let model = try AuditLogWebhook(data: Data(AuditLogModelFixture.all[6].populated.utf8))
        #expect(model.id == WebhookID(rawValue: UInt64.max))
        #expect(model.type == .value(9876))
        #expect(model.guildID == .value(GuildID(rawValue: UInt64.max)))
        #expect(model.channelID == .value(ChannelID(rawValue: UInt64.max)))
        #expect(model.name == .value("private-name"))
        #expect(model.avatar == .value("private-avatar"))
        #expect(model.applicationID == .value(ApplicationID(rawValue: UInt64.max)))
    }

    /// Typed AuditLog properties expose the populated wire values rather than normalized or inferred defaults.
    /// Unknown action/provider/type variants, exact identifiers and partial nested snapshots remain available.
    /// - Throws: Unexpected fixture parsing fails the test; every projected property is asserted.
    @Test func auditLogTypedProperties() throws {
        let model = try AuditLog(data: Data(AuditLogModelFixture.all[7].populated.utf8))
        #expect(model.applicationCommands.count == 1)
        #expect(model.applicationCommands.first?.jsonValue() == model.rawFields["application_commands"]?.auditLogArray?.first)
        #expect(model.auditLogEntries.count == 1)
        #expect(model.auditLogEntries.first?.jsonValue() == model.rawFields["audit_log_entries"]?.auditLogArray?.first)
        #expect(model.autoModerationRules.count == 2)
        #expect(model.autoModerationRules.first == .null)
        let autoModerationRulesValue = try #require(model.autoModerationRules.last?.auditLogNullableValue)
        #expect(autoModerationRulesValue.id.rawValue == UInt64.max)
        #expect(model.guildScheduledEvents.count == 1)
        #expect(model.guildScheduledEvents.first?.jsonValue() == model.rawFields["guild_scheduled_events"]?.auditLogArray?.first)
        #expect(model.integrations.count == 1)
        #expect(model.integrations.first?.jsonValue() == model.rawFields["integrations"]?.auditLogArray?.first)
        #expect(model.threads.count == 1)
        #expect(model.threads.first?.jsonValue() == model.rawFields["threads"]?.auditLogArray?.first)
        #expect(model.users.count == 1)
        #expect(model.users.first?.jsonValue() == model.rawFields["users"]?.auditLogArray?.first)
        #expect(model.webhooks.count == 1)
        #expect(model.webhooks.first?.jsonValue() == model.rawFields["webhooks"]?.auditLogArray?.first)
    }

    /// Minimal AuditLogChange snapshots expose absent optional fields and required nulls without inventing defaults.
    /// Allowed nullable properties preserve explicit null even when other fields remain populated.
    /// - Throws: Unexpected fixture parsing or exact tree serialization fails the test.
    @Test func auditLogChangePresenceStates() throws {
        let minimal = try AuditLogChange(data: Data(AuditLogModelFixture.all[0].minimal.utf8))
        #expect(minimal.key == .null)
        #expect(minimal.newValue == .absent)
        #expect(minimal.oldValue == .absent)
        var fields = try #require(try JSONValue.parse(AuditLogModelFixture.all[0].populated).auditLogObject)
        fields["key"] = .null
        fields["new_value"] = .null
        fields["old_value"] = .null
        let nulls = try AuditLogChange(data: JSONValue.object(fields).serialized())
        #expect(nulls.key == .null)
        #expect(nulls.newValue == .null)
        #expect(nulls.oldValue == .null)
    }

    /// Minimal AuditLogEntryOptions snapshots expose absent optional fields and required nulls without inventing defaults.
    /// Allowed nullable properties preserve explicit null even when other fields remain populated.
    /// - Throws: Unexpected fixture parsing or exact tree serialization fails the test.
    @Test func auditLogEntryOptionsPresenceStates() throws {
        let minimal = try AuditLogEntryOptions(data: Data(AuditLogModelFixture.all[1].minimal.utf8))
        #expect(minimal.applicationID == .absent)
        #expect(minimal.autoModerationRuleName == .absent)
        #expect(minimal.autoModerationRuleTriggerType == .absent)
        #expect(minimal.channelID == .absent)
        #expect(minimal.count == .absent)
        #expect(minimal.deleteMemberDays == .absent)
        #expect(minimal.id == .absent)
        #expect(minimal.membersRemoved == .absent)
        #expect(minimal.messageID == .absent)
        #expect(minimal.roleName == .absent)
        #expect(minimal.type == .absent)
        #expect(minimal.integrationType == .absent)
        #expect(minimal.status == .absent)
    }

    /// Minimal AuditLogEntry snapshots expose absent optional fields and required nulls without inventing defaults.
    /// Allowed nullable properties preserve explicit null even when other fields remain populated.
    /// - Throws: Unexpected fixture parsing or exact tree serialization fails the test.
    @Test func auditLogEntryPresenceStates() throws {
        let minimal = try AuditLogEntry(data: Data(AuditLogModelFixture.all[2].minimal.utf8))
        #expect(minimal.targetID == .null)
        #expect(minimal.changes == .absent)
        #expect(minimal.userID == .null)
        #expect(minimal.options == .absent)
        #expect(minimal.reason == .absent)
        var fields = try #require(try JSONValue.parse(AuditLogModelFixture.all[2].populated).auditLogObject)
        fields["target_id"] = .null
        fields["user_id"] = .null
        let nulls = try AuditLogEntry(data: JSONValue.object(fields).serialized())
        #expect(nulls.targetID == .null)
        #expect(nulls.userID == .null)
    }

    /// Minimal AuditLogIntegration snapshots expose absent optional fields and required nulls without inventing defaults.
    /// Allowed nullable properties preserve explicit null even when other fields remain populated.
    /// - Throws: Unexpected fixture parsing or exact tree serialization fails the test.
    @Test func auditLogIntegrationPresenceStates() throws {
        let minimal = try AuditLogIntegration(data: Data(AuditLogModelFixture.all[3].minimal.utf8))
        #expect(minimal.name == .null)
        #expect(minimal.applicationID == .absent)
        var fields = try #require(try JSONValue.parse(AuditLogModelFixture.all[3].populated).auditLogObject)
        fields["name"] = .null
        let nulls = try AuditLogIntegration(data: JSONValue.object(fields).serialized())
        #expect(nulls.name == .null)
    }

    /// Minimal AuditLogApplicationCommand snapshots expose absent optional fields and required nulls without inventing defaults.
    /// Allowed nullable properties preserve explicit null even when other fields remain populated.
    /// - Throws: Unexpected fixture parsing or exact tree serialization fails the test.
    @Test func auditLogApplicationCommandPresenceStates() throws {
        let minimal = try AuditLogApplicationCommand(data: Data(AuditLogModelFixture.all[4].minimal.utf8))
        #expect(minimal.applicationID == .absent)
        #expect(minimal.guildID == .absent)
        #expect(minimal.name == .absent)
        #expect(minimal.type == .absent)
        #expect(minimal.commandDescription == .absent)
    }

    /// Minimal AuditLogScheduledEvent snapshots expose absent optional fields and required nulls without inventing defaults.
    /// Allowed nullable properties preserve explicit null even when other fields remain populated.
    /// - Throws: Unexpected fixture parsing or exact tree serialization fails the test.
    @Test func auditLogScheduledEventPresenceStates() throws {
        let minimal = try AuditLogScheduledEvent(data: Data(AuditLogModelFixture.all[5].minimal.utf8))
        #expect(minimal.guildID == .absent)
        #expect(minimal.channelID == .absent)
        #expect(minimal.name == .absent)
        #expect(minimal.entityType == .absent)
        #expect(minimal.status == .absent)
        var fields = try #require(try JSONValue.parse(AuditLogModelFixture.all[5].populated).auditLogObject)
        fields["channel_id"] = .null
        let nulls = try AuditLogScheduledEvent(data: JSONValue.object(fields).serialized())
        #expect(nulls.channelID == .null)
    }

    /// Minimal AuditLogWebhook snapshots expose absent optional fields and required nulls without inventing defaults.
    /// Allowed nullable properties preserve explicit null even when other fields remain populated.
    /// - Throws: Unexpected fixture parsing or exact tree serialization fails the test.
    @Test func auditLogWebhookPresenceStates() throws {
        let minimal = try AuditLogWebhook(data: Data(AuditLogModelFixture.all[6].minimal.utf8))
        #expect(minimal.type == .absent)
        #expect(minimal.guildID == .absent)
        #expect(minimal.channelID == .absent)
        #expect(minimal.name == .absent)
        #expect(minimal.avatar == .absent)
        #expect(minimal.applicationID == .absent)
        var fields = try #require(try JSONValue.parse(AuditLogModelFixture.all[6].populated).auditLogObject)
        fields["channel_id"] = .null
        fields["name"] = .null
        fields["avatar"] = .null
        fields["application_id"] = .null
        let nulls = try AuditLogWebhook(data: JSONValue.object(fields).serialized())
        #expect(nulls.channelID == .null)
        #expect(nulls.name == .null)
        #expect(nulls.avatar == .null)
        #expect(nulls.applicationID == .null)
    }

    /// Minimal AuditLog snapshots expose absent optional fields and required nulls without inventing defaults.
    /// Allowed nullable properties preserve explicit null even when other fields remain populated.
    /// - Throws: Unexpected fixture parsing or exact tree serialization fails the test.
    @Test func auditLogPresenceStates() throws {
        let minimal = try AuditLog(data: Data(AuditLogModelFixture.all[7].minimal.utf8))
        #expect(minimal.applicationCommands.isEmpty)
        #expect(minimal.auditLogEntries.isEmpty)
        #expect(minimal.autoModerationRules.isEmpty)
        #expect(minimal.guildScheduledEvents.isEmpty)
        #expect(minimal.integrations.isEmpty)
        #expect(minimal.threads.isEmpty)
        #expect(minimal.users.isEmpty)
        #expect(minimal.webhooks.isEmpty)
    }
}

/// Exact fixture field contract; malformed examples include schema, numeric and nested-element violations.
private struct AuditLogFieldFixture: Sendable {
    let name: String
    let optional: Bool
    let nullable: Bool
    let invalid: [String]
}

/// Type-erased immutable fixture lets the same independently asserted schema matrix exercise all audit objects.
private struct AuditLogModelFixture: Sendable {
    let name: String
    let minimal: String
    let populated: String
    let fields: [AuditLogFieldFixture]
    let parse: @Sendable (Data, JSONLimits) throws -> any MessageResponseValue
    let project: @Sendable (JSONValue, JSONLimits) throws -> any MessageResponseValue

    static let all: [Self] = [
        .init(name: "AuditLogChange",
              minimal: #"{"key":null}"#,
              populated: #"{"key":"private-key","new_value":{"number":1.230000000000000000001e1000,"text":"private-future"},"old_value":{"number":1.230000000000000000001e1000,"text":"private-future"},"future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}}"#,
              fields: [
                .init(name: "key", optional: false, nullable: true, invalid: [#"true"#, #"1"#, #"{}"#, #"[]"#]),
                .init(name: "new_value", optional: true, nullable: true, invalid: []),
                .init(name: "old_value", optional: true, nullable: true, invalid: []),
              ],
              parse: { try AuditLogChange(data: $0, limits: $1) },
              project: { try AuditLogChange(value: $0, limits: $1) }),
        .init(name: "AuditLogEntryOptions",
              minimal: #"{}"#,
              populated: #"{"application_id":"18446744073709551615","auto_moderation_rule_name":"private-auto_moderation_rule_name","auto_moderation_rule_trigger_type":"private-auto_moderation_rule_trigger_type","channel_id":"18446744073709551615","count":"1844674407370955161518446744073709551615","delete_member_days":"1844674407370955161518446744073709551615","id":"18446744073709551615","members_removed":"1844674407370955161518446744073709551615","message_id":"18446744073709551615","role_name":"private-role_name","type":"private-type","integration_type":"private-integration_type","status":"private-status","future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}}"#,
              fields: [
                .init(name: "application_id", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #""""#, #""-1""#, #""1.0""#, #""18446744073709551616""#, #""private-id""#]),
                .init(name: "auto_moderation_rule_name", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #"{}"#, #"[]"#]),
                .init(name: "auto_moderation_rule_trigger_type", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #"{}"#, #"[]"#]),
                .init(name: "channel_id", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #""""#, #""-1""#, #""1.0""#, #""18446744073709551616""#, #""private-id""#]),
                .init(name: "count", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #"{}"#, #"[]"#]),
                .init(name: "delete_member_days", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #"{}"#, #"[]"#]),
                .init(name: "id", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #""""#, #""-1""#, #""1.0""#, #""18446744073709551616""#, #""private-id""#]),
                .init(name: "members_removed", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #"{}"#, #"[]"#]),
                .init(name: "message_id", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #""""#, #""-1""#, #""1.0""#, #""18446744073709551616""#, #""private-id""#]),
                .init(name: "role_name", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #"{}"#, #"[]"#]),
                .init(name: "type", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #"{}"#, #"[]"#]),
                .init(name: "integration_type", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #"{}"#, #"[]"#]),
                .init(name: "status", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #"{}"#, #"[]"#]),
              ],
              parse: { try AuditLogEntryOptions(data: $0, limits: $1) },
              project: { try AuditLogEntryOptions(value: $0, limits: $1) }),
        .init(name: "AuditLogEntry",
              minimal: #"{"target_id":null,"user_id":null,"id":"18446744073709551615","action_type":9876}"#,
              populated: #"{"target_id":"opaque:non-snowflake/target","changes":[{"key":"private-key","new_value":{"number":1.230000000000000000001e1000,"text":"private-future"},"old_value":{"number":1.230000000000000000001e1000,"text":"private-future"},"future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}}],"user_id":"18446744073709551615","id":"18446744073709551615","action_type":9876,"options":{"application_id":"18446744073709551615","auto_moderation_rule_name":"private-auto_moderation_rule_name","auto_moderation_rule_trigger_type":"private-auto_moderation_rule_trigger_type","channel_id":"18446744073709551615","count":"1844674407370955161518446744073709551615","delete_member_days":"1844674407370955161518446744073709551615","id":"18446744073709551615","members_removed":"1844674407370955161518446744073709551615","message_id":"18446744073709551615","role_name":"private-role_name","type":"private-type","integration_type":"private-integration_type","status":"private-status","future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}},"reason":"private-reason","future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}}"#,
              fields: [
                .init(name: "target_id", optional: false, nullable: true, invalid: [#"true"#, #"1"#, #"{}"#, #"[]"#]),
                .init(name: "changes", optional: true, nullable: false, invalid: [#"false"#, #"{}"#, #"[false]"#, #"[{}]"#, #"[null]"#]),
                .init(name: "user_id", optional: false, nullable: true, invalid: [#"true"#, #"1"#, #""""#, #""-1""#, #""1.0""#, #""18446744073709551616""#, #""private-id""#]),
                .init(name: "id", optional: false, nullable: false, invalid: [#"true"#, #"1"#, #""""#, #""-1""#, #""1.0""#, #""18446744073709551616""#, #""private-id""#]),
                .init(name: "action_type", optional: false, nullable: false, invalid: [#"true"#, #""1""#, #"1.0"#, #"1e0"#, #"1.000000000000000000001"#, #"9223372036854775808"#]),
                .init(name: "options", optional: true, nullable: false, invalid: [#"false"#, #"[]"#]),
                .init(name: "reason", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #"{}"#, #"[]"#]),
              ],
              parse: { try AuditLogEntry(data: $0, limits: $1) },
              project: { try AuditLogEntry(value: $0, limits: $1) }),
        .init(name: "AuditLogIntegration",
              minimal: #"{"id":"18446744073709551615","name":null,"type":"FUTURE_PROVIDER","account":{"id":"provider:external/private","name":"private-account","future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}}}"#,
              populated: #"{"id":"18446744073709551615","name":"private-name","type":"FUTURE_PROVIDER","account":{"id":"provider:external/private","name":"private-account","future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}},"application_id":"18446744073709551615","future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}}"#,
              fields: [
                .init(name: "id", optional: false, nullable: false, invalid: [#"true"#, #"1"#, #""""#, #""-1""#, #""1.0""#, #""18446744073709551616""#, #""private-id""#]),
                .init(name: "name", optional: false, nullable: true, invalid: [#"true"#, #"1"#, #"{}"#, #"[]"#]),
                .init(name: "type", optional: false, nullable: false, invalid: [#"true"#, #"1"#, #"{}"#, #"[]"#]),
                .init(name: "account", optional: false, nullable: false, invalid: [#"false"#, #"[]"#, #"{}"#]),
                .init(name: "application_id", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #""""#, #""-1""#, #""1.0""#, #""18446744073709551616""#, #""private-id""#]),
              ],
              parse: { try AuditLogIntegration(data: $0, limits: $1) },
              project: { try AuditLogIntegration(value: $0, limits: $1) }),
        .init(name: "AuditLogApplicationCommand",
              minimal: #"{"id":"18446744073709551615"}"#,
              populated: #"{"id":"18446744073709551615","application_id":"18446744073709551615","guild_id":"18446744073709551615","name":"private-name","type":9876,"description":"private-description","future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}}"#,
              fields: [
                .init(name: "id", optional: false, nullable: false, invalid: [#"true"#, #"1"#, #""""#, #""-1""#, #""1.0""#, #""18446744073709551616""#, #""private-id""#]),
                .init(name: "application_id", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #""""#, #""-1""#, #""1.0""#, #""18446744073709551616""#, #""private-id""#]),
                .init(name: "guild_id", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #""""#, #""-1""#, #""1.0""#, #""18446744073709551616""#, #""private-id""#]),
                .init(name: "name", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #"{}"#, #"[]"#]),
                .init(name: "type", optional: true, nullable: false, invalid: [#"true"#, #""1""#, #"1.0"#, #"1e0"#, #"1.000000000000000000001"#, #"9223372036854775808"#]),
                .init(name: "description", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #"{}"#, #"[]"#]),
              ],
              parse: { try AuditLogApplicationCommand(data: $0, limits: $1) },
              project: { try AuditLogApplicationCommand(value: $0, limits: $1) }),
        .init(name: "AuditLogScheduledEvent",
              minimal: #"{"id":"18446744073709551615"}"#,
              populated: #"{"id":"18446744073709551615","guild_id":"18446744073709551615","channel_id":"18446744073709551615","name":"private-name","entity_type":9876,"status":9876,"future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}}"#,
              fields: [
                .init(name: "id", optional: false, nullable: false, invalid: [#"true"#, #"1"#, #""""#, #""-1""#, #""1.0""#, #""18446744073709551616""#, #""private-id""#]),
                .init(name: "guild_id", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #""""#, #""-1""#, #""1.0""#, #""18446744073709551616""#, #""private-id""#]),
                .init(name: "channel_id", optional: true, nullable: true, invalid: [#"true"#, #"1"#, #""""#, #""-1""#, #""1.0""#, #""18446744073709551616""#, #""private-id""#]),
                .init(name: "name", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #"{}"#, #"[]"#]),
                .init(name: "entity_type", optional: true, nullable: false, invalid: [#"true"#, #""1""#, #"1.0"#, #"1e0"#, #"1.000000000000000000001"#, #"9223372036854775808"#]),
                .init(name: "status", optional: true, nullable: false, invalid: [#"true"#, #""1""#, #"1.0"#, #"1e0"#, #"1.000000000000000000001"#, #"9223372036854775808"#]),
              ],
              parse: { try AuditLogScheduledEvent(data: $0, limits: $1) },
              project: { try AuditLogScheduledEvent(value: $0, limits: $1) }),
        .init(name: "AuditLogWebhook",
              minimal: #"{"id":"18446744073709551615"}"#,
              populated: #"{"id":"18446744073709551615","type":9876,"guild_id":"18446744073709551615","channel_id":"18446744073709551615","name":"private-name","avatar":"private-avatar","application_id":"18446744073709551615","future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}}"#,
              fields: [
                .init(name: "id", optional: false, nullable: false, invalid: [#"true"#, #"1"#, #""""#, #""-1""#, #""1.0""#, #""18446744073709551616""#, #""private-id""#]),
                .init(name: "type", optional: true, nullable: false, invalid: [#"true"#, #""1""#, #"1.0"#, #"1e0"#, #"1.000000000000000000001"#, #"9223372036854775808"#]),
                .init(name: "guild_id", optional: true, nullable: false, invalid: [#"true"#, #"1"#, #""""#, #""-1""#, #""1.0""#, #""18446744073709551616""#, #""private-id""#]),
                .init(name: "channel_id", optional: true, nullable: true, invalid: [#"true"#, #"1"#, #""""#, #""-1""#, #""1.0""#, #""18446744073709551616""#, #""private-id""#]),
                .init(name: "name", optional: true, nullable: true, invalid: [#"true"#, #"1"#, #"{}"#, #"[]"#]),
                .init(name: "avatar", optional: true, nullable: true, invalid: [#"true"#, #"1"#, #"{}"#, #"[]"#]),
                .init(name: "application_id", optional: true, nullable: true, invalid: [#"true"#, #"1"#, #""""#, #""-1""#, #""1.0""#, #""18446744073709551616""#, #""private-id""#]),
              ],
              parse: { try AuditLogWebhook(data: $0, limits: $1) },
              project: { try AuditLogWebhook(value: $0, limits: $1) }),
        .init(name: "AuditLog",
              minimal: #"{"application_commands":[],"audit_log_entries":[],"auto_moderation_rules":[],"guild_scheduled_events":[],"integrations":[],"threads":[],"users":[],"webhooks":[]}"#,
              populated: #"{"application_commands":[{"id":"18446744073709551615","application_id":"18446744073709551615","guild_id":"18446744073709551615","name":"private-name","type":9876,"description":"private-description","future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}}],"audit_log_entries":[{"target_id":"opaque:non-snowflake/target","changes":[{"key":"private-key","new_value":{"number":1.230000000000000000001e1000,"text":"private-future"},"old_value":{"number":1.230000000000000000001e1000,"text":"private-future"},"future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}}],"user_id":"18446744073709551615","id":"18446744073709551615","action_type":9876,"options":{"application_id":"18446744073709551615","auto_moderation_rule_name":"private-auto_moderation_rule_name","auto_moderation_rule_trigger_type":"private-auto_moderation_rule_trigger_type","channel_id":"18446744073709551615","count":"1844674407370955161518446744073709551615","delete_member_days":"1844674407370955161518446744073709551615","id":"18446744073709551615","members_removed":"1844674407370955161518446744073709551615","message_id":"18446744073709551615","role_name":"private-role_name","type":"private-type","integration_type":"private-integration_type","status":"private-status","future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}},"reason":"private-reason","future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}}],"auto_moderation_rules":[null,{"id":"18446744073709551615","guild_id":"18446744073709551615","name":"private-rule","creator_id":"18446744073709551615","event_type":9876,"trigger_type":9876,"trigger_metadata":{},"actions":[{"type":9876}],"enabled":true,"exempt_roles":[],"exempt_channels":[],"future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}}],"guild_scheduled_events":[{"id":"18446744073709551615","guild_id":"18446744073709551615","channel_id":"18446744073709551615","name":"private-name","entity_type":9876,"status":9876,"future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}}],"integrations":[{"id":"18446744073709551615","name":"private-name","type":"FUTURE_PROVIDER","account":{"id":"provider:external/private","name":"private-account","future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}},"application_id":"18446744073709551615","future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}}],"threads":[{"id":"18446744073709551615","type":11,"name":"private-thread","future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}}],"users":[{"id":"18446744073709551615","username":"private-user","avatar":null,"future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}}],"webhooks":[{"id":"18446744073709551615","type":9876,"guild_id":"18446744073709551615","channel_id":"18446744073709551615","name":"private-name","avatar":"private-avatar","application_id":"18446744073709551615","future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}}],"future_secret":{"number":1.230000000000000000001e1000,"text":"private-future"}}"#,
              fields: [
                .init(name: "application_commands", optional: false, nullable: false, invalid: [#"false"#, #"{}"#, #"[false]"#, #"[{}]"#, #"[null]"#]),
                .init(name: "audit_log_entries", optional: false, nullable: false, invalid: [#"false"#, #"{}"#, #"[false]"#, #"[{}]"#, #"[null]"#]),
                .init(name: "auto_moderation_rules", optional: false, nullable: false, invalid: [#"false"#, #"{}"#, #"[false]"#, #"[{}]"#]),
                .init(name: "guild_scheduled_events", optional: false, nullable: false, invalid: [#"false"#, #"{}"#, #"[false]"#, #"[{}]"#, #"[null]"#]),
                .init(name: "integrations", optional: false, nullable: false, invalid: [#"false"#, #"{}"#, #"[false]"#, #"[{}]"#, #"[null]"#]),
                .init(name: "threads", optional: false, nullable: false, invalid: [#"false"#, #"{}"#, #"[false]"#, #"[{}]"#, #"[null]"#]),
                .init(name: "users", optional: false, nullable: false, invalid: [#"false"#, #"{}"#, #"[false]"#, #"[{}]"#, #"[null]"#]),
                .init(name: "webhooks", optional: false, nullable: false, invalid: [#"false"#, #"{}"#, #"[false]"#, #"[{}]"#, #"[null]"#]),
              ],
              parse: { try AuditLog(data: $0, limits: $1) },
              project: { try AuditLog(value: $0, limits: $1) }),
    ]
}

private extension JSONValue {
    /// Extracts an object for deterministic fixture mutation without a Codable or Foundation conversion.
    /// - Returns: Original exact fields, or nil for another JSON kind; no normalization or side effects occur.
    var auditLogObject: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// Extracts an ordered exact array for direct nested projection comparison.
    /// - Returns: Original elements or nil for a nonarray value, preserving every null and numeric lexeme.
    var auditLogArray: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
}

private extension Field {
    /// Extracts a present fixture value while keeping assertions on absence and explicit null deliberate.
    /// - Returns: The associated value, or nil for absent/null; test callers assert presence before use.
    var auditLogValue: Value? {
        if case .value(let value) = self { return value }
        return nil
    }
}

private extension Nullable {
    /// Extracts a required nullable fixture value for typed property assertions.
    /// - Returns: The associated value, or nil only for explicit null; no wire-state mutation occurs.
    var auditLogNullableValue: Value? {
        if case .value(let value) = self { return value }
        return nil
    }
}
