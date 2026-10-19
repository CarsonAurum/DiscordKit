# Author finite modules with explicit dependencies

Build a reusable declaration catalog without starting application work.

## Overview

### Separate declarations, compilation and execution

``BotModule`` supplies an explicit stable ID and a synchronous ``BotBuilder`` body.
Ordinary modules, conditionals and finite loops preserve source order.
``DefinitionPlan`` admits identities, supported kinds/capabilities and finite
count/depth/text limits, then returns an immutable description with retained typed
contributions. Collection invokes no handler or asynchronous service.

Command and event compilers explicitly consume those retained values. An HTTP or
Gateway host then starts execution through existing owners. Construction and
compilation create no tasks, subscriptions, sockets, registrations or persistence.
User builders and validators remain ordinary Swift and must terminate without
side effects; admission cannot preempt arbitrary code or reclaim caller allocations.

### Install reusable identities

``ModuleNamespace`` records exact namespace components separately from each
module/declaration's original ID and metadata. Namespace and local identity limits
share the plan's finite structural budget. A namespace does not rename a Discord
command, component/modal route or event handler. Downstream route/handler duplicate
checks still apply across installations.

``RawDefinitionContribution`` supports local metadata with explicit kind/capability
allowlists. Implement ``DefinitionContribution`` for a typed leaf or ``BotDefinition``
for a custom composite. Custom collection must use ``DefinitionCollector`` admission
and propagate errors; a failed collector cannot produce a successful partial plan.

### Inject actors through a typed contract

``ModuleDependencies`` holds finite immutable configuration and Sendable service
references. ``DependentModule`` admits its installation, synchronously validates
that contract, then creates its body. Invalid dependencies prevent body creation
and produce a bounded diagnostic that omits the original error and dependency text.
Validation checks local configuration; asynchronous service readiness belongs to
an explicitly awaited startup or invocation owner.

Actors retain normal Swift isolation. Reuse the same application-owned actor and
aggregate authorities across modules, await it during execution and keep child
work structured. The DSL performs no ambient lookup or replacement construction.
The independently compiled extension package demonstrates these contracts in
[ExtensionCommands.swift](https://github.com/CarsonAurum/DiscordKit/blob/main/Packages/DiscordDSLExtensions/Sources/DiscordCommandExtensions/ExtensionCommands.swift).

### Keep shared adoption small

This product selects Core and Models only. Shared ``MessageContent`` safely renders
ordinary interpolation with typed mentions; generic ``InvocationPolicy`` and
``InvocationMiddleware`` compose within explicit finite ``PolicyLimits``.
Command-specific response/admission and Gateway ownership live in separate products.
Macro authoring and extension libraries remain downstream package selections.

Follow the repository [adoption guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/DSLAdoption.md)
for independently compiled protocol and macro commands, host choices and tests.
The [design guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/DSLDesign.md)
records ownership and evidence boundaries. Local compilation and metadata limits
establish no live Discord, other-platform or production-capacity qualification.
