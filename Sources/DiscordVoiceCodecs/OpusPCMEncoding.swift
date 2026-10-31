// File: Sources/DiscordVoiceCodecs/OpusPCMEncoding.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

/// A synchronous, exclusively owned fixed-format 48-kHz PCM-to-Opus encoder.
///
/// Implementations accept normalized interleaved Float samples for one stream and
/// retain their own bounded codec history. Callers serialize all mutation, including
/// reset; a reference-backed implementation must never be shared between pipelines.
/// Construction and encoding perform no network or device I/O and create no tasks.
/// Native implementations own their codec allocation until deinitialization.
///
/// ``OpusAudioEncoder`` supplies the default owned Swift implementation. An application
/// may inject a platform implementation into its Voice session without changing RTP,
/// pacing, E2EE, transport encryption, authorization or joined playback ownership.
public protocol OpusPCMEncoding: Sendable {
    /// Fixed samples per channel at 48 kHz, exactly 120, 240, 480 or 960.
    var frameSampleCount: Int {
        /// Returns this stream's immutable 48-kHz samples per channel without advancing codec state.
        get
    }
    /// Fixed interleaved input and encoded packet channel count, one or two.
    var channelCount: Int {
        /// Returns this stream's immutable interleaved layout without advancing codec state.
        get
    }

    /// Encodes one exact fixed-format normalized PCM frame without suspension.
    /// - Parameter samples: Exactly `frameSampleCount * channelCount` finite samples
    ///   in `-1...1`, interleaved by channel. Input storage is not retained.
    /// - Returns: One complete ordinary Opus packet whose parsed 48-kHz duration and
    ///   channels match this encoder, with a complete byte budget through 1,276 bytes.
    ///   A suppressed DTX interval sets `shouldTransmit` false and `isDTX` true;
    ///   its nonempty data may contain only the matching TOC byte.
    /// - Throws: Invalid PCM, codec or byte-budget failures. Implementations describe
    ///   their failure-state guarantees; callers must never replay failed media.
    mutating func encode(_ samples: [Float]) throws -> OpusAudioEncodedPacket

    /// Discards stream history while retaining the immutable format and bitrate policy.
    /// The caller exclusively owns mutation. This synchronous operation performs no
    /// I/O and starts no tasks; it is used when the owning media pipeline closes.
    mutating func reset()
}
