[//]: # "File: Packages/DiscordDSLExtensions/Sources/DiscordBotExtensions/DiscordBotExtensions.docc/SharingEventModules.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Share event modules without creating another host

Inject callbacks into a downstream module and retain startup and cleanup at the composition root.

## Overview

``ExtensionEvents`` composes custom public typed selectors and handlers through
the existing event contribution protocols. ``ExtensionEventDependencies`` captures
explicit READY and stop callbacks. Construction and compilation invoke neither;
the application's bounded event pipeline owns execution and cancellation.

The independent DSLBot consumer selects this library, installs its module under
an explicit namespace and compiles it with the client's chosen intents. It also
selects the command extension library and passes shared actor/services into both
compositions. Module count creates no extra client, subscription authority or
credential quota. The custom stop handler requests nonjoining stop; the outer
runtime joins client and pipeline cleanup.

The selected event library adopts BotDSL's reviewed client/command graph, while
the separately selected command library retains its smaller graph. Neither
requires macros or SwiftSyntax. The consumer's local peers exercise real client
ingestion and exact HTTP callback JSON without Discord credentials or sockets.

Read the [extension guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/ModuleExtensions.md)
and [bot application guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/BotApplications.md)
for identity, authority sharing, intent validation, trusted receipt and joined
cleanup. Offline composition does not establish live Discord provenance, platform
qualification or production capacity.
