// File: Tests/DiscordModelsTests/AutoModerationRequestTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Local request validation tests cover explicit wire construction, every trigger/action association,
/// published boundaries, preview nulls and secret-safe diagnostics without network or credentials.
@Suite struct AutoModerationRequestTests {
    /// Complete create and modify bodies preserve exact snowflakes, action order and current trigger context.
    /// - Throws: Unexpected request construction or fixture validation fails the test.
    @Test func completeBodiesAndContext() throws {
        let metadata = try AutoModerationTriggerMetadataRequest(triggerType: .keyword,
            keywordFilter: .value(["*private*"]), regexPatterns: .value(["(?i)private"]), allowList: .value(["allowed"]))
        let actions = try [AutoModerationActionRequest(type: .blockMessage, customMessage: .value("private-explanation")),
            AutoModerationActionRequest(type: .sendAlertMessage, channelID: .value(.init(rawValue: .max))),
            AutoModerationActionRequest(type: .timeout, durationSeconds: .value(2_419_200))]
        let create = try AutoModerationCreateRequest(name: "private-rule", eventType: .messageSend, triggerType: .keyword,
            triggerMetadata: .value(metadata), actions: actions, enabled: .value(false),
            exemptRoles: .value([.init(rawValue: .max), .init(rawValue: 0)]), exemptChannels: .value([.init(rawValue: .max)]))
        let expected: [String: JSONValue] = ["name": .string("private-rule"), "event_type": number(1),
            "trigger_type": number(1), "trigger_metadata": metadata.jsonValue(), "actions": .array(actions.map { $0.jsonValue() }),
            "enabled": .bool(false), "exempt_roles": .array([.string("18446744073709551615"), .string("0")]),
            "exempt_channels": .array([.string("18446744073709551615")])]
        #expect(create.jsonValue() == .object(expected))
        let modify = try AutoModerationModifyRequest(triggerType: .keyword, name: .value("private-rule"),
            eventType: .value(.messageSend), triggerMetadata: .value(metadata), actions: .value(actions), enabled: .value(false),
            exemptRoles: .value([.init(rawValue: .max), .init(rawValue: 0)]), exemptChannels: .value([.init(rawValue: .max)]))
        var modifiedExpected = expected
        modifiedExpected["trigger_type"] = nil
        #expect(modify.triggerType == .keyword)
        #expect(modify.jsonValue() == .object(modifiedExpected))
        for payload: any GuildRequestPayload in [metadata, actions[0], create, modify] {
            #expect(!payload.description.contains("private-"))
            #expect(payload.debugDescription == payload.description)
            #expect(!String(reflecting: payload).contains("private-"))
            #expect(payload.customMirror.children.count == 1)
            #expect(try JSONValue.parse(payload.jsonValue().serialized()) == payload.jsonValue())
            #expect(payload.jsonValue() == payload.jsonValue())
        }
    }

    /// Each known trigger permits an empty metadata object and zero-change PATCH without inserting context.
    /// - Parameter trigger: Every published trigger kind, including spam with no metadata fields.
    /// - Throws: Unexpected request construction fails the test.
    @Test(arguments: AutoModerationTriggerType.allCases)
    func allTriggerDefaults(_ trigger: AutoModerationTriggerType) throws {
        let metadata = try AutoModerationTriggerMetadataRequest(triggerType: trigger)
        #expect(metadata.triggerType == trigger)
        #expect(metadata.jsonValue() == .object([:]))
        let modify = try AutoModerationModifyRequest(triggerType: trigger)
        #expect(modify.triggerType == trigger)
        #expect(modify.jsonValue() == .object([:]))
        let action = try AutoModerationActionRequest(type: trigger == .memberProfile ? .blockMemberInteraction : .blockMessage)
        let create = try AutoModerationCreateRequest(name: "", eventType: .memberUpdate, triggerType: trigger,
            triggerMetadata: .value(metadata), actions: [action])
        #expect(create.jsonValue() == .object(["name": .string(""), "event_type": number(2),
            "trigger_type": number(trigger.rawValue), "trigger_metadata": .object([:]), "actions": .array([action.jsonValue()])]))
    }

    /// Optional nullable request fields preserve explicit null rather than inventing empty arrays or defaults.
    /// - Throws: Unexpected constructor or serialization failures fail the test.
    @Test func previewNullabilityAndOmission() throws {
        let action = try AutoModerationActionRequest(type: .blockMessage)
        #expect(action.jsonValue() == .object(["type": number(1)]))
        #expect(try AutoModerationActionRequest(type: .blockMemberInteraction).jsonValue() == .object(["type": number(4)]))
        #expect(try AutoModerationActionRequest(type: .blockMessage, customMessage: .null).jsonValue() ==
            .object(["type": number(1), "metadata": .object(["custom_message": .null])]))
        for trigger in [AutoModerationTriggerType.keyword, .spam, .mentionSpam] {
            let create = try AutoModerationCreateRequest(name: "rule", eventType: .messageSend, triggerType: trigger,
                triggerMetadata: .null, actions: [action], enabled: .null, exemptRoles: .null, exemptChannels: .null)
            #expect(create.jsonValue() == .object(["name": .string("rule"), "event_type": number(1), "trigger_type": number(trigger.rawValue),
                "trigger_metadata": .null, "actions": .array([action.jsonValue()]), "enabled": .null,
                "exempt_roles": .null, "exempt_channels": .null]))
            #expect(try AutoModerationCreateRequest(name: "rule", eventType: .messageSend, triggerType: trigger, actions: [action]).jsonValue() ==
                .object(["name": .string("rule"), "event_type": number(1), "trigger_type": number(trigger.rawValue), "actions": .array([action.jsonValue()])]))
            #expect(try AutoModerationModifyRequest(triggerType: trigger, triggerMetadata: .null, actions: .null,
                enabled: .null, exemptRoles: .null, exemptChannels: .null).jsonValue() == .object(["trigger_metadata": .null,
                    "actions": .null, "enabled": .null, "exempt_roles": .null, "exempt_channels": .null]))
        }
        for trigger in [AutoModerationTriggerType.keywordPreset, .memberProfile] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try AutoModerationCreateRequest(name: "rule", eventType: .messageSend, triggerType: trigger, actions: [action])
            }
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try AutoModerationCreateRequest(name: "rule", eventType: .messageSend, triggerType: trigger, triggerMetadata: .null, actions: [action])
            }
            #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationModifyRequest(triggerType: trigger, triggerMetadata: .null) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationModifyRequest(triggerType: .keyword, name: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationModifyRequest(triggerType: .keyword, eventType: .null) }
    }

    /// Keyword/profile metadata accepts all associations, empty selections, maximum counts and preview nulls.
    /// - Parameter trigger: Both user-defined keyword trigger kinds.
    /// - Throws: Unexpected constructor failures fail the test.
    @Test(arguments: [AutoModerationTriggerType.keyword, .memberProfile])
    func keywordMetadataBounds(_ trigger: AutoModerationTriggerType) throws {
        let keyword = String(repeating: "🦊", count: 60)
        let regex = String(repeating: "x", count: 260)
        let bounded = try AutoModerationTriggerMetadataRequest(triggerType: trigger,
            keywordFilter: .value(Array(repeating: keyword, count: 1_000)), regexPatterns: .value(Array(repeating: regex, count: 10)),
            allowList: .value(Array(repeating: keyword, count: 100)))
        #expect(bounded.jsonValue() == .object(["keyword_filter": .array(Array(repeating: .string(keyword), count: 1_000)),
            "regex_patterns": .array(Array(repeating: .string(regex), count: 10)), "allow_list": .array(Array(repeating: .string(keyword), count: 100))]))
        #expect(try AutoModerationTriggerMetadataRequest(triggerType: trigger, keywordFilter: .null, regexPatterns: .null, allowList: .null).jsonValue() ==
            .object(["keyword_filter": .null, "regex_patterns": .null, "allow_list": .null]))
        #expect(try AutoModerationTriggerMetadataRequest(triggerType: trigger, keywordFilter: .value([]), regexPatterns: .value([]), allowList: .value([])).jsonValue() ==
            .object(["keyword_filter": .array([]), "regex_patterns": .array([]), "allow_list": .array([])]))
        #expect(throws: DiscordError.validation(.limitExceeded)) { try AutoModerationTriggerMetadataRequest(triggerType: trigger, keywordFilter: .value(Array(repeating: "x", count: 1_001))) }
        #expect(throws: DiscordError.validation(.limitExceeded)) { try AutoModerationTriggerMetadataRequest(triggerType: trigger, regexPatterns: .value(Array(repeating: "x", count: 11))) }
        #expect(throws: DiscordError.validation(.limitExceeded)) { try AutoModerationTriggerMetadataRequest(triggerType: trigger, allowList: .value(Array(repeating: "x", count: 101))) }
        for invalid in ["", String(repeating: "🦊", count: 61)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationTriggerMetadataRequest(triggerType: trigger, keywordFilter: .value([invalid])) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationTriggerMetadataRequest(triggerType: trigger, allowList: .value([invalid])) }
        }
        for invalid in ["", String(repeating: "x", count: 261)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationTriggerMetadataRequest(triggerType: trigger, regexPatterns: .value([invalid])) }
        }
        let rustOnly = "(?-u:\\b)word(?-u:\\b)"
        #expect(try AutoModerationTriggerMetadataRequest(triggerType: trigger, regexPatterns: .value([rustOnly])).jsonValue() ==
            .object(["regex_patterns": .array([.string(rustOnly)])]))
    }

    /// Preset metadata keeps all known wordsets, distinctness and its larger allow-list bound.
    /// - Throws: Unexpected request construction fails the test.
    @Test func presetMetadataBounds() throws {
        let all = AutoModerationKeywordPresetType.allCases
        #expect(try AutoModerationTriggerMetadataRequest(triggerType: .keywordPreset, presets: .value(all)).jsonValue() ==
            .object(["presets": .array([number(1), number(2), number(3)])]))
        #expect(try AutoModerationTriggerMetadataRequest(triggerType: .keywordPreset, presets: .null, allowList: .null).jsonValue() ==
            .object(["presets": .null, "allow_list": .null]))
        #expect(try AutoModerationTriggerMetadataRequest(triggerType: .keywordPreset, presets: .value([]), allowList: .value([])).jsonValue() ==
            .object(["presets": .array([]), "allow_list": .array([])]))
        let entries = Array(repeating: String(repeating: "x", count: 60), count: 1_000)
        #expect(try AutoModerationTriggerMetadataRequest(triggerType: .keywordPreset, allowList: .value(entries)).jsonValue() ==
            .object(["allow_list": .array(entries.map { .string($0) })]))
        #expect(throws: DiscordError.validation(.limitExceeded)) { try AutoModerationTriggerMetadataRequest(triggerType: .keywordPreset, allowList: .value(entries + ["x"])) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationTriggerMetadataRequest(triggerType: .keywordPreset, presets: .value([.slurs, .slurs])) }
        for invalid in ["", String(repeating: "x", count: 61)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationTriggerMetadataRequest(triggerType: .keywordPreset, allowList: .value([invalid])) }
        }
    }

    /// Mention limits include zero and fifty, reject negative/overflow values and preserve false/null switches.
    /// - Throws: Unexpected request construction fails the test.
    @Test func mentionMetadataBounds() throws {
        for limit in [0, 50] {
            for raid in [true, false] {
                #expect(try AutoModerationTriggerMetadataRequest(triggerType: .mentionSpam, mentionTotalLimit: .value(limit),
                    mentionRaidProtectionEnabled: .value(raid)).jsonValue() == .object(["mention_total_limit": number(limit), "mention_raid_protection_enabled": .bool(raid)]))
            }
        }
        #expect(try AutoModerationTriggerMetadataRequest(triggerType: .mentionSpam, mentionTotalLimit: .null,
            mentionRaidProtectionEnabled: .null).jsonValue() == .object(["mention_total_limit": .null, "mention_raid_protection_enabled": .null]))
        for limit in [-1, 51, Int.min, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationTriggerMetadataRequest(triggerType: .mentionSpam, mentionTotalLimit: .value(limit)) }
        }
    }

    /// Fields associated with other triggers are rejected even when explicitly null or empty.
    /// - Parameter trigger: Every known rule trigger kind.
    @Test(arguments: AutoModerationTriggerType.allCases)
    func metadataAssociations(_ trigger: AutoModerationTriggerType) {
        if ![.keyword, .memberProfile].contains(trigger) {
            #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationTriggerMetadataRequest(triggerType: trigger, keywordFilter: .value([])) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationTriggerMetadataRequest(triggerType: trigger, regexPatterns: .null) }
        }
        if trigger != .keywordPreset {
            #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationTriggerMetadataRequest(triggerType: trigger, presets: .null) }
        }
        if [.spam, .mentionSpam].contains(trigger) {
            #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationTriggerMetadataRequest(triggerType: trigger, allowList: .value([])) }
        }
        if trigger != .mentionSpam {
            #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationTriggerMetadataRequest(triggerType: trigger, mentionTotalLimit: .null) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationTriggerMetadataRequest(triggerType: trigger, mentionRaidProtectionEnabled: .value(false)) }
        }
    }

    /// All action metadata requirements, incompatible fields and published text/duration boundaries are covered.
    /// - Throws: Unexpected constructor failures fail the test.
    @Test func actionBoundsAndAssociations() throws {
        for channel in [UInt64(0), UInt64.max] {
            #expect(try AutoModerationActionRequest(type: .sendAlertMessage, channelID: .value(.init(rawValue: channel))).jsonValue() ==
                .object(["type": number(2), "metadata": .object(["channel_id": .string(String(channel))])]))
        }
        for text in ["", String(repeating: "🦊", count: 150)] {
            #expect(try AutoModerationActionRequest(type: .blockMessage, customMessage: .value(text)).jsonValue() ==
                .object(["type": number(1), "metadata": .object(["custom_message": .string(text)])]))
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationActionRequest(type: .blockMessage, customMessage: .value(String(repeating: "x", count: 151))) }
        for seconds in [0, 2_419_200] {
            #expect(try AutoModerationActionRequest(type: .timeout, durationSeconds: .value(seconds)).jsonValue() ==
                .object(["type": number(3), "metadata": .object(["duration_seconds": number(seconds)])]))
        }
        for seconds in [-1, 2_419_201, Int.min, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationActionRequest(type: .timeout, durationSeconds: .value(seconds)) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationActionRequest(type: .sendAlertMessage) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationActionRequest(type: .sendAlertMessage, channelID: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationActionRequest(type: .timeout) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationActionRequest(type: .timeout, durationSeconds: .null) }
        for type in AutoModerationActionType.allCases {
            if type != .sendAlertMessage {
                #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationActionRequest(type: type, channelID: .value(.init(rawValue: 1))) }
            }
            if type != .timeout {
                #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationActionRequest(type: type, durationSeconds: .value(0)) }
            }
            if type != .blockMessage {
                #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationActionRequest(type: type, customMessage: .null) }
            }
        }
    }

    /// Enclosing requests enforce trigger consistency, timeout/member-interaction eligibility and action bounds.
    /// - Throws: Unexpected fixture construction fails the test.
    @Test func actionAndMetadataContext() throws {
        let timeout = try AutoModerationActionRequest(type: .timeout, durationSeconds: .value(1))
        let block = try AutoModerationActionRequest(type: .blockMessage)
        let quarantine = try AutoModerationActionRequest(type: .blockMemberInteraction)
        for trigger in AutoModerationTriggerType.allCases {
            let metadata = try AutoModerationTriggerMetadataRequest(triggerType: trigger)
            if [.keyword, .mentionSpam].contains(trigger) {
                #expect(try AutoModerationCreateRequest(name: "rule", eventType: .messageSend, triggerType: trigger,
                    triggerMetadata: .value(metadata), actions: [timeout]).jsonValue() == .object(["name": .string("rule"), "event_type": number(1),
                    "trigger_type": number(trigger.rawValue), "trigger_metadata": metadata.jsonValue(), "actions": .array([timeout.jsonValue()])]))
                #expect(try AutoModerationModifyRequest(triggerType: trigger, actions: .value([timeout])).jsonValue() == .object(["actions": .array([timeout.jsonValue()])]))
            } else {
                #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationCreateRequest(name: "rule", eventType: .memberUpdate,
                    triggerType: trigger, triggerMetadata: .value(metadata), actions: [timeout]) }
                #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationModifyRequest(triggerType: trigger, actions: .value([timeout])) }
            }
            if trigger == .memberProfile {
                let create = try AutoModerationCreateRequest(name: "profile", eventType: .memberUpdate,
                    triggerType: trigger, triggerMetadata: .value(metadata), actions: [quarantine])
                #expect(create.jsonValue() == .object(["name": .string("profile"), "event_type": number(2),
                    "trigger_type": number(6), "trigger_metadata": .object([:]), "actions": .array([quarantine.jsonValue()])]))
                #expect(try AutoModerationModifyRequest(triggerType: trigger, actions: .value([quarantine])).jsonValue() ==
                    .object(["actions": .array([quarantine.jsonValue()])]))
            } else {
                #expect(throws: DiscordError.validation(.invalidValue)) {
                    try AutoModerationCreateRequest(name: "rule", eventType: .messageSend, triggerType: trigger,
                        triggerMetadata: .value(metadata), actions: [quarantine])
                }
                #expect(throws: DiscordError.validation(.invalidValue)) {
                    try AutoModerationModifyRequest(triggerType: trigger, actions: .value([quarantine]))
                }
                // Eligibility must inspect every action, not only the first valid item.
                #expect(throws: DiscordError.validation(.invalidValue)) {
                    try AutoModerationModifyRequest(triggerType: trigger, actions: .value([block, quarantine]))
                }
            }
            for count in [0, 6] {
                #expect(throws: DiscordError.validation(.limitExceeded)) { try AutoModerationCreateRequest(name: "rule", eventType: .messageSend,
                    triggerType: trigger, triggerMetadata: .value(metadata), actions: Array(repeating: block, count: count)) }
                #expect(throws: DiscordError.validation(.limitExceeded)) { try AutoModerationModifyRequest(triggerType: trigger, actions: .value(Array(repeating: block, count: count))) }
            }
            let five = Array(repeating: block, count: 5)
            #expect(try AutoModerationModifyRequest(triggerType: trigger, actions: .value(five)).jsonValue() == .object(["actions": .array(five.map { $0.jsonValue() })]))
            let different = try AutoModerationTriggerMetadataRequest(triggerType: trigger == .spam ? .keyword : .spam)
            #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationModifyRequest(triggerType: trigger, triggerMetadata: .value(different)) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationCreateRequest(name: "rule", eventType: .messageSend,
                triggerType: trigger, triggerMetadata: .value(different), actions: [block]) }
        }
    }

    /// Names and exemption arrays exercise both exact limits, explicit empties, duplicates and overflow counts.
    /// - Throws: Unexpected request construction fails the test.
    @Test func namesAndExemptionBounds() throws {
        let action = try AutoModerationActionRequest(type: .blockMessage)
        let roles = (0..<20).map { RoleID(rawValue: UInt64($0)) }
        let channels = (0..<50).map { ChannelID(rawValue: UInt64($0)) }
        let name = String(repeating: "🦊", count: 100)
        let create = try AutoModerationCreateRequest(name: name, eventType: .messageSend, triggerType: .spam,
            actions: [action], enabled: .value(true), exemptRoles: .value(roles), exemptChannels: .value(channels))
        #expect(create.jsonValue() == .object(["name": .string(name), "event_type": number(1), "trigger_type": number(3),
            "actions": .array([action.jsonValue()]), "enabled": .bool(true), "exempt_roles": .array(roles.map { .string($0.description) }),
            "exempt_channels": .array(channels.map { .string($0.description) })]))
        #expect(try AutoModerationModifyRequest(triggerType: .spam, name: .value(""), exemptRoles: .value([]), exemptChannels: .value([])).jsonValue() ==
            .object(["name": .string(""), "exempt_roles": .array([]), "exempt_channels": .array([])]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationCreateRequest(name: name + "x", eventType: .messageSend, triggerType: .spam, actions: [action]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationModifyRequest(triggerType: .spam, name: .value(name + "x")) }
        #expect(throws: DiscordError.validation(.limitExceeded)) { try AutoModerationModifyRequest(triggerType: .spam, exemptRoles: .value(roles + [.init(rawValue: .max)])) }
        #expect(throws: DiscordError.validation(.limitExceeded)) { try AutoModerationModifyRequest(triggerType: .spam, exemptChannels: .value(channels + [.init(rawValue: .max)])) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationModifyRequest(triggerType: .spam, exemptRoles: .value([roles[0], roles[0]])) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationModifyRequest(triggerType: .spam, exemptChannels: .value([channels[0], channels[0]])) }
    }

    /// Published text bounds count Unicode scalars, so combining sequences exercise a different boundary
    /// from grapheme counts or UTF-8 bytes. Accepted values preserve their decomposed bytes exactly;
    /// neither request construction nor serialization normalizes names, keywords, patterns or explanations.
    /// - Throws: Unexpected request construction or serialization fails the test.
    @Test func decomposedUnicodeBoundariesAndExactBytes() throws {
        let unit = "e\u{301}"
        let keyword = String(repeating: unit, count: 30)
        let regex = String(repeating: unit, count: 130)
        let name = String(repeating: unit, count: 50)
        let explanation = String(repeating: unit, count: 75)
        #expect(keyword.count == 30)
        #expect(keyword.unicodeScalars.count == 60)
        #expect(keyword.utf8.count == 90)
        let metadata = try AutoModerationTriggerMetadataRequest(triggerType: .keyword,
            keywordFilter: .value([keyword]), regexPatterns: .value([regex]), allowList: .value([keyword]))
        let block = try AutoModerationActionRequest(type: .blockMessage, customMessage: .value(explanation))
        let create = try AutoModerationCreateRequest(name: name, eventType: .messageSend, triggerType: .keyword,
            triggerMetadata: .value(metadata), actions: [block])
        let modify = try AutoModerationModifyRequest(triggerType: .keyword, name: .value(name),
            triggerMetadata: .value(metadata), actions: .value([block]))
        var expected: [String: JSONValue] = ["name": .string(name), "event_type": number(1), "trigger_type": number(1),
            "trigger_metadata": .object(["keyword_filter": .array([.string(keyword)]),
                "regex_patterns": .array([.string(regex)]), "allow_list": .array([.string(keyword)])]),
            "actions": .array([.object(["type": number(1), "metadata": .object(["custom_message": .string(explanation)])])])]
        #expect(try create.jsonValue().serialized() == JSONValue.object(expected).serialized())
        expected["event_type"] = nil
        expected["trigger_type"] = nil
        #expect(try modify.jsonValue().serialized() == JSONValue.object(expected).serialized())
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try AutoModerationTriggerMetadataRequest(triggerType: .keyword, keywordFilter: .value([keyword + "x"]))
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try AutoModerationTriggerMetadataRequest(triggerType: .keyword, regexPatterns: .value([regex + "x"]))
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try AutoModerationTriggerMetadataRequest(triggerType: .keywordPreset, allowList: .value([keyword + "x"]))
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try AutoModerationActionRequest(type: .blockMessage, customMessage: .value(explanation + "x"))
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try AutoModerationCreateRequest(name: name + "x", eventType: .messageSend, triggerType: .spam, actions: [block])
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try AutoModerationModifyRequest(triggerType: .keyword, name: .value(name + "x"))
        }
    }

    /// Creates canonical integral fixtures without routing through floating-point JSON bridges.
    /// - Parameter value: Exact integer discriminator or count.
    /// - Returns: JSON integer fixture; all Swift Int descriptions satisfy JSON number grammar.
    private func number(_ value: Int) -> JSONValue { .number(try! JSONNumber(rawValue: String(value))) }
}
