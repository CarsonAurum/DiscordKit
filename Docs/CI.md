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
CommandsApp/ActivityHost tests and CommandsApp/VoiceBot/SocialApp offline runs are
explicit. Credential-bearing examples are built only.

The macOS 26 hosted label selects an arm64 host; the initial baseline is scoped to
arm64 macOS 13 module availability. If a runner architecture or platform scope
changes, the comparison must fail and receive review rather than resetting the
baseline silently. Compiler/SDK changes can also produce conservative differences.
The macOS job emits public symbol graphs, compares the named platform API baseline,
and converts every owned public library's DocC archive with warnings as errors,
diagnostic analysis and experimental coverage. Each module receives its own primary
and extension graphs; the umbrella catalog supplies the nine consumer guides.
Archives and API evidence are downloadable workflow artifacts. The job publishes
artifacts only; it does not deploy documentation or publish a package/tag.
DocC public coverage cannot prove private declaration presence or accurate semantics.

A separate Apple job uses installed Xcode SDKs to compile Bits/Core/Transport/Media/
ApplePlatform in dependency order at package minima for macOS, iOS, tvOS, watchOS,
visionOS and their applicable simulators. It emits 45 selected modules and source
hashes. A missing SDK or compiler error fails the job. These are module emissions,
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
