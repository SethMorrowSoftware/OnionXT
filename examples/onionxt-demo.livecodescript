-- onionxt-demo.livecodescript - an interactive, tabbed showcase of OnionXT.
--
-- Formatted like the sibling family's example stacks (SodiumXT's sodium-demo /
-- sodium-tests split, TorrentXT's examples/): a single stack, built entirely in
-- script on preOpenStack (no IDE design work needed), with a header bar, a tab
-- strip, and one content panel per feature. Controls use a "prefix:role" naming
-- scheme (the prefix is the owning tab, the role is the control's job), so a
-- single mouseUp router dispatches every click by parsing the target's name.
--
-- Create a new mainstack, set its script to this file's content (this whole
-- file IS a stack script; it needs at least the one default card every new
-- stack already has), and load onionxt.livecodescript into the message path
-- first (start using it as a library, or start it before opening this stack).
-- Load sodiumxt too for the seed-derived service and the full self-test, and
-- start using onionxt-tests.livecodescript alongside this one for the About
-- tab's "Run self-test" button (dispatch with no explicit target only reaches
-- a library that is started using, not merely a stack that happens to be
-- open). Everything here goes through the public ox* surface
-- documented in docs/05-api-reference.md and docs/10-usage-guide.md; nothing
-- reaches into OnionXT's private internals.
--
-- WHY this differs from SodiumXT's demo (read this before you assume the same
-- shape): SodiumXT is synchronous, pure compute, no I/O - a button click calls
-- an sx* function and the result is ready on the next line. OnionXT is exactly
-- the opposite (CLAUDE.md: "OnionXT owns long-lived network state... is
-- asynchronous and event-driven"): a button click here KICKS OFF a dial or a
-- publish, and the result arrives later through a callback. So every tab that
-- touches the network follows a start-then-wait-for-callback shape instead of a
-- read-input/call/show-output shape; the callbacks (onStatus, onDialStream,
-- onSvcPeerStream) are what actually populate the output fields.
--
-- STATUS: designed and statically reasoned, like the rest of OnionXT; the UI
-- object-creation calls (create field/button/graphic, set properties, show/hide
-- by name) need an on-engine pass the same way the socket code does. The ox*
-- calls themselves are the real feature surface being demonstrated.

-- ==========================================================================
-- Constants. Ports match docs/07 (system tor 9050/9051; Tor Browser 9150/9151).
-- A stable, well-known v3 onion for the Dial tab default (docs/02 test target).
-- ==========================================================================

constant kDemoDefaultSocksPort = 9050
constant kDemoDefaultControlPort = 9051
constant kDemoDefaultDialHost = "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion"
constant kDemoDefaultDialPort = 80
constant kDemoKnownAddress = "2gzyxa5ihm7nsggfxnu52rck2vv4rvmdlkiu3zzui5du4xyclen53wid.onion"
constant kDemoTabs = "stat,dial,svc,addr,about"

-- ==========================================================================
-- Script-local state. One shared control connection and a small per-tab table
-- of in-flight handles, exactly mirroring how the library itself keeps state
-- script-local rather than per-object (every tab shares one oxConnectControl).
-- ==========================================================================

local sTab                  -- the currently visible tab key
local sDialStream           -- the Dial tab's stream handle, or empty
local sSvcHandle            -- the Service tab's published service handle, or empty
local sTabControls          -- array: tab key -> comma list of that tab's control names

-- NOTE on the UI: controls are created directly on the card and shown/hidden by
-- name per tab (sTabControls); OnionXT does NOT reparent them into groups. LiveCode
-- has no "set the owner" reparent (owner is read-only), and copy/relayer grouping
-- is fiddly to do blind, so the demo just toggles visibility, which is simple and
-- valid. This UI-construction path still wants an on-engine pass (the create/set
-- object calls), but it uses no invalid reparenting.

on preOpenStack
   -- Build the whole UI in script; no IDE design work required (matches the
   -- family convention). Point OnionXT's callbacks at this stack's script.
   oxSetCallbackOwner the long id of me
   oxSetStatusCallback "onStatus"
   oxSetPeerCallback "onPeer"
   put "stat" into sTab
   demoBuildChrome
   demoBuildStatusTab
   demoBuildDialTab
   demoBuildServiceTab
   demoBuildAddressTab
   demoBuildAboutTab
   demoShowTab "stat"
   pass preOpenStack
end preOpenStack

-- ==========================================================================
-- Color palette. One function, literal RGB triples, so every control gets a
-- consistent look (SodiumXT's clr() convention).
-- ==========================================================================

private function demoColor pName
   if pName is "header" then
      return "20,30,60"
   else if pName is "panel" then
      return "245,245,248"
   else if pName is "accent" then
      return "40,90,190"
   else if pName is "ok" then
      return "20,140,60"
   else if pName is "fail" then
      return "190,40,40"
   else if pName is "text" then
      return "20,20,25"
   else if pName is "muted" then
      return "110,110,120"
   end if
   return "0,0,0"
end demoColor

-- ==========================================================================
-- Control factory. Small, consistent helpers over the standard LiveCode object
-- commands, so every panel is built the same way.
-- ==========================================================================

private command demoMakeRect pName, pRect, pColorName
   create graphic pName
   set the style of graphic pName to "rectangle"
   set the rect of graphic pName to pRect
   set the filled of graphic pName to true
   set the lineSize of graphic pName to 0
   set the backgroundColor of graphic pName to demoColor(pColorName)
end demoMakeRect

private command demoMakeLabel pName, pRect, pText, pColorName
   create field pName
   set the rect of field pName to pRect
   set the text of field pName to pText
   set the backgroundColor of field pName to demoColor("panel")
   set the foregroundColor of field pName to demoColor(pColorName)
   set the borderWidth of field pName to 0
   set the threeD of field pName to false
   set the lockText of field pName to true
end demoMakeLabel

private command demoMakeInput pName, pRect, pDefaultText
   create field pName
   set the rect of field pName to pRect
   set the text of field pName to pDefaultText
   set the borderWidth of field pName to 1
   set the threeD of field pName to false
end demoMakeInput

private command demoMakeOutput pName, pRect
   -- A monospace, scrolling, append-only output box (the log / result display).
   create field pName
   set the rect of field pName to pRect
   set the text of field pName to empty
   set the textFont of field pName to "Courier,Monaco,monospace"
   set the borderWidth of field pName to 1
   set the threeD of field pName to false
   set the lockText of field pName to true
   set the dontWrap of field pName to false
end demoMakeOutput

private command demoMakeButton pName, pRect, pLabel
   create button pName
   set the rect of button pName to pRect
   set the label of button pName to pLabel
   set the style of button pName to "rectangle"
end demoMakeButton

-- ==========================================================================
-- Chrome: header bar and the tab strip. Tab buttons are named "tabbtn:<key>";
-- clicking one shows that tab and restyles the strip.
-- ==========================================================================

private command demoBuildChrome
   demoMakeRect "chrome:header", "0,0,760,40", "header"
   demoMakeLabel "chrome:title", "12,8,400,32", "OnionXT demo", "panel"
   set the foregroundColor of field "chrome:title" to "255,255,255"
   set the textStyle of field "chrome:title" to "bold"

   local tNames, tI, tKey, tX, tSaved
   put "Status,Dial,Service,Address,About" into tNames
   put 0 into tX
   put the itemDelimiter into tSaved
   set the itemDelimiter to comma
   repeat with tI = 1 to the number of items of kDemoTabs
      put item tI of kDemoTabs into tKey
      demoMakeButton "tabbtn:" & tKey, (12 + tX) & ",48," & (12 + tX + 100) & ",76", item tI of tNames
      add 108 to tX
   end repeat
   set the itemDelimiter to tSaved
   demoRestyleTabs
end demoBuildChrome

private command demoShowTab pKey
   -- Show the chosen tab's controls, hide every other tab's, by name (no groups).
   local tI, tCandidate, tSaved, tJ, tCtrl
   put the itemDelimiter into tSaved
   set the itemDelimiter to comma
   repeat with tI = 1 to the number of items of kDemoTabs
      put item tI of kDemoTabs into tCandidate
      repeat with tJ = 1 to the number of items of sTabControls[tCandidate]
         put item tJ of sTabControls[tCandidate] into tCtrl
         set the visible of control tCtrl to (tCandidate is pKey)
      end repeat
   end repeat
   set the itemDelimiter to tSaved
   put pKey into sTab
   demoRestyleTabs
end demoShowTab

private command demoRestyleTabs
   local tI, tKey, tSaved
   put the itemDelimiter into tSaved
   set the itemDelimiter to comma
   repeat with tI = 1 to the number of items of kDemoTabs
      put item tI of kDemoTabs into tKey
      if tKey is sTab then
         set the backgroundColor of button ("tabbtn:" & tKey) to demoColor("accent")
         set the foregroundColor of button ("tabbtn:" & tKey) to "255,255,255"
      else
         set the backgroundColor of button ("tabbtn:" & tKey) to demoColor("panel")
         set the foregroundColor of button ("tabbtn:" & tKey) to demoColor("text")
      end if
   end repeat
   set the itemDelimiter to tSaved
end demoRestyleTabs

-- ==========================================================================
-- Tab: Status. Connects the ONE shared control connection every other tab
-- relies on, and shows bootstrap progress and the tor version (docs/03, 07).
-- ==========================================================================

private command demoBuildStatusTab
   demoMakeLabel "stat:hdr", "20,90,700,114", "Control connection and bootstrap", "text"
   demoMakeLabel "stat:socksLbl", "20,124,140,146", "SOCKS port:", "muted"
   demoMakeInput "stat:socks", "150,120,260,146", kDemoDefaultSocksPort
   demoMakeLabel "stat:ctlLbl", "280,124,400,146", "Control port:", "muted"
   demoMakeInput "stat:ctl", "410,120,520,146", kDemoDefaultControlPort
   demoMakeButton "stat:connect", "540,118,650,148", "Connect"
   demoMakeButton "stat:disconnect", "660,118,760,148", "Disconnect"
   demoMakeLabel "stat:status", "20,158,740,182", "not connected", "muted"
   demoMakeLabel "stat:bar", "20,190,740,208", "bootstrap: 0%", "muted"
   demoMakeLabel "stat:version", "20,216,740,238", "version: " & oxVersion(), "muted"
   demoMakeLabel "stat:hint", "20,250,740,320", \
      "Needs a tor daemon reachable on loopback. Reference torrc:" & return & \
      "SocksPort 9050" & return & "ControlPort 9051" & return & \
      "CookieAuthentication 1" & return & \
      "(Tor Browser: SOCKS 9150, control 9151.)", "muted"

   local tNames
   put "hdr,socksLbl,socks,ctlLbl,ctl,connect,disconnect,status,bar,version,hint" into tNames
   demoRegisterTab "stat", tNames
end demoBuildStatusTab

private command handleStat pRole
   if pRole is "connect" then
      local tError
      oxSetSocksPort field "stat:socks"
      oxSetControlPort field "stat:ctl"
      set the foregroundColor of field "stat:status" to demoColor("muted")
      put "connecting..." into field "stat:status"
      oxConnectControl
      put the result into tError
      if tError is not empty then
         set the foregroundColor of field "stat:status" to demoColor("fail")
         put tError into field "stat:status"
      end if
   else if pRole is "disconnect" then
      oxDisconnectControl
      set the foregroundColor of field "stat:status" to demoColor("muted")
      put "disconnected" into field "stat:status"
      put "bootstrap: 0%" into field "stat:bar"
   end if
end handleStat

-- ==========================================================================
-- Tab: Dial. Outbound SOCKS5 through Tor (docs/02): dial, then send/receive
-- once the "open" stream event arrives.
-- ==========================================================================

private command demoBuildDialTab
   demoMakeLabel "dial:hdr", "20,90,700,114", "Dial a host through Tor (SOCKS5)", "text"
   demoMakeLabel "dial:hostLbl", "20,124,80,146", "Host:", "muted"
   demoMakeInput "dial:host", "90,120,560,146", kDemoDefaultDialHost
   demoMakeLabel "dial:portLbl", "570,124,610,146", "Port:", "muted"
   demoMakeInput "dial:port", "620,120,700,146", kDemoDefaultDialPort
   demoMakeButton "dial:go", "20,154,140,182", "Dial"
   demoMakeLabel "dial:status", "150,158,760,180", "not dialed", "muted"
   demoMakeInput "dial:msg", "20,192,600,218", "GET / HTTP/1.0" & return & return
   demoMakeButton "dial:send", "610,190,730,220", "Send"
   demoMakeOutput "dial:log", "20,230,740,420"

   local tNames
   put "hdr,hostLbl,host,portLbl,port,go,status,msg,send,log" into tNames
   demoRegisterTab "dial", tNames
end demoBuildDialTab

private command handleDial pRole
   if pRole is "go" then
      demoStartDial
   else if pRole is "send" then
      demoSendDial
   end if
end handleDial

private command demoStartDial
   local tHandle
   put empty into field "dial:log"
   put "dialing..." into field "dial:status"
   set the foregroundColor of field "dial:status" to demoColor("muted")
   oxDial field "dial:host", (field "dial:port")
   put the result into tHandle
   if tHandle is an integer then
      put tHandle into sDialStream
      oxSetStreamCallback sDialStream, "onDialStream"
   else
      put empty into sDialStream
      set the foregroundColor of field "dial:status" to demoColor("fail")
      put tHandle into field "dial:status"
   end if
end demoStartDial

private command demoSendDial
   if sDialStream is empty then
      set the foregroundColor of field "dial:status" to demoColor("fail")
      put "not connected yet" into field "dial:status"
      exit demoSendDial
   end if
   oxWrite sDialStream, textEncode(field "dial:msg", "UTF-8")
   put field "dial:log" & return & "> (sent " & (the number of chars of field "dial:msg") & " chars)" into field "dial:log"
end demoSendDial

-- The stream callback for the Dial tab. Stale-guard against a handle that has
-- already moved on (the app may have redialed since this event was queued).
on onDialStream pStream, pEvent, pData
   if pStream is not sDialStream then
      exit onDialStream
   end if
   if pEvent is "open" then
      set the foregroundColor of field "dial:status" to demoColor("ok")
      put "connected" into field "dial:status"
   else if pEvent is "data" then
      put field "dial:log" & return & textDecode(pData, "UTF-8") into field "dial:log"
   else if pEvent is "closed" then
      set the foregroundColor of field "dial:status" to demoColor("muted")
      put "closed" into field "dial:status"
      put empty into sDialStream
   else if pEvent is "error" then
      set the foregroundColor of field "dial:status" to demoColor("fail")
      put pData into field "dial:status"
      put empty into sDialStream
   end if
end onDialStream

-- ==========================================================================
-- Tab: Service. Publish a v3 onion (docs/03/04), accept an inbound peer, and
-- echo bytes back. Needs the Status tab's control connection authenticated.
-- ==========================================================================

private command demoBuildServiceTab
   demoMakeLabel "svc:hdr", "20,90,700,114", "Publish an onion service", "text"
   demoMakeLabel "svc:vLbl", "20,124,100,146", "Virtual port:", "muted"
   demoMakeInput "svc:vport", "110,120,190,146", 80
   demoMakeLabel "svc:lLbl", "200,124,290,146", "Local port:", "muted"
   demoMakeInput "svc:lport", "300,120,380,146", 8080
   demoMakeButton "svc:publish", "20,154,160,182", "Publish (random key)"
   demoMakeButton "svc:remove", "170,154,290,182", "Remove"
   demoMakeLabel "svc:status", "300,158,760,180", "not published", "muted"
   demoMakeLabel "svc:addrLbl", "20,192,120,214", "Address:", "muted"
   demoMakeOutput "svc:address", "130,190,740,214"
   demoMakeOutput "svc:log", "20,224,740,420"

   local tNames
   put "hdr,vLbl,vport,lLbl,lport,publish,remove,status,addrLbl,address,log" into tNames
   demoRegisterTab "svc", tNames
end demoBuildServiceTab

private command handleSvc pRole
   if pRole is "publish" then
      demoPublishService
   else if pRole is "remove" then
      demoRemoveService
   end if
end handleSvc

private command demoPublishService
   local tHandle
   if not oxIsControlAuthenticated() then
      set the foregroundColor of field "svc:status" to demoColor("fail")
      put "connect and authenticate on the Status tab first" into field "svc:status"
      exit demoPublishService
   end if
   set the foregroundColor of field "svc:status" to demoColor("muted")
   put "publishing..." into field "svc:status"
   put empty into field "svc:address"
   put empty into field "svc:log"
   oxCreateService (field "svc:vport"), (field "svc:lport")
   put the result into tHandle
   if tHandle is an integer then
      put tHandle into sSvcHandle
   else
      set the foregroundColor of field "svc:status" to demoColor("fail")
      put tHandle into field "svc:status"
   end if
end demoPublishService

private command demoRemoveService
   if sSvcHandle is not empty then
      oxRemoveService sSvcHandle
   end if
   put empty into sSvcHandle
   put empty into field "svc:address"
   set the foregroundColor of field "svc:status" to demoColor("muted")
   put "not published" into field "svc:status"
end demoRemoveService

-- The peer callback: a remote peer reached our onion. Register a per-stream
-- callback and echo whatever it sends (the same shape as examples/onion-roundtrip).
on onPeer pStream, pService, pPeerAddr
   oxSetStreamCallback pStream, "onSvcPeerStream"
   put field "svc:log" & return & "peer connected from " & pPeerAddr into field "svc:log"
end onPeer

on onSvcPeerStream pStream, pEvent, pData
   if pEvent is "data" then
      put field "svc:log" & return & "< " & (the number of bytes of pData) & " bytes (echoing)" into field "svc:log"
      oxWrite pStream, pData
   else if pEvent is "closed" then
      put field "svc:log" & return & "peer closed" into field "svc:log"
   else if pEvent is "error" then
      put field "svc:log" & return & "peer error: " & pData into field "svc:log"
   end if
end onSvcPeerStream

-- ==========================================================================
-- Tab: Address. Pure, offline helpers (docs/04): base32 + the address<->key
-- mapping. No network, no tor daemon needed.
-- ==========================================================================

private command demoBuildAddressTab
   demoMakeLabel "addr:hdr", "20,90,700,114", "Address tools (pure, no network)", "text"
   demoMakeLabel "addr:pasteLbl", "20,124,140,146", "Onion address:", "muted"
   demoMakeInput "addr:paste", "150,120,600,146", kDemoKnownAddress
   demoMakeButton "addr:decode", "610,118,730,148", "Decode"
   demoMakeOutput "addr:pubkey", "20,156,740,180"
   demoMakeButton "addr:encode", "20,190,180,218", "Re-encode from pubkey"
   demoMakeOutput "addr:reencoded", "190,190,740,218"
   demoMakeLabel "addr:validLbl", "20,228,740,252", "", "muted"

   local tNames
   put "hdr,pasteLbl,paste,decode,pubkey,encode,reencoded,validLbl" into tNames
   demoRegisterTab "addr", tNames
end demoBuildAddressTab

private command handleAddr pRole
   if pRole is "decode" then
      demoDecodeAddress
   else if pRole is "encode" then
      demoEncodeAddress
   end if
end handleAddr

private command demoDecodeAddress
   local tAddress, tPub, tValid
   put field "addr:paste" into tAddress
   put oxPublicKeyFromAddress(tAddress) into tPub
   if the number of bytes of tPub is 32 then
      put demoBytesToHex(tPub) into field "addr:pubkey"
   else
      put "(not a structurally valid v3 address)" into field "addr:pubkey"
   end if
   put oxIsValidAddress(tAddress) into tValid
   if tValid then
      set the foregroundColor of field "addr:validLbl" to demoColor("ok")
      put "structurally valid (checksum verified if SodiumXT SHA3-256 is available)" into field "addr:validLbl"
   else
      set the foregroundColor of field "addr:validLbl" to demoColor("fail")
      put "not a valid v3 onion address" into field "addr:validLbl"
   end if
end demoDecodeAddress

private command demoEncodeAddress
   local tPubHex, tPub, tAddr
   put field "addr:pubkey" into tPubHex
   if the number of chars of tPubHex is not 64 then
      put "(decode an address above first, or paste a 64-hex-char pubkey)" into field "addr:reencoded"
      exit demoEncodeAddress
   end if
   put binaryEncode("H*", tPubHex) into tPub
   put oxAddressFromPublicKey(tPub) into tAddr
   put tAddr into field "addr:reencoded"
end demoEncodeAddress

-- ==========================================================================
-- Tab: About. Capability flags (which SodiumXT primitives are composed) and
-- the self-test entry point.
-- ==========================================================================

private command demoBuildAboutTab
   demoMakeLabel "about:hdr", "20,90,700,114", "OnionXT " & oxVersion(), "text"
   demoMakeLabel "about:blurb", "20,120,740,190", \
      "A Tor transport and self-authenticating rendezvous layer for OXT/LiveCode." & return & \
      "Adds no cryptography (composes SodiumXT ABI >= 6 for seed-derived onions and" & return & \
      "SAFECOOKIE); assumes a locally-running tor daemon. Status: designed and" & return & \
      "statically reasoned; needs an on-engine pass against a real daemon (CLAUDE.md).", "muted"
   demoMakeLabel "about:capsLbl", "20,198,300,220", "Capabilities (oxTransportInfo):", "text"
   demoMakeOutput "about:caps", "20,224,740,300"
   demoMakeButton "about:runTests", "20,310,220,340", "Run self-test"
   demoMakeOutput "about:testlog", "20,346,740,420"

   local tNames
   put "hdr,blurb,capsLbl,caps,runTests,testlog" into tNames
   demoRegisterTab "about", tNames
   demoShowCapabilities
end demoBuildAboutTab

private command demoShowCapabilities
   local tInfo, tOut
   put oxTransportInfo() into tInfo
   put "transport           : " & tInfo["transport"] & return into tOut
   put "version             : " & tInfo["version"] & return after tOut
   put "safeCookieAuth      : " & tInfo["safeCookieAuth"] & return after tOut
   put "deterministicOnion  : " & tInfo["deterministicOnion"] & return after tOut
   put "offlineAddress      : " & tInfo["offlineAddress"] after tOut
   put tOut into field "about:caps"
end demoShowCapabilities

private command handleAbout pRole
   if pRole is "runTests" then
      demoRunSelfTest
   end if
end handleAbout

private command demoRunSelfTest
   -- The full suite lives in the sibling file onionxt-tests.livecodescript,
   -- started using as a library exactly like onionxt.livecodescript itself, so
   -- oxSelfTest resolves through the normal message path (no explicit "to": a
   -- dispatch "to" a specific object would NOT reach a separate library stack).
   -- Detect it missing the same way the library capability-gates SodiumXT.
   local tReport
   dispatch function "oxSelfTest"
   if it is "unhandled" then
      put "onionxt-tests.livecodescript is not loaded; open it alongside this demo to run the self-test." into field "about:testlog"
      exit demoRunSelfTest
   end if
   put the result into tReport
   put tReport into field "about:testlog"
end demoRunSelfTest

-- ==========================================================================
-- Shared status callback: bootstrap, service address, and readiness updates
-- from whichever tab is not currently focused still get shown where relevant.
-- ==========================================================================

on onStatus pKind, pInfo
   if pKind is "control" then
      if pInfo is "authenticated" then
         set the foregroundColor of field "stat:status" to demoColor("ok")
      else if pInfo begins with "authfailed" or pInfo begins with "error" then
         set the foregroundColor of field "stat:status" to demoColor("fail")
      else
         set the foregroundColor of field "stat:status" to demoColor("muted")
      end if
      put pInfo into field "stat:status"
   else if pKind is "bootstrap" then
      put "bootstrap: " & pInfo & "%" into field "stat:bar"
   else if pKind is "service" then
      put pInfo into field "svc:address"
      set the foregroundColor of field "svc:status" to demoColor("muted")
      put "published, awaiting descriptor upload" into field "svc:status"
   else if pKind is "serviceReady" then
      set the foregroundColor of field "svc:status" to demoColor("ok")
      put "reachable" into field "svc:status"
   end if
end onStatus

-- ==========================================================================
-- Central click router: parse "prefix:role" from the clicked control's short
-- name and dispatch to that tab's handler (SodiumXT's routing convention).
-- ==========================================================================

on mouseUp
   local tName, tPrefix, tRole, tSaved
   put the short name of the target into tName
   if the short name of the target begins with "tabbtn:" then
      put char 8 to -1 of tName into tRole
      demoShowTab tRole
      exit mouseUp
   end if
   if "chrome:" is in tName then
      exit mouseUp
   end if
   put the itemDelimiter into tSaved
   set the itemDelimiter to ":"
   put item 1 of tName into tPrefix
   put item 2 to -1 of tName into tRole
   set the itemDelimiter to tSaved

   if tPrefix is "stat" then
      handleStat tRole
   else if tPrefix is "dial" then
      handleDial tRole
   else if tPrefix is "svc" then
      handleSvc tRole
   else if tPrefix is "addr" then
      handleAddr tRole
   else if tPrefix is "about" then
      handleAbout tRole
   end if
end mouseUp

-- ==========================================================================
-- Small local helpers (demo glue only, not part of the ox* surface).
-- ==========================================================================

private command demoRegisterTab pTabKey, pRoleList
   -- Record this tab's full control names ("prefix:role") in sTabControls and
   -- hide them; demoShowTab toggles their visibility. No groups, no reparenting.
   local tI, tRole, tSaved, tNames, tCtrl
   put the itemDelimiter into tSaved
   set the itemDelimiter to comma
   put empty into tNames
   repeat with tI = 1 to the number of items of pRoleList
      put item tI of pRoleList into tRole
      put pTabKey & ":" & tRole into tCtrl
      if tNames is empty then
         put tCtrl into tNames
      else
         put comma & tCtrl after tNames
      end if
      set the visible of control tCtrl to false
   end repeat
   put tNames into sTabControls[pTabKey]
   set the itemDelimiter to tSaved
end demoRegisterTab

private function demoBytesToHex pData
   -- A local hex helper so this demo has no hidden dependency on OnionXT's
   -- private internals; binaryDecode "H*" is the same primitive the library
   -- itself uses for hex, just called from example glue instead of from inside
   -- onionxt.livecodescript. binaryDecode is a function (returns the count and
   -- fills the output var), so call it as one and `get` the discarded count.
   local tHex
   get binaryDecode("H*", pData, tHex)
   return tHex
end demoBytesToHex
