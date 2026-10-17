import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Deterministic Auto Moderation fixtures verify complete fields, exact presence, future values and
/// redaction without Discord credentials, permissions, network access or timing-dependent work.
@Suite struct AutoModerationModelTests {
    /// Complete rule fields and all nested projections preserve exact IDs, values and unknown subtrees.
    /// - Throws: Unexpected parser, schema or serialization errors fail the test.
    @Test func completeRule() throws {
        let source = #"{"id":"18446744073709551615","guild_id":"0","name":"private-rule","creator_id":"18446744073709551615","event_type":2,"trigger_type":6,"trigger_metadata":{"keyword_filter":["*private*"],"regex_patterns":["(?i)private"],"presets":[1,2,3,9876],"allow_list":["allowed"],"mention_total_limit":50,"mention_raid_protection_enabled":false,"future":1.2300e+100},"actions":[{"type":1,"metadata":{"custom_message":null,"future":"private-metadata"}},{"type":2,"metadata":{"channel_id":"18446744073709551615"}},{"type":3,"metadata":{"duration_seconds":2419200}},{"type":4},{"type":9876,"metadata":{"future":true}}],"enabled":true,"exempt_roles":["18446744073709551615","0"],"exempt_channels":["0","18446744073709551615"],"future":{"exact":18446744073709551616}}"#
        let value = try JSONValue.parse(source)
        let rule = try AutoModerationRule(data: Data(source.utf8))
        #expect(rule.id.rawValue == .max)
        #expect(rule.guildID.rawValue == 0)
        #expect(rule.creatorID.rawValue == .max)
        #expect(rule.name == "private-rule")
        #expect(rule.eventType.knownValue == .memberUpdate)
        #expect(rule.triggerType.knownValue == .memberProfile)
        #expect(rule.enabled)
        #expect(rule.exemptRoles.map(\.rawValue) == [.max, 0])
        #expect(rule.exemptChannels.map(\.rawValue) == [0, .max])
        let metadata = rule.triggerMetadata
        #expect(metadata.keywordFilter == .value(["*private*"]))
        #expect(metadata.regexPatterns == .value(["(?i)private"]))
        #expect(metadata.presets == .value([.init(.profanity), .init(.sexualContent), .init(.slurs), .init(rawValue: 9876)]))
        #expect(metadata.allowList == .value(["allowed"]))
        #expect(metadata.mentionTotalLimit == .value(50))
        #expect(metadata.mentionRaidProtectionEnabled == .value(false))
        #expect(metadata.rawFields["future"] == .number(try JSONNumber(rawValue: "1.2300e+100")))
        #expect(rule.actions.map(\.type.rawValue) == [1, 2, 3, 4, 9876])
        #expect(rule.actions[4].type.knownValue == nil)
        #expect(rule.actions[3].metadata == .absent)
        if case .value(let block) = rule.actions[0].metadata { #expect(block.customMessage == .null) }
        else { Issue.record("Expected block metadata") }
        if case .value(let alert) = rule.actions[1].metadata { #expect(alert.channelID == .value(.init(rawValue: .max))) }
        else { Issue.record("Expected alert metadata") }
        if case .value(let timeout) = rule.actions[2].metadata { #expect(timeout.durationSeconds == .value(2_419_200)) }
        else { Issue.record("Expected timeout metadata") }
        #expect(rule.jsonValue() == value)
        #expect(try AutoModerationRule(value: value, limits: .default) == rule)
        #expect(try JSONValue.parse(rule.jsonValue().serialized()) == value)
    }

    /// A realistic keyword rule exercises the written API's nested response shape and known action meanings.
    /// Unlike deliberately heterogeneous forward-compatibility fixtures, every metadata field belongs to
    /// its enclosing trigger/action; the exact rule remains usable through an audit response as well.
    /// - Throws: Unexpected parsing, projection or fixture serialization fails the test.
    @Test func documentedKeywordRuleShape() throws {
        let source = #"{"id":"969707018069872670","guild_id":"613425648685547541","name":"Keyword Filter","creator_id":"423457898095789043","event_type":1,"trigger_type":1,"trigger_metadata":{"keyword_filter":["cat*","*dog","*ana*","a phrase"],"regex_patterns":["(b|c)at"],"allow_list":[]},"actions":[{"type":1,"metadata":{"custom_message":"Please use the designated channel"}},{"type":2,"metadata":{"channel_id":"123456789123456789"}},{"type":3,"metadata":{"duration_seconds":60}}],"enabled":true,"exempt_roles":["323456789123456789","423456789123456789"],"exempt_channels":["523456789123456789"]}"#
        let rule = try AutoModerationRule(data: Data(source.utf8))
        #expect(rule.eventType.knownValue == .messageSend)
        #expect(rule.triggerType.knownValue == .keyword)
        #expect(rule.triggerMetadata.keywordFilter == .value(["cat*", "*dog", "*ana*", "a phrase"]))
        #expect(rule.triggerMetadata.regexPatterns == .value(["(b|c)at"]))
        #expect(rule.triggerMetadata.allowList == .value([]))
        #expect(rule.actions.map(\.type.knownValue) == [.blockMessage, .sendAlertMessage, .timeout])
        guard case .value(let block) = rule.actions[0].metadata,
              case .value(let alert) = rule.actions[1].metadata,
              case .value(let timeout) = rule.actions[2].metadata else {
            Issue.record("Expected all documented action metadata objects")
            return
        }
        #expect(block.customMessage == .value("Please use the designated channel"))
        #expect(alert.channelID == .value(.init(rawValue: 123_456_789_123_456_789)))
        #expect(timeout.durationSeconds == .value(60))
        let envelope: [String: JSONValue] = ["application_commands": .array([]), "audit_log_entries": .array([]),
            "auto_moderation_rules": .array([rule.jsonValue()]), "guild_scheduled_events": .array([]),
            "integrations": .array([]), "threads": .array([]), "users": .array([]), "webhooks": .array([])]
        let audit = try AuditLog(data: JSONValue.object(envelope).serialized())
        #expect(audit.autoModerationRules == [.value(rule)])
    }

    /// Each known integer discriminator and keyword preset remains recognized with its published value.
    /// - Throws: Unexpected parsing errors fail the test.
    @Test func knownAndFutureDiscriminators() throws {
        #expect(AutoModerationEventType.allCases.map(\.rawValue) == [1, 2])
        #expect(AutoModerationTriggerType.allCases.map(\.rawValue) == [1, 3, 4, 5, 6])
        #expect(AutoModerationActionType.allCases.map(\.rawValue) == [1, 2, 3, 4])
        #expect(AutoModerationKeywordPresetType.allCases.map(\.rawValue) == [1, 2, 3])
        for fixture in AutoModerationFixture.all {
            let parsed = try fixture.parse(Data(fixture.populated.utf8), .default)
            #expect(parsed.rawFields["future"] == .string("private-future"))
            #expect(parsed.description.hasSuffix("(redacted)"))
            #expect(parsed.debugDescription == parsed.description)
            #expect(!String(reflecting: parsed).contains("private-"))
            #expect(parsed.customMirror.children.count == 1)
        }
        var fields = try object(AutoModerationFixture.all[0].populated)
        fields["event_type"] = try number(Int.max)
        fields["trigger_type"] = try number(Int.min)
        let future = try AutoModerationRule(value: .object(fields), limits: .default)
        #expect(future.eventType.rawValue == Int.max)
        #expect(future.eventType.knownValue == nil)
        #expect(future.triggerType.rawValue == Int.min)
        #expect(future.triggerType.knownValue == nil)
    }

    /// Every known field rejects malformed shapes and forbidden nulls; optional fields preserve absence.
    /// - Throws: Unexpected fixture serialization errors fail the test.
    @Test func completeFieldContracts() throws {
        for fixture in AutoModerationFixture.all {
            let baseline = try object(fixture.populated)
            for (name, optional, nullable) in fixture.fields {
                var fields = baseline
                fields[name] = nil
                let missing = try JSONValue.object(fields).serialized()
                if optional { #expect(try fixture.parse(missing, .default).rawFields[name] == nil) }
                else { #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.parse(missing, .default) } }
                fields[name] = .null
                let null = try JSONValue.object(fields).serialized()
                if nullable { #expect(try fixture.parse(null, .default).rawFields[name] == .null) }
                else { #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.parse(null, .default) } }
                fields[name] = .object(["invalid": .bool(true)])
                if ["trigger_metadata", "metadata"].contains(name) { fields[name] = .array([]) }
                let malformed = try JSONValue.object(fields).serialized()
                #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.parse(malformed, .default) }
            }
        }
    }

    /// Exact integer validation rejects fractional lexemes, numeric strings, booleans and overflow.
    /// - Parameter token: Invalid exact numeric token or incompatible JSON scalar.
    /// - Throws: Unexpected fixture parsing/serialization errors fail the test.
    @Test(arguments: ["1.0", "1e0", "1.00000000000000000000001", "1e-999", "18446744073709551616", "\"1\"", "true"])
    func malformedNumbers(_ token: String) throws {
        let invalid = try JSONValue.parse(token)
        for (fixtureIndex, key) in [(0, "event_type"), (0, "trigger_type"), (1, "mention_total_limit"), (2, "type"), (3, "duration_seconds")] {
            let fixture = AutoModerationFixture.all[fixtureIndex]
            var fields = try object(fixture.populated)
            fields[key] = invalid
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try fixture.parse(JSONValue.object(fields).serialized(), .default)
            }
        }
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try AutoModerationTriggerMetadata(data: Data("{\"presets\":[\(token)]}".utf8))
        }
        var rule = try object(AutoModerationFixture.all[0].populated)
        rule["trigger_metadata"] = .object(["presets": .array([try number(1), invalid])])
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try AutoModerationRule(data: JSONValue.object(rule).serialized())
        }
    }

    /// Exact per-element preset projection recognizes published codes while retaining unknown integer extremes.
    /// The array remains ordered and complete; response decoding does not impose request uniqueness limits.
    /// - Throws: Unexpected exact metadata/rule parsing or serialization fails the test.
    @Test func exactPresetIntegersAndUnknownValues() throws {
        let values = [Int.min, -1, 0, 1, 2, 3, 3, Int.max]
        let metadata: JSONValue = .object(["presets": .array(try values.map { try number($0) })])
        let parsed = try AutoModerationTriggerMetadata(data: metadata.serialized())
        guard case .value(let presets) = parsed.presets else {
            Issue.record("Expected present preset array")
            return
        }
        #expect(presets.map(\.rawValue) == values)
        #expect(presets.map(\.knownValue) == [nil, nil, nil, .profanity, .sexualContent, .slurs, .slurs, nil])
        #expect(parsed.jsonValue() == metadata)
        #expect(try AutoModerationTriggerMetadata(data: Data(#"{"presets":[-0]}"#.utf8)).presets == .value([.init(rawValue: 0)]))
        for token in ["null", "false", "{}", "[]"] {
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try AutoModerationTriggerMetadata(data: Data("{\"presets\":[1,\(token)]}".utf8))
            }
        }
    }

    /// Optional empty objects, explicit custom nulls and response values exceeding writable limits remain exact.
    /// - Throws: Unexpected parsing errors fail the test.
    @Test func responsePresenceAndMutationLimitSeparation() throws {
        let trigger = try AutoModerationTriggerMetadata(data: Data("{}".utf8))
        #expect(trigger.keywordFilter == .absent)
        #expect(trigger.regexPatterns == .absent)
        #expect(trigger.presets == .absent)
        #expect(trigger.allowList == .absent)
        #expect(trigger.mentionTotalLimit == .absent)
        #expect(trigger.mentionRaidProtectionEnabled == .absent)
        let action = try AutoModerationActionMetadata(data: Data("{}".utf8))
        #expect(action.channelID == .absent)
        #expect(action.durationSeconds == .absent)
        #expect(action.customMessage == .absent)
        #expect(try AutoModerationActionMetadata(data: Data(#"{"custom_message":null}"#.utf8)).customMessage == .null)
        #expect(try AutoModerationActionMetadata(data: Data(#"{"custom_message":""}"#.utf8)).customMessage == .value(""))
        #expect(try AutoModerationActionMetadata(data: Data(#"{"duration_seconds":-1}"#.utf8)).durationSeconds == .value(-1))
        #expect(try AutoModerationTriggerMetadata(data: Data(#"{"mention_total_limit":51,"presets":[9876]}"#.utf8)).mentionTotalLimit == .value(51))
        #expect(try AutoModerationAction(data: Data(#"{"type":3}"#.utf8)).metadata == .absent)
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try AutoModerationTriggerMetadata(data: Data(#"{"keyword_filter":[null]}"#.utf8))
        }
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try AutoModerationRule(data: Data(AutoModerationFixture.all[0].populated.replacingOccurrences(of: "\"exempt_roles\":[]", with: "\"exempt_roles\":[\"18446744073709551616\"]").utf8))
        }
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try AutoModerationRule(data: Data(AutoModerationFixture.all[0].populated.replacingOccurrences(of: "\"actions\":[]", with: "\"actions\":[null]").utf8))
        }
    }

    /// Nested collection elements are validated independently of the surrounding array's valid shape.
    /// Invalid strings, identifiers, presets and actions must fail the complete rule without accepting a
    /// partial prefix; direct metadata construction and rule-contained construction use the same contract.
    /// - Parameter token: A nonstring JSON element, including explicit null and nested containers.
    /// - Throws: Unexpected valid-fixture parsing or serialization fails the test.
    @Test(arguments: ["null", "false", "1", "{}", "[]"])
    func malformedCollectionElements(_ token: String) throws {
        let invalid = try JSONValue.parse(token)
        for key in ["keyword_filter", "regex_patterns", "allow_list"] {
            let metadata: JSONValue = .object([key: .array([.string("valid-prefix"), invalid])])
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try AutoModerationTriggerMetadata(data: metadata.serialized())
            }
            var rule = try object(AutoModerationFixture.all[0].populated)
            rule["trigger_metadata"] = metadata
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try AutoModerationRule(data: JSONValue.object(rule).serialized())
            }
        }
        for key in ["exempt_roles", "exempt_channels"] {
            var rule = try object(AutoModerationFixture.all[0].populated)
            rule[key] = .array([.string("18446744073709551615"), invalid])
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try AutoModerationRule(data: JSONValue.object(rule).serialized())
            }
        }
        var rule = try object(AutoModerationFixture.all[0].populated)
        rule["actions"] = .array([.object(["type": try number(1)]), invalid])
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try AutoModerationRule(data: JSONValue.object(rule).serialized())
        }
    }

    /// Each public decoder enforces whole-document syntax, roots and parser budgets including unknown fields.
    /// - Throws: Unexpected fixture serialization errors fail the test.
    @Test func parserBoundsAndInvalidRoots() throws {
        for fixture in AutoModerationFixture.all {
            let bytes = Data(fixture.populated.utf8)
            #expect(throws: (any Error).self) { try fixture.parse(bytes, JSONLimits(maximumBytes: 1)) }
            #expect(throws: (any Error).self) { try fixture.parse(bytes, JSONLimits(maximumNodes: 1)) }
            #expect(throws: (any Error).self) { try fixture.parse(bytes, JSONLimits(maximumDepth: 1)) }
            #expect(throws: (any Error).self) { try fixture.parse(bytes, JSONLimits(maximumDepth: 0)) }
            for text in ["null", "[]", "1", #""text""#] {
                #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.parse(Data(text.utf8), .default) }
            }
            for text in [#"{"future":1,"future":2}"#, "{} {}", "{", #"{"future":"\uD800"}"#] {
                #expect(throws: (any Error).self) { try fixture.parse(Data(text.utf8), .default) }
            }
            let parsed = try fixture.parse(bytes, .default)
            #expect(parsed.rawFields["future"] == .string("private-future"))
        }
    }

    /// Extracts a trusted fixture object for mutation of individual schema fields.
    /// - Parameter text: Complete valid JSON object fixture.
    /// - Returns: Its original fields without normalization.
    /// - Throws: Parser errors, or a recorded test failure when the trusted fixture is not an object.
    private func object(_ text: String) throws -> [String: JSONValue] {
        guard case .object(let fields) = try JSONValue.parse(text) else {
            Issue.record("Expected object fixture")
            throw DiscordError.validation(.invalidValue)
        }
        return fields
    }

    /// Constructs an exact signed numeric fixture without floating-point conversion.
    /// - Parameter value: Integral discriminator including platform extremes.
    /// - Returns: Canonical exact JSON integer.
    /// - Throws: Numeric syntax validation failure.
    private func number(_ value: Int) throws -> JSONValue { .number(try JSONNumber(rawValue: String(value))) }
}

/// Data-driven independently parsed schemas and their complete required/optional/null contracts.
private struct AutoModerationFixture: Sendable {
    let populated: String
    let fields: [(String, Bool, Bool)]
    let parse: @Sendable (Data, JSONLimits) throws -> any MessageResponseValue

    /// All four public response decoders, including nested data so depth limits exercise real containers.
    static let all: [Self] = [
        .init(populated: #"{"id":"1","guild_id":"2","name":"private-rule","creator_id":"3","event_type":1,"trigger_type":3,"trigger_metadata":{},"actions":[],"enabled":false,"exempt_roles":[],"exempt_channels":[],"future":"private-future"}"#,
            fields: ["id", "guild_id", "name", "creator_id", "event_type", "trigger_type", "trigger_metadata", "actions", "enabled", "exempt_roles", "exempt_channels"].map { ($0, false, false) },
            parse: { try AutoModerationRule(data: $0, limits: $1) }),
        .init(populated: #"{"keyword_filter":["private"],"regex_patterns":["private"],"presets":[1,2,3,9876],"allow_list":["private"],"mention_total_limit":50,"mention_raid_protection_enabled":true,"future":"private-future"}"#,
            fields: ["keyword_filter", "regex_patterns", "presets", "allow_list", "mention_total_limit", "mention_raid_protection_enabled"].map { ($0, true, false) },
            parse: { try AutoModerationTriggerMetadata(data: $0, limits: $1) }),
        .init(populated: #"{"type":9876,"metadata":{"future":true},"future":"private-future"}"#,
            fields: [("type", false, false), ("metadata", true, false)],
            parse: { try AutoModerationAction(data: $0, limits: $1) }),
        .init(populated: #"{"channel_id":"18446744073709551615","duration_seconds":2419200,"custom_message":"private-text","nested":{"future":true},"future":"private-future"}"#,
            fields: [("channel_id", true, false), ("duration_seconds", true, false), ("custom_message", true, true)],
            parse: { try AutoModerationActionMetadata(data: $0, limits: $1) })
    ]
}
