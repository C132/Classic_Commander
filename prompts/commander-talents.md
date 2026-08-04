# Commander_Talents — the war academy

A full TBC talent calculator inside the game, styled and framed like the
Quartermaster browser. Every class, every tree, every spec — browsable and
editable without a trip to Wowhead, with the suite's loadout language on top:
preset builds for every specialization Quartermaster cites, stat priorities on
the side, and the Quartermaster consumable loadout for the same spec one panel
over.

## Why in-game

Wowhead's TBC calculator is the reference, but it lives in a browser tab.
In-game you want the same three trees while respeccing at the trainer, while
arguing over a build in guild chat, while deciding what your alt becomes. The
client itself only knows YOUR class's trees (`GetTalentInfo` has no inspect
mode on this client), so the addon embeds the full 2.4.3-final talent data for
all nine classes — that is the price of admission and the whole point.

## Shape

One window, `CommanderTalentsFrame`, BasicFrameTemplateWithInset at 1010×590
(WINDOW/DARK/CLASSIC framing + scale + saved screen-space position — the
Quartermaster patterns verbatim, including the drag strip, UISpecialFrames,
and the settings mirror). Bare `/ctalents` (or `/ctal`) toggles it.

- **Left sidebar (Quartermaster's sidebar, 190px):** the loadout list for the
  selected class. Preset builds first (one per Quartermaster spec key — the
  same 27 keys, same names, same role tags), then MY BUILDS (account-wide
  custom saves), then the selection acts on the trees. Class picked from a
  toolbar dropdown, class-colored, defaulting to your own class.
- **Center: all three talent trees side by side**, each on its proper
  `Interface\TalentFrame\<bg>` four-piece art, 4×9 grid, prerequisite arrows
  drawn with Blizzard's own branch/arrow texture coordinates (taken from
  `TalentFrameBase_Shared.lua` on the `classic_anniversary` branch of
  Gethe/wow-ui-source — this client's UI source), rank badges,
  gold-when-maxed,
  desaturated-when-locked. Left click adds a point, right click removes one —
  removal is validated (tier support and prerequisites), and the tooltip
  explains every lock in Blizzard's own red phrasing. **Shift** runs a click
  to its limit (fill to max / empty the talent), stopping at the first
  refusal so a bulk click can never leave an illegal build. Right-clicking a
  **tree header** clears just that tree.
- **Right briefing panel (~210px):** the selected loadout's identity — name,
  role, the 17/44/0 signature — then STAT PRIORITY as a numbered list, NOTES,
  and CONSUMABLES pulled live from Commander_Quartermaster's recommendation
  for the same class+spec key (soft-fail when Quartermaster is absent: the
  section explains itself and nothing errors). An "Open in Quartermaster"
  button jumps the crate window to that exact loadout.

Grid geometry follows Blizzard's relationships rather than its literal
numbers: Blizzard uses 32px buttons on a 63px pitch, so the gap between cells
equals the button size, and that gap is exactly what the connector art is
drawn to fill (each branch quad is button-sized, each arrow fills its gap).
We show all three trees at once instead of one scrolling tree, so the pitch
is tighter — but never so tight that the connectors stop reading. The UI
harness asserts the grid fits its pane by reading back the real `SetPoint`
offsets, so a future tightening cannot silently overflow.

## Rules of the game (the engine, pure Lua, harness-tested)

- 61 points at level 70 (level 9 + N). Footer shows points spent per tree,
  points remaining, and the level the current build requires.
- A talent at row R unlocks at (R−1)×5 points spent in ITS tree; prerequisites
  must be at max rank. Adding respects both plus the 61 cap.
- Removing a point must leave a legal build: no higher talent loses its tier
  support, no dependent loses its prerequisite. Illegal removals do nothing
  except explain themselves on the tooltip/error line.
- Wowhead-compatible export/import: the per-tree digit string
  (`30520...-0550...-...`, row-major, trailing zeros trimmed) plus tolerant
  URL paste. Copyable out of and into an EditBox popup.
- "Load My Talents" imports the character's live talents (own class; both
  GetTalentInfo shapes handled defensively, matched by talent name).
- **Undo**, one slot per class, covering every operation that replaces the
  whole allocation — clears, tree clears, preset and saved-build loads,
  imports, live import — and restoring the sidebar selection with it. Single
  point clicks are not stacked: a click already undoes itself. A failed
  import must leave both the build and the undo slot untouched.
- **Talent search** (toolbar box): matching talents light up cyan across all
  three trees at once while everything else recedes, with a live match count.
  Wowhead has no equivalent.
- **Compare**: hold any other build — a preset, one of your saves, or your
  live talents — up against what's on screen. Every talent badges the
  difference (`+2` green where you have more, `-1` red where you have fewer)
  in the corner opposite the rank badge, and the footer reports the distance
  ("Comparing Protection — 14 points differ" / "Identical to Arms"). This is
  the question a web calculator cannot ask, because it does not know your
  character. Search takes visual precedence when both are active; compare
  state is per class and never leaks across a class switch.

## Data

`CommanderTalentsData_<Class>.lua` × 9, agent-generated to one schema and
never hand-edited casually (regeneration notes in the file header):

```lua
CommanderTalentsData.Classes.WARRIOR = {
  trees = {
    { name = "Arms", bg = "WarriorArms",
      talents = {
        { name = "Improved Heroic Strike", icon = "ability_rogue_ambush",
          row = 1, col = 1, max = 3,
          ranks = { "Reduces the cost of your Heroic Strike by 1 rage point.", ... } },
        -- req = "Taste for Blood" names a same-tree prerequisite
      } },
    ...×3
  },
  builds = {
    { key = "ARMS", name = "Arms", role = "MELEE",
      points = { [1] = { ["Mortal Strike"] = 1, ... }, [2] = {...}, [3] = {...} },
      stats = { "Hit to 9% (142 rating)", "Expertise", "Strength", ... },
      notes = "..." },
    ...one per Quartermaster spec key
  },
}
```

Builds reference talents BY NAME (indices shift when data is corrected; names
are the stable join). The harness cross-verifies every name resolves, every
build is legal under the engine, sums to 61, and covers every Quartermaster
spec key for its class; tree checks enforce unique cells, rows 1–9 with
exactly one 41-pointer at row 9, cols 1–4, ranks arrays exactly `max` long,
and prerequisites that sit above (straight or bent — TBC ships exactly one
bent arrow, Serrated Blades → Hemorrhage) or straight beside their dependent.

## Files

- `Commander_Talents.toc` — Interface 20506, Category Commander, RequiredDeps
  Commander_Events, SavedVariables CommanderTalentsDB + CommanderTalentsCustom
- `CommanderTalentsData.lua` — namespace + shared constants (class order,
  role tags, spec-key → Quartermaster mapping is 1:1 by construction)
- `CommanderTalentsData_<Class>.lua` × 9
- `CommanderTalentsEngine.lua` — pure rules/state/serialization, no frames
- `CommanderTalentsDB.lua` — defaults, settings panel, slash wiring
- `CommanderTalents.lua` — the window
- `Harness/talents_harness.lua` — luajit, data + engine + builds checks

Suite bookkeeping: Operations pillar (after Quartermaster), `## IconTexture`
Interface\Icons\INV_Misc_Book_11, settings ceiling ~8 (master, style, scale,
position reset, open button; view state is widget-less session memory).

## Out of scope (backlog)

Per-talent spell links, PvP variants beyond the one
canonical build per spec, glyph-era niceties, in-window respec cost math,
multi-level undo, a scrollable build sidebar (the list reserves the save row
and announces overflow instead).
