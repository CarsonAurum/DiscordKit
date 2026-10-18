# Maintaining scoped observations and PCM controls

Use finite local state without turning display observations into remote authority.

## Overview

### Replace snapshots and apply ordered events

``SocialRelationshipStore`` retains bounded users, relationships and UTF-8 string bytes under one active ``SocialScope``. Activate first, apply a complete ``SocialStateSnapshot``, then deliver ``SocialStateEvent`` values with the same scope, provider generation and monotonically ordered sequence.

A snapshot replacement is atomic. Duplicate or older events are ignored. A gap, unexpected generation or capacity exhaustion invalidates freshness and requires another complete snapshot. Do not patch over a gap by assuming missing friendships or keeping an unbounded history. Local unknown relationship kinds remain unknown; they do not become friends.

``SocialStateView`` supports ID lookup, relationship grouping and Unicode-lowercased username filtering. Presence groups are display conveniences based on trusted optional observations. Missing/unknown presence stays separate. Online-elsewhere ordering can prefer prior players of this application, but that ordering does not issue friend/block mutations or authorize entitlements.

Clear standalone stores explicitly on consent revocation. The private store inside ``SocialClient`` clears during disconnect. Scope and generation fencing prevents a late reply from a previous account from repopulating current observations.

### Compose local mute, deafen and gain

``SocialAudioControls`` changes application-owned PCM on explicit route keys. It owns no device, queue, codec engine, network call or remote lobby. Global and per-call settings compose: deafen suppresses playback and capture; mute suppresses capture while preserving playback. Linear input/output gains combine and clip once.

```swift
import DiscordMedia
import DiscordSocial

/// Applies an explicit local capture mute to one application-owned route.
func mutedCapture(_ input: PCMBuffer) async throws -> PCMBuffer {
    let controls = try SocialAudioControls(maximumCalls: 4)
    do {
        try await controls.setCall(1, settings: SocialAudioSettings(muted: true))
        let result = try await controls.capture(input, callID: 1)
        await controls.close()
        return result
    } catch {
        await controls.close()
        throw error
    }
}
```

A missing route fails closed. Removing a route frees its slot; closing clears all retained routes. Device selection belongs to a separately qualified native adapter or documented desktop RPC settings. These controls do not implement SDK lobby networking, echo cancellation, noise suppression, AGC or proprietary processing.

### Monitor input level explicitly

``SocialAudioInputMonitor`` measures all-channel RMS in each supplied block. A threshold in `-100...100` dBFS is finite; `-100` disables detection. The owner emits changes after establishing an initial baseline, ignores empty blocks and retains a single replaceable callback. The application explicitly supplies microphone PCM; there is no device-health probe or automatic capture.

Native Discord analysis windows and hysteresis are unpublished, so this block-level local equivalent does not claim identical timing. Keep callback work short and bound any queue receiving notifications. `close()` releases the callback.

Test snapshot gaps, scope replacement, UTF-8 byte exhaustion, unknown relationships, local grouping, mute/deafen combinations, clipping, missing routes and threshold edges. Synthetic PCM and scripted providers do not qualify physical devices, authorized native sessions or sustained remote call behavior. ``SocialActivityInvite`` and ``SocialAdditionalContent`` hold bounded immutable display metadata; they neither redeem invitations nor grant purchases.
