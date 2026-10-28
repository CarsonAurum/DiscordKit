<!--
File: Docs/Feasibility/PlatformTransports.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Native transport feasibility

Verified **2026-10-15**. The tested candidate is SwiftNIO **2.104.0**, released
**2026-10-06**, and SwiftNIO SSL **2.37.5**, released **2026-09-17**. These were
the latest official releases when checked: [NIO release](https://github.com/apple/swift-nio/releases/tag/2.104.0),
[SSL release](https://github.com/apple/swift-nio-ssl/releases/tag/2.37.5).

## Exact graph exercised

The isolated development fixture declares exact direct versions and commits its
lockfile. It does not add network dependencies to the production library.

| Package | Resolved version | Commit | Role |
|---|---|---|---|
| apple/swift-nio | 2.104.0 | 6db9d9abd92ad7399b8a564cafbb87d3507245fa | NIOCore, NIOPosix, NIOHTTP1, NIOWebSocket |
| apple/swift-nio-ssl | 2.37.5 | 322f3c2a4a21df31c84ca416bf65ee5e9059e440 | NIOSSL, bundled BoringSSL and shims |
| apple/swift-atomics | 1.3.1 | 0442cb5a3f98ab802acb777929fdb446bda11a34 | NIO atomics dependency |
| apple/swift-collections | 1.7.3 | 35a1edcb8ebd2bfe251d587f0b69e62af28f508c | NIO queue/storage dependency |
| apple/swift-system | 1.8.1 | 869129b7bf4ecc57b97d0193ad29690ca2134750 | Resolved NIO package dependency; its product is not required by these socket probes |

All resolved package families are Apple-origin. BoringSSL is the normally bundled
implementation from the approved Apple SSL package, not a separately selected
dependency. The tagged [NIO manifest](https://github.com/apple/swift-nio/blob/2.104.0/Package.swift)
requires Swift 6.1, Atomics >=1.1.0, Collections >=1.1.0 and System >=1.4.0.
The [SSL manifest](https://github.com/apple/swift-nio-ssl/blob/2.37.5/Package.swift)
also requires Swift 6.1 and NIO >=2.98.0, and records bundled BoringSSL revision
817ab07ebb53da35afea409ab9328f578492832d. Its declared swift-certificates >=1.19.4
dependency belongs to upstream SSL tests; SwiftPM pruned it from this selected
product graph. Adding X509 or other products later requires a fresh graph audit.

## Source evidence and its limits

NIO supplies HTTP/1.1 and WebSocket codecs and native TCP/UDP bootstraps; NIOTLS
contains abstractions rather than a TLS implementation. NIOSSL supplies TLS
client/server handlers using its bundled BoringSSL. These are low-level pieces:
DiscordKit must author pooling, limits, cancellation, retry policies and adapter
ownership. HTTP/2 would require a separately audited Apple package. See the tagged
[NIO overview](https://github.com/apple/swift-nio/blob/2.104.0/README.md) and
[SSL overview](https://github.com/apple/swift-nio-ssl/blob/2.37.5/README.md).

The tagged native selector implementations include
[Windows WSAPoll](https://github.com/apple/swift-nio/blob/2.104.0/Sources/NIOPosix/SelectorWSAPoll.swift)
and [Linux/Android epoll](https://github.com/apple/swift-nio/blob/2.104.0/Sources/NIOPosix/SelectorEpoll.swift).
The SSL manifest includes Windows-specific C/C++ definitions. These sources are
evidence that a shared candidate exists, not evidence that our graph compiled or
ran on those hosts. NIO's README explicitly describes macOS/Linux development
and testing and does not certify this fixture on all requested platforms.

The [native bootstrap source](https://github.com/apple/swift-nio/blob/2.104.0/Sources/NIOPosix/Bootstrap.swift)
excludes native socket bootstraps on WASI. Native socket availability must not be
inferred from the existence of a CNIOWASI portability target. watchOS policy also
prohibits BSD socket networking; see the full
[capability matrix](../PlatformSupport.md).

## Executed host and results

Host: Apple Silicon arm64, Darwin 27.0.0; Swift 6.4
(swiftlang-6.4.0.34.1), Xcode 27.1 (27A9275), macOS SDK 27.0.
The test runner reports Testing Library 2084. Installed Apple SDKs include iOS
27.1 and tvOS/watchOS/visionOS 27.0. `swift sdk list` reports no installed Swift SDK
bundles. Apple SDK availability alone has not been counted as cross-compilation.

The Swift Testing fixture ran **3 tests, 7 cases, 0 failures**:

| Probe | Assertions | Result |
|---|---|---|
| Plain HTTP | Raw GET request produces HTTP 200 and preserves method, path and query in the response | Passed on macOS arm64 |
| Trusted HTTPS | Real client/server TLS handshake with full certificate and hostname verification; same HTTP response | Passed on macOS arm64 |
| Untrusted TLS root | Self-signed peer absent from default trust roots causes TLS handshake failure | Passed on macOS arm64 |
| Wrong TLS hostname | Trusted certificate for localhost rejects wrong.example with hostname-validation error | Passed on macOS arm64 |
| WebSocket | Raw RFC 6455 upgrade returns HTTP 101 and the known accept digest; masked client text receives exact unmasked echo bytes | Passed on macOS arm64 |
| UDP empty datagram | Zero-byte payload remains a datagram and retains the expected remote address | Passed on macOS arm64 |
| UDP binary datagram | Bytes including 0, 128 and 255 return unchanged with the expected remote address | Passed on macOS arm64 |

All sockets bind to 127.0.0.1 on ephemeral ports. No Discord request, live
credential or external service participates. Each case creates its own event loop
and shuts it down after success or failure; deadline closures prevent a broken
local peer from hanging collection. Those deadlines are failure bounds, not sleeps
used to make successful assertions pass. Handler mutation stays on NIO's event
loop, and the async tests await futures without blocking the cooperative executor.

The committed localhost key is intentionally public test data and has no production
identity or authority. The positive case explicitly trusts only its fixture
certificate; the unknown-root case uses normal default trust roots. No TLS test
uses `.none` certificate verification.

## Reproduce

From the repository root:

```sh
swift test --package-path Tests/Fixtures/PlatformProbe --disable-automatic-resolution
swift package --package-path Tests/Fixtures/PlatformProbe show-dependencies --format json
```

On a fresh checkout, run `swift package --package-path Tests/Fixtures/PlatformProbe resolve`
first; retain and review the committed lockfile. Use Swift 6.4 or newer and allow
local loopback sockets. This fixture is not part of the production target graph or
the root `swift test`; CI must invoke it separately on each native host.

No unavailable-host result is inferred from the macOS tests.

## Open qualification gates

1. Execute this exact locked graph on Linux, Windows and Android, retaining OS,
   architecture, toolchain, dependency revisions, trust-store configuration and
   actual runtime output. Windows/Android remain explicit unavailable-host gates;
   no platform fallback is justified yet.
2. Cross-build the appropriate graph for each Apple target, then run permitted
   scenarios on devices. A watch simulator cannot establish watchOS networking
   rights. Qualify a Network-framework/Foundation path where POSIX networking is
   prohibited. Test Android with its matching official SDK/toolchain/NDK.
3. Adapter qualification requires cancellation before/during connect,
   read/write/close, invalid/expired certificates, failed HTTP upgrades, fragmented
   and multiple WebSocket frames, ping/pong/close, half closes, backpressure,
   repeated start/stop, network replacement and resource counts returning to
   baseline. The short probes above do not establish those properties.
4. Qualify IPv6, DNS, redirects/credential stripping, limits, production root-store
   loading, minimum supported OS versions, x86_64 and other advertised CPU
   architectures. The current tests exercise only IPv4 loopback on one host.
5. Keep Foundation, Apple UI/media, Unix IPC, Windows named pipes, browser/WASI and
   Embedded gates separate. They are not represented by this NIO socket fixture.

Adapter choices remain provisional until the relevant platform gates pass. The
recorded scope is complete; cross-platform runtime qualification is still open.
