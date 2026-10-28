// File: Tests/DiscordApplePlatformTests/AppleAudioDevicesTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

#if canImport(AVFoundation) && canImport(os)
@testable import DiscordApplePlatform
import DiscordMedia
import Testing
#if os(macOS)
import CoreAudio
#endif

/// Native endpoint/routing tests use only copied synthetic metadata and inert injected backends.
@MainActor @Suite("Apple explicit audio routing")
struct AppleAudioDevicesTests {
    /// Exact UID strings are preserved; empty, NUL, byte-excessive and disabled-direction IDs fail.
    @Test func configurationUIDValidation() throws {
        let format = try PCMFormat(sampleRate: 48_000, channelCount: 1)
        for uid in ["", "input\0hidden", String(repeating: "é", count: 513)] {
            #expect(throws: AppleAudioError.invalidConfiguration) {
                try AppleAudioConfiguration(playbackFormat: format, captureDeviceUID: uid)
            }
            #expect(throws: AppleAudioError.invalidConfiguration) {
                try AppleAudioConfiguration(playbackFormat: format, playbackDeviceUID: uid)
            }
        }
        #expect(throws: AppleAudioError.invalidConfiguration) {
            try AppleAudioConfiguration(captureEnabled: false, playbackFormat: format, captureDeviceUID: "input")
        }
        #expect(throws: AppleAudioError.invalidConfiguration) {
            try AppleAudioConfiguration(playbackEnabled: false, playbackFormat: format, playbackDeviceUID: "output")
        }
        let uid = String(repeating: "é", count: 512)
        let configured = try AppleAudioConfiguration(playbackFormat: format, captureDeviceUID: uid, playbackDeviceUID: " output ")
        #expect(configured.captureDeviceUID == uid)
        #expect(configured.playbackDeviceUID == " output ")
        #expect(AppleAudioRouting.validUID(uid))
        #expect(try AppleAudioConfiguration(playbackFormat: format).captureDeviceUID == nil)
    }

    /// Endpoint metadata owns bounded Unicode strings and never treats output visibility as selection.
    @Test func endpointValidationAndResolution() throws {
        let input = try AppleAudioEndpoint(uid: "same", name: "Microphone", direction: .input,
                                          isDefault: false, isSelectable: true)
        let output = try AppleAudioEndpoint(uid: "same", name: "Speaker", direction: .output,
                                           isDefault: true, isSelectable: false)
        #expect(input.uid == "same" && input.name == "Microphone")
        #expect(input.direction == .input && !input.isDefault && input.isSelectable)
        #expect(output.direction == .output && output.isDefault && !output.isSelectable)
        #expect(try AppleAudioRouting.resolve(uid: "same", direction: .input, endpoints: [input, output]) == input)
        #expect(try AppleAudioRouting.resolve(uid: nil, direction: .input, endpoints: []) == nil)
        #expect(throws: AppleAudioError.unsupportedDeviceSelection) {
            try AppleAudioRouting.resolve(uid: "same", direction: .output, endpoints: [input, output])
        }
        #expect(throws: AppleAudioError.deviceUnavailable) {
            try AppleAudioRouting.resolve(uid: "missing", direction: .input, endpoints: [input])
        }
        #expect(throws: AppleAudioError.deviceUnavailable) {
            try AppleAudioRouting.resolve(uid: "same", direction: .output, endpoints: [input])
        }
        #expect(throws: AppleAudioError.invalidConfiguration) {
            try AppleAudioRouting.resolve(uid: "", direction: .input, endpoints: [input])
        }
        #expect(throws: AppleAudioError.nativeFailure) {
            try AppleAudioRouting.resolve(uid: "same", direction: .input, endpoints: [input, input])
        }
        #expect(throws: AppleAudioError.nativeFailure) {
            try AppleAudioRouting.resolve(uid: "same", direction: .input, endpoints: Array(repeating: input, count: 513))
        }
        for (uid, name) in [("", "name"), ("a\0b", "name"), ("a", "name\0hidden"),
                            ("a", String(repeating: "x", count: 1_025))] {
            #expect(throws: AppleAudioError.invalidConfiguration) {
                try AppleAudioEndpoint(uid: uid, name: name, direction: .input, isDefault: false, isSelectable: true)
            }
        }
        #expect(try AppleAudioEndpoint(uid: "a", name: String(repeating: "x", count: 1_024),
            direction: .input, isDefault: false, isSelectable: true).name.utf8.count == 1_024)
        #expect(try AppleAudioEndpoint(uid: "a", name: "", direction: .input,
                                       isDefault: true, isSelectable: true).name.isEmpty)
    }

    /// Explicit discovery and selected UIDs reach an injected backend without implicit construction work.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func explicitDiscoveryAndStartPolicy() throws {
        let format = try PCMFormat(sampleRate: 48_000, channelCount: 1)
        let endpoint = try AppleAudioEndpoint(uid: "input", name: "Mic", direction: .input,
                                             isDefault: false, isSelectable: true)
        let backend = RoutingTestBackend()
        backend.endpoints = [endpoint]
        let configuration = try AppleAudioConfiguration(playbackFormat: format, captureDeviceUID: "input", playbackDeviceUID: "output")
        let device = AppleAudioDevice(configuration: configuration, backend: backend)
        #expect(backend.discoveryCalls == 0 && backend.startCalls == 0)
        #expect(try device.availableDevices() == [endpoint])
        #expect(backend.discoveryCalls == 1 && backend.startCalls == 0)
        backend.format = format
        #expect(try device.start() == format)
        #expect(backend.configuration == configuration)
        device.stop()
        #expect(backend.stops == 1)
        #expect(try device.availableDevices() == [endpoint])
    }

    /// Route selection errors preserve structured reasons and clean up a partial start without fallback.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [AppleAudioError.deviceUnavailable, .unsupportedDeviceSelection])
    func failedExplicitRouteCleansUp(_ failure: AppleAudioError) throws {
        let backend = RoutingTestBackend()
        let format = try PCMFormat(sampleRate: 48_000, channelCount: 1)
        let device = AppleAudioDevice(configuration: try AppleAudioConfiguration(playbackFormat: format,
            captureDeviceUID: "selected"), backend: backend)
        backend.failure = failure
        #expect(throws: failure) { try device.start() }
        #expect(backend.stops == 1 && backend.startCalls == 1)
        #expect(device.snapshot().state == .stopped(.failed))
        #expect(device.snapshot().captureBlocks == 0 && device.snapshot().playbackBytes == 0)
        backend.failure = nil
        backend.format = format
        #expect(try device.start() == format)
        #expect(backend.configuration?.captureDeviceUID == "selected")
        device.stop()
    }

    /// Discovery errors are redacted, excessive injected snapshots fail, and cancellation precedes query.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func discoveryFailureAndCancellation() async throws {
        let backend = RoutingTestBackend()
        let format = try PCMFormat(sampleRate: 48_000, channelCount: 1)
        let device = AppleAudioDevice(configuration: try AppleAudioConfiguration(playbackFormat: format), backend: backend)
        backend.failure = RoutingTestError.native
        #expect(throws: AppleAudioError.nativeFailure) { try device.availableDevices() }
        backend.failure = AppleAudioError.unsupportedDeviceSelection
        #expect(throws: AppleAudioError.unsupportedDeviceSelection) { try device.availableDevices() }
        backend.failure = nil
        let endpoint = try AppleAudioEndpoint(uid: "input", name: "", direction: .input,
                                             isDefault: false, isSelectable: true)
        backend.endpoints = Array(repeating: endpoint, count: 513)
        #expect(throws: AppleAudioError.nativeFailure) { try device.availableDevices() }
        backend.endpoints = []
        #expect(try device.availableDevices().isEmpty)
        let count = backend.discoveryCalls
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) { try device.availableDevices() }
        }
        await task.value
        #expect(backend.discoveryCalls == count)
        #expect(device.snapshot().state == .idle)
    }

    #if os(macOS)
    /// Verifies only explicitly selected directions and detects a second selection changing the first.
    /// A default-routed direction is never queried, and paired reads occur input before output.
    @Test func pairedDeviceReadbackAndSelectionCoupling() throws {
        let properties = RoutingTestBoundDevices()
        try AppleAudioHardwareBinding.verify(input: nil, output: nil, using: properties)
        #expect(properties.reads.isEmpty)
        properties.input = 11
        properties.output = 12
        try AppleAudioHardwareBinding.verify(input: 11, output: nil, using: properties)
        #expect(properties.reads == [.input])
        properties.reads = []
        try AppleAudioHardwareBinding.verify(input: nil, output: 12, using: properties)
        #expect(properties.reads == [.output])
        properties.reads = []
        try AppleAudioHardwareBinding.verify(input: 11, output: 12, using: properties)
        #expect(properties.reads == [.input, .output])
        properties.input = 12 // A coupled second output selection rebound the input unit.
        properties.reads = []
        #expect(throws: AppleAudioError.deviceUnavailable) {
            try AppleAudioHardwareBinding.verify(input: 11, output: 12, using: properties)
        }
        #expect(properties.reads == [.input])
        #expect(properties.input == 12 && properties.output == 12)
    }

    /// A successful pre-start readback cannot authorize bindings silently changed by engine startup.
    /// Unknown/mismatched IDs and a native getter failure fail closed without rewriting either route.
    @Test func pairedDeviceReadbackRejectsStartupRebindingAndErrors() throws {
        let properties = RoutingTestBoundDevices()
        properties.input = 11
        properties.output = 12
        try AppleAudioHardwareBinding.verify(input: 11, output: 12, using: properties)
        properties.output = 99 // Simulates engine.start replacing an explicit output with a default.
        #expect(throws: AppleAudioError.deviceUnavailable) {
            try AppleAudioHardwareBinding.verify(input: 11, output: 12, using: properties)
        }
        properties.output = 0
        #expect(throws: AppleAudioError.deviceUnavailable) {
            try AppleAudioHardwareBinding.verify(input: nil, output: 12, using: properties)
        }
        properties.reads = []
        #expect(throws: AppleAudioError.deviceUnavailable) {
            try AppleAudioHardwareBinding.verify(input: 0, output: nil, using: properties)
        }
        #expect(properties.reads.isEmpty)
        properties.output = 12
        properties.failureDirection = .output
        #expect(throws: AppleAudioError.nativeFailure) {
            try AppleAudioHardwareBinding.verify(input: 11, output: 12, using: properties)
        }
        #expect(properties.input == 11 && properties.output == 12)
        properties.failureDirection = nil
        try AppleAudioHardwareBinding.verify(input: 11, output: 12, using: properties)
    }

    /// Duplex/input-only/output-only/zero-stream devices preserve ordered UIDs and directional defaults.
    @Test func coreAudioCatalogDirectionsAndDefaults() throws {
        let properties = RoutingTestProperties()
        properties.ids = [11, 12, 13, 14]
        properties.input = [11, 12]
        properties.output = [11, 13]
        properties.defaultInput = 12
        properties.defaultOutput = 13
        let entries = try AppleAudioHardwareCatalog.endpoints(using: properties)
        #expect(entries.map(\.uid) == ["uid-11", "uid-11", "uid-12", "uid-13"])
        #expect(entries.map(\.name) == ["name-11", "name-11", "name-12", "name-13"])
        #expect(entries.map(\.direction) == [.input, .output, .input, .output])
        #expect(entries.map(\.isDefault) == [false, false, true, true])
        #expect(entries.allSatisfy { $0.isSelectable })
        #expect(try AppleAudioHardwareCatalog.deviceID(uid: "uid-12", direction: .input, using: properties) == 12)
        #expect(try AppleAudioHardwareCatalog.deviceID(uid: "uid-13", direction: .output, using: properties) == 13)
        #expect(try AppleAudioHardwareCatalog.deviceID(uid: "uid-11", direction: .input, using: properties) == 11)
        properties.ids = []
        #expect(try AppleAudioHardwareCatalog.endpoints(using: properties).isEmpty)
    }

    /// Missing IDs/directions and malformed or ambiguous snapshots fail without a fallback default.
    @Test func coreAudioCatalogRejection() throws {
        let properties = RoutingTestProperties()
        properties.ids = [11]
        properties.input = [11]
        #expect(throws: AppleAudioError.deviceUnavailable) {
            try AppleAudioHardwareCatalog.deviceID(uid: "uid-11", direction: .output, using: properties)
        }
        #expect(throws: AppleAudioError.deviceUnavailable) {
            try AppleAudioHardwareCatalog.deviceID(uid: "gone", direction: .input, using: properties)
        }
        #expect(throws: AppleAudioError.invalidConfiguration) {
            try AppleAudioHardwareCatalog.deviceID(uid: "", direction: .input, using: properties)
        }
        for ids: [AudioDeviceID] in [[0], [11, 11], Array(1...257)] {
            properties.ids = ids
            #expect(throws: AppleAudioError.nativeFailure) { try AppleAudioHardwareCatalog.endpoints(using: properties) }
            #expect(throws: AppleAudioError.nativeFailure) {
                try AppleAudioHardwareCatalog.deviceID(uid: "uid-11", direction: .input, using: properties)
            }
        }
        properties.ids = [11, 12]
        properties.constantUID = "duplicate"
        #expect(throws: AppleAudioError.nativeFailure) { try AppleAudioHardwareCatalog.endpoints(using: properties) }
        #expect(throws: AppleAudioError.nativeFailure) {
            try AppleAudioHardwareCatalog.deviceID(uid: "duplicate", direction: .input, using: properties)
        }
        properties.constantUID = nil
        properties.fail = true
        #expect(throws: RoutingTestError.native) { try AppleAudioHardwareCatalog.endpoints(using: properties) }
        #expect(throws: RoutingTestError.native) {
            try AppleAudioHardwareCatalog.deviceID(uid: "uid-11", direction: .input, using: properties)
        }
    }

    /// Native-shaped metadata/default/stream read failures abort the whole snapshot or lookup.
    @Test func coreAudioCatalogPropertyFailuresAndInvalidMetadata() throws {
        let properties = RoutingTestProperties()
        properties.ids = [11]
        properties.input = [11]
        for operation in ["default", "string", "streams"] {
            properties.failOperation = operation
            #expect(throws: RoutingTestError.native) { try AppleAudioHardwareCatalog.endpoints(using: properties) }
            if operation != "default" {
                #expect(throws: RoutingTestError.native) {
                    try AppleAudioHardwareCatalog.deviceID(uid: "uid-11", direction: .input, using: properties)
                }
            }
        }
        properties.failOperation = nil
        for uid in ["", "a\0b", String(repeating: "x", count: 1_025)] {
            properties.constantUID = uid
            #expect(throws: AppleAudioError.nativeFailure) { try AppleAudioHardwareCatalog.endpoints(using: properties) }
        }
        properties.constantUID = nil
        for name in ["a\0b", String(repeating: "x", count: 1_025)] {
            properties.constantName = name
            #expect(throws: AppleAudioError.nativeFailure) { try AppleAudioHardwareCatalog.endpoints(using: properties) }
        }
    }

    /// The maximum supported native list produces exactly 512 bounded directional metadata entries.
    @Test func coreAudioCatalogMaximum() throws {
        let properties = RoutingTestProperties()
        properties.ids = Array(1...256)
        properties.input = Set(properties.ids)
        properties.output = Set(properties.ids)
        #expect(try AppleAudioHardwareCatalog.endpoints(using: properties).count == 512)
    }
    #endif
}

/// Deterministic failures intentionally carry no native text or hardware identifiers.
private enum RoutingTestError: Error { case native }

/// Isolated test boundary records only explicit operations and never invokes native audio APIs.
@MainActor private final class RoutingTestBackend: AppleAudioBackend {
    var discoveryCalls = 0
    var startCalls = 0
    var stops = 0
    var endpoints: [AppleAudioEndpoint] = []
    var failure: (any Error)?
    var configuration: AppleAudioConfiguration?
    var format: PCMFormat?

    /// Creates zero-operation synthetic state without opening native devices.
    init() {}

    /// Records an explicit metadata query and returns the test-controlled endpoint list.
    /// - Returns: Synthetic entries, including intentionally excessive arrays for owner-bound tests.
    /// - Throws: The configured synthetic/native-shaped error when failure is set.
    func availableDevices() throws -> [AppleAudioEndpoint] {
        discoveryCalls += 1
        if let failure { throw failure }
        return endpoints
    }

    /// Supplies permission without prompting, so routing tests can inspect owner policy delivery.
    /// - Returns: Always granted for this inert backend.
    func recordingPermission() -> AppleAudioPermission { .granted }

    /// Supplies an immediate permission response without a dialog or native task.
    /// - Returns: Always granted.
    func requestRecordingPermission() async -> AppleAudioPermission { .granted }

    /// Records configuration UIDs exactly as delivered to the native boundary.
    /// - Parameters:
    ///   - configuration: Explicit route/format/capacity policy to record.
    ///   - callbacks: Unused generation-fenced callbacks; no synthetic capture is needed here.
    /// - Returns: Test-controlled capture format.
    /// - Throws: The configured route-selection error, simulating rejection before native graph startup.
    func start(configuration: AppleAudioConfiguration, callbacks: AppleAudioCallbacks) throws -> PCMFormat? {
        startCalls += 1
        self.configuration = configuration
        if let failure { throw failure }
        return format
    }

    /// Immediately releases a synthetic scheduled block without retaining PCM or native work.
    /// - Parameters:
    ///   - buffer: Unused portable PCM supplied by the owner.
    ///   - completion: Called synchronously exactly once.
    func enqueuePlayback(_ buffer: PCMBuffer, completion: @escaping @Sendable () -> Void) throws { completion() }

    /// Records cleanup for each explicit owner stop and deinitialization.
    func stop() { stops += 1 }
}

#if os(macOS)
/// Mutable synthetic I/O bindings model paired selection coupling and native startup rebinding.
@MainActor private final class RoutingTestBoundDevices: AppleAudioBoundDeviceProperties {
    var input: AudioDeviceID = 0
    var output: AudioDeviceID = 0
    var reads: [AppleAudioDirection] = []
    var failureDirection: AppleAudioDirection?

    /// Creates unknown bindings without constructing an AVAudioEngine or opening native hardware.
    init() {}

    /// Records exact query ordering and returns a test-controlled actual binding.
    /// - Parameter direction: Input or output current-device property to inspect.
    /// - Returns: Test-controlled device ID, including unknown for fail-closed verification tests.
    /// - Throws: `nativeFailure` when the selected direction's native property read is rejected.
    func currentDevice(direction: AppleAudioDirection) throws -> AudioDeviceID {
        reads.append(direction)
        if direction == failureDirection { throw AppleAudioError.nativeFailure }
        return direction == .input ? input : output
    }
}

/// Synthetic CoreAudio property source exercises catalog logic without hardware access or observers.
@MainActor private final class RoutingTestProperties: AppleAudioHardwareProperties {
    var ids: [AudioDeviceID] = []
    var input: Set<AudioDeviceID> = []
    var output: Set<AudioDeviceID> = []
    var defaultInput: AudioDeviceID = 0
    var defaultOutput: AudioDeviceID = 0
    var constantUID: String?
    var constantName: String?
    var failOperation: String?
    var fail = false

    /// Initializes an empty deterministic hardware property view.
    init() {}

    /// Returns test IDs or a synthetic query error before any native access.
    /// - Returns: Test-controlled list, possibly malformed for rejection tests.
    /// - Throws: RoutingTestError.native when fail is set.
    func deviceIDs() throws -> [AudioDeviceID] {
        if fail { throw RoutingTestError.native }
        return ids
    }

    /// Builds stable names/UIDs from the supplied native-shaped identifier.
    /// - Parameters:
    ///   - device: Synthetic device ID.
    ///   - selector: UID selectors return UID data; other selectors return the display name.
    /// - Returns: Deterministic string, optionally duplicated to test ambiguity rejection.
    /// - Throws: RoutingTestError.native when the string-read failure is selected.
    func string(device: AudioDeviceID, selector: AudioObjectPropertySelector) throws -> String {
        if failOperation == "string" { throw RoutingTestError.native }
        return selector == kAudioDevicePropertyDeviceUID ? (constantUID ?? "uid-\(device)") : (constantName ?? "name-\(device)")
    }

    /// Reports whether the synthetic device supports the requested direction.
    /// - Parameters:
    ///   - device: Synthetic ID to look up.
    ///   - direction: Directional membership set to inspect.
    /// - Returns: True for membership in the requested stream set.
    /// - Throws: RoutingTestError.native when the stream-read failure is selected.
    func hasStreams(device: AudioDeviceID, direction: AppleAudioDirection) throws -> Bool {
        if failOperation == "streams" { throw RoutingTestError.native }
        return (direction == .input ? input : output).contains(device)
    }

    /// Returns the synthetic system default for one direction.
    /// - Parameter direction: Input or output default to read.
    /// - Returns: Test default ID; zero represents no default route.
    /// - Throws: RoutingTestError.native when the default-read failure is selected.
    func defaultDevice(direction: AppleAudioDirection) throws -> AudioDeviceID {
        if failOperation == "default" { throw RoutingTestError.native }
        return direction == .input ? defaultInput : defaultOutput
    }
}
#endif
#endif
