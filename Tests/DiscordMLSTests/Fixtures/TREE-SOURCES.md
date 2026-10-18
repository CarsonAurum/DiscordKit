# Ratchet-tree and TreeKEM vectors

Retrieved from the public [MLS working-group implementation vectors](https://github.com/mlswg/mls-implementations/tree/main/test-vectors)
on 2026-10-18. The source corpus is independently generated; expected cryptographic
bytes were preserved, rather than computed with DiscordKit. JSON was compacted,
and suite-specific inputs were restricted to ciphersuite 2. No production network
or Discord connection is made by these tests.

The [upstream vector descriptions](https://github.com/mlswg/mls-implementations/blob/main/test-vectors.md)
define the assertions. Protocol references are [RFC 9420 sections 7.4–7.9 and
Appendix C](https://www.rfc-editor.org/rfc/rfc9420.html#section-7.4), plus
[RFC 9180 section 7.1.3](https://www.rfc-editor.org/rfc/rfc9180.html#section-7.1.3)
for P-256 deterministic key derivation. These known-answer checks are local
interoperability evidence and do not constitute a security audit.

| File | Preserved scope | Upstream Git blob SHA-1 | Upstream download SHA-256 |
| --- | --- | --- | --- |
| tree-math.json | All 10 perfect-tree sizes | 5c4ba4774ca08d2d64b22c1a44091b10e045590b | 27f04891f56106593b74b674445f01b845e173953770c084deb2f8cf5592e2fc |
| tree-validation.json | All 14 suite-2 trees | b521ed9a1a187ebb8150815b7e8cd0a6db08642a | b66a432d93b520623f0640835ed43b9dfc95e116b8be081d81581d7c11e67a37 |
| treekem.json | All 11 suite-2 trees and all update paths | fb787119a086d7e31c33b33ec51ea72ab1fe151a | d8bbdf78394797f21db7476fd286af6830ebcb18d2e3b2c839fecd4eb11056f8 |

The tree-validation cases include unmerged leaves, internal/trailing blanks and
parent-hash chains that skip blank ancestors. TreeKEM tests verify every receiver
in every published suite-2 update, the exact parent and tree hashes, path secrets,
derived public keys and commit secrets. Sender generation is checked separately
against receiver agreement and failure cases, because ECDSA and HPKE use fresh
backend randomness.

The suite-2 `transcript-hashes.json` entry is embedded in MLSMessagesTests rather
than copied as a separate resource. It checks AuthenticatedContent serialization,
the confirmed/interim transcript digests and the confirmation MAC. Upstream blob:
`a1512433e7a31e19757af723869869fc37988303`; retrieved-file SHA-256:
`58046b58fbd98519b4e60953a105f550e4b427e2b140ea67dedcb751260eecb8`.

Each TreeKEM vector specifies its complete HPKE GroupContext epoch directly; the
test does not increment that epoch. The updated tree hash and unchanged confirmed
transcript hash are used as directed by the upstream description.

Attribution: the [MLS working group repository and its contributors](https://github.com/mlswg/mls-implementations)
publish these interoperability vectors. DiscordKit's local filtering and JSON
formatting do not change the expected cryptographic values.

## Passive Welcome composition

`passive-welcome-suite2-no-psk.json` retains all four entries with
`cipher_suite == 2` and an empty `external_psks` array from
[passive-client-welcome.json at the pinned revision](https://github.com/mlswg/mls-implementations/blob/2034fe72e0c805a683ba76165660c834f2a8142a/test-vectors/passive-client-welcome.json).
The upstream document contains 56 cases; every selected JSON object is unchanged
apart from compact formatting. Retrieved and verified 2026-10-18.

- Upstream SHA-256: `92ebb04b67b1aca4290965ae363650921842ceebe275bd79a2733414078d849c`.
- Local fixture SHA-256: `b3775078be5aadcbc5f7cabca5d452a2e672364db6f07228b28b12cd60db6fd5`.

These are public test private keys and group secrets, never deployment credentials.
The test authenticates the initial Welcome and expected epoch authenticator for
each entry, including two inline and two separately supplied ratchet trees. Any
later `epochs` data retained in an entry is not exercised by this test. Historical
expiry is disabled; all cryptographic checks remain active. Generic identities and
group extensions deliberately bypass the Discord-only actor admission policy.
This establishes independent lower-layer Welcome-vector agreement, not a live
Discord connection, a complete independent client exchange or an external audit.
