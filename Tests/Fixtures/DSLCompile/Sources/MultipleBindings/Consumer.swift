import DiscordCommandDSL
import DiscordDSLMacros
import DiscordInteractions

/// One marker cannot silently apply shared metadata to multiple stored arguments.
@CommandArguments
struct MultipleArguments {
    @Option(description: "Multiple") var one: Int, two: Int
}
