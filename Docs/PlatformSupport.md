# Platform support and qualification

Updated **2026-10-17**. The initial HTTP execution and minimal sharded Gateway
slices are implemented; OAuth flows, voice and desktop RPC remain later work.

Part 7 adds portable consumer/cache/event-delivery code with macOS-local deterministic
tests and separate offline load/soak evidence; see [Client](Client.md). New product
compilation on this host does not qualify another OS, device, minimum deployment
version or persistent background execution. Cache/per-subscriber byte counters and
process RSS measure distinct quantities; no fleet capacity follows from logical users.
The production library now includes portable values, transport contracts and
owned Foundation/NIO/Unix adapters. The Part 0 table below remains historical
feasibility evidence. Part 2 local adapter evidence is recorded separately below;
other platforms' qualification gaps remain open.

## Meaning of the results

- **Compiled** means the specified package graph compiled for that target.
- **Runtime probe passed** means the named local scenarios executed successfully
  on that OS and architecture. It does not establish complete adapter conformance.
- **Not run** means no compilation or runtime result is available. A matching SDK
  being installed is not compilation evidence.
- **Restricted** identifies an OS or host capability boundary independently of
  implementation status. A future unavailable-capability result is not typed parity.

The toolchain minimums below come from the current
[Swift platform table](https://www.swift.org/platform-support/). They do not inherit
the much older minimums in SwiftNIO's README. Individual adapter and UI framework
requirements may raise these baselines when those products are implemented.

## Requested platform matrix

| Platform | Toolchain deployment baseline | Compilation evidence | Runtime evidence | Capability and remaining qualification |
|---|---|---|---|---|
| macOS | 13.0 | Exact transport fixture graph compiled on arm64 with Swift 6.4 and macOS 27 SDK | Local HTTP, trusted HTTPS, rejected trust/hostname, WebSocket upgrade/text echo, and UDP empty/binary echo passed | Server and desktop adapters remain unimplemented. Minimum-OS, x86_64, cancellation, pooling, backpressure, Unix RPC, audio/video, and application lifecycle still need qualification. |
| Linux | Ubuntu 22.04, Debian 12, Fedora 41, Amazon Linux 2023, UBI 9 | Not run | Not run | Candidate NIO POSIX/TLS path; qualify each advertised distribution/architecture and trust-store loading. Ingress/Unix RPC require a reachable listener/desktop host; audio requires a separately supplied device provider. |
| Windows | Windows 10 | Not run | Not run | NIO contains Windows socket/selector code and NIOSSL Windows build definitions. Those are source evidence only. Run the same HTTP/TLS/WebSocket/UDP probes before choosing any owned fallback. Named-pipe RPC and native media remain separate gates. |
| iOS | 16.0 | SDK installed; graph not cross-built | Not run | Foreground HTTP and applicable WebSocket/media/auth adapters are qualification targets. Lifecycle suspension prevents an unconditional persistent Gateway heartbeat promise; test physical-device suspension/recovery and approved background modes. Desktop RPC needs an available local Discord desktop host. |
| tvOS | 16.0 | SDK installed; graph not cross-built | Not run | Qualify foreground HTTP/Gateway and permitted device/media routes. Browser hosting must be capability-checked; do not assume a WebKit view is available. Persistent background execution is not guaranteed. |
| watchOS | 9.0 | SDK installed; graph not cross-built | Not run | Ordinary apps may use high-level HTTP(S). BSD sockets cannot be used for watchOS networking. WebSocket tasks, Network framework TCP/UDP and discovery require an OS-authorized use case, even in foreground. A POSIX NIO socket adapter cannot provide a workaround. Physical-device qualification is mandatory. |
| visionOS | 1.0 | SDK installed; graph not cross-built | Not run | Qualify foreground HTTP/Gateway, lifecycle recovery, permitted native media and applicable browser/auth APIs. SDK availability does not prove device policy, audio routing, or background behavior. |
| Android | Android 9 / API 28 | Not run; no Swift SDK bundle installed | Not run | Requires an exactly matching open-source Swift toolchain/Android Swift SDK plus the Android NDK. Qualify NIO HTTP/TLS/WebSocket/UDP on device/emulator, trust-store handling, app lifecycle, JNI ownership and media/browser adapters. Xcode Swift alone is insufficient. |
| WASI | Matching Swift Wasm SDK and runtime, version to qualify | Not run; no Swift SDK bundle installed | Not run | Pure-value modules are a future qualification target. The fixture's NIOPosix socket bootstrap is excluded on WASI; this native socket graph is not a WASI networking implementation. Host imports and runtime grants need separate adapters. |
| Browser WebAssembly | Matching Swift Wasm SDK plus browser bridge | Not run | Not run | HTTP/WebSocket use browser APIs and their origin/security rules; raw UDP, arbitrary TCP, desktop IPC and native audio-device ownership are unavailable through this native graph. Activities require an authorized Discord host and an owned browser bridge. Browser operation is distinct from a WASI command-line runtime. |
| Embedded Swift | Target-specific Embedded Swift toolchain/runtime | Not run | Not run | Experimental language subset and target facilities determine which future pure-value modules can compile. Foundation, Swift Testing, NIO and the ordinary Swift concurrency runtime are not assumed available. No generic network/media/Discord-host claim. |
| Other experimental ports | Target-specific | Not run | Not run | For example, NIO documents experimental OpenBSD support with file-system exclusions. Qualify the actual selected graph and runtime separately before advertising support. |

The watchOS restrictions above are documented in
[Apple TN3135](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos).
Its simulator permits networking that a real watch blocks. Qualify paired-phone
available/unavailable states on physical hardware. Mobile background execution is
bounded by platform lifecycle rules; see
[Apple's background execution guidance](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time).

Android setup requirements are verified against the
[official Android Swift SDK guide](https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html).
The guide currently uses Swift 6.4.1 and NDK r30; obtain and verify the current
matching artifacts when running that gate. See the
[Swift Wasm SDK guide](https://www.swift.org/documentation/articles/wasm-getting-started.html)
for separate ordinary and experimental Embedded SDKs, and
[Embedded Swift documentation](https://docs.swift.org/latest/documentation/embeddedswift/)
for the language subset.

## Adapter decisions

Keep portable contracts separate from OS adapters. Part 0 identified Foundation
HTTP/Apple WebSocket and shared SwiftNIO transport candidates; Part 2 now implements
them with macOS-local evidence below. Other-host selection remains provisional. Only a reproduced unresolved platform gap justifies an owned networking
fallback. No such gap has been established on Windows or Android because those
runtime checks have not run.

Native audio/video, browser hosting, local IPC and Social SDK-only methods are
separate capabilities. Their availability depends on both OS policy and the
required Discord host or documented public protocol. Network compilation cannot
establish any of them. A bot credential must not be embedded in a public mobile or
browser application to compensate for an unavailable backend.

The exact tested graph, commands, results and incomplete gates are recorded in
[the transport feasibility report](Feasibility/PlatformTransports.md). Part 0 has
recorded every requested platform; broad runtime qualification remains an explicit
open gate. Part 2 runs conformance against real owned adapters only on the host
recorded below.

## Part 2 owned adapter qualification

On macOS arm64 / Swift 6.4, `swift build` and all 193 root test methods in 25
suites pass, including a full `SWIFTNIO_STRICT=1` run that rejects work scheduled
after event-loop shutdown. Root suites execute real Foundation HTTP/WebSocket,
NIO HTTP/TLS/WebSocket/UDP/ingress and Unix IPC peers, including shared HTTP
conformance, invalid wire data, TLS trust/hostname rejection, fragmented messages,
control frames, cancellation/deadlines, body ownership, overload and repeated close.
Local IPv6 UDP is tested separately from the initial IPv4 fixture. See
[adapter semantics and remaining gates](Transport.md) for precise limitations.
The app-driven Apple lifecycle owner and fenced shard lease store use deterministic
capability/virtual-clock tests; they do not grant physical-device or fleet support.

The separate [load report](../Tools/DiscordKitLoadTests/README.md) records exact
hardware/workload budgets, request throughput, tail latency, CPU/RSS/live-heap
snapshots and saturation refusals. Served-account counts select bounded active
cohorts and are distinct from real socket counts. No live Discord load is used.
Foundation's internal buffers/pool are platform-owned and have no advertised exact
memory/socket ceiling. No ordinary watchOS WebSocket support is claimed.

Windows named pipes and Android JNI/platform integration remain unimplemented.
Native browser/auth/media adapters are deferred to their feature phases; no empty
products represent them. Linux/Windows/Android, physical Apple devices, minimum-OS,
DNS/IPv6 beyond the local UDP case, network changes during live traffic, blocked
HTTP/WS connect/write, expired TLS certificates and long soak qualification remain
open. This is a tested macOS transport slice, not whole-platform Part 2 certification.

## Part 3 local runtime evidence

The HTTP pipeline and minimal JSON Gateway control use scripted/virtual-time suites,
with real local Foundation/NIO WebSocket close-code/abort regression tests. Models
retain partial typed coverage explicitly. See [HTTP](HTTP.md) and [Gateway](Gateway.md)
for exact contracts and the separate load report for measured workload budgets.
The graph builds on macOS arm64 with Swift 6.4. These checks do not qualify live
Discord behavior, physical-device background execution, other OS hosts, minimum OS,
a full dispatch/resource catalog, or a durable distributed coordinator.

## Part 6 local catalog and request evidence

Phase 6 extends the same JSON v10 Gateway actors with the written dispatch/command
catalog, intent/capability values, opcode admission and bounded request completion.
Deterministic model/request tests complement the existing lifecycle and local
adapter suites. The [Gateway guide](Gateway.md) and [execution record](../.air/plans/phase-6-execution.plan.md)
record exact supported behavior and validation. Named dispatch coverage does not
qualify every nested resource field, live Discord behavior, new hosts/devices,
distributed storage adapters or sustained runtime capacity. Platform support and
the open transport gates above are unchanged.

## Part 8 local interaction evidence

[Interactions and Commands](Interactions.md) add signed ingress, response lifecycle,
command routing/reconciliation and durable webhook-event admission contracts.
Deterministic macOS arm64/Swift 6.4 tests use real Ed25519 signatures, virtual clocks,
scripted HTTP responses and injected durable admission. Display-only component embeds
and common Open Graph metadata have bounded encoding tests, without a remote preview
rendering claim. The independent [HTTPApp](../Examples/HTTPApp/README.md) builds with
Commands/Interactions/HTTP and NIOTransport; the selected graph contains no Gateway,
Client, Cache or umbrella facade. The executable was not run with Discord credentials.

Only the `Crypto` product from Swift Crypto 5.0.1 is selected. Darwin uses CryptoKit;
other platforms compile conditional bundled native implementations, which were not
exercised on this host. See the [dependency audit](Dependencies.md#part-8-signed-ingress-addition).
No live Discord delivery, other OS, minimum deployment version, physical device,
cross-process durable-store adapter or fleet throughput/memory result follows from
these checks. Existing adapter and background-execution restrictions remain open.
