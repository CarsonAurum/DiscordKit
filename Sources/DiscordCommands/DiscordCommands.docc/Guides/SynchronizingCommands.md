# Synchronizing managed command registrations

Perform one explicit fresh comparison and preserve unrelated registrations and partial progress.

## Overview

### Own one deployment scope

``CommandReconciler`` binds an application, optional guild and finite managed definitions. It validates the complete desired catalog before fetching or writing, including duplicates, command kind caps, global/guild constraints and aggregate encoded bytes. A guild scope and global scope are separate catalogs.

```swift
import DiscordCommands
import DiscordCore

let definition = try CommandDefinition.slash(
    name: "ping", description: "Check the application")
let reconciler = try CommandReconciler(
    applicationID: ApplicationID(rawValue: 1),
    definitions: [definition])
// Explicit deployment action:
// let report = try await reconciler.synchronize(using: registrationClient)
```

The synthetic identifier must be replaced by the registered application. The host supplies an authorized REST client with the usual shared rate identity and bounded deadline. Construction and router adoption send nothing.

### Compare managed fields canonically

Synchronization fetches one uncached list with full localizations, compares known default representations, then creates or patches only changed managed entries. Name/type identifies managed commands and stable server IDs target patches. Repeating equivalent definitions produces zero writes.

Omitted invocation/install contexts, entry-point handler and deprecated permission settings remain unmanaged when configured that way. Managed localizations, ordinary permissions, age restriction and slash options have complete replacement semantics. Exact numeric JSON spelling is preserved rather than rounded during comparison.

Unmanaged commands are not deleted. Omitting or renaming a desired definition does not silently delete the old registration. If you intend destructive complete replacement, use the explicit typed bulk endpoint after reviewing its complete scope; reconciliation does not turn into bulk overwrite automatically.

### Preserve progress and uncertainty

One reconciler owns one local synchronization at a time. Multiple processes or external registration tools require an application-owned coordinator; the fresh snapshot can race an unrelated writer. The reconciler does not promise a transaction, rollback or exactly-once writes.

``CommandSyncReport`` records acknowledged changes and unchanged count. ``CommandSyncFailure`` retains acknowledged progress, the failing desired-definition index and the original failure for deliberate inspection. Subsequent definitions remain unattempted. A failed unsafe write can independently have succeeded remotely; fetch fresh state before another explicit synchronization.

Defaults cap aggregate definition JSON at one MiB and enforce documented per-kind/global/guild totals. An empty desired catalog reads current state and writes nothing. Keep deployment retries finite and do not reset rate authority between attempts.

### Test actual request reduction

Script the list response and expected create/PATCH responses. Assert equivalent defaults/localizations write nothing, one changed field writes only the managed command, unmanaged fields stay preserved and failures stop later writes with exact partial progress. Include concurrent synchronization rejection, cancellation, 429 handling through REST and an ambiguous write followed by explicit fresh reconciliation.
