[//]: # "File: Sources/DiscordVoiceCodecs/DiscordVoiceCodecs.docc/DiscordVoiceCodecs.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# ``DiscordVoiceCodecs``

Parse and encode ordinary Opus packets with owned SILK, CELT and hybrid codec state.

## Overview

The high-level ``OpusAudioEncoder`` and ``OpusAudioDecoder`` provide synchronous, frame-bounded coding at a 48-kHz sample clock. ``OpusPacket`` validates framing independently of entropy decoding. Lower-level range coding, SILK prediction, CELT transform/quantization and hybrid components are exposed for controlled composition and reference testing; they are not interchangeable with a complete network voice session.

Begin with the guides for ownership and composition, then use the complete type index to explore each declaration and its members. Examples name the additional products they import so you can keep your package dependency graph explicit.

## Topics

### Guides

- <doc:PacketAndCodecOwnership>
- <doc:RecoveryAndBitrate>

### Core APIs

- ``OpusPacket``
- ``OpusAudioEncoder``
- ``OpusAudioDecoder``
- ``OpusAudioEncodedPacket``
- ``OpusAudioDecodedFrame``
- ``OpusDTXPolicy``
- ``CELTPacketEncoder``
- ``SILKMonoEncoder``
- ``OpusHybridEncoder``

### Complete API reference

- <doc:APIReference>
