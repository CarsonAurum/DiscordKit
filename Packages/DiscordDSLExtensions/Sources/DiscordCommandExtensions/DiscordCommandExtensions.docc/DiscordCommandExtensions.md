[//]: # "File: Packages/DiscordDSLExtensions/Sources/DiscordCommandExtensions/DiscordCommandExtensions.docc/DiscordCommandExtensions.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# ``DiscordCommandExtensions``

Author and adopt independent command extensions using the public runtime DSL protocols.

## Overview

``UppercaseCode`` implements a bounded custom `ArgumentValue` codec. The reusable
``ExtensionCommands`` module combines its typed slash handler with an exact existing
`CommandDefinition`/`CommandRoute` adapter. ``ExtensionDependencies`` requires the
caller's shared ``ExtensionCounter`` actor and validates immutable configuration
before the dependent module expands its lazy body. ``ExtensionAuthorizationPolicy``
adapts the same actor to the public bounded policy value.

Install the module under an explicit `ModuleNamespace`, compile it using
`CommandCompilation` and apply ``ExtensionCommands/policies(dependencies:)``.
Namespacing qualifies structural identity while preserving command wire names.
Construction and compilation start no tasks, handlers, registration, service calls
or I/O. Invocation retains the existing manual response owner and cancellation.

The selected command extension product excludes Gateway, Client, Cache, concrete
adapters, SwiftSyntax and compiler plugins. Independent signed HTTP and macro-free
Gateway consumers verify local composition; live Discord, platforms and DSL capacity
remain separate qualification gates.

## Topics

### Adopt reusable commands

- <doc:SharingCommandModules>

### Complete public API

- <doc:APIReference>
