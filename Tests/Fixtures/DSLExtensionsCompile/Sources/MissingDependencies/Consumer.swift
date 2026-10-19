import DiscordCommandExtensions

/// Intentionally fails because the extension's required typed dependency contract cannot be omitted.
/// - Throws: Authoring validation would occur only if this deliberately invalid source could compile.
public func missingDependencies() throws { _ = try ExtensionCommands(id: "missing") }
