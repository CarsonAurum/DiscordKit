# External macro compilation fixtures

This independent Swift package proves that the compiler loads the authoring plugin
and type-checks its generated members from a consumer package. `ExternalCodec` is a
separate compiled module. `PositiveExternal` imports its custom `ArgumentValue`,
uses public generated argument/handler conformance, enum and optional arguments,
literal and explicit-nil defaults, an explicitly renamed option, the contribution
factory and a real generated-schema decode expression. No runtime reflection or
imported-source resolution is available to the macro.

Run from the repository root:

```sh
python3 Tools/ci/dsl_compile_fixtures.py --repository .
python3 -m unittest discover -s Tools/ci -p 'test_dsl_compile_fixtures.py'
```

The runner selects each target individually with strict dependency-import checking,
one shared scratch directory and a finite per-process timeout. The positive target
must compile first. Every negative target must fail with the selected semantic
compiler diagnostic; an arbitrary nonzero exit, dependency failure, plugin crash
or timeout does not count. Diagnostics are matched by stable semantic fragments,
without depending on toolchain line numbers or a complete exact message. Optional
`--scratch-path`, `--cache-path`, `--swift` and `--timeout` arguments support isolated
CI environments and existing writable caches. The runner disables SwiftPM's nested
sandbox for compiler plugins; surrounding host permissions still apply.

The negative targets cover nonliteral/invalid command metadata, computed, inferred,
unmarked or multiply bound properties, initialized `let` defaults, dynamic or
incompatible defaults, missing codec conformance, non-Sendable captured handler
state, duplicate external option names, unsupported option metadata and a missing
explicit argument alias. These are deliberately invalid Swift consumers, so a
whole-package `swift build` is expected to fail; use the runner.

The separate macro package's Swift Testing suite executes actual generated schemas
and routes against handwritten implementations. This fixture package supplies
external compilation evidence. Neither check claims live Discord qualification,
application hosting, response policies, macro capacity measurements or complete
Phase 15 support.
