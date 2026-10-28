// File: Sources/DiscordVoiceCodecs/SILKStereoEncoder.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation

/// A conservative stereo SILK frame before Opus framing or optional hybrid CELT.
public struct SILKStereoEncodedPayload: Sendable, Equatable {
    public let mid: SILKEncodedPayload
    public let side: SILKEncodedPayload
    public let finalRange: UInt32
    public let bitsUsed: Int
}

/// One ordinary stereo SILK code-zero packet and its independent channel evidence.
public struct SILKStereoEncodedPacket: Sendable, Equatable {
    public let packet: OpusPacket
    public let payload: SILKStereoEncodedPayload
}

/// Conservative stereo PCM16 encoder using owned independent mid/side SILK streams.
///
/// Converts interleaved left/right into half-sum/half-difference PCM, quantizes both
/// with `SILKMonoEncoder`, and emits ordinary adaptive-stereo syntax with exactly zero
/// predictors and an always-present side. Every packet is ten/twenty milliseconds,
/// with real independently analyzed pitch/LTP and optional active-channel LBRR,
/// without DTX, perceptual delayed-
/// decision shaping or reference-quality equivalence.
/// Fixed zero predictors avoid stereo-adaptation interpolation while retaining real
/// independent channel content. Exact decoder alignment/resampling remains separate.
/// Construction starts no tasks or I/O and links no native codec. Caller-serialized
/// mutations commit both channel histories and shared entropy only on full success.
public struct SILKStereoEncoder: Sendable {
    public let sampleRate: Int
    public let frameDurationMilliseconds: Int
    public let maximumPayloadBytes: Int
    /// Retains and transmits each preceding active channel as next-packet SILK LBRR.
    public let enableInBandFEC: Bool
    /// Required interleaved left/right input values, twice the per-channel frame count.
    public var sampleCount: Int { sampleRate * frameDurationMilliseconds / 1_000 * 2 }
    private var mid: SILKMonoEncoder
    private var side: SILKMonoEncoder
    private static let predictorCDF: [UInt8] = [
        249, 247, 246, 245, 244, 234, 210, 202, 201, 200, 197, 174, 82,
        59, 56, 55, 54, 46, 22, 12, 11, 10, 9, 7, 0
    ]

    /// Initializes two independent fixed-format conservative synthesis/analysis streams.
    /// - Parameters:
    ///   - sampleRate: Exactly 8,000, 12,000 or 16,000 Hz per input channel.
    ///   - frameDurationMilliseconds: Exactly ten/twenty milliseconds, default twenty.
    ///   - maximumPayloadBytes: Shared compressed payload cap in `32...1275`, default
    ///     1,275. Tight caps may reject frames if neither channel can fit its allocation.
    ///   - enableInBandFEC: Default false. True carries the preceding active mid
    ///     and/or side channel as ordinary LBRR, preserving the shared finite budget.
    ///     Tight budgets reject atomically rather than silently omitting redundancy.
    /// - Throws: Rate/duration errors from `SILKFrameParameterError`,
    ///   `SILKMonoEncoderError.invalidPayloadByteLimit`, or audited table/range errors.
    ///   No browser, device, network or native codec work is started.
    public init(sampleRate: Int, frameDurationMilliseconds: Int = 20, maximumPayloadBytes: Int = 1_275, enableInBandFEC: Bool = false) throws {
        mid = try SILKMonoEncoder(sampleRate: sampleRate, frameDurationMilliseconds: frameDurationMilliseconds, enableInBandFEC: enableInBandFEC)
        side = mid
        guard (32...1_275).contains(maximumPayloadBytes) else { throw SILKMonoEncoderError.invalidPayloadByteLimit }
        self.sampleRate = sampleRate
        self.frameDurationMilliseconds = frameDurationMilliseconds
        self.maximumPayloadBytes = maximumPayloadBytes
        self.enableInBandFEC = enableInBandFEC
    }

    /// Clears both bounded channel histories without changing format or cached tables.
    /// This idempotent operation starts no external work and preserves existing outputs.
    public mutating func reset() {
        mid.reset()
        side.reset()
    }

    /// Encodes one interleaved stereo PCM16 frame as a complete ordinary SILK packet.
    /// - Parameter pcm: Exactly `sampleCount` left/right values at the internal sample rate.
    /// - Returns: One code-zero stereo Opus packet within the configured byte cap and
    ///   the exact reconstructed mid/side channel evidence used by ordinary decoders.
    /// - Throws: `SILKMonoEncoderError` for input/budget admission, or range/table/framing
    ///   errors. Both stream histories remain unchanged unless the whole packet succeeds.
    public mutating func encode(_ pcm: [Int16]) throws -> SILKStereoEncodedPacket {
        var working = self
        var sizing = try OpusRangeEncoder(frameByteCount: maximumPayloadBytes)
        let encoded = try working.encodePayload(pcm, to: &sizing)
        var entropy = try OpusRangeEncoder(frameByteCount: max(1, (sizing.bitsUsed + 7) / 8))
        try write(encoded.mid, side: encoded.side, to: &entropy)
        let bytes = try entropy.finalize()
        let bandwidth = sampleRate == 8_000 ? 0 : (sampleRate == 12_000 ? 4 : 8)
        let configuration = bandwidth + (frameDurationMilliseconds == 10 ? 0 : 1)
        let packet = try OpusPacket(Data([UInt8(configuration << 3) | 4]) + bytes)
        self = working
        return SILKStereoEncodedPacket(packet: packet, payload: encoded)
    }

    /// Appends a stereo SILK frame to a caller-owned shared entropy stream.
    /// - Parameters:
    ///   - pcm: Exactly `sampleCount` interleaved PCM16 values. Half sums/differences
    ///     truncate toward zero before quantization, with bounded 32-bit intermediates.
    ///   - encoder: Active shared stream; finalization and correct mode composition
    ///     belong to its owner, permitting subsequent hybrid CELT symbols/raw bits.
    ///   - maximumBits: Optional total bit-use ceiling after SILK, including prefixes.
    ///     Defaults to the smaller of the shared frame bytes and this encoder's cap.
    /// - Returns: Both independently reconstructed channels and shared entropy endpoint.
    /// - Throws: `SILKMonoEncoderError.invalidSampleCount`, `invalidPayloadBitLimit`,
    ///   `payloadBudgetExceeded` or range/table errors. Both channels and caller entropy
    ///   are preserved on every failure. Work/storage remain bounded by two mono frames;
    ///   no asynchronous work, device access, native linkage or external I/O occurs.
    public mutating func encodePayload(
        _ pcm: [Int16], to encoder: inout OpusRangeEncoder, maximumBits: Int? = nil
    ) throws -> SILKStereoEncodedPayload {
        guard pcm.count == sampleCount else { throw SILKMonoEncoderError.invalidSampleCount }
        let fullBudget = min(encoder.frameByteCount, maximumPayloadBytes) * 8
        let limit = maximumBits ?? fullBudget
        guard fullBudget > 0, limit > 0, limit <= fullBudget
        else { throw SILKMonoEncoderError.invalidPayloadBitLimit }
        let channelBits = (limit - encoder.bitsUsed - (enableInBandFEC ? 64 : 32)) / 2
        guard channelBits > 0 else { throw SILKMonoEncoderError.payloadBudgetExceeded }
        var middle: [Int16] = []
        var difference: [Int16] = []
        middle.reserveCapacity(pcm.count / 2)
        difference.reserveCapacity(pcm.count / 2)
        for index in stride(from: 0, to: pcm.count, by: 2) {
            middle.append(Int16((Int32(pcm[index]) + Int32(pcm[index + 1])) / 2))
            difference.append(Int16((Int32(pcm[index]) - Int32(pcm[index + 1])) / 2))
        }
        var working = self
        var midEntropy = try OpusRangeEncoder(frameByteCount: (channelBits + 7) / 8)
        var sideEntropy = midEntropy
        let encodedMid = try working.mid.encodePayload(middle, to: &midEntropy, maximumBits: channelBits)
        let encodedSide = try working.side.encodePayload(difference, to: &sideEntropy, maximumBits: channelBits)
        var entropy = encoder
        try write(encodedMid, side: encodedSide, to: &entropy)
        guard entropy.bitsUsed <= limit else { throw SILKMonoEncoderError.payloadBudgetExceeded }
        let result = SILKStereoEncodedPayload(mid: encodedMid, side: encodedSide, finalRange: entropy.finalRange, bitsUsed: entropy.bitsUsed)
        encoder = entropy
        self = working
        return result
    }

    /// Writes shared channel flags, zero stereo predictors and two complete channel frames.
    /// - Parameters:
    ///   - mid: Independently quantized mid channel with exact parameter/pulse evidence.
    ///   - side: Independently quantized side, always transmitted even when inactive.
    ///   - encoder: Temporary caller stream receiving ordinary normative stereo syntax.
    /// - Throws: Range/model/parameter/pulse errors; the caller owns atomic commit.
    ///   Joint predictor twelve, both coarse symbols one and fine symbols two reconstruct
    ///   both original Q13 predictors to zero, using the normative -820/+820 interval.
    private func write(_ mid: SILKEncodedPayload, side: SILKEncodedPayload, to encoder: inout OpusRangeEncoder) throws {
        for channel in [mid, side] {
            try encoder.encodeBit(channel.parameters.signalType != .inactive, logProbability: 1)
            try encoder.encodeBit(channel.redundancy != nil, logProbability: 1)
        }
        if let redundant = mid.redundancy {
            try writePredictors(midOnly: side.redundancy == nil ? true : nil, to: &encoder)
            try writeChannel(redundant.parameters, pulses: redundant.signedPulses, to: &encoder)
        }
        if let redundant = side.redundancy {
            try writeChannel(redundant.parameters, pulses: redundant.signedPulses, to: &encoder)
        }
        try writePredictors(midOnly: side.parameters.signalType == .inactive ? false : nil, to: &encoder)
        for channel in [mid, side] {
            try writeChannel(channel.parameters, pulses: channel.signedPulses, to: &encoder)
        }
    }

    /// Emits the normative exact-zero stereo predictors and optional mid-only flag.
    /// - Parameters:
    ///   - midOnly: Nil when the channel flags imply a present active side and omit
    ///     this symbol. Otherwise false transmits a side or true omits a redundant
    ///     inactive/missing side. Both predictor interpolation endpoints are zero.
    ///   - encoder: Private bounded entropy state, owned atomically by the caller.
    /// - Throws: Model/range/operation/budget errors without committing stream history.
    private func writePredictors(midOnly: Bool?, to encoder: inout OpusRangeEncoder) throws {
        try encoder.encodeSymbol(12, model: OpusProbabilityModel(inverseCDF: Self.predictorCDF))
        for _ in 0..<2 {
            try encoder.encodeSymbol(1, model: OpusProbabilityModel(inverseCDF: [171, 85, 0]))
            try encoder.encodeSymbol(2, model: OpusProbabilityModel(inverseCDF: [205, 154, 102, 51, 0]))
        }
        if let midOnly { try encoder.encodeSymbol(midOnly ? 1 : 0, model: OpusProbabilityModel(inverseCDF: [64, 0])) }
    }

    /// Emits one independent normal or redundant channel without packet/stereo flags.
    /// - Parameters:
    ///   - parameters: Exact valid decoded indices matching this fixed stream format.
    ///   - pulses: One internal frame's bounded signed excitation pulse sequence.
    ///   - encoder: Caller-owned private bounded range state positioned for the channel.
    /// - Throws: Parameter/pulse/model/range/budget errors; no history is mutated here.
    private func writeChannel(_ parameters: SILKFrameParameters, pulses: [Int16], to encoder: inout OpusRangeEncoder) throws {
        try SILKFrameParameterEncoding.encode(
            parameters, to: &encoder, sampleRate: sampleRate,
            frameDurationMilliseconds: frameDurationMilliseconds
        )
        try SILKPulseCoding.encode(
            pulses, to: &encoder, signalType: parameters.signalType,
            quantizationOffset: parameters.quantizationOffset
        )
    }
}
