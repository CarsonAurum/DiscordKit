# Using low-level authenticated primitives

Reserve primitive APIs for callers that already own keys, nonces and protocol framing.

## Overview

### Distinguish primitives from session protection

``XChaCha20Poly1305`` combines the owned HChaCha20 construction with Swift Crypto ChaChaPoly. Keys are exactly 32 bytes, nonces exactly 24 bytes and tags 16 bytes. The algorithm reference is an expired IETF draft; implementing it is not an audit claim. Each seal/open has explicit payload/associated-data allocation ceilings.

```swift
import DiscordVoiceCrypto
import Foundation

/// Seals once with a caller-reserved nonce, returning ciphertext and tag without the nonce.
func sealPrimitive(
    plaintext: Data,
    key: Data,
    uniqueNonce: Data,
    associatedData: Data
) throws -> Data {
    try XChaCha20Poly1305.seal(
        payload: plaintext,
        key: key,
        nonce: uniqueNonce,
        authenticatedData: associatedData
    )
}
```

The helper does not generate or reserve `uniqueNonce`; its caller must prove uniqueness for that key across every invocation and process. The returned bytes omit the nonce. Preserve it in the exact protocol framing expected by the receiving side. Matching key, nonce and associated bytes are required to open; authentication failure returns no plaintext.

Use ``VoiceTransportCipher`` for the declared RTP-size transport format so counter and replay behavior remain in one owner. Primitive calls alone have no replay detection, SSRC authorization or session lifetime.

### Do not generalize a short-tag profile

``TruncatedAESGCM`` supplies the bounded shortened-tag operation needed by the owned DAVE profile. Short tags require strict total verification and failed-attempt budgets in the higher-level frame cipher. Do not reuse the primitive with an ad hoc packet format, unbounded guesses or a weakened application authentication policy.

Treat the frame-size bound and per-generation attempt counts as security invariants, including successful and failed opens. Multiple receive owners for one domain must coordinate their aggregate attempts; multiplying actors does not multiply a cryptographic safety budget.

### Keep diagnostics and tests deliberate

Never log keys, nonces paired with secret material, plaintext or native error objects that can expose data. Redacted diagnostics reduce accidental disclosure; explicit byte access and memory dumps remain sensitive.

Tests should verify known-answer vectors, empty plaintext, exact key/nonce sizes, maximum payload boundaries, changed associated data and truncated/modified tags. Tests using fixed public keys are fixtures only. Independent review, key provisioning, human identity verification and end-to-end session authorization remain outside the primitive layer.
