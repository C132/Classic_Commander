# Commander_Promotion harness

One luajit check, never loaded by the client. Run it from the AddOns root (it finds the root from
its own path) before any change to the ceremony's trainer line or the offer. It exits non-zero on a
single failed check.

```bash
/opt/homebrew/bin/luajit Commander_Promotion/Harness/promotion_orders_smoke.lua   # 46 checks
PROMOTION_RUNTIME=/path/copy.lua luajit .../promotion_orders_smoke.lua           # a mutated CommanderPromotion.lua
```

## promotion_orders_smoke.lua - the class trainer offer (2.2.0, Commander Orders 3.1)

New ranks wait at your class trainer. On a level-up below the cap the banner names the nearest one
("New ranks at your class trainer: Brother Wilhelm (Elwynn Forest 41.1, 65.8)"), and with **Trainer
Offer** on (it ships on, like Commander Adjutant's repair offer) a quiet Commander Orders waypoint
marks it: source `Promotion`, key `trainer`, temporary, session-only, silent, never asking for the
arrow, never placed in combat (parked until PLAYER_REGEN_ENABLED, Adjutant's rule), moved by the next
level-up and taken down when you open a class trainer (not a profession one). `/cpromo trainer` is
the asked-for version: Orders' arrow there, and Orders says "Waypoint set". One owner: Promotion
offers the class trainer; Adjutant's level-up banner offers nothing (Orders 3.1 critic S9).

The harness boots the REAL Commander Orders over `Commander_Orders/Harness/orders_mock.lua` and
Promotion's two files after it. There is no Questie in the mock, so the trainers come from a
townsfolk resolver registered the way Commander Logistics registers its learned repair book.

- **A** loads clean; Trainer Offer ships on.
- **B** a level-up: the banner names the nearest trainer; ONE waypoint (Promotion, trainer),
  temporary, session-only, in the TRAINER tint, every trainer on the landmass as its choices, no
  chat line; with nothing of yours it is never PINNED; it never takes the arrow from a pin of
  yours; the next level-up moves it.
- **C** in combat: no waypoint until combat ends (the banner still says where).
- **D** a profession trainer leaves the offer; opening a class trainer takes it down.
- **E** at the cap, or with Trainer Offer off: no line, no waypoint.
- **F** nobody to name (no Questie, no resolver): no line, no waypoint, nothing errors.
- **G** `/cpromo trainer`: the waypoint with the arrow on it, Orders' "Waypoint set" line once.

Mutants killed: the offer asking for the arrow, the offer saying "Waypoint set", the combat
parking dropped, a profession trainer taking it down, an offer at the cap, a parked offer never
placed.
