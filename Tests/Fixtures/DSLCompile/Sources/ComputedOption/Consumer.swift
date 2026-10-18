import DiscordCommandDSL
import DiscordDSLMacros
import DiscordInteractions

/// Computed properties cannot become stored invocation-local arguments.
@CommandArguments
struct ComputedArguments {
    /// Deliberately computed rather than stored; the attached macro must diagnose this declaration.
    @Option(description: "Computed") var value: String { "value" }
}
