# Commands, subscriptions and user-visible effects

Preserve typed responses, explicit null semantics and independent authorization for host actions.

## Overview

### Choose the narrow typed command

``ActivityRequests`` constructs typed ``ActivityRequest`` values. Builders validate documented argument shape and decode the corresponding response. Payload projections retain unknown fields for compatibility; unknown raw values do not become permission to execute a new command.

```swift
import DiscordActivities

/// Updates presence after the host has granted the required presence scope.
func publishActivityPresence<C: Clock>(client: ActivityClient<C>) async throws
where C.Duration == Duration {
    let presence = try ActivityPresenceUpdate(
        state: .value("Exploring a level"),
        details: .value("Playing with friends")
    )
    _ = try await client.execute(ActivityRequests.setActivity(activity: .value(presence)))
}
```

The application name comes from the host/application; ``ActivityPresenceUpdate`` intentionally excludes response-only name/application/flags. Optional fields distinguish omission from explicit null. A null whole Activity can explicitly clear embedded presence; do not copy that contract to desktop RPC or bot presence.

Command availability is platform-specific. Inspect ``ActivityHostPlatform`` and availability on the request/catalog before offering a feature, then still handle the authoritative host rejection. A local availability report does not establish approval, current permissions or user consent. Orientation has one narrow compatibility fallback for a documented invalid-payload response; other ambiguous commands are not replayed.

### Own subscription references

`subscribe` returns an ``ActivitySubscription`` token. Equal event/argument tuples share one upstream subscription. Release every token with `unsubscribe`; the final owner sends and awaits the upstream unsubscribe. A duplicate subscriber's cancellation does not cancel other owners. If the final transition becomes uncertain, the client closes rather than letting local and remote subscription state diverge.

Consume ordered events through the client's bounded event path and decode known data with ``ActivityEventPayload``. Keep application processing outside the protocol reader and bound any downstream work. ``ActivityClientLimits`` covers message bytes, pending commands, writes, events, groups and subscription tokens; aggregate budgets across several clients remain the application's responsibility.

### Treat purchases and links as explicit effects

Purchase, invite, sharing, navigation and external-link commands can show UI or mutate remote state. Trigger them from an explicit user action and handle cancellation/rejection without automatic replay. The user may complete an action even if your local waiter times out.

A host entitlement response or `ENTITLEMENT_CREATE` event is an advisory input to a backend check. Bind the authenticated user and SKU, verify authoritative entitlement data server-side, and only then grant access. Do not place client secrets or an entitlement authorization decision in iframe code. Some purchase results are null while completion arrives asynchronously.

Test absent/null/value fields, unknown enum values, invalid argument limits, subscription sharing, last-owner cancellation, full queues, host reload and indeterminate user actions. Actual mobile host capability and purchases remain separate from local simulated-message tests.
