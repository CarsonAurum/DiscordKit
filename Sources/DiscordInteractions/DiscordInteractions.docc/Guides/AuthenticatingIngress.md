# Authenticating exact signed request bytes

Verify before decoding and bound ingress independently from application handlers.

## Overview

### Preserve the signed representation

``SignedRequestVerifier`` authenticates Ed25519 over the exact timestamp bytes followed by the exact body bytes. A reverse proxy or server framework must forward those bytes unchanged. Parsing JSON and serializing it again changes the signed representation even if the object looks equivalent.

Require exactly one signature header and one timestamp header. Invalid encodings, stale/future timestamps, body excess and signature failure must stop before interaction decoding or user handlers. A valid signature establishes request provenance for the configured public key; it does not replace application-ID checks, consent or endpoint authorization.

The verifier defaults to a one-MiB body cap, a 300-second timestamp-age window, 30-second future skew and 4,096 local replay records. Timestamp windows are local policy and have bounded configuration ranges. Keep your server clock trustworthy and apply independent proxy/listener header/body caps.

### Construct the application without opening a listener

```swift
import DiscordCore
import DiscordInteractions

let publicKey = String(repeating: "00", count: 32) // Synthetic configuration only.
let verifier = try SignedRequestVerifier(publicKey: publicKey)
let ingress = try DiscordSignedIngress(verifier: verifier,
    maximumConcurrentRequests: 32)
let application = try InteractionHTTPApplication(
    applicationID: ApplicationID(rawValue: 1), ingress: ingress,
    admission: InteractionAcknowledgementAdmission(maximumConcurrent: 32))
```

This snippet constructs owners only. Replace the synthetic application/key with the registered application before accepting real traffic. The [HTTPApp example](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/HTTPApp) supplies bounded NIO loopback ingress and structured handler tasks. Deployment owns public HTTPS termination and exact-byte forwarding.

### Bound acceptance, body reading and handler work

``DiscordSignedIngress`` uses fail-fast concurrent admission with finite header/body budgets. Authentication failures return 401, unsupported methods 405, excessive body/header data 413/431 and overload 503. Cancellation/deadline propagation closes owned bodies.

``InteractionHTTPApplication`` verifies the application ID after authentication and supplies a normalized ``InteractionContext``. HTTP PING produces inline PONG without invoking user handlers. Successful reply/defer sends its inline response immediately; handler completion remains structured and awaited. A handler that returns without responding fails rather than inventing success.

Capture actual receipt time before slow authentication/body work because it consumes the initial response window. Set a finite transport context for body reading, handler work and fallback transmission. Deferred work may need an outer deadline longer than the initial three-second window and an injected continuation sink.

### Choose replay policy intentionally

Default reject-identical policy fails closed at replay capacity instead of evicting protection. Allow-identical-retries authenticates every attempt and reports replay advisory information; it is appropriate when a durable webhook admission store owns duplicates. Local signed-request replay identity differs from semantic JSON equality and from application business idempotency.

Test real generated signatures, body/timestamp tampering, duplicate headers, age/skew boundaries, replay saturation, malformed payload after valid signing, app mismatch, overload, cancellation and response cleanup. Use synthetic signed bodies without Discord credentials.
