# Configure logging at the application boundary

Choose a native SwiftLog handler before starting subsystem work.

## Overview

Import `DiscordLogging` to use native `Logger` and ``DiscordLog``. Configure
`LoggingSystem.bootstrap` once from the executable, or override
``DiscordLog/loggerFactory`` in a task-local scope around explicit runtime work.
Factories must be cheap, concurrency-safe and nonrecursive. Structured child tasks
inherit a scoped factory; detached work and unrelated callers do not.

``DiscordLog/makeLogger(_:)`` adds a stable `discordkit.<subsystem>` label and
`dk.subsystem` metadata while preserving application thresholds. Library event
sites add fixed `dk.event` values and safe counts/states. Info and notice remain
available for application events. Runtime code starts no output or global bootstrap.

Pure values and per-frame DSP/crypto paths remain quiet. Apply scopes around the full
supervised lifetime so child operation events use the same destination and context.
Native SwiftLog metadata providers can attach application context without changing
the subsystem API. Application-supplied metadata remains its privacy responsibility.
