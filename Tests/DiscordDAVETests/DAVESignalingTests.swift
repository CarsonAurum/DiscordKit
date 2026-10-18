import Crypto
import DiscordCore
import DiscordMLS
import DiscordTransport
import DiscordVoice
import Foundation
import Testing
@testable import DiscordDAVE

/// DAVE controls preserve exact integer/wire boundaries over synthetic authenticated
/// Voice frames. Parsing never authenticates MLS bytes or contacts a service.
@Suite struct DAVESignalingTests {
    /// Creates one server-direction JSON frame from a bounded exact data value.
    /// - Parameters:
    ///   - opcode: Server or future JSON opcode to place in the envelope.
    ///   - data: Exact JSON data shape, including malformed DAVE shapes under test.
    /// - Returns: Structurally admitted Voice frame for the DAVE decoder.
    /// - Throws: JSON or Voice framing errors.
    private func json(_ opcode: UInt8, _ data: JSONValue) throws -> VoiceGatewayFrame {
        let bytes = try JSONValue.object(["op": .number(JSONNumber(rawValue: String(opcode))), "d": data]).serialized()
        return try VoiceGatewayFrame(.text(String(decoding: bytes, as: UTF8.self)))
    }

    /// Creates one server binary control with an independent transport sequence.
    /// - Parameters:
    ///   - opcode: Server DAVE binary opcode or future opcode under test.
    ///   - body: Exact payload without sequence or opcode framing.
    /// - Returns: Frame with sequence 65535 and the unchanged body.
    /// - Throws: Voice framing or size errors.
    private func binary(_ opcode: UInt8, _ body: Data) throws -> VoiceGatewayFrame {
        try VoiceGatewayFrame(.binary(Data([255, 255, opcode]) + body))
    }

    /// Builds an exact required numeric field without converting via floating point.
    /// - Parameter value: Valid JSON number lexeme, including malformed-for-DAVE values.
    /// - Returns: The same spelling as an arbitrary-precision JSON number.
    /// - Throws: Invalid JSON numeric grammar.
    private func number(_ value: String) throws -> JSONValue { try .number(JSONNumber(rawValue: value)) }

    /// Connected/disconnected identity strings retain full-width unsigned IDs,
    /// deduplicate repeated members, admit empty snapshots and ignore future siblings.
    @Test func participantShapesAndExtremeIDs() throws {
        let data: JSONValue = .object(["user_ids": .array([.string("1"), .string(String(UInt64.max)), .string("1")]),
                                        "future": .object(["ignored": .bool(true)])])
        #expect(try DAVESignaling.decode(json(11, data)) == .connected([1, UInt64.max]))
        #expect(try DAVESignaling.decode(json(11, .object(["user_ids": .array([])]))) == .connected([]))
        #expect(try DAVESignaling.decode(json(13, .object(["user_id": .string(String(UInt64.max)), "extra": .null]))) == .disconnected(UInt64.max))
        #expect(try DAVESignaling.decode(json(13, .object(["user_id": .string("0001")]))) == .disconnected(1))
        for malformed in [JSONValue.null, .array([]), .bool(true), .string("1"), .object([:]), .object(["user_ids": .null]),
                          .object(["user_ids": .string("1")]), .object(["user_ids": .array([.null])])] {
            #expect(throws: DAVESessionError.invalidMessage) { try DAVESignaling.decode(json(11, malformed)) }
        }
        for malformed in [JSONValue.null, .array([]), .object([:]), .object(["user_id": .null]),
                          .object(["user_id": .array([])]), .object(["user_id": .bool(true)]),
                          .object(["user_id": try number("1")])] {
            #expect(throws: DAVESessionError.invalidMessage) { try DAVESignaling.decode(json(13, malformed)) }
        }
        for text in ["", "0", "18446744073709551616", "-1", "+1", " 1", "1 ", "1.0", "1e0", "١"] {
            #expect(throws: DAVESessionError.invalidMessage) { try DAVESignaling.decode(json(11, .object(["user_ids": .array([.string(text)])]))) }
            #expect(throws: DAVESessionError.invalidMessage) { try DAVESignaling.decode(json(13, .object(["user_id": .string(text)]))) }
        }
        let identities: JSONValue = .object(["user_ids": .array([.string("1"), .string("1")])])
        #expect(throws: DAVESessionError.invalidMessage) { try DAVESignaling.decode(json(11, identities), maximumMembers: 1) }
        for bound in [0, -1, 1025] {
            #expect(throws: DAVESessionError.invalidConfiguration) { try DAVESignaling.decode(json(11, .object(["user_ids": .array([])])), maximumMembers: bound) }
        }
    }

    /// Transition and epoch controls accept zero/maximal values exactly, while
    /// rejecting wrong JSON types, fractions, exponent notation and signed zero.
    @Test func transitionAndEpochIntegerBoundaries() throws {
        for id in ["0", "65535"] {
            let value = try number(id); let expected = try #require(UInt16(id))
            #expect(try DAVESignaling.decode(json(21, .object(["transition_id": value, "protocol_version": value]))) == .prepareTransition(id: expected, version: expected))
            #expect(try DAVESignaling.decode(json(22, .object(["transition_id": value, "future": .null]))) == .executeTransition(expected))
        }
        for epoch in ["0", String(UInt64.max)] {
            #expect(try DAVESignaling.decode(json(24, .object(["epoch": number(epoch), "protocol_version": number("1")]))) == .prepareEpoch(epoch: UInt64(epoch)!, version: 1))
        }
        for bad in [JSONValue.null, .string("1"), .bool(true), .array([]), .object([:]),
                    try number("-1"), try number("-0"), try number("1.0"), try number("1e0"), try number("65536")] {
            #expect(throws: DAVESessionError.invalidMessage) { try DAVESignaling.decode(json(21, .object(["transition_id": bad, "protocol_version": number("1")]))) }
            #expect(throws: DAVESessionError.invalidMessage) { try DAVESignaling.decode(json(21, .object(["transition_id": number("1"), "protocol_version": bad]))) }
            #expect(throws: DAVESessionError.invalidMessage) { try DAVESignaling.decode(json(22, .object(["transition_id": bad]))) }
            #expect(throws: DAVESessionError.invalidMessage) { try DAVESignaling.decode(json(24, .object(["epoch": number("1"), "protocol_version": bad]))) }
        }
        for bad in [JSONValue.null, .string("1"), .bool(false), try number("-1"), try number("-0"),
                    try number("1.0"), try number("1e0"), try number("18446744073709551616")] {
            #expect(throws: DAVESessionError.invalidMessage) { try DAVESignaling.decode(json(24, .object(["epoch": bad, "protocol_version": number("1")]))) }
        }
        for opcode: UInt8 in [21, 22, 24] {
            for shape in [JSONValue.null, .object([:]), .array([])] {
                #expect(throws: DAVESessionError.invalidMessage) { try DAVESignaling.decode(json(opcode, shape)) }
            }
        }
        #expect(throws: DAVESessionError.invalidMessage) { try DAVESignaling.decode(json(255, .object([:]))) }
    }

    /// External sender packages round-trip exactly and reject all truncation,
    /// trailing bytes and malformed keys before any MLS admission is attempted.
    @Test func externalSenderWireValidation() throws {
        let key = P256.Signing.PrivateKey(compactRepresentable: false)
        let sender = try MLSExternalSender(signatureKey: key.publicKey.x963Representation,
                                           credential: MLSCredential(identity: Data("gateway".utf8)))
        let bytes = try sender.encoded()
        #expect(try DAVESignaling.decode(binary(25, bytes)) == .externalSender(sender))
        for count in 0..<bytes.count {
            #expect(throws: (any Error).self) { try DAVESignaling.decode(binary(25, Data(bytes.prefix(count)))) }
        }
        #expect(throws: MLSError.malformedEncoding) { try DAVESignaling.decode(binary(25, bytes + Data([0]))) }
        var malformed = bytes; malformed[2] = 0
        #expect(throws: MLSError.invalidCredential) { try DAVESignaling.decode(binary(25, malformed)) }
    }

    /// Append vectors contain concatenated canonical public messages, and revoke
    /// vectors contain length-prefixed 32-byte references. Empty vectors are valid;
    /// bounds, unsupported operations, malformed references and suffixes fail atomically.
    @Test func proposalAppendAndRevocationVectors() throws {
        let key = P256.Signing.PrivateKey(compactRepresentable: false)
        let first = try MLSProposal.remove(0).externalMessage(groupID: Data([1]), epoch: 1, signaturePrivateKey: key.rawRepresentation)
        let second = try MLSProposal.remove(UInt32.max).externalMessage(groupID: Data([1]), epoch: 1, signaturePrivateKey: key.rawRepresentation)
        var append = MLSWriter(); append.write(UInt8(0)); try append.writeVector(first + second)
        #expect(try DAVESignaling.decode(binary(27, append.data), maximumMembers: 2) == .appendProposals([first, second]))
        #expect(throws: MLSError.capacityExceeded) { try DAVESignaling.decode(binary(27, append.data), maximumMembers: 1) }
        let references = [Data(repeating: 0, count: 32), Data(repeating: 255, count: 32)]
        var entries = MLSWriter(); for reference in references { try entries.writeVector(reference) }
        var revoke = MLSWriter(); revoke.write(UInt8(1)); try revoke.writeVector(entries.data)
        #expect(try DAVESignaling.decode(binary(27, revoke.data), maximumMembers: 2) == .revokeProposals(references))
        #expect(throws: DAVESessionError.capacityExceeded) { try DAVESignaling.decode(binary(27, revoke.data), maximumMembers: 1) }
        #expect(try DAVESignaling.decode(binary(27, Data([0, 0]))) == .appendProposals([]))
        #expect(try DAVESignaling.decode(binary(27, Data([1, 0]))) == .revokeProposals([]))
        #expect(throws: DAVESessionError.invalidMessage) { try DAVESignaling.decode(binary(27, Data([2, 0]))) }
        for bytes in [Data(), Data([0]), Data([0, 0, 0]), Data([0, 0x40, 0]), Data([1, 1, 32])] {
            #expect(throws: (any Error).self) { try DAVESignaling.decode(binary(27, bytes)) }
        }
        for count in [0, 31, 33] {
            var reference = MLSWriter(); try reference.writeVector(Data(repeating: 0, count: count))
            var body = MLSWriter(); body.write(UInt8(1)); try body.writeVector(reference.data)
            #expect(throws: DAVESessionError.invalidMessage) { try DAVESignaling.decode(binary(27, body.data)) }
        }
        var version = first; version[1] = 2
        var malformed = MLSWriter(); malformed.write(UInt8(0)); try malformed.writeVector(version)
        #expect(throws: MLSError.unsupportedVersion) { try DAVESignaling.decode(binary(27, malformed.data)) }
    }

    /// Commit/Welcome delivery reads the big-endian transition ID; only bare
    /// Welcome receives an MLSMessage version/format wrapper. MLS authentication
    /// remains deferred to the group owner rather than inferred from these bytes.
    @Test func transitionPayloadAndBareWelcomeWrapping() throws {
        let message = Data([0xAA, 0xBB, 0xCC])
        for id: UInt16 in [0, 65535] {
            let prefix = Data([UInt8(id >> 8), UInt8(id & 255)])
            #expect(try DAVESignaling.decode(binary(29, prefix + message)) == .commit(transition: id, message: message))
            #expect(try DAVESignaling.decode(binary(30, prefix + message)) == .welcome(transition: id, message: Data([0, 1, 0, 3]) + message))
        }
        for opcode: UInt8 in [29, 30] {
            for body in [Data(), Data([0]), Data([0, 1])] {
                #expect(throws: (any Error).self) { try DAVESignaling.decode(binary(opcode, body)) }
            }
        }
        #expect(throws: DAVESessionError.invalidMessage) { try DAVESignaling.decode(binary(255, message)) }
    }

    /// Client helpers enforce the DAVE command subset and exact framing: 26/28
    /// carry no server sequence, while 23/31 carry a numeric transition ID in JSON.
    @Test func clientCommandsAndDirection() throws {
        for opcode: UInt8 in [26, 28] {
            let body = Data([0, 1, 0, 5, 0xAA])
            let frame = try DAVESignaling.binaryCommand(opcode: opcode, body: body)
            #expect(frame.opcode == opcode && frame.sequence == nil && frame.payload == .binary(body))
            #expect(try frame.message() == .binary(Data([opcode]) + body))
            #expect(try VoiceGatewayFrame(frame.message(), direction: .clientToServer) == frame)
            #expect(throws: VoiceControlFailure.invalidPayload) {
                try VoiceGatewayFrame(.binary(Data([0, 0, opcode]) + body))
            }
            #expect(throws: DAVESessionError.invalidMessage) { try DAVESignaling.decode(frame) }
        }
        for opcode: UInt8 in [23, 31] {
            for id: UInt16 in [0, 65535] {
                let frame = try DAVESignaling.transitionCommand(opcode: opcode, transitionID: id)
                #expect(frame.opcode == opcode && frame.sequence == nil)
                #expect(try frame.payload == .json(.object(["transition_id": number(String(id))])))
                #expect(try VoiceGatewayFrame(frame.message(), direction: .clientToServer) == frame)
                #expect(throws: VoiceControlFailure.invalidPayload) { try VoiceGatewayFrame(frame.message()) }
                #expect(throws: DAVESessionError.invalidMessage) { try DAVESignaling.decode(frame) }
            }
        }
        for opcode: UInt8 in [0, 23, 25, 27, 29, 30, 31, 255] {
            #expect(throws: (any Error).self) { try DAVESignaling.binaryCommand(opcode: opcode, body: Data()) }
        }
        for opcode: UInt8 in [0, 3, 21, 22, 24, 26, 28, 255] {
            #expect(throws: (any Error).self) { try DAVESignaling.transitionCommand(opcode: opcode, transitionID: 1) }
        }
    }

    /// The one-MiB parser budget includes transport prefixes; oversize binary and
    /// JSON inputs fail before a DAVE control can be admitted or copied again.
    @Test func wholeFrameByteAndParserLimits() throws {
        let maximumBody = Data(repeating: 1, count: 1_048_575)
        let client = try DAVESignaling.binaryCommand(opcode: 26, body: maximumBody)
        #expect(try client.message() == .binary(Data([26]) + maximumBody))
        #expect(throws: JSONValueError.maximumBytesExceeded) {
            try DAVESignaling.binaryCommand(opcode: 26, body: Data(repeating: 0, count: 1_048_576))
        }
        #expect(throws: JSONValueError.maximumBytesExceeded) {
            try binary(29, Data(repeating: 0, count: 1_048_574))
        }
        #expect(throws: JSONValueError.maximumBytesExceeded) {
            try VoiceGatewayFrame(.text("{\"op\":11,\"d\":{\"user_ids\":[],\"future\":\"" + String(repeating: "a", count: 1_048_576) + "\"}}"))
        }
        #expect(throws: JSONValueError.self) {
            try VoiceGatewayFrame(.text("{\"op\":21,\"d\":{\"transition_id\":1,\"transition_id\":2,\"protocol_version\":1}}"))
        }
        let large = try VoiceGatewayFrame(.binary(Data([0, 0, 29]) + Data(repeating: 0, count: 1_048_577)),
                                          limits: JSONLimits(maximumBytes: 2_097_152))
        #expect(throws: MLSError.capacityExceeded) { try DAVESignaling.decode(large) }
    }
}
