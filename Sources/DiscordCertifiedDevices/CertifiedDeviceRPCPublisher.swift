// File: Sources/DiscordCertifiedDevices/CertifiedDeviceRPCPublisher.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordLogging
import DiscordCore
import DiscordRPC
import DiscordTransport

/// Typed full-replacement publication through an independently adopted RPC client.
///
/// The caller owns connection, authentication, event pumping and closure. This
/// wrapper starts no work during construction and does not broaden desktop access.
/// Generic RPC's deprecated WebSocket route remains restricted to approved legacy
/// beta applications; use the RPC client's public IPC transport when applicable.
public struct CertifiedDeviceRPCPublisher<C: Clock>: Sendable where C.Duration == Duration {
    private let client: RPCClient<C>
    private let maximumDevices: Int
    private let maximumArgumentBytes: Int

    /// Borrows a configured RPC client without connecting, authenticating or subscribing.
    /// - Parameters:
    ///   - client: Caller-owned RPC client; it must already be explicitly connected
    ///     and authorized as required by Discord before publication.
    ///   - maximumDevices: Inclusive local device count in `1...1_024`, default 128.
    ///   - maximumArgumentBytes: Local argument-byte limit in `1...1_048_576`, default
    ///     262,144. The RPC client's complete-envelope/frame cap applies independently.
    /// - Throws: `CertifiedDeviceFailure.invalidLimits` for unsafe local bounds.
    public init(client: RPCClient<C>, maximumDevices: Int = 128,
                maximumArgumentBytes: Int = 262_144) throws {
        guard (1...1_024).contains(maximumDevices), (1...1_048_576).contains(maximumArgumentBytes) else {
            throw CertifiedDeviceFailure.invalidLimits
        }
        self.client = client
        self.maximumDevices = maximumDevices
        self.maximumArgumentBytes = maximumArgumentBytes
    }

    /// Sends the entire current device list once through bounded RPC admission.
    /// - Parameters:
    ///   - devices: Complete highest-priority-first list, or empty to clear it.
    ///     Repeated `(type,id)` pairs fail before submission; native IDs may be
    ///     shared across different device types. No prior list is retained or merged.
    ///   - context: Clock, deadline and cooperative cancellation for the borrowed RPC client.
    /// - Throws: Device/count/byte validation failures, RPC connection/approval/auth
    ///   errors, overload, cancellation or expiration. The runtime owns nonce
    ///   correlation and transport cleanup. A non-null acknowledgement fails as
    ///   `.invalidResponse`; requests are never automatically replayed on failure.
    public func publish(_ devices: [CertifiedDevice], context: TransportContext<C>) async throws {
        try context.check()
        let arguments = try certifiedDeviceArguments(devices, maximumDevices: maximumDevices)
        let request = try RPCRequest(command: .setCertifiedDevices, arguments: arguments,
            limits: JSONLimits(maximumBytes: maximumArgumentBytes))
        let logger = DiscordLog.makeLogger("certified_devices.rpc")
        logger.trace("Certified devices RPC publication started", metadata: ["dk.event": "certified_devices.rpc.started",
            "dk.count": .stringConvertible(devices.count)])
        let result = try await client.request(request, context: context)
        guard result == .null else {
            logger.debug("Certified devices RPC acknowledgement rejected", metadata: ["dk.event": "certified_devices.rpc.failed"])
            throw CertifiedDeviceFailure.invalidResponse
        }
        logger.info("Certified devices RPC publication acknowledged", metadata: ["dk.event": "certified_devices.rpc.completed"])
    }
}
