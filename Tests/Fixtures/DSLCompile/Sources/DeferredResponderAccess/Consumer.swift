import DiscordCommandDSL
import DiscordDSL
import DiscordDSLMacros

/// Valid empty arguments keep this external diagnostic focused on deferred response ownership.
@CommandArguments
struct Input {}

/// Deferred handlers must return an original edit without retrieving raw response authority.
@SlashCommand("invalid", description: "Deferred authority boundary")
struct Invalid: DeferredSlashCommandHandler {
    typealias Arguments = Input

    /// Deliberately references a member that the deferred typed snapshot does not expose.
    /// - Parameters:
    ///   - context: Deferred typed snapshot without a responder or acknowledgement operations.
    ///   - arguments: Empty valid invocation state, unused by this compile failure.
    /// - Returns: No result because the external compiler must reject the responder access.
    /// - Throws: A fixture sentinel after the intentionally invalid expression.
    func execute(_ context: DeferredCommandContext, arguments: Arguments) async throws -> DeferredMessageResponse {
        _ = context.responder
        throw Failure.expected
    }
}

/// Ordinary sentinel avoids constructing unrelated response payloads in the negative fixture.
private enum Failure: Error { case expected }
