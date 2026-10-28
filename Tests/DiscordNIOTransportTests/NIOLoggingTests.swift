// File: Tests/DiscordNIOTransportTests/NIOLoggingTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
import DiscordLogging
import DiscordTestSupport
import DiscordTransport
import DiscordNIOTransport

/// Verifies coarse adapter events while packet content remains outside diagnostics.
struct NIOLoggingTests {
    /// Owned UDP binding logs once; sending/receiving payloads never logs packet content.
    @Test func datagramLifecycle() async throws {
        let recorder = LogRecorder()
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let context = TransportContext(clock: ContinuousClock())
            let socket = try await NIODatagramTransport.bind(context: context)
            do {
                let payload = Data("SECRET-PACKET".utf8)
                try await socket.sendDatagram(.init(bytes: payload, peer: socket.localAddress), context: context)
                #expect(try await socket.receiveDatagram(context: context)?.bytes == payload)
            } catch { await socket.close(); throw error }
            await socket.close()
        }
        #expect(recorder.entries.contains { $0.level == .info && $0.metadata["dk.event"] == "nio.datagram.bound" })
        #expect(recorder.entries.contains { $0.level == .info && $0.metadata["dk.event"] == "nio.datagram.closed" })
        #expect(recorder.entries.compactMap { $0.metadata["dk.event"] } == ["nio.datagram.bind", "nio.datagram.bound", "nio.datagram.closed"])
        #expect(!String(describing: recorder.entries).contains("SECRET-PACKET"))
    }
}
