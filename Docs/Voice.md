# Media and voice protocol foundations

Verified and locally added **2026-10-17**. This is the first release of the
multi-release [Part 12 plan](../.air/plans/phase-12-execution.plan.md), with four
independently adopted products. **Complete Discord voice is not implemented.**
No supervised `VoiceSession`/`VoiceManager` is shipped yet. The independent
[Phase 12B MLS product](MLS.md) supplies bounded group key establishment, and
[Phase 12C DAVE](DAVE.md) now supplies signaling coordination, sender ratchets,
codec-aware encoded-frame protection and ephemeral verification. These are
explicitly composed protocol owners; 12D network/media supervision remains open.
Apple system-route capture/playback is independently
available through `DiscordApplePlatform`; device qualification remains open.

The subsequent [12A execution](../.air/plans/phase-12a-execution.plan.md) adds
streaming media, bandlimited resampling, statistical speech detection and native
Apple audio ownership. The [codec/loss continuation](Parity/changes/2026-10-17-phase12a-codec-loss-conformance.md)
adds mono/stereo SILK, shared-entropy hybrid coding, ordinary mode/channel/rate
transitions, and explicit PLC/CNG/in-band FEC recovery. Encoders have deliberately
bounded analysis and configuration; native platform and quality qualification
remain separate. The [encoder and native qualification continuation](Parity/changes/2026-10-17-phase12a-encoder-native-qualification.md)
adds bounded bitrate/DTX ownership and adaptive CELT analysis. This closure request
excludes Windows/Android implementations. Remaining qualification is recorded
explicitly; neither that exclusion nor a numerical comparison implies perceptual,
minimum-OS or all-Apple-device qualification.

## Products and ownership

| Product | Implemented behavior | Dependency boundary |
| --- | --- | --- |
| DiscordMedia | Rational/sample clocks, caller-driven pacing, bounded PCM/audio/video values, PCM16 conversion, gain/mixing, linear/windowed-sinc resampling, RMS/statistical speech detection, polling and terminal-aware async queues | Foundation; no codecs/network/platform capture |
| DiscordVoiceCodecs | Owned Opus framing/entropy, mono/stereo SILK/CELT/hybrid coding, unified ordinary decoding, mode transitions and explicit PLC/CNG/FEC | Media; no native Opus runtime; conservative encoding analysis, ordinary packets and 48-kHz decoder output |
| DiscordVoiceCrypto | XChaCha20-Poly1305, owned HChaCha20, public AES256-GCM, experimental truncated AES128-GCM adapter and actor-owned RTP-size packet protection | Existing Swift Crypto and its public CryptoExtras product |
| DiscordApplePlatform | Apple engine capture/playback, bounded queues, permission/session ownership, explicit supported device selection and observed-route invalidation | Media/Core/Transport; native AVFoundation/CoreAudio only in this adapter |
| DiscordVoice | Bounded Voice v8 JSON/binary frames/opcodes, pure handshake/heartbeat/resume reducer, main-Gateway join rendezvous, discovery, RTP framing, Opus packetization and reorder window | Core/Models/Transport and the three media products; no Client/Gateway/facade ownership |
| DiscordMLS | MLS 1.0/ciphersuite-2 key establishment and restricted DAVE-profile group handshakes | Existing Swift Crypto; no Voice/media/network ownership |
| DiscordDAVE | Authenticated Voice/MLS transition coordination, sender ratchets, codec-aware frame encryption, bounded replay/verification and ephemeral human verification | Voice/MLS/VoiceCrypto/Core/Transport and existing Crypto/CryptoExtras; no concrete network/device adapter |

Constructors start no I/O or tasks. A caller drives each reducer, clock, transport
and cleanup boundary. HTTP, Gateway, Client and the umbrella do not depend on the
voice products. The narrow join inputs use existing immutable Gateway dispatch
models; owning the main client is unnecessary. The [VoiceBot example](../Examples/VoiceBot/README.md)
exercises an offline encoded packet round trip without connecting to Discord.

## Media and Opus limits

PCM uses finite normalized interleaved floats, mono/stereo, 8–192 kHz and at most
120 ms per block. PCM16 little-endian conversion handles every signed sample,
including the asymmetric -32768/+32767 bounds. Mixing and gain clip to the
normalized range. Linear resampling is explicitly per block with no anti-alias
filter or cross-block phase history; it is not a production bandlimited resampler.
The RMS gate is an energy threshold, not speech classification, AEC or denoising.
Queue writes reject overflow without partial retention; immediate reads return
nil for an empty queue, with caller-owned scheduling and completion observation.

`PCMFrameStream` instead waits when idle and returns nil only after finish/drain.
Writes reject overflow immediately, including oversized direct delivery to a
waiting reader. All iterators share consumption, with at most one parked read.
Cancelling iteration finishes/discards the stream. Explicitly finish when abandoning
iteration without cancellation. Accounting excludes blocks transferred to consumers.

`PCMStreamingResampler` carries rational phase across chunks, retaining one input
frame and at most one deferred output frame. Final counts equal the floor of
aggregate input duration at the destination rate. Finish holds only the remaining
tail; output blocks stay within 120ms. It also lacks an antialias filter.

`PCMBandlimitedResampler` adds a finite Blackman-windowed sinc filter with a cutoff
at 90% of the lower Nyquist frequency. It retains at most twice its filter radius,
waits for future samples and flushes endpoint support only at finish. Rational
phase/counts are independent of chunking. Equal rates preserve samples without
filtering. Explicit processingDelay reports lookahead without shifting timestamps;
sinc overshoot clips to normalized PCM. Deterministic spectral tests cover selected
48k/44.1k/192k conversions, not universal perceptual or realtime qualification.

`PCMSpeechActivityDetector` combines approximately 20ms frames, adaptive SNR,
periodicity, spectral shape/bands, temporal change and bounded hangover. Channels
are classified independently, avoiding antiphase cancellation. Evidence is synthetic,
with no corpus accuracy claim. Whisper/unvoiced-only speech can be missed, music
and machinery can be accepted, and stationary long vowels can be suppressed.
It provides no AEC/denoising and is independently adopted from the RMS gate.

`MediaTime.converted` and `compare` use full-width integers; equality remains
representation-based. `PCMSampleClock` reserves exact sample timestamps and rejects
rollover. `PCMFramePacer` uses an injected monotonic clock, carries fractional
nanoseconds and rejects concurrent waits. Failed/cancelled waits reserve no interval.
It reports lateness; consumers own skip/PLC decisions and reset after discontinuities.
It supplies no realtime/device scheduling guarantee.

The Opus parser applies the [RFC 6716 framing rules](https://www.rfc-editor.org/rfc/rfc6716#section-3),
the [RFC 8251 padding correction](https://www.rfc-editor.org/rfc/rfc8251#section-4)
and the [inline errata](https://www.rfc-editor.org/rfc/inline-errata/rfc6716.html).
Packets are capped at 65,536 bytes, frames at 1,275 bytes, and total duration at
120 ms (5,760 samples per channel at 48 kHz). Zero-byte frames are legal. Frame
ranges exclude packing headers/padding. Structural acceptance cannot validate
compressed SILK/CELT data, produce PCM, qualify FEC/PLC or imply codec conformance.

`OpusRangeEncoder`/`OpusRangeDecoder` implement sections 4.1/5.1 entropy operations
and verified erratum 4853 with exact contexts, fixed frames up to 1,275 bytes and
finite coding-call budgets. Operations include uniform/raw splits, carry/termination,
specified zero extension and legal raw/read-ahead overlap. Six independent official
libopus 1.6.1 fixtures compare bytes and per-operation range/bit state. This supplies
no audio syntax by itself; the codec stages below compose with it. Probability
models admit up to 257 symbols for the widest CELT theta context. Frame coder
failures are terminal; complete-frame owners use private copies to preserve stream
history on failure. See the
[dated media/entropy record](Parity/changes/2026-10-17-phase12a-media-entropy.md).

`CELTPulseCodebook` implements RFC 6716 section 4.3.4.2 signed integer pulse
ranking/unranking and uniform entropy composition. Bounds are 1...176 dimensions,
0...128 pulses and at most UInt32.max codewords; oversized codebooks require
the recursive shape coder below. Forty official libopus codeword fixtures and an
opt-in seeded oracle compare integer vectors, indices, counts and entropy output.
This codebook supplies no band allocation or decoded audio by itself; separately
adopted quantizers and frame codecs compose with its integer/entropy contract.
See the [continuation record](Parity/changes/2026-10-17-phase12a-dsp-apple-pvq.md).

`CELTBandQuantizer` adds projected/greedy shape search, all four spreading levels,
one/two/four/eight short blocks, pulse-domain collapse masks and normalized
reconstruction. It composes one admitted codebook with the range coder; bands
requiring recursive splitting remain rejected. Callers supply normalized bands,
pulse allocation, gain and spreading. Shape results contain spectral values,
not PCM or complete compressed audio frames. The source retains the applicable
libopus BSD attribution for adapted search/rotation algorithms.

`CELTTransform` adds all four 48kHz CELT frame sizes (120/240/480/960) and the
120-sample low-overlap window. Its independently implemented mixed-radix FFT
uses bounded O(N log N) work/O(N) storage and Double arithmetic internally.
`CELTTransformStream` owns separate analysis/synthesis histories; unquantized
round trips have exactly 120 samples of delay. Reset discards both tails; explicit
zero input flushes them. The transform itself makes no transient decision and
performs no pre/de-emphasis; the frame codec composes those stages separately.
Official scalar float comparisons are tolerance-qualified, not bit-exact.

`SILKLinearPredictionCoefficients` validates already quantized order-ten/sixteen
Q12 coefficients with conservative floating-point reflection/gain checks.
`SILKShortTermFilter` performs streaming analysis or unclipped all-pole synthesis;
`SILKLongTermSynthesisFilter` adds causal five-tap voiced prediction at 8/12/16kHz.
Callers own gain/rewhitening and parameter transitions. `SILKExcitationReconstructor`
implements all six offset combinations, signed pulse adjustment and exact Q23
excitation/seed updates. These remain independently adopted primitives; the channel
and packet decoders below own their parameter and state transitions.

`SILKPulseCoding` implements rate-level selection, shell splitting, escape/LSB
planes and sign contexts, including mediumband 10ms padding and ten LSB planes.
`SILKFrameParameterDecoder` reads type/gain, NLSF residuals/stabilization, pitch,
LTP and seed syntax. `SILKNLSFCoefficients` performs fixed-point NLSF-to-LPC
conversion, interpolation, fitting and inverse-gain stability. `SILKFrameDecoder`
composes these into ordinary no-loss 8/12/16-kHz PCM16 with gain scaling, rewhitening
and persistent LPC/output history. Independent comparisons check exact integer
PCM, entropy and history across successive frames.

`SILKMonoDecoder` and `SILKStereoDecoder` consume VAD/LBRR headers, decode
10/20/40/60ms payloads and produce 48-kHz PCM16 through owned allpass/FIR
resampling. The generalized stereo owner handles coded mono/stereo, output
mono/stereo, mid-only frames, predictor interpolation and internal-rate changes.
Mono output uses normative mid synthesis rather than averaging rendered left/right.
`SILKFrameDecoder` now owns pitch/LPC concealment, comfort noise and recovery glue.
`conceal` advances missing audio; `recoverPayload` consumes following-packet LBRR
when present and otherwise conceals. Decode that following packet normally afterward.
Independent scalar reference comparisons check complete PCM16 samples and entropy.
SILK's normative entropy zero extension can accept damaged nonempty payloads;
decoding provides no authentication.

`SILKFrameParameterEncoding` supplies the inverse parameter syntax, including
conditional voiced pitch. `SILKMonoEncoder` and `SILKStereoEncoder` emit actual
bounded packets from 8/12/16-kHz PCM16, with 10/20ms frames, quantized NLSF/gains,
voiced pitch/five-tap LTP analysis, exact synthesis-feedback excitation and local
reconstruction. Optional in-band FEC carries preceding active channels as
following-packet LBRR within the same explicit budget. The stereo encoder uses
explicit mid/side coding. Their shared range-encoder entry points permit hybrid
composition without finalizing the interval between layers. Configuration,
analysis and rate-control limitations are documented at the API; independent
reference decoding establishes syntax and reconstruction, not perceptual quality.

SILK rate admission tries at most 64 gains for the selected model, then up to 64
unvoiced gains if voiced coding cannot fit. If ordinary gain admission fails, seven bounded
scalar rate-distortion candidates favor sparse unvoiced pulses, including zero
pulse indices, at the initial unvoiced gain. Work is capped at 135 quantizations
per channel/frame. Every candidate retains the same input frame and VAD state,
requested FEC obligation and exact decoder synthesis feedback. Failed admission
preserves stream and caller entropy state; no retry increases the byte/bit cap.
Sparse pulse indices remain ordinary encoded audio and can materially reduce
waveform fidelity. The measured external speech excerpt at 32kbps mono produced
4.61dB delay-aligned waveform SNR. This low-rate distortion remains a quality
limitation; the numerical result supplies no perceptual acceptance claim.

`CELTEnergyQuantizer`, `CELTFrameHeader` and `CELTBitAllocation` implement segmented
prefix/TF/boost/trim syntax, predictive/coarse/fine/final energies, caps/interpolation,
skips, stereo decisions and fine priorities. `CELTShapeCoding` adds recursive
splitting, theta/stereo/intensity, TF/Haar, folding/noise and bounded PVQ leaves.
`CELTShapeFrameCoding` owns all-band balance/folding and anti-collapse. `CELTSynthesis`
adds denormalization, short/long overlap, delayed pitch postfilters and deemphasis,
sharing history across durations. Floating PCM is normalized by 32768 without clipping.

`CELTFrameDecoder` composes the ordinary frame pipeline with atomic history
replacement, coded/output channel conversion and hybrid start-band selection.
`CELTFrameEncoder` supplies bounded encoding from normalized 48-kHz
PCM: preemphasis, transform, band normalization, energy/allocation and shape coding.
Its default `.fixed` analysis preserves the existing long-block behavior. Opt-in
`.adaptive` analysis selects short MDCTs for masked onsets, reserves anti-collapse
and selects allocation trim from rate/spectral tilt. Low budgets retain long blocks;
near-silent/low-frequency tonal input avoids spurious transient switching. Pitch
prefilter search and reference psychoacoustic/noise-shaping equivalence are not supplied.
`CELTPacketEncoder` supplies a single-frame TOC; `CELTPacketDecoder` accepts ordinary
packing/padding and owns explicit loss. Periodic CELT PLC uses pitch and order-24
LPC, falling back to shaped noise for long loss/high-band-only audio. Loss updates
energy predictors and retains recovery histories. Floating PLC error can amplify
small transform differences; the pinned reports specify exercised tolerances.

`OpusHybridEncoder` combines a delayed, bandlimited 48-to-16-kHz SILK path with
CELT bands 17 and above in one range interval. It supports mono/stereo, 10/20ms,
superwide/full bandwidth and explicit packet budgets. Its conservative layer
allocation and analysis are not libopus perceptual rate-control equivalence.
Optional hybrid FEC protects the SILK layer; its missing high band uses CELT PLC.
`OpusHybridDecoder` independently adopts shared-entropy hybrid payloads, entropy
storage reduction before backward raw-bit access, redundant CELT tails and fades.

`OpusAudioDecoder` is the ordinary packet owner for all three modes. It preserves
histories across coded mono/stereo, bandwidth, duration and mode changes; applies
5ms transition redundancy and squared-window fades; handles empty/one-byte
payload loss; and exposes bounded `conceal` and subsequent-packet `recover`.
The output is fixed mono/stereo 48-kHz normalized float, without clipping. Decode
operations on malformed packed packets commit no history. Cold loss yields zeros;
recovery consumes missing audio before the following packet is decoded normally.
It does not implement multistream/container framing, enhancement extensions,
output gain or integer-output soft clipping. No network/device/task ownership is
implicit. See the dated record for independent streams and official vector results.

`OpusAudioEncoder` owns one explicit mode/bandwidth/layout/duration with normalized
48kHz input. It selects adaptive CELT analysis and bandlimited SILK conversion;
construction starts no tasks or I/O. Total codec bitrate includes TOC/packing,
excludes network headers and carries fractional bytes exactly between frames.
Changing the target clears only fractional carry. Caps never silently increase to
fit content or FEC; an unencodable SILK budget fails without changing stream state.
SILK uses minimum arithmetic storage plus standard packet padding, preventing
unused physical payload from being interpreted as transition redundancy.

Optional `OpusDTXPolicy` measures per-sample RMS without stereo cancellation, retains
a bounded talkspurt hangover and transmits an ordinary refresh at most every 400ms.
`shouldTransmit == false` permits omitting that interval's TOC-only placeholder;
media time still advances and the receiver synthesizes PLC/CNG. Analysis continues
during suppressed frames, so this saves bandwidth without promising CPU savings.
CELT refresh/resumption requests independent energy prediction. The gate can suppress
quiet wanted content and supplies no speech classifier. Automatic mode selection,
perceptual encoder equivalence and hard realtime scheduling remain separate.

Encoded video values retain opaque H.264/H.265/VP8/VP9/AV1, keyframe, dimension and
optional spatial/temporal-layer metadata. Layer bounds are local storage policy,
not inferred wire fields or negotiated capabilities. No
video codec, RTP video packetization, fragmentation, Go Live or camera signaling
is implemented.

## Apple audio ownership

`AppleAudioDevice` is a MainActor owner with an injected `AppleAudioBackend` and an
owned AVAudioEngine/AVAudioPlayerNode backend. Construction opens no devices and
starts no tasks. Capture requires an explicit permission query/request and start;
apps supply microphone usage descriptions and sandbox entitlements. Playback-only
adoption never prompts. Select host-managed shared session ownership or explicitly
exclusive foreground session configuration. This supplies no background entitlement.
Capture uses the selected hardware rate and first one/two channels; portable
resampling is explicit. Playback uses the configured format and selected output route.
`availableDevices()` explicitly queries bounded immutable UID/name/direction metadata.
macOS accepts exact CoreAudio input/output UIDs, resolving them again at start and
checking actual AudioUnit binding. Explicit selection uses independent input/output
engines, disabling each AudioUnit's unused direction before binding. This avoids
AVAudioEngine's implicit duplex aggregate coupling; nil selections keep shared
system-route ownership. iOS/tvOS/visionOS accept available preferred-input
UIDs; cleanup restores only a preference the owner still controls. watchOS input and
arbitrary non-macOS output UID selection fail explicitly because these public APIs
cannot provide those controls. Nil UIDs retain system routing. Discovery starts no
engine or permission prompt, and device identifiers are never diagnostic labels.

Input taps synchronously offer owned at-most-120ms PCM blocks to block/byte-bounded
storage. Overflow drops new capture and saturates a drop counter. Playback reserves
bounded capacity before scheduling; completion releases only its generation's
reservation. No audio callback starts a Swift task. Callback locks/allocations mean
this adapter makes no hard realtime guarantee. Stop revokes callback admission,
stops the engine and discards media. Always stop before abandoning the owner.

Observed route/interruption/reset events stop/discard and require an explicit
restart. A configuration notification can be ignored only while both owned graphs
remain running, capture layout/rate/Float32 format is unchanged and selected native
bindings remain alive and exact. Any failed query or mismatch stops ownership.
Native notifications defer teardown outside the notification stack with a bounded
coalesced invalidation; a benign configuration event cannot erase a pending stop.
macOS also observes default-device changes. OS delivery is not a guaranteed privacy
barrier against every route race. Selected device-alive
and topology monitoring is bounded and released on stop. macOS additionally reads
the selected devices' `DeviceIsAlive` flags after observer installation and again
after engine startup. This rejects an unplug that occurred before the listener
was installed even if the AudioUnit still reports the same bound ID. A shared
duplex device is queried once per checkpoint; there is no default-device fallback.
Listener installation is atomic: a failed registration removes every earlier
registration in reverse order, and late callbacks remain generation-fenced.
The availability flag and observer ownership follow Apple's
[DeviceIsAlive contract](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertydeviceisalive)
and [listener registration contract](https://developer.apple.com/documentation/coreaudio/audioobjectaddpropertylistenerblock(_:_:_:_:)).
These checks narrow startup races; they cannot guarantee hardware remains present
after readback. Real macOS permission, route-change and selected-device hot-unplug
observations are recorded in the [dated qualification record](Parity/changes/2026-10-17-phase12a-encoder-native-qualification.md).
Interruption, minimum-OS and mobile runtime checks remain separate. Windows/Android
capture/playback remain deferred by the requested scope. Linux accepts injected PCM.
Normal unit tests never request permission or open devices; the separate opt-in
[qualification executable](../Tools/AppleAudioQualification/README.md) performs native I/O.

## Transport encryption and RTP

The current [voice reference](https://docs.discord.com/developers/topics/voice-connections)
uses **Voice Gateway v8**, independently of main Gateway/REST v10. It requires
`aead_xchacha20_poly1305_rtpsize` and prefers `aead_aes256_gcm_rtpsize` when offered.
Deprecated XSalsa modes are rejected. A 32-byte negotiated transport key protects
the packet body with a unique 32-bit incremental counter appended in network order.
The counter is placed first in the expanded nonce and followed by zeros. RTP
sequence and timestamp rollover must never reset this cryptographic counter.

`RTPPacket.authenticatedHeaderLength(in:)` splits the fixed header, CSRCs and
optional four-byte extension preamble from the encrypted body. Extension content
and RTP padding stay inside encryption. Authenticate before parsing their lengths,
routing decoded media or inserting packets into `VoiceJitterBuffer`. This buffer
has a finite byte budget and a window below half the RTP sequence space; its
caller-paced pop explicitly reports missing packets without manufacturing PCM.
Resetting playout never resets replay state. `VoiceDiscovery` validates the
74-byte response and SSRC; the socket owner must separately validate its UDP peer.

`OpusRTPPacketizer` validates packet duration, increments sequences and 48 kHz
timestamps only on success and supports the documented five termination-silence
frames. It neither encrypts nor transmits. RTP uses payload type 120. Speaking
state must be announced before actual media; that network orchestration is not
part of this release.

`VoiceTransportCipher` is an actor so copied Swift values cannot duplicate its
transmit nonce allocator. All producers sharing a session key must share that
owner. Never construct another sender with the same key or reset a key's nonce
space; this local actor cannot police cross-process reuse. Counter reservation
precedes encryption, including failures; exhaustion requires a fresh key.
Receive replay windows retain 64 counters per authenticated SSRC with a configured
stream limit, no silent eviction and no state advancement on failed authentication.
Close drops key references and metadata; Swift/Crypto storage is not guaranteed
to be securely erased. Diagnostics redact keys, credentials, payloads and endpoints.

The [expired XChaCha draft revision 03](https://www.ietf.org/archive/id/draft-irtf-cfrg-xchacha-03.html)
supplies HChaCha and full AEAD known-answer vectors. The truncated AES128-GCM
adapter uses public AES block permutation for private candidate decryption and
public full-tag GCM resealing to recompute authentication; candidate plaintext
does not escape unless its eight-byte tag is accepted. It does not implement MLS,
DAVE ratchets, verification-attempt limits or nonce ownership. NIST vectors and
negative tests exercise the adapter, but **external independent crypto review,
compiler timing analysis and protocol usage-limit review remain open**.

## Control and E2EE gates

The main-Gateway `VOICE_STATE_UPDATE` and `VOICE_SERVER_UPDATE` rendezvous accepts
either arrival order and matches guild/user/channel plus a caller-carried local
generation. Replacement/leave/null endpoint invalidates old state. The Gateway
wire itself carries no local generation, so the integration owner must associate
incoming events with its current join and enforce timeout/cancellation ownership.

`VoiceGatewaySessionState` is a pure protocol reducer, not a running session. It
uses HELLO's heartbeat interval, exact v8 `seq_ack` values, matching ACK nonces and
explicit reconnect/resume/close state transitions. Callers schedule deadlines and close
sockets. Valid DAVE controls for the negotiated version suspend media and are
surfaced to a backend. Different-version transitions, downgrade or malformed
protocol-version fields close the reducer and require replacement; automatic
version migration is not implemented. Other DAVE fields and MLS bytes remain
opaque for backend validation. A separately
implemented `VoiceE2EEReadiness` backend must validate actual epoch, membership,
external sender, version, keys, transitions and the full guild/user/channel/session
identity plus generation. A matching generation alone cannot authorize another
session. The independently adopted `DAVEProtocolSession` performs that binding
through `authorizeGateway(_:)`; actual media must continue passing the actor's
active-epoch/membership gates. Its constructor starts no network work and it does
not implement 12D's supervised socket/session owner. DAVE version zero fails closed.

Discord's [E2EE requirement](https://docs.discord.com/developers/topics/voice-connections#end-to-end-encryption-dave-protocol)
took effect for eligible conversations **2026-03-01**. Transport encryption cannot
replace DAVE. [MLS 1.0/ciphersuite 2 key establishment](MLS.md) is independently
implemented. The independently adopted [DAVE product](DAVE.md) now implements
signaling integration, sender ratchets, frame transformations and ephemeral
identity verification. Independent crypto review, complete-client interoperability
and approved live media qualification remain required. Unknown introduction/announcement
dates are recorded as unknown; local implementation dates are separate.

## Validation and remaining release gates

The deterministic suites use synthetic packets, published primitive vectors and
no live credentials. They cover PCM boundaries, malformed Opus/RTP, extension and
padding splits, both AEAD modes, tamper/replay, concurrent nonce allocation,
cancellation, byte/stream limits, counter exhaustion, generation fencing and
heartbeat/resume/E2EE suspension. They establish local component behavior only.

The [owned Opus verification guide](VoiceVerification.md) documents pinned source
admission, independent compressed streams, loss/FEC comparisons and the complete
official RFC 8251 corpus. Reports distinguish exact integer/entropy decisions from
tolerance-qualified floating PCM and record the compiled source snapshots.

The encoder-policy record includes objective speech/music diagnostics and measured
frame p99 on this host. Low-rate SILK speech fidelity remains limited; numerical
agreement supplies no perceptual acceptance. Native reports distinguish local
capture/codec/playback accounting from unavailable hardware render-underrun telemetry.
Independent MLS component/passive-Welcome vectors and local group tests are recorded
in [MLS](MLS.md). Local DAVE signaling/media/verification evidence and its pinned
C++/Swift codec oracle are described in [DAVE](DAVE.md). External crypto review,
complete DAVE interoperability, an owned supervised network/media pipeline, complete
platform/device qualification, non-macOS runtime and minimum-OS testing, authorized
Discord voice smoke and demonstrated lossless hardware duplex remain open.
No production voice, video, cross-platform or fleet-capacity claim
follows from this release. See [source fingerprints](Parity/voice-media-current-sources.json),
[chronological parity](Parity/changes/2026-10-17-voice-media.md) and
[capability inventory](Parity/voice-media-capabilities.json).
