# Supervised voice sessions

Implemented and verified **2026-10-18**. `DiscordVoice` provides bounded per-guild
network/media ownership; `DiscordDAVE` supplies the independently selected actual
E2EE adapter. Voice Gateway **v8**, DAVE **v1** and MLS **1.0/ciphersuite 2** are
explicit. Current official source fingerprints are in
[the Phase 12D source record](Parity/phase12d-current-sources.json).

## Construction and account ownership

`VoiceManager<C>` starts no work during construction. Inject one shared
main-Gateway command authority and an inert session factory. The sender maps
`VoiceManagerCommand` to `GatewayCommand.updateVoiceState` and the correct owned
shard's `send` API; the manager does not import Gateway, Client or the umbrella.
`GUILD_VOICE_STATES`, current account identity and guild/channel permissions remain
application responsibilities. Rate admission belongs to the shared main-Gateway
owner. No ambiguous control mutation is replayed automatically.

Call `join` or `move` from a task while routing typed `VOICE_STATE_UPDATE` and
`VOICE_SERVER_UPDATE` dispatches. Both event orders work. Capture
`generation(guildID:)` before routing and retain the fence across that delivery.
Discord does not include a request nonce, so arbitrarily delayed upstream events
cannot be authenticated as responses to a particular local request. Return means
the fresh session is owned and running; check its readiness separately before
using media. `leave` closes local ownership and sends one explicit leave command.
`stop` cancels and joins all owned runtime tasks and prevents further joins.

Every changed session ID, token, endpoint, null endpoint, self leave or unsolicited
move suspends/disposes the old owner. Fresh matching event halves are required.
A replacement gets a unique full `VoiceConnectionIdentity`, even when Discord
repeats an endpoint. Never reuse a transport key/counter owner or old DAVE backend
across a new identity. The bounded aggregate guild count includes pending joins
and closing slots; failures retain no historical per-guild metadata. Automatic
replacement retains at most four teardown/factory operations per guild. Excess
overlapping replacements close the slot and report capacity failure. Serialize
normal main-Gateway event routing; stop/leave can interrupt pending replacement.

## Session supervision and secure composition

Construct `VoiceSession<C>` with fresh credentials, a TLS WebSocket adapter, an
owned UDP factory, a monotonic clock, finite policy and an actual
`VoiceSessionE2EE` owner. The existing `NIODatagramTransport.bind` is suitable;
portable consumers may inject another conforming bounded transport. HTTP, Client,
Cache and concrete adapters remain independently adoptable. Constructors open no
sockets or devices. A standalone caller owns and awaits `run`; the manager owns
that task when it creates the session.

The supervisor validates the endpoint authority, explicitly connects with `v=8`,
uses HELLO's heartbeat interval, discovers the external UDP address only from the
negotiated peer and installs the selected RTP-size AEAD key. Initial/resume
negotiation and each control write have finite deadlines. ACK debt, resume
sequence acknowledgements and protocol closure have independent ownership.
Resumable socket replacement preserves transport/DAVE nonce authorities and
reauthorizes actual E2EE before enabling media. Session-invalidating/authentication/
terminal peer codes fail closed and require fresh main-Gateway credentials.
The finite retry budget never silently becomes an unbounded reconnect storm.

DAVE imports Voice; Voice imports no DAVE or MLS. `DAVEVoiceSession` implements the
injected protocol using `DAVEProtocolSession`. Supply the trusted external sender,
a P-256 signing key shared across related sessions, authenticated call/group ID
and a single monotonic-seconds closure shared with the supervisor. SSRC bindings
come from authenticated Ready/Speaking controls; RTP cannot create membership.
The adapter serializes bounded concurrent media and prioritizes queued controls,
reserving control admission capacity. No crypto overlap flag is bypassed.

Early authenticated DAVE controls are retained in order under both count and
aggregate byte bounds until Session Description starts DAVE. Membership changes
revoke media until actual epoch/membership state reauthorizes it. Readiness merges
only the authorized phase, preserving heartbeat/sequence state changed during
cross-actor suspension. Old media references remain revocation-gated; late async
results cannot recreate removed sources or restore closed state.

## Sending, receiving and recording

`mediaPipeline()` returns the owned pipeline only while the session is ready.
Before enabling outgoing media the supervisor publishes Speaking with the local
SSRC. `setSpeaking(false)` gates sending independently of receive/playout; publish
Speaking true before a later talkspurt. `play` consumes a cancellation-aware PCM
AsyncSequence with a Sendable iterator, matching the owned encoder's frame size
and 48-kHz format. `PCMFrameStream` provides bounded source/sink composition.
Completion sends five securely transformed 20ms Opus silence frames before
clearing Speaking. Cancellation or source/device disappearance closes the session.
Stop/disconnect cancels and awaits the one owned playback task, releasing a parked
cooperative PCM source. The injected source must cooperate with cancellation; no library can forcibly
interrupt arbitrary user code.

`VoiceMediaPipeline.sendOpus` accepts complete ordinary Opus packets and paces their
parsed durations. PCM sends use the owned encoder. First/restarted talkspurts
anchor pacing to the current monotonic instant; lateness of a full packet period
reanchors the next slot, preventing an arbitrary burst after idle or reconnect.
Both paths perform
encode/validate -> DAVE complete-frame transform -> RTP packetization -> transport
AEAD -> one UDP send. Failed/ambiguous sends consume reservations and are not
replayed. RTP sequence/timestamps wrap normally; cryptographic counters never reset
at wrap. Zero-DAVE/transport-only fallback is forbidden.

Receive performs the inverse authenticated path. Register only authenticated
sources; each has independent bounded jitter/decoder history. Unknown sources,
wrong peer/type, malformed packets, duplicate/replayed frames and failed tags yield
no plaintext delivery. A session counts rejected datagrams without logging media.
Caller-paced `playout` returns authenticated encoded Opus for recording plus PCM,
or explicit PLC for a missing slot. Optional `PCMSink` playback/recording sinks are
bounded caller-owned consumers. Their suspension never blocks heartbeats.
Encoded storage and stream counts have aggregate caps; per-stream buffers have
independent count/byte caps. Caller-owned source/sink queues remain separately
budgeted. No consent, retention, file format or recording storage policy is inferred.

## Validation and remaining gates

[Deterministic tests](../Tests/DiscordVoiceTests/VoiceSessionTests.swift) exercise
handshake/discovery, both main-event orders, replacement, deadlines, heartbeat debt,
resume sequence wrap, peer-close policy, early DAVE, membership, cancellation,
injected source disappearance and repeated cleanup. Real MLS/DAVE adapter tests
exercise complete PCM/Opus/RTP/AEAD duplex, replay/tamper and bounded admission.
[The qualification harness](../Tools/VoiceSessionQualification/README.md) performs
actual localhost UDP with synthetic PCM and a two-member owned MLS/DAVE exchange.
[The validation record](Parity/phase12d-validation.json) states results and limits.

The final release measurement on the published Mac15,10 reference host completed
600 measured seconds after a separate two-second warmup: 60,000 packets sent and
received, 57,600,000 decoded sample frames, no concealed packets, empty final
jitter buffers and all reported owners closed. Two-direction tick p99 was
18.473ms against a 20ms frame period, with three ticks above 20ms and no late
main-loop schedule slots. Tick wall time includes pipeline pacing suspension and
UDP latency; it is not pure codec/crypto CPU cost. Actual RSS rose from 15,319,040
to 20,021,248 bytes after warmup, so **zero resource growth was not demonstrated**.
The raw [final report](Parity/phase12d-local-duplex.json) and
[hardware/source provenance](Parity/phase12d-local-duplex-environment.json) retain
these observations. Earlier failed/intermediate runs remain in the validation
record. Full roadmap qualification remains incomplete.

An authorized Discord smoke is still required: use an application-owned bot/shard,
a permitted test guild/channel and a consenting peer; inject verified participant
keys/external sender, run join/move/replacement/leave, bidirectional audio, participant
change and reconnect, and retain sanitized results. No credentials or trusted
peer material are available here, so this is explicitly **not run**. Standalone
local peers cannot substitute for the service. Independent cryptographic review,
complete-client interoperability, actual device hot-unplug during a Discord call,
minimum-OS/mobile/Windows/Android and production qualification remain open. Native
Apple permission/routing/duplex evidence remains in [Voice.md](Voice.md); this
release does not convert injected source failures into device qualification.

The current [official Voice guide](https://docs.discord.com/developers/topics/voice-connections),
[opcode/close table](https://docs.discord.com/developers/topics/opcodes-and-status-codes#voice)
and [DAVE whitepaper](https://daveprotocol.com/) were rechecked on **2026-10-18**.
Grouped upstream introduction/announcement dates remain unknown. DAVE's eligible
voice enforcement date **2026-03-01** is distinct from local support introduction.
