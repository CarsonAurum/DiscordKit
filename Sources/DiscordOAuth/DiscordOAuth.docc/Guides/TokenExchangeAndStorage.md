[//]: # "File: Sources/DiscordOAuth/DiscordOAuth.docc/Guides/TokenExchangeAndStorage.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Exchanging tokens and coordinating secure storage

Keep confidential authentication on the backend and make refresh replacement atomic.

## Overview

### Use the correct token client

``OAuthClientAuthentication`` distinguishes confidential form authentication from a portal-enabled public PKCE client. Public apps must not ship a client secret. ``OAuthClient`` executes code exchange, refresh, client credentials and revocation through an injected RESTClient. Token operations require a header-free REST client because client authentication is carried in their form body; current-authorization reads use their own bearer policy.

``OAuthEndpoints`` produces bounded fixed-origin descriptors. Code/refresh/revocation mutations disable read reuse and unsafe automatic replay. Explicit rejected 429 handling remains bounded by REST policy; uncertain submission or unsafe 5xx must not be replayed blindly. Closed OAuth failures avoid server descriptions that could leak codes or tokens.

A response's scopes describe that authorization snapshot. Optional advanced-bot guild/webhook data remains partial and sensitive; it does not create another credential category or prove future membership.

### Inject storage with real transaction semantics

``OAuthTokenStorage`` is required; there is no insecure default persistent store. An implementation must atomically compare generations, validate publisher parent freshness/lineage, replace complete credentials and invalidate children when a root is removed. The backend owns encryption, authorization, durability and finite record/lineage retention.

``OAuthTokenIdentity`` separates application audience from an opaque authorization grant. Use the same grant identity for a publisher lineage and a distinct audience for each child. Avoid using access-token text as a storage key, log label or rate diagnostic.

### Refresh only through explicit access

``OAuthTokenCoordinator`` returns a fresh stored token without I/O or owns one local refresh flight per grant/audience. Defaults cap 128 active identities/mutations, 1,024 aggregate waiters and 128 waiters per identity, with a 30-second refresh skew. No timer starts at construction.

Expiry uses trusted UTC time because tokens persist across process lifetimes. Acquisition time anchors expiry conservatively before network work. Future install times and invalid lifetime/skew fail. Omitted refresh tokens preserve the previous refresh credential; rotations replace complete state atomically.

Generation comparison prevents stale storage replacement but does not coordinate remote token rotation across processes. Distributed deployments also need a single refresh owner or external grant lease. A transient or uncertain refresh retains storage without automatic replay. A definitive invalid grant invalidates local state.

### Preserve rotations when waiters cancel

Each cancelled waiter returns independently. Once a refresh is admitted, it continues even if all waiters cancel so a rotated credential can be persisted. `close` rejects new admission, releases waiters, cancels and joins owned exchanges. Storage/network operations must cooperate with cancellation. Install, revoke and invalidate mutations remain caller-owned and must be awaited before disposing storage.

Publisher child expiry is capped to its original parent's remaining lifetime. A child has no direct refresh; refreshing its parent does not extend an existing child. Re-exchange explicitly for a new child. Root revocation durably removes descendants before the remote attempt, while child revocation uses that child's application credentials.

### Validate races and failures

Test fresh hits, expiry boundaries, one-flight concurrent refresh, rotated/omitted refresh tokens, generation conflicts, parent removal racing child install, transient versus definitive failure, cancelled waiters and close. A deterministic in-memory test store validates protocol behavior; production secure-storage durability and cross-process correctness require their own evidence.
