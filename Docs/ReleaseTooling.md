<!--
File: Docs/ReleaseTooling.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Release validation tools

Release tools audit product isolation, source compatibility, documentation,
reviewed protocol records and excluded qualifications. The validation scripts
use the Python standard library and run locally without writing unless an API
snapshot output is requested. The manual publication helper described below
creates release assets, a Git tag and a GitHub release when dispatched.
Consumer builds do not run the tools, fetch documentation or regenerate source.

The current root API candidate is **0.19.0**. Macro and extension packages have
independent baselines. A passed local check establishes its recorded scope; it
does not establish publication, a hosted CI run, platform/runtime qualification,
live Discord interoperability or independent cryptographic approval.

## Manual GitHub releases

The [Release workflow](../.github/workflows/release.yml), named **Release** in
GitHub Actions, packages a selected commit and publishes a GitHub release only
when a maintainer dispatches it. The workflow must first be committed to the
repository's default branch before GitHub offers the manual trigger. Run the
workflow from that default branch; other dispatch branches are rejected.

Supply both required string inputs:

- `version`: canonical `Major.Minor.Build`, for example `1.2.37`. Each component
  is a nonnegative decimal integer without leading zeroes, except `0` itself.
  Omit the `v` prefix and any prerelease or build metadata suffix.
- `commit`: the full 40-character hexadecimal commit SHA to package. Branch
  names, tags and abbreviated SHAs are rejected.

The third component is a manually chosen build number. The workflow does not
increment it, reset it on a major/minor change or impose a monotonic ordering.
Choose the complete version under the existing source API compatibility policy
below; the numbering format does not waive compatibility review or change the
independent macro and extension package baselines.

The target may be any commit present in the repository. Before dispatch, the
exact SHA must already have a completed, successful **Offline
certification** run of [CI](../.github/workflows/ci.yml), triggered by `push` or
`workflow_dispatch`. A pull-request run, a run for another SHA, or documentation
publication does not satisfy this gate. The release workflow checks that existing
run and packages source without rebuilding or rerunning the test suites.

In GitHub, open **Actions > Release > Run workflow**, select the default branch,
and enter the version and full SHA. With GitHub CLI, replace the placeholder
below with the selected full SHA; use the repository's default branch if its name
differs from `main`:

```sh
gh workflow run release.yml --ref main \
  -f version=1.2.37 \
  -f commit='<full-40-character-commit-sha>'
```

See GitHub's [manual workflow instructions](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
for the web, CLI and API entry points. Dispatching this workflow authorizes
publication; it is not a packaging preview.

A successful run creates tag `v1.2.37` at the selected SHA and release title
`DiscordKit 1.2.37`. The release includes:

- `DiscordKit-1.2.37-source.tar.gz`, a platform-neutral SwiftPM source archive
  under one top-level `DiscordKit-1.2.37/` directory. It preserves tracked root
  and nested package files, manifests, committed dependency pins, documentation,
  licenses and attribution notices. Local `.air`, `.build` and `.swiftpm` state
  is excluded. Dependencies are resolved by the consumer from the committed pins;
  the archive contains no precompiled platform binaries.
- A SHA-256 checksum sidecar for the source archive.
- A JSON manifest recording the version, tag, full revision, archive name and
  SHA-256, plus `ciRun` identifying the exact successful certification run.

The preparation job receives only `actions: read` and `contents: read`; the
publication job receives `contents: write`. Reads use the standard `GITHUB_TOKEN`,
which also publishes ordinary targets without an additional repository secret.
[GitHub requires Workflows write permission](https://docs.github.com/en/rest/releases/releases#create-a-release)
when a selected target adds or modifies workflow files relative to the default branch. For those commits, configure the
optional repository secret `RELEASE_TOKEN` with a fine-grained personal access
token granting this repository **Contents: write** and **Workflows: write**. This
token is used only to create the tag and run `gh release create`; CI reads still
use `GITHUB_TOKEN`, so the optional token needs no Actions permission. Repository
rules protecting release tags still apply.

Runs for the same version are serialized and do not cancel an active release.
An existing tag or release causes refusal instead of replacement, even if it
points to the requested commit. The [GitHub CLI release command](https://cli.github.com/manual/gh_release_create)
creates the release, uploads assets and publishes through separate API requests;
an interruption can leave a tag or partial draft. Inspect the failed run and
GitHub's actual tag, release and asset state before deciding how to recover. A
maintainer may explicitly remove an incomplete draft/tag after that inspection
or choose a new version. The workflow performs no destructive cleanup or
automatic retry of an uncertain publication.

The archive, manifest and linked CI run establish the packaged revision and
recorded offline evidence. Existing release reports and historical qualification
records remain unchanged. Publication and archived evidence do not establish
live Discord interoperability, untested platform/runtime behavior or independent
cryptographic approval.

## Dependency and product isolation

```sh
python3 Tools/DiscordKitTools/scripts/release_check.py graph --repository .
```

The audit evaluates root, example, macro, extension and benchmark manifests with
`swift package dump-package` using temporary writable caches. It compares targets,
direct dependencies, products, source roots and resolved package identities/URLs
to the reviewed release policy. Every resolved pin needs an exact revision.

Actual Swift imports are inspected in every conditional compilation branch.
An imported module must be a direct dependency or an allowed system module.
The lexical scan handles comments, strings, interpolation and regex literals;
compilation remains necessary to establish Swift validity. Product closures and
consumer selections must exclude forbidden modules. Test support never enters a
public product. Macro/extension packages remain explicit downstream selections;
runtime products select no compiler plugin, SwiftSyntax or benchmark tooling.

## Source API baselines

Emit fresh compiler graphs and compare them to the reviewed root baseline:

```sh
swift package dump-symbol-graph --minimum-access-level public
python3 Tools/DiscordKitTools/scripts/api_baseline.py snapshot \
  --repository . --symbolgraphs .build/out/symbolgraph \
  --version 0.19.0 --output /tmp/discordkit-current-api.json
python3 Tools/DiscordKitTools/scripts/api_baseline.py check \
  --baseline Docs/Release/api-baseline-0.19.0.json \
  --candidate /tmp/discordkit-current-api.json --version 0.19.0
```

The [0.18.0-to-0.19.0 comparison](Release/publication-api-comparison.json) records
the reviewed pre-1.0 minor increment. Retain the earlier versioned baselines and
reports when validating migration from an older release.

Use the directory printed by SwiftPM if it differs. Compile for the same target,
architecture and deployment scope as the baseline. Preserve older versioned
baselines for compatibility review; record a new baseline only after reviewing
the changed API and semantic version. Do not rewrite a baseline to accept drift.

The macro product has a separate snapshot excluding compiler-plugin internals:

```sh
swift package --package-path Packages/DiscordDSLMacros dump-symbol-graph --minimum-access-level public
python3 Tools/DiscordKitTools/scripts/api_baseline.py snapshot \
  --repository . --authoring-package Packages/DiscordDSLMacros \
  --symbolgraphs Packages/DiscordDSLMacros/.build/out/symbolgraph \
  --version 0.15.0 --output /tmp/discordkit-current-macros-api.json
python3 Tools/DiscordKitTools/scripts/api_baseline.py check \
  --baseline Docs/Release/api-baseline-macros-0.15.0.json \
  --candidate /tmp/discordkit-current-macros-api.json --version 0.15.0
```

Extension libraries use the same separate-package mechanism:

```sh
swift package --package-path Packages/DiscordDSLExtensions dump-symbol-graph --minimum-access-level public
python3 Tools/DiscordKitTools/scripts/api_baseline.py snapshot \
  --repository . --authoring-package Packages/DiscordDSLExtensions \
  --symbolgraphs Packages/DiscordDSLExtensions/.build/out/symbolgraph \
  --version 0.15.0 --output /tmp/discordkit-current-extensions-api.json
python3 Tools/DiscordKitTools/scripts/api_baseline.py check \
  --baseline Docs/Release/api-baseline-extensions-0.15.0.json \
  --candidate /tmp/discordkit-current-extensions-api.json --version 0.15.0
```

Build and test independent packages. Run
`python3 Tools/ci/dsl_extension_fixtures.py --repository .` to verify external
adoption and missing/wrong typed dependencies. Macro compile fixtures check actual
signatures and generated behavior separately from text expansion.

Snapshots normalize graph shards, including external-type extensions, and reject
missing modules, conflicting duplicates and mixed platform scopes. They retain
signatures, defaults, access, constraints, availability and relationships. Source
locations and documentation do not affect signatures.

Removed APIs, changed signatures/availability/constraints, removed relationships,
new protocol requirements and enum cases conservatively require a major version
increment, or a minor increment before 1.0. Other additions require a minor
increment. Identical APIs permit a patch increment or same-version revalidation.
The checker accepts stable three-component versions. Source comparison does not
prove behavioral or binary compatibility. Compiler/SDK changes and other platforms
need separately reviewed compiler-produced evidence.

## Reports and explicit exclusions

```sh
python3 Tools/DiscordKitTools/scripts/release_check.py report --repository . \
  --report Docs/Release/publication-report.json
```

Reports identify candidate version, verification date, protocol versions, required
checks, evidence and supported claims. Each evidence object has a repository-relative
path and exact SHA-256. Missing/changed files, duplicate keys, path traversal and
escaped symlinks reject validation.

A check is `passed` only with scoped evidence. An unavailable check is `unverified`
with a reason and its canonical ID in `excludedClaims`. Every support claim names
passed check IDs and cannot depend on an unavailable check or contradict a global
exclusion. Unknown checks and failed status reject the report. Correct a failed
check or accurately exclude it; changing status does not create successful evidence.
A report with no passed checks can make no support claims. Hashes establish exact
evidence membership, not semantic accuracy, execution or independent attestation.

## Upstream review and dated transitions

```sh
python3 Tools/DiscordKitTools/scripts/release_check.py maintenance --repository . \
  --record Docs/Release/maintenance.json
```

Upstream review must be current, with its next deadline at most seven days after
its recorded date. Source rows bind exact evidence. The read-only maintenance
workflow fetches official material and publishes differences for human review;
it never applies protocol changes automatically or infers review from a hash.

Record upstream announcement/effective dates separately from local support dates.
Unknown upstream dates remain unknown. Dated transition fixtures include preceding
and effective days, with classifications computed from dates. The announced
`2026-11-16` HTTP channel-obfuscation transition has a source-linked fixture and
Swift regression tests. Future-effective behavior remains distinct from active
behavior. Use `--as-of YYYY-MM-DD` only to reproduce an older review; publication
requires current verification, and changing a date does not refresh evidence.

## Validation

```sh
python3 -m unittest discover -s Tools/DiscordKitTools/scripts -p 'test_*.py'
```

Tooling tests cover import isolation, manifests/cycles, consumer selection,
evidence/path safety, excluded claims, source freshness, transition dates,
graph shards and conservative semantic versions. Root Swift, generation, parity,
DocC, examples, browser, load and platform checks retain independent scopes.
See [continuous validation](CI.md) and [release records](Release/README.md).
