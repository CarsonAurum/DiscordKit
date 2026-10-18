import Foundation
import Testing
@testable import DiscordVoiceCodecs

@Suite("SILK fixed-point NLSF conversion")
struct SILKNLSFTests {
    private struct Fixture: Decodable {
        let input: Input
        let output: Output
        struct Input: Decodable { let kind: Int; let values: [Int16] }
        struct Output: Decodable { let q12: [Int16]; let gain: Int32 }
    }

    /// Checks exact Q12 and Q30 outputs from unmodified scalar libopus for both LPC orders.
    /// Degenerate frequency clusters exercise polynomial narrowing, coefficient fitting,
    /// saturation and stability expansion; standalone unstable predictors must return zero.
    /// These are frequency/predictor component fixtures, not official decoded-PCM vectors.
    @Test func officialScalarConversionAndGain() throws {
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(SILKNLSFOracleFixtures.json.utf8))
        #expect(fixtures.count == 30)
        for fixture in fixtures {
            if fixture.input.kind == 0 {
                let coefficients = try SILKNLSFCoefficients(q15: fixture.input.values)
                #expect(coefficients.q15 == fixture.input.values)
                #expect(coefficients.lpcQ12 == fixture.output.q12)
                #expect(coefficients.inversePredictionGainQ30 == fixture.output.gain)
                #expect(try SILKNLSFCoefficients.inversePredictionGain(q12: coefficients.lpcQ12) == fixture.output.gain)
            } else {
                #expect(try SILKNLSFCoefficients.inversePredictionGain(q12: fixture.input.values) == fixture.output.gain)
            }
        }
    }

    /// Arbitrary Q12 inputs once triggered a trap through Swift's shift precedence in
    /// multiply-then-shift arithmetic. The fixed-point reference classifies this predictor
    /// as unstable; integer operations must complete without an intermediate narrowing trap.
    @Test func unstableRecursionNeverTraps() throws {
        let q12: [Int16] = [-1239, 3163, 992, -205, 3921, -1818, -1203, -3504,
                            -1386, 416, 485, -4048, -1284, 2019, 1063, 2827]
        #expect(try SILKNLSFCoefficients.inversePredictionGain(q12: q12) == 0)
        #expect(try SILKNLSFCoefficients.inversePredictionGain(q12: Array(repeating: 0, count: 16)) == 1 << 30)
    }

    /// Rejects every unsupported order before table indexing in conversion or gain testing.
    @Test(arguments: [0, 1, 9, 11, 15, 17, 100])
    func invalidOrder(_ order: Int) {
        #expect(throws: SILKNLSFError.invalidOrder) {
            try SILKNLSFCoefficients(q15: Array(repeating: 0, count: order))
        }
        #expect(throws: SILKNLSFError.invalidOrder) {
            try SILKNLSFCoefficients.inversePredictionGain(q12: Array(repeating: 0, count: order))
        }
    }

    /// Negative and descending Q15 frequencies cannot reach polynomial construction.
    /// Repeated frequencies are deliberately admitted as bounded degenerate inputs.
    @Test func invalidFrequenciesAndAllowedDuplicates() throws {
        for values: [Int16] in [[-1] + Array(repeating: 0, count: 9),
                                 [.min] + Array(repeating: 0, count: 9),
                                 [2, 1] + Array(repeating: 3, count: 8),
                                 Array(repeating: 100, count: 9) + [0]] {
            #expect(throws: SILKNLSFError.invalidFrequencies) { try SILKNLSFCoefficients(q15: values) }
        }
        let repeated = try SILKNLSFCoefficients(q15: Array(repeating: .max, count: 10))
        #expect(repeated.lpcQ12.count == 10)
        #expect(repeated.inversePredictionGainQ30 >= 0)
    }

    /// Quarter-unit interpolation must round negative differences toward minus infinity,
    /// preserve ordering and return the exact previous/current endpoints for weights 0/4.
    @Test(arguments: [10, 16])
    func interpolationUsesSignedQuarterUnits(_ order: Int) throws {
        let previous = (0..<order).map { Int16(10 + $0 * 1000) }
        let current = previous.map { $0 - 3 }
        for weight in 0...4 {
            let interpolated = try SILKNLSFCoefficients.interpolate(previous: previous, current: current, weight: weight)
            let delta = Int16(floor(Double(-3 * weight) / 4))
            #expect(interpolated == previous.map { $0 + delta })
            #expect(try SILKNLSFCoefficients(q15: interpolated).q15 == interpolated)
        }
        #expect(try SILKNLSFCoefficients.interpolate(previous: current, current: previous, weight: 1) == current)
        #expect(try SILKNLSFCoefficients.interpolate(previous: previous, current: current, weight: 4) == current)
    }

    /// Interpolation validates both arrays and its scalar before retaining source storage.
    @Test func interpolationRejectsInvalidContext() throws {
        let good: [Int16] = Array(repeating: 100, count: 10)
        for weight in [Int.min, -1, 5, Int.max] {
            #expect(throws: SILKNLSFError.invalidInterpolationWeight) {
                try SILKNLSFCoefficients.interpolate(previous: good, current: good, weight: weight)
            }
        }
        #expect(throws: SILKNLSFError.invalidOrder) {
            try SILKNLSFCoefficients.interpolate(previous: good, current: Array(repeating: 0, count: 16), weight: 2)
        }
        #expect(throws: SILKNLSFError.invalidFrequencies) {
            try SILKNLSFCoefficients.interpolate(previous: good, current: [-1] + Array(repeating: 0, count: 9), weight: 2)
        }
        #expect(throws: SILKNLSFError.invalidFrequencies) {
            try SILKNLSFCoefficients.interpolate(previous: [1, 0] + Array(repeating: 0, count: 8), current: good, weight: 2)
        }
    }

    /// Value copies and later caller mutation do not affect coefficient/history ownership;
    /// oversized caller reservations are discarded instead of retained in the value.
    @Test func deterministicDenseOwnership() throws {
        var frequencies: [Int16] = []
        frequencies.reserveCapacity(1_000_000)
        frequencies.append(contentsOf: (1...16).map { Int16($0 * 1900) })
        let first = try SILKNLSFCoefficients(q15: frequencies)
        let second = try SILKNLSFCoefficients(q15: frequencies)
        #expect(first == second && first.inversePredictionGainQ30 > 0)
        frequencies[0] = 0
        #expect(first.q15[0] == 1900 && first.q15.capacity < 100)
        #expect(first.lpcQ12.capacity < 100)
    }
}
