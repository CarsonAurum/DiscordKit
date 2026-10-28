[//]: # "File: Sources/DiscordKit/DiscordKit.docc/BuildingDocumentation.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Build and maintain the documentation

Generate independent product archives and a combined library archive with strict DocC diagnostics.

## Overview

### Build locally

Use the Swift 6.4 toolchain and DocC supplied by Xcode or your Swift installation:

```sh
swift package dump-symbol-graph --minimum-access-level public
python3 Tools/ci/curate_docc.py --check
python3 Tools/ci/documentation_examples.py
python3 Tools/ci/build_docc.py
```

Use the symbol graph directory printed by SwiftPM if it differs from the helper's default. The helper converts each root public library module, preserving its primary and owned extension graphs. It enables warnings as errors, diagnostic analysis and public documentation coverage. The umbrella catalog resolves cross-product contents links against those archives. DocC then merges them into `.build/documentation/DiscordKitLibrary.doccarchive` with one library navigator. The macro and extension packages emit separate graphs and catalogs; validate those packages explicitly as described in the repository release-tooling guide.

Open the merged archive in Xcode, or preview the umbrella catalog with the installed DocC command and the appropriate symbol graphs. For web hosting, use DocC's static-hosting output and configure the hosting base path for your deployment; generation does not publish or deploy a site.

### Documentation layout

Each product has a catalog alongside its Swift source. The module page curates authored guides and an APIReference article. Reference pages extend the matching symbols and group initializers, cases, properties, methods, nested types and other members while retaining inline declaration documentation. Source comments describe precise parameter, error, concurrency and ownership contracts; guides explain how the pieces compose.

The umbrella catalog contains the package contents, learning paths, application recipes, operational guides, tutorial contents and twelve tutorials. Tutorial code resources mirror the independent examples and selected extension-library source. They use text resource suffixes to keep displayed manifest/example listings separate from compiled target source.

### Update a public API

1. Update the declaration's documentation and meaningful tests with its implementation.
2. Emit fresh public symbol graphs on the same platform/toolchain scope.
3. Run `python3 Tools/ci/curate_docc.py --write` and review the type/member curation diff.
4. Update the relevant task guide, tutorial or example for changed behavior.
5. Run `python3 Tools/ci/documentation_examples.py --write` when example code changes, then review its displayed snapshots.
6. Run the nonwriting checks and strict conversion again.

Reference generation uses compiler-produced ownership/member relationships and unambiguous symbol links. It never fetches upstream documentation or executes during a consumer build. Platform-specific public declarations require graphs from that platform; a macOS-generated reference inventory cannot establish the availability of a conditionally compiled Windows or Android API.

### Validate content as well as syntax

```sh
python3 -m unittest discover -s Tools/ci -p 'test_*.py'
swift run --package-path Tools/DiscordKitTools DiscordKitTools documentation audit --repository .
python3 Tools/DiscordKitTools/scripts/release_check.py graph --repository .
```

Build each affected independent example, run its offline tests, and inspect representative rendered articles, tutorial listings and type pages. DocC validates syntax, resources and symbol links; it does not typecheck arbitrary fenced snippets or prove semantic completeness. Documentation coverage and source-comment presence are separate checks from live-service, device, platform and cryptographic qualification.

See the [DocC documentation](https://www.swift.org/documentation/docc) for authoring directives and the [repository validation guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/CI.md) for the broader pipeline.
