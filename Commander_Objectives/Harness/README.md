# Commander_Objectives harness

One luajit check, never loaded by the client. Run it from the AddOns root (it finds the root from
its own path) before any change to the Turn-in Offer. It exits non-zero on a single failed check.

```bash
/opt/homebrew/bin/luajit Commander_Objectives/Harness/objectives_orders_smoke.lua   # 42 checks
OBJECTIVES_RUNTIME=/path/copy.lua luajit .../objectives_orders_smoke.lua           # a mutated CommanderObjectives.lua
```

## objectives_orders_smoke.lua - the Turn-in Offer (2.2.0, Commander Orders 3.1)

When a quest in your log turns complete, the **Turn-in Offer** (off by default: quests finish
often) marks where to hand it in: a quiet Commander Orders waypoint at the quest's finisher (source
`Objectives`, key `turnin:<questID>`), every placed spawn as its choices so the arrow takes the
nearest, temporary, session-only, saying nothing and never asking for the arrow (Commander
Adjutant's offer rule); never placed in combat (parked until PLAYER_REGEN_ENABLED); taken down when
the quest is turned in (QUEST_TURNED_IN), abandoned (QUEST_REMOVED) or seen no longer complete. The
quest log is scanned a moment after a QUEST_LOG_UPDATE burst and never expanded (that would move the
selection the stock log and other addons read), so a quest under a collapsed header keeps its state.
The finisher comes from Commander Quest Log's Questie adapter (`CommanderQuestLog.Questie.Finisher`),
the suite's one reader of quest data; without it there is no offer.

The harness boots the REAL Commander Orders over `Commander_Orders/Harness/orders_mock.lua` and
Objectives' two files after it. The quest log is the mock's, and Quest Log's adapter is a stand-in
answering `Finisher(questID)` in its real shape (`{ name, uiMapId, x, y (0..100), spawns }`).

- **A** loads clean; the offer ships off, and off it marks nothing.
- **B** on: a quest turning complete is ONE waypoint (Objectives, turnin:60) titled "Turn in: The
  Fargodeep Mine (Marshal Dughan)", at the finisher, every spawn as its choices, temporary,
  session-only, in the QUEST tint, with no chat line; it never takes the arrow from a pin of yours
  and is never PINNED; quests already complete at login are not offered; another update adds nothing.
- **C** turned in, no longer complete, complete again, abandoned: offered and withdrawn as it should
  be; a quest under a collapsed header keeps its offer and is not offered twice.
- **D** in combat nothing is placed until combat ends; with nothing of yours it is still never
  PINNED.
- **E** without Quest Log's adapter, or a finisher Questie cannot place: nothing.

Mutants killed: the offer asking for the arrow, quests already complete at login offered, a collapsed
header withdrawing, turn-in and abandon not withdrawing, the parked offer never placed, combat not
parking, the spawns dropped.
