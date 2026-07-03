-- spike.livecodescript - de-risking spike: LiveCode's built-in HTTPD Library,
-- published as a Tor onion service by OnionXT.
--
-- WHAT THIS PROVES (the one test that de-risks the onion-hosting platform):
--   1. LiveCode's built-in HTTPD Library can own the loopback socket and parse
--      HTTP requests, while OnionXT publishes an onion that forwards to it. So we
--      REUSE a mature request/response engine instead of writing our own.
--   2. oxPublishService (publish-only: ADD_ONION with NO OnionXT accept loop)
--      composes cleanly with an external server.
--   3. The loopback guard holds when the app, not OnionXT, owns the accept: a
--      Tor-forwarded visitor (from 127.0.0.1) is served; a routable LAN peer is
--      rejected before any response.
--
-- HOW TO RUN: make a new mainstack, set its stack script to this file, put
-- onionxt.livecodescript in the message path (start using it as a library), and
-- have a tor daemon with the control port enabled (see the OnionXT README
-- Troubleshooting section). Click Start, wait for "reachable", then open the
-- printed http://<address>.onion/ in Tor Browser.
--
-- ON-ENGINE UNKNOWNS this spike exists to settle (flagged VERIFY: below):
--   A. Is the built-in HTTPD Library present in OpenXTalk? (It shipped in the
--      open-source LiveCode 9 that OXT forked from, so probably yes.) If not,
--      swap in lchttpd (MIT), which has the same accept + callback shape.
--   B. Does httpdStart bind the port we ask for, or fall back to an ephemeral
--      port when it is busy/reserved? We need the ACTUAL bound port to publish.
--   C. Does the HTTPD Library tolerate the app `close socket`-ing a peer it owns
--      (our loopback-reject path)?

constant kSpikeVirtualPort = 80      -- the onion's public port (so the URL needs no :port)
constant kSpikeLocalPort = 8090      -- loopback port the HTTPD Library binds (8080 is often reserved)
constant kSpikeControlPort = 9051    -- system tor control port (Tor Browser: 9151, and enable it)
constant kSpikeSocksPort = 9050

local sSvcHandle        -- OnionXT service handle, or empty
local sHttpdStarted     -- true once httpdStart succeeded
local sOnionAddress     -- the <56>.onion once ADD_ONION replies

on preOpenStack
   set the width of this stack to 660
   set the height of this stack to 420
   oxSetCallbackOwner the long id of me
   oxSetStatusCallback "onStatus"
   spikeBuildUI
   pass preOpenStack
end preOpenStack

private command spikeBuildUI
   create button "spike:start"
   set the rect of button "spike:start" to "24,20,164,52"
   set the label of button "spike:start" to "Start"
   create button "spike:stop"
   set the rect of button "spike:stop" to "176,20,316,52"
   set the label of button "spike:stop" to "Stop"
   create field "spike:url"
   set the rect of field "spike:url" to "24,64,636,90"
   set the lockText of field "spike:url" to true
   set the opaque of field "spike:url" to true
   set the textFont of field "spike:url" to "Courier"
   set the dontWrap of field "spike:url" to true
   put "(the .onion URL will appear here once published)" into field "spike:url"
   create field "spike:out"
   set the rect of field "spike:out" to "24,102,636,396"
   set the lockText of field "spike:out" to true
   set the opaque of field "spike:out" to true
   set the textFont of field "spike:out" to "Courier"
   set the vScrollbar of field "spike:out" to true
   put empty into field "spike:out"
end spikeBuildUI

on mouseUp
   local tName
   put the short name of the target into tName
   if tName is "spike:start" then
      spikeStart
   else if tName is "spike:stop" then
      spikeStop
   end if
end mouseUp

private command spikeStart
   local tErr
   put empty into field "spike:out"
   put empty into sOnionAddress
   spikeLog "connecting to the tor control port 127.0.0.1:" & kSpikeControlPort & " ..."
   oxSetControlPort kSpikeControlPort
   oxSetSocksPort kSpikeSocksPort
   oxConnectControl
   put the result into tErr
   if tErr is not empty then
      spikeLog "control connect error: " & tErr
   end if
end spikeStart

-- Once the control port authenticates, start the external HTTP server and publish
-- an onion that forwards to it. OnionXT never touches the socket.
on onStatus pKind, pInfo
   if pKind is "control" then
      if pInfo is "authenticated" then
         spikeLog "control authenticated; starting the HTTPD Library + publishing the onion"
         spikePublish
      else if pInfo begins with "authfailed" or pInfo begins with "error" then
         spikeLog "control error: " & pInfo
      else
         spikeLog "control: " & pInfo
      end if
   else if pKind is "service" then
      put pInfo into sOnionAddress
      put "http://" & pInfo & "/" into field "spike:url"
      spikeLog "onion address published: " & pInfo
   else if pKind is "serviceReady" then
      spikeLog "REACHABLE - open  http://" & sOnionAddress & "/  in Tor Browser now"
   end if
end onStatus

private command spikePublish
   local tErr
   -- Start LiveCode's built-in HTTPD Library on the loopback port. It owns the
   -- accept loop, parses each request, and hands us (socket id, request array).
   httpdStart kSpikeLocalPort, "onHttpRequest"
   put the result into tErr
   if tErr is not empty then
      spikeLog "httpdStart error: " & tErr
      exit spikePublish
   end if
   put true into sHttpdStarted
   spikeLog "HTTPD Library started on 127.0.0.1:" & kSpikeLocalPort
   -- VERIFY (B): confirm httpd actually bound kSpikeLocalPort and did not fall back
   -- to an ephemeral port. If the library reports a different bound port, publish
   -- THAT value instead of kSpikeLocalPort.
   oxPublishService kSpikeVirtualPort, kSpikeLocalPort
   put the result into sSvcHandle
   if sSvcHandle is an integer then
      spikeLog "onion publishing (virtual port " & kSpikeVirtualPort & " -> 127.0.0.1:" & kSpikeLocalPort & ") ..."
   else
      spikeLog "publish failed: " & sSvcHandle
   end if
end spikePublish

-- The HTTPD Library request callback: (socket id, an array with method / resource
-- / parameters / headers / content). We enforce loopback, then reply.
on onHttpRequest pSocket, pRequest
   if not spikeIsLoopback(pSocket) then
      -- SECURITY: `accept connections on port` binds all interfaces, so a LAN peer
      -- can reach this port directly, bypassing Tor. Tor forwards from 127.0.0.1;
      -- anything else is refused before a byte of response. (VERIFY C: that the
      -- HTTPD Library tolerates us closing a peer it owns.)
      spikeLog "rejected non-loopback visitor: " & pSocket
      close socket pSocket
      exit onHttpRequest
   end if
   spikeLog "served " & pRequest["method"] & " " & pRequest["resource"] & " to " & pSocket
   httpdResponse pSocket, 200, spikePage(), "Content-Type: text/html; charset=utf-8"
end onHttpRequest

private function spikeIsLoopback pSocket
   -- The accepted-socket id is "<peerhost>:<port>" (maybe with a |suffix). Accept
   -- every loopback spelling; reject a routable peer. (Mirrors OnionXT's own guard.)
   local tHost, tSaved
   put the itemDelimiter into tSaved
   set the itemDelimiter to ":"
   put item 1 of pSocket into tHost
   set the itemDelimiter to tSaved
   if tHost is empty then
      return true
   end if
   if tHost is "127.0.0.1" or tHost begins with "127." then
      return true
   end if
   if tHost is "localhost" then
      return true
   end if
   if "::1" is in pSocket then
      return true
   end if
   return false
end spikeIsLoopback

private function spikePage
   -- Single-quoted HTML attributes (livecodescript string literals are
   -- double-quote-delimited with no escape).
   local tH
   put "<!doctype html>" & return into tH
   put "<html><head><meta charset='utf-8'><title>OnionXT + HTTPD Library</title></head>" & return after tH
   put "<body style='font-family:system-ui,sans-serif;max-width:38em;margin:3em auto;padding:0 1em;line-height:1.5'>" & return after tH
   put "<h1>The composition works.</h1>" & return after tH
   put "<p>This page is served by LiveCode's built-in <strong>HTTPD Library</strong>, published as a Tor v3 onion service by <strong>OnionXT</strong> (oxPublishService), inside an OpenXTalk app.</p>" & return after tH
   put "<p>OnionXT provides the address and the tor forwarding; the HTTPD Library owns the socket and parses the request. Two libraries, one hassle-free onion host.</p>" & return after tH
   put "</body></html>" & return after tH
   return tH
end spikePage

private command spikeStop
   if sHttpdStarted is true then
      httpdStop
      put false into sHttpdStarted
      spikeLog "HTTPD Library stopped"
   end if
   if sSvcHandle is an integer then
      oxRemoveService sSvcHandle
      put empty into sSvcHandle
      spikeLog "onion removed (DEL_ONION)"
   end if
   oxDisconnectControl
end spikeStop

on closeStack
   spikeStop
   oxShutdown
   pass closeStack
end closeStack

private command spikeLog pText
   put pText & return after field "spike:out"
   set the scroll of field "spike:out" to the formattedHeight of field "spike:out"
end spikeLog
