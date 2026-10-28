// File: Tests/DiscordModelsTests/PollTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Exercises all documented poll fields, exact future data, request boundaries, and safe failures.
@Suite struct PollTests {
    /// Projects every nested response field and distinguishes unknown results from zero tallies.
    @Test func completeResponseAndDiagnostics() throws {
        let poll = try Poll(data: Data("""
        {"question":{"text":"Secret question","future":1.2300},
         "answers":[{"answer_id":42,"poll_media":{"text":"Answer","emoji":{"id":"18446744073709551615","name":null,"animated":true}}}],
         "expiry":"2026-11-01T00:00:00Z","allow_multiselect":true,"layout_type":99,
         "results":{"is_finalized":true,"answer_counts":[{"id":42,"count":18446744073709551615,"me_voted":false}]},
         "future":1e1000}
        """.utf8))
        #expect(poll.question.text == .value("Secret question"))
        #expect(poll.answers[0].answerID == 42)
        #expect(poll.expiry == .value("2026-11-01T00:00:00Z"))
        #expect(poll.allowMultiselect)
        #expect(poll.layoutType.rawValue == 99)
        #expect(poll.layoutType.knownValue == nil)
        guard case .value(let emoji) = poll.answers[0].pollMedia.emoji,
              case .value(let results) = poll.results else { Issue.record("Missing nested poll values"); return }
        #expect(emoji.id == .value("18446744073709551615"))
        #expect(emoji.name == .null)
        #expect(emoji.animated == .value(true))
        #expect(results.isFinalized)
        #expect(results.answerCounts[0].id == 42)
        #expect(results.answerCounts[0].count == UInt64.max)
        #expect(!results.answerCounts[0].meVoted)
        #expect(poll.rawFields["future"] == .number(try JSONNumber(rawValue: "1e1000")))
        #expect(poll.question.rawFields["future"] == .number(try JSONNumber(rawValue: "1.2300")))
        #expect(poll == (try Poll(data: JSONValue.object(poll.rawFields).serialized())))
        let objects: [any CustomStringConvertible & CustomDebugStringConvertible & CustomReflectable] = [
            poll, poll.question, poll.answers[0], emoji, results, results.answerCounts[0]
        ]
        for object in objects {
            #expect(!object.description.contains("Secret"))
            #expect(object.debugDescription == object.description)
            #expect(object.description.hasSuffix("(redacted)"))
            #expect(object.customMirror.children.count == 1)
        }
    }

    /// Required nullable expiry and optional/null media text remain separate from missing results.
    @Test func futureNullabilityAndStandaloneInitializers() throws {
        let poll = try Poll(data: fixture())
        #expect(poll.expiry == .null)
        #expect(poll.results == .absent)
        #expect(poll.layoutType.knownValue == .default)
        let media = try PollMedia(data: Data("{\"text\":null,\"emoji\":{\"id\":null,\"name\":\"😀\"}}".utf8))
        #expect(media.text == .null)
        #expect(try PollMedia(data: Data("{}".utf8)).text == .absent)
        guard case .value(let emoji) = media.emoji else { Issue.record("Missing emoji"); return }
        #expect(emoji.id == .null)
        #expect(emoji.name == .value("😀"))
        #expect(emoji.animated == .absent)
        #expect(try PartialEmoji(data: Data("{}".utf8)).id == .absent)
        #expect(try PollAnswer(data: Data("{\"answer_id\":9,\"poll_media\":{}}".utf8)).answerID == 9)
        let results = try PollResults(data: Data("{\"is_finalized\":false,\"answer_counts\":[]}".utf8))
        #expect(!results.isFinalized)
        #expect(results.answerCounts.isEmpty)
        let count = try PollAnswerCount(data: Data("{\"id\":1,\"count\":0,\"me_voted\":true}".utf8))
        #expect(count.count == 0)
        #expect(count.meVoted)
    }

    /// Every mandatory poll key remains mandatory even when its value is nullable.
    /// - Parameter key: One required field removed from an otherwise valid fixture.
    @Test(arguments: ["question", "answers", "expiry", "allow_multiselect", "layout_type"])
    func requiresPollFields(key: String) throws {
        var fields = try fixtureFields()
        fields.removeValue(forKey: key)
        #expect(throws: DiscordError.transport(.invalidResponse)) { try Poll(data: JSONValue.object(fields).serialized()) }
    }

    /// Rejects modeled type/range mismatches without rounding numeric discriminators or leaking payloads.
    /// - Parameter patch: JSON member overriding a valid poll field.
    @Test(arguments: ["\"question\":[]", "\"answers\":null", "\"answers\":[{}]", "\"expiry\":1",
                      "\"allow_multiselect\":null", "\"layout_type\":1.00000000000000001", "\"layout_type\":1e0",
                      "\"results\":null", "\"results\":{}", "\"results\":{\"is_finalized\":true,\"answer_counts\":[{\"id\":1,\"count\":-1,\"me_voted\":false}]}"])
    func rejectsMalformedPoll(patch: String) throws {
        var fields = try fixtureFields()
        guard case .object(let replacement) = try JSONValue.parse("{" + patch + "}") else { return }
        fields.merge(replacement) { _, new in new }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try Poll(data: JSONValue.object(fields).serialized()) }
    }

    /// Covers required nested keys and malformed media/emoji states through their public entry points.
    /// - Parameter json: Invalid nested object fixture; all failures have sanitized error values.
    @Test(arguments: ["{\"text\":1}", "{\"emoji\":null}", "{\"emoji\":[]}", "{\"emoji\":{\"id\":\"18446744073709551616\"}}",
                      "{\"emoji\":{\"id\":\"-1\"}}", "{\"emoji\":{\"animated\":null}}"])
    func rejectsMalformedMedia(json: String) throws {
        #expect(throws: DiscordError.transport(.invalidResponse)) { try PollMedia(data: Data(json.utf8)) }
    }

    /// Missing mandatory nested tally/answer fields and nonintegral integers are rejected deterministically.
    @Test func nestedRequiredFieldsAndBounds() throws {
        #expect(throws: DiscordError.transport(.invalidResponse)) { try PollAnswer(data: Data("{\"answer_id\":1}".utf8)) }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try PollAnswer(data: Data("{\"poll_media\":{}}".utf8)) }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try PollAnswerCount(data: Data("{\"id\":1,\"count\":0}".utf8)) }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try PollResults(data: Data("{\"is_finalized\":true}".utf8)) }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try PollResults(data: Data("{\"answer_counts\":[]}".utf8)) }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try Poll(data: Data("[]".utf8)) }
        #expect(throws: JSONValueError.self) { try Poll(data: Data("{".utf8)) }
        #expect(throws: JSONValueError.maximumBytesExceeded) { try Poll(data: fixture(), limits: JSONLimits(maximumBytes: 1)) }
        #expect(throws: JSONValueError.maximumDepthExceeded) { try Poll(data: fixture(), limits: JSONLimits(maximumDepth: 1)) }
        #expect(throws: JSONValueError.maximumNodesExceeded) { try Poll(data: fixture(), limits: JSONLimits(maximumNodes: 1)) }
        #expect(throws: JSONValueError.invalidLimits) { try Poll(data: fixture(), limits: JSONLimits(maximumDepth: 129)) }
    }

    /// Creation preserves omitted defaults and emits answer wrappers without response-only identifiers.
    @Test func createDefaultsAndExplicitBoundaryValues() throws {
        let answer = try PollMedia(text: .value("Answer"))
        let request = try PollCreate(question: "Question", answers: [answer])
        #expect(request.rawFields["duration"] == nil)
        #expect(request.rawFields["layout_type"] == nil)
        #expect(request.rawFields["allow_multiselect"] == nil)
        #expect(try JSONValue.parse(request.serialized()) == request.jsonValue())
        #expect(request == (try PollCreate(question: "Question", answers: [answer])))
        #expect(String(describing: request) == "PollCreate(redacted)")
        #expect(String(reflecting: request) == "PollCreate(redacted)")
        #expect(Mirror(reflecting: request).children.count == 1)
        let custom = try PollMedia(text: .value(String(repeating: "a", count: 55)), emoji: .value(.object(["id": .string("18446744073709551615")])))
        let unicode = try PollMedia(text: .value("Two"), emoji: .value(.object(["name": .string("😀")])))
        let boundary = try PollCreate(question: String(repeating: "😀", count: 300), answers: [custom, unicode] + Array(repeating: answer, count: 8),
                                      duration: 768, allowMultiselect: true, layoutType: 1)
        #expect(boundary.rawFields["duration"] == .number(try JSONNumber(rawValue: "768")))
        #expect(boundary.rawFields["allow_multiselect"] == .bool(true))
        #expect(try JSONValue.parse(boundary.serialized()) == boundary.jsonValue())
        _ = try PollCreate(question: "Q", answers: [answer], duration: 1, allowMultiselect: false)
        #expect(throws: JSONValueError.maximumBytesExceeded) { try boundary.serialized(limits: JSONLimits(maximumBytes: 1)) }
    }

    /// Current creation limits reject empty/oversize text, answer counts, durations, and future layouts.
    /// - Parameter duration: An invalid hour duration outside one hour through 32 days.
    @Test(arguments: [0, -1, 769, Int.max])
    func invalidCreateDuration(duration: Int) throws {
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try PollCreate(question: "Q", answers: [PollMedia(text: .value("A"))], duration: duration)
        }
    }

    /// Covers all other creation validation branches, including nullable/future media and emoji payload fields.
    @Test func invalidCreateShapes() throws {
        let answer = try PollMedia(text: .value("A"))
        for question in ["", String(repeating: "x", count: 301)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try PollCreate(question: question, answers: [answer]) }
        }
        for answers in [[], Array(repeating: answer, count: 11)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try PollCreate(question: "Q", answers: answers) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try PollCreate(question: "Q", answers: [answer], layoutType: 99) }
        let invalidTexts: [Field<String>] = [.absent, .null, .value(""), .value(String(repeating: "x", count: 56))]
        for text in invalidTexts {
            let bad = try PollMedia(text: text)
            #expect(throws: DiscordError.validation(.invalidValue)) { try PollCreate(question: "Q", answers: [bad]) }
        }
        for json in ["{\"text\":\"A\",\"future\":true}", "{\"text\":\"A\",\"emoji\":{}}",
                     "{\"text\":\"A\",\"emoji\":{\"name\":\"\"}}", "{\"text\":\"A\",\"emoji\":{\"name\":null}}",
                     "{\"text\":\"A\",\"emoji\":{\"id\":\"1\",\"name\":\"custom\"}}"] {
            let bad = try PollMedia(data: Data(json.utf8))
            #expect(throws: DiscordError.validation(.invalidValue)) { try PollCreate(question: "Q", answers: [bad]) }
        }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try PollMedia(emoji: .null) }
    }

    /// Supplies a complete minimal response without results, so omission has observable semantics.
    /// - Returns: Deterministic local UTF-8 poll fixture bytes, with no credentials or live requests.
    private func fixture() -> Data {
        Data("{\"question\":{\"text\":\"Q\"},\"answers\":[],\"expiry\":null,\"allow_multiselect\":false,\"layout_type\":1}".utf8)
    }

    /// Parses the minimal response for targeted missing-key and malformed-field regression tests.
    /// - Returns: Complete poll fields retaining exact JSON values.
    /// - Throws: Fixture parsing errors, indicating a broken test setup.
    private func fixtureFields() throws -> [String: JSONValue] {
        guard case .object(let fields) = try JSONValue.parse(fixture()) else { throw DiscordError.validation(.invalidValue) }
        return fields
    }
}
