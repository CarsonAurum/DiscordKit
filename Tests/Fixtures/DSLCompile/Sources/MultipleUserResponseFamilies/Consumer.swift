import DiscordCommandDSL
import DiscordDSLMacros

/// Two acknowledgement owners cannot be selected by one user context-menu author.
@UserCommand("Inspect User")
struct AmbiguousUser: UserCommandHandler, DeferredUserCommandHandler {}
