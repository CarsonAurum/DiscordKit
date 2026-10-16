# Dependency policy and qualification

Baseline verified: 2026-10-15. The production runtime package currently has **no
external package dependencies**. Separate development probes resolve exact NIO/TLS
and Crypto graphs and have exercised their documented scenarios on macOS arm64.
The candidate list does not establish production adapter support or freeze an
adapter choice; other platforms and full adapter conformance remain unqualified.

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
audit: Crypto/CryptoExtras' complete native-component notices and the
selected binaries' complete attribution requirements remain to be checked before
their production addition or distribution.

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
