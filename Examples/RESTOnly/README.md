<!--
File: Examples/RESTOnly/README.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# REST-only consumer

Build with Swift 6.4: `swift build --package-path Examples/RESTOnly`.
The example links Core, HTTP and Foundation transport, with no Gateway or voice
product dependency. The package resolver may fetch the repository's approved NIO
graph, but this executable does not link its adapter.

Running `swift run --package-path Examples/RESTOnly` uses `DISCORD_BOT_TOKEN` from
the environment, fetches API v10 current-user/current-application snapshots, prints
only their numeric identifiers, and closes its owned coordinator/transport. Keep
the token outside source control. With no token it returns before network work.
Repository tests never run authenticated requests.

Create the application and obtain its bot token in Discord's Developer Portal;
DiscordKit does not invent application-creation or token-provisioning endpoints.
Share the same opaque identity and coordinator when constructing additional
clients for this credential. See [HTTP ownership and policies](../../Docs/HTTP.md).
