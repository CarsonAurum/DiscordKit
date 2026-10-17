# Webhooks, interaction responses and voice control: Phase 5H

Verified and locally added **2026-10-16**, REST API **v10**. Local release/commit
remain unknown until creation. Clean Phase 5G baseline: a33989a. Current
[source fingerprints](../webhook-voice-interaction-current-sources.json) are separate
from historical discovery membership pins; no historical source revision is rewritten.

## Previous and current behavior

Previously these 28 written operations were unsupported. This batch implements
15 webhook, eight interaction-response/message and five Voice REST operations.
Webhook management/token variants, native/Slack/GitHub execution, messages, callback
result variants, original/follow-up messages and voice state/region control now use
validated typed descriptors and bounded owned models. Existing guild voice-region
reads remain available. Related resource projections retain explicit partial coverage.

Path-token clients now require a matching typed credential before cache/admission;
webhook tokens additionally require shared outbound-IP identity for global admission.
Token-scoped route/cache identity remains separate from egress-global protection.
Read reduction is opt-in, uploads are bounded and replayable, successful writes
invalidate resource tags, and uncertain mutations are never silently replayed.

## Known upstream chronology

The [official change log](https://docs.discord.com/developers/change-log) establishes
the announcement dates below. Effective dates remain unknown unless explicitly
stated by the announcement; local support dates never establish upstream history.

| Behavior | Announced | Effective | Adopted behavior |
| --- | --- | --- | --- |
| Application command interactions | 2020-12-15 | unknown | Incoming command data and callbacks |
| Autocomplete interactions | 2021-10-27 | unknown | Typed choices and callback compatibility |
| Modals | 2022-02-08 | unknown | Validated callback definitions and submitted data |
| Delete ephemeral messages | 2022-10-20 | unknown | Original/follow-up delete token routes |
| Voice-state retrieval endpoints | 2024-08-05 | unknown | Current/named-user state GETs |
| Launch Activity callback | 2024-08-26 | unknown | Callback type 12 and returned Activity resource |
| Polls on deferred original response edits | 2024-09-04 | unknown | Explicit deferred-response context |
| Components V2 | 2025-04-22 | unknown | Existing message V2 validation with webhook/interaction restrictions |
| Additional modal components | 2025-08-25 | unknown | Label/select modal validation |
| More modal components | 2025-09-10 | unknown | Current written modal definitions |
| File upload component in modals | 2025-10-15 | unknown | File-input definitions and resolved attachments |
| Resolved channel app_permissions | 2026-07-16 | unknown | Exact partial resolved-channel fields preserved |
| Default file upload limit 20 MiB | 2026-09-03 | 2026-09-03 | Configurable conservative local hard caps remain explicit |

Other introduction/effective dates, including with_response callbacks, remain
unknown in this change. Webhook-event delivery/acknowledgement is distinct from
webhook REST execution and remains later ingress work.

## Compatibility and migration

Written references control preview disagreements. Slack/GitHub acknowledgement
shapes adopt the explicit official preview because prose does not specify response
bodies. Preview-only callback type 13 remains unknown in responses, unavailable as
a supported outgoing request. Callback activity-instance nullable/extra location
fields are explicit preview compatibility. Historical short voice-state examples
omit self_video; the current required structure controls. Minimal PING/future-kind contextual metadata omission remains explicit compatibility;
known non-PING interactions require current documented metadata.

Consumers must construct token-scoped REST clients rather than substituting bot
or bearer credentials for path-token operations; no Authorization is forwarded.
Share opaque rate identities by token and egress UUIDs by outbound IP. External
rate stores must honor usesEgressGlobalLimit in addition to existing global, route,
resource and invalid-response scopes. Existing header-authenticated descriptors
retain their API and policies; early category validation now also guards cached reads.

Callers own trusted receipt times, three-second acknowledgement and 15-minute token
lifetimes, prior response/ephemeral state, install/application eligibility and server
permissions. This REST work does not implement an ingress signature verifier,
router, durable acknowledgement owner or voice media stack. No dependencies or
products were added; 5I–5J and platform/live/distributed/soak qualification remain
open. See [contracts](../../WebhooksInteractionsVoice.md) and
[execution evidence](../../../.air/plans/phase-5h-execution.plan.md).
