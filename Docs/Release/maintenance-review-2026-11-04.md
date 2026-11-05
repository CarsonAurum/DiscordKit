<!--
File: Docs/Release/maintenance-review-2026-11-04.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Official upstream review prepared 2026-11-04

This is an automated analysis prepared for maintainer acceptance. It does not
record human review or advance the [maintenance ledger](maintenance.json).
[CI policy](../CI.md#weekly-official-review) requires the maintainer to accept
the semantic classifications before recording a new review date.

The [source evidence](sources/2026-11-04-maintenance.json) records exact response
hashes for the eight existing maintenance sources, canonical Markdown alternatives
and four affected resource/permission sources. Collection occurred on 2026-11-04
in America/Chicago, already 2026-11-05 UTC. This is why the ledger's inclusive
2026-11-04 due date passed locally but failed the hosted UTC run.

The official written documentation changed from
`37148620d2324292b76047541d5f8331f81ea77a` to
`da52492ced82d375981c46618cc3e182daada9a2` (25 files); the stable/preview specification
changed from `ed014089afa986f2b532ae081c456a85de074d0c` to
`4e75626a4cedfbc397d66f5491c79a9a62a71fd5` (two files). Exact comparisons and patch
hashes are in the evidence. Frozen discovery revisions remain unchanged.

## Proposed classifications

| Upstream change | Current DiscordKit disposition |
| --- | --- |
| October 29 voice-status permission exception | Correct the existing resolver: denied CONNECT no longer removes SET_VOICE_CHANNEL_STATUS. Explicit overwrites, VIEW_CHANNEL denial and timeouts still apply. Connection state and server authorization remain caller/server concerns. |
| October 30 computed member/role permission reads | Four new network endpoints remain unsupported. Local PermissionResolver arithmetic does not provide these HTTP operations. |
| October 29 audit position codes and merging | Exact unknown action codes and raw options survive; named cases 16/33 remain unsupported. Gateway creation events do not establish a complete immutable audit stream. |
| October 28 content-scanning metadata | Existing numeric flags and raw fields retain the additions. Named scanning flags, typed scan metadata and host moderation policies remain unsupported. Scanning can complete after initial message creation. |
| Forum/media starter Components V2 flag | Current upstream docs allow it; the existing ThreadStartInForum helper still rejects it. Its documentation now identifies a helper limitation. |
| Other request, Gateway and OAuth clarifications | Existing optional role-connection fields and Discord issuer validation already cover their selected contracts. Partial catalogs and the frozen inventory gain no broader completeness claim. |
| Other stable/preview additions | Lobby request names, Letterboxd identification, embed audio and further media fields retain existing raw/unsupported boundaries. |
| Native Social SDK guide and documentation-site changes | Native token-expiry/invite/lobby lifecycle guidance remains outside injected-provider support. Link, video, style and site-dependency changes require no owned protocol behavior change. |

The current changelog's newest entry is October 30. The previously reviewed
command identity, limits, autocomplete, interaction receipt/deadlines, message
budgets and Interaction Create inner payload remain intact in the selected
contracts. HTTP channel omission remains future-effective on November 16, 2026,
with no HTTP early opt-in; the existing dated transition fixture remains valid.

## Acceptance and validation

After accepting these classifications, the maintainer can record review date
2026-11-04 and due date 2026-11-11, bind all eight source rows to this new source
evidence hash, and append the review/permission-fix entry to parity history. Use
the actual acceptance date if it differs; collection timestamps stay historical.
Source hashes bind the collected analysis and do not themselves attest human
review. Raw historical response bodies were not committed, so changed hashes do
not establish a complete historical text comparison.

The resolver regression covers both voice and Stage channels, preserving the
status bit without CONNECT and keeping explicit denial, missing VIEW_CHANNEL and
timeout restrictions. Maintenance-date tests cover inclusive due dates, next-day
expiry, future reviews and invalid seven-day windows. The validator now reports
the exact review/due/evaluation dates and the required maintainer review action.

Once accepted, run the maintenance validator with the current date and reproduce
the hosted boundary with `--as-of 2026-11-05`. Existing platform, live Discord,
independent review, parity and capacity gates remain separate.
