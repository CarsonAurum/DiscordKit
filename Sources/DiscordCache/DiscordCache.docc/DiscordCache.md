[//]: # "File: Sources/DiscordCache/DiscordCache.docc/DiscordCache.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# ``DiscordCache``

Maintain optional bounded entity projections and calculate permissions from explicit supplied facts.

## Overview

DiscordCache is independent of HTTP, Gateway and DiscordClient. The host supplies observations and explicit loaders; the cache does not start synchronization, discover resources or infer authorization. Scope, completeness, visibility, provenance and finite retention remain part of every read.

Read <doc:ScopedEntityState> to store observations and refresh them deliberately, and <doc:PermissionCalculations> to handle permission results without inventing missing facts.

## Topics

### State and authorization facts

- <doc:ScopedEntityState>
- <doc:PermissionCalculations>

### API reference

- <doc:APIReference>
