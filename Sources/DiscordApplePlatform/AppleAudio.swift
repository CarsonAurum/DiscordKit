#if canImport(AVFoundation) && canImport(os)
import AVFoundation
import DiscordMedia
import Foundation
import os
#if os(macOS)
import AudioToolbox
import CoreAudio
#endif

/// Microphone authorization as observed without opening a device or displaying a prompt.
public enum AppleAudioPermission: Sendable, Equatable {
    case undetermined, denied, restricted, granted
}

/// App-wide audio-session ownership selected explicitly for a native engine start.
public enum AppleAudioSessionPolicy: Sendable, Equatable {
    /// The embedding app configures and activates its shared audio session.
    case hostManaged
    /// This device configures a foreground record/playback session and deactivates it on stop.
    /// Adopt only when this owner has exclusive authority over the app-wide session.
    case exclusiveForeground
}

/// Closed lifecycle reasons; native errors and device identifiers are not retained in diagnostics.
public enum AppleAudioStopReason: Sendable, Equatable {
    case requested, interruption, routeChanged, configurationChanged, mediaServicesReset, failed
}

/// Caller-visible device lifecycle. A stopped device resumes only through an explicit start.
public enum AppleAudioState: Sendable, Equatable {
    case idle, running, stopped(AppleAudioStopReason)
}

/// Validation, permission and bounded-admission failures from the Apple audio owner.
public enum AppleAudioError: Error, Sendable, Equatable {
    case invalidConfiguration, alreadyRunning, notRunning, permissionRequestInProgress
    case microphonePermissionRequired(AppleAudioPermission)
    case unavailableFormat, incompatibleFormat, queueFull, identifierExhausted, nativeFailure
    case deviceUnavailable, unsupportedDeviceSelection
}

/// Bounded capture/playback policy; construction never queries or changes native devices.
///
/// Capture retains the hardware rate and selects the first one or two input channels.
/// Consumers explicitly resample for a codec. Playback uses the supplied format and the
/// selected output route. Explicit UIDs resolve again at start and never fall back to another device.
/// macOS supports both directions; iOS/tvOS/visionOS select available inputs only. watchOS
/// exposes route metadata but has no public preferred-input API and rejects explicit UIDs.
public struct AppleAudioConfiguration: Sendable, Equatable {
    public let captureEnabled: Bool
    public let playbackEnabled: Bool
    public let captureChannelCount: Int
    public let captureBufferFrames: Int
    public let playbackFormat: PCMFormat
    public let maximumCaptureBlocks: Int
    public let maximumCaptureBytes: Int
    public let maximumPlaybackBlocks: Int
    public let maximumPlaybackBytes: Int
    public let sessionPolicy: AppleAudioSessionPolicy
    public let captureDeviceUID: String?
    public let playbackDeviceUID: String?

    /// Validates independent queue budgets without requesting microphone permission or starting work.
    /// - Parameters:
    ///   - captureEnabled: Whether an explicit start may open the microphone; defaults to true.
    ///   - playbackEnabled: Whether playback is enabled; at least one direction must be enabled.
    ///   - captureChannelCount: First one or two hardware channels to copy; missing channels fail start.
    ///   - captureBufferFrames: Requested tap delivery size in `1...4096` hardware sample frames.
    ///     AVAudioEngine may deliver another size; callbacks split it into at most 120ms blocks.
    ///   - playbackFormat: Required layout for every playback write; no implicit portable conversion.
    ///   - maximumCaptureBlocks: Retained capture block limit in `1...4096`; overflow drops new capture.
    ///   - maximumCaptureBytes: Capture PCM payload limit in `1...67_108_864`; overhead is block-bounded.
    ///   - maximumPlaybackBlocks: Native scheduled-buffer limit in `1...4096`; writes fail when full.
    ///   - maximumPlaybackBytes: Native scheduled PCM payload limit in `1...67_108_864` bytes.
    ///   - sessionPolicy: Host ownership by default; exclusive foreground mode changes the shared
    ///     session on iOS/tvOS/watchOS/visionOS only, and never acquires background execution time.
    ///   - captureDeviceUID: Exact local CoreAudio/input-port UID, nil for the system route. At most
    ///     1,024 UTF-8 bytes; a UID requires that direction enabled. Available inputs depend on session
    ///     state; watchOS rejects explicit selection because its preferred-input API is unavailable.
    ///   - playbackDeviceUID: Exact local CoreAudio UID, nil for the system route. Explicit output
    ///     selection is macOS-only; other Apple platforms fail start with unsupportedDeviceSelection.
    /// - Throws: `AppleAudioError.invalidConfiguration` for invalid bounds, UIDs or disabled directions.
    public init(captureEnabled: Bool = true, playbackEnabled: Bool = true,
                captureChannelCount: Int = 1, captureBufferFrames: Int = 480,
                playbackFormat: PCMFormat, maximumCaptureBlocks: Int = 8,
                maximumCaptureBytes: Int = 1_048_576, maximumPlaybackBlocks: Int = 8,
                maximumPlaybackBytes: Int = 1_048_576,
                sessionPolicy: AppleAudioSessionPolicy = .hostManaged,
                captureDeviceUID: String? = nil, playbackDeviceUID: String? = nil) throws {
        guard captureEnabled || playbackEnabled, (1...2).contains(captureChannelCount),
              (1...4096).contains(captureBufferFrames),
              (1...4096).contains(maximumCaptureBlocks), (1...4096).contains(maximumPlaybackBlocks),
              (1...67_108_864).contains(maximumCaptureBytes),
              (1...67_108_864).contains(maximumPlaybackBytes) else {
            throw AppleAudioError.invalidConfiguration
        }
        guard captureDeviceUID == nil || (captureEnabled && AppleAudioRouting.validUID(captureDeviceUID!)),
              playbackDeviceUID == nil || (playbackEnabled && AppleAudioRouting.validUID(playbackDeviceUID!)) else {
            throw AppleAudioError.invalidConfiguration
        }
        self.captureDeviceUID = captureDeviceUID
        self.playbackDeviceUID = playbackDeviceUID
        self.captureEnabled = captureEnabled
        self.playbackEnabled = playbackEnabled
        self.captureChannelCount = captureChannelCount
        self.captureBufferFrames = captureBufferFrames
        self.playbackFormat = playbackFormat
        self.maximumCaptureBlocks = maximumCaptureBlocks
        self.maximumCaptureBytes = maximumCaptureBytes
        self.maximumPlaybackBlocks = maximumPlaybackBlocks
        self.maximumPlaybackBytes = maximumPlaybackBytes
        self.sessionPolicy = sessionPolicy
    }
}

/// A coherent bounded-accounting snapshot, excluding buffers already transferred to a consumer.
public struct AppleAudioSnapshot: Sendable, Equatable {
    public let state: AppleAudioState
    public let captureFormat: PCMFormat?
    public let captureBlocks: Int
    public let captureBytes: Int
    public let playbackBlocks: Int
    public let playbackBytes: Int
    public let droppedCaptureBlocks: UInt64
}

/// Synchronous capture admission and MainActor lifecycle invalidation supplied to a backend.
///
/// Capture callbacks may run on a native tap thread. They create no Swift task, retain no native
/// buffer and return immediately after bounded queue admission. A false result drops that block.
/// Lifecycle callbacks must execute on MainActor and request fail-closed cleanup, never auto-resume.
public struct AppleAudioCallbacks: Sendable {
    private let captureBody: @Sendable (PCMBuffer) -> Bool
    private let stopBody: @MainActor @Sendable (AppleAudioStopReason) -> Void

    /// Stores injected callbacks without running either one or retaining any device.
    /// - Parameters:
    ///   - capture: Synchronous whole-block admission; false means no block was retained.
    ///   - stopped: MainActor invalidation notification; the owner stops and clears the backend.
    public init(capture: @escaping @Sendable (PCMBuffer) -> Bool,
                stopped: @escaping @MainActor @Sendable (AppleAudioStopReason) -> Void) {
        captureBody = capture
        stopBody = stopped
    }

    /// Offers one captured portable block without scheduling work.
    /// - Parameter buffer: Owned finite normalized mono/stereo PCM, at most 120ms.
    /// - Returns: Whether the current generation retained the entire block; false on stop or overflow.
    public func capture(_ buffer: PCMBuffer) -> Bool { captureBody(buffer) }

    /// Invalidates the current native session, requiring explicit consumer restart.
    /// - Parameter reason: Structured interruption, route, configuration or backend failure reason.
    @MainActor public func stopped(_ reason: AppleAudioStopReason) { stopBody(reason) }
}

/// Injected serialized native-device boundary; deterministic tests need never open hardware.
///
/// Implementations must not start work in their initializer. A failed start must tolerate an
/// immediate stop. Playback completion may run on any thread, exactly once or after a later stop;
/// generation fencing makes late callbacks harmless. Stop synchronously revokes callback admission
/// and releases native devices. Implementations must honor exact configured UIDs or throw
/// unsupportedDeviceSelection/deviceUnavailable; silent default fallback is forbidden. They must
/// not silently change the requested PCM format.
@MainActor public protocol AppleAudioBackend: AnyObject, Sendable {
    /// Explicitly enumerates bounded endpoint metadata without activating/opening audio devices.
    /// - Returns: At most 512 UID/direction entries; AVAudioSession outputs are current-route metadata only.
    /// - Throws: A query failure; the owner redacts native errors. A snapshot can become stale immediately.
    func availableDevices() throws -> [AppleAudioEndpoint]

    /// Reads current permission without a prompt or device access.
    /// - Returns: The currently observed microphone authorization state.
    func recordingPermission() -> AppleAudioPermission

    /// Explicitly requests microphone authorization, possibly suspending for the user's response.
    /// - Returns: The resulting authorization state; a native prompt cannot be dismissed by cancellation.
    func requestRecordingPermission() async -> AppleAudioPermission

    /// Starts native capture/playback only after the owner has validated permission and cancellation.
    /// - Parameters:
    ///   - configuration: Validated routing, format, session and capacity policy.
    ///   - callbacks: Current-generation capture and lifecycle callbacks.
    /// - Returns: Actual hardware-rate capture format, or nil when capture is disabled.
    /// - Throws: A backend failure; the owner always invokes stop before propagating a redacted error.
    func start(configuration: AppleAudioConfiguration, callbacks: AppleAudioCallbacks) throws -> PCMFormat?

    /// Schedules one bounded portable PCM block without retaining it after a throwing return.
    /// - Parameters:
    ///   - buffer: Nonempty PCM matching the configured playback format.
    ///   - completion: Releases its reserved budget after native playback or stop.
    /// - Throws: An allocation/native failure before successful scheduling.
    func enqueuePlayback(_ buffer: PCMBuffer, completion: @escaping @Sendable () -> Void) throws

    /// Stops native devices and notifications, including partially started and repeated stops.
    /// Stop must not wait for a callback that is attempting to acquire MainActor.
    func stop()
}

/// Default enumeration for existing injected backends that do not implement device discovery.
public extension AppleAudioBackend {
    /// Reports that this backend does not expose native device enumeration, without starting I/O.
    /// - Returns: No value; conformers with native discovery override this implementation.
    /// - Throws: Always `unsupportedDeviceSelection`.
    func availableDevices() throws -> [AppleAudioEndpoint] { throw AppleAudioError.unsupportedDeviceSelection }
}

/// Explicit Apple capture/playback owner over a real or injected native backend.
///
/// Construction starts no I/O, tasks, observers or permission prompt. Lifecycle and public calls
/// are serialized by MainActor; the native tap/completion path uses one short OS-allocated lock
/// and creates no task per callback. The input tap is not a realtime render callback, and this
/// adapter makes no realtime, no-allocation, AEC or device-qualification claim. Both directions use
/// bounded payload/block budgets. Capture overflow drops the newest block; playback overflow fails.
///
/// The embedding app supplies NSMicrophoneUsageDescription and required sandbox entitlements.
/// Query/request permission explicitly before capture start. Route changes and interruptions request
/// stop and discard queued media, requiring explicit restart. macOS configuration notifications
/// whose running graphs, capture format, exact bindings and liveness still match are benign delayed
/// setup notifications; other observed configuration changes stop. Native notification delivery is
/// asynchronous and cannot guarantee the absence of transient hardware rerouting. macOS UIDs
/// select exact engine-local devices. AVAudioSession input preferences require app-wide session authority. Native codec processing and background entitlement ownership
/// remain separate work. Call stop before abandoning the owner; deinitialization also stops.
@MainActor
public final class AppleAudioDevice: PCMSource, PCMSink {
    public let configuration: AppleAudioConfiguration
    private let backend: any AppleAudioBackend
    private let storage: AppleAudioStorage
    private var state: AppleAudioState = .idle
    private var captureFormat: PCMFormat?
    private var generation: UInt64 = 0
    private var permissionRequestPending = false

    /// Stores an injected backend and empty bounded queues, performing no native calls.
    /// - Parameters:
    ///   - configuration: Validated per-direction limits and native ownership policy.
    ///   - backend: Serialized real or deterministic native boundary; its initializer must be inert.
    public init(configuration: AppleAudioConfiguration, backend: any AppleAudioBackend) {
        self.configuration = configuration
        self.backend = backend
        storage = AppleAudioStorage(configuration: configuration)
    }

    /// Creates the owned AVAudioEngine backend without constructing an engine or opening a device.
    /// - Parameter configuration: Explicit media budgets and app-wide audio-session ownership policy.
    public convenience init(configuration: AppleAudioConfiguration) {
        self.init(configuration: configuration, backend: NativeAppleAudioBackend())
    }

    /// Stops callback admission and releases any native resources on the owner's actor.
    isolated deinit {
        storage.end()
        backend.stop()
    }

    /// Explicitly queries current endpoint metadata without opening audio or requesting permission.
    ///
    /// On AVAudioSession platforms, available inputs depend on the host-configured active category;
    /// outputs describe only the current route and cannot be selected by UID. UIDs are local hardware
    /// identifiers; store only when needed and do not use them as telemetry labels.
    /// - Returns: At most 512 current endpoint entries; an empty list is valid when no route exists.
    /// - Throws: Cancellation, unsupportedDeviceSelection, or redacted nativeFailure for query errors.
    public func availableDevices() throws -> [AppleAudioEndpoint] {
        try Task.checkCancellation()
        do {
            let devices = try backend.availableDevices()
            guard devices.count <= 512 else { throw AppleAudioError.nativeFailure }
            return devices
        } catch {
            if let known = error as? AppleAudioError { throw known }
            throw AppleAudioError.nativeFailure
        }
    }

    /// Queries microphone status without prompting or starting an engine.
    /// - Returns: The native or injected permission state; playback-only adoption needs no grant.
    public func recordingPermission() -> AppleAudioPermission { backend.recordingPermission() }

    /// Explicitly requests permission once at a time without starting capture.
    ///
    /// Cancellation is checked before invoking the backend and after the native response; the OS
    /// authorization prompt itself cannot be cancelled. Other device operations remain available
    /// while the request is suspended, but a second permission request fails instead of accumulating.
    /// - Returns: Current authorization after the user's response.
    /// - Throws: `CancellationError`, or `permissionRequestInProgress` for a concurrent request.
    public func requestRecordingPermission() async throws -> AppleAudioPermission {
        try Task.checkCancellation()
        guard !permissionRequestPending else { throw AppleAudioError.permissionRequestInProgress }
        permissionRequestPending = true
        defer { permissionRequestPending = false }
        let result = await backend.requestRecordingPermission()
        try Task.checkCancellation()
        return result
    }

    /// Explicitly starts configured routes after permission, with fresh generation-fenced callbacks.
    /// - Returns: Actual capture format at the device rate, or nil for playback-only operation.
    /// - Throws: Cancellation before native access, `alreadyRunning`, `microphonePermissionRequired`,
    ///   `identifierExhausted`, `unavailableFormat`, `deviceUnavailable`,
    ///   `unsupportedDeviceSelection`, or redacted `nativeFailure`. Every native start
    ///   failure stops the backend and clears all queue accounting before returning.
    @discardableResult public func start() throws -> PCMFormat? {
        try Task.checkCancellation()
        guard state != .running else { throw AppleAudioError.alreadyRunning }
        if configuration.captureEnabled {
            let permission = backend.recordingPermission()
            guard permission == .granted else { throw AppleAudioError.microphonePermissionRequired(permission) }
        }
        guard generation < .max else { throw AppleAudioError.identifierExhausted }
        generation += 1
        let current = generation
        storage.begin(generation: current)
        state = .running
        let storage = storage
        let callbacks = AppleAudioCallbacks(capture: { buffer in
            storage.capture(buffer, generation: current)
        }, stopped: { [weak self] reason in
            self?.invalidate(reason, generation: current)
        })
        do {
            let format = try backend.start(configuration: configuration, callbacks: callbacks)
            try Task.checkCancellation()
            guard state == .running,
                  configuration.captureEnabled == (format != nil),
                  format == nil || format?.channelCount == configuration.captureChannelCount else {
                throw AppleAudioError.unavailableFormat
            }
            captureFormat = format
            try storage.setCaptureFormat(format)
            return format
        } catch {
            stop(reason: .failed)
            if error is CancellationError { throw error }
            if let known = error as? AppleAudioError { throw known }
            throw AppleAudioError.nativeFailure
        }
    }

    /// Removes one captured block in FIFO order without retaining a pending read.
    /// - Returns: A hardware-rate block, or nil when currently idle; inspect snapshot for lifecycle.
    /// - Throws: Cancellation before removal, or `notRunning` after stop/before start.
    @MainActor public func read() async throws -> PCMBuffer? {
        try Task.checkCancellation()
        guard state == .running else { throw AppleAudioError.notRunning }
        return storage.read()
    }

    /// Atomically reserves bounded native playback capacity and schedules the whole PCM block.
    ///
    /// Scheduling is serialized on MainActor. Completion releases only its own current-generation
    /// reservation and creates no task. A throwing backend call releases the reservation immediately.
    /// Empty matching blocks are no-ops. Successful return means scheduled, not necessarily audible.
    /// - Parameter buffer: At most 120ms matching configuration.playbackFormat.
    /// - Throws: Cancellation, `notRunning`, `incompatibleFormat`, `queueFull`, identifier exhaustion,
    ///   or redacted `nativeFailure`; failure retains no new playback payload budget.
    @MainActor public func write(_ buffer: PCMBuffer) async throws {
        try Task.checkCancellation()
        guard state == .running, configuration.playbackEnabled else { throw AppleAudioError.notRunning }
        guard buffer.format == configuration.playbackFormat else { throw AppleAudioError.incompatibleFormat }
        guard buffer.frameCount > 0 else { return }
        let current = generation
        let identifier = try storage.reservePlayback(bytes: buffer.accountedBytes)
        let storage = storage
        do {
            try backend.enqueuePlayback(buffer) { storage.completePlayback(identifier, generation: current) }
        } catch {
            storage.completePlayback(identifier, generation: current)
            throw AppleAudioError.nativeFailure
        }
    }

    /// Revokes callback admission before stopping native I/O and discarding all queued media.
    /// - Parameter reason: Defaults to explicit caller stop. Repeated stops are harmless and require
    ///   no permission or uncancelled task; later restart creates an independent callback generation.
    public func stop(reason: AppleAudioStopReason = .requested) {
        storage.end()
        state = .stopped(reason)
        captureFormat = nil
        backend.stop()
    }

    /// Reports coherent PCM accounting without querying native devices or exposing sample content.
    /// - Returns: Lifecycle, actual capture format and block/byte counts within configured limits.
    public func snapshot() -> AppleAudioSnapshot {
        storage.snapshot(state: state, captureFormat: captureFormat)
    }

    /// Applies a backend event only to the session that installed its notification observers.
    /// - Parameters:
    ///   - reason: Current backend interruption/route/configuration invalidation.
    ///   - generation: Monotonic start generation; stale events after restart are ignored.
    private func invalidate(_ reason: AppleAudioStopReason, generation: UInt64) {
        guard state == .running, generation == self.generation else { return }
        stop(reason: reason)
    }
}

/// Synchronous short-lock mailbox shared by non-realtime input taps and completion callbacks.
/// All mutable callback state is held inside the Sendable system lock; no unchecked witness is added.
private final class AppleAudioStorage: Sendable {
    private struct State: Sendable {
        var generation: UInt64 = 0
        var active = false
        var captureFormat: PCMFormat?
        var captures: [PCMBuffer] = []
        var captureBytes = 0
        var playback: [UInt64: Int] = [:]
        var playbackBytes = 0
        var nextPlayback: UInt64 = 0
        var dropped: UInt64 = 0
    }
    private let configuration: AppleAudioConfiguration
    private let lock = OSAllocatedUnfairLock(initialState: State())

    /// Stores bounds without allocating media or beginning device activity.
    /// - Parameter configuration: Validated mailbox bounds, shared by the owning lifecycle.
    init(configuration: AppleAudioConfiguration) { self.configuration = configuration }

    /// Begins empty current-generation accounting while preserving bounded diagnostic drop totals.
    /// - Parameter generation: Fresh monotonic start generation, never reused by the owner.
    func begin(generation: UInt64) {
        lock.withLock { state in
            state.generation = generation
            state.active = true
            state.captureFormat = nil
            state.captures.removeAll(keepingCapacity: false)
            state.captureBytes = 0
            state.playback.removeAll(keepingCapacity: false)
            state.playbackBytes = 0
        }
    }

    /// Commits negotiated capture layout after start, rejecting inconsistent early callbacks.
    /// - Parameter format: Actual native capture layout, nil for playback-only operation.
    /// - Throws: `unavailableFormat` if a backend delivered a different layout during start.
    func setCaptureFormat(_ format: PCMFormat?) throws {
        try lock.withLock { state in
            guard state.captures.allSatisfy({ $0.format == format }) else {
                throw AppleAudioError.unavailableFormat
            }
            state.captureFormat = format
        }
    }

    /// Admits a whole capture block or drops it without partially retaining payload.
    /// - Parameters:
    ///   - buffer: Current backend's immutable normalized PCM block.
    ///   - generation: Callback's owning start generation; stale callbacks are ignored.
    /// - Returns: True on whole-block admission, false on stop, layout mismatch or capacity overflow.
    func capture(_ buffer: PCMBuffer, generation: UInt64) -> Bool {
        lock.withLock { state in
            guard state.active, state.generation == generation, configuration.captureEnabled else { return false }
            guard buffer.format.channelCount == configuration.captureChannelCount,
                  state.captureFormat == nil || state.captureFormat == buffer.format,
                  state.captures.count < configuration.maximumCaptureBlocks,
                  buffer.accountedBytes <= configuration.maximumCaptureBytes - state.captureBytes else {
                if state.dropped < .max { state.dropped += 1 }
                return false
            }
            state.captures.append(buffer)
            state.captureBytes += buffer.accountedBytes
            return true
        }
    }

    /// Transfers the oldest queued capture block to a consumer and releases its accounting.
    /// - Returns: FIFO block, or nil when no current block is buffered.
    func read() -> PCMBuffer? {
        lock.withLock { state in
            guard !state.captures.isEmpty else { return nil }
            let buffer = state.captures.removeFirst()
            state.captureBytes -= buffer.accountedBytes
            return buffer
        }
    }

    /// Reserves one scheduled native block before any native allocation occurs.
    /// - Parameter bytes: Positive bounded PCM payload byte cost.
    /// - Returns: Monotonic callback identifier; repeated completions cannot release another block.
    /// - Throws: `queueFull`, `notRunning`, or `identifierExhausted` without altering budgets.
    func reservePlayback(bytes: Int) throws -> UInt64 {
        try lock.withLock { state in
            guard state.active else { throw AppleAudioError.notRunning }
            guard state.playback.count < configuration.maximumPlaybackBlocks,
                  bytes <= configuration.maximumPlaybackBytes - state.playbackBytes else {
                throw AppleAudioError.queueFull
            }
            guard state.nextPlayback < .max else { throw AppleAudioError.identifierExhausted }
            state.nextPlayback += 1
            let identifier = state.nextPlayback
            state.playback[identifier] = bytes
            state.playbackBytes += bytes
            return identifier
        }
    }

    /// Releases one exact playback reservation; duplicate/stale completions are harmless.
    /// - Parameters:
    ///   - identifier: Identifier returned at reservation, not a native device identifier.
    ///   - generation: Generation captured when this completion was installed.
    func completePlayback(_ identifier: UInt64, generation: UInt64) {
        lock.withLock { state in
            guard state.generation == generation,
                  let bytes = state.playback.removeValue(forKey: identifier) else { return }
            state.playbackBytes -= bytes
        }
    }

    /// Closes admission before native stop, releasing all retained PCM and reservation metadata.
    /// Repeated calls are valid; late callbacks cannot revive storage.
    func end() {
        lock.withLock { state in
            state.active = false
            state.captures.removeAll(keepingCapacity: false)
            state.captureBytes = 0
            state.playback.removeAll(keepingCapacity: false)
            state.playbackBytes = 0
            state.captureFormat = nil
        }
    }

    /// Copies bounded counters under the callback lock; sample payloads are never exposed.
    /// - Parameters:
    ///   - state: MainActor lifecycle observed in the same serialized owner call.
    ///   - captureFormat: Native format committed by the owner after successful start.
    /// - Returns: One coherent payload accounting record.
    func snapshot(state: AppleAudioState, captureFormat: PCMFormat?) -> AppleAudioSnapshot {
        lock.withLock { value in
            AppleAudioSnapshot(state: state, captureFormat: captureFormat,
                               captureBlocks: value.captures.count, captureBytes: value.captureBytes,
                               playbackBlocks: value.playback.count, playbackBytes: value.playbackBytes,
                               droppedCaptureBlocks: value.dropped)
        }
    }
}

/// Real foreground AVAudioEngine implementation, isolated from portable media and deterministic tests.
///
/// Input taps execute outside the realtime render callback contract. Existing installTap remains a
/// fallback for the package's deployment minima; SDK 27 uses its throwing Sendable tap API. The SDK's
/// realtime-safe source/sink callbacks are unavailable to Swift; no Swift render callback is installed.
/// See https://developer.apple.com/documentation/avfaudio/avaudionode and
/// https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes.
@MainActor private final class NativeAppleAudioBackend: AppleAudioBackend {
    private var engine: AVAudioEngine?
    #if os(macOS)
    private var separatePlaybackEngine: AVAudioEngine?
    #endif
    private var player: AVAudioPlayerNode?
    private var playbackFormat: AVAudioFormat?
    private var tapInstalled = false
    private var observers: [NSObjectProtocol] = []
    private var activatedSession = false
    private var activeObserverGeneration: UUID?
    #if !os(macOS) && !os(watchOS)
    private var previousPreferredInput: AVAudioSessionPortDescription?
    private var changedPreferredInput = false
    private var selectedPreferredInputUID: String?
    #endif
    private let invalidation = AppleAudioInvalidationBridge()
    #if os(macOS)
    private let routeObservation = AppleAudioRouteObservation(properties: NativeAppleAudioRouteListenerProperties())
    #endif

    /// Creates an inert backend; AVAudioEngine and native sessions are deferred until explicit start.
    init() {}

    /// Removes notification observers and native resources when explicit cleanup was omitted.
    isolated deinit { stop() }

    /// Queries bounded system device/input-port metadata without an engine or permission prompt.
    /// - Returns: CoreAudio selectable UIDs on macOS; available inputs and current outputs elsewhere.
    /// - Throws: `nativeFailure` for excessive/invalid metadata or CoreAudio query failures.
    func availableDevices() throws -> [AppleAudioEndpoint] {
        do {
            #if os(macOS)
            return try AppleAudioHardwareCatalog.endpoints(using: NativeAppleAudioHardwareProperties())
            #else
            let session = AVAudioSession.sharedInstance()
            let inputs = session.availableInputs ?? []
            let route = session.currentRoute
            guard inputs.count <= 256, route.outputs.count <= 256 else { throw AppleAudioError.nativeFailure }
            let currentInputs = Set(route.inputs.map(\.uid))
            #if os(watchOS)
            let inputSelectable = false
            #else
            let inputSelectable = true
            #endif
            return try inputs.map {
                try AppleAudioEndpoint(uid: $0.uid, name: $0.portName, direction: .input,
                                       isDefault: currentInputs.contains($0.uid), isSelectable: inputSelectable)
            } + route.outputs.map {
                try AppleAudioEndpoint(uid: $0.uid, name: $0.portName, direction: .output,
                                       isDefault: true, isSelectable: false)
            }
            #endif
        } catch {
            throw AppleAudioError.nativeFailure
        }
    }

    /// Reads authorization without touching an input node, ensuring start cannot implicitly prompt.
    /// - Returns: Native microphone authorization mapped to the portable permission state.
    func recordingPermission() -> AppleAudioPermission {
        #if os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .undetermined
        @unknown default: .restricted
        }
        #else
        if #available(iOS 17, tvOS 17, watchOS 10, visionOS 1, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            case .undetermined: return .undetermined
            @unknown default: return .restricted
            }
        } else {
            #if os(tvOS)
            return .restricted
            #else
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            case .undetermined: return .undetermined
            @unknown default: return .restricted
            }
            #endif
        }
        #endif
    }

    /// Presents only an explicitly requested native authorization dialog and waits for its result.
    /// - Returns: Current permission after the OS response; never starts an engine.
    func requestRecordingPermission() async -> AppleAudioPermission {
        #if os(macOS)
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        #else
        if #available(iOS 17, tvOS 17, watchOS 10, visionOS 1, *) {
            _ = await AVAudioApplication.requestRecordPermission()
        } else {
            #if !os(tvOS)
            _ = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            #endif
        }
        #endif
        return recordingPermission()
    }

    /// Builds and starts an engine against exact requested UIDs or the current system routes.
    /// - Parameters:
    ///   - configuration: Validated mono/stereo selection, playback format and session policy.
    ///   - callbacks: Bounded generation-fenced capture and lifecycle callbacks.
    /// - Returns: Actual hardware-rate capture layout, or nil for playback-only use.
    /// - Throws: Native engine/session errors, `unavailableFormat`, `deviceUnavailable` or
    ///   `unsupportedDeviceSelection`; caller invokes stop to release partial device/session ownership.
    ///   macOS installs route/alive listeners before starting the graph and checks selected-device
    ///   liveness both before and after startup, so an earlier unobserved unplug fails closed even
    ///   when the AudioUnit retains its former device ID. Readback is not a hardware-presence guarantee.
    ///   Explicit macOS duplex selection uses two direction-specific engines; a shared engine's
    ///   single duplex unit cannot bind separately to input-only/output-only physical devices.
    func start(configuration: AppleAudioConfiguration, callbacks: AppleAudioCallbacks) throws -> PCMFormat? {
        guard engine == nil else { throw AppleAudioError.alreadyRunning }
        #if !os(macOS)
        guard configuration.playbackDeviceUID == nil else { throw AppleAudioError.unsupportedDeviceSelection }
        #if os(watchOS)
        guard configuration.captureDeviceUID == nil else { throw AppleAudioError.unsupportedDeviceSelection }
        #endif
        if configuration.sessionPolicy == .exclusiveForeground {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(configuration.captureEnabled ? .playAndRecord : .playback, mode: .default)
            try session.setActive(true)
            activatedSession = true
        }
        #endif
        #if !os(macOS) && !os(watchOS)
        if let uid = configuration.captureDeviceUID {
            _ = try AppleAudioRouting.resolve(uid: uid, direction: .input, endpoints: availableDevices())
            let session = AVAudioSession.sharedInstance()
            guard let port = session.availableInputs?.first(where: { $0.uid == uid }) else {
                throw AppleAudioError.deviceUnavailable
            }
            previousPreferredInput = session.preferredInput
            changedPreferredInput = true
            selectedPreferredInputUID = uid
            try session.setPreferredInput(port)
            guard session.currentRoute.inputs.contains(where: { $0.uid == uid }) else {
                throw AppleAudioError.deviceUnavailable
            }
        }
        #endif
        let native = AVAudioEngine()
        engine = native
        #if os(macOS)
        let separateDirections = configuration.captureEnabled && configuration.playbackEnabled &&
            (configuration.captureDeviceUID != nil || configuration.playbackDeviceUID != nil)
        let outputNative = separateDirections ? AVAudioEngine() : native
        if separateDirections { separatePlaybackEngine = outputNative }
        var selectedInputID: AudioDeviceID?
        var selectedOutputID: AudioDeviceID?
        if configuration.captureEnabled && (separateDirections || configuration.captureDeviceUID != nil) {
            selectedInputID = try selectDevice(uid: configuration.captureDeviceUID,
                                               direction: .input, node: native.inputNode)
        }
        if configuration.playbackEnabled && (separateDirections || configuration.playbackDeviceUID != nil) {
            selectedOutputID = try selectDevice(uid: configuration.playbackDeviceUID,
                                                direction: .output, node: outputNative.outputNode)
        }
        let bindingProperties = NativeAppleAudioBoundDeviceProperties(inputEngine: native, outputEngine: outputNative)
        try AppleAudioHardwareBinding.verify(input: selectedInputID, output: selectedOutputID, using: bindingProperties)
        #else
        let outputNative = native
        #endif
        activeObserverGeneration = invalidation.begin()
        var captureFormat: PCMFormat?
        if configuration.captureEnabled {
            let input = native.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.commonFormat == .pcmFormatFloat32,
                  format.channelCount >= UInt32(configuration.captureChannelCount),
                  format.sampleRate.isFinite, format.sampleRate.rounded() == format.sampleRate,
                  (8_000...192_000).contains(format.sampleRate) else {
                throw AppleAudioError.unavailableFormat
            }
            captureFormat = try PCMFormat(sampleRate: Int(format.sampleRate),
                                          channelCount: configuration.captureChannelCount)
            let channels = configuration.captureChannelCount
            if #available(macOS 27, iOS 27, tvOS 27, watchOS 27, visionOS 27, *) {
                try input.installAudioTap(onBus: 0, bufferSize: AVAudioFrameCount(configuration.captureBufferFrames),
                                          format: nil) { buffer, _ in
                    buffer.withUnsafeAudioBufferList { list in
                        Self.copyCapture(format: buffer.format, frameLength: buffer.frameLength,
                                         buffers: UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list)),
                                         channelCount: channels, receive: callbacks.capture)
                    }
                }
            } else {
                input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(configuration.captureBufferFrames),
                                 format: nil) { buffer, _ in
                    Self.copyCapture(format: buffer.format, frameLength: Int(buffer.frameLength),
                                     buffers: UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList),
                                     channelCount: channels, receive: callbacks.capture)
                }
            }
            tapInstalled = true
        }
        if configuration.playbackEnabled {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(configuration.playbackFormat.sampleRate),
                                            channels: AVAudioChannelCount(configuration.playbackFormat.channelCount)) else {
                throw AppleAudioError.unavailableFormat
            }
            let player = AVAudioPlayerNode()
            outputNative.attach(player)
            if #available(macOS 27, iOS 27, tvOS 27, watchOS 27, visionOS 27, *) {
                try outputNative.connectNode(player, to: outputNative.mainMixerNode, format: format)
            } else {
                outputNative.connect(player, to: outputNative.mainMixerNode, format: format)
            }
            self.player = player
            playbackFormat = format
        }
        #if os(macOS)
        let configurationCallbacks = AppleAudioCallbacks(capture: callbacks.capture, stopped: {
            [weak native, weak outputNative] reason in
            guard let native, let outputNative else { callbacks.stopped(reason); return }
            var observedCapture: PCMFormat?
            if let expected = captureFormat {
                let current = native.inputNode.outputFormat(forBus: 0)
                if current.commonFormat == .pcmFormatFloat32,
                   current.sampleRate.isFinite, current.sampleRate.rounded() == current.sampleRate,
                   (8_000...192_000).contains(current.sampleRate),
                   current.channelCount >= UInt32(expected.channelCount) {
                    observedCapture = try? PCMFormat(sampleRate: Int(current.sampleRate),
                                                     channelCount: expected.channelCount)
                }
            }
            guard !AppleAudioConfigurationReadback.requiresStop(captureRunning: native.isRunning,
                playbackRunning: !configuration.playbackEnabled || outputNative.isRunning,
                expectedCapture: captureFormat, observedCapture: observedCapture) else {
                callbacks.stopped(reason)
                return
            }
            do {
                try AppleAudioHardwareBinding.verify(input: selectedInputID, output: selectedOutputID,
                    using: bindingProperties)
                try AppleAudioDeviceLiveness.verify(input: selectedInputID, output: selectedOutputID,
                    using: NativeAppleAudioDeviceLivenessProperties())
            } catch { callbacks.stopped(reason) }
        })
        observe(name: .AVAudioEngineConfigurationChange, object: native,
                reason: .configurationChanged, callbacks: configurationCallbacks)
        if separateDirections {
            observe(name: .AVAudioEngineConfigurationChange, object: outputNative,
                    reason: .configurationChanged, callbacks: configurationCallbacks)
        }
        #else
        observe(name: .AVAudioEngineConfigurationChange, object: native,
                reason: .configurationChanged, callbacks: callbacks)
        #endif
        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        observe(name: AVAudioSession.interruptionNotification, object: session,
                reason: .interruption, callbacks: callbacks)
        observe(name: AVAudioSession.routeChangeNotification, object: session,
                reason: .routeChanged, callbacks: callbacks)
        observe(name: AVAudioSession.mediaServicesWereResetNotification, object: session,
                reason: .mediaServicesReset, callbacks: callbacks)
        #else
        guard let observerGeneration = activeObserverGeneration else { throw AppleAudioError.notRunning }
        try routeObservation.begin(input: selectedInputID, output: selectedOutputID,
            captureEnabled: configuration.captureEnabled, playbackEnabled: configuration.playbackEnabled,
            invalidation: invalidation, callbacks: callbacks, generation: observerGeneration)
        let liveness = NativeAppleAudioDeviceLivenessProperties()
        try AppleAudioDeviceLiveness.verify(input: selectedInputID, output: selectedOutputID, using: liveness)
        #endif
        native.prepare()
        try native.start()
        #if os(macOS)
        if separateDirections {
            outputNative.prepare()
            try outputNative.start()
        }
        try AppleAudioHardwareBinding.verify(input: selectedInputID, output: selectedOutputID, using: bindingProperties)
        try AppleAudioDeviceLiveness.verify(input: selectedInputID, output: selectedOutputID, using: liveness)
        #endif
        if #available(macOS 27, iOS 27, tvOS 27, watchOS 27, visionOS 27, *) {
            try player?.playAudio()
        } else {
            player?.play()
        }
        return captureFormat
    }

    /// Copies a bounded portable block to a native planar buffer, scheduling completion after playback.
    /// - Parameters:
    ///   - buffer: Matching normalized PCM already reserved against the owner's native budget.
    ///   - completion: Short synchronous accounting callback; it never invokes AVAudioPlayerNode.stop.
    /// - Throws: `notRunning` or `nativeFailure` before scheduling when storage cannot be allocated.
    func enqueuePlayback(_ buffer: PCMBuffer, completion: @escaping @Sendable () -> Void) throws {
        guard let player, let playbackFormat else { throw AppleAudioError.notRunning }
        let native = try AppleAudioPCMConversion.playbackBuffer(buffer, format: playbackFormat)
        player.scheduleBuffer(native, completionCallbackType: .dataPlayedBack) { _ in completion() }
    }

    /// Removes observers/tap, stops the engine and deactivates only a session activated by this owner.
    /// Repeated calls are harmless, and completion callbacks only release already-revoked accounting.
    /// macOS invalidation authority is revoked before all exact listener identities are removed in
    /// reverse installation order; late native callbacks cannot stop a replacement generation.
    /// A preferred input is restored only while this owner still owns that preference; a host-selected
    /// replacement is preserved. A disconnected previous port is replaced by the system preference.
    func stop() {
        activeObserverGeneration = nil
        invalidation.end()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll(keepingCapacity: false)
        #if os(macOS)
        routeObservation.stop()
        #endif
        player?.stop()
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0) }
        tapInstalled = false
        engine?.stop()
        #if os(macOS)
        separatePlaybackEngine?.stop()
        separatePlaybackEngine = nil
        #endif
        engine = nil
        player = nil
        playbackFormat = nil
        #if !os(macOS) && !os(watchOS)
        if changedPreferredInput {
            let session = AVAudioSession.sharedInstance()
            if session.preferredInput?.uid == selectedPreferredInputUID {
                let previous = previousPreferredInput.flatMap { port in
                    session.availableInputs?.first { $0.uid == port.uid }
                }
                try? session.setPreferredInput(previous)
            }
        }
        previousPreferredInput = nil
        selectedPreferredInputUID = nil
        changedPreferredInput = false
        #endif
        #if !os(macOS)
        if activatedSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
        activatedSession = false
    }

    /// Installs one observer and coalesces teardown after its notification stack has returned.
    /// Engine deallocation inside a configuration notification handler is forbidden by AVAudioEngine.
    /// - Parameters:
    ///   - name: Engine/session notification requiring conservative stop.
    ///   - object: Exact observed engine or shared audio session, never retained in diagnostics.
    ///   - reason: Structured reason delivered to the owner on MainActor.
    ///   - callbacks: Current start-generation callback set.
    private func observe(name: Notification.Name, object: AnyObject,
                         reason: AppleAudioStopReason, callbacks: AppleAudioCallbacks) {
        guard let generation = activeObserverGeneration else { return }
        let invalidation = invalidation
        observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: nil) { _ in
            invalidation.enqueue(reason, callbacks: callbacks, generation: generation)
        })
    }

    #if os(macOS)
    /// Configures a direction-specific engine and selects its exact physical device when requested.
    /// - Parameters:
    ///   - uid: Exact local UID or nil for this direction's system route; no explicit UID falls back.
    ///   - direction: Input/output stream eligibility to validate before touching the AudioUnit.
    ///   - node: Engine I/O node whose current device is changed before graph/tap setup.
    /// - Returns: Explicit native ID for paired readback/liveness monitoring, or nil for default routing.
    /// - Throws: `deviceUnavailable` for missing UID/direction; `nativeFailure` for native rejection.
    ///   Both selected directions are verified together after selection and again after startup,
    ///   because selecting a second device or starting the engine may rebind an earlier node.
    ///   Selection never changes system-wide default properties.
    private func selectDevice(uid: String?, direction: AppleAudioDirection, node: AVAudioIONode) throws -> AudioDeviceID? {
        let identifier = try uid.map {
            try AppleAudioHardwareCatalog.deviceID(uid: $0, direction: direction,
                                                   using: NativeAppleAudioHardwareProperties())
        }
        if #available(macOS 27, *) {
            try node.withAudioUnit { unit in
                guard let unit else { throw AppleAudioError.nativeFailure }
                try AppleAudioDirectionalBinding.configure(device: identifier, direction: direction,
                    using: NativeAppleAudioDirectionalUnitProperties(unit: unit))
            }
        } else {
            guard let unit = node.audioUnit else { throw AppleAudioError.nativeFailure }
            try AppleAudioDirectionalBinding.configure(device: identifier, direction: direction,
                using: NativeAppleAudioDirectionalUnitProperties(unit: unit))
        }
        return identifier
    }

    #endif

    /// Copies native tap delivery in bounded chunks, never retaining the AVAudioPCMBuffer.
    /// - Parameters:
    ///   - format: Float32 native interleaved/planar layout supplied by AVAudioEngine.
    ///   - frameLength: Complete native frames in this delivery.
    ///   - buffers: Callback-scoped native storage; never mutated or retained by this helper.
    ///   - channelCount: One or two first input channels, validated before engine start.
    ///   - receive: Synchronous whole-block admission; false stops processing this callback's tail.
    nonisolated private static func copyCapture(format: AVAudioFormat, frameLength: Int,
                                                buffers: UnsafeMutableAudioBufferListPointer, channelCount: Int,
                                                receive: (PCMBuffer) -> Bool) {
        guard format.sampleRate.isFinite, (8_000...192_000).contains(format.sampleRate) else { return }
        let maximumFrames = Int(format.sampleRate) * 120 / 1_000
        guard maximumFrames > 0 else { return }
        var offset = 0
        while offset < frameLength {
            let count = min(maximumFrames, frameLength - offset)
            guard let block = try? AppleAudioPCMConversion.captureBuffer(format: format, frameLength: frameLength,
                                                                        buffers: buffers, channelCount: channelCount,
                                                                        frameOffset: offset, frameCount: count),
                  receive(block) else { return }
            offset += count
        }
    }
}

/// One-slot native-event bridge; defers teardown until the native observer stack has returned.
/// Native callbacks take only the short storage lock and never wait for MainActor. The injected
/// scheduler must enqueue, rather than immediately invoke, its action on MainActor.
final class AppleAudioInvalidationBridge: Sendable {
    private struct State: Sendable {
        var generation: UUID?
        var pending: (AppleAudioStopReason, AppleAudioCallbacks)?
        var deliveryScheduled = false
    }
    private let schedule: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
    private let lock = OSAllocatedUnfairLock(initialState: State())

    /// Stores a deferred scheduler without queuing work; defaults to the main dispatch queue.
    /// - Parameter schedule: Enqueues a future MainActor action. Tests retain it until the simulated
    ///   native observer returns. At most one action is outstanding across stop/restart cycles.
    init(schedule: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void = { action in
        DispatchQueue.main.async { action() }
    }) { self.schedule = schedule }

    /// Begins a fresh observation generation while discarding any old pending event.
    /// - Returns: Opaque generation attached to every native observer installed during this start.
    func begin() -> UUID {
        let current = UUID()
        lock.withLock { state in
            state.generation = current
            state.pending = nil
        }
        return current
    }

    /// Revokes observation authority without adding another queued action or resuming the device.
    /// An already queued delivery becomes a harmless no-op unless a new generation queues an event.
    func end() {
        lock.withLock { state in
            state.generation = nil
            state.pending = nil
        }
    }

    /// Coalesces one pending event, preserving an unconditional invalidation over setup notifications.
    /// - Parameters:
    ///   - reason: Latest native reason. New current-generation reasons replace older ones, except
    ///     configurationChanged cannot overwrite a pending non-configuration invalidation. macOS
    ///     configuration callbacks may ignore benign setup readback; route/interruption/reset events
    ///     must retain their unconditional cleanup authority in either notification arrival order.
    ///   - callbacks: Current native session's MainActor invalidation callback.
    ///   - generation: Observer installation generation; stale events after restart are ignored.
    func enqueue(_ reason: AppleAudioStopReason, callbacks: AppleAudioCallbacks, generation: UUID) {
        let needsDelivery = lock.withLock { state in
            guard state.generation == generation else { return false }
            if reason == .configurationChanged, let pending = state.pending,
               pending.0 != .configurationChanged { return false }
            state.pending = (reason, callbacks)
            guard !state.deliveryScheduled else { return false }
            state.deliveryScheduled = true
            return true
        }
        guard needsDelivery else { return }
        schedule { [weak self] in self?.deliver() }
    }

    /// Releases the one scheduling slot before invoking current-generation teardown outside observers.
    /// Clearing first permits callbacks to stop/restart without retaining stale event authority.
    @MainActor private func deliver() {
        let event = lock.withLock { state in
            let event = state.pending
            state.pending = nil
            state.deliveryScheduled = false
            return event
        }
        if let event { event.1.stopped(event.0) }
    }
}

/// Native layout conversion kept internal for synthetic-buffer tests without audio device access.
enum AppleAudioPCMConversion {
    /// Copies a selected native Float32 frame range to dense normalized portable PCM.
    ///
    /// Native finite peaks are clipped; nonfinite device samples become silence. No sample-rate
    /// conversion or channel mixing occurs. The source buffer is neither retained nor mutated.
    /// - Parameters:
    ///   - buffer: Native Float32 planar/interleaved storage with at least the selected channels.
    ///   - channelCount: First one or two channels to copy, preserving their order.
    ///   - frameOffset: Nonnegative first native frame, at most frameLength.
    ///   - frameCount: Nonnegative number of complete frames within storage, at most 120ms.
    /// - Returns: Owned portable block, including an empty block for an empty valid range.
    /// - Throws: `unavailableFormat` for invalid native layout/rate/range; MediaError for oversize PCM.
    static func captureBuffer(_ buffer: AVAudioPCMBuffer, channelCount: Int,
                              frameOffset: Int, frameCount: Int) throws -> PCMBuffer {
        try captureBuffer(format: buffer.format, frameLength: Int(buffer.frameLength),
                          buffers: UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList),
                          channelCount: channelCount, frameOffset: frameOffset, frameCount: frameCount)
    }

    /// Reads callback-scoped native Float32 buffers with explicit layout and byte-bound validation.
    /// - Parameters:
    ///   - format: Native sample rate, channel count and planar/interleaved layout.
    ///   - frameLength: Number of complete input sample frames, nonnegative.
    ///   - buffers: Read-only use of callback-scoped storage; no pointer escapes this call.
    ///   - channelCount: First one or two channels copied into portable PCM.
    ///   - frameOffset: Nonnegative starting frame within frameLength.
    ///   - frameCount: Number of complete frames copied, bounded to the portable 120ms limit.
    /// - Returns: Dense normalized PCM; nonfinite native samples become silence and peaks clip.
    /// - Throws: `unavailableFormat` for invalid storage/layout/range, or MediaError for oversize PCM.
    static func captureBuffer(format native: AVAudioFormat, frameLength: Int,
                              buffers: UnsafeMutableAudioBufferListPointer, channelCount: Int,
                              frameOffset: Int, frameCount: Int) throws -> PCMBuffer {
        guard native.commonFormat == .pcmFormatFloat32,
              native.sampleRate.isFinite, (8_000...192_000).contains(native.sampleRate),
              native.sampleRate.rounded() == native.sampleRate,
              (1...2).contains(channelCount), native.channelCount >= UInt32(channelCount),
              frameLength >= 0, frameOffset >= 0, frameCount >= 0, frameOffset <= frameLength,
              frameCount <= frameLength - frameOffset,
              buffers.count >= (native.isInterleaved ? 1 : channelCount) else {
            throw AppleAudioError.unavailableFormat
        }
        let format = try PCMFormat(sampleRate: Int(native.sampleRate), channelCount: channelCount)
        guard frameCount <= format.sampleRate * 120 / 1_000 else { throw MediaError.bufferTooLarge }
        let endFrame = frameOffset + frameCount
        let neededSamples = endFrame.multipliedReportingOverflow(by: native.isInterleaved ? Int(native.channelCount) : 1)
        guard !neededSamples.overflow,
              neededSamples.partialValue <= Int.max / MemoryLayout<Float>.stride else {
            throw AppleAudioError.unavailableFormat
        }
        let neededBytes = neededSamples.partialValue * MemoryLayout<Float>.stride
        for index in 0..<(native.isInterleaved ? 1 : channelCount) {
            guard buffers[index].mData != nil, neededBytes <= Int(buffers[index].mDataByteSize) else {
                throw AppleAudioError.unavailableFormat
            }
        }
        var samples = [Float]()
        samples.reserveCapacity(frameCount * channelCount)
        for frame in frameOffset..<(frameOffset + frameCount) {
            for channel in 0..<channelCount {
                let data = buffers[native.isInterleaved ? 0 : channel].mData!.assumingMemoryBound(to: Float.self)
                let value = data[native.isInterleaved ? frame * Int(native.channelCount) + channel : frame]
                samples.append(value.isFinite ? max(-1, min(1, value)) : 0)
            }
        }
        return try PCMBuffer(format: format, samples: samples)
    }

    /// Copies portable interleaved PCM to owned native Float32 planar/interleaved storage.
    /// - Parameters:
    ///   - buffer: Immutable normalized PCM; empty buffers are supported by this pure helper.
    ///   - format: Native Float32 destination with exactly matching rate and channel count.
    /// - Returns: Owned AVAudioPCMBuffer with exact frameLength and at least one allocated frame.
    /// - Throws: `incompatibleFormat` for layout mismatch, or `nativeFailure` on allocation failure.
    static func playbackBuffer(_ buffer: PCMBuffer, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard format.commonFormat == .pcmFormatFloat32,
              format.sampleRate == Double(buffer.format.sampleRate),
              format.channelCount == UInt32(buffer.format.channelCount) else {
            throw AppleAudioError.incompatibleFormat
        }
        guard let native = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(max(1, buffer.frameCount))),
              let channels = native.floatChannelData else { throw AppleAudioError.nativeFailure }
        native.frameLength = UInt32(buffer.frameCount)
        for frame in 0..<buffer.frameCount {
            for channel in 0..<buffer.format.channelCount {
                let value = buffer.samples[frame * buffer.format.channelCount + channel]
                if format.isInterleaved { channels[0][frame * buffer.format.channelCount + channel] = value }
                else { channels[channel][frame] = value }
            }
        }
        return native
    }
}
#endif
