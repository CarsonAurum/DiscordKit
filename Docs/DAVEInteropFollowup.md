# Initial DAVE commit interoperability follow-up

Scoped implementation and offline verification: **2026-10-19**, macOS arm64,
Apple Swift 6.4. This follows MiniCarson's Phase 8A initial-commit investigation
against DiscordKit `953acc151470c058507d688372d3b9a849cba779`.

## Subsequent native wire and complete-session evidence — 2026-10-19

The later [opcode-26 correction](Parity/changes/2026-10-19-dave-keypackage-wire.md)
supersedes the earlier investigation's no-defect conclusion at that integration
boundary. `DAVEProtocolSession` now publishes a bare TLS KeyPackage, matching
pinned libdave and the complete Discord.js/Davey Voice send path. The whitepaper's
opcode-26 sketch instead shows an MLSMessage wrapper. Strict native decoding of
actual unchanged SDK publication fails (exit 1); removing only that four-byte
wrapper passes complete canonical decoding, both signatures, suite-2 parameters,
the basic eight-byte Discord credential and capabilities (exit 0). Client binary
framing and the opcode-28 wrapped Commit/bare Welcome concatenation are unchanged.

An isolated full-session oracle builds clean native libdave
`8de72b1f8a2ac3c5a5270755bb8091a62e3c6169` against its Cisco MLS++
`fc724c3100ce3b5d8565dbd6d93648a440991a8c` dependency. One native baseline and ten
cross-language exchanges pass, five in each creator direction. The Swift-creator
path independently checks its epoch-zero tree/context/external sender, verifies
initial membership MAC and signature, rejects a wrong MAC key, admits its Welcome
through native `Session` and matches epoch authenticators and sender exporters.
Native creators validate their selected self-echo before Swift recipients join.
This closes the partial oracle's initial-MAC and full-native-session gaps below.

A separate synthetic media oracle passes 100 frames from the actual Swift music
encoder (48-kHz stereo, 960 samples/channel, CELT/fullband, 64 kbps, no DTX/FEC).
Native OpenSSL authenticates outer AES-256-GCM RTP-size packets, checking payload
type 120, sequence, 960-sample timestamp steps, SSRC and transport counters.
Native libdave decrypts every frame to the exact 160-byte Opus packet, and
libopus 1.6.1 decodes 96,000 samples/channel. RMS is 0.142020; the 440-Hz tone-power
ratio is 0.998897. The safe local results, source/build commands and hashes are
in MiniCarson's ignored `.build/phase8-investigation/native/results.json`; no
private/live key material or audio is retained as a repository fixture.

These are local synthetic native interoperability results. They establish the
opcode-26 representation mismatch and candidate/media compatibility, not Discord
service admission, audible listening or the cause of a historical deadline.
The proposed live wire diagnostic stopped at Keychain before network work while
the listener was unavailable. No new Discord attempt or accepted epoch is claimed.
The explicit command publishes one encoding once; no fallback or mutation retry
is introduced. The original diagnostic and partial-oracle record follows as
history; its exact validation counts and release snapshots remain unchanged.

## Earlier diagnostic and partial-oracle record (historical)

## Established changes

`VoiceSession` preserves the first protocol, crypto, capacity or deadline failure
before looking at numeric close status. A status exposed by cancelled sibling
reads cannot replace a handshake deadline with `peerClosed(1002)`. Only an actual
connection-loss result uses observed close evidence to produce `peerClosed`.
A heartbeat failure retains its original cause when terminal close evidence
prevents resume. Genuine terminal peer codes still fail closed; no retry budget
or DAVE/media gate is relaxed.

`FoundationWebSocketTransport` synchronously marks local closure before cancelling
a native connect, send or receive, or explicitly disposing a connection. Native
close callbacks arriving afterward cannot create peer evidence. The first peer
status observed before local closure is retained through repeated cleanup.
This removes the application-caused ambiguity; it does not infer remote rejection
from a status that was never observed independently of local cancellation.

Deterministic tests reproduce `awaitingE2EE` followed by the finite handshake
deadline, cancellation reporting 1002, no retry, no encrypted media and joined
cleanup. Adapter loopback tests separately cover real peer 1002 and private close
codes, explicit reconnect abort, receive cancellation and deadline expiry.

## Independent candidate evidence

The [official DAVE protocol](https://daveprotocol.com/) and
[native session implementation](https://github.com/discord/libdave/blob/8de72b1f8a2ac3c5a5270755bb8091a62e3c6169/cpp/src/mls/session.cpp)
were compared with current pending-group and candidate handling. The inspected
native revision is `8de72b1f8a2ac3c5a5270755bb8091a62e3c6169`. Current code already
emits a complete public MLSMessage commit followed by a bare Welcome, and retains
tentative state for byte-exact initial self-echo selection. No outgoing MLS wire
defect or Discord rejection is established by this investigation.

The explicit [native oracle](../Tools/DAVEInterop/README.md) builds unmodified
Cisco MLS++ revision `fc724c3100ce3b5d8565dbd6d93648a440991a8c` outside the runtime
product graph. A native recipient creates its own package; Swift generates an
initial Add/Commit/Welcome candidate. MLS++ independently verifies exact framing,
initial group context/current epoch, external and commit signatures, the proposal
reference, preserved signer credential/key, UpdatePath leaf signature and Welcome
recipient. It then joins the inline-tree Welcome and matches the epoch-one
authenticator. Four additional cases reject wrapped Welcome framing, truncation,
commit-signature corruption and encrypted-Welcome corruption. No private key is
exported; only anonymous pipes carry the transient synthetic comparison values.
Only safe test outcomes are retained, with no live payload or key fixtures.

The initial membership MAC is not independently checked: the native recipient
has no creator epoch-zero secret. Native Welcome acceptance and signature checks
do not establish complete peer-commit or Discord-service acceptance. This tool
uses MLS++, not the full native libdave session or a live service.

A separate DAVE session regression appends and revokes initial proposals, checks
the replacement's reference coverage/current epoch/preserved signer/recipient,
and distinguishes exact current self-echo from a superseded candidate. Current
selection acknowledges Ready before Execute authorizes media; stale selection
recovers with the retained identity and fresh invitation key. These checks add
coverage without changing the already conforming MLS selection behavior.

## Validation and remaining gates

All of the following passed on macOS arm64 / Apple Swift 6.4 against the changed
worktree. Swift commands used `--disable-sandbox`, isolated writable caches and
approved local execution after the managed environment denied the default compiler
cache. No live Discord or device test was run.

| Check | Observed result |
|---|---|
| Root `swift build` | Passed |
| `SWIFTNIO_STRICT=1 swift test`, with the native oracle explicitly enabled | 2,439 tests in 304 suites across 34 test products passed |
| Final focused `VoiceSessionTests` after fixture refinement | 17 tests passed, including handshake causality and genuine terminal peer 1002 |
| Native CMake build and opt-in MLS++ test | All five acceptance/corruption cases passed; clean pinned source required |
| DAVE initial-candidate regression | Current and stale self-echo cases passed |
| Independent VoiceBot build and offline run | Passed; MLS/DAVE/media/codec/transport demonstrations and cleanup |
| Callable-documentation audit | 808 Swift files; 8,792 explicit callables; zero missing comments |
| Package graph/import audit | Passed for root and independent consumers; no native-tool runtime dependency |
| Inventory, deterministic generation and parity checks | Passed; five generated artifacts remain byte-identical |
| Tooling Python tests | 229 tests passed |
| Diff whitespace and changed Markdown links | Passed |

See [native setup and scope](../Tools/DAVEInterop/README.md) for reproducible offline
commands and the independent check's specific cryptographic limits. Historical
release/qualification records and API baselines remain unchanged. These changes
introduce no public runtime declarations or dependency changes.

This change does not run MiniCarson's signed live wrapper, access Keychain or send
Discord messages. A new controlled run must still observe accepted 29/30, Ready 23,
Execute 22 and authorized encrypted packet progress. Human listening, participant/
key transitions, actual reconnect, repeatable signed-host UDP/teardown and declared
live/post-cleanup memory budgets remain open. Offline counters or this native
Welcome join cannot close Phase 8A or authorize Phase 8B. Independent crypto review,
complete-client interoperability and device/platform qualification remain separate.
