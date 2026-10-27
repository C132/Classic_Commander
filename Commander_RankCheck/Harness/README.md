# Headless harness (never loaded by the client — not in the TOC)

Run with the compile-gate luajit:

    /opt/homebrew/bin/luajit rankcheck_harness.lua    # 50 checks

`DUMP=1` prints every chat line the run produced, in order.

## What it guards

The mock models this client's **actual** spell APIs, which is the whole point
of the harness. On the Anniversary client:

- `C_Spell.GetSpellInfo` returns a `SpellInfo` struct with **no subtext field**,
  so the global `GetSpellInfo` built on it returns `nil` in the old "rank" slot.
  `local name, rank = GetSpellInfo(id)` reads nothing, forever.
- Rank text is only reachable as `C_Spell.GetSpellSubtext(spellID)`, and it
  **loads asynchronously** — empty until the client sends the spell's text.
  Blizzard's own spellbook (`Blizzard_UIPanels_Game/Vanilla/SpellBookFrame.lua`)
  waits on `Spell:CreateFromSpellID(id):ContinueOnSpellLoad()` before drawing
  its rank line, and reads the subtext off the spell object, not off the
  `GetSpellBookItemName` return it discards.

That combination produced the bug this harness exists to prevent: every slot
read as rankless, `rank > 0` was never true, nothing was ever compared, and the
module reported a cheerful `PASS — all 0 ranked references`. So the checks
assert on the **count of references actually checked**, not just on the verdict
— a scan that examines nothing must never look like a scan that found nothing
wrong. The same reasoning covers the timeout path: when spell text never
arrives, the report says so instead of passing.

Also covered: stale bar slots and their replacement rank, current ranks and
rankless spells never being flagged, macro downranks vs. rankless `/cast`, the
Check Action Bars / Check Macros / Announce When Clean toggles, the quiet login
run (silent when clean, vocal when stale), the disabled-module path, and
`/crank debug`'s per-slot dump.

3.0 (2026-10-26, for Commander Spellbook's Rank Check view) adds:

- `CommanderRankCheck.Scan` as data: every ranked reference, stale or not, with
  the best rank's spell id, broadcast as `COMMANDER_RANKCHECK_RESULT`, and no
  chat of its own (8).
- **Update** on a bar slot, with its guard rails: nothing in combat, nothing
  with the cursor holding something, nothing over a slot that changed since the
  check, and a pickup that failed never reaches `PlaceAction` — the mock's
  PlaceAction swaps exactly as the client's does, so the case where the old
  spell would be lifted off the bar and dropped is reproduced, not assumed (9).
- **Update** on a macro: only that spell at that rank is rewritten, the rest of
  the body byte for byte, paren-named spells whole, name and icon kept (10).
- **Keep**: a kept reference stops failing (and the report says how many were
  kept), Update All leaves it alone, a different rank in the kept slot fails
  again, Unkeep and Clear Kept (11).

Must exit 0 before any rank check change ships.
- A `#showtooltip` line's rank moves with the `/cast` line; an account and a
  character macro of one name keep apart (the key carries the list); a rewrite
  that would pass 255 characters is refused and said so; a refused Update says
  why; Update All ends with its tally; macros are saved with
  `EditMacro(index, nil, nil, body)`, Blizzard's own way (12).
