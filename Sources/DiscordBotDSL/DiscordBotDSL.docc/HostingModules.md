# Host modules with an explicit supervised lifetime

Compile intent-checked events and commands, then start one owner for the client and its pipelines.

## Overview

### Compile before starting work

`EventCompilation` validates explicit intent requirements, handler identities and
finite group admission without executing handlers. The
[DSLEvents example](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/DSLEvents)
uses a custom typed selector and two ordered modules over one bounded subscription.
It explicitly runs the pipelines with a synthetic `RESUMED` envelope and starts no
client. Same-shard handling is serialized; separately selected independent groups
provide cross-group progress with no global ordering guarantee.

The [DSLBot example](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/DSLBot)
imports independently compiled command/event extensions and injects local peers
into the real client. Its application factory captures shared services, intents,
startup/lease/resource authorities, compiled plans and the trusted interaction
adapter. Constructors and compilation start no subscriptions, tasks, client,
registration or I/O. Dependency values retain the exact injected actors.

### Start and join one supervised owner

`BotApplication.makeRuntime` is the explicit composition root. `BotRuntime.run`
subscribes before starting the existing client, then supervises client, event and
optional interaction children. It closes and joins admitted work on stop,
cancellation, setup failure and child failure. Underlying cleanup errors remain
observable. A stopped runtime is single-use.

Handlers request nonjoining `requestStop`; external owners await `run` or joining
`shutdown`. A handler must not await a shutdown that joins itself. User callbacks
must cooperate with cancellation and keep child work structured. Closing a runtime
does not infer ownership of every injected shared transport; the composition root
retains the existing client's explicit dependency cleanup contract.

### Admit interactions through the existing trust boundary

Only the client's package-internal ingestion boundary supplies trusted Gateway
interaction provenance. Normal event-hub publication cannot authenticate a command.
The bridge checks exact application identity and existing malformed/family input
admission before handlers. A synthetic peer exercises local composition without
proving Discord provenance.

Gateway receipt preserves existing HTTP callback delivery. Initial response
admission remains independent of ordinary REST; immediate, deferred and manual
adapters retain one acknowledgement, receipt-relative deadlines, continuation
expiry and uncertainty. `BotServiceAdapter` delegates typed REST with relative
timeouts through the existing shared service context. Registration is explicit;
constructing, compiling or ordinarily running a bot synchronizes zero commands.

### Retain shared authority and actual evidence

Share credential, startup, lease, event, handler, REST and resource authorities
across modules and client replacements. Inject externally coordinated authorities
for multiple workers. Namespaces qualify structural installation identity without
renaming command routes or handler IDs. Queue overflow/freshness changes require
explicit bounded recovery; reconnecting does not replay handler effects.

Test subscribe-before-startup, stop-before-run, cancellation during startup,
handler-requested stop, child and cleanup failures, public-publication rejection,
exact callback JSON and zero final owned counters. The independent examples
provide deterministic offline references; handler/compiler benchmarks and
cache/broadcast soak cover separate workloads. Live Discord, other platforms,
devices and production/fleet capacity remain distinct qualification gates.

The [adoption guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/DSLAdoption.md)
and [bot lifetime guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/BotApplications.md)
give the full host, response and deployment contracts. This selected product
composes Client/CommandDSL while shared and command-only products keep independent
graphs. Concrete adapters, macros, Voice, Social and OAuth remain application choices.
