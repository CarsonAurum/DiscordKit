import DiscordCommandExtensions

/// Intentionally fails because a string is not the extension's explicitly required dependency contract.
/// - Throws: Authoring validation would occur only if this deliberately invalid source could compile.
public func wrongDependencies() throws { _ = try ExtensionCommands(id: "wrong", dependencies: "ambient") }
