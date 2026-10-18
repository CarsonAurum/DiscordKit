#if os(macOS) && canImport(AVFoundation) && canImport(os)
import CoreAudio
import DiscordMedia
@testable import DiscordApplePlatform
import Testing

/// Regression for physical microphones/speakers rejected by a shared duplex AudioUnit.
@MainActor @Suite struct AppleAudioDirectionalBindingTests {
    /// Matching running graph readback ignores delayed setup noise without a timed exemption;
    /// stopped graphs, changed rates/channels and unavailable expected capture require cleanup.
    @Test func configurationReadbackDecision() throws {
        let format = try PCMFormat(sampleRate: 48_000, channelCount: 1)
        for captureRunning in [true, false] {
            for playbackRunning in [true, false] {
                #expect(AppleAudioConfigurationReadback.requiresStop(captureRunning: captureRunning,
                    playbackRunning: playbackRunning, expectedCapture: format, observedCapture: format) ==
                    (!captureRunning || !playbackRunning))
            }
        }
        #expect(!AppleAudioConfigurationReadback.requiresStop(captureRunning: true, playbackRunning: true,
            expectedCapture: nil, observedCapture: nil))
        for observed in [nil, try PCMFormat(sampleRate: 44_100, channelCount: 1),
                         try PCMFormat(sampleRate: 48_000, channelCount: 2)] {
            #expect(AppleAudioConfigurationReadback.requiresStop(captureRunning: true, playbackRunning: true,
                expectedCapture: format, observedCapture: observed))
        }
        #expect(AppleAudioConfigurationReadback.requiresStop(captureRunning: true, playbackRunning: true,
            expectedCapture: nil, observedCapture: format))
    }
    /// Each independent graph disables its opposite direction before selecting a physical device.
    /// These deterministic checks require no engine, microphone permission or native property writes.
    /// - Parameter direction: Both hardware directions are exercised independently.
    @Test(arguments: [AppleAudioDirection.input, .output])
    func selectionOrderAndDefaultPreservation(_ direction: AppleAudioDirection) throws {
        let properties = DirectionalUnitProbe()
        try AppleAudioDirectionalBinding.configure(device: 42, direction: direction, using: properties)
        let requested = direction == .input ? "input" : "output"
        let opposite = direction == .input ? "output" : "input"
        #expect(properties.operations == ["uninitialize", "\(opposite):false", "\(requested):true", "select:42"])
        properties.operations = []
        try AppleAudioDirectionalBinding.configure(device: nil, direction: direction, using: properties)
        #expect(properties.operations == ["uninitialize", "\(opposite):false", "\(requested):true"])
    }

    /// Invalid IDs fail before native access; every partial native failure prevents later mutations.
    /// - Parameter direction: Input/output unit setup with the same deterministic failure matrix.
    @Test(arguments: [AppleAudioDirection.input, .output])
    func invalidDeviceAndFailureShortCircuit(_ direction: AppleAudioDirection) {
        let properties = DirectionalUnitProbe()
        #expect(throws: AppleAudioError.deviceUnavailable) {
            try AppleAudioDirectionalBinding.configure(device: AudioDeviceID(kAudioObjectUnknown),
                                                       direction: direction, using: properties)
        }
        #expect(properties.operations.isEmpty)
        for failedOperation in 1...4 {
            properties.operations = []
            properties.failAt = failedOperation
            #expect(throws: AppleAudioError.nativeFailure) {
                try AppleAudioDirectionalBinding.configure(device: 42, direction: direction, using: properties)
            }
            #expect(properties.operations.count == failedOperation)
        }
    }
}

/// Fixed deterministic unit command recorder; native identifiers are synthetic constants.
@MainActor private final class DirectionalUnitProbe: AppleAudioDirectionalUnitProperties {
    var operations: [String] = []
    var failAt: Int?

    /// Records uninitialization without constructing any native unit.
    /// - Throws: `nativeFailure` at the configured deterministic operation index.
    func uninitialize() throws { try record("uninitialize") }

    /// Records a single direction's enable state using copied synthetic data.
    /// - Parameters:
    ///   - enabled: Requested I/O admission flag.
    ///   - direction: Input or output being changed.
    /// - Throws: `nativeFailure` at the configured deterministic operation index.
    func setEnabled(_ enabled: Bool, direction: AppleAudioDirection) throws {
        try record("\(direction):\(enabled)")
    }

    /// Records exact physical ID selection after the requested I/O operations.
    /// - Parameter device: Synthetic nonzero native ID.
    /// - Throws: `nativeFailure` at the configured deterministic operation index.
    func selectDevice(_ device: AudioDeviceID) throws { try record("select:\(device)") }

    /// Appends an operation before injecting its configured failure.
    /// - Parameter operation: Small bounded test-owned command string.
    /// - Throws: `nativeFailure` when this command reaches the configured failure index.
    private func record(_ operation: String) throws {
        operations.append(operation)
        if failAt == operations.count { throw AppleAudioError.nativeFailure }
    }
}
#endif
