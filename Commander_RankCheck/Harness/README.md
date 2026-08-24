# Headless harness (never loaded by the client — not in the TOC)

Run with the compile-gate luajit:

    /opt/homebrew/bin/luajit rankcheck_harness.lua    # 20 checks

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

Must exit 0 before any rank check change ships.
