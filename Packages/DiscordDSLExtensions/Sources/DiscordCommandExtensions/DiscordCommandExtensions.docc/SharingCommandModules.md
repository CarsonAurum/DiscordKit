[//]: # "File: Packages/DiscordDSLExtensions/Sources/DiscordCommandExtensions/DiscordCommandExtensions.docc/SharingCommandModules.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Share a command module and its actor dependencies

Build a downstream protocol library that both signed HTTP and Gateway hosts can adopt.

## Overview

``ExtensionArguments`` and ``UppercaseCode`` implement public argument protocols
without macros. ``ExtensionCommand`` retains manual response ownership, while
``ExtensionCommands`` collects that typed handler beside an exact existing raw
command adapter. The independent package's tests compile against public APIs;
it requires no runtime-source edit or development-only test support.

``ExtensionDependencies`` retains one ``ExtensionCounter`` actor, immutable local
configuration and an explicit async completion callback. Validation checks only
configuration. A dependent module admits and validates that contract before body
creation, while handlers/policies await the actor during invocation. Construction
and compilation make zero service calls. ``ExtensionAuthorizationPolicy`` and the
handler share the exact injected actor; replacing it per module would split the
application's authority.

The signed HTTP DSLCommands example and supervised DSLBot example select this
library explicitly. Both install it under a namespace, compile its declarations
and apply its explicit policy. Namespace components qualify structural IDs without
renaming command routes. The command-only library excludes Gateway, Client, Cache,
concrete adapters, compiler plugins and SwiftSyntax.

Read the [extension guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/ModuleExtensions.md)
and [adoption guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/DSLAdoption.md)
for limits, actor isolation, policy order, direct adapters and response modes.
The example's fixed counters and synthetic authorization are finite teaching
services; they are not a production authorization or fleet-capacity qualification.
