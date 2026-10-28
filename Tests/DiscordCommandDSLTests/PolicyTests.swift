// File: Tests/DiscordCommandDSLTests/PolicyTests.swift
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
import Synchronization
import Testing

/// Policy execution evidence uses trusted synthetic contexts, virtual clocks and bounded local barriers.
/// No test registers commands, authenticates, connects to Discord or claims deployment capacity.
@Suite(.timeLimit(.minutes(1))) struct CommandPolicyTests {
    /// Guild observations accept only a concrete ID; absent/null observations never infer authorization.
    /// - Parameter variant: Missing, explicit null or a full-width concrete guild snowflake.
    /// - Throws: Unexpected controlled fixture or policy-validation errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [0, 1, 2]) func guildObservations(variant: Int) async throws {
        let guild: JSONValue? = variant == 0 ? nil : (variant == 1 ? .null : .string(String(UInt64.max)))
        let extra = guild.map { ["guild_id": $0] } ?? [:]
        if variant == 1 {
            #expect(throws: DiscordError.self) { try Self.context(trace: PolicyTrace(), extra: extra) }
            return
        }
        let context = try Self.context(trace: PolicyTrace(), extra: extra)
        #expect(try await CommandPolicy.isGuild().evaluate(CommandContext(context), limits: PolicyLimits()) == (variant == 2))
    }

    /// Context authorization requires the exact known wire value and rejects missing/null/future values.
    /// A concrete guild ID deliberately cannot fill in missing context information.
    /// - Parameter observed: Negative fixture sentinels encode missing/null; other values are wire integers.
    /// - Throws: Unexpected controlled fixture or policy-validation errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [-2, -1, 0, 1, 2, 999]) func contextObservations(observed: Int) async throws {
        var extra: [String: JSONValue] = ["guild_id": .string("1")]
        if observed == -1 { extra["context"] = .null }
        if observed >= 0 { extra["context"] = .number(try JSONNumber(rawValue: String(observed))) }
        if observed == -1 {
            #expect(throws: DiscordError.self) { try Self.context(trace: PolicyTrace(), extra: extra) }
            return
        }
        let context = CommandContext(try Self.context(trace: PolicyTrace(), extra: extra))
        for expected in InteractionContextType.allCases {
            #expect(try await CommandPolicy.context(expected).evaluate(context, limits: PolicyLimits()) == (observed == expected.rawValue))
        }
    }

    /// Injected current authorization runs once per explicit evaluation and preserves false/error decisions.
    /// - Parameter variant: Allow, deny or throw an application-owned authorization failure.
    /// - Throws: Unexpected fixture errors fail; injected errors are asserted explicitly.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [0, 1, 2]) func injectedAuthorization(variant: Int) async throws {
        let trace = PolicyTrace(), context = CommandContext(try Self.context(trace: PolicyTrace()))
        let policy = CommandPolicy.authorized { observed in
            #expect(observed.interaction.id.rawValue == UInt64.max)
            trace.append("authorize")
            if variant == 2 { throw PolicyFailure.authorization }
            return variant == 0
        }
        try policy.validate(limits: PolicyLimits())
        #expect(trace.events.isEmpty)
        if variant == 2 {
            await #expect(throws: PolicyFailure.authorization) { try await policy.evaluate(context, limits: PolicyLimits()) }
        } else {
            #expect(try await policy.evaluate(context, limits: PolicyLimits()) == (variant == 0))
        }
        #expect(trace.events == ["authorize"])
    }

    /// Compilation, layering and router construction execute no injected behavior and preserve registrations exactly.
    /// - Throws: Unexpected authoring, compilation or router-configuration failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func inertConstructionAndRegistrationParity() async throws {
        let trace = PolicyTrace(), authority = try CommandConcurrencyLimit(maximumConcurrent: 1)
        let policies = try CommandPolicies(limits: PolicyLimits(), requiring: CommandPolicy.authorized { _ in
            trace.append("predicate"); return true
        }, middleware: InvocationMiddleware { input, next in trace.append("middleware"); try await next(input) },
            concurrency: authority, onRejection: { _ in trace.append("reject"); return .message(try Self.message()) },
            mapError: { _, _ in trace.append("map"); return PolicyFailure.mapped })
        let original = try Self.catalog(trace: trace)
        let wrapped = try original.applying(policies)
        _ = try wrapped.makeRouter()
        #expect(wrapped.description == original.description)
        #expect(wrapped.routes.map(\.key) == original.routes.map(\.key))
        #expect(wrapped.definitions.map { $0.request.jsonValue() } == original.definitions.map { $0.request.jsonValue() })
        #expect(await authority.activeCount == 0)
        #expect(trace.events.isEmpty)
    }

    /// Successful admission encloses the existing immediate/deferred adapter and unwinds left-outer middleware last.
    /// - Parameter deferred: Selects explicit defer-before-work and edit-original ownership.
    /// - Throws: Unexpected fixture/lowering/routing errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func admittedOrder(deferred: Bool) async throws {
        let trace = PolicyTrace()
        let authority = PolicyAuthority(trace: trace)
        let outer = Self.middleware("outer", trace: trace), inner = Self.middleware("inner", trace: trace)
        let policies = try CommandPolicies(limits: PolicyLimits(), requiring: CommandPolicy.authorized { _ in
            trace.append("predicate"); return true
        }, middleware: outer >>> inner, concurrency: authority)
        let router = try Self.catalog(trace: trace, deferred: deferred).applying(policies).makeRouter()
        let context = try Self.context(trace: trace)
        #expect(try await router.route(context))
        #expect(trace.events == ["predicate", "admit", "outer:enter", "inner:enter"] +
            (deferred ? ["initial:5", "handler", "edit"] : ["handler", "initial:4"]) +
            ["inner:exit", "outer:exit", "release"])
        #expect(await authority.activeCount == 0)
        #expect(await router.activeHandlerCount == 0)
    }

    /// False predicates never enter admission/middleware or defer; only explicit rejection may send one message.
    /// - Parameters:
    ///   - deferred: Selects a handler that would otherwise acknowledge before work.
    ///   - reply: Enables the explicit ephemeral rejection callback rather than propagating denial.
    /// - Throws: Unexpected fixture errors fail; denial and responder ownership are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true], [false, true]) func rejectionOwnership(deferred: Bool, reply: Bool) async throws {
        let trace = PolicyTrace(), authority = PolicyAuthority(trace: trace)
        let rejection: (@Sendable (CommandContext) throws -> CommandRejectionResponse)?
        if reply {
            rejection = { _ in trace.append("reject"); return .message(try Self.message()) }
        } else { rejection = nil }
        let policies = try CommandPolicies(limits: PolicyLimits(), requiring: CommandPolicy.authorized { _ in
            trace.append("predicate"); return false
        }, middleware: Self.middleware("forbidden", trace: trace), concurrency: authority, onRejection: rejection)
        let router = try Self.catalog(trace: trace, deferred: deferred).applying(policies).makeRouter()
        let context = try Self.context(trace: trace)
        if reply { #expect(try await router.route(context)) }
        else { await #expect(throws: CommandPolicyError.denied) { try await router.route(context) } }
        #expect(trace.events == (reply ? ["predicate", "reject", "initial:4"] : ["predicate"]))
        #expect(await context.responder.snapshot() == (reply ? .acknowledged(.channelMessageWithSource) : .pending))
        #expect(await authority.activeCount == 0)
    }

    /// Autocomplete denial accepts only empty suggestions, and message commands reject suggestions-only callbacks.
    /// - Parameters:
    ///   - autocomplete: Selects focused autocomplete rather than a slash-message interaction.
    ///   - legal: Chooses the matching callback family rather than an illegal explicit rejection.
    /// - Throws: Unexpected fixture errors fail; illegal callbacks must leave initial ownership pending.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true], [false, true]) func rejectionResponseFamilies(autocomplete: Bool, legal: Bool) async throws {
        let trace = PolicyTrace()
        let policies = try CommandPolicies(limits: PolicyLimits(), requiring: CommandPolicy.authorized { _ in false },
            onRejection: { _ in
                (autocomplete == legal) ? .emptyAutocomplete : .message(try Self.message())
            })
        let catalog = autocomplete ? try Self.autocompleteCatalog(trace: trace) : try Self.catalog(trace: trace)
        let options = autocomplete ? #"[{"name":"person","type":3,"value":"A","focused":true}]"# : Self.validOptions
        let context = try Self.context(trace: trace, kind: autocomplete ? 4 : 2, options: options)
        let router = try catalog.applying(policies).makeRouter()
        if legal {
            #expect(try await router.route(context))
            #expect(trace.events == [autocomplete ? "initial:8" : "initial:4"])
            if autocomplete { #expect(trace.callbacks == [try JSONValue.parse(Data(#"{"type":8,"data":{"choices":[]}}"#.utf8))]) }
        } else {
            await #expect(throws: (any Error).self) { try await router.route(context) }
            #expect(trace.events.isEmpty)
            #expect(await context.responder.snapshot() == .pending)
        }
    }

    /// Complete typed admission runs before predicate, admission, middleware, rejection and error translation.
    /// - Parameters:
    ///   - deferred: Selects immediate or explicit-defer slash adapters.
    ///   - options: Missing, mistyped or unknown submitted argument leaves.
    /// - Throws: Unexpected fixture errors fail; argument diagnostics and exact absence of effects are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true], ["[]", #"[{"name":"person","type":4,"value":2}]"#,
        #"[{"name":"unexpected","type":3,"value":"A"}]"#])
    func malformedBeforePolicies(deferred: Bool, options: String) async throws {
        let trace = PolicyTrace()
        let policies = try CommandPolicies(limits: PolicyLimits(), requiring: CommandPolicy.authorized { _ in
            trace.append("predicate"); return false
        }, middleware: Self.middleware("middleware", trace: trace), concurrency: PolicyAuthority(trace: trace),
            onRejection: { _ in trace.append("reject"); return .message(try Self.message()) },
            mapError: { _, _ in trace.append("map"); return PolicyFailure.mapped })
        let router = try Self.catalog(trace: trace, deferred: deferred).applying(policies).makeRouter()
        let context = try Self.context(trace: trace, options: options)
        await #expect(throws: ArgumentDiagnostic.self) { try await router.route(context) }
        #expect(trace.events.isEmpty)
        #expect(await context.responder.snapshot() == .pending)
        #expect(await router.activeHandlerCount == 0)
    }

    /// Duplicate option names prevent exact route admission and never evaluate policies or manufacture a response.
    /// - Throws: Unexpected controlled fixture/authoring errors fail; unrouteable input remains untouched.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func duplicateInputCannotEnterPolicy() async throws {
        let trace = PolicyTrace()
        let policies = try CommandPolicies(limits: PolicyLimits(), requiring: CommandPolicy.authorized { _ in
            trace.append("forbidden"); return true
        }, mapError: { _, _ in trace.append("forbidden-map"); return PolicyFailure.mapped })
        let context = try Self.context(trace: trace,
            options: #"[{"name":"person","type":3,"value":"A"},{"name":"person","type":3,"value":"B"}]"#)
        let router = try Self.catalog(trace: trace).applying(policies).makeRouter()
        #expect(try await router.route(context) == false)
        #expect(trace.events.isEmpty)
        #expect(await context.responder.snapshot() == .pending)
    }

    /// Cancellation before routing prevents predicates; cancellation after admission unwinds middleware and authority.
    /// Error translation and explicit rejection never turn cancellation into a callback or alternate error.
    /// - Parameters:
    ///   - deferred: Selects whether admission previously completed a defer callback.
    ///   - before: Cancels the task before routing rather than during suspended handler work.
    /// - Throws: Unexpected fixture/barrier errors fail; cancellation and release are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true], [false, true]) func cancellationCleanup(deferred: Bool, before: Bool) async throws {
        let trace = PolicyTrace(), entered = TestBarrier(), gate = TestBarrier()
        let authority = try CommandConcurrencyLimit(maximumConcurrent: 1)
        let policies = try CommandPolicies(limits: PolicyLimits(), requiring: CommandPolicy.authorized { _ in
            trace.append("predicate"); return true
        }, middleware: Self.middleware("middleware", trace: trace), concurrency: authority,
            mapError: { _, _ in trace.append("map"); return PolicyFailure.mapped })
        let catalog = try Self.catalog(trace: trace, deferred: deferred, work: {
            trace.append("handler"); entered.open(); try await gate.wait()
        })
        let router = try catalog.applying(policies).makeRouter(), context = try Self.context(trace: trace)
        let task = Task {
            if before { withUnsafeCurrentTask { $0?.cancel() } }
            return try await router.route(context)
        }
        if !before {
            try await entered.wait()
            #expect(await authority.activeCount == 1)
            task.cancel()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(trace.events == (before ? [] : ["predicate", "middleware:enter"] +
            (deferred ? ["initial:5", "handler"] : ["handler"]) + ["middleware:exit"]))
        #expect(await authority.activeCount == 0)
        #expect(await router.activeHandlerCount == 0)
        #expect(gate.waitingCount == 0)
        #expect(await context.responder.snapshot() == (!before && deferred ? .acknowledged(.deferredChannelMessageWithSource) : .pending))
    }

    /// Invalid capacities fail construction; success/error/pre-cancellation leave zero admitted operations.
    /// - Throws: Unexpected valid authority errors fail; injected operation errors are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func concurrencyAuthorityBoundaries() async throws {
        for maximum in [Int.min, -1, 0] {
            #expect(throws: CommandPolicyError.invalidCapacity) { try CommandConcurrencyLimit(maximumConcurrent: maximum) }
        }
        let authority = try CommandConcurrencyLimit(maximumConcurrent: 1), trace = PolicyTrace()
        #expect(await authority.maximumConcurrent == 1)
        #expect(try await authority.withPermit { trace.append("success"); return 42 } == 42)
        #expect(await authority.activeCount == 0)
        await #expect(throws: PolicyFailure.handler) {
            try await authority.withPermit { trace.append("failure"); throw PolicyFailure.handler }
        }
        #expect(await authority.activeCount == 0)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await authority.withPermit { trace.append("forbidden"); return 1 }
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(await authority.activeCount == 0)
        #expect(trace.events == ["success", "failure"])
    }

    /// Shared admission fails fast while a suspended operation owns its slot and releases only when it exits.
    /// - Parameter cancel: Chooses cancellation cleanup rather than normal completion of the first operation.
    /// - Throws: Unexpected barrier/authority errors fail; exact overload and cancellation are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func concurrencyOverloadAndRelease(cancel: Bool) async throws {
        let authority = try CommandConcurrencyLimit(maximumConcurrent: 1), entered = TestBarrier(), gate = TestBarrier()
        let trace = PolicyTrace()
        let first = Task {
            try await authority.withPermit { entered.open(); try await gate.wait(); return 7 }
        }
        try await entered.wait()
        #expect(await authority.activeCount == 1)
        await #expect(throws: CommandPolicyError.capacityExceeded) {
            try await authority.withPermit { trace.append("forbidden"); return 0 }
        }
        if cancel {
            first.cancel()
            await #expect(throws: CancellationError.self) { try await first.value }
        } else {
            gate.open()
            #expect(try await first.value == 7)
        }
        #expect(await authority.activeCount == 0)
        #expect(try await authority.withPermit { 9 } == 9)
        #expect(trace.events.isEmpty)
        #expect(gate.waitingCount == 0)
    }

    /// Error mapping runs after both middleware and admission cleanup without undoing defer or retrying work.
    /// - Parameter deferred: Selects whether the original failure follows a successfully submitted defer.
    /// - Throws: Unexpected authoring/context errors fail; the mapped failure and retained side effects are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func errorMappingAfterPartialEffects(deferred: Bool) async throws {
        let trace = PolicyTrace(), authority = PolicyAuthority(trace: trace)
        let policies = try CommandPolicies(limits: PolicyLimits(), middleware: Self.middleware("middleware", trace: trace),
            concurrency: authority, onRejection: { _ in trace.append("forbidden-reject"); return .message(try Self.message()) },
            mapError: { error, snapshot in
                #expect(error as? PolicyFailure == .handler)
                #expect(snapshot.interaction.id.rawValue == UInt64.max)
                trace.append("map"); return PolicyFailure.mapped
            })
        let catalog = try Self.catalog(trace: trace, deferred: deferred, work: {
            trace.append("side-effect"); throw PolicyFailure.handler
        })
        let context = try Self.context(trace: trace), router = try catalog.applying(policies).makeRouter()
        await #expect(throws: PolicyFailure.mapped) { try await router.route(context) }
        #expect(trace.events == ["admit", "middleware:enter"] + (deferred ? ["initial:5"] : []) + ["side-effect", "middleware:exit", "release", "map"])
        #expect(await authority.activeCount == 0)
        #expect(await context.responder.snapshot() == (deferred ? .acknowledged(.deferredChannelMessageWithSource) : .pending))
        #expect(await router.activeHandlerCount == 0)
    }

    /// Authorization/coordinator errors cannot invoke a false-predicate rejection or the original handler.
    /// - Parameter authorization: Selects a predicate failure rather than an injected authority failure.
    /// - Throws: Unexpected authoring/context errors fail; original errors and exact effects are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func injectedFailureNoRejection(authorization: Bool) async throws {
        let trace = PolicyTrace(), authority = PolicyAuthority(trace: trace, fail: true)
        let policies = try CommandPolicies(limits: PolicyLimits(), requiring: CommandPolicy.authorized { _ in
            trace.append("predicate")
            if authorization { throw PolicyFailure.authorization }
            return true
        }, concurrency: authority, onRejection: { _ in trace.append("forbidden-reject"); return .message(try Self.message()) })
        let context = try Self.context(trace: trace), router = try Self.catalog(trace: trace).applying(policies).makeRouter()
        await #expect(throws: authorization ? PolicyFailure.authorization : PolicyFailure.coordinator) { try await router.route(context) }
        #expect(trace.events == (authorization ? ["predicate"] : ["predicate", "admit"]))
        #expect(await authority.activeCount == 0)
        #expect(await context.responder.snapshot() == .pending)
    }

    /// Sequential and simultaneous continuation attempts execute the original prepared adapter at most once.
    /// - Parameter concurrent: Attempts both next calls concurrently rather than after the first completes.
    /// - Throws: Unexpected fixture/routing errors fail; duplicate continuation errors are asserted inside middleware.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func duplicateNextIsRejected(concurrent: Bool) async throws {
        let trace = PolicyTrace()
        let middleware = InvocationMiddleware<CommandContext, Void> { input, next in
            if concurrent {
                let successes = await withTaskGroup(of: Int.self) { group in
                    for _ in 0..<2 {
                        group.addTask {
                            do { try await next(input); return 1 }
                            catch { #expect(error as? CommandPolicyError == .continuationAlreadyInvoked); return 0 }
                        }
                    }
                    var successes = 0
                    for await success in group { successes += success }
                    return successes
                }
                #expect(successes == 1)
            } else {
                try await next(input)
                await #expect(throws: CommandPolicyError.continuationAlreadyInvoked) { try await next(input) }
            }
        }
        let policies = try CommandPolicies(limits: PolicyLimits(), middleware: middleware)
        let router = try Self.catalog(trace: trace).applying(policies).makeRouter(), context = try Self.context(trace: trace)
        #expect(try await router.route(context))
        #expect(trace.events == ["handler", "initial:4"])
    }

    /// Exact subsets select only named routes, empty subsets execute nothing and unknown keys reject inertly.
    /// - Parameter empty: Uses an explicitly empty subset instead of the one existing command key.
    /// - Throws: Unexpected authoring/router errors fail; unselected routes retain their original execution.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func exactSubsetAndUnknownKeys(empty: Bool) async throws {
        let trace = PolicyTrace(), original = try Self.catalog(trace: trace)
        let policies = try CommandPolicies(limits: PolicyLimits(), requiring: CommandPolicy.authorized { _ in trace.append("policy"); return true })
        #expect(throws: CommandPolicyError.unknownRoute) { try original.applying(policies, to: [.command(name: "missing")]) }
        #expect(trace.events.isEmpty)
        let wrapped = try original.applying(policies, to: empty ? [] : [.command(name: "reply")])
        #expect(try await wrapped.makeRouter().route(Self.context(trace: trace)))
        #expect(trace.events == (empty ? ["handler", "initial:4"] : ["policy", "handler", "initial:4"]))
    }

    /// Per-expression and cumulative catalog budgets reject excessive nodes/depth before executing retained closures.
    /// - Throws: Unexpected valid-limit/authoring errors fail; each finite boundary is asserted exactly.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cumulativeCompositionBounds() throws {
        let trace = PolicyTrace(), predicate = CommandPolicy.authorized { _ in trace.append("forbidden"); return true }
        #expect(throws: PolicyCompositionError.nodeLimit) {
            try CommandPolicies(limits: PolicyLimits(maximumNodes: 1), requiring: predicate)
        }
        #expect(throws: PolicyCompositionError.depthLimit) {
            try CommandPolicies(limits: PolicyLimits(maximumDepth: 1), requiring: predicate.negated())
        }
        let original = try Self.catalog(trace: trace)
        let nodes = try CommandPolicies(limits: PolicyLimits(maximumNodes: 3), requiring: predicate)
        let once = try original.applying(nodes)
        #expect(throws: PolicyCompositionError.nodeLimit) { try once.applying(nodes) }
        let depth = try CommandPolicies(limits: PolicyLimits(maximumDepth: 1))
        let shallow = try original.applying(depth)
        #expect(throws: PolicyCompositionError.depthLimit) { try shallow.applying(depth) }
        #expect(trace.events.isEmpty)
    }

    /// Cancellation returned by an authorization predicate prevents even the synchronous rejection factory.
    /// - Throws: Unexpected fixture errors fail; cancellation and untouched response ownership are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func predicateCancellationSkipsRejectionFactory() async throws {
        let trace = PolicyTrace()
        let policies = try CommandPolicies(limits: PolicyLimits(), requiring: CommandPolicy.authorized { _ in
            trace.append("predicate")
            withUnsafeCurrentTask { $0?.cancel() }
            return false
        }, onRejection: { _ in trace.append("forbidden-reject"); return .message(try Self.message()) },
            mapError: { _, _ in trace.append("forbidden-map"); return PolicyFailure.mapped })
        let router = try Self.catalog(trace: trace).applying(policies).makeRouter(), context = try Self.context(trace: trace)
        let task = Task { try await router.route(context) }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(trace.events == ["predicate"])
        #expect(await context.responder.snapshot() == .pending)
    }

    /// Successful predicate and short-circuit middleware boundaries retain cancellation despite normal closure returns.
    /// Predicate cancellation prevents injected admission entirely; middleware cancellation releases its acquired slot.
    /// - Parameters:
    ///   - predicate: Cancels in an allowing predicate rather than middleware that deliberately omits next.
    ///   - deferred: Selects immediate or deferred adapters, neither of which may acknowledge or run handler work.
    /// - Throws: Unexpected authoring/context errors fail; cancellation, skipped callbacks and exact cleanup are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true], [false, true])
    func cancellationAfterSuccessfulStage(predicate: Bool, deferred: Bool) async throws {
        let trace = PolicyTrace(), authority = PolicyAuthority(trace: trace)
        let authorization = CommandPolicy.authorized { _ in
            trace.append("predicate")
            if predicate { withUnsafeCurrentTask { $0?.cancel() } }
            return true
        }
        let middleware = InvocationMiddleware<CommandContext, Void> { _, _ in
            trace.append("middleware")
            withUnsafeCurrentTask { $0?.cancel() }
        }
        let policies = try CommandPolicies(limits: PolicyLimits(), requiring: authorization,
            middleware: middleware, concurrency: authority,
            onRejection: { _ in trace.append("forbidden-reject"); return .message(try Self.message()) },
            mapError: { _, _ in trace.append("forbidden-map"); return PolicyFailure.mapped })
        let router = try Self.catalog(trace: trace, deferred: deferred).applying(policies).makeRouter()
        let context = try Self.context(trace: trace)
        let task = Task { try await router.route(context) }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(trace.events == (predicate ? ["predicate"] : ["predicate", "admit", "middleware", "release"]))
        #expect(await authority.activeCount == 0)
        #expect(await router.activeHandlerCount == 0)
        #expect(await context.responder.snapshot() == .pending)
    }

    /// Explicit Discord cancellation remains cancellation even when the current task itself has not been cancelled.
    /// - Throws: Unexpected fixture errors fail; the cancellation category bypasses arbitrary error translation.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func explicitDiscordCancellationBypassesMapping() async throws {
        let trace = PolicyTrace()
        let policies = try CommandPolicies(limits: PolicyLimits(),
            mapError: { _, _ in trace.append("forbidden-map"); return PolicyFailure.mapped })
        let catalog = try Self.catalog(trace: trace, work: { trace.append("handler"); throw DiscordError.cancelled })
        let context = try Self.context(trace: trace), router = try catalog.applying(policies).makeRouter()
        await #expect(throws: DiscordError.cancelled) { try await router.route(context) }
        #expect(trace.events == ["handler"])
        #expect(await context.responder.snapshot() == .pending)
    }

    /// Retaining a continuation cannot execute application work after middleware and admission have returned.
    /// - Throws: Unexpected fixture errors fail; late use must fail without changing response ownership.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func retainedNextClosesAtMiddlewareReturn() async throws {
        let trace = PolicyTrace(), retained = PolicyRetainedNext()
        let middleware = InvocationMiddleware<CommandContext, Void> { input, next in
            await retained.store { try await next(input) }
        }
        let policies = try CommandPolicies(limits: PolicyLimits(), middleware: middleware)
        let router = try Self.catalog(trace: trace).applying(policies).makeRouter(), context = try Self.context(trace: trace)
        #expect(try await router.route(context))
        await #expect(throws: CommandPolicyError.continuationAlreadyInvoked) { try await retained.invoke() }
        #expect(trace.events.isEmpty)
        #expect(await context.responder.snapshot() == .pending)
        #expect(await router.activeHandlerCount == 0)
    }

    /// A child already executing next retains aggregate admission until it completes despite early middleware return.
    /// - Throws: Unexpected fixture/barrier errors fail; overload, cleanup and the joined child result are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func activeChildNextRetainsAdmission() async throws {
        let trace = PolicyTrace(), entered = TestBarrier(), middlewareReturned = TestBarrier(), gate = TestBarrier()
        let authority = try CommandConcurrencyLimit(maximumConcurrent: 1), retained = PolicyRetainedNext()
        let middleware = InvocationMiddleware<CommandContext, Void> { input, next in
            let child = Task { try await next(input) }
            await retained.storeChild(child)
            try await entered.wait()
            middlewareReturned.open()
        }
        let policies = try CommandPolicies(limits: PolicyLimits(), middleware: middleware, concurrency: authority)
        let catalog = try Self.catalog(trace: trace, work: { trace.append("handler"); entered.open(); try await gate.wait() })
        let router = try catalog.applying(policies).makeRouter(), context = try Self.context(trace: trace)
        let route = Task { try await router.route(context) }
        try await middlewareReturned.wait()
        #expect(await authority.activeCount == 1)
        #expect(await router.activeHandlerCount == 1)
        await #expect(throws: CommandPolicyError.capacityExceeded) { try await authority.withPermit { () } }
        #expect(trace.events == ["handler"])
        gate.open()
        #expect(try await route.value)
        try await retained.joinChild()
        #expect(await authority.activeCount == 0)
        #expect(await router.activeHandlerCount == 0)
        #expect(trace.events == ["handler", "initial:4"])
    }

    private static let validOptions = #"[{"name":"person","type":3,"value":"Ada"}]"#

    /// Returns an inert middleware leaf recording entry and unconditional cleanup in caller order.
    /// - Parameters:
    ///   - label: Fixed test event prefix.
    ///   - trace: Synchronous bounded per-test observer, also usable by synchronous error callbacks.
    /// - Returns: A wrapper forwarding the original typed context exactly once.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private static func middleware(_ label: String, trace: PolicyTrace) -> InvocationMiddleware<CommandContext, Void> {
        InvocationMiddleware { input, next in
            trace.append("\(label):enter")
            defer { trace.append("\(label):exit") }
            try await next(input)
        }
    }

    /// Builds one existing-model ephemeral JSON message without submitting it.
    /// - Returns: Controlled immediate message body.
    /// - Throws: Unexpected controlled payload validation errors.
    private static func message() throws -> MessageResponse {
        try MessageResponse(InteractionMessageCreate(content: .value("allowed"), flags: .value(.ephemeral)))
    }

    /// Compiles a finite typed command with interchangeable immediate/deferred adapters and inert injected work.
    /// - Parameters:
    ///   - trace: Per-test operation observer, used when no custom work is supplied.
    ///   - deferred: Selects explicit defer ownership, default immediate.
    ///   - work: Optional cancellation-cooperative operation; nil records one handler entry.
    /// - Returns: One registration and exact route with no execution or registration requests.
    /// - Throws: Controlled schema/lowering errors.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private static func catalog(trace: PolicyTrace, deferred: Bool = false,
        work: (@Sendable () async throws -> Void)? = nil) throws -> CompiledCommands {
        let work = work ?? { trace.append("handler") }
        if deferred {
            return try CommandCompilation.compile(SlashCommand(id: "reply", handler: PolicyDeferred(work: work)))
        }
        return try CommandCompilation.compile(SlashCommand(id: "reply", handler: PolicyImmediate(work: work)))
    }

    /// Compiles matching slash/autocomplete registration snapshots without executing their handlers.
    /// - Parameter trace: Per-test observer for unexpected complete or suggestions work.
    /// - Returns: A two-route catalog sharing one authoritative slash registration.
    /// - Throws: Controlled descriptor, registration or compilation errors.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private static func autocompleteCatalog(trace: PolicyTrace) throws -> CompiledCommands {
        let option = try ArgumentOption<String>(name: "person", description: "Person", autocomplete: true)
        let definition = try CommandDefinition.slash(name: "reply", description: "Reply") { option.registration }
        let route = CommandRoute(key: try .command(name: "reply")) { _ in trace.append("complete") }
        let suggestions = try AutocompleteCommand(id: "suggestions", name: "reply", option: option, handler: PolicySuggestions(trace: trace))
        return try CommandCompilation.compile(Module(id: "catalog") {
            ExistingCommandFamily(id: "registration", definitions: [definition], routes: [route])
            suggestions
        })
    }

    /// Constructs an inert normalized interaction with injected virtual time and local JSON-only sinks.
    /// - Parameters:
    ///   - trace: Per-test response recorder, with no retained credentials.
    ///   - kind: Interaction wire kind, default slash invocation (2).
    ///   - options: Controlled argument leaves, default one complete required string.
    ///   - extra: Additional envelope observations, default none; callers own semantic fixture validity.
    /// - Returns: Pending exact interaction/responder pair without I/O or background work.
    /// - Throws: Controlled model/context/admission validation errors.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private static func context(trace: PolicyTrace, kind: Int = 2, options: String = validOptions,
        extra: [String: JSONValue] = [:]) throws -> InteractionContext {
        var fields: [String: JSONValue] = ["id": .string(String(UInt64.max)), "application_id": .string("9"),
            "type": .number(try JSONNumber(rawValue: String(kind))), "token": .string("fixture-token"),
            "version": .number(try JSONNumber(rawValue: "1")), "app_permissions": .string("0"), "entitlements": .array([]),
            "authorizing_integration_owners": .object([:]), "attachment_size_limit": .number(try JSONNumber(rawValue: "10485760")),
            "data": .object(["id": .string("8"), "name": .string("reply"), "type": .number(try JSONNumber(rawValue: "1")),
                "options": try JSONValue.parse(Data(options.utf8))])]
        fields.merge(extra) { _, replacement in replacement }
        let interaction = try Interaction(data: JSONValue.object(fields).serialized()), clock = ManualClock()
        let responder = InteractionResponder(interaction: interaction, deliveryMode: .http, clock: InteractionClock(clock),
            sink: InteractionResponseSink(initial: { response, _ in
                trace.append("initial:\(response.type.rawValue)")
                trace.callback(try response.jsonValue(interactionType: interaction.type.knownValue))
            }, editOriginal: { _, _ in
                trace.append("edit")
                return try Message(data: Data(policyMessageJSON.utf8))
            }), admission: try InteractionAcknowledgementAdmission())
        return try InteractionContext(interaction: interaction, deliveryMode: .http, responder: responder)
    }
}

/// Fixed test errors distinguish independent failure owners without retaining submitted input.
private enum PolicyFailure: Error, Equatable { case authorization, coordinator, handler, mapped }

/// One required finite typed leaf; its constructor creates fresh argument state for each invocation.
private struct PolicyArguments: CommandArguments {
    let person: String
    /// Returns an inert required string descriptor and invocation-local aggregate constructor.
    static var schema: CommandArgumentSchema<Self> {
        /// Validates the descriptor without decoding supplied data or executing handlers.
        /// - Returns: One finite schema in deterministic registration order.
        /// - Throws: Controlled descriptor/schema errors.
        get throws {
            let person = try ArgumentOption<String>(name: "person", description: "Person")
            return try CommandArgumentSchema(options: [person.erased]) { try Self(person: $0.value(for: person)) }
        }
    }
}

/// Immediate typed adapter fixture retaining work inertly until after policy admission.
private struct PolicyImmediate: SlashCommandHandler {
    typealias Arguments = PolicyArguments
    let work: @Sendable () async throws -> Void
    /// Returns deterministic registration metadata without invoking behavior.
    var command: SlashCommandMetadata { .init(name: "reply", description: "Reply") }
    /// Runs injected admitted work and returns one JSON-only message.
    /// - Parameters:
    ///   - context: Original immutable authenticated invocation snapshot, without response authority.
    ///   - arguments: Fresh typed required person value, already completely validated.
    /// - Returns: One validated immediate callback payload.
    /// - Throws: Injected application failure, cooperative cancellation or controlled payload errors.
    func execute(_ context: CommandContext, arguments: PolicyArguments) async throws -> MessageResponse {
        try await work()
        return try MessageResponse(InteractionMessageCreate(content: .value("allowed")))
    }
}

/// Deferred typed adapter fixture retaining work inertly until after confirmed acknowledgement.
private struct PolicyDeferred: DeferredSlashCommandHandler {
    typealias Arguments = PolicyArguments
    let work: @Sendable () async throws -> Void
    /// Returns deterministic registration metadata without invoking behavior or deferring.
    var command: SlashCommandMetadata { .init(name: "reply", description: "Reply") }
    /// Runs injected admitted work and returns one edit of the already deferred original response.
    /// - Parameters:
    ///   - context: Immutable snapshot supplied after successful explicit deferral.
    ///   - arguments: Fresh typed required person value, admitted before policies and deferral.
    /// - Returns: Validated original edit retaining the existing owner.
    /// - Throws: Injected application failure, cooperative cancellation or controlled edit errors.
    func execute(_ context: DeferredCommandContext, arguments: PolicyArguments) async throws -> DeferredMessageResponse {
        try await work()
        return try DeferredMessageResponse(InteractionMessageEdit(content: .value("allowed"), deferredResponse: true))
    }
}

/// Suggestions fixture makes any unexpected execution visible rather than implicitly suppressing it.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private struct PolicySuggestions: AutocompleteCommandHandler {
    typealias Value = String
    let trace: PolicyTrace
    /// Records one admitted focused invocation and returns a validated empty suggestions payload.
    /// - Parameters:
    ///   - context: Immutable authenticated snapshot without low-level response ownership.
    ///   - input: Completely admitted partial option envelope.
    ///   - value: Focused string decoded before policy work.
    /// - Returns: Explicit zero-choice autocomplete response.
    /// - Throws: Controlled response-bound validation errors.
    func execute(_ context: CommandContext, input: AutocompleteInput, value: String) async throws -> AutocompleteResponse<String> {
        trace.append("suggestions")
        return try AutocompleteResponse([])
    }
}

/// Injected aggregate authority records acquisition/release and can fail before invoking caller work.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor PolicyAuthority: CommandConcurrencyAuthority {
    let trace: PolicyTrace
    let fail: Bool
    private(set) var activeCount = 0
    /// Stores configuration without admission, tasks or I/O.
    /// - Parameters:
    ///   - trace: Per-test observer for acquisition/release ordering.
    ///   - fail: Whether every admission should fail before acquiring a slot, default false.
    init(trace: PolicyTrace, fail: Bool = false) { self.trace = trace; self.fail = fail }
    /// Runs admitted work once and releases before success, failure or cancellation returns.
    /// - Parameter operation: Caller-owned cancellation-cooperative work.
    /// - Returns: Original operation result after synchronous actor-isolated release.
    /// - Throws: Injected coordinator error before execution or the operation's unchanged error.
    func withPermit<Value: Sendable>(operation: @Sendable () async throws -> Value) async throws -> Value {
        trace.append("admit")
        if fail { throw PolicyFailure.coordinator }
        activeCount += 1
        defer { activeCount -= 1; trace.append("release") }
        return try await operation()
    }
}

/// Mutex-backed per-test observations support synchronous mapper/rejection callbacks without unstructured tasks.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private final class PolicyTrace: Sendable {
    private struct State { var events: [String] = []; var callbacks: [JSONValue] = [] }
    private let state = Mutex(State())
    /// Current fixed-marker execution order, returned as a value snapshot.
    var events: [String] { state.withLock { $0.events } }
    /// Current validated callback JSON bodies, returned as a value snapshot.
    var callbacks: [JSONValue] { state.withLock { $0.callbacks } }
    /// Appends one bounded test-only marker synchronously across actors and error callbacks.
    /// - Parameter value: Fixed event marker; never raw submitted data or credentials.
    func append(_ value: String) { state.withLock { $0.events.append(value) } }
    /// Records one validated callback body without sending or interpreting it.
    /// - Parameter value: Controlled existing-model callback JSON.
    func callback(_ value: JSONValue) { state.withLock { $0.callbacks.append(value) } }
}

private let policyMessageJSON = #"{"id":"1","channel_id":"2","author":{"id":"3","username":"fixture","discriminator":"0","avatar":null},"content":"Done","timestamp":"2026-10-18T00:00:00Z","edited_timestamp":null,"tts":false,"mention_everyone":false,"mentions":[],"mention_roles":[],"attachments":[],"embeds":[],"pinned":false,"type":0}"#

/// Test-owned escaping continuations and child tasks remain observable and are explicitly joined by their tests.
private actor PolicyRetainedNext {
    private var next: (@Sendable () async throws -> Void)?
    private var child: Task<Void, any Error>?
    /// Stores one test continuation without invoking it or starting background work.
    /// - Parameter next: Original middleware next bound to its admitted typed input.
    func store(_ next: @escaping @Sendable () async throws -> Void) { self.next = next }
    /// Explicitly invokes the retained continuation after its middleware has returned.
    /// - Throws: Missing fixture storage or the continuation's unchanged closed-lifetime error.
    func invoke() async throws {
        let next = try #require(next)
        try await next()
    }
    /// Retains one already-started test-owned child so its outcome cannot be silently abandoned.
    /// - Parameter child: Task executing one prepared adapter, joined before the test exits.
    func storeChild(_ child: Task<Void, any Error>) { self.child = child }
    /// Waits for the child after the test releases its deterministic suspension gate.
    /// - Throws: Missing fixture storage or the child's unchanged execution failure.
    func joinChild() async throws {
        let child = try #require(child)
        try await child.value
    }
}
