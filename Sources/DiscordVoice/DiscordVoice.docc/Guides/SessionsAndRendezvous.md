# Joining and supervising voice sessions

Bind main-Gateway rendezvous, exact connection identity and cleanup to explicit owners.

## Overview

### Supply the account's main-Gateway authority

``VoiceManager`` owns finite per-guild session slots. Inject the authenticated account ID, shared monotonic clock, one main-Gateway command sender and an inert session factory. The sender maps ``VoiceManagerCommand`` to the correct owned shard's voice-state update and shared rate admission. Guild permissions and the voice-state intent remain application responsibilities.

```swift
import DiscordCore
import DiscordVoice

/// Creates an inert account-scoped voice owner with application-supplied control and session factories.
func makeVoiceManager(
    userID: UserID,
    sendCommand: @escaping VoiceManager<ContinuousClock>.SendCommand,
    makeSession: @escaping VoiceManager<ContinuousClock>.MakeSession
) throws -> VoiceManager<ContinuousClock> {
    try VoiceManager(
        userID: userID,
        clock: ContinuousClock(),
        maximumGuilds: 32,
        sendCommand: sendCommand,
        makeSession: makeSession
    )
}
```

The factory must return a fresh inert session for every credential replacement. It must cooperate with cancellation, avoid logging credentials and never reuse a transport key/counter or stale E2EE backend for a new ``VoiceConnectionIdentity``.

### Route both event halves with a generation fence

Call `join` or `move` in an owned task while forwarding typed main-Gateway voice state/server updates. Either event order works. Capture `generation(guildID:)` before routing and retain that fence across delivery. Normally serialize this event routing.

Discord supplies no request nonce for this rendezvous. An arbitrarily delayed upstream event cannot be proven to answer a particular local request just by its arrival time. The local generation prevents stale application delivery from silently crossing ownership, but does not invent a remote correlation guarantee.

Changed session IDs, tokens, endpoints, null endpoints, self leave or unsolicited moves suspend/dispose old ownership. Fresh matching halves are required. Even an unchanged endpoint can belong to a new exact identity. Pending joins, closing slots and automatic replacement operations count toward finite aggregate limits; overload fails rather than retaining unbounded guild history.

The returned managed session is running under the manager's task, not necessarily network/E2EE ready. Do not call `run()` on it yourself. `leave` closes local ownership and sends an explicit leave. `stop` cancels and joins all owned work and prevents new joins.

### Construct one supervised connection

``VoiceSession`` takes fresh ``VoiceConnectionCredentials``, a TLS WebSocket adapter, an owned UDP factory, real E2EE readiness, finite configuration and a monotonic clock. Initialization opens no socket or device. A direct caller owns and awaits `run()`; terminal return means acquired network/media/E2EE resources have closed. `stop()` is idempotent and unblocks owned work.

The supervisor validates the endpoint, explicitly uses Voice v8, applies HELLO heartbeat timing, discovers UDP only from the negotiated peer and installs the accepted RTP-size transport key. Handshake, control writes and reconnect policy have finite bounds. Heartbeat/control tasks do not wait for application PCM handling.

Resumable socket replacement preserves the exact transport nonce authority and reauthorizes E2EE before media resumes. Authentication/session-invalidating/terminal closures require fresh main-Gateway credentials. A retry budget does not become an unbounded reconnect storm, and ambiguous main-Gateway mutations are not replayed.

``VoiceSession/play(_:)`` pauses PCM source consumption while a resumable socket loss or authenticated key transition revokes media. The wait uses the finite session handshake budget and remains cancellation-aware. If revocation invalidates a frame already waiting for its send slot, playback discards that consumed frame and resumes with the next source frame after actual authorization. The retained pipeline resets pacing while preserving nonce and RTP authorities; no frame is replayed. Source, format, cryptographic and transport failures, and any partial termination-silence failure, still close the session.

DiscordDAVE's adapter implements ``VoiceSessionE2EE`` from a separate product. Share its monotonic-seconds closure with the supervisor and supply the trusted external sender, authenticated group ID and shared signing identity. See the [secure session composition guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/VoiceSessions.md) for the complete boundary.

### Verify supervision without credentials

Use injected transports and clocks to test both event orders, null endpoint, replacement, stale generation, deadlines, ACK debt, resume, canceled factory, early E2EE controls and repeated cleanup. Local synthetic UDP peers do not qualify a real Discord join, physical route changes, independent crypto review or every platform/device.
