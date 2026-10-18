# Phase 13 execution: owned Social providers

Started **2026-10-18** from clean commit `ea5394c`.

1. Refresh the published Social reference, mobile guides, RPC/Activity contracts,
   OAuth and early-access Commerce sources. Reconcile every existing SDK declaration
   and callback with current evidence; signatures alone do not establish a wire protocol.
2. Add independently adopted `DiscordSocial`: an inert actor coordinating explicit
   user consent, host prerequisites, typed narrow providers, finite operation admission,
   deadline/cancellation propagation and stale-session result fencing.
3. Compose real typed HTTP, desktop RPC and Activity operations over existing owned
   clients. Keep bot/backend authority separate from user-consented providers. Add
   bounded local relationship synchronization and local PCM controls without claiming
   SDK-only network calls or a new Social transport.
4. Map every published SDK method/event to tested owned behavior, a qualified partial
   equivalent, or a named unmet projection/protocol/platform/access requirement.
   Keep mobile integration and unavailable Commerce rows visible.
5. Test normal, malformed, overloaded, revoked, cancelled, stale and resync behavior;
   build the independent Social consumer and all affected provider examples. Run root
   build/strict tests, tooling, inventory, generation, parity and browser checks.
6. Review the complete diff, record exact validation and remaining gates, stage only
   phase work, and commit with a detailed message.

## Qualification boundary

The deliverable is an owned public-protocol Social composition and exhaustive gap
accounting. There is no native Discord SDK runtime, reverse-engineered user session,
automatic bot-to-user authority conversion or inferred Commerce protocol. Unpublished
SDK wires, Discord approvals, actual mobile/console hosts, independent crypto review,
live interoperability and device/platform qualifications remain unmet where recorded.
Full entire-platform parity requires those blockers to be resolved upstream and tested.

## Delivery (2026-10-18)

All six implementation/validation steps are complete for the owned public-protocol
release. Root build and **2,107 strict tests in 263 suites across 29 test targets**
pass with approved host-local loopback access. Tooling passes 93 tests; Python passes
185 tests, including 12 Social catalog regressions; the browser bridge passes 36 tests.
The independent Social example builds/runs offline from MainActor and its compiled
20-target graph excludes Gateway/Client/Cache, Voice/MLS/DAVE and concrete adapters.
OAuthApp/RPCApp builds and all three ActivityHost tests pass. Inventory, byte-identical
generation, parity, JSON/link/source-fingerprint and staged hygiene audits pass.

The final catalog retains **743 rows** with **87 named unmet requirements**: 309
narrower partial equivalents, 225 blocked and 209 language/runtime-specific rows.
Current official evidence fingerprints 48 sources. These counts are declarations,
not unique live capabilities or SDK parity. The complete source/test hashes, exact
commands and environment pivots are in
[phase13-validation.json](../../Docs/Parity/phase13-validation.json).

The full entire-platform qualification remains incomplete. Public owned functionality
and exhaustive explicit gap accounting satisfy this release's Phase 13 deliverable;
unpublished SDK/Commerce protocols, missing authorized live projections/host access,
mobile/console/device/platform, live interoperability and production/fleet qualification
remain excluded from support claims. No mocks, local PCM or synthetic peers close
those gates.
