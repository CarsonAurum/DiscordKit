# Explore the example cookbook

Choose a runnable program, a tested backend composition or a contextual snippet for your task.

## Overview

### Whole application examples

Every example below has its own Swift package and imports its selected products explicitly. A build checks compilation without running its entry point.

| Package | Learn | Execution behavior |
| --- | --- | --- |
| [CommandsApp](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/CommandsApp) | Slash definition, message validation, button custom ID, ephemeral/public tests | Offline; no credentials or I/O |
| [DSLCommands](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/DSLCommands) | Macro/protocol commands, actor dependencies, policies, families and signed HTTP callbacks | Default/`--offline` uses synthetic signatures; explicit `--listen` binds loopback |
| [DSLEvents](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/DSLEvents) | Custom typed selector, two ordered modules and bounded pipeline ownership | Offline synthetic dispatch; starts no client |
| [DSLBot](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/DSLBot) | Independent extension modules, trusted client ingestion and joined runtime cleanup | Offline injected HTTP/WebSocket peers; no registration or sockets |
| [RESTOnly](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/RESTOnly) | Foundation adapter, shared rate authority, typed reads, cleanup | With configured bot token, performs two real API reads |
| [GatewayBot](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/GatewayBot) | Intents, authority, cache projection, subscription before run, shutdown | With configured bot credentials, connects to Discord |
| [HTTPApp](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/HTTPApp) | Signed bytes, bounded listener/handlers, routing and initial reply | With configured ID/key, binds loopback listener |
| [OAuthApp](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/OAuthApp) | Fresh state, issuer-bound callback, S256 PKCE and user install | Constructs a flow without presenting UI or network |
| [RPCApp](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/RPCApp) | Local connector injection, request/device metadata, explicit consent | Constructs values; opens no desktop session |
| [ActivityHost](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/ActivityHost) | Injected host transport, backend code exchange and entitlement policy | Portable executable describes required host injection |
| [SocialApp](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/SocialApp) | Scoped relationship state, consent generation and muted synthetic PCM | Offline local actors; closes state/audio owners |
| [VoiceBot](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/VoiceBot) | PCM/Opus, RTP rollover, AEAD, MLS and DAVE | Synthetic frames/public fixture keys; no devices or network |

```sh
swift build --package-path Examples/RESTOnly
swift test --package-path Examples/CommandsApp
swift run --package-path Examples/CommandsApp
swift run --package-path Examples/SocialApp
swift run --package-path Examples/VoiceBot VoiceBot
```

Do not run a credential-bearing example as an automatic documentation check. Follow <doc:DiscordKitTutorials> for the guided reading order and each example's README for configuration.

### API usage snippets

Product guides use focused Swift snippets for values, descriptor construction, actor methods, routing and local transforms. Some listings require a configured client, context, clock or injected provider from their surrounding discussion. These contextual excerpts illustrate the API rather than acting as independent executables. Use a whole example package when you need imports, manifest settings, entry point and cleanup together.

### Wire fixtures and negative examples

The root [test suites](https://github.com/CarsonAurum/DiscordKit/tree/main/Tests) cover malformed JSON, null/missing fields, large IDs, unknown raw values, exact signed bytes, rate limits, split IPC frames, replay, stale generations and media authentication. They show what must be rejected as well as how successful payloads are decoded.

The [Activity browser tests](https://github.com/CarsonAurum/DiscordKit/tree/main/Browser/DiscordActivityBridge) use Node's built-in test runner and a simulated message host. They demonstrate exact event source/origin admission without a live iframe. ActivityHost's Swift tests demonstrate server-side entitlement policy without purchasing an item.

### Primitive and local protocol demonstrations

VoiceBot contains separate MLS and DAVE demonstrations beside its media entry point. These compose synthetic peers and public test keys. Never reuse those keys for actual media. The independent [voice session qualification harness](https://github.com/CarsonAurum/DiscordKit/tree/main/Tools/VoiceSessionQualification) uses local UDP peers; the [load harness](https://github.com/CarsonAurum/DiscordKit/tree/main/Tools/DiscordKitLoadTests) exercises bounded local capacity. Their workloads and outputs establish only their stated local scope.

### Tutorial code snapshots

Tutorial listings are synchronized snapshots of the source packages, including their supporting MLS/DAVE, Activity backend and DSL policy/family/extension files. The command-module tutorial also displays the separately compiled extension library. The documentation check detects changed or missing snapshots. The original examples and extension package remain the build/test authority; copying directory-sensitive manifests into another folder requires adjusting the local package path.
