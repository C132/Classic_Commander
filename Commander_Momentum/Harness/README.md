# Headless harness (never loaded by the client — not in the TOC)

Run with the compile-gate luajit:

    /opt/homebrew/bin/luajit momentum_harness.lua    # streak + zone-record logic under
                                                     # a WoW mock, loading the REAL
                                                     # Commander_Events framework
                                                     # (60 checks)

Covers login/restore, kill chains through CLEU, window expiry via the
watchdog ticker, the per-zone record books (live writes, baseline captures,
end-of-chain recaps, open-world border crossings, instance naming), death
and zone-change session resets, the tester's no-side-effects contract,
lament stats, the window clock spelled out in the public brag and lament,
the player-frame display (every style draws, the legacy `PORTRAIT` value
lands on the ring style, placements resolve to the right anchor frame and
point, the info toggles compose the readout, Combat Only hides the display
without touching the chain), `/cmom report|records|display`, and
settings-reset survival of the records. `DUMP=1` prints every chat line the
run produced, in order.

The AddOns path is absolute at the top of the file — adjust if the install
moves. Must exit 0 before any momentum change ships.
