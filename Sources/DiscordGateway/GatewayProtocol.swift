import DiscordCore
import DiscordTransport
import Foundation

/// Safe closed failures; payloads, session IDs and bot tokens never enter errors.
public enum GatewayFailure: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidPayload
    case unsupportedEncoding
    case invalidTransition
    case alreadyRunning
    case staleGeneration
    case disconnected
    case reconnectRequested
    case missedHeartbeatACK
    case fatalClose(Int)
    case retryLimitExceeded
    case eventCapacityExceeded
    case startupRefreshRequired
    case coordinatorUnavailable
}

/// Explicit phases for one socket/session lifecycle, independently testable without I/O.
public enum GatewayPhase: String, Sendable, CaseIterable {
    case disconnected, connecting, awaitingHello, identifying, resuming, ready
    case reconnecting, draining, stopped
}

/// Inputs accepted by the pure lifecycle reducer. Fatal and stop inputs are terminal.
public enum GatewaySignal: Sendable, Equatable {
    case start, connected, hello(resumable: Bool), ready, reconnect, drain, closed, fatal
}

/// Side effects requested by a transition; the reducer itself never performs them.
public enum GatewayAction: Sendable, Equatable {
    case connect, authenticate(resume: Bool), receive, close, retry, none
}

/// A pure, closed transition table used by the shard actor and deterministic tests.
public struct GatewaySessionState: Sendable, Equatable {
    public private(set) var phase: GatewayPhase = .disconnected

    /// Creates a disconnected state without allocating resources or starting tasks.
    public init() {}

    /// Advances one valid lifecycle edge atomically, or leaves state unchanged.
    /// - Parameter signal: Connection, protocol or owner input; readiness requires authentication.
    /// - Returns: The side effect to execute after committing the new phase.
    /// - Throws: `invalidTransition` for edges absent from the explicit table.
    public mutating func apply(_ signal: GatewaySignal) throws -> GatewayAction {
        let next: GatewayPhase
        let action: GatewayAction
        switch (phase, signal) {
        case (.disconnected, .start), (.reconnecting, .start): (next, action) = (.connecting, .connect)
        case (.connecting, .connected): (next, action) = (.awaitingHello, .receive)
        case (.awaitingHello, .hello(let resume)):
            (next, action) = (resume ? .resuming : .identifying, .authenticate(resume: resume))
        case (.identifying, .ready), (.resuming, .ready): (next, action) = (.ready, .receive)
        case (.connecting, .reconnect), (.awaitingHello, .reconnect), (.identifying, .reconnect),
             (.resuming, .reconnect), (.ready, .reconnect): (next, action) = (.reconnecting, .retry)
        case (.disconnected, .drain), (.connecting, .drain), (.awaitingHello, .drain),
             (.identifying, .drain), (.resuming, .drain), (.ready, .drain), (.reconnecting, .drain):
            (next, action) = (.draining, .close)
        case (.draining, .closed): (next, action) = (.stopped, .none)
        case (_, .fatal) where phase != .stopped: (next, action) = (.stopped, .close)
        default: throw GatewayFailure.invalidTransition
        }
        phase = next
        return action
    }
}

/// Discord Gateway disconnect policy, verified against the official status table 2026-10-16.
/// https://docs.discord.com/developers/topics/opcodes-and-status-codes#gateway
public enum GatewayCloseDisposition: Sendable, Equatable {
    case resume, identify, fatal

    /// Classifies every documented Gateway code; unknown transport failures allow bounded resume.
    /// - Parameter code: Peer close code, or `nil` for an abrupt connection loss.
    /// - Returns: Fatal for authentication/configuration errors, Identify for invalid sessions
    ///   and normal closure, otherwise Resume subject to a retained session and adapter support.
    public static func classify(_ code: Int?) -> Self {
        switch code {
        case 4004, 4010, 4011, 4012, 4013, 4014: .fatal
        case 1000, 1001, 4003, 4007, 4009: .identify
        default: .resume
        }
    }
}

/// A bounded raw Gateway event; later catalog work can decode its lossless payload.
/// This ingestion queue is single-consumer polling, not a broadcast subscription.
public struct GatewayEvent: Sendable, CustomStringConvertible, CustomReflectable {
    public let shard: ShardIdentity
    public let opcode: Int
    public let name: String?
    public let sequence: Int64?
    public let data: JSONValue
    let byteCount: Int

    /// Constructs a received event after frame bounds and protocol fields were validated.
    /// - Parameters:
    ///   - shard: Fixed topology source; nonguild events are delivered by Discord to shard zero.
    ///   - envelope: Parsed complete envelope, including unknown opcodes and fields in `data`.
    init(shard: ShardIdentity, envelope: GatewayEnvelope) {
        self.shard = shard; opcode = envelope.opcode; name = envelope.name
        sequence = envelope.sequence; data = envelope.data; byteCount = envelope.byteCount
    }

    /// Conceals payload and session-bearing event fields in generic diagnostics.
    public var description: String { "GatewayEvent(redacted)" }

    /// Prevents reflection from traversing potentially sensitive event payloads.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Internal bounded JSON envelope. Known control fields are strict; unknown data remains lossless.
struct GatewayEnvelope: Sendable {
    let opcode: Int
    let name: String?
    let sequence: Int64?
    let data: JSONValue
    let byteCount: Int

    /// Parses one uncompressed JSON text frame without converting numeric payload lexemes.
    /// - Parameters:
    ///   - message: Complete adapter frame; binary/ETF/compression are unsupported.
    ///   - maximumBytes: Positive UTF-8 bound enforced before JSON allocation.
    /// - Throws: `unsupportedEncoding`, `invalidPayload`, or bounded JSON parser failures.
    init(_ message: WebSocketMessage, maximumBytes: Int) throws {
        guard case .text(let text) = message else { throw GatewayFailure.unsupportedEncoding }
        let value = try JSONValue.parse(text, limits: JSONLimits(maximumBytes: maximumBytes))
        guard case .object(let object) = value,
              case .number(let op) = object["op"], let opcode = Int(op.rawValue), opcode >= 0 else {
            throw GatewayFailure.invalidPayload
        }
        self.opcode = opcode
        if let sequence = object["s"], sequence != .null {
            guard case .number(let number) = sequence, let integer = Int64(number.rawValue), integer >= 0 else {
                throw GatewayFailure.invalidPayload
            }
            self.sequence = integer
        } else { sequence = nil }
        if let name = object["t"], name != .null {
            guard case .string(let string) = name else { throw GatewayFailure.invalidPayload }
            self.name = string
        } else { name = nil }
        data = object["d"] ?? .null
        byteCount = text.utf8.count
    }
}

/// Validates Gateway origins before a bot token can be written to a discovered socket.
/// - Parameter value: Official discovery/READY WSS URL, with no user information or fragment.
/// - Returns: Explicit v10 JSON URL with compression disabled and existing query replaced.
/// - Throws: `invalidPayload` for origins outside Discord's discord.gg domain or invalid URL parts.
func gatewayURL(_ value: String) throws -> URL {
    guard var parts = URLComponents(string: value), parts.scheme == "wss",
          let host = parts.host?.lowercased(), host.hasSuffix(".discord.gg"),
          parts.user == nil, parts.password == nil, parts.fragment == nil,
          parts.port == nil || parts.port == 443 else { throw GatewayFailure.invalidPayload }
    parts.queryItems = [URLQueryItem(name: "v", value: "10"), URLQueryItem(name: "encoding", value: "json")]
    guard let url = parts.url else { throw GatewayFailure.invalidPayload }
    return url
}

/// Produces an exact numeric JSON value for protocol-owned bounded integers.
/// - Parameter value: Valid Swift integer, whose decimal spelling is always valid JSON.
/// - Returns: A lossless numeric value.
func gatewayNumber<T: BinaryInteger>(_ value: T) -> JSONValue {
    // Decimal integers produced by the standard library satisfy JSONNumber's grammar.
    .number(try! JSONNumber(rawValue: String(value)))
}

/// Sanitizes injected-boundary failures before public errors can expose arbitrary credential-bearing text.
/// - Parameter error: Original dependency failure; it is never logged or retained in a wrapper.
/// - Returns: Known closed runtime/ownership/transport errors unchanged, malformed JSON as invalid
///   payload, or a fixed coordinator-unavailable category for every other injected error type.
func safeGatewayFailure(_ error: any Error) -> any Error {
    if error is GatewayFailure || error is ShardOwnershipFailure || error is TransportFailure || error is CancellationError {
        return error
    }
    if error is JSONValueError { return GatewayFailure.invalidPayload }
    return GatewayFailure.coordinatorUnavailable
}
