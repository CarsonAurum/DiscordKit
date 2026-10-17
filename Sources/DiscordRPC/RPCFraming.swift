import DiscordCore
import Foundation

/// Fixed failures without peer messages, credentials, paths or payload diagnostics.
public enum RPCFailure: Error, Sendable, Equatable {
    case invalidConfiguration
    case malformedFrame
    case frameTooLarge
    case invalidPayload
    case unavailable
    case alreadyConnected
    case notConnected
    case overloaded
    case concurrentRead
    case connectionLost
    case closed
    case server(code: Int)
}

/// RPC v1 IPC opcodes; unknown integers fail closed rather than acting as messages.
public enum RPCOpcode: UInt32, Sendable, CaseIterable {
    case handshake = 0, frame = 1, close = 2, ping = 3, pong = 4
}

/// One IPC frame. Payload may contain credentials; diagnostics hide all bytes.
public struct RPCFrame: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let opcode: RPCOpcode
    public let payload: Data

    /// Stores a complete frame without performing I/O; encoding validates its size.
    /// - Parameters:
    ///   - opcode: Documented RPC v1 opcode, independent of Gateway opcodes.
    ///   - payload: Opaque bytes; ping/pong bytes need not be valid JSON.
    public init(opcode: RPCOpcode, payload: Data) { self.opcode = opcode; self.payload = payload }

    /// Redacts opaque frame bytes during ordinary formatting.
    public var description: String { "RPCFrame(redacted)" }
    /// Redacts opaque frame bytes during debug formatting.
    public var debugDescription: String { description }
    /// Prevents automatic diagnostic expansion of secret-bearing payloads.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }

    /// Encodes the 8-byte little-endian opcode/length header followed by payload.
    /// - Parameter maximumPayloadBytes: Positive local cap, default 1 MiB; at most UInt32.max.
    /// - Returns: Complete IPC wire frame, including an empty payload when supplied.
    /// - Throws: Invalid cap or oversized payload; never truncates integer lengths.
    public func encoded(maximumPayloadBytes: Int = 1_048_576) throws -> Data {
        guard maximumPayloadBytes > 0, maximumPayloadBytes <= UInt32.max else { throw RPCFailure.invalidConfiguration }
        guard payload.count <= maximumPayloadBytes else { throw RPCFailure.frameTooLarge }
        var data = Data()
        for value in [opcode.rawValue, UInt32(payload.count)] {
            for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8(truncatingIfNeeded: value >> shift)) }
        }
        data.append(payload)
        return data
    }
}

/// Incremental bounded IPC decoder accepting arbitrarily split/coalesced input.
///
/// At most one incomplete header/payload is retained. Each append is capped to
/// `maximumPayloadBytes + 8`; callers must bound their read size accordingly.
/// Complete returned frames are caller-owned. Any append error discards buffered input.
public struct RPCFrameDecoder: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Hides incomplete secret-bearing frame bytes from ordinary formatting.
    public var description: String { "RPCFrameDecoder(redacted)" }
    /// Hides incomplete secret-bearing frame bytes from debug formatting.
    public var debugDescription: String { description }
    /// Prevents reflective expansion of retained partial payloads.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
    public let maximumPayloadBytes: Int
    private var buffer = Data()

    /// Validates frame bounds without allocating a frame-sized buffer.
    /// - Parameter maximumPayloadBytes: Positive byte cap, default 1 MiB, at most UInt32.max minus 8.
    /// - Throws: `RPCFailure.invalidConfiguration` for unsafe caps.
    public init(maximumPayloadBytes: Int = 1_048_576) throws {
        guard maximumPayloadBytes > 0, maximumPayloadBytes <= UInt32.max - 8 else { throw RPCFailure.invalidConfiguration }
        self.maximumPayloadBytes = maximumPayloadBytes
    }

    /// Consumes one bounded fragment and emits every completed frame in wire order.
    /// - Parameter bytes: At most one maximum-sized frame per call; empty fragments are accepted.
    /// - Returns: Zero or more complete frames, preserving opaque ping/pong bytes.
    /// - Throws: Oversized input/announced length, unknown opcode or invalid header.
    ///   Errors reset this decoder; the enclosing connection must terminate.
    public mutating func append(_ bytes: Data) throws -> [RPCFrame] {
        do {
            guard bytes.count <= maximumPayloadBytes + 8 else { throw RPCFailure.frameTooLarge }
            // Process incrementally, avoiding a second maximum-frame-sized retained buffer.
            var frames: [RPCFrame] = []
            var offset = bytes.startIndex
            while offset < bytes.endIndex {
                if buffer.count < 8 {
                    let count = min(8 - buffer.count, bytes.endIndex - offset)
                    buffer.append(bytes[offset..<(offset + count)]); offset += count
                }
                guard buffer.count == 8 || buffer.count > 8 else { break }
                let header = Array(buffer.prefix(8))
                let opcodeValue = (0..<4).reduce(UInt32(0)) { $0 | UInt32(header[$1]) << ($1 * 8) }
                let length = (0..<4).reduce(UInt32(0)) { $0 | UInt32(header[$1 + 4]) << ($1 * 8) }
                guard let opcode = RPCOpcode(rawValue: opcodeValue) else { throw RPCFailure.malformedFrame }
                guard length <= maximumPayloadBytes else { throw RPCFailure.frameTooLarge }
                let required = 8 + Int(length)
                let count = min(required - buffer.count, bytes.endIndex - offset)
                if count > 0 { buffer.append(bytes[offset..<(offset + count)]); offset += count }
                if buffer.count == required {
                    frames.append(RPCFrame(opcode: opcode, payload: Data(buffer.dropFirst(8))))
                    buffer.removeAll(keepingCapacity: false)
                }
            }
            return frames
        } catch { buffer.removeAll(keepingCapacity: false); throw error }
    }

    /// Validates that EOF falls on a frame boundary without accepting truncated input.
    /// - Throws: `RPCFailure.malformedFrame` when any header/payload bytes remain.
    public func finish() throws { guard buffer.isEmpty else { throw RPCFailure.malformedFrame } }

    /// Discards incomplete header/payload storage without changing validated size bounds.
    /// Use after connection closure or before beginning an unrelated byte stream. This
    /// releases retained Data ownership; Swift does not guarantee secret-memory wiping.
    public mutating func reset() { buffer.removeAll(keepingCapacity: false) }
}
