# Phase 12C execution: DAVE integration

Started 2026-10-18 from clean commit `38445ca`, at the user's request to plan,
implement, test and commit Phase 12C in full. The master roadmap remains authoritative.

1. Verify the current DAVE whitepaper, Voice v8 documentation and official libdave
   source. Track negotiated DAVE version 1 separately from whitepaper revision 1.1.4.
2. Introduce independently adopted DiscordDAVE with bounded binary opcode parsing,
   trusted external sender/membership admission, MLS coordination, commit selection,
   ready/execute transitions, fresh-package recovery and exact voice-session binding.
3. Implement actor-owned sender counters, MLS-style sender ratchets, truncated GCM
   framing, authenticated clear ranges, replay/verification bounds and timed expiry.
4. Implement codec-aware Opus, VP8, VP9, H264, H265 and AV1 transforms. Transform
   complete reassembled frames; network video packetization is separate Phase 12D/12E.
5. Implement pairwise verification fingerprints/display codes and bounded ephemeral
   verification state, preserving shared identity keys across recovery/media sessions.
6. Exercise membership changes, concurrent commits, invalid Welcome/group recovery,
   stale epochs, downgrade rejection, tamper, replay, expiry and malformed codecs.
7. Build/test the root and offline VoiceBot; run tools/inventory/generation/parity,
   documentation/JSON/dependency checks, review the full diff, and commit.

Independent cryptographic review, complete-client/live Discord interoperability,
device/platform and supervised network/duplex qualification remain explicit release
gates. Local implementation and tests cannot establish those external results.

## Completion and validation (2026-10-18)

All seven planned implementation steps are complete. `DiscordDAVE` owns exact-session
Voice/MLS coordination, ready/execute and recovery, shared signing identity, bounded
sender ratchets/media domains and ephemeral verification. Opus, VP8, VP9, H264, H265
and AV1 complete-frame transforms are implemented and tested, including eight exact
comparisons with unchanged pinned official C++ codec algorithms. No new runtime
dependency or upward Voice/VoiceCrypto-to-MLS/DAVE edge was introduced.

The final root build and complete strict run passed **1,976 tests in 248 suites
across 28 targets**, including **54 DAVE tests in seven suites** and **73 MLS tests
in 13 suites**. Tools passed **93 tests**, Python discovery passed **173 tests**,
and inventory/generation/parity checks passed. The independent VoiceBot built and
ran its synthetic MLS/DAVE/media exchange offline. The initial restricted socket
run was superseded by a passing full host-local run; no Discord service was used.

The [validation record](../../Docs/Parity/phase12c-validation.json) retains exact
counts, environment and qualifications. [DAVE ownership](../../Docs/DAVE.md) and
the [cryptographic review packet](../../Docs/MLSCryptoReview.md) record the normative
opcode-26 library-versus-wire evidence boundary, the known GCM
key-commitment property and pending independent review/interoperability gates.
Phase 12D/12E network/device/provider work and full Part 12 qualification remain open.
