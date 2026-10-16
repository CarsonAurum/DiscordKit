import Foundation
import Testing
@testable import DiscordCore

/// Exact identifier arithmetic and credential diagnostic boundaries without I/O.
@Suite struct SnowflakeCredentialTests {
    /// Covers the full unsigned range, values beyond JSON's safe integer range,
    /// leading-zero canonicalization, ordering and exact decimal-string coding.
    /// - Parameter pair: Decimal input and its exact unsigned integer value.
    /// - Throws: Unexpected encoder/decoder or required-value failures.
    @Test(arguments: [
        ("0", UInt64(0)), ("00001", UInt64(1)),
        ("9007199254740993", UInt64(9_007_199_254_740_993)),
        ("18446744073709551615", UInt64.max),
    ])
    func decimalRoundTrips(pair: (String, UInt64)) throws {
        let value = try #require(UserID(pair.0))
        #expect(value.rawValue == pair.1)
        #expect(value.description == String(pair.1))
        #expect(value == UserID(rawValue: pair.1))
        #expect(Set([value, UserID(rawValue: pair.1)]).count == 1)
        let encoded = try JSONEncoder().encode(value)
        #expect(String(decoding: encoded, as: UTF8.self) == "\"\(pair.1)\"")
        #expect(try JSONDecoder().decode(UserID.self, from: encoded) == value)
        #expect(!(value < value))
        if pair.1 > 0 { #expect(UserID(rawValue: pair.1 - 1) < value) }
    }

    /// Ensures malformed identifiers never normalize into accepted IDs.
    /// - Parameter text: Invalid decimal input, including signs, spaces and overflow.
    @Test(arguments: ["", " ", "+1", "-1", "1.0", "1e3", "1_000", " 1", "1\n", "１２", "١", "18446744073709551616"])
    func rejectsMalformedDecimal(text: String) {
        #expect(UserID(text) == nil)
    }

    /// Rejects numeric/null/aggregate JSON and malformed or overflowing strings.
    /// - Parameter json: One invalid encoded snowflake value.
    @Test(arguments: ["null", "0", "9007199254740993", "true", "{}", "[]", "\"\"", "\"-1\"", "\"18446744073709551616\""])
    func rejectsInvalidWireIdentifiers(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(UserID.self, from: Data(json.utf8))
        }
    }

    /// Checks epoch/minimum/maximum extraction, non-timestamp low bits, Date units
    /// and checked construction at both boundaries without wall-clock assumptions.
    /// - Throws: Unexpected timestamp-construction errors.
    @Test func timestampBoundaries() throws {
        let epoch = UserID.epochMilliseconds
        let maximum = epoch + (UInt64.max >> 22)
        #expect(try UserID(timestampMilliseconds: epoch).rawValue == 0)
        #expect(try UserID(timestampMilliseconds: maximum).rawValue == UInt64.max & ~UInt64(0x3F_FFFF))
        #expect(UserID(rawValue: 0).timestampMilliseconds == epoch)
        #expect(UserID(rawValue: UInt64.max).timestampMilliseconds == maximum)
        #expect(UserID(rawValue: 0x3F_FFFF).timestampMilliseconds == epoch)
        #expect(UserID(rawValue: 1 << 22).timestampMilliseconds == epoch + 1)
        #expect(UserID(rawValue: 0).timestamp.timeIntervalSince1970 == 1_420_070_400)
        #expect(abs(UserID(rawValue: 1 << 22).timestamp.timeIntervalSince1970 - 1_420_070_400.001) < 0.000_001)
        #expect(throws: SnowflakeTimestampError.beforeEpoch) { try UserID(timestampMilliseconds: epoch - 1) }
        #expect(throws: SnowflakeTimestampError.outOfRange) { try UserID(timestampMilliseconds: maximum + 1) }
        #expect(throws: SnowflakeTimestampError.outOfRange) { try UserID(timestampMilliseconds: .max) }
    }

    /// Confirms provider IDs retain their exact opaque strings instead of sharing
    /// Discord snowflake numeric semantics, including empty and Unicode values.
    /// - Parameter text: A provider identifier with no shared validation assumptions.
    /// - Throws: Unexpected coding failures.
    @Test(arguments: ["", "0000123", "steam:18446744073709551616", "外部-ID", "a/b"])
    func externalIdentifiersRemainStrings(text: String) throws {
        let provider = ExternalProviderID(rawValue: text)
        let account = ExternalUserID(rawValue: text)
        #expect(provider.rawValue == text)
        #expect(account.rawValue == text)
        #expect(Set([provider, ExternalProviderID(rawValue: text)]).count == 1)
        let encoded = try JSONEncoder().encode(provider)
        #expect(try JSONDecoder().decode(ExternalProviderID.self, from: encoded) == provider)
        #expect(try JSONDecoder().decode(String.self, from: encoded) == text)
    }

    /// Ensures opaque provider IDs still reject nonstring wire values.
    /// - Parameter json: A JSON value that is not an opaque string.
    @Test(arguments: ["null", "12", "{}", "[]"])
    func rejectsNonstringExternalIdentifiers(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ExternalUserID.self, from: Data(json.utf8))
        }
    }

    /// Rejects empty credentials without attaching input to errors, and rejects
    /// whitespace/control characters that could alter authorization headers.
    /// - Parameter text: An invalid token string.
    @Test(arguments: ["", " ", "a b", "a\r\nb", "a\tb", "a\u{0}b", "a\u{7F}b", "a\u{80}b", "a\u{9F}b", "a\u{A0}b"])
    func rejectsInvalidCredentials(text: String) {
        #expect(throws: DiscordError.validation(text.isEmpty ? .emptyCredential : .invalidCredential)) {
            try BotToken(text)
        }
    }

    /// Checks explicit secret access, rethrowing, normal/debug descriptions and
    /// recursive dump reflection for every credential category without network I/O.
    /// - Throws: Unexpected credential-validation failures.
    @Test func credentialsConcealSecrets() throws {
        let sentinel = "SENTINEL.secret+/with%characters"
        let token = try BotToken(sentinel)
        #expect(token.withUnsafeValue { $0 } == sentinel)
        #expect(throws: ValidationFailure.invalidValue) {
            try token.withUnsafeValue { _ in throw ValidationFailure.invalidValue }
        }
        #expect(token.description == "[REDACTED]")
        #expect(token.debugDescription == "[REDACTED]")
        #expect(String(describing: token) == "[REDACTED]")
        #expect(String(reflecting: token) == "[REDACTED]")
        var tokenDump = ""
        dump(token, to: &tokenDump)
        #expect(!tokenDump.contains(sentinel))
        #expect(token.customMirror.children.count == 1)
        let credentials: [Credential] = [
            .none, .bot(token), .bearer(try BearerToken(sentinel)),
            .interaction(try InteractionToken(sentinel)),
            .webhook(WebhookID(rawValue: 1), try WebhookToken(sentinel)),
        ]
        for credential in credentials {
            #expect(!credential.description.contains(sentinel))
            #expect(credential.debugDescription == credential.description)
            #expect(String(reflecting: credential) == credential.description)
            var output = ""
            dump(credential, to: &output)
            #expect(!output.contains(sentinel))
            #expect(credential.customMirror.children.count == 1)
        }
        #expect(credentials.map(\.description) == [
            "Credential.none", "Credential.bot([REDACTED])", "Credential.bearer([REDACTED])",
            "Credential.interaction([REDACTED])", "Credential.webhook([REDACTED])",
        ])
        #expect(try ClientSecret(sentinel).withUnsafeValue { $0 } == sentinel)
    }
}
