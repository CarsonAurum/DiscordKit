[//]: # "File: Sources/DiscordHTTP/DiscordHTTP.docc/DiscordHTTP.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# ``DiscordHTTP``

Execute typed API v10 REST operations with bounded admission, replay policy and optional read reuse.

## Overview

DiscordHTTP is independently usable without Gateway or a consumer client. Construct operation descriptors without I/O, inject one transport and shared credential authority, and execute only when the caller chooses. The catalog spans messages, channels, guilds, moderation, expressions, discovery, application/user administration, webhooks, interaction responses, monetization, lobbies and profiles.

Start with <doc:RESTClientSetup>, then read <doc:RateLimitsRetriesAndReuse>. The remaining guides map resource families and explain bounded uploads, pagination and partial workflows. The [RESTOnly example](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/RESTOnly) demonstrates complete adapter ownership.

## Topics

### Execution and ownership

- <doc:RESTClientSetup>
- <doc:RateLimitsRetriesAndReuse>
- <doc:UploadsPaginationAndWorkflows>

### Resource catalog

- <doc:MessagingAndChannels>
- <doc:GuildsModerationAndExpressions>
- <doc:DiscoveryAndApplications>
- <doc:WebhooksCommerceAndLobbies>

### API reference

- <doc:APIReference>
