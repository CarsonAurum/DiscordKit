# Forwarding application lifecycle

Transfer transport ownership only while both host policy and actual adapter qualification allow it.

## Overview

### Make the app the source of lifecycle events

``AppleLifecycle`` is an actor that starts no UI observers, sockets or background tasks. Your AppKit, SwiftUI or UIKit integration forwards the app's actual state through `transition(to:)`. Use active, inactive, background, suspended and stopped as host observations rather than guesses based on elapsed time.

```swift
import DiscordApplePlatform
import DiscordCore
import DiscordTransport

/// Retains a qualified transport until host policy revokes it, then awaits shutdown.
func retainUntilSuspended(
    resource: any TransportResource,
    capability: PlatformCapability,
    qualified: Set<PlatformCapability>
) async throws {
    let lifecycle = try AppleLifecycle(
        qualifiedCapabilities: qualified,
        maximumResources: 16
    )
    do {
        _ = try await lifecycle.retain(resource, requiring: capability)
        await lifecycle.transition(to: .suspended)
        await lifecycle.close()
    } catch {
        // A failed retain leaves ownership with the caller.
        await resource.close()
        await lifecycle.close()
        throw error
    }
}
```

The `qualified` argument must come from evidence for the actual adapter and deployment host. Supplying a capability is an assertion, not an OS permission request or probe. The default empty set reports `notQualified`. The helper illustrates ownership; a real app retains the lifecycle actor across foreground transitions instead of immediately suspending it.

### Handle transfer and reentrancy correctly

Successful retention transfers cleanup responsibility and returns a registration token. A rejected retention leaves the resource with its caller. `release` closes one registration; `transition` first prevents new admission and then closes resources invalidated by the new policy. Both await the cleanup they own. Competing transitions wait for current cleanup before applying their state.

After any suspension point, query current availability again before creating or retaining replacement resources. An already submitted network write cannot be recalled. Cancellation of a transition caller does not abandon its owned cleanup.

`close()` applies stopped state. An explicit later transition to active can begin another adoption lifecycle, but previously closed resources need fresh owners. Do not reuse encryption counters, socket objects or invalidated credentials merely because foreground use becomes permitted again.

### Respect platform restrictions

Mobile background/suspended states do not promise long-lived network execution. watchOS policy restricts raw sockets and listeners, and this owner does not infer exceptions or acquire execution time. Local IPC/listeners remain restricted outside macOS. Browser authorization and audio capability rows are not activated by caller qualification in this lifecycle policy; native audio has the separate contract in <doc:NativeAudio>.

Use injected hosts and fake closeable resources to test resource caps, rejected transfer, repeated release and transitions during cleanup. A simulator build does not establish device lifecycle or background entitlement behavior.
