<!--
File: Examples/RESTOnly/README.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# REST-only consumer

Build with Swift 6.4: `swift build --package-path Examples/RESTOnly`.
The example links Core, HTTP and the platform's transport, with no Gateway or voice
product dependency. On macOS it uses Foundation; on Linux it uses NIO because the
Foundation HTTP adapter is Apple-only. Conditional product dependencies keep the
NIO adapter out of the macOS executable, although package resolution may fetch its
approved dependency graph. The Linux adapter owns an event loop and TLS context;
the example awaits its closure after requests finish.

Running `swift run --package-path Examples/RESTOnly` uses `DISCORD_BOT_TOKEN` from
the environment, fetches API v10 current-user/current-application snapshots, prints
only their numeric identifiers, and closes its owned coordinator/transport. Keep
the token outside source control. With no token it returns before network work.
Repository tests never run authenticated requests.

Create the application and obtain its bot token in Discord's Developer Portal;
DiscordKit does not invent application-creation or token-provisioning endpoints.
Share the same opaque identity and coordinator when constructing additional
clients for this credential. See [HTTP ownership and policies](../../Docs/HTTP.md).
