# Inject an OAuth host and token owner

Keep consent, browser lifecycle and transactional secure storage explicit.

```sh
swift build --package-path Examples/OAuthApp
```

The [OAuthApp consumer](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/OAuthApp)
builds an idle authorization flow with state, issuer and S256 PKCE binding.
It opens no browser, logs no authorization URL, sends no request and selects no
Gateway, Client, Cache, Commands or concrete network adapter.

Replace synthetic IDs and redirects with your registered application. Bind the
flow to the authenticated user session; an OS browser callback is input to validate,
not proof of account authority. Inject OAuthBrowserAdapter and transactional secure
storage with atomic generation replacement and publisher-child invalidation.
Keep confidential secrets on the backend; use publicPKCE only for an explicitly
enabled public client. Explicit bounded device polling is a confidential backend
operation and does not create a native public-client grant.

Share the relevant REST/application authorities. Cancel browser sessions and
await token-owner shutdown as required by your composition. Secure storage and
real OS authentication UI have separate qualification gates. See the
[OAuth contract](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/OAuth.md).
