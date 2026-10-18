import DiscordCommandDSL
import DiscordDSLMacros
import DiscordInteractions

/// Type inference is deliberately unavailable to syntax-only schema generation.
@CommandArguments
struct InferredArguments {
    @Option(description: "Inferred") var count = 2
}
