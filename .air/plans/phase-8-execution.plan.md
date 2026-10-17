# Phase 8 execution

Started 2026-10-17 from clean commit aa4325a. This implements Part 8 of the full
platform roadmap, preserving independent HTTP-only interaction adoption.

## Plan and acceptance

1. Verify current official interaction, webhook-event, command and component-embed
   contracts, API version and change log; record verification separately from
   unknown upstream introduction dates.
2. Add real Interactions and Commands products with implementations and tests.
   Authenticate exact timestamp plus raw bytes with maintained Ed25519 primitives;
   bound bodies, admission and replay metadata, with configurable retry handling.
3. Normalize HTTP/Gateway interaction contexts and reserve initial acknowledgement
   before suspension. Cover three-second admission, fifteen-minute token expiry,
   defer/reply races, ambiguous outcomes, cancellation, overload and compatible
   early auto-defer using virtual clocks. Gateway delivery responds through HTTP.
4. Reuse validated command payloads through explicit builders, bounded typed routing
   and change-only reconciliation that preserves unmanaged registrations.
5. Implement independently authenticated webhook events with typed/unknown values,
   PING, duplicate-aware admission, durable hook before 204 and retry on failure.
   Add display-only link-preview component embeds and metadata helpers.
6. Build an independent HTTPApp example without Gateway; update architecture,
   dependency audit, parity/history, guides and qualification limits together.
7. Run focused tests, root build and strict tests, tooling/inventory/generation/parity
   checks, independent example builds and affected local load checks. Review the
   complete diff and commit the validated changes with a detailed message.

## Evidence boundary

Local deterministic tests and macOS builds do not establish live Discord delivery,
durable distributed storage, physical-device or other-host qualification, or fleet
capacity. Durable admission and distributed replay/ack coordination remain injected
consumer responsibilities. Results and any remaining gates are recorded below.

## Implemented scope

- Added independent Interactions and Commands products, without adding Gateway,
  Client or Cache to the HTTP-only graph. Swift Crypto 5.0.1 supplies maintained
  Ed25519/SHA-256 primitives; all five root/example/load resolution files agree.
- Added exact-byte signed authentication, bounded ingress/replay/admission and
  receipt-relative response ownership with explicit uncertainty, early defer,
  token expiry and cancellation/deadline cleanup. Gateway contexts use HTTP sinks.
- Added macro-free definitions, bounded exact routing and explicit change-only
  synchronization. Existing IDs use PATCH, new commands use POST, identical
  definitions send zero writes and unmanaged registrations/settings survive.
- Added independently versioned webhook events with durable admission before 204,
  retryable failed/uncertain admission, retained unknowns and partial social data.
  Added display-only component embeds and common Open Graph fallback markup.
- Added the independent HTTPApp example, interaction guide, current source hashes,
  chronological parity entry, six reviewed contracts and sixty-two newly reviewed
  discovery records. Regenerated committed artifacts and preserved historical pins.

## Completed deterministic validation

- Root `swift build` passed. Full `SWIFTNIO_STRICT=1 swift test` passed:
  **1,324 test functions across 148 suites in sixteen target executions**, including
  parameterized cases. No live Discord calls or real credentials were used.
- The final signed-ingress regressions cover late handler response-body cleanup,
  successful ownership transfer, failed response transmission, authenticated handler
  error classification, uppercase hexadecimal and oversized/malformed direct input.
- Fixed a deterministic command-test timeout: cancellation retains already consumed
  provisional quota; the test now advances its ManualClock through the one-second
  window before asserting a subsequent successful read. Production quota behavior
  was preserved.
- DiscordKitTools: **93 test functions / 7 suites**. Load harness: **28 / 4**.
  Python tooling: **10 tests**; Python load peers: **12 tests**. All passed.
- RESTOnly, GatewayBot and HTTPApp independent builds passed without authenticated
  execution. The HTTPApp compiled graph excludes Gateway, Client, Cache and umbrella.
- Inventory validation, nonwriting generation byte-identity and parity checks passed
  after explicit regeneration. All 107 reviewed relative documentation links resolve.
- Six release HTTP profiles and twelve finite cache/broadcast profiles passed all
  configured resource, request-reduction and shutdown invariants. Their evidence
  and measurement boundaries are in
  [Part 8 baselines](../../Tools/DiscordKitLoadTests/Baselines/Part8/README.md).

Managed-sandbox restrictions initially blocked compiler caches, host metadata,
dSYM work or loopback sockets. Validation used isolated writable module/package
caches, `--disable-sandbox` and authorized host access for affected checks. The
successful runs use Swift 6.4 on macOS arm64; no other-host/device, live Discord,
remote durable store, rendered-preview or fleet qualification is claimed.

## Sustained regression result and final review

The required fixed-working-set burst soak completed **1800.006434 seconds**
and **234,603 recovery rounds**, retaining 121 bounded RSS/accounted-byte
checkpoints. Four scopes shared twenty fixed keys each. Peak accounted cache use
was **72,512 bytes** under the **262,144-byte** aggregate cap;
actual process peak RSS was **9,961,472 bytes**. Refresh coalescing remained
exactly eight completed callers per loader, overflow refusals matched the offered
storm, and entries, refreshes, waiters, subscriptions and buffered events all
returned to **zero** after shutdown. Source/executable hashes matched final review.
See the [report](../../Tools/DiscordKitLoadTests/Baselines/Part8/soak-accounts-1000000-1800s-burst.json)
and [provenance](../../Tools/DiscordKitLoadTests/Baselines/Part8/soak-1800s-environment.json).
This is cache/broadcast regression evidence; Phase 8 ingress/durable storage and
live/fleet capacity are outside the measured workload.

Independent review matched all nine Part 8 roadmap items to implementation,
tests and documented boundaries. All 257 audited explicit Swift declarations
have method documentation. The complete staged scope passed whitespace review;
generated output remains byte-identical after regeneration. No required local
validation remains outstanding.
