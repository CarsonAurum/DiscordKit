# Published suite-2 cryptography vectors

Source: the IETF MLS working group's public implementation interoperability repository,
[mlswg/mls-implementations](https://github.com/mlswg/mls-implementations).
Pinned revision: `2034fe72e0c805a683ba76165660c834f2a8142a`.
Retrieved 2026-10-17. These are public test keys, not deployment credentials.

The three `suite2-*.json` case documents retain all upstream cases whose
`cipher_suite` equals `2`, including every original field and expected value.
Only JSON whitespace and case filtering differ. `suite2-provenance.json` gives
immutable source URLs, original-document SHA-256, local-fixture SHA-256 and case
counts. Tests run offline and never regenerate expectations from production code.

- `suite2-crypto-basics.json`: one case for labeled KDF, ratchet KDF, reference
  hash, DER signature verification and a pre-existing independent HPKE ciphertext.
- `suite2-key-schedule.json`: one case containing five chained epochs, named
  epoch branches, deterministic external public keys and exporter outputs.
  Exporter `label` fields are UTF-8 text; their hex-looking characters are literal.
- `suite2-secret-tree.json`: three cases containing 1, 8 and 32 leaves, with
  independent handshake/application keys and nonces at generations 0 and 15,
  plus sender-data KDF expectations.

Retrieval used the host's TLS-validating `/usr/bin/curl --fail --location`.
A maintainer refresh must select a new explicit revision, verify the upstream
changes, retain provenance and inspect all changed expectations. Never replace
these with local seal/open round trips. Such round trips supplement independent
vectors but do not create interoperability evidence.
