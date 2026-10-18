import DiscordCommandDSL
import DiscordCommands
import DiscordCore
import DiscordDSL
import DiscordInteractions
import DiscordModels
import Foundation
import Testing

/// Local public-API equivalence and lifecycle checks. No credentials, transports or timers are run.
@Suite(.timeLimit(.minutes(1))) struct CompilationTests {
    /// Typed registration equals direct low-level construction, including advanced metadata and ordering.
    /// Compilation and router construction must leave both behavior and response ownership untouched.
    /// - Throws: Unexpected definition, schema or lowering errors fail the test.
    @Test func registrationParityAndInertConstruction() async throws {
        let recorder = InvocationRecorder()
        let command = try SlashCommand(id: "greet", handler: GreetingHandler(recorder: recorder))
        let plan = try CommandCompilation.compile(Module(id: "community") { command })
        let direct = try CommandDefinition.slash(name: "greet", description: "Greet a person",
            nameLocalizations: .value(["de": "gruss"]), defaultMemberPermissions: .value("0"),
            integrationTypes: [.guildInstall], contexts: [.guild], nsfw: false) {
                try ApplicationCommandOptionCreate(type: .string, name: "person", description: "Person", required: true)
                try ApplicationCommandOptionCreate(type: .integer, name: "count", description: "Count", required: false)
            }
        #expect(plan.definitions.count == 1)
        #expect(try plan.definitions[0].request.jsonValue().serialized() == direct.request.jsonValue().serialized())
        #expect(plan.routes[0].key == (try .command(name: "greet")))
        #expect(plan.description.declarations[0].modulePath == ["community"])
        _ = try plan.makeRouter()
        #expect(await recorder.values.isEmpty)
        #expect(throws: (any Error).self) { try plan.makeRouter(maximumConcurrentHandlers: 0) }
    }

    /// Both receipt modes and concurrent callers receive invocation-local arguments and explicit defaults.
    /// A handler that does not reply must leave the existing response owner pending.
    /// - Parameter gateway: Selects the injected delivery mode, without creating a Gateway connection.
    /// - Throws: Any unexpected local parsing, route, or handler error fails the test.
    @Test(arguments: [false, true]) func invocationParity(gateway: Bool) async throws {
        let recorder = InvocationRecorder()
        let plan = try CommandCompilation.compile(try SlashCommand(id: "greet", handler: GreetingHandler(recorder: recorder)))
        let router = try plan.makeRouter()
        let context = try Self.context(options: #"[{"name":"person","type":3,"value":"Ada"}]"#,
            mode: gateway ? .gateway : .http)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<12 {
                let distinct = try Self.context(options: "[{\"name\":\"person\",\"type\":3,\"value\":\"Person\(index)\"},{\"name\":\"count\",\"type\":4,\"value\":\(index)}]",
                    mode: gateway ? .gateway : .http)
                group.addTask {
                    let matched = try await router.route(distinct)
                    #expect(matched)
                }
            }
            try await group.waitForAll()
        }
        #expect(await recorder.values.sorted() == (0..<12).map { "Person\($0):\($0)" }.sorted())
        #expect(try await router.route(context))
        #expect(await recorder.values.last == "Ada:2")
        #expect(await context.responder.snapshot() == .pending)
        #expect(await router.activeHandlerCount == 0)

        let directRecorder = InvocationRecorder()
        let direct = try CommandRouter(routes: [CommandRoute(key: .command(name: "greet")) { input in
            guard case .value(.command(let data)) = input.interaction.data,
                  case .value(let options) = data.options,
                  let person = options.first, case .value(.string(let name)) = person.value else {
                throw InvocationFailure.failed
            }
            await directRecorder.record("\(name):2")
        }])
        #expect(try await direct.route(context))
        #expect(await directRecorder.values == ["Ada:2"])
    }

    /// Invalid values fail before user behavior; ambiguous duplicates remain unhandled by the existing router.
    /// - Parameter options: Synthetic malformed, incomplete, unknown or wrongly typed leaf list.
    /// - Throws: Setup failures are unexpected; schema failures are asserted inside the test.
    @Test(arguments: ["[]", #"[{"name":"person","type":3,"value":null}]"#,
        #"[{"name":"person","type":5,"value":true}]"#,
        #"[{"name":"person","type":3,"value":"Ada"},{"name":"future","type":3,"value":"hidden"}]"#,
        #"[{"name":"person","type":3,"value":"Ada"},{"name":"person","type":3,"value":"Grace"}]"#,
        #"[{"name":"person","type":3,"value":"Ada","focused":true}]"#])
    func invalidInvocation(options: String) async throws {
        let recorder = InvocationRecorder()
        let plan = try CommandCompilation.compile(try SlashCommand(id: "greet", handler: GreetingHandler(recorder: recorder)))
        let router = try plan.makeRouter()
        if options.contains("null") {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try Self.context(options: options) }
            #expect(await recorder.values.isEmpty)
            return
        }
        let input = try Self.context(options: options)
        if options.contains("Grace") { #expect(try await router.route(input) == false) }
        else {
            await #expect(throws: ArgumentDiagnostic.self) { try await router.route(input) }
        }
        #expect(await recorder.values.isEmpty)
        #expect(await router.activeHandlerCount == 0)
    }

    /// The existing router enforces exact names/types/paths and propagates handler failure/cancellation.
    /// - Throws: Local setup failures fail; terminal handler errors and cancellation are explicitly asserted.
    @Test func routingFailureAndCancellation() async throws {
        let recorder = InvocationRecorder()
        let plan = try CommandCompilation.compile(try SlashCommand(id: "greet", handler: GreetingHandler(recorder: recorder, fails: true)))
        let router = try plan.makeRouter()
        let context = try Self.context(options: #"[{"name":"person","type":3,"value":"Ada"}]"#)
        await #expect(throws: InvocationFailure.failed) { try await router.route(context) }
        #expect(await router.activeHandlerCount == 0)
        #expect(try await router.route(Self.context(options: "[]", name: "other")) == false)
        #expect(try await router.route(Self.context(options: "[]", interactionType: 4)) == false)
        #expect(try await router.route(Self.context(options: #"[{"name":"sub","type":1,"options":[]}]"#)) == false)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await router.route(context)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await recorder.values == ["Ada:2"])
        #expect(await router.activeHandlerCount == 0)
    }

    /// A synchronous aggregate constructor can cancel its caller; the post-decode checkpoint prevents execution.
    /// - Throws: Setup errors fail; cancellation after decoding and null invocation structure are asserted.
    @Test func cancellationDuringDecodeAndNullEnvelope() async throws {
        let recorder = InvocationRecorder()
        let plan = try CommandCompilation.compile(try SlashCommand(id: "cancel", handler: CancelDuringDecode(recorder: recorder)))
        let router = try plan.makeRouter()
        let input = try Self.context(options: "[]")
        let task = Task { try await router.route(input) }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await recorder.values.isEmpty)
        #expect(await router.activeHandlerCount == 0)
        let regular = try CommandCompilation.compile(try SlashCommand(id: "greet", handler: GreetingHandler(recorder: recorder)))
        let ordinaryRouter = try regular.makeRouter()
        await #expect(throws: DiscordError.transport(.invalidResponse)) {
            try await ordinaryRouter.route(Self.context(options: "null"))
        }
    }

    /// Duplicate route/identity and structural bounds reject complete compilation without invocation.
    /// - Throws: Expected diagnostics are asserted; unexpected local authoring failures fail the test.
    @Test func boundedCompilationAndOrdering() async throws {
        let recorder = InvocationRecorder()
        let a = try SlashCommand(id: "one", handler: GreetingHandler(recorder: recorder))
        let b = try SlashCommand(id: "two", handler: GreetingHandler(recorder: recorder))
        #expect(throws: CommandCompilationDiagnostic.self) {
            try CommandCompilation.compile(Module(id: "m") { a; b })
        }
        #expect(throws: DefinitionDiagnostic.self) {
            try CommandCompilation.compile(Module(id: "m") { a; a })
        }
        #expect(throws: DefinitionDiagnostic.self) { try CommandCompilation.compile(a, limits: .init(maxDeclarations: 0)) }
        #expect(throws: DefinitionDiagnostic.self) { try CommandCompilation.compile(a, limits: .init(maxTextBytes: 0)) }
        #expect(throws: DefinitionDiagnostic.self) { try CommandCompilation.compile(Module(id: "m") { a }, limits: .init(maxDepth: 1)) }
        #expect(throws: DefinitionDiagnostic.self) { try CommandCompilation.compile(a, limits: .init(maxStructuralNodes: 0)) }
        let existing = try ExistingSlashCommand(id: "second", definition: .slash(name: "second", description: "Second"),
            route: CommandRoute(key: .command(name: "second")) { _ in })
        let ordered = try CommandCompilation.compile(Module(id: "m") { a; existing })
        #expect(ordered.definitions.map(\.request.name) == ["greet", "second"])
        #expect(try ordered.description == CommandCompilation.compile(Module(id: "m", source: ordered.description.modules[0].source) { a; existing }).description)
        let empty = try CommandCompilation.compile(EmptyBotDefinition())
        #expect(empty.definitions.isEmpty)
        #expect(try await empty.makeRouter().route(Self.context(options: "[]")) == false)
        #expect(await recorder.values.isEmpty)
    }

    /// Explicit adapters preserve the low-level pair, reject unsupported shapes, and detect spoofed metadata.
    /// - Throws: Setup failures fail; every malformed adapter is explicitly rejected.
    @Test func existingAdaptersAndUntrustedContributions() throws {
        let root = CommandRoute(key: try .command(name: "greet")) { _ in }
        let definition = try CommandDefinition.slash(name: "greet", description: "Greeting")
        let adapter = try ExistingSlashCommand(id: "raw", definition: definition, route: root)
        #expect(try CommandCompilation.compile(adapter).definitions[0].request.jsonValue() == definition.request.jsonValue())
        #expect(throws: CommandCompilationDiagnostic.self) {
            try ExistingSlashCommand(id: "raw", definition: definition,
                route: CommandRoute(key: .command(name: "other")) { _ in })
        }
        #expect(throws: CommandCompilationDiagnostic.self) {
            try ExistingSlashCommand(id: "raw", definition: .contextMenu(name: "Greet", type: .user), route: root)
        }
        for option in [
            try ApplicationCommandOptionCreate(type: .subcommand, name: "sub", description: "Sub"),
            try ApplicationCommandOptionCreate(type: .string, name: "query", description: "Query", autocomplete: true)
        ] {
            #expect(throws: CommandCompilationDiagnostic.self) {
                try ExistingSlashCommand(id: "raw", definition: .slash(name: "greet", description: "Greeting") { option }, route: root)
            }
        }
        #expect(throws: CommandCompilationDiagnostic.self) { try CommandCompilation.compile(ForgedCommand(definition: definition, route: root)) }
        #expect(throws: CommandCompilationDiagnostic.self) {
            try CommandCompilation.compile(RawDefinitionContribution(id: "raw", kind: CommandCompilation.contributionKind))
        }
        #expect(throws: DefinitionDiagnostic.self) {
            try CommandCompilation.compile(RawDefinitionContribution(id: "raw", kind: "future.command"))
        }
        let diagnostic = CommandCompilationDiagnostic(code: .invalidInvocation,
            commandName: String(repeating: "😀", count: 1000), source: .init(fileID: String(repeating: "a", count: 1000), line: 2, column: 3))
        #expect(diagnostic.commandName.unicodeScalars.count == 128)
        #expect(diagnostic.source.fileID.utf8.count == 256)
    }

    /// Invalid command metadata is contextualized at the authoring source before behavior can execute.
    /// - Throws: Expected validation is asserted; unexpected errors fail the test.
    @Test func invalidMetadata() throws {
        let source = DefinitionSourceLocation(fileID: "Commands.swift", line: 42, column: 3)
        do {
            _ = try SlashCommand(id: "bad", handler: GreetingHandler(recorder: InvocationRecorder(), name: "INVALID"), source: source)
            Issue.record("Invalid metadata was admitted")
        } catch let error as CommandCompilationDiagnostic {
            #expect(error.code == .invalidCommand)
            #expect(error.commandName == "INVALID")
            #expect(error.source == source)
        }
    }

    /// Creates inert trusted-origin test input; no signature authentication or network qualification is claimed.
    /// - Parameters:
    ///   - options: Complete JSON leaf list, including intentionally invalid shapes.
    ///   - name: Exact command name, default greet.
    ///   - interactionType: Command or autocomplete discriminator, default command.
    ///   - mode: Synthetic receipt channel, default HTTP.
    /// - Returns: Normalized input with a pending responder and inert sink.
    /// - Throws: Malformed fixture JSON/model or responder ownership validation.
    private static func context(options: String, name: String = "greet", interactionType: Int = 2,
        mode: InteractionDeliveryMode = .http) throws -> InteractionContext {
        let data = try JSONValue.parse(Data(options.utf8))
        let interaction = try Interaction(data: JSONValue.object([
            "id": .string("18446744073709551615"), "application_id": .string("9"),
            "type": .number(JSONNumber(rawValue: String(interactionType))), "token": .string("synthetic"),
            "version": .number(JSONNumber(rawValue: "1")),
            "app_permissions": .string("0"), "entitlements": .array([]),
            "authorizing_integration_owners": .object([:]),
            "attachment_size_limit": .number(JSONNumber(rawValue: "10485760")),
            "data": .object(["id": .string("8"), "name": .string(name), "type": .number(JSONNumber(rawValue: "1")), "options": data])
        ]).serialized())
        let responder = InteractionResponder(interaction: interaction, deliveryMode: mode,
            clock: InteractionClock(ContinuousClock()), sink: InteractionResponseSink(initial: { _, _ in }),
            admission: try InteractionAcknowledgementAdmission())
        return try InteractionContext(interaction: interaction, deliveryMode: mode, responder: responder)
    }
}

/// Invocation-local explicit arguments used to compare typed and direct implementations.
private struct GreetingArguments: CommandArguments {
    let person: String
    let count: Int
    /// Defines one required string and one explicit-default integer from typed descriptors.
    static var schema: CommandArgumentSchema<Self> {
        /// Builds validated descriptors once per schema capture; returns an inert constructor.
        /// - Throws: Descriptor or complete schema validation errors; no recorder is invoked.
        get throws {
            let person = try ArgumentOption<String>(name: "person", description: "Person")
            let count = try ArgumentOption<Int>(name: "count", description: "Count", defaultValue: .value(2))
            return try CommandArgumentSchema(options: [person.erased, count.erased]) { decoder in
                try Self(person: decoder.value(for: person), count: decoder.value(for: count))
            }
        }
    }
}

/// Manual handler with injected actor state; construction itself performs no work.
private struct GreetingHandler: ManualSlashCommandHandler {
    typealias Arguments = GreetingArguments
    let recorder: InvocationRecorder
    var fails = false
    var name = "greet"
    /// Returns deterministic registration metadata without invoking the recorder.
    var command: SlashCommandMetadata {
        .init(name: name, description: "Greet a person", nameLocalizations: .value(["de": "gruss"]),
            defaultMemberPermissions: .value("0"), integrationTypes: [.guildInstall], contexts: [.guild], nsfw: false)
    }
    /// Records decoded arguments and optionally fails, leaving the response pending for ownership assertions.
    /// - Parameters:
    ///   - context: Synthetic context whose responder is deliberately untouched.
    ///   - arguments: Separate values for each invocation.
    /// - Throws: The injected sentinel failure after recording when fails is true.
    func execute(_ context: InteractionContext, arguments: GreetingArguments) async throws {
        await recorder.record("\(arguments.person):\(arguments.count)")
        if fails { throw InvocationFailure.failed }
    }
}

/// Thread-safe observable work used to prove zero invocation during construction/compilation.
private actor InvocationRecorder {
    var values: [String] = []
    /// Appends one invocation result in actor admission order without suspension.
    /// - Parameter value: Nonsecret synthetic string consumed by test assertions.
    func record(_ value: String) { values.append(value) }
}

private enum InvocationFailure: Error { case failed }

/// Cancellation injection at the synchronous decode boundary, without sleeps or background work.
private struct CancellingArguments: CommandArguments {
    /// Constructs an empty aggregate after cancelling its current invocation task.
    static var schema: CommandArgumentSchema<Self> {
        /// Returns an inert schema whose constructor cancels only when decoding is explicitly invoked.
        /// - Throws: Unexpected empty-schema configuration errors fail fixture construction.
        get throws {
            try CommandArgumentSchema(options: []) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return Self()
            }
        }
    }
}

/// A handler whose execution is forbidden when the injected aggregate constructor cancels.
private struct CancelDuringDecode: ManualSlashCommandHandler {
    typealias Arguments = CancellingArguments
    let recorder: InvocationRecorder
    /// Uses the same exact root name as the synthetic invocation fixture.
    var command: SlashCommandMetadata { .init(name: "greet", description: "Cancel before execution") }
    /// Records an erroneous execution, which the cancellation test requires never to happen.
    /// - Parameters:
    ///   - context: Synthetic trusted-origin input, unused.
    ///   - arguments: Empty decoded aggregate, unused.
    func execute(_ context: InteractionContext, arguments: CancellingArguments) async throws {
        await recorder.record("unexpected")
    }
}

/// Deliberately mismatched public extension proving raw metadata cannot bypass pair validation.
private struct ForgedCommand: CommandContribution {
    let definition: CommandDefinition
    let route: CommandRoute
    /// Supplies admitted kind metadata whose payload disagrees with the actual registration.
    var declaration: RawDefinitionContribution { .init(id: "forged", kind: CommandCompilation.contributionKind) }
}
