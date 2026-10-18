import DiscordCommandDSL
import DiscordDSLMacros
import DiscordInteractions

/// The handler must explicitly identify its argument aggregate rather than relying on macro inference.
@SlashCommand("alias", description: "Missing alias")
struct MissingAliasCommand {
    /// Supplies the right method shape while intentionally omitting the required explicit Arguments alias.
    /// - Parameters:
    ///   - context: Existing trusted interaction, unused.
    ///   - arguments: An unrelated string that cannot substitute for CommandArguments.
    func execute(_ context: InteractionContext, arguments: String) async throws {}
}
