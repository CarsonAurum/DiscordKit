# Phase 5 execution plan

Date: 2026-10-16. Source: Part 5 in the master roadmap.

The user selected **5A: messages and polls** as this independent staged work
package. Batches 5B–5J remain pending. This change must not claim the whole REST
catalog or untested-platform qualification.

1. Review the clean committed Phase 4 baseline and run its build, root, example,
   tooling, generation, parity and load checks before implementation.
2. Verify the current official API v10 message, poll, component and upload
   contracts and change log. Preserve the distinction between upstream dates
   and the local implementation date.
3. Implement bounded, presence-aware Message/Poll response schemas, typed nested
   message values, forward references/snapshots, reaction variants and Components V2.
4. Implement create/edit payload validation, attachment retention, poll creation,
   mention control, voice constraints and replayable streaming uploads with separate
   per-file and complete-request limits.
5. Implement every currently documented message/poll descriptor, including search
   indexing, current/deprecated pin routes, reaction variants and poll voters/expiry.
   Keep shared credential/rate/retry/ordering policies in the existing HTTP pipeline.
6. Add finite lazy pagination, bounded indexing retries and explicit bulk-delete
   chunking with completed/indeterminate progress preserved. Never merge mutations
   implicitly or use short search pages as an exhaustion signal.
7. Link supported behavior and remaining nested-family gaps to reviewed contracts,
   inventory and chronological history. Regenerate committed reports explicitly.
8. Test model and request boundaries, endpoint wire shapes, auth/API/transport
   failures, cancellation, request counts, pagination/search and upload cleanup.
9. Run root build/tests, independent example/tooling/load checks, deterministic
   generation and parity; review the complete diff and stage the intended changes.
10. Suggest a commit message from the final staged snapshot without creating a commit.

## Baseline

Clean HEAD a2fae07 passed root build and strict tests (300 methods), REST-only
example build, tooling Swift tests (87), tooling Python tests (10), load Swift
tests (18), load Python tests (8), inventory validation, byte-identical generation
and parity checks. Local loopback tests used approved host access after sandbox
bind restrictions. Platform/device, live Discord, long-soak and durable-coordinator
qualification remain separate open gates.

## Completed execution

Implemented the selected 5A slice: 22 message/poll descriptors, message-owned
response projections and named variants, create/edit validation, Components V2,
bounded replayable uploads, search/indexing continuation and explicit bulk-delete
plans. Related User/Application/Channel/Sticker/interaction projections remain
explicitly partial; batches 5B–5J remain pending. No dependencies were added.

Current official source hashes and upstream chronology are recorded separately
from original discovery pins. Reviewed records now include 307 handwritten field
contracts and 111 named variant mappings across 124 definitions. Explicit offline
regeneration changed the two documentation reports; all five generated artifacts
pass byte-for-byte checks and generated Swift behavior is unchanged.

Final macOS validation (2026-10-16):

- Root build and SWIFTNIO_STRICT=1 root tests: 392 methods, 45 suites, 12 bundles.
- Independent REST-only example build; no authenticated execution.
- Tooling: 93 Swift methods in seven suites and ten Python tests.
- Load harness: release build, 18 Swift methods in three suites and eight Python tests.
- Current inventory, generation check and parity validation; local documentation links,
  explicit method documentation audit and whitespace review.
- Six serial offline HTTP profiles: all three logical served-user populations in normal
  and burst modes, zero unexpected failures and zero active/queued/flight/cache ownership
  after shutdown. All sampled resource budgets passed. Normal p99 values were
  8.856 / 10.719 / 4.651 ms with no refusals. These short scripted checks do not
  qualify deployment capacity, Discord quotas or long-running behavior.

The full run exposed an existing cancellation-test race: initial admission could be
mistaken for the retry queue before a scripted 429. A transport barrier now proves
the rejection first; three focused strict reruns and the final full suite pass.
Loopback tests and Xcode release dSYM generation used approved host access after
sandbox restrictions. Non-macOS/device/minimum-OS, live Discord, network replacement,
durable distributed coordination and soak qualification remain open.
