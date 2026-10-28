// File: Sources/DiscordRPC/RPCConnection.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordTransport
import Foundation

/// A message connection owned exclusively by one RPCClient session.
/// Concrete adapters own local IPC/WebSocket I/O, never remote Gateway sessions.
public protocol RPCConnection: TransportResource {
    /// Sends a handshake. IPC writes opcode 0; WebSocket has already sent URL parameters.
    /// - Parameters:
    ///   - applicationID: Application registered for local RPC v1.
    ///   - context: Clock, deadline and cooperative cancellation for admission/completion.
    /// - Throws: Validation, cancellation, deadline or redacted transport failure.
    func handshake<C: Clock>(applicationID: ApplicationID, context: TransportContext<C>) async throws where C.Duration == Duration
    /// Sends one IPC control or standard JSON frame without retrying ambiguous writes.
    /// - Parameters:
    ///   - frame: Complete bounded frame; ordinary WebSockets accept only `.frame`.
    ///   - context: Operation clock/deadline/cancellation.
    /// - Throws: Invalid frame, cancellation, deadline or redacted I/O failure.
    func send<C: Clock>(_ frame: RPCFrame, context: TransportContext<C>) async throws where C.Duration == Duration
    /// Reads one complete frame with one active reader and bounded internal retention.
    /// - Parameter context: Operation clock/deadline/cancellation.
    /// - Returns: Complete frame, or nil at clean EOF.
    /// - Throws: Malformed/oversized/truncated input, concurrent read or transport failure.
    func receive<C: Clock>(context: TransportContext<C>) async throws -> RPCFrame? where C.Duration == Duration
}

/// Creates a fresh, exclusively owned local connection for each explicit connect/reconnect.
public protocol RPCConnector: Sendable {
    /// Opens local I/O; a failed startup retains cleanup ownership in the connector.
    /// - Parameters:
    ///   - applicationID: Registered RPC application; never a bot credential.
    ///   - context: Startup deadline/cancellation, also covering discovery.
    /// - Returns: Owned connection that must eventually be closed.
    /// - Throws: Unavailable host, cancellation, timeout or redacted transport failure.
    func connect<C: Clock>(applicationID: ApplicationID, context: TransportContext<C>) async throws -> any RPCConnection where C.Duration == Duration
}

/// Adapts a bounded native byte stream to RPC v1 framing; starts no task at construction.
public actor RPCIPCConnection: RPCConnection {
    private let transport: any IPCTransport
    private var decoder: RPCFrameDecoder
    private var frames: [RPCFrame] = []
    private var reading = false
    private var closed = false

    /// Transfers exclusive stream ownership; no other caller may read the stream.
    /// - Parameters:
    ///   - transport: Already connected Unix socket or qualified Windows named-pipe adapter.
    ///   - maximumPayloadBytes: Positive per-frame byte cap; default 1 MiB.
    /// - Throws: Invalid size bound, without taking transport ownership on failure.
    public init(transport: any IPCTransport, maximumPayloadBytes: Int = 1_048_576) throws {
        self.decoder = try RPCFrameDecoder(maximumPayloadBytes: maximumPayloadBytes)
        self.transport = transport
    }

    /// Sends the explicit RPC v1 handshake before reading READY.
    /// - Parameters:
    ///   - applicationID: Registered application ID, preserved as a decimal string.
    ///   - context: Startup clock/deadline/cancellation.
    /// - Throws: Frame validation or stream write failures.
    public func handshake<C: Clock>(applicationID: ApplicationID, context: TransportContext<C>) async throws where C.Duration == Duration {
        try context.check()
        guard applicationID.rawValue != 0 else { throw RPCFailure.invalidConfiguration }
        let payload = try JSONValue.object(["v": .number(JSONNumber(rawValue: "1")), "client_id": .string(applicationID.description)]).serialized()
        try await send(.init(opcode: .handshake, payload: payload), context: context)
    }

    /// Serializes one bounded IPC frame; RPCClient supplies a single writer.
    /// - Parameters:
    ///   - frame: Header opcode and opaque payload.
    ///   - context: Write deadline/cancellation.
    /// - Throws: Closure, frame bounds or stream errors; bytes are never replayed.
    public func send<C: Clock>(_ frame: RPCFrame, context: TransportContext<C>) async throws where C.Duration == Duration {
        try context.check()
        guard !closed else { throw RPCFailure.closed }
        try await transport.write(frame.encoded(maximumPayloadBytes: decoder.maximumPayloadBytes), context: context)
    }

    /// Reads bounded fragments until a complete frame or clean EOF becomes available.
    /// - Parameter context: Read deadline/cancellation.
    /// - Returns: Next frame in stream order, or nil at frame-aligned EOF.
    /// - Throws: Concurrent read, closure, decoder or stream errors.
    public func receive<C: Clock>(context: TransportContext<C>) async throws -> RPCFrame? where C.Duration == Duration {
        try context.check()
        guard !reading else { throw RPCFailure.concurrentRead }
        guard !closed else { return nil }
        reading = true; defer { reading = false }
        while frames.isEmpty {
            guard let bytes = try await transport.read(maximumBytes: min(decoder.maximumPayloadBytes + 8, 65_536), context: context) else {
                try decoder.finish(); return nil
            }
            try context.check()
            guard !closed else { return nil }
            guard !bytes.isEmpty else { throw RPCFailure.malformedFrame }
            frames = try decoder.append(bytes)
        }
        return frames.removeFirst()
    }

    /// Discards buffered frames and closes the owned stream, unblocking pending I/O.
    /// Repeated/concurrent calls await the underlying adapter's idempotent cleanup.
    public func close() async { closed = true; frames.removeAll(); decoder.reset(); await transport.close() }
}

/// Selects the documented native IPC discovery namespace, independently of host support.
public enum RPCIPCPlatform: Sendable { case unix, windows }

/// Computes bounded candidate names without probing the filesystem or opening I/O.
public enum RPCDiscovery {
    /// Produces candidate names in deterministic index order for one selected prefix.
    /// - Parameters:
    ///   - platform: Unix sockets or Windows named pipes; not an availability claim.
    ///   - environment: Explicit host environment. Unix selects the first nonempty documented prefix.
    ///   - indices: Explicit local discovery budget, default 0..<10; upstream publishes no upper index limit.
    /// - Returns: At most 100 validated absolute paths or documented Windows pipe names.
    /// - Throws: Relative/NUL paths, invalid/empty/over-100 index ranges. No probing occurs.
    public static func ipcCandidates(platform: RPCIPCPlatform, environment: [String: String], indices: Range<Int> = 0..<10) throws -> [String] {
        guard indices.lowerBound >= 0, !indices.isEmpty, indices.count <= 100 else { throw RPCFailure.invalidConfiguration }
        if platform == .windows { return indices.map { "\\\\?\\pipe\\discord-ipc-\($0)" } }
        let prefix = ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"].compactMap { environment[$0] }.first { !$0.isEmpty } ?? "/tmp"
        guard prefix.hasPrefix("/"), !prefix.utf8.contains(0) else { throw RPCFailure.invalidConfiguration }
        var base = prefix
        while base.hasSuffix("/") { base.removeLast() }
        return indices.map { "\(base)/discord-ipc-\($0)" }
    }
}

/// Injected native IPC opening; platform packages implement sockets or named pipes.
public protocol RPCIPCOpening: Sendable {
    /// Opens exactly one local candidate, without retries or Discord framing.
    /// - Parameters:
    ///   - path: Absolute candidate or documented Windows named-pipe path; never log it.
    ///   - context: Bounded discovery operation's clock/deadline/cancellation.
    /// - Returns: Owned stream; failed startup remains opener-owned.
    /// - Throws: Unavailable candidate, cancellation, timeout or redacted native I/O failure.
    func open<C: Clock>(path: String, context: TransportContext<C>) async throws -> any IPCTransport where C.Duration == Duration
}

/// Bounded sequential IPC discovery with an injected platform opener; no implicit TCP fallback.
public struct RPCIPCConnector: RPCConnector {
    private let candidates: [String]
    private let opener: any RPCIPCOpening
    private let maximumPayloadBytes: Int

    /// Stores validated candidate paths and a native opener without starting work.
    /// - Parameters:
    ///   - platform: Namespace used to construct candidates, independently of OS availability.
    ///   - environment: Explicit process environment for Unix prefix selection.
    ///   - indices: Local discovery budget; default 0..<10, maximum 100 entries.
    ///   - opener: Injected Unix or qualified Windows native stream provider.
    ///   - maximumPayloadBytes: Positive per-frame bound, default 1 MiB.
    /// - Throws: Invalid discovery or frame bounds.
    public init(platform: RPCIPCPlatform, environment: [String: String], indices: Range<Int> = 0..<10, opener: any RPCIPCOpening, maximumPayloadBytes: Int = 1_048_576) throws {
        self.candidates = try RPCDiscovery.ipcCandidates(platform: platform, environment: environment, indices: indices)
        _ = try RPCFrameDecoder(maximumPayloadBytes: maximumPayloadBytes)
        self.maximumPayloadBytes = maximumPayloadBytes; self.opener = opener
    }

    /// Attempts each candidate once; a success transfers stream cleanup to the connection.
    /// - Parameters:
    ///   - applicationID: Registered app ID, used later by the handshake.
    ///   - context: Cancellation/deadline shared across all sequential attempts.
    /// - Returns: First available native IPC connection.
    /// - Throws: Cancellation/deadline immediately, or `.unavailable` after all failures.
    public func connect<C: Clock>(applicationID: ApplicationID, context: TransportContext<C>) async throws -> any RPCConnection where C.Duration == Duration {
        for path in candidates {
            try context.check()
            do {
                let stream = try await opener.open(path: path, context: context)
                do {
                    try context.check()
                    return try RPCIPCConnection(transport: stream, maximumPayloadBytes: maximumPayloadBytes)
                } catch { await stream.close(); throw error }
            } catch is CancellationError { throw CancellationError() }
            catch TransportFailure.deadlineExceeded { throw TransportFailure.deadlineExceeded }
            catch { try context.check() }
        }
        throw RPCFailure.unavailable
    }
}

/// Explicit opt-in for deprecated, approved-private-beta local RPC WebSockets.
/// Uses the RPC-specific documented range 6463...6472; Certified Devices differs.
public struct RPCWebSocketConnector: RPCConnector {
    private let transport: any WebSocketTransport
    private let port: Int
    private let origin: String
    private let maximumPayloadBytes: Int

    /// Stores one explicitly selected local port; never scans or guesses approval.
    /// - Parameters:
    ///   - transport: Caller-owned WebSocket factory, which must honor exact loopback URLs.
    ///   - port: RPC-specific documented port in 6463...6472.
    ///   - origin: Registered HTTP(S) origin with no path/query/credentials/fragment.
    ///   - maximumPayloadBytes: Positive message cap, default 1 MiB.
    /// - Throws: Invalid local port, origin or byte cap. Portal approval is server-authoritative.
    public init(transport: any WebSocketTransport, port: Int, origin: String, maximumPayloadBytes: Int = 1_048_576) throws {
        guard (6463...6472).contains(port), let url = URLComponents(string: origin),
              ["http", "https"].contains(url.scheme), url.host != nil, url.user == nil, url.password == nil,
              url.path.isEmpty, url.query == nil, url.fragment == nil,
              !origin.unicodeScalars.contains(where: { $0.properties.isWhitespace || $0.properties.generalCategory == .control }) else { throw RPCFailure.invalidConfiguration }
        _ = try RPCFrameDecoder(maximumPayloadBytes: maximumPayloadBytes)
        self.transport = transport; self.port = port; self.origin = origin; self.maximumPayloadBytes = maximumPayloadBytes
    }

    /// Opens JSON RPC v1 on fixed 127.0.0.1 with the registered Origin header.
    /// - Parameters:
    ///   - applicationID: App ID encoded as the client_id query parameter.
    ///   - context: Startup cancellation/deadline.
    /// - Returns: Owned local JSON connection; no separate IPC handshake is sent.
    /// - Throws: Upgrade/access/transport failures, cancellation or deadline.
    public func connect<C: Clock>(applicationID: ApplicationID, context: TransportContext<C>) async throws -> any RPCConnection where C.Duration == Duration {
        try context.check()
        guard applicationID.rawValue != 0 else { throw RPCFailure.invalidConfiguration }
        let url = URL(string: "ws://127.0.0.1:\(port)/?v=1&client_id=\(applicationID)&encoding=json")!
        let socket = try await transport.connectWebSocket(HTTPRequest(method: "GET", url: url, headers: [.init(name: "Origin", value: origin)]), context: context)
        do {
            try context.check()
            return RPCWebSocketConnection(socket: socket, maximumPayloadBytes: maximumPayloadBytes)
        } catch { await socket.close(); throw error }
    }
}

/// Message-level RPC WebSocket adaptation; WebSocket adapters own RFC 6455 ping/pong.
private struct RPCWebSocketConnection: RPCConnection {
    let socket: any WebSocketConnection
    let maximumPayloadBytes: Int

    /// Checks startup cancellation; protocol version/application ID were sent in the upgrade URL.
    /// - Parameters:
    ///   - applicationID: Already encoded registered client ID.
    ///   - context: Startup clock/deadline/cancellation.
    /// - Throws: Cancellation or deadline before READY is read.
    func handshake<C: Clock>(applicationID: ApplicationID, context: TransportContext<C>) async throws where C.Duration == Duration { try context.check() }

    /// Sends one UTF-8 JSON message with no IPC header.
    /// - Parameters:
    ///   - frame: Must use `.frame`; control frames belong to the WebSocket adapter.
    ///   - context: Write cancellation/deadline.
    /// - Throws: Unsupported opcode, invalid UTF-8, oversized payload or transport failure.
    func send<C: Clock>(_ frame: RPCFrame, context: TransportContext<C>) async throws where C.Duration == Duration {
        try context.check()
        guard frame.opcode == .frame, frame.payload.count <= maximumPayloadBytes,
              let text = String(data: frame.payload, encoding: .utf8) else { throw RPCFailure.invalidPayload }
        try await socket.send(.text(text), context: context)
    }

    /// Receives one complete UTF-8 text message; binary/ETF messages are unsupported.
    /// - Parameter context: Read clock/deadline/cancellation.
    /// - Returns: A `.frame` wrapper or nil at clean EOF.
    /// - Throws: Binary/oversized input or underlying transport failure.
    func receive<C: Clock>(context: TransportContext<C>) async throws -> RPCFrame? where C.Duration == Duration {
        try context.check()
        guard let message = try await socket.receive(context: context) else { return nil }
        try context.check()
        guard case .text(let text) = message else { throw RPCFailure.invalidPayload }
        guard text.utf8.count <= maximumPayloadBytes else { throw RPCFailure.frameTooLarge }
        return RPCFrame(opcode: .frame, payload: Data(text.utf8))
    }

    /// Closes the exclusively owned socket and releases all adapter resources.
    func close() async { await socket.close() }
}
