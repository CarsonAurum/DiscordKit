import DiscordCommandDSL
import DiscordDSLMacros
import DiscordInteractions

/// Ordinary enum syntax does not provide the required runtime ArgumentValue conformance.
enum UnsupportedChoice: String { case red }
/// The macro may preserve this type spelling; Swift must reject the generated generic descriptor.
@CommandArguments
struct UnsupportedArguments {
    @Option(description: "Unsupported") let value: UnsupportedChoice
}
