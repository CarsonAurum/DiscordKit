# Independent signed key-package vectors

`mlswg-key-packages-suite2.json` retains the eight `key_package` fields whose
`cipher_suite` is 2 from the MLS working group's
[passive-client-welcome.json](https://github.com/mlswg/mls-implementations/blob/2034fe72e0c805a683ba76165660c834f2a8142a/test-vectors/passive-client-welcome.json).
Upstream commit: `2034fe72e0c805a683ba76165660c834f2a8142a`.
Retrieved and verified: 2026-10-17.

Only the public signed MLSMessage bytes are copied. Private test key material,
PSKs and group secrets are not included. Tests parse and exactly re-encode the
objects, verify the signed leaves and signed packages using P-256/SHA-256, and
derive the KeyPackage reference. Expiry policy is disabled for these historical
fixtures; signature and structural validation remain enabled. This evidence
does not establish complete TreeKEM/Welcome/group or Discord DAVE interoperability.

`mlswg-contexts-suite2.json` contains the public GroupContext fields from
`mls_group_info` in zero-based rows 200, 220, 260 and 299 of the same commit's
[messages.json](https://github.com/mlswg/mls-implementations/blob/2034fe72e0c805a683ba76165660c834f2a8142a/test-vectors/messages.json).
Tests verify their separately extracted group ID, epoch, tree hash, transcript
hash and exact serialization. These context-only fixtures make no assertion
about authentication of the enclosing GroupInfo.

The upstream `messages.json` key packages are not used for admission: that file's
suite-2 samples advertise default proposal/extension capabilities prohibited
by RFC 9420 Section 7.2. The implementation rejects that advertisement.
