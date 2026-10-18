import DiscordCommandDSL
import DiscordDSLMacros
import DiscordInteractions

/// Every instance field must explicitly declare its option metadata.
@CommandArguments
struct MissingMarkerArguments {
    let value: String
}
