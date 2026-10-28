// File: Sources/DiscordMedia/MediaClock.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation

/// Rounding for nonnegative rational media timestamps; no floating point is involved.
public enum MediaTimeRounding: Sendable {
    case down
    case up
    case nearestTiesAwayFromZero
}

extension MediaTime {
    /// Converts this rational time to another integer clock without intermediate overflow.
    ///
    /// Uses a full-width product, so a large timestamp can be converted whenever the
    /// final rounded result fits `Int64`, even if its intermediate product does not.
    /// This is a value conversion, not a synchronization of two physical clocks.
    /// - Parameters:
    ///   - timescale: Positive destination ticks per second.
    ///   - rounding: Policy for a fractional tick; defaults to discarding the fraction.
    /// - Returns: The same time rounded into the requested clock domain. Equality still
    ///   compares the stored fraction, as documented by `MediaTime`.
    /// - Throws: `MediaError.invalidTime` for a nonpositive timescale or result overflow.
    public func converted(to timescale: Int32, rounding: MediaTimeRounding = .down) throws -> MediaTime {
        guard timescale > 0 else { throw MediaError.invalidTime }
        let numerator = UInt64(value).multipliedFullWidth(by: UInt64(timescale))
        let divisor = UInt64(self.timescale)
        guard numerator.high < divisor else { throw MediaError.invalidTime }
        let division = divisor.dividingFullWidth(numerator)
        var ticks = division.quotient
        let increment: Bool
        switch rounding {
        case .down: increment = false
        case .up: increment = division.remainder > 0
        case .nearestTiesAwayFromZero: increment = division.remainder * 2 >= divisor
        }
        if increment {
            let rounded = ticks.addingReportingOverflow(1)
            guard !rounded.overflow else { throw MediaError.invalidTime }
            ticks = rounded.partialValue
        }
        guard ticks <= UInt64(Int64.max) else { throw MediaError.invalidTime }
        return try MediaTime(value: Int64(ticks), timescale: timescale)
    }

    /// Orders mathematical times without changing representation-based `Equatable`.
    /// - Parameter other: A timestamp in any positive media timescale.
    /// - Returns: Numeric ordering, including `.orderedSame` for equivalent fractions.
    ///   Cross-products use 128 bits and accept all valid `MediaTime` values.
    public func compare(to other: MediaTime) -> ComparisonResult {
        let left = UInt64(value).multipliedFullWidth(by: UInt64(other.timescale))
        let right = UInt64(other.value).multipliedFullWidth(by: UInt64(timescale))
        if left.high != right.high { return left.high < right.high ? .orderedAscending : .orderedDescending }
        if left.low != right.low { return left.low < right.low ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }

    /// Converts to Swift's duration clock, truncating only below one attosecond.
    /// - Returns: A nonnegative duration; integral seconds remain exact, including
    ///   `Int64.max`. No wall-clock epoch or device clock is inferred.
    public var duration: Duration {
        let seconds = value / Int64(timescale)
        let remainder = UInt64(value % Int64(timescale))
        let product = remainder.multipliedFullWidth(by: 1_000_000_000_000_000_000)
        let attoseconds = UInt64(timescale).dividingFullWidth(product).quotient
        return Duration(secondsComponent: seconds, attosecondsComponent: Int64(attoseconds))
    }
}

/// A caller-driven PCM sample clock with exact timestamps and checked lifetime rollover.
///
/// The value owns no task, device or physical clock. Advance only after accepting a
/// block; reset explicitly when starting a different timeline. Copies are independent.
public struct PCMSampleClock: Sendable {
    public let sampleRate: Int
    private var currentTimestamp: MediaTime

    /// Nonnegative sample-frame position in the fixed sample-rate clock domain.
    public var samplePosition: Int64 { currentTimestamp.value }

    /// Creates an exact sample timeline without reading system time.
    /// - Parameters:
    ///   - sampleRate: Sample frames per second, in `8_000...192_000`.
    ///   - samplePosition: Nonnegative initial sample frame, default zero.
    /// - Throws: `MediaError.invalidFormat` for the rate; `invalidTime` for negative position.
    public init(sampleRate: Int = 48_000, samplePosition: Int64 = 0) throws {
        _ = try PCMFormat(sampleRate: sampleRate, channelCount: 1)
        guard samplePosition >= 0 else { throw MediaError.invalidTime }
        self.sampleRate = sampleRate
        currentTimestamp = try MediaTime(value: samplePosition, timescale: Int32(sampleRate))
    }

    /// Returns the timestamp for the next accepted PCM frame, exactly in sample units.
    /// Reading this stored validated value performs no conversion, allocation or clock I/O.
    public var timestamp: MediaTime { currentTimestamp }

    /// Reserves the next sample interval and returns its start timestamp atomically.
    /// - Parameter frameCount: Nonnegative sample frames, independent of channel count.
    ///   Zero leaves the clock unchanged. This timing value does not allocate PCM storage.
    /// - Returns: The timestamp before advancing; cumulative increments have no rounding drift.
    /// - Throws: `MediaError.invalidTime` for a negative count or `Int64` position overflow.
    ///   Failure leaves the clock unchanged; callers must begin a fresh timeline at rollover.
    public mutating func advance(by frameCount: Int) throws -> MediaTime {
        guard let count = Int64(exactly: frameCount), count >= 0 else { throw MediaError.invalidTime }
        let next = samplePosition.addingReportingOverflow(count)
        guard !next.overflow else { throw MediaError.invalidTime }
        let start = timestamp
        currentTimestamp = try MediaTime(value: next.partialValue, timescale: Int32(sampleRate))
        return start
    }

    /// Replaces the timeline position, including after a caller-owned seek or discontinuity.
    /// - Parameter samplePosition: Nonnegative frame index; zero begins a new local timeline.
    /// - Throws: `MediaError.invalidTime` for a negative position, leaving state unchanged.
    public mutating func reset(to samplePosition: Int64 = 0) throws {
        guard samplePosition >= 0 else { throw MediaError.invalidTime }
        currentTimestamp = try MediaTime(value: samplePosition, timescale: Int32(sampleRate))
    }
}
