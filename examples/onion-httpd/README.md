# Hosting HTTP onion services in OpenXTalk

A working, self-contained example of hosting Tor onion services from an OXT app.
It serves HTTP over an onion using **OnionXT's own accept loop** via the
`src/onion-httpd.livecodescript` module (`oxh*`). It depends on nothing but
OnionXT and that module - no engine-shipped HTTPD Library (which is not present on
every OpenXTalk build), so it runs wherever OnionXT runs.

```
Tor  --(onion:80)-->  OnionXT accept loop (loopback-guarded, proven)
                          |  onPeer / onStreamData
                      onion-httpd (oxh*)  <- parses the request, routes it, replies
                          |
                      your route handlers  /  a folder of static files
```

## What the module gives you (`oxh*`)

| call | does |
|---|---|
| `oxhInit the long id of me` | tells the module where your route handlers live |
| `oxhServe pVirtualPort, pLocalPort` | publishes an onion and serves HTTP on it (returns the service handle) |
| `oxhRoute pMethod, pPath, pHandler` | registers a dynamic route; the handler is `pHandler pStream, pRequest` |
| `oxhSetRoot pFolder` | serves static files from a folder (`/` maps to `/index.html`, with MIME types and a path-traversal guard) |
| `oxhReply pStream, pCode, pBodyText, pHeaders` | sends a response from a route handler |
| `oxhStop pService` | tears the onion down |

A request array carries `__method`, `__path`, `__query`, `__body`, and the request
headers (lowercased). The module handles request framing (buffering until the
head and any `Content-Length` body have arrived), the exact-`Content-Length`
response, and the clean close.

## How to run

1. Make a new mainstack, set its stack script to `spike.livecodescript`.
2. Put **both** `src/onionxt.livecodescript` and `src/onion-httpd.livecodescript`
   in the message path (`start using` them as libraries).
3. Have a tor daemon with the **control port enabled** (see the OnionXT README
   Troubleshooting section: `ControlPort 9051` + `CookieAuthentication 1`).
4. Click **Start**, wait for `REACHABLE`, then open the printed
   `http://<address>.onion/` in **Tor Browser** and click between the two pages.

## Serving a static site instead

Drop this into `preOpenStack` (in place of, or besides, the routes):

```
oxhSetRoot "/full/path/to/your/site"
```

and every file under that folder is served by path, with `index.html` as the
default document. That is a complete static site, hosted anonymously, from your
own machine.

## Status / notes

- Built entirely on OnionXT primitives that are already confirmed on-engine (the
  accept loop, the loopback guard, chunked stream delivery, the write + clean
  close). The request parser and router are new livecodescript and want an
  on-engine pass, but they lean only on those proven building blocks.
- Single-threaded and blocking, like OnionXT itself: right for a lightweight
  self-hosting appliance (sites, forms, small apps, file drops), not a
  high-traffic server.
- If the local forward port (8090) reports `cannot listen ...`, it is reserved or
  in use; change `kLocalPort` to a free one (same Windows reserved-port note as
  the main demo).
- A note on the earlier `httpdStart` approach: LiveCode's built-in HTTPD Library
  is not loaded on this OXT engine, so this module replaces it with a small parser
  over OnionXT's accept loop. If you ever want a routing framework instead,
  [lchttpd](https://github.com/toddgeist/lchttpd) (MIT) is a pure-script drop-in.
