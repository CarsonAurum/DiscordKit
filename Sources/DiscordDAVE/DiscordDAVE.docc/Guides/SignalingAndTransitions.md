# Coordinating authenticated DAVE transitions

Keep Voice control identity, MLS candidate selection and media readiness in one owner.

## Overview

### Bind to an exact authenticated session

``DAVEProtocolSession`` requires the full Voice connection identity, authenticated call/group ID, trusted external sender and shared P-256 signing identity. Membership controls come from the authenticated Voice socket. Untrusted media, a key package or an arbitrary endpoint cannot introduce participants.

Related sessions share the signing identity when continuity is required. Recovery replaces HPKE/init material rather than silently creating a different signing identity. Group IDs are exact authenticated bytes, ordinarily an eight-byte big-endian snowflake, not a display name.

The constructor starts no transport or timers. `start(protocolVersion:)` accepts version one and emits ordered key-package commands. Version zero or unsupported negotiation does not enable a plaintext fallback.

### Follow selection and execution, not local optimism

The owner decodes authenticated DAVE controls, updates expected membership and exchanges bounded MLS proposals/candidates/Welcome. Several members may prepare a commit. A local candidate does not automatically win, and preparing receive keys does not immediately authorize sending.

The authenticated delivery choice and Ready/Execute transition control decide which epoch becomes active. ``DAVEProtocolSession`` retains that ordering and can prepare a selected remote candidate before execution. Membership changes revoke media until the current epoch actually authorizes it. Invalid messages and downgrade fail closed rather than keeping stale optimistic readiness.

```swift
import DiscordDAVE
import DiscordVoice
import Foundation

/// Processes one exact-session authenticated control and returns once-only outbound controls.
func processDAVEControl(
    _ frame: VoiceGatewayFrame,
    session: DAVEProtocolSession,
    monotonicSeconds: TimeInterval
) async throws -> [VoiceGatewayFrame] {
    try await session.receive(frame, now: monotonicSeconds)
}
```

The application sends returned commands once, in order, on the same authenticated Voice socket. The helper does not validate a socket source or retry writes. Time must be finite, nonnegative and nondecreasing in the one monotonic domain shared with frame expiry; wall-clock changes are not a suitable source.

### Prefer the supervised Voice adapter

``DAVEVoiceSession`` implements the injected Voice E2EE contract while preserving the dependency direction from DAVE to Voice. Supply the same monotonic-seconds closure to the adapter and Voice supervisor. The adapter registers SSRC bindings only from authenticated Ready/Speaking controls. RTP cannot create membership or reassign another participant's source.

The protocol owner rejects overlapping operations. The adapter adds bounded serialization, prioritizes queued controls over media and reserves one queue position for control admission. Do not bypass its overlap gate or create a parallel protocol writer to work around overload. Stop/close must revoke admission and await cleanup.

A fresh Voice identity gets a fresh DAVE backend. Resuming the same authorized connection preserves appropriate crypto owners rather than resetting counters. The supervisor rechecks actual DAVE readiness after resumable socket replacement before enabling media.

### Exercise recovery and failure

Use scripted authenticated controls with an owned MLS peer to test external sender mismatch, unauthorized members, candidate loss, remote candidate selection, selected Welcome, Ready-before-Execute, unsupported version, early controls, replay and removal. Bound both count and bytes for retained control frames, attempts and pending operations.

The [offline DAVE example](https://github.com/CarsonAurum/DiscordKit/blob/main/Examples/VoiceBot/Sources/VoiceBot/DAVEExample.swift) models a trusted synthetic delivery service and has no network/device I/O. It does not establish independent cryptographic review, complete external-client interoperability or live Discord acceptance.
