// File: Tests/DiscordCommandDSLTests/AutocompleteFamilyTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordCommands
import DiscordCore
import DiscordDSL
import DiscordInteractions
import DiscordModels
import Foundation
import Testing
@testable import DiscordCommandDSL

/// Typed partial autocomplete and complete-registration reference checks use only local normalized frames.
@Suite(.timeLimit(.minutes(1))) struct AutocompleteFamilyTests {
    /// Descriptor admission rejects autocomplete on unsupported wire kinds and on static-choice codecs.
    /// Explicit false remains distinct from omission while both preserve ordinary typed registration.
    /// - Throws: Unexpected valid descriptor/direct-model errors fail; invalid combinations are asserted.
    @Test func autocompleteDescriptorAdmission() throws {
        #expect(throws: ArgumentDiagnostic.self) {
            try ArgumentOption<Bool>(name: "flag", description: "Flag", autocomplete: true)
        }
        #expect(throws: ArgumentDiagnostic.self) {
            try ArgumentOption<AutocompleteStaticChoice>(name: "choice", description: "Choice", autocomplete: true)
        }
        let disabled = try ArgumentOption<AutocompleteStaticChoice>(name: "choice", description: "Choice", autocomplete: false)
        let omitted = try ArgumentOption<AutocompleteStaticChoice>(name: "choice", description: "Choice", autocomplete: nil)
        let legacy = try ArgumentOption<AutocompleteStaticChoice>(name: "choice", description: "Choice")
        let direct = try ApplicationCommandOptionCreate(type: .string, name: "choice", description: "Choice",
            required: true, choices: [ApplicationCommandChoiceCreate(name: "example", value: .string("example"))],
            autocomplete: false)
        #expect(disabled.registration.jsonValue() == direct.jsonValue())
        #expect(disabled.registration.jsonValue() != omitted.registration.jsonValue())
        #expect(omitted.registration.jsonValue() == legacy.registration.jsonValue())
    }

    /// Partial strings bypass complete minimum lengths; omitted required/defaulted siblings remain absent.
    /// The same slash schema still rejects incomplete final invocations before handler execution.
    /// - Parameter grouped: Selects a root or grouped autocomplete route.
    /// - Throws: Unexpected setup/model/local response errors fail the test.
    @Test(arguments: [false, true]) func partialInvocationAndPayloadParity(grouped: Bool) async throws {
        let recorder = SlashFamilyRecorder()
        let handler = try PartialSuggestions(recorder: recorder)
        let registration = try CompleteAutocompleteHandler(recorder: recorder)
        let path = grouped ? ["tools", "search"] : []
        let root: ExistingCommandFamily
        if grouped {
            let tree = try SlashCommandTree(id: "tree", command: .init(name: "utility", description: "Utilities"),
                children: [.group(try SlashSubcommandGroup(name: "tools", description: "Tools",
                    subcommands: [SlashSubcommand(handler: registration)]))])
            root = ExistingCommandFamily(id: "registration", definitions: tree.family.definitions, routes: tree.family.routes)
        } else {
            let command = try SlashCommand(id: "root", handler: registration)
            root = ExistingCommandFamily(id: "registration", definitions: [command.definition], routes: [command.route])
        }
        let name = grouped ? "utility" : "search"
        let autocomplete = try AutocompleteCommand(id: "suggestions", name: name, path: path,
            option: handler.query, options: handler.descriptors, handler: handler)
        let plan = try CommandCompilation.compile(Module(id: "catalog") { root; autocomplete })
        #expect(plan.definitions.count == 1)
        #expect(plan.routes.count == 2)
        #expect(plan.routes[1].key == (try .autocomplete(name: name, path: path, focusedOption: "query")))
        #expect(await recorder.values.isEmpty)
        let router = try plan.makeRouter()
        let responseRecorder = SlashFamilyResponseRecorder()
        let context = try SlashFamilyFixtures.context(name: name, path: path,
            options: #"[{"name":"query","type":3,"value":"a","focused":true}]"#, type: 4,
            responseRecorder: responseRecorder)
        #expect(try await router.route(context))
        #expect(await recorder.values == ["a:absent"])
        #expect(await responseRecorder.types == [8])
        #expect(await router.activeHandlerCount == 0)
        let final = try SlashFamilyFixtures.context(name: name, path: path,
            options: #"[{"name":"query","type":3,"value":"abcd"}]"#)
        await #expect(throws: ArgumentDiagnostic.self) { try await router.route(final) }
        #expect(await recorder.values == ["a:absent"])
        let response = try AutocompleteResponse([AutocompleteChoice(name: "Choice", value: "abcd")])
        #expect(try InteractionResponse.autocomplete(response.choices.map(\.choice)).jsonValue(interactionType: .applicationCommandAutocomplete) ==
            JSONValue.parse(Data(#"{"type":8,"data":{"choices":[{"name":"Choice","value":"abcd"}]}}"#.utf8)))
    }

    /// Numeric focused values and choices preserve their legal discriminator and exact wire range.
    /// Empty and maximum-count replies pass; oversized lists, fractional integer and incompatible codecs fail.
    /// - Throws: Unexpected local codec/response errors fail; invalid construction is explicitly rejected.
    @Test func numericValuesAndChoiceBounds() async throws {
        let integer = try ArgumentOption<Int>(name: "amount", description: "Amount", autocomplete: true)
        let definition = try CommandDefinition.slash(name: "utility", description: "Utilities") { integer.registration }
        let normal = CommandRoute(key: try .command(name: "utility")) { _ in }
        let recorder = SlashFamilyRecorder()
        let autocomplete = try AutocompleteCommand(id: "integer", name: "utility", option: integer,
            handler: IntegerSuggestions(recorder: recorder))
        let plan = try CommandCompilation.compile(Module(id: "integers") {
            ExistingCommandFamily(id: "registration", definitions: [definition], routes: [normal]); autocomplete
        })
        let context = try SlashFamilyFixtures.context(options: #"[{"name":"amount","type":4,"value":9007199254740991,"focused":true}]"#, type: 4)
        #expect(try await plan.makeRouter().route(context))
        #expect(await recorder.values == ["9007199254740991"])
        let number = try ArgumentOption<Double>(name: "number", description: "Number", autocomplete: true)
        let numberDefinition = try CommandDefinition.slash(name: "utility", description: "Utilities") { number.registration }
        let numberAutocomplete = try AutocompleteCommand(id: "number", name: "utility", option: number, handler: NumberSuggestions())
        let numberPlan = try CommandCompilation.compile(Module(id: "numbers") {
            ExistingCommandFamily(id: "registration", definitions: [numberDefinition], routes: [normal])
            numberAutocomplete
        })
        #expect(try await numberPlan.makeRouter().route(SlashFamilyFixtures.context(
            options: #"[{"name":"number","type":10,"value":1.25,"focused":true}]"#, type: 4)))
        #expect(try AutocompleteResponse<Int>().choices.isEmpty)
        let choice = try AutocompleteChoice(name: "Maximum", value: Int64(9_007_199_254_740_991))
        #expect(try AutocompleteResponse(Array(repeating: choice, count: 25)).choices.count == 25)
        #expect(throws: (any Error).self) { try AutocompleteResponse(Array(repeating: choice, count: 26)) }
        #expect(throws: (any Error).self) { try AutocompleteChoice(name: "Too large", value: Int64.max) }
        #expect(throws: (any Error).self) { try AutocompleteChoice(name: "Invalid", value: Double.infinity) }
        #expect(throws: (any Error).self) { try AutocompleteChoice(name: "Invalid", value: String(repeating: "a", count: 101)) }
        #expect(throws: (any Error).self) { try AutocompleteChoice(name: "", value: "valid") }
    }

    /// Missing or mismatched registration references and duplicates are rejected before any behavior executes.
    /// - Throws: Unexpected valid setup errors fail; malformed catalogs are explicitly rejected.
    @Test func catalogReferenceValidation() throws {
        let recorder = SlashFamilyRecorder()
        let handler = try PartialSuggestions(recorder: recorder)
        let autocomplete = try AutocompleteCommand(id: "autocomplete", name: "search", option: handler.query,
            options: handler.descriptors, handler: handler)
        #expect(throws: CommandCompilationDiagnostic.self) { try CommandCompilation.compile(autocomplete) }
        let registration = try SlashCommand(id: "root", handler: CompleteAutocompleteHandler(recorder: recorder))
        #expect(throws: CommandCompilationDiagnostic.self) { try CommandCompilation.compile(registration) }
        let mismatched = try ArgumentOption<String>(name: "query", description: "Different", autocomplete: true)
        let wrong = try AutocompleteCommand(id: "wrong", name: "search", option: mismatched, handler: handler)
        #expect(throws: CommandCompilationDiagnostic.self) {
            try CommandCompilation.compile(Module(id: "m") { registration; wrong })
        }
        let duplicate = try AutocompleteCommand(id: "duplicate", name: "search", option: handler.query,
            options: handler.descriptors, handler: handler)
        #expect(throws: CommandCompilationDiagnostic.self) {
            try CommandCompilation.compile(Module(id: "m") { registration; autocomplete; duplicate })
        }
        #expect(throws: DefinitionDiagnostic.self) {
            try CommandCompilation.compile(Module(id: "m") { registration; autocomplete }, limits: .init(maxDeclarations: 1))
        }
        let disabled = try ArgumentOption<String>(name: "query", description: "Query")
        #expect(throws: CommandCompilationDiagnostic.self) {
            try AutocompleteCommand(id: "disabled", name: "search", option: disabled, handler: handler)
        }
        #expect(throws: CommandCompilationDiagnostic.self) {
            try AutocompleteCommand(id: "duplicate-options", name: "search", option: handler.query,
                options: [handler.query.erased, handler.query.erased], handler: handler)
        }
        #expect(throws: CommandCompilationDiagnostic.self) {
            try AutocompleteCommand(id: "missing-option", name: "search", option: handler.query, options: [], handler: handler)
        }
    }

    /// Every supplied partial envelope is admitted before handlers execute, even when focus itself is valid.
    /// - Parameter options: Malformed/unknown/oversized focused leaf array.
    /// - Throws: Setup failures fail; route rejection or sanitized partial decoding errors are asserted.
    @Test(arguments: ["[]",
        #"[{"name":"query","type":3,"value":"a"}]"#,
        #"[{"name":"query","type":3,"value":"a","focused":true},{"name":"query","type":3,"value":"b"}]"#,
        #"[{"name":"query","type":3,"value":"a","focused":true},{"name":"unknown","type":3,"value":"x"}]"#,
        #"[{"name":"query","type":3,"focused":true}]"#,
        #"[{"name":"query","type":3,"value":"a","focused":true},{"name":"count","type":4,"value":9007199254740992}]"#,
        #"[{"name":"query","type":3,"value":"a","focused":true},{"name":"count","type":4,"value":1,"focused":true}]"#])
    func invalidPartialInvocation(options: String) async throws {
        let recorder = SlashFamilyRecorder()
        let handler = try PartialSuggestions(recorder: recorder)
        let root = try SlashCommand(id: "root", handler: CompleteAutocompleteHandler(recorder: recorder))
        let autocomplete = try AutocompleteCommand(id: "auto", name: "search", option: handler.query,
            options: handler.descriptors, handler: handler)
        let router = try CommandCompilation.compile(Module(id: "m") { root; autocomplete }).makeRouter()
        let context = try SlashFamilyFixtures.context(name: "search", options: options, type: 4)
        do { #expect(try await router.route(context) == false) }
        catch { #expect(error is ArgumentDiagnostic) }
        #expect(await recorder.values.isEmpty)
        #expect(await router.activeHandlerCount == 0)
    }

    /// Partial lookups preserve omission and reject forged generic descriptors without invoking complete defaults.
    /// Malformed focus/null/nested envelopes fail during admission, before any requested codec runs.
    /// - Throws: Unexpected valid setup errors fail; malformed input and sanitized conversion errors are asserted.
    @Test func partialLookupIdentityAndEnvelopeAdmission() throws {
        let query = try ArgumentOption<String>(name: "query", description: "Query", autocomplete: true)
        let count = try ArgumentOption<Int>(name: "count", description: "Count", defaultValue: .value(9))
        let options = [query.erased, count.erased]
        let focused = try InteractionCommandOption(data: Data(#"{"name":"query","type":3,"value":"secret-partial","focused":true}"#.utf8))
        let source = DefinitionSourceLocation(fileID: "Synthetic", line: 1, column: 1)
        let input = try AutocompleteInput(options: [focused], descriptors: options, focusedOption: "query",
            resolved: .absent, commandName: "search", source: source)
        #expect(try input.value(for: query) == "secret-partial")
        #expect(try input.value(for: count) == nil)
        let mismatch = try ArgumentOption<String>(name: "query", description: "Different", autocomplete: true)
        #expect(throws: ArgumentDiagnostic.self) { try input.value(for: mismatch) }
        let wrongCodec = try ArgumentOption<RejectingPartialString>(name: "query", description: "Query", autocomplete: true)
        #expect(throws: ArgumentDiagnostic.self) { try input.value(for: wrongCodec) }
        let rejecting = try AutocompleteInput(options: [focused], descriptors: [wrongCodec.erased], focusedOption: "query",
            resolved: .absent, commandName: "search", source: source)
        do {
            _ = try rejecting.value(for: wrongCodec)
            Issue.record("Rejecting codec unexpectedly succeeded")
        } catch let error as ArgumentDiagnostic {
            #expect(error.code == .invalidValue)
            #expect(!error.description.contains("secret-partial"))
        }
        for json in [
            #"{"name":"query","type":3,"value":"a","focused":false}"#,
            #"{"name":"query","type":3,"value":"a","focused":null}"#,
            #"{"name":"query","type":3,"focused":true,"options":[]}"#,
            #"{"name":"unknown","type":3,"value":"a","focused":true}"#,
            #"{"name":"query","type":3,"focused":true}"#
        ] {
            if json.contains("null") {
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try InteractionCommandOption(data: Data(json.utf8))
                }
            } else {
                let leaf = try InteractionCommandOption(data: Data(json.utf8))
                #expect(throws: ArgumentDiagnostic.self) {
                    try AutocompleteInput(options: [leaf], descriptors: options, focusedOption: "query",
                        resolved: .absent, commandName: "search", source: source)
                }
            }
        }
        #expect(throws: ArgumentDiagnostic.self) {
            try AutocompleteInput(options: Array(repeating: focused, count: 26), descriptors: options,
                focusedOption: "query", resolved: .absent, commandName: "search", source: source)
        }
    }

    /// Cancellation before routing and user errors propagate without a response or leaked handler admission.
    /// - Throws: Unexpected setup failures fail; cancellation and sentinel errors are asserted.
    @Test func cancellationAndErrorPropagation() async throws {
        let query = try ArgumentOption<String>(name: "query", description: "Query", autocomplete: true)
        let root = ExistingCommandFamily(id: "root", definitions: [try .slash(name: "utility", description: "Utilities") { query.registration }],
            routes: [CommandRoute(key: try .command(name: "utility")) { _ in }])
        let autocomplete = try AutocompleteCommand(id: "auto", name: "utility", option: query, handler: ThrowingSuggestions())
        let router = try CommandCompilation.compile(Module(id: "m") { root; autocomplete }).makeRouter()
        let context = try SlashFamilyFixtures.context(options: #"[{"name":"query","type":3,"value":"a","focused":true}]"#, type: 4)
        await #expect(throws: DiscordError.cancelled) { try await router.route(context) }
        #expect(await context.responder.snapshot() == .pending)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await router.route(context) }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await router.activeHandlerCount == 0)
    }
}

/// Finite static choices are incompatible with enabled Discord autocomplete even though their wire kind is string.
private enum AutocompleteStaticChoice: String, StringArgumentChoice {
    case example
}

/// Captured descriptor helpers ensure full and partial handlers reference identical registration fields.
private struct AutocompleteDescriptors: Sendable {
    let query: ArgumentOption<String>
    let flag: ArgumentOption<Bool>
    let count: ArgumentOption<Int>
    /// Constructs required-before-optional registrations; explicit fallback must stay unused during partial decode.
    /// - Throws: Existing descriptor authoring validation errors.
    init() throws {
        query = try ArgumentOption(name: "query", description: "Query", minLength: 4, autocomplete: true)
        flag = try ArgumentOption(name: "flag", description: "Flag")
        count = try ArgumentOption(name: "count", description: "Count", defaultValue: .value(9))
    }
    /// Returns exact registration order without decoding values or applying defaults.
    var options: [AnyArgumentOption] { [query.erased, flag.erased, count.erased] }
}

/// Complete invocation arguments, deliberately distinct from partial suggestions.
private struct CompleteAutocompleteArguments: CommandArguments {
    let query: String
    let flag: Bool
    let count: Int
    /// Returns a complete constructor that partial invocation must never execute.
    static var schema: CommandArgumentSchema<Self> {
        /// Captures finite descriptors and an inert typed constructor; authoring errors propagate.
        get throws {
            let descriptors = try AutocompleteDescriptors()
            return try CommandArgumentSchema(options: descriptors.options) { decoder in
                try Self(query: decoder.value(for: descriptors.query), flag: decoder.value(for: descriptors.flag),
                    count: decoder.value(for: descriptors.count))
            }
        }
    }
}

/// Normal final command handler; any execution would be separately visible in the shared recorder.
private struct CompleteAutocompleteHandler: ManualSlashCommandHandler {
    typealias Arguments = CompleteAutocompleteArguments
    let recorder: SlashFamilyRecorder
    /// Captures an inert behavior reference; argument descriptors remain owned by the schema.
    /// - Parameter recorder: Test-local execution observer.
    init(recorder: SlashFamilyRecorder) throws { self.recorder = recorder }
    /// Returns root/leaf metadata with no parent-only settings.
    var command: SlashCommandMetadata { .init(name: "search", description: "Search") }
    /// Records only admitted complete invocation data.
    /// - Parameters:
    ///   - context: Existing responder, deliberately left untouched.
    ///   - arguments: Complete freshly decoded query/flag/count values.
    func execute(_ context: InteractionContext, arguments: CompleteAutocompleteArguments) async throws {
        await recorder.record("complete:\(arguments.query)")
    }
}

/// Suggestions-only string behavior observes omission independently of complete defaults.
private struct PartialSuggestions: AutocompleteCommandHandler {
    typealias Value = String
    let recorder: SlashFamilyRecorder
    let query: ArgumentOption<String>
    let count: ArgumentOption<Int>
    let descriptors: [AnyArgumentOption]
    /// Captures matching descriptors without invoking the partial handler.
    /// - Parameter recorder: Test-local admitted invocation observer.
    /// - Throws: Unexpected descriptor authoring errors.
    init(recorder: SlashFamilyRecorder) throws {
        let descriptors = try AutocompleteDescriptors()
        self.recorder = recorder
        query = descriptors.query
        count = descriptors.count
        self.descriptors = descriptors.options
    }
    /// Verifies partial defaults stay absent and returns one typed existing-model choice.
    /// - Parameters:
    ///   - context: Restricted immutable interaction snapshot.
    ///   - input: Admitted partial siblings.
    ///   - value: Focused partial string, allowed below complete minimum length.
    /// - Returns: One validated suggestion.
    /// - Throws: Unexpected partial lookup or choice-validation errors.
    func execute(_ context: CommandContext, input: AutocompleteInput, value: String) async throws -> AutocompleteResponse<String> {
        #expect(input.focusedOption == "query")
        #expect(input.description == "AutocompleteInput(redacted)")
        #expect(input.debugDescription == input.description)
        #expect(input.customMirror.children.count == 1)
        let partialCount = try input.value(for: count)
        await recorder.record("\(value):\(partialCount.map(String.init) ?? "absent")")
        return try AutocompleteResponse([AutocompleteChoice(name: "Choice", value: value + "bcd")])
    }
}

/// Integer suggestions retain the legal large-integer range through the typed value.
private struct IntegerSuggestions: AutocompleteCommandHandler {
    typealias Value = Int
    let recorder: SlashFamilyRecorder
    /// Records the exact focused integer and supplies one typed suggestion.
    /// - Parameters:
    ///   - context: Restricted normalized snapshot.
    ///   - input: Admitted partial values.
    ///   - value: Exact representable Discord integer.
    /// - Returns: One integer choice.
    /// - Throws: Choice or response validation errors.
    func execute(_ context: CommandContext, input: AutocompleteInput, value: Int) async throws -> AutocompleteResponse<Int> {
        await recorder.record(String(value))
        return try AutocompleteResponse([AutocompleteChoice(name: "Value", value: value)])
    }
}

/// Number suggestions verify fractional focused values stay a separate numeric response family.
private struct NumberSuggestions: AutocompleteCommandHandler {
    typealias Value = Double
    /// Returns a typed finite fractional suggestion.
    /// - Parameters:
    ///   - context: Restricted normalized snapshot.
    ///   - input: Admitted partial values.
    ///   - value: Focused finite number.
    /// - Returns: One fractional numeric choice.
    /// - Throws: Choice/response validation errors.
    func execute(_ context: CommandContext, input: AutocompleteInput, value: Double) async throws -> AutocompleteResponse<Double> {
        #expect(value == 1.25)
        return try AutocompleteResponse([AutocompleteChoice(name: "Value", value: value)])
    }
}

/// Sentinel failing behavior verifies no fallback callback is synthesized.
private struct ThrowingSuggestions: AutocompleteCommandHandler {
    typealias Value = String
    /// Throws a deterministic error before any response is returned.
    /// - Parameters:
    ///   - context: Restricted normalized snapshot.
    ///   - input: Admitted partial values.
    ///   - value: Valid focused string.
    /// - Returns: Never returns a response.
    /// - Throws: Always throws the sentinel cancelled error.
    func execute(_ context: CommandContext, input: AutocompleteInput, value: String) async throws -> AutocompleteResponse<String> {
        throw DiscordError.cancelled
    }
}

/// Custom same-wire-kind codec used to verify generic descriptor identity and redacted conversion errors.
private struct RejectingPartialString: ArgumentValue {
    /// Uses the string wire family while retaining a distinct Swift identity.
    static var optionType: ApplicationCommandOptionType { .string }
    /// Always rejects conversion without retaining or reflecting the supplied value.
    /// - Parameters:
    ///   - value: Synthetic present partial value.
    ///   - resolved: Unused same-interaction resource data.
    /// - Returns: Never returns a value.
    /// - Throws: Always throws a deterministic local validation error.
    static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self {
        throw ArgumentValueError.invalidChoice
    }
    /// Provides a valid author-only scalar; no invocation codec is executed by construction.
    var argumentValue: Field<JSONValue> { .value(.string("author")) }
}
