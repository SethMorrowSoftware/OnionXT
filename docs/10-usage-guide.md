# 10 - Usage Guide (for any OXT / LiveCode app)

OnionXT is useful to any OpenXTalk / LiveCode app that wants an anonymous socket or a serverless,
self-authenticating inbound address, not only to Riptide. This is the from-zero guide: how to load the
library, point it at a tor daemon, dial out, publish an onion service, handle the callbacks, compose
SodiumXT for the parts OnionXT deliberately does not do, and read the honesty caveats.

> OnionXT is livecodescript and has not yet run on an OXT engine. Everything below is the intended API
> and the intended shape of a program that uses it; confirm the on-engine behaviour against a real tor
> daemon before you rely on it (CLAUDE.md: "designed and statically reasoned; needs an on-engine pass").

## 1. Start a tor daemon

OnionXT talks to a locally-running tor; it does not embed or ship one. Any of these works:

- **Tor Browser** - SOCKS on `127.0.0.1:9150`, control on `127.0.0.1:9151`. You may need to enable the
  control port and cookie auth in its config.
- **System tor** (a package on Linux/macOS, or a service) with this bring-up `torrc`:

```
SocksPort 9050
ControlPort 9051
CookieAuthentication 1
```

Dialing out needs only the SOCKS port. Publishing an onion service, and reading bootstrap/events, needs
the control port and an auth method (cookie auth above, or `HashedControlPassword`).

## 2. Load the library

Put `onionxt.livecodescript` in the message path so its `ox*` handlers resolve, for example:

```
start using stack "onionxt"          -- if you wrap the script in a stack
-- or insert the script of the library into the back / a library stack
```

If you also want deterministic onion addresses, SAFECOOKIE control auth, or offline address validation,
load **SodiumXT** the same way: OnionXT composes its `sx*` primitives and degrades to a clear error when
one is missing (see section 7). Tell OnionXT which object your callbacks live in:

```
oxSetCallbackOwner the long id of me
```

(If you skip this, OnionXT dispatches callbacks to the topStack, which is usually but not always your
app's stack.)

## 3. Dial a host through Tor (outbound)

`oxDial` reports a stream handle immediately; the SOCKS handshake finishes asynchronously and your
stream callback receives `"open"` (or `"error"`). The far end never learns your IP, and the name is
resolved inside Tor (ATYP=3), never by a local DNS lookup.

```
local sStream

on connectOut
   oxSetSocksPort 9050                      -- 9150 for Tor Browser
   oxSetCallbackOwner the long id of me
   oxDial "example.onion", 80               -- a .onion or a clearnet name
   put the result into sStream
   if sStream is not an integer then
      answer "Dial failed:" && sStream      -- a mapped SOCKS error string
      exit connectOut
   end if
   oxSetStreamCallback sStream, "onStream"
end connectOut

on onStream pStream, pEvent, pData
   if pEvent is "open" then
      -- The tunnel is live. OnionXT does not encrypt: seal with SodiumXT first
      -- if you need confidentiality/integrity. textEncode before writing text.
      oxWrite pStream, textEncode("hello" & numToChar(10), "UTF-8")
   else if pEvent is "data" then
      put pData after field "log"            -- your protocol frames the bytes
   else if pEvent is "closed" then
      put "-- closed --" & return after field "log"
   else if pEvent is "error" then
      answer "Stream error:" && pData        -- already torn down; fail closed
   end if
end onStream
```

Close a stream you are done with (idempotent): `oxCloseStream sStream`.

## 4. Publish an onion service (inbound)

Being reachable needs the control port. `oxConnectControl` connects and authenticates asynchronously;
watch the status callback for `"control","authenticated"`, then publish. OnionXT starts the loopback
listener before `ADD_ONION`, so a peer that connects the instant the descriptor publishes is answered.

```
local sService

on goOnline
   oxSetControlPort 9051                     -- 9151 for Tor Browser
   oxSetCallbackOwner the long id of me
   oxSetStatusCallback "onStatus"
   oxSetPeerCallback "onPeer"
   oxConnectControl                          -- completes via onStatus
end goOnline

on onStatus pKind, pInfo
   if pKind is "control" and pInfo is "authenticated" then
      oxCreateService 80, 8080               -- virtual port 80 -> loopback 8080
      put the result into sService
   else if pKind is "service" then
      put "Reachable at" && pInfo into field "myAddress"   -- <56>.onion
   else if pKind is "serviceReady" then
      -- The descriptor uploaded; the address is now reachable from the network.
   else if pKind is "bootstrap" then
      set the label of this stack to "Tor" && pInfo & "%"  -- coalesced to ~4 Hz
   end if
end onStatus

on onPeer pStream, pService, pPeerAddr
   -- A remote peer reached your onion. pStream is a fresh inbound stream handle
   -- that behaves exactly like a dialed one; register a callback and reply.
   oxSetStreamCallback pStream, "onPeerStream"
end onPeer

on onPeerStream pStream, pEvent, pData
   if pEvent is "data" then
      oxWrite pStream, pData                  -- echo (seal with SodiumXT in real use)
   end if
end onPeerStream
```

Remove a service (idempotent): `oxRemoveService sService`.

## 5. Deterministic, reproducible addresses

`oxCreateService` lets Tor pick a random key. For an address that survives a reinstall and doubles as a
published identity key, derive it from a 32-byte seed (composes SodiumXT; see section 7):

```
oxCreateServiceFromSeed tSeed, 80, 8080      -- same seed -> same .onion, always
```

And convert between an address and its ed25519 public key (base32 is pure; the checksum needs SodiumXT
SHA3-256, so `oxAddressFromPublicKey` returns a clear error if that primitive is absent):

```
put oxPublicKeyFromAddress("....onion") into tPubKey   -- 32 bytes, no crypto needed
put oxAddressFromPublicKey(tPubKey) into tAddress       -- needs sxSha3_256
if oxIsValidAddress(tPasted) then ...                   -- structural, + checksum if available
```

## 6. Shutdown

There is no deterministic unload hook in OXT, so free what you opened, for example on `closeStack`.
`oxShutdown` closes every stream, removes every service, and disconnects control, and is safe to call
twice:

```
on closeStack
   oxShutdown
end closeStack
```

## 7. What OnionXT does NOT do (compose SodiumXT)

OnionXT is a transport and a naming layer. It adds **no cryptography**. The bytes it carries are
protected only if you sealed them with SodiumXT before `oxWrite` and open them after the `"data"`
event. A few OnionXT features compose SodiumXT primitives and degrade to a clear error string when the
primitive is missing (see docs/08); check availability with:

```
put oxTransportInfo() into tInfo            -- an array of capability flags
-- tInfo["safeCookieAuth"]     needs sxHmacSha256 + sxRandomBytes
-- tInfo["deterministicOnion"] needs sxSignSeedToExpandedKey or sxSha512
-- tInfo["offlineAddress"]     needs sxSha3_256
```

When a primitive is absent, OnionXT falls back where it safely can (SAFECOOKIE -> COOKIE control auth,
for instance) and otherwise returns `"OnionXT: ... needs SodiumXT sxXxx (see docs/08)"` rather than
hand-rolling a hash.

## 8. Honesty caveats (read before you ship)

- **Tor is not total anonymity.** It defends the network path against a non-global adversary. Traffic
  correlation by a global passive adversary, a compromised local tor daemon, and descriptor/activity
  timing all remain (docs/01, docs/09). Say "IP-anonymous against a non-global adversary," not
  "untraceable."
- **The address authenticates the key, not the person.** Reaching `<56>.onion` proves you reached the
  holder of that ed25519 key, but if you were tricked into using the wrong address, Tor faithfully
  connects you to the attacker. Pin or verify the address (bind it into a SodiumXT signature at first
  contact) exactly as Riptide does.
- **Seal your payload.** OnionXT moves bytes; confidentiality, integrity, and replay protection are
  SodiumXT's job and must be done.
- **Bootstrapping is slow and visible.** A cold tor takes tens of seconds; an onion service takes
  seconds more to publish. Surface progress from the status callback; never freeze the UI.

## 9. Callback and error reference

| Callback | Signature | Delivered when |
|---|---|---|
| status | `pKind, pInfo` | control state, bootstrap %, service address/ready, raw events |
| stream | `pStream, pEvent, pData` | `open` / `data` / `closed` / `error` on a dialed or inbound stream |
| peer   | `pStream, pService, pPeerAddr` | a remote peer connected to a published service |

Commands that yield a handle (`oxDial`, `oxCreateService`, `oxCreateServiceFromSeed`) report the integer
handle through `the result` on success, or a human-readable `"OnionXT: ..."` string on failure; test
`the result is an integer`. Other commands report empty on success or an error string on failure. Every
wire error fails closed and tears the resource down; there is no silent fallback to an unproxied or
unauthenticated path.
