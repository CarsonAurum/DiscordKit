[//]: # "File: Sources/DiscordHTTP/DiscordHTTP.docc/Guides/UploadsPaginationAndWorkflows.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Uploading files and traversing bounded workflows

Preserve full-request byte bounds, operation-specific continuation and partial mutation outcomes.

## Overview

### Match attachment metadata to real files

``MessageUploadFile`` holds materialized bytes or a fresh bounded producer factory. File identifiers must be unique and match outgoing attachment metadata. For edits with new uploads, explicitly include every attachment to retain and every new attachment; an empty attachment array removes existing files, while omission preserves them when allowed.

``MessageUploadLimits`` distinguishes per-file bytes from complete multipart request bytes. Defaults are 20 MiB per file and 25 MiB for the complete request, including JSON, headers and delimiters. A server account's allowance and the concrete adapter's collection cap can be lower. Configure all layers together instead of assuming a per-file limit is the complete body budget.

Factories remain unopened during metadata validation and return a newly owned stream for each admitted attempt. Success, cancellation and failures close active producers. Multipart validation covers names, filenames, controls and boundary collisions. The owned HTTP adapters collect bounded upload bytes before transmission; a pull-based source alone does not establish streaming network uploads.

Sticker, emoji, soundboard, forum and invite-target CSV operations select their own media and complete-body validation. A CDN URL returned in a resource never authorizes forwarding API credentials. ``AssetClient`` is credential-free, HTTPS-only, bounded and single-send.

### Let each endpoint define completion

``CursorPagination`` is lazy. Constructing it does not fetch; each iterator pull obtains one page. Stopping iteration issues no next request. Its cursor-cycle detection and finite page budget bound continuation metadata rather than accumulating every result.

```swift
import DiscordHTTP
import DiscordTransport

let clock = ContinuousClock()
let pages = try CursorPagination<Int, Int, ContinuousClock>(
    maximumPages: 3, context: TransportContext(clock: clock)) { cursor in
        let current = cursor ?? 0
        return CursorPage(items: [current],
            nextCursor: current < 2 ? current + 1 : nil)
    }
var collected: [Int] = []
for try await page in pages { collected += page }
assert(collected == [0, 1, 2])
```

This executable pattern is entirely local. Replace its fetch closure with an operation-specific executor that returns the correct cursor. A short page does not universally indicate completion; pins use their explicit continuation metadata, search can return indexing state and lobby recent messages have no documented cursor to invent.

### Bound polling and mutation plans

``PollingOperation`` uses explicit terminal states, finite poll counts, cancellation and one shared deadline. Polling an asynchronous server job should not create a detached infinite loop. Keep server retry intervals distinct from REST rate admission.

Bulk helpers model concrete legal upstream groups and preserve completed progress. A later error cannot undo earlier accepted writes. Inspect returned silent drops, removals, unattempted items and indeterminate outcomes. Full replacements must remain full replacements: splitting one destructive command or lobby replacement into smaller requests can change meaning and is not generic batching.

Test early break, repeated cursors, page limits, cancellation before the next fetch, empty pages with valid continuation, terminal polling errors and partial bulk failures. Keep clocks injected and use barriers for concurrent cleanup tests.
