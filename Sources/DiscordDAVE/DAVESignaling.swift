// File: Sources/DiscordDAVE/DAVESignaling.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordMLS
import DiscordTransport
import DiscordVoice
import Foundation

/// Sanitized signaling failures; no remote payload, identity, or secret is retained.
public enum DAVESessionError: Error, Sendable, Equatable {
    case invalidConfiguration, invalidMessage, unsupportedVersion, downgradeRejected
    case invalidTransition, externalSenderMismatch, capacityExceeded, operationInProgress
    case mediaUnavailable, invalidClock, closed
}

/// Parsed authenticated-channel DAVE controls, still subject to MLS authentication.
/// Wire DAVE version 1 is distinct from Voice v8 and whitepaper revision 1.1.4.
public enum DAVESignaling: Sendable, Equatable {
    case connected(Set<UInt64>), disconnected(UInt64)
    case prepareTransition(id: UInt16, version: UInt16), executeTransition(UInt16)
    case prepareEpoch(epoch: UInt64, version: UInt16)
    case externalSender(MLSExternalSender)
    case appendProposals([Data]), revokeProposals([Data])
    case commit(transition: UInt16, message: Data), welcome(transition: UInt16, message: Data)

    /// Parses one complete server control using canonical MLS vectors and exact integers.
    /// - Parameters:
    ///   - frame: Server frame from the authenticated Voice connection; direction/framing
    ///     is validated by `VoiceGatewayFrame` before this decoder is invoked.
    ///   - maximumMembers: Bound on connected IDs and proposals, 1...1024, default 256.
    /// - Returns: A bounded command; Welcome bytes include their MLSMessage wrapper.
    /// - Throws: Sanitized signaling or MLS wire errors for unsupported opcodes, missing/
    ///   null/wrong-type fields, zero identities, invalid lengths or excessive counts.
    ///   Unknown JSON siblings are ignored; no group or media state changes here.
    public static func decode(_ frame: VoiceGatewayFrame, maximumMembers: Int = 256) throws -> Self {
        guard (1...1024).contains(maximumMembers) else { throw DAVESessionError.invalidConfiguration }
        if case .json(.object(let object)) = frame.payload {
            switch frame.opcode {
            case 11:
                guard case .array(let values) = object["user_ids"], values.count <= maximumMembers else {
                    throw DAVESessionError.invalidMessage
                }
                var ids: Set<UInt64> = []
                for value in values {
                    guard case .string(let string) = value, let id = UInt64(string), id > 0,
                          string.utf8.allSatisfy({ (48...57).contains($0) }) else { throw DAVESessionError.invalidMessage }
                    ids.insert(id)
                }
                return .connected(ids)
            case 13:
                guard case .string(let string) = object["user_id"], let id = UInt64(string), id > 0,
                      string.utf8.allSatisfy({ (48...57).contains($0) }) else { throw DAVESessionError.invalidMessage }
                return .disconnected(id)
            case 21: return try .prepareTransition(id: integer(object, "transition_id"), version: integer(object, "protocol_version"))
            case 22: return try .executeTransition(integer(object, "transition_id"))
            case 24: return try .prepareEpoch(epoch: integer(object, "epoch"), version: integer(object, "protocol_version"))
            default: throw DAVESessionError.invalidMessage
            }
        }
        guard case .binary(let data) = frame.payload else { throw DAVESessionError.invalidMessage }
        var reader = try MLSReader(data)
        switch frame.opcode {
        case 25: return try .externalSender(MLSExternalSender.decode(data))
        case 27:
            let operation = try reader.readUInt8()
            let body = try reader.readVector(); try reader.requireEnd()
            if operation == 0 { return try .appendProposals(MLSProposal.splitExternalMessages(body, maximumMessages: maximumMembers)) }
            guard operation == 1 else { throw DAVESessionError.invalidMessage }
            var references = try MLSReader(body); var result: [Data] = []
            while !references.isAtEnd {
                guard result.count < maximumMembers else { throw DAVESessionError.capacityExceeded }
                let reference = try references.readVector()
                guard reference.count == 32 else { throw DAVESessionError.invalidMessage }
                result.append(reference)
            }
            return .revokeProposals(result)
        case 29, 30:
            let id = try reader.readUInt16(); let message = try reader.readRaw(count: reader.remainingCount)
            guard !message.isEmpty else { throw DAVESessionError.invalidMessage }
            return frame.opcode == 29 ? .commit(transition: id, message: message)
                : .welcome(transition: id, message: Data([0, 1, 0, 3]) + message)
        default: throw DAVESessionError.invalidMessage
        }
    }

    /// Produces a bounded client binary frame without inventing an extra body length.
    /// - Parameters:
    ///   - opcode: KeyPackage 26 or Commit/Welcome 28; other directions are rejected.
    ///   - body: Complete self-delimiting payload, at most the frame parser's one-MiB limit.
    /// - Returns: Client-direction Voice frame, ready for an injected WebSocket owner.
    /// - Throws: Voice framing or byte-budget errors. No network retry is performed.
    public static func binaryCommand(opcode: UInt8, body: Data) throws -> VoiceGatewayFrame {
        guard opcode == 26 || opcode == 28 else { throw DAVESessionError.invalidMessage }
        return try VoiceGatewayFrame(.binary(Data([opcode]) + body), direction: .clientToServer)
    }

    /// Constructs a JSON transition acknowledgement or invalid-commit notification.
    /// - Parameters:
    ///   - opcode: Client opcode 23 or 31; validated by the Voice frame constructor.
    ///   - transitionID: Complete unsigned 16-bit transition ID, including initialization zero.
    /// - Returns: A frame with the exact numeric `transition_id` field.
    /// - Throws: Invalid opcode/direction or bounded serialization errors.
    public static func transitionCommand(opcode: UInt8, transitionID: UInt16) throws -> VoiceGatewayFrame {
        guard opcode == 23 || opcode == 31 else { throw DAVESessionError.invalidMessage }
        return try VoiceGatewayFrame(opcode: opcode, data: .object(["transition_id": .number(JSONNumber(rawValue: String(transitionID)))]))
    }

    /// Reads a required unsigned JSON integer without floating-point conversion.
    /// - Parameters:
    ///   - object: Parsed server JSON data fields.
    ///   - key: Required exact field name.
    /// - Returns: The requested unsigned integer; absent/null/fractional values fail.
    /// - Throws: `invalidMessage` when the value is missing, signed, fractional or out of range.
    private static func integer<T: FixedWidthInteger & UnsignedInteger>(_ object: [String: JSONValue], _ key: String) throws -> T {
        guard case .number(let number) = object[key], number.rawValue.utf8.allSatisfy({ (48...57).contains($0) }),
              let result = T(number.rawValue) else {
            throw DAVESessionError.invalidMessage
        }
        return result
    }
}
