// File: Tests/DiscordModelsTests/ContentScanTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Exercises delayed media-scan responses and exact flag contracts with local API v10 payloads.
@Suite struct ContentScanTests {
    /// Attachment/embed flags use bits 4, 6 and 7; component-media scan flags use bits 0, 1 and 2.
    /// Unknown bits survive wrapping and repeated membership checks without authorizing outgoing fields.
    @Test func documentedContentScanBits() {
        let attachment: [(MessageAttachmentFlags, UInt64)] = [
            (.containsExplicitContent, 1 << 4), (.containsGoreContent, 1 << 6), (.containsSelfHarmContent, 1 << 7)
        ]
        let embed: [(MessageEmbedFlags, UInt64)] = [
            (.containsExplicitContent, 1 << 4), (.containsGoreContent, 1 << 6), (.containsSelfHarmContent, 1 << 7)
        ]
        let media: [(UnfurledMediaContentScanFlags, UInt64)] = [
            (.isExplicitContent, 1 << 0), (.isGoreContent, 1 << 1), (.isSelfHarmContent, 1 << 2)
        ]
        let unknown: UInt64 = 1 << 63
        for (flag, bit) in attachment {
            #expect(flag.rawValue == bit)
            #expect(MessageAttachmentFlags(rawValue: unknown | bit).contains(flag))
        }
        for (flag, bit) in embed {
            #expect(flag.rawValue == bit)
            #expect(MessageEmbedFlags(rawValue: unknown | bit).contains(flag))
        }
        for (flag, bit) in media {
            #expect(flag.rawValue == bit)
            #expect(UnfurledMediaContentScanFlags(rawValue: unknown | bit).contains(flag))
        }
        #expect(UnfurledMediaContentScanFlags(rawValue: 0).isEmpty)
        #expect(UnfurledMediaContentScanFlags(rawValue: .max).rawValue == .max)
        #expect(UnfurledMediaContentScanFlags(rawValue: unknown).rawValue == unknown)
    }

    /// Metadata preserves zero, every future flag bit and unknown exact numeric fields while redacting diagnostics.
    /// - Parameter flags: Boundary and combined bitfields encoded as exact unsigned JSON integers.
    /// - Throws: Unexpected parser, bounded-codec or assertion failures fail the test.
    @Test(arguments: [UInt64(0), 7, UInt64.max])
    func metadataBoundariesAndUnknownFields(flags: UInt64) throws {
        let data = Data("{\"flags\":\(flags),\"future_secret\":1.2300e1000}".utf8)
        let metadata = try UnfurledMediaContentScanMetadata(data: data)
        #expect(metadata.flags == flags)
        #expect(metadata.rawFields["future_secret"] == .number(try JSONNumber(rawValue: "1.2300e1000")))
        #expect(try UnfurledMediaContentScanMetadata(data: JSONValue.object(metadata.rawFields).serialized()) == metadata)
        #expect(metadata.description == "UnfurledMediaContentScanMetadata(redacted)")
        #expect(metadata.debugDescription == metadata.description)
        #expect(metadata.customMirror.children.count == 1)
        #expect(throws: JSONValueError.maximumBytesExceeded) {
            try UnfurledMediaContentScanMetadata(data: data, limits: JSONLimits(maximumBytes: 1))
        }
        #expect(throws: JSONValueError.maximumNodesExceeded) {
            try UnfurledMediaContentScanMetadata(data: data, limits: JSONLimits(maximumNodes: 1))
        }
    }

    /// Required scan flags reject null, incompatible types, overflow and nonintegral numeric spellings.
    /// - Parameter json: One complete malformed scan-metadata object.
    @Test(arguments: ContentScanTests.malformedResponses)
    func malformedMetadata(json: String) {
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try UnfurledMediaContentScanMetadata(data: Data(json.utf8))
        }
    }

    /// Unscanned media keeps metadata absent; a later component response exposes typed scan results.
    /// Response-only metadata is retained for inspection and rejected by outgoing component validation.
    /// - Throws: Unexpected component, metadata or bounded-parser failures fail the test.
    @Test func componentScanPresenceAndResponseOnlyContract() throws {
        let unscanned = try UnfurledMediaItem(data: Data("{\"url\":\"attachment://image.png\"}".utf8))
        #expect(unscanned.contentScanMetadata == .absent)
        let json = "{\"type\":11,\"media\":{\"url\":\"attachment://image.png\",\"content_scan_metadata\":{\"flags\":7,\"future\":true}}}"
        let component = try MessageComponent(data: Data(json.utf8))
        guard case .value(let media) = component.media, case .value(let metadata) = media.contentScanMetadata
        else { Issue.record("Missing media scan metadata"); return }
        #expect(metadata.flags == 7)
        #expect(metadata.rawFields["future"] == .bool(true))
        #expect(try component.jsonValue() == JSONValue.parse(json))
        let section = try MessageComponent(data: Data("{\"type\":9,\"components\":[{\"type\":10,\"content\":\"Image\"}],\"accessory\":\(json)}".utf8))
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try MessageComponent.validateMessage([section], componentsV2: true)
        }
        for invalid in ["null", "[]", "{}", "{\"flags\":null}"] {
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try UnfurledMediaItem(data: Data("{\"url\":\"u\",\"content_scan_metadata\":\(invalid)}".utf8))
            }
        }
        #expect(throws: JSONValueError.maximumDepthExceeded) {
            try UnfurledMediaItem(data: Data("{\"url\":\"u\",\"content_scan_metadata\":{\"flags\":0}}".utf8),
                                  limits: JSONLimits(maximumDepth: 1))
        }
    }

    /// An interaction upload can lack flags, while a later Message Update independently supplies scan results.
    /// Sparse updates preserve omitted message content and exact unknown bits across attachments, embeds and components.
    /// - Throws: Unexpected resolved-data, update-payload or required-value assertion failures fail the test.
    @Test func delayedScanResultsInMessageUpdates() throws {
        let attachment = "{\"id\":\"18446744073709551615\",\"filename\":\"image.png\",\"size\":1,\"url\":\"https://example.test/image\",\"proxy_url\":\"https://proxy.test/image\"}"
        let resolved = try InteractionResolvedData(data: Data("{\"attachments\":{\"18446744073709551615\":\(attachment)}}".utf8))
        guard case .value(let uploads) = resolved.attachments else { Issue.record("Missing resolved uploads"); return }
        #expect(uploads["18446744073709551615"]?.flags == .absent)
        guard case .object(var fields) = try JSONValue.parse(attachment)
        else { Issue.record("Expected attachment object fixture"); return }
        let flags = try JSONValue.parse("9223372036854776016")
        fields["flags"] = flags
        let value = JSONValue.object([
            "id": .string("18446744073709551615"), "channel_id": .string("2"),
            "attachments": .array([.object(fields)]), "embeds": .array([.object(["flags": flags])]),
            "components": .array([try JSONValue.parse("{\"type\":12,\"items\":[{\"media\":{\"url\":\"attachment://image.png\",\"content_scan_metadata\":{\"flags\":7}}}]}")])
        ])
        let update = try GatewayMessageUpdate(data: value.serialized())
        #expect(update.id.rawValue == UInt64.max)
        #expect(update.content == .absent)
        guard case .value(let attachments) = update.attachments, case .value(let embeds) = update.embeds,
              case .value(let components) = update.components
        else { Issue.record("Missing delayed scan response"); return }
        let component = try #require(components.first)
        guard case .value(let items) = component.items else { Issue.record("Missing gallery items"); return }
        let item = try #require(items.first)
        guard case .value(let metadata) = item.media.contentScanMetadata
        else { Issue.record("Missing delayed component scan metadata"); return }
        let expected: UInt64 = (1 << 63) | (1 << 4) | (1 << 6) | (1 << 7)
        #expect(attachments.first?.flags == .value(expected))
        #expect(embeds.first?.flags == .value(expected))
        #expect(metadata.flags == 7)
        #expect(update.jsonValue() == value)
        #expect(try GatewayMessageUpdate(data: value.serialized()) == update)
    }

    /// Invalid scan responses covering required flags, incompatible scalar types, overflow and exact integer spelling.
    static let malformedResponses = [
        "[]", "{}", "{\"flags\":null}", "{\"flags\":\"1\"}", "{\"flags\":true}",
        "{\"flags\":-1}", "{\"flags\":1.5}", "{\"flags\":1e0}", "{\"flags\":18446744073709551616}"
    ]
}
