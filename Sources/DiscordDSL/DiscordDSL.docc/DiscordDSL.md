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
schema support. Typed commands, macros, message/policy builders and HTTP/Gateway
execution remain later milestones. The product selects no transport, client,
concrete adapter, compiler plugin or documentation tooling.

## Topics

### Modules and structure

- ``BotDefinition``
- ``BotModule``
- ``Module``
- ``BotBuilder``
- ``BotDefinitionGroup``
- ``EmptyBotDefinition``

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

### Complete API reference

- <doc:APIReference>
