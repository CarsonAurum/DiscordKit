import Crypto
import DiscordCommandDSL
import DiscordCore
import DiscordDSL
import DiscordDSLMacros
import DiscordHTTP
import DiscordInteractions
import DiscordModels
import DiscordTransport
import Foundation

/// One typed search invocation; autocomplete uses its own partial input contract.
struct SearchArguments: CommandArguments {
    let query: String
    static var schema: CommandArgumentSchema<Self> {
        /// Captures the same finite option used by the autocomplete contribution without executing it.
        /// - Throws: Existing descriptor/schema validation errors.
        get throws {
            let query = try FamilyExamples.queryOption()
            return try CommandArgumentSchema(options: [query.erased]) { try Self(query: $0.value(for: query)) }
        }
    }
}

/// A complete invocation validates arguments before producing one message.
@SlashCommand("search", description: "Search an offline catalog")
struct Search: SlashCommandHandler {
    typealias Arguments = SearchArguments
    /// Produces a fixed local response after complete schema decoding.
    /// - Parameters:
    ///   - context: Authenticated immutable snapshot without acknowledgement methods.
    ///   - arguments: Fresh complete arguments; query is never shared with another invocation.
    /// - Returns: Validated immediate message.
    /// - Throws: Existing message validation errors.
    func execute(_ context: CommandContext, arguments: Arguments) async throws -> MessageResponse {
        try MessageResponse(InteractionMessageCreate(content: .value("search")))
    }
}

/// Suggestions can execute with required sibling values absent and never construct SearchArguments.
struct SearchSuggestions: AutocompleteCommandHandler {
    /// Returns one correctly typed suggestion in response to a focused partial string.
    /// - Parameters:
    ///   - context: Snapshot with no response authority.
    ///   - input: Admitted partial options, separate from complete command arguments.
    ///   - value: Focused partial text, including empty input.
    /// - Returns: One finite string suggestion.
    /// - Throws: Existing suggestion/response validation errors.
    func execute(_ context: CommandContext, input: AutocompleteInput, value: String) async throws -> AutocompleteResponse<String> {
        try AutocompleteResponse([AutocompleteChoice(name: "Example", value: "example")])
    }
}

/// A macro contributes only user-menu registration metadata and exact protocol plumbing.
@UserCommand("Inspect User")
struct InspectUser: UserCommandHandler {
    /// Responds without fetching or treating a partial target as authorization.
    /// - Parameters:
    ///   - context: Immutable authenticated snapshot.
    ///   - target: Exact selected user and optional same-interaction projections.
    /// - Returns: One validated local message.
    /// - Throws: Existing message validation failures.
    func execute(_ context: CommandContext, target: UserReference) async throws -> MessageResponse {
        try MessageResponse(InteractionMessageCreate(content: .value("user")))
    }
}

/// The message menu has a distinct route namespace and typed partial target.
@MessageCommand("Inspect Message")
struct InspectMessage: MessageCommandHandler {
    /// Responds without hydrating the selected partial message.
    /// - Parameters:
    ///   - context: Immutable authenticated snapshot without responder access.
    ///   - target: Exact message identity and optional partial observation.
    /// - Returns: One validated local message.
    /// - Throws: Existing message validation errors.
    func execute(_ context: CommandContext, target: MessageCommandTarget) async throws -> MessageResponse {
        try MessageResponse(InteractionMessageCreate(content: .value("message")))
    }
}

/// Exact component IDs are independent of matching modal submission IDs.
struct ExampleButton: ComponentHandler {
    let customID = "example.form"
    let componentType = ComponentType.button
    /// Handles only the admitted exact button without a prefix parser or dynamic route capture.
    /// - Parameters:
    ///   - context: Immutable interaction snapshot.
    ///   - input: Kind-checked button values and same-interaction resolved data.
    /// - Returns: One validated immediate message.
    /// - Throws: Existing response validation errors.
    func execute(_ context: CommandContext, input: ComponentInput) async throws -> MessageResponse {
        try MessageResponse(InteractionMessageCreate(content: .value("component")))
    }
}

/// A fresh typed modal aggregate is constructed after complete tree/field admission.
struct ExampleModalValues: ModalValues {
    let note: String
    static var schema: ModalSchema<Self> {
        /// Declares the exact text input and local constructor without executing user work.
        /// - Throws: Descriptor/schema validation errors.
        get throws {
            let note = try ModalField<String>(customID: "note")
            return try ModalSchema(fields: [note.erased]) { try Self(note: $0.value(for: note)) }
        }
    }
}

/// A modal shares the button's ID while remaining a distinct route and response family.
struct ExampleModal: ModalHandler {
    typealias Values = ExampleModalValues
    let customID = "example.form"
    /// Handles admitted invocation-local values without opening another modal.
    /// - Parameters:
    ///   - context: Authenticated immutable snapshot.
    ///   - values: Complete typed modal fields, never retained between invocations.
    /// - Returns: One validated immediate message.
    /// - Throws: Existing response validation errors.
    func execute(_ context: CommandContext, values: Values) async throws -> MessageResponse {
        try MessageResponse(InteractionMessageCreate(content: .value("modal")))
    }
}

/// Independent offline command-family consumer; every callback passes real signed HTTP verification.
enum FamilyExamples {
    /// Builds the identical option registration used by the full command and focused partial provider.
    /// - Returns: Required string descriptor with explicit autocomplete enabled.
    /// - Throws: Existing option validation errors.
    static func queryOption() throws -> ArgumentOption<String> {
        try ArgumentOption(name: "query", description: "Search text", autocomplete: true)
    }

    /// Compiles root/grouped slash, user/message menus and route-only autocomplete/component/modal handlers.
    /// - Returns: Three root command kinds plus a grouped root and their finite exact routes.
    /// - Throws: Macro/manual metadata, schema, structural or catalog consistency errors.
    static func catalog() throws -> CompiledCommands {
        let search = try Search().contribution(id: "search", source: .init(fileID: "FamilyExamples", line: 1))
        let tree = try SlashCommandTree(id: "tools", command: .init(name: "tools", description: "Offline tools"),
            children: [.group(try SlashSubcommandGroup(name: "admin", description: "Administration",
                subcommands: [try Ping().slashSubcommand()]))])
        let user = try InspectUser().contribution(id: "user", source: .init(fileID: "FamilyExamples", line: 1))
        let message = try InspectMessage().contribution(id: "message", source: .init(fileID: "FamilyExamples", line: 1))
        let autocomplete = try AutocompleteCommand(id: "autocomplete", name: "search", option: queryOption(), handler: SearchSuggestions())
        let component = try ComponentCommand(id: "component", handler: ExampleButton())
        let modal = try ModalCommand(id: "modal", handler: ExampleModal())
        return try CommandCompilation.compile(Module(id: "families") { search; tree; user; message; autocomplete; component; modal })
    }

    /// Executes each supported protocol family without credentials, sockets, registration or a Discord host.
    /// Every request receives a fresh verifier/response owner and an exact model-equivalent callback assertion.
    /// - Throws: Any signing, authentication, routing, decoding or callback parity failure.
    static func run() async throws {
        let commands = try catalog()
        let cases: [(Int, String, String)] = [
            (2, #"{"id":"3","name":"search","type":1,"options":[{"name":"query","type":3,"value":"example"}]}"#, #"{"type":4,"data":{"content":"search"}}"#),
            (2, #"{"id":"3","name":"tools","type":1,"options":[{"name":"admin","type":2,"options":[{"name":"ping","type":1}]}]}"#, #"{"type":4,"data":{"content":"Pong!","flags":64,"allowed_mentions":{"parse":[],"replied_user":false}}}"#),
            (2, #"{"id":"3","name":"Inspect User","type":2,"target_id":"18446744073709551615"}"#, #"{"type":4,"data":{"content":"user"}}"#),
            (2, #"{"id":"3","name":"Inspect Message","type":3,"target_id":"18446744073709551615"}"#, #"{"type":4,"data":{"content":"message"}}"#),
            (4, #"{"id":"3","name":"search","type":1,"options":[{"name":"query","type":3,"value":"e","focused":true}]}"#, #"{"type":8,"data":{"choices":[{"name":"Example","value":"example"}]}}"#),
            (3, #"{"custom_id":"example.form","component_type":2}"#, #"{"type":4,"data":{"content":"component"}}"#),
            (5, #"{"custom_id":"example.form","components":[{"type":18,"id":1,"component":{"type":4,"id":2,"custom_id":"note","value":"hello"}}]}"#, #"{"type":4,"data":{"content":"modal"}}"#),
        ]
        for (kind, data, expected) in cases {
            try await exchange(commands: commands, kind: kind, data: data, expected: expected)
        }
    }

    /// Signs one synthetic interaction and transfers its finite body through the independent HTTP application.
    /// - Parameters:
    ///   - commands: Inert shared catalog; no registration client is created.
    ///   - kind: Current API v10 interaction discriminator.
    ///   - data: Fixed local JSON interaction data with no user interpolation.
    ///   - expected: Fixed expected callback JSON for exact parity assertion.
    /// - Throws: Signing, stream, ingress, routing or response assertion failures.
    static func exchange(commands: CompiledCommands, kind: Int, data: String, expected: String) async throws {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 9, count: 32))
        let source = kind == 3 ? #","message":{"id":"1","channel_id":"2","author":{"id":"3","username":"offline","discriminator":"0","avatar":null},"content":"Source","timestamp":"2026-10-18T00:00:00Z","edited_timestamp":null,"tts":false,"mention_everyone":false,"mentions":[],"mention_roles":[],"attachments":[],"embeds":[],"pinned":false,"type":0}"# : ""
        let bytes = Data("""
        {"id":"1","application_id":"2","type":\(kind),"token":"synthetic-offline","version":1,
        "data":\(data),"app_permissions":"0","entitlements":[],"authorizing_integration_owners":{},"attachment_size_limit":1000\(source)}
        """.utf8)
        let signature = try key.signature(for: Data("1000".utf8) + bytes)
        let app = try CommandApplication(applicationID: .init(rawValue: 2), commands: commands,
            ingress: DiscordSignedIngress(verifier: SignedRequestVerifier(publicKey: DSLCommands.hex(key.publicKey.rawRepresentation), now: { 1000 })),
            admission: InteractionAcknowledgementAdmission())
        let responder = try FamilyOfflineResponder(expected: JSONValue.parse(Data(expected.utf8)))
        let request = HTTPRequest(method: "POST", url: URL(string: "https://example.invalid/interactions")!,
            headers: [HTTPHeader(name: "X-Signature-Ed25519", value: DSLCommands.hex(signature)),
                HTTPHeader(name: "X-Signature-Timestamp", value: "1000")],
            body: try RequestBody(bytes: bytes, contentType: "application/json").makeStream())
        try await app.handle(HTTPExchange(request: request, responder: responder), context: TransportContext(clock: ContinuousClock()))
        guard await responder.count == 1 else { throw DiscordError.transport(.invalidResponse) }
    }
}

/// Finite exactly-once response assertions; bodies always transfer to bounded collection.
private actor FamilyOfflineResponder: HTTPResponder {
    let expected: JSONValue
    private(set) var count = 0
    /// Captures a fixed expected payload without starting work or acquiring a resource.
    /// - Parameter expected: Trusted local JSON fixture, never received data.
    init(expected: JSONValue) { self.expected = expected }
    /// Consumes one callback and compares exact structure, fields and scalar values.
    /// - Parameters:
    ///   - response: Owned finite callback stream.
    ///   - context: Existing monotonic cancellation/deadline authority.
    /// - Throws: Duplicate callback, status/JSON mismatch, deadline/cancellation or oversized body.
    func respond<C: Clock>(_ response: HTTPResponse, context: TransportContext<C>) async throws where C.Duration == Duration {
        guard count == 0 else { await response.body?.close(); throw DiscordError.validation(.invalidValue) }
        count += 1
        do {
            try context.check()
            let bytes = try await ResponseBody.collect(response.body, maximumBytes: 4096)
            guard response.status == 200, try JSONValue.parse(bytes) == expected else { throw DiscordError.transport(.invalidResponse) }
        } catch { await response.body?.close(); throw error }
    }
    /// Owns no external resources; response bodies are consumed or closed by respond.
    func close() {}
}
