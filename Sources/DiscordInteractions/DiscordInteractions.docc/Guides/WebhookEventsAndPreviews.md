[//]: # "File: Sources/DiscordInteractions/DiscordInteractions.docc/Guides/WebhookEventsAndPreviews.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Durable webhook events and display-only previews

Acknowledge recoverable work only after durable admission and keep previews outside command routing.

## Overview

### Distinguish webhook events from interactions

``WebhookEventProcessor`` accepts verifier-produced bytes for its configured application and supported envelope. Webhook event PING uses envelope type zero and returns empty 204; interaction PING uses type one and a PONG callback. They are independent protocols even though both use signed HTTP ingress.

Configure the signature verifier to allow authenticated identical retries for webhook events. Supply a durable admission hook that atomically commits recoverable work and a duplicate marker before returning accepted/already-accepted. Only then may the processor return 204. PING needs no durable write.

### Make duplicate ownership durable

The processor has no background handler queue or automatic side-effect retry. Defaults bound concurrent durable calls to 32 and retain 1,024 successful delivery digests locally. Retention can be zero, requiring every retry to consult durable storage. The digest is SHA-256 of the exact signed body, so another serialization can yield another key; business effects may need additional semantic idempotency.

Pending duplicates, overload, uncertain durable commits, unavailable storage and cancellation return 503. Cancellation after a successful commit retains the marker so a later retry can resolve it. The local digest cache accelerates acknowledgement but is not authoritative across restart or workers. Bound store latency so admission fits the upstream acknowledgement window.

Authorization/deauthorization, entitlement and documented social-message events retain known fields plus exact unknown JSON. A partial message projection does not imply every native SDK variant or attachment is implemented. Unknown event names remain visible and need an explicit application policy.

### Separate admission from effect delivery

After durable acceptance, an application worker owns retry, dead-letter handling, ordering and idempotent effects. A successful webhook acknowledgement is not proof the game item or business action completed. Test duplicate races, store failure before commit, uncertain commit, cancellation after commit, zero local retention, restart and application mismatch.

### Publish only display-safe previews

The DiscordModels `ComponentEmbed` and `LinkPreviewMetadata` helpers construct display-only linked/inline metadata. They validate a parent container with allowed display components/link buttons, component/gallery limits, permitted URLs, escaped inline script and the complete JSON byte budget. They fetch no URLs and do not establish public reachability or actual Discord rendering.

Display components are never routed as user interactions by DiscordCommands. A link preview cannot stand in for a signed button action, consent or purchase confirmation. Server-render escaped metadata from approved application values, keep client secrets out of the page and use explicit fallback metadata for consumers that ignore the richer preview.

See the [signed ingress contract](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Interactions.md) for exact webhook admission and preview constraints.
