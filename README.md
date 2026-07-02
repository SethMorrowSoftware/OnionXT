# OnionXT

**Tor transport and self-authenticating rendezvous for OpenXTalk (OXT) / the xTalk family.**

OnionXT gives xTalk apps two things by talking to a **locally-running Tor daemon** (it does not
embed or ship Tor):

1. **IP anonymity for any TCP stream** - dial out through Tor's SOCKS5 proxy, so a peer, a tracker,
   a broker, or a server never learns your IP address, and you never learn theirs.
2. **Self-authenticating rendezvous** - create and reach **v3 onion services**, whose address *is*
   an ed25519 public key. Connecting to `<56-char-base32>.onion` cryptographically proves you
   reached the holder of that key, with no certificate authority, no DNS, and no key-distribution
   step that a man-in-the-middle can hijack.

```
   tor daemon (already running: Tor Browser, system tor, or a bundled binary)
      |  127.0.0.1:9050  SOCKS5 proxy        (outbound: dial a .onion or clearnet host)
      |  127.0.0.1:9051  control port         (inbound: ADD_ONION, events, bootstrap)
      v
   OnionXT (ox*)   src/onionxt.livecodescript
      |- speaks SOCKS5 (RFC 1928) over an engine socket        -> dial
      |- speaks the Tor control protocol over an engine socket -> publish an onion service
      |- runs a local accept loop that Tor forwards inbound onion traffic to
            |
            +--> composes SodiumXT (sx*) for the payload and for deterministic onion keys
            +--> plugs into Riptide (rt*) as the `ox` transport (doc 06)
```

## Why this matters

[Riptide](https://github.com/SethMorrowSoftware/RipTide) documents "no IP anonymity by default" and "incomplete metadata privacy" as
open, unsolved items in its threat model (its rung-4 adversary). OnionXT is the direct answer:
route Riptide's transport through Tor and swap DHT rendezvous for onion-service rendezvous, and the
IP-layer metadata the DHT and direct peer connections leak simply stops being emitted. OnionXT is
useful on its own (any xTalk app that wants an anonymous socket or a serverless, self-authenticating
inbound address), and it is the metadata-privacy upgrade path for the whole secure-comms family.

## What OnionXT is NOT

- **It is not Tor, and it does not bundle Tor.** It assumes a tor daemon is reachable on the loopback
  SOCKS and control ports. Launching or bundling a tor binary is an optional convenience layer
  (doc 07), never a requirement, and never a reimplementation of onion routing.
- **It adds no cryptography.** ed25519 identity, key derivation, and the payload sealing are all
  SodiumXT calls. OnionXT is a transport and a naming layer, not a cipher.
- **It is not an anonymity guarantee by itself.** Tor defends the network path; it does not defend
  against a global passive adversary doing traffic correlation, against a compromised local daemon,
  or against you connecting to the wrong onion address. See [docs/01-threat-model.md](docs/01-threat-model.md).

## Layout

```
OnionXT/
  README.md                 you are here
  CLAUDE.md                 the operational guide + all carried OXT/LCB/FFI lessons (read first)
  IMPLEMENTATION-PLAN.md    the phased build order
  docs/
    00-overview.md          architecture and the composition story
    01-threat-model.md      what Tor buys, what it does not, and the honesty rules
    02-socks5-client.md     the SOCKS5 dial path (RFC 1928 + Tor's extensions), byte for byte
    03-control-port.md      the Tor control protocol: auth, ADD_ONION, events, bootstrap
    04-onion-rendezvous.md  v3 onion == ed25519 pubkey; deterministic onions from a seed
    05-api-reference.md     the public ox* surface
    06-riptide-integration.md   OnionXT as a Riptide transport
    07-tor-lifecycle.md     assume-running vs launch-a-bundled-binary; bootstrap UX
    08-capabilities-required.md the small upstream gaps (SodiumXT SHA-512 / ed25519 expansion)
    09-open-questions.md    the honest to-do list
    10-usage-guide.md       from-zero guide for any OXT app that uses OnionXT
  tools/
    check-livecodescript.py the static gate (carried verbatim from the family)
    check-docs-style.py     the prose house-style gate (no dashes / curly quotes)
    onion-kat.py            known-answer vectors: base32, v3 address, ed25519 seed
  .github/workflows/ci.yml  the three gates above, on every push / PR
  src/
    onionxt.livecodescript  the library (public ox* handlers, implemented)
  examples/
    socks-dial/             dial a host through Tor and read the reply
    onion-roundtrip/        two instances talk over Tor with no server, sealed by SodiumXT
```

## Status

The library is **implemented**: `src/onionxt.livecodescript` has the full public `ox*` surface built
out byte-for-byte against the specs (SOCKS5 dial, control-port connect + all four auth methods, onion
services with a loopback accept loop, deterministic-from-seed addresses, base32 and the address<->key
mapping, events and bootstrap, idempotent teardown, and the Riptide transport seam). It composes
SodiumXT for every hash / HMAC / signature and adds no cryptography of its own.

It has **not run on an OXT engine yet.** The pure-compute paths (base32, the v3 address, the ed25519
seed derivation) are pinned by known-answer vectors in `tools/onion-kat.py` and verified against two
real onion addresses; the socket handshakes are designed and statically reasoned and are marked
"designed and statically reasoned; needs an on-engine pass" against a real tor daemon, with each
on-engine unknown flagged `VERIFY:` in the source. The static and house-style gates and the KAT
self-check pass in CI. Start with [CLAUDE.md](CLAUDE.md), the [usage guide](docs/10-usage-guide.md),
and [IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md).

## House style

ASCII only in `.livecodescript` / `.lcb`. No em-dashes anywhere (hyphens, commas, colons,
parentheses). Comment the *why*, densely. These are enforced by `tools/check-livecodescript.py` and
the docs-style CI job, and they are not optional: curly quotes fail OXT compilation outright.
