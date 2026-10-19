import DiscordCommandDSL
import DiscordCore
import DiscordDSL
import DiscordModels
import Foundation
import Synchronization
import Testing

/// A local aggregate proving declaration-order lookup, optional absence and explicit default behavior.
private struct SchemaArguments: Sendable, Equatable {
    let text: String
    let flag: Bool?
    let count: Int64
}

/// Deliberately embeds submitted text in its thrown error so schema redaction can be verified.
private enum SchemaFixtureError: Error {
    case submitted(String)
    case expectedFailure
}

/// A custom string codec that always fails; discarded underlying errors must never escape the schema.
private struct RejectingSchemaArgument: ArgumentValue {
    /// Uses the ordinary string discriminator so envelope admission succeeds before codec rejection.
    static var optionType: ApplicationCommandOptionType { .string }

    /// Throws an intentionally unsafe fixture error to prove the schema replaces custom codec failures.
    /// - Parameters:
    ///   - value: Present string copied into the private fixture error, never into a public diagnostic.
    ///   - resolved: Ignored local partial resources.
    /// - Returns: Never returns successfully.
    /// - Throws: `SchemaFixtureError.submitted` for every input, containing the fixture's sensitive marker.
    static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self {
        throw SchemaFixtureError.submitted("private submitted marker")
    }

    /// Supplies valid wire text so default validation must exercise and sanitize the failing codec.
    var argumentValue: Field<JSONValue> { .value(.string("private default marker")) }
}

/// A deliberately permissive numeric codec, used to test independent schema wire/range admission.
private struct LaxSchemaNumber: ArgumentValue {
    let value: JSONValue
    /// Uses the number discriminator without adding independent value validation.
    static var optionType: ApplicationCommandOptionType { .number }

    /// Retains any present value; the schema must reject incompatible wire forms before this hook.
    /// - Parameters:
    ///   - value: Present scalar already admitted by the schema.
    ///   - resolved: Ignored local resources.
    /// - Returns: The exact retained scalar, preserving all decimal digits for constraint checks.
    /// - Throws: A fixture failure for absence, which the test schemas never intentionally admit.
    static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self {
        guard case .value(let value) = value else { throw SchemaFixtureError.expectedFailure }
        return Self(value: value)
    }

    /// Returns retained raw data without validation, letting schema default admission exercise its own guard.
    var argumentValue: Field<JSONValue> { .value(value) }
}

/// A fake structural codec proving manual custom conformance cannot introduce subcommands through a leaf schema.
private struct StructuralSchemaArgument: ArgumentValue {
    /// Intentionally invalid leaf kind; descriptor construction must reject it.
    static var optionType: ApplicationCommandOptionType { .subcommand }

    /// Supplies an inert value if called; structural admission should prevent this hook from running.
    /// - Parameters:
    ///   - value: Ignored synthetic input.
    ///   - resolved: Ignored local resources.
    /// - Returns: An empty fixture value without work.
    static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self { Self() }

    /// Supplies ordinary text that cannot make the structural discriminator valid.
    var argumentValue: Field<JSONValue> { .value(.string("value")) }
}

/// A local enum whose declaration-order choices become registration and runtime value restrictions.
private enum SchemaColor: String, StringArgumentChoice {
    case red, blue
}

/// Enumerates enough valid choice text to exercise aggregate registration admission across sibling options.
private struct LargeSchemaChoices: ArgumentValue {
    /// Uses the ordinary string option kind.
    static var optionType: ApplicationCommandOptionType { .string }
    /// Generates a valid bounded choice list whose combined sibling text may exceed the command bound.
    static var choices: [ApplicationCommandChoiceCreate] {
        /// Returns 25 individually valid choices without handler execution or I/O.
        /// - Throws: Unexpected owned choice-model validation failures fail test setup.
        get throws {
            try (0..<25).map { index in
                try ApplicationCommandChoiceCreate(name: String(repeating: "n", count: 98) + String(index),
                    value: .string(String(repeating: "v", count: 98) + String(index)))
            }
        }
    }

    /// Returns the inert fixture because this test only constructs registration metadata.
    /// - Parameters:
    ///   - value: Ignored local scalar.
    ///   - resolved: Ignored partial resources.
    /// - Returns: An empty fixture value without side effects.
    static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self { Self() }

    /// Supplies text solely to satisfy the codec contract; no test defaults this fixture.
    var argumentValue: Field<JSONValue> { .value(.string("unused")) }
}

/// An exact numeric choice that IEEE-754 rounding would incorrectly conflate with nearby values.
private struct ExactSchemaChoice: ArgumentValue {
    let raw: Field<JSONValue>
    /// Selects Discord's number leaf kind.
    static var optionType: ApplicationCommandOptionType { .number }
    /// Declares a fraction differing from one below ordinary Double precision.
    static var choices: [ApplicationCommandChoiceCreate] {
        /// Produces one bounded exact decimal registration choice.
        /// - Throws: Unexpected JSON/choice-model construction failures fail setup.
        get throws { [try .init(name: "Exact", value: .number(JSONNumber(rawValue: "1.0000000000000001")))] }
    }

    /// Retains the scalar so independent schema choice comparison supplies all admission semantics.
    /// - Parameters:
    ///   - value: Exact supplied scalar, already validated by the schema.
    ///   - resolved: Ignored partial resources.
    /// - Returns: A fixture wrapping the exact submitted spelling.
    static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self { Self(raw: value) }

    /// Returns the retained exact representation without normalization.
    var argumentValue: Field<JSONValue> { raw }
}

/// Synchronizes observations of custom codecs without actor tasks, sleeps or invocation timing assumptions.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private struct ObservedSchemaArgument: ArgumentValue {
    static let calls = Mutex(0)
    let text: String
    /// Uses the ordinary string discriminator.
    static var optionType: ApplicationCommandOptionType { .string }

    /// Counts one exact conversion and returns its string without starting background work.
    /// - Parameters:
    ///   - value: Required string scalar admitted by the schema.
    ///   - resolved: Ignored local resources.
    /// - Returns: The submitted string in a fixture wrapper.
    /// - Throws: Built-in String codec errors for malformed input.
    static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self {
        calls.withLock { $0 += 1 }
        return Self(text: try String.decodeArgument(value, resolved: resolved))
    }

    /// Preserves its text in the ordinary string wire shape.
    var argumentValue: Field<JSONValue> { .value(.string(text)) }
}

/// Complete manual-schema validation, kept serialized only for the explicit synchronous counter fixture.
@Suite(.serialized, .timeLimit(.minutes(1))) struct ArgumentTests {
    /// The pre-autocomplete initializer remains a usable function value with its exact original labels and arity.
    /// Forwarding preserves localized metadata, fallback behavior, constraints and the caller's source coordinate.
    /// - Throws: Unexpected descriptor, direct-model or invocation decoding errors fail the regression.
    @Test func originalInitializerFunctionReference() throws {
        let factory: (String, String, ArgumentDefault<String>, Field<[String: String]>,
            Field<[String: String]>, [ChannelType]?, JSONNumber?, JSONNumber?, Int?, Int?, [String]?,
            DefinitionSourceLocation?, String, UInt, UInt) throws -> ArgumentOption<String> =
                ArgumentOption<String>.init(name:description:defaultValue:nameLocalizations:descriptionLocalizations:channelTypes:minValue:maxValue:minLength:maxLength:fileTypes:source:fileID:line:column:)
        let option = try factory("query", "Query", .value("fallback"), .value(["de": "suche"]),
            .value(["de": "Suche"]), nil, nil, nil, 1, 32, nil, nil, "LegacyCaller", 7, 3)
        let direct = try ApplicationCommandOptionCreate(type: .string, name: "query", description: "Query",
            nameLocalizations: .value(["de": "suche"]), descriptionLocalizations: .value(["de": "Suche"]),
            required: false, minLength: 1, maxLength: 32)
        #expect(option.registration.jsonValue() == direct.jsonValue())
        #expect(option.source == DefinitionSourceLocation(fileID: "LegacyCaller", line: 7, column: 3))
        let schema = try CommandArgumentSchema<String>(options: [option.erased]) { try $0.value(for: option) }
        #expect(try schema.decode(options: [], commandName: "legacy") == "fallback")
        #expect(try schema.decode(options: Self.options(#"[{"name":"query","type":3,"value":"explicit"}]"#),
            commandName: "legacy") == "explicit")
        let explicit = DefinitionSourceLocation(fileID: "Explicit", line: 11, column: 2)
        let located = try factory("query", "Query", .none, .absent, .absent, nil, nil, nil,
            nil, nil, nil, explicit, "IgnoredCaller", 99, 99)
        #expect(located.source == explicit)
        #expect(located.registration.required == true)
    }

    /// Author order and inferred requiredness match direct registration, while omission remains distinct from defaulting.
    /// - Throws: Unexpected local descriptor/schema/parsing failures fail the test.
    @Test func orderedRegistrationAndDefaults() throws {
        let text = try ArgumentOption<String>(name: "text", description: "Text", minLength: 1, maxLength: 6)
        let flag = try ArgumentOption<Bool?>(name: "flag", description: "Flag")
        let count = try ArgumentOption<Int64>(name: "count", description: "Count", defaultValue: .value(3),
                                            minValue: JSONNumber(rawValue: "1"), maxValue: JSONNumber(rawValue: "5"))
        let schema = try CommandArgumentSchema<SchemaArguments>(options: [text.erased, .init(flag), count.erased]) { decoder in
            SchemaArguments(text: try decoder.value(for: text), flag: try decoder.value(for: flag), count: try decoder.value(for: count))
        }
        #expect(schema.options.map(\.name) == ["text", "flag", "count"])
        #expect(schema.options.map(\.required) == [true, false, false])
        #expect(schema.descriptors.map(\.name) == ["text", "flag", "count"])
        #expect(try schema.decode(options: Self.options(#"[{"name":"text","type":3,"value":"hello"}]"#),
                                  commandName: "check") == SchemaArguments(text: "hello", flag: nil, count: 3))
        #expect(try schema.decode(options: Self.options(#"[{"name":"count","type":4,"value":5},{"name":"flag","type":5,"value":false},{"name":"text","type":3,"value":"yes"}]"#),
                                  commandName: "check") == SchemaArguments(text: "yes", flag: false, count: 5))
    }

    /// Optional omission, explicit nil defaults and present fallback values remain distinct in metadata and behavior.
    /// Explicit null never silently selects a fallback, including on an optional option.
    /// - Throws: Unexpected local setup failures fail the test.
    @Test func optionalNilAndExplicitNull() throws {
        let omitted = try ArgumentOption<String?>(name: "text", description: "Text", source: Self.source)
        let nilDefault = try ArgumentOption<String?>(name: "text", description: "Text", defaultValue: .value(nil), source: Self.source)
        let valueDefault = try ArgumentOption<String?>(name: "text", description: "Text", defaultValue: .value("fallback"), source: Self.source)
        let absent = try CommandArgumentSchema<String?>(options: [omitted.erased], source: Self.source) { try $0.value(for: omitted) }
        let explicitNil = try CommandArgumentSchema<String?>(options: [nilDefault.erased], source: Self.source) { try $0.value(for: nilDefault) }
        let fallback = try CommandArgumentSchema<String?>(options: [valueDefault.erased], source: Self.source) { try $0.value(for: valueDefault) }
        #expect(try absent.decode(options: [], commandName: "check") == nil)
        #expect(try explicitNil.decode(options: [], commandName: "check") == nil)
        #expect(try fallback.decode(options: [], commandName: "check") == "fallback")
        #expect(absent.metadata != explicitNil.metadata)
        #expect(explicitNil.metadata != fallback.metadata)
        for schema in [absent, explicitNil, fallback] {
            #expect(throws: DiscordError.self) {
                _ = try schema.decode(options: Self.options(#"[{"name":"text","type":3,"value":null}]"#), commandName: "check")
            }
        }
        #expect(try fallback.decode(options: Self.options(#"[{"name":"text","type":3,"value":""}]"#), commandName: "check") == "")
    }

    /// Complete invocation envelopes reject duplicates, wrong discriminators, null, missing, nested and focused values.
    /// - Parameters:
    ///   - input: Synthetic ordinary or malformed interaction option array.
    ///   - code: Expected stable schema failure category.
    /// - Throws: Unexpected setup or missing expected diagnostics fail the test.
    @Test(arguments: [
        ("[]", ArgumentDiagnostic.Code.missingValue),
        (#"[{"name":"text","type":3}]"#, .missingValue),
        (#"[{"name":"text","type":5,"value":true}]"#, .wrongType),
        (#"[{"name":"text","type":999,"value":"secret"}]"#, .wrongType),
        (#"[{"name":"text","type":3,"value":"a"},{"name":"text","type":3,"value":"b"}]"#, .duplicateOption),
        (#"[{"name":"text","type":3,"value":"a"},{"name":"unknown-secret-name","type":3,"value":"secret"}]"#, .unknownOption),
        (#"[{"name":"text","type":3,"options":[]}]"#, .nestedOption),
        (#"[{"name":"text","type":3,"value":"a","focused":true}]"#, .focusedOption),
        (#"[{"name":"text","type":3,"value":"a","focused":false}]"#, .focusedOption)
    ]) func malformedInvocation(input: String, code: ArgumentDiagnostic.Code) throws {
        let text = try ArgumentOption<String>(name: "text", description: "Text", source: Self.source)
        let schema = try CommandArgumentSchema<String>(options: [text.erased]) { try $0.value(for: text) }
        let error = try Self.failure { _ = try schema.decode(options: Self.options(input), commandName: "check") }
        #expect(error.code == code)
        #expect(error.commandName == "check")
        if code == .unknownOption { #expect(error.optionName == nil) }
        #expect(!String(reflecting: error).contains("secret"))
        #expect(!String(describing: error).contains("secret"))
    }

    /// The existing public interaction parser rejects explicit-null option fields before schema decoding.
    /// - Parameter input: Controlled null scalar, child-array or focus-field fixture.
    /// - Throws: No error escapes; each owned model failure is asserted as a sanitized DiscordError.
    @Test(arguments: [#"[{"name":"text","type":3,"value":null}]"#,
        #"[{"name":"text","type":3,"value":"a","options":null}]"#,
        #"[{"name":"text","type":3,"value":"a","focused":null}]"#])
    func nullWireFieldsFailInOwnedModel(input: String) throws {
        #expect(throws: DiscordError.self) { _ = try Self.options(input) }
    }

    /// Explicit ignoring admits only ordinary future scalar leaves; duplicate/focus/nesting/null admission stays strict.
    /// - Throws: Unexpected local parsing or setup errors fail the test.
    @Test func unknownPolicyAndSubmittedBounds() throws {
        let text = try ArgumentOption<String>(name: "text", description: "Text")
        let schema = try CommandArgumentSchema<String>(options: [text.erased], unknownOptions: .ignore) { try $0.value(for: text) }
        #expect(try schema.decode(options: Self.options(#"[{"name":"future","type":999,"value":"ignored"},{"name":"text","type":3,"value":"kept"}]"#), commandName: "check") == "kept")
        let reject = try CommandArgumentSchema<String>(options: [text.erased]) { try $0.value(for: text) }
        #expect(schema.metadata != reject.metadata)
        let duplicate = try Self.failure { _ = try schema.decode(options: Self.options(#"[{"name":"future","type":999,"value":"a"},{"name":"future","type":999,"value":"b"}]"#), commandName: "check") }
        #expect(duplicate.code == .duplicateOption)
        #expect(duplicate.optionName == nil)
        let nested = try Self.failure { _ = try schema.decode(options: Self.options(#"[{"name":"future","type":1,"options":[]}]"#), commandName: "check") }
        #expect(nested.code == .nestedOption)
        let tooMany = try Self.options("[" + (0..<26).map { "{\"name\":\"x\($0)\",\"type\":3,\"value\":\"v\"}" }.joined(separator: ",") + "]")
        #expect(try Self.failure { _ = try schema.decode(options: tooMany, commandName: "check") }.code == .optionLimit)
    }

    /// Descriptor identity includes the exact Swift type, registration constraints and explicit default fingerprint.
    /// Equivalent copied descriptors remain valid, while changed registrations cannot reinterpret cached values.
    /// - Throws: Unexpected local setup errors fail the test.
    @Test func typedDescriptorMismatches() throws {
        let original = try ArgumentOption<String>(name: "text", description: "Text")
        let changed = try ArgumentOption<String>(name: "text", description: "Different")
        let wrongType = try ArgumentOption<SchemaColor>(name: "text", description: "Text")
        let absent = try ArgumentOption<String>(name: "other", description: "Other")
        let options = try Self.options(#"[{"name":"text","type":3,"value":"red"}]"#)
        let equivalent = try ArgumentOption<String>(name: "text", description: "Text")
        let valid = try CommandArgumentSchema<String>(options: [original.erased]) { try $0.value(for: equivalent) }
        #expect(try valid.decode(options: options, commandName: "check") == "red")
        for candidate in [changed, absent] {
            let schema = try CommandArgumentSchema<String>(options: [original.erased]) { try $0.value(for: candidate) }
            #expect(try Self.failure { _ = try schema.decode(options: options, commandName: "check") }.code == .descriptorMismatch)
        }
        let typeMismatch = try CommandArgumentSchema<SchemaColor>(options: [original.erased]) { try $0.value(for: wrongType) }
        #expect(try Self.failure { _ = try typeMismatch.decode(options: options, commandName: "check") }.code == .descriptorMismatch)
        let a = try ArgumentOption<String?>(name: "text", description: "Text")
        let b = try ArgumentOption<String?>(name: "text", description: "Text", defaultValue: .value(nil))
        let defaultMismatch = try CommandArgumentSchema<String?>(options: [a.erased]) { try $0.value(for: b) }
        #expect(try Self.failure { _ = try defaultMismatch.decode(options: [], commandName: "check") }.code == .descriptorMismatch)
    }

    /// Invalid author metadata fails before use: duplicate/count/order/aggregate bounds and invalid defaults are checked.
    /// - Throws: Unexpected setup failures fail; every intended authoring error must be a structured diagnostic.
    @Test func invalidSchemasAndDefaults() throws {
        let required = try ArgumentOption<String>(name: "required", description: "Required")
        let optional = try ArgumentOption<String?>(name: "optional", description: "Optional")
        #expect(try Self.failure { _ = try CommandArgumentSchema<Void>(options: [required.erased, required.erased]) { _ in () } }.code == .duplicateOption)
        #expect(try Self.failure { _ = try CommandArgumentSchema<Void>(options: Array(repeating: required.erased, count: 26)) { _ in () } }.code == .optionLimit)
        #expect(try Self.failure { _ = try CommandArgumentSchema<Void>(options: [optional.erased, required.erased]) { _ in () } }.code == .invalidSchema)
        #expect(try Self.failure { _ = try ArgumentOption<String>(name: "UPPER", description: "Text") }.code == .invalidSchema)
        #expect(try Self.failure { _ = try ArgumentOption<String>(name: "text", description: "") }.code == .invalidSchema)
        #expect(try Self.failure { _ = try ArgumentOption<String>(name: "text", description: "Text", minLength: 3, maxLength: 2) }.code == .invalidSchema)
        #expect(try Self.failure { _ = try ArgumentOption<StructuralSchemaArgument>(name: "sub", description: "Sub") }.code == .invalidSchema)
        #expect(try Self.failure { _ = try ArgumentOption<String>(name: "text", description: "Text", defaultValue: .value("long"), maxLength: 2) }.code == .invalidDefault)
        #expect(try Self.failure { _ = try ArgumentOption<Int64>(name: "count", description: "Count", defaultValue: .value(0), minValue: JSONNumber(rawValue: "1")) }.code == .invalidDefault)
        #expect(try Self.failure { _ = try ArgumentOption<Double>(name: "number", description: "Number", defaultValue: .value(.nan)) }.code == .invalidDefault)
        #expect(try Self.failure { _ = try ArgumentOption<RejectingSchemaArgument>(name: "text", description: "Text", defaultValue: .value(.init())) }.code == .invalidDefault)
        #expect(try Self.failure { _ = try ArgumentOption<LaxSchemaNumber>(name: "number", description: "Number", defaultValue: .value(.init(value: .bool(true)))) }.code == .invalidDefault)
        #expect(try Self.failure { _ = try ArgumentOption<Double>(name: "number", description: "Number", minValue: JSONNumber(rawValue: "9007199254740993")) }.code == .invalidSchema)
        #expect(try Self.failure { _ = try ArgumentOption<Double>(name: "number", description: "Number", minValue: JSONNumber(rawValue: "1.0000000000000002"), maxValue: JSONNumber(rawValue: "1.0000000000000001")) }.code == .invalidSchema)
        let largeA = try ArgumentOption<LargeSchemaChoices>(name: "a", description: "A")
        let largeB = try ArgumentOption<LargeSchemaChoices>(name: "b", description: "B")
        #expect(try Self.failure { _ = try CommandArgumentSchema<Void>(options: [largeA.erased, largeB.erased]) { _ in () } }.code == .invalidSchema)
        let inflated = try (0..<25).map { index in
            try ArgumentOption<SchemaColor>(name: "option\(index)", description: String(repeating: "x", count: 100),
                descriptionLocalizations: .value(["de": String(repeating: "y", count: 100)])).erased
        }
        #expect(try CommandArgumentSchema<Void>(options: inflated) { _ in () }.options.count == 25)
    }

    /// String limits count Unicode scalars, enum restrictions are enforced, and numeric bounds compare exact decimal values.
    /// - Throws: Unexpected schema, fixture or successful-path decoding failures fail the test.
    @Test func scalarConstraintsAndChoices() throws {
        let text = try ArgumentOption<String>(name: "text", description: "Text", minLength: 2, maxLength: 3)
        let strings = try CommandArgumentSchema<String>(options: [text.erased]) { try $0.value(for: text) }
        #expect(try strings.decode(options: Self.options(#"[{"name":"text","type":3,"value":"é"}]"#), commandName: "check") == "é")
        for value in ["a", "four"] {
            let input = "[{\"name\":\"text\",\"type\":3,\"value\":\"\(value)\"}]"
            #expect(try Self.failure { _ = try strings.decode(options: Self.options(input), commandName: "check") }.code == .constraintViolation)
        }
        let color = try ArgumentOption<SchemaColor>(name: "color", description: "Color")
        let colors = try CommandArgumentSchema<SchemaColor>(options: [color.erased]) { try $0.value(for: color) }
        #expect(try colors.decode(options: Self.options(#"[{"name":"color","type":3,"value":"blue"}]"#), commandName: "check") == .blue)
        #expect(try Self.failure { _ = try colors.decode(options: Self.options(#"[{"name":"color","type":3,"value":"green"}]"#), commandName: "check") }.code == .constraintViolation)
        let number = try ArgumentOption<LaxSchemaNumber>(name: "number", description: "Number",
            minValue: JSONNumber(rawValue: "1"), maxValue: JSONNumber(rawValue: "1.0000000000000001"))
        let numbers = try CommandArgumentSchema<LaxSchemaNumber>(options: [number.erased]) { try $0.value(for: number) }
        for value in ["1", "1.0000000000000001"] {
            _ = try numbers.decode(options: Self.options("[{\"name\":\"number\",\"type\":10,\"value\":\(value)}]"), commandName: "check")
        }
        for value in ["0.999999999999999999", "1.0000000000000002", "1e-1000000"] {
            let error = try Self.failure { _ = try numbers.decode(options: Self.options("[{\"name\":\"number\",\"type\":10,\"value\":\(value)}]"), commandName: "check") }
            #expect(error.code == .constraintViolation)
        }
        let unrestricted = try ArgumentOption<LaxSchemaNumber>(name: "number", description: "Number")
        let shape = try CommandArgumentSchema<LaxSchemaNumber>(options: [unrestricted.erased]) { try $0.value(for: unrestricted) }
        #expect(try Self.failure { _ = try shape.decode(options: Self.options(#"[{"name":"number","type":10,"value":9007199254740993}]"#), commandName: "check") }.code == .wrongType)
        let exact = try ArgumentOption<ExactSchemaChoice>(name: "exact", description: "Exact")
        let choices = try CommandArgumentSchema<ExactSchemaChoice>(options: [exact.erased]) { try $0.value(for: exact) }
        _ = try choices.decode(options: Self.options(#"[{"name":"exact","type":10,"value":1.00000000000000010}]"#), commandName: "check")
        for value in ["1", "1.0000000000000002"] {
            #expect(try Self.failure { _ = try choices.decode(options: Self.options("[{\"name\":\"exact\",\"type\":10,\"value\":\(value)}]"), commandName: "check") }.code == .constraintViolation)
        }
    }

    /// Channel filters require same-interaction type evidence and accept canonical resolution for padded snowflakes.
    /// Attachment filters preserve validated host picker metadata while file content validation remains caller-owned.
    /// - Throws: Unexpected local fixture or successful-path decoding failures fail the test.
    @Test func channelFiltersAndAttachmentRegistration() throws {
        let channel = try ArgumentOption<ChannelReference>(name: "channel", description: "Channel", channelTypes: [.guildText])
        let schema = try CommandArgumentSchema<ChannelReference>(options: [channel.erased]) { try $0.value(for: channel) }
        let options = try Self.options(#"[{"name":"channel","type":7,"value":"0007"}]"#)
        let resolved = try InteractionResolvedData(data: Data(#"{"channels":{"7":{"id":"7","type":0}}}"#.utf8))
        #expect(try schema.decode(options: options, resolved: .value(resolved), commandName: "check").id.description == "7")
        #expect(try Self.failure { _ = try schema.decode(options: options, commandName: "check") }.code == .constraintViolation)
        let mismatch = try InteractionResolvedData(data: Data(#"{"channels":{"7":{"id":"7","type":2}}}"#.utf8))
        #expect(try Self.failure { _ = try schema.decode(options: options, resolved: .value(mismatch), commandName: "check") }.code == .constraintViolation)
        let unknown = try InteractionResolvedData(data: Data(#"{"channels":{"7":{"id":"7","type":999}}}"#.utf8))
        #expect(try Self.failure { _ = try schema.decode(options: options, resolved: .value(unknown), commandName: "check") }.code == .constraintViolation)
        let attachment = try ArgumentOption<AttachmentReference>(name: "attachment", description: "Attachment", fileTypes: ["image", ".png"])
        guard case .object(let fields) = attachment.registration.jsonValue() else { throw SchemaFixtureError.expectedFailure }
        #expect(fields["file_types"] == .array([.string("image"), .string(".png")]))
        #expect(try Self.failure { _ = try ArgumentOption<AttachmentReference>(name: "attachment", description: "Attachment", fileTypes: [".png", ".PNG"]) }.code == .invalidSchema)
    }

    /// Every declared codec executes before aggregate construction, and repeated lookups reuse an invocation-local cache.
    /// - Throws: Unexpected local codec/schema failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func eagerDecodeAndCachedRepeatedAccess() throws {
        ObservedSchemaArgument.calls.withLock { $0 = 0 }
        let first = try ArgumentOption<ObservedSchemaArgument>(name: "first", description: "First")
        let second = try ArgumentOption<ObservedSchemaArgument>(name: "second", description: "Second")
        let schema = try CommandArgumentSchema<String>(options: [first.erased, second.erased]) { decoder in
            let a = try decoder.value(for: first).text
            let b = try decoder.value(for: first).text
            return a + b
        }
        #expect(ObservedSchemaArgument.calls.withLock { $0 } == 0)
        #expect(try schema.decode(options: Self.options(#"[{"name":"first","type":3,"value":"a"},{"name":"second","type":3,"value":"unused"}]"#), commandName: "check") == "aa")
        #expect(ObservedSchemaArgument.calls.withLock { $0 } == 2)
        _ = try schema.decode(options: Self.options(#"[{"name":"first","type":3,"value":"b"},{"name":"second","type":3,"value":"unused"}]"#), commandName: "check")
        #expect(ObservedSchemaArgument.calls.withLock { $0 } == 4)
    }

    /// Failing unused codecs still prevent aggregate construction, and unsafe constructor/codec errors are sanitized.
    /// - Throws: Unexpected local setup failures fail the test.
    @Test func codecAndConstructorFailuresAreSanitized() throws {
        let rejecting = try ArgumentOption<RejectingSchemaArgument>(name: "text", description: "Text", source: Self.source)
        let failingCodec = try CommandArgumentSchema<Void>(options: [rejecting.erased]) { _ in throw SchemaFixtureError.expectedFailure }
        let codecError = try Self.failure { _ = try failingCodec.decode(options: Self.options(#"[{"name":"text","type":3,"value":"private submitted marker"}]"#), commandName: "check") }
        #expect(codecError.code == .invalidValue)
        #expect(codecError.source == Self.source)
        #expect(!String(reflecting: codecError).contains("private"))
        let failingConstructor = try CommandArgumentSchema<Void>(options: [], source: Self.source) { _ in throw SchemaFixtureError.submitted("private marker") }
        let constructorError = try Self.failure { _ = try failingConstructor.decode(options: [], commandName: "check") }
        #expect(constructorError.code == .constructionFailed)
        #expect(constructorError.source == Self.source)
        #expect(!String(reflecting: constructorError).contains("private"))
    }

    /// Source defaults capture the caller; diagnostics retain bounded labels and contextualization without scalar data.
    /// - Throws: Unexpected descriptor/schema failures fail the test.
    @Test func sourceCaptureMetadataAndDiagnosticBounds() throws {
        let sourceLine = UInt(#line + 1)
        let text = try ArgumentOption<String>(name: "text", description: "Text")
        #expect(text.source.fileID == #fileID)
        #expect(text.source.line == sourceLine)
        let schemaLine = UInt(#line + 1)
        let schema = try CommandArgumentSchema<String>(options: [text.erased]) { try $0.value(for: text) }
        #expect(schema.source.fileID == #fileID)
        #expect(schema.source.line == schemaLine)
        #expect(try schema.metadata.serialized() == schema.metadata.serialized())
        let diagnostic = ArgumentDiagnostic(code: .invalidSchema, commandName: String(repeating: "🔒", count: 100),
            optionName: String(repeating: "a", count: 1000), source: .init(fileID: "\n" + String(repeating: "b", count: 1000), line: 4, column: 5))
        #expect(diagnostic.commandName.utf8.count <= 128)
        #expect(diagnostic.optionName?.utf8.count == 128)
        #expect(diagnostic.source.fileID.utf8.count == 256)
        #expect(diagnostic.source.line == 4)
        #expect(diagnostic.source.column == 5)
        #expect(!diagnostic.source.fileID.contains("\n"))
        let contextualized = diagnostic.contextualized(commandName: "check")
        #expect(contextualized.commandName == "check")
        #expect(contextualized.optionName == diagnostic.optionName)
        #expect(contextualized.source == diagnostic.source)
        #expect(String(describing: diagnostic) == "ArgumentDiagnostic(invalidSchema)")
        #expect(String(reflecting: diagnostic) == "ArgumentDiagnostic(invalidSchema)")
        #expect(Mirror(reflecting: diagnostic).children.count == 1)
    }

    /// Fixture source used to make source forwarding independent of changing test line numbers.
    private static var source: DefinitionSourceLocation { .init(fileID: "SchemaFixture", line: 7, column: 3) }

    /// Parses synthetic option arrays through the owned interaction model without widening model visibility.
    /// - Parameter text: Complete controlled JSON option array used only by deterministic local tests.
    /// - Returns: The exact parsed option order, or empty if the controlled fixture unexpectedly omits options.
    /// - Throws: Owned JSON/model parse errors; live credentials and requests are never used.
    private static func options(_ text: String) throws -> [InteractionCommandOption] {
        let data = Data(("{\"id\":\"1\",\"name\":\"check\",\"type\":1,\"options\":" + text + "}").utf8)
        let command = try InteractionCommandData(data: data)
        guard case .value(let options) = command.options else { throw SchemaFixtureError.expectedFailure }
        return options
    }

    /// Requires one structured schema failure, preserving only its public sanitized representation.
    /// - Parameter operation: Synchronous local action expected to throw `ArgumentDiagnostic`.
    /// - Returns: The structured diagnostic for exact category/context assertions.
    /// - Throws: The original unexpected error, or a fixture error when the operation incorrectly succeeds.
    private static func failure(_ operation: () throws -> Void) throws -> ArgumentDiagnostic {
        do { try operation() } catch let diagnostic as ArgumentDiagnostic { return diagnostic }
        throw SchemaFixtureError.expectedFailure
    }
}
