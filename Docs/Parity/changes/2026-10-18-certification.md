<!--
File: Docs/Parity/changes/2026-10-18-certification.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Release certification and maintenance

Recorded and verified **2026-10-18**. Local candidate **0.14.0** is unpublished.
REST/Gateway v10, Voice v8, RPC v1, MLS 1.0 and DAVE v1 remain explicit.
The [release report](../../Release/2026-10-18.md),
[machine report](../../Release/release-report-0.14.0.json) and
[maintenance record](../../Release/maintenance.json) bound all claims.

Release validation adds
SwiftSyntax presence enforcement, actual manifest/import/product isolation checks,
all-product public API baseline comparison and semantic version policy, DocC adoption
guides, a compiled command/component example, CI and weekly official-source review.
SwiftSyntax 604.0.0 is a development-tool dependency only; production dependencies,
protocol behavior and public signatures are unchanged. Comprehensive semantic
documentation remains a separate review responsibility from comment presence.

The official [2026-08-12 channel-obfuscation announcement](https://docs.discord.com/developers/change-log#channel-obfuscation-for-users-and-bots)
states an HTTP effective date of **2026-11-16**, still future on this verification
date. Before then, HTTP guild channel lists can include inaccessible channels. From
then, Discord omits them. Gateway obfuscation has a separate temporary opt-in and
interaction payloads follow a separate path. HTTP has no early opt-in.
`GuildEndpoints.channels` documents these dates; dated synthetic regression fixtures
cover pre-effective, boundary, empty and restored responses. The decoder returns the
server list without inspecting local time, inventing rows or turning omission into a
delete event. Exact IDs above 2^53 and UInt64.max remain intact.

No breaking source/API change or consumer code migration is required. Applications
should invalidate stale visibility-sensitive snapshots, re-establish current authority,
and handle a missing channel without asserting deletion. No response snapshot proves
current VIEW_CHANNEL. Existing Gateway cache redaction and indeterminate permission
resolution remain separate evidence.

Platform CI definitions are executable procedures, not historical qualification.
Unavailable infrastructure, devices, approved Discord hosts, independent crypto review,
complete codec/MLS/DAVE interoperability, production/fleet capacity and entire-platform
parity remain explicitly excluded. Local profiles report offered/admitted arithmetic
populations, process CPU/RSS and bounded cleanup rather than live Discord capacity.
