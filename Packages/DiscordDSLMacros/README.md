# DiscordDSLMacros

Part 15C's optional authoring package supplies `@CommandArguments`, `@Option` and
`@SlashCommand`. It generates the existing typed argument schemas and manual
slash-command contributions. The runtime products never depend on this package,
its compiler plugin or SwiftSyntax.

Use Swift 6.4 or newer. The compiler-host dependency is pinned exactly to
[SwiftSyntax 604.0.0](https://github.com/swiftlang/swift-syntax/releases/tag/604.0.0),
the Swift 6.4 release line verified on 2026-10-18. Compiler upgrades require their
own compatibility checks.

For a local checkout, add `.package(path: "../DiscordKit/Packages/DiscordDSLMacros")`
to your consumer manifest and select
`.product(name: "DiscordDSLMacros", package: "DiscordDSLMacros")` alongside the
runtime products your application uses. The package retains its sibling root
checkout dependency; remote standalone publication is not provided in this slice.
Import `DiscordDSLMacros` and the runtime modules used by your declarations.

The [authoring guide](../../Docs/MacroDSL.md) describes supported forms, migration
from handwritten schemas and complete examples. Metadata uses simple single-line
string literals without raw/multiline spelling, escapes or interpolation. Every
instance option needs an explicit type. Required `let` fields are supported;
defaults use `var` initializers containing finite scalar literals, nil or enum
members. The macro retains external codec type spellings and lets Swift check
their conformance. It never resolves imported source files or evaluates defaults.

Construction, expansion and compilation start no tasks, I/O, registration or
handler execution. Explicit schema access performs existing synchronous validation.
Handlers supply an explicit `Arguments` typealias and `execute(_:arguments:)`;
the existing responder still owns manual acknowledgement and completion. Response
policies and application hosting remain Part 15D.

Run from the repository root:

```sh
swift build --package-path Packages/DiscordDSLMacros --explicit-target-dependency-import-check error
swift test --package-path Packages/DiscordDSLMacros
python3 Tools/ci/dsl_compile_fixtures.py --repository .
```

The independent expansion, execution parity and external compiler fixtures are
local authoring evidence. They do not qualify live Discord, platforms or capacity.
