# Phase 15A: shared module declarations

Recorded, verified and local support date: **2026-10-18**. This is an additive,
unpublished authoring-layer checkpoint. Upstream announcement/effective dates are
**unknown** because no Discord protocol change is introduced. REST/Gateway v10,
Voice v8, RPC v1, MLS 1.0 and DAVE v1 retain their existing explicit versions.

Previously, consumers composed existing command definitions, routes, interaction
owners and Gateway clients directly. `DiscordDSL` adds a shared Core/Models-only
structural foundation: protocol-led modules and custom leaves, empty/conditional/
array/loop builders, explicit stable module identities, source locations, bounded
diagnostics and deterministic finite declaration descriptions. A public raw
contribution carries inert application-defined metadata for custom compilation.

Construction and compilation are synchronous. Library composition and validation
start no tasks, network/device/persistence work, command registration or handler
execution. Application-supplied synchronous module bodies and contribution getters
must themselves terminate and remain free of side effects; the library cannot
sandbox arbitrary Swift code. Structural bounds apply to the compiler's admitted
state rather than proving a resource bound for arbitrary user builder code.

Duplicate identities, unavailable contribution capabilities and exceeded structural
limits fail before a validated plan is returned. Declaration order follows builder
order. Existing products gain no upward dependency; shared DSL adoption requires
no Gateway, HTTP, client, cache, concrete adapter, compiler plugin or SwiftSyntax.

Existing consumer code requires no migration. Adopt `DiscordDSL` explicitly for
structural authoring and inspect its offline description. Typed argument decoding,
command lowering, macros, response/message builders, policies, event adapters and
supervised HTTP/Gateway applications remain later milestones in the
[implementation status](../../DSLImplementationRoadmap.md).

No upstream endpoint, payload field, permission, intent, event or opcode support is
added. Existing discovery/reviewed inventories and their support classifications
remain unchanged. The [shared declaration guide](../../DSL.md) explains the local
API; root Swift Testing and graph/documentation/API checks bound the local evidence.
This checkpoint does not qualify live Discord, platforms/hardware, command/event
execution, macro interoperability or capacity.
