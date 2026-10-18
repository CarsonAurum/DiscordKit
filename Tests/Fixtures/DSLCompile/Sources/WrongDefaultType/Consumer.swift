import DiscordCommandDSL
import DiscordDSLMacros
import DiscordInteractions

/// Swift type checking remains authoritative for literal defaults accepted by syntax policy.
@CommandArguments
struct WrongDefaultArguments {
    @Option(description: "Default") var count: Int = "three"
}
