# Offline DSL measurements

Part 15K supplies the independent development package
[`DiscordDSLBenchmarks`](../Tools/DiscordDSLBenchmarks/README.md). Runtime products
never depend on the benchmark, its compiler fixtures or its scripts. The package
uses public APIs and synthetic interactions; no credentials or Discord calls are
required. Part 15L's [release records](Release/README.md) complete local authoring
candidate certification while preserving external qualification exclusions.

The implementation plan is to establish identical direct/DSL workloads, assert
functional invariants before accepting timings, measure manual/macro compiler costs,
record the first observations, then select explicit finite regression tolerances.
The existing cache/broadcast workload and the new handler workload have independent
artifacts and qualification limits.

The runtime matrix declares 10, 100 and 1,000 handlers. Each path reuses a compiled
catalog and a bounded aggregate router. Direct routes capture their schemas once;
DSL routes use ordinary typed command lowering. Both decode the same finite text
argument, execute the same handler and acknowledge through the existing response
owner into the same synthetic sink. The default offers eight workers and completes
1,000,000 invocations per path and handler count. Handler counts describe declarations,
not simultaneous connections or people served.

Reports separate catalog construction/compilation from steady-state invocation.
They record sampled p50/p95/p99 latency, completed throughput, finite accounted
state, actual process RSS and supported live allocator gauges. Sample count is
bounded independently of invocation count. Accounted state describes named logical
storage; `planDescriptionTextBytes` observes the admitted description during
compilation, which is released after lowering; allocator gauges describe live process allocations, not cumulative allocation
traffic or all transitive Swift object sizes. Peak RSS is a process high-water mark;
workloads in one process share allocator history. Retained allocator pages do not
establish retained handler ownership.

Hard functional gates apply to every run: schemas are not rebuilt during invocation,
responses and decoded values agree, offered work and payload/sample/handler limits
are finite, and owned activity returns to zero after cleanup. No registration or
hydration operation is part of the workload. These checks are independent of timing
regression decisions. Deterministic tests cover invalid configuration, direct/DSL
payload parity, configured limits and cleanup rather than asserting machine speed.

The compiler matrix generates external manual and macro consumers with 10, 100 and
1,000 concrete declarations on the same compiler. Dependency/plugin bootstrap is
reported separately. A clean **consumer** sample removes that target's outputs while
retaining dependency products. An incremental sample changes one response literal
in one file, runs the normal build, then restores the source. These are compiler
process observations, not IDE responsiveness, a cold network/dependency build or
an independent macro-interoperability certification.

The scripts record observations before creating numerical budgets. Comparison
requires matching hardware, toolchain and workload; functional failures, missing
matrix rows and incompatible artifacts fail independently. A single timing overrun
is a local budget failure. Investigate a regression greater than 10% reproduced in
three comparable runs before attributing it to a change, as required by
[scalability guidance](Scalability.md). Hosted CI runs functional tests and a small
smoke matrix without comparing another machine against this host's baseline.

The [15K validation record](Release/phase15k-validation.json) identifies exact
commands, source/executable hashes, compiler/hardware, measurements and limitations.
[Runtime and compiler budgets](../Tools/DiscordDSLBenchmarks/README.md) provide the
reproduction commands. Earlier milestone reports remain historical.

Local synthetic handler and cache/broadcast measurements do not qualify live Discord,
HTTP signature/transport throughput, supervised Gateway event execution, devices,
other platforms, sustained production service or fleet capacity. No performance
claim applies outside the recorded workload. The benchmark introduces no endpoint,
event, permission, intent, model or wire support classification.

The first local matrix used Mac15,10, arm64, 14 logical CPUs, 36 GiB RAM and
Apple Swift 6.4. Concurrent compiler/validation work and the cache soak were active;
these observations establish a baseline, not isolated overhead or regression attribution.
Each runtime row completed exactly 1,000,000 invocations, with unchanged schema
counts and zero active ownership after cleanup.

| Declarations | Path | Invocations/s | Prefix p50 / p95 / p99 (ms) | Plan compile (ms) |
| --- | --- | --- | --- | --- |
| 10 | direct | 59,920 | 0.147 / 0.190 / 0.210 | 1.38 |
| 10 | dsl | 58,890 | 0.132 / 0.169 / 0.185 | 1.12 |
| 100 | direct | 55,991 | 0.142 / 0.182 / 0.205 | 4.02 |
| 100 | dsl | 55,537 | 0.145 / 0.185 / 0.206 | 9.17 |
| 1,000 | direct | 52,283 | 0.155 / 0.195 / 0.214 | 41.03 |
| 1,000 | dsl | 51,222 | 0.161 / 0.201 / 0.219 | 78.34 |

| Declarations | Authoring | Clean consumer (s) | Incremental (s) | Reported clean peak RSS (MiB) |
| --- | --- | --- | --- | --- |
| 10 | manual | 4.034 | 4.107 | 205.95 |
| 10 | macro | 4.269 | 4.261 | 205.86 |
| 100 | manual | 4.619 | 4.526 | 211.14 |
| 100 | macro | 4.603 | 4.304 | 211.59 |
| 1,000 | manual | 6.356 | 4.684 | 241.31 |
| 1,000 | macro | 8.015 | 6.088 | 285.73 |

The runtime/compiler artifacts retain process memory, accounting and complete
configuration data beyond this table. Compiler timings are one sample per operation
and exclude the separately reported dependency/plugin bootstrap. Future candidates
require the same recorded identities and the full matrix for numerical comparison.

The separate 1,000-handler sustained run completed 3,121,728 direct invocations in
60.020 seconds and 3,113,536 DSL invocations in 60.014 seconds. Each path retained
55 actual process-memory observations, unchanged 1,000-schema capture counts and
zero final active owners. It is a 60-second-per-path handler observation; the
cache/broadcast 30-minute requirement is covered by its separate workload.
