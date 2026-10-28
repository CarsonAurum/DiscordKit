// File: Sources/DiscordVoiceCodecs/SILKMonoPacketDecoder.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation

/// A complete ordinary mono SILK Opus packet at the mandatory 48kHz sample clock.
public struct SILKDecodedPacket: Sendable, Equatable {
    public let pcm48k: [Int16]
    public let payloads: [SILKDecodedPayload]
}

extension SILKMonoDecoder {
    /// Decodes all frame-packing forms of a structurally validated mono SILK Opus packet.
    /// - Parameter packet: An ordinary `OpusPacket` whose SILK bandwidth matches this
    ///   decoder's fixed internal rate; one through twelve 10/20/40/60ms payloads,
    ///   collectively bounded by the parser to 120ms and 48 frame ranges.
    /// - Returns: 480 through 5,760 PCM16 samples at 48kHz plus payload evidence.
    /// - Throws: `SILKMonoDecoderError.unsupportedMode`, `unsupportedChannels` or
    ///   `sampleRateMismatch` before state changes, or any payload error, including
    ///   empty DTX/loss frames requiring explicit `conceal` calls. Any failure preserves the whole decoder,
    ///   even if earlier payloads in this packet succeeded. Padding is excluded by
    ///   `OpusPacket`; rate changes, concealment and FEC selection are explicit calls.
    public mutating func decode(_ packet: OpusPacket) throws -> SILKDecodedPacket {
        guard packet.mode == .silk else { throw SILKMonoDecoderError.unsupportedMode }
        guard packet.channelCount == 1 else { throw SILKMonoDecoderError.unsupportedChannels }
        let internalRate = [8_000, 12_000, 16_000][packet.configuration / 4]
        guard internalRate == sampleRate else { throw SILKMonoDecoderError.sampleRateMismatch }
        var working = self
        var output: [Int16] = []
        var payloads: [SILKDecodedPayload] = []
        output.reserveCapacity(packet.sampleCount)
        for range in packet.frameRanges {
            let decoded = try working.decodePayload(packet.data.subdata(in: range), durationMilliseconds: packet.frameSampleCount / 48)
            output.append(contentsOf: decoded.pcm48k)
            payloads.append(decoded)
        }
        self = working
        return SILKDecodedPacket(pcm48k: output, payloads: payloads)
    }
}
