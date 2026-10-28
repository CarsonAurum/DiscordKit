[//]: # "File: Sources/DiscordKit/DiscordKit.docc/CommandsComponents.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Compose commands and components

Validate definitions and message payloads offline before explicit registration.

```sh
swift build --package-path Examples/CommandsApp
swift test --package-path Examples/CommandsApp
swift run --package-path Examples/CommandsApp
```

The [CommandsApp consumer](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/CommandsApp)
creates a greet slash command with a required name and optional private flag, then
validates a greeting reply and one primary refresh button. Both ephemeral and
public payloads are tested. The run is offline, reads no credentials and creates
no responder or network resource.

The ordinary CommandDefinition result builder preserves order; required options
precede optional ones. Construction validates names and payload bounds. Apply
registration through explicit typed endpoints or review a CommandReconciler plan;
no definition registers itself and unmanaged registrations are preserved by policy.

Route command names and exact component custom IDs in separate namespaces.
The greeting:refresh ID selects a handler; authorize its invoker and any retained
application state independently. Pair the message with a trusted HTTP/Gateway
InteractionContext and explicitly reply/defer. See <doc:HTTPApplications> for a
signed receipt composition and the
[component reference](https://docs.discord.com/developers/components/reference)
for current component shapes.
