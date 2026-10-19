# Add macros to a protocol command

Select authoring syntax separately while keeping runtime response and lifetime ownership.

## Overview

### Begin with the working package

The independently compiled
[DSLCommands example](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/DSLCommands)
contains a minimal `@CommandArguments`/`@SlashCommand` `/ping` handler, its complete
manifest and signed offline execution tests. The root DocC command-module tutorial
displays synchronized copies of that source and its policy/family examples.

Add this package explicitly beside the required root runtime products. Its pinned
SwiftSyntax 604.0.0 compiler plugin generates ordinary Swift declarations. Runtime
products select no plugin or SwiftSyntax. The separate extension package and DSLBot
show macro-free authoring through the same public protocols.

### Declare supported syntax and one response family

`@CommandArguments` requires a nongeneric struct with an explicit supported type
and exactly one `@Option` on every instance field. Computed properties, other
wrappers and inferred types reject. Required `let` fields are supported; defaulted
fields use `var` and the admitted finite expression forms. Metadata uses simple
single-line literal strings, rather than dynamic/raw/multiline spelling.

`@SlashCommand` requires an explicit `Arguments` typealias and an implementation
of `execute(_:arguments:)`. Directly spell one supported immediate, deferred,
modal-opening or manual protocol so the macro can generate the matching factory.
It does not resolve imported protocol refinements. User/message context-menu
macros likewise select one supported typed target family. Autocomplete, exact-ID
components and modal submissions use the public runtime protocols directly.

The runtime still prepares fresh complete input, validates response compatibility
and owns acknowledgement/completion. Typed contexts omit raw responder access;
manual handlers retain it explicitly. Expansion itself starts no work,
registration or I/O.

### Validate generated behavior through real compilation

Macro package tests compare expansion and compiled execution against direct runtime
construction. External positive and negative fixtures verify plugin loading,
diagnostics, unsupported syntax and illegal response contracts. Generated callable
documentation is asserted in expansion fixtures and remains subject to the source
documentation audit. Printed expansion alone does not prove runtime parity.

Use [the macro guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/MacroDSL.md)
for exact syntax restrictions and
[the adoption guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/DSLAdoption.md)
for module reuse, policies, hosts, response modes and deployment ownership. These
checks are local compiler/offline evidence; live Discord and production capacity
remain separately qualified.
