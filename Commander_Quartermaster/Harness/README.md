# Commander_Quartermaster harness

## Offline generators

The enhancement database is generated, never hand-edited. Three scripts, in
order; everything they download lands in the gitignored `.cache/`:

```
python3 tbcdb_to_sqlite.py --fetch      # stage the CMaNGOS TBC world DB
python3 build_enhancements.py           # write CommanderQuartermasterEnhanceData.lua
python3 crosscheck_enhancements.py      # verify identity against Wowhead
python3 crosscheck_atlasloot.py         # verify sourcing against AtlasLoot
```

## In-addon check

```bash
/opt/homebrew/bin/luajit Harness/quartermaster_harness.lua   # 332 checks
/opt/homebrew/bin/luajit Harness/globals_lint.lua            # 6 files, 0 undeclared globals
```

`globals_lint.lua` exists because this module is 3,400 lines of mutually
recursive local functions, and in Lua a local declared AFTER a function body is
not in that body's scope — the reference silently compiles to a global access
and reads nil at runtime. It was added the day `SidebarButton` was written
above `CreateSidebarButton` and would have called a nil global on the only path
that matters (a list outgrowing the button pool), which nothing exercises until
it happens to a player. luajit's bytecode listing names every global a file
really touches, so the check is exact rather than heuristic. Add a genuinely new
WoW API to `ALLOWED`; do not add a name just to make it quiet.

`tbcdb_to_sqlite.py` stages the server-side facts the client does not carry —
npc_vendor with extended costs, creature/object/reference loot, quests,
trainers, prospecting, disenchanting. `build_enhancements.py` takes the
universe from the client's own DB2 tables for build 2.5.6 (every spell with an
ENCHANT_ITEM or ENCHANT_ITEM_TEMPORARY effect, plus every gem item, fetched
from wago.tools) and marries the two. `crosscheck_enhancements.py` re-reads
the generated Lua with luajit and compares every entry's name, quality,
required level, profession gate and reputation standing against Wowhead's
tooltip endpoint at dataEnv=5 — the live Anniversary dataset. It currently
reports zero disagreements across all 629 entries, and it reports rather than
rewrites: a disagreement is as likely to be Wowhead rendering a later patch as
it is to be us.

`crosscheck_atlasloot.py` covers what Wowhead's tooltip endpoint cannot:
SOURCING. It reads the AtlasLoot Classic TBC tables installed alongside this
addon — an independent, hand-curated dataset — and checks every enhancement
and every recipe that AtlasLoot also knows: that we source it at all, and that
our reputation gate and standing agree with theirs. 215 items overlap and
nothing disagrees. Its `unseen` column (things we source and AtlasLoot does
not list) is informational — AtlasLoot does not attempt trainers, world drops
or vanilla-era content in its TBC files.

That check found the one systematic hole worth finding: CMaNGOS ships the
Consortium quartermasters with an empty shelf, so a reputation reward sold by
nobody had no source at all. The generator now falls back to the item's OWN
reputation gate, which the client enforces regardless of what the world DB
knows about shelves — "Reputation reward: The Consortium - Exalted" is true
and useful even when no vendor row exists.

Both generators print their own coverage. `build_enhancements.py` names every
enchantment display string containing a stat phrase its parser does not know
(currently none) and every entry with no obtainable source (currently nine,
all flagged `unobtainable` — items this client carries but never hands out).

## Harness

Offline smoke checks that load the REAL shared framework
(`Commander_Events/CommanderSettingsUI.lua` + `CommanderEvents.lua`), the three
Quartermaster files, and Commander_Inventory (for the crate-button integration)
under a permissive WoW mock. Run both modes before shipping any change:

```
/opt/homebrew/bin/luajit quartermaster_harness.lua        # full run (~120 checks)
/opt/homebrew/bin/luajit quartermaster_harness.lua noqm   # Inventory without Quartermaster
```

The full run also loads `CommanderQuartermasterFringe.lua` and enforces its house
rule: fringe-spec picks (Shockadin, Smite, Subtlety, Demo Tank, Dreamstate) may only
reference item IDs the generated database already verified. The Lvl column is
covered in both faces — client item level in item lists, character level in the
Roster — including the sort-order correction when item info arrives late.

Sections S and R are the tripwires for a file nobody watches being written:
S asserts the SHAPE of the generated data (ids, slots, kinds, stat vectors,
every shelf ranking for every role, every entry's sources rendering, every gem
falling on exactly one colour shelf) and R asserts the class/subclass filter
that separates a wand from a gun. S has already earned itself twice — it
caught a renderer that would have thrown on 142 entries the first time a
trainer-taught craft was drawn, and it found the two three-colour gems
(Void Sphere, Prismatic Sphere) that fit every socket and had no shelf.

Enhancement coverage (sections N, O, P): the index by enchant effect id and by
carrier item, the link parser, socket counting from GetItemStats, the
profession gate on ring enchants, BestHeld against the ledger, the Gear view's
audit page and per-slot shelf, search reaching into sources (typing "moroes"
finds Mongoose), owned-only filtering, role ranking and its honesty rules, and
both tooltip halves — the enhancement's own slot/source lines and the verdict
on a piece of gear. These run against the real generated database, not a
fixture, so a regeneration that broke the shape would fail here.

Coverage: login + ledger filing, the v1 close-race flushes (bank withdrawal
inside the coalesce window, the mail inbox-seen gate), tooltip count scoping
(realm scope, Track* gates, transit layer, alt breakdown), outbound-mail
transit (case-insensitive recipient match, merge, MAIL_FAILED discard,
unknown recipients, supersede-by-own-scan, 31-day login prune), deep token
search, era/source filters, column sorting, the watchlist (targets, badges,
markers, popup plumbing, reset survival), favorites (section U: the star
button's own click, both key shapes — carrier item and enchant+spell for the
enchanter-cast entries — the shelf on both pages, the favorites-only filter,
the tooltip line with counts turned off, the shopping-list section, and reset
survival), loadout readiness grades + both
GetTalentTabInfo shapes + played-class verdict isolation, the shopping list,
the raid supply check (dedupe window, sound, master toggle), the roster view
(hide/forget, gold, column relabel), slash dispatch, and the Inventory crate
button in both installed and absent worlds.

Mock lessons baked in (do not regress): auto-generated widget methods are
prefix-matched only so template-child property probes (`browser.TitleText`)
read nil unless the template mock provides them; `HookScript` CHAINS handlers
(the search box hooks a placeholder onto its own OnTextChanged); and
`C_Timer.After` feeds an executable queue because every scan and browser
refresh coalesces through it.
