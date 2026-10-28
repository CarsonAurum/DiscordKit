// File: Tests/DiscordMLSTests/MLSMessagesTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordMLS

/// Independent upstream transcript/framing evidence and strict DAVE message boundaries.
@Suite struct MLSMessagesTests {
    /// Verifies the MLSWG suite-2 transcript known answer, preserving exact framed content,
    /// reference-only Commit, signature, confirmation vector and interim-transcript hash.
    /// Source: https://github.com/mlswg/mls-implementations/blob/main/test-vectors/transcript-hashes.json
    @Test func publishedTranscriptHashes() throws {
        let authenticated = hex("00010567726f7570000000000000345601000000000003220220e740a6faf2db65f5853148d75d9a335d7c4b94ab106fe5f237bc34fdcfc74584004046304402206f5ac008efb1d7edc106a27b4f3b71aa34821ca679543fd8bde8d728517b53bc0220223fb7226cc477e31ea25910d712fc915ce3df9f0399e0e7615babd593e2cdbb20fc804973ae28d04b9f3b71930414e29aa508f0711df720519f230e43a534b714")
        let message = try MLSPublicMessage.decode(Data([0, 1]) + authenticated + Data([0]))
        #expect(try message.authenticatedContent() == authenticated)
        let previous = hex("de0a78a0008b6c5c921c910d68da44abe0e692e1eea7e9f8226219ca34560f0d")
        let confirmed = MLSCipherSuite2.hash(try previous + message.transcriptInput())
        #expect(confirmed == hex("e50ae43acf8ba84f712d8f48fa6ccd4768e48fad9c95feaf3061c54fe87a2779"))
        #expect(MLSCipherSuite2.verifyMAC(key: hex("6999e1655b7f4bdda3cf2991965d889a331b487526a9c99c19d1060e4d677996"), content: confirmed, tag: message.confirmationTag))
        #expect(try mlsInterimTranscript(confirmed: confirmed, confirmation: message.confirmationTag) == hex("87829eecb1aadfa10cbe2630fcc7ae9769d7fb2520f27b44ef76341c43ad834b"))
        #expect(try message.encoded() == Data([0, 1]) + authenticated + Data([0]))
    }

    /// Rejects unsupported proposal/sender/wire/version forms and incomplete messages,
    /// and confirms the reference-only Commit format rejects inline and repeated entries.
    @Test func malformedMessageBoundaries() throws {
        #expect(throws: MLSError.unsupportedVersion) { try MLSPublicMessage.decode(Data([0, 2])) }
        #expect(throws: MLSError.invalidCommit) { try MLSPublicMessage.decode(Data([0, 1, 0, 2])) }
        for bytes in [Data(), Data([0]), Data([0, 1, 0])] {
            #expect(throws: MLSError.malformedEncoding) { try MLSPublicMessage.decode(bytes) }
        }
        var sender = try MLSReader(Data([3])); #expect(throws: MLSError.invalidCommit) { try MLSSender.decode(&sender) }
        var proposal = try MLSReader(Data([0, 2])); #expect(throws: MLSError.invalidProposal) { try MLSProposal.decode(&proposal) }
        var inline = try MLSReader(Data([1, 1, 0])); #expect(throws: MLSError.invalidCommit) { try MLSCommit.decode(&inline) }
        var body = MLSWriter(); var repeated = MLSWriter()
        for _ in 0..<2 { repeated.write(UInt8(2)); try repeated.writeVector(Data(count: 32)) }
        try body.writeVector(repeated.data); body.write(UInt8(0))
        var cursor = try MLSReader(body.data); #expect(throws: MLSError.invalidCommit) { try MLSCommit.decode(&cursor) }
        #expect(throws: MLSError.invalidCommit) { try MLSCommit(references: [Data(count: 31)], path: nil).encoded() }
        #expect(throws: MLSError.invalidCommit) { try MLSCommit(references: Array(repeating: Data(count: 32), count: 1025), path: nil).encoded() }
    }

    /// Decodes a published vector's fixed hexadecimal without text normalization.
    /// - Parameter value: Even-length hexadecimal string with valid byte pairs.
    /// - Returns: Exact vector bytes, including empty data for an empty string.
    private func hex(_ value: String) -> Data {
        let characters = Array(value.utf8); var result = Data()
        for index in stride(from: 0, to: characters.count, by: 2) {
            result.append(UInt8(String(decoding: characters[index...index + 1], as: UTF8.self), radix: 16)!)
        }
        return result
    }
}
