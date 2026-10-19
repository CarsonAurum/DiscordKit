# Supervised bot modules

This independent package composes handwritten command and event protocol modules through
`BotApplication` and `BotRuntime`. Its injected HTTP and WebSocket peers feed the real
`DiscordClient` shard and private Gateway interaction ingress. No Discord credentials,
network adapters, environment variables, macros or command synchronization are used.

```sh
swift build --package-path Examples/DSLBot
swift test --package-path Examples/DSLBot
swift run --package-path Examples/DSLBot DSLBot
```

The peer emits Hello, READY and one `/ping` interaction. The manual command awaits
its one ephemeral HTTP `Pong!` callback before allowing the peer's next synthetic `OFFLINE_STOP` event.
The synthetic peer waits for READY handling before emitting the command; independent
pipelines provide no global callback ordering. A typed event handler then calls
`requestStop`, while the application owner joins
all client, event and command work. The offline runner validates exact callback JSON,
zero registration requests and zero retained local resource counters.

The application explicitly injects bot and exact-token REST clients with separate
initial-response admission, shared finite handler authority, shard leases, startup
and client budgets. Construction and catalog compilation execute no callbacks or I/O.
The tests also exercise the protocol's inherited `main` and pre-cancelled startup.

This establishes local protocol composition and cleanup only. Live Discord,
privileged intents, cross-platform transport, throughput and Phase 15K capacity
qualification remain separate.
