# Audit logs and Auto Moderation REST catalog

Phase 5D implements all **six operations** in the current official
[Audit Log](https://docs.discord.com/developers/resources/audit-log) and
[Auto Moderation](https://docs.discord.com/developers/resources/auto-moderation)
references: audit retrieval and rule list/get/create/modify/delete. Contracts were
verified **2026-10-16** against REST **v10**, the
[Permissions reference](https://docs.discord.com/developers/topics/permissions),
[API reference](https://docs.discord.com/developers/reference),
[official OpenAPI](https://github.com/discord/discord-api-spec) and
[change log](https://docs.discord.com/developers/change-log). Current source hashes
are recorded separately from discovery membership pins. No dependency or product
target was added. Phase 5E adds [emoji, stickers and soundboard](Expressions.md);
phases 5F–5J and corresponding Gateway event catalogs remain pending.

Import `DiscordModels` and `DiscordHTTP`, inject a transport and shared
credential-scoped rate/reuse authorities, then execute the descriptors. REST
adoption requires no Gateway. Each operation uses the existing bounded
[HTTP pipeline](HTTP.md), explicit v10 paths and the guild major rate partition.
Shards do not increase REST quotas. Construction performs no network request,
permission lookup or related-resource hydration.

```swift
let audit = try await client.execute(AuditLogEndpoints.get(guildID: guildID, limit: 50))
let rules = try await client.execute(AutoModerationEndpoints.list(guildID: guildID))
if let current = rules.first, let trigger = current.triggerType.knownValue {
    let request = try AutoModerationModifyRequest(triggerType: trigger, enabled: .value(true))
    if let edit = try AutoModerationOperations.modifyIfChanged(current: current, request: request) {
        _ = try await client.execute(edit)
    }
}
```

## Operations and authorization

| Descriptors | Contract and additional requirements |
| --- | --- |
| `AuditLogEndpoints.get` | VIEW_AUDIT_LOG; optional actor/action filters, one exclusive before/after boundary and 1–100 entries (upstream default 50); entries retained upstream for 45 days |
| `AutoModerationEndpoints.list`, `get` | MANAGE_GUILD; return all configured rules or one rule; no invented pagination or per-rule fan-out |
| `AutoModerationEndpoints.create`, `modify` | MANAGE_GUILD; timeout actions additionally require MODERATE_MEMBERS; accept typed validated JSON and optional audit reason |
| `AutoModerationEndpoints.delete` | MANAGE_GUILD; optional audit reason; require HTTP 204 and an empty response body |

Audit and rule resource responses require HTTP 200. Mutations preserve ordinary
unsafe replay semantics: explicit rejected-429 retries remain bounded, while
ambiguous submissions or unsafe server errors are not silently replayed. Permissions,
rule quotas, channel existence, Rust regex syntax and current server state remain
upstream checks. Audit reasons use the existing bounded, percent-encoded
`X-Audit-Log-Reason` header. No mutation reason is added to its JSON body.

## Models and compatibility

Audit envelopes retain entries and all referenced collections. Entries expose
required nullable target/actor IDs, exact entry IDs, open integral action types,
optional changes/options/reason and unknown fields. Targets retain the written
nullable string contract rather than assuming every entity ID is a snowflake.
Change values remain heterogeneous lossless JSON: absent, explicit null and present
values are distinct, including nested objects, arrays and exact numeric lexemes.
Command-permission keys and `$add`/`$remove` role changes need no lossy conversion.
Optional audit information retains decimal counts and type codes as wire strings.

The audit envelope uses complete Auto Moderation rule and existing Channel contracts,
an audit-specific partial integration projection, and explicitly partial User,
application-command, scheduled-event and webhook projections. Referencing these
objects does not implement their full resource families or corresponding Gateway
events. Partial webhook projections deliberately retain sensitive raw fields, so
ordinary diagnostics and reflection conceal payloads; deliberate raw JSON/property
access remains caller-owned.

All 69 written-reference audit action codes and seven preview-only codes are
recognized. Recognition describes values received in audit entries and does not
claim the corresponding endpoints/events are implemented. Unknown action, trigger,
preset and event integers remain representable in responses. Malformed known fields
fail with sanitized errors. Parsing uses the shared finite JSON byte/depth/node
bounds and preserves future fields without fetching more data.

The [ambiguity register](Parity/ambiguities.json) records written/preview differences:
nullable audit change keys and referenced rule elements, partial integration
nullability, preview-only action codes, nullable request fields and conflicting
custom-message limits. The written 150-character block-message cap and timeout
metadata requirements control outgoing validation. Neither a decoded snapshot nor
a retained cache entry establishes current permission or authorization.

## Validated requests

`AutoModerationTriggerMetadataRequest` validates trigger-specific fields: keyword
and member-profile keyword/regex filters, preset wordsets and allow lists, and
mention-spam count/raid controls. Bounds include 1,000 keywords, ten 260-character
patterns, 60-character keywords/allow-list entries, 100 keyword/profile allow-list
entries or 1,000 preset entries, and mention limits of 0–50. Empty arrays preserve
explicit selection; empty strings in filters are invalid. Character bounds use
Unicode scalars without normalizing text. Regex syntax remains Discord's decision.

`AutoModerationActionRequest` requires the matching metadata for alerts and timeout,
rejects metadata belonging to another action, and preserves nullable block-message
explanations. Timeout durations permit 0–2,419,200 seconds and are valid only for
keyword or mention-spam triggers. Blocking member interaction requires a
member-profile trigger. Creation requires 1–5 actions, an explicit event
and trigger type, and metadata for preset/profile rules. Names allow at most 100
Unicode scalars; the preview publishes no minimum. Role/channel exemption arrays
allow at most 20/50 distinct IDs, preserving caller order. No rule/event pairing is
invented where upstream does not specify one.

`AutoModerationModifyRequest` keeps the caller's current trigger type as local
validation context and never transmits `trigger_type`, which is immutable in the
written PATCH contract. Absent fields leave server values unchanged; supported nulls
retain their preview semantics and differ from empty arrays. Unknown future trigger
types remain readable but cannot be safely constructed as typed outgoing requests.
No hidden GET fills missing state. Local validation performs synchronous work
under published payload constraints and does not reserve rate allowance or start tasks.

## Request reduction and bounded traversal

Eligible reads coalesce within the injected authentication identity; completed
caching requires a positive opt-in TTL. Audit snapshots carry audit/guild/channel/
message-search invalidation tags; rule snapshots carry moderation/guild tags.
Successful rule mutations invalidate moderation/audit snapshots and the common
guild visibility tags. Existing guild/channel/message writes can therefore invalidate
affected audit snapshots. The common pipeline fences stale in-flight completions.
External actions and other workers outside the shared authority can remain unseen
until TTL expiry. Pagination disables reuse to avoid carrying cached pages through
a traversal.

`AuditLogOperations.pages` lazily yields each complete envelope, retaining related
objects for local correlation. Default/before traversal is newest first; after
traversal is oldest first, with zero available as an initial oldest-first boundary.
Every entry must advance strictly in the chosen direction, including nonfinal rows;
oversized, duplicate, out-of-order or nonadvancing results fail. Short nonempty pages
continue, and the empty-entry terminal envelope is yielded once. The iterator
requests at most 100 entries per page and 10,000 pages, never prefetches and retains
bounded cursor history. Cancellation, deadline, executor and page-budget errors
permanently finish an iterator. New iterators have independent cursor state.
Concurrent actions and 45-day retention expiry prevent snapshot completeness claims.

`AutoModerationOperations.modifyIfChanged` compares only explicitly requested raw
fields against the caller's snapshot and returns nil for a no-op. It requires the
snapshot trigger to match the request's validation context. It performs no read or
write; a returned descriptor uses ordinary admission and mutation ordering.
Stale snapshots retain the usual reconciliation race and do not prove current
server state. No generic batching, implicit rule enumeration or bulk mutation is added.

## Validation scope

Swift Testing covers all six descriptors through injected HTTP execution, including
exact versioned paths and bodies, permissions/authentication failures, malformed
responses, unknown variants, large IDs, nullable and heterogeneous changes, request
bounds, redaction, API/rate/transport errors, unsafe replay handling, cancellation,
resource cleanup, credential isolation, coalescing and scoped invalidation. Audit
tests exercise both directions, strict cursor progress, terminal envelopes and finite
budgets; reconciliation tests assert no-op and changed payload behavior.

Root build/tests, the independent REST example, offline generation/parity checks
and local HTTP policy scenarios validate this slice on macOS arm64 with Swift 6.4.
They use finite fixtures and no Discord credentials or live Discord requests.
Other hosts/devices, live API conformance, durable coordination and long-soak
qualification remain separate [platform gates](PlatformSupport.md). Upstream
announcement/effective dates and local support history remain distinct in the
[Phase 5D change record](Parity/changes/2026-10-16-moderation.md).
