# ``DiscordVoiceCrypto``

Protect voice transport packets with explicit nonce ownership and bounded replay state.

## Overview

``VoiceTransportCipher`` owns a transport key's nonwrapping transmit counter and bounded per-SSRC replay windows. It supports the declared RTP-size AES-256-GCM and XChaCha20-Poly1305 modes. This product authenticates the outer transport layer; DAVE supplies a separate end-to-end complete-frame layer. Primitive APIs require caller-owned nonce discipline and do not negotiate protocols.

Begin with the guides for ownership and composition, then use the complete type index to explore each declaration and its members. Examples name the additional products they import so you can keep your package dependency graph explicit.

## Topics

### Guides

- <doc:TransportProtection>
- <doc:PrimitiveUse>

### Core APIs

- ``VoiceTransportCipher``
- ``VoiceEncryptionMode``
- ``VoiceCryptoError``
- ``XChaCha20Poly1305``
- ``TruncatedAESGCM``

### Complete API reference

- <doc:APIReference>
