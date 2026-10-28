<!--
File: Examples/ActivityHost/README.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# ActivityHost

Build with `swift build --package-path Examples/ActivityHost`. The executable starts
no browser, network connection or authenticated request. Its selected client graph
uses Activities/Core/Transport; the separately compiled ActivityBackend target uses
OAuth/Commerce/HTTP/Models. Neither selects Gateway, RPC, Client or Cache. Keep the
backend target and its client secret out of browser/mobile bundles.

ActivityHostSession demonstrates AUTHORIZE → authenticated backend exchange →
AUTHENTICATE and START_PURCHASE → backend entitlement verification. ActivityBackend
uses confidential Activity code descriptor and authoritative grant policy.
The server must authenticate its user session, enforce CSRF/replay protection and
derive the expected user/SKU from its own state. Return only scoped access tokens
and application grant results. durable webhook ingress can trigger the same
grant recheck when ENTITLEMENT_CREATE arrives asynchronously.

The Web folder is a dependency-free browser entry point using the owned bridge.
Serve it and the bridge modules under an approved Discord URL mapping; insert the
public client ID via a discord-client-id meta tag and configure the exact allowed
discord-host-origin meta tag (Discord stable is the explicit default). It must run inside Discord's actual
Activity iframe. The example intentionally does not install a fake Activity host or
send a purchase automatically. The authenticate action requires your independently
deployed, authenticated HTTPS `/api/token` backend returning `{access_token}`.

Swift/native bindings adapt `createActivityTransport` from the browser bridge,
including its source/origin authentication, to ActivityTransport's bounded single
reader. No production Swift-Wasm/WebKit/JNI binding or real Discord browser/mobile
smoke test is claimed by compiling this example. See the Activities guide.

Run `swift test --package-path Examples/ActivityHost` for local backend-policy tests
and `node --test Browser/DiscordActivityBridge/*.test.mjs` for simulated-host
browser transport tests. Neither sends live Discord requests.
