# Local Voice session qualification

This independent executable uses actual localhost UDP sockets and continuous-clock
20ms pacing for two audio directions. Synthetic 48kHz mono PCM passes through the
owned Opus encoder, a real two-member MLS/DAVE epoch, RTP, transport AEAD, the
opposite UDP socket, both authentication layers, bounded jitter, and PCM decoding.
Both synthetic senders share the single same-key transport nonce authority.

```sh
swift run --package-path Tools/VoiceSessionQualification -c release \
  VoiceSessionQualification --seconds 600 --output /tmp/voice-session-600s.json
```

Use `--seconds 2` for a smoke check. The default is 600 measured seconds; accepted
durations are 0.02 through 3,600 seconds. A separate 100-frame/two-second warmup
precedes measurement while preserving the same codec, RTP, DAVE and AEAD owners.
A report includes measured and lifetime packet/sample counts, processing
percentiles for each full two-direction tick (concurrent sends, both receives,
authentication and PCM decoding) excluding the explicit main pacing wait, missed 20ms processing and
schedule deadlines, pre-warmup cold and post-warmup initial/final/sampled-high
resident bytes, a once-per-second RSS trace, first/last-minute median RSS, signed
growth after warmup, and post-closure RSS. It also records the explicitly accounted
timing-sample storage, configured media/UDP buffer bounds, peak/final retained
jitter bytes, sampled DAVE queue counts, and awaited resource closure. The report
applies no invented RSS plateau or realtime pass threshold; the raw observations
and deadline misses remain visible.
Observed software scheduling delays are reported; their cause is not inferred.
They provide no real-time audio guarantee. Any socket/cryptographic/codec failure
exits nonzero after cleanup.

The private signing scalars and credentials are public fixtures. The tool performs
no DNS, authenticated Discord requests, WebSocket connection, device access, audio
playback, microphone capture, or persistence beyond the explicitly requested JSON.
The two-member signaling is synthetic even though MLS/DAVE cryptography and UDP
I/O are real. A successful run supplies local software-duplex evidence; it does
not establish hardware/acoustic, live Discord, independent-client interoperability,
cross-platform qualification, or independent cryptographic review.
