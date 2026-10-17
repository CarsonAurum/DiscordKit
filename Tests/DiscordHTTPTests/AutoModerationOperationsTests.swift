import DiscordCore
import DiscordModels
import Foundation
import Testing
@testable import DiscordHTTP

/// Snapshot comparison is explicit, presence-aware and produces no transport work.
@Suite struct AutoModerationOperationsTests {
    /// Matching/empty edits skip mutation; changes preserve target identity, reason validation and exact body.
    /// - Throws: Unexpected request/model/descriptor errors fail this test.
    @Test func noOpReconciliation() throws {
        let current = try AutoModerationRule(data: Data(ModerationEndpointTests.ruleJSON.utf8))
        #expect(try AutoModerationOperations.modifyIfChanged(current: current, request: AutoModerationModifyRequest(triggerType: .spam)) == nil)
        #expect(try AutoModerationOperations.modifyIfChanged(current: current,
            request: AutoModerationModifyRequest(triggerType: .spam, name: .value("fixture"), enabled: .value(false), exemptRoles: .value([]), exemptChannels: .value([])), auditReason: "\n") == nil)
        let request = try AutoModerationModifyRequest(triggerType: .spam, name: .value("new"))
        let edit = try #require(try AutoModerationOperations.modifyIfChanged(current: current, request: request, auditReason: "why"))
        #expect(edit.method == "PATCH")
        #expect(edit.path == ["guilds", "18446744073709551615", "auto-moderation", "rules", "18446744073709551615"])
        #expect(edit.auditReason == "why")
        #expect(try JSONValue.parse(#require(edit.body?.storedBodyBytes)) == request.jsonValue())
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try AutoModerationOperations.modifyIfChanged(current: current, request: request, auditReason: "\n")
        }
        let clear = try AutoModerationModifyRequest(triggerType: .spam, exemptRoles: .null)
        #expect(try AutoModerationOperations.modifyIfChanged(current: current, request: clear) != nil)
        var raw = current.rawFields
        raw["exempt_roles"] = nil
        // Response schemas require this key; absence must fail rather than inventing a comparable empty default.
        #expect(throws: (any Error).self) { try AutoModerationRule(data: JSONValue.object(raw).serialized()) }
    }

    /// The snapshot trigger must agree with request validation, including empty edits and future rule kinds.
    /// A timeout valid for keyword rules cannot bypass the actual spam rule's action restrictions.
    /// - Parameter trigger: A known mismatched or future response discriminator retained by the model.
    /// - Throws: Unexpected model/request setup errors fail this test; incompatible contexts are asserted.
    @Test(arguments: [1, 4, 5, 6, 999]) func incompatibleSnapshotContext(trigger: Int) throws {
        var raw = try AutoModerationRule(data: Data(ModerationEndpointTests.ruleJSON.utf8)).rawFields
        raw["trigger_type"] = .number(try JSONNumber(rawValue: String(trigger)))
        let current = try AutoModerationRule(data: JSONValue.object(raw).serialized())
        for request in [try AutoModerationModifyRequest(triggerType: .spam),
                        try AutoModerationModifyRequest(triggerType: .spam, name: .value("changed"))] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try AutoModerationOperations.modifyIfChanged(current: current, request: request)
            }
        }
        let spam = try AutoModerationRule(data: Data(ModerationEndpointTests.ruleJSON.utf8))
        let timeout = try AutoModerationModifyRequest(triggerType: .keyword,
            actions: .value([AutoModerationActionRequest(type: .timeout, durationSeconds: .value(60))]))
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try AutoModerationOperations.modifyIfChanged(current: spam, request: timeout)
        }
    }

    /// Exact comparison covers event context, nested metadata, actions and exemption arrays without hidden reads.
    /// Unrequested future fields do not force a write; reordered explicitly requested arrays remain a change.
    /// - Throws: Unexpected fixture, validation or descriptor errors fail this test.
    @Test func completeFieldComparison() throws {
        let metadata = try AutoModerationTriggerMetadataRequest(triggerType: .keyword,
            keywordFilter: .value(["word"]), allowList: .value(["allowed"]))
        let action = try AutoModerationActionRequest(type: .blockMessage, customMessage: .value("explanation"))
        let request = try AutoModerationModifyRequest(triggerType: .keyword, name: .value("fixture"),
            eventType: .value(.messageSend), triggerMetadata: .value(metadata), actions: .value([action]),
            enabled: .value(false), exemptRoles: .value([.init(rawValue: 2), .init(rawValue: UInt64.max)]),
            exemptChannels: .value([.init(rawValue: 4), .init(rawValue: 5)]))
        var raw = try AutoModerationRule(data: Data(ModerationEndpointTests.ruleJSON.utf8)).rawFields
        guard case .object(let fields) = request.jsonValue() else { Issue.record("Expected request object"); return }
        raw.merge(fields) { _, new in new }
        raw["trigger_type"] = .number(try JSONNumber(rawValue: "1"))
        raw["future"] = .object(["untouched": .bool(true)])
        let current = try AutoModerationRule(data: JSONValue.object(raw).serialized())
        #expect(try AutoModerationOperations.modifyIfChanged(current: current, request: request) == nil)
        let changed = [
            try AutoModerationModifyRequest(triggerType: .keyword, eventType: .value(.memberUpdate)),
            try AutoModerationModifyRequest(triggerType: .keyword,
                triggerMetadata: .value(AutoModerationTriggerMetadataRequest(triggerType: .keyword, keywordFilter: .value(["different"])))),
            try AutoModerationModifyRequest(triggerType: .keyword, actions: .value([AutoModerationActionRequest(type: .blockMessage)])),
            try AutoModerationModifyRequest(triggerType: .keyword, enabled: .value(true)),
            try AutoModerationModifyRequest(triggerType: .keyword, exemptRoles: .value([.init(rawValue: UInt64.max), .init(rawValue: 2)])),
            try AutoModerationModifyRequest(triggerType: .keyword, exemptChannels: .value([]))
        ]
        for change in changed {
            let endpoint = try #require(try AutoModerationOperations.modifyIfChanged(current: current, request: change))
            #expect(try JSONValue.parse(#require(endpoint.body?.storedBodyBytes)) == change.jsonValue())
            #expect(endpoint.retrySafety == .unsafe)
            #expect(endpoint.readPolicy == nil)
        }
        #expect(current.rawFields["future"] == .object(["untouched": .bool(true)]))
    }
}
