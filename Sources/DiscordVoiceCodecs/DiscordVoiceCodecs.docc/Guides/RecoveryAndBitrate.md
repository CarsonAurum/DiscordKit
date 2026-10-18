# Bitrate, DTX and packet-loss recovery

Keep codec allocation separate from network overhead and make missing intervals explicit.

## Overview

### Budget codec bytes

``OpusAudioEncoder`` targets total codec bits per second including the TOC, excluding RTP, DAVE and transport AEAD overhead. Fractional byte carry makes successive ordinary allocations differ by at most one byte. The target must fit both the format minimum and `maximumPacketByteCount`; a hard cap never silently grows to make a difficult frame fit.

SILK can increase quantization gain and use bounded alternate admission, but may still reject a signal it cannot fit. A requested FEC policy is not silently removed. Update only the supported bitrate control on an existing owner; create a fresh owner for fixed mode/layout changes.

### Treat DTX as a transmission decision

``OpusDTXPolicy`` uses all-channel RMS, a threshold and hangover rather than a trained speech/music classifier. Quiet wanted content can be suppressed if the threshold is too high. The encoder continues analysis during silence; bandwidth savings do not promise reduced CPU.

```swift
import DiscordVoiceCodecs

var encoder = try OpusAudioEncoder(
    channelCount: 1,
    dtx: OpusDTXPolicy(thresholdDBFS: -80, hangoverMilliseconds: 200)
)
let result = try encoder.encode(Array(repeating: Float(0), count: 960))
if result.shouldTransmit {
    // Deliver result.data once through the caller's bounded, authenticated sender.
}
```

A suppressed interval still advances codec and media clocks. Do not keep RTP timestamps fixed when omitting transmission. An ordinary refresh occurs at most every 400 milliseconds under this policy. `isDTX` describes a suppressed zero-payload interval, not a complete discontinuity in the timeline.

### Conceal a missing interval at playout time

Do not decode arrival order from UDP directly. A protocol jitter buffer first identifies the next ordered packet or missing sample interval. ``OpusAudioDecoder`` then either decodes the ordinary packet, synthesizes explicit PLC/CNG, or attempts in-band FEC using a following packet.

```swift
import DiscordVoiceCodecs
import Foundation

/// Recovers a missing 20ms interval and then decodes the following packet exactly once.
func recoverThenDecode(
    following: Data,
    decoder: inout OpusAudioDecoder
) throws -> [OpusAudioDecodedFrame] {
    let missing = try decoder.recover(following, frameSampleCount: 960)
    let current = try decoder.decode(following)
    return [missing] + current
}
```

Recovery inspects the following packet without consuming its ordinary audio. Decode that same packet afterward. SILK LBRR supplies in-band FEC when available; CELT, unavailable redundancy or unsuitable duration falls back to concealment. CELT encoding rejects `enableInBandFEC: true` because it has no ordinary SILK LBRR mechanism.

`conceal(frameSampleCount:)` requires a positive multiple of 120 through 5,760 samples/channel. Before coded history it returns zeros; later it uses bounded preceding history. Neither PLC nor FEC reconstructs a cryptographically missing packet or guarantees perceptual identity to the original.

### Validate the right claim

Test malformed framing/entropy, mode transitions, mono/stereo conversion, loss bursts, FEC/no-FEC, bitrate fractional carry, cap failures and state preservation after errors. Compare published vectors and independent reference outputs where available. Local synthetic round trips do not independently establish perceptual quality, complete-client interoperability, native device performance or realtime scheduling on every supported host.
