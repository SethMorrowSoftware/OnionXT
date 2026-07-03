-- spike.livecodescript - host onion services in OpenXTalk, self-contained.
--
-- This is the WORKING path: it serves HTTP over a Tor onion using OnionXT's own
-- accept loop via the onion-httpd.livecodescript module (oxh*). It needs NOTHING
-- but OnionXT + this module - no engine-shipped HTTPD Library (which is not
-- present on every OXT build). It publishes an onion and serves two routes, to
-- show how easily an app hosts a variety of content.
--
-- HOW TO RUN: make a new mainstack, set its stack script to this file, and put
-- BOTH src/onionxt.livecodescript AND src/onion-httpd.livecodescript in the
-- message path (start using them as libraries). Have a tor daemon with the
-- control port enabled (OnionXT README Troubleshooting). Click Start, wait for
-- "REACHABLE", then open the printed http://<address>.onion/ in Tor Browser and
-- click around.

constant kVirtualPort = 80       -- the onion's public port (URL needs no :port)
constant kLocalPort = 8090       -- loopback forward port (8080 is often reserved)
constant kControlPort = 9051     -- system tor control port (Tor Browser: 9151)
constant kSocksPort = 9050

local sSvcHandle
local sOnionAddress

on preOpenStack
   set the width of this stack to 660
   set the height of this stack to 420
   oxSetCallbackOwner the long id of me
   oxSetStatusCallback "onStatus"
   oxhInit the long id of me                    -- route handlers live in this stack
   oxhRoute "GET", "/", "pageHome"
   oxhRoute "GET", "/about", "pageAbout"
   -- To serve a folder of static files instead of (or besides) routes:
   --   oxhSetRoot "/full/path/to/your/site"
   demoBuildUI
   pass preOpenStack
end preOpenStack

-- Route handlers: (stream, request array). Reply with oxhReply.
command pageHome pStream, pRequest
   oxhReply pStream, 200, homeHtml(), "Content-Type: text/html; charset=utf-8"
   demoLog "served GET / to " & pStream
end pageHome

command pageAbout pStream, pRequest
   oxhReply pStream, 200, aboutHtml(), "Content-Type: text/html; charset=utf-8"
   demoLog "served GET /about to " & pStream
end pageAbout

-- Control lifecycle: connect, then publish + serve once authenticated.
on onStatus pKind, pInfo
   if pKind is "control" then
      if pInfo is "authenticated" then
         demoLog "control authenticated; publishing the onion and serving HTTP"
         oxhServe kVirtualPort, kLocalPort
         put the result into sSvcHandle
         if sSvcHandle is an integer then
            demoLog "serving (onion port " & kVirtualPort & " -> 127.0.0.1:" & kLocalPort & ") ..."
         else
            demoLog "serve failed: " & sSvcHandle
         end if
      else if pInfo begins with "authfailed" or pInfo begins with "error" then
         demoLog "control error: " & pInfo
      else
         demoLog "control: " & pInfo
      end if
   else if pKind is "service" then
      put pInfo into sOnionAddress
      put "http://" & pInfo & "/" into field "demo:url"
      demoLog "onion address: " & pInfo
   else if pKind is "serviceReady" then
      demoLog "REACHABLE - open  http://" & sOnionAddress & "/  in Tor Browser now"
   end if
end onStatus

private function homeHtml
   local tH
   put "<!doctype html>" & return into tH
   put "<html><head><meta charset='utf-8'><title>Hosted in OpenXTalk</title></head>" & return after tH
   put "<body style='font-family:system-ui,sans-serif;max-width:38em;margin:3em auto;padding:0 1em;line-height:1.5'>" & return after tH
   put "<h1>Hosted in OpenXTalk, over Tor.</h1>" & return after tH
   put "<p>This onion service runs entirely inside an OXT app: <strong>OnionXT</strong> provides the address and the tor forwarding, and <strong>onion-httpd</strong> parses the request and serves this page - no web server, no hosting, no port forwarding.</p>" & return after tH
   put "<p><a href='/about'>About this demo</a></p>" & return after tH
   put "</body></html>" & return after tH
   return tH
end homeHtml

private function aboutHtml
   local tH
   put "<!doctype html>" & return into tH
   put "<html><head><meta charset='utf-8'><title>About</title></head>" & return after tH
   put "<body style='font-family:system-ui,sans-serif;max-width:38em;margin:3em auto;padding:0 1em;line-height:1.5'>" & return after tH
   put "<h1>About</h1>" & return after tH
   put "<p>Two routes (<code>/</code> and <code>/about</code>) served from one small OXT stack. Add more with oxhRoute, or serve a folder of files with oxhSetRoot. The address is an ed25519 public key, so reaching it proves you connected to this host - no certificate authority.</p>" & return after tH
   put "<p><a href='/'>Back home</a></p>" & return after tH
   put "</body></html>" & return after tH
   return tH
end aboutHtml

-- Minimal UI + lifecycle.
private command demoBuildUI
   create button "demo:start"
   set the rect of button "demo:start" to "24,20,164,52"
   set the label of button "demo:start" to "Start"
   create button "demo:stop"
   set the rect of button "demo:stop" to "176,20,316,52"
   set the label of button "demo:stop" to "Stop"
   create field "demo:url"
   set the rect of field "demo:url" to "24,64,636,90"
   set the lockText of field "demo:url" to true
   set the opaque of field "demo:url" to true
   set the textFont of field "demo:url" to "Courier"
   set the dontWrap of field "demo:url" to true
   put "(the .onion URL will appear here once published)" into field "demo:url"
   create field "demo:out"
   set the rect of field "demo:out" to "24,102,636,396"
   set the lockText of field "demo:out" to true
   set the opaque of field "demo:out" to true
   set the textFont of field "demo:out" to "Courier"
   set the vScrollbar of field "demo:out" to true
   put empty into field "demo:out"
end demoBuildUI

on mouseUp
   local tName
   put the short name of the target into tName
   if tName is "demo:start" then
      demoStart
   else if tName is "demo:stop" then
      demoStop
   end if
end mouseUp

private command demoStart
   local tErr
   put empty into field "demo:out"
   put empty into sOnionAddress
   demoLog "connecting to the tor control port 127.0.0.1:" & kControlPort & " ..."
   oxSetControlPort kControlPort
   oxSetSocksPort kSocksPort
   oxConnectControl
   put the result into tErr
   if tErr is not empty then
      demoLog "control connect error: " & tErr
   end if
end demoStart

private command demoStop
   if sSvcHandle is an integer then
      oxhStop sSvcHandle
      put empty into sSvcHandle
      demoLog "onion removed"
   end if
   oxDisconnectControl
end demoStop

on closeStack
   demoStop
   oxShutdown
   pass closeStack
end closeStack

private command demoLog pText
   put pText & return after field "demo:out"
   set the scroll of field "demo:out" to the formattedHeight of field "demo:out"
end demoLog
