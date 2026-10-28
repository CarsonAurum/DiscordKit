<!--
File: Docs/MLSCryptoReview.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# MLS and voice cryptography review packet

Prepared 2026-10-18. This packet identifies the owned constructions and the
questions an independent reviewer must resolve. **No external cryptographic audit
has been completed. Production cryptographic support remains gated on that
review**, including compiler timing and protocol usage limits. Published component
vectors, local tests and source review do not discharge this gate.

## Primitive boundary

`DiscordMLS` implements only RFC 9420 suite `0x0002`: DHKEM(P-256,
HKDF-SHA256), HKDF-SHA256, AES-128-GCM, SHA-256, HMAC-SHA256 and
ECDSA-P256-SHA256. It imports the existing pinned Swift Crypto product and
Foundation. AES, P-256 arithmetic, SHA, HMAC and entropy generation are supplied
by the maintained crypto dependency and its platform backend. DiscordKit does not
implement those primitive algorithms. This does not transfer an independent
review of the MLS composition to the dependency.

Owned code in `MLSCipherSuite2` includes MLS label serialization, reference hashes,
RFC 9180 DHKEM derivation and base-mode key scheduling, one-shot HPKE orchestration,
AEAD byte layout and error mapping. The explicit HPKE orchestration preserves the
package's macOS 13 floor: the platform's public CryptoKit HPKE interface requires a
newer OS. Every single-shot HPKE seal obtains a fresh P-256 ephemeral key from the
backend; neither sender sequence state nor authentication/PSK HPKE modes are
exposed. MLS pre-shared-secret key-schedule input is distinct from HPKE PSK mode.

Relevant standards are [RFC 9420 sections 5, 8 and 9](https://www.rfc-editor.org/rfc/rfc9420.html),
[RFC 9180 sections 4, 5 and 7.1](https://www.rfc-editor.org/rfc/rfc9180.html),
and [NIST SP 800-38D](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38d.pdf).
These references describe the constructions; they certify neither this code nor
its operational configuration.

## Labels, keys and authentication

- `expandWithLabel` enforces a 32-byte pseudorandom key and an output in
  `0...8160` bytes, the SHA-256 HKDF limit. The encoded length is uint16;
  label/context fields use canonical MLS vectors. The UTF-8 and byte-label
  overloads preserve their documented semantics. Exporter labels in the
  published key-schedule fixtures are text, even when that text looks hexadecimal.
- `deriveSecret` uses an empty context and a 32-byte result. `deriveTreeSecret`
  serializes the generation as a big-endian uint32. `refHash` frames its exact
  reference label without adding the signing/KDF prefix.
- `signWithLabel` signs the exact MLS-framed content and returns a DER ECDSA
  signature. `verifyWithLabel` checks an uncompressed P-256 point, its DER
  signature and the same domain-separated bytes. Application authentication and
  participant authorization remain separate from mathematical signature validity.
- `deriveHPKEKeyPair` implements RFC 9180 P-256 rejection sampling, including
  KEM suite ID, version marker, `dkp_prk` and `candidate` labels and the one-byte
  counter. It never reduces a candidate modulo the curve order. All 256
  candidates may be tried; exhaustion fails without selecting an invalid scalar.
- `hpkeSharedSecret` binds ECDH to the encapsulated and recipient public points.
  `hpkeBaseKeys` includes the base-mode byte, empty PSK identity hash, MLS
  EncryptContext hash, and the full KEM/KDF/AEAD suite ID. Sequence zero is the
  only supported sequence, with a newly encapsulated key for every invocation.
- `seal`/`open` require 16-byte keys, 12-byte nonces and complete 16-byte tags.
  Plaintext and AAD each have a one-MiB ceiling, and opens enforce the corresponding
  ciphertext ceiling before backend work. Returned ciphertext is normalized to zero-based `Data`. Authenticated opens
  never return candidate plaintext. Backend authentication failures are mapped
  to fixed errors containing no key, peer identity or remote text.
- `verifyMAC` requires a full 32-byte tag and uses the backend's authentication
  comparison. No custom constant-time claim is made for ordinary Swift equality.

`MLSKeySchedule` supports commit advancement, Welcome joining and fresh group
creation. Welcome and epoch branches are separated after PSK extraction. The
exporter derives its purpose secret and expands with the context hash. Its named
secrets are explicit caller-owned `Data`; consumers must retain only the branches
needed by their actual owner. An entire schedule must not remain reachable merely
for convenience after message-key use consumes its ancestor secrets.

## Ratchets, counters and state publication

`MLSSecretTree` accepts perfect trees of 1...65536 leaves. Nodes are derived
lazily, and a split removes its parent secret from the candidate dictionary. Both
handshake and application ratchets are initialized before the leaf secret is
removed. Advancing a sender replaces its current secret; only bounded skipped
message keys remain available for out-of-order delivery.

The default maximum forward displacement is 1024 generations and the default
aggregate retained skipped-key bound is 256. Configuration admits at most 65536
for either bound. A generation uses uint32 wire representation and uint64 local
next-index accounting, so consuming generation `UInt32.max` cannot wrap back to
zero. A caller may select a smaller inclusive `maximumGeneration` cryptoperiod
cap; tests exercise exhaustion with that production policy. The exhausted ratchet
drops its final derivation secret. Repeated consumed
keys fail. Invalid leaf, stale generation and capacity failures do not publish
candidate state. Membership checks belong to the group owner: blank leaves must
never become accepted senders merely because their numerical index is in range.

`consume` transfers ownership of a single generation to its caller. For received
messages, the caller must mutate a private candidate and publish it only after
AEAD, signature, epoch, sender and content checks succeed. Authentication failure
must leave canonical replay/ratchet state untouched. For sending, reserve the
key before exposing ciphertext and do not reuse it after a later delivery failure.
`guardedNonce` requires exactly four reuse-guard bytes; the owner supplies fresh
random guards and prevents generation reuse across process restore or copied
values. The secret tree is a synchronous value, not a cross-process nonce service.

`VoiceTransportCipher` is a separate actor with a nonwrapping uint32 transmit
counter. Its configurable packet lifetime is at most `2^32`, its maximum packet
is 65507 bytes including clear header and encryption overhead, and receive state
is bounded to a configured number of authenticated SSRCs with 64-counter windows.
Counter reservation precedes encryption. Failed authentication allocates no replay
state. A new actor initialized with the same key would reset counters and is
forbidden; replacement and restart require fresh keys. These transport rules do
not establish DAVE media-ratchet ownership or a general fleet-wide usage bound.

## Truncated GCM usage profile and DAVE ownership

`TruncatedAESGCM` supplies an experimental eight-byte-tag adapter. Its `open`
obtains a private candidate using AES block permutation, reseals that candidate
with the maintained full-tag GCM backend and compares all eight supplied tag bytes
before releasing plaintext. It implements neither AES nor GHASH. Packet length
controls work; the comparison loop has no source-level early exit, but compiler
and hardware timing need independent measurement. Candidate bytes exist in
process memory before verification and are never returned on failure.

The primitive currently allows ciphertext and AAD independently up to `2^20`
bytes, making their combined ceiling `2^21`. Appendix C, Table 2 of
[NIST SP 800-38D](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38d.pdf)
pairs that combined size with at most `2^23` authenticated-decryption invocations
per key across all instances. Attempts include authentication failures, not just
accepted frames. The table is an upper operational constraint, not a security
audit or a claim that every use of 64-bit tags is acceptable.

DiscordKit implements the independent [DAVE owner](DAVE.md). Its enforced
combined ciphertext-plus-AAD cap is `2^19` bytes (default `2^14`). Its enforced
per-sender/per-generation total authenticated-decryption cap is `2^26`, matching
Appendix C Table 2's `2^19` row, and its separate failed-verification cap is
`2^17`. Applications may reduce these limits. Every actual AEAD attempt consumes
the total allowance before cryptography, and a failed tag consumes the failure
allowance. Malformed/replayed input rejected before AEAD consumes no cryptographic
attempt. These enforced bounds remain subject to independent external review.

One `DAVEFrameCipher` actor owns each sender/exporter domain. Its counter spans
audio/video and consumes a fresh nonce even when an H26x collision requires another
encryption attempt. The generation changes every `2^24` positions; the absolute
counter cannot exceed `2^56-1`, and generation encoding cannot wrap UInt32. Media
nonces are eight zero bytes plus the synchronization UInt32 in little-endian
order, under the generation-specific key. A new owner must never restart counters
under an existing exporter domain. Recovery creates fresh MLS/HPKE material;
logical teardown prevents the previous owner from resuming transmission.

The session tries at most pending, active and one retired epoch for a sender.
Candidate-local replay, expiry, forward-gap or quota rejection cannot select an
epoch and therefore cannot prevent another distinct candidate from authenticating.
Each attempted candidate retains its own budget/replay state, and failed
authentication cannot advance its canonical ratchet. Old generations/epochs are
bounded in count and expire after at most ten injected monotonic seconds. There
are no automatic network replies or packet-level error messages from the media
transform. The caller must keep sanitized errors out of sensitive diagnostics and
coordinate account-wide admission/resource limits.

These limits apply to the local key owner. Duplicating receive owners or retaining
the same key on many recipients requires aggregate accounting and review of the
all-instances NIST constraint, recipient fanout and forgery opportunity across
participants/epochs. Independent receiver-local counters are not proof of that
fleet-wide condition. The stateless truncated primitive and the new protocol
owner remain unqualified for production until external review establishes an
approved operating profile.

## DAVE protocol composition review status

The [verified source record](Parity/dave-current-sources.json) pins the official
DAVE whitepaper, current Voice documentation/changelog and libdave commit
`8de72b1f8a2ac3c5a5270755bb8091a62e3c6169`. The owned implementation binds exact
Voice identity/context, authenticated expected membership and the trusted external
sender; coordinates selected Commit/Welcome before media epoch activation; retains
the shared signing identity across fresh-package recovery; and rejects protocol
zero or unsupported downgrades. Codec-aware sending and codec-independent receiving
share authenticated clear-range framing, with no ordinary plaintext passthrough.
The exact SFU `F8 FF FE` exception requires explicit audio context/admission.

AES-GCM is not key committing. The
[official media-ciphersuite discussion](https://daveprotocol.com/#media-ciphersuite)
identifies the known sophisticated-participant attack in which a crafted frame can
authenticate to different plaintexts under different retained keys during a
transition. Multiple epoch candidates inherit that protocol property; local tests
do not remove it or establish a stronger key-commitment guarantee.

Opcode 26 now publishes a bare TLS KeyPackage, matching pinned libdave and the
complete Discord.js/Davey Voice send path. This corrects the previous MLSMessage
wrapper, which followed the conflicting whitepaper sketch. An independent native
strict-decoder regression rejects the unchanged SDK publication and accepts it
after removal of only the four-byte wrapper, validating both signatures, suite-2
parameters and the basic eight-byte Discord credential. The
[wire correction record](Parity/changes/2026-10-19-dave-keypackage-wire.md) documents
the source conflict and exact boundary. It establishes local representation parity;
it does not establish live service acceptance or explain a past service outcome.
No alternate encoding is probed or ambiguous mutation replayed at runtime.

Independent Python HMAC/scrypt answers, a Node/OpenSSL AES-GCM media vector and
[exact pinned C++/Swift codec comparisons](Parity/dave-codec-oracle.json) check
algorithm bytes. They do not constitute independent protocol review, a full
libdave client handshake, compiler timing analysis, platform/device evidence or
approved Discord smoke. No reviewer, audit report or production approval is claimed.

## Memory, diagnostics and timing

Swift value copies and backend allocations prevent a guaranteed physical-erasure
claim. Clearing dictionaries, replacing `Data`, closing owners and removing old
epoch references provide logical lifetime boundaries only. Key-pair, schedule,
secret-tree and ratchet-key diagnostics redact `description`, `debugDescription`
and `customMirror`; explicit public secret access remains caller responsibility.
Crash dumps and application logging require their own policy.

Cryptographic primitive timing is delegated to the maintained backend. MLS
parsing, tree traversal, rejection sampling and capacity errors are not constant
time and operate on public structure or local configuration. No independent
whole-program timing proof exists. Review must check that compiler optimization,
error mapping, allocation and logging do not turn the truncated-tag comparison
or private candidate processing into a useful oracle.

## Independent review checklist

1. Reconstruct `MLSCipherSuite2` byte encodings from RFC 9420/RFC 9180, independently
   of these tests. Verify KEM/suite IDs, ECDH public-point validation, rejection
   sampling, base-mode PSK extraction order, label prefixes and one-shot nonce use.
2. Inspect backend versions, each supported OS/backend path, entropy failure
   handling and minimum-platform builds. Review ECDSA DER malleability behavior
   against the protocol's required validation rules.
3. Trace key-package consumption, private leaf/node-key ownership, Welcome
   recipient binding, tree/parent hashes, proposal references, transcript hashes,
   confirmation MAC and participant authorization through the group owner.
   Inject faults between validation and state publication, including concurrent
   commits, cancellation, removed members and stale epochs.
4. Trace `MLSSecretTree` deletion and skipped-key policy across all owner copies.
   Verify no failed message advances canonical state and no retry or persistence
   path reissues an encryption generation. Assess worst-case aggregate memory
   and work, including many senders at the configured leaf limit.
5. Independently evaluate `TruncatedAESGCM.open` equivalence, constant-time tag
   handling in optimized compiler output, data-dependent error timing, scratch
   plaintext lifetime and per-key/fanout usage accounting. Enforce the approved
   operating profile and aggregate constraints in the implemented DAVE owner before
   enabling production use. Include simultaneous pending/active/retired candidates,
   counter/generation wrap, codec collision retries, transition teardown and state loss.
6. Verify negative-case and independent interoperability evidence on each
   supported backend. Record reviewer, scope, exact commit, findings, remediation
   and residual limits. Component fixture success alone is insufficient.

## Reproducible component evidence

The offline suite-2 fixtures are filtered without altering field values from
[mlswg/mls-implementations commit 2034fe72e0c805a683ba76165660c834f2a8142a](https://github.com/mlswg/mls-implementations/tree/2034fe72e0c805a683ba76165660c834f2a8142a/test-vectors).
The fixture provenance JSON records immutable URLs and SHA-256 hashes for the
upstream documents and selected local JSON. Tests compare published primitive
KDF/reference/signature/HPKE outputs, five chained key-schedule epochs including
exporters and deterministic external public keys, and secret trees with 1, 8 and
32 leaves at generations 0 and 15. Negative tests cover tampering, label/context
binding, truncation, invalid keys, output bounds, replay, reordering, capacity
rollback, and diagnostic redaction. These deterministic local observations do
not establish authorized Discord interoperability, production safety, native
hardware behavior, or an external security assessment.
