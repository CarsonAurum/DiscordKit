# Command-family authoring

Part 15F extends `DiscordCommandDSL` with slash trees, typed user/message context
menus, partial autocomplete providers, exact component handlers and typed modal
submissions. All families lower into the existing bounded `CommandRouter` and
`CommandReconciler`. Compilation is synchronous and inert. `CommandApplication`
authenticates signed HTTP interactions and owns serving only when explicitly run;
registration requires a separate `synchronize` call.

The independent [DSLCommands consumer](../Examples/DSLCommands/README.md) provides
executable offline examples. Local fixtures exercise the existing API v10 wire
models. They do not qualify live Discord registration, UI rendering, notification
delivery, deployment capacity or other platforms.

## Slash paths and registration

`SlashCommand` remains the root typed adapter. `SlashSubcommand` adapts an existing
immediate, deferred, manual or modal-opening slash handler into one leaf.
`SlashSubcommandGroup` contains leaves; `SlashCommandTree` supplies root metadata and
ordered `.subcommand`/`.group` branches. One tree produces one registration and exact
routes for its leaves. A group cannot contain another group, and a root cannot mix
primitive arguments with subcommands. Existing Models enforce unique sibling names,
25-option limits, localization validation and the aggregate text budget.

Leaf argument schemas are unchanged: complete invocation decoding precedes user
execution or explicit defer. An omitted options collection on a zero-argument leaf
means empty arguments; explicit null, unexpected paths and malformed containers
fail admission. Each invocation creates fresh typed arguments. Subcommand metadata
uses the leaf's name/description/localizations; installation contexts, permissions
and other root registration settings belong on the tree root.

`ExistingSlashCommand` keeps its original root-only contract.
`ExistingCommandFamily` adopts existing complete definitions and exact routes,
including advanced fields already exposed by Models. This adapter performs no typed
decoding. Compilation verifies snapshot agreement, registration coverage and exact
route uniqueness. Registration-only Discord-launched Activity entry points retain
their existing eligibility gates; selecting them does not implement an Activity host.

## Context-menu targets and response ownership

`UserCommandHandler` and `MessageCommandHandler` receive `UserReference` and
`MessageCommandTarget` respectively. Their IDs are exact 64-bit identifiers; resolved
user/member/message projections retain absent/null/partial observations. They never
hydrate resources or infer authorization. A target ID and valid context-menu
envelope are required before user execution. Slash options cannot enter these routes.
`UserCommand` and `MessageCommand` capture validated metadata and immutable behavior.
The optional authoring package supplies `@UserCommand` and `@MessageCommand` metadata
and contribution plumbing; ordinary protocols remain usable without macros.

Immediate context-menu handlers return a `CommandInitialResponse`, supplied by
`MessageResponse` or `ModalResponse`. Deferred user/message handlers explicitly
acknowledge then return `DeferredMessageResponse` for edit-original completion.
Manual protocols retain the original responder. `ModalSlashCommandHandler` opens a
modal immediately with complete typed arguments; it cannot defer first. Typed
contexts expose snapshots without acknowledgement authority. Errors, cancellation,
expiry and indeterminate writes propagate through the existing response owner.

## Partial autocomplete

`AutocompleteCommandHandler` receives a separate `AutocompleteInput` and returns
`AutocompleteResponse<Value>`. Supplied options are partial: required sibling
arguments may be absent, and focused text may not satisfy final invocation bounds.
Full `CommandArguments` construction and defaults never run during autocomplete.
Exactly one declared supported string/integer/number option must be focused.
Unknown, duplicate, null, wrong-kind and malformed options fail before the provider.
Responses admit at most 25 choices with values matching the focused option kind.
Autocomplete has its own exact namespace and only sends a type-8 response.

An `AutocompleteCommand` contribution names the root/path/focused option and its
finite option descriptors. Compilation checks agreement with the actual registration
and rejects missing or orphaned providers. `ArgumentOption` exposes explicit
`autocomplete` metadata; it cannot also declare static choices. Final command
invocation still applies the complete argument schema.

## Components and modal submissions

Component and modal routes match exact custom IDs, never prefixes, regular
expressions or dynamic captures. They have independent namespaces, so the same ID
can identify a component and its submitted modal. Component handlers declare their
expected component kind and receive admitted immutable values and resolved data.
Buttons and select families have different envelope requirements.

Modal handlers declare `ModalValues` with a finite `ModalSchema` of exact
`ModalField<Value>` descriptors. The schema admits the complete tree before invoking
codecs or constructing the invocation-local aggregate. It rejects duplicate IDs,
undeclared field IDs, unknown component kinds, wrong shapes, overlarge text/selections
and malformed or nested containers. Legacy action-row text inputs and current label-wrapped fields remain
explicitly validated. Built-in codecs cover text, radio values, checkboxes and
`ModalSelections` for selects, uploads and checkbox groups. Optional codecs preserve
omission and the documented unselected radio state; resolved resources stay on the
interaction snapshot without hydration.

`ComponentInitialResponse` permits a message, modal or `UpdateMessageResponse`.
`ModalInitialResponse` permits a message or source-message update and cannot open
another modal. Updating a modal's source requires the triggering interaction to
contain a message. Immediate and explicit deferred/manual protocols retain separate
response ownership. Unknown third-party response wrappers are checked against the
legal callback kinds before transmission; custom code remains responsible for its
own effects and cooperative cancellation.

## Explicit synchronization and finite admission

A compiled catalog contains registration definitions independently of route-only
autocomplete/component/modal contributions. Application ID and optional guild ID are
explicit host inputs. Desired `(type, name)` pairs form the managed-name policy:
same-name slash/user/message registrations are distinct, omitted commands stay
unmanaged, and renamed commands do not imply deletion. Localization, permission,
installation/invocation contexts, age restriction and other existing writable fields
retain their omission/null/value semantics. Guild scope rejects global-only fields.
Registration defaults never authorize application work locally.

Only explicit synchronization performs a fresh list with full localizations and
sequential changed managed upserts. An identical catalog sends zero mutations.
Unmanaged registrations survive. Failure exposes `CommandSyncFailure` with its
acknowledged progress and failed index; later writes are not attempted and ambiguous
mutations are not blindly retried. No constructor, compiler or ordinary serve/run
operation registers, deletes or bulk-overwrites commands.

Shared structural limits account for full definition, schema, response-policy and
exact-route metadata. Route count/text admission remains finite and one shared
router supplies the aggregate concurrency bound. Captured user closures and injected
services remain caller-owned; these limits establish no memory or throughput
qualification. Part 15G adds [bounded policies and middleware](CommandPolicies.md).
Part 15I adds [Gateway hosts](BotApplications.md), Part 15K records
[local measurements](DSLBenchmarks.md), and Part 15L supplies complete
[adoption guidance](DSLAdoption.md) and scoped [release records](Release/README.md).
Those records preserve live/platform and production-capacity exclusions.

The reviewed [command reference](https://docs.discord.com/developers/interactions/application-commands),
[interaction reference](https://docs.discord.com/developers/interactions/receiving-and-responding)
and [component reference](https://docs.discord.com/developers/components/reference)
are recorded with [exact source hashes](Release/sources/2026-10-18-phase15f.json).
No new endpoint, intent, permission, model-parity classification or protocol version
is introduced by these authoring adapters.
