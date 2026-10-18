# Headless harness (never loaded by the client — not in the TOC)

Run with the compile-gate luajit:

    /opt/homebrew/bin/luajit adjutant_queue_smoke.lua   # the 2.2.0 deployment
                                                        # countdown and the 2.3.0
                                                        # repair offer under a WoW
                                                        # mock, loading the REAL
                                                        # Commander_Events
                                                        # framework (106 checks)

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

Section O (2.3.0) is the repair alert's offer, against a stub Commander
Logistics: the banner names the nearest repair vendor and its distance, one
temporary, quiet offer per alert, never placed in combat (it lands on
PLAYER_REGEN_ENABLED, and not at all if the gear was mended first),
withdrawn once mended (asking Logistics for the offer only, `offerOnly`: a
repair waypoint you asked for on the same line is yours, review 2026-10-05),
and every switch (Mark the Nearest Repair, the repair alert itself) plus a
throwing Logistics. The same flow against the REAL
Logistics and Commander Orders is
`Commander_Logistics/Harness/logistics_orders_smoke.lua` section E.

Section P (2.4.0, Commander Orders 3.1) is the full-bags alert's offer, the
same shape against a stub Logistics "Vendor" supply line
(`CommanderLogistics_Nearest`, `_SupplyWaypoint`, `_ClearSupplyWaypoint`):
the banner names the nearest vendor and its distance, one temporary, quiet
offer per alert, parked in combat, withdrawn by the first free slot (the
offer only, `offerOnly`, as for repair), Mark the
Nearest Vendor and the alert's own switch, and a throwing Logistics. The real
flow is `Commander_Logistics/Harness/logistics_orders_smoke.lua` section I.

The AddOns path is absolute at the top of the file — adjust if the install
moves. Must exit 0 before any Adjutant change ships.
