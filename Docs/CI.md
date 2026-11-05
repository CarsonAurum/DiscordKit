<!--
File: Docs/CI.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Continuous validation and platform qualification

The repository defines offline validation, optional platform qualification and
upstream-maintenance workflows. A workflow definition does not establish that a
hosted runner, self-hosted machine, protected environment or Discord account has
been configured or executed. Review actual artifacts before changing support claims.

## Offline validation

[Offline validation](../.github/workflows/ci.yml) runs on push, pull request and
manual dispatch with read-only repository permissions and no Discord secrets.
Separate macOS 26 and Ubuntu 24.04 jobs use Swift 6.4.1, build/test the root, test
independent tooling/load packages and Python helpers, run browser-bridge tests,
validate documentation/inventory/generation/parity, audit manifest/import isolation,
validate release records and build independent consumers. Credential-bearing
examples are built only; explicit offline modes use synthetic peers and payloads.
Consumers keep independent manifests and import checks while sharing one sequential
SwiftPM scratch directory to reuse compiled dependencies. Each desktop job allows
up to 120 minutes. The macOS job retains `setup-swift@v3`, Node 24, its existing
build/test commands, public API comparisons and DocC conversion. Fixture helpers
enforce committed dependency pins on both hosts; their optional job limit is
applied explicitly only by the Ubuntu runner.

The observed Ubuntu failure occurred before compilation: the signing-key import
reported `gpg: no valid OpenPGP data found`. The Ubuntu job now uses the official
`swift:6.4.1-noble` container, pinned to multi-architecture manifest digest
`sha256:6304481cf2717966b7ba175162e397ea2f2cc3161909f2b2a5cf40036079a0f7`.
This supplies the release compiler and Ubuntu runtime dependencies without a
per-run Swiftly bootstrap or signing-key download. Node 24 is installed separately.

[The Ubuntu runner](../Tools/ci/linux_ci.py) checks Ubuntu 24.04, the exact Swift
version, a native Linux target and required executables, recording compiler,
target, memory and disk evidence. Every Swift build/test/run uses two compiler
jobs and `--force-resolved-versions`, including separate authoring/tooling graphs,
consumers, external fixtures and optimized builds. Missing or stale committed
resolution fails instead of silently updating dependencies. Root, authoring,
tooling, benchmarks, audit, consumers and release stages execute sequentially;
optimized root/macro/extension compilation also runs on pull requests.

Each command has a finite timeout, streams output to a log and records progress
and its result under `.build/linux-ci`. Timeout/interruption cleanup terminates
the command's process group, including compiler/plugin descendants. The workflow
always attempts to upload these logs and host evidence, including after failures.
Only successful non-pull-request runs package the clean Git revision as a SwiftPM
source archive with checksums and compiler/host metadata. This artifact contains
source, not precompiled libraries, and does not publish a release.

For a local reproduction, use a Docker-compatible Linux runtime and an ordinary
Git checkout. Run from the repository root. This adds Node 24 to the same Swift
image, mounts the checkout read-only, then copies it into the container without
macOS SwiftPM caches. The default runner executes every stage, including optimized
compilation, and leaves source packaging to the workflow:

```sh
docker build --platform linux/amd64 --tag discordkit-ubuntu-ci - <<'DOCKERFILE'
FROM node:24-bookworm-slim AS node
FROM swift:6.4.1-noble@sha256:6304481cf2717966b7ba175162e397ea2f2cc3161909f2b2a5cf40036079a0f7
COPY --from=node /usr/local/bin/node /usr/local/bin/node
DOCKERFILE

docker run --rm --platform linux/amd64 \
  --mount "type=bind,source=$PWD,target=/source,readonly" \
  --workdir /workspace discordkit-ubuntu-ci bash -lc '
    set -euo pipefail
    tar -C /source --exclude=.build --exclude=.swiftpm --exclude=.air -cf - . | tar --no-same-owner -xf -
    python3 Tools/ci/linux_ci.py
  '
```

To retain local logs before the disposable container exits, copy `.build/linux-ci`
to a mounted output directory or omit `--rm` and use `docker cp` afterward. Select
one gate with, for example, `--stage authoring`; set `--jobs 1` to lower compiler
concurrency. Every selected stage still performs preflight. Cold runs need network
access to pull images and fetch the committed SwiftPM dependencies; offline refers
to the Discord workload, not an air-gapped dependency bootstrap. On Apple silicon,
the example's amd64 container may run under emulation and is not native arm64
qualification. The editing host had no available Linux container runtime, so this
repair's local helper checks do not establish a completed Ubuntu build. Review a
successful native Linux run and its artifacts before changing platform claims.

The maintenance freshness failure observed during this repair is a separate
semantic-review gate. The Ubuntu build changes do not waive that gate or advance
the maintenance ledger; a maintainer must complete the review described below.

Checks cover typed arguments, command-family routing, response ownership,
message/mention safety, policies, bounded Gateway dispatch, supervised bot cleanup
and external module adoption. Separate macro tests compile expansions and external
positive/negative fixtures, including Sendable and dependency checks. Runtime
products never select SwiftSyntax or compiler plugins. Independent extension
libraries receive their own graph, public API and DocC checks.

The benchmark package has independent Swift/Python tests and a small paired
runtime smoke matrix. Full runtime/compiler measurements use explicit local
commands and are compared only with matching hardware, toolchain and workload.
API checks compare fresh compiler output to the applicable reviewed root, macro
and extension baselines; changing an existing baseline requires compatibility
review. None of these checks establishes publication or production capacity.

The runtime API compatibility candidate is 0.20.0. Encoder injection adds the
`OpusPCMEncoding` contract, packet construction and timing diagnostics, and changes
the Voice initializers and error cases. These changes require an explicit pre-1.0
minor increment under the conservative source API policy. CI compares fresh graphs
against every retained baseline through 0.19.0; it does not replace the reviewed
0.19.0 baseline or its historical release evidence. The candidate version records
compatibility intent and makes no publication claim. The independently versioned
macro and extension comparisons remain at 0.15.0.

The macOS 26 hosted label selects an arm64 host; the initial baseline is scoped to
arm64 macOS 13 module availability. If a runner architecture or platform scope
changes, the comparison must fail and receive review rather than resetting the
baseline silently. Compiler/SDK changes can also produce conservative differences.
The committed baselines were emitted locally with Apple Swift 6.4;
hosted CI requests Swift 6.4.1. A workflow definition does not demonstrate that
these toolchains emit identical signatures. Review actual same-version comparison
results before accepting hosted compatibility; do not regenerate a baseline to
hide compiler-driven differences.
The macOS job emits public symbol graphs, compares the named platform API baseline,
and converts every owned public library's DocC archive with warnings as errors,
diagnostic analysis and experimental coverage. Each module receives its own primary
and extension graphs. Every product has authored guides and curated individual
type pages. The umbrella catalog supplies the package contents, learning paths,
twelve step-by-step tutorials and application recipes. Nonwriting checks reject
drift in compiler-derived type/member navigation and tutorial example snapshots.
The converter resolves cross-product links through local archive metadata and
merges all products into one `DiscordKitLibrary.doccarchive` navigator.
Archives and API evidence are downloadable workflow artifacts. The job publishes
artifacts only; it does not deploy documentation or publish a package/tag.
DocC public coverage cannot prove private declaration presence or accurate semantics.

A separate Apple job installs Swift 6.4.1, resolves the root's pinned SwiftLog checkout, then uses installed
Xcode SDKs to compile Logging, DiscordLogging, DiscordLogHandlers and Bits/Core/Transport/
Media/ApplePlatform in dependency order at package minima for macOS, iOS, tvOS, watchOS,
visionOS and their applicable simulators. The eight modules produce 72 emissions
across nine destinations, with source hashes including upstream Logging and its resolved revision. The Logging
emission uses its upstream concurrency settings; owned modules use the root settings.
`compile_apple.py` accepts `--scratch-path`, `--cache-path` and `--disable-sandbox`
for managed hosts and inherits the caller's environment. `--skip-resolve` uses an
existing checkout offline, requiring its SwiftPM state and Git revision to match
`Package.resolved`; missing sources fail. A missing SDK or compiler error fails the job. These are module emissions,
not a complete graph build, linked app, physical-device test, audio route test or
minimum-OS runtime result. The helper uses `swift` and `swiftc` from the selected
toolchain on `PATH`, and `xcrun` only locates SDKs from the selected Xcode. The compiler
must be Swift 6.4+ and Xcode must provide every named SDK; installation alone is never
recorded as a passed compile.

## Manual Windows and Android qualification

[Platform qualification](../.github/workflows/platform-qualification.yml) has three
independent boolean dispatch inputs. Windows/Android are disabled unless both the
input and repository enable variable are set. Configure trusted self-hosted runners
before dispatching these jobs; they never run untrusted pull-request code.

| Job | Required infrastructure | Scope on a successful actual run |
| --- | --- | --- |
| Windows | Labels `self-hosted`, `Windows`, `X64`, `discordkit-swift64`; installed Swift 6.4+, SDK, compiler/linker tools; variable `WINDOWS_CI_ENABLED=true` | Root build/tests plus offline CommandsApp tests; real Discord desktop, named-pipe I/O and hardware remain separate |
| Android | Labels `self-hosted`, `Linux`, `X64`, `discordkit-android-swift64`; exactly matching open-source Swift 6.4+ toolchain/Android SDK, NDK r30, adb and explicitly selected arm64 API28+ device/emulator; variables `ANDROID_CI_ENABLED=true`, `ANDROID_SWIFT_SDK`, `ANDROID_SERIAL`; runner environment `ANDROID_NDK_HOME` | Cross-build and execute only CommandsApp with static Swift runtime; no network, JNI app integration, native media or complete-package qualification |

Follow the official [Android Swift setup guide](https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html)
for matched toolchain/SDK/NDK installation. Xcode's Apple Swift alone cannot provide
that cross-compilation environment. The Android helper uses the explicit adb serial,
checks API28, copies only its executable and NDK C++ runtime into a fixed temporary
device directory, runs offline payload validation, then removes that directory.
Any failed command fails qualification. Keep the runner dedicated to this task.

The always-run summary records success, failure or skipped for every dispatched
surface. **Skipped means unverified**, including when an enable variable is unset.
Adding or enabling a job never establishes that its platform passed. Hardware,
physical Apple devices, authorized Discord media/Activities/RPC, independent
cryptographic review and fleet capacity retain their named gates.

## Optional read-only live smoke

The manual `live_rest` input builds RESTOnly, then performs its implemented API v10
current-user/current-application reads. It does not register commands, send messages,
join voice, start Gateway, change server state or guess an unimplemented protocol.
No scheduled or ordinary offline job receives the credential.

Configure the `discord-live-smoke` GitHub environment with your chosen branch/reviewer
protection and a `DISCORD_SMOKE_BOT_TOKEN` secret for a dedicated approved test
application, and variable `DISCORD_SMOKE_APPLICATION_ID` with its expected public ID.
The wrapper requires the exact two-read success line and matching application ID;
RESTOnly's normal process exit on a categorized failure cannot pass qualification.
GitHub environment protection is operator configuration, not something
the workflow can silently create. A missing credential fails; it is not treated as
successful smoke. Only numeric public IDs are printed by RESTOnly; never log tokens.
No live smoke was invoked as part of local validation.

## Weekly official review

[Weekly official upstream review](../.github/workflows/upstream-review.yml) runs each
Monday at 14:00 UTC and on manual dispatch. It fetches only the official Discord
documentation/specification Git repositories, compares their current heads to the
frozen discovery revisions, collects the current official change log, and publishes
exact refs, hashes, patches and a human-review reminder as artifacts and job summary.
Network/fetch failures fail collection. No API account is contacted, no issue/message
is sent, and no production source or verified-on date is changed automatically.

A maintainer reviews written-doc changes alongside stable/preview spec diffs,
classifies affected inventory rows, updates regression tests/docs/append-only history,
and records the actual semantic review and next due date in the maintenance ledger.
Automation does not satisfy that human review by itself. The release maintenance
validator rejects overdue reviews; before publishing, refresh affected source rows
and resolve unclassified entries. Preserve the original frozen discovery pins so
the review artifact remains reproducible and useful over time.
