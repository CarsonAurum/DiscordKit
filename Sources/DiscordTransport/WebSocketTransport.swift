// File: Sources/DiscordTransport/WebSocketTransport.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation

/// Complete application messages; adapters own fragmentation and control frames.
public enum WebSocketMessage: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case text(String)
    case binary(Data)

    /// Avoids exposing application messages or credentials to generic diagnostics.
    public var description: String { "WebSocketMessage(redacted)" }

    /// Returns redacted formatting for debug interpolation and thrown-error context.
    public var debugDescription: String { description }

    /// Hides associated payload values from reflection-based diagnostics.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// An established ordered WebSocket; bounded adapters report oversized messages.
public protocol WebSocketConnection: TransportResource {
    /// Writes one complete message. Concurrent writes are serialized by the adapter.
    /// - Parameters:
    ///   - message: Complete text or binary message within adapter-configured bounds.
    ///   - context: Clock and deadline for admission and write completion.
    /// - Throws: Cancellation, deadline, closure, oversized-message or transport errors.
    func send<C: Clock>(_ message: WebSocketMessage, context: TransportContext<C>) async throws
        where C.Duration == Duration

    /// Pulls the next message without an unbounded receive queue.
    /// - Parameter context: Clock and deadline for this single read.
    /// - Returns: Next complete message in wire order, or `nil` for orderly EOF.
    /// - Throws: Concurrent-read, cancellation, deadline, closure or transport errors.
    ///   Cancellation must terminate pending I/O without leaking the connection.
    func receive<C: Clock>(context: TransportContext<C>) async throws -> WebSocketMessage?
        where C.Duration == Duration
}

/// Establishes WebSockets without Gateway policy, compression, authentication or retry.
public protocol WebSocketTransport: Sendable {
    /// Opens one connection; partial startup resources remain adapter-owned on failure.
    /// - Parameters:
    ///   - request: Upgrade URL and ordered headers. Body must be absent.
    ///   - context: Clock and deadline covering connection and upgrade.
    /// - Returns: Connection whose ownership transfers to the caller until close.
    /// - Throws: Cancellation, expiration, invalid upgrade or transport failures.
    func connectWebSocket<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws
        -> any WebSocketConnection where C.Duration == Duration
}

/// Optional session-aware socket operations for resumable higher-level protocols.
///
/// Ordinary `WebSocketConnection` remains usable; consumers must conservatively
/// discard resumable state after locally closing a connection without this capability.
/// Implementations must retain only the numeric peer code, never unbounded close reasons.
public protocol WebSocketSessionConnection: WebSocketConnection {
    /// Aborts or closes with a code other than 1000/1001, preserving server-side sessions.
    /// Cleanup is idempotent, usable under cancellation, and unblocks pending I/O.
    func closeForReconnect() async

    /// Reports the last observed peer close code without waiting for a future close.
    /// - Returns: Numeric protocol code, or `nil` when unavailable/abruptly disconnected.
    func peerCloseCode() async -> Int?
}
