# ``DiscordModels``

Decode presence-aware Discord resources and construct operation-specific validated payloads.

## Overview

DiscordModels contains resource snapshots, unknown-preserving discriminators, Gateway payloads and request values. It owns no HTTP client, socket, cache or credential lifetime. Response projections retain original fields without treating partial child resources as complete state; request types validate the subset legal for a particular operation.

Follow <doc:ReadingResources> for decoding and <doc:ConstructingPayloads> for messages, components and other writes. Browse <doc:APIReference> for each type's declaration and members.

## Topics

### Working with resources

- <doc:ReadingResources>
- <doc:ConstructingPayloads>

### API reference

- <doc:APIReference>
