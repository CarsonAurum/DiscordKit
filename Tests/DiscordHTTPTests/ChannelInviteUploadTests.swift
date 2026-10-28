// File: Tests/DiscordHTTPTests/ChannelInviteUploadTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Verifies bounded channel-invite CSV construction, replay and required empty JSON bodies.
@Suite struct ChannelInviteUploadTests {
    /// No parameters still produce `{}`; CSV uses the exact named form field and preserves duplicates/CRLF.
    /// - Throws: Unexpected body construction or stream-collection errors fail the test; expected validation failures are asserted locally.
    @Test func jsonAndCSVWire() async throws {
        let empty = try channelInviteBody(ChannelInviteCreate(), csv: nil, maximumBytes: 2)
        #expect(empty.bytes == Data("{}".utf8) && empty.contentType == "application/json")
        let csv = Data("18446744073709551615\r\n42\r\n42\r\n".utf8)
        let body = try channelInviteBody(.init(maxAge: 0, roleIDs: [.init(rawValue: 1)]), csv: csv, maximumBytes: 1_048_576)
        let text = String(decoding: body.bytes, as: UTF8.self)
        #expect(text.contains("name=\"payload_json\""))
        #expect(text.contains("name=\"target_users_file\"; filename=\"users.csv\""))
        #expect(text.contains(String(decoding: csv, as: UTF8.self)))
        #expect(text.contains("\"max_age\":0") && text.contains("\"role_ids\":[\"1\"]"))
        let first = try await ResponseBody.collect(body.makeStream(), maximumBytes: 1_048_576)
        let second = try await ResponseBody.collect(body.makeStream(), maximumBytes: 1_048_576)
        #expect(first == second && first == body.bytes)
        #expect(try channelInviteBody(.init(), csv: Data("1".utf8), maximumBytes: 1_048_576).bytes.count > 1)
    }

    /// Malformed, non-UTF8, multi-column, whitespace, blank/header and out-of-range CSV rows fail before I/O.
    /// - Parameter csv: Complete invalid single-column input including empty and integer-overflow boundaries.
    /// - Throws: Unexpected body construction or stream-collection errors fail the test; expected validation failures are asserted locally.
    @Test(arguments: ["", "\n", "1\n\n", "id\n1", "1,2", "\"1\"", " 1", "1 ", "1\r2", "1\r", "\r\n", "-1", "+1", "1e2", "18446744073709551616", "99999999999999999999", "\u{FEFF}1"])
    func invalidCSV(csv: String) throws {
        #expect(throws: DiscordError.validation(.invalidValue)) { try channelInviteBody(.init(), csv: Data(csv.utf8), maximumBytes: 1_048_576) }
    }

    /// Explicit ID/CSV conflicts and complete multipart byte limits include all framing rather than file bytes alone.
    /// - Throws: Unexpected body construction or stream-collection errors fail the test; expected validation failures are asserted locally.
    @Test func conflictsAndBounds() throws {
        #expect(throws: DiscordError.validation(.invalidValue)) { try channelInviteBody(.init(targetUserIDs: []), csv: Data("1".utf8), maximumBytes: 1_048_576) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try channelInviteBody(.init(), csv: Data([255]), maximumBytes: 1_048_576) }
        for limit in [0, -1, 8_388_609, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try channelInviteBody(.init(), csv: nil, maximumBytes: limit) }
        }
        #expect(throws: (any Error).self) { try channelInviteBody(.init(), csv: nil, maximumBytes: 1) }
        #expect(throws: (any Error).self) { try channelInviteBody(.init(), csv: Data("12".utf8), maximumBytes: 1) }
        #expect(throws: DiscordError.validation(.limitExceeded)) {
            try channelInviteBody(.init(), csv: Data("123".utf8), maximumBytes: 2)
        }
        let body = try channelInviteBody(.init(), csv: Data("1\n".utf8), maximumBytes: 1_048_576)
        #expect(try channelInviteBody(.init(), csv: Data("1\n".utf8), maximumBytes: body.bytes.count).bytes == body.bytes)
        #expect(throws: DiscordError.validation(.limitExceeded)) { try channelInviteBody(.init(), csv: Data("1\n".utf8), maximumBytes: body.bytes.count - 1) }
        #expect(throws: DiscordError.self) { try channelInviteBody(.init(maxAge: -1), csv: nil, maximumBytes: 1_048_576) }
    }
}
