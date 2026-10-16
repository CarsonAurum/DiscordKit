# Platform transport probe

This development-only Swift package qualifies the exact locked Apple-origin NIO
graph independently of DiscordKit's production dependencies. Run from the root:

```sh
swift package --package-path Tests/Fixtures/PlatformProbe resolve
swift test --package-path Tests/Fixtures/PlatformProbe --disable-automatic-resolution
```

Tests use Swift Testing and actual IPv4 loopback sockets on ephemeral ports. They
exercise HTTP, trusted TLS, trust/hostname rejection, a WebSocket upgrade/text frame
and empty/binary UDP datagrams. Tests can run in parallel and use no live Discord
credentials. They require a host that permits local sockets. Compilation alone is
not runtime qualification.

Resources include a self-signed localhost certificate and its intentionally public
private key. They are fixture data, never production credentials. A positive TLS
test explicitly trusts that certificate; default trust roots and a wrong hostname
are separate rejection cases. These tests never disable certificate verification.
The fixture certificate's fixed validity interval is 2000-01-01 through 2120-01-01;
its generation date is not a runtime dependency and it must never be installed in
an operating-system trust store.

See [the transport report](../../../Docs/Feasibility/PlatformTransports.md) for
verified versions, provenance, results and the remaining adapter/platform gates.
