import Foundation
import Testing
@testable import DiscordMedia

@Suite("Exact media time and PCM sample clocks")
struct MediaClockTests {
    /// Covers exact conversion, zero values and the default downward rounding policy.
    /// The stored fraction remains representation-based even after a numeric conversion.
    @Test func exactConversionsAndDefaultRounding() throws {
        let zero = try MediaTime(value: 0, timescale: .max)
        #expect(try zero.converted(to: 1) == MediaTime(value: 0, timescale: 1))
        #expect(try zero.converted(to: .max, rounding: .up) == zero)
        let second = try MediaTime(value: 44_101, timescale: 44_101)
        #expect(try second.converted(to: 48_000) == MediaTime(value: 48_000, timescale: 48_000))
        #expect(try second.converted(to: 44_101) == second)
        #expect(try MediaTime(value: 2, timescale: 3).converted(to: 1).value == 0)
        #expect(try second.converted(to: 1) != second)
        #expect(try second.converted(to: 1).compare(to: second) == .orderedSame)
    }

    /// Exercises fractional boundaries below, at and above a tie using integer arithmetic.
    /// - Parameters:
    ///   - value: Nonnegative source ticks.
    ///   - scale: Positive source ticks per second.
    ///   - destination: Positive destination ticks per second.
    ///   - down: Expected truncation toward zero, equivalent to floor for these timestamps.
    ///   - up: Expected ceiling when a fractional destination tick remains.
    ///   - nearest: Expected nearest tick with ties rounded away from zero.
    @Test(arguments: [
        (Int64(0), Int32(3), Int32(2), Int64(0), Int64(0), Int64(0)),
        (1, 4, 1, 0, 1, 0), (1, 2, 1, 0, 1, 1), (2, 3, 1, 0, 1, 1),
        (3, 2, 1, 1, 2, 2), (1, 3, 2, 0, 1, 1), (2, 3, 2, 1, 2, 1),
        (4, 2, 3, 6, 6, 6), (7, 4, 2, 3, 4, 4)
    ])
    func conversionRounding(value: Int64, scale: Int32, destination: Int32,
                            down: Int64, up: Int64, nearest: Int64) throws {
        let time = try MediaTime(value: value, timescale: scale)
        #expect(try time.converted(to: destination, rounding: .down).value == down)
        #expect(try time.converted(to: destination, rounding: .up).value == up)
        #expect(try time.converted(to: destination, rounding: .nearestTiesAwayFromZero).value == nearest)
        #expect(try time.converted(to: destination).timescale == destination)
    }

    /// Checks conversions whose multiplication exceeds 64 bits but whose final result fits.
    /// The reference expressions avoid wide products, independently exercising high-word math.
    @Test func fullWidthConversionWithinRange() throws {
        let maximum = try MediaTime(value: .max, timescale: .max)
        #expect(try maximum.converted(to: .max) == maximum)
        let scale = Int64(Int32.max)
        let whole = Int64.max / scale
        let remainder = Int64.max % scale
        #expect(try maximum.converted(to: 1).value == whole)
        #expect(try maximum.converted(to: 1, rounding: .up).value == whole + 1)
        #expect(remainder == 1)
        let destination = Int32.max - 1
        #expect(try maximum.converted(to: destination).value == Int64.max - whole - 1)
        #expect(try maximum.converted(to: destination, rounding: .up).value == Int64.max - whole)
        #expect(try maximum.converted(to: destination, rounding: .nearestTiesAwayFromZero).value == Int64.max - whole)
    }

    /// Rejects invalid destination scales and both quotient and rounding-induced overflow.
    /// Each failure leaves the immutable source representation available for recovery.
    @Test func conversionOverflowAndInvalidScale() throws {
        let time = try MediaTime(value: .max, timescale: 1)
        for scale: Int32 in [.min, -1, 0] {
            #expect(throws: MediaError.invalidTime) { try time.converted(to: scale) }
        }
        for scale: Int32 in [2, .max] {
            #expect(throws: MediaError.invalidTime) { try time.converted(to: scale) }
        }
        #expect(time.value == .max && time.timescale == 1)

        // 3 * this value = 2 * Int64.max + 1: floor fits and its exact half-tie does not.
        let tie = try MediaTime(value: 6_148_914_691_236_517_205, timescale: 2)
        #expect(try tie.converted(to: 3, rounding: .down).value == .max)
        #expect(throws: MediaError.invalidTime) { try tie.converted(to: 3, rounding: .up) }
        #expect(throws: MediaError.invalidTime) {
            try tie.converted(to: 3, rounding: .nearestTiesAwayFromZero)
        }

        // The quotient is UInt64.max with remainder three: rounding must never wrap to zero.
        let unsignedBoundary = try MediaTime(value: 8_198_552_921_648_689_607, timescale: 4)
        for rounding: MediaTimeRounding in [.down, .up, .nearestTiesAwayFromZero] {
            #expect(throws: MediaError.invalidTime) {
                try unsignedBoundary.converted(to: 9, rounding: rounding)
            }
        }
    }

    /// Distinguishes mathematical ordering from stored equality, including full-width products.
    /// Ordered pairs check symmetry, transitivity and both high- and low-word comparisons.
    @Test func mathematicalComparisonAcrossClockDomains() throws {
        let half = try MediaTime(value: 1, timescale: 2)
        let equivalent = try MediaTime(value: 2, timescale: 4)
        #expect(half != equivalent)
        #expect(half.compare(to: equivalent) == .orderedSame)
        let sorted = try [MediaTime(value: 0, timescale: .max),
                          MediaTime(value: 1, timescale: .max),
                          MediaTime(value: 1, timescale: 2),
                          MediaTime(value: 2, timescale: 3),
                          MediaTime(value: 1, timescale: 1),
                          MediaTime(value: .max - 1, timescale: .max),
                          MediaTime(value: .max, timescale: .max),
                          MediaTime(value: .max, timescale: 1)]
        for first in sorted.indices {
            for second in sorted.indices {
                let expected: ComparisonResult = first == second ? .orderedSame
                    : first < second ? .orderedAscending : .orderedDescending
                #expect(sorted[first].compare(to: sorted[second]) == expected)
            }
        }
        #expect(try MediaTime(value: .max, timescale: 1).compare(to: MediaTime(value: .max - 1, timescale: 1)) == .orderedDescending)
        #expect(try MediaTime(value: 0, timescale: 1).compare(to: MediaTime(value: 0, timescale: .max)) == .orderedSame)
    }

    /// Checks exact integral and fractional Duration components without floating-point time.
    /// - Parameters:
    ///   - value: Nonnegative source ticks, including Int64's largest timestamp.
    ///   - scale: Source ticks per second, including the largest positive Int32 timescale.
    ///   - seconds: Expected whole seconds after division.
    ///   - attoseconds: Expected fractional seconds, truncated below one attosecond.
    @Test(arguments: [
        (Int64(0), Int32(1), Int64(0), Int64(0)),
        (.max, 1, .max, 0), (1, 2, 0, 500_000_000_000_000_000),
        (1, 3, 0, 333_333_333_333_333_333), (2, 3, 0, 666_666_666_666_666_666),
        (7, 2, 3, 500_000_000_000_000_000),
        (1, .max, 0, 465_661_287),
        (Int64(Int32.max) - 1, .max, 0, 999_999_999_534_338_712),
        (.max, .max, 4_294_967_298, 465_661_287)
    ])
    func durationComponents(value: Int64, scale: Int32, seconds: Int64, attoseconds: Int64) throws {
        let duration = try MediaTime(value: value, timescale: scale).duration
        #expect(duration.components.seconds == seconds)
        #expect(duration.components.attoseconds == attoseconds)
        #expect(duration == Duration(secondsComponent: seconds, attosecondsComponent: attoseconds))
    }

    /// Checks default/rate-edge clock construction and rejection of invalid rates or positions.
    /// Format and position validation acquire no device, task or physical-clock resources.
    @Test func sampleClockConstruction() throws {
        let standard = try PCMSampleClock()
        #expect(standard.sampleRate == 48_000 && standard.samplePosition == 0)
        #expect(standard.timestamp == (try MediaTime(value: 0, timescale: 48_000)))
        for rate in [8_000, 44_101, 48_000, 192_000] {
            let clock = try PCMSampleClock(sampleRate: rate, samplePosition: .max)
            #expect(clock.sampleRate == rate && clock.samplePosition == .max)
            #expect(clock.timestamp == (try MediaTime(value: .max, timescale: Int32(rate))))
        }
        for rate in [Int.min, 7_999, 192_001, Int.max] {
            #expect(throws: MediaError.invalidFormat) { try PCMSampleClock(sampleRate: rate) }
        }
        for position: Int64 in [.min, -1] {
            #expect(throws: MediaError.invalidTime) { try PCMSampleClock(samplePosition: position) }
        }
    }

    /// Advances thousands of varying frame counts in an awkward sample domain without drift.
    /// Each reservation returns its previous exact timestamp; zero counts never advance it.
    @Test func sampleClockReservationsHaveNoRoundingDrift() throws {
        var clock = try PCMSampleClock(sampleRate: 44_101, samplePosition: 7)
        var total: Int64 = 7
        for index in 0..<4_096 {
            let count = index % 97
            let before = try MediaTime(value: total, timescale: 44_101)
            #expect(try clock.advance(by: count) == before)
            total += Int64(count)
            #expect(clock.samplePosition == total)
            #expect(clock.timestamp == (try MediaTime(value: total, timescale: 44_101)))
        }
        let unchanged = clock.timestamp
        #expect(try clock.advance(by: 0) == unchanged)
        #expect(clock.timestamp == unchanged)
        #expect(try clock.timestamp.converted(to: 48_000).value == total * 48_000 / 44_101)
    }

    /// Covers zero and maximum increments, negative counts and atomic lifetime overflow.
    /// Failures preserve the previous timestamp so the owner can explicitly reset its timeline.
    @Test func sampleClockAdvanceOverflowIsAtomic() throws {
        var clock = try PCMSampleClock(samplePosition: .max - 2)
        #expect(try clock.advance(by: 1).value == .max - 2)
        #expect(try clock.advance(by: 1).value == .max - 1)
        let final = clock.timestamp
        #expect(final.value == .max)
        for count in [Int.min, -1, 1, Int.max] {
            #expect(throws: MediaError.invalidTime) { try clock.advance(by: count) }
            #expect(clock.timestamp == final && clock.samplePosition == .max)
        }
        #expect(try clock.advance(by: 0) == final)
        try clock.reset()
        #expect(try clock.advance(by: Int.max).value == 0)
        #expect(clock.samplePosition == Int64(Int.max))
    }

    /// Resets seek/discontinuity positions, rejects negative values atomically and isolates copies.
    /// A reset after lifetime overflow starts a new caller-owned timeline without changing rate.
    @Test func sampleClockResetAndIndependentCopies() throws {
        var clock = try PCMSampleClock(sampleRate: 8_000, samplePosition: 17)
        var copy = clock
        #expect(try copy.advance(by: 5).value == 17)
        #expect(copy.samplePosition == 22 && clock.samplePosition == 17)
        try clock.reset(to: .max)
        let maximum = clock.timestamp
        for position: Int64 in [.min, -1] {
            #expect(throws: MediaError.invalidTime) { try clock.reset(to: position) }
            #expect(clock.timestamp == maximum)
        }
        #expect(throws: MediaError.invalidTime) { try clock.advance(by: 1) }
        try clock.reset(to: 23)
        #expect(clock.timestamp == (try MediaTime(value: 23, timescale: 8_000)))
        try clock.reset()
        try clock.reset()
        #expect(clock.samplePosition == 0 && clock.sampleRate == 8_000)
        #expect(copy.samplePosition == 22 && copy.sampleRate == 8_000)
    }
}
