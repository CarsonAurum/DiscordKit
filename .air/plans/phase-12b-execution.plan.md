# Phase 12B execution: cryptographic primitives and MLS

Started 2026-10-17 from clean commit `78d3703` at the user's request to plan,
implement, test and commit Phase 12B. The master roadmap's original completion
requirements remain authoritative; no passing local test constitutes an audit.

## Implementation plan

1. Reverify RFC 9420, its published implementation vectors, RFC 9180, Swift
   Crypto's resolved public APIs and the current DAVE MLS profile. Preserve
   Voice v8, MLS 1.0 and DAVE wire-version distinctions.
2. Add an independently adopted DiscordMLS product over the existing Swift
   Crypto dependency. Implement bounded canonical encodings, basic credentials,
   signed key packages/leaves, P256 HPKE/signatures, key schedule, secret tree,
   ratchet tree, TreeKEM paths and tree/parent authentication.
3. Implement the required DAVE v1 MLS profile: exact external-sender binding,
   authenticated external Add/Remove proposals, cached proposal references,
   signed public commits, tentative commit ownership, Welcome, epoch advancement,
   participant authorization, removal, recovery and explicit cleanup. Other MLS
   profiles and DAVE signaling/media transforms belong to separate scope.
4. Test published independent vectors and malformed/tampered/replayed input;
   exercise multi-member epochs, concurrent commits, proposal revocation,
   capacity limits, cancellation, key-package consumption and failure rollback.
5. Build/test the root, tooling and offline VoiceBot. Review generated parity,
   dependency boundaries, documentation, secret diagnostics and the complete diff.
6. Commit validated work with exact evidence and remaining qualification gates.

## Qualification boundary

Independent cryptographic review of newly owned constructions and protocol state
is required before production support. An agent review, an owned round trip or
published component vectors cannot substitute for this external assessment.
Live Discord/DAVE integration and media sender ratchets remain Parts 12C/12D.

## Validation

Completed 2026-10-18 on macOS 27.0.1 arm64 with Apple Swift 6.4. The required
Phase 12B code categories are implemented. The independently reviewed/audited
production-support gate remains open; neither this implementation status nor
the following results asserts audited completion.

- Root `swift build` passed. The complete `SWIFTNIO_STRICT=1 swift test` run
  passed 1,913 tests in 239 suites across 27 test targets, including 64 MLS tests
  in 11 suites. An additional focused MLS run passed the same 64 tests.
- SwiftPM checks used `--disable-sandbox` and isolated writable compiler caches;
  the host run permits the root suites' local loopback sockets. No Discord
  credentials, authenticated requests, audio devices or live media were used.
- All pinned suite-2 primitive, five-epoch schedule, secret-tree, signed-package,
  context, tree-validation and TreeKEM cases passed. Four independent no-PSK
  passive Welcome fixtures verified the lower-layer composition. Generic fixtures
  deliberately do not establish Discord-profile or live complete-client admission.
- The offline VoiceBot package built and ran its two-member MLS exchange and
  existing media/codec/transport checks. Its dependency selection preserves the
  independent voice graph; package requirements and resolved pins are unchanged.
- DiscordKitTools passed 93 tests in 7 suites; its Python scripts passed 173 tests.
  Inventory validation, explicit `generate --write`, subsequent `generate --check`
  and parity validation passed. Inventory remains 18,137 entries / 280 pinned
  sources / zero unclassified entries; all seven newly mapped voice MLS sections
  are recorded as partial, with production and integration gates retained.
- Reviewed the source/test changes, generated artifacts, method documentation,
  fixture provenance, secret diagnostics, dependency boundaries, JSON syntax,
  local documentation links and whitespace. Final staging excludes build output,
  credentials and unrelated files.

The retained machine-readable evidence is
[phase12b-validation.json](../../Docs/Parity/phase12b-validation.json). External
review, minimum-OS/other-platform execution and complete-client interoperability
remain unverified. DAVE media/signaling and supervised voice remain 12C/12D.
