// File: Examples/RPCApp/Sources/RPCApp/RPCApp.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordRPC
import DiscordCertifiedDevices
import Foundation

/// Independently adopted desktop protocol examples; execution opens no sockets or authorization UI.
@main struct RPCApp {
    /// Builds local requests/device metadata and prints only redacted descriptions.
    /// - Throws: Local catalog/device validation failures; no network/authenticated call is made.
    static func main() throws {
        let request = try RPCRequest.getGuilds()
        let product = try CertifiedDeviceProduct(name: "Example", url: URL(string: "https://example.com")!)
        let input = try CertifiedDevice(type: .audioInput, id: "Injected native device name", vendor: product, model: product, related: [])
        print(request.description)
        print(input.description)
    }

    /// Composes a session with an application-supplied local connector; starts no I/O or tasks.
    /// - Parameters:
    ///   - applicationID: Registered Discord RPC application ID; not a bot credential.
    ///   - connector: Owned Unix socket/Windows pipe opener or approved legacy local WebSocket factory.
    /// - Returns: Unconnected session; the application must explicitly connect, authorize, subscribe and close.
    /// - Throws: Invalid local runtime configuration or a zero application identifier.
    static func makeClient(applicationID: ApplicationID, connector: any RPCConnector) throws -> RPCClient<ContinuousClock> {
        try RPCClient(applicationID: applicationID, clock: ContinuousClock(), connector: connector)
    }
}
