# ``DiscordDSLMacros``

Generate typed argument schemas, grouped slash leaves and typed context-menu contributions using the
existing DiscordCommandDSL protocols.

## Overview

This optional package is selected alongside the runtime products used by your
application. Runtime libraries remain independently adoptable. The compiler plugin
uses the pinned SwiftSyntax 604.0.0 host tools and generates ordinary Swift code;
the runtime package has no dependency on the plugin or SwiftSyntax.

Apply `@CommandArguments` to a nongeneric struct and mark every instance property
with `@Option`; accessors and other property wrappers are unsupported. Each field needs an explicit type conforming to the
runtime argument protocol. Required `let` fields are supported. Defaulted fields
use `var` with a finite literal, nil or enum-member expression; custom codec and
member behavior remains application-owned code. Metadata uses simple single-line
string literals without raw or multiline spelling, escapes or interpolation.

Apply `@SlashCommand` to a nongeneric handler with an explicit `Arguments`
typealias and an `execute(_:arguments:)` implementation. Directly inherit
`SlashCommandHandler` for immediate `CommandContext`/`MessageResponse`,
`ModalSlashCommandHandler` for immediate `ModalResponse`, or
`DeferredSlashCommandHandler` for `DeferredCommandContext`/`DeferredMessageResponse`.
Typed contexts expose immutable invocation data; existing interaction responders
retain acknowledgement and completion ownership in the runtime adapter. Explicit
`ManualSlashCommandHandler`, or omitting all supported family names for compatibility,
retains manual responder access. Select one supported family directly; the macro
does not resolve imported protocol refinements. Import DiscordDSL when using the
generated contribution factory's explicit source location.

Macro expansion emits declarations and diagnostics. It starts no tasks, I/O,
registration or handler execution. Explicit schema access and command compilation
perform existing synchronous validation. The generated `slashSubcommand()`
factory retains the same handler for an explicit `SlashCommandTree`, including one supported subcommand-group level. `@UserCommand`
and `@MessageCommand` generate context-menu metadata and factories with typed
`UserReference` and `MessageCommandTarget` targets. Directly spell exactly one immediate,
deferred or manual target-family protocol; without one, manual ownership is generated.
Use the runtime protocols directly for autocomplete, exact-ID components and modal
submissions. Supplied response wrappers keep legal callback families distinct; runtime
adapters recheck callback kinds before responding. Local compiler and execution
fixtures do not establish live Discord, platform or capacity qualification.

## Topics

### Adopt macro authoring

- <doc:AdoptingMacros>

### Authoring declarations

- <doc:APIReference>
