# Phase 5E execution

Date: 2026-10-16. Source: the master roadmap's independent expressions/media work
package. Readiness review preserves the prior phase history and the existing
platform/device/live/soak gates; these are independent of this REST slice.

1. Verify current Emoji, Sticker, Soundboard, Permissions, API reference, change log
   and official specification; retain hashes separately from original discovery pins.
2. Implement all 25 current written-reference operations: ten Emoji, eight Sticker
   and seven Soundboard, including Get Sticker Pack and Soundboard play.
3. Preserve nullable/deleted/animated emoji, premium restrictions, application/guild
   ownership, packs/unknown sticker formats, default sound IDs and availability.
4. Validate request presence/bounds, data URIs and direct multipart fields; preserve
   bounded source ownership and explicitly document media/eligibility server checks.
5. Add scoped reuse/invalidation and snapshot no-op reconciliation without hidden
   fetches, generic mutation packing or invented list pagination.
6. Link actual fields, symbols and tests in reviewed parity, append chronology and
   ambiguity decisions, explicitly regenerate and review outputs, run root/example/
   tooling/load validation, then stage without committing.

## Validation evidence

The final source candidate passed on macOS arm64 with Apple Swift 6.4. All
checks used current verification dates; no historical `--as-of` override was used.
No Discord credentials or live Discord requests were required.

- Root `swift build` and `SWIFTNIO_STRICT=1 swift test`: **641 methods in 71
  suites across 12 bundles**. Coverage includes all 25 expression/media operations,
  every written model field, validated requests, upload limits/framing/replay,
  malformed bodies, exact 201/200/204 contracts, authentication/API/transport
  errors, finite 429 retries, cancellation, scoped reuse/expiry/invalidation and
  actual zero/one-request snapshot reconciliation. Optional application emoji
  renames and the backward-compatible String initializer are included.
- Independent REST-only example: build passed without authenticated execution.
- DiscordKitTools: **93 Swift tests / seven suites** and **10 Python tests** passed.
  Explicit `generate --write` reviewed five artifacts; only the two documentation
  reports changed. Subsequent `generate --check` is byte-identical across all five.
  Inventory validation and parity checks pass: **18,137 original discovery entries,
  280 sources, zero unclassified IDs, 388 reviewed definitions and 128 mapped
  implemented endpoints**. These counts are not an API parity percentage.
- Independent load harness: **18 Swift tests / three suites**, **eight Python peer
  tests** and the release build passed. The six serial offline HTTP profiles below
  passed request reduction, finite retries, sampled resource/RSS and cleanup gates.
  Normal workloads had zero refusals and met the 100-ms successful p99 target.
  Every run ended with zero active/queued/coalesced/cache owners. Burst refusals
  are expected bounded admission outcomes.

| Logical accounts | Mode | Successes | Refusals | Avoided exchanges | Successful p99 ms | Peak RSS MiB |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 100 | normal | 2,000 | 0 | 1,147 | 10.343 | 10.22 |
| 100 | burst | 1,179 | 821 | 1,048 | 35.856 | 12.69 |
| 10,000 | normal | 10,000 | 0 | 5,912 | 10.248 | 11.62 |
| 10,000 | burst | 6,679 | 3,321 | 5,807 | 70.619 | 14.56 |
| 1,000,000 | normal | 20,000 | 0 | 11,983 | 5.358 | 13.92 |
| 1,000,000 | burst | 14,221 | 5,779 | 11,847 | 94.544 | 17.94 |

These profiles exercise the shared pipeline with synthetic logical served-user
dimensions, 2/4/16 actual credential partitions and no sockets or Discord traffic.
They establish no Discord quota throughput, distributed fairness, simultaneous
user connections, or soak qualification. Current source hashes and known upstream
chronology remain separate from original discovery membership pins.

Managed sandbox cache/socket restrictions were resolved with writable isolated
caches, `--disable-sandbox` and authorized local socket access. A stale cache with
mixed `/tmp` and `/private/tmp` aliases was replaced by a fresh canonical cache;
no production code change was needed. Release debug-symbol creation also required
host access. All final checks passed; no validation failure remains outstanding.
Other hosts/devices, live API conformance, durable external coordination and
long-soak qualification remain the existing separate open gates. Phase 5E makes
no new deployment capacity claim. The final intended diff is staged for review;
no commit is created by this task.
