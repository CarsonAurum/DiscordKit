# Part 0 coverage and completion gates

Verified **2026-10-15**, on macOS arm64 with Swift **6.4**. This is a discovery and
feasibility baseline. **The complete Part 0 gate is still open**: other-host runtime
qualification, full semantic inventory review and missing upstream contracts cannot
be established by local tests. No Discord integration or full API parity is claimed.

## Discovery baseline

The committed inventory has **18,137 records from 280 source groups**, with
**zero unclassified discovered IDs**, **zero implemented support records**, and
**18,137 records pending semantic review**. Repeated documentation/specification
representations and reference sections are included; these are not counts of unique
Discord operations. Every record is independently addressable and linked to pinned
source membership, provenance, explicit status and an access/protocol condition.

| Discovered kind | Records |
|---|---:|
| Pages, sections and unrecognized table rows | 4,759 |
| Endpoint definitions/examples | 776 |
| Named model/callback definitions | 1,147 |
| Fields/static values | 8,412 |
| Enum values | 1,732 |
| Events | 347 |
| SDK methods/commands | 772 |
| Permissions / intents | 52 / 24 |
| Opcodes / close codes | 42 / 45 |
| Protocol-state sections | 29 |

Discovery includes all 204 official MDX source files at the pinned documentation
revision, the documentation index, both official preview specification files, and
SDK source groups with method/definition membership. The separate contract map has
**718 method/event/capability rows** and **302 enum/callback/static definitions**;
**89 distinct missing-contract blockers** are retained. It classifies local work,
public wire candidates and unproven equivalents separately. Neither mapping a
candidate nor extracting a schema changes implementation status.

## Executed checks

| Check | Result and practical limit |
|---|---|
| `swift build` | Passed for the existing runtime and explicit nonisolated default. No production dependencies added. |
| `swift test` | Passed, 1 existing empty scaffold. This does not establish Discord behavior coverage. |
| `swift test --package-path Tools/DiscordKitTools` | Passed, 35 Swift Testing test methods / 300 parameterized executions. Covers classification vocabularies, real dates, malformed/missing/null/wrong JSON, source metadata, duplicate and lost/wrong-source IDs, evidence and whitespace regressions. |
| Python standard-library extraction tests | Passed, 10 tests. Covers nested/inline schemas, large integers, routes, guide-only templates, unversioned OAuth URLs, independent protocol versions, permissions/intents/events, code-fence handling, SDK overloads/enum metadata and deterministic output. |
| `inventory validate --repository .` | Passed: exact source discovery membership and metadata; no network or source mutation. Does not authenticate upstream bytes or perform general JSON Schema validation. |
| Snapshot acquisition verification | All 204 MDX files matched Git blob hashes in the pinned, nontruncated official Git tree. Source SHA-256 values retained. |
| Inventory reproduction | Repeated harvesting from those snapshots and the committed SDK map produces byte-identical catalogs. |
| Platform fixture | Passed, 3 Swift Testing test methods / 7 cases: actual local HTTP, fully verified TLS, trust/hostname rejection, WebSocket upgrade/frame and empty/binary UDP. IPv4 loopback on macOS arm64 only. |
| Voice fixture | Passed, 5 Swift Testing test methods / 10 cases: AES-GCM/ChaCha roundtrip and authentication failure, truncated-tag/nonce rejection, AES block known answer, exact HPKE primitive suite. No DAVE or MLS implementation/interoperability claim. |
| Diff/link review | Whitespace, local Markdown links, JSON syntax and generated/cache exclusion reviewed. |

In the managed workspace, normal Swift compiler caches and sandbox DNS were
unavailable. Successful dependency acquisition and Swift checks used approved host
access. Those initial environment failures are not compatibility or test failures.

## Roadmap completion gates

| Part 0 requirement | State | Evidence or remaining work |
|---|---|---|
| Adopt graph, dependencies, API and concurrency conventions | Recorded | Architecture, concurrency and dependency policy; Swift 6.4/ApproachableConcurrency preserved, explicit `.defaultIsolation(nil)` in each implemented package target. |
| Versioned discovery inventory and change history | Implemented locally | Schema/catalog, 18,137 classified records, source membership validator, append-only history and dated baseline. Definition extraction remains a discovery aid, with pending semantic review explicit. |
| Every discovered ID classified | Structural check passed | All discovered entries are unsupported, with an explicit condition. This does not prove every upstream prose-only contract was discovered or reviewed. |
| Exact schema/access/platform metadata per operation | Open semantic gate | Review each source contract before implementing; generic source prerequisites do not establish individual auth/scopes/permissions. Resolve retained table rows and arbitrary prose or new markup forms. |
| Ambiguity register and protocol blockers | Recorded | Identity Profile response, RPC/device port discrepancy, preview precedence, source-only Activity variants, SDK contracts and commerce access/schema gaps. |
| Every target platform explicitly classified | Recorded | Capability matrix covers macOS, Linux, Windows, iOS, tvOS, watchOS, visionOS, Android, WASI, browser, Embedded and experimental ports. |
| Qualify exact native graph across requested hosts | Open external gate | macOS local transport probe passed; Linux, Windows, Android and Apple-device/minimum-OS runs are not available here. Do not freeze adapter choices or introduce a fallback without this evidence. |
| Verify public voice primitives and isolate owned work | Primitive feasibility recorded | Exact Crypto/CryptoExtras probe, XChaCha/HChaCha and truncated-tag gaps, MLS/DAVE/codecs still require owned implementations and conformance vectors. |
| Map every discovered Social/Activity/Commerce operation | Discovery mapping recorded | Method-level source anchors/hashes, public/local/missing-contract categories, prerequisites and concrete required evidence. Source-only and unproven equivalents remain blockers. |
| Entire-platform implementation feasibility resolved | Open upstream gate | Public wire schemas/access/host evidence are still missing for named operations. No native SDK/runtime wrapper or invented private protocol is permitted. |

The next implementation part may build portable values independently. Full Part 0
qualification remains tracked here; passing this repository's tests cannot close
unavailable-host or missing-upstream-contract gates.

## Subsequent transport implementation

Part 2's 2026-10-15 [transport record](changes/2026-10-15-transports.md) adds owned
network adapters and local macOS evidence. It does not change discovery inventory
operation statuses, close the historical semantic-review gate, or qualify unavailable
hosts. Current adapter behavior, limits and outstanding platform gates are recorded
in [Transport](../Transport.md); the Part 0 results above remain historical.

## Part 3 HTTP and early Gateway update (2026-10-16)

The historical counts above describe the Part 0 baseline. Current inventory keeps
all18,137 discovered IDs, with three reviewed written-reference endpoint records:
one supported Gateway discovery and two partial User/Application projections.
Duplicates from preview specifications remain unsupported pending their independent
semantic review; these are not unique-operation or full-platform parity counts.

The root HTTP, read-reuse, model, rate-coordination and Gateway suites cover the
initial runtime slice with virtual time and scripted peers. WebSocket loopback suites
exercise real Foundation/NIO session-aware reconnect and peer codes. The REST-only
example is independently built without running authenticated operations. See
[HTTP policies](../HTTP.md), [Gateway contracts](../Gateway.md), and the
[local load harness](../../Tools/DiscordKitLoadTests/README.md) for numeric budgets
and measured limits. Full event/resource models, durable external coordinators,
other-host sessions and sustained-capacity certification remain open gates.
