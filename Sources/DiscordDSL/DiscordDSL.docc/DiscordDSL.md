# ``DiscordDSL``

Compose finite Swift modules into a deterministic, bounded declaration description.

## Overview

Part 15A provides synchronous structural authoring over Core and Models.
``BotModule`` and ``BotBuilder`` compose ordered definitions; ``DefinitionPlan``
validates explicit identities, supported metadata kinds, host capabilities and
finite structural/text budgets. An immutable ``DefinitionDescription`` records
modules, declarations, source coordinates and accounting for offline comparison.

``RawDefinitionContribution`` is an inert metadata escape hatch. Applications may
supply typed ``DefinitionContribution`` leaves and custom ``BotDefinition``
composites without changing a central case list. Typed leaves are retained for
explicit downstream compilation, while collection never invokes their execution
methods. A custom composite uses ``DefinitionCollector`` admission before expanding
its children and propagates errors.

Owned construction and compilation start no tasks, subscriptions, sockets, device
work, persistence or command registration. User-supplied synchronous builders,
bodies and metadata getters must terminate and remain free of side effects;
arbitrary Swift is not sandboxed. Structural bounds govern admitted compilation
state rather than temporary allocations in caller code.

This milestone adds no new Discord endpoint, event, permission, intent or wire
schema support. Separately adopted `DiscordCommandDSL` adds typed arguments and
command lowering, typed responses and signed HTTP applications over this foundation.
The separate macro package remains downstream. Part 15E adds ``MessageContent`` with
safe typed mention interpolation; the separately selected CommandDSL adds pure
message/component builders over existing validated Models. Explicit lowering rejects
illegal layouts and limits before transmission; response ownership remains with
Interactions. Part 15G adds ``InvocationPolicy`` and ``InvocationMiddleware`` with
finite ``PolicyLimits``. Named and operator composition are inert; explicit evaluation
uses caller-owned tasks and cancellation. Command-specific authorization/admission
lives in the separately selected CommandDSL. The separately selected BotDSL supplies
explicit Gateway event/application ownership. Part 15J adds ``ModuleNamespace`` for
reusable local identities and ``DependentModule`` for lazy bodies over explicit
``ModuleDependencies``. Dependencies validate after module admission and before body
creation. ``DefinitionIdentity`` retains exact namespace components without changing
original metadata or wire route names. External extension libraries remain downstream;
local measurements and release-candidate evidence remain separately scoped.
This shared product selects no transport, client, concrete adapter,
compiler plugin or documentation tooling.

## Topics

### Adopt the authoring layer

- <doc:AuthoringModules>

### Modules and structure

- ``BotDefinition``
- ``BotModule``
- ``Module``
- ``BotBuilder``
- ``BotDefinitionGroup``
- ``EmptyBotDefinition``

### External installation and dependencies

- ``ModuleNamespace``
- ``ModuleDependencies``
- ``DependentModule``
- ``DefinitionIdentity``
- ``PlannedNamespace``

### Contributions and compilation

- ``DefinitionContribution``
- ``RawDefinitionContribution``
- ``DefinitionCollector``
- ``DefinitionPlan``
- ``DefinitionDescription``
- ``PlannedModule``
- ``PlannedDeclaration``

### Admission and diagnostics

- ``DefinitionLimits``
- ``DefinitionDiagnostic``
- ``DefinitionSourceLocation``

### Message authoring

- ``MessageContent``
- ``RenderedMessageContent``
- ``MessageContentError``

### Policies and middleware

- ``InvocationPolicy``
- ``InvocationMiddleware``
- ``PolicyLimits``
- ``PolicyCompositionError``

### Complete API reference

- <doc:APIReference>
