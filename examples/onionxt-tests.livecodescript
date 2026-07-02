-- onionxt-tests.livecodescript - OnionXT's self-test harness.
--
-- Formatted like the sibling family's test harnesses (SodiumXT's
-- sodium-tests.livecodescript: module-level sLog/sPass/sFail, an sxCheck
-- assertion helper, sxSection headers, known-answer vectors, and negative-path
-- checks under try/catch). Start using this stack alongside onionxt.livecodescript
-- and call oxSelfTest() (from a message box, a button, or the "Run self-test"
-- button on examples/onionxt-demo.livecodescript's About tab).
--
-- WHY this suite is PURE and OFFLINE, unlike SodiumXT's (read this before you
-- extend it): SodiumXT is stateless compute with zero I/O, so its self-test can
-- exercise every primitive end-to-end with no external process. OnionXT's whole
-- job is long-lived network I/O against a real tor daemon (CLAUDE.md: "OnionXT
-- owns long-lived network state... is asynchronous and event-driven"), and a
-- synchronous test function fundamentally cannot wait for an async callback
-- without blocking the one interpreter thread, which the library forbids
-- (CLAUDE.md: "never block the interpreter thread on the network"). So this
-- harness deliberately tests only what is reachable WITHOUT a daemon:
--   1. the pure address / base32 logic (docs/04), cross-checked against the
--      same known-answer vectors pinned in tools/onion-kat.py;
--   2. the fail-closed contract on every public command (CLAUDE.md rule 4:
--      argument validation, "not authenticated yet", unknown-handle misses);
--   3. idempotent teardown (duplicate close/remove/disconnect/shutdown).
-- The actual wire handshakes (SOCKS5 dial, control auth, ADD_ONION) are an
-- on-engine / integration concern: run examples/onionxt-demo.livecodescript or
-- examples/onion-roundtrip against a real tor daemon for those (see
-- IMPLEMENTATION-PLAN.md phase 4 and CLAUDE.md's on-engine VERIFY checklist).
--
-- CAUTION - side effects on shared state: OnionXT's connection/service/stream
-- state is a script-local singleton shared by the whole message path (not
-- per-object), so the idempotent-teardown section below really does call
-- oxDisconnectControl / oxShutdown. If a live demo session (or any other code
-- using this same OnionXT instance) currently has an open control connection,
-- streams, or published services, running oxSelfTest CLOSES THEM as part of
-- proving teardown is idempotent. Run this in a fresh session, or expect it to
-- tear down whatever is currently open.
--
-- STATUS: designed and statically reasoned; needs an on-engine pass like the
-- rest of OnionXT, though everything here is pure script with no socket I/O of
-- its own, so the risk surface is much smaller than the library itself.

-- Two real, published v3 onion addresses, the same vectors pinned in
-- tools/onion-kat.py, so the Python KAT and this livecodescript suite agree.
constant kTestAddrTorProject = "2gzyxa5ihm7nsggfxnu52rck2vv4rvmdlkiu3zzui5du4xyclen53wid.onion"
constant kTestAddrDuckDuckGo = "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion"

local sLog
local sPass
local sFail

-- ==========================================================================
-- Entry point.
-- ==========================================================================

function oxSelfTest
   put empty into sLog
   put 0 into sPass
   put 0 into sFail

   testVersionAndCapabilities
   testInitialState
   testFailClosedArguments
   testUnknownHandlesAreCleanMisses
   testIdempotentTeardown
   testAddressRoundTrip
   testAddressNegativePaths

   local tSummary
   put sPass & " passed, " & sFail & " failed" into tSummary
   return tSummary & return & "----------------------------------------" & return & sLog
end oxSelfTest

-- ==========================================================================
-- Assertion helpers (SodiumXT's sxCheck / sxSection convention).
-- ==========================================================================

private command oxCheck pCondition, pLabel
   if pCondition then
      add 1 to sPass
      put sLog & "  ok   " & pLabel & return into sLog
   else
      add 1 to sFail
      put sLog & "  FAIL " & pLabel & return into sLog
   end if
end oxCheck

private command oxSection pTitle
   put sLog & return & "-- " & pTitle & " --" & return into sLog
end oxSection

-- ==========================================================================
-- Section 1: version string and the transport capability probe.
-- ==========================================================================

private command testVersionAndCapabilities
   oxSection "version and capabilities"
   oxCheck (oxVersion() is not empty), "oxVersion reports a non-empty string"

   local tInfo
   put oxTransportInfo() into tInfo
   oxCheck (tInfo["transport"] is "ox"), "oxTransportInfo advertises the ox transport"
   oxCheck (tInfo["version"] is oxVersion()), "oxTransportInfo version matches oxVersion"
   -- The three capability flags are always present, true or false, whether or
   -- not SodiumXT is loaded (CLAUDE.md rule 1: a missing primitive degrades to
   -- a clear flag/error, never a crash).
   oxCheck (tInfo["safeCookieAuth"] is true or tInfo["safeCookieAuth"] is false), \
      "safeCookieAuth capability flag is a boolean"
   oxCheck (tInfo["deterministicOnion"] is true or tInfo["deterministicOnion"] is false), \
      "deterministicOnion capability flag is a boolean"
   oxCheck (tInfo["offlineAddress"] is true or tInfo["offlineAddress"] is false), \
      "offlineAddress capability flag is a boolean"
end testVersionAndCapabilities

-- ==========================================================================
-- Section 2: state before any connection has ever been made. Control state is
-- a script-local singleton shared by the whole message path (CLAUDE.md: state
-- is script-local, not per-object), so if this session already called
-- oxConnectControl (for example via examples/onionxt-demo.livecodescript's
-- Status tab) these checks would otherwise be a false failure, not a real bug.
-- Skip them with a clear note rather than asserting something session order
-- can make untrue; run oxSelfTest first, before connecting, for full coverage.
-- ==========================================================================

private command testInitialState
   oxSection "initial state (before oxConnectControl)"
   if oxIsControlAuthenticated() then
      put sLog & "  --   (skipped: this session is already control-authenticated; " & \
         "run oxSelfTest before oxConnectControl for this section)" & return into sLog
      exit testInitialState
   end if
   oxCheck (oxBootstrapProgress() is 0), "bootstrap progress starts at 0"
   oxCheck (not oxIsReady()), "oxIsReady is false before connecting"
   oxCheck (not oxIsControlAuthenticated()), "control is not authenticated before connecting"
end testInitialState

-- ==========================================================================
-- Section 3: fail-closed argument validation (CLAUDE.md rule 4). Every one of
-- these needs no network access; the library rejects the request before it
-- ever opens a socket or sends a command.
-- ==========================================================================

private command testFailClosedArguments
   oxSection "fail-closed argument validation"

   -- oxDial / oxCreateService* are COMMANDS: invoke them as statements and read
   -- their handle-or-error from `the result` (you cannot call a command with
   -- function-call parentheses; that syntax needs a `function` handler). Only
   -- oxAddressFromPublicKey below is a function, so it takes parentheses.
   local tResult
   oxDial empty, 80
   put the result into tResult
   oxCheck (tResult begins with "OnionXT:"), "oxDial rejects an empty host"

   oxDial "example.onion", 99999
   put the result into tResult
   oxCheck (tResult begins with "OnionXT:"), "oxDial rejects a port outside 1..65535"

   -- These two prove the pre-auth fail-closed guard specifically, so they are
   -- only meaningful while nothing has authenticated yet in this session (see
   -- the note on testInitialState above); skip rather than false-fail if a
   -- prior oxConnectControl in this session already succeeded.
   if oxIsControlAuthenticated() then
      put sLog & "  --   (skipped: pre-auth guard on oxCreateService* needs a " & \
         "session that has not authenticated yet)" & return into sLog
   else
      oxCreateService 80, 8080
      put the result into tResult
      oxCheck (tResult begins with "OnionXT:"), \
         "oxCreateService fails closed without an authenticated control connection"

      oxCreateServiceFromSeed testZeroSeed(), 80, 8080
      put the result into tResult
      oxCheck (tResult begins with "OnionXT:"), \
         "oxCreateServiceFromSeed also fails closed without an authenticated control connection"
   end if

   put oxAddressFromPublicKey("short") into tResult
   oxCheck (tResult begins with "OnionXT:"), \
      "oxAddressFromPublicKey rejects a public key that is not 32 bytes"
end testFailClosedArguments

-- ==========================================================================
-- Section 4: an unknown / stale handle is a clean miss, never a crash
-- (CLAUDE.md handles-and-state: "a stale or closed id must be a clean no-op /
-- error, never a crash").
-- ==========================================================================

private command testUnknownHandlesAreCleanMisses
   oxSection "unknown handles are clean misses"
   local tUnknown, tResult
   put 999999 into tUnknown

   -- oxStreamState / oxServiceAddress / oxServiceIsReady are functions (parens);
   -- oxSetStreamCallback / oxWrite are commands (statement + `the result`).
   oxCheck (oxStreamState(tUnknown) is "unknown"), "an unknown stream handle reports state unknown"
   oxCheck (oxServiceAddress(tUnknown) is empty), "an unknown service handle has no address"
   oxCheck (not oxServiceIsReady(tUnknown)), "an unknown service handle is not ready"

   oxSetStreamCallback tUnknown, "someHandler"
   put the result into tResult
   oxCheck (tResult begins with "OnionXT:"), "oxSetStreamCallback on an unknown handle fails closed"

   oxWrite tUnknown, "x"
   put the result into tResult
   oxCheck (tResult begins with "OnionXT:"), "oxWrite to an unknown/unconnected stream fails closed"
end testUnknownHandlesAreCleanMisses

-- ==========================================================================
-- Section 5: idempotent teardown. Every close/remove/disconnect is safe to
-- call twice, and safe to call on something that was never opened.
-- ==========================================================================

private command testIdempotentTeardown
   oxSection "idempotent teardown (duplicate close is a no-op)"
   local tOk
   put true into tOk
   try
      oxCloseStream 999999
      oxCloseStream 999999
      oxRemoveService 999999
      oxRemoveService 999999
      oxDisconnectControl
      oxDisconnectControl
      oxShutdown
      oxShutdown
   catch tError
      put false into tOk
   end try
   oxCheck tOk, "double close / remove / disconnect / shutdown never throws"
   oxCheck (not oxIsControlAuthenticated()), "control is disconnected after teardown"
end testIdempotentTeardown

-- ==========================================================================
-- Section 6: the v3 address <-> public key mapping, cross-checked against two
-- REAL, published onion addresses (the same vectors tools/onion-kat.py pins).
-- No crypto here except the optional SHA3-256 checksum re-encode, which is
-- skipped (not failed) when SodiumXT does not provide it.
-- ==========================================================================

private command testAddressRoundTrip
   oxSection "v3 address <-> public key (docs/04), against real onions"
   testOneKnownAddress kTestAddrTorProject, "torproject.org's onion"
   testOneKnownAddress kTestAddrDuckDuckGo, "DuckDuckGo's onion"
end testAddressRoundTrip

private command testOneKnownAddress pAddress, pLabel
   local tPub, tInfo
   put oxPublicKeyFromAddress(pAddress) into tPub
   oxCheck (the number of bytes of tPub is 32), \
      pLabel & ": oxPublicKeyFromAddress returns a 32-byte public key"
   oxCheck oxIsValidAddress(pAddress), pLabel & ": oxIsValidAddress accepts it"

   put oxTransportInfo() into tInfo
   if tInfo["offlineAddress"] is true then
      oxCheck (oxAddressFromPublicKey(tPub) is pAddress), \
         pLabel & ": oxAddressFromPublicKey re-encodes the exact same address"
   else
      put sLog & "  --   (skipped: " & pLabel & " re-encode needs SodiumXT sxSha3_256, docs/08)" & return into sLog
   end if
end testOneKnownAddress

-- ==========================================================================
-- Section 7: structural negative paths. A malformed address must not crash
-- and must be rejected, never silently accepted (CLAUDE.md rule 4).
-- ==========================================================================

private command testAddressNegativePaths
   oxSection "address negative paths"
   oxCheck (not oxIsValidAddress("tooshort.onion")), "a too-short address is rejected"
   oxCheck (not oxIsValidAddress("not a valid onion address at all")), "garbage input is rejected"
   oxCheck (oxPublicKeyFromAddress("short.onion") is empty), \
      "a malformed address yields an empty key, not a crash"

   -- Flip the first character of a known-good address (to something else in
   -- the base32 alphabet); it must no longer validate, either structurally (if
   -- the flip breaks the version byte) or by checksum when SHA3-256 is
   -- available.
   local tTampered, tInfo
   put kTestAddrTorProject into tTampered
   if char 1 of tTampered is "2" then
      put "3" into char 1 of tTampered
   else
      put "2" into char 1 of tTampered
   end if
   put oxTransportInfo() into tInfo
   if tInfo["offlineAddress"] is true then
      oxCheck (not oxIsValidAddress(tTampered)), "a tampered address fails checksum validation"
   else
      put sLog & "  --   (skipped: tamper-detection needs SodiumXT sxSha3_256, docs/08)" & return into sLog
   end if
end testAddressNegativePaths

-- ==========================================================================
-- Small local helper (test glue only).
-- ==========================================================================

private function testZeroSeed
   local tOut, tI
   put empty into tOut
   repeat with tI = 1 to 32
      put numToByte(0) after tOut
   end repeat
   return tOut
end testZeroSeed
