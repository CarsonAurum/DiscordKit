import DiscordApplePlatform
import QualificationSupport
import Testing

/// Hermetic qualification policy tests; no native backend, permission prompt or device I/O.
@Suite struct QualificationTests {
    /// Immediate capacity causes no suspension; native stop wins without querying capacity.
    @Test @MainActor func immediatePlaybackAdmissionAndStopPriority() async throws {
        var capacityReads = 0
        let ready = try await PlaybackAdmission.wait(maximumWaitMilliseconds: 0,
            isRunning: { true }, hasCapacity: { capacityReads += 1; return true },
            milliseconds: { 10 }, suspend: { Issue.record("Immediate admission must not suspend") })
        #expect(ready.outcome == .ready && ready.suspensions == 0 && ready.waitMilliseconds == 0)
        #expect(capacityReads == 1)
        let stopped = try await PlaybackAdmission.wait(isRunning: { false },
            hasCapacity: { capacityReads += 1; return true }, milliseconds: { 10 },
            suspend: { Issue.record("A stopped owner must not suspend") })
        #expect(stopped.outcome == .stopped && stopped.suspensions == 0 && capacityReads == 1)
    }

    /// Full capacity waits cooperatively; exact-boundary readiness wins and late readiness times out.
    @Test @MainActor func boundedPlaybackAdmissionWaitsAndTimeouts() async throws {
        var now = 0.0
        let ready = try await PlaybackAdmission.wait(maximumWaitMilliseconds: 6,
            isRunning: { true }, hasCapacity: { now >= 6 }, milliseconds: { now },
            suspend: { now += 2 })
        #expect(ready.outcome == .ready && ready.suspensions == 3 && ready.waitMilliseconds == 6)
        now = 0
        let timeout = try await PlaybackAdmission.wait(maximumWaitMilliseconds: 6,
            isRunning: { true }, hasCapacity: { false }, milliseconds: { now }, suspend: { now += 2 })
        #expect(timeout.outcome == .timedOut && timeout.suspensions == 3 && timeout.waitMilliseconds == 6)
        now = 0
        let late = try await PlaybackAdmission.wait(maximumWaitMilliseconds: 5,
            isRunning: { true }, hasCapacity: { now >= 6 }, milliseconds: { now }, suspend: { now += 2 })
        #expect(late.outcome == .timedOut && late.waitMilliseconds == 6)
        now = 0
        let stopped = try await PlaybackAdmission.wait(isRunning: { now < 2 },
            hasCapacity: { false }, milliseconds: { now }, suspend: { now += 2 })
        #expect(stopped.outcome == .stopped && stopped.suspensions == 1 && stopped.waitMilliseconds == 2)
    }

    /// Invalid bounds and nonfinite/backwards clocks fail instead of creating an unbounded wait.
    @Test @MainActor func invalidPlaybackAdmissionMeasurements() async {
        for bound in [Double.nan, .infinity, -.infinity, -1] {
            await #expect(throws: QualificationError.invalidArguments) {
                try await PlaybackAdmission.wait(maximumWaitMilliseconds: bound, isRunning: { true },
                    hasCapacity: { true }, milliseconds: { 0 }, suspend: {})
            }
        }
        for initial in [Double.nan, .infinity, -.infinity] {
            await #expect(throws: QualificationError.invalidArguments) {
                try await PlaybackAdmission.wait(isRunning: { true }, hasCapacity: { true },
                    milliseconds: { initial }, suspend: {})
            }
        }
        for invalid in [Double.nan, .infinity, -.infinity, -1] {
            var now = 0.0
            await #expect(throws: QualificationError.invalidArguments) {
                try await PlaybackAdmission.wait(isRunning: { true }, hasCapacity: { false },
                    milliseconds: { now }, suspend: { now = invalid })
            }
        }
    }

    /// Cancellation before admission and while suspended propagates without consuming capacity.
    @Test @MainActor func playbackAdmissionCancellationAndSuspensionFailure() async {
        let cancelled = Task { @MainActor in
            try await PlaybackAdmission.wait(isRunning: { true }, hasCapacity: { true },
                milliseconds: { 0 }, suspend: { Issue.record("Pre-cancelled admission must not suspend") })
        }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        let during = Task { @MainActor in
            try await PlaybackAdmission.wait(isRunning: { true }, hasCapacity: { false },
                milliseconds: { 0 }, suspend: { withUnsafeCurrentTask { $0?.cancel() } })
        }
        await #expect(throws: CancellationError.self) { try await during.value }
        await #expect(throws: CancellationError.self) {
            try await PlaybackAdmission.wait(isRunning: { true }, hasCapacity: { false },
                milliseconds: { 0 }, suspend: { throw CancellationError() })
        }
        await #expect(throws: QualificationError.unavailableDevice) {
            try await PlaybackAdmission.wait(isRunning: { true }, hasCapacity: { false },
                milliseconds: { 0 }, suspend: { throw QualificationError.unavailableDevice })
        }
    }

    /// RSS evidence preserves actual byte extrema and treats missing native measurements as absent.
    @Test func residentMemorySummary() {
        var memory = ResidentMemoryEvidence()
        memory.record(bytes: nil)
        #expect(memory.samples == 0 && memory.initialBytes == nil && memory.finalBytes == nil)
        for bytes: UInt64 in [100, 80, 140, 90] { memory.record(bytes: bytes) }
        memory.record(bytes: nil)
        #expect(memory.samples == 4 && memory.initialBytes == 100 && memory.finalBytes == 90)
        #expect(memory.minimumBytes == 80 && memory.maximumBytes == 140)
    }
    /// Default probe cannot request permission or accidentally enable native I/O through flags.
    @Test func safeProbeAndExplicitNativeConsent() throws {
        let probe = try QualificationOptions(arguments: ["--output", "report.json"])
        #expect(probe.mode == .probe && !probe.requestPermission)
        #expect(probe.seconds == 120 && probe.inputIndex == nil && probe.outputIndex == nil)
        #expect(probe.reportPath == "report.json")
        for arguments in [
            ["--output", "x", "--request-permission"],
            ["--output", "x", "--enable-device-io"],
        ] {
            #expect(throws: QualificationError.invalidArguments) { try QualificationOptions(arguments: arguments) }
        }
        #expect(throws: QualificationError.missingConsent) {
            try QualificationOptions(arguments: ["--mode", "duplex", "--output", "x"])
        }
        let duplex = try QualificationOptions(arguments: ["--mode", "duplex", "--output", "x",
            "--enable-device-io", "--request-permission"])
        #expect(duplex.seconds == 600 && duplex.requestPermission)
    }

    /// Unknown, duplicate, missing, oversized and malformed arguments fail before native enumeration.
    /// - Parameter arguments: Invalid complete argument list; each case must fail before native access.
    @Test(arguments: [
        [String](), ["--output"], ["--output", ""], ["--output", "x", "--unknown", "x"],
        ["--output", "x", "--output", "y"], ["--output", "x", "--mode", "fake"],
        ["--output", "x", "--seconds", "0"], ["--output", "x", "--seconds", "601"],
        ["--output", "x", "--input-index", "-1"], ["--output", "x", "--output-index", "256"],
        ["--output", "x", "--input-index", "one"], ["--output", "x", "--seconds", "nan"],
        ["--output", "--mode", "probe"],
        ["--output", "x", "--enable-device-io", "--enable-device-io"],
        ["--output", "x", "--request-permission", "--request-permission"],
        ["--output", "x", "--mode", "duplex", "--seconds", "599", "--enable-device-io"],
        ["--output", "x", "--mode", "duplex", "--seconds", "3601", "--enable-device-io"],
    ])
    func malformedArguments(_ arguments: [String]) {
        #expect(throws: QualificationError.invalidArguments) { try QualificationOptions(arguments: arguments) }
    }

    /// Native fault modes retain independent timeouts and direction-specific explicit selection.
    /// - Parameter mode: Each externally observed route/unplug/interruption mode under test.
    @Test(arguments: ["route", "unplug", "interruption"])
    func faultModesAndExactDeviceSelection(_ mode: String) throws {
        let options = try QualificationOptions(arguments: ["--mode", mode, "--output", "x",
            "--seconds", "1", "--input-index", "1", "--output-index", "0", "--enable-device-io"])
        #expect(options.seconds == 1 && options.mode.rawValue == mode)
        let endpoints = try [
            AppleAudioEndpoint(uid: "out", name: "output", direction: .output, isDefault: true, isSelectable: true),
            AppleAudioEndpoint(uid: "in0", name: "first", direction: .input, isDefault: true, isSelectable: true),
            AppleAudioEndpoint(uid: "in1", name: "second", direction: .input, isDefault: false, isSelectable: true),
        ]
        #expect(try options.selectedUID(in: endpoints, direction: .input) == "in1")
        #expect(try options.selectedUID(in: endpoints, direction: .output) == "out")
        #expect(throws: QualificationError.unavailableDevice) {
            try options.selectedUID(in: [], direction: .output)
        }
        let unavailable = try AppleAudioEndpoint(uid: "out", name: "unselectable", direction: .output,
                                                 isDefault: true, isSelectable: false)
        #expect(throws: QualificationError.unavailableDevice) {
            try options.selectedUID(in: [unavailable], direction: .output)
        }
        let defaults = try QualificationOptions(arguments: ["--output", "x"])
        #expect(try defaults.selectedUID(in: [], direction: .input) == nil)
    }

    /// The bounded histogram ignores nonfinite/negative samples and conservatively reports tails.
    @Test func timingHistogramBoundsAndP99() {
        var histogram = ProcessingHistogram()
        #expect(histogram.p99Milliseconds() == nil)
        for invalid in [Double.nan, .infinity, -.infinity, -1] { histogram.record(milliseconds: invalid) }
        #expect(histogram.count == 0)
        for _ in 0..<99 { histogram.record(milliseconds: 1) }
        histogram.record(milliseconds: 500)
        #expect(histogram.count == 100 && histogram.deadlineMisses == 1)
        #expect(histogram.maximumMilliseconds == 500)
        #expect(histogram.p99Milliseconds() == 1.1)
        var overflow = ProcessingHistogram()
        overflow.record(milliseconds: 20)
        overflow.record(milliseconds: 5_000)
        #expect(overflow.p99Milliseconds() == 5_000 && overflow.deadlineMisses == 2)
    }

    /// Ten-minute passing evidence requires actual duration, processed microphone energy and cleanup.
    @Test func duplexGateCannotPassEmptyOrShortMeasurements() {
        #expect(!DuplexEvidence().passed(seconds: 600))
        var evidence = DuplexEvidence()
        evidence.elapsedSeconds = 600
        evidence.capturedSampleRate = 48_000
        evidence.capturedFrames = 600 * 48_000
        evidence.playedFrames = 600 * 48_000
        evidence.processedFrames = 600 * 48_000
        evidence.nonSilentCaptureFrames = 960
        evidence.queuesCleared = true
        evidence.processing.record(milliseconds: 2)
        #expect(evidence.passed(seconds: 600))
        #expect(!evidence.passed(seconds: 599) && !evidence.passed(seconds: 601))
        var changed = evidence
        changed.captureDrops = 1
        #expect(!changed.passed(seconds: 600))
        changed = evidence; changed.playbackRejections = 1
        #expect(!changed.passed(seconds: 600))
        changed = evidence; changed.playbackBackpressureTimeouts = 1
        #expect(!changed.passed(seconds: 600))
        changed = evidence; changed.playbackBackpressureWaits = 1
        changed.maximumPlaybackBackpressureMilliseconds = 20
        #expect(changed.passed(seconds: 600))
        changed = evidence; changed.unexpectedStops = 1
        #expect(!changed.passed(seconds: 600))
        changed = evidence; changed.queuesCleared = false
        #expect(!changed.passed(seconds: 600))
        changed = evidence; changed.nonSilentCaptureFrames = 0
        #expect(!changed.passed(seconds: 600))
        changed = evidence; changed.capturedFrames = 0
        #expect(!changed.passed(seconds: 600))
        changed = evidence; changed.playedFrames = 0
        #expect(!changed.passed(seconds: 600))
        changed = evidence; changed.processedFrames = 0
        #expect(!changed.passed(seconds: 600))
        changed = evidence; changed.capturedSampleRate = 0
        #expect(!changed.passed(seconds: 600))
        changed = evidence; changed.elapsedSeconds = 599.99
        #expect(!changed.passed(seconds: 600))
        changed = evidence; changed.processing = ProcessingHistogram()
        #expect(!changed.passed(seconds: 600))
        changed = evidence; changed.processing.record(milliseconds: 20)
        #expect(!changed.passed(seconds: 600))
    }
}
