import Crypto
import DiscordCommandDSL
import DiscordCore
import DiscordDSL
import DiscordDSLMacros
import DiscordHTTP
import DiscordInteractions
import DiscordModels
import DiscordNIOTransport
import DiscordTransport
import Foundation

/// No arguments are retained or mutated between invocations.
@CommandArguments struct PingArguments: Sendable {}

/// The compiler generates metadata and contribution plumbing; response delivery remains runtime owned.
@SlashCommand("ping", description: "Check this command application")
struct Ping: SlashCommandHandler {
    typealias Arguments = PingArguments

    /// Produces one explicit ephemeral message after complete invocation decoding.
    /// - Parameters:
    ///   - context: Authenticated snapshot without raw responder access.
    ///   - arguments: Fresh empty arguments; no shared invocation state exists.
    /// - Returns: Validated pong message sent once by the immediate response adapter.
    /// - Throws: Message validation failures; cancellation/delivery are owned by the router/responder.
    func execute(_ context: CommandContext, arguments: Arguments) async throws -> MessageResponse {
        try MessageResponse(InteractionMessageCreate(content: .value("Pong!"), flags: .value(.ephemeral)))
    }
}

/// Standalone macro-authored HTTP consumer. The default is a real signed synthetic exchange with no sockets.
@main struct DSLCommands {
    /// Chooses offline qualification by default, or explicitly opts into a caller-configured loopback listener.
    /// Listener mode requires DISCORD_APPLICATION_ID and DISCORD_PUBLIC_KEY and optional DISCORD_HTTP_PORT.
    /// Neither mode reads a bot token or registers commands. HTTPS termination remains deployment owned.
    /// - Throws: Configuration, compile, crypto, response validation, listener or cooperative cancellation errors.
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.isEmpty || arguments == ["--offline"] || arguments == ["--listen"] else {
            print("Usage: DSLCommands [--offline | --listen]")
            throw DiscordError.validation(.invalidValue)
        }
        let ping = try Ping().contribution(id: "example.ping", source: .init(fileID: "DSLCommands", line: 1))
        let commands = try CommandCompilation.compile(Module(id: "example") { ping })
        if arguments == ["--listen"] {
            let environment = ProcessInfo.processInfo.environment
            guard let rawID = environment["DISCORD_APPLICATION_ID"], let identifier = UInt64(rawID),
                  let publicKey = environment["DISCORD_PUBLIC_KEY"],
                  let port = UInt16(environment["DISCORD_HTTP_PORT"] ?? "8080"), port > 0 else {
                print("Set DISCORD_APPLICATION_ID and DISCORD_PUBLIC_KEY; DISCORD_HTTP_PORT defaults to 8080.")
                throw DiscordError.validation(.missingValue)
            }
            let clock = ContinuousClock()
            let application = try CommandApplication(applicationID: .init(rawValue: identifier), commands: commands,
                ingress: DiscordSignedIngress(verifier: SignedRequestVerifier(publicKey: publicKey)),
                admission: InteractionAcknowledgementAdmission(), maximumConcurrentRequests: 32)
            let listener = try await NIOHTTPIngress.bind(localAddress: .init(host: "127.0.0.1", port: port),
                maximumConnections: 64, maximumPendingRequests: 32, context: TransportContext(clock: clock))
            print("Loopback command listener ready on port \(port); registration is explicit and separate.")
            try await application.run(listener: listener, context: TransportContext(clock: clock))
        } else {
            try await offline(commands)
            print("Offline macro /ping: signed HTTP 200, one ephemeral Pong!, zero registration requests.")
        }
    }

    /// Executes a genuine Ed25519-authenticated local request through the compiled command application.
    /// - Parameter commands: Inert compiled macro catalog; no registration transport is constructed.
    /// - Throws: Signing, stream, routing or exact callback assertion failures.
    static func offline(_ commands: CompiledCommands) async throws {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 9, count: 32))
        let bytes = Data("""
        {"id":"1","application_id":"2","type":2,"token":"synthetic-offline","version":1,
        "data":{"id":"3","name":"ping","type":1},"app_permissions":"0","entitlements":[],
        "authorizing_integration_owners":{},"attachment_size_limit":1000}
        """.utf8)
        let signature = try key.signature(for: Data("1000".utf8) + bytes)
        let application = try CommandApplication(applicationID: .init(rawValue: 2), commands: commands,
            ingress: DiscordSignedIngress(verifier: SignedRequestVerifier(publicKey: hex(key.publicKey.rawRepresentation), now: { 1000 })),
            admission: InteractionAcknowledgementAdmission())
        let responder = OfflineResponder()
        let request = HTTPRequest(method: "POST", url: URL(string: "https://example.invalid/interactions")!,
            headers: [HTTPHeader(name: "X-Signature-Ed25519", value: hex(signature)),
                HTTPHeader(name: "X-Signature-Timestamp", value: "1000")],
            body: try RequestBody(bytes: bytes, contentType: "application/json").makeStream())
        try await application.handle(HTTPExchange(request: request, responder: responder), context: TransportContext(clock: ContinuousClock()))
        guard await responder.responseCount == 1 else { throw DiscordError.transport(.invalidResponse) }
    }

    /// Encodes the fixed offline key/signature in Discord's ASCII header format.
    /// - Parameter bytes: Synthetic public key or signature.
    /// - Returns: Lowercase hexadecimal with two characters per byte.
    static func hex(_ bytes: Data) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
}

/// Exactly-once offline response assertion, with finite body collection and no network adapter.
private actor OfflineResponder: HTTPResponder {
    private(set) var responseCount = 0

    /// Consumes the single callback and requires exact parity with the expected existing-model response.
    /// - Parameters:
    ///   - response: Owned callback body; always closed after bounded collection.
    ///   - context: Caller clock/deadline; cancellation and expiration are checked before collection.
    /// - Throws: Duplicate response, clock/cancellation failure, oversized body or callback mismatch.
    func respond<C: Clock>(_ response: HTTPResponse, context: TransportContext<C>) async throws where C.Duration == Duration {
        guard responseCount == 0 else { await response.body?.close(); throw DiscordError.validation(.invalidValue) }
        responseCount += 1
        do {
            try context.check()
            let expected = Data(#"{"type":4,"data":{"content":"Pong!","flags":64}}"#.utf8)
            let bytes = try await ResponseBody.collect(response.body, maximumBytes: 1024)
            guard response.status == 200, try JSONValue.parse(bytes) == JSONValue.parse(expected) else {
                throw DiscordError.transport(.invalidResponse)
            }
        } catch { await response.body?.close(); throw error }
    }

    /// Releases no external resources; all response bodies are consumed or closed by `respond`.
    func close() {}
}
