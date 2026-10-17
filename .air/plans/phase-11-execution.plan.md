# Phase 11 execution

Started 2026-10-17 from the completed Phase 10 local RPC/device implementation.
Implements the independently adopted Activity browser protocol and Swift consumer
slice of Part 11; approved Discord browser/mobile host qualification remains a
separate completion gate.

## Plan and acceptance

1. Verify current official Activity architecture, Embedded App SDK reference,
   networking, OAuth, entitlement and change-log contracts. Pin the official SDK
   source revision as protocol/schema evidence without importing its npm graph.
2. Add independent Activities values, typed command/event catalog and bounded
   transport-neutral Swift client without HTTP/Gateway/OAuth dependencies.
3. Author a zero-runtime-dependency browser bridge with explicit startup,
   host-parameter validation, fixed trusted origin/source, handshake/READY,
   bounded nonce correlation, ordered events, cancellation and teardown.
4. Preserve all documented/exported names, source-only schemas and migration
   aliases while recording per-host/scope/terms/preview restrictions. Distinguish
   implemented codecs from exhaustive nested model projection and host availability.
5. Add reference-counted subscriptions, independent deadlines/cancellation,
   unknown-value preservation and explicit bounded network URL mapping helpers.
6. Add an independent ActivityHost consumer with caller-supplied host binding,
   server OAuth exchange and authoritative entitlement verification using Parts 8–9.
   Construction must perform no I/O; browser code must contain no client secrets.
7. Run Swift Testing protocol/catalog suites and Node's built-in simulated-host
   suites, root build/tests, independent consumer build, generation/parity/tooling
   checks and final source/doc/whitespace review. Commit the validated scope with a
   detailed exact message.

## Evidence boundary

An Activity runs inside Discord's authorized iframe/mobile messaging host. A
standalone browser, native WebKit container, simulated postMessage peer or successful
Swift compilation cannot create or qualify that host. Browser/iOS/Android Discord
smoke tests for handshake, auth, participants and purchases/entitlements require
approved application setup and user consent; these remain unrun unless separately
recorded. Swift/browser-Wasm and native UI bindings are injected integration points,
not tested universal adapters. All local tests use synthetic/recorded contract
frames with no live Discord requests, purchases or real credentials.

The source-only Quest/proxy/invite/share commands have published official source
schemas, but no complete reference platform/scope/access matrix. Their codec support
does not establish ordinary application access. The reference marks
ENTITLEMENT_CREATE unavailable during Developer Preview; real delivery remains
host-authoritative. Broader native Social/Commerce and voice/media remain separate.

## Source and tooling review

Official SDK main HEAD was verified on 2026-10-17 at revision
`14264eccbf9e68d5d58c1aadbc7579e003e0dce6` (commit timestamp 2026-05-05,
SDK 2.5.0). The current-source record fingerprints 50 reference/source/API
responses. All 32 overlapping historical SDK source pins match the downloaded
revision exactly; original discovery provenance remains unchanged.

The Activity catalog contains 54 explicit rows: 28 exported command factories,
two subscription controls, four lifecycle methods, the participant alias,
15 events including special ERROR, three explicit network helpers and one
confidential backend code exchange. Each row records codec/test/docs paths,
platform/scope certainty and host qualification. Separate SDK global URL patching,
permission convenience and localized price formatting remain unimplemented;
their feasibility records do not count them as supported Activity methods.

Tooling validation passed on macOS arm64 with Swift 6.4 and isolated writable
compiler/SwiftPM caches plus `--disable-sandbox`: 93 Swift tests in seven tooling
suites and ten Python tests. Explicit reviewed regeneration changed only two
generated documentation artifacts; generated runtime Swift remains unchanged.
The nonwriting byte-identity check passed for all five generated artifacts.
Parity validation passed for 18,137 discovery IDs, 280 original source pins,
928 reviewed definitions and 249 mapped implemented endpoints. The six Phase 11
reviewed groups remain partial, preserving host/access and related-resource gates.
Local Markdown links, all catalog codec/test/docs paths, JSON syntax and whitespace
review passed.

## Final implementation and validation

Delivered the independent Swift Activities product, 28 typed command factories,
72 typed payload projections, 14 dispatch codecs plus special ERROR handling,
the participant migration alias, and a bounded v1 client. Session ownership covers
correlated replies, refcounted subscriptions, independent cancellation/deadlines,
ordered writes/events and bounded close cleanup. The owned browser modules include
an authenticated raw-frame binding, standalone command client and explicit URL,
fetch and WebSocket mapping helpers, with no runtime npm dependencies or global
patches. The ActivityHost example separates browser/client composition from
confidential backend OAuth exchange and authoritative entitlement verification.

Final local validation passed on macOS arm64 with Swift 6.4:

- Root `swift build` and the complete strict root test run: 1,475 tests in 172
  suites across 22 test targets. The Activity target contributes 36 tests in five
  suites, including a 72-case typed response matrix.
- Node simulated-host/network/example tests: 36 passed, with no skipped tests;
  the browser example also passed JavaScript syntax checking.
- Independent ActivityHost Swift tests: three tests in one suite, including
  parameterized purchase-hint cases and backend policy verification.
- All six independent example packages built: ActivityHost, OAuthApp, RESTOnly,
  HTTPApp, GatewayBot and RPCApp. No authenticated calls were made.
- The final nonwriting generation and parity checks passed after implementation
  review. JSON, local links, method documentation and whitespace were audited.

The root adapter tests used approved host loopback access because the managed
sandbox cannot bind their local sockets. Writable compiler and SwiftPM caches
used canonical paths to avoid duplicate module-cache identities. These are local
validation environment requirements, not additional platform qualification.

Review added regression coverage for blocked-writer teardown, pre-cancelled
subscription release, invalid subscription names without state mutation, optional
ERROR messages and generated empty results, strict READY optional-user shapes,
permission BigInt conversion, unsafe JavaScript integer admission, and the actual
example's simulated-host authentication flow. The explicitly listed approved
Discord browser/mobile, native binding and real purchase gates remain open.
