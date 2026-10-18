# ``DiscordVoice``

Supervise Voice v8 sessions and bounded authenticated Opus media over injected transports.

## Overview

Use ``VoiceManager`` for account-scoped guild join/move/leave ownership, or ``VoiceSession`` when directly owning one supervised connection. Both initialize without I/O. Inject main-Gateway command/event routing, WebSocket and UDP transports, clocks and a real ``VoiceSessionE2EE`` implementation. The product deliberately does not import a DAVE implementation or create a device.

Begin with the guides for ownership and composition, then use the complete type index to explore each declaration and its members. Examples name the additional products they import so you can keep your package dependency graph explicit.

## Topics

### Guides

- <doc:SessionsAndRendezvous>
- <doc:MediaAndPlayout>

### Core APIs

- ``VoiceManager``
- ``VoiceSession``
- ``VoiceSessionConfiguration``
- ``VoiceSessionE2EE``
- ``VoiceJoinRendezvous``
- ``VoiceConnectionIdentity``
- ``VoiceMediaPipeline``
- ``VoiceJitterBuffer``
- ``OpusRTPPacketizer``
- ``RTPPacket``

### Complete API reference

- <doc:APIReference>
