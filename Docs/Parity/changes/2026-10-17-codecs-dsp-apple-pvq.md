<!--
File: Docs/Parity/changes/2026-10-17-codecs-dsp-apple-pvq.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# DSP, native Apple audio and CELT pulse prerequisites

Verified **2026-10-17**. Full codec and device qualification requires the evidence
listed in the [voice guide](../../Voice.md). Upstream introduction/announcement/effective dates for these grouped
local APIs are unknown. Voice Gateway v8 and the 48kHz RTP clock are unchanged.

## Portable DSP and codec building blocks

Previously Media exposed continuous linear interpolation and an RMS energy gate.
`PCMBandlimitedResampler` adds finite Blackman-windowed sinc conversion with exact
chunk-independent rational phase/counts, explicit bounded lookahead and endpoint
flush. Selected-rate alias/image tests and an independent convolution reference
establish synthetic component behavior. Equal-rate conversion is an exact bypass;
clip headroom, filter transition band and synchronous processing cost are explicit.
The [windowed-sinc construction](https://ccrma.stanford.edu/~jos/pasp/Windowed_Sinc_Interpolation.html)
is approximate and does not establish universal perceptual or realtime quality.

`PCMSpeechActivityDetector` adds approximately 20ms per-channel statistical analysis:
adaptive background-relative energy, pitch correlation, spectrum/bands/flatness,
temporal changes and bounded hangover. It preserves framing across chunks and
avoids antiphase stereo cancellation. Synthetic fixtures cover tone/DC/noise
rejection and modulated harmonic speech-like activity. Corpus accuracy is unrun;
whispers/steady vowels may be missed, and music/machinery may be accepted. It
provides no denoiser, AEC or claim of a standard algorithm's conformance.

`CELTPulseCodebook` adds exact signed pulse enumeration and Opus uniform range
composition from [RFC 6716 section 4.3.4.2](https://www.rfc-editor.org/rfc/rfc6716#section-4.3.4.2).
Dimension/pulse/table/codeword bounds are explicit; oversized bands are rejected
rather than wrapped or rescaled. The mathematical U recurrence is computed by
owned Swift; consumer builds do not use libopus tables or a native codec runtime.
Forty fixtures compare independently compiled official libopus 1.6.1 codewords.

The opt-in [PVQ verifier](../../../Tools/DiscordKitTools/scripts/verify_celt_pulse_oracle.py)
compiles separately supplied, SHA256-pinned official source in temporary storage
with upstream COPYING preserved. It verifies 40 fixed, 220 boundary and 2,000
seeded cases against exact counts, vectors, ranks, entropy bytes and decoded
integer vectors. Its [report](../codecs-pvq-validation.json) records source,
fixture, compiler and owned Swift fingerprints. Normal unit tests never fetch
or compile native codec sources. Reproduce explicitly:

```sh
python3 Tools/DiscordKitTools/scripts/verify_celt_pulse_oracle.py \
  --repository . --source-archive /path/to/opus-1.6.1.tar.gz \
  --report /path/to/pvq-validation.json
```

These integer-codebook and entropy checks supply no decoded PCM, full SILK/CELT/
hybrid codec, recursive band splitting/allocation, MDCT, PLC/FEC or
[RFC 8251 full conformance](https://www.rfc-editor.org/rfc/rfc8251#section-11).

## Native Apple ownership

Previously ApplePlatform contained lifecycle contracts only. It now separately
selects Media and system AVFoundation/CoreAudio, without a new package dependency
or any portable target selecting a platform adapter. `AppleAudioDevice` owns
explicit engine start/stop, microphone status/request, host-managed or explicitly
exclusive foreground session policy and default-route capture/playback.

The MainActor backend is injectable. Native callbacks retain no AVAudioPCMBuffer,
start no Swift task and admit only bounded block/byte budgets. Capture overflow
drops new blocks. Playback reserves before scheduling and generation-fenced
completions cannot release another session's capacity. Explicit stop, observed
interruption/route/configuration changes and failures revoke admission and clear
media. Native teardown is deferred/coalesced off the notification stack; late
callbacks and repeated events are fenced. Apps supply microphone usage descriptions
and entitlements. Construction and normal tests never prompt or open devices.

Actual hardware permission, recording, audible playback, routing, hot-unplug,
interruption and minimum-OS runtime tests remain unrun. OS event delivery cannot
promise a privacy barrier against every route race. Arbitrary device selection,
Windows/Android adapters and their host qualification remain unimplemented.
Linux continues to accept injected PCM. The reviewed media/device records stay
partial. Existing consumers keep their APIs; the independent offline VoiceBot
now exercises bandlimited/VAD/pulse primitives and retains its portable graph.

## Remaining qualification

Required work still includes SILK/CELT/hybrid analysis/synthesis and full codecs,
PLC/FEC, official decoded-PCM vectors and final-range conformance, complete device
routing/adapters and platform/hardware evidence. Synthetic DSP/packet tests and
cross-SDK compilation cannot satisfy those requirements. These component results do not establish production voice, complete codec
conformance or broad platform support.
