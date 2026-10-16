# Changelog

Library changes and upstream Discord changes are recorded separately. Historical
Discord behavior, announcement/effective dates, verification evidence and
per-operation support belong in the [parity records](Docs/Parity/README.md).
Unknown upstream dates must remain unknown; a local commit date is not evidence
of when Discord introduced a feature.

## Unreleased

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
