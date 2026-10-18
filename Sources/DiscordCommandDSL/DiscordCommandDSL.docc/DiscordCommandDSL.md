# ``DiscordCommandDSL``

Compile typed argument schemas and manual slash handlers into existing command definitions and routes.

## Overview

Part 15B adds handwritten ``CommandArguments`` and ``ArgumentValue`` protocols,
finite typed option schemas and strict invocation-local decoding. A
``ManualSlashCommandHandler`` contributes explicit registration metadata through
``SlashCommand``. ``CommandCompilation`` lowers finite shared modules into
``CompiledCommands`` with existing definitions, exact routes and an explicit
bounded-router factory. ``ExistingSlashCommand`` supports incremental adoption of
validated low-level root slash definitions/routes without adding typed decoding.

Construction and compilation perform no registration, network work, task startup
or handler execution. Router invocation retains existing interaction response
ownership: handlers explicitly use their supplied responder and honor cancellation.
Partial resolved references remain local observations; no hydration or authorization
is inferred. Schemas preserve missing/null/value distinctions and validate complete
input before constructing one fresh argument value. Schema metadata retains ordered
registrations, explicit default fingerprints, the unknown-option policy and source
coordinates; admitted text bounds cover that metadata. Defaults are author-visible
metadata, while executable captures and their memory size are outside those bounds.

Select this library independently. Existing products and the Core/Models-only shared
DSL retain their adoption graphs. Macros, response builders, subcommands/autocomplete,
other command families, policies and HTTP/Gateway hosts remain later milestones.
Local compilation/tests do not qualify live Discord, platforms, macros or capacity.

## Topics

### Typed arguments

- ``CommandArguments``
- ``CommandArgumentSchema``
- ``ArgumentOption``
- ``AnyArgumentOption``
- ``ArgumentDecoder``
- ``ArgumentDefault``
- ``UnknownArgumentPolicy``
- ``ArgumentValue``
- ``StringArgumentChoice``

### Partial references

- ``UserReference``
- ``ChannelReference``
- ``RoleReference``
- ``MentionableReference``
- ``AttachmentReference``

### Manual commands and compilation

- ``ManualSlashCommandHandler``
- ``SlashCommandMetadata``
- ``SlashCommand``
- ``ExistingSlashCommand``
- ``CommandContribution``
- ``CommandCompilation``
- ``CompiledCommands``

### Bounded diagnostics

- ``ArgumentDiagnostic``
- ``ArgumentValueError``
- ``CommandCompilationDiagnostic``

### Complete API reference

- <doc:APIReference>
