# ``DiscordOAuth``

Own explicit OAuth consent flows, backend token operations and coordinated secure token lifetimes.

## Overview

DiscordOAuth separates browser authorization, callback validation, token transport and secure storage. Construction starts no browser, polling timer or network work. The host supplies registered redirects, presentation, authenticated-session binding, storage and trusted clocks. Public PKCE and confidential backend authentication remain different contracts.

Start with <doc:AuthorizationAndInstallation>, continue to <doc:TokenExchangeAndStorage> and use <doc:DeviceAndActivityAuthorization> for those specialized flows. The [OAuthApp example](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/OAuthApp) constructs a consent flow offline.

## Topics

### OAuth applications

- <doc:AuthorizationAndInstallation>
- <doc:TokenExchangeAndStorage>
- <doc:DeviceAndActivityAuthorization>

### API reference

- <doc:APIReference>
