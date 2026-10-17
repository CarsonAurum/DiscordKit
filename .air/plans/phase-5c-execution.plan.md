# Phase 5C execution

Date: 2026-10-16. Source: the master roadmap's independent Guild work package.
Clean committed 5B baseline d3657a0 passed the root build and all 459 strict macOS
Swift test methods before implementation. Existing platform/device/live/soak gates
remain separate; the focused readiness review found no implementation blocker.

1. Verify current Guild, Permissions, Voice, API version, change log and official
   schema revision; record source hashes separately from original discovery pins.
2. Implement all 45 current Guild operations (reusing active threads), complete
   written guild-owned models/requests and explicit preview compatibility.
3. Preserve member screening pending state, exact IDs/permission strings, future
   variants and partial related resources. Add bounded lazy member/ban traversal,
   explicit no-op reconciliation and partial-result bulk-ban plans.
4. Cover wire/status/auth metadata, field boundaries, failures/cancellation,
   correlation/request counts and scoped visibility invalidation deterministically.
5. Update reviewed inventory, chronology and docs; explicitly regenerate, review
   output, run root/example/tooling/load checks and stage without committing.

## Validation evidence

All checks passed on macOS arm64 with Swift 6.4; no Discord credentials or live
Discord requests were used.

- Root `swift build` and `SWIFTNIO_STRICT=1 swift test`: 522 test methods in
  57 suites across 12 test bundles. The clean 5B baseline had 459 methods.
- Independent REST-only example: build passed, without authenticated execution.
- DiscordKitTools: 93 Swift tests in seven suites and 10 Python tests passed.
- Inventory: 18,137 original discovery entries and 280 sources, zero unclassified
  IDs; 303 reviewed definitions and 91 uniquely mapped implemented endpoints.
- Explicit `generate --write` reviewed five outputs. Only the two documentation
  reports changed; generated production Swift and fixtures remained unchanged.
  Subsequent `generate --check` was byte-identical and `parity check` passed.
- Load harness: 18 Swift tests in three suites and eight Python peer tests passed.
  Release harness build and all six offline HTTP profiles passed.
- Final source review corrected scoped property declarations and source anchors in
  reviewed metadata; no discovery membership or original source pin was replaced.
  Endpoint integration tests exercise all 45 current Guild descriptors.
- Documentation, local links, generated-output diff and whitespace checks passed.

Validation used isolated writable compiler/package caches and `--disable-sandbox`;
loopback adapter/peer tests used the permitted local socket environment. A stale
mixed cache-path issue in the tools subprocess resolved with a fresh isolated
scratch/module cache. An existing message-policy assertion was updated for the
new visibility invalidation tag, then the entire strict root suite passed.

## Offline HTTP measurements

These are finite deterministic executor scenarios using scripted responses and
profiled logical-account cohorts, not measurements of live Discord or a deployment
serving the named number of users. Burst refusals are expected bounded admission.


| Profile | Mode | Successes | Refused | Avoided exchanges | p99 ms | Peak RSS bytes |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| accounts-100 | normal | 2000 | 0 | 1135 | 11.118 | 10469376 |
| accounts-100 | burst | 1303 | 697 | 1164 | 39.040 | 13287424 |
| accounts-10000 | normal | 10000 | 0 | 5900 | 10.439 | 12419072 |
| accounts-10000 | burst | 6653 | 3347 | 5793 | 55.180 | 15138816 |
| accounts-1000000 | normal | 20000 | 0 | 11984 | 4.553 | 14647296 |
| accounts-1000000 | burst | 14419 | 5581 | 11971 | 88.615 | 19038208 |

All profiles met configured RSS, sampled resource and p99 targets, reported no
unexpected failures, and ended with zero active/queued requests, read flights and
cache entries after shutdown. Measurements and hardware metadata were recorded
outside the repository as local validation artifacts.

Cross-platform/device and minimum-OS qualification, live API behavior, network/TLS
changes, blocked-I/O and long-soak cases, and durable distributed coordination
remain separate open gates. This phase adds no runtime capacity qualification.
