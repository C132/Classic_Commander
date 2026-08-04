# Headless harness (never loaded by the client — not in the TOC)

Run with the compile-gate luajit:

    /opt/homebrew/bin/luajit momentum_harness.lua    # streak + zone-record logic under
                                                     # a WoW mock, loading the REAL
                                                     # Commander_Events framework
                                                     # (43 checks)

Covers login/restore, kill chains through CLEU, window expiry via the
watchdog ticker, the per-zone record books (live writes, baseline captures,
end-of-chain recaps, open-world border crossings, instance naming), death
and zone-change session resets, the tester's no-side-effects contract,
lament stats, `/cmom report|records`, and settings-reset survival of the
records. `DUMP=1` prints every chat line the run produced, in order.

The AddOns path is absolute at the top of the file — adjust if the install
moves. Must exit 0 before any momentum change ships.
