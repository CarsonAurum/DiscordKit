# Offline VoiceBot protocol example

Build without credentials, network calls or audio-device access:

```sh
swift build --package-path Examples/VoiceBot
swift run --package-path Examples/VoiceBot VoiceBot
```

The executable packetizes five synthetic Opus silence frames, authenticates them
with XChaCha20-Poly1305 RTP-size encryption, opens/parses the RTP packets and drains
a bounded playout queue across sequence/timestamp rollover. Its key is a public
fixed **test fixture**, never a real session key. The receiver owns no sends.
There are no Discord requests, joins, permissions or background production tasks.
Root Swift Testing suites exercise the same components and failure paths.

Before that transport example, it drains synthetic PCM through the bounded
AsyncSequence/resampler and checks exactly 1,920 output frames with a sample clock.
It separately round-trips synthetic entropy symbols. Those symbols contain no
SILK/CELT audio syntax and are never sent as Opus.

The selected product graph excludes HTTP, Gateway, Client, Cache, OAuth,
Interactions, Commands, NIO and concrete network/device adapters. It includes
Core/Models/Transport plus Media/VoiceCodecs/VoiceCrypto and the existing Swift
Crypto/CryptoExtras graph. See [Voice](../../Docs/Voice.md) for ownership and limits.

This Phase 12 consumer has no MLS/DAVE backend, supervised network session,
Opus encoder/decoder or microphone/playback adapter. Discord requires DAVE for
eligible live sessions; this synthetic transport-only example cannot join one.
It is not the roadmap's ten-minute duplex or authorized Discord smoke qualification.
