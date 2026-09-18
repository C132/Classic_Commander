# Commander_Formulary — decisions

Numbered so code comments and future sessions can cite them.

## D1 — One window for the whole profession, and it replaces the stock one

The stock Enchanting window is a one-column list of what you know with a Create button. The
Formulary is the same list with the other two thirds of the profession beside it: every recipe that
exists, under the slot it enchants or the thing it makes, the unknown ones with exactly where they
come from, and a briefing pane. It replaces the stock window (an option) rather than sitting beside
it, the way the Quest Log replaces the stock log — but the stock window is still *read* every time
it opens, because it is the one authority on what this character knows (ASSUMPTIONS A2), and only
then put away.

## D2 — The data is generated, never typed

`Harness/make_enchanting.py` writes `CommanderFormularyData_Enchanting.lua` from this build's DB2
tables (SkillLineAbility, SpellName, SpellReagents, SpellEffect, SpellEquippedItems, ItemEffect,
ItemSparse, FactionTemplate, UiMap, AreaTable, Map) and the CMaNGOS TBC world DB (trainers,
vendors and vendor templates, creature / object / container loot with reference lists and group
shares resolved, quest rewards, spawn points). 223 recipes come out of SkillLineAbility for skill
333; 221 are obtainable; the two that were never put in the game are excluded by name. Every
formula in the file has at least one source or a note. The generator prints what it could not
source and a cross-check against Recipe Master's curated list, which is the only practical check
on a systematic world-DB hole.

Three encodings that cost time, kept here so nobody pays twice: a formula's taught spell is the
`ItemEffect` row with `TriggerType 6` (slot 0 is the generic "Learning" spell 483); weapon and
shield enchants name their targets by item *subclass* mask, not inventory type; and most TBC
vendor stock is on `npc_vendor_template`, not `npc_vendor`. Bosses are kept even when never
spawned (Ouro and Nightbane are summoned); everything else unspawned is a GM stock room.

## D3 — Recipe Master's known-recipe bug, and why this module matches by name

Recipe Master records what the craft window lists by the id in `GetCraftItemLink`, which for a
rod, wand or oil is the *item* made, not the spell — so every item-making recipe reads as never
learned. This module matches the craft list by localised spell name into the generated recipe
table, and asks `IsSpellKnown` first (Commander_Tradecraft D6).

## D4 — Categories are the slot, and rows carry the source word

Weapon, Two-Hand Weapon, Ranged, Bracer, Chest, Cloak, Boots, Gloves, Shield, Ring, then Rods,
Wands, Oils, Shards & Spheres. Known rows are coloured as the craft list colours them; unknown
rows are dim with one word for the source — Trainer, Vendor, Reputation, Drop, World drop, Quest —
and the skill they are learned at. A green dot marks a recipe that could be learned this minute:
the trainer at your skill, the formula in your bags or bank, a vendor you can actually use (right
faction, enough standing). Category headers carry known / total, a completion hairline, and a
green +N for the learnable ones.

## D5 — Reputation standings are off by one between the data and the client

ItemSparse counts standings from Hated = 0 (Honored 5, Revered 6); `GetFactionInfoByID` counts
from Hated = 1 (Honored 6, Revered 7). Every comparison adds one to the data's figure. The first
build did not, and would have called a Friendly character Honored.

## D6 — The Craft button is a secure macro button

Crafting is protected on this client (Commander_Tradecraft D7 has the whole story), so the button
runs `/cast <recipe>`. By default that is all: this window is for enchanting whatever you choose,
so the glowing cursor is left for you to aim. "On my gear" adds `/use <slot>` and the
`/click StaticPopup1Button1` answer, for anyone using the Formulary to level. The button sits in a
plain holder frame that the layout shows and hides; in combat nothing protected is touched.

## D7 — The recipe's own tooltip is embedded, not re-typed

The briefing shows a `GameTooltipTemplate` frame parented into the page with
`SetHyperlink("enchant:<spell>")`: the client renders the effect text, the reagents and the
requirements exactly as the craft window would, in every locale, and nothing here has to carry
spell descriptions. The reagent list underneath is this module's, because it carries what you
hold. The tooltip is moved to the window's own strata so it is part of the page and clips with it.

## D8 — Richness that earns its place

Added on review, each for a reason a completionist would give: a **Craftable** filter (known and
the reagents on hand — the "what can I make right now" question); the header's percentage and, on
the Learnable filter, how many formulas a usable vendor sells at your skill and what they cost
together (one shopping trip); shift-click or right-click a row to link the recipe in chat; the
**trainers** at the foot of the navigator with what each would teach you now; a line on recipes
that sit on the Commander_Tradecraft leveling route; and a **verdict on every formula's tooltip** —
already known / can learn now / needs N skill — which is the question you are actually asking at a
vendor or the auction house.
