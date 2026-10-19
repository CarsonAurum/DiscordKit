# ``DiscordLogging``

Emit native SwiftLog diagnostics with application-owned outputs and task-scoped routing.

## Overview

``DiscordLog`` provides a logger factory used by independent operation owners.
Library flow uses trace/debug; exceptional recoveries and terminal failures use
warning/error/critical. Info and notice remain reserved for application semantic
events. Constructors and pure compilation emit nothing. The application configures
SwiftLog once and may select the optional `DiscordLogHandlers` product.

## Topics

### Adoption

- <doc:ScopedLogging>
- <doc:APIReference>
