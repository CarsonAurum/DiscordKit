[//]: # "File: Packages/DiscordDSLExtensions/Sources/DiscordBotExtensions/DiscordBotExtensions.docc/DiscordBotExtensions.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# ``DiscordBotExtensions``

Import reusable typed event modules across an ordinary package compilation boundary.

## Overview

``ExtensionEvents`` combines the custom public selector in ``ExtensionReadyHandler``
with the exact synthetic completion filter in ``ExtensionStopHandler``. Its required
``ExtensionEventDependencies`` captures the application's explicit ready and stop
callbacks. Captured actors, authority sharing and host termination remain caller owned.

Install the module under an explicit `ModuleNamespace`, compile it with existing
`EventCompilation` and supply the compiled declarations to an explicit `BotRuntime`.
Construction and compilation execute no callbacks, subscriptions, tasks, client
startup, registration or I/O. The existing bounded event pipeline owns execution,
cancellation, ordering and failure propagation; callbacks never create a second host.

This separately selected product adopts the reviewed BotDSL graph. Command-only
extensions retain their independent graph, and neither library requires macros,
SwiftSyntax or compiler plugins. The independent macro-free bot demonstrates a
custom READY selector, ignored unrelated future events and explicit nonjoining stop
over local injected peers. Live Discord, platforms and DSL capacity remain separate.

## Topics

### Adopt reusable events

- <doc:SharingEventModules>

### Complete public API

- <doc:APIReference>
