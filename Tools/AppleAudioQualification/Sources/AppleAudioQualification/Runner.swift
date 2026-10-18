import DiscordApplePlatform
import DiscordMedia
import DiscordVoiceCodecs
import Foundation
import QualificationSupport
import Darwin
import CryptoKit

/// Redacted endpoint metadata; indices are direction-local and valid only for this snapshot.
private struct EndpointSummary: Codable {
    let index: Int
    let direction: String
    let name: String
    let isDefault: Bool
    let isSelectable: Bool
}

/// Measured native evidence; absent checks remain explicit rather than passing by default.
private struct NativeReport: Codable {
    var schemaVersion = 1
    var date = Date()
    var platform = ProcessInfo.processInfo.operatingSystemVersionString
    var mode = "probe"
    var permissionBefore = "unknown"
    var permissionAfter = "unknown"
    var endpoints: [EndpointSummary] = []
    var inputAvailable = false
    var outputAvailable = false
    var nativeIOStarted = false
    var audioPath = "No device I/O"
    var nativeRenderUnderrunTelemetryAvailable = false
    var losslessDuplexQualified = false
    var processingTimingScope = "Synchronous codec encode/decode only; excludes resampling, scheduling, device rendering and OS latency"
    var sourceSHA256: [String: String] = [:]
    var sourceDriftDuringRun: Bool?
    var binarySHA256: String?
    var selectedInput = false
    var selectedOutput = false
    var passed = false
    var observedStop: String?
    var defaultRouteChanged = false
    var selectedDeviceRemoved = false
    var duplex: DuplexEvidence?
    var failure: String?
    var exclusions = ["Windows/Android", "Apple mobile devices", "minimum-OS runtime",
                      "perceptual listening assessment", "live Discord", "network transport",
                      "automatic equivalence between route, unplug and interruption events"]
}

/// Explicit standalone native qualification; ordinary root tests never invoke this executable.
@main private enum AppleAudioQualification {
    /// Parses arguments, probes without I/O by default, and always writes bounded structured evidence.
    /// Native modes require an explicit flag and may monitor captured audio and open the microphone.
    /// Permission prompts require a second explicit flag; no PCM content is written or transmitted.
    /// A successful probe reports only host capabilities and cannot pass hardware qualification.
    @MainActor static func main() async {
        let options: QualificationOptions
        do {
            options = try QualificationOptions(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            print("Usage: AppleAudioQualification --output report.json [--mode probe|duplex|route|unplug|interruption] [--seconds N] [--input-index N] [--output-index N] [--enable-device-io] [--request-permission]")
            exit(2)
        }
        var report = NativeReport()
        report.mode = options.mode.rawValue
        report.sourceSHA256 = (try? sourceFingerprints()) ?? [:]
        report.binarySHA256 = try? digest(URL(fileURLWithPath: CommandLine.arguments[0]))
        do {
            let format = try PCMFormat(sampleRate: 48_000, channelCount: 1)
            let discovery = AppleAudioDevice(configuration: try AppleAudioConfiguration(playbackFormat: format))
            report.permissionBefore = String(describing: discovery.recordingPermission())
            report.permissionAfter = report.permissionBefore
            let endpoints = try discovery.availableDevices()
            var counts: [String: Int] = [:]
            report.endpoints = endpoints.map { endpoint in
                let direction = String(describing: endpoint.direction)
                let index = counts[direction, default: 0]
                counts[direction] = index + 1
                return EndpointSummary(index: index, direction: direction,
                    name: endpoint.name, isDefault: endpoint.isDefault, isSelectable: endpoint.isSelectable)
            }
            report.inputAvailable = endpoints.contains { $0.direction == .input }
            report.outputAvailable = endpoints.contains { $0.direction == .output }
            if options.mode != .probe {
                guard report.inputAvailable && report.outputAvailable else {
                    throw QualificationError.unavailableDevice
                }
                let input = try options.selectedUID(in: endpoints, direction: .input)
                let output = try options.selectedUID(in: endpoints, direction: .output)
                report.selectedInput = input != nil
                report.selectedOutput = output != nil
                if options.mode == .unplug && input == nil && output == nil {
                    throw QualificationError.invalidArguments
                }
                let device = AppleAudioDevice(configuration: try AppleAudioConfiguration(
                    captureBufferFrames: 480, playbackFormat: format,
                    maximumCaptureBlocks: 32, maximumPlaybackBlocks: 16,
                    captureDeviceUID: input, playbackDeviceUID: output))
                if options.requestPermission {
                    report.permissionAfter = String(describing: try await device.requestRecordingPermission())
                }
                if options.mode == .duplex {
                    report.duplex = try await duplex(device: device, seconds: options.seconds, report: &report)
                    report.passed = report.failure == nil && report.duplex?.passed(seconds: options.seconds) == true
                } else {
                    try await observe(device: device, endpoints: endpoints, input: input, output: output,
                                      options: options, report: &report)
                }
            }
        } catch {
            report.failure = String(describing: error)
        }
        if !report.sourceSHA256.isEmpty {
            report.sourceDriftDuringRun = (try? sourceFingerprints()) != report.sourceSHA256
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: URL(fileURLWithPath: options.reportPath), options: .atomic)
        } catch {
            print("Could not write qualification evidence.")
            exit(2)
        }
        print("mode=\(report.mode) inputs=\(report.endpoints.filter { $0.direction == "input" }.count) outputs=\(report.endpoints.filter { $0.direction == "output" }.count) permission=\(report.permissionAfter) nativeIO=\(report.nativeIOStarted) passed=\(report.passed)")
        if report.failure != nil || (options.mode != .probe && !report.passed) { exit(1) }
    }

    /// Fingerprints the locally built source graph and standalone harness without reading audio data.
    /// - Returns: SHA256 keyed by repository-relative Swift paths, plus the harness manifest/plist.
    ///   These are observed runtime source hashes, not compiler attestation. Keep sources unchanged
    ///   between the recorded build and run; the final comparison also detects changes during I/O.
    /// - Throws: Local enumeration/read errors. An installed executable without its source checkout
    ///   reports an empty provenance map and must not be treated as reproducible source evidence.
    private static func sourceFingerprints() throws -> [String: String] {
        var repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<4 { repository.deleteLastPathComponent() }
        let directories = ["Sources/DiscordBits", "Sources/DiscordCore", "Sources/DiscordTransport",
            "Sources/DiscordMedia", "Sources/DiscordVoiceCodecs", "Sources/DiscordApplePlatform",
            "Tools/AppleAudioQualification/Sources"]
        var result: [String: String] = [:]
        for directory in directories {
            guard let enumerator = FileManager.default.enumerator(at: repository.appendingPathComponent(directory),
                includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
                throw QualificationError.invalidArguments
            }
            for case let file as URL in enumerator where file.pathExtension == "swift" {
                guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                let relative = String(file.path.dropFirst(repository.path.count + 1))
                result[relative] = try digest(file)
            }
        }
        for relative in ["Tools/AppleAudioQualification/Package.swift", "Tools/AppleAudioQualification/Support/Info.plist"] {
            result[relative] = try digest(repository.appendingPathComponent(relative))
        }
        return result
    }

    /// Hashes one local source or executable without logging its contents.
    /// - Parameter file: Existing regular file in the explicitly selected build/source graph.
    /// - Returns: Lowercase SHA256 hexadecimal fingerprint.
    /// - Throws: Local read errors; callers preserve absence instead of inventing a digest.
    private static func digest(_ file: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
    }

    /// Runs real capture through the owned codec and native playback for at least ten minutes.
    ///
    /// Captured PCM is bandlimited-resampled, CELT-encoded, decoded, attenuated by 0.025 and
    /// scheduled for playback. Use headphones to prevent acoustic feedback. No PCM is recorded
    /// or transmitted. Completion counts measure native played-buffer callbacks; they do not
    /// independently measure acoustic latency, perceptual quality or render-device underruns.
    /// - Parameters:
    ///   - device: Fresh explicitly authorized native owner, always stopped on every return path.
    ///   - seconds: Validated 600...3600-second observation duration.
    ///   - report: Native-start and stop evidence updated before returning.
    /// - Returns: Frame counts, bounded frame timing histogram and final queue cleanup evidence.
    ///   Runtime read/codec/cancellation failures preserve partial measurements and set report.failure,
    ///   preventing a passing report; admission timeouts retain their separate failed-run counter.
    /// - Throws: Permission, cancellation, native-start or processing-configuration errors before
    ///   the measurement loop. Native cleanup still runs on every return or throw.
    @MainActor private static func duplex(device: AppleAudioDevice, seconds: Int,
                                          report: inout NativeReport) async throws -> DuplexEvidence {
        var evidence = DuplexEvidence()
        defer { device.stop() }
        guard let capture = try device.start() else { throw AppleAudioError.unavailableFormat }
        report.nativeIOStarted = true
        evidence.residentMemory.record(bytes: residentBytes())
        evidence.capturedSampleRate = capture.sampleRate
        var resampler = try PCMBandlimitedResampler(inputFormat: capture, outputSampleRate: 48_000)
        var encoder = try CELTPacketEncoder(frameSampleCount: 960)
        var decoder = try OpusAudioDecoder()
        var pending: [Float] = []
        var scheduled = 0
        let format = try PCMFormat(sampleRate: 48_000, channelCount: 1)
        report.audioPath = "Microphone -> bandlimited 48kHz mono -> owned CELT 20ms/161-byte packets (64kbps payload, 64.4kbps including TOC) -> owned Opus decoder -> gain 0.025 -> native playback"
        let began = ProcessInfo.processInfo.systemUptime
        var nextProgress = 10.0
        do {
            captureLoop: while ProcessInfo.processInfo.systemUptime - began < Double(seconds) {
                let elapsed = ProcessInfo.processInfo.systemUptime - began
                guard device.snapshot().state == .running else {
                    evidence.unexpectedStops += 1
                    report.observedStop = String(describing: device.snapshot().state)
                    break
                }
                for _ in 0..<32 {
                    guard try await playbackCapacity(device: device, evidence: &evidence) else { break captureLoop }
                    guard let captured = try await device.read() else { break }
                    evidence.capturedFrames += captured.frameCount
                    if captured.samples.contains(where: { abs($0) > 0.000_01 }) {
                        evidence.nonSilentCaptureFrames += captured.frameCount
                    }
                    for converted in try resampler.process(captured) { pending.append(contentsOf: converted.samples) }
                    while pending.count >= 960 {
                        guard try await playbackCapacity(device: device, evidence: &evidence) else { break captureLoop }
                        let samples = Array(pending.prefix(960))
                        pending.removeFirst(960)
                        let started = ProcessInfo.processInfo.systemUptime
                        let packet = try encoder.encode(samples, packetByteCount: 161)
                        let decoded = try decoder.decode(packet)
                        evidence.processing.record(milliseconds: (ProcessInfo.processInfo.systemUptime - started) * 1_000)
                        guard decoded.count == 1, decoded[0].samples.count == 960,
                              decoded[0].samples.allSatisfy(\.isFinite) else {
                            throw AppleAudioError.incompatibleFormat
                        }
                        evidence.processedFrames += 960
                        let playback = decoded[0].samples.map { max(-1, min(1, $0 * 0.025)) }
                        do {
                            try await device.write(PCMBuffer(format: format, samples: playback))
                            scheduled += 960
                        } catch AppleAudioError.queueFull {
                            evidence.playbackRejections += 1
                            break captureLoop
                        }
                    }
                }
                if elapsed >= nextProgress {
                    print("native duplex elapsed=\(Int(elapsed))s captured=\(evidence.capturedFrames) codec=\(evidence.processedFrames) drops=\(device.snapshot().droppedCaptureBlocks) rejects=\(evidence.playbackRejections) admissionWaits=\(evidence.playbackBackpressureWaits) admissionTimeouts=\(evidence.playbackBackpressureTimeouts) codecDeadlineMisses=\(evidence.processing.deadlineMisses)")
                    fflush(nil)
                    evidence.residentMemory.record(bytes: residentBytes())
                    nextProgress += 10
                }
                try await Task.sleep(for: .milliseconds(2))
            }
        } catch {
            // Retain all partial counters on cancellation/read/codec failure; no failed run can pass.
            report.failure = String(describing: error)
        }
        evidence.elapsedSeconds = ProcessInfo.processInfo.systemUptime - began
        let drainBegan = ProcessInfo.processInfo.systemUptime
        if report.failure == nil {
            do {
                while device.snapshot().state == .running && device.snapshot().playbackBlocks > 0 &&
                        ProcessInfo.processInfo.systemUptime - drainBegan < 2 {
                    try await Task.sleep(for: .milliseconds(2))
                }
            } catch { report.failure = String(describing: error) }
        }
        let snapshot = device.snapshot()
        if snapshot.state == .running {
            evidence.playedFrames = max(0, scheduled - snapshot.playbackBlocks * 960)
        } else {
            // Native stop revokes reservations without proving their completion; do not count
            // cleared queued buffers as played, including a stop during the final drain.
            evidence.unexpectedStops = max(1, evidence.unexpectedStops)
            report.observedStop = String(describing: snapshot.state)
            evidence.playedFrames = 0
        }
        evidence.captureDrops = snapshot.droppedCaptureBlocks
        device.stop()
        let stopped = device.snapshot()
        evidence.queuesCleared = stopped.captureBytes == 0 && stopped.playbackBytes == 0 &&
            stopped.captureBlocks == 0 && stopped.playbackBlocks == 0
        evidence.residentMemory.record(bytes: residentBytes())
        return evidence
    }

    /// Applies bounded backpressure before consuming/encoding one 960-sample mono frame.
    /// - Parameters:
    ///   - device: Running caller-owned native sink; capacity reads neither reserve nor play audio.
    ///   - evidence: Fixed-size wait/timeout counters; encode/decode timing excludes these waits.
    /// - Returns: True when block and byte budgets permit the next frame; false on stop or a
    ///   250ms timeout. The caller ends a failed run instead of discarding the pending frame.
    /// - Throws: Cancellation or admission-clock/suspension failure; partial evidence is retained.
    @MainActor private static func playbackCapacity(device: AppleAudioDevice,
                                                    evidence: inout DuplexEvidence) async throws -> Bool {
        let observation = try await PlaybackAdmission.wait(isRunning: { device.snapshot().state == .running },
            hasCapacity: {
                let snapshot = device.snapshot()
                return snapshot.playbackBlocks < device.configuration.maximumPlaybackBlocks &&
                    960 * MemoryLayout<Float>.size <= device.configuration.maximumPlaybackBytes - snapshot.playbackBytes
            }, milliseconds: { ProcessInfo.processInfo.systemUptime * 1_000 },
            suspend: { try await Task.sleep(for: .milliseconds(2)) })
        if observation.suspensions > 0 {
            evidence.playbackBackpressureWaits += 1
            evidence.maximumPlaybackBackpressureMilliseconds = max(evidence.maximumPlaybackBackpressureMilliseconds,
                                                                   observation.waitMilliseconds)
        }
        if observation.outcome == .timedOut { evidence.playbackBackpressureTimeouts += 1 }
        return observation.outcome == .ready
    }

    /// Reads actual process resident memory through the bounded Mach task-info structure.
    /// - Returns: Resident bytes, or nil when the OS denies/fails the query. No allocation count,
    ///   audio content or device identifier is inferred; the caller stores only fixed-size extrema.
    private static func residentBytes() -> UInt64? {
        var information = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(information.resident_size) : nil
    }

    /// Observes a real externally triggered route, selected-device unplug or interruption event.
    ///
    /// This method never posts a synthetic notification, changes the host's default route or
    /// manufactures a passing operator action. macOS has no AVAudioSession interruption API;
    /// interruption remains unqualified unless the backend actually reports that reason.
    /// - Parameters:
    ///   - device: Fresh native duplex owner, stopped on return or error.
    ///   - endpoints: Pre-start native endpoint snapshot for default/removal comparisons.
    ///   - input: Exact selected input UID or nil for system routing.
    ///   - output: Exact selected output UID or nil for system routing.
    ///   - options: Fault mode and finite timeout; unplug requires at least one selected UID.
    ///   - report: Records observed native reason, route/removal comparisons and cleanup assessment.
    /// - Throws: Permission/start/query failures or cancellation. No automatic restart is attempted.
    @MainActor private static func observe(device: AppleAudioDevice, endpoints: [AppleAudioEndpoint],
                                           input: String?, output: String?, options: QualificationOptions,
                                           report: inout NativeReport) async throws {
        defer { device.stop() }
        try device.start()
        report.nativeIOStarted = true
        report.audioPath = "Native microphone capture -> discard; playback graph active without scheduled audible playback"
        let began = ProcessInfo.processInfo.systemUptime
        print("native observation started; perform the externally requested \(options.mode.rawValue) action now")
        fflush(nil)
        while device.snapshot().state == .running &&
                ProcessInfo.processInfo.systemUptime - began < Double(options.seconds) {
            for _ in 0..<32 { if try await device.read() == nil { break } }
            try await Task.sleep(for: .milliseconds(10))
        }
        let stopped = device.snapshot()
        report.observedStop = String(describing: stopped.state)
        var current: [AppleAudioEndpoint]?
        for _ in 0..<100 {
            // Teardown may remove the engine's implicit private aggregate while CoreAudio enumerates.
            // Retry only copied metadata, never start or silently choose another physical route.
            if let stable = try? device.availableDevices() { current = stable; break }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard let current else { throw AppleAudioError.nativeFailure }
        let previousDefaults = Set(endpoints.filter(\.isDefault).map { "\($0.direction):\($0.uid)" })
        let currentDefaults = Set(current.filter(\.isDefault).map { "\($0.direction):\($0.uid)" })
        report.defaultRouteChanged = previousDefaults != currentDefaults
        report.selectedDeviceRemoved = [input, output].compactMap { $0 }.contains { uid in
            !current.contains { $0.uid == uid }
        }
        let cleared = stopped.captureBlocks == 0 && stopped.playbackBlocks == 0 &&
            stopped.captureBytes == 0 && stopped.playbackBytes == 0
        switch options.mode {
        case .route:
            report.passed = (stopped.state == .stopped(.routeChanged) ||
                stopped.state == .stopped(.configurationChanged)) && report.defaultRouteChanged && cleared
        case .unplug:
            report.passed = (stopped.state == .stopped(.routeChanged) ||
                stopped.state == .stopped(.configurationChanged)) && report.selectedDeviceRemoved && cleared
        case .interruption:
            report.passed = stopped.state == .stopped(.interruption) && cleared
        default: report.passed = false
        }
    }
}
