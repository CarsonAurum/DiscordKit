# HTTP execution and request reuse

Implemented 2026-10-16 with Swift 6.4. REST **v10** is explicit and verified against
the [API reference](https://docs.discord.com/developers/reference) and
[change log](https://docs.discord.com/developers/change-log). `DiscordHTTP` depends
on Models and Transport, and requires no Gateway, voice or concrete network adapter.
The independent [REST-only example](../Examples/RESTOnly/README.md) shows adoption.

## Requests and responses

`Endpoint<Response>` declares encoded path segments, ordered repeated queries,
authentication, success statuses, canonical rate route, major resource, audit
reason, body, replay safety, read policy, invalidation tags and bulk metadata.
The descriptor does no I/O. Paths cannot escape `https://discord.com/api/v10`;
authentication/framing headers cannot override client policy. Raw relative routes
use exactly the same pipeline and establish no typed endpoint parity. Adapters
must send once and reject redirects; the owned adapters satisfy that requirement.

JSON, URL-encoded form and multipart bodies have explicit complete-byte bounds.
Replayable stream factories create a fresh pull source for each attempt, enforcing
a total-byte cap; streaming bodies cannot enter read coalescing/cache keys.
Each retry obtains a newly owned body source. Multipart framing validates boundary
collisions, names, filenames, byte limits and controls. Response bodies are consumed
or closed on success, cancellation, malformed JSON, overload and errors. Empty/204
responses require an explicit empty decoder. Unknown Discord numeric codes and
nested validation trees survive in `APIResponseError` with bounded raw evidence.
Ordinary diagnostics/reflection redact URLs, headers, bodies and credentials;
explicit unsafe evidence inspectors transfer the logging responsibility to callers.

The first typed descriptors are `DiscordEndpoints.currentUser()` and
`currentApplication()` plus `GatewayEndpoints.bot()` in the optional Gateway product.
Phase 5G completes User/Application owned projections while retaining explicit
partial referenced resources, exact unknown JSON, large string snowflakes and
absent/null/value states. Resource
catalog expansion includes Part 5A [messages and polls](RESTCatalog.md) and Part 5B
[channels and threads](Channels.md), Part 5C [guild administration](Guilds.md), and
Part 5D [audit logs and Auto Moderation](Moderation.md), and Part 5E
[emoji, stickers and soundboard](Expressions.md), and Part 5F
[invites, templates, scheduled events and stages](DiscoveryEvents.md), and Part 5G
[applications, users, linked roles and commands](ApplicationsUsers.md), and Part 5H
[webhooks, interaction responses and voice control](WebhooksInteractionsVoice.md);
these initial descriptors do not imply full resource-family parity.

`AssetClient` accepts HTTPS destinations without credential/header customization.
It never attaches API authorization, follows redirects, retries, or uses authenticated
REST budgets. It returns at most its configured byte cap. Custom transports must
honor the same single-send/no-redirect contract.

## Shared authority and ordering

Create a `RateLimitIdentity` for an authorization scope and **share it and the same
`RateLimitCoordinator` across clients using that credential**. Across processes,
inject a common atomic `RateLimitStore`; no durable-store dependency is shipped.
The reusable `RateLimitStoreContract` test harness exercises direct and forwarding
adapters through a factory and optional outage hook; consumer backends must run
the same contract plus backend-specific transaction, crash and clock checks.
External adapters must translate process-local instants into a common clock domain,
atomically reserve all applicable quotas and fail closed during outages. Do not
create independent stores after an authority failure. Rotate read scope and invalidate
old snapshots when permissions or credentials change; applicable resource/egress
limits must survive rotation. For unauthenticated requests, share the identity by
outbound IP so the IP global allowance is coordinated. Supply the same `egress` UUID
for shared outbound invalid-request protection across authenticated identities.

The in-process authority partitions credential state across up to eight bounded actors,
with a small aggregate ownership gate. Buckets learn case-insensitive headers,
major-resource identities, relative fractional reset delays and user/shared/global
429 restrictions. Provisional windows are conservative; the initial configurable
50 requests/second is startup policy, not a permanent replacement for server limits.
Documented interaction operations can explicitly opt out of the bot-global limit.
Shared-resource restrictions and invalid-response pressure compose across identities.
The configurable default invalid-response trip threshold is 9,000; the quiet-window
implementation is deliberately conservative relative to Discord's documented limit.

Admission uses bounded cancellable FIFO queues within identity/route/major/class;
blocked partitions cannot stall eligible unrelated identities. Unsafe operations
hold their partition through retries/backoff. Cross-process rate reservation alone
does not serialize application mutations across workers: consumers must assign one
owner/order authority where mutation ordering spans processes. Cancellation removes
queued work. Possible sends never refund quota. Token expiry cannot recall a network
write already in flight, so adapters must honor deadlines before new sends.

Metadata is bounded and learned aliases are retained conservatively. Partition skew
may refuse discovery before the aggregate cap. Exhaustion never evicts an exhausted
budget to create new allowance; inability to retain learned restrictions latches the
shared authority unavailable. Operator recovery must preserve/reset only genuinely
expired authority state, rather than silently constructing independent budgets.

Retries have finite attempt and exponential-delay budgets. A 429 is an explicit
rejection and goes back through learned admission. Transport failures and 5xx replay
only explicitly safe operations. Unsafe ambiguous sends and HTTP 5xx responses return an indeterminate
outcome; reconcile state before retrying. Local validation and known HTTP failures
remain distinct. Operation deadlines bound admission, retries, transport and body EOF.

## Coalescing, freshness and bounded ownership

Read reuse is explicitly declared, never inferred from GET. Keys include opaque
authorization identity, method, response type, authentication policy, complete path,
ordered queries, representation headers and eligible materialized body. Keys also
separate the client user-agent, response byte/lifetime/retry bounds, accepted success statuses,
exact endpoint TTL and sorted invalidation tags so a reused result cannot bypass
response limits or satisfy a stricter acceptance/freshness contract. Reuse owners
must only be shared between clients with the same authorization interpretation and
transport backend. Cache snapshots cannot establish current authorization.

`RequestCoalescer` defaults to 128 flights total, 32 per identity, 1,024 subscribers
total and 256 per flight. One cancelled subscriber leaves others intact; the final
subscriber cancels and awaits exchange cleanup. Shared flights have a bounded client
exchange deadline independent of subscriber deadlines. Close awaits owned tasks;
there are no permanently running background loops.

`ReadCache` is opt-in per descriptor TTL and per injected owner. Defaults are 256
entries/4 MiB payload total and 64 entries/1 MiB payload per identity. LRU eviction,
inclusive monotonic expiry and invalidation fence stale fetch completions.
Request/response no-store/no-cache and response Vary:* prohibit retention; max-age/Expires, Age and
exchange elapsed time can shorten endpoint TTL. Conditional revalidation is not
implemented. These conservative private-cache rules follow
[RFC 9111](https://www.rfc-editor.org/rfc/rfc9111.html). Cache
entries never retain HTTP failures as absence. Successful local writes invalidate
declared tags; observed visibility/scope changes require explicit invalidation.
TTL bounds staleness from unobserved external changes. Every key is capped at 128 KiB,
and invalidation metadata at 128 tags/64 KiB per entry; payload byte counters exclude
that separately bounded metadata and Swift allocator/index overhead.

The transport, authority, cache and coalescer are separately owned and injected;
a RESTClient never implicitly closes a dependency shared with other clients.
Call coalescer/coordinator close and adapter close after clients finish. Cache has
no tasks; removeAll releases retained snapshots. Counter snapshots expose aggregate
ownership without credentials or per-account labels.

## Pagination, polling and qualification

`CursorPagination` fetches lazily, preserving operation-selected continuation rules;
it never universally treats a short page as final. Early termination makes no next
request. `PollingOperation` uses caller-defined terminal states, finite poll counts,
injected clocks, cancellation and a shared deadline. Bulk metadata documents concrete
upstream limits without introducing a generic mutation batching API.

Deterministic Swift Testing suites cover wire construction, nullable/unknown fields,
error statuses, request count reduction, shared-worker rate reservations, fractional
windows, cancellation, overload, fail-closed authority and body ownership. Separate
[HTTP load evidence](../Tools/DiscordKitLoadTests/README.md) names measured workloads.
These checks do not establish live Discord conformance, cross-platform qualification,
full resource/event parity, distributed-store certification, or million-socket capacity.
A fixed-working-set 30-minute soak and host-specific allocation traces remain release
capacity gates; no deployment capacity claim is made by this implementation.
