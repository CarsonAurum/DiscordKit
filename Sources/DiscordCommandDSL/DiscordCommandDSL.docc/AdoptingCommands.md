# Adopt typed commands over existing response owners

Move one command at a time into an inert compiled catalog and choose its host explicitly.

## Overview

### Start with an independently compiled command

The [DSLCommands package](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/DSLCommands)
contains the minimal macro-authored `/ping`. Its empty argument value and immediate
handler generate ordinary runtime protocols. The separate
[extension package](https://github.com/CarsonAurum/DiscordKit/tree/main/Packages/DiscordDSLExtensions)
shows handwritten ``CommandArguments``, ``ArgumentValue`` and
``ManualSlashCommandHandler`` implementations with no compiler plugin selection.
Use the complete packages for manifests, imports and tests; the umbrella tutorials
display synchronized copies of those sources.

``CommandCompilation`` captures finite schemas and lowers explicit module
contributions to existing command definitions and routes. Complete input decoding
creates a fresh argument value for each invocation. Partial resolved references
cause no hydration and grant no current authorization. Construction, compilation
and policy application invoke no handlers or services and register nothing.

### Select one response contract

| Contract | Ownership |
| --- | --- |
| ``SlashCommandHandler`` | Return ``MessageResponse`` for one initial reply. |
| ``DeferredSlashCommandHandler`` | The adapter confirms defer before user work; return ``DeferredMessageResponse`` for edit-original completion. |
| ``ManualSlashCommandHandler`` | Explicitly use the existing responder and its acknowledgement/continuation state. |
| Other typed families | Preserve separate autocomplete, modal-opening, message-update and message-reply response kinds. |

Typed contexts omit the raw responder. Complete input preparation happens before
policies or deferral. The existing response owner retains deadlines, token expiry,
cancellation and uncertainty; a failed or ambiguous delivery is not an invitation
to retry side effects or send a fallback initial response. Do not add competing
application auto-defer around a typed deferred adapter.

``MessageBuilder`` and ``ComponentBuilder`` lower through existing payload
validators. Shared message interpolation escapes ordinary strings and neutralizes
untrusted mention spelling. Use typed mentions and explicit allowlists when
notifications are intended. Raw Models, exact field presence and intentional raw
markup remain available.

### Apply explicit policies and shared admission

``CommandPolicies`` runs after typed preparation. Inject current authorization;
registration permission defaults and cached resources remain observations.
Generic named `and`/`or`/`negated` match `&&`/`||`/`!`, with left-to-right short
circuiting. Named `then` matches `>>>`: the left middleware enters first and exits
last on success. Cleanup on errors requires `defer` or explicit error handling.

Every structure has finite limits. Reuse ``CommandConcurrencyLimit`` or an injected
``CommandConcurrencyAuthority`` across catalogs for aggregate admission. Command
terminal execution is single-use and closes with middleware. Denial/error mapping
is explicit, response-family checked and never retries a mutation. HTTP rate
coordination remains with the existing shared authority.

### Choose HTTP or Gateway receipt

``CommandApplication`` verifies signed HTTP receipt and invokes the existing
bounded router. Inject the shared acknowledgement admission and an explicit
listener. Its ordinary run owns that listener without registering commands;
``CommandApplication/synchronize(using:deadline:)`` explicitly reconciles the
reviewed managed catalog. The DSLCommands default/`--offline` run verifies genuine
synthetic Ed25519 input without sockets. `--listen` explicitly binds loopback;
deployment owns HTTPS and original signed byte preservation.

Select BotDSL separately for supervised Gateway interaction receipt. Only client
ingestion supplies trusted input. Callback delivery remains HTTP with independent
initial-response admission and the same response families. Command-only adoption
continues to exclude Gateway, Client, Cache, concrete adapters and compiler plugins.

### Migrate and test incrementally

``ExistingSlashCommand`` adopts an exact supported root slash definition and route.
``ExistingCommandFamily`` adopts validated low-level families. Existing direct
consumers need no conversion. Inspect definitions, keep unmanaged registrations
and synchronize only deliberately.

The [adoption guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/DSLAdoption.md)
connects these APIs to protocol/macro sources, actor dependencies, exact callback
tests and deployment ownership. Test malformed/absent/null input, zero compile-time
effects, policy short circuiting, response uncertainty and cancellation cleanup.
Offline examples qualify their local contracts; live Discord, platform and
production-capacity gates retain separate evidence.
