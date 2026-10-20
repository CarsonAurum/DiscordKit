# DAVE opcode 26 native wire correction — 2026-10-19

`DAVEProtocolSession` now sends opcode 26 followed directly by a bare TLS
KeyPackage. The previous command inserted the MLSMessage version/type prefix
`00 01 00 05` before that package. Client Voice binary messages contain the opcode
and payload only; the server's two-byte sequence prefix is not sent by clients.
Opcode 28 retains a complete Commit MLSMessage followed by a bare Welcome.

The [DAVE whitepaper](https://daveprotocol.com/#dave_mls_key_package-26) shows a
wrapped opcode-26 sketch, so this is an explicit source disagreement. The
[pinned libdave serializer](https://github.com/discord/libdave/blob/8de72b1f8a2ac3c5a5270755bb8091a62e3c6169/cpp/src/mls/session.cpp)
returns `tls::marshal(*joinKeyPackage_)`, a bare KeyPackage. The complete
[Discord.js DAVE owner](https://github.com/discordjs/discord.js/blob/03777df7f7cc372de88fd05cd3999ab59e5c36c0/packages/voice/src/networking/DAVESession.ts),
[network owner](https://github.com/discordjs/discord.js/blob/03777df7f7cc372de88fd05cd3999ab59e5c36c0/packages/voice/src/networking/Networking.ts)
and [WebSocket sender](https://github.com/discordjs/discord.js/blob/03777df7f7cc372de88fd05cd3999ab59e5c36c0/packages/voice/src/networking/VoiceWebSocket.ts)
forward Davey's `getSerializedKeyPackage()` and prepend only the opcode byte.
[Davey's binding](https://github.com/Snazzah/davey/blob/73bcec27b7190ce47088c831e0aa72600cc657e7/davey-node/src/session.rs)
returns [the Rust session's](https://github.com/Snazzah/davey/blob/73bcec27b7190ce47088c831e0aa72600cc657e7/davey/src/session.rs)
direct `KeyPackage.tls_serialize_detached()` output; neither layer adds an
MLSMessage wrapper.

An isolated offline regression generated actual unchanged SDK opcode-26 output
through public rendezvous, `DAVEProtocolSession.start` and `VoiceGatewayFrame.message`.
Cisco MLS++ `fc724c3100ce3b5d8565dbd6d93648a440991a8c` strict bare-KeyPackage decoding
failed on that output (exit 1). Removing only the four-byte MLSMessage wrapper
passed canonical full-consumption decoding, inner LeafNode and KeyPackage
signature checks, protocol 1/suite 2, distinct init/leaf keys, the basic eight-byte
synthetic Discord credential and supported capabilities (exit 0). Synthetic
public material crossed an anonymous pipe; no real credentials or private keys
were persisted. A Swift regression also fixes the exact opcode/version/suite
prefix and rejects confusing bare and wrapped representations. Existing DAVE
peer/recovery tests now decode the actual bare publication.

This evidence establishes a local wire integration defect and native representation
parity. It does not establish Discord service admission, accepted Commit/Welcome,
readiness, encrypted listening or the cause of an earlier deadline. A live wrapper
diagnostic stopped at credential access before any network session and supplies
no service evidence. Runtime behavior sends one encoding once; no fallback or
automatic retry is introduced.
