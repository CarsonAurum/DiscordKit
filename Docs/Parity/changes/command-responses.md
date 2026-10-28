<!--
File: Docs/Parity/changes/command-responses.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Command response ownership and signed HTTP applications

Recorded, verified and local support date: **2026-10-18**. The **0.15.0 candidate**
remains unpublished. Upstream announcement/effective dates are **unknown**: this additive Swift
authoring/composition change introduces no new Discord wire operation. REST/Gateway
v10, Voice v8, RPC v1, MLS 1.0 and DAVE v1 remain unchanged.

Previously, the macro/manual command path supplied schemas and exact routes while
applications owned acknowledgement, signed HTTP composition and registration. The
new immediate and deferred protocols return validated JSON response values through
restricted contexts. The existing unique responder sends the immediate message or
acknowledges before deferred user work and completes through edit-original. Manual
handlers retain raw responder access. Envelope and complete schema validation precede
acknowledgement/user work, and cancellation or uncertain delivery never causes a blind
second response or mutation replay. The macro uses the explicitly selected handler
family and preserves its original manual default.

`CommandApplication` composes existing signed ingress and bounded routing, rejects
application auto-defer and owns an explicitly injected listener only during `run`.
Construction, dispatch and ordinary run make zero registration requests. Explicit
`synchronize` uses the existing reconciler, preserving unmanaged commands and partial
progress. The independent DSLCommands package defaults to a synthetic signed `/ping`
exchange; listener mode is explicit. See [response contracts](../../CommandResponses.md)
and [migration](../../Migration.md).

Existing products keep independent adoption. CommandDSL adds direct HTTP/Transport
dependencies for host composition; its runtime selects no Gateway/Client/Cache,
concrete adapter, macro plugin or SwiftSyntax. No existing API is removed. See the [authoring guide](../../DSLAdoption.md)
for separately selected message builders, command families, policies and Gateway hosts.

The official [interaction reference](https://docs.discord.com/developers/interactions/receiving-and-responding),
[command reference](https://docs.discord.com/developers/interactions/application-commands),
[API reference](https://docs.discord.com/developers/reference),
[change log](https://docs.discord.com/developers/change-log) and
[Swift concurrency chapter](https://docs.swift.org/latest/documentation/the-swift-programming-language/concurrency/)
were reviewed for the affected contracts. [Exact source hashes](../../Release/sources/2026-10-18-command-responses.json)
identify those inputs. Existing discovery classifications and historical evidence
remain unchanged. Synthetic signed HTTP and already trusted normalized-context tests
do not establish authorized live Discord, a Gateway host, other platforms, production
capacity or independent security review.
