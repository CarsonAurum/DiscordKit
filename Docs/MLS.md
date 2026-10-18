# Independently adopted MLS

Implemented locally: 2026-10-18. Protocol sources verified: 2026-10-17.

`DiscordMLS` implements owned Swift MLS 1.0 ciphersuite 2 components and the
restricted group-handshake profile required by Discord DAVE v1. It selects only
the existing Swift Crypto product. Importing MLS selects no HTTP, Gateway, Client,
Cache, OAuth, media, codec, device or network-adapter product. Construction starts
no tasks, timers, sockets or other I/O. The implementation and test fixtures are
committed; consumer builds fetch no specifications or test vectors.

This product supplies MLS key establishment. The independently adopted
[DAVE product](DAVE.md) now composes it with Voice signaling, sender ratchets,
encoded-frame transforms and ephemeral verification; MLS itself retains no
Voice/media dependency. Sender verification UI and supervised network sessions
remain separate integration work. See [voice ownership and remaining
qualification gates](Voice.md) and [dependency policy](Dependencies.md).

## Protocol and scope

The normative wire and cryptographic baseline is
[RFC 9420](https://www.rfc-editor.org/rfc/rfc9420.html), including canonical
one-, two- and four-byte vector lengths. The selected suite is
`MLS_128_DHKEMP256_AES128GCM_SHA256_P256` (`0x0002`): P-256 DHKEM,
HKDF-SHA256, AES-128-GCM and DER ECDSA over P-256/SHA-256. Public points use
65-byte uncompressed SEC1 encoding; private scalars and MLS secrets use 32 bytes.
HPKE base mode follows [RFC 9180](https://www.rfc-editor.org/rfc/rfc9180.html).
No external MLS implementation or Discord native SDK is linked or vendored.

Implemented components include labeled hashes/KDFs, references, signatures,
HPKE, the epoch key schedule and exporters; basic credentials; signed leaves
and key packages; public proposal/commit framing; ratchet-tree serialization,
tree/parent hashes, resolutions and filtered paths; TreeKEM encrypted update
paths; encrypted Welcome and signed GroupInfo processing; transcript and
confirmation/membership authentication; and bounded secret-tree sender ratchets.

The group profile follows the
[DAVE v1 MLS restrictions](https://daveprotocol.com/):

- Explicit MLS version 1 and ciphersuite 2.
- Basic member identity is the exact eight-byte big-endian Discord user snowflake.
- One trusted external sender in the sole `external_senders` GroupContext extension.
- No leaf-node extensions. Unknown advertised KeyPackage extensions remain preserved
  and ignored as required by RFC 9420. Owners emit the full unsigned lifetime
  `0...UInt64.max`; DAVE members deliberately ignore received key-package expiry
  and do not require that an authenticated package repeats that emitted interval.
- Only externally authorized Add and Remove proposals, committed by reference.
- No PSKs, reinitialization, external commits, arbitrary proposal types or MLS
  private/application messages. DAVE media obtains its key material through exporters.

These exclusions are enforced by the profile. General-purpose credential/leaf
wire values preserve bounded unknown capabilities and extensions for inspection
and cryptographic validation; that does not admit those extensions into a DAVE group.
The ordinary leaf/key-package validation API supports injected time and an explicit
maximum lifetime; callers choose the DAVE-specific policy deliberately.

## Authentication and ownership

Basic credentials contain identity assertions. A valid leaf or key-package
signature proves possession of a signing key. `MLSGroupPolicy` authenticates the
identity/key association through Add proposals signed by its trusted external
sender, together with the application's authenticated participant authorization
set. Never authorize a member solely because its signed credential claims an
allowed ID. Inject the expected external-sender key and credential from the
authenticated delivery service; an untrusted tree or Welcome cannot choose its
own trust anchor. This establishes the configured service authority, with human
identity comparison left to an independent verification flow.

Private keys are supplied or generated explicitly at the ownership boundary.
An invitation init key is distinct from the leaf encryption key and must be
published and consumed once. Reusing one init key for multiple invitations can
undermine forward secrecy. Low-level `MLSKeyPackage.generate` accepts public
keys from the caller and cannot enforce freshness across independent callers.

Wire decoding yields candidate values. Admission must verify the complete
signature, participant/identity/key association, source-specific context,
tree integrity, transcript and confirmation/membership authentication before
publishing candidate epoch state. Update/commit leaves sign both group ID and
leaf index; key-package leaves use their separate source context. Member public
messages authenticate the current GroupContext; external proposal signatures omit it.
Proposal references bind AuthenticatedContent and omit the membership MAC.

`MLSGroupContext` also represents a provisional next-epoch context during commit
calculation. Its transcript hash may temporarily be empty before the confirmed
transcript is calculated. An authenticated final GroupInfo after epoch zero must
contain the complete 32-byte confirmed transcript hash.

The product owns no delivery retries. Keep the caller's group/session generation
associated with every submitted or received operation, and do not replay an
ambiguous commit as a fresh mutation. `DAVEProtocolSession` coordinates approved
epoch transitions with media key installation and teardown when explicitly adopted;
independent MLS callers retain that responsibility themselves.

## Actor API and lifecycle

`MLSKeyPackageOwner(userID:)` generates fresh P-256 signing, leaf-encryption and
independent invitation-init keys. Its immutable nonisolated `keyPackage` can be
published as `keyPackage.encoded(messageWrapped: true)`. The actor retains private
key material until one successful `createGroup(groupID:policy:)` or
`join(welcome:expectedGroupID:policy:)`. A failed or cancelled admission preserves
the package for a corrected authenticated input. Success consumes the owner;
another create/join then throws `closed`. The explicit `retainForWelcome: true`
option permits a provisional initial group while preserving the invitation keys
until delivery-service selection chooses a Commit or Welcome; selecting a later
Commit closes the unused invitation owner. DAVE uses an injected shared signing
private key across related media sessions and fresh HPKE/init keys for recovery.
The default remains consuming single-owner creation. `close()` discards an unused package
explicitly and can be repeated.

The creator uses `createGroup` for a fresh unique group ID and policy containing
its own authorized user ID. Other members use `join` with that exact group ID
from authenticated session context. Join verifies the matching KeyPackage
reference, HPKE, encrypted GroupInfo, complete tree/hash/parent chains, expected
participants and external sender, signer identity/signature and confirmation MAC
before returning an `MLSGroup`. It exposes no candidate GroupInfo or secrets.
Successful use of one owner cannot accept the same Welcome twice.

`MLSGroupPolicy` fixes the trusted external sender and resource budgets. A group
keeps a separate current participant-authorization set. Use
`setExpectedParticipants(_:)` only with authenticated session membership; a changed
set invalidates its tentative commit, and cached Add proposals are rechecked
before application. Membership mutations still arrive as authorized proposals.

The group actor's explicit handshake sequence is:

1. Call `cacheProposal(_:)` with a complete externally signed public Add/Remove.
   It validates group, epoch, external-sender index/key and participant admission
   before storing its reference. Byte-identical duplicates are idempotent;
   capacity overflow preserves existing proposals.
2. Apply `revokeProposal(_:)` only for an authenticated delivery-service revocation.
   The method accepts a reference, while the caller authenticates the instruction.
   Unknown well-formed references leave state unchanged.
3. Call `prepareCommit()` to construct one `MLSTentativeCommit` containing the
   signed commit, optional addressed inline-tree Welcome and proposed epoch.
   The actor continues exporting from the current epoch. Repeated preparation
   returns the same retained candidate until proposals or authorization change.
4. Deliver the wire outputs through the application's authenticated channel.
   Call `acceptCommit(_:)` only for the delivery-service-selected commit. The
   actor selects an exact echo of its local candidate or verifies a remote
   winning commit before atomically replacing the epoch. At epoch zero, DAVE
   permits only the creator's own exact candidate. A valid remote winner discards
   the local tentative state; a failed candidate preserves it.
5. Handle `.advanced` by installing the newly approved exporter output in the
   separate media/session owner. Handle `.removed` by tearing down that owner's
   media state; the MLS group immediately closes its keys on authenticated removal.

Use `export(label:context:length:)` for purpose- and context-bound current-epoch
secrets. `epochAuthenticator()` returns a 32-byte secret for an explicit independent
comparison. Both outputs require caller-controlled retention and redaction.
`snapshot()` exposes only epoch/counts, queued bytes, pending/closed state and no
participant identifiers or keys. `close()` releases current and tentative epochs,
proposal storage and signing authority. Recovery after close/removal requires a
fresh package owner, fresh external authorization and an authenticated new Welcome;
an existing group replaces a previous member through Remove followed by Add.

Actor calls serialize with no internal suspension or callbacks. Fallible public
operations check cancellation on entry, including after a caller waits for actor
admission. Synchronous cryptography completes within its configured operation
bound once admitted. There is no background task to cancel or network shutdown
to await. `close()` and the nonsecret `snapshot()` remain available for cleanup
and diagnostics.

## Bounds and failure behavior

| Resource | Bound or behavior |
| --- | --- |
| Encoded object/reader | One MiB by default; vector/raw writes check the aggregate budget before allocation |
| Vector encoding | Shortest valid 6-, 14- or 30-bit length; prefix `11`, truncation and overlong lengths rejected |
| Basic identity | 1...1024 bytes in generic wire values; exact eight-byte nonzero snowflake for DAVE members |
| Group ID | 1...255 bytes |
| Extension | At most 64 KiB data; at most 128 unique extension types per list |
| Capabilities | At most 128 unique IDs per category; default proposal/extension types are implicit |
| Signed public objects | Valid P-256 points; signatures bounded to 80 DER bytes |
| Ratchet tree | Explicit maximum members, default 1024; finite power-of-two capacity |
| Group policy | Default 256 members and pending proposals; each configurable in 1...1024 |
| Proposal storage | Default one MiB aggregate; configurable from 1024 to 16777216 bytes |
| Group operation message/export input | Default one MiB; configurable from 1024 to 1048576 bytes |
| Commit/Welcome lists | At most 1024 references or recipients; duplicate references rejected |
| Secret-tree skip policy | Explicit forward-distance/skipped-key budgets; defaults 1024/256 |

Low-level fixed-width writer operations are nonthrowing. Their caller must bound
the number of scalars it emits; every production list has an independent count
limit and enclosing vector/raw writes enforce aggregate object limits. A reader
checks the full input budget before parsing. Decoders consume complete top-level
objects and reject suffix bytes. Unknown values remain unsupported when they
control a mandatory profile choice.

Errors contain bounded categorical failures rather than secrets or remotely
supplied diagnostic strings. Authentication failure must release no candidate
plaintext or candidate epoch state. Ratchet keys are single-use; successful use
consumes the corresponding generation, and replay/stale generations fail. A
failed candidate authentication must not consume valid pending state.

Secrets are represented by caller-owned Swift `Data` values. Secret containers
redact ordinary descriptions. Dropping references and consuming ratchet generations
does not guarantee physical zeroization of every copy, compiler temporary or
cryptographic backend buffer. Avoid logging, reflecting, persisting or copying raw
keys/exporters, and use host secure storage for any application-authorized persistence.
This implementation has not received an independent cryptographic security review.

## Validation evidence

The offline Swift Testing suites cover canonical wire lengths, all truncation
boundaries for representative signed objects, malformed/duplicate/default capability
values, invalid P-256 points, identity/source/group/index binding, expired and
full-range lifetimes, tampered signatures/MACs/HPKE, queue and counter bounds,
tree hashes and update paths, Welcome authentication and epoch transitions.
Policy/ownership tests also cover cancellation before actor admission, failed
Welcome recovery without consumption, single-use packages, bounded proposal
storage without eviction, trusted participant/revocation fences, and replacing
a closed member with a fresh externally authorized package.

Independent MLS working-group vectors are pinned under
[the MLS test fixtures](../Tests/DiscordMLSTests/Fixtures/KEY-PACKAGE-PROVENANCE.md).
Eight published suite-2 KeyPackages verify both their leaf and package signatures;
four public GroupContext fixtures verify independent field extraction and exact
serialization. Additional pinned vectors exercise labeled crypto, key schedule,
secret tree, tree arithmetic, tree validation and TreeKEM. Each fixture's provenance
records its source and qualification boundary. Historical expiry is disabled only
for the historical fixture checks; authenticity remains required.

Synthetic local peers and published vectors do not establish interoperability
with a live Discord voice deployment, an independent complete MLS client, all
supported platforms or all deployment minima. External crypto review, complete
complete DAVE-client interoperability, approved Discord smoke tests, device qualification and
ten-minute hardware duplex remain release gates. Protocol component support does
not make those gates pass implicitly.

Run root `swift build` and `swift test` after changes. Media/voice integration
changes additionally build and run the offline VoiceBot example and preserve its
independent graph. No validation here requires Discord credentials or live requests.
The [Phase 12B validation record](Parity/phase12b-validation.json) retains the
host, check totals, fixture fingerprints and remaining qualification gates.
