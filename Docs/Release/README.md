# Release certification

Invocation resilience advances the unpublished root API candidate to **0.17.0**,
adding explicit Gateway invocation recovery and immutable safe failure diagnostics.
See [validation](invocation-resilience-validation.json),
[adoption and attribution limits](../BotApplications.md) and the separately named
[root API baseline](api-baseline-0.17.0.json). Existing snapshots and reports remain
historical. No release or tag is published, and offline tests do not attribute
MiniCarson's pre-existing Failed state or establish live Discord acceptance.

The historical integrated [SwiftLog work](../Logging.md) advanced the unpublished root API
candidate to **0.16.0**, adding two independently adopted logging products.
Its [validation record](logging-validation.json) covers actual local checks,
with a separately named [root API baseline](api-baseline-0.16.0.json): 33 modules
and 14,511 symbols on macOS arm64. Compared with 0.15.0, this adds 266 symbols
in two logging modules and changes/removes no existing symbols or relationships.
That checkpoint compared 0.16.0 with both frozen historical snapshots and its new baseline;
macro/extension APIs retain their existing 0.15.0 baselines. The authoring checkpoint and its
measurements below remain historical and do not certify this source revision.
No package/tag is published by this work.

The **0.15.0 authoring checkpoint** covers Parts 15A-15L: [shared declarations](../DSL.md),
[typed commands](../CommandDSL.md), [macros](../MacroDSL.md),
[response ownership and signed HTTP](../CommandResponses.md),
[message builders](../MessageBuilders.md), [command families](../CommandFamilies.md),
[policies](../CommandPolicies.md), [typed Gateway event modules](../GatewayEventModules.md)
and [supervised bot applications](../BotApplications.md), with
[external modules and typed dependencies](../ModuleExtensions.md), plus
[offline direct/DSL measurements and finite budgets](../DSLBenchmarks.md), and
[design](../DSLDesign.md), [adoption](../DSLAdoption.md) and migration guidance.
Earlier milestone validation records remain historical. The checkpoint
[machine report](phase15l-report.json) and [15L validation record](phase15l-validation.json)
state its recorded checks and explicit exclusions. The [readable release record](phase15l.md)
summarizes the evidence. This completes the locally verifiable
[DSL milestones](../DSLImplementationRoadmap.md); production capacity and external
qualification remain separate gates. The [15K report](phase15-report.json) retains
its checkpoint evidence.

The historical [0.14.0 candidate report](2026-10-18.md) and
[machine-readable certification](phase14-report.json) retain their exact evidence
and excluded claims. Historical snapshots remain unchanged and do not certify new
source. No checkpoint is a published package release or tag.
Use [release tooling](../ReleaseTooling.md), [CI](../CI.md),
[setup](../Setup.md) and [migration](../Migration.md) for repeatable adoption/release work.

Release candidates use semantic versions. Additive public API requires a minor
increment; source removals or changed declarations require a major increment (or an
explicit pre-1.0 minor increment under the checked policy). Patch versions cannot add
or break API. Upstream Discord changes have their own announcement/effective/verified
dates in [append-only history](../Parity/history.json); they do not silently change
the local package version. A symbol graph compares declarations and relationships on
its captured platform, not binary ABI or unavailable platform branches.

The reviewed [runtime 0.15.0 baseline](api-baseline-0.15.0.json) captures 31 modules
and 14,245 symbols on macOS arm64. Its comparison with the preserved 0.14.0 baseline
adds 1,010 symbols without changed or removed symbols. The separately selected
[macro](api-baseline-macros-0.15.0.json) and
[extension](api-baseline-extensions-0.15.0.json) baselines capture five and 86 symbols.
CI retains these authoring comparisons while checking the current root baseline
and historical root migrations. First authoring baselines prove no earlier
compatibility, behavioral compatibility or binary ABI.

Before release, refresh affected official sources, classify discoveries, update dated
transition fixtures, run certification and review migration notes. Review official
documentation and pinned specification/source diffs **at least weekly**; the
[maintenance record](maintenance.json) expires after seven days. The scheduled workflow
captures upstream hashes/diffs for human review without modifying production source.
An unchanged hash does not establish semantic coverage of unrelated documentation.

Every runtime release carries workload, hardware, throughput, p50/p95/p99, CPU/RSS,
request savings, overload/recovery and fixed-working-set 30-minute evidence. The
[measurements](Measurements/environment.json) identify Phase 14's earlier finite
synthetic runs. Part 15K reruns the existing cache/broadcast profiles and 30-minute
fixed-working-set soak, preserving exact source/executable identity. Independent
direct/DSL handler measurements and a separate sustained-handler run cover their
recorded workloads and durations. Manual/macro compiler costs and finite local
budgets establish the first measured baseline. A baseline self-check does not prove
a comparison against an earlier implementation or controlled performance regression.
15L preserves these hash-bound observations and verifies their runtime and benchmark
source identities; it does not present them as new timing or soak runs.
None of these workloads establishes production capacity.
Reproduce greater-than-10% regressions three times on matching hardware
and workload before attributing them. Concurrent build/test activity and historical
baselines do not provide such a controlled comparison. See [scalability](../Scalability.md).

Passing local checks cannot close absent native implementations, hardware/host access,
live Discord, independent crypto review, complete codec/MLS/DAVE interoperability,
production/fleet or entire-platform parity gates. The report excludes those claims and
fails validation when a claim relies on an unverified check.
