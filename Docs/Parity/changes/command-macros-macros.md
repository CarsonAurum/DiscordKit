<!--
File: Docs/Parity/changes/command-macros-macros.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Separate macro authoring

Recorded, verified and local support date: **2026-10-18**. The **0.15.0 candidate**
remains unpublished. Upstream announcement/effective dates are **unknown**: this is an additive
Swift authoring change, with no new Discord wire behavior. REST/Gateway v10, Voice
v8, RPC v1, MLS 1.0 and DAVE v1 remain unchanged.

Previously, consumers wrote typed argument descriptors, schema construction and
manual slash metadata explicitly. The separate `DiscordDSLMacros` package now emits
that ordinary Swift from `@CommandArguments`, `@Option` and `@SlashCommand` declarations.
Generated schemas use existing validated options and strict invocation decoding;
commands reference `Arguments` through its protocol and keep behavior in `execute`.
The compiler checks external codec conformances and Sendable constraints. Generated
callables carry documentation, and invalid authoring forms report source diagnostics.

Adoption is optional: existing runtime products and macro-free consumers retain
identical dependency graphs. Only the separate plugin selects SwiftSyntax 604.0.0,
verified against the Swift 6.4 host. No existing API is removed. Select the separate
macro product and relevant runtime products explicitly; see [migration](../../Migration.md)
and [supported forms](../../MacroDSL.md). Advanced unsupported authoring forms remain
available through explicit argument schemas. Manual response acknowledgement,
registration and host ownership remain application controlled.

The [official command reference](https://docs.discord.com/developers/interactions/application-commands),
[interaction reference](https://docs.discord.com/developers/interactions/receiving-and-responding),
[API reference](https://docs.discord.com/developers/reference),
[change log](https://docs.discord.com/developers/change-log),
[SwiftSyntax release](https://github.com/swiftlang/swift-syntax/releases/tag/604.0.0)
and [attached macro proposal](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0389-attached-macros.md)
were reviewed for the affected contracts. [Exact source hashes](../../Release/sources/2026-10-18-command-macros.json)
identify the review inputs; unchanged discovery classifications are not promoted.

Real generated-code execution parity, expansion diagnostics and external compiler
fixtures establish local offline behavior. They do not qualify other platforms or
toolchains, live Discord, runtime capacity or HTTP/Gateway host behavior. Historical release/validation records remain unchanged.
