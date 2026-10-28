// File: Tests/DiscordCommandDSLTests/ArgumentValueTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

@testable import DiscordCommandDSL
import DiscordCore
import DiscordModels
import Foundation
import Testing

/// Exercises local codecs without transports, handler execution, resource hydration, or Discord credentials.
@Suite struct ArgumentValueTests {
    /// String and boolean conversion preserve exact Unicode/boolean values and expose their registration kinds.
    @Test func scalarSuccessAndKinds() throws {
        #expect(String.optionType == .string)
        #expect(Bool.optionType == .boolean)
        #expect(Int.optionType == .integer)
        #expect(Int64.optionType == .integer)
        #expect(Double.optionType == .number)
        #expect(try String.choices.isEmpty)
        #expect(!String.isOptional)
        for text in ["", "plain", "e\u{301}", "日本語🦊"] {
            let value = try String.decodeArgument(.value(.string(text)), resolved: .null)
            #expect(value.unicodeScalars.elementsEqual(text.unicodeScalars))
            #expect(value.argumentValue == .value(.string(text)))
        }
        for flag in [true, false] {
            #expect(try Bool.decodeArgument(.value(.bool(flag)), resolved: .absent) == flag)
            #expect(flag.argumentValue == .value(.bool(flag)))
        }
    }

    /// Required built-ins consistently distinguish omission, explicit null, and incompatible wire scalars.
    @Test func scalarPresenceAndKinds() throws {
        let inputs: [(Field<JSONValue>, ArgumentValueError)] = [
            (.absent, .missing), (.null, .nullValue), (.value(.null), .nullValue),
            (.value(.object([:])), .wrongKind), (.value(.array([])), .wrongKind)
        ]
        for (input, error) in inputs {
            #expect(throws: error) { try String.decodeArgument(input, resolved: .absent) }
            #expect(throws: error) { try Bool.decodeArgument(input, resolved: .absent) }
            #expect(throws: error) { try Int.decodeArgument(input, resolved: .absent) }
            #expect(throws: error) { try Int64.decodeArgument(input, resolved: .absent) }
            #expect(throws: error) { try Double.decodeArgument(input, resolved: .absent) }
        }
        #expect(throws: ArgumentValueError.wrongKind) { try String.decodeArgument(.value(.bool(true)), resolved: .absent) }
        #expect(throws: ArgumentValueError.wrongKind) { try Bool.decodeArgument(.value(.string("true")), resolved: .absent) }
        #expect(throws: ArgumentValueError.wrongKind) { try Bool.decodeArgument(number("1"), resolved: .absent) }
        #expect(throws: ArgumentValueError.wrongKind) { try Double.decodeArgument(.value(.string("1")), resolved: .absent) }
    }

    /// Exact safe integer boundaries, signed zero and ordinary integers round-trip without floating-point coercion.
    /// - Parameter text: Valid canonical integer text, including both documented extreme magnitudes.
    @Test(arguments: ["0", "-0", "1", "-42", "9007199254740991", "-9007199254740991"])
    func integerRoundTrip(text: String) throws {
        let integer = try Int64.decodeArgument(number(text), resolved: .absent)
        #expect(integer == Int64(text))
        #expect(try Int64.decodeArgument(integer.argumentValue, resolved: .absent) == integer)
        let native = try Int.decodeArgument(number(text), resolved: .null)
        #expect(Int64(native) == integer)
        #expect(try Int.decodeArgument(native.argumentValue, resolved: .absent) == native)
    }

    /// Integers outside the safe range and signed machine range fail before conversion or default encoding.
    /// - Parameter text: Valid JSON integer text whose magnitude exceeds Discord's documented bound.
    @Test(arguments: ["9007199254740992", "-9007199254740992", "9223372036854775807", "-9223372036854775808",
                      "9223372036854775808", "18446744073709551615", "99999999999999999999999999999999999999"])
    func integerOverflow(text: String) throws {
        #expect(throws: ArgumentValueError.outOfRange) { try Int64.decodeArgument(number(text), resolved: .absent) }
        #expect(throws: ArgumentValueError.outOfRange) { try Int.decodeArgument(number(text), resolved: .absent) }
        #expect(throws: ArgumentValueError.outOfRange) { try Int64.max.argumentValue }
        #expect(throws: ArgumentValueError.outOfRange) { try Int64.min.argumentValue }
        #expect(throws: ArgumentValueError.outOfRange) { try Int.max.argumentValue }
    }

    /// Integer codecs follow the existing interaction parser and reject decimal/exponent syntax despite integral values.
    /// - Parameter text: Valid numeric JSON whose spelling is unsuitable for the integer option kind.
    @Test(arguments: ["1.0", "1e0", "1E1", "-0.0", "1e10000"])
    func integerNonintegerSpellings(text: String) throws {
        #expect(throws: ArgumentValueError.wrongKind) { try Int64.decodeArgument(number(text), resolved: .absent) }
        #expect(throws: ArgumentValueError.wrongKind) { try Int.decodeArgument(number(text), resolved: .absent) }
    }

    /// Number options accept fractional/exponent forms, both exact boundaries, leading fractional zeroes and underflow.
    /// - Parameter text: Valid number within the exact mathematical ±2^53 boundary.
    @Test(arguments: ["0", "-0", "1.25", "-4.5", "1e3", "9007199254740992", "-9007199254740992",
                      "9007199254740992.000", "90071992547409920e-1", "9.007199254740992e15", "0.00009",
                      "0.0009007199254740992e19", "1e-999999999999999999999999", "0e999999999999999999999999"])
    func numberRoundTrip(text: String) throws {
        let value = try Double.decodeArgument(number(text), resolved: .absent)
        #expect(value.isFinite)
        #expect(abs(value) <= 9_007_199_254_740_992)
        #expect(value == Double(text))
        #expect(try Double.decodeArgument(value.argumentValue, resolved: .absent) == value)
    }

    /// Exact decimal admission rejects values that would round down into the accepted boundary and enormous exponents.
    /// - Parameter text: Mathematically out-of-range finite-syntax JSON number.
    @Test(arguments: ["9007199254740993", "-9007199254740993", "9007199254740992.0000001", "-9007199254740992.1",
                      "90071992547409921e-1", "9.007199254740993e15", "1e16", "1e999999999999999999999999",
                      "1e309", "-1e309", "900719925474099200000001e-8"])
    func exactNumberOverflow(text: String) throws {
        #expect(throws: ArgumentValueError.outOfRange) { try Double.decodeArgument(number(text), resolved: .absent) }
    }

    /// In-memory nonfinite numbers and values beyond the boundary fail explicit encoding; negative zero remains signed.
    @Test func numberEncodingValidation() throws {
        for value in [Double.nan, Double.infinity, -Double.infinity, 9_007_199_254_740_994, -9_007_199_254_740_994] {
            #expect(throws: ArgumentValueError.outOfRange) { try value.argumentValue }
        }
        let negativeZero = try Double.decodeArgument(number("-0.0"), resolved: .absent)
        #expect(negativeZero.sign == .minus)
        #expect(try negativeZero.argumentValue == number("-0.0"))
    }

    /// Exact decimal ordering covers fractional precision beyond Double, signed zero and arbitrary-width exponent carry/borrow.
    /// Every comparison is also reversed to exercise sign/order symmetry without exposing private arithmetic helpers.
    @Test func exactNumberComparisons() throws {
        let cases: [(String, String, Int)] = [
            ("0", "-0", 0), ("0e999999999999999999999", "-0.00e-999999999999999999999", 0),
            ("0", "1", -1), ("0", "-1", 1), ("-1", "1", -1),
            ("1", "1.0", 0), ("10", "1e1", 0), ("1e-1", "0.1", 0),
            ("1e+000000001", "10", 0), ("0.0001", "1e-4", 0),
            ("1.0000000000000001", "1.0", 1), ("-1.0000000000000001", "-1.0", -1),
            ("0.999999999999999999999", "1", -1), ("100.0000000001", "100", 1),
            ("1", "0.01", 1), ("-1", "-0.01", -1),
            ("1000", "999", 1), ("10", "100", -1),
            ("1e-999999999999999999999", "1e-999999999999999999998", -1),
            ("1e999999999999999999999", "1e999999999999999999998", 1),
            ("1e999999999999999999999", "1e-999999999999999999999", 1),
            ("1e-100000000000000000000", "0.1e-99999999999999999999", 0),
            ("10e99999999999999999999", "1e100000000000000000000", 0),
            ("1e-99999999999999999999", "10e-100000000000000000000", 0),
            ("1e-100000000000000000000", "9e-100000000000000000001", 1),
            ("-1e999999999999999999999", "-1e999999999999999999998", -1),
            ("1.000000000000000000001e-99999999999999999999", "1e-99999999999999999999", 1),
            ("0.001e1", "1e-2", 0), ("0.001e4", "10", 0), ("0.001e2", "0.1", 0)
        ]
        for (lhs, rhs, expected) in cases {
            let left = try JSONNumber(rawValue: lhs)
            let right = try JSONNumber(rawValue: rhs)
            #expect(argumentCompareNumbers(left, right) == expected)
            #expect(argumentCompareNumbers(right, left) == -expected)
            #expect(argumentCompareNumbers(left, left) == 0)
        }
    }

    /// Optional omission is distinct from explicit null; wrappers forward all present states and preserve choice metadata.
    @Test func optionalPresence() throws {
        #expect(Optional<String>.isOptional)
        #expect(Optional<String>.optionType == .string)
        #expect(try Optional<String>.choices.isEmpty)
        #expect(try Optional<String>.decodeArgument(.absent, resolved: .null) == nil)
        #expect(try Optional<String>.decodeArgument(.value(.string("")), resolved: .absent) == "")
        #expect(try Optional<String>.none.argumentValue == .absent)
        #expect(try Optional<String>.some("value").argumentValue == .value(.string("value")))
        #expect(throws: ArgumentValueError.nullValue) { try Optional<String>.decodeArgument(.null, resolved: .absent) }
        #expect(throws: ArgumentValueError.nullValue) { try Optional<String>.decodeArgument(.value(.null), resolved: .absent) }
        #expect(throws: ArgumentValueError.wrongKind) { try Optional<String>.decodeArgument(.value(.bool(false)), resolved: .absent) }
        #expect(throws: ArgumentValueError.outOfRange) { try Optional<Double>.some(.nan).argumentValue }
        #expect(try Optional<NullArgument>.decodeArgument(.null, resolved: .absent) == .some(NullArgument()))
        #expect(try Optional<NullArgument>.some(NullArgument()).argumentValue == .null)
    }

    /// Explicit enums produce declaration-order choices and custom display text; only exact known raw values decode.
    @Test func explicitChoiceEnums() throws {
        #expect(Flavor.optionType == .string)
        #expect(Flavor.sweet.choiceName == "sweet")
        #expect(try Flavor.choices.map { $0.jsonValue() } == [
            .object(["name": .string("sweet"), "value": .string("sweet")]),
            .object(["name": .string("Savory flavor"), "value": .string("savory")])
        ])
        #expect(try Flavor.decodeArgument(.value(.string("savory")), resolved: .absent) == .savory)
        #expect(try Flavor.savory.argumentValue == .value(.string("savory")))
        #expect(try Optional<Flavor>.choices.map { $0.jsonValue() } == Flavor.choices.map { $0.jsonValue() })
        #expect(throws: ArgumentValueError.invalidChoice) { try Flavor.decodeArgument(.value(.string("SWEET")), resolved: .absent) }
        #expect(throws: ArgumentValueError.wrongKind) { try Flavor.decodeArgument(.value(.bool(false)), resolved: .absent) }
        #expect(throws: ArgumentValueError.missing) { try Flavor.decodeArgument(.absent, resolved: .absent) }
        #expect(throws: ArgumentValueError.nullValue) { try Flavor.decodeArgument(.null, resolved: .absent) }
    }

    /// Invalid custom choice collections fail explicitly instead of silently removing cases or losing their registration constraint.
    @Test func invalidChoiceSchemas() throws {
        #expect(throws: ArgumentValueError.invalidChoice) { try EmptyChoice.choices }
        #expect(throws: ArgumentValueError.invalidChoice) { try DuplicateChoice.choices }
        #expect(throws: ArgumentValueError.invalidChoice) { try ExcessiveChoice.choices }
        #expect(throws: ArgumentValueError.invalidChoice) { try InvalidNameChoice.choices }
        #expect(throws: ArgumentValueError.invalidChoice) { try InvalidValueChoice.choices }
        #expect(throws: ArgumentValueError.invalidChoice) { try DuplicateChoice.decodeArgument(.value(.string("same")), resolved: .absent) }
        #expect(throws: ArgumentValueError.invalidChoice) { try OpenChoice(rawValue: "unknown")!.argumentValue }
        #expect(try OpenChoice(rawValue: "known")!.argumentValue == .value(.string("known")))
        #expect(try BoundaryChoice.choices.count == 25)
        #expect(try BoundaryChoice.choices.allSatisfy { choice in
            guard case .string(let value) = choice.value else { return false }
            return value.unicodeScalars.count == 100
        })
        #expect(try EmptyValueChoice.decodeArgument(.value(.string("")), resolved: .absent) == .empty)
        #expect(try EmptyValueChoice.empty.argumentValue == .value(.string("")))
    }

    /// Every entity kind accepts all 64 snowflake bits, preserves unresolved states and encodes only canonical strings.
    @Test func unresolvedEntityKindsAndConstructors() throws {
        let input = Field<JSONValue>.value(.string("18446744073709551615"))
        let user = try UserReference.decodeArgument(input, resolved: .absent)
        let channel = try ChannelReference.decodeArgument(input, resolved: .absent)
        let role = try RoleReference.decodeArgument(input, resolved: .absent)
        let attachment = try AttachmentReference.decodeArgument(input, resolved: .absent)
        let mentionable = try MentionableReference.decodeArgument(input, resolved: .absent)
        #expect(user == UserReference(id: UserID(rawValue: .max)))
        #expect(channel == ChannelReference(id: ChannelID(rawValue: .max)))
        #expect(role == RoleReference(id: RoleID(rawValue: .max)))
        #expect(attachment == AttachmentReference(id: AttachmentID(rawValue: .max)))
        #expect(mentionable == MentionableReference(id: MentionableID(rawValue: .max)))
        #expect(user.argumentValue == input)
        #expect(channel.argumentValue == input)
        #expect(role.argumentValue == input)
        #expect(attachment.argumentValue == input)
        #expect(mentionable.argumentValue == input)
        #expect(UserReference.optionType == .user)
        #expect(ChannelReference.optionType == .channel)
        #expect(RoleReference.optionType == .role)
        #expect(AttachmentReference.optionType == .attachment)
        #expect(MentionableReference.optionType == .mentionable)
        #expect(try UserReference.decodeArgument(.value(.string("0000")), resolved: .absent).argumentValue == .value(.string("0")))
    }

    /// Entity codecs reject missing/null/wrong-kind input and malformed/overflowing identifiers uniformly.
    @Test func invalidEntityIdentifiers() throws {
        let invalid = ["", "-1", "+1", " 1", "1 ", "1.0", "1e2", "١", "18446744073709551616"]
        var cases: [(Field<JSONValue>, ArgumentValueError)] = invalid.map { (.value(.string($0)), .invalidIdentifier) }
        cases += [(.absent, .missing), (.null, .nullValue), (.value(.null), .nullValue),
                  (.value(.bool(true)), .wrongKind), (try number("1"), .wrongKind)]
        for (input, error) in cases {
            #expect(throws: error) { try UserReference.decodeArgument(input, resolved: .absent) }
            #expect(throws: error) { try ChannelReference.decodeArgument(input, resolved: .absent) }
            #expect(throws: error) { try RoleReference.decodeArgument(input, resolved: .absent) }
            #expect(throws: error) { try AttachmentReference.decodeArgument(input, resolved: .absent) }
            #expect(throws: error) { try MentionableReference.decodeArgument(input, resolved: .absent) }
        }
    }

    /// Resolved objects/category maps retain independent absent/null states and missing keys never create partial resources.
    @Test func resolvedPresenceStates() throws {
        let input = Field<JSONValue>.value(.string("7"))
        #expect(try UserReference.decodeArgument(input, resolved: .null).user == .null)
        #expect(try UserReference.decodeArgument(input, resolved: .null).member == .null)
        #expect(try ChannelReference.decodeArgument(input, resolved: .null).channel == .null)
        #expect(try RoleReference.decodeArgument(input, resolved: .null).role == .null)
        #expect(try AttachmentReference.decodeArgument(input, resolved: .null).attachment == .null)
        let nullMentionable = try MentionableReference.decodeArgument(input, resolved: .null)
        #expect(nullMentionable.user == .null && nullMentionable.member == .null && nullMentionable.role == .null)
        let empty = try resolved(#"{"users":{},"members":{},"roles":{},"channels":{},"attachments":{}}"#)
        #expect(try UserReference.decodeArgument(input, resolved: empty).user == .absent)
        #expect(try UserReference.decodeArgument(input, resolved: empty).member == .absent)
        #expect(try ChannelReference.decodeArgument(input, resolved: empty).channel == .absent)
        #expect(try RoleReference.decodeArgument(input, resolved: empty).role == .absent)
        #expect(try AttachmentReference.decodeArgument(input, resolved: empty).attachment == .absent)
        #expect(try MentionableReference.decodeArgument(input, resolved: empty).role == .absent)
        let absentCategories = try resolved("{}")
        #expect(try UserReference.decodeArgument(input, resolved: absentCategories).user == .absent)
        #expect(try ChannelReference.decodeArgument(input, resolved: absentCategories).channel == .absent)
    }

    /// Partial users/members/channels/roles/attachments remain exact and unknown fields survive local reference projection.
    @Test func resolvedEntityObservations() throws {
        let data = try resolved(#"{"users":{"7":{"id":"7","username":"u","avatar":null,"future":1e100}},"members":{"7":{"roles":[],"permissions":"8"}},"roles":{"7":{"id":"7","name":"r","future":true}},"channels":{"7":{"id":"7","name":"c","type":0}},"attachments":{"7":{"id":"7","filename":"a","size":1,"url":"https://example.invalid/a","proxy_url":"https://example.invalid/p"}}}"#)
        let input = Field<JSONValue>.value(.string("7"))
        let user = try UserReference.decodeArgument(input, resolved: data)
        guard case .value(let author) = user.user, case .value(let member) = user.member else { Issue.record("Missing local observations"); return }
        #expect(author.id == UserID(rawValue: 7))
        #expect(author.rawFields["future"] == .number(try JSONNumber(rawValue: "1e100")))
        #expect(member.rawFields["permissions"] == .string("8"))
        let channel = try ChannelReference.decodeArgument(input, resolved: data)
        let role = try RoleReference.decodeArgument(input, resolved: data)
        let attachment = try AttachmentReference.decodeArgument(input, resolved: data)
        guard case .value(let channelObject) = channel.channel, case .value(let roleObject) = role.role,
              case .value(let attachmentObject) = attachment.attachment else { Issue.record("Missing resolved objects"); return }
        #expect(channelObject.name == .value("c"))
        #expect(roleObject.rawFields["future"] == .bool(true))
        #expect(attachmentObject.filename == "a")
        let mentionable = try MentionableReference.decodeArgument(input, resolved: data)
        #expect(mentionable.user == user.user && mentionable.member == user.member && mentionable.role == role.role)
        #expect(UserReference(id: user.id, user: user.user, member: user.member) == user)
        #expect(ChannelReference(id: channel.id, channel: channel.channel) == channel)
        #expect(RoleReference(id: role.id, role: role.role) == role)
        #expect(AttachmentReference(id: attachment.id, attachment: attachment.attachment) == attachment)
        #expect(MentionableReference(id: mentionable.id, user: mentionable.user, member: mentionable.member, role: mentionable.role) == mentionable)
        #expect(try UserReference.decodeArgument(.value(.string("0007")), resolved: data).user == user.user)
        let padded = try resolved(#"{"users":{"0007":{"id":"7","username":"padded","avatar":null}}}"#)
        guard case .value(let paddedUser) = try UserReference.decodeArgument(.value(.string("0007")), resolved: padded).user
        else { Issue.record("Padded map key was lost"); return }
        #expect(paddedUser.username == "padded")
    }

    /// Resolved map keys cannot bind one selected ID to another object's ID; absent partial IDs remain supported.
    @Test func contradictoryResolvedIdentifiers() throws {
        let input = Field<JSONValue>.value(.string("7"))
        let users = try resolved(#"{"users":{"7":{"id":"8","username":"u","avatar":null}}}"#)
        let channels = try resolved(#"{"channels":{"7":{"id":"8"}}}"#)
        let roles = try resolved(#"{"roles":{"7":{"id":"invalid"}}}"#)
        let attachments = try resolved(#"{"attachments":{"7":{"id":"8","filename":"a","size":1,"url":"u","proxy_url":"p"}}}"#)
        #expect(throws: ArgumentValueError.invalidIdentifier) { try UserReference.decodeArgument(input, resolved: users) }
        #expect(throws: ArgumentValueError.invalidIdentifier) { try MentionableReference.decodeArgument(input, resolved: users) }
        #expect(throws: ArgumentValueError.invalidIdentifier) { try ChannelReference.decodeArgument(input, resolved: channels) }
        #expect(throws: ArgumentValueError.invalidIdentifier) { try RoleReference.decodeArgument(input, resolved: roles) }
        #expect(throws: ArgumentValueError.invalidIdentifier) { try MentionableReference.decodeArgument(input, resolved: roles) }
        #expect(throws: ArgumentValueError.invalidIdentifier) { try AttachmentReference.decodeArgument(input, resolved: attachments) }
        let partial = try resolved(#"{"channels":{"7":{"name":"partial"}},"roles":{"7":{"name":"partial"}}}"#)
        guard case .value(let channel) = try ChannelReference.decodeArgument(input, resolved: partial).channel,
              case .value(let role) = try RoleReference.decodeArgument(input, resolved: partial).role
        else { Issue.record("Partial resources were rejected"); return }
        #expect(channel.id == .absent && role.id == .absent)
    }

    /// Constructs an exact numeric test scalar through the same grammar validator used by production models.
    /// - Parameter text: Complete valid JSON numeric spelling.
    /// - Returns: A present numeric scalar preserving its lexeme.
    /// - Throws: `JSONValueError.invalidNumber` if a fixture is malformed.
    private func number(_ text: String) throws -> Field<JSONValue> { .value(.number(try JSONNumber(rawValue: text))) }

    /// Parses bounded synthetic resolved data without external lookups or credentials.
    /// - Parameter text: Complete JSON object with optional partial resource maps.
    /// - Returns: The present exact resolved projection.
    /// - Throws: Model/JSON errors when a test fixture violates its existing schema.
    private func resolved(_ text: String) throws -> Field<InteractionResolvedData> {
        .value(try InteractionResolvedData(data: Data(text.utf8)))
    }
}

/// Exercises explicit optional forwarding to a custom codec that deliberately permits null.
private struct NullArgument: ArgumentValue, Equatable {
    static let optionType = ApplicationCommandOptionType.string
    /// Accepts both explicit-null representations to demonstrate that Optional delegates rather than consumes them.
    /// - Parameters:
    ///   - value: Required explicit-null input.
    ///   - resolved: Ignored local resources.
    /// - Returns: An inert marker for explicit null.
    /// - Throws: `.wrongKind` for any input that is not explicit null.
    static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self {
        switch value {
        case .null, .value(.null): return Self()
        default: throw ArgumentValueError.wrongKind
        }
    }
    /// Encodes the deliberately supported explicit-null state.
    var argumentValue: Field<JSONValue> { .null }
}

/// Valid explicit enum with stable raw values and one display-name override.
private enum Flavor: String, StringArgumentChoice {
    case sweet, savory
    /// Supplies a human-readable override while preserving the raw value used by the wire.
    var choiceName: String { self == .sweet ? rawValue : "Savory flavor" }
}

/// A custom raw-representable type whose constructor admits values beyond its explicit allowed cases.
private struct OpenChoice: StringArgumentChoice {
    let rawValue: String
    static let allCases = [Self(rawValue: "known")!]
    /// Retains arbitrary raw text so membership validation can be tested independently of construction.
    /// - Parameter rawValue: Any exact candidate string.
    /// - Returns: Always a constructed value; only the explicit allowed case may encode.
    init?(rawValue: String) { self.rawValue = rawValue }
}

/// Invalid empty declaration cannot accidentally become an unrestricted string schema.
private enum EmptyChoice: String, StringArgumentChoice {
    case value
    static let allCases: [Self] = []
}

/// Invalid duplicate explicit case collection verifies bounded duplicate validation.
private enum DuplicateChoice: String, StringArgumentChoice {
    case same
    static let allCases: [Self] = [.same, .same]
}

/// Invalid excessive collection demonstrates rejection on the twenty-sixth case without full enumeration.
private struct ExcessiveChoice: StringArgumentChoice {
    let rawValue: String
    static let allCases = (0..<26).map { Self(rawValue: String($0))! }
    /// Retains unique candidate text so the case-count test reaches the twenty-sixth case.
    /// - Parameter rawValue: The exact locally declared numeric string.
    /// - Returns: An inert choice candidate without validating the complete collection.
    init?(rawValue: String) { self.rawValue = rawValue }
}

/// Invalid display name verifies propagation of existing registration validation as a sanitized choice failure.
private enum InvalidNameChoice: String, StringArgumentChoice {
    case value
    /// Returns invalid empty display text without changing the raw wire value.
    var choiceName: String { "" }
}

/// Invalid raw value verifies the existing one-hundred-scalar choice-value bound.
private struct InvalidValueChoice: StringArgumentChoice {
    let rawValue: String
    static let allCases = [Self(rawValue: String(repeating: "a", count: 101))!]
    /// Retains a deliberately excessive raw string for schema validation tests.
    /// - Parameter rawValue: Unvalidated raw candidate text.
    /// - Returns: A local marker without registration or runtime work.
    init?(rawValue: String) { self.rawValue = rawValue }
    /// Keeps display text valid so the failure specifically exercises the raw-value limit.
    var choiceName: String { "Valid name" }
}

/// Valid maximum case/text boundaries verify that inclusive limits are admitted.
private struct BoundaryChoice: StringArgumentChoice {
    let rawValue: String
    static let allCases = (0..<25).map { index in
        Self(rawValue: String(repeating: "🦊", count: 100 - String(index).count) + String(index))!
    }
    /// Retains one valid one-hundred-scalar raw value used as both display text and exact option value.
    /// - Parameter rawValue: Unnormalized raw choice text with at most one hundred Unicode scalars.
    /// - Returns: A local choice candidate without evaluating registration or handlers.
    init?(rawValue: String) { self.rawValue = rawValue }
}

/// Empty string values are valid when an independently supplied display name is nonempty.
private enum EmptyValueChoice: String, StringArgumentChoice {
    case empty = ""
    /// Supplies valid display text for the intentionally empty wire value.
    var choiceName: String { "Empty value" }
}
