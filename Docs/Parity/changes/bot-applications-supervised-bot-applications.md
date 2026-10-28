<!--
File: Docs/Parity/changes/bot-applications-supervised-bot-applications.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Supervised bot applications

Verified on 2026-10-18 for the unpublished 0.15.0 candidate. Upstream announcement
and effective dates are unknown: this change composes existing Gateway/REST v10
owners and introduces no new event, endpoint, intent, permission or model projection.

Previously BotDSL compiled typed event modules and owned their bounded pipelines;
applications assembled client supervision and Gateway command delivery directly.
BotDSL adds the explicit `BotApplication` factory/default entry point and
single-use `BotRuntime`. It subscribes before client startup, supervises client,
event and optional interaction children, and cancels/closes/joins them on all exits.
Noncancellation cleanup failures remain observable. Handlers request stop without
joining themselves; external owners await run or shutdown before handoff.

`GatewayInteractionAdapter` receives only the package-internal client-ingestion
stream. Public broadcast publication cannot authenticate an interaction. Bounded
private queues isolate decoding, service factories and command execution from
client ingestion/control. The original socket receipt age survives queueing so
acknowledgement and continuation lifetimes cannot restart at dispatch. Malformed,
wrong-application and unmatched interactions fail the supervised owner closed.

Gateway responses still use exact-token HTTP callbacks and the existing normalized
context/responder. Initial admission remains independent of ordinary REST;
immediate/deferred/manual ownership, input preparation, expiry and uncertain sends
remain authoritative. `BotServiceAdapter` reuses shared typed services and mutation
invalidation. Construction and ordinary serving issue no registration requests;
explicit synchronization retains the existing managed-name and partial-outcome rules.

BotDSL now explicitly selects Client, CommandDSL and the existing HTTP interaction
owners. Existing products gain no upward dependency, and shared/command-only
adoption remains independent. Concrete adapters, compiler plugins, voice, Social
and OAuth stay optional at the application composition root. Consumers auditing an
event-only product closure must accept BotDSL's expanded host dependencies or use
the existing direct Gateway APIs.

Adopt the [application guide](../../BotApplications.md) and independently compiled
[DSLBot consumer](../../../Examples/DSLBot/README.md). The current official
[Gateway receipt](https://docs.discord.com/developers/events/gateway-events#interaction-create)
and [HTTP response rules](https://docs.discord.com/developers/interactions/receiving-and-responding)
were reviewed in the [source record](../../Release/sources/2026-10-18-bot-applications.json).
Synthetic peers and the existing cache/broadcast soak do not establish live Discord,
other platforms, hardware or DSL handler capacity. External qualification remains separate.
