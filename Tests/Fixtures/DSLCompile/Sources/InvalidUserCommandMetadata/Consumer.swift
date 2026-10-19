import DiscordDSLMacros

/// Empty context-menu names are rejected by the authoring macro before runtime construction.
@UserCommand("")
struct InvalidUser {}
