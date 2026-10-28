// File: Sources/DiscordVoice/JitterBuffer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation

/// The deterministic outcome of one caller-paced playout slot.
public enum VoicePlayout: Sendable, Equatable {
    case packet(RTPPacket)
    case missing(sequence: UInt16)
}

/// A bounded, single-stream RTP reorder window with explicit missing-packet results.
///
/// The caller owns pacing and a fixed/negotiated packet duration; this type does not
/// sleep, spawn tasks, decode audio or synthesize PLC. The window is less than half
/// the RTP sequence space, making wraparound ordering unambiguous. Use only after
/// authenticating a packet. Copying this value copies its finite playout state.
public struct VoiceJitterBuffer: Sendable {
    public let capacity: Int
    public let maximumBytes: Int
    public let ssrc: UInt32
    public private(set) var nextSequence: UInt16
    public private(set) var bufferedBytes = 0
    private var packets: [UInt16: RTPPacket] = [:]

    /// Establishes a bounded stream without starting playout or accepting packets.
    /// - Parameters:
    ///   - ssrc: The sole accepted RTP stream. Route distinct participants separately.
    ///   - nextSequence: Expected first packet, including a caller-selected initial delay.
    ///   - capacity: Maximum forward sequence distance plus one, in `1...32767`.
    ///   - maximumBytes: Positive retained serialized-packet byte budget; default 256 KiB.
    /// - Throws: `VoicePacketError.invalidConfiguration` for invalid bounds.
    public init(ssrc: UInt32, nextSequence: UInt16, capacity: Int = 64, maximumBytes: Int = 262_144) throws {
        guard (1...32_767).contains(capacity), maximumBytes > 0 else { throw VoicePacketError.invalidConfiguration }
        self.ssrc = ssrc
        self.nextSequence = nextSequence
        self.capacity = capacity
        self.maximumBytes = maximumBytes
    }

    /// Inserts an already authenticated packet without displacing retained packets.
    /// - Parameter packet: Expected SSRC and sequence within the forward window.
    /// - Throws: `VoicePacketError.wrongStream`, `.duplicateOrLate` or `.capacityExceeded`.
    ///   Failure leaves the window unchanged. Bytes include full plaintext RTP overhead.
    public mutating func insert(_ packet: RTPPacket) throws {
        guard packet.ssrc == ssrc else { throw VoicePacketError.wrongStream }
        let distance = Int(packet.sequence &- nextSequence)
        guard distance < 32_768, packets[packet.sequence] == nil else { throw VoicePacketError.duplicateOrLate }
        let bytes = packet.serialized().count
        guard distance < capacity, bytes <= maximumBytes - bufferedBytes else { throw VoicePacketError.capacityExceeded }
        packets[packet.sequence] = packet
        bufferedBytes += bytes
    }

    /// Advances exactly one playout slot, even when its packet has not arrived.
    /// - Returns: The retained packet or an explicit sequence gap. Late arrivals for
    ///   an emitted gap are rejected; sequence 65,535 wraps to zero.
    public mutating func pop() -> VoicePlayout {
        let sequence = nextSequence
        nextSequence &+= 1
        if let packet = packets.removeValue(forKey: sequence) {
            bufferedBytes -= packet.serialized().count
            return .packet(packet)
        }
        return .missing(sequence: sequence)
    }

    /// Examines the expected authenticated packet without advancing its sequence slot.
    /// - Returns: The packet at `nextSequence`, or nil when that sequence has not arrived.
    ///   Future packets remain retained. A media scheduler can compare RTP timestamps and
    ///   fill a DTX interval before consuming its next transmitted packet. No state changes,
    ///   asynchronous work or payload copies occur; lookup is bounded by the finite window.
    public func peek() -> RTPPacket? {
        packets[nextSequence]
    }

    /// Releases all retained media and optionally reanchors sequence ordering.
    /// - Parameter nextSequence: New expected sequence, or nil to retain the current cursor.
    ///   This is a local stream reset; it must not reset cryptographic replay/nonce state.
    public mutating func reset(nextSequence: UInt16? = nil) {
        packets.removeAll(keepingCapacity: false)
        bufferedBytes = 0
        if let nextSequence { self.nextSequence = nextSequence }
    }
}
