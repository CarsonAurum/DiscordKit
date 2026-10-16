# Platform support and qualification

Updated **2026-10-15**. This is the capability baseline, not a claim that
DiscordKit already implements REST, OAuth, Gateway, voice, ingress, or desktop RPC.
The production library implements portable values and transport contracts.
Network transport evidence comes from a separate development fixture, not a
published adapter. Part 1 foundation tests execute on macOS arm64; the other
platforms' qualification gaps below remain open.

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

Keep portable contracts separate from OS adapters. Foundation HTTP and Apple
WebSocket adapters remain candidates; SwiftNIO is the shared native transport
candidate. Only a reproduced unresolved platform gap justifies an owned networking
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
open gate. Part 2 must rerun the conformance suite against real owned adapters.
