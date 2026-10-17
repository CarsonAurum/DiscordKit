# Phase 9 execution

Started 2026-10-17 from clean commit f5dfa0a. Implements Part 9 of the full
platform roadmap with independently adopted OAuth, GameServices and Commerce.

## Plan and acceptance

1. Verify official OAuth, provisional-account, publisher, profile/lobby,
   entitlement, Activity purchasing and Social Commerce references and change log.
   Preserve historical discovery pins and record current source fingerprints.
2. Add fixed-origin authorization/installation URLs, state/redirect/issuer handling,
   S256 PKCE, explicit legacy implicit compatibility and form-encoded token
   exchange, refresh, client credentials and revocation. Keep credentials distinct.
3. Coordinate refresh by application and authorization lineage with injected atomic
   storage, expiry/skew, bounded independently cancellable waiters, token replacement,
   invalid-grant handling and publisher-child revocation/expiry semantics.
4. Implement the documented public account/publisher wire operations. Make
   destructive migrations explicit. Preserve missing native/public wire contracts
   as blockers rather than inventing endpoints.
5. Compose existing typed profile/stat and linked-lobby operations, preserving
   full replacement, sparse results and mutation uncertainty.
6. Verify entitlements from server data, expose explicit consumption and injected
   Activity purchase orchestration. Inventory catalog/pricing/gifting/wishlist/
   fulfillment capabilities independently from ordinary entitlement consumption.
7. Add independent OAuth adoption example, guides, dependency/platform records,
   versioned parity and chronological history. Run focused/root tests, builds,
   tooling/inventory/generation/parity, examples and applicable local measurements.
8. Review documentation, method coverage, complete staged diff and generated
   artifacts; commit validated changes with the exact detailed message.

## Evidence boundary

No live Discord calls, real credentials or automatic migration are authorized or
needed for validation. Local macOS deterministic tests do not qualify browser OS UI,
distributed secure storage, physical devices, other hosts, gated publisher access,
Social Commerce fulfillment or fleet capacity. Missing official contracts remain
explicitly blocked. Product construction starts no I/O, sessions or background tasks.

## Implemented result

Completed the public-contract Phase 9 slice on 2026-10-17. Added independently
adopted OAuth, GameServices and Commerce products, their umbrella aliases and an
OAuth-only example. Authorization includes fixed-origin install/consent URLs,
OS-random state/S256 PKCE, exact redirect/issuer checks, one-use callbacks and an
injected main-actor browser adapter. Form grants and revocation preserve secret
categories, redacted diagnostics, typed webhook/guild responses and unsafe-replay
policy.

The bounded refresh actor uses injected atomic secure storage, generation checks,
independently canceled waiters, rotation persistence, expiry, invalid-grant cleanup,
explicit local invalidation and publisher-child cascades. Public provisional,
external-proof, merge/unmerge and publisher-child descriptors remain explicit;
profile stats keep full-replacement semantics and lobby plans preserve sparse
partial outcomes. Entitlement verification checks authoritative ownership and
exact validity instants before explicit consumption. Activity purchasing accepts
a host operation and verifies returned receipts independently on the backend.

Native-only provisional creation, post-create naming and public unmerge remain
blocked on published wire contracts. Publisher hierarchy configuration remains
Discord-managed. Social Commerce catalog, pricing, gifting, wishlist, purchase
management and fulfillment remain schema/access blockers. No wrapper around an
unimplemented native SDK, implicit destructive migration or guessed endpoint
counts as support. Current official source fingerprints, dated parity history,
10 reviewed operation groups and generated review documentation record these
boundaries; historical source pins are preserved.

## Final validation

All final checks passed on macOS arm64 with Swift 6.4. Root and package builds
used isolated writable compiler/SwiftPM caches and `--disable-sandbox`; host
loopback access was used for deterministic adapter and Python peer tests.

- Root `swift build` and `SWIFTNIO_STRICT=1 swift test`: 1,380 tests in 158 suites
  across 19 target executions, zero failures. New suites cover OAuth security,
  form/status/error contracts, bounded concurrent refresh/storage transitions,
  account descriptors, full-replacement/sparse conveniences and entitlement
  ownership/expiry/consumption.
- `swift test --package-path Tools/DiscordKitTools`: 93 tests in 7 suites.
- Explicit `DiscordKitTools generate --write --repository .`, reviewed output,
  then inventory validation, `generate --check` and parity check: passed; all
  five generated artifacts match byte-for-byte and runtime generated Swift is
  unchanged.
- `python3 -m unittest discover -s Tools/DiscordKitTools/scripts -p 'test_*.py'`:
  10 tests passed. Load-harness Python peer tests: 12 tests passed.
- `swift test --package-path Tools/DiscordKitLoadTests`: 28 tests in 4 suites.
- Release HTTP load harness: all six normal/burst profiles passed at logical
  served-user cohorts of 100, 10,000 and 1,000,000. Shutdown returned active,
  queued, coalesced-flight and cache-entry counts to zero. Exact executable/source
  provenance and reports are committed under `Baselines/Part9`. These profiles
  exercise shared HTTP policy rather than token refresh or live users.
- Independent `swift build --package-path` examples: OAuthApp, RESTOnly, HTTPApp
  and GatewayBot passed. OAuthApp's selected build excludes Gateway, Client,
  Cache, Commands, Interactions, GameServices, Commerce and concrete adapters.
  Locked dependencies match the root; no authenticated example was run.
- Method-documentation audit, relative documentation links, parity JSON parsing,
  independent source review and staged whitespace/artifact review: passed.

The final review required only documentation precision and whitespace cleanup
after the complete source suite. No consumer/cache/event implementation changed, so a new 30-minute consumer
soak was outside this phase. Local tests do not establish live OAuth consent, OS
browser behavior, secure distributed storage, approved publisher/native SDK access,
Commerce fulfillment, other-platform/device support or fleet capacity.
