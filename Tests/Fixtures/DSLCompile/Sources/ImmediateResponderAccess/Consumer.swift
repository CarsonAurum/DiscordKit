import DiscordCommandDSL
import DiscordDSL
import DiscordDSLMacros

/// Minimal generated arguments isolate the response-authority failure from unrelated decoding checks.
@CommandArguments
struct Input {}

/// Ordinary immediate handlers must not be able to access low-level acknowledgement authority.
@SlashCommand("invalid", description: "Immediate authority boundary")
struct Invalid: SlashCommandHandler {
    typealias Arguments = Input

    /// Deliberately fails to type-check when trying to retrieve the raw responder.
    /// - Parameters:
    ///   - context: Immediate typed snapshot whose public surface excludes response authority.
    ///   - arguments: Empty valid invocation state, unused by this compile failure.
    /// - Returns: No result because compilation must reject the forbidden member access.
    /// - Throws: A fixture sentinel after the deliberately invalid expression.
    func execute(_ context: CommandContext, arguments: Arguments) async throws -> MessageResponse {
        _ = context.responder
        throw Failure.expected
    }
}

/// Ordinary sentinel leaves the intended member diagnostic as the only missing API.
private enum Failure: Error { case expected }
