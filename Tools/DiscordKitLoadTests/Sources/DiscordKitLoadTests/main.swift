// File: Tools/DiscordKitLoadTests/Sources/DiscordKitLoadTests/main.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordLogging
import DiscordNIOTransport
import Foundation

/// Repository-relative package location; source checkout is required for local peers/profiles.
enum LoadPaths {
    static let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
}

/// Validated small CLI surface; unimplemented runtime scenarios fail explicitly.
struct LoadOptions: Equatable, Sendable {
    let profileName: String
    let scenario: String
    let burst: Bool
    let portable: Bool
    let withoutDeadline: Bool
    let settleSeconds: Int
    let rounds: Int?
    let durationSeconds: Int?

    /// Parses workload and allocation diagnostics without starting runtime work.
    /// Profile defaults to accounts-100 and scenario to transport; HTTP and Gateway
    /// select separate offline policy scripts. `--burst` offers
    /// tenfold concurrency; `--portable` removes sockets; `--without-deadline`
    /// explicitly disables ten-second deadlines. `--settle-seconds` defaults to zero
    /// and accepts zero through thirty seconds solely for post-cleanup measurements.
    /// - Parameter arguments: Arguments after the executable name.
    /// - Throws: `invalidArguments` for unknown/missing/duplicate flags, or
    ///   `unsupportedScenario` for unknown scenarios. Cache/soak accepts exact
    ///   `--rounds` in 1...1,000,000; other scenarios reject that option. Soak alone
    ///   accepts `--duration-seconds` in 1...3,600; rounds then set minimum work.
    init(arguments: [String]) throws {
        var profile = "accounts-100"
        var scenario = "transport"
        var isBurst = false
        var isPortable = false
        var disablesDeadline = false
        var settling = 0
        var rounds: Int?
        var duration: Int?
        var seen: Set<String> = []
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            guard seen.insert(flag).inserted else { throw LoadFailure.invalidArguments }
            switch flag {
            case "--profile", "--scenario", "--settle-seconds", "--rounds", "--duration-seconds":
                guard index + 1 < arguments.count else { throw LoadFailure.invalidArguments }
                index += 1
                if flag == "--profile" { profile = arguments[index] }
                else if flag == "--scenario" { scenario = arguments[index] }
                else if flag == "--rounds" {
                    guard let count = Int(arguments[index]), (1...1_000_000).contains(count) else { throw LoadFailure.invalidArguments }
                    rounds = count
                }
                else if flag == "--duration-seconds" {
                    guard let seconds = Int(arguments[index]), (1...3_600).contains(seconds) else { throw LoadFailure.invalidArguments }
                    duration = seconds
                }
                else {
                    guard let value = Int(arguments[index]), (0...30).contains(value) else { throw LoadFailure.invalidArguments }
                    settling = value
                }
            case "--burst": isBurst = true
            case "--portable": isPortable = true
            case "--without-deadline": disablesDeadline = true
            default: throw LoadFailure.invalidArguments
            }
            index += 1
        }
        guard ["transport", "http", "gateway", "cache", "soak"].contains(scenario) else { throw LoadFailure.unsupportedScenario }
        guard !profile.isEmpty else { throw LoadFailure.invalidArguments }
        guard rounds == nil || scenario == "cache" || scenario == "soak" else { throw LoadFailure.invalidArguments }
        guard duration == nil || scenario == "soak" else { throw LoadFailure.invalidArguments }
        profileName = profile
        self.scenario = scenario
        burst = isBurst
        portable = isPortable
        withoutDeadline = disablesDeadline
        settleSeconds = settling
        self.rounds = rounds
        durationSeconds = duration
    }
}

/// An owned local Python peer; process metrics deliberately exclude peer overhead.
struct LocalPeer {
    let process: Process
    let output: FileHandle
    let url: URL

    /// Starts a loopback-only HTTP/1.1 peer and consumes its one-line bound-port handshake.
    ///
    /// Startup briefly blocks on the development subprocess pipe. It is outside the
    /// measured workload and never appears in library/runtime products. The source
    /// checkout and `python3` on PATH are required.
    /// - Parameter payloadBytes: Validated exact response bytes, zero through 1 MiB.
    /// - Returns: Running peer whose owner must call `stop` on every exit path.
    /// - Throws: Process launch errors or `peerStartup` for an invalid/absent handshake.
    static func start(payloadBytes: Int) throws -> Self {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", LoadPaths.packageDirectory.appendingPathComponent("scripts/local_peer.py").path,
                             "--payload-bytes", String(payloadBytes)]
        process.standardOutput = pipe
        try process.run()
        do {
            let data = pipe.fileHandleForReading.availableData
            guard let text = String(data: data, encoding: .utf8),
                  let port = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...65_535).contains(port), let url = URL(string: "http://127.0.0.1:\(port)/payload")
            else { throw LoadFailure.peerStartup }
            return Self(process: process, output: pipe.fileHandleForReading, url: url)
        } catch {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            throw error
        }
    }

    /// Terminates/reaps the peer and reads its final physical-socket counter snapshot.
    /// The synchronous process wait runs outside measured I/O. Call after client
    /// cleanup; a repeated stop performs no additional cleanup and may return nil.
    /// - Returns: Peer aggregate counts, or nil after failed/previously consumed output.
    func stop() -> PeerConnectionMetrics? {
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        return try? JSONDecoder().decode(PeerConnectionMetrics.self, from: output.availableData)
    }
}

/// Actual peer-side TCP counts, independent of the client's sampled pool slots.
struct PeerConnectionMetrics: Codable, Sendable {
    let acceptedConnections: Int
    let activeConnections: Int
    let peakConnections: Int
}

/// Reviewable output includes post-shutdown ownership and explicit measurement limits.
struct LoadReport: Codable {
    let measurement: LoadMeasurement
    let afterShutdown: ProcessSample
    let settledAfterShutdown: ProcessSample?
    let settleSeconds: Int
    let peerConnections: PeerConnectionMetrics?
    let poolActiveAfterShutdown: Int
    let poolIdleAfterShutdown: Int
    let operatingSystem: String
    let processorCount: Int
    let notes: [String]
}

/// Owns the peer and adapter through successful, failed, and cancelled load execution.
enum LoadCommand {
    /// Runs one supported local scenario and writes a credential-free JSON report.
    /// - Parameter arguments: Command-line flags, defaulting to `CommandLine.arguments` tail.
    /// - Throws: Argument/profile/startup, transport setup, encoding, or stdout errors.
    ///   Runtime per-request failures are counted. Transport measurements never retry;
    ///   the HTTP scenario exercises its explicit finite rejected-request retry contract.
    static func run(arguments: [String]) async throws {
        let options = try LoadOptions(arguments: arguments)
        if options.scenario == "cache" || options.scenario == "soak" {
            guard !options.portable, !options.withoutDeadline, options.settleSeconds == 0 else { throw LoadFailure.invalidArguments }
            guard #available(macOS 15, *) else { throw LoadFailure.unsupportedHost }
            let report = try await CacheLoadRunner().run(profileName: options.profileName, burst: options.burst,
                rounds: options.rounds ?? (options.scenario == "soak" ? 512 : 8), scenario: options.scenario,
                durationSeconds: options.durationSeconds)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            var data = try encoder.encode(report); data.append(10)
            try FileHandle.standardOutput.write(contentsOf: data)
            return
        }
        if options.scenario == "gateway" {
            guard !options.portable, !options.withoutDeadline, options.settleSeconds == 0 else { throw LoadFailure.invalidArguments }
            let report = try await GatewayLoadRunner().run(profileName: options.profileName, burst: options.burst)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            var data = try encoder.encode(report); data.append(10)
            try FileHandle.standardOutput.write(contentsOf: data)
            return
        }
        if options.scenario == "http" {
            guard !options.portable, !options.withoutDeadline, options.settleSeconds == 0 else { throw LoadFailure.invalidArguments }
            let profile = try HTTPWorkloadProfile.load(name: options.profileName,
                directory: LoadPaths.packageDirectory.appendingPathComponent("HTTPProfiles"))
            let report = try await HTTPPolicyRunner().run(profile: profile, burst: options.burst)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            var data = try encoder.encode(report); data.append(10)
            try FileHandle.standardOutput.write(contentsOf: data)
            return
        }
        let profile = try WorkloadProfile.load(name: options.profileName,
                                               directory: LoadPaths.packageDirectory.appendingPathComponent("Profiles"))
        if options.portable {
            let measurement = try await LoadRunner().run(
                profile: profile, transport: PortableLoadTransport(payloadBytes: profile.payloadBytes),
                url: URL(string: "http://127.0.0.1/")!,
                offeredConcurrency: profile.activeCohort * (options.burst ? profile.burstMultiplier : 1),
                requestDeadline: options.withoutDeadline ? nil : .seconds(10))
            try await emit(measurement: measurement, active: 0, idle: 0, peerConnections: nil,
                           settleSeconds: options.settleSeconds,
                     extraNotes: ["Portable allocation diagnostic: zero sockets; no capacity qualification."])
            return
        }
        let peer = try LocalPeer.start(payloadBytes: profile.payloadBytes)
        defer { _ = peer.stop() }
        let transport = try NIOHTTPTransport(configuration: NIOHTTPConfiguration(
            maximumConnections: profile.maximumConnections,
            maximumConnectionsPerOrigin: profile.maximumConnections,
            maximumRequestBytes: 0, maximumResponseBytes: profile.payloadBytes,
            maximumHeaderBytes: 4_096, chunkBytes: 1_024))
        do {
            let measurement = try await LoadRunner().run(
                profile: profile, transport: transport, url: peer.url,
                offeredConcurrency: profile.activeCohort * (options.burst ? profile.burstMultiplier : 1),
                requestDeadline: options.withoutDeadline ? nil : .seconds(10),
                poolSlots: {
                    let counts = await transport.connectionCounts()
                    return counts.active + counts.idle
                })
            await transport.close()
            let counts = await transport.connectionCounts()
            guard let peerConnections = peer.stop() else { throw LoadFailure.peerStartup }
            try await emit(measurement: measurement, active: counts.active, idle: counts.idle,
                           peerConnections: peerConnections, settleSeconds: options.settleSeconds,
                     extraNotes: options.withoutDeadline ? ["Explicit diagnostic: per-request deadlines disabled."] : [])
        } catch {
            await transport.close()
            throw error
        }
    }
    /// Encodes a completed measurement with post-cleanup gauges and safe scope notes.
    /// - Parameters:
    ///   - measurement: Completed bounded workload result.
    ///   - active: Adapter-owned active slots after shutdown, expected zero.
    ///   - idle: Adapter-owned idle slots after shutdown, expected zero.
    ///   - peerConnections: Actual local-peer TCP counts, nil for portable diagnostics.
    ///   - settleSeconds: Optional wall-time diagnostic wait, zero through thirty seconds.
    ///     Only performance probes wait; deterministic unit tests never rely on this delay.
    ///   - extraNotes: Explicit diagnostic qualifiers, empty for ordinary transport runs.
    /// - Throws: Cancellation during optional settling, JSON encoding or stdout write errors.
    private static func emit(measurement: LoadMeasurement, active: Int, idle: Int,
                             peerConnections: PeerConnectionMetrics?, settleSeconds: Int,
                             extraNotes: [String]) async throws {
        let immediate = ProcessSample.capture()
        var settled: ProcessSample?
        if settleSeconds > 0 {
            try await Task.sleep(for: .seconds(settleSeconds))
            settled = ProcessSample.capture()
        }
        let report = LoadReport(
            measurement: measurement, afterShutdown: immediate, settledAfterShutdown: settled, settleSeconds: settleSeconds,
            peerConnections: peerConnections, poolActiveAfterShutdown: active, poolIdleAfterShutdown: idle,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            processorCount: ProcessInfo.processInfo.processorCount,
            notes: extraNotes + [
                "Logical accounts are served end users; one client process and a separate Python loopback peer for socket runs.",
                "Pool-slot peaks are sampled; configured cap and real successful socket exchanges are distinct.",
                "Live malloc block/byte gauges are not a cumulative allocation trace; CPU/RSS exclude the peer.",
                "This transport measurement excludes HTTP/Gateway policy scenarios and 30-minute soak qualification.",
            ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(report)
        data.append(10)
        try FileHandle.standardOutput.write(contentsOf: data)
    }
}

// Process entry owns diagnostic routing; reusable runners never bootstrap SwiftLog.
LoggingSystem.bootstrap(StreamLogHandler.standardError)

do {
    try await LoadCommand.run(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    let reason = (error as? LoadFailure).map { String(describing: $0) } ?? "localScenarioFailed"
    FileHandle.standardError.write(Data("Local load harness failed: \(reason)\n".utf8))
    exit(1)
}
