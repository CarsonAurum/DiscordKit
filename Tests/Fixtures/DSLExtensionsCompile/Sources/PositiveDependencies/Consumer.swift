import DiscordBotExtensions
import DiscordCommandDSL
import DiscordCommandExtensions
import DiscordDSL

/// Compiles an imported module and its custom policy using only public APIs from independent packages.
/// - Parameter dependencies: Required exact Sendable contract, including the application's shared actor.
/// - Returns: Inert typed/raw command routes; handlers, service decisions and I/O remain unexecuted.
/// - Throws: Immutable dependency, command, structural or policy validation failures.
public func compileExternalCommands(dependencies: ExtensionDependencies) throws -> CompiledCommands {
    let module = try ExtensionCommands(id: "commands", dependencies: dependencies)
    return try CommandCompilation.compile(ModuleNamespace(id: "consumer") { module })
        .applying(ExtensionCommands.policies(dependencies: dependencies))
}

/// Type-checks independently imported event callbacks without requiring a command macro or private API.
/// - Parameter dependencies: Required ready/stop callbacks; captured actor/host authority remains caller-owned.
/// - Returns: Inert reusable event declarations with explicit namespaced structural identity.
public func externalEvents(dependencies: ExtensionEventDependencies) -> some BotDefinition {
    ModuleNamespace(id: "consumer") { ExtensionEvents(id: "events", dependencies: dependencies) }
}
