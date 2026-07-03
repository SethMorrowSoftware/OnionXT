#!/usr/bin/env python3
"""build-standalone.py - bundle the OnionXT + onion-httpd libraries and the demo
app into ONE self-contained .livecodescript.

You can use the pieces two ways:
  - as LIBRARIES (start using onionxt + onion-httpd, app on top) - best for real
    projects; the sources under src/ and examples/ are the single source of truth;
  - as ONE stack script - paste examples/onion-httpd/standalone.livecodescript into
    a single mainstack's stack script and it self-builds its UI, no wiring.

This script generates the second from the first, so there is no duplicated code to
keep in sync. It also refuses to build if the parts have colliding constant /
handler / script-local names (a merged script would fail on the engine otherwise).

Usage:
  python3 tools/build-standalone.py           # write the standalone
  python3 tools/build-standalone.py --check    # verify the committed file is current
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = "examples/onion-httpd/standalone.livecodescript"

# Order matters: constants must be declared before use, and each part only uses
# its own (and earlier parts'), so library first, then the app.
PARTS = [
    ("OnionXT library", "src/onionxt.livecodescript"),
    ("onion-httpd library", "src/onion-httpd.livecodescript"),
    ("demo / test app", "examples/onion-httpd/spike.livecodescript"),
]

HEADER = """\
-- standalone.livecodescript - OnionXT onion-service hosting, ALL IN ONE stack script.
--
-- GENERATED - do not edit by hand. Regenerate with tools/build-standalone.py after
-- changing src/onionxt.livecodescript, src/onion-httpd.livecodescript, or
-- examples/onion-httpd/spike.livecodescript (the sources of truth). It concatenates
-- the two libraries and the demo app into one script, so you can paste it straight
-- into a single mainstack's stack script with no "start using" wiring: every ox* /
-- oxh* / demo handler lives in the one script and self-builds the UI on preOpenStack.
-- (For a real project, prefer the libraries; this is for quick paste-and-run testing.)
--
-- TO TEST: new mainstack -> Object menu -> Stack Script -> paste this whole file ->
-- Apply. Have a tor daemon with the control port enabled (see the OnionXT README
-- Troubleshooting). Then reopen the stack (so preOpenStack builds the UI), click
-- Start, then Share Folder, and open the printed .onion in Tor Browser.
"""

HANDLER_RE = re.compile(
    r"\s*(?:private\s+)?(?:on|command|function|getter|setter)\s+([A-Za-z_][A-Za-z0-9_]*)")
CONST_RE = re.compile(r"\s*constant\s+([A-Za-z_][A-Za-z0-9_]*)")
LOCAL_RE = re.compile(r"\s*local\s+([A-Za-z_][A-Za-z0-9_]*)\s*$")


def names(text):
    """Declared constant names, handler names, and top-of-script local names."""
    consts, handlers, script_locals = set(), set(), set()
    seen_handler = False
    for line in text.splitlines():
        stripped = line.split("--", 1)[0]
        m = CONST_RE.match(stripped)
        if m:
            consts.add(m.group(1))
        m = HANDLER_RE.match(stripped)
        if m:
            handlers.add(m.group(1))
            seen_handler = True
        m = LOCAL_RE.match(stripped)
        if m and not seen_handler:      # a script-local lives above the first handler
            script_locals.add(m.group(1))
    return consts, handlers, script_locals


def build():
    owner = {"constant": {}, "handler": {}, "script-local": {}}
    collisions = []
    chunks = [HEADER]
    for label, rel in PARTS:
        with open(os.path.join(ROOT, rel), encoding="utf-8") as handle:
            text = handle.read()
        consts, handlers, script_locals = names(text)
        for kind, found in (("constant", consts), ("handler", handlers),
                            ("script-local", script_locals)):
            for name in sorted(found):
                if name in owner[kind]:
                    collisions.append(
                        f"{kind} `{name}` in {rel} collides with {owner[kind][name]}")
                else:
                    owner[kind][name] = rel
        bar = "-- " + "=" * 72
        chunks.append(f"\n\n{bar}\n-- ==== {label}  ({rel})\n{bar}\n\n{text.rstrip()}\n")
    if collisions:
        sys.stderr.write("build-standalone: NAME COLLISIONS (merged script would fail):\n")
        for c in collisions:
            sys.stderr.write("  " + c + "\n")
        sys.exit(2)
    return "\n".join(chunks)


def main(argv):
    content = build()
    out_path = os.path.join(ROOT, OUT)
    if "--check" in argv[1:]:
        try:
            with open(out_path, encoding="utf-8") as handle:
                current = handle.read()
        except FileNotFoundError:
            current = None
        if current != content:
            print(f"build-standalone: {OUT} is STALE; run tools/build-standalone.py")
            return 1
        print("build-standalone: standalone is up to date")
        return 0
    with open(out_path, "w", encoding="utf-8") as handle:
        handle.write(content)
    print(f"build-standalone: wrote {OUT} ({content.count(chr(10)) + 1} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
