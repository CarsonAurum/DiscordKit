// File: Sources/DiscordVoice/OpusRTPPacketizer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import DiscordVoiceCodecs

/// Deterministic encoded-Opus RTP packetizer; does not encode, encrypt, pace or send.
///
/// A session owns one instance for its SSRC. Cryptographic counters belong to a
/// separate noncopyable/actor authority and must never derive from RTP rollover.
/// Silence termination is explicit: send five `silencePacket()` results through
/// the same E2EE and transport paths before clearing the speaking state.
public struct OpusRTPPacketizer: Sendable {
    public let ssrc: UInt32
    public private(set) var nextSequence: UInt16
    public private(set) var nextTimestamp: UInt32

    /// Stores a stream's initial RTP counters without network work.
    /// - Parameters:
    ///   - ssrc: Value assigned by Voice Ready.
    ///   - sequence: Initial sixteen-bit packet sequence; callers may randomize it.
    ///   - timestamp: Initial media timestamp at 48,000 ticks per second.
    public init(ssrc: UInt32, sequence: UInt16 = 0, timestamp: UInt32 = 0) {
        self.ssrc = ssrc
        self.nextSequence = sequence
        self.nextTimestamp = timestamp
    }

    /// Validates an encoded Opus packet and advances RTP state only on success.
    /// - Parameters:
    ///   - opus: Complete RFC 6716 packet, including its TOC and packed frames.
    ///   - marker: Explicit RTP marker bit, false by default; no talkspurt policy is inferred.
    /// - Returns: Plaintext payload-type-120 RTP packet with the current counters.
    ///   Sequence advances by one and timestamp by the parsed per-channel sample
    ///   count. Both wrap with their unsigned RTP widths.
    /// - Throws: Opus parsing errors or `VoicePacketError.packetTooLarge`. Failure
    ///   preserves both counters. E2EE must transform the encoded payload before transmission.
    public mutating func packetize(_ opus: Data, marker: Bool = false) throws -> RTPPacket {
        let parsed = try OpusPacket(opus)
        let packet = try RTPPacket(marker: marker, sequence: nextSequence, timestamp: nextTimestamp, ssrc: ssrc, payload: opus)
        nextSequence &+= 1
        nextTimestamp &+= UInt32(parsed.sampleCount)
        return packet
    }

    /// Emits one documented 20 ms Opus silence packet while advancing ordinary counters.
    /// - Returns: RTP wrapping `F8 FF FE`, the Discord termination-silence payload.
    /// - Throws: Packetization errors; the fixed valid packet fits all local limits.
    ///   Call five times before stopping, then protect/send each packet normally.
    public mutating func silencePacket() throws -> RTPPacket {
        try packetize(Data([0xf8, 0xff, 0xfe]))
    }
}
