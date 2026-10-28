<!--
File: Docs/Parity/README.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Protocol inventory

The inventory connects Discord's published contracts to DiscordKit declarations,
validation rules and test evidence. Use it to check the supported scope of a resource
or protocol; discovery counts alone do not establish implemented behavior or unique
operation counts.

## Records

- [Discovery inventory](inventory-v1.json) classifies reference pages, routes, fields,
  enum values, permissions, intents, opcodes, events, SDK methods and protocol sections.
  Its [schema](inventory.schema.json) defines the interchange format.
- [Reviewed contracts](reviewed-v1.json) and their [schema](reviewed.schema.json) link
  finite semantic contracts to source pins, public symbols, tests and fixtures.
  [The generated report](generated-reviewed.md) derives counts from these records.
- [Source catalog](sources-2026-10-15.json) records exact documentation/specification
  revisions, SHA-256 hashes, verification dates, protocol versions and source membership.
  Resource-specific current-source records retain later reviews separately.
- [Ambiguities](ambiguities.json) names contradictions, adopted precedence and missing
  contracts. Unresolved schemas or access requirements remain explicit blockers.
- [History](history.json) and the [change records](changes/) preserve dated support
  changes, migration notes and the limits of their original evidence.
- [Coverage and qualification](coverage.md) separates deterministic local tests from
  platform, live-service, device, cryptographic and interoperability qualification.
- [Method contracts](../Feasibility/method-contracts.json), the
  [Social catalog](social-catalog.json), [Activity catalog](activity-catalog.json)
  and [voice capability inventory](voice-media-capabilities.json) describe narrower
  SDK/provider and media boundaries that endpoint counts cannot express.

## Reading support claims

`status` describes DiscordKit implementation: `supported`, `partial`, `unsupported`,
`deprecated` or `removed`. `condition` describes an independent access or protocol
boundary: `public_protocol`, `approval_required`, `portal_only`, `unavailable_upstream`,
`undocumented_protocol`, `unavailable_host` or `not_applicable`.

A discovered source definition has not necessarily received semantic review.
Supported and partial records require explicit review and nonempty evidence. Referenced
symbols, named tests and structured fixtures must exist, but their existence does not
prove that assertions cover the full contract. Related-resource projections, unknown
fields and unqualified hosts remain gaps even when an endpoint or event name is present.

Duplicate representations in written documentation, stable specifications and preview
specifications remain separate records. Local authoring, cache and client composition
adds no upstream endpoints or dispatch names. Permission calculations and cached values
do not establish current Discord authorization.

Protocol versions remain distinct: REST **10**, Gateway **10**, Voice Gateway **8**,
RPC handshake **1**, MLS **1.0** and negotiated DAVE versions. Unversioned OAuth,
Activity and Social contracts do not acquire a version from REST. Upstream
announcement/effective dates remain `unknown` without official evidence; a local
verification or support date never supplies an upstream introduction date.

## Source precedence and reproduction

Written Discord documentation takes precedence over the official preview API
specifications. Preserve contradictions in the ambiguity register rather than silently
adopting a generated schema. SDK reference pages may be unversioned, so source hashes,
anchors and review dates identify the exact reviewed inputs.

The discovery baseline pins official documentation revision
`37148620d2324292b76047541d5f8331f81ea77a` and specification revision
`ed014089afa986f2b532ae081c456a85de074d0c`. The retained index snapshot is a discovery
boundary, not proof of coverage for future documentation. Acquire and verify those
exact revisions before reproducing the baseline:

```sh
python3 Tools/DiscordKitTools/scripts/harvest_inventory.py \
    --docs /path/to/discord-api-docs \
    --spec /path/to/discord-api-spec \
    --index Docs/Parity/snapshots/llms-2026-10-15.txt \
    --methods Docs/Feasibility/method-contracts.json \
    --output /tmp/discordkit-inventory
diff -u Docs/Parity/inventory-v1.json /tmp/discordkit-inventory/inventory-v1.json
diff -u Docs/Parity/sources-2026-10-15.json /tmp/discordkit-inventory/sources-2026-10-15.json
```

Harvesting is offline and uses Python's standard library. It records supplied source
revisions and hashes without authenticating checkout acquisition. New prose or markup
can contain definitions the extractor does not recognize. Pending-review records keep
this limitation visible. Consumer builds never harvest documentation or regenerate code.

## Validation and updates

```sh
swift test --package-path Tools/DiscordKitTools
python3 -m unittest discover -s Tools/DiscordKitTools/scripts -p 'test_*.py'
swift run --package-path Tools/DiscordKitTools DiscordKitTools inventory validate --repository .
swift run --package-path Tools/DiscordKitTools DiscordKitTools generate --check --repository .
swift run --package-path Tools/DiscordKitTools DiscordKitTools parity check --repository .
```

These commands check dates, source provenance, exact membership, classifications,
references, real declarations, executable evidence and generated-output drift without
writing or accessing the network. Default validation uses the current UTC date and
rejects stale verification. `--as-of YYYY-MM-DD` reproduces an explicitly dated audit;
it cannot substitute for current source review. Generation requires explicit `--check`
or `--write`; see [generation](../Generation.md).

Before changing a support claim, review the authoritative contract and exact access,
platform and schema requirements, update symbols and meaningful deterministic evidence,
and append a dated history entry with behavior, limitations and migration guidance.
Current [release validation](../Release/README.md) separately audits documentation,
dependencies, API compatibility and qualification exclusions.
