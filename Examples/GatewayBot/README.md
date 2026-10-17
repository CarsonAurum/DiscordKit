# Gateway bot consumer

Build from the repository root with `swift build --package-path Examples/GatewayBot`.
Validation only builds the executable and never sends authenticated requests.

To opt in to live API v10 traffic, set `DISCORD_BOT_TOKEN` and the matching public
`DISCORD_BOT_ID`, then use `swift run --package-path Examples/GatewayBot`. Keep the
token out of shell history, source and logs. The example subscribes before starting,
receives READY, executes the typed current-user service and awaits clean shutdown.

Intents are explicitly `.guilds`; privileged member/presence/message-content access
requires separate Developer Portal configuration. The client owns discovery,
heartbeat, reconnect and leases. Its constructor starts no tasks or network work.

One cache, session budget, startup/opcode authority and rate coordinator are shown.
Share these authorities across clients as described in [the client guide](../../Docs/Client.md).
Distributed deployments must inject shared external coordinators/leases; process-local
defaults do not qualify worker failover or deployment capacity. The example owns its
adapters and closes them once in its cleanup closure; shared adapters need separate ownership.
