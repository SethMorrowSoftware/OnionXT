# Examples

Formatted like the sibling family's example stacks (SodiumXT's `sodium-demo.livecodescript` /
`sodium-tests.livecodescript`, TorrentXT's `examples/`).

| File | What it shows |
|---|---|
| `onionxt-demo.livecodescript` | An interactive, tabbed showcase of every public `ox*` feature: connect + bootstrap, dial through SOCKS5, publish an onion service and echo an inbound peer, the address/base32 tools, and the capability flags + a "Run self-test" button. Open it as a mainstack (see the header comment for the exact load order). |
| `onionxt-tests.livecodescript` | A pure, offline self-test harness: module-level `sLog`/`sPass`/`sFail`, an `oxCheck`/`oxSection` assertion pair, and known-answer vectors cross-checked against `tools/onion-kat.py`. Call `oxSelfTest()` directly, or use the demo's "Run self-test" button. Read its header before extending it: it deliberately does not attempt a live daemon handshake (see the header for why). |
| `socks-dial/` | The thinnest slice: dial a host through Tor and read the reply. No control port needed. |
| `onion-roundtrip/` | The headline milestone: two instances talk over Tor with no server, sealed by SodiumXT. |

All of these are designed and statically reasoned against the specs, like the library itself; they have
not run on an OXT engine yet (CLAUDE.md: "designed and statically reasoned; needs an on-engine pass").
