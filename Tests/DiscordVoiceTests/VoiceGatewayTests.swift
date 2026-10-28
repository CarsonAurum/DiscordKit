// File: Tests/DiscordVoiceTests/VoiceGatewayTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordTransport
import Foundation
import Testing
@testable import DiscordVoice

/// Exact framing, direction, bound, and redaction coverage using local synthetic v8 messages.
@Suite("Voice Gateway framing")
struct VoiceGatewayTests {
    /// Exercises every documented opcode's declared encoding and sender, including all DAVE opcodes.
    /// - Parameter opcode: Each public catalog case; symmetric Speaking is valid in both directions.
    @Test(arguments: VoiceGatewayOpcode.allCases)
    func catalog(_ opcode: VoiceGatewayOpcode) throws {
        #expect(opcode.isBinary == (25...30).contains(opcode.rawValue))
        for direction in [VoiceGatewayDirection.clientToServer, .serverToClient] {
            let allowed = direction == .clientToServer ? opcode.isClientSent : opcode.isServerSent
            let message: WebSocketMessage
            if opcode.isBinary {
                let prefix: [UInt8] = direction == .serverToClient ? [0x12, 0x34, opcode.rawValue] : [opcode.rawValue]
                message = .binary(Data(prefix + [0xA5]))
            } else { message = .text("{\"op\":\(opcode.rawValue),\"d\":null}") }
            if allowed {
                let frame = try VoiceGatewayFrame(message, direction: direction)
                #expect(frame.opcode == opcode.rawValue)
                #expect(try VoiceGatewayFrame(frame.message(), direction: direction) == frame)
            } else { #expect(throws: VoiceControlFailure.invalidPayload) { try VoiceGatewayFrame(message, direction: direction) } }
        }
        let wrongEncoding: WebSocketMessage = opcode.isBinary
            ? .text("{\"op\":\(opcode.rawValue),\"d\":null}")
            : .binary(Data(opcode.isServerSent ? [0, 0, opcode.rawValue] : [opcode.rawValue]))
        #expect(throws: VoiceControlFailure.unsupportedEncoding) {
            try VoiceGatewayFrame(wrongEncoding, direction: opcode.isServerSent ? .serverToClient : .clientToServer)
        }
    }

    /// Preserves arbitrary future payload numbers, unknown envelope members, and explicit null data.
    @Test func exactJSONAndFutureOpcodes() throws {
        let source = "{\"op\":255,\"d\":{\"id\":18446744073709551615,\"future\":1.2300e999},\"seq\":65535,\"extra\":null}"
        let frame = try VoiceGatewayFrame(.text(source))
        #expect(frame.sequence == 65535)
        #expect(frame.rawFields?["extra"] == .null)
        #expect(try JSONValue.parse({
            guard case .text(let text) = try frame.message() else { return "null" }; return text
        }()) == JSONValue.parse(source))
        #expect(try VoiceGatewayFrame(.text("{\"op\":255,\"d\":null}")).payload == .json(.null))
        let command = try VoiceGatewayFrame(opcode: 255, data: .object(["x": .number(JSONNumber(rawValue: "-0.00"))]))
        #expect(try VoiceGatewayFrame(command.message(), direction: .clientToServer) == command)
        #expect(VoiceGatewayFrame.version == 8)
    }

    /// Rejects malformed envelope shapes, missing data, invalid sequences, and nonintegral opcodes.
    /// - Parameter source: A complete but invalid server envelope; no partial frame may escape.
    @Test(arguments: ["null", "[]", "{\"op\":8}", "{\"op\":-1,\"d\":null}",
        "{\"op\":256,\"d\":null}", "{\"op\":8.0,\"d\":null}", "{\"op\":\"8\",\"d\":null}",
        "{\"op\":8,\"d\":null,\"seq\":null}", "{\"op\":8,\"d\":null,\"seq\":-1}",
        "{\"op\":8,\"d\":null,\"seq\":65536}", "{\"op\":8,\"d\":null,\"seq\":false}"])
    func invalidEnvelope(_ source: String) {
        #expect(throws: VoiceControlFailure.invalidPayload) { try VoiceGatewayFrame(.text(source)) }
    }

    /// Covers binary server sequence endianness, empty bodies, minimum frame lengths, and tight bounds.
    @Test func binaryBoundsAndFraming() throws {
        let message = WebSocketMessage.binary(Data([0xFF, 0xFE, 29, 0, 10, 0xAB, 0xCD]))
        let frame = try VoiceGatewayFrame(message)
        #expect(frame.sequence == 65534)
        #expect(frame.payload == .binary(Data([0, 10, 0xAB, 0xCD])))
        #expect(try frame.message(limits: JSONLimits(maximumBytes: 7)) == message)
        #expect(throws: JSONValueError.maximumBytesExceeded) { try frame.message(limits: JSONLimits(maximumBytes: 6)) }
        #expect(throws: JSONValueError.maximumBytesExceeded) {
            try VoiceGatewayFrame(message, limits: JSONLimits(maximumBytes: 6))
        }
        for count in 0..<3 {
            #expect(throws: VoiceControlFailure.invalidPayload) { try VoiceGatewayFrame(.binary(Data(repeating: 0, count: count))) }
        }
        let empty = try VoiceGatewayFrame(.binary(Data([26])), direction: .clientToServer,
            limits: JSONLimits(maximumBytes: 1))
        #expect(empty.payload == .binary(Data()))
        #expect(try empty.message(limits: JSONLimits(maximumBytes: 1)) == .binary(Data([26])))
        let future = try VoiceGatewayFrame(.binary(Data([0, 0, 250])))
        #expect(future.sequence == 0)
        #expect(future.opcode == 250)
    }

    /// A bounded slice with a nonzero index round-trips independently of its large caller-owned backing.
    /// The parser's explicit owned copy prevents retention of the larger allocation behind that slice.
    @Test func sliceBackedBinaryPayload() throws {
        var backing = Data(repeating: 0xAA, count: 1_048_576)
        let start = 500_000
        backing.replaceSubrange(start..<(start + 3), with: [0x12, 0x34, 29])
        let source = backing[start..<(start + 259)]
        let frame = try VoiceGatewayFrame(.binary(source), limits: JSONLimits(maximumBytes: 259))
        #expect(frame.sequence == 0x1234 && frame.opcode == 29)
        #expect(frame.payload == .binary(Data(repeating: 0xAA, count: 256)))
        backing.replaceSubrange(start..<(start + 259), with: Data(repeating: 0, count: 259))
        #expect(try frame.message(limits: JSONLimits(maximumBytes: 259)) == .binary(source))
    }

    /// Applies JSON byte/depth/node limits to both parse and command construction, without lossy fallback.
    @Test func jsonLimitsAndClientValidation() throws {
        #expect(throws: JSONValueError.maximumBytesExceeded) {
            try VoiceGatewayFrame(.text("{\"op\":8,\"d\":null}"), limits: JSONLimits(maximumBytes: 4))
        }
        #expect(throws: JSONValueError.maximumDepthExceeded) {
            try VoiceGatewayFrame(.text("{\"op\":8,\"d\":{}}"), limits: JSONLimits(maximumDepth: 1))
        }
        #expect(throws: JSONValueError.maximumNodesExceeded) {
            try VoiceGatewayFrame(opcode: 0, data: .array([.null]), limits: JSONLimits(maximumNodes: 2))
        }
        #expect(throws: JSONValueError.invalidLimits) {
            try VoiceGatewayFrame(.binary(Data([26])), direction: .clientToServer, limits: JSONLimits(maximumBytes: 0))
        }
        #expect(throws: VoiceControlFailure.invalidPayload) { try VoiceGatewayFrame(opcode: 8, data: .null) }
        #expect(throws: VoiceControlFailure.unsupportedEncoding) { try VoiceGatewayFrame(opcode: 26, data: .null) }
        #expect(throws: VoiceControlFailure.invalidPayload) {
            try VoiceGatewayFrame(.text("{\"op\":0,\"d\":null,\"seq\":1}"), direction: .clientToServer)
        }
    }

    /// Ensures generic descriptions/reflection cannot reveal token-bearing payloads.
    @Test func redactedDiagnostics() throws {
        let frame = try VoiceGatewayFrame(opcode: 0, data: .string("secret-session-token"))
        #expect(frame.description == "VoiceGatewayFrame(redacted)")
        #expect(frame.customMirror.children.count == 1)
        #expect(!String(reflecting: frame).contains("secret-session-token"))
    }
}
