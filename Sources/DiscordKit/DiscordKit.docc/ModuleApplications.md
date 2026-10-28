[//]: # "File: Sources/DiscordKit/DiscordKit.docc/ModuleApplications.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Adopt modular command and bot authoring

Choose protocol or macro syntax while preserving explicit service, response and host ownership.

## Overview

### Follow the authoring path

Start with <doc:AuthorCommandModules> for a minimal macro `/ping`, handwritten
protocol handlers, shared actor dependencies and bounded policies. Continue to
<doc:ComposeGatewayModules> for typed ordered event pipelines, then
<doc:HostAModuleBot> for one supervised client and trusted interaction bridge.
All three use independently compiled packages with explicit offline execution.

Shared DSL declarations select Core/Models only. CommandDSL adds finite typed input,
family routes, validated message builders and response adapters over existing
Commands/Interactions/HTTP/Transport. BotDSL composes the existing client and those
command/event owners. Macro authoring and extension packages remain separate
downstream selections. Existing direct consumers need no conversion.

### Preserve the three ownership stages

Modules declare explicit identities and contributions. Compilation admits finite
structure, captures schemas and validates metadata/intents without starting work.
An explicitly run host invokes handlers through existing bounded owners. None of
those ordinary stages registers commands. Review compiled definitions and call
synchronization separately, retaining unmanaged registrations and partial outcomes.

Typed Sendable dependencies retain application-owned actors and services.
Dependency validation is synchronous/local and precedes lazy body creation;
invocation awaits actors through ordinary isolation. Namespace components qualify
structural installation identity without rewriting command routes or event handler
IDs. Share aggregate authorities across modules rather than deriving one per module.

### Select response and deployment ownership

Immediate handlers return one initial response. Deferred handlers confirm defer
before user work and finish by editing the original. Manual families retain the
existing responder explicitly. Input preparation precedes policies and deferral;
typed contexts expose no raw response authority. Expiry, cancellation and ambiguous
delivery never cause automatic replay or a second initial reply.

HTTP deployment owns HTTPS termination, exact signed byte preservation and listener
configuration. Gateway hosts select explicit intents, subscribe before client
startup and join child cleanup. Handlers request nonjoining stop; external owners
await completion. Only client ingestion authenticates Gateway interactions, whose
callbacks still use HTTP and independent initial-response admission.

Use <doc:TestingApplications>, <doc:DeploymentState> and <doc:Compatibility> before
deployment. The [repository adoption guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/DSLAdoption.md)
connects protocol/macro commands, operator semantics, actor dependencies, test
commands and direct API escape hatches. The
[design guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/DSLDesign.md)
records product graphs and evidence boundaries. Local/offline qualification does
not imply live Discord, other platforms, hardware or production/fleet capacity.

## Topics

### Work through independent examples

- <doc:AuthorCommandModules>
- <doc:ComposeGatewayModules>
- <doc:HostAModuleBot>

### Read the product guides

- <doc:/DiscordDSL>
- <doc:/DiscordCommandDSL>
- <doc:/DiscordBotDSL>
