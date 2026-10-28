<!--
File: Tools/DAVEInterop/README.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Offline initial DAVE candidate interoperability

This explicit development tool uses unmodified
[Cisco MLS++](https://github.com/cisco/mlspp/tree/fc724c3100ce3b5d8565dbd6d93648a440991a8c)
revision `fc724c3100ce3b5d8565dbd6d93648a440991a8c` as an independent decoder,
signature/reference verifier and Welcome recipient. It is never selected by a
DiscordKit product or ordinary test run. No source is vendored and the tool never
fetches dependencies. CMake rejects a different or dirty reference checkout.

Provision CMake 3.20+, a C++17 compiler, OpenSSL 1.1.1+ (tested with 3.0.18),
nlohmann-json (tested with 3.11.3), and the pinned MLS++ checkout explicitly.
Keep external build directories outside that clean checkout. For example, with
those dependencies already provisioned:

```sh
cmake -S Tools/DAVEInterop -B .build/dave-interop-native \
  -DMLSPP_SOURCE=/path/to/clean/mlspp \
  -DCMAKE_PREFIX_PATH=/path/to/dependency/prefix \
  -DCMAKE_BUILD_TYPE=Release
cmake --build .build/dave-interop-native --target DAVEInterop -j 8
DISCORDKIT_DAVE_INTEROP_EXECUTABLE="$PWD/.build/dave-interop-native/DAVEInterop" \
  swift test --filter MLSNativeDAVEInteropTests
```

OpenSSL may instead be selected explicitly with `OPENSSL_INCLUDE_DIR`,
`OPENSSL_CRYPTO_LIBRARY` and `OPENSSL_SSL_LIBRARY`. The Apple Swift 6.4 toolchain
used for the recorded run requires the repository's normal writable caches and
local execution permissions. The opt-in Swift test is available on macOS/Linux;
only macOS arm64 was run here. No CI pass is implied by these commands.

Each of the five test cases launches a fresh native recipient. The native process
retains its own generated signing, leaf and invitation private keys and emits
only a public KeyPackage over an anonymous pipe. Swift constructs the initial
DAVE-profile group and external Add, prepares a candidate, selects its exact echo
locally and sends synthetic public messages plus a transient expected epoch
authenticator to the native process through another anonymous pipe. No private
key crosses the process boundary. No messages or secrets are written to fixture
files, command arguments or diagnostic output. The reference child has a
15-second watchdog and is joined on every exit.

The reference independently checks:

- Complete versioned public MLSMessage followed immediately by a **bare** Welcome,
  exact consumption and byte-identical reserialization.
- Group ID, epoch zero, member sender zero, external Add signature and proposal
  reference, and the public commit signature under the initial GroupContext.
- A fresh UpdatePath retaining the original signer credential/key, its leaf
  signature, ciphersuite and exact Welcome recipient reference.
- Inline-tree Welcome join with MLS++'s tree, signature, HPKE, key-schedule and
  confirmation validation, followed by matching epoch-one authenticator bytes.
- Rejection of a wrapped Welcome, truncation, modified commit signature and
  modified encrypted Welcome.

The native process prints only `accepted` or `rejected:` plus a fixed stage;
the public-package startup line stays inside the test pipe. It deliberately does
not log native exception descriptions. The initial commit's membership MAC
cannot be independently checked without the creator's prior secret; this test
neither exports that secret nor claims that check. Full peer commit acceptance,
all membership transitions, DAVE media, native libdave session behavior, live
Discord acceptance and independent cryptographic review remain separate gates.
See [the scoped follow-up](../../Docs/DAVE.md).
