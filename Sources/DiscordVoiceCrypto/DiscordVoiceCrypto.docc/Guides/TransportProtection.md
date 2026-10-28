[//]: # "File: Sources/DiscordVoiceCrypto/DiscordVoiceCrypto.docc/Guides/TransportProtection.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Protecting an exact transport-key lifetime

Share one counter owner per key and authenticate the exact RTP header.

## Overview

### Keep counter ownership unique

``VoiceTransportCipher`` is an actor so copying a value cannot accidentally fork the transmit counter. All senders using the same negotiated transport key must share that actor. Creating a second sending owner with the same key resets its counter and is forbidden. Session replacement requires fresh key material; RTP sequence/timestamp wrap does not reset cryptographic counters.

The actor accepts exactly 32 key bytes and a mode already negotiated by the authenticated Voice session. It does not obtain keys or choose protocol fallback. Constructor limits bound packet size, retained receive streams and total sends. Counter exhaustion requires a new key rather than wraparound.

```swift
import DiscordVoiceCrypto
import Foundation

/// Creates one exact-session nonce authority from fresh negotiated key material.
func makeTransportCipher(freshKey: Data) throws -> VoiceTransportCipher {
    try VoiceTransportCipher(
        mode: .aeadXChaCha20Poly1305RTPSize,
        key: freshKey,
        maximumPacketBytes: 1_500,
        maximumReceiveStreams: 64
    )
}
```

Use the server's accepted mode instead of hardcoding the example's mode in a real negotiator. Do not pass a public fixture key for real media. The owner has no network or background work, and explicit `close()` logically releases keys and replay state. Swift and underlying crypto storage do not guarantee physical memory erasure.

### Authenticate header and payload in the correct order

`seal(payload:authenticatedHeader:)` receives the exact clear RTP header and the already transformed complete payload. It returns ciphertext, a 16-byte authentication tag and a four-byte counter suffix. The exact header is AEAD associated data, including the SSRC bytes used by the receiver's replay partition.

```swift
import DiscordVoiceCrypto
import Foundation

/// Authenticates one packet using the caller's exact wire header and shared key owner.
func protectPayload(
    _ payload: Data,
    exactHeader: Data,
    cipher: VoiceTransportCipher
) async throws -> Data {
    try await cipher.seal(payload: payload, authenticatedHeader: exactHeader)
}
```

For headers containing extensions or CSRCs, obtain the authenticated header length from a validated RTP parser. Splitting every packet at a fixed 12-byte offset loses authenticated bytes. On receive, authenticate before exposing any plaintext to codecs, jitter state or application recording.

A send failure can still consume a reserved nonce. Never roll it back or replay an ambiguous encrypted write. There is no automatic retry inside this product.

### Bound receive state and reject replay

Receive replay windows retain authenticated SSRC histories under a configured stream cap. Failed tags do not advance accepted replay state. Already accepted counters or counters outside the retained replay window fail without plaintext. New authenticated streams above capacity fail; there is no silent eviction that could reset old replay protection.

The actor's local serialization cannot coordinate duplicate owners across processes. Deployments sharing a key outside one owner must supply a higher-level unique nonce authority, or avoid sharing that key entirely. Match peer/session identity before trusting any SSRC; a valid transport tag alone does not assign participant membership.

Test published primitive vectors, tampered header/payload/tag/suffix, duplicate packets, out-of-window counters, exact stream cap, exhaustion, cancellation and repeated closure. Passing those checks is not independent cryptographic review or live Discord interoperability.
