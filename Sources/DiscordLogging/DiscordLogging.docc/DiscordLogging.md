# ``DiscordLogging``

Emit native SwiftLog diagnostics with application-owned outputs and task-scoped routing.

## Overview

``DiscordLog`` provides a logger factory used by independent operation owners.
Trace describes execution steps, debug describes diagnostic summaries, info records
normal lifecycle outcomes and notice records recovery or operational milestones.
Warning/error/critical identify degradation, terminal failure and lost safety.
Component thresholds and correlated operation context are task scoped.
Constructors and pure compilation emit nothing. The application configures
SwiftLog once and may select the optional `DiscordLogHandlers` product.

## Topics

### Adoption

- <doc:ScopedLogging>
- <doc:APIReference>
