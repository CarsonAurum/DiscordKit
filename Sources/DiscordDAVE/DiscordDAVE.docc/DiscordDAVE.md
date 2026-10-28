[//]: # "File: Sources/DiscordDAVE/DiscordDAVE.docc/DiscordDAVE.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# ``DiscordDAVE``

Coordinate authenticated DAVE v1 transitions and protect complete encoded media frames.

## Overview

``DAVEProtocolSession`` binds authenticated Voice controls to MLS epochs, sender ratchets and codec-aware transforms. ``DAVEVoiceSession`` adapts that owner to DiscordVoice's injected E2EE contract. Construction starts no sockets, devices, clocks, persistence or tasks. Trusted external sender, membership, exact session identity, shared signing identity and monotonic time are application inputs. Downgrade and missing readiness fail closed.

Begin with the guides for ownership and composition, then use the complete type index to explore each declaration and its members. Examples name the additional products they import so you can keep your package dependency graph explicit.

## Topics

### Guides

- <doc:SignalingAndTransitions>
- <doc:FramesAndVerification>

### Core APIs

- ``DAVEProtocolSession``
- ``DAVEVoiceSession``
- ``DAVEFrameCipher``
- ``DAVEKeyRatchet``
- ``DAVECodecTransform``
- ``DAVESignaling``
- ``DAVEVerificationStore``
- ``DAVEVerification``

### Complete API reference

- <doc:APIReference>
