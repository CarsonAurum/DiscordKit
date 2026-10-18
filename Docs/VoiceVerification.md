# Owned Opus verification

Normal package builds and Swift Testing use committed synthetic fixtures and owned
Swift only. They perform no source/vector downloads, native codec linkage, device
access or Discord calls. The separate Python unit tests exercise verifier admission,
fingerprints, malformed inputs, comparisons and report generation hermetically.

The opt-in scripts below accept a separately supplied official libopus 1.6.1
archive. They validate its pinned SHA256 before extracting regular bounded paths,
build temporary scalar reference code, compile owned Swift snapshots and compare
complete output samples and arithmetic state. Archive inputs, compiler versions,
source/fixture/verifier hashes and numerical tolerances are recorded in reports.
No temporary native source or binary enters a product or normal test graph.

## Official RFC 8251 corpus

Supply the exact [updated official vectors](https://www.opus-codec.org/docs/opus_testvectors-rfc8251.tar.gz)
and [libopus source release](https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz):

```sh
python3 Tools/DiscordKitTools/scripts/verify_opus_conformance.py \
  --vector-archive /path/to/opus_testvectors-rfc8251.tar.gz \
  --source-archive /path/to/opus-1.6.1.tar.gz \
  --report /tmp/opus-conformance.json
```

The default runs all twelve complete streams at 48kHz for both mono and stereo
output. Every packet is retained, including channel/bandwidth/duration/mode
transitions and packed payloads. Nonzero expected final ranges must match exactly;
sample count and complete stream consumption are mandatory. Owned normalized float
PCM is bounded/rounded to signed PCM16 for the official `opus_compare` executable.
The acceptance rule follows upstream `tests/run_vectors.sh`: either supplied
reference variant may pass for each output layout. Both comparison results remain
visible. The `m.dec` files are alternative stereo references, not mono files;
the official comparator performs reference channel conversion.

`--vectors` and `--channels` permit diagnostic subsets, which report
`fullCorpus: false`. A full-corpus result qualifies only the recorded ordinary
48kHz decoded-PCM/range behavior. It does not certify encoding quality, enhancement
extensions, multistream/container APIs, integer soft clipping, devices, live voice
or realtime deadlines. Reports record source drift so an earlier snapshot cannot
silently qualify a later edit.

## Independent compressed streams and loss

Each command accepts `--source-archive` and an optional `--report` destination:

| Script in Tools/DiscordKitTools/scripts | Independent behavior |
| --- | --- |
| verify_silk_stereo_oracle.py | SILK coded/output mono/stereo, mid-only frames, internal-rate/duration changes and exact PCM16 |
| verify_silk_loss_oracle.py | SILK periodic loss, comfort noise, recovery glue, missing/present LBRR and subsequent ordinary decoding |
| verify_silk_encoder_oracle.py | Owned mono/stereo PCM encoders decoded by native libopus, exact reconstructed output and budget failures |
| verify_opus_hybrid_oracle.py | Native-to-owned and owned-to-native hybrid coding, both bandwidths/layouts and 10/20ms |
| verify_opus_audio_oracle.py | Unified mode/channel/rate/duration transitions, redundant fades, explicit loss and following-packet FEC |
| verify_celt_plc_oracle.py | Raw periodic/noise PLC, pitch/LPC state, loss duration, envelopes and RNG |
| verify_celt_packet_loss_oracle.py | Actual compressed CELT reception, withheld packets, burst loss, duration/bandwidth changes and recovery |
| verify_celt_synthesis_oracle.py | Denormalization/IMDCT, overlap/postfilter/deemphasis and coded/output channel conversion |
| verify_celt_adaptive_oracle.py | Owned masked-transient short blocks, anti-collapse and rate/spectral trim, independently decoded by scalar libopus |

Existing entropy, codebook, transform, energy, allocation, shape, frame and packet
verifiers remain independently useful. Run each script's `--help` for reference
build reuse, seeded case counts and explicit fixture-writing options. Fixture
regeneration is opt-in and requires reviewing the complete fixture/report diff.

SILK fixed-point PCM and entropy comparisons are exact. Ordinary CELT/hybrid float
PCM uses tight declared tolerances. Repeated periodic PLC can amplify tiny transform
differences through order-24 LPC; stress reports use explicit sequence-peak/sample
scaled bounds and separately record absolute maxima. These limits describe measured
numerical agreement and are not a speech-quality or perceptual MOS measurement.

## Native platform gate

Apple adapter property/backend tests and cross-SDK compilation remain separate
from real microphone permission, routing, interruption and hot-unplug qualification.
The [native availability audit](Parity/phase12a-native-platform-audit.json) records
actual missing Windows/Android Swift libraries and audio SDK headers on this host,
plus concrete WASAPI and AAudio/JNI implementation prerequisites. It does not count
an injected backend or a failed compile probe as a native audio implementation.

## Encoder policy and signal measurements

`verify_opus_encoder_policy.py` builds an immutable optimized owned source snapshot
and a separately supplied pinned scalar libopus decoder. It checks encoded final
ranges, independent complete PCM, bounded allocations and DTX refreshes. It records
sequential encode/decode p50/p99 with ten warmup frames followed by a reset; these
sample measurements do not guarantee deadlines on another host or under device load.

```sh
python3 Tools/DiscordKitTools/scripts/verify_opus_encoder_policy.py \
  --source-archive /path/to/opus-1.6.1.tar.gz \
  --speech-wav /path/to/speech_orig.wav --music-wav /path/to/music_orig.wav \
  --report /tmp/encoder-policy.json
```

WAV inputs are optional external 48kHz PCM16 mono/stereo. At most the first five
seconds plus an explicit 60ms silent tail are measured. Inputs remain external;
reports retain fingerprints. The recorded sample run uses the unmodified speech
and music originals linked by the [official Opus examples](https://opus-codec.org/examples/):
[speech](https://media.xiph.org/opus/samples/examples/speech_orig.wav) and
[music](https://media.xiph.org/opus/samples/examples/music_orig.wav). No conversion
is applied. Synthetic vowel/unvoiced, chord/percussion and DTX signals run separately.

Unscaled waveform SNR follows bounded delay alignment and remains a diagnostic.
There is no invented MOS/pass threshold, trained speech accuracy or listening-panel
claim. Independent PCM tolerance is tight before suppression; PLC/recovery uses
an explicitly wider sequence-scaled bound after the first suppressed interval.
The Apple qualification executable is separate from normal tests; see its README
for native permission/device actions and the exact measured versus unmeasured gates.

Four additional FEC-plus-DTX streams cover wideband SILK and fullband hybrid in
mono/stereo at fixed 20ms duration, using finite total targets of 256kbps mono and
384kbps stereo. They preserve the existing ordinary synthetic/external cases.
Each added stream first receives an independent ordinary native decode, then
replays the same encoded packets while omitting source frames 2, 10 and 52.
Recovery from the following packet must select actual LBRR before suppression
and on talkspurt resumption; the omitted suppressed interval must use PLC with
no LBRR. The following packet is subsequently decoded normally. The report keeps
selected LBRR and suppressed PLC counts separate and compares complete recovery
PCM and final ranges against the same operations in pinned libopus. Its
`opus_packet_has_lbrr` inspection independently confirms selected/absent LBRR. These
selected loss cases do not establish complete FEC/loss behavior, low-bitrate
quality or waveform identity to the omitted ordinary decode. Recovery replay
timings are excluded from the ordinary sequential encode/decode benchmark.

Adaptive CELT fixture reproduction is nonwriting by default:

```sh
python3 Tools/DiscordKitTools/scripts/verify_celt_adaptive_oracle.py \
  --source-archive /path/to/opus-1.6.1.tar.gz \
  --report /tmp/celt-adaptive.json
```

The verifier compares its six committed independent fixture streams byte for byte.
Only `--write-fixtures` replaces them; review the complete generated diff before
accepting such a change. The [Apple runner guide](../Tools/AppleAudioQualification/README.md)
describes separate real-device commands, source/binary provenance, native fault
observations and the limits of callback and RSS accounting.
