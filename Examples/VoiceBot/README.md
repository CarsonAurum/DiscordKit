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

Before that transport example, it establishes a two-member synthetic MLS group via
a trusted external Add, tentative Commit and encrypted Welcome. Both owners must
agree on explicit exporter bytes before cleanup; keys are never printed. The external
signing scalar is a public test fixture. See [MLS](../../Docs/MLS.md) for audit limits.

It also drains synthetic PCM through the bounded
AsyncSequence/windowed-sinc resampler and checks exactly 1,920 output frames with a
sample clock, then checks silence rejection by statistical VAD. It separately
round-trips synthetic entropy and CELT pulse-codebook symbols. Those symbols do not
form a complete SILK/CELT frame and are never sent as Opus. A separate component
demonstration checks the CELT transform's 120-sample overlap delay, entropy-codes
one normalized band shape, and inverts SILK short-term predictor analysis/synthesis.
Those individual primitive checks remain separate from compressed-audio integration.
The executable then encodes three actual mono CELT packets and reconstructs 2,880
48-kHz PCM samples. A committed synthetic libopus 1.6.1 SILK packet decodes to 480
48-kHz PCM16 samples whose complete fingerprint and final range match the independent
reference. It also emits and decodes stereo SILK and hybrid packets, exercises CELT
loss concealment and subsequent recovery, and drives the unified decoder across
all three modes plus explicit conceal/FEC fallback and following-packet decoding.
Every demonstration checks exact duration and finite output.
Normal builds use only the owned Swift codec, never native libopus.

The selected product graph excludes HTTP, Gateway, Client, Cache, OAuth,
Interactions, Commands, NIO and concrete network/device adapters. It includes
Core/Models/Transport plus Media/VoiceCodecs/VoiceCrypto/MLS and the existing Swift
Crypto/CryptoExtras graph. See [Voice](../../Docs/Voice.md) for ownership and limits.

This Phase 12 consumer has no DAVE media backend, supervised network session,
microphone/playback adapter or perceptual/realtime qualification. Discord
requires DAVE for eligible live sessions; this offline example cannot join one.
It is not the roadmap's ten-minute duplex or authorized Discord smoke qualification.
