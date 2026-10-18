# Compatibility and migration

The current authoring candidate is **0.15.0**, covering Parts 15A/15B/15C. The
historical Phase 14 checkpoint is **0.14.0**. Neither candidate implies a tag or
package publication. Preserve the
explicit protocol versions REST/Gateway **v10**, Voice **v8**, RPC **v1**, MLS **1.0**
with ciphersuite **2**, and DAVE **v1** independently of the package version.

## Local Swift API changes

Compare the current emitted public symbol graphs with the committed API baseline
before publishing. The baseline records its compiler/platform scope; compare using
the same toolchain and host. Treat removed declarations, signature changes,
default-argument changes, enum evolution, concurrency/isolation changes, behavior
and error contracts as compatibility review inputs. Symbol graph comparison cannot
establish binary ABI, source compatibility on every platform or unchanged behavior.

Use semantic versioning: after 1.0, incompatible public changes require a major
version; backward-compatible additions require a minor version; compatible fixes
require a patch. During 0.x, use a minor increment for breaking API design changes
and document each affected symbol and migration. Do not silently reset a baseline
to make a check pass. Retain the previous baseline/report for release comparison,
review the difference, explain required edits, then adopt the new baseline as part
of the approved release change. Phase 14 establishes the initial recorded baseline;
it introduces tooling/docs/example composition and no intended runtime API removal.

Independent adoption remains the preferred migration path: replace umbrella imports
with the products your consumer needs, inject the shared authorities it owns,
start work explicitly, and await closure. Values with `Field.absent`, `.null` and
`.value` retain different update meanings. Unknown enum values and raw fields do
not prove implemented support for the corresponding upstream feature.

## Adopt typed command authoring

Existing `DiscordCommands` consumers require no migration. Select `DiscordDSL`
for structural modules and `DiscordCommandDSL` for typed argument decoding and
manual root slash handlers. A `SlashCommand` contribution captures one schema and
lowers it to existing `CommandDefinition`/`CommandRoute` values; inspect the
compiled definitions before explicit reconciliation or registration.

To adopt an existing root slash definition and exact matching route incrementally,
wrap them in `ExistingSlashCommand`. This adapter performs no typed decoding and
rejects unsupported families, nesting and autocomplete. Keep full low-level APIs
for those existing capabilities until the corresponding authoring milestone ships.
Use `ManualSlashCommandHandler` with the existing `InteractionContext.responder`
for explicit response ownership. Part 15C optionally replaces schema/metadata
boilerplate with the separate [macro package](MacroDSL.md), retaining the same
protocols and decoders. Typed response builders and supervised HTTP/Gateway
applications remain later milestones. See [the guide](CommandDSL.md)
for argument presence, limits, diagnostics and the custom-code contract.

## Upstream protocol changes

An upstream addition, deprecation, effective-date change or removal is separate
from a local Swift API break. Append parity history with previous/current wire
behavior, affected symbols/payloads, official sources, announcement/effective dates
or `unknown`, the verification day, local release/commit and migration advice.
Review affected inventory rows and regression fixtures together. Keep future
effective transitions distinct from the current contract; do not infer introduction
dates from local commits or automatically apply changed documentation to code.

In particular, the announced channel-obfuscation HTTP transition is effective
**2026-11-16**. The dated transition fixtures and release report identify the
pre-effective and future-effective expectations. A fixture is regression evidence,
not a live preproduction or post-effective Discord result. Reverify the official
[change log](https://docs.discord.com/developers/change-log) and applicable
[HTTP guidance](HTTP.md) at release time; policy or error handling changes must be
reviewed before that effective date.

## Evidence carried with releases

Each release includes a machine-readable report and a readable companion identifying
toolchain, protocols, source verification day, platform matrix, public API baseline,
isolation/build/test/generation results, capacity evidence and excluded gates.
The current [release directory](Release/README.md) explains the initial records.
Run the report validator and current-source/maintenance checks before publishing.
Changing a date does not refresh upstream evidence.

Retain workload, hardware and revision alongside performance results. Investigate a
greater-than-10% baseline regression reproduced in three runs on matching hardware.
A local 30-minute fixed-working-set soak measures its named cohort and resources;
it does not count logical accounts as real sockets or qualify a live fleet.
Unverified infrastructure, hardware, live Discord and independent cryptographic
review remain excluded from the associated claims even when all local tests pass.
