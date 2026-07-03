# Spike: HTTPD Library + OnionXT

A tiny de-risking spike for the onion-hosting platform. It proves one thing: that
**LiveCode's built-in HTTPD Library can serve an onion service that OnionXT
publishes**, so the platform reuses a mature HTTP request/response engine instead
of building one.

```
Tor  --(onion:80)-->  127.0.0.1:8090        <- LiveCode's HTTPD Library binds + parses
                          |
                      onHttpRequest(pSocket, pRequest)   <- loopback guard, then reply
                          |
                      httpdResponse(pSocket, 200, page, headers)

OnionXT: oxPublishService 80, 8090   <- ADD_ONION forwards the onion to :8090, NO accept loop
```

## What it exercises

1. **`oxPublishService` (new, publish-only).** `ADD_ONION` maps the onion's virtual
   port to `127.0.0.1:8090`, but OnionXT does NOT start its own accept loop, so an
   external server can own that port. Teardown `DEL_ONION`s the service and leaves
   the socket alone.
2. **The built-in HTTPD Library** (`httpdStart` / `httpdResponse` / `httpdStop`,
   Andre Garzia). It owns the socket, parses each request into
   `method` / `resource` / `parameters` / `headers` / `content`, and hands the
   callback `(socket id, request array)`. The reply is one `httpdResponse` call
   (it sets `Content-Length` / `Date` / `Server` / `Connection` for us).
3. **The loopback guard, app-side.** Because `accept connections on port` binds all
   interfaces, `onHttpRequest` rejects any non-`127.0.0.1` peer before responding,
   exactly as OnionXT's own accept loop does. Tor forwards from loopback; a LAN
   scanner is refused.

## How to run

1. Make a new mainstack, set its stack script to `spike.livecodescript`.
2. Put `src/onionxt.livecodescript` in the message path (`start using` it as a
   library).
3. Have a tor daemon with the **control port enabled** (see the OnionXT README
   Troubleshooting section: `ControlPort 9051` + `CookieAuthentication 1`).
4. Click **Start**. Watch the log reach `control authenticated`, then the
   `.onion` address appears, then `REACHABLE`.
5. Open the printed `http://<address>.onion/` in **Tor Browser**. Success is the
   "The composition works." page.

## Success / failure signals

- **Success:** the page renders in Tor Browser, and the log shows
  `served GET / to 127.0.0.1:...`.
- **`cannot listen ...` at start:** the local port (8090) is reserved/in use; edit
  `kSpikeLocalPort` to a free one (this is the same Windows reserved-port issue the
  main demo documents).
- **Empty response in Tor Browser but no `served ...` log line:** Tor is not
  forwarding into the HTTPD Library. The likely cause is the port-binding unknown
  below (httpd bound a different port than we published).

## On-engine unknowns this spike settles (the point of a spike)

- **A. Is the HTTPD Library present in OpenXTalk?** It shipped in the open-source
  LiveCode 9 that OXT forked from, so probably yes. If `httpdStart` is unknown on
  the OXT engine, swap in [lchttpd](https://github.com/toddgeist/lchttpd) (MIT),
  which has the same accept + callback shape (and adds Express-style routing).
- **B. Does `httpdStart` bind the port we ask for, or fall back to an ephemeral
  port when it is busy/reserved?** We need the ACTUAL bound port to publish. If the
  library reports a different port, publish THAT value in `spikePublish`.
- **C. Does the HTTPD Library tolerate the app `close socket`-ing a peer it owns**
  (the loopback-reject path)? If not, reject by replying `403` instead of closing.

Once these are confirmed on-engine, the platform architecture is de-risked: the
HTTP engine is reuse, not build, and the net-new work is the tor lifecycle
(Mode B), the service manager, presets, and access control.
