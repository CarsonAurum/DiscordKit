# Adopt bounded voice and media

Separate offline protocol demonstrations from supervised network/device ownership.

```sh
swift build --package-path Examples/VoiceBot
swift run --package-path Examples/VoiceBot VoiceBot
```

The [VoiceBot consumer](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/VoiceBot)
uses synthetic PCM and public fixture keys to exercise codec, RTP, transport AEAD,
MLS and DAVE components. It never joins Discord, opens a device or sends media.
It excludes HTTP/Gateway/Client/Cache/OAuth and concrete adapters.

For an actual session, adopt VoiceSession/VoiceManager with injected transports,
monotonic clocks, SSRC authority and devices; run/join owns work, stop/leave awaits
closure. DAVEVoiceSession implements Voice interfaces while preserving the
DAVE-to-Voice dependency direction. Supply trusted participant/external-sender
associations and share signing identity across related sessions. Downgrade fails
closed, complete encoded frames are transformed around RTP packetization, and
counter/replay/queue budgets remain finite.

Voice v8, MLS 1.0 ciphersuite 2 and DAVE v1 are separate protocol versions.
Local vectors, offline round trips and the local synthetic duplex harness do not
establish independent cryptographic review, full-client interoperability, device
routing, authorized Discord media or other-platform qualification. See the
[voice-session contract](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/VoiceSessions.md).
