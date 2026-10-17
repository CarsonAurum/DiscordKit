import DiscordCore
import DiscordTransport
import Foundation

/// Sanitized failures for deterministic Voice Gateway and join coordination.
/// Errors never retain session identifiers, tokens, keys, endpoints, or packet bodies.
public enum VoiceControlFailure: Error, Equatable, Sendable {
    case invalidConfiguration, invalidPayload, unsupportedEncoding, invalidTransition
    case staleGeneration, heartbeatPending, invalidHeartbeatACK, missedHeartbeatACK
    case unsupportedEncryption, e2eeRequired, e2eeUnavailable, closed
}

/// Documented Voice Gateway v8 opcodes, verified 2026-10-17 against Discord's opcode table.
/// This catalog identifies DAVE envelopes; it does not implement MLS or DAVE cryptography.
/// https://docs.discord.com/developers/topics/opcodes-and-status-codes#voice
public enum VoiceGatewayOpcode: UInt8, Sendable, CaseIterable {
    case identify = 0, selectProtocol = 1, ready = 2, heartbeat = 3
    case sessionDescription = 4, speaking = 5, heartbeatACK = 6, resume = 7
    case hello = 8, resumed = 9, clientsConnect = 11, clientDisconnect = 13
    case davePrepareTransition = 21, daveExecuteTransition = 22, daveTransitionReady = 23
    case davePrepareEpoch = 24, daveMLSExternalSender = 25, daveMLSKeyPackage = 26
    case daveMLSProposals = 27, daveMLSCommitWelcome = 28
    case daveMLSAnnounceCommitTransition = 29, daveMLSWelcome = 30
    case daveMLSInvalidCommitWelcome = 31

    /// Whether the opcode uses binary framing rather than a JSON envelope.
    public var isBinary: Bool { (25...30).contains(rawValue) }

    /// Whether a documented client-to-server frame may carry this opcode.
    public var isClientSent: Bool {
        switch self {
        case .identify, .selectProtocol, .heartbeat, .speaking, .resume,
             .daveTransitionReady, .daveMLSKeyPackage, .daveMLSCommitWelcome,
             .daveMLSInvalidCommitWelcome: true
        default: false
        }
    }

    /// Whether a documented server-to-client frame may carry this opcode.
    public var isServerSent: Bool { self == .speaking || !isClientSent }
}

/// Frame direction determines binary sequence framing and validates documented opcodes.
public enum VoiceGatewayDirection: Sendable, Equatable {
    case clientToServer, serverToClient
}

/// A bounded v8 Voice Gateway frame retaining exact JSON values or opaque MLS bytes.
/// Unknown future opcode values survive decoding. Known opcodes reject the wrong
/// encoding or direction. Parsing performs no network, MLS, replay, or authorization work.
public struct VoiceGatewayFrame: Sendable, Equatable, CustomStringConvertible, CustomReflectable {
    /// Explicit Voice Gateway version; this differs from the main Gateway's API version.
    public static let version = 8
    /// Raw unsigned opcode, retaining undocumented future values without interpreting them.
    public let opcode: UInt8
    /// Server sequence, including zero after wrapping; absent for client frames and unnumbered JSON.
    public let sequence: UInt16?
    /// JSON data or opaque binary payload, excluding framing bytes.
    public let payload: Payload
    /// Complete JSON envelope, preserving unknown siblings; nil for binary frames.
    public let rawFields: [String: JSONValue]?

    /// Encoding-preserving frame body; binary MLS payloads are intentionally not projected.
    public enum Payload: Sendable, Equatable {
        case json(JSONValue), binary(Data)
    }

    /// Creates a client JSON command under complete-envelope bounds.
    /// - Parameters:
    ///   - opcode: A documented client JSON opcode or unknown future opcode.
    ///   - data: Exact `d` value, including explicit null and numeric lexemes.
    ///   - limits: Whole-envelope byte/depth/node limits, default 1 MiB/64/100,000.
    /// - Throws: `unsupportedEncoding` or `invalidPayload` for a known wrong encoding/direction,
    ///   or `JSONValueError` for invalid/exceeded serialization bounds. No I/O occurs.
    public init(opcode: UInt8, data: JSONValue, limits: JSONLimits = .default) throws {
        try Self.validate(opcode: opcode, binary: false, direction: .clientToServer)
        let object: [String: JSONValue] = ["op": voiceControlNumber(opcode), "d": data]
        _ = try JSONValue.object(object).serialized(limits: limits)
        self.opcode = opcode; sequence = nil; payload = .json(data); rawFields = object
    }

    /// Parses a complete text or binary message before any higher-level state mutation.
    /// - Parameters:
    ///   - message: Complete adapter message; fragmentation/control frames remain adapter-owned.
    ///   - direction: Server-to-client by default; server binary messages require a two-byte
    ///     big-endian sequence, client binary messages contain only opcode plus payload.
    ///   - limits: Whole-frame byte bound plus JSON depth/node bounds, default 1 MiB/64/100,000.
    /// - Throws: `VoiceControlFailure` for malformed framing, direction or encoding; bounded
    ///   `JSONValueError` for JSON syntax, duplicate keys, or invalid/exceeded limits.
    /// Empty binary bodies remain valid opaque payloads; MLS validity belongs to an injected backend.
    public init(_ message: WebSocketMessage, direction: VoiceGatewayDirection = .serverToClient,
                limits: JSONLimits = .default) throws {
        switch message {
        case .text(let text):
            let root = try JSONValue.parse(text, limits: limits)
            guard case .object(let object) = root,
                  case .number(let number) = object["op"],
                  let opcode = UInt8(number.rawValue), let data = object["d"] else {
                throw VoiceControlFailure.invalidPayload
            }
            try Self.validate(opcode: opcode, binary: false, direction: direction)
            if let value = object["seq"] {
                guard direction == .serverToClient, case .number(let number) = value,
                      let sequence = UInt16(number.rawValue) else { throw VoiceControlFailure.invalidPayload }
                self.sequence = sequence
            } else { sequence = nil }
            self.opcode = opcode; payload = .json(data); rawFields = object
        case .binary(let data):
            // Run the same limit validation used by JSON before copying an opaque body.
            _ = try voiceControlNumber(0).serialized(limits: limits)
            guard data.count <= limits.maximumBytes else { throw JSONValueError.maximumBytesExceeded }
            let prefix = direction == .serverToClient ? 3 : 1
            guard data.count >= prefix else { throw VoiceControlFailure.invalidPayload }
            let bytes = [UInt8](data.prefix(prefix))
            opcode = bytes[prefix - 1]
            try Self.validate(opcode: opcode, binary: true, direction: direction)
            sequence = direction == .serverToClient ? UInt16(bytes[0]) << 8 | UInt16(bytes[1]) : nil
            // Data's slice initializer may share arbitrarily large caller backing storage.
            // Keep only an owned copy of the admitted, bounded body.
            payload = .binary(data.dropFirst(prefix).withUnsafeBytes { Data($0) }); rawFields = nil
        }
    }

    /// Serializes an already-validated frame without changing JSON numeric spellings.
    /// - Parameter limits: Complete output bounds; defaults to the package's standard JSON limits.
    /// - Returns: One text or binary adapter message; server binary sequences are big-endian.
    /// - Throws: Bounded `JSONValueError` for exceeded or invalid limits. Work is synchronous,
    ///   linear in frame size, and neither writes to a socket nor examines task cancellation.
    public func message(limits: JSONLimits = .default) throws -> WebSocketMessage {
        switch payload {
        case .json:
            guard let rawFields else { throw VoiceControlFailure.invalidPayload }
            let data = try JSONValue.object(rawFields).serialized(limits: limits)
            return .text(String(decoding: data, as: UTF8.self))
        case .binary(let body):
            _ = try voiceControlNumber(0).serialized(limits: limits)
            let prefix = sequence == nil ? 1 : 3
            guard body.count <= limits.maximumBytes - prefix else { throw JSONValueError.maximumBytesExceeded }
            var bytes = Data()
            if let sequence { bytes.append(UInt8(sequence >> 8)); bytes.append(UInt8(sequence & 255)) }
            bytes.append(opcode); bytes.append(body)
            return .binary(bytes)
        }
    }

    /// Redacts arbitrary JSON, MLS material, session identifiers, and tokens in diagnostics.
    public var description: String { "VoiceGatewayFrame(redacted)" }

    /// Prevents reflective diagnostic code from traversing frame payloads.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }

    /// Checks documented framing and direction without rejecting future opcode values.
    /// - Parameters:
    ///   - opcode: Raw unsigned opcode from the complete frame.
    ///   - binary: Whether the complete adapter message uses binary encoding.
    ///   - direction: Which peer sent the message.
    /// - Throws: `unsupportedEncoding` for a known encoding mismatch; `invalidPayload`
    ///   for a documented opcode sent by the wrong peer. Unknown opcodes pass unchanged.
    private static func validate(opcode: UInt8, binary: Bool, direction: VoiceGatewayDirection) throws {
        guard let known = VoiceGatewayOpcode(rawValue: opcode) else { return }
        guard known.isBinary == binary else { throw VoiceControlFailure.unsupportedEncoding }
        guard direction == .clientToServer ? known.isClientSent : known.isServerSent else {
            throw VoiceControlFailure.invalidPayload
        }
    }
}

/// Produces exact JSON for a protocol-owned integer without floating-point conversion.
/// - Parameter value: Any Swift integer; its standard decimal spelling is valid JSON.
/// - Returns: A numeric JSON value retaining every bit in its decimal representation.
func voiceControlNumber<T: BinaryInteger>(_ value: T) -> JSONValue {
    .number(try! JSONNumber(rawValue: String(value)))
}
