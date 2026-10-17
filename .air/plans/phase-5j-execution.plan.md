# Phase 5J execution

Date: 2026-10-16. Baseline: clean committed Phase 5I ca2ecf5. This batch
implements the master roadmap's social/game backend REST slice in the existing
independent Models/HTTP products. Native Social SDK, event dispatch, OAuth consent
flows and platform qualification remain separate.

1. Verify current official Lobby, Application Identity Profile, API version,
   rate-limit and change-log contracts. Preserve historical discovery pins and
   record current hashes separately; document written/specification conflicts.
2. Implement all 16 written Lobby operations and five identity/profile operations,
   complete owned response fields, validated payloads and explicit bot/Bearer
   authorization. Preserve exact unknown values and absence/null distinctions.
3. Add bounded sequential member bulk plans with explicit correlation of returned,
   removed and silently dropped members, partial progress and cancellation. Add
   caller-snapshot no-op reconciliation without hidden fetches or profile merging.
4. Add deterministic Swift Testing coverage of every route, meaningful schema and
   payload boundaries, authorization/status/API/transport/rate failures, request
   reduction, invalidation, cancellation and bounded workflow outcomes.
5. Update reviewed field/operation evidence, discovery statuses, ambiguities,
   chronological history and contract guides. Explicitly regenerate and review
   outputs; run root build/tests, independent REST build, tool/Python checks and
   affected offline HTTP load scenarios.
6. Review the complete diff, stage the intended changes, create the requested
   commit and report the final commit summary, message and validation limits.

## Validation evidence

Validated locally on macOS arm64 with Apple Swift 6.4. All identities, credentials
and responses were synthetic; no authenticated Discord request ran.

| Check | Result |
| --- | --- |
| Root `swift build` | Passed for the final executable implementation. |
| Root `SWIFTNIO_STRICT=1 swift test` | Passed: 1,066 test methods in 125 suites across 12 target bundles, including local loopback adapter tests and parameterized cases. |
| New focused resource coverage | Passed: 84 methods in nine suites (24 lobby model/request, 25 lobby endpoint/integration/workflow, 35 identity/profile model/request/endpoint/integration). |
| Independent REST-only example build | Passed without running authenticated calls. |
| Tooling Swift tests | Passed: 93 methods in seven suites, including generated-template compilation. |
| Discovery Python tests | Passed: 10 tests. |
| Load-harness Swift tests | Passed: 18 methods in three suites. |
| Load-harness Python peer tests | Passed: eight tests with local loopback access. |
| Explicit `generate --write --repository .` | Reviewed all five artifacts; two documentation reports change and generated Swift remains unchanged. A second write changed zero artifacts. |
| `inventory validate --repository .` | Passed: 18,137 discovery entries, 280 sources, zero unclassified discovery IDs. |
| `generate --check --repository .` | Passed: all five artifacts are byte-identical. |
| `parity check --repository .` | Passed: 730 reviewed definitions and 240 mapped implemented endpoint records, adding 21 written operations. |
| Diff and support review | Independent implementation reviews found no executable defects; one unsupported token-side-effect documentation claim was corrected. Source documentation, test assertions, JSON syntax, local Markdown targets, historical preservation and whitespace were reviewed. |

Validation used isolated writable Clang/Swift module and package caches and
`--disable-sandbox`. Host access supplied loopback socket permissions and dSYM
generation. Initial restricted socket/dsymutil attempts failed environmentally;
the affected checks passed with host access. Tool audit date was the actual UTC
**2026-10-17**, without historical `--as-of` overrides; verification/local support
records use **2026-10-16** locally. No dependencies or target settings changed.

This batch adds 59 reviewed contracts, 158 real symbol anchors, 84 test anchors
and 51 owned-field contracts. Exactly 111 discovery entries change status/evidence,
all within the two written resource sources; membership, order, original provenance
and all other entries are preserved. Existing reviewed records remain unchanged;
chronological history is appended and the existing profile-success ambiguity gains
an explicit tested compatibility policy. All 198 new explicit function, initializer
and test declarations have documentation blocks, reviewed with implementation.

## Offline HTTP measurements

Built the independent harness in release mode and ran all six profiles serially
with `record_baseline.py --scenario http`, writing temporary results outside the
repository. These profiles exercise shared HTTP policy, not native Social SDK or
live Discord. The adapter uses artificial 1 ms latency and an artificial allowance;
there are no sockets or network requests. Population labels describe served-user
configurations with only 2/4/16 actual synthetic identity partitions in one process.

| Cohort / identities / mode | Successes | Bounded refusals | Avoided exchanges | p99 ms | Peak RSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| 100 / 2 / normal | 2,000 | 0 | 1,150 | 9.664 | 10.25 |
| 100 / 2 / burst | 1,198 | 802 | 1,075 | 34.020 | 12.97 |
| 10,000 / 4 / normal | 10,000 | 0 | 5,904 | 11.091 | 11.91 |
| 10,000 / 4 / burst | 7,005 | 2,995 | 6,036 | 58.592 | 14.73 |
| 1,000,000 / 16 / normal | 20,000 | 0 | 11,984 | 5.538 | 13.62 |
| 1,000,000 / 16 / burst | 14,172 | 5,828 | 11,903 | 97.550 | 18.02 |

All six passed resource/RSS and cleanup gates, exercised retries, reuse and every
identity, and left zero active/queued/flights/cache entries after shutdown. Normal
profiles had no refusals and met the configured p99 target; burst refusals retained
fixed resource caps. These finite artificial runs do not establish production
Discord throughput, application-wide quotas, distributed fairness, device/network
qualification, native SDK interoperability or sustained/soak capacity.
