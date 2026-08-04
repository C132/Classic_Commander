# Headless harnesses (never loaded by the client — not in the TOC)

Run with the compile-gate luajit:

    /opt/homebrew/bin/luajit meters_harness.lua      # engine fixture: §7 invariants,
                                                     # determinism, retention, resets,
                                                     # throughput measurement (736 checks)
    /opt/homebrew/bin/luajit meters_ui_harness.lua   # UI smoke under a WoW mock, loading
                                                     # the REAL Commander_Events framework
                                                     # (134 checks)

Paths to the AddOns dir are absolute at the top of each file — adjust if the
install moves. Both must exit 0 before any engine or UI change ships.
