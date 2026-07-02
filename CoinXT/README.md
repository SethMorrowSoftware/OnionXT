# CoinXT

**Bitcoin and Ethereum cryptography for OpenXTalk (OXT) / the xTalk family.**

CoinXT gives an xTalk app the primitives a wallet or a dapp client is built from, by wrapping
**trezor-crypto** (the MIT-licensed, dependency-free C crypto core of the Trezor hardware wallet) behind
a thin C ABI and a livecodescript API. One wrap covers both chains:

- **secp256k1** keypairs, ECDSA (RFC 6979 deterministic), **recoverable** signatures and public-key
  recovery (Ethereum's `v` / `ecrecover`), ECDH, and Schnorr / BIP-340 (Taproot).
- **Hashes** both chains need: SHA-256/512, SHA3-256/512, **Keccak-256** (Ethereum's non-NIST padding),
  RIPEMD-160, plus HMAC and PBKDF2-HMAC-SHA512.
- **HD wallets:** BIP-32 derivation, BIP-39 mnemonics (SLIP-39 later).
- **Address and serialization formats:** Base58Check, Bech32 / Bech32m, hex, RLP, xprv/xpub, WIF, and the
  EIP-55 Ethereum checksum.

```
app (livecodescript)
   |
CoinXT (cx*)   src/coinxt.livecodescript
   |- encodings in SCRIPT   hex, Base58Check, Bech32/Bech32m, RLP, addresses (pure byte work)
   |- FFI seam              one .lcb module
CoinXT C shim (cnx_)   native/coinxt.c  +  vendored trezor-crypto (MIT, no external deps)
   |- curve + hashes in C   secp256k1, SHA2/SHA3/Keccak-256/RIPEMD-160, HMAC, PBKDF2, BIP-32, BIP-39
```

## What CoinXT is NOT

- **Not a wallet, node, or broadcaster.** It produces keys, addresses, and signed bytes. The app owns key
  storage, backup, the confirm-before-sign UX, and putting a signed transaction on the wire (optionally
  through Tor via OnionXT, a documentation-level composition).
- **Not new cryptography.** Every curve op and hash is trezor-crypto's. CoinXT adds no cipher of its own,
  the same rule SodiumXT and OnionXT hold.
- **Not hardware-wallet isolation.** It runs in a general-purpose OXT process; script variables are not
  locked memory. It is a strong, correct, self-contained crypto layer, not a secure element.

## Why trezor-crypto

MIT-licensed, plain C, **no external dependencies**, and it bundles secp256k1 (also MIT). That is exactly
what the family's FFI pattern wants: a self-contained C library with a buffer-in / buffer-out API and a
permissive license we can vendor and redistribute. It is the crypto core of a shipping hardware wallet,
so the curve and hash code is battle-tested. CoinXT vendors a subset of its `.c` files plus a small shim
and builds one shared library per platform. No autotools, no submodule tree.

## Layout (planned)

```
CoinXT/
  README.md                 you are here
  SPEC.md                   what CoinXT is: the C/script split, the ABI contract, formats, security model
  IMPLEMENTATION-PLAN.md    the phased build order
  CLAUDE.md                 the operational guide + the FFI/C-ABI law (read before touching the shim)
  native/
    coinxt.c                the C shim (cnx_ ABI over the vendored crypto)
    vendor/                 the vendored trezor-crypto subset (MIT) + VENDOR.md + LICENSE
    MANIFEST.sha256         hashes of the shipped binaries, vendored sources, and the wordlist
  src/
    coinxt.lcb              the foreign-handler module (binds to cnx_*)
    coinxt.livecodescript   the public cx* API + the script-side encodings
  tools/
    coin-kat.py             known-answer vectors (RFC 6979, BIP-32/39, BIP-173/350, EIP-55, Keccak)
  examples/
    coinxt-demo.livecodescript    keygen, addresses, sign/verify, an HD wallet from a mnemonic
    coinxt-tests.livecodescript   a pure, offline self-test harness (sPass/sFail, KATs)
```

## Status

**Design only. Nothing built yet.** [SPEC.md](SPEC.md), [IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md),
and [CLAUDE.md](CLAUDE.md) are the design; the code comes next, phase by phase, native seam and KAT
harness first. Every deterministic path will be pinned to a public known-answer vector, and the "done"
bar for a signing feature is that a CoinXT signature verifies in a mainstream external library, not just
in CoinXT.

This sub-project lives inside the OnionXT repository for now; it is an independent library (it does not
depend on OnionXT) and may move to its own repo later.

## A note on handling money

CoinXT deals with private keys and real funds, so the family's "compose an audited library, never
hand-roll crypto" rule counts double: the curve and hashes are trezor-crypto's, the app owns custody and
confirm-before-sign, and every checksum is verified on decode with a fail-closed error. See the security
model in [SPEC.md](SPEC.md) section 8 and the rules in [CLAUDE.md](CLAUDE.md).

## House style

ASCII only in `.livecodescript` / `.lcb`. No em-dashes anywhere (hyphens, commas, colons,
parentheses). Comment the *why*, densely. Enforced by the carried `check-livecodescript.py` and
`check-docs-style.py` gates.
