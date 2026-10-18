# Commander_Vitals harness

One luajit check, never loaded by the client. Run it from the AddOns root (it finds the root from
its own path, so it also runs from this folder) before any change to the wireframe's tooltip or its
slash words. It exits non-zero on a single failed check.

```bash
/opt/homebrew/bin/luajit Commander_Vitals/Harness/vitals_orders_smoke.lua   # 29 checks
VITALS_RUNTIME=/path/copy.lua luajit .../vitals_orders_smoke.lua           # a mutated CommanderVitals.lua
```

## vitals_orders_smoke.lua - the nearest repairer (2.2.0, Commander Orders 3.1)

A worn slot's tooltip names the nearest repairer and how to go there; `/cvitals repair` points the
Commander Orders arrow at it. The rows stay hover-only (the HUD keeps passing clicks through), so the
way there is a slash word, not a click on the wireframe.

The harness boots the REAL Commander Orders over `Commander_Orders/Harness/orders_mock.lua` (the
real Commander_Events framework, this build's map rows) and Vitals' two files after it, as the
client does. There is no Questie in the mock, so the repairers come from a townsfolk resolver
registered the way Commander Logistics registers its learned repair book; Orders' locator merges
resolvers with Questie's lists and answers from them alone without Questie.

- **A** loads clean; the wireframe shows for a slot worn under the warning line.
- **B** a worn slot's tooltip: its condition, then "Nearest repair: Smith Argus (Elwynn Forest 41.8,
  67.1)" (the spot Orders' PlaceFor would take, named from the locator's own list), then
  "/cvitals repair: Go to Repair"; the coordinates follow Orders' Coordinate Decimals.
- **C** a slot above the warning line: its condition only.
- **D** nobody to name (no Questie, no resolver), or Orders switched off: the condition only, and
  nothing errors.
- **E** `/cvitals repair`: ONE waypoint (Vitals, repair) in the VENDOR tint, the arrow on the
  nearest repairer, Orders' "Waypoint set" line once; again, the same waypoint.

Mutants killed: the line on every slot, the repairer left unnamed, the waypoint unkeyed, the
coordinates not Orders'.
