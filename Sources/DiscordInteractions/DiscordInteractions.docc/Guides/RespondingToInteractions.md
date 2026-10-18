# Replying, deferring and completing interactions

Reserve one initial response and preserve uncertainty after a possibly submitted callback.

## Overview

### One actor owns acknowledgement

``InteractionResponder`` binds the exact interaction ID, application ID, token, delivery mode, receipt time, clock, response sink and acknowledgement admission. ``InteractionContext`` validates that ownership when normalizing delivery. An unrelated token or another interaction's responder cannot be substituted accidentally.

The initial response deadline is strictly before receipt plus three seconds. A confirmed acknowledgement permits continuations strictly before receipt plus 900 seconds. Capture receipt before decoding or queueing. Future receipt offsets fail instead of extending token lifetime.

The actor reserves acknowledgement before its first suspension, preventing concurrent reply/defer calls from sending two callbacks. ``InteractionAcknowledgementAdmission`` bounds initial count and encoded JSON bytes independently of ordinary REST traffic.

### Choose the response that fits the trigger

`reply` is initial-only. `respond` supports implemented callback variants, including message, update/defer, autocomplete, modal and Activity results. An update needs an actual source-message snapshot. Unknown incoming kinds remain inspectable without inventing callback compatibility. Ephemeral visibility, quotas, permissions and application eligibility remain subject to Discord.

For work that needs longer than the initial window, defer first and complete the original response:

```swift
import DiscordInteractions
import DiscordModels

/// Completes an already normalized application interaction with explicit deferral.
/// - Parameter context: Authenticated context with a continuation-capable response sink.
/// - Throws: Admission, token expiry, response-sink or uncertain-mutation failures.
func completeDeferredExample(_ context: InteractionContext) async throws {
    try await context.responder.deferResponse(ephemeral: true)
    _ = try await context.responder.editOriginal(
        InteractionMessageEdit(content: .value("Work completed"),
            deferredResponse: true))
}
```

Ephemeral visibility is selected by the defer. A follow-up before completing that deferred original is rejected locally. Confirmed original deletion prevents another edit/delete through the owner. Only one continuation mutation can be active; overlapping callers fail promptly instead of accumulating a queue.

### Keep HTTP receipt separate from REST mechanics

HTTP and Gateway are alternative configured receipt modes. Gateway-delivered interactions still respond through HTTP. Use ``InteractionResponseSink`` with dedicated initial and continuation REST clients that retain the exact interaction token, shared token identity and applicable rate authority. Separate acknowledgement queues do not bypass learned route/resource limits.

Inline HTTP responses and external callback endpoints have different original-request acknowledgement mechanics. The supplied HTTP application uses inline JSON; a custom sink owns its matching response behavior.

### Handle auto-defer and uncertainty explicitly

``InteractionAutoDeferPolicy`` owns a bounded handler/timer pair through `runWithAutoDefer`. A manual response reservation wins without a second callback. Message mode requires an explicit visibility choice; update mode requires a compatible message-associated trigger. PING, autocomplete and unknown kinds are not automatically deferred.

Unknown initial adapter failures leave an indeterminate owner and block another callback. Only positive not-submitted evidence or a complete rejection can reopen the slot. Continuation cancellation or transport loss after adapter entry can mean the write succeeded. Preserve acknowledged progress and reconcile before repeating a possibly applied operation.

Test concurrent initial calls, exact deadlines, fast/slow handlers, defer/manual races, unsupported triggers, original deletion, continuation overlap, explicit rejection, uncertain submission and cancellation joining children. Virtual clocks and barriers make those races deterministic.
