# Defining and routing commands

Separate registration values, exact invocation identity and application authorization.

## Overview

### Define a finite command catalog

``CommandDefinition`` wraps validated application command request values. Builders support slash commands, user/message context menus and Activity entry points. ``CommandOptionsBuilder`` preserves source order with blocks, arrays, conditionals and loops; it does not start tasks or bypass validation.

```swift
import DiscordCommands
import DiscordModels

let ping = try CommandDefinition.slash(
    name: "ping", description: "Check the application")
let inspectUser = try CommandDefinition.contextMenu(
    name: "Inspect user", type: .user)
```

Slash names/descriptions, option counts, required-before-optional ordering, unique siblings, subcommand nesting, choices/autocomplete and localization budgets are validated before registration. Context menus do not accept slash-only descriptions/options. Advanced fields remain available through the underlying request.

### Route authenticated contexts by exact identity

``CommandRouter`` separates command kind/name/subcommand path, focused autocomplete, component custom ID and modal custom ID. Routes do not register commands automatically.

```swift
import DiscordCommands
import DiscordModels

let router = try CommandRouter(routes: [
    CommandRoute(key: .command(name: "ping")) { context in
        try await context.responder.reply(
            InteractionMessageCreate(content: .value("Pong!"),
                flags: .value(.ephemeral)))
    }
], maximumConcurrentHandlers: 16)
```

Pass the normalized context from DiscordInteractions to `route`. A false result means there is no matching route; your host chooses a compatible fallback acknowledgement. A thrown handler error remains observable to that host. The [HTTPApp example](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/HTTPApp) demonstrates this complete path.

Custom IDs match exactly. They are untrusted application input, not authorization tokens. Check the invoking user, guild, resource ownership, consent and current application rules before side effects. Preserve submitted component/modal values from the context and validate their meaning in the handler. Display-only link previews never route as interactive commands.

### Bound retained routes and active handlers

Defaults cap 1,024 fixed routes, 256 KiB retained route text and 64 active handlers. Nested input inspection is bounded. Excess handlers fail immediately rather than becoming an unlimited queue. Errors and cancellation release handler admission; callbacks execute in the caller's task, outside Gateway heartbeat/control ownership.

Long work should explicitly defer through the responder and complete the original response. A router does not extend the initial deadline or make multiple initial responses valid. If using auto-defer, account for the state in which the timer already owns acknowledgement.

### Test identity and ownership separately

Test command type/name/path collisions, focused options, unknown inputs, exact custom IDs, duplicate route rejection, capacity, cancellation and error cleanup. Assert handler side effects and response calls. Then test response ownership with concurrent reply/defer attempts using an injected sink and clock. Avoid live registration merely to unit-test a route.
