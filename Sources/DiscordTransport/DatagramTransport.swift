// File: Sources/DiscordTransport/DatagramTransport.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation

/// An explicit host/port address; DNS and socket-family policy belongs to adapters.
public struct DatagramAddress: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let host: String
    public let port: UInt16

    /// Stores a destination without performing resolution or opening a socket.
    /// - Parameters:
    ///   - host: Hostname or literal address; adapter validates supported syntax.
    ///   - port: Wire port; zero may request ephemeral binding when opening a socket.
    public init(host: String, port: UInt16) { self.host = host; self.port = port }

    /// Hides arbitrary host text from diagnostics; direct address access remains available.
    public var description: String { "DatagramAddress(redacted)" }

    /// Uses safe diagnostic formatting for debug output.
    public var debugDescription: String { description }

    /// Prevents reflective diagnostics from expanding host text.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// One complete datagram and its peer; message boundaries are never combined.
public struct Datagram: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let bytes: Data
    public let peer: DatagramAddress

    /// Creates a datagram without sending it; empty payloads are meaningful.
    /// - Parameters:
    ///   - bytes: Complete payload within adapter-configured size limits.
    ///   - peer: Source for received datagrams, destination for outbound datagrams.
    public init(bytes: Data, peer: DatagramAddress) { self.bytes = bytes; self.peer = peer }

    /// Hides payload bytes and arbitrary peer text from ordinary diagnostics.
    public var description: String { "Datagram(redacted)" }

    /// Uses the same safe representation for debug output.
    public var debugDescription: String { description }

    /// Hides payload and peer storage from generic reflection.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// A bounded pull datagram socket. Delivery, ordering and uniqueness are not promised.
public protocol DatagramTransport: TransportResource {
    /// Sends once without retrying or claiming delivery to the remote application.
    /// - Parameters:
    ///   - datagram: Complete payload and destination, bounded by adapter configuration.
    ///   - context: Deadline and cancellation for this send.
    /// - Throws: Cancellation, expiration, closure, size, resolution or socket errors.
    func sendDatagram<C: Clock>(_ datagram: Datagram, context: TransportContext<C>) async throws
        where C.Duration == Duration

    /// Receives one complete datagram, rejecting truncation instead of returning partial bytes.
    /// - Parameter context: Deadline and cancellation for this single-consumer receive.
    /// - Returns: Next datagram, including an empty payload, or `nil` after orderly close.
    /// - Throws: Concurrent-read, cancellation, expiration, overflow or socket errors.
    func receiveDatagram<C: Clock>(context: TransportContext<C>) async throws -> Datagram?
        where C.Duration == Duration
}
