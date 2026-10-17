# Independent OAuth application

Build from the repository root:

```sh
swift build --package-path Examples/OAuthApp
```

The example creates an idle state/issuer-bound user-install code flow with fresh
S256 PKCE. It never opens a browser, logs the authorization URL or sends requests.
Replace its synthetic application ID and HTTPS redirect with your registered
application. The selected graph excludes Gateway, Client, Cache, Commands,
Interactions, GameServices, Commerce and concrete network adapters.

A real host supplies `OAuthBrowserAdapter` with its main-actor OS browser session,
binds the flow to the authenticated user session, and passes the validated code
to `OAuthClient.exchange`. Confidential server applications keep their client
secret on the backend. Explicit Public Client-enabled applications use
`OAuthClientAuthentication.publicPKCE` and keep secrets out of distributed apps.
Inject and share a REST rate authority/application identity and bounded transactional
secure token storage; construction starts no tasks or network work.

See [OAuth contracts](../../Docs/OAuth.md) for callback, expiry, cancellation,
refresh, publisher lineage and storage ownership. Building is local compilation
evidence; it does not qualify OS browser UI or live Discord OAuth.
