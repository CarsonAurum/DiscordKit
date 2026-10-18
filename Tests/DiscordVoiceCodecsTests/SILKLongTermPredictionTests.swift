import Testing
@testable import DiscordVoiceCodecs

@Suite("SILK five-tap long-term prediction")
struct SILKLongTermPredictionTests {
    /// Uses each isolated tap with explicitly seeded chronological history, proving
    /// the RFC's `lag - 2 + k` addressing and signed Q7 scaling at all internal rates.
    /// - Parameter sampleRate: A supported NB/MB/WB internal SILK sample rate.
    @Test(arguments: [8_000, 12_000, 16_000]) func tapOrderAndRanges(sampleRate: Int) throws {
        let maximumLag = sampleRate * 18 / 1000
        let history = (0..<(maximumLag + 2)).map { Double($0) / 8 }
        let minimumLag = sampleRate * 2 / 1000
        for lag in [minimumLag, maximumLag] {
            for tap in 0..<5 {
                var coefficients = Array(repeating: Int8(0), count: 5)
                coefficients[tap] = -64
                var filter = try SILKLongTermSynthesisFilter(sampleRate: sampleRate, history: history)
                #expect(filter.sampleRate == sampleRate)
                #expect(filter.pitchLagRange == minimumLag...maximumLag)
                let expected = 0.25 - history[history.count - lag + 2 - tap] / 2
                #expect(try filter.process([0.25], pitchLag: lag, coefficientsQ7: coefficients) == [expected])
                #expect(filter.history == Array(history.dropFirst()) + [expected])
            }
        }
    }

    /// Checks a known single-center-tap impulse echo train at 2 ms pitch. Taps use
    /// dyadic scaling so expected residuals and chunk invariance are exact, including
    /// samples that depend on residuals produced earlier in the current block.
    /// - Parameter sampleRate: NB/MB/WB rate, determining a causal 2 ms pitch delay.
    @Test(arguments: [8_000, 12_000, 16_000]) func analyticalEchoAndStreaming(sampleRate: Int) throws {
        let lag = sampleRate * 2 / 1000
        let excitation = [2.0] + Array(repeating: 0, count: lag * 4)
        var expected = Array(repeating: 0.0, count: excitation.count)
        for echo in 0...4 { expected[echo * lag] = 2 / Double(1 << echo) }
        var whole = try SILKLongTermSynthesisFilter(sampleRate: sampleRate)
        #expect(try whole.process(excitation, pitchLag: lag, coefficientsQ7: [0, 0, 64, 0, 0]) == expected)
        var chunked = try SILKLongTermSynthesisFilter(sampleRate: sampleRate)
        var actual: [Double] = []
        for offset in stride(from: 0, to: excitation.count, by: 7) {
            let block = Array(excitation[offset..<min(offset + 7, excitation.count)])
            actual += try chunked.process(block, pitchLag: lag, coefficientsQ7: [0, 0, 64, 0, 0])
        }
        #expect(actual == expected)
        #expect(chunked.history == whole.history)
        var copied = whole
        try copied.reset()
        #expect(copied.history.allSatisfy { $0 == 0 })
        #expect(whole.history.contains { $0 != 0 })
    }

    /// Compares all five signed taps against an independent full-array convolution
    /// recurrence over a maximum block. A full source array avoids the implementation's
    /// state-shifting/indexing strategy and checks order, negative taps and lag changes.
    @Test func independentFullArrayRecurrenceAndUnvoiced() throws {
        let coefficients: [Int8] = [3, -8, 75, 18, -2]
        var filter = try SILKLongTermSynthesisFilter(sampleRate: 16_000)
        let initial = (0..<290).map { Double(($0 * 17) % 31 - 15) / 32 }
        try filter.reset(history: initial)
        var oracle = initial
        for lag in [32, 121, 288] {
            let excitation = (0..<960).map { Double(($0 * 13) % 61 - 30) / 64 }
            var expected: [Double] = []
            for sample in excitation {
                let index = oracle.count
                var value = 0.0
                for tap in 0..<5 { value += oracle[index - lag + 2 - tap] * Double(coefficients[tap]) / 128 }
                value += sample
                oracle.append(value)
                expected.append(value)
            }
            #expect(try filter.process(excitation, pitchLag: lag, coefficientsQ7: coefficients) == expected)
            #expect(filter.history == Array(oracle.suffix(290)))
        }
        let before = filter.history
        #expect(try filter.process([], pitchLag: 32, coefficientsQ7: nil).isEmpty)
        #expect(filter.history == before)
        #expect(try filter.process([1, -2, 3], pitchLag: 288, coefficientsQ7: nil) == [1, -2, 3])
        #expect(Array(filter.history.suffix(3)) == [1, -2, 3])
        #expect(try filter.process([4], pitchLag: 32, coefficientsQ7: [0, 0, 0, 0, 0]) == [4])
    }

    /// Rejects unsupported rates, invalid histories/taps/lags, nonfinite values and
    /// oversized blocks. Arithmetic overflow after earlier valid samples also rolls
    /// back all state, so a caller can recover by replacing the explicit history.
    @Test func malformedInputAndAtomicOverflow() throws {
        for rate in [Int.min, 0, 7_999, 8_001, 24_000, 48_000, Int.max] {
            #expect(throws: SILKPredictionError.invalidSampleRate) { try SILKLongTermSynthesisFilter(sampleRate: rate) }
        }
        for history in [[], Array(repeating: 0.0, count: 289), Array(repeating: 0, count: 291)] {
            #expect(throws: SILKPredictionError.invalidHistory) {
                try SILKLongTermSynthesisFilter(sampleRate: 16_000, history: history)
            }
        }
        for invalid in [Double.nan, .infinity, -.infinity] {
            #expect(throws: SILKPredictionError.nonFiniteSample) {
                try SILKLongTermSynthesisFilter(sampleRate: 16_000, history: [invalid] + Array(repeating: 0, count: 289))
            }
        }
        var filter = try SILKLongTermSynthesisFilter(sampleRate: 16_000)
        let before = filter.history
        #expect(throws: SILKPredictionError.invalidHistory) { try filter.reset(history: []) }
        #expect(throws: SILKPredictionError.nonFiniteSample) {
            try filter.reset(history: [Double.nan] + Array(repeating: 0, count: 289))
        }
        for lag in [Int.min, 0, 31, 289, Int.max] {
            #expect(throws: SILKPredictionError.invalidPitchLag) { try filter.process([], pitchLag: lag, coefficientsQ7: nil) }
        }
        for count in [0, 1, 4, 6] {
            #expect(throws: SILKPredictionError.invalidLongTermCoefficients) {
                try filter.process([0], pitchLag: 32, coefficientsQ7: Array(repeating: 0, count: count))
            }
        }
        #expect(throws: SILKPredictionError.invalidSampleCount) {
            try filter.process(Array(repeating: 0, count: 961), pitchLag: 32, coefficientsQ7: nil)
        }
        for invalid in [Double.nan, .infinity, -.infinity] {
            #expect(throws: SILKPredictionError.nonFiniteSample) { try filter.process([0, invalid], pitchLag: 32, coefficientsQ7: nil) }
        }
        #expect(filter.history == before)
        let extreme = Double.greatestFiniteMagnitude
        var seeded = Array(repeating: 0.0, count: 290)
        // The first output is finite; the second five-tap sum overflows.
        seeded[261] = extreme
        seeded[260] = extreme
        try filter.reset(history: seeded)
        #expect(throws: SILKPredictionError.numericalOverflow) {
            try filter.process([0, 0], pitchLag: 32, coefficientsQ7: [127, 127, 127, 127, 127])
        }
        #expect(filter.history == seeded)
        try filter.reset()
        #expect(filter.history == before)
    }
}
