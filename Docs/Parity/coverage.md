<!--
File: Docs/Parity/coverage.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Coverage and qualification

DiscordKit's coverage records distinguish implemented behavior from discovery,
source review and runtime qualification. [Reviewed contracts](reviewed-v1.json) and
[the generated report](generated-reviewed.md) contain the detailed source, symbol and
test mappings. Run `parity check` for validated current totals; duplicate source records
are not unique operation counts.

## Local validation

Root Swift tests use deterministic fixtures, virtual clocks, scripted peers and local
loopback adapters. They require no Discord credentials. Independent packages exercise
consumers, compiler macros, transport probes and finite load workloads. Their recorded
commands, source identities and exclusions appear in the
[release reports](../Release/README.md), [load harness](../../Tools/DiscordKitLoadTests/README.md)
and [DSL measurements](../DSLBenchmarks.md).

| Area | Evidence and supported scope | Separate qualification |
| --- | --- | --- |
| Models and REST | Presence-aware decoding, exact IDs, validated requests, bounded uploads, traversal and partial outcomes | Live authorization, server acceptance and complete related-resource projections |
| HTTP and transport | Shared admission/retry ownership, cache reuse, cancellation, real local TLS/WebSocket/UDP peers | Other-host runtime, root stores, minimum OS, device network changes and production capacity |
| Gateway and client | Typed dispatch names, ordered complete-shard delivery, correlated requests, bounded state and supervised cleanup | Live Discord, fleet coordination, full resource hydration and production throughput |
| Interactions and commands | Signed synthetic HTTP, initial-response ownership, deferral, expiry, uncertainty, routing and explicit synchronization | Authorized live Discord, rendering, notification delivery and live command registration |
| OAuth, game services and Commerce | Published HTTP flows, token lineage, bounded polling and server-authoritative entitlements | Secure-storage/browser implementations, unpublished native SDK wires and Game Shop contracts |
| RPC and Certified Devices | Local v1 framing/session peers, typed commands/events and full-array publication | Real desktop/hardware smoke, Windows named-pipe I/O, conflicting port bounds and presence-clear semantics |
| Activities | Synthetic Swift frames, simulated postMessage hosts and local browser bridge tests | Approved Discord Web/iOS/Android handshake, authentication, participants and purchases |
| Media, codecs and voice | Published vectors, primitive negative tests, synthetic PCM/Opus, bounded queues, local MLS/DAVE peers and session tests | Perceptual codec policy, independent crypto review, complete-client interoperability, devices and authorized Discord |
| Social providers | Explicit consent/capabilities, narrow public HTTP/RPC/Activity composition, bounded local state and PCM controls | Native SDK session/call/relationship schemas, access and platform host behavior |
| Swift authoring APIs | Structural bounds, strict decoding, payload parity, compiled macros, explicit hosts and finite local measurements | Live service behavior, external integrations and production capacity |

The [Social catalog](social-catalog.json), [Activity catalog](activity-catalog.json),
[voice capabilities](voice-media-capabilities.json) and
[method map](../Feasibility/method-contracts.json) name individual missing contracts and
required evidence. A public equivalent may have narrower behavior than the native SDK.
Matching a method or event name never establishes matching authority or lifecycle.

## Probe evidence

The dated [native transport probe](../Feasibility/PlatformTransports.md) exercised three
Swift Testing methods and seven cases on macOS arm64: local HTTP, verified TLS,
trust/hostname rejection, WebSocket upgrade/frame exchange and empty/binary UDP.
All sockets were local IPv4 loopback. These results do not establish other operating
systems, CPU architectures or minimum OS behavior.

The dated [voice primitive probe](../Feasibility/VoicePrimitives.md) exercised five
methods and ten parameterized invocations for standard AEAD, malformed nonces/tags,
an AES known answer and the required HPKE primitive tuple. Primitive success does not
establish MLS, DAVE, codec or complete voice interoperability. Later component evidence
is separately described in [Voice](../Voice.md), [MLS](../MLS.md), [DAVE](../DAVE.md) and
[voice sessions](../VoiceSessions.md).

## Unverified gates

- **Semantic coverage:** extraction, declaration presence and passing tests do not prove
  that every upstream prose contract, field or behavior has been reviewed and implemented.
- **Platform runtime:** configured CI and selected SDK module emissions do not establish
  complete builds, linked applications, simulator/device execution or host capabilities.
- **Native protocols:** missing Social/Commerce schemas, source-only Activity behavior,
  RPC port/presence ambiguities and absent adapters remain explicit boundaries.
- **Media and security:** independent crypto review, complete codec/MLS/DAVE client
  interoperability and advertised device/platform qualification require their own evidence.
  A synthetic local round trip cannot qualify a live voice session or human audibility.
- **Live Discord:** authorized service, Activity/RPC host, purchase and negotiated media
  checks must run on the actual supported surface with fresh eligible interactions.
- **Capacity:** finite synthetic populations, throughput and RSS/accounted-byte reports
  establish only their named workload, hardware and duration. They do not qualify fleets
  or production capacity, and zero owned counters do not prove absence of resident growth.

Qualification claims must name the exact check, source/executable identity, platform,
workload, date and limits. Historical reports retain their original scope and cannot
certify a changed source revision. Missing evidence stays unverified in the
[release report](../Release/README.md).
