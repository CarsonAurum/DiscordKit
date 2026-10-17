# Signed ingress, interactions and commands: Phase 8

Verified and locally added **2026-10-17**. REST callbacks and command registration
use **API v10**; incoming interaction payload version **1** and webhook-event
envelope version **1** are separate protocols. Original discovery snapshots and
source revision/hash pins are preserved. Current written source fingerprints are
in [the verification record](../interaction-runtime-current-sources.json).

Previously Models/HTTP described callbacks, commands and components without an
authenticated ingress, response owner, router or command synchronization layer.
Independent Interactions and Commands products implement those paths. The umbrella
adds aliases; the independent HTTP application excludes Gateway, Client and Cache.

Ed25519 covers original timestamp bytes followed by the exact original request body
before decoding. Bounds cover bodies, headers, handlers, initial acknowledgements
and replay metadata. Replay policy is explicit; webhook-event retries use
allow-identical policy with durable admission. Request and response bodies close
through cancellation/deadline races. Local replay metadata is not a fleet authority.

Response actors reserve the initial acknowledgement before suspension, enforce
receipt-relative three-second acknowledgement and fifteen-minute token expiry, and
retain ambiguous outcomes. Compatible auto-defer has explicit visibility; autocomplete
never auto-defers. HTTP sends the inline callback while handlers remain structured.
Gateway contexts use the same types with HTTP callback sinks and separate initial
admission. Deferred originals complete explicitly before follow-up creation.

Macro-free definitions adopt existing validated payloads. Bounded exact routes
distinguish commands, autocomplete, components and modals. Explicit synchronization
fetches/canonicalizes, PATCHes changed existing IDs, POSTs new definitions and sends
zero writes for identical definitions. Unmanaged commands and omitted installation,
context, handler and deprecated settings survive. No startup registration, deletion
or global bulk overwrite occurs; failures retain partial write evidence.

Webhook events recognize twelve names and preserve future values. Authorization
and entitlement data are typed; social-message child families and the unavailable
quest schema remain partial. PING receives empty 204. Events receive 204 after
accepted/duplicate durable admission; overload, pending duplicates and failed or
uncertain durable commits return 503 for retry. Bounded exact-byte SHA256 metadata
does not promise semantic exactly-once effects or ordered delivery.

Website component embeds are display-only and never routed as interactions.
Publishing validates the supported display subset, root Container, forty-component,
ten-gallery-item and 3,000 escaped UTF-8 byte limits. Inline/linked markup and common
Open Graph fallbacks are provided. Video/oEmbed/JSON-LD metadata and an HTML parser
remain unsupported. Existing component projections retain unknown fields.

Discord announced webhook events on **2024-10-25**, radio/checkbox modal components
on **2026-02-12** and component embeds/link-preview docs on **2026-10-05**. Other
upstream introduction/effective dates remain unknown. Sources reviewed:
[interaction lifecycle](https://docs.discord.com/developers/interactions/receiving-and-responding),
[commands](https://docs.discord.com/developers/interactions/application-commands),
[webhook events](https://docs.discord.com/developers/events/webhook-events),
[component embeds](https://docs.discord.com/developers/link-previews/component-embeds),
[link previews](https://docs.discord.com/developers/link-previews/overview),
[components](https://docs.discord.com/developers/components/reference),
[API reference](https://docs.discord.com/developers/reference) and
[change log](https://docs.discord.com/developers/change-log).

Migration is additive: import the independent products, share bounded authorities,
select one delivery mode, explicitly register managed commands and own adapter/store
cleanup. Existing typed endpoints handle bounded multipart callbacks/follow-ups;
convenience response sinks are JSON-only. Local deterministic/macOS evidence does
not qualify live Discord, rendered previews, remote durable stores, other hosts or
devices, or fleet capacity. See [contracts](../../Interactions.md) and the
[execution record](../../../.air/plans/phase-8-execution.plan.md).
