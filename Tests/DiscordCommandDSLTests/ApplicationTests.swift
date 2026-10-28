// File: Tests/DiscordCommandDSLTests/ApplicationTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Crypto
import DiscordCommandDSL
import DiscordCommands
import DiscordCore
import DiscordDSL
import DiscordHTTP
import DiscordInteractions
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing

/// Real signed synthetic HTTP exchanges prove host composition and explicit registration without sockets.
@Suite(.timeLimit(.minutes(1))) struct ApplicationTests {
    /// Constructs a finite signed application from a manual command so host tests remain macro independent.
    /// - Parameters:
    ///   - maximumRequests: Active exchange bound, default two.
    ///   - autoDefer: Deliberately competing policy for negative initialization tests; default nil.
    ///   - handler: Optional exact route behavior; nil sends a public pong.
    /// - Returns: Inert command host with an independently owned verifier/router/reconciler.
    /// - Throws: Authoring, signature policy or host configuration errors.
    static func application(maximumRequests: Int = 2, autoDefer: InteractionAutoDeferPolicy? = nil,
        handler: (@Sendable (InteractionContext) async throws -> Void)? = nil) throws -> CommandApplication {
        let route = try CommandRoute(key: .command(name: "ping")) { context in
            if let handler { try await handler(context) }
            else { try await context.responder.reply(InteractionMessageCreate(content: .value("pong"))) }
        }
        let commands = try CommandCompilation.compile(ExistingSlashCommand(id: "ping",
            definition: .slash(name: "ping", description: "Check response ownership"), route: route))
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 9, count: 32))
        return try CommandApplication(applicationID: .init(rawValue: 2), commands: commands,
            ingress: DiscordSignedIngress(verifier: SignedRequestVerifier(publicKey: hex(key.publicKey.rawRepresentation),
                replayPolicy: .allowIdenticalRetries, now: { 1000 })),
            admission: InteractionAcknowledgementAdmission(), maximumConcurrentRequests: maximumRequests,
            autoDefer: autoDefer)
    }

    /// Encodes exact bytes for Discord's ASCII hexadecimal signature headers.
    /// - Parameter bytes: Public key or signature; never a real credential.
    /// - Returns: Two lowercase hexadecimal characters per byte.
    static func hex(_ bytes: Data) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

    /// Builds a complete synthetic command or Discord PING with optional invalid envelope fields.
    /// - Parameters:
    ///   - name: Route name, default ping.
    ///   - application: Expected owner unless deliberately varied, default two.
    ///   - ping: True produces an interaction PING with no command data.
    /// - Returns: Exact deterministic JSON bytes preserving the local-only token marker.
    static func bytes(name: String = "ping", application: Int = 2, ping: Bool = false) -> Data {
        if ping { return Data("{\"id\":\"1\",\"application_id\":\"\(application)\",\"type\":1,\"token\":\"synthetic\",\"version\":1}".utf8) }
        return Data("""
        {"id":"1","application_id":"\(application)","type":2,"token":"synthetic","version":1,
        "data":{"id":"3","name":"\(name)","type":1},"app_permissions":"0","entitlements":[],
        "authorizing_integration_owners":{},"attachment_size_limit":1000}
        """.utf8)
    }

    /// Signs original bytes and transfers a finite body into an exchange.
    /// - Parameters:
    ///   - bytes: Original JSON or intentionally malformed content.
    ///   - responder: Single-response scripted owner.
    ///   - valid: False mutates the signature without mutating the body; default true.
    /// - Returns: Local request/response mechanics; no network or credentials are involved.
    /// - Throws: Ed25519 signing, URL or body validation failures.
    static func exchange(_ bytes: Data, responder: any HTTPResponder, valid: Bool = true) throws -> HTTPExchange {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 9, count: 32))
        let signature = try key.signature(for: Data("1000".utf8) + bytes)
        let headers = [HTTPHeader(name: "X-Signature-Ed25519", value: valid ? hex(signature) : String(repeating: "0", count: 128)),
            HTTPHeader(name: "X-Signature-Timestamp", value: "1000")]
        return HTTPExchange(request: HTTPRequest(method: "POST", url: URL(string: "https://example.invalid/interactions")!,
            headers: headers, body: try RequestBody(bytes: bytes, contentType: "application/json").makeStream()), responder: responder)
    }

    /// Signed command and PING each reserve exactly one callback; constructor/serving never use REST registration.
    /// - Parameter ping: Selects protocol PONG versus routed message response.
    /// - Throws: Unexpected synthetic signing or host errors fail this test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func signedDispatch(ping: Bool) async throws {
        let clock = ManualClock(), app = try Self.application()
        let responder = ScriptedHTTPResponder { response in
            #expect(response.status == 200)
            let payload = try JSONValue.parse(await ResponseBody.collect(response.body, maximumBytes: 1000))
            let expected = ping ? #"{"type":1}"# : #"{"type":4,"data":{"content":"pong"}}"#
            #expect(payload == (try JSONValue.parse(Data(expected.utf8))))
        }
        #expect(await responder.reservationCount == 0)
        try await app.handle(Self.exchange(Self.bytes(ping: ping), responder: responder), context: TransportContext(clock: clock))
        #expect(await responder.reservationCount == 1)
        #expect(await responder.completionCount == 1)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Signature, application and parse failures are rejected before command execution; unmatched routes propagate.
    /// - Parameter variant: Authentication, ownership, parsing or unmatched-route failure.
    /// - Throws: Unexpected setup errors fail; unmatched dispatch is asserted explicitly.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<4) func rejectedDispatch(variant: Int) async throws {
        let app = try Self.application(handler: { _ in Issue.record("Rejected request executed handler") })
        let responder = ScriptedHTTPResponder { response in #expect(response.status == [401, 403, 400, 500][variant]) }
        let bytes = variant == 1 ? Self.bytes(application: 99) : variant == 2 ? Data("bad".utf8) : Self.bytes(name: variant == 3 ? "missing" : "ping")
        let exchange = try Self.exchange(bytes, responder: responder, valid: variant != 0)
        if variant == 3 {
            await #expect(throws: CommandApplicationError.unmatchedCommand) {
                try await app.handle(exchange, context: TransportContext(clock: ManualClock()))
            }
        } else { try await app.handle(exchange, context: TransportContext(clock: ManualClock())) }
        #expect(await responder.reservationCount == 1)
    }

    /// Invalid host bounds and every competing auto-defer mode fail synchronously before network or handlers.
    /// - Throws: Unexpected policy initialization errors fail this test.
    @Test func configurationAdmission() throws {
        for bound in [0, -1] { #expect(throws: DiscordError.validation(.invalidValue)) { try Self.application(maximumRequests: bound) } }
        for mode: InteractionAutoDeferPolicy.Mode in [.message(ephemeral: false), .message(ephemeral: true), .update] {
            #expect(throws: CommandApplicationError.competingAutoDefer) { try Self.application(autoDefer: .init(mode: mode)) }
        }
    }

    /// Finite ingress is drained in bounded groups; normal EOF and empty input close listener ownership.
    /// - Parameter count: Empty, exactly one full group or multiple groups of signed requests.
    /// - Throws: Unexpected signing or serving failures fail this test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [0, 2, 5]) func runDrainsAndCloses(count: Int) async throws {
        let tracker = ResourceCounter(), lease = await tracker.acquire()
        let responders = (0..<count).map { _ in ScriptedHTTPResponder() }
        let exchanges = try responders.map { try Self.exchange(Self.bytes(), responder: $0) }
        let listener = try ScriptedHTTPIngress(incoming: exchanges, lease: lease)
        let app = try Self.application(), clock = ManualClock()
        try await app.run(listener: listener, context: TransportContext(clock: clock))
        #expect(await listener.acceptanceCount == count)
        for responder in responders { #expect(await responder.completionCount == 1) }
        #expect(await tracker.snapshot().live == 0)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Pre-cancellation closes all queued exchanges and the listener without transferring work.
    /// - Throws: Unexpected fixture configuration fails; cancellation itself is expected.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancelledRunClosesQueuedOwnership() async throws {
        let tracker = ResourceCounter(), lease = await tracker.acquire()
        let listener = try ScriptedHTTPIngress(incoming: [Self.exchange(Self.bytes(), responder: ScriptedHTTPResponder())], lease: lease)
        let app = try Self.application()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await app.run(listener: listener, context: TransportContext(clock: ManualClock()))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await listener.acceptanceCount == 0)
        #expect(await tracker.snapshot().live == 0)
    }

    /// A handler failure is propagated after one response and closes queued ingress resources without retries.
    /// - Throws: Unexpected setup errors fail; exact original handler failure is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func runFailureClosesListener() async throws {
        let tracker = ResourceCounter(), lease = await tracker.acquire()
        let response = ScriptedHTTPResponder { response in #expect(response.status == 500) }
        let listener = try ScriptedHTTPIngress(incoming: [Self.exchange(Self.bytes(), responder: response)], lease: lease)
        let app = try Self.application(maximumRequests: 1, handler: { _ in throw TestSupportFailure.scripted("handler") })
        await #expect(throws: TestSupportFailure.scripted("handler")) {
            try await app.run(listener: listener, context: TransportContext(clock: ManualClock()))
        }
        #expect(await tracker.snapshot().live == 0)
        #expect(await response.reservationCount == 1)
    }

    /// A handler failure interrupts a suspended next acceptance and releases both accepted and queued ownership.
    /// The virtual-clock sleeper is removed before return, so failure cannot wait for another connection.
    /// - Throws: Unexpected setup errors fail; the exact handler error is required.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func handlerFailureInterruptsAcceptance() async throws {
        let accepting = TestBarrier(), clock = ManualClock(), tracker = ResourceCounter()
        let response = ScriptedHTTPResponder(lease: await tracker.acquire())
        let queued = ScriptedHTTPResponder(lease: await tracker.acquire())
        let blocked = HTTPExchange(request: HTTPRequest(method: "GET", url: URL(string: "https://example.invalid/pending")!), responder: queued)
        let listener = try ScriptedHTTPIngress(incoming: [Self.exchange(Self.bytes(), responder: response), blocked],
            lease: await tracker.acquire(), beforeAccept: { request in
                if request.method == "GET" {
                    accepting.open()
                    try await clock.sleep(until: clock.now.advanced(by: .seconds(60)))
                }
            })
        let app = try Self.application(handler: { _ in
            try await accepting.wait()
            throw TestSupportFailure.scripted("handler")
        })
        await #expect(throws: TestSupportFailure.scripted("handler")) {
            try await app.run(listener: listener, context: TransportContext(clock: clock))
        }
        #expect(await listener.acceptanceCount == 1)
        #expect(await response.reservationCount == 1)
        #expect(await queued.reservationCount == 0)
        #expect(await tracker.snapshot().live == 0)
        #expect(clock.pendingSleepCount == 0)
    }

    /// The host admits no second exchange while its configured single active handler is suspended.
    /// - Throws: Unexpected setup, cancellation or serving errors fail this deterministic barrier test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func runBoundsActiveExchanges() async throws {
        let entered = TestBarrier(), release = TestBarrier()
        let responders = [ScriptedHTTPResponder(), ScriptedHTTPResponder()]
        let listener = try ScriptedHTTPIngress(incoming: responders.map { try Self.exchange(Self.bytes(), responder: $0) })
        let app = try Self.application(maximumRequests: 1, handler: { context in
            entered.open()
            try await release.wait()
            try await context.responder.reply(InteractionMessageCreate(content: .value("pong")))
        })
        let task = Task { try await app.run(listener: listener, context: TransportContext(clock: ManualClock())) }
        try await entered.wait()
        #expect(await listener.acceptanceCount == 1)
        release.open()
        try await task.value
        #expect(await listener.acceptanceCount == 2)
        for responder in responders { #expect(await responder.completionCount == 1) }
    }

    /// Only explicit synchronization sends a fresh list and preserves an unmanaged registration without writes.
    /// - Throws: Unexpected host, response or REST errors fail this test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func synchronizationIsExplicit() async throws {
        let clock = ManualClock(), app = try Self.application()
        let list = Data(#"[{"id":"3","application_id":"2","version":"4","name":"ping","description":"Check response ownership","type":1,"default_member_permissions":null},{"id":"5","application_id":"2","version":"6","name":"unmanaged","description":"Preserve me","type":1,"default_member_permissions":null}]"#.utf8)
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            #expect(request.method == "GET")
            #expect(request.url.path == "/api/v10/applications/2/commands")
            return HTTPResponse(status: 200, body: try RequestBody(bytes: list, contentType: "application/json").makeStream())
        }])
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        #expect(await transport.executionCount == 0)
        try await app.run(listener: ScriptedHTTPIngress(incoming: []), context: TransportContext(clock: clock))
        #expect(await transport.executionCount == 0)
        let report = try await app.synchronize(using: client)
        #expect(report.unchangedCount == 1 && report.written.isEmpty)
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        await coordinator.close()
    }
}
