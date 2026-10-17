# Dependency policy and qualification

Updated: 2026-10-17. Part 2 adds approved Apple SwiftNIO/TLS dependencies only
to the concrete NIO/Unix adapters. Bits, Core, Transport, DiscordKit and Foundation
products do not import or link NIO. Separate development probes retain their
independent exact graphs. Runtime qualification remains capability/host-specific;
see [owned adapters](Transport.md) and [platform evidence](PlatformSupport.md).

Part 8 adds Swift Crypto only to Interactions, and consequently to Commands and the
umbrella facade. Bits/Core/Transport, Models, HTTP and Foundation transport remain
independent of Crypto. Its selected products and conditional native graph are recorded
[below](#part-8-signed-ingress-addition).

Part 9 additionally selects the existing Swift Crypto product in OAuth for RFC 7636
S256. GameServices depends on OAuth; Commerce depends only on HTTP/Models/Core/Transport.
The locked versions and native/transitive graph remain unchanged. The independent
OAuthApp graph excludes Gateway, Cache, Client, Commands and Interactions. Browser
presentation and encrypted transactional token storage remain application supplied;
no native Social SDK or third-party storage dependency is introduced.

Part 10 adds no package dependency. RPC depends on portable Core/Transport and
CertifiedDevices depends on RPC/Core/Transport. Applications inject an existing
Unix IPC or WebSocket/HTTP adapter; importing either product does not select NIO,
Foundation networking, OAuth, Gateway or the umbrella facade. The independent
RPCApp consumer verifies the portable graph. Native Windows named-pipe I/O,
audio-device enumeration and Discord's distributed SDK remain outside this graph.

Part 11 adds no package or npm runtime dependency. Activities selects only Core
and Transport. The owned browser bridge uses browser APIs and JavaScript built-ins;
Node's built-in runner is development-only. Official Embedded App SDK source is
pinned as protocol/schema evidence, without importing or vendoring its runtime or
transitive packages. Native/WebAssembly Swift-to-browser bindings are injected and
qualified separately. ActivityHost composes backend OAuth/Commerce explicitly.

Part 12 additionally selects the existing **CryptoExtras** product for public
AES block permutation in the experimental truncated-tag adapter. Media is
Foundation-only; VoiceCodecs depends on Media; Voice selects Core/Models/Transport
and those media/crypto products. Existing REST/Gateway/Client/Kit do not select
voice. This is a real native-graph expansion on Apple hosts: CryptoExtras imports
CCryptoBoringSSL, CryptoBoringWrapper, Crypto and SwiftASN1 even where Crypto alone
uses platform CryptoKit. No BoringSSL internal API is called from DiscordKit.
No package version or root resolved pin changes. The official latest release
remains [Crypto 5.0.1](https://github.com/apple/swift-crypto/releases/tag/5.0.1),
published 2026-10-12 and reverified 2026-10-17; its Swift tools 6.2 manifest is
compatible with this package's Swift 6.4 baseline and preserves lower deployment
minima. The `from: "5.0.1"` requirement retains a next-major upper bound.
Resolved Crypto revision is `1c80d3aff53fedc445b60692980cb4f19a618657`; ASN.1
1.7.3 remains `3b6410f7dee09eb33cdd26260c5fd47fda19b0e2`.
The existing Apache-2.0/NOTICE and bundled BoringSSL ISC/OpenSSL attribution terms
apply to this newly selected native graph; preserve upstream component notices.
Full binary redistribution audit and other-host qualification remain open.
Current source/manifest hashes are in [voice sources](Parity/voice-media-current-sources.json).
Phase 12A adds no runtime dependency: its entropy implementation is owned Swift.
An opt-in development verifier compiles separately supplied official libopus source
in temporary storage; no product or normal test build downloads, vendors or links it.
Published AEAD/AES vector tests establish local primitive behavior, not an external
crypto audit or MLS/DAVE interoperability. See [Voice](Voice.md).

The foundational targets use the Swift standard library and Foundation. The internal
test-support clock uses the standard `Synchronization` module's `Mutex` with
explicit newer Apple availability; it does not raise the runtime product minima
or introduce a package dependency. The runtime adapter graph is now independently
resolved and committed in the root lockfile.

## Allowed graph

Allow approved Apple-origin or official Swift-project package families and their
normal maintained transitive and bundled implementations. Review the whole
resolved graph, including native sources and conditional/platform edges. A
permitted Apple package can legitimately ship maintained upstream code; this does
not permit independently introducing an unrelated dependency.

Standard library, Foundation, CryptoKit and system networking are platform
facilities rather than additional third-party packages. Record platform-specific
availability and deployment requirements when relying on them. Do not vendor a
disallowed package into an owned folder or wrap Discord's distributed native SDK
to evade the policy.

Add a dependency only when an implemented target needs it. Documentation,
generation and source-audit tools stay out of public runtime products. Reviewed
official Discord specification/source snapshots are development evidence, not
consumer runtime dependencies. Never fetch them during consumer builds.

## Stable release candidates

The official latest-release pages were checked on 2026-10-15 and resolved to these
stable tags. The table records release availability; selected probe evidence is
recorded separately below. Compatibility, licenses, full transitive revisions and
runtime behavior must be verified for the specific selected products before a
production addition. Publication dates for exercised packages appear in the probe
reports; dates for the other candidates remain unknown here and must be recorded
in their addition's dependency audit.

| Official package | Observed stable tag | Intended use when needed |
| --- | --- | --- |
| [swift-collections](https://github.com/apple/swift-collections/releases/tag/1.7.3) | 1.7.3 | Bounded queues and ordered collections |
| [swift-async-algorithms](https://github.com/apple/swift-async-algorithms/releases/tag/1.1.7) | 1.1.7 | Stable sequence/channel algorithms |
| [swift-http-types](https://github.com/apple/swift-http-types/releases/tag/1.8.0) | 1.8.0 | Shared HTTP value types |
| [swift-log](https://github.com/apple/swift-log/releases/tag/1.16.0) | 1.16.0 | Consumer-configured logging |
| [swift-crypto](https://github.com/apple/swift-crypto/releases/tag/5.0.1) | 5.0.1 | Supported signatures, hashes and AEAD primitives |
| [swift-nio](https://github.com/apple/swift-nio/releases/tag/2.104.0) | 2.104.0 | Owned HTTP, WebSocket, UDP and ingress adapters |
| [swift-nio-ssl](https://github.com/apple/swift-nio-ssl/releases/tag/2.37.5) | 2.37.5 | TLS for qualified NIO adapters |
| [swift-system](https://github.com/apple/swift-system/releases/tag/1.8.1) | 1.8.1 | Low-level system access where required |
| [swift-docc-plugin](https://github.com/swiftlang/swift-docc-plugin/releases/tag/1.5.0) | 1.5.0 | Development-only documentation tooling |
| [swift-syntax](https://github.com/swiftlang/swift-syntax/releases/tag/604.0.0) | 604.0.0 | Toolchain-aligned development-only declaration audits |

Use only stable public APIs. In particular, candidate availability does not
approve an experimental AsyncAlgorithms streaming trait or other unstable API.
SwiftSyntax must align with the compiler/toolchain used by the audit tool.

## Exercised development graphs and licenses

The [transport probe report](Feasibility/PlatformTransports.md) records the exact
locked NIO 2.104.0/NIOSSL 2.37.5 graph, including Atomics 1.3.1, Collections 1.7.3
and System 1.8.1. Its HTTP, TLS trust/hostname checks, WebSocket and UDP scenarios
ran on macOS arm64. The [voice primitive report](Feasibility/VoicePrimitives.md)
records Crypto 5.0.1 and ASN.1 1.7.3, their exact revisions and executed public
AES/ChaCha/HPKE primitive checks. These are isolated development dependencies,
with Apple-origin repository URLs recorded in their committed lockfiles. They
provide no Linux, Windows, Android or device-runtime results and no completed
Discord transport, MLS, DAVE or codec implementation.

License identification was checked against the transport checkouts at their
locked revisions: [NIO](https://github.com/apple/swift-nio/blob/6db9d9abd92ad7399b8a564cafbb87d3507245fa/LICENSE.txt)
and [NIOSSL](https://github.com/apple/swift-nio-ssl/blob/322f3c2a4a21df31c84ca416bf65ee5e9059e440/LICENSE.txt)
use Apache-2.0; Atomics, Collections and System include Apache-2.0 with the Swift
Runtime Library Exception. The pinned
[ASN.1 license](https://github.com/apple/swift-asn1/blob/3b6410f7dee09eb33cdd26260c5fd47fda19b0e2/LICENSE.txt)
is Apache-2.0, as is the pinned
[Crypto license](https://github.com/apple/swift-crypto/blob/1c80d3aff53fedc445b60692980cb4f19a618657/LICENSE.txt).
Crypto's [NOTICE](https://github.com/apple/swift-crypto/blob/1c80d3aff53fedc445b60692980cb4f19a618657/NOTICE.txt)
also directs consumers to component-specific license files. NIO's
[NOTICE](https://github.com/apple/swift-nio/blob/6db9d9abd92ad7399b8a564cafbb87d3507245fa/NOTICE.txt)
also identifies bundled MIT/BSD-3 components; NIOSSL's
[NOTICE](https://github.com/apple/swift-nio-ssl/blob/322f3c2a4a21df31c84ca416bf65ee5e9059e440/NOTICE.txt)
identifies bundled BoringSSL under combined ISC/OpenSSL terms. Preserve the
applicable license and attribution notices when distributing those components.
This identifies reviewed files rather than certifying a complete redistribution
audit: selected binaries' complete native-component attribution requirements remain
to be reviewed for distribution. The Part 8 addition below records the selected
Crypto product; CryptoExtras remains a development-probe dependency only.

## Requirements, resolved pins and provenance

For ordinary runtime libraries, use a compatible lower bound and next-major
upper bound, as recommended by
[SwiftPM's dependency reference](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html).
Do not impose exact manifest requirements merely to make a development run
repeatable; conflicting exact requirements can prevent consumers from resolving
their graphs. Record a narrower constraint and its rationale when compatibility
or a verified defect requires it.

Separately capture **exact stable versions and commit revisions** for feasibility
probes, CI and release audits. A tag name alone is insufficient evidence of which
source was tested. Retain the probe's resolved graph, platform/toolchain versions,
selected package products, conditional dependencies and exact Git revisions in
its evidence. Recheck for a newer suitable stable release before each addition,
and explain why any newer release is excluded.

For each addition/update, record:

1. Official repository/provenance, product/target importing it and concrete need.
2. Selected version range, exact resolved version/revision, upstream release date
   and verification date; mark unavailable dates explicitly unknown.
3. License at that revision, required attribution and bundled native components.
4. Swift tools/language requirements, deployment minima and migration notes.
5. Complete direct/transitive/bundled graph, platform conditions and policy review.
6. Compile and runtime test evidence per advertised capability/platform, plus
   gaps, fallback decisions and consumer product-isolation results.

Repository-level resolution is useful evidence for a development graph; it does
not force downstream consumers to adopt those same pins. Test supported manifest
ranges and consumer product separation independently.

## Feasibility gates

NIO HTTP, TLS, WebSocket and UDP need concrete runtime qualification on Windows
and Android as well as macOS/Linux before adapter selection is frozen. Apple
device and constrained/experimental hosts need their own capability evidence.
Do not preemptively author a second Windows network stack; create a fallback only
for a demonstrated unresolved gap. Compilation alone does not qualify networking.

Swift Crypto availability does not prove DAVE, MLS, XChaCha, truncated tags or
codec support. Establish exact primitive/public-API requirements and official
vectors, then isolate missing owned implementations. A native SDK wrapper, toy
cryptographic substitute or capability stub cannot close these gaps.

Current platform and voice findings, including checks unavailable on the current
host, belong in [platform support](PlatformSupport.md) and the
[parity evidence](Parity/README.md). The baseline includes the macOS development
probe evidence above; it makes no cross-platform adapter, production dependency
qualification or voice interoperability claim.

## Part 2 production adapter addition

Verified official latest stable tags on **2026-10-15**:
[NIO 2.104.0](https://github.com/apple/swift-nio/releases/tag/2.104.0)
(released 2026-10-06) and
[NIOSSL 2.37.5](https://github.com/apple/swift-nio-ssl/releases/tag/2.37.5)
(released 2026-09-17). Root requirements use `from: "2.104.0"` and
`from: "2.37.5"` (next-major upper bounds), preserving consumer resolution.
The lockfile records the exact graph tested, with these revisions:

| Package | Version | Git revision |
| --- | --- | --- |
| swift-nio | 2.104.0 | 6db9d9abd92ad7399b8a564cafbb87d3507245fa |
| swift-nio-ssl | 2.37.5 | 322f3c2a4a21df31c84ca416bf65ee5e9059e440 |
| swift-atomics | 1.3.1 | 0442cb5a3f98ab802acb777929fdb446bda11a34 |
| swift-collections | 1.7.3 | 35a1edcb8ebd2bfe251d587f0b69e62af28f508c |
| swift-system | 1.8.1 | 869129b7bf4ecc57b97d0193ad29690ca2134750 |

`DiscordNIOTransport` imports NIOCore/Posix/HTTP1/WebSocket/ConcurrencyHelpers and
NIOSSL. `DiscordUnixPlatform` imports Core/Posix/ConcurrencyHelpers. Test-only
NIOEmbedded is excluded from runtime products. The graph, license files and
bundled BoringSSL revision match the reviewed feasibility graph above; production
TLS uses full verification with no insecure toggle. NIO and SSL require Swift 6.1,
compatible with root 6.4. Root Apple deployment minima remain unchanged; other
hosts have no inferred qualification. No newer stable tag was shown by the
verified latest-release links. The existing Apache-2.0, Swift Runtime Library
Exception, NIO NOTICE and BoringSSL attribution obligations apply to distribution.
There are no dependency migrations for consumers of the portable products.

Native compiler cache/temp files and loopback tests required approved host access
in the managed workspace. Resolution reused the existing verified local repository
cache for a stalled transitive fetch; no checkout was vendored or substituted
for the official lockfile revisions. The independent load package resolves the
same approved graph and remains outside runtime products.

## Part 3 products (2026-10-16)

Models, HTTP and Gateway introduce no external package dependency. They use existing
Core/Transport, Swift standard concurrency and Foundation JSON/date/URL facilities.
Gateway depends on HTTP only for authenticated discovery; HTTP does not import
Gateway or a concrete adapter. The RESTOnly example selects Foundation transport;
the separate load harness adopts HTTP/Gateway explicitly. Existing approved NIO/TLS
versions remain unchanged. Example resolution is pinned independently and build/test
support is excluded from all runtime products.

## Part 8 signed ingress addition

The official latest stable [Swift Crypto release](https://github.com/apple/swift-crypto/releases/tag/5.0.1)
was verified as **5.0.1 on 2026-10-17**; its upstream publication date is unknown in
this record. The root requirement is `from: "5.0.1"`, allowing compatible releases
below 6.0.0. `DiscordInteractions` selects only `Crypto` for Ed25519 signature
verification and SHA-256 webhook delivery digests. No CryptoExtras or SwiftASN1
product is linked by that selection. Package-level resolution still includes ASN.1
because CryptoExtras declares it; the committed root and HTTPApp lockfiles retain
the exact two new pins:

| Package | Version | Git revision | Selected role |
| --- | --- | --- | --- |
| swift-crypto | 5.0.1 | 1c80d3aff53fedc445b60692980cb4f19a618657 | `Crypto` runtime product |
| swift-asn1 | 1.7.3 | 3b6410f7dee09eb33cdd26260c5fd47fda19b0e2 | Resolved, unselected product dependency |

The pinned [Crypto manifest](https://github.com/apple/swift-crypto/blob/1c80d3aff53fedc445b60692980cb4f19a618657/Package.swift)
requires Swift tools 6.2; ASN.1 requires 6.1, both compatible with the root's 6.4
minimum. Root Apple deployment minima remain unchanged. Darwin's Crypto module
reexports the platform CryptoKit implementation. On Linux, Android, Windows, WASI,
OpenBSD and FreeBSD its selected target conditionally includes CCryptoBoringSSL,
CryptoBoringWrapper, CXKCP and CXKCPShims. The vendored BoringSSL revision is
`0226f30467f540a3f62ef48d453f93927da199b6`; XKCP provenance and notices are
retained in the pinned package's source headers and vendored-source records.
Those edges describe source selection, not compilation or runtime qualification
on those hosts.

The pinned Crypto and ASN.1 top-level licenses are Apache-2.0, linked above.
Crypto's NOTICE and embedded native-source notices also apply to distributions
containing those components; the newer Crypto BoringSSL copy must not inherit
NIOSSL's separate older combined-license description by assumption. The checked
Crypto signing source includes Apache-2.0 and public-domain-origin attribution;
XKCP files carry their own notices. Preserve the applicable exact notices and
review the complete selected binary's attribution on each distributing platform.
The top-level license check is not a complete native redistribution audit.

Real-signature and digest tests run locally on macOS arm64/Swift 6.4. The independent
[HTTPApp](../Examples/HTTPApp/README.md) builds through Interactions/Commands and an
explicit NIO adapter without compiling Gateway, Client, Cache or the umbrella.
REST-only consumers still select HTTP without Crypto or Gateway. No authenticated
example execution, other-host native Crypto build, physical-device result or
voice/MLS interoperability is established by these checks. Existing NIO/TLS pins
are unchanged; see [the interaction guide](Interactions.md) for the implemented scope.
