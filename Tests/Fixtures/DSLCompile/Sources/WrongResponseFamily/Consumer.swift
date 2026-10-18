import DiscordCommandDSL
import DiscordDSL
import DiscordDSLMacros

/// Valid generated empty arguments isolate the protocol's required response type.
@CommandArguments
struct Input {}

/// An immediate handler cannot satisfy its protocol by returning a deferred completion.
@SlashCommand("invalid", description: "Wrong response family")
struct Invalid: SlashCommandHandler {
    typealias Arguments = Input

    /// Intentionally returns the wrong response family and must fail real Swift protocol conformance.
    /// - Parameters:
    ///   - context: Valid immediate invocation snapshot, unused by this negative fixture.
    ///   - arguments: Valid empty generated argument value.
    /// - Returns: No runtime result; the declaration's return type deliberately violates its protocol.
    /// - Throws: A fixture sentinel, leaving the response signature as the intended compile failure.
    func execute(_ context: CommandContext, arguments: Arguments) async throws -> DeferredMessageResponse {
        throw Failure.expected
    }
}

/// Ordinary sentinel keeps the invalid response-family signature independent of payload construction.
private enum Failure: Error { case expected }
