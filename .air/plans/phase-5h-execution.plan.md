# Phase 5H execution

Date: 2026-10-16. Baseline: clean committed Phase 5G a33989a. Its execution
record reports 831 strict root test methods in 97 suites; this phase revalidates
the complete final tree. Existing device/other-host, live API, distributed authority
and soak qualification gates do not block the independent REST catalog batch.

1. Review repository, roadmap, existing validation evidence and current official
   Webhook/Interaction/Voice references, API version, change log and preview schemas.
2. Implement complete owned bounded models/validated payloads and all 28 written
   operations, typed token binding, bounded uploads and explicit response variants.
3. Preserve credential-scoped reuse/order, separate webhook IP-global admission,
   interaction exemptions, finite retry/cancellation/deadline/cleanup semantics.
4. Update current source fingerprints, semantic/field evidence, ambiguity decisions,
   chronological parity and documentation; explicitly regenerate and inspect outputs.
5. Run focused/root/strict tests and build, independent REST example, tools/Python,
   inventory/generation/parity checks and affected serial offline HTTP load scenarios.
6. Review the complete diff, stage all intended changes, verify staged/unstaged
   state and suggest the commit message. Do not create a commit.

## Validation evidence

Validated locally on macOS arm64 with Swift 6.4. All credentials and peers were
synthetic; no authenticated operation or live Discord request ran.

| Check | Result |
| --- | --- |
| Root `swift build` | Passed after the final source changes. |
| Root `SWIFTNIO_STRICT=1 swift test` | Passed: 938 test methods in 111 suites across 12 target bundles; includes parameterized executions and real local loopback adapter tests. |
| Focused model/HTTP suites | Passed for webhook, interaction, voice, path credentials and IP-global admission, including final V2 edit-upload and deprecated callback regressions. |
| Independent REST-only example build | Passed after the final source changes; no authenticated calls executed. |
| Tooling Swift tests | Passed: 93 methods in seven suites, including generated-template compilation. |
| Discovery Python tests | Passed: 10 tests. |
| Load-harness Swift tests | Passed: 18 methods in three suites. |
| Load-harness Python peer tests | Passed: eight tests with local socket access. |
| Explicit `generate --write --repository .` | Reviewed all five artifacts. Only two documentation artifacts differ from the baseline; generated Swift source is unchanged. |
| `inventory validate --repository .` | Passed: 18,137 discovery entries, 280 sources, zero unclassified discovery IDs; 639 reviewed definitions and 211 mapped implemented endpoints. |
| `generate --check --repository .` | Passed: all five artifacts are byte-identical. |
| `parity check --repository .` | Passed; discovery counts describe records rather than unique implemented operations. |
| Complete diff review | JSON syntax, relative Markdown links, method documentation, scoped statuses and prior-record preservation checked; `git diff --check` passed. |

Swift validation used isolated writable Clang/Swift module and package caches,
`--disable-sandbox`, and approved host loopback access where necessary. Tooling also
used an isolated scratch path. Initial default-cache and restricted-socket errors
were environmental; their affected commands passed with these settings. The tool
audit date was the actual UTC date **2026-10-17**; no historical `--as-of` override
was used. Source verification and local support dates use **2026-10-16** locally.

All earlier reviewed definitions, symbols, evidence and source pins remain
semantically unchanged. This phase adds 75 manual definitions, preserves exact
discovery membership, and updates current support/evidence for the implemented
slice. The earlier partial guild-scoped region review remains historical; this
phase qualifies all five region fields with the global region read.

## Offline HTTP measurements

Built the independent load harness in release mode and ran all six profiles
serially with `record_baseline.py --scenario http`, writing temporary results
outside the repository. The offline adapter uses artificial 1 ms latency and an
artificial global allowance to isolate policy overhead. Cohort labels represent
served-user configurations, with only 2/4/16 synthetic bot identities in one process;
they do not establish that those numbers of users or connections were exercised.

| Cohort / bot identities / mode | Successes | Bounded refusals | Avoided exchanges | p99 ms | Peak RSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| 100 / 2 / normal | 2,000 | 0 | 1,161 | 9.784 | 10.31 |
| 100 / 2 / burst | 1,109 | 891 | 993 | 38.512 | 12.75 |
| 10,000 / 4 / normal | 10,000 | 0 | 5,906 | 9.657 | 11.95 |
| 10,000 / 4 / burst | 6,817 | 3,183 | 5,946 | 50.534 | 14.94 |
| 1,000,000 / 16 / normal | 20,000 | 0 | 11,981 | 4.555 | 13.91 |
| 1,000,000 / 16 / burst | 14,423 | 5,577 | 11,978 | 83.338 | 18.22 |

All six passed resource/RSS gates, exercised retries/read reduction/every identity,
and retained zero active requests, queues, flights or cache entries after shutdown.
Normal workloads had zero refusals and met configured p99 targets; burst refusals
were expected bounded overload. Latencies retain at most 4,096 successful prefix
samples. These short local measurements do not qualify Discord quotas, distributed
stores, live network throughput, devices, other hosts, minimum OS or long soaks.
