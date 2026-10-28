// File: Packages/DiscordDSLExtensions/Sources/DiscordCommandExtensions/ExtensionCommands.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordCommands
import DiscordCore
import DiscordDSL
import DiscordInteractions
import DiscordModels

/// Finite extension-owned validation failures; submitted code text is never retained in errors.
public enum ExtensionError: Error, Sendable, Equatable { case invalidCode, invalidConfiguration, limitExceeded }

/// A separately compiled custom string codec: one through eight ASCII uppercase letters.
/// It uses the existing public protocol and requires no macro or core discriminator changes.
public struct UppercaseCode: ArgumentValue, Equatable {
    public let text: String
    /// Declares an ordinary string option while keeping stronger domain validation extension-owned.
    public static var optionType: ApplicationCommandOptionType { .string }

    /// Validates bounded uppercase ASCII text synchronously without normalization or I/O.
    /// - Parameter text: One through eight bytes, each in ASCII A...Z; other Unicode is rejected.
    /// - Throws: `ExtensionError.invalidCode` without retaining submitted text.
    public init(_ text: String) throws {
        let bytes = text.utf8.prefix(9)
        guard (1...8).contains(bytes.count), bytes.allSatisfy({ (65...90).contains($0) }) else {
            throw ExtensionError.invalidCode
        }
        self.text = text
    }

    /// Preserves the standard codec's absence/null/kind errors, then applies domain validation.
    /// - Parameters:
    ///   - value: Exact retained field; omission, null and strings remain distinct.
    ///   - resolved: Interaction-local partial resources, unused by the string codec.
    /// - Returns: A bounded uppercase code without hydration, tasks or implicit case conversion.
    /// - Throws: Standard scalar admission errors or `ExtensionError.invalidCode`.
    public static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self {
        try Self(String.decodeArgument(value, resolved: resolved))
    }

    /// Encodes the same exact validated bytes, preserving direct-model payload parity.
    public var argumentValue: Field<JSONValue> { .value(.string(text)) }
}

/// Fixed-count actor service shared explicitly by policies and handlers; no keyed history or tasks exist.
public actor ExtensionCounter {
    private let allowed: Bool
    private var authorizationCount = 0
    private var executionCount = 0

    /// Captures the application's authorization decision without executing it during construction.
    /// - Parameter allowed: Fixed local policy decision; default true. A real bounded authority may replace it.
    public init(allowed: Bool = true) { self.allowed = allowed }

    /// Applies the injected current decision, with a finite observation limit and cancellation check.
    /// - Returns: The explicitly supplied decision; registration permissions grant no authority.
    /// - Throws: Cancellation or `ExtensionError.limitExceeded` after eight observations.
    public func authorize() throws -> Bool {
        try Task.checkCancellation()
        guard authorizationCount < 8 else { throw ExtensionError.limitExceeded }
        authorizationCount += 1
        return allowed
    }

    /// Records one admitted handler entry, including entries whose later response delivery fails.
    /// - Throws: Cancellation or `ExtensionError.limitExceeded` after eight executions.
    public func executed() throws {
        try Task.checkCancellation()
        guard executionCount < 8 else { throw ExtensionError.limitExceeded }
        executionCount += 1
    }

    /// Copies fixed counters after the caller has joined its own work; no service execution occurs.
    /// - Returns: Authorization and execution counts, each bounded to eight.
    public func snapshot() -> (authorizations: Int, executions: Int) { (authorizationCount, executionCount) }
}

/// An explicit Sendable dependency contract. No reflection, ambient container or implicit service lookup occurs.
public struct ExtensionDependencies: ModuleDependencies {
    public let counter: ExtensionCounter
    public let configurationName: String
    public let completed: @Sendable () async -> Void

    /// Stores an actor and caller-owned completion hook without invoking either.
    /// - Parameters:
    ///   - counter: Shared bounded authorization/execution service; never replaced by the module.
    ///   - configurationName: One through 32 ASCII letters identifying this local configuration.
    ///   - completed: Explicit post-reply hook; default does nothing. Runs in the existing caller task.
    public init(counter: ExtensionCounter, configurationName: String = "offline",
        completed: @escaping @Sendable () async -> Void = {}) {
        self.counter = counter
        self.configurationName = configurationName
        self.completed = completed
    }

    /// Rejects invalid immutable configuration before dependent body expansion without consulting the actor.
    /// - Throws: `ExtensionError.invalidConfiguration` for empty, oversized or non-ASCII-letter names.
    public func validate() throws {
        let bytes = configurationName.utf8.prefix(33)
        guard (1...32).contains(bytes.count), bytes.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0)
        }) else { throw ExtensionError.invalidConfiguration }
    }
}

/// An extension-owned policy type that adapts explicit actor authority to the public bounded DSL value.
/// It retains the same service instance as the module and owns no queue, keyed state or runtime tasks.
public struct ExtensionAuthorizationPolicy: Sendable {
    public let dependencies: ExtensionDependencies

    /// Captures typed services without consulting authorization or executing any handler.
    /// - Parameter dependencies: The exact caller-injected actor and immutable configuration contract.
    public init(dependencies: ExtensionDependencies) { self.dependencies = dependencies }

    /// Lowers this custom policy to the existing policy extension point without executing its decision.
    /// - Returns: A bounded caller-task predicate; service cancellation and failures propagate unchanged.
    public func requiringAuthorization() -> InvocationPolicy<CommandContext> {
        InvocationPolicy { _ in try await dependencies.counter.authorize() }
    }
}

/// A public aggregate schema demonstrating cross-module custom codecs without compiler plugins.
public struct ExtensionArguments: CommandArguments {
    public let code: UppercaseCode
    /// Validates a required string option and captures fresh typed construction for every invocation.
    /// - Throws: Existing schema/option validation errors; no decoder or handler is invoked now.
    public static var schema: CommandArgumentSchema<Self> {
        /// Produces finite public schema metadata and a fresh value constructor.
        /// - Returns: One required code option with matching existing-model string length constraints.
        /// - Throws: Existing descriptor validation errors; decoding errors occur only at invocation.
        get throws {
            let option = try ArgumentOption<UppercaseCode>(name: "code", description: "Uppercase ASCII code",
                minLength: 1, maxLength: 8)
            return try CommandArgumentSchema(options: [option.erased]) { values in
                Self(code: try values.value(for: option))
            }
        }
    }
}

/// The custom codec and actor service enter execution through the existing manual response owner.
public struct ExtensionCommand: ManualSlashCommandHandler {
    public let command = SlashCommandMetadata(name: "extension", description: "Use an independently compiled extension")
    public let dependencies: ExtensionDependencies

    /// Captures exact typed injected services without querying authorization or opening runtime work.
    /// - Parameter dependencies: Explicit module-owned contract; compilation validates immutable configuration.
    public init(dependencies: ExtensionDependencies) { self.dependencies = dependencies }

    /// Records admitted handler entry, replies once and calls the explicit hook only after confirmed reply.
    /// - Parameters:
    ///   - context: Existing authenticated interaction and unique response owner.
    ///   - arguments: Fresh custom-codec values, completely validated before policy or handler execution.
    /// - Throws: Existing response/transport/cancellation failures or finite service accounting errors.
    public func execute(_ context: InteractionContext, arguments: ExtensionArguments) async throws {
        try await dependencies.counter.executed()
        let response = try MessageResponse(visibility: .ephemeral) { Text("Code: \(arguments.code.text)") }
        try await context.responder.reply(response.message)
        await dependencies.completed()
    }
}

/// A reusable external module over existing command contributions, with lazy typed dependency validation.
/// Consumers may wrap it in `ModuleNamespace` for structural identity; Discord wire names remain unchanged.
public struct ExtensionCommands: BotModule {
    public let moduleID: String
    private let dependencies: ExtensionDependencies
    private let typed: SlashCommand<ExtensionCommand>
    private let raw: ExistingSlashCommand

    /// Captures independently compiled typed and direct-command adapters; starts no runtime work.
    /// - Parameters:
    ///   - id: Stable module ID, globally unique within its explicit namespace.
    ///   - dependencies: Exact typed services validated before dependent body expansion.
    /// - Throws: Existing schema, command metadata or direct-adapter validation errors.
    public init(id: String, dependencies: ExtensionDependencies) throws {
        moduleID = id
        self.dependencies = dependencies
        typed = try SlashCommand(id: "typed", handler: ExtensionCommand(dependencies: dependencies))
        let definition = try CommandDefinition.slash(name: "raw-extension", description: "Use an existing raw command adapter")
        let route = CommandRoute(key: try .command(name: "raw-extension")) { context in
            try await dependencies.counter.executed()
            try await context.responder.reply(InteractionMessageCreate(content: .value("Raw extension")))
        }
        raw = try ExistingSlashCommand(id: "raw", definition: definition, route: route)
    }

    /// Admits the exact dependency contract before collecting typed and raw contributions in author order.
    @BotBuilder public var body: some BotDefinition {
        DependentModule(id: "command-dependencies", dependencies: dependencies) { _ in
            typed
            raw
        }
    }

    /// Builds an external custom policy without consulting the actor until explicit router invocation.
    /// - Parameter dependencies: The same explicitly shared service contract supplied to the module.
    /// - Returns: Finite existing-owner command policies, with explicit ephemeral denial.
    /// - Throws: Existing finite policy-bound validation failures.
    public static func policies(dependencies: ExtensionDependencies) throws -> CommandPolicies {
        let authorization = ExtensionAuthorizationPolicy(dependencies: dependencies).requiringAuthorization()
        return try CommandPolicies(limits: PolicyLimits(maximumNodes: 4, maximumDepth: 4), requiring: authorization,
            onRejection: { _ in .message(try MessageResponse(visibility: .ephemeral) { Text("Extension denied") }) })
    }
}
