# Commander_Armory harnesses

Three luajit checks, all in-addon. Run **all three** before any change.

```bash
/opt/homebrew/bin/luajit armory_harness.lua      # engine fixture — 459 checks
/opt/homebrew/bin/luajit armory_ui_harness.lua   # UI + host      — 356 checks
/opt/homebrew/bin/luajit globals_lint.lua        # 5 files, 0 undeclared globals
```

All three resolve the AddOns root from their own file location, so they work in
a git worktree as well as in the live AddOns directory. Each is silent on
success and exits non-zero on the first failure it finds.

---

## `armory_harness.lua` — the engine

No mock at all. `CommanderArmoryEngine` is pure Lua, so this loads only
`CommanderArmoryData.lua` and `CommanderArmoryEngine.lua` and drives
hand-written world snapshots through the real calls. A failure here is always a
real logic bug, never a mock artefact.

Covers item identity against links this client really writes, the three-state
entry model and the IGNORED-is-not-EMPTY invariant, the flyout's contents and
ordering, every refusal path in the planner, the complete TBC unique-equipped
model, the allocation ledger that tells two identical rings apart by location,
free-bag-slot accounting by formula, the multi-pass run state machine, and the
stat totals.

Sections **B2** and **B3** are the newest and cover the two halves of authoring:
that a *new* set is naked (nineteen entries, seventeen `EMPTY`, shirt and tabard
`IGNORED`) and therefore plans a real strip rather than the no-op an entryless
set used to plan; and that an entry built from a candidate row carries every
field a captured one does — `baseKey` especially — and is a **copy**, so
rewriting the pooled row it came from cannot reach it.

## `armory_ui_harness.lua` — the UI and the host

Loads the **real** shared framework (`CommanderSettingsUI.lua`,
`CommanderEvents.lua`) plus all five addon files under the suite's permissive
widget mock, on top of a fixtured world: nineteen paperdoll slots on a
protection paladin, three bags (one of them a quiver, so the family-0 rule has
something to exclude), a bank with two pieces in it, and a character frame with
five tabs waiting for a sixth.

The cursor is the reason this file is long. **The mock's pickups really move
items**: `PickupInventoryItem` empties the square it came from, locks it, fires
`ITEM_LOCK_CHANGED`, and puts a displaced item back where the incoming one came
from. So a run below genuinely relocates items between the fixture containers,
and the assertions afterwards read the fixture rather than the addon's opinion
of it. `PickupInventoryItem` and `PickupContainerItem` also record a violation
if they are ever reached under `InCombatLockdown()`, which is how the harness
proves the combat rules rather than assuming them.

Sections, in order:

- **A** boots with **no `CharacterFrame` at all**, checks nothing errors and the
  window fallback works, then introduces the character sheet and checks the tab
  is adopted on the next settings pass rather than needing a reload.
- **B** the settings page: every section, the scroll frame, the slash
  registration, the module registry entry.
- **C** the sixth tab: id 6, listed in `CHARACTERFRAME_SUBFRAMES`, sized by hand
  because the built-in bounds check only loops 1..5, and clicking it shows our
  frame and hides the paperdoll (and tab 1 brings it back).
- **D** the paperdoll: nineteen popout arrows, none on ammo, each pointing away
  from the model, plus the ignore overlays and the chained
  `PaperDollItemSlotButton_Update` hook.
- **E** the flyout's actual contents: the worn item excluded, the other ring
  offered and badged `worn: Ring 2`, a one-hander refused off-hand until dual
  wield is trained, item level descending, search, and alt-click hiding.
- **F** the bank: nothing invented before the first visit, a live withdrawal
  badge at the bank, and away from it the item **still listed**, badged and
  dimmed, with a click that says "open a banker" instead of failing silently.
- **G** slot 18's three faces: `RELIC` offering only this class's librams,
  `RANGED` offering only bows, and the ammo readout following.
- **H** the cursor and locks as primitives, before anything depends on them.
- **I/J** one-slot swaps through the popout (including a ring-to-ring swap that
  must never route through a bag), then a whole set equipped end to end with the
  runner driven to completion and the fixture inspected afterwards.
- **K** ignore semantics, including the case retail gets right.
- **L** the three slot states rendered distinctly: ignored is our overlay,
  locked is desaturation, broken is Blizzard's 0.9/0/0 red — and each says which
  it is in words on the tooltip.
- **M** pre-flight: missing and banked as two different answers, in the plan
  reasons, in the pane's sentence, in the set-list row, and in `/cgear list`.
- **N** combat: queue, announce, refuse to drain while combat is on, flush on
  `PLAYER_REGEN_ENABLED`, cancel, and the merchant refusal.
- **O** the secure channel: the `/equipslot [combat]` macrotext, the sibling
  container parented to `UIParent`, and an empty macro for a set that ignores
  the weapons.
- **P** stats, the set list rows, and the item tooltip line (including that a
  second `OnTooltipSetItem` for the same item does not stack a duplicate).
- **Q/R/S** every slash command, the name/icon dialog, Restore Defaults leaving
  the sets alone, and the wipe.
- **U** runs on the far side of the wipe, from zero sets — which is exactly the
  state a new set is made from. A new set is naked and captures nothing; the
  ignore scratchpad reflects shirt and tabard and nothing else; a click on the
  pane's slot grid writes the set and moves not one square of the fixture, while
  the same list opened from the paperdoll arrow still equips; leave-bare writes
  `EMPTY` as a real entry; shift-click wears instead of writing; the header
  renames in place and refuses an empty or duplicate name out loud; the item
  tooltip answers both ways and stays silent for a potion and for ammo; and a
  fresh naked set, equipped, really does take the gear off.
- **T** last: nothing accumulated — no errors, no restricted call, empty cursor.

## `globals_lint.lua`

Dumps `luajit -bl` bytecode for all five addon files, greps the `GGET`/`GSET`
constant names, subtracts an `ALLOWED` list (base library, suite globals, our
own exports, OptionalDeps, and the WoW APIs each file deliberately touches), and
fails on anything left over.

In Lua a local declared **after** a function body is not in that body's scope,
so the reference compiles to a global read and returns nil at runtime with no
warning at all. Nothing else in the toolchain catches it. Add a genuinely new
WoW API to `ALLOWED`, with a note saying where it is called from; do not add a
name to make the lint quiet, because that is the failure mode it exists for.

---

## Checks that exist because they caught a real bug

Each of these was written against behaviour that was wrong at the time. They are
listed with the bug, so nobody weakens one later without knowing what it cost.

**`globals_lint`: `UNDECLARED GLOBAL CommanderArmoryUI.lua HiddenMap`**
The local `HiddenMap()` helper was removed from `CommanderArmoryUI.lua` while
two call sites were left behind. Both compiled cleanly; the file loaded cleanly;
the module ran happily right up until somebody opened a popout, at which point
`CandidateRows` tried to call nil. The lint named the file, the global and the
reason in under a second, before a single frame had been drawn.

**`U: and does NOT capture the gear you are wearing into it`**
The opposite half of the check below, and the reason both are needed. `/cgear
save <name>` means "record what I have on" and must still do exactly that; the
pane's **New** button must now do the opposite and leave the set naked. The two
share `NewSet` and one ignore scratchpad, so an edit that fixes either one in
isolation breaks the other silently — the set still exists, still appears in the
list, and only its entries say which behaviour ran.

**`Q: /cgear save <name> ... and records the gear you are wearing in it`**
A brand-new set has an empty `entries` table, and the "a slot with no entry is
IGNORED" rule — which exists to make a *half-authored* set safe — read that as
"every slot ignored". `NewSet` loaded that into the ignore scratchpad and the
very next `CaptureSet` therefore recorded a set that touches nothing. `/cgear
save Arena` produced a set that did precisely nothing, silently, forever. The
check asserts the saved set contains at least one `ITEM` entry, which is the
only thing the command is for.

**`R: accepting the New dialog stores the set`**
The name dialog built its set with `E.NewSet` and handed it straight to
`SaveSet`, which fills in `entries` but does not append to the store. The set
was announced as saved, appeared nowhere, and vanished at the next repaint. The
check counts the sets before and after, rather than trusting the "saved" line.

**`J: without calling it a refusal` / `J: and without leaving the run state BLOCKED`**
The engine deliberately answers "nothing to do" with `ok = false` and
`verdict = "OK"`, and says in its own comment that the two are different
questions. `StartRun` branched on `plan.ok` alone, so equipping a set you were
already wearing printed a red `"Arena Kit" cannot be equipped:` and parked the
run state at `BLOCKED` — and the `is already on` branch next to it was
unreachable. Asserting only "no run started" would have passed throughout.

**`S: the bank cache goes with them` / `S: as does the hidden-item list`**
`COMMANDER_ARMORY_WIPE` tells the player "the bank cache and the hidden-item
list go with them", and the DB file's own fallback path clears all three — but
the host's `CommanderArmory_WipeSets`, which is the path that actually runs,
cleared only `store.sets`. A wiped character kept a bank cache describing gear
for sets that no longer existed. The checks read the store directly rather than
the confirmation message.
