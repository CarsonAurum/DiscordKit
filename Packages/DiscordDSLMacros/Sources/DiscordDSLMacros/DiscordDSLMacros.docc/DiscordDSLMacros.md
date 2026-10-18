# ``DiscordDSLMacros``

Generate typed argument schemas and manual slash-command contributions using the
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

Apply `@SlashCommand` to a nongeneric manual handler with an explicit `Arguments`
typealias and an `execute(_:arguments:)` implementation. Import DiscordDSL when
using the generated contribution factory's explicit source location. Existing
interaction responders retain acknowledgement and completion ownership.

Macro expansion emits declarations and diagnostics. It starts no tasks, I/O,
registration or handler execution. Explicit schema access and command compilation
perform existing synchronous validation. Response policies and application hosts
remain separate milestones. Local compiler and execution fixtures do not establish
live Discord, platform or capacity qualification.

## Topics

### Authoring declarations

- <doc:APIReference>
