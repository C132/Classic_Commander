# Commander_Spellbook harnesses

Run from the AddOns folder. Every one must exit 0 before a change ships.

```bash
/opt/homebrew/bin/luajit Commander_Spellbook/Harness/spellbook_harness.lua    # 101 checks
/opt/homebrew/bin/luajit Commander_Spellbook/Harness/data_smoke.lua           # 124 checks
/opt/homebrew/bin/luajit Commander_Spellbook/Harness/globals_lint.lua         # 6 files
/opt/homebrew/bin/luajit Commander_RankCheck/Harness/rankcheck_harness.lua    # 50 checks
```

## spellbook_harness.lua

Loads the REAL shared framework (CommanderSettingsUI, CommanderGoButton, CommanderEvents), the real
Commander Rank Check and every Commander Spellbook file over `spellbook_mock.lua`, on a fixtured
level 40 human priest whose class data is a hand-built slice of the real format (so these checks do
not move when the generator does). Sections:

- **A** login: the settings page, the override bindings on the spellbook and pet book keys, `/csb`,
  Rank Check's button in Blizzard's book standing down.
- **B** the model: one family per spell carrying every rank of its chain; lower ranks the book does
  not list known through IsPlayerSpell; ranks 3 and 4 both trainable now (one visit); race masks;
  the General tab split into General / Professions / Racial; Passives; role order; the stock book's
  tabs as the other grouping; search (unlearned spells, folded groups opened, another race's spell
  never offered, group names matched); a spell the data does not chain joining the chain of its name.
- **C** Training: Train Now (chained ranks, the total), Weapon Skills, Coming Up, Needs a Talent,
  another race's ranks never listed, Ignore, the folded far end.
- **D** the window: rows painted, selection, cast buttons placed over the icons on screen, parented to
  UIParent, none over a row scrolled out of view, the exact rank's id, the up-stroke attribute,
  nothing on right-click or on a passive, the ladder's chips casting their own rank, drag picking up
  the highest rank, a scroll re-placing the buttons where the icons now are.
- **E** combat: the buttons put away at PLAYER_REGEN_DISABLED; search, scroll, repaint, close and
  reopen in combat touch NOTHING protected (the mock refuses and records Show / Hide / SetPoint /
  SetSize / SetScale / SetAttribute on a protected frame in combat, and a secure template protects
  its parent chain and its anchor targets — the field's rules); drag still works; the buttons come
  back after.
- **F** the takeover: the stock book handed over out of combat, left alone in combat, the keys given
  back and taken again with the setting, a rebind followed.
- **G** Rank Check in the book: the view's foldouts, Update on a bar slot, Keep, Update All on a
  macro, the footer's PASS, the `+N` and `!` badges.
- **H** the Training view in the window: the toolbar count, Ignore, Go to Trainer, a weapon skill's
  Go to every weapon master of your faction.
- **I** the pet: the pet book key, autocast on right-click, drag from the pet book slot, no cast
  button on a pet command.

The 2026-10-26 review added: the Cast button's own secure button (D11), shift-click linking instead
of casting (D12), the selection holding through a fold (D13) and an Ignore (H4), the micro button
toggling the window shut (F1), Up to Date folded (G2), a row's Ctrl+Right-click going straight to
Orders (H6). The fixture defines only `C_SpellBook.IsSpellKnown / IsSpellInSpellBook`, not the
deprecated `IsPlayerSpell / IsSpellKnown` globals (DECISIONS D11).

## spellbook_mock.lua

The suite's permissive widget mock with GEOMETRY (every SetPoint resolved to an absolute rect the way
the client does it, Commander_ArenaFrames' resolver, a ScrollFrame offsetting its child) and
PROTECTION (above). `GetLeft/GetTop/GetWidth/GetHeight` answer from the resolver, so the cast
buttons' placement and clipping are tested for real. `HookScript` chains; `Flush` lets time pass
until nothing is waiting.

## Pictures: spellbook_render.lua + render_svg.py

```bash
RENDER=/tmp/book.json RENDER_TRAIN=/tmp/train.json \
  /opt/homebrew/bin/luajit Commander_Spellbook/Harness/spellbook_harness.lua
python3 Commander_Spellbook/Harness/render_svg.py /tmp/book.json /tmp/book.svg
qlmanage -t -s 1700 -o /tmp /tmp/book.svg
```

The painted window drawn from the layout code's own rectangles (not the game's art): rows, the rank
ladder, the briefing, the toolbar and actions, text clipped to its scroll viewport, the embedded
tooltip as a placeholder box, and every placed cast button as a dashed cyan outline over what it
casts for. The 1.0.0 pictures (2026-10-26) showed the Spells and Training views clean, with every
cast outline sitting exactly on its icon.

## data_smoke.lua

The generated `CommanderSpellbookData.lua`: its shape (roles, sources, no rank in two chains, every
trainer row with a level and a price, few trainer rows outside a chain — those are armour
proficiencies and rogue poisons, which Training lists as families of one), the facts the book leans
on (Lesser Heal, Flash Heal's nine ranks, Mind Flay a talent with trained ranks, Polymorph Crowd
Control, Teleport: Stormwind for the Alliance, Seal of Righteousness, the hunter's aspects, the
warrior's stances, Bear Form and Summon Voidwalker from quests), then the real model and Training
code once per class: level 1 has something to train; level 40 knowing everything due has nothing
now and something coming up; level 70 knowing everything has nothing left.

## Data generator

```bash
python3 Commander_Spellbook/Harness/make_spellbook_data.py Commander_Quartermaster/Harness/.cache
```

Writes `../CommanderSpellbookData.lua` (the data is generated, never typed) and prints a report.
Python 3, stdlib only (csv, sqlite3, gzip). The same input gives a byte-identical file.

**Inputs**, all in the git-ignored Quartermaster cache:

- The client's DB2 tables for build **2.5.6.68941** as CSV from wago.tools
  (`https://wago.tools/db2/<Table>/csv?build=2.5.6.68941`, product `wow_anniversary`):
  SkillLine, SkillLineAbility, SkillRaceClassInfo, Spell, SpellName, SpellMisc, SpellDuration,
  SpellLevels, SpellEffect, SpellCategories, SpellAuraOptions, Talent, ChrClasses, ChrRaces,
  CharBaseInfo, FactionTemplate, UiMap, UiMapAssignment, ItemSparse, ItemEffect. The cache already
  held the Quartermaster set (fetched Aug 2026); SpellMisc, SpellDuration, SpellAuraOptions, Talent,
  SkillRaceClassInfo, ChrClasses, ChrRaces, CharBaseInfo and FactionTemplate were added on
  2026-10-26 for the same build. The script lists any missing table and exits.
- The CMaNGOS TBC world DB as `tbcdb.sqlite` (trainers, spawns, quests, items), plus
  `tbcdb.sql.gz` read once for the `conditions` table the SQLite stage does not carry (parsed with
  `Commander_Formulary/Harness/cmangos.py`, imported read-only).
- Read only, for the cross-check: `WhatsTraining/Classes/TBC/*.lua` and
  `WhatsTraining/Classes/WeaponSkills.lua` (third party, MIT). Nothing of theirs is copied into the
  data; when the folder is absent the cross-check is skipped.

**What it decides, and where to look when it is wrong**

- *Chains*: every SkillLineAbility row on a class skill line (category 7, class from
  SkillRaceClassInfo; pet lines have no SkillRaceClassInfo row and are skipped) that the spellbook
  shows (`SpellMisc.Attributes_0` lacks 0x80, which hides talent passives, proficiencies, riding)
  and that something teaches: a spawned class trainer, a talent, a live quest's reward, a book
  (ItemEffect LEARN_SPELL_ID), or AcquireMethod 1/2 (starting spells). Ranks are grouped by name and
  ordered by `NameSubtext_lang` "Rank N"; SupercedesSpell (sparse in this build) and SpellLevels
  are checked against that order. On profession-like class lines (SkillLine.Flags 0x80: Poisons,
  Lockpicking, Beast Training) crafts and the pet's Beast Training rows are left out.
- *src*: T if a trainer teaches rank 1, else L (talent), Q (quest), O (a starting spell, a book,
  or nothing found).
- *role*: `role_of` reads the **highest rank's** effects (and the spells it triggers outright), in
  the order its docstring gives. `MANUAL_ROLE` (keyed by the rank-1 spell id, a reason per line)
  covers what effects cannot say: totems, seals, traps, dummy-effect spells (Execute, Holy Shock,
  Prayer of Mending), offensive cooldowns spent on the next cast, threat drops. TRAVEL (added by the
  lead, 2026-10-26) is the teleports and portals by name (Shadowstep teleports too, by effect, and is
  no journey) and the summoned mounts by their mount aura.
- *train*: the union over spawned class trainers (template and direct rows, learn spells resolved).
  Level = the lowest trainer level (a 0 is ignored when another trainer gives one), cost = the
  lowest cost. The race mask is the races the trainers reach (their side by FactionTemplate, their
  row conditions: player race / team, AND / OR) within SkillLineAbility's race mask, omitted when
  every race of the class qualifies (CharBaseInfo). A trainer spell SkillLineAbility gives only to
  other classes is dropped (the shaman trainers' priest Cure Disease, 528). `MANUAL_TRAIN` holds the
  rows CMaNGOS lacks or has wrong, each with its evidence.
- *general*: visible, non-recipe spells on racial, profession / secondary and weapon / generic
  skill lines.
- *weapons*: weapon proficiency spells (category-6 lines, effect 60) taught by spawned TrainerType 2
  NPCs; classMask from SkillRaceClassInfo; masters placed with Commander_Formulary's zone rule
  (`zone_of`, copied), `MANUAL_PLACE_IN` for a master on a zone's rim.

**The report** (`SPELLBOOK_VERBOSE=1` adds every dropped spell and every chain with its role and
reason): per-class counts, rank problems, trainer-vs-SpellLevels level differences, race masks
narrowed by SkillLineAbility, the chains left as UTILITY because no rule matched, and the
What's Training? cross-check (spells only in ours / only in theirs, level, cost and race
differences per class; weapon masters, what they teach and where they stand).

As of 2026-10-26 the cross-check agrees spell-for-spell on every class but two: Hunter (theirs
also lists the 56 pet-trainer Beast Training ranks, which are not the hunter's book) and Paladin
(ours adds Summon Warhorse 13819 and the Seal of Righteousness rank 1 that Judgement's learn spell
teaches). Searing Totem 7's level was fixed in MANUAL_TRAIN from its tooltip; one level difference
(warrior Parry: 1 here, 6 there) and 48 cost differences remain. The largest are TBC-era ranks of
talent spells (Mind Flay 7,
Holy Nova 7, Vampiric Touch 3, Dragon's Breath 3/4, Hemorrhage 4, Trueshot Aura 4) where CMaNGOS
charges full price and What's Training? a tenth or a twentieth. They are left as CMaNGOS has them
for want of a citable source.

WhatsTraining was uninstalled on 2026-10-26 once this module replaced it, so the cross-check now
skips itself. To run it again, put a copy of WhatsTraining back in the AddOns folder for the run.
