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
let dynamicName = "dynamic"
/// Runtime expressions cannot substitute for checked literal macro metadata.
@SlashCommand(dynamicName, description: "Description")
struct DynamicCommand {
    typealias Arguments = EmptyArguments
    /// The expected-failure declaration never executes this deliberately inert handler.
    /// - Parameters:
    ///   - context: Existing response owner, unused by the compile fixture.
    ///   - arguments: Empty local values, unused by the compile fixture.
    func execute(_ context: InteractionContext, arguments: Arguments) async throws {}
}
