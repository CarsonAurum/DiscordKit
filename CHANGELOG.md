# Changelog

Library changes and upstream Discord changes are recorded separately. Historical
Discord behavior, announcement/effective dates, verification evidence and
per-operation support belong in the [parity records](Docs/Parity/README.md).
Unknown upstream dates must remain unknown; a local commit date is not evidence
of when Discord introduced a feature.

## Unreleased

### 2026-10-16 — Gateway dispatches and bounded requests (Phase 6)

- Add typed recognition of all 79 documented opcode-zero dispatch names, preserving
  sparse/unavailable resources, exact raw fields, unknown values and event names.
- Add all 13 Gateway opcode values, 21 named intents, Identify capabilities and
  validated presence, voice-state, member, soundboard and channel-info commands.
- Add bounded request correlation, nonce/chunk completion, partial progress,
  cancellation/deadlines, rate-limit outcomes and connection-generation cleanup.
- Separate opcode admission from REST/startup scheduling and reserve control
  headroom; preserve shared all-members quota scope and server cooldowns.
- Record current source hashes, upstream chronology, channel-obfuscation migration
  and deterministic evidence. Child-resource schemas and platform/live/soak gates
  retain explicit limits; JSON/uncompressed transport remains the protocol choice.

### 2026-10-16 — monetization REST catalog (Phase 5I)

- Add all eight current SKU, Entitlement and Subscription REST operations with
  exact IDs, owned fields, unknown values and explicit Bot/Bearer authorization.
- Add typed guild/user test-entitlement ownership and complete premium interaction
  entitlements, including perpetual partial test responses and subscription linkage.
- Preserve current subscription status values, nullable renewal/cancellation data
  and private-scope country omission; subscription state never grants premium access.
- Add finite lazy traversal with retained filters, exclusive cursors, cancellation,
  deadlines, page budgets and response scope checks, without prefetch or hidden reads.
- Retain credential-scoped reuse/invalidation, unsafe mutation outcome semantics,
  current source fingerprints, upstream chronology and deterministic regression evidence.
  Broader Commerce, Gateway catalogs, 5J and existing qualification gates remain open.

### 2026-10-16 — emoji, stickers and soundboard REST catalog (Phase 5E)

- Add all 25 current Emoji, Sticker and Soundboard operations with complete written
  resource-owned models, validated requests and explicitly partial User projections.
- Preserve Unicode/deleted/animated emoji, application/guild ownership, sticker packs,
  unknown formats, default sound IDs and required nullable sound emoji fields.
- Add bounded data-URI media and direct sticker multipart creation; document caller/
  server responsibility for dimensions, duration, premium eligibility and voice state.
- Share authentication-scoped read reuse and invalidation; add opt-in snapshot no-op
  reconciliation without hidden reads, bulk mutations or invented pagination.
- Record current official hashes, written/preview conflicts, upstream chronology and
  deterministic fixture evidence; batches 5F–5J and Gateway event catalogs remain pending.

### 2026-10-16 — audit logs and Auto Moderation REST catalog (Phase 5D)

- Add all six current audit-log and Auto Moderation operations with typed entries,
  changes, options, rules, actions and trigger metadata; keep related-resource
  projections and Gateway coverage explicitly partial or pending.
- Preserve exact heterogeneous change values, nullable targets, unknown action codes
  and nested fields; validate outgoing trigger/action metadata and bounded exemptions.
- Add finite lazy audit traversal in either exclusive cursor direction, retaining
  referenced objects, and explicit snapshot-based rule reconciliation without hidden reads.
- Share credential-scoped admission, coalescing and opt-in freshness; invalidate rule,
  audit and affected guild snapshots after successful moderation mutations.
- Record current official contracts, written/preview discrepancies, upstream chronology
  and deterministic regression evidence; batches 5E–5J remain pending.

### 2026-10-16 — guild administration REST catalog (Phase 5C)

- Add all 45 current Guild operations, reusing active threads, with typed guild,
  member, ban, role, integration, widget, welcome, onboarding and incident contracts.
- Validate settings, token consent payloads, role colors and fixed-clock moderation
  windows; preserve exact IDs, unknown values and screening pending state.
- Add finite lazy member/ban continuation, explicit snapshot no-op reconciliation
  and sequential bulk-ban plans retaining partial failures and uncertain progress.
- Invalidate authentication-scoped guild/channel/message visibility after guild
  mutations; keep public widgets credential-free and retained payload diagnostics redacted.
- Record current official contracts, preview compatibility, removed guild-creation
  history and deterministic regression evidence; batches 5D–5J remain pending.

### 2026-10-16 — channel and thread REST catalog (Phase 5B)

- Add every documented channel descriptor plus active guild threads: settings,
  overwrites, invites, announcement follows, typing, group-DM recipients, voice
  status, thread/forum/media creation and membership/archive enumeration.
- Preserve the complete Channel field surface, unknown variants/bits, exact
  permission strings, nullable application IDs and flagged obfuscated state.
- Validate type-specific requests and forum initial-message/upload compatibility;
  bound invite CSVs, reuse shared upload ownership and invalidate visibility snapshots.
- Add lazy member/archive workflows with correct v10 pagination, distinct
  timestamp/ID cursors, member correlation and explicit no-op settings reconciliation.
- Record current contract verification, upstream chronology and deterministic
  regression evidence. Related resource families and batches 5C–5J remain pending.

### 2026-10-16 — message and poll REST catalog (Phase 5A)

- Add typed descriptors for all current message/poll routes, including indexing
  search, burst reaction reads, current/deprecated pins and poll voters/expiry.
- Add presence-aware message/poll and component projections, request validation,
  forwards/snapshots, voice metadata, Components V2 and attachment retention.
- Bound multipart uploads separately per file and per complete request; retain
  producer cleanup, byte admission, credential isolation and conservative retry policy.
- Add finite lazy pagination/search polling and explicit ordered bulk-delete plans
  preserving completed, attempted and unattempted progress on failure.
- Link current official contract verification and deterministic regression evidence
  to parity/history records; keep batches 5B–5J and related-family gaps explicit.

### 2026-10-16 — reviewed inventory and schema generation

- Add versioned reviewed contracts with per-field semantics, pinned provenance,
  stable symbol/evidence links and separate upstream/local support dates.
- Generate the existing partial model/endpoint slice, reviewed documentation and
  fixture/parity indexes deterministically, offline and outside consumer builds.
- Add nonwriting inventory, generation and parity checks, explicit regeneration,
  freshness checks and negative regression tests for incomplete contracts/evidence.
- Derive parity counts from validated records while preserving partial projections,
  unsupported discovery records and handwritten runtime policy.

### 2026-10-16 — HTTP execution and early sharded Gateway

- Add independent Models/HTTP/Gateway products preserving Swift 6.4 concurrency settings.
- Add fixed-origin API v10 typed/raw descriptors, bounded codecs/errors, replayable bodies,
  pagination/polling, credential-free assets and a standalone REST-only example.
- Add partitioned injectable rate authority, finite FIFO scheduling, mutation ordering,
  deadlines and safe retry/indeterminate-outcome handling.
- Add independently cancellable scoped read coalescing and opt-in bounded TTL/LRU caching
  with local-write/visibility invalidation and stale-completion fences.
- Retrieve current user/application snapshots and Gateway discovery; record their partial
  typed projections separately from complete catalog parity.
- Add supervised sharded Gateway JSON v10 lifecycle, heartbeat/ACK handling, Resume,
  close-code classification, bounded event ingestion, fenced leases and atomic Identify budgets.
- Preserve peer close codes and session-aware reconnect cleanup in Foundation/NIO adapters.
- Batch NIO WebSocket upgrade writes so fast peers cannot upgrade before the request ends.
- Extend deterministic regression and local load evidence; retain explicit host, full-catalog,
  durable-store and sustained-capacity qualification gates.

### 2026-10-15 — owned transport adapters and local qualification

- Add independent Foundation HTTP/WebSocket, NIO HTTP/TLS/WebSocket/UDP/ingress,
  Unix IPC and Apple lifecycle products with explicit cancellation/close ownership.
- Bound connection admission, messages, bodies and queues; preserve send-once
  behavior, reject unsafe wire input and return redirects without credential forwarding.
- Add full-verification TLS policy, shared HTTP conformance and local malformed-peer,
  cancellation, overload and cleanup regression tests.
- Recheck scripted HTTP cancellation and deadlines after suspension before
  transferring request/response ownership or recording successful completion.
- Add shard-routing/fenced lease coordination contracts and a bounded in-process store.
- Add a separate local load harness with versioned account/cohort budgets and measured
  transport baselines. No Discord operation, untested-host or million-connection claim.
- Record Foundation buffering/header limitations and remaining cross-platform,
  Windows IPC, Android, device, media/UI and extended conformance gates.

### 2026-10-15 — scalability design requirements

- Adopt early capacity planning for deployments serving hundreds through millions
  of accounts and multiple bot identities, with explicit workload dimensions.
- Require coordinated rate admission, bounded caches, read coalescing, documented
  bulk request helpers, aggregate budgets and fair scheduling in runtime slices.
- Move sharding design into architecture/transport work and the minimal sharded
  lifecycle alongside the first HTTP slice; add load, overload and failover gates.
- These are roadmap and policy changes; no new runtime support or measured
  account/connection capacity is claimed.

### 2026-10-15 — portable values and transport foundations

- Add independent DiscordBits, DiscordCore and DiscordTransport products with
  arbitrary-width bits, exact identifiers/JSON, field presence and timestamps.
- Add forward-compatible raw values, typed redacted credentials, diagnostic
  redaction, safe errors and explicit capability reporting.
- Define cancellable transport contracts, monotonic deadlines and bounded pull
  bodies with idempotent ownership cleanup; add deterministic test infrastructure.
- Replace `hello()` and the empty test with foundational umbrella APIs and
  consumer tests. Removing `hello()` is a source-breaking scaffold cleanup;
  clients should use the portable APIs or remove their greeting call.
- Declare the existing documented Apple deployment baselines in the manifest.
  No endpoint, network adapter or cross-platform runtime support is claimed.

### 2026-10-15 — architecture and parity foundation

- Record the intended product dependency graph, public API conventions,
  concurrency ownership rules and approved dependency policy.
- Establish platform capability and protocol feasibility records, a versioned
  parity baseline and explicit unresolved upstream contracts.
- Preserve Swift 6.4 and `ApproachableConcurrency`; make the nonisolated default
  deliberate in library and test target settings.
- Keep the `hello()` runtime scaffold. No Discord integration, transport adapter,
  voice codec or cryptographic protocol is claimed as implemented.

This entry describes an unreleased milestone. It has no release version or
published release date. Feasibility findings and inventory coverage limitations
remain part of the baseline; their existence is not a completed support claim.
