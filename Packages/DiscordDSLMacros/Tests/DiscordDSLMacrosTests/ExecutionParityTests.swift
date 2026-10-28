// File: Packages/DiscordDSLMacros/Tests/DiscordDSLMacrosTests/ExecutionParityTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordCommands
import DiscordCore
import DiscordDSL
import DiscordDSLMacros
import DiscordInteractions
import DiscordModels
import Foundation
import Testing

/// Real compiler-expanded authoring declarations compared with independent handwritten schemas and routes.
@Suite(.timeLimit(.minutes(1))) struct ExecutionParityTests {
    /// Generated contributions preserve registration, choice order, defaults and route ownership without execution.
    /// - Throws: Unexpected schema or command validation failures fail the test.
    @Test func definitionsRoutesAndInertConstruction() async throws {
        let generatedRecorder = MacroInvocationRecorder()
        let manualRecorder = MacroInvocationRecorder()
        let source = DefinitionSourceLocation(fileID: "ExternalCommand.swift", line: 7, column: 2)
        let generated = try GeneratedGreeting(recorder: generatedRecorder).contribution(id: "greet", source: source)
        let manual = try DiscordCommandDSL.SlashCommand(id: "greet", handler: HandwrittenGreeting(recorder: manualRecorder), source: source)
        let generatedPlan = try CommandCompilation.compile(Module(id: "example") { generated })
        let manualPlan = try CommandCompilation.compile(Module(id: "example") { manual })
        #expect(try generatedPlan.definitions[0].request.jsonValue().serialized() == manualPlan.definitions[0].request.jsonValue().serialized())
        #expect(generatedPlan.routes[0].key == manualPlan.routes[0].key)
        #expect(generatedPlan.description.declarations[0].modulePath == manualPlan.description.declarations[0].modulePath)
        #expect(generatedPlan.description.declarations[0].declaration.source == source)
        #expect(manualPlan.description.declarations[0].declaration.source == source)
        #expect(generatedPlan.description.declarations[0].declaration.id == manualPlan.description.declarations[0].declaration.id)
        #expect(try GeneratedGreetingArguments.schema.descriptors.allSatisfy { $0.source.line > 0 && $0.source.fileID.hasSuffix("ExecutionParityTests.swift") })
        #expect(try GeneratedGreetingArguments.schema.options.map(\.name) == ["person", "shade", "token", "count", "user", "repeat-count", "suffix"])
        #expect(try GeneratedGreetingArguments.schema.options.map(\.required) == [true, true, true, false, false, false, false])
        _ = try generatedPlan.makeRouter()
        _ = try manualPlan.makeRouter()
        #expect(await generatedRecorder.values.isEmpty)
        #expect(await manualRecorder.values.isEmpty)
    }

    /// Explicit typed nil defaults match handwritten decoding while preserving present empty and nonempty strings.
    /// - Parameter suffix: Omitted nil or controlled present suffix; fixture strings need no JSON escaping.
    /// - Throws: Unexpected model/schema errors fail the test; all decoding remains synchronous and local.
    @Test(arguments: [nil, "", "tail"] as [String?]) func explicitNilDefaultParity(suffix: String?) throws {
        let extra = suffix.map { ",{\"name\":\"suffix\",\"type\":3,\"value\":\"\($0)\"}" } ?? ""
        let options = try Self.options("[\(Self.required())\(extra)]")
        let generated = try GeneratedGreetingArguments.schema.decode(options: options, commandName: "greet")
        let manual = try HandwrittenGreetingArguments.schema.decode(options: options, commandName: "greet")
        #expect(generated.suffix == suffix)
        #expect(generated.suffix == manual.suffix)
        #expect(generated.count == nil)
        #expect(generated.repeatCount == 2)
    }

    /// Typed defaults and nil omission remain invocation-local across concurrent HTTP and Gateway deliveries.
    /// - Parameter gateway: Selects a local delivery envelope without creating a transport or connection.
    /// - Throws: Unexpected fixture parsing, routing or handler failures fail the test.
    @Test(arguments: [false, true]) func invocationParityAndFreshState(gateway: Bool) async throws {
        let generatedRecorder = MacroInvocationRecorder()
        let manualRecorder = MacroInvocationRecorder()
        let generated = try CommandCompilation.compile(GeneratedGreeting(recorder: generatedRecorder).contribution(id: "greet", source: .init(fileID: "Commands.swift", line: 1, column: 1)))
        let manual = try CommandCompilation.compile(try DiscordCommandDSL.SlashCommand(id: "greet", handler: HandwrittenGreeting(recorder: manualRecorder)))
        let generatedRouter = try generated.makeRouter()
        let manualRouter = try manual.makeRouter()
        let mode: InteractionDeliveryMode = gateway ? .gateway : .http
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<12 {
                group.addTask {
                    let options = Self.required(person: "Person\(index)") + ",{\"name\":\"count\",\"type\":4,\"value\":\(index)}"
                    let generatedInput = try Self.context(options: "[\(options)]", mode: mode)
                    let manualInput = try Self.context(options: "[\(options)]", mode: mode)
                    #expect(try await generatedRouter.route(generatedInput))
                    #expect(try await manualRouter.route(manualInput))
                    #expect(await generatedInput.responder.snapshot() == .pending)
                    #expect(await manualInput.responder.snapshot() == .pending)
                }
            }
            try await group.waitForAll()
        }
        let generatedInput = try Self.context(options: "[\(Self.required())]", mode: mode)
        let manualInput = try Self.context(options: "[\(Self.required())]", mode: mode)
        #expect(try await generatedRouter.route(generatedInput))
        #expect(try await manualRouter.route(manualInput))
        #expect(await generatedRecorder.values.sorted() == manualRecorder.values.sorted())
        #expect(await generatedRecorder.values.last == "Ada:blue:owned:nil:nil:2")
        #expect(await generatedRouter.activeHandlerCount == 0)
        #expect(await manualRouter.activeHandlerCount == 0)
    }

    /// A real generated decoder preserves exact integer edges and unresolved 64-bit user identities.
    /// - Parameter text: Exact supported integer lexeme, including both safe-integer boundaries.
    /// - Throws: Unexpected model or generated/manual schema failures fail the test.
    @Test(arguments: ["0", "-0", "9007199254740991", "-9007199254740991"])
    func exactNumbersAndUnresolvedReferences(text: String) throws {
        let options = try Self.options("[\(Self.required()),{\"name\":\"count\",\"type\":4,\"value\":\(text)},{\"name\":\"user\",\"type\":6,\"value\":\"18446744073709551615\"},{\"name\":\"repeat-count\",\"type\":4,\"value\":0}]")
        let generated = try GeneratedGreetingArguments.schema.decode(options: options, commandName: "greet")
        let manual = try HandwrittenGreetingArguments.schema.decode(options: options, commandName: "greet")
        #expect(generated.count == Int(text))
        #expect(generated.count == manual.count)
        #expect(generated.user == manual.user)
        #expect(generated.user?.id.description == "18446744073709551615")
        #expect(generated.user?.user == .absent)
        #expect(generated.user?.member == .absent)
        #expect(generated.repeatCount == 0)
    }

    /// Generated argument aggregates share strict schema errors for omissions, duplicates, kinds, choices and numbers.
    /// - Parameters:
    ///   - suffix: Additional JSON leaves following an otherwise valid required prefix, or a complete replacement.
    ///   - code: Expected stable sanitized failure category from both independent implementations.
    /// - Throws: Unexpected local parser/schema errors fail the test.
    @Test(arguments: [
        ("[]", ArgumentDiagnostic.Code.missingValue),
        (#"[{"name":"person","type":5,"value":true}]"#, .wrongType),
        (#"[{"name":"person","type":3}]"#, .missingValue),
        (#"[{"name":"person","type":3,"value":"Ada"},{"name":"person","type":3,"value":"Grace"}]"#, .duplicateOption),
        (#",{"name":"count","type":4,"value":9007199254740992}"#, .wrongType),
        (#",{"name":"future","type":3,"value":"secret"}"#, .unknownOption),
        (#"[{"name":"person","type":3,"value":"Ada"},{"name":"shade","type":3,"value":"unknown"},{"name":"token","type":3,"value":"owned"}]"#, .constraintViolation),
        (#"[{"name":"person","type":3,"value":"Ada"},{"name":"shade","type":3,"value":"blue"},{"name":"token","type":3,"value":"rejected"}]"#, .invalidValue)
    ]) func malformedGeneratedArguments(suffix: String, code: ArgumentDiagnostic.Code) throws {
        let text = suffix.hasPrefix(",") ? "[\(Self.required())\(suffix)]" : suffix
        let options = try Self.options(text)
        #expect(try Self.diagnostic { _ = try GeneratedGreetingArguments.schema.decode(options: options, commandName: "greet") } == code)
        #expect(try Self.diagnostic { _ = try HandwrittenGreetingArguments.schema.decode(options: options, commandName: "greet") } == code)
    }

    /// Explicit null and noninteger integer spellings fail in the shared model before either schema may default them.
    /// - Throws: No unexpected error escapes; model-level failures are asserted for required and optional fields.
    @Test func invalidWireValuesDoNotSelectDefaults() throws {
        for name in ["person", "count", "repeat-count", "suffix"] {
            let kind = name == "person" || name == "suffix" ? 3 : 4
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                _ = try Self.options("[{\"name\":\"\(name)\",\"type\":\(kind),\"value\":null}]")
            }
        }
        for lexeme in ["1.25", "1e0"] {
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                _ = try Self.options("[{\"name\":\"count\",\"type\":4,\"value\":\(lexeme)}]")
            }
        }
    }

    /// Generated routes preserve exact dispatch, ambiguous-duplicate rejection, handler errors and cancellation.
    /// - Throws: Setup failures fail the test; expected execution failures are explicitly asserted.
    @Test func routeFailureAndCancellationParity() async throws {
        let recorder = MacroInvocationRecorder()
        let plan = try CommandCompilation.compile(GeneratedGreeting(recorder: recorder, fails: true).contribution(id: "greet", source: .init(fileID: "Commands.swift", line: 1, column: 1)))
        let router = try plan.makeRouter()
        let context = try Self.context(options: "[\(Self.required())]")
        await #expect(throws: MacroInvocationFailure.failed) { try await router.route(context) }
        #expect(await recorder.values == ["Ada:blue:owned:nil:nil:2"])
        #expect(try await router.route(Self.context(options: "[]", name: "other")) == false)
        #expect(try await router.route(Self.context(options: "[\(Self.required()),{\"name\":\"person\",\"type\":3,\"value\":\"Grace\"}]")) == false)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await router.route(context)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await recorder.values.count == 1)
        #expect(await router.activeHandlerCount == 0)
        #expect(await context.responder.snapshot() == .pending)
    }

    /// Provides the required ordinary leaf sequence used by independent compiled and handwritten schemas.
    /// - Parameter person: Controlled fixture name containing no JSON escaping characters; default Ada.
    /// - Returns: Three JSON leaves without array delimiters; no user or external input is interpolated.
    private static func required(person: String = "Ada") -> String {
        "{\"name\":\"person\",\"type\":3,\"value\":\"\(person)\"},{\"name\":\"shade\",\"type\":3,\"value\":\"blue\"},{\"name\":\"token\",\"type\":3,\"value\":\"owned\"}"
    }

    /// Parses an entire option array through the existing strict Interaction model.
    /// - Parameter text: Complete synthetic JSON option array, possibly intentionally malformed.
    /// - Returns: Retained ordinary options from the trusted local interaction.
    /// - Throws: `DiscordError` for malformed wire shapes, including explicit-null scalar values.
    private static func options(_ text: String) throws -> [InteractionCommandOption] {
        let input = try context(options: text)
        guard case .value(.command(let data)) = input.interaction.data, case .value(let options) = data.options else {
            throw MacroInvocationFailure.failed
        }
        return options
    }

    /// Captures only the stable schema failure category for cross-source implementation comparison.
    /// - Parameter body: Synchronous local decode that is required to fail without handler execution.
    /// - Returns: The sanitized diagnostic code; never retained submitted scalar text.
    /// - Throws: Unexpected errors, or the fixture sentinel if the decode incorrectly succeeds.
    private static func diagnostic(_ body: () throws -> Void) throws -> ArgumentDiagnostic.Code {
        do { try body() }
        catch let error as ArgumentDiagnostic { return error.code }
        throw MacroInvocationFailure.failed
    }

    /// Creates an inert trusted-origin input with the original pending response owner.
    /// - Parameters:
    ///   - options: Complete JSON option list, including negative wire-model cases.
    ///   - name: Exact local dispatch name; default greet.
    ///   - mode: Local HTTP/Gateway envelope, default HTTP; no transport is created.
    /// - Returns: An interaction context whose sink performs no I/O and whose clock owns no background work.
    /// - Throws: Model or acknowledgement admission validation errors.
    private static func context(options: String, name: String = "greet", mode: InteractionDeliveryMode = .http) throws -> InteractionContext {
        let data = try JSONValue.parse(Data(options.utf8))
        let interaction = try Interaction(data: JSONValue.object([
            "id": .string("18446744073709551615"), "application_id": .string("9"),
            "type": .number(JSONNumber(rawValue: "2")), "token": .string("synthetic"),
            "version": .number(JSONNumber(rawValue: "1")), "app_permissions": .string("0"),
            "entitlements": .array([]), "authorizing_integration_owners": .object([:]),
            "attachment_size_limit": .number(JSONNumber(rawValue: "10485760")),
            "data": .object(["id": .string("8"), "name": .string(name), "type": .number(JSONNumber(rawValue: "1")), "options": data])
        ]).serialized())
        let responder = InteractionResponder(interaction: interaction, deliveryMode: mode,
            clock: InteractionClock(ContinuousClock()), sink: InteractionResponseSink(initial: { _, _ in }),
            admission: try InteractionAcknowledgementAdmission())
        return try InteractionContext(interaction: interaction, deliveryMode: mode, responder: responder)
    }
}

/// Ordinary enum choices retain their declaration order through real compiler-generated schema construction.
private enum MacroShade: String, StringArgumentChoice { case blue, green }

/// A custom codec deliberately unknown to the macro implementation; conformance is resolved by Swift.
private struct MacroToken: ArgumentValue {
    let text: String
    /// Selects the existing string wire shape without a new runtime kind.
    static var optionType: ApplicationCommandOptionType { .string }
    /// Decodes the bounded marker through the normal string codec and adds one application restriction.
    /// - Parameters:
    ///   - value: Ordinary present string scalar; malformed presence follows the built-in codec errors.
    ///   - resolved: Same-interaction partial maps, ignored by the string codec.
    /// - Returns: The owned fixture marker without tasks or I/O.
    /// - Throws: String codec errors or `MacroInvocationFailure.failed` for another marker.
    static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self {
        let text = try String.decodeArgument(value, resolved: resolved)
        guard text == "owned" else { throw MacroInvocationFailure.failed }
        return Self(text: text)
    }
    /// Encodes the exact marker so typed defaults can use the ordinary schema validator.
    var argumentValue: Field<JSONValue> { .value(.string(text)) }
}

/// Compiler-expanded immutable argument values with one mutable stored default required for Swift initialization.
@CommandArguments
private struct GeneratedGreetingArguments {
    @Option(description: "Person") let person: String
    @Option(description: "Shade") let shade: MacroShade
    @Option(description: "Token") let token: MacroToken
    @Option(description: "Count") let count: Int?
    @Option(description: "User") let user: UserReference?
    @Option(name: "repeat-count", description: "Repetitions") var repeatCount: Int = 2
    @Option(description: "Suffix") var suffix: String? = nil
}

/// Independent handwritten aggregate whose schema spells out every descriptor and constructor assignment.
private struct HandwrittenGreetingArguments: CommandArguments {
    let person: String
    let shade: MacroShade
    let token: MacroToken
    let count: Int?
    let user: UserReference?
    let repeatCount: Int
    let suffix: String?
    /// Uses existing runtime validation without compiler-generated descriptor construction.
    static var schema: CommandArgumentSchema<Self> {
        /// Creates each inert descriptor and captures the exact typed keys for one per-invocation aggregate.
        /// - Throws: Existing registration or schema validation errors; no handler or response work executes.
        get throws {
            let person = try ArgumentOption<String>(name: "person", description: "Person")
            let shade = try ArgumentOption<MacroShade>(name: "shade", description: "Shade")
            let token = try ArgumentOption<MacroToken>(name: "token", description: "Token")
            let count = try ArgumentOption<Int?>(name: "count", description: "Count")
            let user = try ArgumentOption<UserReference?>(name: "user", description: "User")
            let repeats = try ArgumentOption<Int>(name: "repeat-count", description: "Repetitions", defaultValue: .value(2))
            let suffix = try ArgumentOption<String?>(name: "suffix", description: "Suffix", defaultValue: .value(nil))
            return try CommandArgumentSchema(options: [person.erased, shade.erased, token.erased, count.erased, user.erased, repeats.erased, suffix.erased]) { decoder in
                try Self(person: decoder.value(for: person), shade: decoder.value(for: shade), token: decoder.value(for: token),
                    count: decoder.value(for: count), user: decoder.value(for: user), repeatCount: decoder.value(for: repeats), suffix: decoder.value(for: suffix))
            }
        }
    }
}

/// Generated command metadata and contribution convenience retain explicit manual response ownership.
@SlashCommand("greet", description: "Greet a person")
private struct GeneratedGreeting {
    typealias Arguments = GeneratedGreetingArguments
    let recorder: MacroInvocationRecorder
    var fails = false
    /// Records only explicit router invocations, leaving the existing response owner pending.
    /// - Parameters:
    ///   - context: Local trusted interaction; response behavior is deliberately untouched.
    ///   - arguments: Fresh compiled-schema values for this invocation.
    /// - Throws: The injected failure after recording when fails is true; actor access suspends normally.
    func execute(_ context: InteractionContext, arguments: Arguments) async throws {
        await recorder.record("\(arguments.person):\(arguments.shade.rawValue):\(arguments.token.text):\(arguments.count.map(String.init) ?? "nil"):\(arguments.user?.id.description ?? "nil"):\(arguments.repeatCount)")
        if fails { throw MacroInvocationFailure.failed }
    }
}

/// Handwritten command conformance proving macro convenience is unnecessary for the same runtime behavior.
private struct HandwrittenGreeting: ManualSlashCommandHandler {
    typealias Arguments = HandwrittenGreetingArguments
    let recorder: MacroInvocationRecorder
    /// Provides the same finite low-level metadata as the attached macro.
    var command: SlashCommandMetadata { .init(name: "greet", description: "Greet a person") }
    /// Observes one independently decoded invocation without implicit response or transport ownership.
    /// - Parameters:
    ///   - context: Local trusted interaction whose pending response state is preserved.
    ///   - arguments: Independently decoded handwritten-schema values.
    func execute(_ context: InteractionContext, arguments: Arguments) async throws {
        await recorder.record("\(arguments.person):\(arguments.shade.rawValue):\(arguments.token.text):\(arguments.count.map(String.init) ?? "nil"):\(arguments.user?.id.description ?? "nil"):\(arguments.repeatCount)")
    }
}

/// Serial observation of actual handler work without sleeps, timers or unchecked shared state.
private actor MacroInvocationRecorder {
    var values: [String] = []
    /// Appends exactly one controlled invocation result in actor admission order.
    /// - Parameter value: Synthetic nonsecret result compared by the parity assertions.
    func record(_ value: String) { values.append(value) }
}

/// Local sentinel whose propagation proves generated routes preserve existing handler failures.
private enum MacroInvocationFailure: Error { case failed }
