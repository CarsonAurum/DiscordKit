import DiscordMedia

/// Local PCM controls; these values never mutate a Discord account or remote call.
public struct SocialAudioSettings: Sendable, Equatable {
    public let muted: Bool
    public let deafened: Bool
    public let inputGain: Float
    public let outputGain: Float

    /// Validates finite local gains and stores explicit capture/playback suppression.
    /// - Parameters:
    ///   - muted: Suppresses captured PCM; defaults to false.
    ///   - deafened: Suppresses playback and capture, matching local deafen-implies-mute policy.
    ///   - inputGain: Linear capture multiplier in `0...4`, default 1.
    ///   - outputGain: Linear playback multiplier in `0...4`, default 1.
    /// - Throws: `MediaError.invalidGain` for nonfinite or out-of-range multipliers.
    public init(muted: Bool = false, deafened: Bool = false,
                inputGain: Float = 1, outputGain: Float = 1) throws {
        guard inputGain.isFinite, outputGain.isFinite,
              (0...4).contains(inputGain), (0...4).contains(outputGain) else {
            throw MediaError.invalidGain
        }
        self.muted = muted; self.deafened = deafened
        self.inputGain = inputGain; self.outputGain = outputGain
    }
}

/// Bounded independently adopted local media provider with global and per-call controls.
///
/// Call identifiers are application-owned routing keys, not negotiated Discord lobby
/// or voice-session IDs. The application routes each source/sink through this actor.
/// It owns no buffers, devices, network calls, timers or tasks. There is no echo/noise
/// processing or proprietary engine. Synchronous actor operations are atomic and do
/// not observe task cancellation after admission. Input/output channels/timing survive.
public actor SocialAudioControls {
    private var global: SocialAudioSettings
    private var calls: [UInt64: SocialAudioSettings] = [:]
    private let maximumCalls: Int
    private var closed = false

    /// Creates an inert local provider with neutral global controls and a fixed call cap.
    /// - Parameter maximumCalls: Positive retained-call limit in `1...1024`, default 16.
    /// - Throws: `SocialFailure.invalidConfiguration` outside the supported count range.
    public init(maximumCalls: Int = 16) throws {
        guard (1...1024).contains(maximumCalls) else { throw SocialFailure.invalidConfiguration }
        self.maximumCalls = maximumCalls
        self.global = try SocialAudioSettings()
    }

    /// Atomically replaces global controls without changing per-call settings.
    /// - Parameter settings: Validated gains and suppression policy.
    /// - Throws: `SocialFailure.closed` after permanent closure.
    public func setGlobal(_ settings: SocialAudioSettings) throws {
        guard !closed else { throw SocialFailure.closed }
        global = settings
    }

    /// Reads the active local global settings without querying Discord or a device.
    /// - Returns: Current immutable mute/deafen and linear gain settings.
    /// - Throws: `SocialFailure.closed` after permanent closure.
    public func globalSettings() throws -> SocialAudioSettings {
        guard !closed else { throw SocialFailure.closed }
        return global
    }

    /// Reads one route's local settings without applying global composition or doing I/O.
    /// - Parameter id: Previously registered nonzero application-owned call key.
    /// - Returns: Immutable per-call controls; global controls remain independently inspectable.
    /// - Throws: Closed or missingProvider for an unregistered route.
    public func callSettings(_ id: UInt64) throws -> SocialAudioSettings { try require(id) }

    /// Registers or replaces one local call's independent controls with fail-fast bounds.
    /// - Parameters:
    ///   - id: Nonzero application-owned route key; zero is rejected.
    ///   - settings: Validated controls. Replacement at capacity remains permitted.
    /// - Throws: Closed, invalid identifier, or overloaded without partially retaining data.
    public func setCall(_ id: UInt64, settings: SocialAudioSettings) throws {
        guard !closed else { throw SocialFailure.closed }
        guard id != 0 else { throw SocialFailure.invalidConfiguration }
        guard calls[id] != nil || calls.count < maximumCalls else { throw SocialFailure.overloaded }
        calls[id] = settings
    }

    /// Erases one route's settings; repeated or unknown removals are harmless.
    /// - Parameter id: Application-owned route key. No network leave operation occurs.
    public func removeCall(_ id: UInt64) { calls[id] = nil }

    /// Applies global and per-call capture policy before the application encodes/transmits PCM.
    /// - Parameters:
    ///   - buffer: Validated bounded normalized PCM, including empty blocks.
    ///   - callID: A previously registered local route; missing routes fail closed.
    /// - Returns: Same-layout PCM, muted for either mute/deafen flag; otherwise gain is
    ///   multiplied once then clipped to `-1...1` by the owned media primitive.
    /// - Throws: Closed or missing route. No PCM is retained after the call returns.
    public func capture(_ buffer: PCMBuffer, callID: UInt64) throws -> PCMBuffer {
        let settings = try require(callID)
        let gain: Float = global.muted || global.deafened || settings.muted || settings.deafened
            ? 0 : global.inputGain * settings.inputGain
        return try buffer.applyingGain(gain)
    }

    /// Applies global and per-call playback policy before the application writes to a sink.
    /// - Parameters:
    ///   - buffer: Validated bounded PCM with its original format and duration.
    ///   - callID: Previously registered local route.
    /// - Returns: Silence for either deafen flag; otherwise clipped combined output gain.
    ///   Capture mute alone deliberately leaves received audio audible.
    /// - Throws: Closed or missing route; no device or sink I/O is performed.
    public func playback(_ buffer: PCMBuffer, callID: UInt64) throws -> PCMBuffer {
        let settings = try require(callID)
        let gain: Float = global.deafened || settings.deafened ? 0 : global.outputGain * settings.outputGain
        return try buffer.applyingGain(gain)
    }

    /// Permanently closes local processing and releases every retained call identifier.
    /// Repeated calls are harmless; application-owned devices and remote calls are unaffected.
    public func close() { closed = true; calls.removeAll(keepingCapacity: false) }

    /// Reads the exact bounded count without exposing route identifiers or samples.
    /// - Returns: Retained local calls, zero after close.
    public func retainedCalls() -> Int { calls.count }

    /// Requires an active explicitly registered route; absence never bypasses mute policy.
    /// - Parameter id: Application-owned route key.
    /// - Returns: Current immutable local settings.
    /// - Throws: Closed or missingProvider for an unregistered route.
    private func require(_ id: UInt64) throws -> SocialAudioSettings {
        guard !closed else { throw SocialFailure.closed }
        guard let settings = calls[id] else { throw SocialFailure.missingProvider }
        return settings
    }
}
