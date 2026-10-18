# Frame protection, ratchets and human verification

Transform complete encoded frames with one sender nonce domain and explicit verification limits.

## Overview

### Protect frames at the codec boundary

The send order is encode, DAVE complete-frame transform, RTP packetization and outer transport AEAD. On receive, authenticate transport and reassemble/depacketize before DAVE opening, then pass authenticated encoded bytes to the codec. Never encrypt each arbitrary RTP fragment as if it were a complete DAVE frame.

``DAVECodecTransform`` preserves codec-required clear portions and normalizes the supported encoded formats. Opus/VP9 are fully encrypted; VP8 preserves its required prefix. H264/H265 use Annex B normalization, and AV1 filtering/size rewriting can change the recovered normalized bytes. It is a framing transform, not an Opus/video encoder or a general-purpose arbitrary-byte encryption API. Use the explicit codec and respect its malformed-input errors.

```swift
import DiscordDAVE
import Foundation

/// Protects a complete Opus packet using an active, authenticated session epoch.
func protectCompleteOpus(
    _ opus: Data,
    session: DAVEProtocolSession
) async throws -> Data {
    try await session.seal(opus, codec: .opus)
}
```

At receive, provide the sender ID from authenticated membership/SSRC association and the media type expected by that route. A packet's own bytes cannot authorize the sender. Missing epoch, wrong sender, expired generation, replay or tag failure produces no plaintext. The low-level open APIs expose one opt-in audio exception for the exact `F8 FF FE` Opus silence packet; it defaults to disabled and does not admit arbitrary plaintext. The supervised adapter uses the protected-frame path.

### Keep one sender domain across audio and video

``DAVEFrameCipher`` owns a sender's MLS exporter domain. Every audio/video source and SSRC for that sender shares the actor's absolute transmit nonce. Do not create another sending actor from the same base secret, copy a low-level ``DAVEKeyRatchet`` into an independent sender, or reset counters after packet loss or RTP rollover.

The base secret is exactly sixteen bytes exported with the DAVE label, sender little-endian user-ID context and output length. Prefer ``DAVEProtocolSession`` to derive it from the authenticated accepted epoch. Raw cipher construction is suitable for controlled peers/tests only when that domain ownership is explicit.

``DAVEFrameCipher/Configuration`` independently bounds transformed frame bytes, forward ratchet work, retained generations, replay distance, total verifications, failed verifications, generation expiry and transmit lifetime. Shortened authentication tags make attempt budgets security requirements. Duplicated receive owners must coordinate aggregate budgets; more actors do not create a larger safe key-domain allowance.

Old-generation retention is finite and never above ten seconds under this implementation. Supply one monotonic time source to receive operations. Authentication failure does not accept replay state, while failed attempts still count against their verification budget. Exhaustion requires recovery rather than unlimited guesses.

### Verify humans without inventing trust

``DAVEVerification`` derives pairwise fingerprints/display codes and epoch codes. ``DAVEVerificationStore`` retains bounded account-scoped ephemeral verification across explicitly identified sessions. A matching displayed code must be confirmed through an authenticated human comparison channel; computing it locally does not authenticate the remote person.

Read a fingerprint for the exact session/user, compare out of band, then confirm the same bytes. Key changes invalidate the relevant confirmation. Replacing/removing sessions updates the store's bounded live domain. `clear()` releases all retained verification; this product does not persist a trust database or decide recording consent.

Do not log fingerprints alongside private keys, raw media or secret exporters. Ordinary cipher diagnostics redact secrets, but Swift Data and Crypto do not promise physical erasure.

### Validate tamper, replay and scope

Test codec-specific clear/encrypted ranges, complete-frame reassembly, changed tags/footers, malformed ranges, generation wrap/expiry, counter exhaustion, failed-attempt caps, replay windows and independent audio/video nonce use. Test verification with key replacement, session removal and mismatched confirmation bytes. Local round trips and published vectors remain separate from independent audit, actual device behavior and authorized service interoperability.
