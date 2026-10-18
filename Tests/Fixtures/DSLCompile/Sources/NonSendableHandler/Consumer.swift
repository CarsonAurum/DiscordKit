import DiscordCommandDSL
import DiscordDSLMacros
import DiscordInteractions

/// Empty handwritten arguments keep command-metadata diagnostics independent of generated argument syntax.
struct EmptyArguments: CommandArguments {
    /// Supplies a valid empty schema without handler, registration or I/O work.
    static var schema: CommandArgumentSchema<Self> {
        /// Returns an inert empty constructor.
        /// - Throws: Existing empty-schema validation errors, unexpected for this fixture.
        get throws { try CommandArgumentSchema(options: []) { _ in Self() } }
    }
}
/// Mutable reference state deliberately lacks Sendable conformance.
final class MutableState { var value = 0 }
/// Generated protocol conformance must preserve Swift's Sendable checking for captured handler state.
@SlashCommand("state", description: "State")
struct NonSendableCommand {
    let state: MutableState
    typealias Arguments = EmptyArguments
    /// The expected-failure declaration never executes this deliberately inert handler.
    /// - Parameters:
    ///   - context: Existing response owner, unused by the compile fixture.
    ///   - arguments: Empty local values, unused by the compile fixture.
    func execute(_ context: InteractionContext, arguments: Arguments) async throws {}
}
