// File: Tests/DiscordRPCTests/RPCFramingTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordTransport
import DiscordTestSupport
import Foundation
import Testing
@testable import DiscordRPC

/// Synthetic frame tests exercise byte boundaries without a running desktop client.
@Suite struct RPCFramingTests {
    /// Round trips every opcode with opaque bytes under every possible two-fragment split.
    /// - Parameter opcode: Each documented opcode; ping/pong deliberately contain non-JSON data.
    /// - Throws: Unexpected valid-frame encoding or incremental parsing failure.
    @Test(arguments: RPCOpcode.allCases) func splitFrames(opcode: RPCOpcode) throws {
        let frame = RPCFrame(opcode: opcode, payload: Data([0, 255, 1, 128]))
        let encoded = try frame.encoded(maximumPayloadBytes: 4)
        #expect(Array(encoded.prefix(8)) == [UInt8(opcode.rawValue), 0, 0, 0, 4, 0, 0, 0])
        for split in 0...encoded.count {
            var decoder = try RPCFrameDecoder(maximumPayloadBytes: 4)
            let first = try decoder.append(Data(encoded.prefix(split)))
            let second = try decoder.append(Data(encoded.dropFirst(split)))
            #expect(first + second == [frame])
            try decoder.finish()
        }
        #expect(!String(reflecting: frame).contains("255"))
        #expect(frame.customMirror.children.count == 1)
    }

    /// Decodes coalesced zero-length frames, byte-at-a-time input and a retained trailing fragment.
    /// - Throws: Unexpected valid-frame failures.
    @Test func coalescingAndTruncation() throws {
        let empty = RPCFrame(opcode: .pong, payload: Data())
        let bytes = try empty.encoded() + empty.encoded()
        var decoder = try RPCFrameDecoder(maximumPayloadBytes: 32)
        #expect(try decoder.append(bytes) == [empty, empty])
        #expect(try decoder.append(Data()).isEmpty)
        var frames: [RPCFrame] = []
        for byte in bytes { frames += try decoder.append(Data([byte])) }
        #expect(frames == [empty, empty])
        _ = try decoder.append(Data([1]))
        #expect(throws: RPCFailure.malformedFrame) { try decoder.finish() }
    }

    /// Incomplete secret-bearing frame buffers never expand through diagnostic reflection.
    /// - Throws: Unexpected partial-frame admission failure.
    @Test func partialBufferRedaction() throws {
        let secret = "private-authorization-code"
        var decoder = try RPCFrameDecoder()
        let bytes = try RPCFrame(opcode: .frame, payload: Data(secret.utf8)).encoded()
        #expect(try decoder.append(Data(bytes.dropLast())).isEmpty)
        var output = ""; dump(decoder, to: &output)
        #expect(!output.contains(secret))
        #expect(decoder.description == "RPCFrameDecoder(redacted)")
        #expect(decoder.debugDescription == decoder.description)
        #expect(decoder.customMirror.children.count == 1)
        decoder.reset(); decoder.reset()
        try decoder.finish()
        #expect(try decoder.append(bytes) == [.init(opcode: .frame, payload: Data(secret.utf8))])
        decoder.reset(); try decoder.finish()
    }

    /// Rejects unsafe caps, UInt32 length attacks and unknown opcodes before buffering bodies.
    /// - Throws: Unexpected decoder setup failure for valid bounds.
    @Test func malformedAndOversized() throws {
        for limit in [0, -1, Int.max] {
            #expect(throws: RPCFailure.invalidConfiguration) { try RPCFrameDecoder(maximumPayloadBytes: limit) }
            #expect(throws: RPCFailure.invalidConfiguration) { try RPCFrame(opcode: .frame, payload: Data()).encoded(maximumPayloadBytes: limit) }
        }
        var decoder = try RPCFrameDecoder(maximumPayloadBytes: 16)
        #expect(throws: RPCFailure.frameTooLarge) { try decoder.append(Data([1, 0, 0, 0, 255, 255, 255, 255])) }
        #expect(throws: RPCFailure.malformedFrame) { try decoder.append(Data([5, 0, 0, 0, 0, 0, 0, 0])) }
        #expect(throws: RPCFailure.frameTooLarge) { try decoder.append(Data(repeating: 0, count: 25)) }
        #expect(throws: RPCFailure.frameTooLarge) { try RPCFrame(opcode: .frame, payload: Data(count: 17)).encoded(maximumPayloadBytes: 16) }
        try decoder.finish()
    }

    /// Verifies documented environment precedence, absolute paths and bounded Windows discovery names.
    /// - Throws: Unexpected candidate construction error.
    @Test func discovery() throws {
        let env = ["XDG_RUNTIME_DIR": "/run/user/123/", "TMPDIR": "/other", "TMP": "/third", "TEMP": "/fourth"]
        #expect(try RPCDiscovery.ipcCandidates(platform: .unix, environment: env, indices: 2..<4) == ["/run/user/123/discord-ipc-2", "/run/user/123/discord-ipc-3"])
        #expect(try RPCDiscovery.ipcCandidates(platform: .unix, environment: ["TMPDIR": "", "TMP": "/selected"], indices: 0..<1) == ["/selected/discord-ipc-0"])
        #expect(try RPCDiscovery.ipcCandidates(platform: .unix, environment: [:], indices: 0..<1) == ["/tmp/discord-ipc-0"])
        #expect(try RPCDiscovery.ipcCandidates(platform: .unix, environment: ["TEMP": "/"], indices: 0..<1) == ["/discord-ipc-0"])
        #expect(try RPCDiscovery.ipcCandidates(platform: .windows, environment: [:], indices: 0..<1) == ["\\\\?\\pipe\\discord-ipc-0"])
        for bad in ["relative", "/bad\0path"] {
            #expect(throws: RPCFailure.invalidConfiguration) { try RPCDiscovery.ipcCandidates(platform: .unix, environment: ["TMPDIR": bad]) }
        }
        for range in [0..<0, -1..<2, 0..<101] {
            #expect(throws: RPCFailure.invalidConfiguration) { try RPCDiscovery.ipcCandidates(platform: .windows, environment: [:], indices: range) }
        }
    }

    /// Adapts a coalesced byte script, writes the exact v1 handshake and reports truncated EOF.
    /// - Throws: Unexpected adapter errors.
    @Test func ipcConnection() async throws {
        let context = TransportContext(clock: ContinuousClock())
        let one = RPCFrame(opcode: .ping, payload: Data([255]))
        let stream = try ScriptedIPCTransport(incoming: one.encoded() + one.encoded())
        let wire = try RPCIPCConnection(transport: stream)
        try await wire.handshake(applicationID: ApplicationID(rawValue: UInt64.max), context: context)
        var decoder = try RPCFrameDecoder()
        let frames = try decoder.append(await stream.written)
        #expect(frames.first?.opcode == .handshake)
        #expect(try JSONValue.parse(#require(frames.first?.payload)) == .object(["v": .number(try JSONNumber(rawValue: "1")), "client_id": .string(String(UInt64.max))]))
        #expect(try await wire.receive(context: context) == one)
        #expect(try await wire.receive(context: context) == one)
        #expect(try await wire.receive(context: context) == nil)
        await wire.close(); await wire.close()
        #expect(try await wire.receive(context: context) == nil)
        await #expect(throws: RPCFailure.closed) { try await wire.send(one, context: context) }
        let truncated = try RPCIPCConnection(transport: ScriptedIPCTransport(incoming: Data([1, 0])))
        await #expect(throws: RPCFailure.malformedFrame) { try await truncated.receive(context: context) }
        await truncated.close()
    }
}
