// File: Sources/DiscordVoiceCodecs/SILKPulseCoding.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

/// Rejections from independently adopted RFC 6716 SILK pulse entropy syntax.
public enum SILKPulseCodingError: Error, Sendable, Equatable {
    case invalidSampleCount
    case invalidRateLevel
    case pulseMagnitudeExceeded
}

/// One decoded SILK excitation pulse frame, before gain, LPC or LTP synthesis.
///
/// This is RFC 6716 section 4.2.7.8 syntax, not a complete SILK audio frame. The
/// caller must first decode the enclosing frame parameters and position the range
/// coder at the rate-level symbol. State and all retained arrays are bounded to
/// twenty shell blocks, 320 output samples and eight discarded padding samples.
public struct SILKPulseFrame: Sendable, Equatable {
    /// Category supplied by the enclosing SILK frame's previously decoded type.
    public let signalType: SILKSignalType
    /// Offset category supplied by the enclosing SILK frame, also selecting signs.
    public let quantizationOffset: SILKQuantizationOffset
    /// Decoded Table 45 rate-level index, in `0...8`.
    public let rateLevel: Int
    /// Final signed pulses in sample order, excluding mediumband padding.
    public let signedPulses: [Int16]
    /// Eight parsed but inaudible samples for 10 ms mediumband, otherwise empty.
    /// An encoder can legally place nonzero pulses here; decoding still consumes them.
    public let discardedPadding: [Int16]
    /// The final shell count in `0...16` for each 16-sample block, before LSBs.
    public let shellPulseCounts: [Int]
    /// Number of restored low-order magnitude bits per shell block, in `0...10`.
    public let leastSignificantBitCounts: [Int]

    /// Converts these decoded signed pulses into exact frame-seeded Q23 excitation.
    /// - Parameter seed: The enclosing SILK frame's two-bit seed, in `0...3`.
    /// - Returns: One signed Q23 residual per output pulse. Padding never contributes
    ///   to the random sequence, matching SILK frame reconstruction.
    /// - Throws: `SILKExcitationError.invalidSeed` above three. All frame lengths
    ///   satisfy the excitation primitive's bound. This method changes no frame state.
    public func reconstructExcitation(seed: UInt8) throws -> [Int32] {
        var reconstructor = try SILKExcitationReconstructor(
            seed: seed, signalType: signalType, quantizationOffset: quantizationOffset
        )
        return try reconstructor.reconstruct(signedPulses)
    }
}

/// Owned bounded SILK pulse entropy encoding and decoding, RFC 6716 section 4.2.7.8.
///
/// Implements rate selection, pulse-count escapes, recursive shell splits, arithmetic
/// LSBs and contextual signs. This layer composes with an existing Opus range coder:
/// it emits no Opus TOC, frame parameters, LPC/NLSF, gains, redundancy, FEC or PCM.
/// It performs no I/O, uses no native codec and starts no tasks. Every operation
/// copies the caller's bounded coder and commits only on complete success. A failed
/// call therefore preserves its caller's entropy state, including operation counters.
public enum SILKPulseCoding {
    /// Decodes one 10 ms or 20 ms internal SILK channel's excitation pulse syntax.
    /// - Parameters:
    ///   - decoder: Range coder positioned at this channel frame's rate-level symbol.
    ///     Successful decoding advances it past all signs, including padding signs.
    ///   - sampleCount: Exactly 80, 120, 160, 240 or 320, covering all NB/MB/WB
    ///     10/20 ms combinations. Longer packets contain independently coded frames.
    ///   - signalType: Previously decoded frame type selecting rate/sign contexts.
    ///   - quantizationOffset: Previously decoded offset category selecting signs.
    /// - Returns: Owned signed pulses, shell metadata and any discarded MB padding.
    /// - Throws: `invalidSampleCount` before entropy reading; range-coder operation
    ///   or state errors. Normative zero extension remains permitted: this primitive
    ///   does not authenticate compressed data or reliably identify truncation.
    /// - Complexity: O(samples * 10) bounded work and O(samples) temporary storage;
    ///   at most ten LSB escapes per block and four shell recursion levels.
    public static func decode(
        from decoder: inout OpusRangeDecoder,
        sampleCount: Int,
        signalType: SILKSignalType,
        quantizationOffset: SILKQuantizationOffset
    ) throws -> SILKPulseFrame {
        try validateSampleCount(sampleCount)
        var working = decoder
        let rate = try working.decodeSymbol(model: model(SILKPulseTables.rate[signalType.rawValue >> 1]))
        let blocks = (sampleCount + 15) / 16
        var counts = Array(repeating: 0, count: blocks)
        var shifts = counts
        for block in 0..<blocks {
            var count = try working.decodeSymbol(model: model(SILKPulseTables.counts[rate]))
            while count == 17 {
                shifts[block] += 1
                count = try working.decodeSymbol(model: countModel(escapeBits: shifts[block]))
            }
            counts[block] = count
        }
        var magnitudes = Array(repeating: 0, count: blocks * 16)
        for block in 0..<blocks {
            try decodeShell(from: &working, total: counts[block], offset: block * 16, width: 16, pulses: &magnitudes)
        }
        let lsbModel = try model([120, 0])
        for block in 0..<blocks where shifts[block] > 0 {
            for sample in (block * 16)..<((block + 1) * 16) {
                for _ in 0..<shifts[block] {
                    magnitudes[sample] = magnitudes[sample] * 2 + (try working.decodeSymbol(model: lsbModel))
                }
            }
        }
        for block in 0..<blocks {
            let sign = try signModel(signalType, quantizationOffset, shellCount: counts[block])
            for sample in (block * 16)..<((block + 1) * 16) where magnitudes[sample] > 0 {
                if try working.decodeSymbol(model: sign) == 0 { magnitudes[sample] = -magnitudes[sample] }
            }
        }
        // At most sixteen shell pulses and ten LSBs yield magnitude <= 17,407.
        let signed = magnitudes.map { Int16($0) }
        let frame = SILKPulseFrame(
            signalType: signalType, quantizationOffset: quantizationOffset, rateLevel: rate,
            signedPulses: Array(signed.prefix(sampleCount)), discardedPadding: Array(signed.dropFirst(sampleCount)),
            shellPulseCounts: counts, leastSignificantBitCounts: shifts
        )
        decoder = working
        return frame
    }

    /// Encodes already quantized signed pulses into a caller-owned Opus entropy frame.
    /// - Parameters:
    ///   - pulses: Exactly 80, 120, 160, 240 or 320 signed samples. Mediumband's
    ///     last eight coded samples are explicitly zero-filled. Analysis, quantization,
    ///     gain choice and rate control belong to the complete encoder above this layer.
    ///   - encoder: Active range coder at the rate-level position. Success advances
    ///     it past all signs; finalization remains the caller's responsibility.
    ///   - signalType: Frame type whose enclosing parameter symbols must agree.
    ///   - quantizationOffset: Frame offset category whose parameter must agree.
    ///   - rateLevel: `0...8` to select a specified context, or `nil` to minimize the
    ///     reference Q5 pulse-count/rate cost with lowest-index tie breaking.
    /// - Returns: The chosen rate-level index. Encoder state commits atomically.
    /// - Throws: `invalidSampleCount`, `invalidRateLevel`, `pulseMagnitudeExceeded`
    ///   when more than ten LSB shifts are needed to satisfy shell limits 8/10/12/16,
    ///   or range-coder operation/frame/state errors. Every error preserves `encoder`.
    /// - Complexity: O(samples * 10) bounded work, O(samples) storage; synchronous,
    ///   no shared state, suspension, background work or native codec dependency.
    @discardableResult
    public static func encode(
        _ pulses: [Int16],
        to encoder: inout OpusRangeEncoder,
        signalType: SILKSignalType,
        quantizationOffset: SILKQuantizationOffset,
        rateLevel: Int? = nil
    ) throws -> Int {
        try validateSampleCount(pulses.count)
        if let rateLevel, !(0...8).contains(rateLevel) { throw SILKPulseCodingError.invalidRateLevel }
        let blocks = (pulses.count + 15) / 16
        let signed = pulses.map { Int($0) } + Array(repeating: 0, count: blocks * 16 - pulses.count)
        var magnitudes = signed.map { abs($0) }
        var counts = Array(repeating: 0, count: blocks)
        var shifts = counts
        for block in 0..<blocks {
            let start = block * 16
            while !isShellAdmissible(Array(magnitudes[start..<(start + 16)])) {
                guard shifts[block] < 10 else { throw SILKPulseCodingError.pulseMagnitudeExceeded }
                shifts[block] += 1
                for index in start..<(start + 16) { magnitudes[index] >>= 1 }
            }
            counts[block] = magnitudes[start..<(start + 16)].reduce(0, +)
        }
        let rate = rateLevel ?? selectRate(signalType: signalType, counts: counts, shifts: shifts)
        var working = encoder
        try working.encodeSymbol(rate, model: model(SILKPulseTables.rate[signalType.rawValue >> 1]))
        for block in 0..<blocks {
            try working.encodeSymbol(shifts[block] == 0 ? counts[block] : 17, model: model(SILKPulseTables.counts[rate]))
            if shifts[block] > 0 {
                for shift in 1...shifts[block] {
                    try working.encodeSymbol(shift == shifts[block] ? counts[block] : 17, model: countModel(escapeBits: shift))
                }
            }
        }
        for block in 0..<blocks {
            try encodeShell(to: &working, pulses: magnitudes, offset: block * 16, width: 16, total: counts[block])
        }
        let lsbModel = try model([120, 0])
        for block in 0..<blocks where shifts[block] > 0 {
            for sample in (block * 16)..<((block + 1) * 16) {
                for bit in stride(from: shifts[block] - 1, through: 0, by: -1) {
                    try working.encodeSymbol((abs(signed[sample]) >> bit) & 1, model: lsbModel)
                }
            }
        }
        for block in 0..<blocks {
            let sign = try signModel(signalType, quantizationOffset, shellCount: counts[block])
            for sample in (block * 16)..<((block + 1) * 16) where signed[sample] != 0 {
                try working.encodeSymbol(signed[sample] < 0 ? 0 : 1, model: sign)
            }
        }
        encoder = working
        return rate
    }

    /// Checks the finite set of internal 10/20 ms channel frame lengths.
    /// - Parameter count: Number of output channel samples, without MB shell padding.
    /// - Throws: `invalidSampleCount` unless the count is one of the five legal lengths.
    private static func validateSampleCount(_ count: Int) throws {
        guard [80, 120, 160, 240, 320].contains(count) else { throw SILKPulseCodingError.invalidSampleCount }
    }

    /// Constructs an exact 256-total frequency model from audited normative iCDF data.
    /// - Parameter inverseCDF: A nonincreasing normative table ending in zero.
    /// - Returns: An immutable bounded model preserving all context frequencies.
    /// - Throws: Range-model validation errors if internal normative data is corrupted.
    private static func model(_ inverseCDF: [UInt8]) throws -> OpusProbabilityModel {
        try OpusProbabilityModel(inverseCDF: inverseCDF)
    }

    /// Selects the escape context, removing the escape symbol after the tenth LSB.
    /// - Parameter escapeBits: Number of previously decoded escape symbols in `1...10`.
    /// - Returns: Table 46 rate nine, or its one-entry-shifted terminal context.
    /// - Throws: Range-model validation errors for internally corrupted data.
    private static func countModel(escapeBits: Int) throws -> OpusProbabilityModel {
        try model(escapeBits == 10 ? Array(SILKPulseTables.counts[9].dropFirst()) : SILKPulseTables.counts[9])
    }

    /// Selects a sign context using the original shell count before any restored LSBs.
    /// - Parameters:
    ///   - signal: Previously decoded inactive/unvoiced/voiced category.
    ///   - offset: Previously decoded low/high quantization category.
    ///   - shellCount: Shell pulse sum in `0...16`; zero remains meaningful with LSBs.
    /// - Returns: Exact two-symbol Table 52 model, with symbol zero meaning negative.
    /// - Throws: Range-model validation errors for internally corrupted data.
    private static func signModel(
        _ signal: SILKSignalType, _ offset: SILKQuantizationOffset, shellCount: Int
    ) throws -> OpusProbabilityModel {
        try model([SILKPulseTables.signs[signal.rawValue * 2 + offset.rawValue][min(shellCount, 6)], 0])
    }

    /// Builds the shell split context for a positive parent count and current width.
    /// - Parameters:
    ///   - total: Positive parent count in `1...16`, already validated by syntax.
    ///   - width: Number of descendant samples, exactly 2, 4, 8 or 16.
    /// - Returns: The matching Table 47-50 split model with `total + 1` symbols.
    /// - Throws: Range-model validation errors for internally corrupted data.
    private static func shellModel(total: Int, width: Int) throws -> OpusProbabilityModel {
        let table: [UInt8]
        switch width {
        case 2: table = SILKPulseTables.shell0
        case 4: table = SILKPulseTables.shell1
        case 8: table = SILKPulseTables.shell2
        default: table = SILKPulseTables.shell3
        }
        let offset = (total - 1) * (total + 2) / 2
        return try model(Array(table[offset..<(offset + total + 1)]))
    }

    /// Recursively decodes a shell in depth-first order, skipping zero-count nodes.
    /// - Parameters:
    ///   - decoder: Temporary caller coder, committed only after complete pulse success.
    ///   - total: Parent pulse count in `0...16`, conserved across the child split.
    ///   - offset: Start of this node inside the allocated padded pulse storage.
    ///   - width: Power-of-two node width in `1...16`; recursion is at most four deep.
    ///   - pulses: Bounded zero-initialized magnitude storage mutated at leaf nodes.
    /// - Throws: Range operation/state or internal context validation errors.
    private static func decodeShell(
        from decoder: inout OpusRangeDecoder, total: Int, offset: Int, width: Int, pulses: inout [Int]
    ) throws {
        if width == 1 { pulses[offset] = total; return }
        guard total > 0 else { return }
        let left = try decoder.decodeSymbol(model: shellModel(total: total, width: width))
        try decodeShell(from: &decoder, total: left, offset: offset, width: width / 2, pulses: &pulses)
        try decodeShell(from: &decoder, total: total - left, offset: offset + width / 2, width: width / 2, pulses: &pulses)
    }

    /// Emits the corresponding depth-first shell split tree from known magnitudes.
    /// - Parameters:
    ///   - encoder: Temporary caller coder, committed only after full pulse success.
    ///   - pulses: Padded, shifted nonnegative magnitudes meeting every shell limit.
    ///   - offset: First sample belonging to this node inside `pulses`.
    ///   - width: Power-of-two node width in `1...16`.
    ///   - total: Sum of this node's descendant magnitudes, in `0...16`.
    /// - Throws: Range operation/frame/state or internal model validation errors.
    private static func encodeShell(
        to encoder: inout OpusRangeEncoder, pulses: [Int], offset: Int, width: Int, total: Int
    ) throws {
        guard width > 1, total > 0 else { return }
        let half = width / 2
        let left = pulses[offset..<(offset + half)].reduce(0, +)
        try encoder.encodeSymbol(left, model: shellModel(total: total, width: width))
        try encodeShell(to: &encoder, pulses: pulses, offset: offset, width: half, total: left)
        try encodeShell(to: &encoder, pulses: pulses, offset: offset + half, width: half, total: total - left)
    }

    /// Checks all pairwise shell sums against the encoder's normative stage limits.
    /// - Parameter pulses: Exactly sixteen nonnegative, shifted magnitudes.
    /// - Returns: Whether all 8/10/12/16 pulse limits hold without further shifting.
    private static func isShellAdmissible(_ pulses: [Int]) -> Bool {
        var row = pulses
        for limit in [8, 10, 12, 16] {
            var next: [Int] = []
            for index in stride(from: 0, to: row.count, by: 2) {
                let sum = row[index] + row[index + 1]
                if sum > limit { return false }
                next.append(sum)
            }
            row = next
        }
        return true
    }

    /// Chooses the reference Q5 minimum-cost pulse/rate context with stable ties.
    /// - Parameters:
    ///   - signalType: Inactive/unvoiced uses row zero, voiced uses row one.
    ///   - counts: Final pulse count for each padded sixteen-sample shell.
    ///   - shifts: LSB count per corresponding shell; positive counts select escape.
    /// - Returns: Lowest-index rate in `0...8` with the smallest integer Q5 estimate.
    private static func selectRate(signalType: SILKSignalType, counts: [Int], shifts: [Int]) -> Int {
        var best = 0
        var bestCost = Int.max
        for rate in 0...8 {
            var cost = Int(SILKPulseTables.rateCosts[signalType.rawValue >> 1][rate])
            for block in counts.indices {
                cost += Int(SILKPulseTables.countCosts[rate][shifts[block] > 0 ? 17 : counts[block]])
            }
            if cost < bestCost { best = rate; bestCost = cost }
        }
        return best
    }
}
