[//]: # "File: Sources/DiscordKit/DiscordKit.docc/Compatibility.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Review compatibility and release evidence

Track local API design and upstream feature transitions independently.

The initial 0.14.0 development API baseline records documentation
presence audit, isolated consumer checks and release evidence. It does not publish
a tag or qualify every host. Use a matching compiler/platform when comparing
public symbol graphs; review semantic behavior, isolation, defaults and errors
alongside symbol changes. An unchanged graph is not a full source or binary ABI proof.

After 1.0, incompatible public API changes require a major version; compatible
additions use a minor and compatible fixes use a patch. During 0.x, document
breaking design changes with a minor increment. Retain previous baselines and
review migration before updating the recorded comparison target.

Append parity history for upstream additions/changes/deprecations/removals,
including previous/current behavior, symbols/payloads, official sources,
announcement/effective dates or unknown, local release/commit and migration.
Future-effective transitions remain distinct from current behavior. The upcoming
channel-obfuscation HTTP change is effective 2026-11-16 and has dated fixtures;
reverify the official change log before its effective date and every release.

Weekly read-only upstream review produces a report and pinned-spec diff artifact;
it never regenerates production code. Every release carries readable and
machine-readable evidence with unverified gates excluded from support claims.
See the [migration guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Migration.md)
and [CI guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/CI.md).
