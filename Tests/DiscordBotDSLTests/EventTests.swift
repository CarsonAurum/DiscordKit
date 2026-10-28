// File: Tests/DiscordBotDSLTests/EventTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordBotDSL
import DiscordCore
import DiscordDSL
import DiscordGateway
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing

/// Models an independently authored handler whose injected work remains inert during compilation.
private struct FixtureEventHandler<Event: Sendable>: GatewayEventHandler {
    let handlerID: String
    let selector: GatewayEventSelector<Event>
    var requiredIntents: GatewayIntents = []
    var eventGroup: String? = nil
    var sourceLocation = DefinitionSourceLocation(fileID: "Fixtures/Events.swift", line: 12, column: 4)
    let work: @Sendable (Event, GatewayEventContext) async throws -> Void

    /// Invokes only the test's explicitly supplied work after ordinary runtime admission.
    /// - Parameters:
    ///   - event: Selector-projected event, retained as its concrete Sendable type.
    ///   - context: Exact original envelope and shard provenance supplied by the runtime.
    /// - Throws: The fixture callback's original failure or cancellation.
    func handle(_ event: Event, context: GatewayEventContext) async throws {
        try await work(event, context)
    }
}

/// Serializes observations without giving callbacks executor affinity or introducing timing assumptions.
private actor EventObservations {
    private var values: [String] = []

    /// Appends one nonsecret label in the order callbacks reach this actor.
    /// - Parameter value: Fixture-owned label; event payloads and credentials are never recorded.
    func record(_ value: String) { values.append(value) }

    /// Captures all completed observation calls atomically.
    /// - Returns: A value snapshot in insertion order.
    func snapshot() -> [String] { values }
}

/// Original application failures must survive scheduling and structured sibling cleanup unchanged.
private enum EventFixtureFailure: Error, Equatable {
    case callback
    case selector
    case missingFailure
}

/// Uses every public handler protocol default while supplying only identity, selection and behavior.
private struct DefaultEventHandler: GatewayEventHandler {
    let handlerID = "defaults"
    let selector = GatewayEventSelector<GatewayDispatch>.all

    /// Provides inert work used only to prove compilation preserves a handwritten conformer.
    /// - Parameters:
    ///   - event: Selected typed dispatch, intentionally unused by this no-op fixture.
    ///   - context: Original event envelope, intentionally unused.
    func handle(_ event: GatewayDispatch, context: GatewayEventContext) async throws {}
}

/// Keeps a third-party executable registration separate from the metadata it asks the collector to trust.
private struct FixtureEventContribution: GatewayEventContribution {
    let registration: GatewayHandlerRegistration
    let declaration: RawDefinitionContribution
}

/// Makes a pipeline owner available to an injected callback only after explicit subscription succeeds.
private actor EventPipelineReference {
    private var pipelines: GatewayEventPipelines?

    /// Stores the sole fixture owner without invoking callbacks or starting a task.
    /// - Parameter pipelines: Ready owner installed before the test starts its run.
    func install(_ pipelines: GatewayEventPipelines) { self.pipelines = pipelines }

    /// Removes the fixture's retained owner before cancelling it from inside its own callback.
    /// The local reference keeps cancellation valid across suspension while breaking the fixture's
    /// owner-handler-reference cycle; cancellation must never join the caller's own task.
    func cancel() async {
        let owner = pipelines
        pipelines = nil
        await owner?.cancel()
    }
}

/// Exercises independently authored Gateway handlers through owned offline hubs and deterministic gates.
@Suite("Gateway event DSL", .timeLimit(.minutes(1)))
struct EventTests {
    /// Structural namespaces cannot duplicate the existing runtime dispatcher handler identity.
    /// Rejection occurs at compilation, before creating a subscription or invoking user callbacks.
    /// - Throws: Unexpected handler construction or diagnostic-capture errors fail the test.
    @Test func namespacesPreserveRuntimeHandlerUniqueness() throws {
        let first = FixtureEventHandler(handlerID: "shared", selector: GatewayEventSelector<GatewayEvent>.raw) { _, _ in
            Issue.record("Compilation executed a handler")
        }
        let second = FixtureEventHandler(handlerID: "shared", selector: GatewayEventSelector<GatewayEvent>.raw,
            eventGroup: "independent") { _, _ in Issue.record("Compilation executed a handler") }
        let diagnostic = try Self.compilationFailure {
            try EventCompilation.compile(BotDefinitionGroup([
                ModuleNamespace(id: "one") { first }, ModuleNamespace(id: "two") { second },
            ]), intents: [])
        }
        #expect(diagnostic.code == .duplicateHandlerID)
        #expect(diagnostic.handlerID == "shared")
        #expect(diagnostic.source == second.sourceLocation)
    }

    /// Builds a bounded synthetic event while retaining exact complete shard and connection provenance.
    /// - Parameters:
    ///   - sequence: Nonnegative fixture sequence, default one.
    ///   - shard: Zero-based shard within the fixture's two-shard topology, default zero.
    ///   - name: Exact dispatch name; unknown future spellings remain valid. Defaults to `RESUMED`.
    ///   - data: Exact JSON payload, default an empty resumed object.
    ///   - opcode: Nonnegative opcode, default dispatch zero; control events may omit typed decoding.
    /// - Returns: A validated immutable raw event without opening any socket.
    /// - Throws: Invalid envelope, shard or JSON bounds failures for an invalid fixture.
    private static func event(_ sequence: Int64 = 1, shard: Int = 0, name: String = "RESUMED",
                              data: JSONValue = .object([:]), opcode: Int = 0) throws -> GatewayEvent {
        try GatewayEvent(shard: .init(botID: .init(rawValue: 18_446_744_073_709_551_615),
            topologyGeneration: 7, index: shard, count: 2), opcode: opcode, name: name,
            sequence: sequence, data: data, socketGeneration: 11)
    }

    /// Captures a typed downstream diagnostic while rejecting unrelated structural or application errors.
    /// - Parameter operation: Synchronous compilation expected to fail downstream event admission.
    /// - Returns: Original event diagnostic for exact code, identity, source and missing-bit assertions.
    /// - Throws: Unexpected errors, or a fixture failure if invalid input was accepted.
    private static func compilationFailure(_ operation: () throws -> CompiledEvents) throws -> EventCompilationDiagnostic {
        do {
            _ = try operation()
            Issue.record("Expected event compilation to fail")
            throw EventFixtureFailure.missingFailure
        } catch let diagnostic as EventCompilationDiagnostic {
            return diagnostic
        }
    }

    /// An empty graph allocates no pipeline, and protocol defaults remain usable without a convenience wrapper.
    /// - Throws: Unexpected valid compilation, subscription or execution failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func emptyPlanAndProtocolDefaults() async throws {
        let hub = GatewayEventHub(configuration: try .init())
        let compiled = try EventCompilation.compile(EmptyBotDefinition(), intents: [])
        #expect(compiled.handlerIDs.isEmpty)
        #expect(compiled.groupIDs.isEmpty)
        #expect(compiled.requiredIntents.isEmpty)
        #expect(compiled.description.declarations.isEmpty)
        let pipelines = try await compiled.subscribe(to: hub, configuration: .init())
        #expect(pipelines.subscriptionCount == 0)
        try await pipelines.run()
        #expect(await hub.snapshot().subscriptions == 0)
        let defaults = DefaultEventHandler()
        #expect(defaults.requiredIntents.isEmpty)
        #expect(defaults.eventGroup == nil)
        #expect(defaults.sourceLocation.fileID == "<unknown>")
        let plan = try EventCompilation.compile(defaults, intents: [])
        #expect(plan.handlerIDs == ["defaults"])
        #expect(plan.description.declarations.count == 1)
        #expect(plan.description.declarations.first?.declaration.id == "defaults")
    }

    /// Selector and handler requirements are unioned, including privileged content, before any subscription exists.
    /// Presence in an explicit Identify bitset does not infer external portal enablement or approval.
    /// - Throws: Unexpected valid compilation failures or an error outside the expected diagnostic type.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func missingOrdinaryAndPrivilegedIntentsFailBeforeSubscriptions() async throws {
        let selector = GatewayEventSelector<GatewayDispatch>(id: "members", requiredIntents: .guildMembers) { $0 }
        let handler = FixtureEventHandler(handlerID: "privileged", selector: selector,
            requiredIntents: .messageContent) { _, _ in Issue.record("Compilation invoked callback") }
        let hub = GatewayEventHub(configuration: try .init())
        let absent = try Self.compilationFailure { try EventCompilation.compile(handler, intents: []) }
        #expect(absent.code == .missingIntents)
        #expect(absent.handlerID == "privileged")
        #expect(absent.missingIntents == [.guildMembers, .messageContent])
        #expect(absent.source == handler.sourceLocation)
        let partial = try Self.compilationFailure { try EventCompilation.compile(handler, intents: .guildMembers) }
        #expect(partial.missingIntents == .messageContent)
        let exact: GatewayIntents = [.guildMembers, .messageContent]
        let plan = try EventCompilation.compile(handler, intents: exact)
        #expect(plan.requiredIntents == exact)
        #expect(await hub.snapshot().subscriptions == 0)
        let message = FixtureEventHandler(handlerID: "messages", selector: GatewayEventSelector<GatewayMessageUpdate>.messageUpdate) { _, _ in }
        let messageAbsent = try Self.compilationFailure { try EventCompilation.compile(message, intents: []) }
        #expect(messageAbsent.missingIntents == [.guildMessages, .directMessages])
        let messagePartial = try Self.compilationFailure { try EventCompilation.compile(message, intents: .guildMessages) }
        #expect(messagePartial.missingIntents == .directMessages)
        let ordinary = try EventCompilation.compile(message, intents: [.guildMessages, .directMessages])
        #expect(ordinary.requiredIntents == [.guildMessages, .directMessages])
        #expect(!ordinary.requiredIntents.contains(.messageContent))
    }

    /// Handler identities remain globally unique across modules while group identities and counts are bounded.
    /// - Throws: Unexpected compilation errors; exact structural and downstream codes are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func duplicateIdentityAndIndependentGroupAdmission() throws {
        let first = FixtureEventHandler(handlerID: "duplicate", selector: GatewayEventSelector<GatewayEvent>.raw) { _, _ in }
        let second = FixtureEventHandler(handlerID: "duplicate", selector: GatewayEventSelector<GatewayEvent>.raw,
            eventGroup: "other") { _, _ in }
        let duplicate = BotDefinitionGroup([Module(id: "one") { first }, Module(id: "two") { second }])
        do {
            _ = try EventCompilation.compile(duplicate, intents: [])
            Issue.record("Duplicate handler identity was accepted")
        } catch let diagnostic as DefinitionDiagnostic {
            #expect(diagnostic.code == .duplicateDeclarationID)
            #expect(diagnostic.modulePath == ["two"])
        }
        let independent = FixtureEventHandler(handlerID: "independent", selector: GatewayEventSelector<GatewayEvent>.raw,
            eventGroup: "other") { _, _ in }
        let multiple = BotDefinitionGroup([first, independent])
        let limited = try Self.compilationFailure {
            try EventCompilation.compile(multiple, intents: [], maximumIndependentGroups: 0)
        }
        #expect(limited.code == .independentGroupLimit)
        let admitted = try EventCompilation.compile(multiple, intents: [], maximumIndependentGroups: 1)
        #expect(admitted.handlerIDs == ["duplicate", "independent"])
        #expect(admitted.groupIDs.count == 2)
        for group in ["", "bad\nidentity", String(repeating: "a", count: 129)] {
            let invalid = FixtureEventHandler(handlerID: "bad-group", selector: GatewayEventSelector<GatewayEvent>.raw,
                eventGroup: group) { _, _ in }
            #expect(try Self.compilationFailure { try EventCompilation.compile(invalid, intents: []) }.code == .invalidRegistration)
        }
    }

    /// Invalid downstream and shared structural limits fail deterministically before executable work is retained.
    /// - Throws: Unexpected valid compilation errors or a diagnostic of an unrelated type.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func invalidConfigurationAndStructuralBounds() throws {
        let handler = DefaultEventHandler()
        for bound in [-1, 129] {
            let invalid = try Self.compilationFailure {
                try EventCompilation.compile(handler, intents: [], maximumIndependentGroups: bound)
            }
            #expect(invalid.code == .invalidConfiguration)
        }
        for limits in [DefinitionLimits(maxDepth: 0), DefinitionLimits(maxDeclarations: -1)] {
            do {
                _ = try EventCompilation.compile(handler, intents: [], limits: limits)
                Issue.record("Invalid shared limits were accepted")
            } catch let diagnostic as DefinitionDiagnostic {
                #expect(diagnostic.code == .invalidLimits)
            }
        }
        do {
            _ = try EventCompilation.compile(handler, intents: [], limits: .init(maxDeclarations: 0))
            Issue.record("Declaration count bound was bypassed")
        } catch let diagnostic as DefinitionDiagnostic {
            #expect(diagnostic.code == .declarationLimit)
        }
    }

    /// Extra selector identities obey byte/control limits, and diagnostic display bounds preserve Unicode scalars.
    /// - Throws: Unexpected diagnostic or valid-boundary compilation failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func selectorIdentitiesAndBoundedUnicodeDiagnostics() throws {
        for identity in ["", "bad\u{7f}", String(repeating: "a", count: 129)] {
            let selector = GatewayEventSelector<GatewayDispatch>(id: identity) { $0 }
            let handler = FixtureEventHandler(handlerID: "selector", selector: selector) { _, _ in }
            #expect(try Self.compilationFailure { try EventCompilation.compile(handler, intents: []) }.code == .invalidRegistration)
        }
        let boundary = GatewayEventSelector<GatewayDispatch>(id: String(repeating: "🛠", count: 32)) { $0 }
        let handler = FixtureEventHandler(handlerID: "boundary", selector: boundary) { _, _ in }
        #expect(try EventCompilation.compile(handler, intents: []).handlerIDs == ["boundary"])
        let identity = String(repeating: "🛠", count: 100)
        let source = DefinitionSourceLocation(fileID: identity, line: 91, column: 7)
        let missing = GatewayIntents(rawValue: UInt64.max)
        let diagnostic = EventCompilationDiagnostic(code: .missingIntents, handlerID: identity,
            source: source, missingIntents: missing)
        #expect(diagnostic.handlerID == String(repeating: "🛠", count: 32))
        #expect(diagnostic.source.fileID == String(repeating: "🛠", count: 64))
        #expect(diagnostic.source.line == 91)
        #expect(diagnostic.source.column == 7)
        #expect(diagnostic.missingIntents == missing)
    }

    /// A structurally valid raw declaration cannot impersonate an executable event contribution.
    /// - Throws: Unexpected structural compilation failures or a different downstream diagnostic type.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func unsupportedRawContributionsAreRejected() throws {
        let source = DefinitionSourceLocation(fileID: "Fixtures/Impersonator.swift", line: 4, column: 2)
        let kind = DefaultEventHandler().declaration.kind
        let raw = RawDefinitionContribution(id: "impostor", kind: kind, source: source)
        let diagnostic = try Self.compilationFailure { try EventCompilation.compile(raw, intents: []) }
        #expect(diagnostic.code == .unsupportedContribution)
        #expect(diagnostic.handlerID == "impostor")
        #expect(diagnostic.source == source)
    }

    /// Custom event adapters preserve valid snapshots and reject changes to every trusted metadata field.
    /// - Throws: Unexpected valid compilation errors or diagnostics outside the exercised admission owner.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func customRegistrationMetadataCannotBeForged() throws {
        let registration = GatewayHandlerRegistration(DefaultEventHandler())
        let metadata = registration.declaration
        let valid = FixtureEventContribution(registration: registration, declaration: metadata)
        #expect(try EventCompilation.compile(valid, intents: []).handlerIDs == ["defaults"])
        var changedIntents = metadata.payload
        var changedDecode = metadata.payload
        if case .object(var fields) = metadata.payload {
            fields["required_intents"] = .string("32768")
            changedIntents = .object(fields)
            fields = if case .object(let original) = metadata.payload { original } else { [:] }
            fields["decode_dispatch"] = .bool(false)
            changedDecode = .object(fields)
        }
        let forged = [
            RawDefinitionContribution(id: "forged-id", kind: metadata.kind, payload: metadata.payload, source: metadata.source),
            RawDefinitionContribution(id: metadata.id, kind: metadata.kind, text: "forged text", payload: metadata.payload, source: metadata.source),
            RawDefinitionContribution(id: metadata.id, kind: metadata.kind, payload: changedIntents, source: metadata.source),
            RawDefinitionContribution(id: metadata.id, kind: metadata.kind, payload: changedDecode, source: metadata.source),
            RawDefinitionContribution(id: metadata.id, kind: metadata.kind, payload: metadata.payload,
                source: .init(fileID: "Changed.swift", line: 99, column: 5))
        ]
        for declaration in forged {
            let diagnostic = try Self.compilationFailure {
                try EventCompilation.compile(FixtureEventContribution(registration: registration, declaration: declaration), intents: [])
            }
            #expect(diagnostic.code == .invalidRegistration)
        }
        for (kind, capabilities, code) in [
            (metadata.kind, Set(["forged-capability"]), DefinitionDiagnostic.Code.unsupportedCapability),
            ("forged-kind", Set<String>(), DefinitionDiagnostic.Code.unsupportedKind)
        ] {
            let declaration = RawDefinitionContribution(id: metadata.id, kind: kind, requiredCapabilities: capabilities,
                payload: metadata.payload, source: metadata.source)
            do {
                _ = try EventCompilation.compile(FixtureEventContribution(registration: registration, declaration: declaration), intents: [])
                Issue.record("Forged kind or capability was accepted")
            } catch let diagnostic as DefinitionDiagnostic {
                #expect(diagnostic.code == code)
            }
        }
    }

    /// Two modules share one default pipeline, and both handlers finish before the next shard event begins.
    /// Construction and structural compilation must execute no injected callback and allocate no subscription.
    /// - Throws: Unexpected compilation, subscription, callback or fixture errors.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func declarationOrderAcrossModulesAndSameShardOrder() async throws {
        let observations = EventObservations()
        let done = TestBarrier()
        let first = FixtureEventHandler(handlerID: "first", selector: GatewayEventSelector<GatewayEvent>.raw) { _, context in
            await observations.record("a:\(context.rawEvent.sequence!)")
            #expect(context.rawEvent.shard.topologyGeneration == 7)
            #expect(context.rawEvent.socketGeneration == 11)
        }
        let second = FixtureEventHandler(handlerID: "second", selector: GatewayEventSelector<GatewayEvent>.raw) { _, context in
            await observations.record("b:\(context.rawEvent.sequence!)")
            if context.rawEvent.sequence == 2 { done.open() }
        }
        let definition = BotDefinitionGroup([Module(id: "one") { first }, Module(id: "two") { second }])
        let hub = GatewayEventHub(configuration: try .init())
        let compiled = try EventCompilation.compile(definition, intents: [])
        #expect(compiled.handlerIDs == ["first", "second"])
        #expect(compiled.groupIDs.count == 1)
        #expect(compiled.groupIDs.first! == nil)
        #expect(compiled.requiredIntents.isEmpty)
        #expect(await observations.snapshot().isEmpty)
        #expect(await hub.snapshot().subscriptions == 0)
        let pipelines = try await compiled.subscribe(to: hub, configuration: .init())
        #expect(pipelines.subscriptionCount == 1)
        #expect(await hub.snapshot().subscriptions == 1)
        #expect(await observations.snapshot().isEmpty)
        let run = Task { try await pipelines.run() }
        await hub.publish(try Self.event(1))
        await hub.publish(try Self.event(2))
        try await done.wait()
        await hub.finish()
        try await run.value
        #expect(await observations.snapshot() == ["a:1", "b:1", "a:2", "b:2"])
        #expect(await hub.snapshot().subscriptions == 0)
    }

    /// A suspended callback blocks only its complete shard identity; another shard progresses concurrently.
    /// - Throws: Unexpected compilation, scheduling, fixture or callback failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func crossShardProgressWithoutSameShardOverlap() async throws {
        let observations = EventObservations()
        let entered = TestBarrier(), blocked = TestBarrier(), other = TestBarrier(), done = TestBarrier()
        let handler = FixtureEventHandler(handlerID: "ordered", selector: GatewayEventSelector<GatewayEvent>.raw) { event, _ in
            await observations.record("begin:\(event.shard.index):\(event.sequence!)")
            if event.shard.index == 0, event.sequence == 1 {
                entered.open()
                try await blocked.wait()
            }
            await observations.record("end:\(event.shard.index):\(event.sequence!)")
            if event.shard.index == 1 { other.open() }
            if event.shard.index == 0, event.sequence == 2 { done.open() }
        }
        let hub = GatewayEventHub(configuration: try .init())
        let compiled = try EventCompilation.compile(handler, intents: [])
        let pipelines = try await compiled.subscribe(to: hub, configuration: .init(maximumConcurrentHandlers: 2))
        let run = Task { try await pipelines.run() }
        await hub.publish(try Self.event(1))
        try await entered.wait()
        await hub.publish(try Self.event(2))
        await hub.publish(try Self.event(3, shard: 1))
        try await other.wait()
        #expect(await observations.snapshot() == ["begin:0:1", "begin:1:3", "end:1:3"])
        blocked.open()
        try await done.wait()
        await hub.finish()
        try await run.value
        #expect(await observations.snapshot().suffix(3) == ["end:0:1", "begin:0:2", "end:0:2"])
        #expect(await hub.snapshot().subscriptions == 0)
    }

    /// Future event names reach both the general typed dispatch and exact unknown fallback with lossless data.
    /// - Throws: Unexpected compilation, projection or fixture errors.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func unknownFallbackRetainsNameDataAndRawContext() async throws {
        let observations = EventObservations()
        let done = TestBarrier()
        let payload: JSONValue = .array([.string("future"), .null])
        let all = FixtureEventHandler(handlerID: "all", selector: GatewayEventSelector<GatewayDispatch>.all) { dispatch, context in
            guard case .unknown(let name, let data) = dispatch else {
                Issue.record("Unknown event was not preserved")
                return
            }
            #expect(name == "FUTURE_EVENT")
            #expect(data == payload)
            #expect(context.rawEvent.name == name)
            #expect(context.rawEvent.data == payload)
            await observations.record("all")
        }
        let unknown = FixtureEventHandler(handlerID: "unknown", selector: GatewayEventSelector<GatewayUnknownEvent>.unknown) { event, _ in
            #expect(event.name == "FUTURE_EVENT")
            #expect(event.data == payload)
            await observations.record("unknown")
            done.open()
        }
        let hub = GatewayEventHub(configuration: try .init())
        let compiled = try EventCompilation.compile(BotDefinitionGroup([all, unknown]), intents: [])
        let pipelines = try await compiled.subscribe(to: hub, configuration: .init())
        let run = Task { try await pipelines.run() }
        await hub.publish(try Self.event(name: "FUTURE_EVENT", data: payload))
        try await done.wait()
        await hub.finish()
        try await run.value
        #expect(await observations.snapshot() == ["all", "unknown"])
    }

    /// Future unknown names and payloads stay explicitly accessible while ordinary diagnostics conceal both.
    /// - Throws: A required reflection child assertion if the redacted mirror loses its fixed marker.
    @Test func unknownEventDiagnosticsRedactNameAndPayload() throws {
        let name = "private-future-event-name"
        let payload: JSONValue = .object(["private-future-key": .string("private-future-payload")])
        let event = GatewayUnknownEvent(name: name, data: payload)
        #expect(event.name == name)
        #expect(event.data == payload)
        #expect(event.description == "GatewayUnknownEvent(redacted)")
        #expect(event.debugDescription == event.description)
        #expect(String(describing: event) == event.description)
        #expect(String(reflecting: event) == event.description)
        let mirror = Mirror(reflecting: event)
        #expect(mirror.children.count == 1)
        let child = try #require(mirror.children.first)
        #expect(child.label == "redacted")
        #expect(child.value as? Bool == true)
        for diagnostic in [String(describing: event), String(reflecting: event), String(reflecting: child.value)] {
            #expect(!diagnostic.contains(name))
            #expect(!diagnostic.contains("private-future-key"))
            #expect(!diagnostic.contains("private-future-payload"))
        }
    }

    /// Typed projections validate known payloads before any group callback, including preceding raw observers.
    /// - Throws: Unexpected setup failures; the known invalid response is asserted explicitly.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func malformedKnownDispatchFailsBeforeCallbacks() async throws {
        let observations = EventObservations()
        let raw = FixtureEventHandler(handlerID: "raw", selector: GatewayEventSelector<GatewayEvent>.raw) { _, _ in
            await observations.record("raw")
        }
        let typed = FixtureEventHandler(handlerID: "typed", selector: GatewayEventSelector<GatewayDispatch>.all) { _, _ in
            await observations.record("typed")
        }
        let hub = GatewayEventHub(configuration: try .init())
        let compiled = try EventCompilation.compile(BotDefinitionGroup([raw, typed]), intents: [])
        let pipelines = try await compiled.subscribe(to: hub, configuration: .init())
        let run = Task { try await pipelines.run() }
        await hub.publish(try Self.event(name: "MESSAGE_CREATE", data: .object([:])))
        await #expect(throws: DiscordError.transport(.invalidResponse)) { try await run.value }
        #expect(await observations.snapshot().isEmpty)
        #expect(await hub.snapshot().subscriptions == 0)
    }

    /// Raw-only pipelines accept malformed current payloads and control opcodes without projecting a model.
    /// - Throws: Unexpected setup, callback, JSON or ownership failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func rawOnlyObservesMalformedAndControlEnvelopes() async throws {
        let observations = EventObservations()
        let done = TestBarrier()
        let handler = FixtureEventHandler(handlerID: "raw", selector: GatewayEventSelector<GatewayEvent>.raw) { event, context in
            #expect(event.data == context.rawEvent.data)
            #expect(event.opcode == context.rawEvent.opcode)
            await observations.record("\(event.opcode):\(event.sequence!)")
            if event.sequence == 2 { done.open() }
        }
        let hub = GatewayEventHub(configuration: try .init())
        let compiled = try EventCompilation.compile(handler, intents: [])
        let pipelines = try await compiled.subscribe(to: hub, configuration: .init())
        let run = Task { try await pipelines.run() }
        await hub.publish(try Self.event(1, name: "MESSAGE_CREATE", data: .null))
        await hub.publish(try Self.event(2, data: .null, opcode: 11))
        try await done.wait()
        await hub.finish()
        try await run.value
        #expect(await observations.snapshot() == ["0:1", "11:2"])
    }

    /// Built-in selectors preserve concrete model fields, skip unrelated dispatches and leave controls raw.
    /// Custom selection remains an external extension point whose nil result simply skips its callback.
    /// - Throws: Unexpected model, JSON, compilation, fixture or execution errors.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func builtInAndCustomSelectorsPreserveTypedParityAndFiltering() async throws {
        let observations = EventObservations()
        let done = TestBarrier()
        let readyData = try JSONValue.parse(Data(#"{"v":10,"user":{"id":"1","username":"fixture","discriminator":"0","global_name":null,"avatar":null},"guilds":[],"session_id":"offline","resume_gateway_url":"wss://offline.invalid","application":{"id":"1","flags":0}}"#.utf8))
        let createData = try JSONValue.parse(Data(#"{"id":"18446744073709551615","channel_id":"1","author":{"id":"1","username":"fixture","avatar":null},"content":"visible","timestamp":"2026-10-18T00:00:00Z","edited_timestamp":null,"tts":false,"mention_everyone":false,"mentions":[],"mention_roles":[],"attachments":[],"embeds":[],"pinned":false,"type":0}"#.utf8))
        let updateData: JSONValue = .object(["id": .string("18446744073709551615"), "channel_id": .string("1"),
            "future_field": .string("retained")])
        let ready = FixtureEventHandler(handlerID: "ready", selector: GatewayEventSelector<GatewayReady>.ready) { event, _ in
            #expect(event.v == 10)
            #expect(event.user.id.rawValue == 1)
            await observations.record("ready")
        }
        let create = FixtureEventHandler(handlerID: "create", selector: GatewayEventSelector<GatewayMessageCreate>.messageCreate) { event, _ in
            #expect(event.message.id.rawValue == UInt64.max)
            #expect(event.message.content == "visible")
            #expect(event.mentions.isEmpty)
            await observations.record("create")
        }
        let update = FixtureEventHandler(handlerID: "update", selector: GatewayEventSelector<GatewayMessageUpdate>.messageUpdate) { event, _ in
            #expect(event.id.rawValue == UInt64.max)
            #expect(event.content == .absent)
            #expect(event.rawFields["future_field"] == .string("retained"))
            await observations.record("update")
        }
        let resumed = GatewayEventSelector<String>(id: "resumed") { dispatch in
            if case .resumed = dispatch { "resumed" } else { nil }
        }
        let custom = FixtureEventHandler(handlerID: "custom", selector: resumed) { event, _ in
            await observations.record(event)
        }
        let unknown = FixtureEventHandler(handlerID: "unknown", selector: GatewayEventSelector<GatewayUnknownEvent>.unknown) { event, _ in
            #expect(event.name == "FUTURE")
            await observations.record("unknown")
        }
        let raw = FixtureEventHandler(handlerID: "raw", selector: GatewayEventSelector<GatewayEvent>.raw) { event, _ in
            await observations.record("raw:\(event.sequence!)")
            if event.sequence == 6 { done.open() }
        }
        let hub = GatewayEventHub(configuration: try .init())
        let compiled = try EventCompilation.compile(BotDefinitionGroup([ready, create, update, custom, unknown, raw]),
            intents: [.guildMessages, .directMessages])
        let pipelines = try await compiled.subscribe(to: hub, configuration: .init())
        let run = Task { try await pipelines.run() }
        await hub.publish(try Self.event(1, name: "READY", data: readyData))
        await hub.publish(try Self.event(2, name: "MESSAGE_CREATE", data: createData))
        await hub.publish(try Self.event(3, name: "MESSAGE_UPDATE", data: updateData))
        await hub.publish(try Self.event(4))
        await hub.publish(try Self.event(5, name: "FUTURE", data: .null))
        await hub.publish(try Self.event(6, name: "HEARTBEAT_ACK", data: .null, opcode: 11))
        try await done.wait()
        await hub.finish()
        try await run.value
        #expect(await observations.snapshot() == ["ready", "raw:1", "create", "raw:2", "update", "raw:3",
            "resumed", "raw:4", "unknown", "raw:5", "raw:6"])
    }

    /// Original selector errors stop execution before handlers and release all subscription accounting.
    /// - Throws: Unexpected setup errors; the selector's exact application error is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func selectorFailurePropagatesBeforeHandlers() async throws {
        let selector = GatewayEventSelector<GatewayDispatch>(id: "throwing") { _ in throw EventFixtureFailure.selector }
        let handler = FixtureEventHandler(handlerID: "selector", selector: selector) { _, _ in
            Issue.record("Throwing selector invoked handler")
        }
        let hub = GatewayEventHub(configuration: try .init())
        let compiled = try EventCompilation.compile(handler, intents: [])
        let pipelines = try await compiled.subscribe(to: hub, configuration: .init())
        let run = Task { try await pipelines.run() }
        await hub.publish(try Self.event())
        await #expect(throws: EventFixtureFailure.selector) { try await run.value }
        #expect(await hub.snapshot().subscriptions == 0)
    }

    /// A terminal slow-subscriber overflow remains observable instead of silently dropping continuity.
    /// - Throws: Unexpected setup or envelope failures; the exact resynchronization failure is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func overflowPropagatesAndReleasesSubscriptions() async throws {
        let handler = FixtureEventHandler(handlerID: "never", selector: GatewayEventSelector<GatewayEvent>.raw) { _, _ in
            Issue.record("Overflowed buffered event executed")
        }
        let hub = GatewayEventHub(configuration: try .init())
        let compiled = try EventCompilation.compile(handler, intents: [])
        let pipelines = try await compiled.subscribe(to: hub, configuration: .init(), maximumEvents: 1)
        let first = await hub.publish(try Self.event(1))
        let second = await hub.publish(try Self.event(2))
        #expect(first.delivered == 1)
        #expect(second.terminated == 1)
        await #expect(throws: GatewayEventDeliveryFailure.resynchronizationRequired) { try await pipelines.run() }
        #expect(await hub.snapshot().subscriptions == 0)
        #expect(await hub.snapshot().bufferedEvents == 0)
        #expect(await hub.snapshot().bufferedBytes == 0)
    }

    /// A failed callback cancels its concurrently suspended sibling and releases shared aggregate admission.
    /// - Throws: Unexpected setup failures; the callback's exact error survives structured cleanup.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func callbackFailureCancelsSiblingAndCleansAuthority() async throws {
        let waiting = TestBarrier(), blocked = TestBarrier()
        let handler = FixtureEventHandler(handlerID: "throwing", selector: GatewayEventSelector<GatewayEvent>.raw) { event, _ in
            if event.shard.index == 0 {
                waiting.open()
                try await blocked.wait()
            } else {
                try await waiting.wait()
                throw EventFixtureFailure.callback
            }
        }
        let hub = GatewayEventHub(configuration: try .init())
        let authority = try GatewayHandlerAuthority(maximumActiveHandlers: 2)
        let compiled = try EventCompilation.compile(handler, intents: [])
        let pipelines = try await compiled.subscribe(to: hub, configuration: .init(maximumConcurrentHandlers: 2), authority: authority)
        let run = Task { try await pipelines.run() }
        await hub.publish(try Self.event())
        await hub.publish(try Self.event(shard: 1))
        await #expect(throws: EventFixtureFailure.callback) { try await run.value }
        #expect(blocked.waitingCount == 0)
        #expect(await authority.snapshot().activeHandlers == 0)
        #expect(await authority.snapshot().waitingHandlers == 0)
        #expect(await hub.snapshot().subscriptions == 0)
    }

    /// A failure in one independent pipeline promptly cancels another pipeline's suspended callback.
    /// - Throws: Unexpected setup errors; the original application failure remains the exact run outcome.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func independentGroupFailureCancelsOtherGroups() async throws {
        let started = TestBarrier(), blocked = TestBarrier()
        let waiting = FixtureEventHandler(handlerID: "waiting", selector: GatewayEventSelector<GatewayEvent>.raw) { _, _ in
            started.open()
            try await blocked.wait()
        }
        let failing = FixtureEventHandler(handlerID: "failing", selector: GatewayEventSelector<GatewayEvent>.raw,
            eventGroup: "failure") { _, _ in
            try await started.wait()
            throw EventFixtureFailure.callback
        }
        let hub = GatewayEventHub(configuration: try .init())
        let authority = try GatewayHandlerAuthority(maximumActiveHandlers: 2)
        let compiled = try EventCompilation.compile(BotDefinitionGroup([waiting, failing]), intents: [])
        let pipelines = try await compiled.subscribe(to: hub, configuration: .init(), authority: authority)
        let run = Task { try await pipelines.run() }
        defer { run.cancel() }
        await hub.publish(try Self.event())
        await #expect(throws: EventFixtureFailure.callback) { try await run.value }
        #expect(blocked.waitingCount == 0)
        #expect(await hub.snapshot().subscriptions == 0)
        #expect(await authority.snapshot().activeHandlers == 0)
        #expect(await authority.snapshot().waitingHandlers == 0)
    }

    /// Independent groups own separate subscriptions while a shared authority bounds their aggregate callbacks.
    /// - Throws: Unexpected setup, task or fixture errors.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func independentGroupsShareBoundedAdmission() async throws {
        let blocked = TestBarrier(), started = TestBarrier(), done = TestBarrier()
        let observations = EventObservations()
        let first = FixtureEventHandler(handlerID: "default", selector: GatewayEventSelector<GatewayEvent>.raw) { _, _ in
            await observations.record("first")
            started.open()
            try await blocked.wait()
            if await observations.snapshot().count == 2 { done.open() }
        }
        let second = FixtureEventHandler(handlerID: "independent", selector: GatewayEventSelector<GatewayEvent>.raw,
            eventGroup: "secondary") { _, _ in
            await observations.record("second")
            started.open()
            try await blocked.wait()
            if await observations.snapshot().count == 2 { done.open() }
        }
        let hub = GatewayEventHub(configuration: try .init())
        let authority = try GatewayHandlerAuthority(maximumActiveHandlers: 1, maximumWaitingHandlers: 1)
        let compiled = try EventCompilation.compile(BotDefinitionGroup([first, second]), intents: [])
        #expect(compiled.groupIDs.count == 2)
        let pipelines = try await compiled.subscribe(to: hub, configuration: .init(), authority: authority)
        #expect(pipelines.subscriptionCount == 2)
        let run = Task { try await pipelines.run() }
        await hub.publish(try Self.event())
        try await started.wait()
        while await authority.snapshot().waitingHandlers != 1 {
            try Task.checkCancellation()
            await Task.yield()
        }
        #expect(await observations.snapshot().count == 1)
        #expect(await authority.snapshot().activeHandlers == 1)
        blocked.open()
        try await done.wait()
        await hub.finish()
        try await run.value
        #expect(await observations.snapshot().sorted() == ["first", "second"])
        #expect(await authority.snapshot().activeHandlers == 0)
        #expect(await authority.snapshot().waitingHandlers == 0)
        #expect(await hub.snapshot().subscriptions == 0)
    }

    /// A later group subscription failure rolls back every earlier subscription created by the same operation.
    /// - Throws: Unexpected structural or configuration failures; exact metadata exhaustion is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func subscriptionSetupFailureRollsBackEarlierGroups() async throws {
        let first = FixtureEventHandler(handlerID: "one", selector: GatewayEventSelector<GatewayEvent>.raw) { _, _ in }
        let second = FixtureEventHandler(handlerID: "two", selector: GatewayEventSelector<GatewayEvent>.raw,
            eventGroup: "second") { _, _ in }
        let compiled = try EventCompilation.compile(BotDefinitionGroup([first, second]), intents: [])
        let hub = GatewayEventHub(configuration: try .init(maximumSubscriptions: 1))
        await #expect(throws: GatewayEventDeliveryFailure.subscriptionCapacityExceeded) {
            try await compiled.subscribe(to: hub, configuration: .init())
        }
        #expect(await hub.snapshot().subscriptions == 0)
        #expect(await hub.snapshot().bufferedEvents == 0)
    }

    /// Cancellation during a callback cooperatively unwinds its barrier, permit and owned subscription.
    /// - Parameter explicitOwnerCancel: Chooses owner cancellation or cancelling the task awaiting its run.
    /// - Throws: Unexpected setup or fixture failures; cancellation is asserted as the run outcome.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func cancellationDuringRunAndIdempotentCleanup(explicitOwnerCancel: Bool) async throws {
        let started = TestBarrier(), blocked = TestBarrier()
        let handler = FixtureEventHandler(handlerID: "wait", selector: GatewayEventSelector<GatewayEvent>.raw) { _, _ in
            started.open()
            try await blocked.wait()
        }
        let hub = GatewayEventHub(configuration: try .init())
        let authority = try GatewayHandlerAuthority(maximumActiveHandlers: 1)
        let compiled = try EventCompilation.compile(handler, intents: [])
        let pipelines = try await compiled.subscribe(to: hub, configuration: .init(), authority: authority)
        let run = Task { try await pipelines.run() }
        await hub.publish(try Self.event())
        try await started.wait()
        if explicitOwnerCancel { await pipelines.cancel() } else { run.cancel() }
        await #expect(throws: CancellationError.self) { try await run.value }
        await pipelines.cancel()
        await pipelines.cancel()
        #expect(blocked.waitingCount == 0)
        #expect(await authority.snapshot().activeHandlers == 0)
        #expect(await hub.snapshot().subscriptions == 0)
    }

    /// A callback may cancel its own pipeline owner without waiting on itself or retaining an admission permit.
    /// - Throws: Unexpected setup or callback failures; the enclosing run observes cancellation.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func callbackCanCancelItsOwnOwnerWithoutSelfJoin() async throws {
        let reference = EventPipelineReference()
        let observations = EventObservations()
        let handler = FixtureEventHandler(handlerID: "self-cancel", selector: GatewayEventSelector<GatewayEvent>.raw) { _, _ in
            await observations.record("entered")
            await reference.cancel()
            await observations.record("returned")
        }
        let hub = GatewayEventHub(configuration: try .init())
        let authority = try GatewayHandlerAuthority(maximumActiveHandlers: 1)
        let compiled = try EventCompilation.compile(handler, intents: [])
        let pipelines = try await compiled.subscribe(to: hub, configuration: .init(), authority: authority)
        await reference.install(pipelines)
        let run = Task { try await pipelines.run() }
        defer { run.cancel() }
        await hub.publish(try Self.event())
        await #expect(throws: CancellationError.self) { try await run.value }
        #expect(await observations.snapshot() == ["entered", "returned"])
        #expect(await hub.snapshot().subscriptions == 0)
        #expect(await authority.snapshot().activeHandlers == 0)
    }

    /// A task cancelled before run admission invokes no callback and releases its precreated subscription.
    /// - Throws: Unexpected setup errors; cancellation is asserted explicitly.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellationBeforeRunReleasesOwnedSubscriptions() async throws {
        let handler = FixtureEventHandler(handlerID: "never", selector: GatewayEventSelector<GatewayEvent>.raw) { _, _ in
            Issue.record("Precancelled handler executed")
        }
        let hub = GatewayEventHub(configuration: try .init())
        let compiled = try EventCompilation.compile(handler, intents: [])
        let pipelines = try await compiled.subscribe(to: hub, configuration: .init())
        await hub.publish(try Self.event())
        let run = Task {
            while !Task.isCancelled { await Task.yield() }
            try await pipelines.run()
        }
        run.cancel()
        await #expect(throws: CancellationError.self) { try await run.value }
        #expect(await hub.snapshot().subscriptions == 0)
        #expect(await hub.snapshot().bufferedEvents == 0)
    }

    /// The pipeline is single-use, rejects simultaneous ownership and cancels a consumer awaiting input.
    /// - Throws: Unexpected setup or fixture failures; ownership and cancellation errors are asserted exactly.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func concurrentAndRepeatedRunsFailWithSingleOwnership() async throws {
        let handler = DefaultEventHandler()
        let hub = GatewayEventHub(configuration: try .init())
        let compiled = try EventCompilation.compile(handler, intents: [])
        let pipelines = try await compiled.subscribe(to: hub, configuration: .init())
        let run = Task { try await pipelines.run() }
        defer { run.cancel() }
        while await hub.snapshot().waitingConsumers != 1 {
            try Task.checkCancellation()
            await Task.yield()
        }
        await #expect(throws: GatewayEventPipelineFailure.alreadyRun) { try await pipelines.run() }
        await pipelines.cancel()
        await #expect(throws: CancellationError.self) { try await run.value }
        await #expect(throws: GatewayEventPipelineFailure.alreadyRun) { try await pipelines.run() }
        #expect(await hub.snapshot().subscriptions == 0)
    }

    /// Explicit cancellation before first execution retains no buffered event and never invokes a handler.
    /// - Throws: Unexpected setup or fixture errors; run cancellation is asserted explicitly.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func explicitCancellationBeforeRunIsTerminalAndIdempotent() async throws {
        let observations = EventObservations()
        let handler = FixtureEventHandler(handlerID: "never", selector: GatewayEventSelector<GatewayEvent>.raw) { _, _ in
            await observations.record("unexpected")
        }
        let hub = GatewayEventHub(configuration: try .init())
        let compiled = try EventCompilation.compile(handler, intents: [])
        let pipelines = try await compiled.subscribe(to: hub, configuration: .init())
        await hub.publish(try Self.event())
        await pipelines.cancel()
        await pipelines.cancel()
        await #expect(throws: CancellationError.self) { try await pipelines.run() }
        #expect(await observations.snapshot().isEmpty)
        #expect(await hub.snapshot().subscriptions == 0)
        #expect(await hub.snapshot().bufferedEvents == 0)
    }
}
