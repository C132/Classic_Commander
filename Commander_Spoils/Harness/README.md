# Commander_Spoils harness

Offline smoke checks that load the REAL shared framework
(`Commander_Events/CommanderSettingsUI.lua` + `CommanderEvents.lua`) and all
three Commander_Spoils files under a permissive WoW mock. It must exit 0 before
any change ships.

```
/opt/homebrew/bin/luajit spoils_harness.lua      # 245 checks
/opt/homebrew/bin/luajit globals_lint.lua        # 0 undeclared globals
```

The mock drives `OnUpdate` on every created frame (`RunFrames`), because the
addon's ticker is an anonymous local — leaving it undriven meant the entire
dirty-repaint and visibility-reconcile path had no coverage, which is where
three round-3 defects were hiding.

`globals_lint.lua` exists because a Lua local declared AFTER a function body is
not in that body's scope — the reference compiles to a global read and returns
nil. This module hit that five times during development, and the last one
(`createdThisTick`, which silently disabled the reconciler's CRAFTED
attribution) was found by the lint rather than by a human. It dumps luajit's
bytecode listing, subtracts the globals the module means to touch, and fails on
anything left. Add a genuinely new WoW API to its `ALLOWED` list; never add a
name just to make it quiet.

The path to the AddOns dir is absolute at the top of the file — adjust if the
install moves.

Coverage: the Blizzard-takeover suppression layer in both directions (exact
restore from an `IsEventRegistered` snapshot, idempotent `Sync`, `Undo` vs
`RestoreAll`, the master switch as an exit path, the watchdog's session block);
the GlobalString pattern builder against this build's literal enUS strings
(bracket escaping in the `|HlootHistory:` prefix, non-greedy capture past an
`x` in an item name, roll/item/player argument order); loot, money and currency
parsing including another player's pickups; the `(classID, subClassID)`
classifier and the Armor/Cloth vs Tradegoods/Cloth trap; the bag census (junk
by sellPrice not `hasNoValue`, reclaimable partial stacks); the reconciler
(baseline-not-diff on the first scan, merchant attribution, bank-open
suppression, silent acquisitions filed as OTHER and kept out of the headline);
the roll lifecycle (misclick guard, ineligibility enforcement, win detection
from loot history, withdrawn ≠ missed, ineligible ≠ missed, packed player
detail, `GetActiveLootRollIDs` reload recovery, a malformed server confirm
string); the interest model's precedence; value tiers; folds; retention and
index rebasing; sparse master-loot probe indices; loot slots including the
uncached case; a UI smoke over every pane, scope and filter; one regression check per defect
the peer review found, and the Try It buttons (each one drives the real
painting code, so a broken band fails here rather than in a raid).

The frame names the harness addresses are the shipped ones:
`CommanderSpoilsFrame` and its bands `CommanderSpoilsPickups`,
`CommanderSpoilsCorpse`, `CommanderSpoilsRolls`, with rows
`CommanderSpoilsRow<N>`, `CommanderSpoilsPickupRow<N>`,
`CommanderSpoilsSlotRow<N>`, `CommanderSpoilsRollRow<N>` and
`CommanderSpoilsCandidateRow<N>`.

Mock lessons baked in (do not regress):

- Auto-generated widget methods are **prefix-matched only**, so template-child
  probes (`check.Text`) read nil unless `CreateFrame` provides them explicitly.
- `HookScript` **chains** handlers; `SetScript` replaces.
- `IsEventRegistered` is implemented for real, because the suppression layer's
  whole correctness claim rests on it.
- `C_Timer.After` feeds an executable queue: the settle debounce re-schedules
  itself, and auto-pass runs on a 2s grace.
- Rows are **named** (`CommanderSpoilsRow1`, `CommanderSpoilsContestRow1`,
  `CommanderSpoilsSalvageRow1`, `CommanderSpoilsWireRow1`) purely so the
  harness can assert content. A UI check that only asserts "nothing threw"
  cannot tell a working feature from one that silently does nothing — that was
  the peer review's central criticism and the reason those names exist.
