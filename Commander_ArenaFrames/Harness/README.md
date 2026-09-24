# Commander Arena Frames — harness

Two generators and a test. Nothing here runs in the game; everything here runs
without it, which is the point.

## The generators

Both write a Lua fragment that is pasted into `CommanderArenaFramesData.lua`.
Re-run them after a client patch and diff the result — a change in either
output is a change in the game's rules and deserves to be read.

They need the client's own DB2 tables as CSV, for the build the account is
actually running (`/Applications/World of Warcraft/.build.info` → `Version`):

```
for t in SpellName SpellCategories SpellEffect SpellClassOptions \
         SkillLineAbility SkillLine SpellDuration SpellMisc SpellCooldowns; do
  curl -sSL -o "$t.csv" "https://wago.tools/db2/$t/csv?build=2.5.6.69546"
done
```

### `make_dr_table.py` — diminishing returns

```
python3 Commander_ArenaFrames/Harness/make_dr_table.py --csv <dir> --out dr.lua
```

The classifier is a transcription of CMaNGOS `mangos-tbc`'s
`GetDiminishingReturnsGroupForSpell` (`src/game/Spells/SpellMgr.cpp`), run over
the client's own mechanic and spell-family columns. That is what makes the
result an implementation of the rules rather than a list somebody typed: every
rank of every spell is covered, including the triggered auras nobody trains and
so nobody remembers (Freezing Trap Effect, Seduction's applied aura).

Three things in it are hand-maintained, and each is commented where it lives:

* the **triggered** stun/root list. `triggered` is a property of the cast
  (`m_triggeredByAuraSpell != nullptr`), not a column — it means "an aura
  procced this", which in TBC is a short closed list of talents. Note what it
  does *not* include: Charge Stun and Intercept Stun are triggered by a spell
  effect, so they are ordinary controlled stuns.
* the **Turn Evil** and **Nature's Grasp** `Attributes` guards. Their family
  bits alone are shared with Divine Protection, Vindication and Holy Light.
* the **Dragon's Breath** disorient filter. Blast Wave carries the same family
  bit in this client's data and the server does hand both to the same group;
  harmless there, wrong on a board that opens a bracket from it.

### `make_cooldown_book.py` — the enemy cooldown book

```
python3 Commander_ArenaFrames/Harness/make_cooldown_book.py --csv <dir> --out book.lua
```

*Which* abilities are worth a slot is curated in the `BOOK` table at the top of
the script — that is a judgement about arena, and it belongs to a person. Every
number attached to them is the client's own.

Skill lines are keyed by **ID, never by name**: three display names are shared
by two classes each ("Protection" is warrior 257 and paladin 267, "Holy" is
paladin 594 and priest 56, "Restoration" is shaman 374 and druid 573), and
keying on the name hands one class the other's spellbook. The warlock's pet
lines are attributed to the warlock, because an arena player counts Spell Lock
and Seduction as the warlock's cooldowns.

The script reports two things rather than hiding them: entries it could not
find, and entries it dropped because the client says they have no cooldown
(Cyclone, Purge, Piercing Howl, Mass Dispel and friends genuinely have none in
TBC). Read both.

## The tests

```
luajit Commander_ArenaFrames/Harness/arenaframes_engine_smoke.lua
```

Covers `CommanderArenaFramesEngine.lua`, which touches no WoW API at all. The
sections that matter:

* **A** asserts the DR category of the ~40 spells a TBC arena is actually
  decided by, and asserts that silence, Scatter Shot and Blast Wave carry no
  DR — the three a board is most likely to bracket wrongly.
* **B/C** are the reset clock. It starts when the aura **fades**, not when it
  lands, and it is frozen while anything in the category is still up. An
  apply-stamped clock reads "full" while the enemy is still stunned; there is a
  test whose only job is to fail if someone reintroduces that.
* **D** is duration prediction: the 10s PvP cap applies **before** the ladder,
  which is why a 50s Polymorph and a 20s Fear both come out at 5s on the second
  cast.

```
luajit Commander_ArenaFrames/Harness/arenaframes_board_smoke.lua
```

Covers the half the engine test cannot reach: what the board actually PAINTS
once a client has answered. It loads all four files of the module over a WoW
mock (the widget model is lifted from the Party Frames harness, which is where
it was built), fires real events, and asserts on the text and the colours that
come out the other end. Every section is there because of a specific failure,
and each one has been checked by breaking the fix and watching it go red:

* **A/B** the state strip, and the fact that crowd control LEADS it. A sap used
  to reach the board only as a 16-pixel icon sorted below every buff the enemy
  had — so five buffs pushed it off a five-slot strip entirely, and the one
  thing the board most needed to say was the first thing it discarded.
* **C** silence. TBC gives it no diminishing returns at all, so a lockout
  carries no DR category — and a board that derives "are they controlled" from
  the DR table alone never draws a locked-out healer, which is the most
  valuable thing it could say to a caster.
* **D/E** the priority ladder between the five states that can claim the strip,
  and the fact that an expired one lapses on its own. The scan deliberately
  bails on a unit the client will not answer for, so nothing else would clear
  it.
* **F** the enemy the client will not answer for. A stealthed rogue used to be
  drawn at FULL health, which is the most misleading thing an arena frame can
  say about the enemy who just vanished at 20%.
* **G** names, cut in characters rather than bytes. `#name` counts bytes, so a
  cut through an accented name lands mid-sequence — and it is precisely the
  long names that get cut, so the bug only ever showed on the enemy whose name
  did not fit.
* **H** the board coming down. Leaving an arena flipped a flag and wiped the
  state, but nothing called `Draw` — so the board stayed on screen, frozen on
  the last frame of the game that had just ended.

## The renderer

```
luajit Commander_ArenaFrames/Harness/arenaframes_render.lua board.json
python3 Commander_ArenaFrames/Harness/render_svg.py board.json board.svg 4
qlmanage -t -s 1400 -o . board.svg        # board.svg.png, on a Mac
```

The board smoke's mock records every `SetPoint`, `SetSize`, colour, texture,
font size, text and sweep. That record is enough to *draw* the test board —
not with the game's art (icons are labelled squares, the class sheet is a
plain tile), but with the real layout code's own numbers, which is the half of
"does it look right" that a queue is not needed for. `arenaframes_render.lua`
runs the smoke and, at the moment the test board is up and painted, resolves
every anchor to an absolute rectangle and writes the lot; `render_svg.py`
draws it at 4x. It exists because the 2026-09-20 Gladdy pass was made against
it: the spark overshooting the power bar, the state clock a different size
from the health number, and `HELD` spilling off an 18-pixel icon were all
found in the picture, none of them in a check.

Text widths in it are estimated (the mock has no font metrics), so two labels
on one line can *look* closer together than the game draws them; positions,
sizes and everything else are exact.

## The other two checks

```
python3 Commander_ArenaFrames/Harness/settings_reach.py
python3 Commander_ArenaFrames/Harness/order_lint.py
```

**`settings_reach.py`** answers the question the phrase "highly configurable"
actually rests on: can the settings page reach every setting the board obeys?
The failure it exists for is invisible — a setting the engine really reads and
no control can change, so the board behaves in a way the user cannot explain
and cannot fix, and nothing in the code looks wrong. It has already caught two
(`HealthTextSize`, and a `Scale` that duplicated the HUD chrome's).

**`order_lint.py`** catches a local function used above its own declaration.
Lua resolves a bare name at compile time, so a call written above `local
function Say` compiles to a global lookup, finds nil, and errors only when that
branch finally runs — which in a combat addon can mean "only when an enemy
presses a particular button". This module had exactly that: the alert helpers
sat below the combat-log handler that called them, so an announced defensive
would have thrown. It was found by reading bytecode, which is not a repeatable
way to find anything; the lint reads the same bytecode automatically. It then
immediately caught a second one that moving the first had created.
