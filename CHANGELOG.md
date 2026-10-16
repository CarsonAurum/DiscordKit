# Changelog

Library changes and upstream Discord changes are recorded separately. Historical
Discord behavior, announcement/effective dates, verification evidence and
per-operation support belong in the [parity records](Docs/Parity/README.md).
Unknown upstream dates must remain unknown; a local commit date is not evidence
of when Discord introduced a feature.

## Unreleased

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
