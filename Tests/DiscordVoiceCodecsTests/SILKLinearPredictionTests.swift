import Testing
@testable import DiscordVoiceCodecs

@Suite("SILK short-term prediction primitives")
struct SILKLinearPredictionTests {
    /// Verifies zero, one-pole and two-pole analytical reflection/gain results at
    /// both SILK orders. This independently fixes the coefficient and Schur signs.
    /// - Parameter order: One of the two supported SILK predictor orders, ten/sixteen.
    @Test(arguments: [10, 16]) func analyticalStability(order: Int) throws {
        var values = Array(repeating: Int16(0), count: order)
        let zero = try SILKLinearPredictionCoefficients(q12: values)
        #expect(zero.inversePredictionGain == 1)
        #expect(zero.reflectionCoefficients == Array(repeating: 0, count: order))
        values[0] = 2048
        let first = try SILKLinearPredictionCoefficients(q12: values)
        #expect(first.q12 == values)
        #expect(first.reflectionCoefficients[0] == -0.5)
        #expect(first.inversePredictionGain == 0.75)
        // Reflection pair (-0.5, -0.25) expands to predictor (0.375, 0.25).
        values[0] = 1536
        values[1] = 1024
        let second = try SILKLinearPredictionCoefficients(q12: values)
        #expect(second.reflectionCoefficients[0] == -0.5)
        #expect(second.reflectionCoefficients[1] == -0.25)
        #expect(second.inversePredictionGain == 0.75 * 0.9375)
    }

    /// Rejects unsupported order, unstable poles, conservative reflection limits
    /// and excessive prediction gain, including a stable but too-high-gain pair.
    @Test func invalidPredictors() throws {
        for count in [0, 1, 9, 11, 15, 17] {
            #expect(throws: SILKPredictionError.invalidOrder) {
                try SILKLinearPredictionCoefficients(q12: Array(repeating: 0, count: count))
            }
        }
        for prefix: [Int16] in [[4096], [-4096], [4095], [Int16.max], [Int16.min], [0, 4096], [8148, -4055]] {
            let values = prefix + Array(repeating: Int16(0), count: 10 - prefix.count)
            #expect(throws: SILKPredictionError.unstableCoefficients) {
                try SILKLinearPredictionCoefficients(q12: values)
            }
        }
        var values = Array(repeating: Int16(0), count: 10)
        values[0] = 4094
        #expect(try SILKLinearPredictionCoefficients(q12: values).inversePredictionGain > 0.0001)
    }

    /// Uses exact dyadic one-pole impulse/analysis fixtures, proving all-pole state
    /// remains unclipped, chunk invariant, independently copied and explicitly reset.
    /// - Parameter order: Ten or sixteen coefficients; the trailing taps are zero.
    @Test(arguments: [10, 16]) func impulseStreamingAndUnclampedState(order: Int) throws {
        let coefficients = try SILKLinearPredictionCoefficients(q12: [2048] + Array(repeating: 0, count: order - 1))
        var whole = try SILKShortTermFilter(direction: .synthesis, coefficients: coefficients)
        let input = [4.0] + Array(repeating: 0, count: 39)
        let expected = (0..<40).map { index in 4 / Double(UInt64(1) << index) }
        #expect(try whole.process(input) == expected)
        #expect(whole.direction == .synthesis)
        #expect(whole.history == Array(expected.suffix(order)))
        var chunked = try SILKShortTermFilter(direction: .synthesis, coefficients: coefficients)
        var actual: [Double] = []
        for range in [0..<1, 1..<3, 3..<10, 10..<40] { actual += try chunked.process(Array(input[range])) }
        #expect(actual == expected)
        #expect(chunked.history == whole.history)
        var copied = whole
        try copied.reset()
        #expect(copied.history == Array(repeating: 0, count: order))
        #expect(whole.history == Array(expected.suffix(order)))
        var analysis = try SILKShortTermFilter(direction: .analysis, coefficients: coefficients)
        #expect(try analysis.process(expected) == input)
        #expect(analysis.history == Array(expected.suffix(order)))
    }

    /// Reconstructs independent official libopus 1.6.1 floating LPC-analysis fixtures
    /// for orders ten/sixteen and compares the separately implemented inverse-gain
    /// routine. Integer/dyadic samples make the residuals exactly representable.
    /// The oracle prepended history because libopus clears its first `order` outputs;
    /// this streaming primitive deliberately emits residuals for every provided sample.
    @Test func officialAnalysisFixtures() throws {
        let fixtures: [(Int, Double, [Double])] = [
            (10, 0.90909135341644287, [
                2.27978515625, -5.85711669921875, -0.321044921875, 4.6910400390625,
                -5.81304931640625, 0.9066162109375, 5.326904296875, -4.88128662109375,
                1.6904296875, 6.1846923828125, -4.06048583984375, 2.52972412109375,
                -5.607177734375, -0.07110595703125, 4.94097900390625, -5.5631103515625,
                1.15655517578125, 5.57684326171875, -4.63134765625, 1.94036865234375,
                6.43463134765625, -3.810546875, 2.7796630859375, -5.35723876953125,
            ]),
            (16, 0.90908998250961304, [
                5.3282470703125, -4.88189697265625, 1.690948486328125, 6.18634033203125,
                -4.060791015625, 2.530548095703125, -5.61138916015625, -0.068023681640625,
                4.93902587890625, -5.563934326171875, 1.1568603515625, 5.578277587890625,
                -4.631866455078125, 1.94097900390625, 6.436370849609375, -3.810760498046875,
                2.78057861328125, -5.361358642578125, 0.1820068359375, 5.189056396484375,
                -5.31390380859375, 1.406890869140625, 5.82830810546875, -4.3818359375,
            ]),
        ]
        let q12: [Int16] = [1024, 512, -256, 128, -64, 32, -16, 8, -4, 2, -2, 1, -1, 1, -1, 1]
        for (order, inverseGain, expected) in fixtures {
            let coefficients = try SILKLinearPredictionCoefficients(q12: Array(q12.prefix(order)))
            #expect(abs(coefficients.inversePredictionGain - inverseGain) < 0.0000001)
            let source = (0..<(order + 24)).map { Double(($0 * 37) % 101 - 50) / 8 }
            let history = Array(source.prefix(order))
            let input = Array(source.dropFirst(order))
            var filter = try SILKShortTermFilter(direction: .analysis, coefficients: coefficients, history: history)
            #expect(try filter.process(input) == expected)
            var inverse = try SILKShortTermFilter(direction: .synthesis, coefficients: coefficients, history: history)
            #expect(try inverse.process(expected) == input)
        }
    }

    /// Exercises both directions at the block bound, seeded histories and predictor
    /// replacement. Inverse filtering recovers independent multi-tap source signals.
    /// - Parameter order: Ten or sixteen coefficients, exercising both internal modes.
    @Test(arguments: [10, 16]) func inverseAndCoefficientTransitions(order: Int) throws {
        let first = try SILKLinearPredictionCoefficients(q12: [1024, -512, 256] + Array(repeating: 0, count: order - 3))
        let zero = try SILKLinearPredictionCoefficients(q12: Array(repeating: 0, count: order))
        let history = (0..<order).map { Double($0 - order) / 16 }
        var analysis = try SILKShortTermFilter(direction: .analysis, coefficients: first, history: history)
        var synthesis = try SILKShortTermFilter(direction: .synthesis, coefficients: first, history: history)
        let input = (0..<960).map { Double(($0 * 73) % 239 - 119) / 128 }
        let residual = try analysis.process(input)
        let recovered = try synthesis.process(residual)
        for (actual, expected) in zip(recovered, input) { #expect(abs(actual - expected) < 0.000000000001) }
        try analysis.updateCoefficients(zero)
        #expect(analysis.coefficients == zero)
        #expect(analysis.history == Array(input.suffix(order)))
        #expect(try analysis.process(input) == input)
        try synthesis.reset(history: history)
        #expect(synthesis.history == history)
        let before = synthesis.history
        #expect(try synthesis.process([]).isEmpty)
        #expect(synthesis.history == before)
    }

    /// Checks malformed histories, nonfinite input and oversized blocks before state
    /// mutation, plus arithmetic overflow after a successful sample in the same call.
    @Test func rejectionIsAtomic() throws {
        let coefficients = try SILKLinearPredictionCoefficients(q12: [1536, 1024] + Array(repeating: 0, count: 8))
        let otherOrder = try SILKLinearPredictionCoefficients(q12: Array(repeating: 0, count: 16))
        for history: [Double] in [[], [1], Array(repeating: 0, count: 11)] {
            #expect(throws: SILKPredictionError.invalidHistory) {
                try SILKShortTermFilter(direction: .analysis, coefficients: coefficients, history: history)
            }
        }
        for invalid in [Double.nan, .infinity, -.infinity] {
            let history = [invalid] + Array(repeating: 0, count: 9)
            #expect(throws: SILKPredictionError.nonFiniteSample) {
                try SILKShortTermFilter(direction: .synthesis, coefficients: coefficients, history: history)
            }
        }
        for direction: SILKShortTermFilter.Direction in [.analysis, .synthesis] {
            var filter = try SILKShortTermFilter(direction: direction, coefficients: coefficients)
            let before = filter.history
            #expect(throws: SILKPredictionError.invalidOrder) { try filter.updateCoefficients(otherOrder) }
            #expect(filter.coefficients == coefficients)
            #expect(throws: SILKPredictionError.invalidHistory) { try filter.reset(history: []) }
            #expect(throws: SILKPredictionError.nonFiniteSample) {
                try filter.reset(history: [Double.nan] + Array(repeating: 0, count: 9))
            }
            #expect(throws: SILKPredictionError.invalidSampleCount) { try filter.process(Array(repeating: 0, count: 961)) }
            for invalid in [Double.nan, .infinity, -.infinity] {
                #expect(throws: SILKPredictionError.nonFiniteSample) { try filter.process([0, invalid]) }
            }
            #expect(filter.history == before)
            let extreme = Double.greatestFiniteMagnitude
            let samples = direction == .synthesis ? [extreme, extreme] : [extreme, -extreme]
            #expect(throws: SILKPredictionError.numericalOverflow) { try filter.process(samples) }
            #expect(filter.history == before)
        }
    }

    /// Ensures small accepted coefficient/history arrays do not retain a caller's
    /// oversized reserved capacity through construction or history replacement.
    @Test func retainedStorageIsBounded() throws {
        var q12: [Int16] = []
        q12.reserveCapacity(100_000)
        q12.append(contentsOf: Array(repeating: 0, count: 10))
        let coefficients = try SILKLinearPredictionCoefficients(q12: q12)
        #expect(coefficients.q12.capacity < 100)
        var history: [Double] = []
        history.reserveCapacity(100_000)
        history.append(contentsOf: Array(repeating: 0, count: 10))
        var filter = try SILKShortTermFilter(direction: .synthesis, coefficients: coefficients, history: history)
        #expect(filter.history.capacity < 100)
        try filter.reset(history: history)
        #expect(filter.history.capacity < 100)
        var longHistory: [Double] = []
        longHistory.reserveCapacity(100_000)
        longHistory.append(contentsOf: Array(repeating: 0, count: 290))
        var longFilter = try SILKLongTermSynthesisFilter(sampleRate: 16_000, history: longHistory)
        #expect(longFilter.history.capacity < 1024)
        try longFilter.reset(history: longHistory)
        #expect(longFilter.history.capacity < 1024)
    }
}
