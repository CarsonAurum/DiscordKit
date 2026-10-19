# Supervised bot modules

This independent package imports handwritten command and event protocol modules from
the separate `Packages/DiscordDSLExtensions` package and composes them through
`BotApplication` and `BotRuntime`. Its injected HTTP and WebSocket peers feed the real
`DiscordClient` shard and private Gateway interaction ingress. No Discord credentials,
network adapters, environment variables, macros or command synchronization are used.

```sh
swift build --package-path Examples/DSLBot
swift test --package-path Examples/DSLBot
swift run --package-path Examples/DSLBot DSLBot
```

The peer emits Hello, READY and one `/extension code:ABC` interaction. The imported
manual command uses its public custom `ArgumentValue` codec and awaits its one
ephemeral HTTP `Code: ABC` callback before allowing the peer's synthetic future events.
The imported event module ignores `OFFLINE_IGNORED` and stops only for `OFFLINE_STOP`.
The synthetic peer waits for READY handling before emitting the command; independent
pipelines provide no global callback ordering. A typed event handler then calls
`requestStop`, while the application owner joins
all client, event and command work. The offline runner validates exact callback JSON,
zero registration requests and zero retained local resource counters.

The command module's `ExtensionDependencies` and custom `ExtensionAuthorizationPolicy`
share the same explicitly injected `ExtensionCounter` actor. The joined run asserts
one authorization and one admitted handler entry. `ExtensionEventDependencies`
captures application-owned READY and stop callbacks; a public custom typed selector
supplies READY through the existing decoder without central switch changes. Both
modules install under explicit `ModuleNamespace` identities, which leave wire names
unchanged. The selected graph excludes macro plugins and SwiftSyntax.

The application explicitly injects bot and exact-token REST clients with separate
initial-response admission, shared finite handler authority, shard leases, startup
and client budgets. Construction and catalog compilation execute no callbacks or I/O.
The tests also exercise the protocol's inherited `main` and pre-cancelled startup.

This establishes local protocol composition and cleanup only. Live Discord,
privileged intents, cross-platform transport, throughput and Phase 15K capacity
qualification remain separate.
