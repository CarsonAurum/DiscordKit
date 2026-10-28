// File: Sources/DiscordVoiceCodecs/SILKFrameParameterEncoder.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

/*
Copyright (c) 2006-2011, Skype Limited. All rights reserved.
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
- Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.
- Neither the name of Internet Society, IETF or IETF Trust, nor the
names of specific contributors, may be used to endorse or promote
products derived from this software without specific prior written
permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
*/


import Foundation

/// Rejections before ordinary SILK parameter indices enter a caller's range coder.
public enum SILKFrameParameterEncodingError: Error, Sendable, Equatable {
    case invalidGainIndices
    case invalidNormalizedLSFIndices
    case invalidInterpolation
    case invalidPitchIndices
    case invalidLongTermIndices
    case invalidSeed
}

/// Owned inverse of the ordinary SILK channel parameter entropy syntax.
///
/// Writes RFC 6716 sections 4.2.7.3 through 4.2.7.7 from quantized indices.
/// PCM analysis, quantization, packet/stereo flags and pulse coding are separate.
/// All category, dimension and context checks precede mutation. Calls copy the
/// supplied bounded entropy state and commit only after every symbol succeeds.
/// No native codec, shared mutable state, tasks or I/O are involved. Contexts and
/// symbol order follow libopus 1.6.1 silk/encode_indices.c (verified 2026-10-17).
public enum SILKFrameParameterEncoding {
    /// Encodes already quantized channel parameters through the two-bit excitation seed.
    /// - Parameters:
    ///   - parameters: Quantized indices produced by a decoder or owned encoder.
    ///     Reconstructed gain/LSF/pitch/tap arrays are evidence and are not encoded.
    ///     Inactive type requires a false VAD context; the other types require true.
    ///   - encoder: Active caller-owned entropy stream positioned after packet/stereo
    ///     flags. Pulse syntax and finalization remain the caller's responsibility.
    ///   - sampleRate: Internal channel rate, exactly 8,000, 12,000 or 16,000 Hz.
    ///   - frameDurationMilliseconds: Internal ten/twenty-millisecond channel frame.
    ///   - coding: Independent/conditional syntax selected by the packet owner.
    ///   - previousSignalType: Previous channel type used only by conditional voiced
    ///     pitch coding. Defaults inactive at reset; callers own this bounded history.
    ///   - previousPitchLagIndex: Previous signed primary lag, default zero. Eligible
    ///     deltas from -8 through 11 use relative syntax; other lags use absolute coding.
    /// - Throws: `SILKFrameParameterError` for unsupported rate/duration, an encoding
    ///   error for inconsistent indices, or range operation/frame/state errors. Every
    ///   failure leaves the caller's encoder unchanged. No gain history is mutated.
    /// - Complexity: O(LPC order + subframes), at most sixteen residual and four LTP
    ///   symbols. The synchronous method has no suspension or cancellation point.
    public static func encode(
        _ parameters: SILKFrameParameters,
        to encoder: inout OpusRangeEncoder,
        sampleRate: Int,
        frameDurationMilliseconds: Int,
        coding: SILKParameterCoding = .independent,
        previousSignalType: SILKSignalType = .inactive,
        previousPitchLagIndex: Int16 = 0
    ) throws {
        let format = try SILKFrameParameterDecoder(sampleRate: sampleRate, frameDurationMilliseconds: frameDurationMilliseconds)
        let subframes = format.subframeCount
        let order = format.normalizedLSFOrder
        guard parameters.gainIndices.count == subframes,
              parameters.gainIndices.enumerated().allSatisfy({ index, value in
                  (0...(index == 0 && coding != .conditional ? 63 : 40)).contains(value)
              }) else { throw SILKFrameParameterEncodingError.invalidGainIndices }
        guard (0...31).contains(parameters.normalizedLSFCodebookIndex),
              parameters.normalizedLSFResidualIndices.count == order,
              parameters.normalizedLSFResidualIndices.allSatisfy({ (-10...10).contains($0) })
        else { throw SILKFrameParameterEncodingError.invalidNormalizedLSFIndices }
        guard (0...4).contains(parameters.interpolationQ2),
              subframes == 4 || parameters.interpolationQ2 == 4
        else { throw SILKFrameParameterEncodingError.invalidInterpolation }
        guard parameters.seed < 4 else { throw SILKFrameParameterEncodingError.invalidSeed }
        let voiced = parameters.signalType == .voiced
        var relativeLag: Int?
        if voiced {
            guard let lag = parameters.pitchLagIndex, let contour = parameters.pitchContourIndex,
                  (0..<contourTable(rate: sampleRate, subframes: subframes).count).contains(contour)
            else { throw SILKFrameParameterEncodingError.invalidPitchIndices }
            let delta = Int(lag) - Int(previousPitchLagIndex)
            if coding == .conditional, previousSignalType == .voiced, (-8...11).contains(delta) {
                relativeLag = delta + 9
            } else {
                guard (0..<(32 * (sampleRate / 2_000))).contains(Int(lag))
                else { throw SILKFrameParameterEncodingError.invalidPitchIndices }
            }
            guard let periodicity = parameters.periodicityIndex, (0...2).contains(periodicity),
                  parameters.longTermGainIndices.count == subframes,
                  parameters.longTermGainIndices.allSatisfy({ (0..<(8 << periodicity)).contains($0) }),
                  let scale = parameters.longTermScaleIndex, (0...2).contains(scale),
                  coding == .independent || scale == 0
            else { throw SILKFrameParameterEncodingError.invalidLongTermIndices }
        } else {
            guard parameters.pitchLagIndex == nil, parameters.pitchContourIndex == nil,
                  parameters.periodicityIndex == nil, parameters.longTermGainIndices.isEmpty,
                  parameters.longTermScaleIndex == nil
            else { throw SILKFrameParameterEncodingError.invalidLongTermIndices }
        }
        var working = encoder
        let active = parameters.signalType != .inactive
        let type = parameters.signalType.rawValue * 2 + parameters.quantizationOffset.rawValue
        try write(type - (active ? 2 : 0), table: active ? SILKParameterTables.typeActive : SILKParameterTables.typeInactive, to: &working)
        if coding == .conditional {
            try write(parameters.gainIndices[0], table: SILKParameterTables.gainDelta, to: &working)
        } else {
            let category = parameters.signalType.rawValue * 8
            try write(parameters.gainIndices[0] >> 3, table: Array(SILKParameterTables.gain[category..<(category + 8)]), to: &working)
            try write(parameters.gainIndices[0] & 7, table: SILKParameterTables.uniform8, to: &working)
        }
        for gain in parameters.gainIndices.dropFirst() { try write(gain, table: SILKParameterTables.gainDelta, to: &working) }
        let wide = sampleRate == 16_000
        let stage1 = wide ? SILKParameterTables.wideStage1 : SILKParameterTables.narrowStage1
        let context = (parameters.signalType.rawValue >> 1) * 32
        try write(parameters.normalizedLSFCodebookIndex, table: Array(stage1[context..<(context + 32)]), to: &working)
        let selection = wide ? SILKParameterTables.wideSelection : SILKParameterTables.narrowSelection
        let stage2 = wide ? SILKParameterTables.wideStage2 : SILKParameterTables.narrowStage2
        for index in 0..<order {
            let entry = selection[parameters.normalizedLSFCodebookIndex * order / 2 + index / 2]
            let offset = ((entry >> (index & 1 == 0 ? 1 : 5)) & 7) * 9
            let residual = parameters.normalizedLSFResidualIndices[index]
            try write(min(8, max(0, residual + 4)), table: Array(stage2[offset..<(offset + 9)]), to: &working)
            if abs(residual) >= 4 { try write(abs(residual) - 4, table: SILKParameterTables.nlsfExtension, to: &working) }
        }
        if subframes == 4 { try write(parameters.interpolationQ2, table: SILKParameterTables.interpolation, to: &working) }
        if voiced {
            if coding == .conditional, previousSignalType == .voiced {
                try write(relativeLag ?? 0, table: SILKParameterTables.pitchDelta, to: &working)
            }
            if relativeLag == nil {
                let lowCount = sampleRate / 2_000
                let lag = Int(parameters.pitchLagIndex!)
                try write(lag / lowCount, table: SILKParameterTables.pitchLag, to: &working)
                let low = sampleRate == 8_000 ? SILKParameterTables.uniform4
                    : (sampleRate == 12_000 ? SILKParameterTables.uniform6 : SILKParameterTables.uniform8)
                try write(lag % lowCount, table: low, to: &working)
            }
            try write(parameters.pitchContourIndex!, table: contourTable(rate: sampleRate, subframes: subframes), to: &working)
            let periodicity = parameters.periodicityIndex!
            try write(periodicity, table: SILKParameterTables.periodicity, to: &working)
            let gains = periodicity == 0 ? SILKParameterTables.ltp0
                : (periodicity == 1 ? SILKParameterTables.ltp1 : SILKParameterTables.ltp2)
            for gain in parameters.longTermGainIndices { try write(gain, table: gains, to: &working) }
            if coding == .independent { try write(parameters.longTermScaleIndex!, table: SILKParameterTables.ltpScale, to: &working) }
        }
        try write(Int(parameters.seed), table: SILKParameterTables.uniform4, to: &working)
        encoder = working
    }

    /// Writes one bounded symbol with the exact normative 256-total frequency context.
    /// - Parameters:
    ///   - symbol: Previously validated symbol within the supplied table's dimensions.
    ///   - table: Audited nonincreasing inverse CDF terminating in zero.
    ///   - encoder: Temporary entropy copy whose mutation is committed by the caller.
    /// - Throws: Range model, operation, state or byte-budget failures.
    private static func write(_ symbol: Int, table: [Int], to encoder: inout OpusRangeEncoder) throws {
        try encoder.encodeSymbol(symbol, model: OpusProbabilityModel(inverseCDF: table.map { UInt8($0) }))
    }

    /// Chooses the finite rate/duration-specific pitch contour entropy context.
    /// - Parameters:
    ///   - rate: Validated internal channel rate in 8/12/16 kHz.
    ///   - subframes: Validated number of five-millisecond subframes, two or four.
    /// - Returns: Three/eleven NB or twelve/thirty-four MB/WB contour symbols.
    private static func contourTable(rate: Int, subframes: Int) -> [Int] {
        if rate == 8_000 { return subframes == 2 ? SILKParameterTables.contourNarrow10 : SILKParameterTables.contourNarrow20 }
        return subframes == 2 ? SILKParameterTables.contourWide10 : SILKParameterTables.contourWide20
    }
}
