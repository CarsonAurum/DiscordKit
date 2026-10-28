// File: Tests/DiscordMLSTests/MLSNativeDAVEInteropTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

#if os(macOS) || os(Linux)
import Crypto
import Dispatch
import Foundation
import Testing
@testable import DiscordMLS

/// Explicitly opted-in native MLS++ comparison; ordinary tests never fetch or build native code.
/// Anonymous pipes carry synthetic public messages and a transient epoch authenticator. No live
/// material, private keys, wire dumps or secret-bearing failure descriptions are retained.
@Suite struct MLSNativeDAVEInteropTests {
    /// Public corruption scenarios verify that the independent oracle fails closed as well as
    /// accepting the authentic candidate; each scenario owns a fresh native recipient process.
    enum Scenario: String, CaseIterable, Sendable { case valid, wrappedWelcome, truncated, signature, welcome }

    /// Reads one bounded protocol line; the native watchdog closes the pipe if its owner stalls.
    /// - Parameter handle: Anonymous stdout pipe owned by this test's child process.
    /// - Returns: One UTF-8 line of at most 65,536 bytes, excluding its newline.
    /// - Throws: Pipe read errors, malformed UTF-8, EOF or an excessive line assertion.
    private func readLine(_ handle: FileHandle) throws -> String {
        var bytes = Data()
        while bytes.count <= 65_536 {
            guard let next = try handle.read(upToCount: 1), let byte = next.first else {
                throw MLSError.malformedEncoding
            }
            if byte == 10 { return try #require(String(data: bytes, encoding: .utf8)) }
            bytes.append(byte)
        }
        throw MLSError.capacityExceeded
    }

    /// Decodes the reference peer's public KeyPackage without permissive hexadecimal conversion.
    /// - Parameter value: Even-length lowercase hexadecimal line from the bounded native protocol.
    /// - Returns: Complete MLSMessage bytes, containing no private material.
    /// - Throws: Invalid characters or odd/truncated hexadecimal encoding.
    private func unhex(_ value: String) throws -> Data {
        let characters = Array(value.utf8)
        guard characters.count.isMultiple(of: 2) else { throw MLSError.malformedEncoding }
        var bytes = Data()
        for offset in stride(from: 0, to: characters.count, by: 2) {
            guard let byte = UInt8(String(decoding: characters[offset..<offset + 2], as: UTF8.self), radix: 16) else {
                throw MLSError.malformedEncoding
            }
            bytes.append(byte)
        }
        return bytes
    }

    /// Verifies an emitted initial candidate against a separately compiled Cisco MLS++ decoder,
    /// signature/reference verifier and full Welcome join. The expected authenticator crosses
    /// an anonymous pipe only; the child prints a fixed acceptance/failure stage and no inputs.
    /// A 15-second process watchdog bounds native hangs, and deferred cleanup always joins it.
    /// - Parameter scenario: Authentic input or one deliberate framing/authentication corruption.
    /// - Throws: Synthetic setup, process/pipe or MLS errors; never requires Discord or devices.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DISCORDKIT_DAVE_INTEROP_EXECUTABLE"] != nil),
          arguments: Scenario.allCases)
    func initialCandidateAcceptedByMLSpp(_ scenario: Scenario) async throws {
        let executable = try #require(ProcessInfo.processInfo.environment["DISCORDKIT_DAVE_INTEROP_EXECUTABLE"])
        let process = Process(), input = Pipe(), output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        try process.run()
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: watchdog)
        defer {
            watchdog.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
            try? errors.fileHandleForReading.close()
        }
        let native = try MLSKeyPackage.decode(unhex(readLine(output.fileHandleForReading)), messageWrapped: true)
        try native.validate(now: 0, validateLifetime: false)
        let external = P256.Signing.PrivateKey(compactRepresentable: false)
        let sender = try MLSExternalSender(signatureKey: external.publicKey.x963Representation,
            credential: MLSCredential(identity: Data("synthetic-gateway".utf8)))
        let owner = try MLSKeyPackageOwner(userID: 1)
        let id = Data([0, 0, 0, 0, 0, 0, 0, 4])
        let policy = try MLSGroupPolicy(externalSender: sender, expectedParticipants: [1, 2])
        let group = try await owner.createGroup(groupID: id, policy: policy)
        let proposal = try MLSProposal.add(native).externalMessage(groupID: id, epoch: 0,
            signaturePrivateKey: external.rawRepresentation)
        _ = try await group.cacheProposal(proposal)
        let candidate = try await group.prepareCommit()
        let welcome = try #require(candidate.welcome)
        let publicCommit = try MLSPublicMessage.decode(candidate.commit)
        var wire = candidate.commit + welcome.dropFirst(4)
        switch scenario {
        case .valid: break
        case .wrappedWelcome: wire = candidate.commit + welcome
        case .truncated: wire.removeLast()
        case .signature:
            var altered = publicCommit; altered.signature[0] ^= 1
            wire = try altered.encoded() + welcome.dropFirst(4)
        case .welcome: wire[wire.count - 1] ^= 1
        }
        #expect(try await group.acceptCommit(candidate.commit) == .advanced)
        let authenticator = try await group.epochAuthenticator()
        await group.close()
        for bytes in [try owner.keyPackage.encoded(messageWrapped: true), try sender.encoded(), proposal, wire, authenticator] {
            let line = bytes.map { String(format: "%02x", $0) }.joined() + "\n"
            try input.fileHandleForWriting.write(contentsOf: Data(line.utf8))
        }
        try input.fileHandleForWriting.close()
        let result = try readLine(output.fileHandleForReading)
        process.waitUntilExit()
        switch scenario {
        case .valid: #expect(result == "accepted"); #expect(process.terminationStatus == 0)
        case .wrappedWelcome, .truncated: #expect(result == "rejected:native.candidate_decode")
        case .signature: #expect(result == "rejected:native.signatures_references")
        case .welcome: #expect(result == "rejected:native.welcome_join")
        }
        if scenario != .valid { #expect(process.terminationStatus == 1) }
    }
}
#endif
