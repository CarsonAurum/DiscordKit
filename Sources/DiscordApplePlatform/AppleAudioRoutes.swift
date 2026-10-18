#if os(macOS) && canImport(AVFoundation) && canImport(os)
import CoreAudio
import Foundation

/// Injected selected-device liveness reads; a bound AudioUnit ID does not establish device availability.
@MainActor protocol AppleAudioDeviceLivenessProperties {
    /// Reads the current native availability flag without opening or changing an audio device.
    /// - Parameter device: Nonzero exact selected CoreAudio ID, local to the current host.
    /// - Returns: True only when the device reports that it is alive.
    /// - Throws: `nativeFailure` for a disconnected object, malformed flag or native query failure.
    func deviceIsAlive(_ device: AudioDeviceID) throws -> Bool
}

/// Fails closed when an explicit device disappears before its native listener can observe the change.
@MainActor enum AppleAudioDeviceLiveness {
    /// Checks each selected device once, preserving input-before-output ordering for distinct devices.
    ///
    /// Invoke after listener installation and again after engine startup. Readback closes a missed
    /// earlier-notification window; it cannot guarantee that hardware remains alive after the read.
    /// An AudioUnit's CurrentDevice property may still contain a disconnected device's former ID.
    /// - Parameters:
    ///   - input: Explicit selected input ID, or nil when default input routing was requested.
    ///   - output: Explicit selected output ID, or nil when default output routing was requested.
    ///   - properties: Synchronous native or deterministic query boundary, never retained.
    /// - Throws: `deviceUnavailable` for unknown/dead devices; native read errors propagate. No
    ///   routing, retries, tasks, permissions or fallback occurs; at most two properties are read.
    static func verify(input: AudioDeviceID?, output: AudioDeviceID?,
                       using properties: any AppleAudioDeviceLivenessProperties) throws {
        var inspected: [AudioDeviceID] = []
        for identifier in [input, output].compactMap({ $0 }) {
            guard identifier != AudioDeviceID(kAudioObjectUnknown) else {
                throw AppleAudioError.deviceUnavailable
            }
            guard !inspected.contains(identifier) else { continue }
            guard try properties.deviceIsAlive(identifier) else { throw AppleAudioError.deviceUnavailable }
            inspected.append(identifier)
        }
    }
}

/// Native fixed-size availability read; construction queries no hardware and starts no observers.
@MainActor struct NativeAppleAudioDeviceLivenessProperties: AppleAudioDeviceLivenessProperties {
    /// Copies the exact UInt32 DeviceIsAlive property and validates the documented boolean value.
    /// - Parameter device: Exact current selected CoreAudio device ID.
    /// - Returns: Whether the device reports one; zero reports a dead device.
    /// - Throws: `nativeFailure` for invalid native size/value, disappeared device or property error.
    func deviceIsAlive(_ device: AudioDeviceID) throws -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
              size == MemoryLayout<UInt32>.size, value <= 1 else { throw AppleAudioError.nativeFailure }
        return value == 1
    }
}

/// Bounded identity for one observed global property; identifiers never enter diagnostics.
struct AppleAudioRouteProperty: Sendable, Hashable {
    let object: AudioObjectID
    let selector: AudioObjectPropertySelector
}

/// Injectable installation boundary preserving the exact native listener block and dispatch queue.
@MainActor protocol AppleAudioRouteListenerProperties {
    /// Installs one observer and returns its idempotently owner-invoked cancellation action.
    /// - Parameters:
    ///   - property: Exact object/selector; global scope and main element are fixed.
    ///   - changed: Native-thread callback; it must not synchronously tear down the audio graph.
    /// - Returns: Cleanup retaining the exact listener identity until removal is attempted.
    /// - Throws: `nativeFailure` if installation fails; failure retains no observer for this call.
    func install(_ property: AppleAudioRouteProperty,
                 changed: @escaping @Sendable () -> Void) throws -> @MainActor () -> Void
}

/// Native CoreAudio block ownership using the same global queue for registration and removal.
@MainActor struct NativeAppleAudioRouteListenerProperties: AppleAudioRouteListenerProperties {
    /// Registers one CoreAudio listener without opening an input/output stream.
    /// - Parameters:
    ///   - property: Object/selector to watch at global scope and main element.
    ///   - changed: Short callback invoking the bounded invalidation bridge.
    /// - Returns: Exact matching removal action. An already destroyed native object can reject
    ///   removal; generation revocation keeps any late/in-flight callback harmless.
    /// - Throws: `nativeFailure` when CoreAudio rejects registration.
    func install(_ property: AppleAudioRouteProperty,
                 changed: @escaping @Sendable () -> Void) throws -> @MainActor () -> Void {
        let listener: AudioObjectPropertyListenerBlock = { _, _ in changed() }
        let address = AudioObjectPropertyAddress(mSelector: property.selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var registrationAddress = address
        guard AudioObjectAddPropertyListenerBlock(property.object, &registrationAddress, .global(), listener) == noErr else {
            throw AppleAudioError.nativeFailure
        }
        return {
            var removalAddress = address
            AudioObjectRemovePropertyListenerBlock(property.object, &removalAddress, .global(), listener)
        }
    }
}

/// Atomic bounded ownership for selected-device/default-route/topology listeners.
///
/// Construction is inert. Begin retains at most three cancellation closures. Native callbacks only
/// offer a generation-fenced invalidation; stop removes listeners in reverse registration order.
/// The backend revokes its invalidation generation before calling stop, including partial starts.
@MainActor final class AppleAudioRouteObservation {
    private let properties: any AppleAudioRouteListenerProperties
    private var cancellations: [@MainActor () -> Void] = []

    /// Stores an injectable registration boundary without native operations or listener allocation.
    /// - Parameter properties: Native or deterministic CoreAudio listener installer, retained by this owner.
    init(properties: any AppleAudioRouteListenerProperties) { self.properties = properties }

    /// Attempts cleanup when a partially started backend omits its explicit stop.
    isolated deinit { stop() }

    /// Installs one coherent observation set, rolling back all successful installs on any failure.
    /// - Parameters:
    ///   - input: Explicit selected input ID; nil observes the system input default when enabled.
    ///   - output: Explicit selected output ID; nil observes the system output default when enabled.
    ///   - captureEnabled: Whether capture routing must be monitored.
    ///   - playbackEnabled: Whether playback routing must be monitored.
    ///   - invalidation: Shared deferred mailbox; callbacks never invoke lifecycle teardown inline.
    ///   - callbacks: Current backend generation's capture/lifecycle callback set.
    ///   - generation: Current opaque invalidation generation; stale callbacks are ignored by the mailbox.
    /// - Throws: `alreadyRunning` if listeners are already owned; `deviceUnavailable` for an unknown
    ///   selected ID; property installation errors propagate after full partial-install cleanup.
    func begin(input: AudioDeviceID?, output: AudioDeviceID?, captureEnabled: Bool, playbackEnabled: Bool,
               invalidation: AppleAudioInvalidationBridge, callbacks: AppleAudioCallbacks,
               generation: UUID) throws {
        guard cancellations.isEmpty else { throw AppleAudioError.alreadyRunning }
        var requested: [AppleAudioRouteProperty] = []
        let system = AudioObjectID(kAudioObjectSystemObject)
        if captureEnabled && input == nil {
            requested.append(.init(object: system, selector: kAudioHardwarePropertyDefaultInputDevice))
        }
        if playbackEnabled && output == nil {
            requested.append(.init(object: system, selector: kAudioHardwarePropertyDefaultOutputDevice))
        }
        requested.append(.init(object: system, selector: kAudioHardwarePropertyDevices))
        for identifier in [captureEnabled ? input : nil, playbackEnabled ? output : nil].compactMap({ $0 }) {
            guard identifier != AudioDeviceID(kAudioObjectUnknown) else { throw AppleAudioError.deviceUnavailable }
            let property = AppleAudioRouteProperty(object: identifier, selector: kAudioDevicePropertyDeviceIsAlive)
            if !requested.contains(property) { requested.append(property) }
        }
        do {
            for property in requested {
                let cancellation = try properties.install(property) {
                    invalidation.enqueue(.routeChanged, callbacks: callbacks, generation: generation)
                }
                cancellations.append(cancellation)
            }
        } catch {
            stop()
            throw error
        }
    }

    /// Removes each successfully installed listener exactly once, including after partial failure.
    ///
    /// Repeated calls are harmless. Revoking the shared invalidation generation first prevents late
    /// or in-flight native callbacks from affecting another start. No media graph is touched here.
    func stop() {
        for cancel in cancellations.reversed() { cancel() }
        cancellations.removeAll(keepingCapacity: false)
    }
}
#endif
