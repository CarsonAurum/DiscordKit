# Signed ingress, interaction lifecycle and commands

Phase 8 adds independently adopted `DiscordInteractions` and `DiscordCommands`
products. HTTP interaction applications need no Gateway, Client, Cache or voice
product. Construction starts no listeners, timers, handler tasks, registration
writes or network requests. Applications inject and own those resources.

The current [interaction lifecycle](https://docs.discord.com/developers/interactions/receiving-and-responding),
[command](https://docs.discord.com/developers/interactions/application-commands),
[webhook-event](https://docs.discord.com/developers/events/webhook-events),
[component](https://docs.discord.com/developers/components/reference),
[component-embed](https://docs.discord.com/developers/link-previews/component-embeds)
and [link-preview](https://docs.discord.com/developers/link-previews/overview)
references and [change log](https://docs.discord.com/developers/change-log) were
verified **2026-10-17**. [Source fingerprints](Parity/interaction-runtime-current-sources.json)
preserve that verification separately from historical discovery pins. REST/Gateway
**v10**, interaction payload version **1** and webhook envelope version **1** are
distinct protocol versions. Unknown upstream announcement/effective dates remain unknown.

## HTTP-only adoption

The independent [HTTPApp example](../Examples/HTTPApp/README.md) builds a signed
HTTP application with an ephemeral `/ping` command and an owned NIO ingress adapter:

```sh
swift build --package-path Examples/HTTPApp
```

Its selected graph compiles Bits, Core, Transport, Models, HTTP, Interactions,
Commands and NIOTransport; Gateway, Client, Cache and the DiscordKit facade are
absent. Building neither runs authenticated requests nor registers commands.
Execution requires the application's public key/ID, an explicitly registered
command and deployment-owned HTTPS termination. Forward the original request body
and signature fields unchanged. The example binds loopback, limits structured
handlers to 32 and accepted connections to 64, and has a separate 32-slot initial
acknowledgement budget. The reusable library defaults below are independent limits.

`InteractionHTTPApplication.handle` authenticates before decoding an `Interaction`,
checks its application ID and gives the handler an `InteractionContext`. HTTP PING
receives an inline 200 PONG without invoking user handlers. A successful reply or
defer sends its inline HTTP 200 immediately; handler completion remains structured
and awaited. A handler that returns without responding produces HTTP 500. A handler
error before acknowledgement produces 500 and remains observable to the caller;
after an initial slot is reserved there is no second fallback response. PONG and
handler transmission failures propagate after cleanup.

The application's injected transport context bounds body reading, handler work and
fallback transmission. Capture receipt time before authentication/body work; that
work consumes the initial-response window. A context with no deadline supplies no
outer timeout, so listeners must choose a finite ingress/handler policy. Deferred
handlers may need an outer deadline longer than three seconds and an injected
continuation sink; the initial responder still has its own three-second deadline.

## Authentication, replay and admission

`SignedRequestVerifier` uses Ed25519 over the exact original timestamp bytes followed
by the exact body bytes. It requires one signature header and one timestamp header,
validates their encodings, checks its timestamp policy and authenticates before
inserting replay metadata. JSON reformatting, body mutation and timestamp mutation
invalidate the signature. Verification does not trust forwarded permission fields
or grant application authorization.

| Bound or policy | Default / allowed values | Ownership |
| --- | --- | --- |
| Public key / signature | 32 / 64 bytes, exact hexadecimal headers | Verifier |
| Timestamp age / future skew | 300 / 30 seconds; each configurable in 0...86,400 | Local policy, inclusive edges |
| Complete authenticated body | 1 MiB | Verifier and independent ingress cap |
| Replay records | 4,096 signatures | Process-local verifier |
| Concurrent ingress requests/handlers | 32, no waiting queue | Shared ingress actor |
| Total header field-name/value bytes | 16 KiB per request | Ingress |
| Initial callbacks in flight | 256 | Shared acknowledgement authority |
| Initial encoded JSON bytes in flight | 8 MiB total | Shared acknowledgement authority |
| Default JSON bounds | 1 MiB, depth 64, 100,000 nodes | Complete-document parser |

All count/byte capacities are finite and configurable. Share application-scoped
authorities and aggregate authorities across cooperating consumers as appropriate;
creating independent instances does not create a fleet-wide limit. Ingress admission
is fail-fast: overload returns 503, body/header excess returns 413/431, unsupported
methods return 405 and authentication failures return 401. Cancellation/deadline
expiry closes owned bodies and propagates through the supplied transport context.

Reject-identical replay policy is the verifier default. Its full window fails closed
with 503 for a new signature rather than evicting protection. Allow-identical-retries
mode authenticates every attempt, reports advisory `isReplay` and evicts the oldest
timestamp at capacity. Use allow-identical-retries for webhook events so durable
duplicate admission can acknowledge retries. Replay identity is the signed request,
not semantic JSON equality or a Discord event identifier. Replay state is local;
durable or distributed duplicate ownership remains a consumer responsibility.

## Response ownership and deadlines

`InteractionContext` retains the complete presence-aware snapshot, selected delivery
mode and one `InteractionResponder`. Its initializer verifies ID, application ID,
token and delivery-mode ownership. Commands, components, modals, localization,
attachments, entitlements, contexts, installation owners, resolved resources and
unknown variants remain accessible through the original snapshot. No hydration or
implicit cache access occurs.

The response actor reserves `.acknowledging` before its first suspension. Concurrent
reply/defer attempts therefore cannot submit two initial callbacks. The initial
deadline is exclusive at receipt + **3 seconds**; missing it invalidates local token
use. A confirmed acknowledgement permits continuations only before receipt +
**900 seconds**. Expiry never retracts a mutation that may already have been submitted.
Future receipt offsets fail validation instead of extending the window.

Initial acknowledgement has count/encoded-byte admission separate from ordinary
REST work. For Gateway delivery, use `InteractionResponseSink.rest` with a dedicated
initial REST client/queue and a separate continuation client. Both must retain the
exact interaction credential, shared opaque token identity and applicable shared
rate authority. Separate queues do not bypass learned route/resource limits. The
typed callback endpoint is global-limit exempt; explicit rejected 429 responses
retain the client's finite retry policy. Ambiguous callback submission is never retried.

```swift
// `interaction` comes from trusted Gateway delivery. Capture actual receipt time
// in this shared clock domain before slow decoding or dispatch work.
let responseClock = InteractionClock(clock)
let receivedAt = responseClock.now
let responder = InteractionResponder(
    interaction: interaction,
    deliveryMode: .gateway,
    clock: responseClock,
    sink: .rest(interaction: interaction, initialClient: initialClient,
                continuationClient: continuationClient, clock: clock),
    admission: acknowledgementAdmission,
    receivedAt: receivedAt
)
let context = try InteractionContext(interaction: interaction,
    deliveryMode: .gateway, responder: responder)
_ = try await router.route(context)
```

Discord selects HTTP or Gateway interaction delivery per application; these are
mutually exclusive receipt modes. A Gateway interaction responds through HTTP,
never a Gateway opcode. For an HTTP interaction, inline response and callback-endpoint
response have different transport mechanics: inline uses 200 JSON; an external
callback requires the original HTTP request's 202 empty acknowledgement. The supplied
HTTP application uses inline responses; consumers supplying another sink own its
matching HTTP response mechanics.

`reply` is an initial-only message. `respond` supports every implemented typed
callback, including PONG, update/defer, autocomplete, modal and Activity results;
deprecated premium-required remains explicitly deprecated. Unknown incoming kinds
are preserved but cannot acquire an invented callback compatibility guarantee.
Updates require an actual source-message snapshot. Activity/monetization eligibility,
permissions, message visibility and follow-up quotas remain Discord checks.

For explicit long work, acknowledge first and complete through an original PATCH:

```swift
try await context.responder.deferResponse(ephemeral: true)
let result = try await performApplicationWork()
_ = try await context.responder.editOriginal(
    InteractionMessageEdit(content: .value(result), deferredResponse: true)
)
```

`deferredResponse: true` requires a deferred-message acknowledgement and supplies
the evidence needed by deferred poll edits. Ephemeral visibility is fixed by the
initial defer. A follow-up before completing the deferred original is rejected
locally; this avoids Discord's deprecated implicit edit-original behavior. Confirmed
original deletion prevents another local original edit/delete, while eligible
follow-ups retain their own token lifetime. Only one continuation mutation may
be active per responder; overlapping callers fail promptly rather than building
an unbounded queue. JSON-only conveniences do not silently buffer uploads; bounded
uploads and other original/follow-up operations remain available through
[typed endpoints](WebhooksInteractionsVoice.md).

Unknown initial adapter failures leave `.indeterminate`, blocking retry and further
continuation through that owner. Only positive not-submitted evidence or a complete
rejection reopens the slot; Discord codes 10062 and 40060 retain expired-token or
unknown remote acknowledgement ownership respectively. Continuation cancellation,
deadline or transport loss after adapter entry is an explicit
`DiscordError.unknownMutationOutcome`. Confirmed partial progress remains visible;
reconcile remote state before repeating a possibly applied operation. Neither a
cancelled task nor an expired timer establishes that a mutation was rejected.

## Optional early auto-defer

`InteractionAutoDeferPolicy` requires a positive receipt-relative delay below three
seconds; its default is two seconds. Message mode requires explicit public/ephemeral
visibility. Update mode silently acknowledges an existing component/message-associated
modal message. PING, autocomplete and unknown kinds are never automatically deferred.

`runWithAutoDefer` owns and joins one handler/timer pair. A reserved manual response
wins the initial slot; the timer sends no second callback. A fast handler still owns
its response; returning without replying does not invent success. After a confirmed
defer, handlers complete with `editOriginal`, rather than another `reply`. Races are
reported as in-flight/already-acknowledged state, so handlers must account for that
state when choosing an immediate response or completing a defer. Handler errors
remain observable after acknowledgement. Cancellation joins child cleanup; injected
operations must cooperate with cancellation. Continuous-clock deadline waits use
100 ms checkpoints to bound cancelled native timer retention; custom clocks keep
their original registration/cancellation behavior.

## Definitions, routing and explicit reconciliation

`CommandDefinition` provides macro-free slash, user/message context-menu and Activity
entry-point builders over `ApplicationCommandCreate`. Its options result builder
supports ordered blocks, arrays, conditionals and loops. Existing validation covers
all current option types, required-before-optional ordering, unique sibling names,
group → subcommand → leaf nesting, choice/autocomplete combinations, localizations,
permissions, invocation/install contexts and the shared 8,000-scalar command text
budget. Invalid definitions fail before any fetch or write.

`CommandRouter` keeps command/type/subcommand, focused autocomplete, component and
modal identities separate. It matches exact custom IDs, preserves submitted values
on the context and never routes display-only link previews. Defaults are 1,024 fixed
routes, 256 KiB of retained route text and 64 active handlers. Input inspection is
bounded to three levels of at most 25 siblings. Overload fails immediately; handler
errors/cancellation release admission. Adopting a router registers no commands and
starts no tasks. Handlers run in the caller's task, outside Gateway heartbeat/control
ownership.

`CommandReconciler.synchronize` is explicit: one uncached list with full localizations,
canonical comparison, then only changed managed creates or PATCHes by stable ID.
There is no startup sync, unmanaged deletion, bulk overwrite or rollback. Repeating
equivalent definitions writes nothing. Known omitted defaults and empty/null locale
dictionaries compare consistently; numeric values keep exact JSON lexemes. Omitted
contexts, installation types, handler and deprecated DM/default-permission settings
remain unmanaged and are preserved when another field changes. Localization,
ordinary permissions, age restriction and slash options are complete replacements
when managed. Desired catalogs are bounded to documented per-kind caps (131 global
or 130 guild total) and 1 MiB of definition JSON by default. One owner permits one
sync at a time; cross-process writers require external coordination. A failed write
reports acknowledged changes, failing definition index and original mutation evidence.

## Independent webhook-event ingress

Webhook event PING is envelope type **0** and returns empty **204** with the required
JSON content type; interaction PING is type **1** and responds with a PONG callback.
`WebhookEventProcessor` accepts only verifier-produced bytes for its application and
supported envelope version/kind. It parses typed/unknown event payloads independently
of interaction routing. Documented authorization/deauthorization, entitlement,
lobby-message and game-direct-message names are represented; quest enrollment is
upstream-unavailable and retained without claiming a delivered implementation.

The processor has no handler queue or automatic side-effect retry. Its required
durable-admission hook must atomically commit recoverable work and a duplicate marker
before returning `.accepted` or `.alreadyAccepted`; only then does the processor
return 204. PING needs no durable write. Default limits are 32 concurrent durable
calls and 1,024 retained successful delivery digests. Retention may be zero; then
every retry consults durable storage. Pending duplicates, overload, unavailable or
uncertain durable commits and cancellation return 503. The sole digest is SHA-256
of the exact signed body, not a Discord event ID; different serialization can produce
a different key, so consumers may need additional semantic idempotency.

Use a verifier configured to allow identical retries. A local successful-digest hit
accelerates acknowledgement; durable storage remains authoritative after eviction
or restart. Cancellation after a successful commit retains the marker but returns
503, allowing a later retry to resolve it. Discord expects acknowledgement within
three seconds and retries with exponential backoff for up to ten minutes. Bound
store latency and retention/recovery accordingly. Ordering, exactly-once effects,
durable storage implementation and fleet coordination are not supplied by the
process-local digest cache.

Webhook social-message projections are deliberately partial: selected message,
author, lobby/channel, metadata, flags and timestamp fields are typed, with exact
unknown data retained. They do not complete the native Social SDK message union,
attachments or every related child resource. Unknown event names remain inspectable
without becoming supported native SDK operations.

## Display-only link previews

`ComponentEmbed` publishes a single parent Container containing permitted display
components and link-style buttons. It validates at most 40 components including
the parent, ten gallery items across the document, no nested Containers or
interactive controls, RGB in 0...0xFFFFFF and a complete **3,000 UTF-8 byte** JSON
budget. Inline script escaping of `<`, `>` and `&` is included in that byte budget.
Media URLs must be absolute HTTP(S), without credentials; linked JSON must share
the page host or its parent/subdomain relationship. The helpers fetch no URLs.

`inlineScript` and `linkedJSONTag` produce server-rendered head declarations;
`LinkPreviewMetadata` supplies escaped common Open Graph title/description/URL/type
and optional provider/image/theme/large-image fallback tags. These helpers cover a
named metadata slice, not the entire Open Graph/oEmbed ecosystem. Discord may trim,
decline or cache a preview and requires its page/assets to be fetchable within its
documented ten-second window. A valid local model proves neither rendering nor
fetchability. Display components are never routed as user interactions.

## Validation and qualification

Swift Testing suites use real Ed25519 signatures, raw-body tampering, exact large
IDs, virtual clocks, finite scripted transports and cancellation gates. They cover
signature/replay policy, HTTP PING/response mechanics, overload, concurrent initial
reservation, defer/reply ownership, expiry, handler failures, explicit mutation
uncertainty, command routing/no-op reconciliation, durable admission and display
constraints. Run `swift build`, `swift test` and build the independent HTTPApp.
Reviewed inventory changes also require the [offline generation checks](Generation.md).

Evidence is local macOS arm64/Swift 6.4. The independent example builds with the
selected product graph and no authenticated execution. Live Discord delivery,
minimum OS, physical devices, other hosts, durable-store implementations, native
Social SDK completion, cross-process coordination and fleet throughput/memory
qualification remain separate gates. Existing [transport](Transport.md) and
[platform](PlatformSupport.md) limits continue to apply.
