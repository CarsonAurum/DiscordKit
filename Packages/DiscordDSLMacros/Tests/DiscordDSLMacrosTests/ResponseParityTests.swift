import DiscordCommandDSL
import DiscordCore
import DiscordDSL
import DiscordDSLMacros
import DiscordInteractions
import DiscordModels
import Foundation
import Testing

/// Real compiled macro handlers retain the same typed response behavior as handwritten conformances.
@Suite(.timeLimit(.minutes(1))) struct ResponseParityTests {
    /// Generated immediate factories match handwritten definitions and send one initial after user work.
    /// - Parameter gateway: Chooses a trusted Gateway-normalized envelope or a synthetic HTTP envelope.
    /// - Throws: Unexpected schema, parser, router or response-owner failures fail the test.
    @Test(arguments: [false, true]) func immediateResponseParity(gateway: Bool) async throws {
        let generatedTrace = ResponseParityTrace()
        let directTrace = ResponseParityTrace()
        let source = DefinitionSourceLocation(fileID: "Responses.swift", line: 1, column: 1)
        let generated = try CommandCompilation.compile(GeneratedImmediate(trace: generatedTrace)
            .contribution(id: "response", source: source))
        let direct = try CommandCompilation.compile(DiscordCommandDSL.SlashCommand(id: "response",
            handler: DirectImmediate(trace: directTrace), source: source))
        let events = try await compare(generated: generated, direct: direct, generatedTrace: generatedTrace,
            directTrace: directTrace, gateway: gateway, expectedState: .acknowledged(.channelMessageWithSource))
        #expect(events == [.handler("Ada"), .initial(try InteractionResponse.message(
            InteractionMessageCreate(content: .value("Hello Ada"))).jsonValue())])
    }

    /// Generated deferred factories acknowledge before work, then perform exactly one matching original edit.
    /// - Parameters:
    ///   - gateway: Selects a trusted Gateway-normalized or synthetic HTTP envelope without creating a connection.
    ///   - ephemeral: Explicit visibility captured by both independent handler implementations.
    /// - Throws: Unexpected local validation, routing or response state-machine errors fail the test.
    @Test(arguments: [false, true], [false, true])
    func deferredResponseParity(gateway: Bool, ephemeral: Bool) async throws {
        let generatedTrace = ResponseParityTrace()
        let directTrace = ResponseParityTrace()
        let source = DefinitionSourceLocation(fileID: "Responses.swift", line: 1, column: 1)
        let visibility: CommandResponseVisibility = ephemeral ? .ephemeral : .public
        let generated = try CommandCompilation.compile(GeneratedDeferred(trace: generatedTrace, responseVisibility: visibility)
            .contribution(id: "response", source: source))
        let direct = try CommandCompilation.compile(DiscordCommandDSL.SlashCommand(id: "response",
            handler: DirectDeferred(trace: directTrace, responseVisibility: visibility), source: source))
        let events = try await compare(generated: generated, direct: direct, generatedTrace: generatedTrace,
            directTrace: directTrace, gateway: gateway, expectedState: .acknowledged(.deferredChannelMessageWithSource))
        #expect(events == [.initial(try InteractionResponse.deferredMessage(ephemeral: ephemeral).jsonValue()),
            .handler("Ada"), .edit(try InteractionMessageEdit(content: .value("Hello Ada")).jsonValue())])
    }

    /// Compares inert construction, complete registrations, routes, response events and released handler permits.
    /// - Parameters:
    ///   - generated: Real compiler-generated contribution lowered into a finite command plan.
    ///   - direct: Independent handwritten conformance lowered through the same public runtime constructor.
    ///   - generatedTrace: Local deterministic event recorder for the generated handler and response sink.
    ///   - directTrace: Independent recorder for the direct handler and its separate responder.
    ///   - gateway: Chooses the trusted input delivery mode for both independent invocations.
    ///   - expectedState: Confirmed callback family retained by each exact interaction response owner.
    /// - Returns: Generated event trace after proving equality with the handwritten route's events.
    /// - Throws: Unexpected validation, local decoding, routing or response sink failures.
    private func compare(generated: CompiledCommands, direct: CompiledCommands,
                         generatedTrace: ResponseParityTrace, directTrace: ResponseParityTrace,
                         gateway: Bool, expectedState: InteractionResponseState) async throws -> [ResponseParityEvent] {
        #expect(generated.definitions[0].request.jsonValue() == direct.definitions[0].request.jsonValue())
        #expect(generated.description == direct.description)
        #expect(generated.routes[0].key == direct.routes[0].key)
        let generatedRouter = try generated.makeRouter()
        let directRouter = try direct.makeRouter()
        #expect(await generatedTrace.events.isEmpty)
        #expect(await directTrace.events.isEmpty)
        let mode: InteractionDeliveryMode = gateway ? .gateway : .http
        let generatedContext = try context(trace: generatedTrace, mode: mode)
        let directContext = try context(trace: directTrace, mode: mode)
        #expect(try await generatedRouter.route(generatedContext))
        #expect(try await directRouter.route(directContext))
        #expect(await generatedContext.responder.snapshot() == expectedState)
        #expect(await directContext.responder.snapshot() == expectedState)
        #expect(await generatedRouter.activeHandlerCount == 0)
        #expect(await directRouter.activeHandlerCount == 0)
        let generatedEvents = await generatedTrace.events
        #expect(await generatedEvents == directTrace.events)
        return generatedEvents
    }

    /// Creates one pending response owner and immutable trusted input over a frozen monotonic clock.
    /// - Parameters:
    ///   - trace: Actor receiving callback, user-work and original-edit observations in exact admission order.
    ///   - mode: Trusted local input envelope; no transport or credentials are created.
    /// - Returns: One inert context with independent initial acknowledgement admission.
    /// - Throws: Synthetic model or acknowledgement-configuration validation errors.
    private func context(trace: ResponseParityTrace, mode: InteractionDeliveryMode) throws -> InteractionContext {
        let interaction = try Interaction(data: Data(#"{"id":"18446744073709551615","application_id":"9","type":2,"token":"synthetic","version":1,"app_permissions":"0","entitlements":[],"authorizing_integration_owners":{},"attachment_size_limit":10485760,"data":{"id":"8","name":"response","type":1,"options":[{"name":"person","type":3,"value":"Ada"}]}}"#.utf8))
        let sink = InteractionResponseSink(initial: { response, _ in
            await trace.record(.initial(try response.jsonValue()))
        }, editOriginal: { edit, _ in
            await trace.record(.edit(try edit.jsonValue()))
            return try Message(data: Data(#"{"id":"18446744073709551615","channel_id":"4","author":{"id":"5","username":"user","discriminator":"0","avatar":null},"content":"response","timestamp":"2026-10-18T12:00:00Z","edited_timestamp":null,"tts":false,"mention_everyone":false,"mentions":[],"mention_roles":[],"attachments":[],"embeds":[],"pinned":false,"type":20}"#.utf8))
        })
        let responder = InteractionResponder(interaction: interaction, deliveryMode: mode,
            clock: InteractionClock(ResponseParityClock()), sink: sink,
            admission: try InteractionAcknowledgementAdmission())
        return try InteractionContext(interaction: interaction, deliveryMode: mode, responder: responder)
    }
}

/// Compiler-generated argument decoding shared by the response-family execution parity fixtures.
@CommandArguments
private struct ResponseArguments {
    @Option(description: "Person") let person: String
}

/// Explicit immediate inheritance prevents the macro from generating manual responder conformance.
@SlashCommand("response", description: "Response parity")
private struct GeneratedImmediate: SlashCommandHandler {
    typealias Arguments = ResponseArguments
    let trace: ResponseParityTrace

    /// Records explicit work and returns the sole immediate result without raw responder access.
    /// - Parameters:
    ///   - context: Immutable typed invocation snapshot; no acknowledgement operations are exposed.
    ///   - arguments: Fresh compiler-generated values for this invocation.
    /// - Returns: One complete validated JSON-only message.
    /// - Throws: Existing message validation failures; actor recording suspends in the caller's task.
    func execute(_ context: CommandContext, arguments: Arguments) async throws -> MessageResponse {
        await trace.record(.handler(arguments.person))
        return try MessageResponse(InteractionMessageCreate(content: .value("Hello \(arguments.person)")))
    }
}

/// Independent handwritten immediate conformance with the same registration and response contract.
private struct DirectImmediate: SlashCommandHandler {
    typealias Arguments = ResponseArguments
    let trace: ResponseParityTrace
    /// Supplies the same inert metadata as the compiler-generated witness.
    var command: SlashCommandMetadata { .init(name: "response", description: "Response parity") }

    /// Records independent explicit work and returns an equivalent complete immediate message.
    /// - Parameters:
    ///   - context: Typed normalized invocation without response authority.
    ///   - arguments: Invocation-local compiler-checked arguments.
    /// - Returns: One validated JSON-only message.
    /// - Throws: Existing message validation errors; no fallback or acknowledgement occurs here.
    func execute(_ context: CommandContext, arguments: Arguments) async throws -> MessageResponse {
        await trace.record(.handler(arguments.person))
        return try MessageResponse(InteractionMessageCreate(content: .value("Hello \(arguments.person)")))
    }
}

/// Explicit deferred inheritance keeps defer-before-work and original-edit policy in the runtime adapter.
@SlashCommand("response", description: "Response parity")
private struct GeneratedDeferred: DeferredSlashCommandHandler {
    typealias Arguments = ResponseArguments
    let trace: ResponseParityTrace
    let responseVisibility: CommandResponseVisibility

    /// Records work after the confirmed defer and returns a single original completion.
    /// - Parameters:
    ///   - context: Typed snapshot supplied after the existing responder confirms its loading callback.
    ///   - arguments: Complete arguments decoded before acknowledgement.
    /// - Returns: One validated partial original edit, preserving immutable defer visibility.
    /// - Throws: Existing local edit validation errors; no follow-up or second initial is representable.
    func execute(_ context: DeferredCommandContext, arguments: Arguments) async throws -> DeferredMessageResponse {
        await trace.record(.handler(arguments.person))
        return try DeferredMessageResponse(InteractionMessageEdit(content: .value("Hello \(arguments.person)")))
    }
}

/// Handwritten deferred implementation used to compare the compiler-authored factory and route behavior.
private struct DirectDeferred: DeferredSlashCommandHandler {
    typealias Arguments = ResponseArguments
    let trace: ResponseParityTrace
    let responseVisibility: CommandResponseVisibility
    /// Returns equivalent registration metadata without invoking work or response mechanics.
    var command: SlashCommandMetadata { .init(name: "response", description: "Response parity") }

    /// Observes deferred user work and produces the same edit as the compiler-authored counterpart.
    /// - Parameters:
    ///   - context: Immutable deferred snapshot with no low-level responder.
    ///   - arguments: Complete invocation-local arguments decoded before the runtime acknowledges.
    /// - Returns: One validated partial edit of the deferred original.
    /// - Throws: Existing edit validation errors; actor recording suspends in the owning router task.
    func execute(_ context: DeferredCommandContext, arguments: Arguments) async throws -> DeferredMessageResponse {
        await trace.record(.handler(arguments.person))
        return try DeferredMessageResponse(InteractionMessageEdit(content: .value("Hello \(arguments.person)")))
    }
}

/// Exact bounded synthetic observations preserve payload equality as well as response ordering.
private enum ResponseParityEvent: Sendable, Equatable {
    case initial(JSONValue)
    case handler(String)
    case edit(JSONValue)
}

/// Actor-owned response events avoid sleeps, mutable shared state or unchecked synchronization.
private actor ResponseParityTrace {
    var events: [ResponseParityEvent] = []

    /// Appends one local event in actor admission order.
    /// - Parameter event: Synthetic payload or invocation text retained solely for deterministic assertions.
    func record(_ event: ResponseParityEvent) { events.append(event) }
}

/// Frozen monotonic time allows response-owner deadline tasks to be cancelled without real timer races.
private struct ResponseParityClock: Clock {
    let now = ContinuousClock.now
    /// Reports nanosecond precision for the immutable instant without scheduling or advancing time.
    var minimumResolution: Duration { .nanoseconds(1) }

    /// Suspends until cancellation because frozen time never reaches a future deadline.
    /// - Parameters:
    ///   - deadline: Absolute deadline in this clock's immutable instant domain.
    ///   - tolerance: Optional scheduling tolerance, ignored because the clock does not advance.
    /// - Throws: `CancellationError` when the owning response race finishes and cancels its timer child.
    ///   No wall-clock timer, detached task or continuation storage is created.
    func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {
        if deadline <= now { return }
        let stream = AsyncStream<Void> { _ in }
        for await _ in stream {}
        try Task.checkCancellation()
    }
}
