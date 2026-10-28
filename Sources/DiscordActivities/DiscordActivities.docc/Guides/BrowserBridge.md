[//]: # "File: Sources/DiscordActivities/DiscordActivities.docc/Guides/BrowserBridge.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Use the JavaScript browser bridge

Choose one session owner, authenticate the browser message source, and map network calls explicitly.

## Overview

### Choose JavaScript or Swift lifecycle ownership

The dependency-free ES modules under [DiscordActivityBridge](https://github.com/CarsonAurum/DiscordKit/tree/main/Browser/DiscordActivityBridge) can own Activity RPC in JavaScript, or supply a raw byte transport to a Swift ActivityClient. Choose one lifecycle owner for a session. Starting both owners on the same host session would duplicate handshake, correlation and subscription ownership.

The modules require a modern browser's URL, TextEncoder/TextDecoder, AbortSignal and crypto.randomUUID APIs. Constructing the bridge validates configuration without attaching a listener or sending a message. Your deployment supplies the exact trusted source object and host origin. A standalone browser window does not become a Discord Activity host.

### Start a JavaScript-owned session

This contextual browser example uses a Discord-owned iframe. Replace the public application ID and select the source/origin from your deployment's authenticated embedding contract; a popout or mobile host can require a different explicit adapter.

```javascript
import { ActivityBridge, createWindowTransport } from './ActivityBridge.mjs';

const trustedSource = window.parent;
const bridge = new ActivityBridge({
    clientId: 'YOUR_APPLICATION_ID',
    search: window.location.search,
    source: trustedSource,
    hostOrigin: 'https://discord.com',
    allowedOrigins: ['https://discord.com'],
    transport: createWindowTransport(window, trustedSource),
});

try {
    await bridge.start({ timeoutMs: 15000 });
    const response = await bridge.request(
        'GET_ACTIVITY_INSTANCE_CONNECTED_PARTICIPANTS', {}
    );
    // Inspect response.data without logging profile payloads.
    const queuedFrames = bridge.takeEvents();
    // Process the bounded handoff queue in application receive order.
} finally {
    bridge.close();
}
```

Every incoming frame must match both exact event.source identity and the configured event.origin. The origin must be in the explicit allowlist. Wildcard, opaque null and referrer-derived trust are rejected. READY establishes host readiness; user authorization and backend code exchange remain separate operations.

### JavaScript API map

| Export or member | Contract |
| --- | --- |
| ActivityOpcodes | Frozen HANDSHAKE/FRAME/CLOSE/HELLO values for the RPC v1 tuple wire |
| ActivityBridgeError | Categorized bridge failure with optional RPC error code |
| parseActivityHostParameters(search) | Validates bounded host query parameters; context is configuration rather than source authentication |
| createWindowTransport(activityWindow, trustedSource) | Creates an injected listen/post adapter for the selected source |
| ActivityBridge constructor | Validates client ID, source, origin, transport and positive resource/time bounds; starts no work |
| bridge.context / bridge.clientId | Validated read-only session configuration |
| bridge.state / bridge.diagnostics | Lifecycle and bounded count/byte diagnostics without token or payload values |
| bridge.start(options) | Sends one handshake and awaits authenticated READY; initial startup owns its deadline/signal |
| bridge.request(cmd, args, options) | Correlates both command and nonce; returns the complete matching response frame |
| bridge.subscribe(event, args, listener, options) | Reference-counts canonical event/argument subscriptions; each handle owns its own listener |
| handle.unsubscribe() | Removes the listener immediately and awaits upstream unsubscribe for the final owner |
| bridge.takeEvents() | Drains the bounded event/native handoff queue; drain even when listeners are installed |
| bridge.close() | Ends the lifecycle, detaches listeners and rejects pending owned work |
| createActivityTransport(options) | Raw authenticated byte adapter with start(receive, onClose), send(bytes) and close() |
| ActivityURLMapper | Validates an ordered proxy mapping table; map(input) returns a local URL without I/O |
| createActivityFetch(mapper, fetchImpl, RequestType) | Produces an explicit fetch helper preserving native Request/stream behavior |
| createActivityWebSocket(mapper, WebSocketType) | Produces an explicit mapped socket factory; caller owns socket backpressure and close |

Request/start/subscription options accept AbortSignal and positive millisecond timeouts. Cancellation does not reverse a host mutation and never triggers an automatic replay. Synchronous listener exceptions are isolated; returned listener promises are not awaited. Enqueue heavy work into your own bounded pipeline.

Default bounds are 1 MiB per frame, 64 pending commands, 4 MiB pending command bytes, 64 subscription groups, 128 listeners, 128 queued events and 4 MiB queued event bytes. The default deadline is 15 seconds. Positive integer overrides must fit the native timer range. Queue overflow and malformed authenticated frames terminate the lifecycle rather than retaining unbounded state.

### Bind a Swift-owned session

Use createActivityTransport when Swift owns handshake, pending commands and subscriptions. Its start callback delivers an owned Uint8Array containing one JSON tuple. Your binding supplies a bounded Swift receive queue, rejects pending reads on close and converts outgoing Data to Uint8Array. The raw adapter does not provide a native WebKit runtime or retain its own receive queue. See <doc:HostAuthentication> for Swift startup and authorization.

### Map network calls explicitly

```javascript
import {
    ActivityURLMapper, createActivityFetch, createActivityWebSocket
} from './ActivityNetwork.mjs';

const mapper = new ActivityURLMapper({
    activityOrigin: window.location.origin,
    mappings: [{ prefix: '/api', target: 'api.example.com/v1' }],
});
const activityFetch = createActivityFetch(mapper, window.fetch.bind(window));
const activitySocket = createActivityWebSocket(mapper, window.WebSocket);
// A later invocation performs I/O; constructing these helpers does not.
```

Configure corresponding URL mappings in the Developer Portal. Mappings match exact host and target-path boundaries and preserve query parameters. Credentials, fragments, traversal, encoded path separators and unmapped external URLs are rejected. Helpers do not patch global fetch/WebSocket or bypass Discord's proxy and content-security policy. Native transport errors propagate; the host application owns socket lifetime and body consumption.

### Validate without a live host

Run `node --test Browser/DiscordActivityBridge/*.test.mjs`. Tests use simulated hosts and deterministic timers to cover spoofed sources/origins, correlation, subscription races, bounds, raw UTF-8 transport, proxy paths and streamed Request preservation. They require no npm runtime dependencies or Discord credentials. Real Discord Web/iOS/Android embedding, native bindings and purchase behavior require separate host qualification.
