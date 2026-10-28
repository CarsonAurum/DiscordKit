// File: Tools/AppleAudioQualification/Sources/QualificationSupport/Qualification.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordApplePlatform
import DiscordMedia
import Foundation

/// Argument failures are explicit; invalid input never falls through to device access.
public enum QualificationError: Error, Equatable {
    case invalidArguments, missingConsent, unavailableDevice
}

/// Explicit qualification operations; probing never starts I/O or requests permission.
public enum QualificationMode: String, Codable, Sendable {
    case probe, duplex, route, unplug, interruption
}

/// A bounded playback-capacity observation; waiting never reserves or discards audio.
public struct PlaybackAdmissionObservation: Equatable, Sendable {
    /// Explicit outcomes distinguish native stop from sustained capacity exhaustion.
    public enum Outcome: Equatable, Sendable { case ready, stopped, timedOut }
    public let outcome: Outcome
    public let waitMilliseconds: Double
    public let suspensions: Int
}

/// Caller-owned backpressure with injected monotonic time and cooperative suspension.
@MainActor public enum PlaybackAdmission {
    /// Waits for capacity before the runner consumes or encodes another microphone frame.
    /// No PCM, native reservation or waiter task is retained by this operation. The caller must
    /// keep capture independently bounded and decide how to report a stop or timeout.
    /// - Parameters:
    ///   - maximumWaitMilliseconds: Finite nonnegative bound; zero permits only an immediate check.
    ///   - isRunning: Actor-local lifecycle read, checked before capacity at every iteration.
    ///   - hasCapacity: Actor-local capacity read; true means the next frame can be admitted.
    ///   - milliseconds: Finite monotonic clock in milliseconds, injected for deterministic tests.
    ///   - suspend: Cooperative bounded suspension; the runner uses a two-millisecond sleep.
    /// - Returns: Outcome, elapsed wait and actual suspension count. Capacity observed at the
    ///   timeout boundary wins because admission is already available; a stopped owner never does.
    /// - Throws: Cancellation before admission or from suspension, propagated suspension errors,
    ///   or `invalidArguments` for an invalid bound/nonfinite/backwards clock. No audio is consumed.
    public static func wait(maximumWaitMilliseconds: Double = 250,
                            isRunning: () -> Bool, hasCapacity: () -> Bool,
                            milliseconds: () -> Double,
                            suspend: () async throws -> Void) async throws -> PlaybackAdmissionObservation {
        guard maximumWaitMilliseconds.isFinite, maximumWaitMilliseconds >= 0 else {
            throw QualificationError.invalidArguments
        }
        let began = milliseconds()
        guard began.isFinite else { throw QualificationError.invalidArguments }
        var previous = began
        var suspensions = 0
        while true {
            try Task.checkCancellation()
            let now = milliseconds()
            guard now.isFinite, now >= previous else { throw QualificationError.invalidArguments }
            previous = now
            let elapsed = now - began
            guard elapsed.isFinite else { throw QualificationError.invalidArguments }
            if !isRunning() {
                return PlaybackAdmissionObservation(outcome: .stopped, waitMilliseconds: elapsed,
                                                     suspensions: suspensions)
            }
            if elapsed <= maximumWaitMilliseconds && hasCapacity() {
                return PlaybackAdmissionObservation(outcome: .ready, waitMilliseconds: elapsed,
                                                     suspensions: suspensions)
            }
            if elapsed >= maximumWaitMilliseconds {
                return PlaybackAdmissionObservation(outcome: .timedOut, waitMilliseconds: elapsed,
                                                     suspensions: suspensions)
            }
            suspensions += 1
            try await suspend()
        }
    }
}

/// Bounded opt-in configuration shared by the native runner and hermetic tests.
public struct QualificationOptions: Sendable {
    public let mode: QualificationMode
    public let seconds: Int
    public let inputIndex: Int?
    public let outputIndex: Int?
    public let requestPermission: Bool
    public let reportPath: String

    /// Parses exact long options, rejecting unknown/duplicate flags before native work.
    /// - Parameter arguments: Arguments excluding the executable name. `--output` is mandatory;
    ///   probe is the default. Native modes require `--enable-device-io`; duplex duration is
    ///   600...3600 seconds, fault observations 1...600. Device indices address each direction's
    ///   probe order independently; omitted indices retain system routing.
    /// - Throws: `invalidArguments` for invalid/duplicate values, or `missingConsent` when native
    ///   I/O was not explicitly enabled. Permission prompts additionally need `--request-permission`.
    public init(arguments: [String]) throws {
        var values: [String: String] = [:]
        var switches: Set<String> = []
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            if ["--enable-device-io", "--request-permission"].contains(flag) {
                guard switches.insert(flag).inserted else { throw QualificationError.invalidArguments }
                index += 1
            } else {
                guard ["--mode", "--seconds", "--input-index", "--output-index", "--output"].contains(flag),
                      index + 1 < arguments.count, values[flag] == nil,
                      !arguments[index + 1].hasPrefix("--") else { throw QualificationError.invalidArguments }
                values[flag] = arguments[index + 1]
                index += 2
            }
        }
        guard let mode = QualificationMode(rawValue: values["--mode"] ?? "probe"),
              let path = values["--output"], !path.isEmpty,
              let seconds = Int(values["--seconds"] ?? (mode == .duplex ? "600" : "120")) else {
            throw QualificationError.invalidArguments
        }
        for flag in ["--input-index", "--output-index"] {
            if let value = values[flag] {
                guard let parsed = Int(value), (0..<256).contains(parsed) else {
                    throw QualificationError.invalidArguments
                }
            }
        }
        guard (mode == .duplex ? 600...3600 : 1...600).contains(seconds) else {
            throw QualificationError.invalidArguments
        }
        if mode != .probe && !switches.contains("--enable-device-io") {
            throw QualificationError.missingConsent
        }
        guard mode != .probe || (!switches.contains("--request-permission") &&
                                 !switches.contains("--enable-device-io")) else {
            throw QualificationError.invalidArguments
        }
        self.mode = mode
        self.seconds = seconds
        self.inputIndex = values["--input-index"].flatMap(Int.init)
        self.outputIndex = values["--output-index"].flatMap(Int.init)
        self.requestPermission = switches.contains("--request-permission")
        self.reportPath = path
    }

    /// Resolves a direction-local index without changing any route or retaining a catalog.
    /// - Parameters:
    ///   - endpoints: Current native metadata; the snapshot may become stale immediately.
    ///   - direction: Input or output to select.
    /// - Returns: The exact selected UID, or nil for system routing.
    /// - Throws: `unavailableDevice` when the requested index is missing or unselectable.
    public func selectedUID(in endpoints: [AppleAudioEndpoint], direction: AppleAudioDirection) throws -> String? {
        let index = direction == .input ? inputIndex : outputIndex
        guard let index else { return nil }
        let candidates = endpoints.filter { $0.direction == direction }
        guard candidates.indices.contains(index), candidates[index].isSelectable else {
            throw QualificationError.unavailableDevice
        }
        return candidates[index].uid
    }
}

/// Bounded percentile sampling; no audio samples, native IDs or diagnostic labels are stored.
public struct ProcessingHistogram: Sendable, Codable {
    private var buckets = Array(repeating: 0, count: 2_001)
    public private(set) var count = 0
    public private(set) var maximumMilliseconds: Double = 0
    public private(set) var deadlineMisses = 0

    /// Creates an empty 0.1ms histogram with an overflow bucket at 200ms.
    public init() {}

    /// Records one synchronous frame interval without growing storage.
    /// - Parameter milliseconds: Finite nonnegative elapsed wall time; invalid values are ignored.
    ///   Intervals of at least 20ms count as deadline misses for the runner's 20ms CELT frames.
    public mutating func record(milliseconds: Double) {
        guard milliseconds.isFinite, milliseconds >= 0 else { return }
        count += 1
        maximumMilliseconds = max(maximumMilliseconds, milliseconds)
        if milliseconds >= 20 { deadlineMisses += 1 }
        buckets[min(2_000, Int(min(200, milliseconds) * 10))] += 1
    }

    /// Returns a conservative upper bucket edge for the sampled p99.
    /// - Returns: Nil for no samples, otherwise a bucket upper bound in milliseconds. The overflow
    ///   bucket returns the measured maximum so slow frames are never reported as bounded by 200ms.
    public func p99Milliseconds() -> Double? {
        guard count > 0 else { return nil }
        let target = count - count / 100
        var accumulated = 0
        for (index, value) in buckets.enumerated() {
            accumulated += value
            if accumulated >= target {
                return index == 2_000 ? maximumMilliseconds : Double(index + 1) / 10
            }
        }
        return maximumMilliseconds
    }
}

/// Device-run evidence that can only pass after measured native I/O and clean bounded accounting.
public struct DuplexEvidence: Codable, Sendable {
    public var elapsedSeconds: Double = 0
    public var capturedFrames = 0
    public var capturedSampleRate = 0
    public var playedFrames = 0
    public var processedFrames = 0
    public var nonSilentCaptureFrames = 0
    public var captureDrops: UInt64 = 0
    public var playbackRejections = 0
    public var playbackBackpressureWaits = 0
    public var playbackBackpressureTimeouts = 0
    public var maximumPlaybackBackpressureMilliseconds: Double = 0
    public var unexpectedStops = 0
    public var queuesCleared = false
    public var processing = ProcessingHistogram()
    public var residentMemory = ResidentMemoryEvidence()

    /// Creates an empty measurement, which does not satisfy any native qualification gate.
    public init() {}

    /// Assesses an uninterrupted device run against a requested ten-minute-or-longer interval.
    /// - Parameter seconds: Requested duration; values below 600 cannot pass.
    /// - Returns: True only for sufficient elapsed, capture and played duration (99% allows native
    ///   start/drain boundaries), observed nonzero microphone energy, codec output, clean stop and
    ///   zero drop/rejection/admission-timeout/20ms processing misses. Bounded backpressure waits
    ///   are measured separately and do not discard microphone frames. This is local device evidence, not perceptual,
    ///   minimum-OS, mobile, interruption, hot-unplug or live Discord qualification.
    public func passed(seconds: Int) -> Bool {
        guard seconds >= 600, elapsedSeconds >= Double(seconds), capturedSampleRate > 0 else { return false }
        return Double(capturedFrames) / Double(capturedSampleRate) >= Double(seconds) * 0.99 &&
            Double(playedFrames) / 48_000 >= Double(seconds) * 0.99 &&
            Double(processedFrames) / 48_000 >= Double(seconds) * 0.99 && nonSilentCaptureFrames > 0 &&
            captureDrops == 0 && playbackRejections == 0 && playbackBackpressureTimeouts == 0 &&
            unexpectedStops == 0 && queuesCleared &&
            processing.count > 0 && processing.deadlineMisses == 0
    }
}

/// Fixed-size process RSS summary; allocations and device buffer ownership remain separately bounded.
public struct ResidentMemoryEvidence: Codable, Sendable {
    public private(set) var samples = 0
    public private(set) var initialBytes: UInt64?
    public private(set) var minimumBytes: UInt64?
    public private(set) var maximumBytes: UInt64?
    public private(set) var finalBytes: UInt64?

    /// Creates empty evidence; unavailable native RSS does not become a zero-byte measurement.
    public init() {}

    /// Records actual process resident bytes without retaining per-sample arrays.
    /// - Parameter bytes: Native RSS or nil for a failed query; nil preserves prior evidence.
    ///   RSS includes system/framework effects and is not a retained-allocation or leak proof.
    public mutating func record(bytes: UInt64?) {
        guard let bytes else { return }
        samples += 1
        if initialBytes == nil { initialBytes = bytes }
        minimumBytes = min(minimumBytes ?? bytes, bytes)
        maximumBytes = max(maximumBytes ?? bytes, bytes)
        finalBytes = bytes
    }
}
