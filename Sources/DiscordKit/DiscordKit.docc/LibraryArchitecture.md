# Understand the library architecture

Compose a small product graph around your application's authority and lifecycle needs.

## Overview

### Values, protocols and concrete adapters

The foundations form a directed dependency chain: DiscordBits provides exact arbitrary-width masks; DiscordCore adds identifiers, JSON, presence, errors and credentials; DiscordTransport defines asynchronous I/O contracts. Domain products build on these contracts. Concrete Foundation, NIO, Unix and Apple adapters live in separate products so portable consumers choose their platform integration explicitly.

![Values support protocols, domain services use those protocols, and the application injects concrete adapters and owns their lifecycle.](LibraryArchitecture.svg)

DiscordModels provides wire values independently of transport execution. DiscordHTTP describes and executes typed REST operations without requiring a Gateway connection. DiscordGateway owns the remote event connection and shard lifecycle. DiscordClient optionally composes discovery, shards, service access and cache observation for a consumer application.

### Select the application surface

| Need | Starting product | Additional choices |
| --- | --- | --- |
| Typed REST operations | DiscordHTTP | Models, transport backend, shared rate authority |
| Supervised bot | DiscordClient | Explicit intents, shard authority, optional Cache |
| Signed HTTP interaction handler | DiscordInteractions | Commands, ingress listener, signing public key |
| Reusable typed command modules | DiscordDSL / DiscordCommandDSL | Explicit HTTP host, response contract, optional separate macro package |
| Supervised module bot | DiscordBotDSL | Existing Client, shared services/authorities and explicit intents |
| OAuth account linking | DiscordOAuth | Browser presentation and transactional secure store |
| Game backend or premium access | DiscordGameServices / DiscordCommerce | Backend credentials and server-derived policy |
| Local Discord desktop | DiscordRPC | Injected connector, consent, optional CertifiedDevices |
| Embedded Discord application | DiscordActivities | Authenticated browser bridge and separate backend |
| User-facing provider composition | DiscordSocial | Consent, host capabilities, bounded scoped observations |
| PCM, Opus or voice sessions | DiscordMedia / DiscordVoice | Codecs, transport crypto, optionally MLS and DAVE |

### Keep authority explicit

Share credential rate limits and aggregate resource budgets across clients that use the same identity. One actor in one process cannot coordinate unrelated workers; inject a distributed authority when deploying across processes. Bot guild permissions, user consent, host capability, trusted MLS participant identity and backend entitlement policy remain separate decisions.

Cache observations and browser purchase responses do not authorize access. Missing data does not grant permissions. Unknown protocol values should remain observable and bounded rather than being converted into a known success state.

### Know the dependency boundaries

Shared DSL selects Core/Models only. CommandDSL composes existing command/interaction owners while excluding Gateway/Client/Cache. BotDSL explicitly broadens adoption to the supervised client graph. Runtime products select no macro plugin or SwiftSyntax; extension libraries remain downstream choices. Declaration construction and compilation start no work, and ordinary serving registers no commands. Follow <doc:ModuleApplications> for the complete adoption path.

Cache operates on scoped model projections without importing HTTP or Gateway. RPC and Activities can be adopted without the bot runtime. Voice and VoiceCrypto do not depend on MLS or DAVE; DAVE composes their interfaces with MLS. An Activity's confidential OAuth code exchange and entitlement verification belong in a separately deployed backend.

The umbrella aliases are conveniences. Import each independent product when controlling your link graph matters. The [architecture contract](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Architecture.md) and [independent example packages](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples) give the reviewed boundaries and compileable compositions.

### Navigate by task or symbol

Use <doc:LearningPaths> for an ordered route through the guides. Each product landing page links its conceptual guides and APIReference. Type extension pages preserve source documentation and organize creation, values, operations, cases, nested types and related members. Follow inherited-member sections when looking for synthesized protocol behavior.
