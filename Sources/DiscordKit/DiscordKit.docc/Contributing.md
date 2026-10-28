[//]: # "File: Sources/DiscordKit/DiscordKit.docc/Contributing.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Contribute and verify changes

Keep implementation, API contracts, examples, generated outputs and compatibility records synchronized.

## Overview

### Work in the appropriate product

Inspect the working tree and preserve unrelated changes. Add functionality to its independently adopted product, retain the declared dependency direction and keep development tooling outside consumer libraries. Test support, local peers, probes and load harnesses are separate targets or packages. The [architecture](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Architecture.md), [dependency policy](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Dependencies.md) and [concurrency policy](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Concurrency.md) describe the boundaries.

Use Swift 6.4 or newer, structured concurrency and Swift Testing. Document every explicitly declared callable, including private helpers and tests. Explain parameter ranges/units, return and error behavior, ownership, cancellation, isolation and ordering. New or modified production methods need meaningful deterministic tests through observable callers.

### Validate source changes

```sh
swift build
swift test
```

Add the independent consumer build for the affected surface. Run browser tests for Activity changes, offline VoiceBot for media/voice changes, and the Social example/catalog checks for Social changes. HTTP and Gateway changes also need their relevant local load scenarios. A documentation-only edit needs content/link review; changed documentation tooling also needs its deterministic Python tests and a DocC rebuild.

Root tests use fixtures and local loopback adapters without Discord credentials. Separate [platform](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Feasibility/PlatformTransports.md) and [voice primitive probes](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Feasibility/VoicePrimitives.md) are independently resolved packages; root swift test does not execute them. Update their pinned graphs and evidence only when the affected probe is actually run.

### Maintain reviewed definitions and generated outputs

The development-only DiscordKitTools package validates reviewed inventory and produces deterministic source from the checked-in definitions. Consumer builds neither fetch documentation nor regenerate source.

```sh
swift test --package-path Tools/DiscordKitTools
swift run --package-path Tools/DiscordKitTools DiscordKitTools inventory validate --repository .
swift run --package-path Tools/DiscordKitTools DiscordKitTools generate --check --repository .
swift run --package-path Tools/DiscordKitTools DiscordKitTools parity check --repository .
python3 -m unittest discover -s Tools/DiscordKitTools/scripts -p 'test_*.py'
```

When changing a reviewed definition or generator, explicitly run generate --write, review the generated diff and rerun the nonwriting checks. The [generation guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Generation.md) explains the reviewed schema and ownership. Documentation reference curation is a separate compiler-graph-derived operation described in <doc:BuildingDocumentation>.

### Record upstream changes accurately

Verify relevant API versions, endpoints, events, fields, permissions, intents and limits against current official Discord sources before changing integrations. Keep announcement/effective dates separate from the local implementation date. Preserve chronological parity history and record previous/current behavior, affected symbols, compatibility choices and migration guidance. Unknown dates stay unknown. A future-effective change is distinct from currently active behavior.

The [release tools](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/ReleaseTooling.md) audit product/import isolation, public API baselines, evidence membership and maintenance freshness. Workflow definitions alone do not establish that a platform run passed. Source-compatible symbols do not prove behavioral or binary compatibility; local primitive vectors do not establish independent review or complete-client interoperability.

### Measure the affected workload

Use the [independent load package](https://github.com/CarsonAurum/DiscordKit/tree/main/Tools/DiscordKitLoadTests) and its Python peer tests when changing the harness. Report workload, connections, identities, queue bounds, throughput, tail latency, RSS, accounted bytes and saturation/recovery. Consumer/cache/event changes require the documented fixed-working-set local soak. Keep local measurements distinct from fleet, live-service, hardware and other-platform claims.

### Review the documentation deliverable

Run <doc:BuildingDocumentation>'s reference/snapshot checks, strict conversion and example builds. Inspect rendered tutorials, navigation, symbol pages and resource listings as well as Markdown source. Keep generated build output, credentials and local IDE metadata outside commits. Describe exactly which validation ran and any unavailable qualification in the change review.
