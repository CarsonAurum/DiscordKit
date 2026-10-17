# Phase 6 execution

Date: 2026-10-16. The existing Part 3 implementation supplies the early sharded
lifecycle required by Part 6 steps 1–5. This phase extends the independent Models
and Gateway products with the current written JSON v10 dispatch/command catalog,
correlated bounded request execution and separate Gateway opcode admission.

1. Verify current official Gateway, event, opcode, API-version and change-log
   references. Preserve historical discovery membership/pins; record fresh source
   fingerprints separately. Review the full receive catalog, intents/capabilities,
   channel obfuscation, voice status/timing and opcode-rate-limit contracts.
2. Add typed decoding for all 79 documented opcode-zero dispatch names, including
   READY/RESUMED, RATE_LIMITED, current channel/soundboard and monetization events.
   Keep sparse updates, unavailable guilds, exact unknown fields and unknown names.
   State inherited partial child-resource projections separately from named coverage.
3. Add the 13 documented opcode values, all 21 intents, Identify capabilities and
   validated outgoing presence/voice/member/soundboard/channel-info contracts.
   Preserve the documented JSON/uncompressed transport and control-loop ownership.
4. Add bounded request execution with nonce/chunk correlation for members and
   exclusive guild/family correlation for soundboard/channel-info, which have no
   upstream nonce. Retain partial progress and explicit cancellation, deadline,
   disconnect, overflow and rate-limit failures. Never replay requests implicitly.
   Admission is separate from REST; reserve room for heartbeats and bound metadata.
5. Cover catalog/encoding boundaries, all lifecycle/close-code classes, request
   chunk ordering, duplicates, limits, timeout/cancellation and cleanup using Swift
   Testing and injected clocks/peers. Run root build/tests, independent REST-only
   build, tool/Python suites and affected offline Gateway load scenarios.
6. Append chronological parity/history and reviewed evidence, explicitly regenerate
   and review all committed outputs, review the complete diff, stage and create the
   requested commit. Report actual validation and any remaining platform/live/soak
   qualification gates without turning synthetic cohort labels into capacity claims.

## Validation evidence

No authenticated Discord request or real credential is required. The current source
verification and local support date is 2026-10-16; the tooling audit used the actual
UTC day **2026-10-17**, without historical `--as-of` overrides.

| Check | Result |
| --- | --- |
| Root `swift build` | Passed for final production source; the final strict test build also compiled all test declarations. |
| Root `SWIFTNIO_STRICT=1 swift test` | Passed: 1,126 test methods in 129 suites across 12 target bundles, including local loopback adapters. |
| Focused catalog/runtime coverage | Eight model methods cover 79 dispatch fixtures, 62 payload matrices and the real asynchronous worker-stack regression. The Gateway target passes 75 methods in six suites. |
| Explicit `generate --write --repository .` | Five artifacts reviewed; only two documentation reports change. Repeating the write changed zero artifacts before final evidence-anchor integration. Generated Swift and fixture outputs remain unchanged. |
| `inventory validate --repository .` | Passed: 18,137 discovery entries, 280 sources and zero unclassified discovery IDs. |
| `generate --check --repository .` | Passed: all five committed artifacts are byte-identical. |
| `parity check --repository .` | Passed: 891 reviewed definitions and 240 mapped implemented endpoint records. Event-name coverage remains separate from full typed child-resource parity. |
| Discovery Python tests | Passed: 10 tests. |
| Tooling Swift tests | Passed: 93 methods in seven suites, including generated-template compilation. |
| Independent REST-only consumer | `swift build --package-path Examples/RESTOnly` passed without running authenticated operations. |
| Independent load-harness Swift tests | Passed: 20 methods in three suites. |
| Load-harness Python peer tests | Passed: eight tests. |
| Independent release load-harness build | Passed; all six Gateway profiles passed recorder/resource/cleanup gates. |

The overlay appends 161 reviewed definitions: 79 partial event definitions,
62 handwritten partial payload structures plus the availability enum, four open received-value contracts,
11 command/value contracts, three runtime groups and the existing close-code policy.
It links 870 real source anchors, 63 named test anchors and 234 owned-field
contracts. Exactly 467 discovery records change status/evidence; membership,
ordering, original source pins and all other records remain unchanged. All 730
previous reviewed definitions, 2,984 previous symbol anchors and 781 previous
evidence anchors are preserved unchanged. The inventory retains its compact
record-per-line formatting.

The finite policies and synthetic workloads do not establish live Discord behavior,
new hosts/devices, distributed adapter certification or sustained runtime capacity.
The root restricted run could not bind local sockets. The identical compiled
strict suite passed with host loopback permissions (`--skip-build`); this was an
environmental permission failure, not a live Discord failure. Validation used
isolated writable Clang/Swift/package caches and `--disable-sandbox`. No external package
dependencies or target concurrency settings changed; the load harness explicitly
imports the existing DiscordModels product. Independent load-harness checks and final finite measurements are recorded below.

## Offline Gateway measurements

The refreshed six release captures exercise the production Gateway actors with
synthetic transport, no sockets, no real credentials and no live Discord requests.
The logical served-user populations select 1/4/16 actual local sessions across
1/2/4 synthetic bot identities. Each shard reconnects twice and completes three
member, three soundboard and three channel-info requests across its ready generations.
That produces 12 typed response events and 15 application writes per shard.

| Logical users | Mode | Sessions / bots | Control p99 ms | Event lag p99 ms | CPU one-core % | Peak RSS MiB |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 100 | Normal | 1 / 1 | 0.038 | 0.070 | 211.7 | 9.84 |
| 100 | Burst | 1 / 1 | 0.031 | 0.143 | 211.7 | 9.83 |
| 10,000 | Normal | 4 / 2 | 0.052 | 0.320 | 323.4 | 11.91 |
| 10,000 | Burst | 4 / 2 | 0.043 | 1.161 | 333.2 | 11.66 |
| 1,000,000 | Normal | 16 / 4 | 0.486 | 2.655 | 409.3 | 12.80 |
| 1,000,000 | Burst | 16 / 4 | 0.423 | 3.128 | 430.2 | 13.25 |

All profiles delivered their exact synthetic dispatch targets (10,000/100,000/
100,000), completed 2/8/32 Resumes, 3/12/48 requests per family and 12/48/192
response decodes, and left zero pending requests, application writes, connections
or leases. The changed fixture permits at most one requested heartbeat per socket
generation to respect the new connection-event admission policy, so control sampling
contains at most three observations per shard. Earlier one-Resume/control-per-eight-
dispatch captures used a different workload and are not directly comparable.
These finite artificial runs do not establish live network throughput, production
Discord quotas, distributed fairness, platform/device qualification or soak capacity.
