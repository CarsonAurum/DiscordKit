# Continuous validation and unavailable gates

Phase 14 adds three workflows. Their definitions are committed infrastructure;
local checks do not establish that a hosted runner, self-hosted machine, protected
environment or Discord account has been configured or executed. Review actual
workflow artifacts before upgrading a platform claim.

## Offline certification

[Offline certification](../.github/workflows/ci.yml) runs on push, pull request and
manual dispatch with read-only repository permissions and no Discord secrets.
Hosted macOS 26/Ubuntu 24.04 jobs install Swift 6.4.1, build/test the root, test
tooling/load packages and Python helpers, run browser bridge tests, validate
documentation presence/inventory/generation/parity/Social catalog, audit the actual
manifest/import DAG, validate release/maintenance records, and build every consumer.
CommandsApp/DSLCommands/DSLEvents/DSLBot/ActivityHost/LoggingApp tests and
CommandsApp/DSLCommands/DSLEvents/DSLBot/VoiceBot/SocialApp/LoggingApp offline runs are
explicit. Credential-bearing examples are built only. Integrated SwiftLog adds a
root `0.16.0` API baseline and optional output handlers; macro/extension baselines
remain `0.15.0`. Existing runtime products never select the output library.

Parts 15A and 15B add independently selected `DiscordDSL` and `DiscordCommandDSL`
products and their root tests. CI compares the current root candidate against
the frozen `0.14.0`/`0.15.0` API snapshots and the new `0.16.0` baseline, validates
historical release/maintenance records, and discovers the public DocC modules
from the manifest. The authoring checkpoint covers shared
declarations, typed argument decoding, explicit command lowering and Part 15C's
separate macro authoring package. Part 15D adds typed immediate/deferred/manual
responses and signed HTTP application composition with explicit synchronization.
The independent DSLCommands consumer runs its synthetic signed exchange in explicit
offline mode; listener startup and registration are never part of routine CI.
CI tests compiled macro expansions and external
positive/negative fixtures, including Sendable checks and a cross-module codec.
Part 15E adds safe text/typed-mention, layout and direct-payload-parity root suites,
and the independent DSLCommands exchange now exercises a builder-authored response.
Part 15F adds family routing/input/response and catalog reconciliation regressions,
compiled family macros and external incompatible-response fixtures. Part 15G adds
policy ordering, rejection, cancellation and terminal-ownership tests. Part 15H adds
typed Gateway event compilation, explicit intents, ordered bounded dispatch and the
independent DSLEvents offline consumer. Part 15I adds supervised client/event/interaction
lifecycle tests and the independently compiled DSLBot offline consumer, whose synthetic
host uses no credentials or external sockets. Part 15J tests the separate
`DiscordDSLExtensions` libraries and genuine external positive/negative dependency
compile fixtures. DSLCommands and macro-free DSLBot import reusable command/event
modules through their explicitly selected products; shared actor state, custom
codecs/policies and raw command adoption execute only in their offline modes.
Graph auditing includes the separate package's exact imports and product selections;
its public API and DocC are collected independently from runtime and macro APIs.
Part 15K adds independent benchmark Swift/Python tests and a small paired offline
runtime smoke matrix. Full runtime/compiler measurements are explicit local qualification
commands; compare numerical budgets only on matching hardware, toolchain and workload.
Part 15L preserves `Docs/Release/phase15l-report.json` as authoring checkpoint
evidence and keeps the Phase 14 and 15K reports intact and separately validated.
The semantic logging candidate records current local checks in
[semantic logging validation](Release/semantic-logging-validation.json); the first
[logging validation](Release/logging-validation.json) stays historical. It also checks freshly emitted macro and extension APIs against their
separate `0.15.0` baselines. The root comparison retains the historical `0.14.0`
migration checks, then rejects same-version root API drift against the reviewed
`0.18.0` snapshot. None of these checks replaces running the current source validation or
establishes a passed platform run, publication or production capacity.

The macOS 26 hosted label selects an arm64 host; the initial baseline is scoped to
arm64 macOS 13 module availability. If a runner architecture or platform scope
changes, the comparison must fail and receive review rather than resetting the
baseline silently. Compiler/SDK changes can also produce conservative differences.
The committed Phase 15 baselines were emitted locally with Apple Swift 6.4;
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

A separate Apple job resolves the root's pinned SwiftLog checkout, then uses installed
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
minimum-OS runtime result. The toolchain's Xcode selection must provide Swift 6.4+
and every named SDK; installation alone is never recorded as a passed compile.

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
No live smoke was invoked as part of local Phase 14 validation.

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
