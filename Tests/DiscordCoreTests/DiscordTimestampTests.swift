// File: Tests/DiscordCoreTests/DiscordTimestampTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordCore

/// Validates the documented timestamp profile with exact calendar/fraction semantics and Codable fidelity.
@Suite struct DiscordTimestampTests {
    /// Known proleptic Gregorian dates and explicit offsets map to exact Unix seconds, including epoch boundaries.
    /// - Parameters:
    ///   - source: A valid supported ISO-8601 timestamp.
    ///   - expectedSeconds: Exact floor UTC seconds since 1970-01-01.
    /// - Throws: Unexpected parse or round-trip failures.
    @Test(arguments: [
        ("1970-01-01T00:00:00Z", Int64(0)), ("1969-12-31T23:59:59Z", -1),
        ("1970-01-01T01:00:00+01:00", 0), ("1970-01-01T00:00:00-01:00", 3600),
        ("1970-01-01T23:59:00+23:59", 0), ("1970-01-01T00:00:00-23:59", 86340),
        ("2000-02-29T00:00:00Z", 951782400), ("2020-02-29T00:00:00Z", 1582934400),
        ("0001-01-01T00:00:00Z", -62135596800), ("9999-12-31T23:59:59Z", 253402300799),
    ])
    func calendarAndOffsets(source: String, expectedSeconds: Int64) throws {
        let timestamp = try DiscordTimestamp(rawValue: source)
        #expect(timestamp.rawValue == source)
        #expect(timestamp.unixSeconds == expectedSeconds)
        #expect(timestamp.nanosecond == 0)
        #expect(timestamp.date == Date(timeIntervalSince1970: Double(expectedSeconds)))
        #expect(try JSONDecoder().decode(DiscordTimestamp.self, from: JSONEncoder().encode(timestamp)) == timestamp)
        #expect(Set([timestamp, timestamp]).count == 1)
    }

    /// Each accepted fractional precision preserves original spelling and pads to exact nanoseconds internally.
    /// - Parameters:
    ///   - fraction: One to nine ASCII fractional digits.
    ///   - expectedNanos: Exact fractional nanoseconds represented by those digits.
    /// - Throws: Unexpected parse or coding errors.
    @Test(arguments: [
        ("1", UInt32(100000000)), ("12", 120000000), ("123", 123000000), ("1234", 123400000),
        ("12345", 123450000), ("123456", 123456000), ("1234567", 123456700),
        ("12345678", 123456780), ("123456789", 123456789), ("000000001", 1), ("000", 0), ("999999999", 999999999),
    ])
    func fractionalPrecision(fraction: String, expectedNanos: UInt32) throws {
        let source = "1969-12-31T23:59:59." + fraction + "Z"
        let value = try DiscordTimestamp(rawValue: source)
        #expect(value.rawValue == source)
        #expect(value.unixSeconds == -1)
        #expect(value.nanosecond == expectedNanos)
        #expect(try JSONDecoder().decode(DiscordTimestamp.self, from: JSONEncoder().encode(value)) == value)
        #expect(abs(value.date.timeIntervalSince1970 - (-1 + Double(expectedNanos) / 1_000_000_000)) < 0.000001)
    }

    /// Unsupported ISO-8601 variants and malformed component syntax fail rather than being guessed or truncated.
    /// - Parameter source: Invalid syntax or unsupported precision/format.
    @Test(arguments: [
        "", "1970-01-01", "19700101T000000Z", "1970-01-01 00:00:00Z", "1970-01-01t00:00:00Z",
        "1970-01-01T00:00:00z", "1970-01-01T00:00:00", "1970-01-01T00:00:00.Z",
        "1970-01-01T00:00:00.1234567890Z", "1970-01-01T00:00:00,123Z", "1970-01-01T00:00:00.1",
        "1970-01-01T00:00:00+0000", "1970-01-01T00:00:00+00", "1970-01-01T00:00:00+00:00x",
        "1970-01-01T00:00:00Zx", "1970-01-01T00:00:00Q", "1970/01-01T00:00:00Z",
        "19x0-01-01T00:00:00Z", "1970-01-01T00:00:00+0x:00", "1970-01-01T00:00:00.１２Z",
    ])
    func unsupportedFormats(source: String) {
        #expect(throws: DiscordTimestampError.invalidFormat) { try DiscordTimestamp(rawValue: source) }
    }

    /// Out-of-range fields and nonexistent Gregorian dates fail with the date-validation error.
    /// - Parameter source: A syntactically complete timestamp with invalid calendar/time/offset components.
    @Test(arguments: [
        "0000-01-01T00:00:00Z", "1970-00-01T00:00:00Z", "1970-13-01T00:00:00Z",
        "1970-01-00T00:00:00Z", "1970-01-32T00:00:00Z", "1970-04-31T00:00:00Z",
        "1900-02-29T00:00:00Z", "2023-02-29T00:00:00Z", "2000-02-30T00:00:00Z",
        "1970-01-01T24:00:00Z", "1970-01-01T00:60:00Z", "1970-01-01T00:00:60Z",
        "1970-01-01T00:00:00+24:00", "1970-01-01T00:00:00-00:60",
    ])
    func invalidDates(source: String) {
        #expect(throws: DiscordTimestampError.invalidDate) { try DiscordTimestamp(rawValue: source) }
    }

    /// Equivalent instants retain distinct original representations, while malformed Codable values report data corruption.
    /// - Throws: Unexpected parsing failures for valid fixtures.
    @Test func representationAndCodableErrors() throws {
        #expect(throws: DiscordTimestampError.invalidFormat) {
            try DiscordTimestamp(rawValue: String(repeating: "0", count: 1_000_000))
        }
        let utc = try DiscordTimestamp(rawValue: "1970-01-01T00:00:00.100Z")
        let offset = try DiscordTimestamp(rawValue: "1970-01-01T01:00:00.1+01:00")
        #expect(utc != offset)
        #expect(utc.unixSeconds == offset.unixSeconds)
        #expect(utc.nanosecond == offset.nanosecond)
        #expect(utc.date == offset.date)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DiscordTimestamp.self, from: Data("\"invalid\"".utf8))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DiscordTimestamp.self, from: Data("0".utf8))
        }
    }
}
