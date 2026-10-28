// File: Examples/LoggingApp/Sources/LoggingApp/LoggingApp.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import DiscordLogging
import DiscordLogHandlers
import DiscordTransport

/// Standalone offline process demonstrating application-owned SwiftLog bootstrap.
@main struct LoggingApp {
    /// Bootstraps once, exercises semantic/subsystem events and closes the shared file.
    /// - Throws: File setup/close errors or an invalid smoke-test observation.
    ///   No Discord credentials, network connections or devices are used.
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("discordkit.ndjson")
        let sink = try DiscordFileLogSink(url: destination)
        LoggingSystem.bootstrap({ label, provider in
            var console = StreamLogHandler.standardError(label: label)
            console.logLevel = .info
            console.metadataProvider = provider
            return MultiplexLogHandler([
                DiscordLevelFilterLogHandler(console, minimumLevel: .info),
                DiscordFileLogHandler(label: label, sink: sink, logLevel: .trace, metadataProvider: provider),
            ])
        }, metadataProvider: .init { ["example.context": "offline"] })

        let policy = DiscordLogConfiguration(defaultLevel: .info, overrides: [
            "example.logging": .trace, "transport": .trace,
        ])
        try DiscordLog.$configuration.withValue(policy) {
            try DiscordLog.$context.withValue(["example.run": "offline"]) {
                try DiscordLog.withOperation("example.logging", event: "example.logging") {
                    let app = DiscordLog.makeLogger("example.logging")
                    app.info("Offline logging example started")
                    app.notice("Application semantic event", metadata: ["action": "logging-demo"])
                    do {
                        let clock = ContinuousClock()
                        try TransportContext(clock: clock, deadline: clock.now).check()
                    } catch TransportFailure.deadlineExceeded {
                        app.debug("Expected synthetic deadline observed")
                    }
                }
            }
        }
        try sink.close()
        let records = try readRecords(from: destination)
        guard records.contains(where: { $0["level"] as? String == "notice" }),
              records.contains(where: {
                  ($0["metadata"] as? [String: Any])?["dk.event"] as? String == "transport.deadline.expired"
              }), records.contains(where: {
                  let metadata = $0["metadata"] as? [String: Any]
                  return metadata?["dk.event"] as? String == "example.logging.completed"
                      && metadata?["dk.duration_ns"] is String
              }), records.allSatisfy({
                  let metadata = $0["metadata"] as? [String: Any]
                  return metadata?["example.context"] as? String == "offline"
                      && metadata?["example.run"] as? String == "offline"
                      && metadata?["dk.trace_id"] is String && metadata?["dk.span_id"] is String
              }) else {
            throw ExampleFailure.missingOutput
        }
    }

    /// Reads the example's bounded NDJSON output after explicit sink closure.
    /// - Parameter url: Temporary destination owned by this example.
    /// - Returns: JSON objects in file order, with no retained file handle.
    /// - Throws: Read/JSON failures or a nonobject line.
    static func readRecords(from url: URL) throws -> [[String: Any]] {
        try Data(contentsOf: url).split(separator: 10).map { line in
            guard let object = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                throw ExampleFailure.missingOutput
            }
            return object
        }
    }
}

/// Explicit smoke-test failure without paths, log payloads or underlying error text.
enum ExampleFailure: Error, Equatable { case missingOutput }
