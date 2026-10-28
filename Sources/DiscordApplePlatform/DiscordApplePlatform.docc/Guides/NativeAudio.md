[//]: # "File: Sources/DiscordApplePlatform/DiscordApplePlatform.docc/Guides/NativeAudio.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Capturing and playing native audio

Start audio explicitly, preserve sample units and respond to permission and route changes.

## Overview

### Choose session and route authority

``AppleAudioDevice`` is a MainActor owner backed by an inert ``AppleAudioBackend``. Its initializer validates policy and queues without opening devices. Use `.hostManaged` when the app already owns the shared audio session. Choose `.exclusiveForeground` only when this owner has exclusive authority to configure and deactivate that session.

```swift
import DiscordApplePlatform
import DiscordMedia

/// Creates a playback-only owner; the caller explicitly starts and later stops it.
@MainActor
func makePlaybackDevice() throws -> AppleAudioDevice {
    let format = try PCMFormat(sampleRate: 48_000, channelCount: 2)
    let configuration = try AppleAudioConfiguration(
        captureEnabled: false,
        playbackFormat: format,
        maximumPlaybackBlocks: 8,
        maximumPlaybackBytes: 1_048_576,
        sessionPolicy: .hostManaged
    )
    return AppleAudioDevice(configuration: configuration)
}
```

Playback-only use requires no microphone grant. For capture, supply the app's microphone usage description and applicable sandbox entitlements, inspect `recordingPermission()`, and request permission explicitly before `start()`. The OS authorization prompt cannot itself be canceled; the async owner checks task cancellation around its result.

`availableDevices()` queries bounded metadata without opening audio. macOS supports exact input/output CoreAudio UIDs. On supported audio-session platforms, input availability depends on the configured session; output entries describe the current route and cannot be selected by UID. watchOS does not expose preferred-input selection. Explicit unavailable UIDs fail instead of silently choosing a different device.

### Convert hardware PCM deliberately

`start()` returns the actual capture format, or nil for playback-only use. Capture preserves the hardware sample rate and selects the configured first one or two channels. A `captureBufferFrames` request is a preference; native callbacks may deliver another size. The owner splits delivery into bounded blocks of at most 120 milliseconds.

A sample frame contains one value per channel. For stereo, 960 frames means 1,920 interleaved Float samples. Resample explicitly before passing hardware PCM to a 48-kHz codec, and write playback only in the exact configured format. There is no silent format conversion in the portable boundary.

Capture callbacks admit whole blocks synchronously without spawning Swift tasks. At the configured count/byte limit they drop new capture and update `droppedCaptureBlocks`. Playback writes fail when the native scheduling budget is full. Choose upstream queues and overflow behavior separately; bounded device queues do not bound an application's recording backlog.

### Stop, clear and restart explicitly

Call `stop()` before releasing the owner. Route changes, interruption, media reset or incompatible configuration stop capture/playback and discard queued media. Restart is explicit after rechecking permission and routing. Callback generations prevent late native completions from restoring an old session. Asynchronous OS notifications cannot prove there was no transient hardware rerouting.

Inject a fake backend to test permission states, queue pressure, exact UID failure, late completion, interruption and repeated stop without opening hardware. Real microphone/speaker, hot unplug, minimum-OS and per-device duplex behavior need physical-host testing. Native echo cancellation, noise suppression, automatic gain control and sustained realtime quality are separate policies; the portable PCM owner does not imply them.
