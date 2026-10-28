<!--
File: Examples/SocialApp/README.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Offline Social composition

Run `swift run --package-path Examples/SocialApp SocialApp`. This independent consumer
imports Social/Core/Media, exercises the public actor APIs from MainActor, and performs
no network, native device or Discord-host work. Its selected graph excludes Gateway,
Client, Cache, Voice, MLS, DAVE and concrete transport/platform adapters.

Real applications inject a `SocialHTTPProvider` for an approved user bearer client,
or a `SocialRPCProvider`/`SocialActivityProvider` for an explicitly authorized host.
They obtain consent through OAuth, qualify the exact host, then call `activate` with
that application/account/consent generation and exact granted scopes. Bot/backend
identity operations use `SocialHTTPApplicationProvider` separately.

Disconnect/close clears local observations and fences pending results. Callers still
cancel and await outstanding provider operations and close their shared transports;
a submitted mutation may already have executed. See [Social contracts](../../Docs/Social.md)
and the [complete SDK catalog](../../Docs/Parity/social-catalog.json) for unsupported
native Social networking, mobile adapters and early-access Commerce requirements.
