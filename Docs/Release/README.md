<!--
File: Docs/Release/README.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Release validation

The current root API candidate is **0.19.0**, with
[publication validation](publication-validation.json), a
[machine report](publication-report.json), the
[root API baseline](api-baseline-0.19.0.json) and its
[compatibility comparison](publication-api-comparison.json). It includes creator and
copyright attribution, publication documentation, updated library identification
and explicit Gateway scheduling construction. The candidate is unpublished and
untagged. Local checks and their scopes are recorded in the report; unrun
qualification gates remain unverified. Historical results cannot certify the
current revision.

The [0.18.0 semantic logging record](semantic-logging-report.json) and its
[baseline](api-baseline-0.18.0.json) retain their historical scope. See
[the migration notes](../Migration.md) for the updated REST identification default
and Gateway construction options.

## Required checks

Use [release tooling](../ReleaseTooling.md) and [CI](../CI.md) for exact commands.
Run the root build/tests, affected independent packages and examples, callable-documentation
audit, manifest/import/product isolation audit, public API comparison, strict DocC
conversion, inventory/generation/parity validation, and applicable browser/Python checks.
Validate machine release and maintenance records with `release_check.py`.

Review affected official sources, refresh their exact hashes and semantic classifications,
update dated protocol-transition fixtures, and check [migration notes](../Migration.md).
The [maintenance record](maintenance.json) expires seven days after review. Scheduled
collection gathers upstream differences for review; unchanged hashes alone do not prove
semantic coverage of unrelated documentation.

Release candidates use semantic versions. Additive public API requires a minor increment;
removed or changed declarations require a major increment, or an explicit pre-1.0 minor
increment under the checked policy. Patch versions cannot add or break API. Discord's
announcement and effective dates remain independent of the local package version.
Symbol graphs compare declarations and relationships on their captured platform; they
do not prove binary ABI or conditional APIs on other platforms.

The root baseline is separate from the
[macro](api-baseline-macros-0.15.0.json) and
[extension](api-baseline-extensions-0.15.0.json) baselines. Earlier
[0.14.0](2026-10-18.md) and [0.15.0](release-0.15.0.md) reports retain dated evidence and
exclusions. Review the applicable baseline and actual source identity for each comparison.

## Measurements

Record workload, hardware, toolchain, executable/source identity, throughput,
p50/p95/p99, CPU/RSS, accounted bytes, request savings, overload/recovery and cleanup.
[Finite load reports](Measurements/environment.json), the fixed-working-set 30-minute
cache/broadcast soak and the separate [direct/DSL measurements](../DSLBenchmarks.md)
cover different workloads and durations. A baseline self-comparison does not establish
a controlled performance comparison against an earlier implementation.

Reproduce regressions greater than 10% three times on matching hardware and workloads
before attribution. Concurrent build/test activity does not provide a controlled
comparison. See [scalability](../Scalability.md). Finite local results do not establish
production or fleet capacity.

## Qualification limits

Passing local checks cannot close missing native implementations, unavailable host or
device execution, live Discord, independent cryptographic review, complete codec/MLS/DAVE
interoperability, semantic documentation completeness or entire-platform parity. Keep
these checks explicitly unverified or excluded in release records. Configured workflows,
synthetic signed HTTP, local UDP peers and selected SDK module emissions establish only
their recorded scope. Publication requires a fresh review of those claims and their
actual supporting evidence.
