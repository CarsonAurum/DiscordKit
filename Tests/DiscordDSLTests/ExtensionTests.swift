// File: Tests/DiscordDSLTests/ExtensionTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordDSL
import Synchronization
import Testing

/// Records only explicit handler invocation after a typed extension has been retained.
private actor ExtensionService {
    private var invocations = 0

    /// Records one explicit use; compilation never calls this asynchronous operation.
    func execute() { invocations += 1 }

    /// Returns the number of executions already owned by the test.
    /// - Returns: Exact invocation count, initially zero.
    func count() -> Int { invocations }
}

/// Safely observes synchronous validation/factory ordering without creating background work.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private final class ExtensionObservations: Sendable {
    private let values = Mutex<[String]>([])

    /// Appends one fixture observation under its sole lock.
    /// - Parameter value: Nonsecret test label in exact synchronous visitation order.
    func append(_ value: String) { values.withLock { $0.append(value) } }

    /// Copies observations completed before the assertion.
    /// - Returns: Deterministically ordered labels; empty when no callback ran.
    func snapshot() -> [String] { values.withLock { $0 } }
}

/// Carries a deliberately sensitive validation error that must never escape compilation.
private struct ExtensionDependencyError: Error {
    let secret: String
}

/// Demonstrates finite configuration plus an explicitly injected service reference.
private struct ExtensionDependencies: ModuleDependencies {
    let configured: Bool
    let service: ExtensionService
    let observeValidation: @Sendable () -> Void

    /// Checks only the local flag and records validation without calling the injected actor.
    /// - Throws: A deliberately secret-bearing fixture error when configuration is unavailable.
    func validate() throws {
        observeValidation()
        guard configured else { throw ExtensionDependencyError(secret: "never-display-private-token") }
    }
}

/// Retains an injected actor reference beside inert external metadata without service discovery.
private struct ExtensionAction: DefinitionContribution {
    let declaration: RawDefinitionContribution
    let service: ExtensionService
}

/// Exercises the public namespace hook independently of the convenience builder wrapper.
private struct DirectExtensionNamespace: BotDefinition {
    let id: String
    let source: DefinitionSourceLocation
    let child: any BotDefinition

    /// Opens a common bounded namespace before collecting the external child.
    /// - Parameter collector: Exclusive state sharing the same identity and admission authorities.
    /// - Throws: Namespace admission or the child's error, without rewriting child metadata.
    func collect(into collector: inout DefinitionCollector) throws {
        try collector.withNamespace(id: id, source: source) { nested in
            try child.collect(into: &nested)
        }
    }
}

/// Deliberately catches dependency validation failure to exercise sticky collector failure.
private struct SwallowedExtensionDependencyFailure: BotDefinition {
    let invalid: ExtensionDependencies
    let later: ExtensionDependencies
    let source: DefinitionSourceLocation

    /// Swallows one module's error, then attempts an unrelated dependency validation.
    /// - Parameter collector: Exclusive state that must retain the first bounded diagnostic.
    /// - Throws: The original `invalidDependencies` diagnostic before validating `later`.
    func collect(into collector: inout DefinitionCollector) throws {
        do {
            try collector.withNamespace(id: "private", source: source) { scoped in
                try scoped.withModule(id: "invalid", source: source) { nested in
                    try nested.validateDependencies(invalid, source: source)
                }
            }
        } catch {}
        try collector.validateDependencies(later, source: source)
    }
}

/// Verifies public extension identity, dependency injection and bounded pure collection contracts.
@Suite struct ExtensionTests {
    private static let source = DefinitionSourceLocation(fileID: "External/Reusable.swift", line: 45, column: 9)

    /// Creates one inert raw contribution with exact source and payload metadata.
    /// - Parameters:
    ///   - id: Stable local declaration identity; defaults to the reusable instance's fixed ID.
    ///   - requiredCapabilities: Explicit host requirements; default empty.
    /// - Returns: A leaf whose wire-like metadata must never be changed by a namespace.
    private static func raw(_ id: String = "action", requiredCapabilities: Set<String> = []) -> RawDefinitionContribution {
        RawDefinitionContribution(id: id, kind: "external", requiredCapabilities: requiredCapabilities,
            text: "original", payload: .object(["route": .string("/unchanged"), "custom_id": .string("opaque:id")]),
            source: source)
    }

    /// Captures a specifically typed compilation failure for exact source, identity and code assertions.
    /// - Parameter operation: Compilation that must fail with a bounded definition diagnostic.
    /// - Returns: The first terminal diagnostic.
    /// - Throws: Unexpected errors or a fixture failure if compilation unexpectedly succeeds.
    private static func failure(_ operation: () throws -> DefinitionPlan) throws -> DefinitionDiagnostic {
        do {
            _ = try operation()
            Issue.record("Expected extension compilation to fail")
            throw ExtensionDependencyError(secret: "missing-expected-failure")
        } catch let diagnostic as DefinitionDiagnostic { return diagnostic }
    }

    /// Distinct namespace installations support the same module and leaf IDs without metadata rewriting.
    /// Source order, raw module ancestry, exact sources and payloads remain independently inspectable.
    /// - Throws: Unexpected valid compilation failures.
    @Test func repeatedModulesInExplicitNamespaces() throws {
        let reusable = Module(id: "reusable", source: Self.source) { Self.raw() }
        let definition = Module(id: "root", source: Self.source) {
            ModuleNamespace(id: "first", source: Self.source) { reusable }
            ModuleNamespace(id: "second", source: Self.source) { reusable }
        }
        let plan = try DefinitionPlan.compile(definition, supportedKinds: ["external"])
        #expect(plan.description.modules.map(\.id) == ["root", "reusable", "reusable"])
        #expect(plan.description.modules.map(\.path) == [["root"], ["root", "reusable"], ["root", "reusable"]])
        #expect(plan.description.modules.map(\.identity) == [.init(id: "root"),
            .init(namespacePath: ["first"], id: "reusable"), .init(namespacePath: ["second"], id: "reusable")])
        #expect(plan.description.declarations.map(\.identity) == [.init(namespacePath: ["first"], id: "action"),
            .init(namespacePath: ["second"], id: "action")])
        #expect(plan.description.declarations.map(\.namespacePath) == [["first"], ["second"]])
        #expect(plan.description.declarations.allSatisfy { $0.declaration == Self.raw() && $0.modulePath == ["root", "reusable"] })
        #expect(plan.contributions.map(\.declaration) == [Self.raw(), Self.raw()])
        #expect(plan.description.modules.allSatisfy { $0.source == Self.source })
        #expect(plan.description.namespaces.map(\.modulePath) == [["root"], ["root"]])
        #expect(plan.description.namespaces.allSatisfy { $0.source == Self.source })
        #expect(try DefinitionPlan.compile(definition, supportedKinds: ["external"]).description == plan.description)
    }

    /// Nested namespace components are distinct from a single ID containing any familiar delimiter.
    /// Qualified module/declaration identity also separates the local ID from namespace boundaries.
    /// - Throws: Unexpected valid compilation failures.
    @Test func namespaceIdentityNeverUsesDelimiterJoining() throws {
        let definition = BotDefinitionGroup([
            ModuleNamespace(id: "a/b", source: Self.source) { Module(id: "module", source: Self.source) { Self.raw() } },
            ModuleNamespace(id: "a", source: Self.source) {
                ModuleNamespace(id: "b", source: Self.source) { Module(id: "module", source: Self.source) { Self.raw() } }
                Self.raw("b/action")
            },
            ModuleNamespace(id: "a:b", source: Self.source) { Self.raw() },
            Self.raw("a/b/action"),
        ], source: Self.source)
        let plan = try DefinitionPlan.compile(definition, supportedKinds: ["external"])
        #expect(plan.description.namespaces.map(\.path) == [["a/b"], ["a"], ["a", "b"], ["a:b"]])
        #expect(Set(plan.description.declarations.map(\.identity)).count == 5)
        #expect(Set(plan.description.modules.map(\.identity)).count == 2)
        #expect(DefinitionIdentity(namespacePath: ["a/b"], id: "action") != .init(namespacePath: ["a", "b"], id: "action"))
        #expect(DefinitionIdentity(namespacePath: ["a"], id: "b/action") != .init(namespacePath: ["a", "b"], id: "action"))
    }

    /// Explicit namespaces themselves have unique paths, including empty namespaces in separate module bodies.
    /// Repeated local module IDs still fail unless the installation explicitly uses another namespace.
    /// - Throws: Unexpected diagnostic capture or valid compilation failures.
    @Test func duplicateInstallationsRemainExplicit() throws {
        let duplicateNamespace = BotDefinitionGroup([
            Module(id: "one", source: Self.source) { ModuleNamespace(id: "same", source: Self.source) {} },
            Module(id: "two", source: Self.source) { ModuleNamespace(id: "same", source: Self.source) {} },
        ])
        let namespaceError = try Self.failure { try DefinitionPlan.compile(duplicateNamespace) }
        #expect(namespaceError.code == .duplicateNamespaceID)
        #expect(namespaceError.modulePath == ["two"])
        #expect(namespaceError.namespacePath.isEmpty)
        #expect(namespaceError.source == Self.source)
        let modules = ModuleNamespace(id: "scope", source: Self.source) {
            Module(id: "same", source: Self.source) {}
            Module(id: "same", source: Self.source) {}
        }
        #expect(try Self.failure { try DefinitionPlan.compile(modules) }.code == .duplicateModuleID)
        let declarations = ModuleNamespace(id: "scope", source: Self.source) { Self.raw(); Self.raw() }
        #expect(try Self.failure { try DefinitionPlan.compile(declarations, supportedKinds: ["external"]) }.code == .duplicateDeclarationID)
        let distinctModules = BotDefinitionGroup([
            Module(id: "first-instance", source: Self.source) {}, Module(id: "second-instance", source: Self.source) {},
        ])
        #expect(try DefinitionPlan.compile(distinctModules).description.modules.count == 2)
    }

    /// Empty namespaces consume their own finite count, one structural scope and their exact metadata bytes.
    /// Exact boundaries succeed; one lower byte/node/count fails before returning a plan.
    /// - Throws: Unexpected valid compilation or diagnostic capture failures.
    @Test func namespaceAdmissionBoundaries() throws {
        let definition = ModuleNamespace(id: "雪", source: Self.source) {}
        let expectedBytes = "雪".utf8.count + Self.source.fileID.utf8.count
        let limits = DefinitionLimits(maxModules: 0, maxDeclarations: 0, maxTextBytes: expectedBytes,
            maxStructuralNodes: 2, maxNamespaces: 1)
        let plan = try DefinitionPlan.compile(definition, limits: limits)
        #expect(plan.description.namespaces.count == 1)
        #expect(plan.description.textBytes == expectedBytes)
        #expect(plan.description.structureCount == 2)
        #expect(plan.description.modules.isEmpty && plan.description.declarations.isEmpty)
        #expect(try Self.failure {
            try DefinitionPlan.compile(definition, limits: DefinitionLimits(maxNamespaces: 0))
        }.code == .namespaceLimit)
        #expect(try Self.failure {
            try DefinitionPlan.compile(definition, limits: DefinitionLimits(maxStructuralNodes: 1))
        }.code == .structureLimit)
        #expect(try Self.failure {
            try DefinitionPlan.compile(definition, limits: DefinitionLimits(maxDepth: 1))
        }.code == .depthLimit)
        #expect(try Self.failure {
            try DefinitionPlan.compile(definition, limits: DefinitionLimits(maxTextBytes: expectedBytes - 1))
        }.code == .textLimit)
        #expect(try Self.failure {
            try DefinitionPlan.compile(definition, limits: DefinitionLimits(maxNamespaces: -1))
        }.code == .invalidLimits)
        let siblings = BotDefinitionGroup([definition, ModuleNamespace(id: "other", source: Self.source) {}])
        #expect(try DefinitionPlan.compile(siblings, limits: DefinitionLimits(maxNamespaces: 2)).description.namespaces.count == 2)
        #expect(try Self.failure {
            try DefinitionPlan.compile(siblings, limits: DefinitionLimits(maxNamespaces: 1))
        }.code == .namespaceLimit)
    }

    /// Namespace identity applies existing byte/control rules without changing arbitrary Unicode spelling.
    /// - Parameter id: Empty, control-bearing or oversized local namespace component.
    /// - Throws: Unexpected diagnostic capture failures.
    @Test(arguments: ["", "\n", "bad\u{0}id", "bad\u{7f}id", String(repeating: "é", count: 65)])
    func invalidNamespaceComponents(id: String) throws {
        let error = try Self.failure { try DefinitionPlan.compile(ModuleNamespace(id: id, source: Self.source) {}) }
        #expect(error.code == .invalidIdentity)
        #expect(error.source == Self.source)
    }

    /// Caller-coordinate overloads preserve authored coordinates, and exact Unicode identity bounds remain valid.
    /// Public external namespace composition restores ancestry before collecting later siblings.
    /// - Throws: Unexpected valid compilation failures.
    @Test func namespaceCallSitesAndScopeRestoration() throws {
        let namespace = ModuleNamespace(id: String(repeating: "é", count: 64)) { Self.raw("first") }
        let direct = DirectExtensionNamespace(id: "direct", source: Self.source, child: Self.raw("inside"))
        let plan = try DefinitionPlan.compile(BotDefinitionGroup([namespace, direct, Self.raw("outside")]),
            supportedKinds: ["external"])
        let captured = try #require(plan.description.namespaces.first?.source)
        #expect(captured.fileID.hasSuffix("ExtensionTests.swift") && captured.line > 0 && captured.column > 0)
        #expect(plan.description.namespaces.last?.source == Self.source)
        #expect(plan.description.declarations.map(\.namespacePath) == [[String(repeating: "é", count: 64)], ["direct"], []])
        #expect(plan.description.declarations.last?.identity == .init(id: "outside"))
        #expect(plan.description.declarations.allSatisfy { $0.modulePath.isEmpty })
    }

    /// Namespaces grant neither kind nor capability support, and diagnostics retain exact bounded namespace ancestry.
    /// - Throws: Unexpected valid compilation or diagnostic capture failures.
    @Test func namespaceCapabilityChecksRemainFailClosed() throws {
        let definition = ModuleNamespace(id: "scope", source: Self.source) {
            Module(id: "module", source: Self.source) { Self.raw(requiredCapabilities: ["explicit"]) }
        }
        let kind = try Self.failure { try DefinitionPlan.compile(definition) }
        #expect(kind.code == .unsupportedKind && kind.namespacePath == ["scope"] && kind.modulePath == ["module"])
        let capability = try Self.failure { try DefinitionPlan.compile(definition, supportedKinds: ["external"]) }
        #expect(capability.code == .unsupportedCapability && capability.source == Self.source)
        #expect(capability.namespacePath == ["scope"])
        #expect(try DefinitionPlan.compile(definition, supportedKinds: ["external"], capabilities: ["explicit"])
            .description.declarations.first?.declaration == Self.raw(requiredCapabilities: ["explicit"]))
        let long = String(repeating: "é", count: 65)
        let bounded = DefinitionDiagnostic(code: .invalidDependencies, source: Self.source, modulePath: [],
            namespacePath: Array(repeating: long, count: 200))
        #expect(bounded.namespacePath.count == 128)
        #expect(bounded.namespacePath.allSatisfy { $0 == String(repeating: "é", count: 64) })
    }

    /// Constructing dependency modules does not validate or construct bodies; collection validates first and retains the exact actor.
    /// Explicit later invocation confirms injected service identity without ambient discovery or compilation execution.
    /// - Throws: Unexpected valid compilation or typed retention failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func dependenciesValidateBeforeLazyBodyAndRetainService() async throws {
        let observations = ExtensionObservations()
        let service = ExtensionService()
        let dependencies = ExtensionDependencies(configured: true, service: service,
            observeValidation: { observations.append("validate") })
        let module = DependentModule(id: "dependent", dependencies: dependencies, source: Self.source) { supplied in
            let _ = observations.append("body")
            ExtensionAction(declaration: Self.raw("first"), service: supplied.service)
            Self.raw("second")
        }
        #expect(module.dependencies.service === service)
        #expect(observations.snapshot().isEmpty)
        #expect(await service.count() == 0)
        let plan = try DefinitionPlan.compile(module, supportedKinds: ["external"])
        #expect(observations.snapshot() == ["validate", "body"])
        #expect(plan.description.declarations.map { $0.declaration.id } == ["first", "second"])
        #expect(plan.description.declarations.allSatisfy { $0.modulePath == ["dependent"] })
        #expect(plan.description.modules.first?.source == Self.source)
        let retained = try #require(plan.contributions.first as? ExtensionAction)
        #expect(retained.service === service)
        #expect(await service.count() == 0)
        await retained.service.execute()
        #expect(await service.count() == 1)
        #expect(try DefinitionPlan.compile(module, supportedKinds: ["external"]).description == plan.description)
        #expect(observations.snapshot() == ["validate", "body", "validate", "body"])
    }

    /// Invalid injected configuration produces only a bounded source-located diagnostic and never evaluates the child factory.
    /// - Throws: Unexpected diagnostic capture failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func invalidDependenciesSkipBodyAndRedactErrors() async throws {
        let observations = ExtensionObservations()
        let service = ExtensionService()
        let dependencies = ExtensionDependencies(configured: false, service: service,
            observeValidation: { observations.append("validate") })
        let definition = ModuleNamespace(id: "scope", source: Self.source) {
            DependentModule(id: "dependent", dependencies: dependencies, source: Self.source) { _ in
                let _ = observations.append("body")
                Self.raw()
            }
        }
        #expect(observations.snapshot().isEmpty)
        let error = try Self.failure { try DefinitionPlan.compile(definition, supportedKinds: ["external"]) }
        #expect(error.code == .invalidDependencies && error.source == Self.source)
        #expect(error.modulePath == ["dependent"] && error.namespacePath == ["scope"])
        #expect(!String(describing: error).contains("never-display-private-token"))
        #expect(observations.snapshot() == ["validate"])
        #expect(await service.count() == 0)
    }

    /// Module, namespace, structural, identity and text admission all precede dependency validation and body execution.
    /// - Throws: Unexpected diagnostic capture failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func admissionPrecedesDependencyValidation() throws {
        let observations = ExtensionObservations()
        let dependencies = ExtensionDependencies(configured: false, service: ExtensionService(),
            observeValidation: { observations.append("validate") })
        let module = DependentModule(id: "dependent", dependencies: dependencies, source: Self.source) { _ in
            let _ = observations.append("body")
            Self.raw()
        }
        for (limits, expected) in [(DefinitionLimits(maxModules: 0), DefinitionDiagnostic.Code.moduleLimit),
            (DefinitionLimits(maxStructuralNodes: 0), .structureLimit), (DefinitionLimits(maxTextBytes: 0), .textLimit)] {
            #expect(try Self.failure { try DefinitionPlan.compile(module, limits: limits) }.code == expected)
        }
        let nested = ModuleNamespace(id: "scope", source: Self.source) { module }
        #expect(try Self.failure {
            try DefinitionPlan.compile(nested, limits: DefinitionLimits(maxDepth: 2))
        }.code == .depthLimit)
        #expect(try Self.failure {
            try DefinitionPlan.compile(nested, limits: DefinitionLimits(maxNamespaces: 0))
        }.code == .namespaceLimit)
        let invalid = DependentModule(id: "", dependencies: dependencies, source: Self.source) { _ in
            let _ = observations.append("body")
        }
        #expect(try Self.failure { try DefinitionPlan.compile(invalid) }.code == .invalidIdentity)
        #expect(observations.snapshot().isEmpty)
    }

    /// Rejected duplicate installations never validate their dependencies or build their bodies.
    /// The same module in a distinct namespace validates independently with deterministic expansion order.
    /// - Throws: Unexpected valid compilation or diagnostic capture failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func duplicateAdmissionSkipsSecondValidation() throws {
        let observations = ExtensionObservations()
        let dependencies = ExtensionDependencies(configured: true, service: ExtensionService(),
            observeValidation: { observations.append("validate") })
        let module = DependentModule(id: "reusable", dependencies: dependencies, source: Self.source) { _ in
            let _ = observations.append("body")
        }
        #expect(try Self.failure { try DefinitionPlan.compile(BotDefinitionGroup([module, module])) }.code == .duplicateModuleID)
        #expect(observations.snapshot() == ["validate", "body"])
        let first = ModuleNamespace(id: "first", source: Self.source) { module }
        #expect(try Self.failure { try DefinitionPlan.compile(BotDefinitionGroup([first, first])) }.code == .duplicateNamespaceID)
        #expect(observations.snapshot() == ["validate", "body", "validate", "body"])
        let second = ModuleNamespace(id: "second", source: Self.source) { module }
        #expect(try DefinitionPlan.compile(BotDefinitionGroup([first, second])).description.modules.count == 2)
        #expect(observations.snapshot() == Array(repeating: ["validate", "body"], count: 4).flatMap { $0 })
    }

    /// Dependency rejection remains terminal across custom catches and stops later dependency validation.
    /// Caller-coordinate lazy modules also report their external authoring call site.
    /// - Throws: Unexpected diagnostic capture failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func dependencyFailurePoisoningAndCapturedCallSite() throws {
        let observations = ExtensionObservations()
        let service = ExtensionService()
        let invalid = ExtensionDependencies(configured: false, service: service,
            observeValidation: { observations.append("invalid") })
        let later = ExtensionDependencies(configured: true, service: service,
            observeValidation: { observations.append("later") })
        let swallowed = SwallowedExtensionDependencyFailure(invalid: invalid, later: later, source: Self.source)
        let error = try Self.failure { try DefinitionPlan.compile(swallowed) }
        #expect(error.code == .invalidDependencies && error.modulePath == ["invalid"] && error.namespacePath == ["private"])
        #expect(observations.snapshot() == ["invalid"])
        let captured = DependentModule(id: "captured", dependencies: invalid) { _ in EmptyBotDefinition() }
        let capturedError = try Self.failure { try DefinitionPlan.compile(captured) }
        #expect(capturedError.source.fileID.hasSuffix("ExtensionTests.swift"))
        #expect(capturedError.source.line > 0 && capturedError.source.column > 0)
    }
}
