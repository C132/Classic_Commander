# Headless harness (never loaded by the client — not in the TOC)

Run with the compile-gate luajit:

    /opt/homebrew/bin/luajit adjutant_queue_smoke.lua   # the 2.2.0 deployment
                                                        # countdown under a WoW
                                                        # mock, loading the REAL
                                                        # Commander_Events
                                                        # framework (54 checks)

Covers the battleground invite countdown end to end: the pop banner, the bar
anchored under whichever invite window is up (PVPReadyDialog on this client,
the CONFIRM_BATTLEFIELD_ENTRY static popup as the other path), the drain
fraction, the free-standing timer that takes over when the invite is hidden
and the click that ports you in through it, the once-per-invite closing
warning, the fallback window for a client that will not report an expiration,
millisecond normalization, every settings gate (countdown, keep-after-hiding,
pop banner, master switch), and the `/cadj timer` demo.

The queue mock is the honest part of this: `GetBattlefieldStatus` and
`GetBattlefieldPortExpiration` are driven per queue slot, so the timer is
tested against the same shape the client hands it.

The AddOns path is absolute at the top of the file — adjust if the install
moves. Must exit 0 before any Adjutant change ships.
