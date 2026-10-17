# Phase 5F execution

Date: 2026-10-16. Source: the master roadmap's independent discovery/events batch.

The clean committed 5E baseline d8f5224 passed root build and strict root tests:
**641 methods in 71 suites across 12 bundles**. Prior independent slice records
include their example, tooling, generation/parity and local load results. Existing
platform/device, live Discord, durable coordination and soak gates remain separate
from this independent REST work package.

1. Verify all current Invite, Guild Template, Guild Scheduled Event and Stage
   Instance operations against official written references, preview schemas,
   permissions, API versions and change log; retain current hashes separately
   from original discovery membership pins.
2. Implement all 25 resource-family operations through the shared bounded HTTP
   pipeline, reusing existing channel/guild invite creation/listing contracts.
3. Complete invite-owned nested projections, bounded CSV upload/export and finite
   lazy job observation; preserve explicit bulk grouping and partial/uncertain progress.
4. Model template snapshots with typed integer placeholders, validated metadata and
   explicit synchronization; retain partial referenced User/Application projections.
5. Implement complete event/stage-owned fields, current recurrence validation,
   hosting constraints, status transitions, finite subscriber continuation and
   explicit snapshot no-op helpers without background hydration or prefetch.
6. Link implemented fields, variants, endpoints, declarations and fixtures to
   reviewed parity, chronology and ambiguity decisions. Regenerate explicitly
   and review every changed generated artifact.
7. Run root build/strict tests, independent REST example, tooling/Python checks,
   inventory/generation/parity validation and affected local HTTP load profiles.
   Review documentation, diff and method coverage, then stage without committing.

## Validation evidence

The final candidate passed on macOS arm64 with Apple Swift 6.4, using current
verification dates and no historical `--as-of` override. No Discord credentials or
live Discord requests were used.

- Root `swift build` and `SWIFTNIO_STRICT=1 swift test`: **731 methods in 84
  suites across 12 bundles**, zero recorded issues. The prior baseline was 641
  methods/71 suites. Coverage includes every one of the 25 descriptors through
  real injected HTTP policy, complete owned-field presence and unknown variants,
  exact statuses/authentication/errors, finite 429 retries, cancellation/cleanup,
  credential-scoped read reuse/expiry/invalidation, CSV framing/export/job states,
  bulk target chunking and correlated uncertain progress, placeholder compatibility,
  recurrence/hosting/status boundaries and finite bidirectional subscriber traversal.
  Maximum event-image bodies preserve the full 1 MiB decoded limit inside a
  2 MiB complete encoded-JSON cap. Snapshot reconciliation proves zero/one actual
  requests without hidden synchronization or refresh.
- Independent REST-only example: build passed without authenticated execution.
- DiscordKitTools: **93 Swift tests in seven suites** and **10 Python tests**
  passed. Inventory validation and parity checks pass: **18,137 discovery entries,
  280 sources, zero unclassified IDs, 465 reviewed definitions and 153 mapped
  implemented endpoints**. These counts are not an API parity percentage. The new
  slice contributes 77 manual contracts, 307 exact declaration anchors and 95
  validator-compatible test anchors. Historical membership/source pins remain intact.
  Explicit `generate --write` changed only the two documentation reports; subsequent
  `generate --check` is byte-identical across all five committed output artifacts.
  Generated Swift and fixture output are unchanged.
- Independent load harness: **18 Swift tests in three suites**, **eight Python
  peer tests** and the final release build passed. The six serial offline HTTP
  profiles below passed request reduction, finite retry, sampled resource/RSS
  and cleanup gates. Every run had zero unexpected failures and ended with zero
  active/queued/coalesced/cache owners. Normal workloads had zero refusals and
  met the 100-ms successful p99 target; burst refusals are bounded admission outcomes.

| Logical accounts | Mode | Successes | Refusals | Avoided exchanges | Successful p99 ms | Peak RSS MiB |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 100 | normal | 2,000 | 0 | 1,143 | 10.508 | 10.16 |
| 100 | burst | 1,171 | 829 | 1,040 | 39.377 | 12.64 |
| 10,000 | normal | 10,000 | 0 | 5,898 | 10.143 | 11.75 |
| 10,000 | burst | 6,616 | 3,384 | 5,766 | 63.484 | 16.23 |
| 1,000,000 | normal | 20,000 | 0 | 11,982 | 4.639 | 13.73 |
| 1,000,000 | burst | 14,271 | 5,729 | 11,926 | 90.265 | 17.81 |

These short profiles use synthetic logical served-user dimensions and 2/4/16
actual credential partitions in one process, with no sockets or Discord traffic.
They establish no Discord quota throughput, distributed fairness, simultaneous
user connections or soak qualification.

The first validation attempts hit managed compiler-cache and loopback-socket
restrictions; canonical writable caches, `--disable-sandbox` and authorized local
socket access resolved them. Python peer tests likewise required local socket
access, and release dSYM generation used host access. New Invite cache fixtures
initially omitted learned rate headers, so immediate re-fetch correctly queued on
the unknown-route provisional throttle with stationary manual time. Supplying the
same explicit learned-rate fixture as existing integration tests resolved those
six test timeouts; the final complete strict run passed with no issues. Production
rate policy was preserved. Other hosts/devices, live API conformance, durable
external coordination and long-soak qualification remain separate open gates.

Source compatibility: ChannelInvite guild, assigned-role and scheduled-event
properties now use typed projections. Explicit old generic type annotations need
migration; exact rawFields remain available. Historical support entries and
original discovery source membership pins remain preserved.

Documentation links, explicit method documentation, semantic inventory changes,
generated output and whitespace were reviewed. The complete intended Phase 5F
diff is staged for review; no commit is created by this task.
