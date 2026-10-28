// File: Sources/DiscordCertifiedDevices/CertifiedDeviceWebSocketConnector.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordRPC
import DiscordTransport
import Foundation

/// Explicit deprecated WebSocket connector for the Certified Devices documented port range.
///
/// Discord's RPC reference restricts WebSockets to approved legacy beta participants.
/// This connector does not grant approval or turn the desktop interface into bot REST.
/// Construction performs no scan, network I/O or background work.
public struct CertifiedDeviceWebSocketConnector: RPCConnector {
    private let transport: any WebSocketTransport
    private let port: Int
    private let origin: String
    private let maximumPayloadBytes: Int

    /// Pins an approved local WebSocket endpoint and registered RPC origin.
    /// - Parameters:
    ///   - transport: Borrowed WebSocket factory. It must honor exact loopback URLs,
    ///     avoid redirects/proxies, and return an exclusively owned connection.
    ///   - port: Explicit Certified Devices port in `6463...6473`; no discovery occurs.
    ///   - origin: Registered absolute HTTP(S) origin with no path, query, fragment,
    ///     credentials or whitespace, at most 2,048 UTF-8 bytes. Server approval remains authoritative.
    ///   - maximumPayloadBytes: Complete text-frame byte cap in `1...1_048_576`, default 262,144.
    /// - Throws: `CertifiedDeviceFailure.invalidPort`, `.invalidURL` or `.invalidLimits`.
    public init(transport: any WebSocketTransport, port: Int, origin: String,
                maximumPayloadBytes: Int = 262_144) throws {
        guard CertifiedDeviceHTTPPublisher.documentedPorts.contains(port) else { throw CertifiedDeviceFailure.invalidPort }
        guard let parts = URLComponents(string: origin), let scheme = parts.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty, parts.path.isEmpty, parts.query == nil,
              parts.fragment == nil, parts.user == nil, parts.password == nil,
              origin.utf8.count <= 2_048,
              !origin.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0)
                  || CharacterSet.controlCharacters.contains($0) }) else { throw CertifiedDeviceFailure.invalidURL }
        guard (1...1_048_576).contains(maximumPayloadBytes) else { throw CertifiedDeviceFailure.invalidLimits }
        self.transport = transport
        self.port = port
        self.origin = origin
        self.maximumPayloadBytes = maximumPayloadBytes
    }

    /// Opens exactly one JSON v1 WebSocket on 127.0.0.1 without scanning or retries.
    /// - Parameters:
    ///   - applicationID: Nonzero registered application ID, sent as `client_id`.
    ///   - context: Cancellation/deadline covering the upgrade and ownership transfer.
    /// - Returns: Exclusively owned RPC connection; its close releases the socket.
    /// - Throws: Invalid application ID, upgrade/access errors, cancellation or deadline.
    ///   Native transport failures are redacted to `RPCFailure.connectionLost`.
    public func connect<C: Clock>(applicationID: ApplicationID, context: TransportContext<C>) async throws
        -> any RPCConnection where C.Duration == Duration {
        try context.check()
        guard applicationID.rawValue != 0 else { throw CertifiedDeviceFailure.invalidClientID }
        var parts = URLComponents()
        parts.scheme = "ws"
        parts.host = "127.0.0.1"
        parts.port = port
        parts.path = "/"
        parts.queryItems = [URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "client_id", value: applicationID.description),
            URLQueryItem(name: "encoding", value: "json")]
        guard let url = parts.url else { throw CertifiedDeviceFailure.invalidURL }
        do {
            let socket = try await transport.connectWebSocket(HTTPRequest(method: "GET", url: url,
                headers: [HTTPHeader(name: "Origin", value: origin)]), context: context)
            do {
                try context.check()
                return CertifiedDeviceSocketConnection(socket: socket, maximumPayloadBytes: maximumPayloadBytes)
            } catch {
                await socket.close()
                throw error
            }
        } catch is CancellationError { throw CancellationError() }
        catch TransportFailure.deadlineExceeded { throw TransportFailure.deadlineExceeded }
        catch { throw RPCFailure.connectionLost }
    }
}

/// Adapts complete JSON messages to RPC frames; the socket owns WebSocket control frames.
private struct CertifiedDeviceSocketConnection: RPCConnection {
    let socket: any WebSocketConnection
    let maximumPayloadBytes: Int

    /// Checks startup context; v1/application identity already accompanied the upgrade.
    /// - Parameters:
    ///   - applicationID: Identity already sent in the WebSocket URL; no second handshake is emitted.
    ///   - context: Startup cancellation and deadline.
    /// - Throws: Cancellation or expiration; performs no I/O.
    func handshake<C: Clock>(applicationID: ApplicationID, context: TransportContext<C>) async throws
        where C.Duration == Duration { try context.check() }

    /// Sends one bounded complete UTF-8 JSON frame without an IPC byte header.
    /// - Parameters:
    ///   - frame: Standard RPC `.frame`; IPC control opcodes and malformed UTF-8 are rejected.
    ///   - context: Cancellation/deadline supplied by the owning RPC client.
    /// - Throws: `RPCFailure.frameTooLarge` or `.invalidPayload`, or socket errors.
    func send<C: Clock>(_ frame: RPCFrame, context: TransportContext<C>) async throws where C.Duration == Duration {
        try context.check()
        guard frame.payload.count <= maximumPayloadBytes else { throw RPCFailure.frameTooLarge }
        guard frame.opcode == .frame, let text = String(data: frame.payload, encoding: .utf8) else {
            throw RPCFailure.invalidPayload
        }
        try await socket.send(.text(text), context: context)
    }

    /// Receives one complete text message, preserving JSON bytes for bounded RPC parsing.
    /// - Parameter context: Cancellation/deadline for the single runtime reader.
    /// - Returns: A standard RPC frame, or nil when the peer reaches EOF.
    /// - Throws: Binary messages as `.invalidPayload`, excessive bytes as `.frameTooLarge`,
    ///   or socket read/cancellation/deadline errors. ETF is deliberately unsupported.
    func receive<C: Clock>(context: TransportContext<C>) async throws -> RPCFrame? where C.Duration == Duration {
        try context.check()
        guard let message = try await socket.receive(context: context) else { return nil }
        guard case .text(let text) = message else { throw RPCFailure.invalidPayload }
        guard text.utf8.count <= maximumPayloadBytes else { throw RPCFailure.frameTooLarge }
        return RPCFrame(opcode: .frame, payload: Data(text.utf8))
    }

    /// Releases the exclusively owned socket; the adapter provides idempotent cleanup.
    func close() async { await socket.close() }
}
