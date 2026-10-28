// File: Tests/DiscordDSLTests/DefinitionTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordDSL
import Synchronization
import Testing

/// Records only explicitly invoked extension work, independently of synchronous plan collection.
private actor DefinitionWorkCounter {
    private var value = 0

    /// Records one invocation after a test explicitly executes a retained contribution.
    func record() { value += 1 }

    /// Returns the complete invocation count without starting additional work.
    /// - Returns: Number of explicit calls to `record` in this test fixture.
    func snapshot() -> Int { value }
}

/// Makes synchronous getter observations safely visible without introducing tasks during compilation.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private final class DefinitionSynchronousCounter: Sendable {
    private let value = Mutex(0)

    /// Records one synchronous getter evaluation under the fixture's sole lock.
    func record() { value.withLock { $0 += 1 } }

    /// Returns the number of evaluations completed before this assertion.
    /// - Returns: Exact synchronous callback count.
    func snapshot() -> Int { value.withLock { $0 } }
}

/// Exposes an observable metadata getter while retaining an ordinary external contribution conformance.
private struct ObservedDefinitionContribution: DefinitionContribution {
    let read: @Sendable () -> RawDefinitionContribution

    /// Produces the immutable declaration snapshot and records this getter's explicit evaluation.
    var declaration: RawDefinitionContribution { read() }
}

/// Exposes an observable module body getter, evaluated only after module admission.
private struct ObservedDefinitionModule: BotModule {
    let moduleID: String
    let sourceLocation: DefinitionSourceLocation
    let observed: @Sendable () -> Void

    /// Records body evaluation and returns an empty bounded definition without invoking runtime work.
    @BotBuilder var body: some BotDefinition {
        let _ = observed()
        EmptyBotDefinition(source: sourceLocation)
    }
}

/// Demonstrates that external contribution types retain their own executable behavior and metadata.
private struct ExternalDefinitionContribution: DefinitionContribution {
    let declaration: RawDefinitionContribution
    let work: @Sendable () async -> Void
}

/// Uses the associated body requirement directly, without macros or a closed declaration enumeration.
private struct ExplicitDefinitionModule: BotModule {
    let moduleID: String
    let sourceLocation: DefinitionSourceLocation
    let body: BotDefinitionGroup
}

/// Relies on the protocol's honest unknown-source fallback for a handwritten module.
private struct UnlocatedDefinitionModule: BotModule {
    let moduleID = "unlocated"

    /// Returns an empty structural body without inventing a source coordinate for this module.
    @BotBuilder var body: some BotDefinition {}
}

/// Deterministic errors used to verify propagation of third-party collection failures.
private enum DefinitionFixtureError: Error, Equatable {
    case expected
    case missingFailure
}

/// Throws during synchronous collection so compilation cannot return a partial plan.
private struct FailingDefinition: BotDefinition {
    /// Stops collection with the fixture's original error before admitting any declarations.
    /// - Parameter collector: Caller-owned collector, left untouched by this fixture.
    /// - Throws: `DefinitionFixtureError.expected` on every call.
    func collect(into collector: inout DefinitionCollector) throws {
        throw DefinitionFixtureError.expected
    }
}

/// Attempts to hide a collector admission error, which must still poison the final compilation.
private struct SwallowingDefinition: BotDefinition {
    let contribution: RawDefinitionContribution
    var throwAfterFailure = false

    /// Catches append failure to verify the collector retains its first terminal diagnostic.
    /// - Parameter collector: Caller-owned collector whose sticky failure must survive this catch.
    /// - Throws: An unrelated fixture error when requested, which cannot replace the first collector failure.
    func collect(into collector: inout DefinitionCollector) throws {
        do { try collector.append(contribution) } catch {}
        if throwAfterFailure { throw DefinitionFixtureError.expected }
    }
}

/// Attempts to hide an arbitrary body failure, which cannot produce a valid partial plan.
private struct SwallowingBodyDefinition: BotDefinition {
    /// Catches a body error after opening a scope; compilation must propagate the original error.
    /// - Parameter collector: Collector whose scope cleanup and sticky failure are exercised.
    func collect(into collector: inout DefinitionCollector) throws {
        do {
            try collector.withStructure { _ in throw DefinitionFixtureError.expected }
        } catch {}
    }
}

/// Expands only through the public structural hook, allowing exact finite recursion-budget tests.
private struct RecursiveDefinition: BotDefinition {
    let remaining: Int
    let source: DefinitionSourceLocation

    /// Visits one structural node and recursively visits exactly `remaining` additional nodes.
    /// - Parameter collector: Shared collector whose depth and structural budgets gate expansion.
    /// - Throws: The collector's diagnostic when the next node exceeds a configured budget.
    func collect(into collector: inout DefinitionCollector) throws {
        try collector.withStructure(source: source) { nested in
            if remaining > 0 {
                try RecursiveDefinition(remaining: remaining - 1, source: source).collect(into: &nested)
            }
        }
    }
}

/// Exercises the public, macro-free authoring contract with deterministic local values and no runtime I/O.
@Suite struct DefinitionTests {
    private static let source = DefinitionSourceLocation(fileID: "Fixtures/Definition.swift", line: 12, column: 4)

    /// Captures one expected structural failure without allowing an unrelated error to satisfy the assertion.
    /// - Parameter operation: Synchronous compilation expected to produce a `DefinitionDiagnostic`.
    /// - Returns: The exact diagnostic for structured code, source and path assertions.
    /// - Throws: An unexpected compiler error, or `DefinitionFixtureError.missingFailure` after recording success as a failure.
    private static func failure(_ operation: () throws -> DefinitionPlan) throws -> DefinitionDiagnostic {
        do {
            _ = try operation()
            Issue.record("Expected definition compilation to fail")
            throw DefinitionFixtureError.missingFailure
        } catch let diagnostic as DefinitionDiagnostic {
            return diagnostic
        }
    }

    /// Creates a small, explicitly located raw leaf whose kind can be opted into by the test compiler.
    /// - Parameters:
    ///   - id: Stable leaf identity, validated during compilation rather than construction.
    ///   - text: Literal metadata retained byte-for-byte; defaults to an empty value.
    ///   - payload: Opaque semantic JSON metadata; defaults to the four-byte JSON `null` value.
    /// - Returns: An inert raw contribution with the fixture's shared explicit source location.
    private static func raw(_ id: String, text: String = "", payload: JSONValue = .null) -> RawDefinitionContribution {
        RawDefinitionContribution(id: id, kind: "test", text: text, payload: payload, source: source)
    }

    /// Empty definitions and empty result-builder blocks produce reproducible plans without declarations.
    /// All-zero admission counts remain useful for empty descriptions when the structural budget admits the root.
    /// - Throws: Unexpected compilation failures for valid empty fixtures.
    @Test func emptyDefinitionsAndDefaults() throws {
        let empty = EmptyBotDefinition(source: Self.source)
        let plan = try DefinitionPlan.compile(empty)
        #expect(plan.description.modules.isEmpty)
        #expect(plan.description.declarations.isEmpty)
        #expect(plan.contributions.isEmpty)
        #expect(plan.description.structureCount == 1)
        #expect(try DefinitionPlan.compile(empty).description == plan.description)
        let limits = DefinitionLimits(maxModules: 0, maxDeclarations: 0, maxTextBytes: 0, maxStructuralNodes: 1)
        #expect(try DefinitionPlan.compile(empty, limits: limits).description.declarations.isEmpty)
        let module = Module(id: "empty", source: Self.source) {}
        let modulePlan = try DefinitionPlan.compile(module)
        #expect(modulePlan.description.modules.map(\.id) == ["empty"])
        #expect(modulePlan.description.declarations.isEmpty)
        let unlocated = try DefinitionPlan.compile(UnlocatedDefinitionModule())
        #expect(unlocated.description.modules.first?.source == DefinitionSourceLocation(fileID: "<unknown>", line: 0, column: 0))
        #expect(DefinitionLimits() == DefinitionLimits(maxModules: 256, maxDepth: 32, maxDeclarations: 4_096,
            maxTextBytes: 1_048_576, maxStructuralNodes: 16_384))
    }

    /// Builder branches, homogeneous/existential arrays and finite loops retain source declaration order.
    /// Both conditional alternatives and both optional outcomes are exercised without executing handlers.
    /// - Parameter includeOptional: Selects the conditional branch and presence of an optional declaration.
    /// - Throws: Unexpected valid compilation failures.
    @Test(arguments: [false, true]) func builderOrder(includeOptional: Bool) throws {
        let homogeneous = [Self.raw("array-a"), Self.raw("array-b")]
        let heterogeneous: [any BotDefinition] = [Self.raw("existential"), EmptyBotDefinition(source: Self.source)]
        let module = Module(id: "root", source: Self.source) {
            Self.raw("first")
            homogeneous
            heterogeneous
            if includeOptional { Self.raw("optional") }
            if includeOptional { Self.raw("then") } else { Self.raw("else") }
            if #available(macOS 13, iOS 16, tvOS 16, watchOS 9, visionOS 1, *) { Self.raw("available") }
            for index in 0..<3 { Self.raw("loop-\(index)") }
            for _ in 0..<0 { Self.raw("never") }
            [RawDefinitionContribution]()
            [any BotDefinition]()
        }
        let plan = try DefinitionPlan.compile(module, supportedKinds: ["test"])
        let expected = ["first", "array-a", "array-b", "existential"]
            + (includeOptional ? ["optional", "then"] : ["else"])
            + ["available", "loop-0", "loop-1", "loop-2"]
        #expect(plan.description.declarations.map { $0.declaration.id } == expected)
        #expect(plan.description.declarations.allSatisfy { $0.modulePath == ["root"] })
        #expect(plan.contributions.map { $0.declaration.id } == expected)
        #expect(try DefinitionPlan.compile(module, supportedKinds: ["test"]).description == plan.description)
    }

    /// Explicit protocol modules and nested convenience modules retain preorder module paths and exact sources.
    /// - Throws: Unexpected valid compilation failures.
    @Test func explicitModulesAndNestedSources() throws {
        let innerSource = DefinitionSourceLocation(fileID: "Fixtures/Nested.swift", line: 44, column: 2)
        let inner = Module(id: "inner", source: innerSource) { Self.raw("inside") }
        let outer = ExplicitDefinitionModule(moduleID: "outer", sourceLocation: Self.source,
            body: BotDefinitionGroup([Self.raw("before"), inner, Self.raw("after")], source: Self.source))
        let plan = try DefinitionPlan.compile(outer, supportedKinds: ["test"])
        #expect(plan.description.modules.map(\.id) == ["outer", "inner"])
        #expect(plan.description.modules.map(\.path) == [["outer"], ["outer", "inner"]])
        #expect(plan.description.modules.map(\.source) == [Self.source, innerSource])
        #expect(plan.description.declarations.map { $0.declaration.id } == ["before", "inside", "after"])
        #expect(plan.description.declarations.map(\.modulePath) == [["outer"], ["outer", "inner"], ["outer"]])
        #expect(plan.description.declarations.allSatisfy { $0.declaration.source == Self.source })
    }

    /// Construction and compilation preserve an external contribution without invoking its injected runtime work.
    /// Explicit execution after compilation proves that the retained typed value, rather than a metadata surrogate, survives.
    /// - Throws: Unexpected compilation or required-cast failures.
    @Test func externalContributionsRemainInertAndTyped() async throws {
        let counter = DefinitionWorkCounter()
        let contribution = ExternalDefinitionContribution(declaration: Self.raw("external"), work: { await counter.record() })
        let module = Module(id: "external-module", source: Self.source) { contribution }
        #expect(await counter.snapshot() == 0)
        let plan = try DefinitionPlan.compile(module, supportedKinds: ["test"])
        #expect(await counter.snapshot() == 0)
        #expect(plan.description.declarations.map { $0.declaration } == [contribution.declaration])
        let retained = try #require(plan.contributions.first as? ExternalDefinitionContribution)
        await retained.work()
        #expect(await counter.snapshot() == 1)
    }

    /// Raw metadata remains lossless for Unicode, future fields, large exact numbers and capability sets.
    /// The root convenience initializer captures usable compiler source metadata without requiring a macro.
    /// - Throws: Unexpected numeric construction or compilation failures.
    @Test func rawPayloadAndAutomaticSource() throws {
        let payload: JSONValue = .object(["future": .array([.null, .bool(true), .string("雪🐶"),
            .number(try JSONNumber(rawValue: "1844674407370955161618446744073709551616"))])])
        let leaf = RawDefinitionContribution(id: "raw", kind: "future-kind", requiredCapabilities: ["read", "write"],
            text: "é\n🐶", payload: payload)
        let module = Module(id: "captured") { leaf }
        let plan = try DefinitionPlan.compile(module, supportedKinds: ["future-kind"], capabilities: ["read", "write", "extra"])
        #expect(plan.description.declarations.first?.declaration == leaf)
        #expect(plan.description.declarations.first?.declaration.payload == payload)
        #expect(leaf.source.fileID.hasSuffix("DefinitionTests.swift"))
        #expect(leaf.source.line > 0)
        #expect(leaf.source.column > 0)
        #expect(plan.description.modules.first?.source.fileID.hasSuffix("DefinitionTests.swift") == true)
    }

    /// Every invalid configuration fails before expanding a user definition, including unsafe hard depth limits.
    /// - Parameter limits: A negative count/byte budget or depth outside the supported `1...128` range.
    /// - Throws: Unexpected diagnostic-capture failures.
    @Test(arguments: [DefinitionLimits(maxModules: -1), DefinitionLimits(maxDepth: 0), DefinitionLimits(maxDepth: -1),
        DefinitionLimits(maxDepth: 129), DefinitionLimits(maxDeclarations: -1), DefinitionLimits(maxTextBytes: -1),
        DefinitionLimits(maxStructuralNodes: -1)])
    func invalidLimitsPrecedeCollection(limits: DefinitionLimits) throws {
        let error = try Self.failure { try DefinitionPlan.compile(FailingDefinition(), limits: limits) }
        #expect(error.code == .invalidLimits)
    }

    /// Module admission succeeds at the exact total limit and fails before admitting one additional module.
    /// - Throws: Unexpected valid compilation or diagnostic-capture failures.
    @Test func moduleCountBoundary() throws {
        let definition = Module(id: "outer", source: Self.source) {
            Module(id: "inner", source: Self.source) {}
        }
        #expect(try DefinitionPlan.compile(definition, limits: DefinitionLimits(maxModules: 2)).description.modules.count == 2)
        let error = try Self.failure { try DefinitionPlan.compile(definition, limits: DefinitionLimits(maxModules: 1)) }
        #expect(error.code == .moduleLimit)
        #expect(error.source == Self.source)
        #expect(error.modulePath.contains("outer"))
        #expect(try Self.failure {
            try DefinitionPlan.compile(Module(id: "one", source: Self.source) {}, limits: DefinitionLimits(maxModules: 0))
        }.code == .moduleLimit)
    }

    /// Declaration admission counts all flattened leaves, including leaves within distinct nested modules.
    /// - Throws: Unexpected valid compilation or diagnostic-capture failures.
    @Test func declarationCountBoundary() throws {
        let definition = BotDefinitionGroup([Self.raw("one"), Self.raw("two")], source: Self.source)
        #expect(try DefinitionPlan.compile(definition, supportedKinds: ["test"],
            limits: DefinitionLimits(maxDeclarations: 2)).description.declarations.count == 2)
        let error = try Self.failure {
            try DefinitionPlan.compile(definition, supportedKinds: ["test"], limits: DefinitionLimits(maxDeclarations: 1))
        }
        #expect(error.code == .declarationLimit)
        #expect(error.source.fileID == "<contribution>")
        #expect(try Self.failure {
            try DefinitionPlan.compile(Self.raw("one"), supportedKinds: ["test"], limits: DefinitionLimits(maxDeclarations: 0))
        }.code == .declarationLimit)
    }

    /// Structural nodes include empty groups and extension expansion, preventing declaration-free recursion from escaping bounds.
    /// - Throws: Unexpected valid compilation or diagnostic-capture failures.
    @Test func structuralCountBoundary() throws {
        let definition = BotDefinitionGroup([EmptyBotDefinition(source: Self.source), EmptyBotDefinition(source: Self.source)],
            source: Self.source)
        let plan = try DefinitionPlan.compile(definition, limits: DefinitionLimits(maxStructuralNodes: 3))
        #expect(plan.description.structureCount == 3)
        #expect(try Self.failure {
            try DefinitionPlan.compile(definition, limits: DefinitionLimits(maxStructuralNodes: 2))
        }.code == .structureLimit)
        #expect(try Self.failure {
            try DefinitionPlan.compile(EmptyBotDefinition(source: Self.source), limits: DefinitionLimits(maxStructuralNodes: 0))
        }.code == .structureLimit)
    }

    /// Custom structural expansion respects the exact configured depth, including the supported hard ceiling.
    /// - Parameter depth: Representative minimum, default and maximum structural depths.
    /// - Throws: Unexpected valid compilation or diagnostic-capture failures.
    @Test(arguments: [1, 32, 128]) func structuralDepthBoundary(depth: Int) throws {
        let limits = DefinitionLimits(maxDepth: depth)
        let plan = try DefinitionPlan.compile(RecursiveDefinition(remaining: depth - 1, source: Self.source), limits: limits)
        #expect(plan.description.structureCount == depth)
        #expect(try Self.failure {
            try DefinitionPlan.compile(RecursiveDefinition(remaining: depth, source: Self.source), limits: limits)
        }.code == .depthLimit)
    }

    /// Text accounting uses UTF-8 and compact JSON bytes, including IDs, capabilities and explicit source file IDs.
    /// An exact bound succeeds and one fewer byte fails without confusing Unicode character counts with byte counts.
    /// - Throws: Unexpected valid compilation or diagnostic-capture failures.
    @Test func textByteBoundaryAndAccounting() throws {
        let source = DefinitionSourceLocation(fileID: "é", line: 1, column: 1)
        let leaf = RawDefinitionContribution(id: "leaf", kind: "test", requiredCapabilities: ["read"], text: "🐶\n",
            payload: .object(["k": .string("雪")]), source: source)
        let definition = Module(id: "root", source: source) { leaf }
        let payloadBytes = try leaf.payload.serialized().count
        let expected = ["root", "é", "leaf", "test", "read", "🐶\n", "é"].reduce(0) { $0 + $1.utf8.count } + payloadBytes
        let plan = try DefinitionPlan.compile(definition, supportedKinds: ["test"], capabilities: ["read"],
            limits: DefinitionLimits(maxTextBytes: expected))
        #expect(plan.description.textBytes == expected)
        #expect(try Self.failure {
            try DefinitionPlan.compile(definition, supportedKinds: ["test"], capabilities: ["read"],
                limits: DefinitionLimits(maxTextBytes: expected - 1))
        }.code == .textLimit)
    }

    /// Opaque JSON must satisfy finite depth and node bounds even when the surrounding definition has only one leaf.
    /// - Throws: Unexpected diagnostic-capture failures.
    @Test func oversizedOpaquePayloads() throws {
        var payload = JSONValue.null
        for _ in 0..<64 { payload = .array([payload]) }
        #expect(try DefinitionPlan.compile(Self.raw("exact-depth", payload: payload), supportedKinds: ["test"])
            .description.declarations.count == 1)
        payload = .array([payload])
        #expect(try Self.failure {
            try DefinitionPlan.compile(Self.raw("deep", payload: payload), supportedKinds: ["test"])
        }.code == .invalidPayload)
        #expect(try DefinitionPlan.compile(Self.raw("exact-nodes", payload: .array(Array(repeating: .null, count: 99_999))),
            supportedKinds: ["test"]).description.declarations.count == 1)
        #expect(try Self.failure {
            try DefinitionPlan.compile(Self.raw("many", payload: .array(Array(repeating: .null, count: 100_000))),
                supportedKinds: ["test"])
        }.code == .invalidPayload)
        let oversized = JSONValue.string(String(repeating: "x", count: 100))
        #expect(try Self.failure {
            try DefinitionPlan.compile(Self.raw("large", payload: oversized), supportedKinds: ["test"],
                limits: DefinitionLimits(maxTextBytes: 64))
        }.code == .textLimit)
    }

    /// Every JSON category uses the serializer's exact byte count, including escaping expansion beyond raw UTF-8.
    /// A payload fitting the complete metadata budget succeeds; one byte less fails before any plan is returned.
    /// - Parameter json: Valid representative wire JSON, including future exact numeric spellings and escaped object keys.
    /// - Throws: Unexpected fixture parsing, serialization, valid compilation or diagnostic-capture failures.
    @Test(arguments: ["null", "true", "false", "1844674407370955161618446744073709551616", "-1.2300e+999",
        #""雪🐶\n\t\\\"""#, "[]", "[null,true,false]", "{}", #"{"雪\n":"🐶\t","z":[null,false]}"#])
    func exactPayloadByteBoundary(json: String) throws {
        let payload = try JSONValue.parse(json)
        let declaration = Self.raw("payload", payload: payload)
        let metadataBytes = [declaration.id, declaration.kind, declaration.source.fileID]
            .reduce(0) { $0 + $1.utf8.count }
        let expectedBytes = metadataBytes + (try payload.serialized().count)
        let plan = try DefinitionPlan.compile(declaration, supportedKinds: ["test"],
            limits: DefinitionLimits(maxTextBytes: expectedBytes))
        #expect(plan.description.textBytes == expectedBytes)
        #expect(plan.description.declarations.first?.declaration.payload == payload)
        #expect(try Self.failure {
            try DefinitionPlan.compile(declaration, supportedKinds: ["test"],
                limits: DefinitionLimits(maxTextBytes: expectedBytes - 1))
        }.code == .textLimit)
    }

    /// Oversized caller-allocated string values and object keys fail the same bounded payload byte admission.
    /// - Parameter asObjectKey: Selects an oversized dictionary key instead of an oversized scalar value.
    /// - Throws: Unexpected diagnostic-capture failures.
    @Test(arguments: [false, true]) func oversizedPayloadTextAndKeys(asObjectKey: Bool) throws {
        let enormous = String(repeating: "雪🐶", count: 1_024)
        let payload: JSONValue = asObjectKey ? .object([enormous: .null]) : .string(enormous)
        let error = try Self.failure {
            try DefinitionPlan.compile(Self.raw("oversized", payload: payload), supportedKinds: ["test"],
                limits: DefinitionLimits(maxTextBytes: 128))
        }
        #expect(error.code == .textLimit)
        #expect(error.source == Self.source)
    }

    /// Invalid JSON shape takes priority over an oversized sibling regardless of unordered dictionary traversal.
    /// Both object-depth expansion and aggregate descendant count remain bounded before serialization or key sorting.
    /// - Throws: Unexpected diagnostic-capture failures.
    @Test func invalidPayloadShapePrecedesTextAdmission() throws {
        var deeplyNested = JSONValue.null
        for _ in 0..<65 { deeplyNested = .object(["child": deeplyNested]) }
        let oversizedSibling = JSONValue.string(String(repeating: "x", count: 4_096))
        for payload in [JSONValue.object(["a": deeplyNested, "z": oversizedSibling]),
            .object(["a": oversizedSibling, "z": deeplyNested])] {
            #expect(try Self.failure {
                try DefinitionPlan.compile(Self.raw("shape", payload: payload), supportedKinds: ["test"],
                    limits: DefinitionLimits(maxTextBytes: 128))
            }.code == .invalidPayload)
        }
        let descendants = JSONValue.array(Array(repeating: .array([.null]), count: 50_000))
        #expect(try Self.failure {
            try DefinitionPlan.compile(Self.raw("descendants", payload: descendants), supportedKinds: ["test"])
        }.code == .invalidPayload)
        let object = JSONValue.object(Dictionary(uniqueKeysWithValues: (0..<100_000).map { ("key-\($0)", JSONValue.null) }))
        #expect(try Self.failure {
            try DefinitionPlan.compile(Self.raw("object-nodes", payload: object), supportedKinds: ["test"])
        }.code == .invalidPayload)
    }

    /// Stable module IDs are globally unique, including when duplicate instances occur in separate branches.
    /// - Throws: Unexpected diagnostic-capture failures.
    @Test func duplicateModuleIdentity() throws {
        let definition = Module(id: "root", source: Self.source) {
            Module(id: "duplicate", source: Self.source) {}
            Module(id: "duplicate", source: Self.source) {}
        }
        let error = try Self.failure { try DefinitionPlan.compile(definition) }
        #expect(error.code == .duplicateModuleID)
        #expect(error.source == Self.source)
        #expect(error.modulePath.contains("root"))
    }

    /// Leaf identities remain unique across module paths so future lowering cannot silently overwrite a contribution.
    /// - Throws: Unexpected diagnostic-capture failures.
    @Test func duplicateDeclarationIdentity() throws {
        let definition = Module(id: "root", source: Self.source) {
            Module(id: "a", source: Self.source) { Self.raw("duplicate") }
            Module(id: "b", source: Self.source) { Self.raw("duplicate") }
        }
        let error = try Self.failure { try DefinitionPlan.compile(definition, supportedKinds: ["test"]) }
        #expect(error.code == .duplicateDeclarationID)
        #expect(error.source == Self.source)
        #expect(error.modulePath == ["root", "b"])
    }

    /// Missing kind or host capability support fails closed at the leaf's explicit source and containing path.
    /// - Throws: Unexpected valid compilation or diagnostic-capture failures.
    @Test func unsupportedKindsAndCapabilities() throws {
        let contribution = RawDefinitionContribution(id: "leaf", kind: "extension", requiredCapabilities: ["read", "write"],
            source: Self.source)
        let definition = Module(id: "root", source: Self.source) { contribution }
        let unsupportedKind = try Self.failure { try DefinitionPlan.compile(definition) }
        #expect(unsupportedKind.code == .unsupportedKind)
        #expect(unsupportedKind.source == Self.source)
        #expect(unsupportedKind.modulePath == ["root"])
        let unsupportedCapability = try Self.failure {
            try DefinitionPlan.compile(definition, supportedKinds: ["extension"], capabilities: ["read"])
        }
        #expect(unsupportedCapability.code == .unsupportedCapability)
        #expect(unsupportedCapability.source == Self.source)
        #expect(unsupportedCapability.modulePath == ["root"])
        #expect(try DefinitionPlan.compile(definition, supportedKinds: ["extension"], capabilities: ["read", "write"])
            .description.declarations.count == 1)
    }

    /// Empty or control-containing identities cannot enter module, declaration, kind or capability namespaces.
    /// - Parameter identity: An invalid identity whose rejection must remain synchronous and source-located.
    /// - Throws: Unexpected diagnostic-capture failures.
    @Test(arguments: ["", "\n", "invalid\u{0000}identity", "invalid\u{007f}identity", String(repeating: "x", count: 129)])
    func invalidIdentities(identity: String) throws {
        #expect(try Self.failure { try DefinitionPlan.compile(Module(id: identity, source: Self.source) {}) }.code == .invalidIdentity)
        #expect(try Self.failure {
            try DefinitionPlan.compile(Self.raw(identity), supportedKinds: ["test"])
        }.code == .invalidIdentity)
        #expect(try Self.failure {
            try DefinitionPlan.compile(RawDefinitionContribution(id: "leaf", kind: identity, source: Self.source), supportedKinds: [identity])
        }.code == .invalidIdentity)
        #expect(try Self.failure {
            try DefinitionPlan.compile(RawDefinitionContribution(id: "leaf", kind: "test", requiredCapabilities: [identity],
                source: Self.source), supportedKinds: ["test"], capabilities: [identity])
        }.code == .invalidIdentity)
    }

    /// Extremely long invalid metadata produces bounded diagnostics instead of echoing user-provided declaration text.
    /// - Throws: Unexpected diagnostic-capture failures.
    @Test func diagnosticsStayBounded() throws {
        let enormous = String(repeating: "sensitive", count: 10_000)
        let source = DefinitionSourceLocation(fileID: enormous, line: .max, column: .max)
        let error = try Self.failure {
            try DefinitionPlan.compile(RawDefinitionContribution(id: "", kind: "test", text: enormous, source: source),
                supportedKinds: ["test"])
        }
        #expect(error.code == .invalidIdentity)
        #expect(error.source.fileID.utf8.count <= 256)
        #expect(String(describing: error).utf8.count <= 2_048)
        #expect(!String(describing: error).contains(enormous))
        let splitSource = DefinitionSourceLocation(fileID: String(repeating: "a", count: 255) + "é", line: 8, column: 3)
        let splitIdentity = String(repeating: "a", count: 127) + "é"
        let bounded = DefinitionDiagnostic(code: .invalidIdentity, source: splitSource,
            modulePath: Array(repeating: splitIdentity, count: 200))
        #expect(bounded.source.fileID == String(repeating: "a", count: 255))
        #expect(bounded.source.fileID.utf8.count <= 256)
        #expect(bounded.source.line == 8 && bounded.source.column == 3)
        #expect(bounded.modulePath.count == 128)
        #expect(bounded.modulePath.allSatisfy { $0 == String(repeating: "a", count: 127) && $0.utf8.count <= 128 })
        let exactUnicode = DefinitionSourceLocation(fileID: String(repeating: "é", count: 128), line: 0, column: 0)
        #expect(DefinitionDiagnostic(code: .textLimit, source: exactUnicode, modulePath: []).source == exactUnicode)
    }

    /// UTF-8 identity validation admits the exact 128-byte boundary without imposing an ASCII-only namespace.
    /// - Parameter identity: An ASCII or Unicode identity at the exact maximum byte count.
    /// - Throws: Unexpected valid compilation failures.
    @Test(arguments: [String(repeating: "x", count: 128), String(repeating: "é", count: 64)])
    func identityByteBoundary(identity: String) throws {
        let definition = Module(id: identity, source: Self.source) { Self.raw(identity) }
        let plan = try DefinitionPlan.compile(definition, supportedKinds: ["test"])
        #expect(plan.description.modules.first?.id == identity)
        #expect(plan.description.declarations.first?.declaration.id == identity)
    }

    /// Count admission precedes custom declaration getters, and each admitted metadata snapshot is read exactly once.
    /// - Throws: Unexpected valid compilation or diagnostic-capture failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func declarationGettersRespectAdmission() throws {
        let first = DefinitionSynchronousCounter()
        let second = DefinitionSynchronousCounter()
        let one = ObservedDefinitionContribution(read: { first.record(); return Self.raw("one") })
        let two = ObservedDefinitionContribution(read: { second.record(); return Self.raw("two") })
        let definition = BotDefinitionGroup([one, two], source: Self.source)
        #expect(try Self.failure {
            try DefinitionPlan.compile(definition, supportedKinds: ["test"], limits: DefinitionLimits(maxDeclarations: 1))
        }.code == .declarationLimit)
        #expect(first.snapshot() == 1)
        #expect(second.snapshot() == 0)
        let plan = try DefinitionPlan.compile(two, supportedKinds: ["test"])
        #expect(plan.description.declarations.first?.declaration.id == "two")
        #expect(second.snapshot() == 1)
    }

    /// Module count and depth failures stop expansion before evaluating the rejected module's arbitrary body getter.
    /// - Throws: Unexpected diagnostic-capture failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func moduleBodiesRespectAdmission() throws {
        let counter = DefinitionSynchronousCounter()
        let module = ObservedDefinitionModule(moduleID: "observed", sourceLocation: Self.source, observed: { counter.record() })
        #expect(try Self.failure {
            try DefinitionPlan.compile(module, limits: DefinitionLimits(maxModules: 0))
        }.code == .moduleLimit)
        #expect(counter.snapshot() == 0)
        #expect(try Self.failure {
            try DefinitionPlan.compile(BotDefinitionGroup([module], source: Self.source), limits: DefinitionLimits(maxDepth: 1))
        }.code == .depthLimit)
        #expect(counter.snapshot() == 0)
        #expect(try DefinitionPlan.compile(module).description.modules.count == 1)
        #expect(counter.snapshot() == 1)
    }

    /// Custom extensions cannot turn swallowed admission or expansion failures into successful partial plans.
    /// - Throws: Unexpected diagnostic-capture failures.
    @Test func swallowedCollectionFailuresRemainTerminal() throws {
        #expect(try Self.failure {
            try DefinitionPlan.compile(SwallowingDefinition(contribution: Self.raw("unsupported")))
        }.code == .unsupportedKind)
        #expect(try Self.failure {
            try DefinitionPlan.compile(SwallowingDefinition(contribution: Self.raw("unsupported"), throwAfterFailure: true))
        }.code == .unsupportedKind)
        #expect(throws: DefinitionFixtureError.expected) { try DefinitionPlan.compile(SwallowingBodyDefinition()) }
    }

    /// Maximum representable integer budgets remain valid without arithmetic overflow while admitting a small fixture.
    /// - Throws: Unexpected compilation failures for positive, representable non-depth budgets.
    @Test func maximumIntegerBudgets() throws {
        let limits = DefinitionLimits(maxModules: .max, maxDepth: 128, maxDeclarations: .max, maxTextBytes: .max,
            maxStructuralNodes: .max)
        let definition = Module(id: "root", source: Self.source) { Self.raw("leaf") }
        let plan = try DefinitionPlan.compile(definition, supportedKinds: ["test"], limits: limits)
        #expect(plan.description.modules.count == 1)
        #expect(plan.description.declarations.count == 1)
    }

    /// Third-party synchronous expansion errors propagate unchanged and never return an apparently valid partial plan.
    /// - Throws: Unexpected fixture construction failures.
    @Test func collectionErrorsPropagate() throws {
        let definition = Module(id: "root", source: Self.source) {
            Self.raw("before")
            FailingDefinition()
            Self.raw("after")
        }
        #expect(throws: DefinitionFixtureError.expected) { try DefinitionPlan.compile(definition, supportedKinds: ["test"]) }
    }
}
