# ``DiscordCommandDSL``

Compile typed command families into existing definitions and routes, with explicit response and HTTP ownership.

## Overview

Part 15B adds handwritten ``CommandArguments`` and ``ArgumentValue`` protocols,
finite typed option schemas and strict invocation-local decoding. A
``ManualSlashCommandHandler`` contributes explicit registration metadata through
``SlashCommand``. ``CommandCompilation`` lowers finite shared modules into
``CompiledCommands`` with existing definitions, exact routes and an explicit
bounded-router factory. ``ExistingSlashCommand`` supports incremental adoption of
validated low-level root slash definitions/routes without adding typed decoding.

Part 15D adds ``SlashCommandHandler`` and ``DeferredSlashCommandHandler`` with
restricted ``CommandContext`` and ``DeferredCommandContext`` snapshots. Immediate
handlers return ``MessageResponse`` for one initial reply. Deferred handlers are
acknowledged before user work and return ``DeferredMessageResponse`` for
edit-original completion. ``ManualSlashCommandHandler`` retains the raw responder.
``CommandApplication`` composes the existing signed HTTP owner and bounded router;
it never registers commands during construction or ordinary serving. Its explicit
``CommandApplication/synchronize(using:deadline:)`` adopts the existing reconciler.

Construction and compilation perform no registration, network work, task startup
or handler execution. Router invocation retains existing interaction response
ownership: typed adapters transmit returned responses; manual handlers explicitly use
their supplied responder. Cancellation and delivery uncertainty propagate without replay.
Partial resolved references remain local observations; no hydration or authorization
is inferred. Schemas preserve missing/null/value distinctions and validate complete
input before constructing one fresh argument value. Schema metadata retains ordered
registrations, explicit default fingerprints, the unknown-option policy and source
coordinates; admitted text bounds cover that metadata. Defaults are author-visible
metadata, while executable captures and their memory size are outside those bounds.

Select this library independently. Existing products and the Core/Models-only shared
DSL retain their adoption graphs. The runtime selects no compiler plugin; optional
macro authoring lives in its separate package. Part 15E adds builder initializers for
``MessageResponse`` and ``DeferredMessageResponse`` with pure ``MessageBuilder`` and
``ComponentBuilder`` authoring. Shared `DiscordDSL.MessageContent` supplies typed
interpolation and explicit mention policy; existing payload validation remains
authoritative.
Part 15F adds ``SlashCommandTree``, ``UserCommand``, ``MessageCommand``,
``AutocompleteCommand``, ``ComponentCommand`` and ``ModalCommand``. Complete arguments,
partial autocomplete and typed modal values retain separate admission contracts.
``CommandFamily`` catalogs account for exact routes, including route-only handlers;
``ExistingCommandFamily`` supports explicit low-level adoption. Family-specific response
protocols retain legal callback kinds and the unique existing responder. Part 15G adds
``CommandPolicies`` after complete input preparation, with ``CommandPolicy`` observations
and injected authorization, ordered shared middleware, ``CommandConcurrencyAuthority``
and explicit denial/error translation. ``CommandConcurrencyLimit`` supplies fixed-count,
fail-fast local admission. Gateway hosts remain later milestones. Local tests do not
qualify live Discord, platforms or capacity.

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

### Commands and compilation

- ``ManualSlashCommandHandler``
- ``SlashCommandHandler``
- ``DeferredSlashCommandHandler``
- ``SlashCommandMetadata``
- ``SlashCommand``
- ``ExistingSlashCommand``
- ``CommandContribution``
- ``CommandCompilation``
- ``CompiledCommands``

### Command families

- ``CommandFamily``
- ``CommandFamilyContribution``
- ``ExistingCommandFamily``
- ``SlashSubcommand``
- ``SlashSubcommandGroup``
- ``SlashCommandTree``
- ``UserCommand``
- ``MessageCommand``
- ``MessageCommandTarget``
- ``AutocompleteCommand``
- ``AutocompleteInput``
- ``AutocompleteResponse``
- ``ComponentCommand``
- ``ComponentInput``
- ``ModalCommand``
- ``ModalSchema``
- ``ModalField``
- ``ModalResponse``
- ``UpdateMessageResponse``

### Response ownership and HTTP applications

- ``CommandContext``
- ``DeferredCommandContext``
- ``MessageResponse``
- ``DeferredMessageResponse``
- ``CommandResponseVisibility``
- ``CommandApplication``
- ``CommandApplicationError``

### Message and component authoring

- ``MessageBuilder``
- ``ComponentBuilder``
- ``Text``
- ``Embed``
- ``Components``
- ``Component``

### Policies and admission

- ``CommandPolicies``
- ``CommandPolicy``
- ``CommandPolicyError``
- ``CommandRejectionResponse``
- ``CommandConcurrencyAuthority``
- ``CommandConcurrencyLimit``

### Bounded diagnostics

- ``ArgumentDiagnostic``
- ``ArgumentValueError``
- ``CommandCompilationDiagnostic``

### Complete API reference

- <doc:APIReference>
