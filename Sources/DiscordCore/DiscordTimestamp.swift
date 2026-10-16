import Foundation

/// Validation failures for the timestamp profile accepted by `DiscordTimestamp`.
public enum DiscordTimestampError: Error, Sendable, Equatable {
    /// The input does not match the documented date/time, fraction, or offset spelling.
    case invalidFormat
    /// A component is outside its permitted range or names a nonexistent Gregorian date.
    case invalidDate
}

/// A lossless ISO-8601 timestamp with an exact whole-second and nanosecond representation.
///
/// Accepts the extended Gregorian profile `YYYY-MM-DDTHH:mm:ss[.fraction](Z|±HH:mm)`:
/// years 0001–9999, seconds 00–59, offsets 00:00–23:59, and one through nine
/// fractional digits. Leap seconds, basic-format dates, local times, lowercase
/// separators, and fractions beyond nanosecond precision are rejected explicitly.
/// These are deliberate parser limits, not a claim that ISO-8601 excludes other forms.
///
/// The original string, fractional precision, and offset survive Codable unchanged.
/// Equality and hashing compare this representation, so two offset spellings of the
/// same instant remain distinct. Compare `unixSeconds` and `nanosecond` for instant
/// equality. Discord describes model timestamps as ISO8601 without a universal
/// fractional-precision guarantee: <https://docs.discord.com/developers/reference#iso8601-datetime>.
public struct DiscordTimestamp: Sendable, Hashable, Codable {
    /// The validated input string, retained without normalizing its fractional digits or offset.
    public let rawValue: String
    /// Integral UTC seconds since 1970-01-01T00:00:00Z, using floor semantics before the epoch.
    public let unixSeconds: Int64
    /// Fractional nanoseconds within the second, in `0...999_999_999`.
    public let nanosecond: UInt32

    /// A Foundation date approximating this instant using binary floating-point seconds.
    ///
    /// Conversion may round subsecond precision, especially far from the epoch;
    /// use the exact components or `rawValue` when lossless round trips matter.
    /// The computed value owns no external resource and requires no shared formatter.
    public var date: Date {
        Date(timeIntervalSince1970: Double(unixSeconds) + Double(nanosecond) / 1_000_000_000)
    }

    /// Validates and preserves a timestamp in the documented extended ISO-8601 profile.
    ///
    /// Validation and Gregorian conversion use integer arithmetic in linear time
    /// over at most 35 ASCII bytes, without shared mutable state or locale effects.
    /// - Parameter rawValue: A complete timestamp with an explicit UTC or numeric offset.
    /// - Throws: `DiscordTimestampError.invalidFormat` for unsupported syntax or precision;
    ///   `.invalidDate` for out-of-range components or an impossible calendar date.
    public init(rawValue: String) throws {
        guard (20...35).contains(rawValue.utf8.count) else { throw DiscordTimestampError.invalidFormat }
        let bytes = Array(rawValue.utf8)
        guard bytes[4] == 45, bytes[7] == 45,
              bytes[10] == 84, bytes[13] == 58, bytes[16] == 58 else {
            throw DiscordTimestampError.invalidFormat
        }
        let year = try Self.digits(bytes, offset: 0, count: 4)
        let month = try Self.digits(bytes, offset: 5, count: 2)
        let day = try Self.digits(bytes, offset: 8, count: 2)
        let hour = try Self.digits(bytes, offset: 11, count: 2)
        let minute = try Self.digits(bytes, offset: 14, count: 2)
        let second = try Self.digits(bytes, offset: 17, count: 2)
        guard (1...9999).contains(year), (1...12).contains(month),
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else {
            throw DiscordTimestampError.invalidDate
        }
        let leap = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
        let daysInMonth = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...daysInMonth[month - 1]).contains(day) else { throw DiscordTimestampError.invalidDate }

        var index = 19
        var nanos: UInt32 = 0
        if bytes[index] == 46 {
            index += 1
            let first = index
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
            let precision = index - first
            guard (1...9).contains(precision) else { throw DiscordTimestampError.invalidFormat }
            nanos = UInt32(try Self.digits(bytes, offset: first, count: precision))
            for _ in precision..<9 { nanos *= 10 }
        }
        guard index < bytes.count else { throw DiscordTimestampError.invalidFormat }
        var offset = 0
        if bytes[index] == 90 {
            guard index + 1 == bytes.count else { throw DiscordTimestampError.invalidFormat }
        } else {
            guard bytes[index] == 43 || bytes[index] == 45,
                  index + 6 == bytes.count, bytes[index + 3] == 58 else {
                throw DiscordTimestampError.invalidFormat
            }
            let offsetHour = try Self.digits(bytes, offset: index + 1, count: 2)
            let offsetMinute = try Self.digits(bytes, offset: index + 4, count: 2)
            guard (0...23).contains(offsetHour), (0...59).contains(offsetMinute) else {
                throw DiscordTimestampError.invalidDate
            }
            offset = (offsetHour * 3600 + offsetMinute * 60) * (bytes[index] == 45 ? -1 : 1)
        }
        let days = Self.daysSinceEpoch(year: year, month: month, day: day)
        self.rawValue = rawValue
        unixSeconds = Int64(days * 86400 + hour * 3600 + minute * 60 + second - offset)
        nanosecond = nanos
    }

    /// Decodes a string timestamp with the same syntax and precision validation as the raw initializer.
    /// - Parameter decoder: The decoder positioned at an ISO-8601 string.
    /// - Throws: A decoding type error for non-strings, or a data-corruption error for invalid timestamps.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do { try self.init(rawValue: value) }
        catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported or invalid ISO-8601 timestamp.")
        }
    }

    /// Encodes the original timestamp string with its exact input precision and offset.
    /// - Parameter encoder: The destination string encoder.
    /// - Throws: Errors from the supplied encoder; no calendar conversion occurs.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Reads a fixed ASCII digit slice after its caller has established array bounds.
    /// - Parameters:
    ///   - bytes: UTF-8 bytes of the timestamp.
    ///   - offset: First digit index, with `offset + count <= bytes.count`.
    ///   - count: Number of digits, between one and nine for the current parser.
    /// - Returns: The nonnegative decimal component.
    /// - Throws: `DiscordTimestampError.invalidFormat` if any byte is not an ASCII digit.
    private static func digits(_ bytes: [UInt8], offset: Int, count: Int) throws -> Int {
        var value = 0
        for index in offset..<(offset + count) {
            guard (48...57).contains(bytes[index]) else { throw DiscordTimestampError.invalidFormat }
            value = value * 10 + Int(bytes[index] - 48)
        }
        return value
    }

    /// Converts a validated proleptic Gregorian date to signed days since the Unix epoch.
    ///
    /// March-based 400-year eras avoid floating point, locale, and calendar cutover
    /// behavior. All intermediates fit in `Int` for the supported four-digit years.
    /// - Parameters:
    ///   - year: Valid Gregorian year in `1...9999`.
    ///   - month: Valid month in `1...12`.
    ///   - day: A valid day for that year and month.
    /// - Returns: Days relative to 1970-01-01, including negative values before that date.
    private static func daysSinceEpoch(year: Int, month: Int, day: Int) -> Int {
        let adjustedYear = year - (month <= 2 ? 1 : 0)
        let era = adjustedYear / 400
        let yearOfEra = adjustedYear - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146097 + dayOfEra - 719468
    }
}
