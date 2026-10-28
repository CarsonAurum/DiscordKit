[//]: # "File: Sources/DiscordBotDSL/DiscordBotDSL.docc/Guides/InvocationRecovery.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Recover invocation failures and observe diagnostics

Select `failurePolicy: .continueInvocations` when constructing
``GatewayInteractionAdapter`` to keep serving after an ordinary invocation fails.
The default ``GatewayInvocationFailurePolicy/failFast`` preserves supervised shutdown.

## Preserve response and lifetime ownership

Recovery observes matched handler, acknowledgement, continuation and structurally
valid unmatched-command failures after router cleanup. Expired acknowledgement or
token windows end only that invocation. Recovery sends no response, retries no
operation, refreshes no token and never repeats a handler. An indeterminate callback
remains indeterminate; confirmed deferral retains the existing responder state.
Applications reconcile possible side effects explicitly.

Malformed input or routing shape, failed typed preparation, untrusted provenance,
wrong application, input overflow/continuity loss, cancellation and owner/setup
failures remain terminal. Closed safe owner evidence is captured before HTTP or
continuation error translation, preserving terminal authority failures even when
the public error correctly remains mutation uncertainty. The generic Gateway dispatcher and ``BotRuntime`` continue
to cancel and join siblings on terminal failure. Constructing these values starts
no tasks, registration or I/O; synchronization remains explicit.

## Consume finite safe metadata

Pass ``BotFailureObserver`` separately to the adapter for invocation failures and
the runtime for terminal operation failures. The synchronous nonthrowing callback
receives only ``BotFailureDiagnostic``: a fixed stage/category and optional numeric
HTTP status/API code/fatal close code. It must return promptly and support concurrent
calls. The library creates no observer tasks, queue or token-indexed retention.
Unknown injected errors map to `unclassified`. No arbitrary error formatting,
interaction options, credentials, bodies, headers, URLs or route paths are exposed.

``BotFailureDiagnostic/classify(_:stage:)`` classifies aggregate errors separately,
up to three entries; nested aggregates are unclassified. Runtime aggregates retain
bounded safe observations alongside explicit original error access.

Setup/client/event/router/lease-release stages are recorded at owned boundaries.
Known response failures record one closed safe fingerprint per invocation, without
changing errors visible to application catches; successful operations clear it.
The router correlates matching fingerprints with acknowledgement/continuation
observations. Unknown or differently mapped errors use the handler boundary.
Same-category application replacements cannot be distinguished causally; diagnostic
stages describe observations and do not establish mutation retry safety.

Local synthetic regression tests establish ownership/recovery behavior only.
Live Discord acceptance, platform/hardware qualification and production capacity
require separate evidence.
