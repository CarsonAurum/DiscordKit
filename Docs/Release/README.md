# Release certification

The current **0.15.0 authoring candidate** covers Parts 15A-15J: [shared declarations](../DSL.md),
[typed commands](../CommandDSL.md), [macros](../MacroDSL.md),
[response ownership and signed HTTP](../CommandResponses.md),
[message builders](../MessageBuilders.md), [command families](../CommandFamilies.md),
[policies](../CommandPolicies.md), [typed Gateway event modules](../GatewayEventModules.md)
and [supervised bot applications](../BotApplications.md), with
[external modules and typed dependencies](../ModuleExtensions.md).
Earlier milestone validation records remain historical. The current
[machine report](phase15-report.json) and [15J validation record](phase15j-validation.json)
state current checks and explicit exclusions. Capacity work and the remaining
[DSL milestones](../DSLImplementationRoadmap.md) retain separate implementation gates.

The historical [0.14.0 candidate report](2026-10-18.md) and
[machine-readable certification](phase14-report.json) retain their exact evidence
and excluded claims. Historical snapshots remain unchanged and do not certify new
source. Neither checkpoint is a published package release or tag.
Use [release tooling](../ReleaseTooling.md), [CI](../CI.md),
[setup](../Setup.md) and [migration](../Migration.md) for repeatable adoption/release work.

Release candidates use semantic versions. Additive public API requires a minor
increment; source removals or changed declarations require a major increment (or an
explicit pre-1.0 minor increment under the checked policy). Patch versions cannot add
or break API. Upstream Discord changes have their own announcement/effective/verified
dates in [append-only history](../Parity/history.json); they do not silently change
the local package version. A symbol graph compares declarations and relationships on
its captured platform, not binary ABI or unavailable platform branches.

Before release, refresh affected official sources, classify discoveries, update dated
transition fixtures, run certification and review migration notes. Review official
documentation and pinned specification/source diffs **at least weekly**; the
[maintenance record](maintenance.json) expires after seven days. The scheduled workflow
captures upstream hashes/diffs for human review without modifying production source.
An unchanged hash does not establish semantic coverage of unrelated documentation.

Every runtime release carries workload, hardware, throughput, p50/p95/p99, CPU/RSS,
request savings, overload/recovery and fixed-working-set 30-minute evidence. The
[measurements](Measurements/environment.json) identify Phase 14's earlier finite
synthetic runs. Part 15J reruns the existing cache/broadcast profiles and 30-minute fixed-working-set
soak, with exact source drift and executable identity retained in its measurement record.
Those results cover the cache/broadcast harness; they are not DSL handler execution,
controlled performance regression or capacity evidence. Part 15K retains direct-versus-DSL
handler measurements and DSL-specific soak qualification.
Reproduce greater-than-10% regressions three times on matching hardware
and workload before attributing them. Concurrent build/test activity and historical
baselines do not provide such a controlled comparison. See [scalability](../Scalability.md).

Passing local checks cannot close absent native implementations, hardware/host access,
live Discord, independent crypto review, complete codec/MLS/DAVE interoperability,
production/fleet or entire-platform parity gates. The report excludes those claims and
fails validation when a claim relies on an unverified check.
