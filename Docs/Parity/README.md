# Parity inventory and chronological history

Baseline date: **2026-10-15**; implementation update **2026-10-16**. The initial
HTTP/Gateway slice has three reviewed endpoint definitions: current-user and
current-application are partial typed projections; Gateway bot discovery is supported
with deterministic evidence. See the [HTTP/Gateway history](changes/2026-10-16-http-gateway.md).
Part 4 links the existing implementation to [reviewed contracts](reviewed-v1.json),
per-field semantics, real symbols and test/fixture evidence. See the
[generation guide](../Generation.md), [generated reviewed report](generated-reviewed.md)
and [tooling history](changes/2026-10-16-reviewed-generation.md). Phase 5A adds the
[message/poll catalog](../RESTCatalog.md); Phase 5B adds the
[channel/thread catalog](../Channels.md), including all 24 Channel operations and
active guild threads. Phase 5C adds all 45 current [Guild operations](../Guilds.md),
reusing active threads, with typed member/ban/role/settings models and bounded workflows.
Phase 5D adds the [Audit Log and Auto Moderation catalog](../Moderation.md): one
Audit Log retrieval operation, five Auto Moderation operations, directional audit
continuation and opt-in rule reconciliation. Audit-owned fields and moderation rules
are typed; referenced User, application-command, scheduled-event and webhook families
retain partial projections. Numeric audit action recognition does not implement their
related Gateway events or resource operations. Phase 5E adds all 25 current
[Emoji, Sticker and Soundboard operations](../Expressions.md), including guild/app
emoji, sticker packs and direct multipart creation, default/guild soundboard reads,
writes and play, and explicit snapshot reconciliation. Phase 5F adds all 25 current
[Invite, Guild Template, Guild Scheduled Event and Stage Instance operations](../DiscoveryEvents.md),
including target-user CSV/jobs/bulk changes, typed template placeholders, recurrence/status
contracts, finite subscriber traversal and snapshot reconciliation.
Phase 5G adds [applications, users, linked roles and commands](../ApplicationsUsers.md).
Phase 5H adds all 28 [webhook, interaction-response and voice-control operations](../WebhooksInteractionsVoice.md),
with typed path credentials and independent IP-global admission.
Phase 5I adds all eight written [SKU, entitlement and subscription operations](../Monetization.md),
complete owned resource fields, typed premium interaction entitlements and finite lazy traversal.
Phase 5J adds all 21 written [lobby and identity/profile operations](../SocialGame.md),
bounded correlated member bulk plans and full-replacement game-stat requests.
Phase 6 adds all 79 documented [Gateway dispatch names](../Gateway.md), typed
commands/intents/capabilities and bounded correlated requests. Event-name coverage
is separate from full typed child-resource parity; reviewed events retain explicit
partial classifications where relevant. See [Gateway history](changes/2026-10-16-gateway-catalog.md).
Phase 7 adds the [consumer client and optional scoped state](../Client.md), bounded
broadcast/handlers and permission resolution. This local composition adds no new
Discord endpoints or dispatch names and does not inflate discovery support counts;
see [consumer runtime history](changes/2026-10-16-consumer-runtime.md).
Phase 9 adds [OAuth/installation and token ownership](../OAuth.md),
[public game account and entitlement workflows](../Phase9ServiceContracts.md),
and current verification hashes with explicit native/Commerce blockers; see
[Phase 9 history](changes/2026-10-17-oauth-game-commerce.md).
These handwritten contracts retain explicit partial related
resource projections and do not claim full resource-family parity.
Part 1 adds local values and transport contracts, recorded in the
[foundation history](changes/2026-10-15-foundations.md). Part 2 adds independently
adoptable network adapters and local evidence in the
[transport history](changes/2026-10-15-transports.md). This inventory makes future coverage
measurable; discovery records and unavailable-capability stubs do not count as support.

## Versioned records

- `inventory-v1.json` contains individually classified discovery records for written
  reference/guide pages, sections, routes, fields, enum values, permissions, intents,
  opcodes, close codes, events, SDK methods and protocol-state sections.
- `inventory.schema.json` describes the inventory and its separate source catalog.
- `sources-2026-10-15.json` pins source revisions, SHA-256 content hashes, verification
  date, authority, protocol version, prerequisites and exact discovered membership.
- Resource-specific current-source records, including `moderation-current-sources.json` and
  `expression-current-sources.json`, `discovery-event-current-sources.json`,
  `application-user-current-sources.json`, `webhook-voice-interaction-current-sources.json`
  `monetization-current-sources.json` and `social-game-current-sources.json`,
  retain current official verification hashes separately from original discovery pins.
- `ambiguities.json` records contradictions, adopted precedence and unresolved contracts.
- `history.json` is append-only support history; `changes/` contains human-readable entries.
- `reviewed-v1.json` and `reviewed.schema.json` describe the finite generation seed,
  source pins, semantic overrides, stable references, symbols and evidence. The discovery
  schema remains version 1; reviewed contracts are a separately versioned document.
- `generated-reviewed.md` derives reviewed counts from generator inputs after validation.
  `parity check` also reports discovery kind/status counts and checks support mappings.
- `coverage.md` records actual tests and completion gates, including work that cannot
  be qualified on this host. `../Feasibility/method-contracts.json` maps SDK operations
  individually to public protocols, local work or named missing-contract blockers.

Source metadata is inherited by its entries. Announcement/effective dates are
`unknown` until official evidence establishes them; the local baseline date is
never used as an upstream introduction date. Protocol versions are explicitly REST
**10**, Gateway **10**, Voice Gateway **8**. An entry may override a mixed source's
protocol version (for example, Voice opcodes in the common opcode reference).
OAuth/RPC/Activity/Social protocols with no such version are documented separately;
REST versioning does not assign a version to a native SDK or iframe protocol.
RPC IPC's documented handshake `v: 1` is a payload-level protocol choice; its
mixed RPC/OAuth reference source is cataloged as unversioned rather than REST v10.

## Status, conditions and evidence

`status` describes **DiscordKit implementation**: `supported`, `partial`,
`unsupported`, `deprecated`, `removed`. Upstream availability is independent.
`condition` describes an access/protocol boundary: `public_protocol`,
`approval_required`, `portal_only`, `unavailable_upstream`, `undocumented_protocol`,
`unavailable_host`, or `not_applicable` for documentation/local values.

Historical baseline discovery records were all `unsupported`; current support is
recorded individually with evidence and append-only history. `review: discovered` means
extraction found a source definition; it does not certify its auth, availability,
permissions, scope or full schema. Broad source defaults identify the public
surface; exact per-operation prerequisites require semantic review before implementation.
SDK contract mappings retain more precise prerequisites and blockers. Section and
unrecognized `table_row` records deliberately preserve material requiring review.
Foundational snowflake/bitset/JSON support does not implement a resource model,
named permission policy or endpoint; the baseline operation records therefore
remain unsupported. Local foundation evidence is recorded separately without
inflating protocol support counts.
Duplicate representations across written docs, stable spec and preview spec remain
distinct; their counts are **not unique operation counts**.

Before changing support, review the authoritative contract, classify exact access
requirements and platform availability, link symbols and deterministic test evidence,
and append a history entry with previous/current behavior, official links, upstream
announcement/effective dates, local support date/release/commit, limitations and migration.
`supported`/`partial` require review and nonempty evidence. The reviewed validator
also checks real source declarations, named test functions and structured fixture cases.
Existence does not establish that a test proves behavior: semantic review remains necessary.
Absent a local release or commit, record `unknown` until it exists.

## Source precedence and reproducibility

The baseline uses all **204 MDX files** (189 developer pages plus 15 imported snippets)
from official documentation revision `37148620d2324292b76047541d5f8331f81ea77a`.
Every downloaded MDX blob was checked against that revision's nontruncated recursive
Git tree using Git's blob hash before extraction. The public documentation index is
retained in `snapshots/llms-2026-10-15.txt` with its content hash; it is a discovery
boundary, not proof that all future documents are covered. SDK reference content is
unversioned, so its full source SHA-256, signature hashes and definition anchors are retained
in the contract map. Re-fetching an unversioned SDK page may differ from this baseline.

Both `openapi.json` and `openapi_preview.json` are pinned at official specification
revision `ed014089afa986f2b532ae081c456a85de074d0c`. The
[specification README](https://github.com/discord/discord-api-spec/blob/ed014089afa986f2b532ae081c456a85de074d0c/README.md)
states that these are preview material and written docs take precedence. Do not use
them as a runtime dependency, infer unsupported fields are stable, or resolve a
contradiction by silently preferring the generated schema. Preserve the ambiguity
and require official resolution or reviewed compatibility policy.

Acquire checkouts at those **exact revisions**, verify them, then run from the repository:

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

Python 3 uses only its standard library; no runtime or development package dependency
is installed. The extractor is deliberately offline. It records the specified revision
and source hashes; **it does not authenticate a checkout's revision**. Verify acquisition
before using its results. It retains source locations and identifying labels, rather
than vendoring full reference documents. Never run harvesting during consumer builds.

The current extractor retains headings/tables, normative intent code blocks, Route
elements and known guide URL/template forms. Arbitrary prose or a new markup style can
introduce definitions it does not recognize. The pending-review count and retained
sections keep that limitation visible. Zero unclassified discovered IDs is a structural
property; it is not a full-parity or exhaustive semantic-discovery claim.

## Validation

```sh
swift test --package-path Tools/DiscordKitTools
python3 -m unittest discover -s Tools/DiscordKitTools/scripts -p 'test_*.py'
swift run --package-path Tools/DiscordKitTools DiscordKitTools inventory validate --repository .
swift run --package-path Tools/DiscordKitTools DiscordKitTools generate --check --repository .
swift run --package-path Tools/DiscordKitTools DiscordKitTools parity check --repository .
```

The offline discovery validator checks schema version, protocol baseline, real Gregorian dates,
provenance metadata, allowed classifications, unique IDs, source references, exact
discovered membership and evidence/review requirements. Errors exit nonzero; the command
does not modify files. The JSON Schema is an interchange contract; the dependency-free
Swift validator implements the named semantic checks rather than a general JSON Schema
engine. Unknown metadata keys are rejected at inventory/catalog/entry/source boundaries;
the intentionally opaque upstream `definition` object retains source-specific metadata.
The separately versioned reviewed schema rejects unknown keys recursively. Reviewed
checks add freshness, pinned revision/hash agreement, cross-record contracts, source
symbols and executable/fixture evidence, including partial-model omissions. Generation
checks compare committed output byte for byte without writing or accessing the network.

Counts printed by `parity check` derive from validated records, with discovery and
reviewed totals kept separate. These are not unique-operation counts or a full-parity
claim. `--as-of YYYY-MM-DD` reproduces an explicitly dated audit; default validation
uses the current UTC day and rejects stale verification. See the generation guide
for explicit regeneration and source review requirements.

Full-catalog implementation, documentation audits and dependency-audit CLI commands
remain future work. Unknown commands fail with usage status 64; validation failures
exit 1. `generate` requires an explicit `--check` or `--write` flag.
