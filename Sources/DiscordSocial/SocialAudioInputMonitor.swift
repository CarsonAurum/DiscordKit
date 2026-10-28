// File: Sources/DiscordSocial/SocialAudioInputMonitor.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordMedia
import Foundation

/// Constant-size local microphone-detection state; it contains no samples or device identifiers.
public struct SocialAudioInputSnapshot: Sendable, Equatable {
    public let thresholdDBFS: Double
    public let enabled: Bool
    public let inputDetected: Bool?
    public let closed: Bool
}

/// Owned local no-audio-input threshold and transition delivery over application-routed microphone PCM.
///
/// The published Social threshold range is `-100...100` dBFS; `-100` disables detection.
/// This implementation uses RMS across each complete input block and all interleaved channels.
/// Discord does not publish the native engine's analysis window/hysteresis, so identical native
/// detector timing is not claimed. The embedding application routes raw microphone PCM before
/// intentional application mute/deafen to diagnose capture; processing muted PCM diagnoses that
/// supplied stream instead. There are no devices, sockets, timers, tasks or retained PCM buffers.
///
/// Reference verified 2026-10-18:
/// https://docs.discord.com/developers/discord-social-sdk/development-guides/managing-voice-chat#detecting-no-audio-input.
public actor SocialAudioInputMonitor {
    private var thresholdDBFS: Double
    private var thresholdAmplitude: Double
    private var inputDetected: Bool?
    private var callback: (@Sendable (Bool) -> Void)?
    private var closed = false

    /// Validates the threshold and stores one optional transition observer without starting work.
    /// - Parameters:
    ///   - thresholdDBFS: Finite inclusive `-100...100` dBFS threshold; default `-100` disables detection.
    ///     Normalized PCM cannot exceed 0 dBFS, so positive thresholds classify every nonempty block as silent.
    ///   - callback: Optional synchronous transition observer, nil by default. Must not block; it executes
    ///     on this actor after state changes, never on a promised audio/UI executor. It receives no initial event.
    /// - Throws: `MediaError.invalidThreshold` for nonfinite or out-of-range thresholds.
    public init(thresholdDBFS: Double = -100, callback: (@Sendable (Bool) -> Void)? = nil) throws {
        guard thresholdDBFS.isFinite, (-100...100).contains(thresholdDBFS) else { throw MediaError.invalidThreshold }
        self.thresholdDBFS = thresholdDBFS
        self.thresholdAmplitude = pow(10, thresholdDBFS / 20)
        self.callback = callback
    }

    /// Replaces the local threshold atomically without inspecting devices or emitting a synthetic transition.
    /// - Parameter thresholdDBFS: Finite inclusive `-100...100` dBFS; `-100` disables detection.
    ///   An actual threshold change erases the old baseline; setting the same threshold preserves it.
    /// - Throws: `MediaError.closed` after terminal close or `invalidThreshold` for invalid input.
    /// Validation occurs before state changes, so a failed update preserves the previous detector state.
    public func setThreshold(_ thresholdDBFS: Double) throws {
        guard !closed else { throw MediaError.closed }
        guard thresholdDBFS.isFinite, (-100...100).contains(thresholdDBFS) else { throw MediaError.invalidThreshold }
        guard self.thresholdDBFS != thresholdDBFS else { return }
        self.thresholdDBFS = thresholdDBFS
        thresholdAmplitude = pow(10, thresholdDBFS / 20)
        inputDetected = nil
    }

    /// Replaces or removes the sole transition observer without resetting detection or replaying old state.
    /// - Parameter callback: Optional synchronous Sendable observer. Nil unregisters it; repeated registrations
    ///   replace rather than append. It must not block and receives only later threshold crossings.
    /// - Throws: `MediaError.closed` after terminal close. The monitor retains at most one callback closure;
    ///   the application owns any values captured by that closure and should avoid strong ownership cycles.
    public func setCallback(_ callback: (@Sendable (Bool) -> Void)?) throws {
        guard !closed else { throw MediaError.closed }
        self.callback = callback
    }

    /// Classifies one complete normalized microphone block and emits only changes from an established baseline.
    /// - Parameter buffer: Validated mono/stereo PCM of at most 120 ms. Empty input has no observation and
    ///   never changes the baseline. RMS averages the squared magnitudes across all interleaved samples,
    ///   so opposite stereo polarities do not cancel. Equality to the threshold counts as detected input.
    /// - Returns: New boolean only when an established detection state changes; nil when disabled, empty,
    ///   establishing the first nonempty baseline, or unchanged. Use `snapshot()` to read the baseline itself.
    /// - Throws: `MediaError.closed` after terminal close. The input already validates finite normalized samples.
    /// Work is synchronous and linear in the bounded sample count, with constant retained state and no
    /// scratch/sample allocations. State updates precede the optional callback, invoked exactly once inline.
    /// Actor admission is atomic; there is no suspension or cancellation checkpoint during processing.
    public func process(_ buffer: PCMBuffer) throws -> Bool? {
        guard !closed else { throw MediaError.closed }
        guard thresholdDBFS > -100, !buffer.samples.isEmpty else { return nil }
        var sum: Double = 0
        for sample in buffer.samples {
            let value = Double(sample)
            sum += value * value
        }
        let detected = sqrt(sum / Double(buffer.samples.count)) >= thresholdAmplitude
        let previous = inputDetected
        inputDetected = detected
        guard let previous, previous != detected else { return nil }
        callback?(detected)
        return detected
    }

    /// Reads the constant-size detector state without deriving remote microphone/device health.
    /// - Returns: Configured threshold, current enabled flag, optional baseline and terminal closure flag.
    /// The baseline is nil before the first nonempty enabled block, after a threshold change or after close.
    public func snapshot() -> SocialAudioInputSnapshot {
        SocialAudioInputSnapshot(thresholdDBFS: thresholdDBFS, enabled: !closed && thresholdDBFS > -100,
                                 inputDetected: inputDetected, closed: closed)
    }

    /// Permanently disables observations and releases callback/baseline ownership; repeated calls are harmless.
    /// Application-owned capture devices, buffers and remote calls remain independently owned.
    public func close() {
        closed = true; callback = nil; inputDetected = nil
    }
}
