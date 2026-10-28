// File: Examples/DSLCommands/Tests/DSLCommandsTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordDSL
import Testing
@testable import DSLCommands

/// The independent application compiles genuine macros and executes exact signed HTTP response assertions.
@Suite struct DSLCommandsTests {
    /// One macro-authored ping is compiled once and served twice using independent signature/response owners.
    /// Construction/compilation and serving have no registration client or network adapter to invoke.
    /// - Throws: Any schema, macro registration, crypto, ingress, routing or callback mismatch fails the test.
    @Test func signedOfflinePing() async throws {
        let ping = try Ping().contribution(id: "example.ping", source: .init(fileID: "test", line: 1))
        let commands = try CommandCompilation.compile(Module(id: "test") { ping })
        #expect(commands.definitions.map(\.request.name) == ["ping"])
        for _ in 0..<2 { try await DSLCommands.offline(commands) }
    }
    /// The independent consumer executes every family through signed HTTP with exact callback assertions.
    /// Its catalog contains four registrations and seven routes; shared component/modal IDs remain distinct.
    /// - Throws: Any catalog, signing, authentication, invocation or callback mismatch fails this test.
    @Test func signedOfflineFamilies() async throws {
        let commands = try FamilyExamples.catalog()
        #expect(commands.definitions.count == 4)
        #expect(commands.routes.count == 7)
        try await FamilyExamples.run()
    }

    /// Independent policy composition runs through genuine synthetic signed HTTP and exact callback checks.
    /// The successful request records outer-left/inner-right entry and reverse exit; denial records only
    /// current authorization and returns its explicit ephemeral callback before middleware or handler work.
    /// - Throws: Authoring, signature, response parity, event order or shared-permit cleanup failures.
    @Test func signedOfflinePolicies() async throws {
        let evidence = try await PolicyExamples.run()
        #expect(evidence.allowed == ["authorize", "audit enter", "metrics enter", "handler", "metrics exit", "audit exit"])
        #expect(evidence.denied == ["authorize"])
    }

    /// An imported extension executes custom decoding, exact raw command parity and actor-backed denial.
    /// - Throws: Any dependency, signature, callback or effect-count mismatch fails the external consumer.
    @Test func signedOfflineExternalExtensions() async throws {
        let evidence = try await ExtensionExamples.run()
        #expect(evidence.authorizations == 2)
        #expect(evidence.executions == 2)
    }
}
