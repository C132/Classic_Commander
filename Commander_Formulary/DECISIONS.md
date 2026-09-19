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
spawned (Ouro and Nightbane are summoned); everything else unspawned is a GM stock room. Two rows
are corrected by hand in the generator's `MANUAL_*` tables: Ring - Stats (a TBC Classic addition the
world DB predates) and Ring - Striking, which the world DB puts on a Violet Eye vendor in Karazhan
while the item itself is gated on Consortium standing.

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

## D9 — Gold, where it is a fact and never where it is a guess

With Auctionator's scan data the briefing gains a Gold section: what a cast costs in reagents
(vendor-sold reagents at the vendor — `vendorBuy` in the data, which only lists items three or more
spawned vendors carry unlimited, so one GM stock room cannot make Strange Dust "vendor-sold"), what
an item-making recipe's product sells for (times what a cast makes — Void Shatter makes two), the
profit or loss per cast, and for an unknown recipe the cost to learn and try it (the cheapest usable
vendor's formula price, else the auction price for a BoE formula, plus a first cast). A **Profit**
filter lists the known recipes that make money today. Anything without a price stays unpriced and
says so; nothing is estimated.

## D10 — Disenchant advice from the game's own tables

Every item's disenchant loot id in the world DB falls into an item-level bracket per quality and
class, so the generator derives the rule (`disenchant["quality:class"]`, brackets by majority with
gaps filled) and the tooltip hook applies it to any green, blue or purple weapon or armour: what it
breaks into with chances (weapons favour essences, armour dust — the tables say so), the expected
value at today's prices, against the vendor price and the auction price, and the verdict. This is
where an enchanter's gold comes from and the game gives no hint of it. A **soulbound** copy has no
auction option — the first in-game screenshot (2026-09-18) showed "sell it on the auction house"
under a Soulbound shield; the tooltip's own `ITEM_SOULBOUND` line is the one place the bound state of
*this* copy is known, so it is read before the verdict. The verdict line uses a dash, not an arrow:
the client's fonts draw arrow glyphs as boxes (the same screenshot).

## D11 — Trips

The **Trips** filter regroups the unknown formulas a vendor of your faction sells by zone — a
reputation you have not earned yet is listed and marked "needs Honored", because that is a trip you
can plan for; the other faction's vendors are no trip at all — one row per zone with its vendor, how many formulas, how many at your skill and
the gold for the lot; right-click for a waypoint to the vendor. One Moonglade trip, one Silithus
trip, one Shattrath sweep — the completionist's errand list.

## D12 — The navigator's columns, and Refresh Prices

A recipe row is four columns: icon and name, source and skill, cost. Under a slot header the name
drops its "Enchant Ring - " — the header already says it, and with the cost beside it the full
name was being cut off (screenshot, 2026-09-18). A trip row keeps the whole name because it sits
under a zone, not a slot. The cost column is the reagent cost of one cast in coin icons rounded to
the silver; on a trip row or a vendor formula under Learnable it is the formula's price instead,
in the primary ink, because that is the gold that trip needs.

Every price in the window is Auctionator's, so "up to date" means Auctionator has searched the item
lately. **Refresh Prices** appears in the actions row only while the auction house is open with
Auctionator loaded: it hands `MultiSearchExact` the exact names of every item that moves a number
here — 110 reagents, 30 disenchant results, 82 formulas that trade hands, 28 crafted goods — and
Auctionator searches them in its Shopping tab; the window rebuilds on its `SearchEnd` (and on a
Full Scan's `ScanComplete`), reached through its event bus in a pcall. Shift-click, or
`/cfm refresh <recipe>`, searches one recipe's items. Auctionator's Full Scan remains the way to
refresh the whole realm — it is the only thing that prices the random green in your bag for the
disenchant verdict — but it is limited to once every fifteen minutes; this is the touch-up between.
