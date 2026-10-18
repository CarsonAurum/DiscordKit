# Offline commands and components

```sh
swift build --package-path Examples/CommandsApp
swift test --package-path Examples/CommandsApp
swift run --package-path Examples/CommandsApp
```

This independent consumer creates a validated `/greet` definition, a text reply and
one primary button with the exact custom ID `greeting:refresh`. It validates both
ephemeral and public message payloads. It reads no credentials, starts no tasks or
sockets, and never registers a command or acknowledges an interaction.

The selected graph includes Commands/Interactions/HTTP/Models/Core/Transport and
Swift Crypto. It excludes Gateway/Client/Cache, OAuth, voice, RPC, Activities,
Social and concrete transport adapters. Importing Commands does not create a REST
client; register explicitly with `CommandReconciler` after reviewing its proposed
changes, or use the typed application-command endpoints.

For a deployed application, connect `CommandRouteKey.command(name: "greet")` and
`CommandRouteKey.component(customID: "greeting:refresh")` to explicit handlers and
call `context.responder.reply` with the constructed message. Authorize the invoker
and any stored state separately; a component custom ID does not confer authority.
The existing [HTTPApp](../HTTPApp/README.md) demonstrates signed HTTP receipt and
bounded handlers; [Interactions](../../Docs/Interactions.md) covers Gateway receipt,
defer deadlines, continuation sinks, registration ownership and overload.

See [setup](../../Docs/Setup.md) before opting into deployment. The offline run and
tests do not establish Discord delivery, command propagation or rendering evidence.
