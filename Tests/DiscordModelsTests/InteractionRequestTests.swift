// File: Tests/DiscordModelsTests/InteractionRequestTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Exercises callback/message/modal construction without transport, credentials, clocks or hidden state machines.
@Suite struct InteractionRequestTests {
    /// Each written callback kind has the exact envelope and only its documented payload fields.
    /// Complete case discovery includes the deprecated premium response and Activity launch in wire order.
    /// - Parameter index: Stable index in the complete written callback catalog.
    /// - Throws: Unexpected fixture/request/serialization failures fail the test.
    @Test(arguments: 0..<9) func callbackCatalog(index: Int) throws {
        let response = try Self.responses()[index]
        let types = [1, 4, 5, 6, 7, 8, 9, 10, 12]
        #expect(InteractionCallbackType.allCases.map(\.rawValue) == types)
        let value = try response.jsonValue()
        guard case .object(let fields) = value else { Issue.record("Expected callback object"); return }
        #expect(response.type.rawValue == types[index])
        #expect(fields["type"] == .number(try JSONNumber(rawValue: String(types[index]))))
        #expect(Set(fields.keys).isSubset(of: ["type", "data"]))
        #expect(response.description == response.debugDescription)
        #expect(response.customMirror.children.count == 1)
        #expect(!String(reflecting: response).contains("response\""))
        if [1, 6, 10, 12].contains(types[index]) { #expect(fields["data"] == nil) }
        #expect(try JSONValue.parse(value.serialized()) == value)
        if types[index] == 5 { #expect(fields["data"] == .object(["flags": .number(try JSONNumber(rawValue: "64"))])) }
        if types[index] == 8 { #expect(fields["data"] == .object(["choices": .array([])])) }
        if types[index] == 7 { #expect(fields["data"] == .object(["content": .null])) }
    }

    /// Trigger/callback compatibility covers PING, commands, components, autocomplete and modal submission.
    /// Unknown triggering context can be deliberately omitted, but supplied context is always validated.
    /// - Parameters:
    ///   - source: Every known incoming kind.
    ///   - index: Every written callback kind.
    /// - Throws: Unexpected fixture/request failures fail the test; incompatible combinations are asserted.
    @Test(arguments: InteractionType.allCases, 0..<9)
    func callbackCompatibility(source: InteractionType, index: Int) throws {
        let response = try Self.responses()[index]
        let type = response.type
        let valid: Bool
        if source == .ping { valid = type == .pong }
        else if source == .applicationCommandAutocomplete { valid = type == .applicationCommandAutocompleteResult }
        else if type == .pong || type == .applicationCommandAutocompleteResult { valid = false }
        else if type == .modal { valid = source != .modalSubmit }
        else if type == .deferredUpdateMessage || type == .updateMessage { valid = source == .messageComponent || source == .modalSubmit }
        else { valid = true }
        if valid { #expect(try response.jsonValue(interactionType: source) == response.jsonValue()) }
        else { #expect(throws: DiscordError.validation(.invalidValue)) { try response.jsonValue(interactionType: source) } }
        if type != .channelMessageWithSource && type != .updateMessage {
            #expect(throws: DiscordError.validation(.invalidValue)) { try response.jsonValue(uploadIDs: [0]) }
        }
    }

    /// Deferred callbacks restrict flags to the explicit ephemeral Boolean and autocomplete caps choices at 25.
    /// Strings, exact numeric values and localizations retain the existing command-choice validation.
    /// - Throws: Unexpected valid request failures fail the test.
    @Test func deferralAndAutocomplete() throws {
        #expect(try InteractionResponse.deferredMessage().jsonValue() == .object(["type": .number(JSONNumber(rawValue: "5"))]))
        let choice = try ApplicationCommandChoiceCreate(name: "choice", value: .number(JSONNumber(rawValue: "9007199254740991")))
        let value = try InteractionResponse.autocomplete(Array(repeating: choice, count: 25)).jsonValue(interactionType: .applicationCommandAutocomplete)
        guard case .object(let fields) = value, case .object(let data) = fields["data"], case .array(let choices) = data["choices"]
        else { Issue.record("Expected choices"); return }
        #expect(choices.count == 25)
        #expect(choices.first == choice.jsonValue())
        #expect(throws: DiscordError.validation(.invalidValue)) { try InteractionResponse.autocomplete(Array(repeating: choice, count: 26)).jsonValue() }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try InteractionResponse.update(InteractionMessageEdit(content: .value("later"), deferredResponse: true)).jsonValue()
        }
    }

    /// Common message fields retain explicit false/empty selectors and EPHEMERAL without admitting channel-only fields.
    /// The complete wire object still applies ordinary message/attachment/embed/poll/component validation.
    /// - Throws: Unexpected request/fixture failures fail the test.
    @Test func messageCreationFields() throws {
        let mentions = try MessageAllowedMentions(parse: [], repliedUser: false)
        let poll = try PollCreate(question: "Question?", answers: [PollMedia(text: .value("Yes"))])
        let embed = try MessageEmbed(data: Data(#"{"title":"embed"}"#.utf8))
        let message = try InteractionMessageCreate(content: .value("response"), tts: .value(false), embeds: .value([embed]),
            allowedMentions: .value(mentions), components: .value([]), attachments: .value([]),
            flags: .value([.ephemeral, .suppressEmbeds, .suppressNotifications]), poll: .value(poll))
        let value = try message.jsonValue()
        guard case .object(let fields) = value else { Issue.record("Expected message"); return }
        #expect(fields["content"] == .string("response"))
        #expect(fields["tts"] == .bool(false))
        #expect(fields["embeds"] == .array([embed.jsonValue()]))
        #expect(fields["allowed_mentions"] == mentions.jsonValue())
        #expect(fields["components"] == .array([]))
        #expect(fields["attachments"] == .array([]))
        #expect(try fields["poll"] == poll.jsonValue())
        #expect(message.flags == .value(.init(rawValue: 4_164)))
        #expect(fields["flags"] == .number(try JSONNumber(rawValue: "4164")))
        #expect(Set(fields.keys) == ["content", "tts", "embeds", "allowed_mentions", "components", "attachments", "poll", "flags"])
        #expect(message.description == message.debugDescription)
        #expect(message.customMirror.children.count == 1)
        #expect(!String(reflecting: message).contains("Question?"))
        #expect(try InteractionMessageCreate(content: .value("zero"), flags: .value([])).jsonValue() != .object([:]))
        #expect(throws: DiscordError.validation(.missingValue)) { try InteractionMessageCreate().jsonValue() }
        #expect(throws: DiscordError.validation(.invalidValue)) { try InteractionMessageCreate(content: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try InteractionMessageCreate(flags: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try InteractionMessageCreate(flags: .value(.init(rawValue: UInt64.max))) }
        #expect(throws: DiscordError.validation(.limitExceeded)) { try InteractionMessageCreate(content: .value(String(repeating: "x", count: 2_001))) }
    }

    /// File-only and voice responses validate the actual upload IDs/media types, while V2 excludes traditional content.
    /// - Throws: Unexpected valid-request failures fail the test.
    @Test func uploadsVoiceAndComponentsV2() throws {
        let file = try MessageAttachmentRequest(id: .upload(0), filename: "voice.ogg", durationSecs: 2, waveform: "AA==")
        let voice = try InteractionMessageCreate(attachments: .value([file]), flags: .value([.isVoiceMessage, .ephemeral]))
        #expect(try voice.jsonValue(uploadIDs: [0], uploadContentTypes: [0: "audio/ogg"]) != .object([:]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try voice.jsonValue(uploadIDs: [0], uploadContentTypes: [0: "text/plain"]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try voice.jsonValue(uploadIDs: [1], uploadContentTypes: [1: "audio/ogg"]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try voice.jsonValue(uploadIDs: [0, 0]) }
        let fileOnly = try InteractionMessageCreate()
        #expect(try fileOnly.jsonValue(uploadIDs: [0]) == .object([:]))
        let display = try MessageComponent(data: Data(#"{"type":10,"content":"component response"}"#.utf8))
        let v2 = try InteractionMessageCreate(components: .value([display]), flags: .value([.isComponentsV2, .ephemeral]))
        guard case .object(let fields) = try v2.jsonValue() else { Issue.record("Expected V2"); return }
        #expect(fields["flags"] == .number(try JSONNumber(rawValue: "32832")))
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try InteractionMessageCreate(content: .value("cannot combine"), components: .value([display]), flags: .value(.isComponentsV2))
        }
    }

    /// Edits preserve nullable fields and retained uploads, reject illegal immutable visibility changes,
    /// and permit new polls exclusively when the caller explicitly identifies an original deferred response.
    /// - Throws: Unexpected request/fixture failures fail the test.
    @Test func editsAndDeferredPolls() throws {
        let empty = try InteractionMessageEdit()
        #expect(try empty.jsonValue() == .object([:]))
        #expect(!empty.deferredResponse)
        #expect(empty.poll == .absent)
        #expect(empty.description == empty.debugDescription)
        #expect(empty.customMirror.children.count == 1)
        let cleared = try InteractionMessageEdit(content: .null, embeds: .null, allowedMentions: .null,
            components: .null, attachments: .null, flags: .null, poll: .null)
        #expect(try cleared.jsonValue() == .object(["content": .null, "embeds": .null, "allowed_mentions": .null,
            "components": .null, "attachments": .null, "flags": .null, "poll": .null]))
        let poll = try PollCreate(question: "Question?", answers: [PollMedia(text: .value("Yes"))])
        #expect(throws: DiscordError.validation(.invalidValue)) { try InteractionMessageEdit(poll: .value(poll)) }
        let deferred = try InteractionMessageEdit(poll: .value(poll), deferredResponse: true)
        #expect(deferred.deferredResponse)
        #expect(try deferred.jsonValue() == .object(["poll": poll.jsonValue()]))
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try InteractionMessageEdit(poll: .value(poll), deferredResponse: true, previousFlags: 1 << 15)
        }
        let retained = try InteractionMessageEdit(flags: .value(.init(rawValue: 68)), previousFlags: 64)
        #expect(try retained.jsonValue() == .object(["flags": .number(JSONNumber(rawValue: "68"))]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try InteractionMessageEdit(flags: .value([]), previousFlags: 64) }
        let attachment = try MessageAttachmentRequest(id: .upload(0), filename: "new.txt")
        let update = try InteractionMessageEdit(attachments: .value([attachment]))
        #expect(try update.jsonValue(uploadIDs: [0]) != .object([:]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try update.jsonValue() }
        #expect(throws: DiscordError.validation(.missingValue)) { try empty.jsonValue(uploadIDs: [0]) }
        let migrated = try InteractionMessageEdit(content: .null, embeds: .value([]), flags: .value(.isComponentsV2), poll: .null)
        guard case .object(let migratedFields) = try migrated.jsonValue() else { Issue.record("Expected migration"); return }
        #expect(migratedFields["sticker_ids"] == nil)
        #expect(migratedFields["poll"] == .null)
    }

    /// All current modal input kinds validate when wrapped in a label; text displays and legacy rows remain supported.
    /// Numeric IDs are globally unique except zero, custom IDs are unique, and valid output retains exact object fields.
    /// - Parameter child: Independently authored minimal valid child definition for every current modal kind.
    /// - Throws: Unexpected valid modal failures fail the test.
    @Test(arguments: [#"{"type":3,"custom_id":"input","options":[{"label":"one","value":"1"}]}"#, #"{"type":4,"custom_id":"input","style":1,"min_length":0,"max_length":4000,"placeholder":"prompt","value":"preset","required":false}"#, #"{"type":5,"custom_id":"input","default_values":[{"id":"18446744073709551615","type":"user"}]}"#, #"{"type":6,"custom_id":"input","default_values":[{"id":"1","type":"role"}]}"#, #"{"type":7,"custom_id":"input","default_values":[{"id":"1","type":"user"}]}"#, #"{"type":8,"custom_id":"input","channel_types":[0,2],"default_values":[{"id":"1","type":"channel"}]}"#, #"{"type":19,"custom_id":"input","min_values":0,"max_values":10,"required":false,"file_types":["image",".pdf"]}"#, #"{"type":21,"custom_id":"input","options":[{"label":"one","value":"1","default":true},{"label":"two","value":"2"}]}"#, #"{"type":22,"custom_id":"input","options":[{"label":"one","value":"1"}],"min_values":0,"required":false}"#, #"{"type":23,"custom_id":"input","default":false}"#])
    func validModalChildren(child: String) throws {
        let component = try MessageComponent(data: Data(#"{"type":18,"id":1,"label":"Input","description":"description","component":\#(child)}"#.utf8))
        let display = try MessageComponent(data: Data(#"{"type":10,"id":0,"content":"Information"}"#.utf8))
        let modal = try InteractionModal(customID: "modal", title: "Modal", components: [display, component, display])
        #expect(try JSONValue.parse(modal.jsonValue().serialized()) == modal.jsonValue())
        #expect(modal.jsonValue() == .object(["custom_id": .string("modal"), "title": .string("Modal"),
            "components": .array([try display.jsonValue(), try component.jsonValue(), try display.jsonValue()])]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try InteractionModal(customID: "m", title: "m", components: [component, component]) }
        let row = try MessageComponent(data: Data(#"{"type":1,"components":[{"type":4,"custom_id":"legacy","style":2,"label":"Legacy"}]}"#.utf8))
        #expect(try InteractionModal(customID: "legacy", title: "Legacy", components: [row]).jsonValue() != .object([:]))
    }

    /// Wrong modal placement, unknown fields, invalid bounds/defaults/filters and duplicate values are rejected locally.
    /// - Parameter child: Independently authored invalid label child which still satisfies incoming component typing.
    /// - Throws: Unexpected component-projection errors fail the test; modal validation must reject every fixture.
    @Test(arguments: [#"{"type":2,"custom_id":"input","style":1,"label":"button"}"#, #"{"type":99,"custom_id":"input"}"#, #"{"type":4,"custom_id":"input","style":3}"#, #"{"type":4,"custom_id":"input","style":1,"min_length":4000,"max_length":1}"#, #"{"type":4,"custom_id":"input","style":1,"disabled":false}"#, #"{"type":3,"custom_id":"input","options":[]}"#, #"{"type":3,"custom_id":"input","options":[{"label":"a","value":"a"}],"max_values":2}"#, #"{"type":3,"custom_id":"input","options":[{"label":"a","value":"a"}],"min_values":0}"#, #"{"type":5,"custom_id":"input","default_values":[{"id":"1","type":"role"}]}"#, #"{"type":5,"custom_id":"input","default_values":[{"id":"1","type":"user"},{"id":"1","type":"user"}]}"#, #"{"type":8,"custom_id":"input","channel_types":[99]}"#, #"{"type":19,"custom_id":"input","file_types":[".PDF",".pdf"]}"#, #"{"type":19,"custom_id":"input","file_types":[".a/b"]}"#, #"{"type":19,"custom_id":"input","file_types":["invalid"]}"#, #"{"type":19,"custom_id":"input","min_values":11}"#, #"{"type":21,"custom_id":"input","options":[{"label":"a","value":"a"}]}"#, #"{"type":21,"custom_id":"input","options":[{"label":"a","value":"a","default":true},{"label":"b","value":"b","default":true}]}"#, #"{"type":21,"custom_id":"input","options":[{"label":"a","value":"a"},{"label":"b","value":"a"}]}"#, #"{"type":22,"custom_id":"input","options":[{"label":"a","value":"a","emoji":{"name":"x"}}]}"#, #"{"type":23,"custom_id":"input","required":false}"#])
    func invalidModalChildren(child: String) throws {
        let label = try MessageComponent(data: Data(#"{"type":18,"label":"Input","component":\#(child)}"#.utf8))
        #expect(throws: DiscordError.validation(.invalidValue)) { try InteractionModal(customID: "m", title: "Modal", components: [label]) }
    }

    /// Root modal identity/title/count boundaries and container structure are checked independently of input projection.
    /// - Throws: Unexpected valid fixture failures fail the test.
    @Test func modalRootBounds() throws {
        let display = try MessageComponent(data: Data(#"{"type":10,"content":"Info"}"#.utf8))
        #expect(try InteractionModal(customID: String(repeating: "x", count: 100), title: String(repeating: "t", count: 45),
            components: Array(repeating: display, count: 5)).jsonValue() != .object([:]))
        for customID in ["", String(repeating: "x", count: 101)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try InteractionModal(customID: customID, title: "Title", components: [display]) }
        }
        for title in ["", String(repeating: "x", count: 46)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try InteractionModal(customID: "m", title: title, components: [display]) }
        }
        for count in [0, 6] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try InteractionModal(customID: "m", title: "Title", components: Array(repeating: display, count: count)) }
        }
        for invalid in [#"{"type":1,"components":[]}"#, #"{"type":18,"label":"Input"}"#,
                        #"{"type":18,"label":"Input","component":{"type":10,"content":"no nested display"}}"#,
                        #"{"type":10,"content":"Info","future":true}"#] {
            let component = try MessageComponent(data: Data(invalid.utf8))
            #expect(throws: DiscordError.validation(.invalidValue)) { try InteractionModal(customID: "m", title: "Title", components: [component]) }
        }
    }

    /// Builds the complete written callback catalog with independently authored minimal valid payloads.
    /// - Returns: Nine variants in discriminator order, including the deprecated premium callback.
    /// - Throws: Unexpected fixture/model validation errors.
    static func responses() throws -> [InteractionResponse] {
        let display = try MessageComponent(data: Data(#"{"type":10,"content":"Info"}"#.utf8))
        return [.pong, .message(try InteractionMessageCreate(content: .value("response"))), .deferredMessage(ephemeral: true),
                .deferredUpdate, .update(try InteractionMessageEdit(content: .null)), .autocomplete([]),
                .modal(try InteractionModal(customID: "modal", title: "Modal", components: [display])), .premiumRequired, .launchActivity]
    }
}
