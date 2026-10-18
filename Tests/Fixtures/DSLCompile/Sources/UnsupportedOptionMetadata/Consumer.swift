import DiscordCommandDSL
import DiscordDSLMacros
import DiscordInteractions

/// Autocomplete remains outside the finite manual command macro surface.
@CommandArguments
struct AutocompleteArguments {
    @Option(description: "Query", autocomplete: true) let query: String
}
