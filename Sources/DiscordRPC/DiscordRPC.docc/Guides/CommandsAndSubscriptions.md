[//]: # "File: Sources/DiscordRPC/DiscordRPC.docc/Guides/CommandsAndSubscriptions.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Executing commands and consuming desktop events

Use typed builders, exact correlation and bounded ordered delivery.

## Overview

### Build a command before sending

``RPCRequest`` validates documented command shapes. ``RPCResponsePayload`` projects replies by command; ``RPCEventPayload`` projects known dispatches while preserving explicit unknown data paths.

```swift
import DiscordRPC
import DiscordTransport

/// Reads the desktop user's guild list after the caller has established required authority.
func desktopGuilds(
    client: RPCClient<ContinuousClock>,
    clock: ContinuousClock
) async throws -> RPCResponsePayload {
    let request = try RPCRequest.getGuilds()
    let result = try await client.request(
        request,
        context: TransportContext(
            clock: clock,
            deadline: clock.now.advanced(by: .seconds(10))
        )
    )
    return try RPCResponsePayload.decode(command: request.command, data: result)
}
```

The client correlates a reply by nonce and command, and event where applicable. A matching nonce with the wrong command is not accepted as a successful response. Tokens, activity join secrets, device names and unknown payload fields are excluded from ordinary diagnostic descriptions; application code must preserve that discipline when examining explicit raw values.

Voice settings alter the Discord desktop client's configuration. They do not open the embedding application's microphone or establish an application's Voice session. Channel selection and force-move operations retain their own user approval and scope prerequisites. Rich Presence is also distinct from bot presence and Activity iframe presence; an unresolved desktop clear contract should not be guessed from another surface.

### Subscribe and drain with one consumer

Submit `RPCRequest.subscribe` for the exact event and arguments after authorization. Consume dispatches using `nextEvent(context:)` from one task, project `name` and `data`, and hand work to a separately bounded application queue when needed. Keep business handlers outside the client's protocol reader so slow work cannot stall framing or control replies.

Event and pending-request capacities are explicit. Exhaustion terminates the session rather than silently dropping subscription state. `resourceCounts()` exposes aggregate counts and bytes for tests and operational observation without user payloads. Reconnect requires renewed authorization and subscriptions.

### Frame streams incrementally

``RPCFrameDecoder`` handles arbitrary IPC chunking using a bounded payload length, opcode and little-endian framing. A stream read may contain a partial header, several frames or any combination. `finish()` detects an unfinished frame at EOF. ``RPCIPCConnection`` owns this translation for normal consumers; raw framing is useful for injected peers and protocol tests.

Test fragmented/coalesced frames, oversized lengths, unsupported opcodes, nonce/command mismatch, repeated EOF, pending cancellation, event overflow and protocol close during a command. Do not replay a mutation just because a timeout removed its local waiter.
