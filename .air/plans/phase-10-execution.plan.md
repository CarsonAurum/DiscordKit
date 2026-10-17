# Phase 10 execution

Started 2026-10-17 from clean commit a96048c. Implements the documented portable
local RPC/device slice of Part 10, with real local Unix transport integration.

## Plan and acceptance

1. Verify current official RPC/Certified Devices/OAuth/version/change-log contracts;
   record source fingerprints and separate known contradictions/access gates.
2. Add independent RPC and CertifiedDevices products without remote Gateway/HTTP
   adoption. Preserve task-free construction and injected concrete transports.
3. Implement bounded native discovery names, incremental IPC v1 framing,
   handshake/READY, single-writer request correlation/control traffic, ordered
   subscriptions/events, independent cancellation, explicit reconnect and close.
4. Add every documented command/event name and typed public-contract projections,
   retaining unknown/partial child data and redacting secret-bearing diagnostics.
5. Implement validated prioritized full-device replacement via fixed-loopback HTTP
   and approved legacy WebSocket RPC, with processing metadata/native identities.
6. Add deterministic Swift Testing coverage, actual local Unix simulated-peer
   integration, an independent example, guides and versioned parity/history.
7. Run focused/root builds/tests, tools inventory/generation/parity/Python checks,
   independent examples, method-doc/link/JSON audits and staged diff review. Commit
   the validated scoped changes with a detailed exact message.

## Evidence boundary

No live Discord calls, local installed-client port scan, real credentials or
approval dialog is part of this work. The owned Windows named-pipe provider,
real Discord desktop smoke tests on macOS/Linux/Windows, approved deprecated
WebSocket access, native device enumeration and minimum-OS/device qualification
remain open. Portable Windows candidate names/injected framing are not an owned
Windows I/O implementation. Official port/scope/clear-presence contradictions are
recorded rather than guessed. These gates prevent a whole-platform Phase 10
completion claim; local deterministic implementations are independently usable.

## Final validation

Completed the local implementation and final review on 2026-10-17. Independent
reviews resolved startup-close ownership, stale writer reuse after failure,
documented subscription acknowledgement correlation, reflective redaction,
native device identifier validation and partial-frame storage release.

All final checks passed on macOS arm64 with Swift 6.4. Isolated canonical writable
compiler/SwiftPM caches and `--disable-sandbox` were used. Host loopback access
was used for local adapter and real Unix simulated-peer tests.

- Root `swift build` and `SWIFTNIO_STRICT=1 swift test`: **1,437 tests in 166 suites**
  across 21 target executions, zero failures. This includes 57 new RPC/device/native
  test methods with parameterized variants, all 18 command factories/all 25 event
  projections, bounded framing/correlation/subscription/cancellation/reconnect,
  startup/close ownership, malformed data, numeric fidelity and redacted diagnostics.
- Native Unix simulated-peer integration passed using the production Unix byte
  stream, with handshake/READY, request/control exchange, cancellation and cleanup.
  The peer is local test code, not an installed Discord desktop client.
- Tools package: **93 tests in 7 suites**; tooling Python: **10 tests**. Inventory
  validation, explicit reviewed regeneration, byte-identity check of five generated
  artifacts and parity checks passed: 18,137 discovery IDs, 922 reviewed definitions,
  249 mapped endpoints. Only generated documentation changed; generated runtime
  Swift remains unchanged.
- All five independent examples built: RPCApp, RESTOnly, HTTPApp, GatewayBot,
  OAuthApp. RPCApp selected only Bits/Core/Transport/RPC/CertifiedDevices. Its
  pinned dependency identities/revisions/versions match the root. The new package
  used ignored local mirrors of the already resolved repositories after a network
  fetch stalled. No authenticated example or live desktop operation ran.
- Independent source/doc review, source fingerprints, historical pin preservation,
  268 explicit method/protocol declarations and 44 computed-property documentation
  checks, local Markdown links, parity JSON and whitespace/artifact review passed.

No HTTP/Gateway/cache/load implementation changed, so additional HTTP profiles or
the 30-minute consumer soak were outside this local RPC phase. Real desktop smoke,
Windows named-pipe I/O, approved deprecated WebSocket access, native enumeration,
other-platform/minimum-OS qualification and upstream contradictions remain open.
The committed implementation is the local public-contract slice, not whole-platform
Phase 10 certification.
