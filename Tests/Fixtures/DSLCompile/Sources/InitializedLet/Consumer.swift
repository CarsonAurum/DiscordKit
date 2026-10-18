import DiscordCommandDSL
import DiscordDSLMacros
import DiscordInteractions

/// Swift cannot overwrite initialized let storage while decoding an invocation.
@CommandArguments
struct ConstantDefaultArguments {
    @Option(description: "Default") let count: Int = 2
}
