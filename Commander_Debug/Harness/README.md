# Headless harness (never loaded by the client — not in the TOC)

Run with the compile-gate luajit:

    /opt/homebrew/bin/luajit debug_harness.lua   # capture + report under a WoW mock,
                                                 # loading the REAL Commander_Events
                                                 # framework (122 checks)
    /opt/homebrew/bin/luajit globals_lint.lua    # a local declared after its use
                                                 # compiles to a global read; this
                                                 # catches that (0 tolerated)

`debug_harness.lua` covers both capture paths — the built-in error hook
(dedupe by message, occurrence counters, chaining to the previous handler,
LUA_WARNING and blocked-action lines) and the BugGrabber adapter (session
scoping, corrupt-entry rejection, newest-first ordering) — plus attribution
parsing across the path shapes error text actually uses, the Commander-only
filter, the error cap, and then the report itself: header contents, per-error
blocks, stack and locals toggles, line trimming, escape-sequence sanitising,
the empty state, and the page split (every error appearing on exactly one
page, each page standing alone as a prompt, an oversized single error still
getting a page). `DUMP=1` prints the first built page in full.

The AddOns path is absolute at the top of each file — adjust if the install
moves. Both must exit 0 before any Commander Debug change ships.
