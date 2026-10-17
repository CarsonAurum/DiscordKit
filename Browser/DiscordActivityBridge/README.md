# DiscordKit Activity browser bridge

This is an owned, dependency-free implementation of the Activity iframe RPC v1
messaging lifecycle. Import the ES modules directly; no npm install, code generation,
or third-party runtime is needed. It requires modern browser `URL`, `TextEncoder`,
`AbortSignal`, and `crypto.randomUUID` APIs. Construction starts no listener, timer,
network request, or background task.

The protocol evidence is Discord's [Embedded App SDK source at revision
14264eccbf9e68d5d58c1aadbc7579e003e0dce6](https://github.com/discord/embedded-app-sdk/tree/14264eccbf9e68d5d58c1aadbc7579e003e0dce6),
including `src/Discord.ts`, `src/schema/index.ts`, `src/schema/common.ts`, and
`src/schema/responses.ts`. That source is research evidence, not a runtime import
or copied implementation. The owned bridge does not advertise the upstream npm
SDK's version in its optional handshake field.

## JavaScript lifecycle

```js
import { ActivityBridge, createWindowTransport } from './ActivityBridge.mjs';

// Select this source and origin from the embedding/deployment contract.
// A popout may require parent.opener; do not infer trust from document.referrer.
const trustedSource = window.parent;
const hostOrigin = 'https://discord.com';
const bridge = new ActivityBridge({
    clientId: 'YOUR_APPLICATION_ID',
    search: window.location.search,
    source: trustedSource,
    hostOrigin,
    allowedOrigins: ['https://discord.com'],
    transport: createWindowTransport(window, trustedSource),
});

await bridge.start({ timeoutMs: 15000 });
const reply = await bridge.request('GET_ACTIVITY_INSTANCE_CONNECTED_PARTICIPANTS', {});
const subscription = await bridge.subscribe(
    'ACTIVITY_INSTANCE_PARTICIPANTS_UPDATE', {}, (data) => render(data.participants),
);
// Drain regularly even when listeners are installed: this is also the bounded
// event/native handoff queue. Queue overflow closes the lifecycle.
const frames = bridge.takeEvents();
await subscription.unsubscribe();
bridge.close();
```

Every input frame requires both exact `event.source` identity and the selected
exact `event.origin`. The selected origin must occur in the explicit allowlist.
Opaque `null` origins, wildcard targets, credentials, paths, and referrer-derived
trust are rejected. Mobile/WebKit or popout embeddings need an injected,
explicitly authenticated source contract; a permissive origin fallback is absent.

`start()` sends `[0,{v:1,encoding:'json',client_id,frame_id}]` and resolves only
after an authenticated `[1,{cmd:'DISPATCH',evt:'READY',nonce:null,data:...}]`
containing RPC version 1 and READY configuration. Legacy HELLO is ignored.
Commands send opcode 1 and resolve to the complete response frame. Both nonce
and command must match; subscription acknowledgements use outer `evt:null`
and `data.evt` for the event name. RPC `evt:'ERROR'` rejects the matching command;
uncorrelated errors and unknown dispatch events remain in the event queue.
The documented `GET_CHANNEL_PERMISSIONS` response permits a structured-clone
`bigint` or string. That field normalizes to an exact decimal string before the
JSON boundary, preserving bits above JavaScript's safe integer range. Other
non-JSON BigInts are rejected; no conversion through `Number` occurs.
All other numeric values use the JavaScript JSON numeric domain: numbers must
be finite, and integer-valued numbers must be within the safe integer range.
The raw Swift adapter rejects overflowing or unsafe decoded integer values before
postMessage; encode opaque identifiers and wide integral values as strings.
Fractional values retain native JavaScript binary-number semantics.
Close code/reason, malformed authenticated frames, and queue overflow terminate
the bridge and reject all owned work. Peer close reasons are optional.

`AbortSignal` and positive millisecond timeouts are available for startup,
requests, and subscription ownership. Cancellation never retries or reverses
a remote mutation: its result can be indeterminate. Duplicate event+argument
subscriptions share one upstream subscription, using canonical structural
argument identity. Each caller owns an independent listener/handle, even for
the same function. Release removes its listener immediately; the last release
awaits upstream unsubscribe. Races serialize subscribe/unsubscribe transitions.
A transition that fails or never acknowledges closes the session to prevent
ambiguous remote subscription state from accumulating. Listeners run in receive
order without awaiting returned promises; synchronous listener exceptions are
isolated. Keep callbacks synchronous and enqueue heavy or asynchronous work.

Default bounds are 1 MiB per frame, 64 pending commands, 4 MiB pending command
bytes, 64 subscription groups, 128 listeners, 128 queued events, 4 MiB queued
event bytes, and a 15-second startup/command deadline. `limits` overrides must
be positive integers; deadlines cannot exceed the native timer range. Context
query text is limited to 16 KiB and duplicate known parameters are rejected.
Known parameter values have a 4096-byte UTF-8 bound and reject ASCII controls.
`diagnostics` contains counts/bytes only, without credentials or payloads.

## Swift/native raw transport

Use `createActivityTransport` when `DiscordActivities.ActivityClient` owns the
handshake, correlation, subscriptions, and receive queue. Do not run the raw
adapter and JavaScript `ActivityBridge` lifecycle on the same session.

```js
import { createActivityTransport } from './ActivityBridge.mjs';

const transport = createActivityTransport({
    activityWindow: window,
    trustedSource: window.parent,
    hostOrigin: 'https://discord.com',
    allowedOrigins: ['https://discord.com'],
    maxFrameBytes: 1024 * 1024,
});
// The app-provided binding owns a bounded Swift receive queue and rejects all
// pending reads in onClose. Each onFrame argument is an owned Uint8Array.
transport.start(bytes => swiftBinding.receive(bytes), error => swiftBinding.close(error.code));
// Outgoing Swift Data must be bridged to a Uint8Array containing one JSON tuple.
swiftBinding.onSend = bytes => transport.send(bytes);
// After the Swift owner sends its protocol close frame:
swiftBinding.onStop = () => transport.close();
```

`start` installs a single listener and can run once. `send` accepts strict UTF-8
JSON tuple bytes only after start. The raw adapter bounds bytes and validates
source/origin before delivering a frame; it does not retain a receive queue or
create pending-read promises. Invalid authenticated input terminates the adapter
and calls the injected close callback once. That callback must release the
binding's pending reads. `close()` detaches listeners even if owner callbacks fail.
This binding contract can be implemented by a WebKit host, a browser/Wasm build,
or another explicitly authenticated adapter. The module does not ship a native
WebKit runtime or imply that arbitrary browsers can create Discord Activity hosts.

## Explicit Activity network helpers

```js
import { ActivityURLMapper, createActivityFetch, createActivityWebSocket } from './ActivityNetwork.mjs';

const mapper = new ActivityURLMapper({
    activityOrigin: window.location.origin,
    mappings: [
        { prefix: '/api', target: 'api.example.com/v1' },
        { prefix: '/tenant/{tenant}', target: '{tenant}.example.net/api' },
    ],
});
const activityFetch = createActivityFetch(mapper, window.fetch.bind(window));
const activitySocket = createActivityWebSocket(mapper, window.WebSocket);
await activityFetch('https://api.example.com/v1/items');
const socket = activitySocket('wss://api.example.com/v1/live', ['json']);
```

Configure the corresponding URL mappings in Discord's developer portal. These
helpers neither register routes nor bypass Discord's proxy/CSP. Matching uses
exact host and target-path boundaries, with escaped literals and whole DNS-label
substitutions. Queries and trailing slashes survive mapping. The mapper rejects
credentials, fragments, unsupported schemes, nested encoded path separators,
traversal, and unmapped external URLs. Local relative/already proxied URLs remain
within the Activity origin. Mapping tables are limited to 128 routes, individual
prefixes/targets to 2048 characters, and input URLs to 16 KiB UTF-8.

Helpers preserve Request bodies as streams through native Request constructors;
they do not materialize blobs or prebuffer unbounded uploads. Request-init
overrides and signals follow native semantics. Socket lifetime/backpressure
belongs to the injected WebSocket and its caller. There is no global fetch,
WebSocket, XHR, DOM attribute, script, or console patching.

## Local validation and qualification

Run `node --test Browser/DiscordActivityBridge/*.test.mjs` from the repository
root, or `npm test` from this directory. Tests use Node's built-in runner,
manual timers, recorded/synthetic tuples, and simulated host identity; they
perform no live Discord calls and require no npm dependency installation.

They cover source/origin spoofing, READY spoofing, synchronous reply races,
nonce/command isolation, structured errors, deadlines/cancellation, bounded
admission and queues, subscription refcount/transition races, never-ack cleanup,
raw UTF-8 transport teardown, proxy boundaries, and streamed Request preservation.
Fake-DOM integration also imports the real browser example and exercises READY,
authorization/backend exchange, authentication, participants, deployment-origin
rejection, backend rejection, and page disposal without reading a referrer.
Approved Web/iOS/Android Discord host smoke tests remain required for handshake,
OAuth, participants, and purchase/entitlement qualification. Client secrets and
OAuth token exchange or server entitlement verification belong in the server
products; the browser bridge does not receive a client secret.
