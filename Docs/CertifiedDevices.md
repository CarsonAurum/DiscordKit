# Certified Devices

`DiscordCertifiedDevices` is an independently adopted local desktop integration.
It publishes the hardware state supplied by a host application through the
documented HTTP POST or through an independently owned `DiscordRPC` client.
Importing or constructing these values starts no network I/O, discovery, device
observation or background task. No native SDK is linked.

The [Certified Devices reference](https://docs.discord.com/developers/topics/certified-devices)
and [RPC reference](https://docs.discord.com/developers/topics/rpc) were verified
on 2026-10-17. Both describe v1 local payloads. Generic RPC WebSockets are
deprecated and available only to approved legacy private-beta participants;
publishing these types does not grant hardware certification, application
approval, tester access or user authorization.

## Host supplied device state

`CertifiedDevice` requires a documented `CertifiedDeviceType`, native ID, vendor,
model and an ordered list of related native IDs. The host supplies the Windows
native audio device identifier (called a UUID in the reference, with endpoint-instance
tokens in its example) or, on macOS, the device name. No Windows/macOS native device
enumeration or identifier extraction is implemented. A related list may include
its own device ID, matching Discord's published example.

`CertifiedDeviceAudioProcessing` reports optional `echo_cancellation`,
`noise_suppression`, `automatic_gain_control` and `hardware_mute` states. It is
accepted only for audio inputs. Missing flags are omitted; explicit false remains
false. These are observed native states, not instructions to change Discord's
voice configuration.

Every publication sends the **entire current array**, highest preference first.
A later array replaces the previous array; it does not merge devices. An empty
array clears the list. The host should publish fresh full state after connection,
device changes, mute changes and native processing changes. It owns observation,
debouncing, application lifecycle and reconciliation after an indeterminate error.

Device IDs, product names, URLs and related identifiers are redacted from normal,
debug and reflective diagnostics. Explicit properties and `jsonValue` deliberately
expose wire metadata to the caller, who must apply the same diagnostic discipline.
Vendor/model URLs are descriptive only and are never fetched.

## HTTP publication

`CertifiedDeviceHTTPPublisher` borrows an injected `DiscordTransport.HTTPTransport`.
The caller explicitly chooses a port; the endpoint is fixed to
`http://127.0.0.1:PORT/rpc?v=1&client_id=APPLICATION_ID`. A publication sends one POST
with JSON content type and a fresh nonce. It validates a 200 acknowledgement with
matching command/nonce, null event and null data. Unknown response fields are
accepted. An ERROR event becomes a numeric `CertifiedDeviceFailure.remoteError`;
desktop error text is discarded. Non-200 statuses and mismatched or malformed
acknowledgements fail without an implicit second request.

The actor admits one publication at a time and immediately rejects overlap. It
does not retain a hardware-state cache or waiter queue. Cancellation, deadline,
parse, size and transport failure paths close operation-owned bodies. Await
`close()` to prevent new work and cancel/await pending publication. The caller
continues to own the shared transport pool. Closing does not clear desktop state.

The injected transport must preserve the fixed loopback destination, avoid
redirects and proxies, propagate cancellation and avoid request replay. Concrete
adapters remain separately adopted. Discovery is explicit because opaque transport
errors cannot establish whether a state-changing request reached a prior port.

## WebSocket publication

`CertifiedDeviceWebSocketConnector` implements `RPCConnector` for the documented
Certified Devices WebSocket URL. It pins 127.0.0.1, explicit port, JSON encoding
and v1, and sends the caller's registered RPC Origin. It accepts UTF-8 text only;
binary/ETF input and excessive messages fail. The socket adapter handles
WebSocket control frames. Application approval and Origin validation remain
Discord desktop decisions.

Pass that connector to `RPCClient`, explicitly connect, and use
`CertifiedDeviceRPCPublisher` to publish typed complete arrays. The RPC client
owns READY handling, nonce/command correlation, bounded pending requests/events,
authentication commands, transport failure and close. The publisher borrows the
client and never silently connects, authenticates, subscribes, reconnects or replays.
An approved IPC RPC client can also be borrowed without adding a WebSocket dependency.
Callers must await the RPC client's close separately.

The Certified Devices page documents ports **6463 through 6473**. Generic RPC
documents **6463 through 6472**. The dedicated connector and HTTP publisher retain
the Certified Devices range; generic `RPCWebSocketConnector` retains its own
range. The disagreement remains open in the ambiguity register. No common
resolved range or automatic service scan is claimed.

## Local bounds and qualification

All resource limits are local safety policy, not published Discord quotas:

| Resource | Local bound |
| --- | --- |
| Device ID or related ID | 1,024 UTF-8 bytes, nonblank and control-free |
| Product name | 256 UTF-8 bytes, nonblank and control-free |
| Related devices | 64 unique identifiers |
| Product URL | 2,048 UTF-8 bytes, absolute HTTP(S), no user information or fragment |
| Complete device count | Default 128; configurable through 1,024 |
| HTTP nonce | 128 UTF-8 bytes, nonblank and control-free |
| HTTP request bytes / response bytes | Default 262,144 / 65,536; configurable through 1 MiB |
| RPC argument bytes / certified WebSocket message bytes | Default 262,144 each; configurable through 1 MiB |

Duplicate `(type,id)` pairs fail before I/O; the same native ID can describe
different types. Complete RPC frame and aggregate pending/event budgets are
independent limits configured on the RPC runtime. JSON depth and node bounds also
apply. No automatic generic batching, device deduplication, mutation retry or
unbounded queue is introduced.

Swift Testing suites use deterministic HTTP and WebSocket peers and injected
clocks. They cover projection, optional input capabilities, full-array replacement,
priority, empty clearing, range endpoints, origin policy, rejection/error paths,
redaction, cancellation, deadlines and cleanup. This is local protocol evidence.
No real desktop service, approved beta account, certified hardware, Windows native
device API or live application approval has been qualified.
