<!--
File: Docs/Release/release-0.15.0.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Authoring release candidate

The unpublished, untagged **0.15.0** authoring candidate has the local scope
recorded by the [machine report](release-report-0.15.0-final.json) and
[validation evidence](authoring-release-validation.json). Validation ran on macOS arm64
with Apple Swift 6.4; local date 2026-10-18, execution UTC date 2026-10-19.
REST/Gateway v10, Voice v8, RPC v1, MLS 1.0 and DAVE v1 remain unchanged.

The candidate includes [design](../DSLDesign.md), [adoption](../DSLAdoption.md)
and migration guides, twelve independently buildable example tutorial paths,
32 synchronized listings and public product DocC guides. All 31 root, one macro
and two extension module archives converted with strict diagnostics. The source
audit found zero missing comments among 8,578 explicit callables in 778 files;
separate macro tests inspect the emitted getters, initializers and factories.
These are documentation presence/navigation checks, not semantic completeness.

The root API baseline records 31 modules and 14,245 symbols. Comparing with the
preserved 0.14.0 baseline found 1,010 additions and no changed/removed symbols or
removed relationships. Three additions extend existing command preparation and
interception; the rest belongs to the three DSL modules. The checked pre-1.0
minor-version rule accepts the candidate. Separate first macro/extension
baselines record five/86 symbols. Fresh output matches all three 0.15.0 baselines.
Existing direct consumers need no migration. See [release tooling](../ReleaseTooling.md).

Local validation passed 2,367 root tests across 32 targets, 105 tooling tests,
34 macro tests, 26 external macro compiler fixtures, three dependency compiler
fixtures and the independently built example/test/offline consumers. Graph,
inventory, generation, parity, browser, Social catalog, Python, maintenance and
load/benchmark functional checks passed. Unix/loopback tests used local peers.
No authenticated Discord request was made.

The unchanged runtime and benchmark inputs retain the recorded paired
handler/compiler observations, 30-minute cache/broadcast soak and separate
60-second-per-path handler observations. This validation verifies their exact source hashes
and preserves those artifacts; it does not rerun timing/soak workloads. Finite
budget self-comparison does not establish a controlled performance regression or
production capacity. Current CI selects the new report and separately validates
the historical release reports.

Weekly source maintenance remains current through 2026-10-25. This documentation
update changes no upstream wire classification and performs no fresh upstream
collection or semantic protocol review. Linux/Windows/Android, Apple simulator/
device/minimum-OS runtime, live Discord, hardware, independent crypto review,
complete codec/MLS/DAVE interoperability, other-platform APIs, binary ABI, entire
platform parity and production/fleet qualification remain excluded. Configured
hosted workflows establish no passed platform run.
