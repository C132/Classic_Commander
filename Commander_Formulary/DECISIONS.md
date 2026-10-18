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
the gold for the lot; right-click to walk it (D14). One Moonglade trip, one Silithus trip, one
Shattrath sweep — the completionist's errand list.

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

## D13 — A second profession is a second data file, not a second window

First Aid (2026-09-19) is `CommanderFormularyData_FirstAid.lua`, written by the same generator
(`make_formulary.py`, which took over from `make_enchanting.py` and is parameterised by a
`PROFESSIONS` entry: skill line, rank ladder, category rule, the handful of manual rows). Every
Enchanting figure came out byte-identical, except where the zone rule improved — see below. The
window is unchanged in shape: one profession is on screen at a time, the rank readout in the toolbar
is the switch (click to cycle, hover for every profession's rank and how its next rank is obtained),
`/cfm firstaid` and `/cfm enchanting` do the same, and whichever stock window opens brings its
profession on screen. The character remembers which profession they were looking at and the
selected recipe per profession.

Three things First Aid does differently, all carried in the data rather than the code. It is a
**trade-skill** profession (`frame = "TRADESKILL"`): the window is `TradeSkillFrame`, the events are
`TRADE_SKILL_SHOW / CLOSE`, the list is `GetNumTradeSkills / GetTradeSkillInfo` and the skill line
is `GetTradeSkillLine`; the UI keeps one channel table per frame kind with the same four operations.
Its **ranks are not all trainer-taught**: Expert is a book from two vendors, Artisan is the Triage
quest (the item "Artisan First Aid - Heal Thyself" exists in the item table and is sold by nobody),
Master is a book from Burko or Aresella that needs 300 — so a rank row carries `book` or `quests`,
the header note says "from a book" or "from a quest" instead of "trainable", and `M.RankRoute`
turns the row into lines with the vendor or the doctor for the character's faction. And its
categories are the cloth (Bandages, Outland Bandages, Anti-Venom), because there is no slot.

The **zone rule** had to change. Smallest-containing-box put Deneb Walker in Hillsbrad at 90.8,
91.2 (he is at Stromgarde, Arathi 27.0, 58.8) and Balai Lok'Wein in Mulgore at 96.1, 82.4
(Brackenwall, Dustwallow 36.5, 30.4): zone boxes overlap at their edges and the smaller neighbour
was winning. The rule is now: a box that wholly contains another candidate loses to it (Lower City
is Shattrath, not Terokkar); among boxes the point is at least ten percent from every edge of, the
smallest; failing that, the deepest. It also moved eleven Enchanting placements to where the
published locations are (Dalria to Astranaar, Vance Undergloom to Brill, Zixil to Hillsbrad). Two
creatures that genuinely live on a zone's rim are pinned by `PLACE_IN` (Mire Lord, Meilosh).

Disenchant advice stays Enchanting's and appears only for a character who has Enchanting, whatever
profession the window is showing. A formula or manual tooltip is judged against the profession it
belongs to — a Netherweave manual says "at 330 (you are 200)" against First Aid's 200 even while
Enchanting at 146 is on screen.

## D14 — Go buttons and trips go to Commander Orders

1.1.0, 2026-10-04. TomTom left the suite and Commander Orders 3.0 is its navigation; `SetWaypoint`
never tried Orders, so the day TomTom went every Go button would have dropped to printing. A Go press
(a vendor, a trainer, a dropper) calls `CommanderOrders.Add` with source "Formulary" and key
"place:<name>@<map>": a place owns ONE waypoint, a second press moves nothing and stacks nothing, and
the waypoint takes the arrow because the player asked for it. Session only, Orders' default for a
consumer. Orders absent, turned off or refusing: the place is printed with its `/way` line, and the
Go tooltip says which it will be when hovered.

The Trips view walks, rather than pointing at a zone's first vendor only. A right-click on a zone
routes every vendor stop listed under it as one Commander Orders route, nearest first (a zone with
one vendor is simply a waypoint to it), owned as (Formulary, "trip:<profession>:<zone>").
**Route All Trips** (the action bar, on the Trips view only; `/cfm trips`) routes every zone at once
as (Formulary, "trips:<profession>"), and buys each RECIPE once: Trips lists a formula under every
zone that sells it, several TBC recipes are taught by two or three formula items (the reprints), and
a route through everything must not send you to buy a recipe twice. The cover is greedy in Trips'
own order, most formulas first. A vendor with no place on the map (Lokhtos inside Blackrock Depths,
the wizard in Old Hillsbrad) gets no stop: no arrow can go there. Each stop is titled with the vendor
and the first recipe bought there ("Lorelae Wintersong: Enchant Cloak - Superior Defense (+1)").
Asking again replaces the route. Without Orders, the stops' `/way` lines are printed. UI harness B3
and C8.

## D15 — Every Go is the suite's one Go button; instance creatures go to their door

1.2.0, 2026-10-05 (Commander Orders 3.1). Orders 3.1 made "Go to" one widget and one API for every
Commander module, and its DECISIONS carry the one words-and-gestures rule every consumer cites (D31):
"Go" on a row button, "Go to <Thing>" on a standalone one; click Go, Shift-click share the place in
chat, Ctrl-click copy its `/way` line; a list row with no room for a button takes Ctrl+Right-click
with `Commander.UI.GoRowHint` in its tooltip. So:

- Every Go in the briefing is a `Commander.UI.GoButton` (pooled with the briefing's other widgets,
  its options filled afresh at every paint). D14's own `SetWaypoint` and lookup are gone; the
  success line is Orders' own "Waypoint set: <title> (Zone x, y)", behind Orders' Announce
  setting. Sources, keys ("place:<name>@<map>"), titles and "takes the arrow" are D14's. A
  trainer's Go names the TRAINER icon (the navigator's trainer foot used to name none). A Trips
  route of one stop goes through `CommanderOrders.GoTo` too; the routes are D14's.
- **Creatures inside an instance go to its door.** The generator now emits `instance = <id>`, the
  creature's Map.db2 ID (the client's instanceMapID), where it wrote `instance = true`
  (`make_formulary.py`, `add_npc`); a boss with no spawn row ("(summoned)") keeps `true`. The
  data was regenerated (Enchanting 113 rows, First Aid 3; nothing else in either file moved; a
  fresh run on the Quartermaster cache's DB2 CSVs and CMaNGOS dump reproduced the old files byte
  for byte before the change). Their Go asks Orders' locator for `{ entrance = { instance = id } }`
  (Orders' shipped door table, then the client's), titled "<creature> (<dungeon> entrance)", key
  "door:<id>": every creature of one dungeon moves the same waypoint. All 30 instance ids the
  data names (Shadowfang Keep 33 to Zul'Aman 568) have a door in Orders' table. The critic's first
  idea, a dungeon NAME through Orders' zone resolver, could not work: the zone index holds zones
  and continents only, and the names are Map.db2's ("Magister's Terrace", sic).
- **"Any trainer will teach it now"** has a Go to the nearest trainer of the profession, through
  the locator (`{ townsfolk = "<Profession> Trainer" }`, "Nearest <profession> trainer").
- **The next rank.** The rank readout's tooltip already said how the next rank comes (a trainer, a
  book's vendor, Triage's giver); Ctrl+Right-click on the readout now goes there (key
  "rank:<profession>"): the first placed vendor or giver of the rank route, else Outland's trainers
  for a rank only they teach (one waypoint, the arrow on the nearest), else the nearest trainer of
  any kind. Plain right-click stays nothing and left-click still switches the profession; the
  tooltip ends with the hint ("Ctrl+Right-click: Go to Doctor Gregory Victor").

The locator Gos need Questie for trainers; the doors do not (Orders ships its door table). Without
Orders a placed Go prints its `/way` line and a locator Go says it needs Commander Orders. UI
harness B3b, B4b, B4c and G3b.

The row Go is 18 high and anchored 1 above its row, and a single-line row is only 12 + 3 high, so
stacked Gos (a formula's vendors and droppers, Outland's trainers) overlapped by 3 px: the lower
button's bevel covered the upper's edge, and those 3 px clicked the next row's place. Since the
2026-10-05 review `GoRow` keeps the next row 18 below the row's top (the Quest Log's LINE_GO_H rule):
the buttons sit edge to edge. A wrapped row is taller than that already and does not move (B7).

**A greyed Go promises no press** (the review's round 2, 2026-10-05). Since Orders turned the
GoButton's motion scripts on (its D31), a greyed Go shows its tooltip, and the briefing's line read
"Prints the coordinates and a /way line to chat (Commander Orders is turned off)" above the red "Commander
Orders is turned off (/corder)"; a door or trainer Go without Orders said it would print above "Needs
Commander Orders". 2.5.6 delivers no OnClick to a disabled Button, so nothing printed. A briefing Go's
line is now `GoWords(button)`: nil while Orders is turned off, nil for a locator Go (door, trainer)
without Orders, and only an enabled Go is worded (the arrow, or a placed Go's `/way` line without
Orders). D14's "turned off: the place is printed" now holds for the Trips route and Route All Trips
only (plain buttons, still enabled, whose words stay `WaypointWords`). UI harness B3c and B4d.

