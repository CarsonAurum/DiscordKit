<!--
File: Packages/DiscordDSLExtensions/README.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Independently compiled DSL extensions

This package is an ordinary downstream consumer of DiscordKit public APIs. It
contains no compiler plugins, private imports or `@testable` access. It adds no
runtime dependency from the existing DiscordKit products back to extensions.

`DiscordCommandExtensions` selects the command-only runtime graph. It excludes
Gateway, Client, Cache, concrete adapters, SwiftSyntax and compiler plugins.
`UppercaseCode` is an `ArgumentValue` codec for one through eight uppercase ASCII
letters. `ExtensionCommands` is a reusable `BotModule` with an explicit
`ExtensionDependencies` contract, an injected fixed-count `ExtensionCounter`
actor, the custom `ExtensionAuthorizationPolicy` and a validated typed command.
It also adopts an existing `CommandDefinition`/`CommandRoute` pair through
`ExistingSlashCommand`, preserving the low-level response owner.

`DiscordBotExtensions` separately selects the reviewed bot graph. Its reusable
`ExtensionEvents` module has an explicit `ExtensionEventDependencies` contract,
a custom public READY selector and an exact synthetic completion-event handler.
Callbacks keep application actors and stop ownership injected; module construction
starts no tasks, subscriptions, network requests or registration.

Install modules under an explicit `ModuleNamespace`. Namespaces qualify authoring
IDs while preserving Discord command/route/event wire names. The dependent module
validates immutable configuration before its lazy body is expanded. Its injected
actor and callbacks run only during explicit host/router execution.

```sh
swift test --package-path Packages/DiscordDSLExtensions
swift run --package-path Examples/DSLCommands DSLCommands --offline
swift run --package-path Examples/DSLBot DSLBot
python3 Tools/ci/dsl_extension_fixtures.py
```

The HTTP consumer verifies signed synthetic typed/raw/denied callbacks and exact
actor effects. The macro-free bot consumer imports both reusable modules and
verifies real client ingestion, the custom selector, a decoded command, one HTTP
callback, explicit stop and zero retained owned counters. External compile fixtures
require a successful public consumer, then actual semantic errors for omitted and
wrong typed dependencies. The example actor bounds both observation counts to eight
and retains no credential, submitted value, per-user key or queue.

This establishes local cross-package extensibility and ownership behavior. Live
Discord, platform deployment and capacity qualification remain separate.
