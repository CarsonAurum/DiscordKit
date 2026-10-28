// File: Tests/DiscordCommandDSLTests/ResponseTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordCommands
import DiscordCore
import DiscordDSL
import DiscordInteractions
import DiscordModels
import DiscordTestSupport
import Foundation
import Testing

/// Deterministic response-family checks using virtual monotonic time and local injected sinks.
/// Tests never authenticate, register commands, contact Discord, or claim live deadline qualification.
@Suite(.timeLimit(.minutes(1))) struct ResponseTests {
    /// Wrappers retain exact existing-model payloads, reject unresolved uploads, and redact every formatting path.
    /// Typed contexts preserve immutable invocation snapshots and delivery mode without retaining response authority.
    /// - Throws: Unexpected valid fixture/model construction errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func wrappersAndContexts() throws {
        let recorder = ResponseRecorder(), clock = ManualClock()
        let context = try Self.context(recorder: recorder, clock: clock, mode: .gateway)
        let immediate = try MessageResponse(InteractionMessageCreate(content: .value("private-response-marker"), flags: .value(.ephemeral)))
        #expect(try immediate.message.jsonValue() == .object(["content": .string("private-response-marker"), "flags": .number(JSONNumber(rawValue: "64"))]))
        #expect(throws: DiscordError.self) { try MessageResponse(InteractionMessageCreate()) }
        let upload = try MessageAttachmentRequest(id: .upload(0), filename: "private-file")
        #expect(throws: DiscordError.self) {
            try MessageResponse(InteractionMessageCreate(attachments: .value([upload])))
        }
        #expect(throws: DiscordError.self) {
            try DeferredMessageResponse(InteractionMessageEdit(attachments: .value([upload])))
        }
        let retained = try MessageAttachmentRequest(id: .existing(AttachmentID(rawValue: UInt64.max)))
        let deferred = try DeferredMessageResponse(InteractionMessageEdit(content: .null, embeds: .value([]),
            attachments: .value([retained]), deferredResponse: true))
        #expect(try deferred.edit.jsonValue() == .object(["content": .null, "embeds": .array([]),
            "attachments": .array([.object(["id": .string(String(UInt64.max))])])]))
        #expect(try DeferredMessageResponse(InteractionMessageEdit()).edit.jsonValue() == .object([:]))
        let ordinary = CommandContext(context), afterDefer = DeferredCommandContext(context)
        #expect(ordinary.interaction.id == context.interaction.id)
        #expect(afterDefer.interaction.id == context.interaction.id)
        #expect(ordinary.deliveryMode == .gateway)
        #expect(afterDefer.deliveryMode == .gateway)
        for value in [ordinary as any CustomStringConvertible, afterDefer, immediate, deferred] {
            #expect(value.description.hasSuffix("(redacted)"))
            #expect(String(reflecting: value).hasSuffix("(redacted)"))
            #expect(Mirror(reflecting: value).children.count == 1)
            #expect(!value.description.contains("private"))
        }
    }

    /// Explicit and caller-captured initializers lower all response families to identical registrations without work.
    /// Policy metadata remains deterministic and records fixed deferred visibility separately from registration.
    /// - Throws: Any unexpected schema, lowering or router configuration error fails the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func constructionAndRegistrationParity() async throws {
        let recorder = ResponseRecorder(), source = DefinitionSourceLocation(fileID: "Responses", line: 4, column: 2)
        let immediate = ResponseImmediate { _, _ in await recorder.append("forbidden"); return try Self.message() }
        let deferred = ResponseDeferred(responseVisibility: .ephemeral) { _, _ in await recorder.append("forbidden"); return try Self.edit() }
        let manual = ResponseManual(recorder: recorder)
        let commands = [
            try CommandCompilation.compile(SlashCommand(id: "i", handler: immediate, source: source)),
            try CommandCompilation.compile(SlashCommand(id: "i", handler: immediate)),
            try CommandCompilation.compile(SlashCommand(id: "d", handler: deferred, source: source)),
            try CommandCompilation.compile(SlashCommand(id: "d", handler: deferred)),
            try CommandCompilation.compile(SlashCommand(id: "m", handler: manual, source: source)),
            try CommandCompilation.compile(SlashCommand(id: "m", handler: manual))
        ]
        let direct = try CommandDefinition.slash(name: "reply", description: "Reply to a person") {
            try ApplicationCommandOptionCreate(type: .string, name: "person", description: "Person", required: true)
        }
        for compiled in commands {
            #expect(compiled.definitions[0].request.jsonValue() == direct.request.jsonValue())
            #expect(compiled.routes[0].key == (try .command(name: "reply")))
            _ = try compiled.makeRouter()
        }
        #expect(commands[0].description.declarations[0].declaration.source == source)
        #expect(commands[0].description.declarations[0].declaration.payload != commands[2].description.declarations[0].declaration.payload)
        #expect(commands[2].description.declarations[0].declaration.payload != commands[4].description.declarations[0].declaration.payload)
        #expect(await recorder.events.isEmpty)
        let defaults = ResponsePublicDeferred()
        #expect(defaults.responseVisibility == .public)
    }

    /// Immediate user work precedes one type-4 callback with its exact message, in either receipt mode.
    /// - Parameter mode: Synthetic HTTP or Gateway delivery; no transport is created.
    /// - Throws: Unexpected valid invocation failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [InteractionDeliveryMode.http, .gateway]) func immediate(mode: InteractionDeliveryMode) async throws {
        let recorder = ResponseRecorder(), clock = ManualClock()
        let context = try Self.context(recorder: recorder, clock: clock, mode: mode)
        let handler = ResponseImmediate { input, arguments in
            #expect(input.deliveryMode == mode)
            #expect(input.interaction.id == context.interaction.id)
            await recorder.append("work:\(arguments.person)")
            return try Self.message()
        }
        let compiled = try CommandCompilation.compile(SlashCommand(id: "immediate", handler: handler))
        let router = try compiled.makeRouter()
        #expect(try await router.route(context))
        #expect(await recorder.events == ["work:Ada", "initial:4"])
        #expect(await recorder.callbacks == [try InteractionResponse.message(Self.message().message).jsonValue(interactionType: .applicationCommand)])
        #expect(await context.responder.snapshot() == .acknowledged(.channelMessageWithSource))
        #expect(await router.activeHandlerCount == 0)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Defer is confirmed before any user behavior, then completion uses one original edit and fixes visibility.
    /// Repeated routing cannot re-enter deferred user work after the initial slot has been acknowledged.
    /// - Parameters:
    ///   - ephemeral: Whether to select a private original at acknowledgement time.
    ///   - mode: Synthetic receipt channel normalized through the existing response owner.
    /// - Throws: Any unexpected valid invocation/model failure fails the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true], [InteractionDeliveryMode.http, .gateway])
    func deferred(ephemeral: Bool, mode: InteractionDeliveryMode) async throws {
        let recorder = ResponseRecorder(), clock = ManualClock()
        let context = try Self.context(recorder: recorder, clock: clock, mode: mode)
        let handler = ResponseDeferred(responseVisibility: ephemeral ? .ephemeral : .public) { input, arguments in
            #expect(input.deliveryMode == mode)
            #expect(await context.responder.snapshot() == .acknowledged(.deferredChannelMessageWithSource))
            await recorder.append("work:\(arguments.person)")
            return try Self.edit()
        }
        let router = try CommandCompilation.compile(SlashCommand(id: "deferred", handler: handler)).makeRouter()
        #expect(try await router.route(context))
        #expect(await recorder.events == ["initial:5", "work:Ada", "edit"])
        #expect(await recorder.callbacks == [try InteractionResponse.deferredMessage(ephemeral: ephemeral).jsonValue(interactionType: .applicationCommand)])
        #expect(await recorder.edits == [try Self.edit().edit.jsonValue()])
        await #expect(throws: InteractionLifecycleError.alreadyAcknowledged) { try await router.route(context) }
        #expect(await recorder.events == ["initial:5", "work:Ada", "edit"])
        #expect(clock.pendingSleepCount == 0)
    }

    /// Complete argument validation rejects missing/wrong/unknown leaves before handler behavior or deferral.
    /// - Parameters:
    ///   - deferred: Selects the explicit deferred route rather than immediate message policy.
    ///   - options: Controlled incomplete or invalid submitted option array.
    /// - Throws: Setup errors fail; intended typed diagnostics are asserted inside the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true], ["[]", #"[{"name":"person","type":5,"value":true}]"#,
        #"[{"name":"person","type":3,"value":"Ada"},{"name":"extra","type":3,"value":"x"}]"#])
    func validationBeforeResponse(deferred: Bool, options: String) async throws {
        let recorder = ResponseRecorder(), clock = ManualClock()
        let context = try Self.context(options: options, recorder: recorder, clock: clock)
        let router = try Self.router(deferred: deferred, recorder: recorder)
        await #expect(throws: ArgumentDiagnostic.self) { try await router.route(context) }
        #expect(await recorder.events.isEmpty)
        #expect(await context.responder.snapshot() == .pending)
        #expect(await router.activeHandlerCount == 0)
    }

    /// Handler failures propagate without fallback replies or edits; confirmed deferred state stays acknowledged.
    /// - Parameter deferred: Whether the adapter acknowledges before entering failing user work.
    /// - Throws: Any unexpected fixture error fails the test; the injected failure is asserted exactly.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func handlerFailure(deferred: Bool) async throws {
        let recorder = ResponseRecorder(), clock = ManualClock()
        let context = try Self.context(recorder: recorder, clock: clock)
        let router = try Self.router(deferred: deferred, recorder: recorder, failure: true)
        await #expect(throws: ResponseFailure.handler) { try await router.route(context) }
        #expect(await recorder.events == (deferred ? ["initial:5", "work"] : ["work"]))
        #expect(await context.responder.snapshot() == (deferred ? .acknowledged(.deferredChannelMessageWithSource) : .pending))
        #expect(await recorder.edits.isEmpty)
        #expect(await router.activeHandlerCount == 0)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Explicit no-submission and ambiguous acknowledgement failures both stop deferred user work and never retry.
    /// - Parameter submitted: Whether the sink reports positive no-send evidence or ambiguous submission.
    /// - Throws: Local fixture failures fail the test; exact transport evidence and owner state are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func acknowledgementFailure(submitted: Bool) async throws {
        let recorder = ResponseRecorder(), clock = ManualClock()
        let failure = submitted ? InteractionDeliveryError.indeterminate : .notSubmitted
        let sink = InteractionResponseSink(initial: { _, _ in await recorder.append("initial-failed"); throw failure })
        let context = try Self.context(recorder: recorder, clock: clock, sink: sink)
        let router = try Self.router(deferred: true, recorder: recorder)
        await #expect(throws: failure) { try await router.route(context) }
        #expect(await recorder.events == ["initial-failed"])
        #expect(await context.responder.snapshot() == (submitted ? .indeterminate : .pending))
        #expect(await router.activeHandlerCount == 0)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Cancellation before admission prevents all behavior; a handler cancelling at return cannot transmit its result.
    /// - Parameters:
    ///   - deferred: Immediate or explicit defer policy.
    ///   - before: Cancellation before routing rather than while returning a successfully constructed result.
    /// - Throws: Unexpected setup failure fails; cancellation and exact callback state are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true], [false, true]) func cancellationCheckpoints(deferred: Bool, before: Bool) async throws {
        let recorder = ResponseRecorder(), clock = ManualClock()
        let context = try Self.context(recorder: recorder, clock: clock)
        let router = try Self.router(deferred: deferred, recorder: recorder, cancelAtReturn: !before)
        let task = Task {
            if before { withUnsafeCurrentTask { $0?.cancel() } }
            return try await router.route(context)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await recorder.events == (before ? [] : (deferred ? ["initial:5", "work"] : ["work"])))
        #expect(await context.responder.snapshot() == (!before && deferred ? .acknowledged(.deferredChannelMessageWithSource) : .pending))
        #expect(await router.activeHandlerCount == 0)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Cooperative cancellation during acknowledgement prevents user work and retains indeterminate remote ownership.
    /// Concurrent routing cannot enter another deferred handler while the initial slot is reserved.
    /// - Throws: Setup/barrier failures fail; both the reservation conflict and cancellation are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellationDuringAcknowledgementAndConcurrentOwnership() async throws {
        let entered = TestBarrier(), blocked = TestBarrier(), recorder = ResponseRecorder(), clock = ManualClock()
        let sink = InteractionResponseSink(initial: { _, _ in
            await recorder.append("initial-entered")
            entered.open()
            try await blocked.wait()
        })
        let context = try Self.context(recorder: recorder, clock: clock, sink: sink)
        let router = try Self.router(deferred: true, recorder: recorder)
        let task = Task { try await router.route(context) }
        try await entered.wait()
        #expect(await context.responder.snapshot() == .acknowledging)
        await #expect(throws: InteractionLifecycleError.initialResponseInFlight) { try await router.route(context) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await recorder.events == ["initial-entered"])
        #expect(await context.responder.snapshot() == .indeterminate)
        #expect(await router.activeHandlerCount == 0)
        #expect(blocked.waitingCount == 0)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Cancelling suspended deferred user work joins its task and skips completion while retaining the initial defer.
    /// - Throws: Unexpected local/barrier failures fail the test; cancellation is checked exactly.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellationDuringUserWork() async throws {
        let entered = TestBarrier(), blocked = TestBarrier(), recorder = ResponseRecorder(), clock = ManualClock()
        let context = try Self.context(recorder: recorder, clock: clock)
        let handler = ResponseDeferred { _, _ in
            await recorder.append("work")
            entered.open()
            try await blocked.wait()
            return try Self.edit()
        }
        let router = try CommandCompilation.compile(SlashCommand(id: "deferred", handler: handler)).makeRouter()
        let task = Task { try await router.route(context) }
        try await entered.wait()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await recorder.events == ["initial:5", "work"])
        #expect(await context.responder.snapshot() == .acknowledged(.deferredChannelMessageWithSource))
        #expect(await router.activeHandlerCount == 0)
        #expect(blocked.waitingCount == 0)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Existing response deadlines reject expired immediate submission or deferred completion without transport calls.
    /// - Parameter deferred: Selects three-second initial or fifteen-minute continuation expiry.
    /// - Throws: Setup failures fail; exact lifecycle errors are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func expiry(deferred: Bool) async throws {
        let recorder = ResponseRecorder(), clock = ManualClock()
        let context = try Self.context(recorder: recorder, clock: clock)
        let router: CommandRouter
        if deferred {
            let handler = ResponseDeferred { _, _ in
                await recorder.append("work")
                try clock.advance(by: .seconds(900))
                return try Self.edit()
            }
            router = try CommandCompilation.compile(SlashCommand(id: "deferred", handler: handler)).makeRouter()
        } else {
            let handler = ResponseImmediate { _, _ in
                await recorder.append("work")
                try clock.advance(by: .seconds(3))
                return try Self.message()
            }
            router = try CommandCompilation.compile(SlashCommand(id: "immediate", handler: handler)).makeRouter()
        }
        await #expect(throws: deferred ? InteractionLifecycleError.tokenExpired : .deadlineExceeded) { try await router.route(context) }
        #expect(await recorder.events == (deferred ? ["initial:5", "work"] : ["work"]))
        #expect(await context.responder.snapshot() == .expired)
        #expect(await router.activeHandlerCount == 0)
        #expect(clock.pendingSleepCount == 0)
    }

    /// An ambiguous deferred edit is submitted once and reported as mutation uncertainty without fallback/follow-up.
    /// - Throws: Setup failures fail; existing continuation evidence classification is asserted exactly.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func editFailureEvidence() async throws {
        let recorder = ResponseRecorder(), clock = ManualClock()
        let sink = InteractionResponseSink(initial: { try await recorder.initial($0, timeout: $1) },
            editOriginal: { _, _ in await recorder.append("edit-failed"); throw DiscordError.transport(.disconnected) },
            followup: { _, _ in Issue.record("Deferred route used follow-up"); throw ResponseFailure.handler })
        let context = try Self.context(recorder: recorder, clock: clock, sink: sink)
        let router = try Self.router(deferred: true, recorder: recorder)
        await #expect(throws: DiscordError.unknownMutationOutcome(.connectionLostAfterSubmission)) { try await router.route(context) }
        #expect(await recorder.events == ["initial:5", "work", "edit-failed"])
        #expect(await context.responder.snapshot() == .acknowledged(.deferredChannelMessageWithSource))
        #expect(await router.activeHandlerCount == 0)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Creates one exact response-policy router for deterministic failure and cancellation paths.
    /// - Parameters:
    ///   - deferred: Select explicit pre-work acknowledgement or immediate-message policy.
    ///   - recorder: Isolated test-only event recorder.
    ///   - failure: Throw the sentinel after recording work when true, default false.
    ///   - cancelAtReturn: Cancel the current task before returning a valid result when true, default false.
    /// - Returns: An inert bounded router with no tasks or submissions until explicit invocation.
    /// - Throws: Unexpected local schema/contribution/router validation errors.
    private static func router(deferred: Bool, recorder: ResponseRecorder, failure: Bool = false,
        cancelAtReturn: Bool = false) throws -> CommandRouter {
        if deferred {
            let handler = ResponseDeferred { _, _ in
                await recorder.append("work")
                if failure { throw ResponseFailure.handler }
                if cancelAtReturn { withUnsafeCurrentTask { $0?.cancel() } }
                return try edit()
            }
            return try CommandCompilation.compile(SlashCommand(id: "deferred", handler: handler)).makeRouter()
        }
        let handler = ResponseImmediate { _, _ in
            await recorder.append("work")
            if failure { throw ResponseFailure.handler }
            if cancelAtReturn { withUnsafeCurrentTask { $0?.cancel() } }
            return try message()
        }
        return try CommandCompilation.compile(SlashCommand(id: "immediate", handler: handler)).makeRouter()
    }

    /// Returns one validated private immediate-message fixture without executing response work.
    /// - Returns: Exact existing message body, including explicit ephemeral visibility.
    /// - Throws: Unexpected controlled fixture validation errors.
    private static func message() throws -> MessageResponse {
        try MessageResponse(InteractionMessageCreate(content: .value("Hello"), flags: .value(.ephemeral)))
    }

    /// Returns one presence-aware deferred edit without transmitting or claiming remote completion.
    /// - Returns: Explicit deferred-original content replacement.
    /// - Throws: Unexpected controlled edit validation errors.
    private static func edit() throws -> DeferredMessageResponse {
        try DeferredMessageResponse(InteractionMessageEdit(content: .value("Done"), deferredResponse: true))
    }

    /// Builds trusted-origin synthetic interaction input and a virtual-time response owner with isolated admission.
    /// - Parameters:
    ///   - options: Controlled complete option array, default one required person string.
    ///   - recorder: Records exact callback/edit order from the default sink.
    ///   - clock: Shared monotonic time advanced explicitly by tests.
    ///   - mode: Synthetic receipt mode, default HTTP; Gateway still uses an injected callback sink.
    ///   - sink: Optional controlled failure/cancellation sink; nil records successful JSON-only delivery.
    /// - Returns: Normalized context whose responder begins pending and has no running tasks.
    /// - Throws: Controlled fixture/model, admission or context ownership validation errors.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private static func context(options: String = #"[{"name":"person","type":3,"value":"Ada"}]"#,
        recorder: ResponseRecorder, clock: ManualClock, mode: InteractionDeliveryMode = .http,
        sink: InteractionResponseSink? = nil) throws -> InteractionContext {
        let interaction = try Interaction(data: JSONValue.object([
            "id": .string(String(UInt64.max)), "application_id": .string("9"), "type": .number(JSONNumber(rawValue: "2")),
            "token": .string("private-token-marker"), "version": .number(JSONNumber(rawValue: "1")),
            "app_permissions": .string("0"), "entitlements": .array([]), "authorizing_integration_owners": .object([:]),
            "attachment_size_limit": .number(JSONNumber(rawValue: "10485760")),
            "data": .object(["id": .string("8"), "name": .string("reply"), "type": .number(JSONNumber(rawValue: "1")),
                "options": try JSONValue.parse(Data(options.utf8))])
        ]).serialized())
        let responder = InteractionResponder(interaction: interaction, deliveryMode: mode, clock: InteractionClock(clock),
            sink: sink ?? InteractionResponseSink(initial: { try await recorder.initial($0, timeout: $1) },
                editOriginal: { try await recorder.edit($0, timeout: $1) },
                followup: { _, _ in Issue.record("Typed policy used a follow-up"); throw ResponseFailure.handler }),
            admission: try InteractionAcknowledgementAdmission())
        return try InteractionContext(interaction: interaction, deliveryMode: mode, responder: responder)
    }
}

private enum ResponseFailure: Error, Equatable { case handler }

/// Fresh invocation-local arguments shared by all three response-family fixtures.
private struct ResponseArguments: CommandArguments {
    let person: String
    /// Captures a single finite required leaf without decoding submitted values or running handler work.
    static var schema: CommandArgumentSchema<Self> {
        /// Returns an inert schema whose aggregate constructor creates one new value per invocation.
        /// - Throws: Unexpected descriptor/schema validation errors.
        get throws {
            let person = try ArgumentOption<String>(name: "person", description: "Person")
            return try CommandArgumentSchema(options: [person.erased]) { try Self(person: $0.value(for: person)) }
        }
    }
}

/// Explicit immediate behavior injection with no execution in construction or metadata access.
private struct ResponseImmediate: SlashCommandHandler {
    typealias Arguments = ResponseArguments
    let work: @Sendable (CommandContext, ResponseArguments) async throws -> MessageResponse
    /// Returns deterministic registration shared across direct and policy-based lowering.
    var command: SlashCommandMetadata { .init(name: "reply", description: "Reply to a person") }
    /// Forwards one admitted invocation to the test operation in the caller's task.
    /// - Parameters:
    ///   - context: Typed snapshot without exposed response ownership.
    ///   - arguments: Fresh validated person string.
    /// - Returns: Injected immediate message.
    /// - Throws: Injected application failure or cancellation unchanged.
    func execute(_ context: CommandContext, arguments: ResponseArguments) async throws -> MessageResponse {
        try await work(context, arguments)
    }
}

/// Explicit deferred behavior injection whose visibility remains immutable for the compiled route.
private struct ResponseDeferred: DeferredSlashCommandHandler {
    typealias Arguments = ResponseArguments
    var responseVisibility: CommandResponseVisibility = .public
    let work: @Sendable (DeferredCommandContext, ResponseArguments) async throws -> DeferredMessageResponse
    /// Returns deterministic root registration without acknowledging or executing injected work.
    var command: SlashCommandMetadata { .init(name: "reply", description: "Reply to a person") }
    /// Runs injected work after the adapter has confirmed deferred ownership.
    /// - Parameters:
    ///   - context: Snapshot whose normal route entry follows successful acknowledgement.
    ///   - arguments: Fresh validated person string.
    /// - Returns: Original-edit result for exactly one adapter submission.
    /// - Throws: Injected application failure or cancellation unchanged.
    func execute(_ context: DeferredCommandContext, arguments: ResponseArguments) async throws -> DeferredMessageResponse {
        try await work(context, arguments)
    }
}

/// Exercises the public default visibility accessor without providing an override.
private struct ResponsePublicDeferred: DeferredSlashCommandHandler {
    typealias Arguments = ResponseArguments
    /// Supplies the same finite registration as the other fixture families.
    var command: SlashCommandMetadata { .init(name: "reply", description: "Reply to a person") }
    /// Returns a validated edit; tests only inspect policy and never invoke this operation.
    /// - Parameters:
    ///   - context: Unused typed snapshot without response authority.
    ///   - arguments: Unused validated arguments.
    /// - Returns: Controlled JSON-only deferred-original edit.
    /// - Throws: Unexpected controlled edit validation errors.
    func execute(_ context: DeferredCommandContext, arguments: ResponseArguments) async throws -> DeferredMessageResponse {
        try DeferredMessageResponse(InteractionMessageEdit(content: .value("Done")))
    }
}

/// Manual response fixture confirms compatibility with the original explicit ownership protocol.
private struct ResponseManual: ManualSlashCommandHandler {
    typealias Arguments = ResponseArguments
    let recorder: ResponseRecorder
    /// Returns finite root registration with no acknowledgement or user work.
    var command: SlashCommandMetadata { .init(name: "reply", description: "Reply to a person") }
    /// Records work only if invoked; inert construction tests deliberately never invoke it.
    /// - Parameters:
    ///   - context: Original low-level response authority, deliberately untouched by this fixture.
    ///   - arguments: Fresh validated person string, unused in construction tests.
    func execute(_ context: InteractionContext, arguments: ResponseArguments) async throws {
        await recorder.append("manual")
    }
}

/// Serializes observable test events and exact wire bodies independently of handler task scheduling.
private actor ResponseRecorder {
    var events: [String] = []
    var callbacks: [JSONValue] = []
    var edits: [JSONValue] = []

    /// Records one nonsecret synthetic event in actor admission order.
    /// - Parameter event: Fixed test-only marker; never credentials or arbitrary production content.
    func append(_ event: String) { events.append(event) }

    /// Records one validated initial response and asserts the adapter's bounded remaining timeout.
    /// - Parameters:
    ///   - response: Existing callback from the exact response owner.
    ///   - timeout: Positive receipt-relative allowance of at most three seconds.
    /// - Throws: Unexpected fixture callback JSON validation failures.
    func initial(_ response: InteractionResponse, timeout: Duration) throws {
        #expect(timeout > .zero && timeout <= .seconds(3))
        events.append("initial:\(response.type.rawValue)")
        callbacks.append(try response.jsonValue(interactionType: .applicationCommand))
    }

    /// Records one original edit and returns a complete synthetic message without network I/O.
    /// - Parameters:
    ///   - edit: Validated JSON-only original update from the deferred response adapter.
    ///   - timeout: Positive allowance of at most fifteen minutes in the same virtual clock domain.
    /// - Returns: Controlled required-fields message proving the existing continuation completed.
    /// - Throws: Unexpected controlled JSON/model validation errors.
    func edit(_ edit: InteractionMessageEdit, timeout: Duration) throws -> Message {
        #expect(timeout > .zero && timeout <= .seconds(900))
        events.append("edit")
        edits.append(try edit.jsonValue())
        return try Message(data: Data(#"{"id":"1","channel_id":"2","author":{"id":"3","username":"fixture","discriminator":"0","avatar":null},"content":"Done","timestamp":"2026-10-18T00:00:00Z","edited_timestamp":null,"tts":false,"mention_everyone":false,"mentions":[],"mention_roles":[],"attachments":[],"embeds":[],"pinned":false,"type":0}"#.utf8))
    }
}
