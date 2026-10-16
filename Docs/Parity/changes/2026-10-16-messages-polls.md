# Messages and polls: Phase 5A

Local implementation/verification date: **2026-10-16**. Local release/commit:
unknown until committed/released. REST version: **10**. Existing consumers remain
source compatible; this adds opt-in Models/HTTP APIs without new dependencies.

Previously only current-user/current-application and Gateway discovery descriptors
were implemented. This update adds all twenty currently documented message routes
and both poll routes, typed message/poll payloads, component projections and message
validation, bounded multipart uploads, explicit bulk deletion and lazy continuation.
Current pin routes and their three deprecated predecessors remain independently
addressable; deprecated methods carry migration annotations. Other REST batches and
referenced resource-family gaps remain explicit in the [catalog guide](../../RESTCatalog.md).

Upstream chronology is independent of local support:

- **2025-06-25:** Discord announced paginated pin routes and deprecated the old
  routes. Effective date is unknown beyond the announcement's availability claim.
- **2025-08-20:** PIN_MESSAGES split was announced. An initial January 2026
  transition date was superseded by the **2025-11-24** announcement specifying
  **2026-02-23** for removal of MANAGE_MESSAGES pin authorization. Current docs and
  method comments require PIN_MESSAGES.
- **2026-03-19:** Discord announced the guild-message search documentation,
  requiring READ_MESSAGE_HISTORY and MESSAGE_CONTENT eligibility. The upstream
  introduction date is unknown; a documentation announcement is not proof of it.
- **2026-09-03:** Default per-file upload limit increased from 10 MiB to 20 MiB.
  The message complete-request maximum remains 25 MiB; these are separate limits.
- Other message/poll field introduction/effective dates remain unknown unless
  independently recorded. No local support date is used as an upstream date.

Verified official sources on 2026-10-16:

- [Message reference](https://docs.discord.com/developers/resources/message)
- [Poll reference](https://docs.discord.com/developers/resources/poll)
- [Component reference](https://docs.discord.com/developers/components/reference)
- [API versioning and uploads](https://docs.discord.com/developers/reference)
- [Discord change log](https://docs.discord.com/developers/change-log)

The reviewed inventory links handwritten implementations to original discovery IDs
and exact declaration/test evidence. Current verification hashes are recorded
separately from the historical discovery pins; neither historical membership nor
an offline check substitutes for live schema review. Related-family partial
projections and modal-only request validation are not promoted to full support.

Migration: adopt `MessageEndpoints`/`PollEndpoints`, share rate/reuse identity across
clients using a credential, explicitly close owned transports and consume/close
upload streams. Use `pins`/`pin`/`unpin` instead of `legacyPins`/`legacyPin`/
`legacyUnpin`. Supply current original flags when editing to retain immutable bits,
and enumerate both retained and new attachments when explicitly editing attachments.
