# Phase 5I execution

Date: 2026-10-16. Baseline: clean committed Phase 5H c119f10. This batch
implements the master roadmap's monetization REST slice in the existing independent
Models/HTTP products. Broader Commerce, event catalogs and platform qualification
remain separate.

1. Verify current official SKU, Entitlement, Subscription, premium Interaction,
   API version and change-log contracts, retaining unknown upstream dates explicitly.
2. Implement all eight written REST operations, complete owned presence-aware models,
   typed test-entitlement ownership, subscription lifecycle values and premium
   interaction entitlements, without treating subscription state as authorization.
3. Add explicit bounded lazy entitlement/subscription continuation with preserved
   filters, no prefetch, finite page/cursor budgets, cancellation and deadlines.
   Keep mutation ordering, credential-scoped reuse and conservative invalidation.
4. Add deterministic Swift Testing coverage for schemas, unknown/partial values,
   payloads, every route/auth/status, HTTP failures and continuation boundaries.
5. Update source fingerprints, semantic/field evidence, parity history and docs;
   explicitly regenerate and inspect generated artifacts. Run root build/tests,
   independent REST build, tool/Python validation and affected offline HTTP loads.
6. Review the final diff, stage intended changes and create the requested commit.
   Report the commit summary, message and verified validation limits.

## Validation evidence

Validated locally on macOS arm64 with Swift 6.4. All identities, credentials and
responses were synthetic; no authenticated call or live Discord request ran.

| Check | Result |
| --- | --- |
| Root `swift build` | Passed after the final production changes. |
| Root `SWIFTNIO_STRICT=1 swift test` | Passed: 982 test methods in 116 suites across 12 target bundles, including parameterized cases and local loopback adapter tests. |
| Focused monetization/interaction tests | Passed: 55 methods across six suites, including model/request, premium projection, endpoint, integration and bounded traversal coverage. |
| Independent REST-only example build | Passed without executing authenticated calls. |
| Tooling Swift tests | Passed: 93 methods in seven suites, including generated-template compilation. |
| Discovery Python tests | Passed: 10 tests. |
| Load-harness Swift tests | Passed: 18 methods in three suites. |
| Load-harness Python peer tests | Passed: eight tests with local loopback access. |
| Explicit `generate --write --repository .` | Reviewed all five artifacts; only two documentation reports change. Generated Swift source is unchanged. |
| `inventory validate --repository .` | Passed: 18,137 discovery entries, 280 sources, zero unclassified discovery IDs. |
| `generate --check --repository .` | Passed: all five generated artifacts are byte-identical. |
| `parity check --repository .` | Passed: 671 reviewed definitions and 219 mapped implemented endpoints, adding eight operations. |
| Complete diff review | Source documentation, meaningful tests, JSON syntax, Markdown links, scoped support and historical-record preservation checked; `git diff --check` passed. |

Swift validation used isolated writable Clang/Swift module and package caches,
`--disable-sandbox` and host access for local loopback tests and debug-symbol
generation. Initial default-cache and restricted-dsymutil failures were environmental;
the affected validations passed with those settings. Tool audit date was the actual
UTC date **2026-10-17**, with no historical `--as-of` override. Verification and local
support records use **2026-10-16** locally.

This batch adds 32 reviewed contracts, 70 real symbol anchors, 55 test anchors and
26 explicit owned-field contracts. Discovery membership/order and historical source
pins remain unchanged. Only 68 discovery entries in this slice change status/evidence.
The existing interaction contract and entitlement symbol gain typed premium data;
prior evidence and chronological history are preserved.

## Offline HTTP measurements

Built the independent harness in release mode and ran all six profiles serially
with `record_baseline.py --scenario http`, writing temporary results outside the
repository. The adapter uses artificial 1 ms latency and an artificial allowance;
there are no network requests. Population labels describe served-user configurations
with only 2/4/16 actual synthetic bot identities in one process.

| Cohort / bot identities / mode | Successes | Bounded refusals | Avoided exchanges | p99 ms | Peak RSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| 100 / 2 / normal | 2,000 | 0 | 1,155 | 9.386 | 10.41 |
| 100 / 2 / burst | 1,203 | 797 | 1,073 | 31.956 | 12.81 |
| 10,000 / 4 / normal | 10,000 | 0 | 5,881 | 10.732 | 11.97 |
| 10,000 / 4 / burst | 6,607 | 3,393 | 5,771 | 68.175 | 14.73 |
| 1,000,000 / 16 / normal | 20,000 | 0 | 11,984 | 4.640 | 14.14 |
| 1,000,000 / 16 / burst | 14,222 | 5,778 | 11,899 | 86.721 | 18.53 |

All six passed resource/RSS and cleanup gates, exercised retries, read reduction
and every identity, and retained zero active work, queues, flights or cache entries
after shutdown. Normal runs had zero refusals and met configured p99 targets; burst
refusals are expected bounded overload. Latencies retain at most 4,096 successful
prefix samples. These short local measurements do not establish Discord quotas,
live network throughput, distributed-store behavior, other-host/device/minimum-OS
qualification or sustained/soak capacity. Broader Commerce and 5J remain separate.
