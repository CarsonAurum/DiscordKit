# OAuth2, game services and entitlement ownership: Phase 9

Verified and locally added **2026-10-17**. REST uses **API v10**; browser OAuth is
unversioned. Current [source fingerprints](../oauth-game-commerce-current-sources.json)
remain separate from original discovery membership/revisions/hashes. The publisher
guide's initial release is **2026-02-18**; its effective date and other upstream
announcement/effective dates remain unknown unless separately recorded.

Previously callers supplied preexisting bearer credentials and composed typed
lobby/profile/entitlement operations themselves. Independent OAuth, GameServices
and Commerce products now add explicit authentication and backend conveniences;
HTTP retains its independent graph without OAuth, Gateway or Crypto. OAuth selects
the already locked Swift Crypto product for S256. The umbrella adds deliberate
aliases and the independent OAuthApp example compiles without Gateway/Client/Cache,
Commands/Interactions, GameServices/Commerce or a concrete transport.

Authorization flows generate state and S256, bind exact redirects and issuer,
consume authenticated success/denial callbacks once, and provide explicit legacy
implicit compatibility. Separate callbackless bot/command installations preserve
user/guild contexts, decimal permissions and guild hints. Scope approval metadata
is advisory. Discord's authorization-server metadata explicitly supports S256,
issuer identification and public `none` token/revocation authentication; configured
public clients remain distinct from confidential backend client secrets.

Token grants/revocation use bounded form bodies, fixed origin, uncached unsafe
submission semantics and the existing coordinated HTTP policy. Redacted response
variants include incoming webhook and advanced bot guild data. Authorization
information keeps partial application/user projections. Bounded token ownership
shares one local refresh per audience/grant with independently canceled waiters,
conservative UTC expiry, atomic rotation, definitive invalid-grant removal and
local/remote revocation fences. Secure transactional storage and distributed leases
remain injected responsibilities. Publisher children retain original expiry after
parent refresh; parent removal cascades, individual child removal preserves siblings.

Public account operations cover bot provisioning/initial naming, confidential
external proof exchange, explicit code/device-code merge, destructive backend
unmerge and approved publisher child exchange. Migration is asynchronous and never
runs at construction/startup. Unmerge lacks a precise published success schema;
bounded optional JSON/empty 2xx acknowledgement remains explicitly partial. Native-only
public-client creation, post-create naming and public-client unmerge remain blocked
without invented routes or a native SDK wrapper. Device-code acquisition/UI is host-owned.

Profile/stat conveniences preserve complete replacement and avoid matching writes;
linked-lobby plans retain silent omissions and partial progress. Authoritative
entitlement helpers match application/SKU/receipt and exact user/guild ownership,
reject deleted/unknown/expired/test purchases by policy, distinguish open/missing
bounds and verify consumable availability. A purchaser user ID on a guild grant
never grants user-wide access. Explicit consumption retains uncertain outcomes;
client Activity purchase IDs are hints requiring fresh server verification.
Subscription status alone never authorizes a premium feature.

Social Commerce catalog/storefront, pricing, gifts, wishlists, commerce-specific
purchases and fulfillment webhooks/acknowledgements retain **awaiting schema/access**
blockers. Existing ordinary entitlement consumption does not implement fulfillment.
The [capability inventory](../../Phase9ServiceContracts.md) identifies each boundary.

Migration is additive: import independent products, share rate/refresh authorities,
inject secure CAS storage and main-actor browser UI, and explicitly invalidate
lineage after observed deauthorization/unmerge. Consumers own OS UI, distributed
coordination, durable game delivery and adapter/store cleanup. See [OAuth contracts](../../OAuth.md)
and [execution evidence](../../../.air/plans/phase-9-execution.plan.md). Local macOS
results do not qualify live Discord, OS browser sessions, distributed secure storage,
approval-gated publisher access, other hosts/devices, payment fulfillment or fleet capacity.
