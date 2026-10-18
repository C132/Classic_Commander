# Commander_Tradecraft — decisions

Numbered so code comments and future sessions can cite them.

## D1 — The route is data, and the engine is pure

`CommanderTradecraftData.lua` is the guide: recipes with their skill colours and reagents, formulas
with their vendors, and the route as segments with paths. `CommanderTradecraftEngine.lua` turns that
plus a `world` table (rank, known recipes, item counts, faction, standing) into a plan, and touches
no frame and no WoW API. The window only paints what the engine hands it.

Two reasons. The first is the usual one — the harness proves the route logic without a mock, 752
checks worth. The second is that this is the shape a second profession needs: another guide table,
the same engine, the same window. Nothing in the engine or the window says "enchanting" except
through `D.PROFESSIONS[guide.profession]`.

## D2 — Every number came from the client's own tables, not from memory or the guide's text

Reagents and colour thresholds are from `SpellReagents` and `SkillLineAbility` for this exact build;
formula ids, prices and rep gates from `ItemSparse`; vendors, trainers and their coordinates from the
CMaNGOS world DB converted through this build's `UiMapAssignment`. The guide's text was the route and
a cross-check, never the source of an id.

This mattered on the first pass: from memory, Lesser Mana Oil was 25130 (that is Brilliant),
Superior Wizard Oil was 28016 (that is Superior Mana Oil), and 16207 was the Arcanite rod's formula
(it is the rod itself, and a reagent of the Fel Iron rod). The file header keeps that list as a
warning to whoever adds the next profession.

## D3 — The skill-up model is the engine's, and the guide's counts are a reference figure

The window says "about N more crafts" from the standard model: certain below yellow, then
`(grey − rank) / (grey − yellow)`, summed as reciprocals. The guide's own `×N` is shown beside it as
"guide says ×N", scaled to what is left.

The model is what lets the guide work for someone starting at 146 rather than 1 — the guide's counts
are for whole segments. The two agree within twenty percent everywhere, and where they disagree the
guide is the generous one with itself (harness B3 names the two places).

**The guide's count is a floor.** For any step the guide gives a count for, the plan is
`max(model + margin, guide count pro rata for what is left)`. Verified against the guide's own
materials list (its .mhtml export, 2026-09-17): the model alone ran under it on four items by a few
percent — Illusion Dust 314 against 322 — and someone shopping from this list should never come up
short of what the published guide says. With the floor the list equals the guide everywhere and
exceeds it where the model is stricter (Arcane Dust 333 against 309; harness B3a, C13). The
bracket split shares a step's planned total by each part's model share, because the yellow tail of
a step costs more per point than its orange start.

**Margin goes on the uncertain part only.** The shopping list plans `certain + ceil(uncertain × (1 +
margin))`. A whole-count margin made a one-rod step plan two rods and warned you about a Runed Copper
Rod you were holding (harness B3b, C1, C9 — all three failed before this was split).

## D4 — Trainer visits are a banner, not a step

The trainer ladder is derived from the rank table rather than placed in the route. A rank becomes
trainable in the middle of a craft segment (Journeyman at 50, inside Minor Health 2–90), so as a step
it would have to split segments the guide does not split. As a banner it can say "available" from
50 and "you are at your cap" from 75 without moving the current step at all.

Master is at **275**, not 300 — the trainer table says so, and the guide's own 300 would have you
stand at the cap for the Arcanite rod for no reason.

## D5 — A formula stops mattering when the last step that uses it is behind you

A buy step is done when the recipe is known or when the skill has passed every craft step on the
chosen route that uses it. The obvious test — the segment's own end — is wrong for the Moonglade trip,
which buys the Arcanite rod's formula in the 285–299 segment for a step in the next one, and for the
Superior Defense formula, which the 301–317 step still needs after 285–299 is over. Harness C7 and
C10 are those two cases.

**And a formula you cannot learn yet never blocks the crafting that gets you there.** The current
step is the first pending step that can be acted on; a buy step whose skill requirement is above
you is left pending, shown in the preview with "needs N", and becomes current at that rank. The
Moonglade trip at 285 buys the Arcanite rod's formula, which needs 290, while Superior Defense is
what you should be crafting (harness C7b).

## D6 — Known recipes: the spellbook first, the craft window as memory

`IsSpellKnown` is asked first. Whether it answers for craft recipes on this client is ASSUMPTIONS A2;
if it does not, the fallback is that every open of the craft window records what it lists into
`CommanderTradecraftChar.knownRecipes`. Either way a formula you learn resolves its step the next time
the window is open, and the step's own text says to right-click the formula while you hold it.

## D7 — The Craft button is a secure macro button, because DoCraft is protected

The first in-game press of the original Craft button raised `ADDON_ACTION_FORBIDDEN` for `DoCraft()`:
on this client crafting is a protected action, like casting. So the button is a `SecureActionButton`
of type `macro`, and its macro is the one enchanters have typed by hand since vanilla:

    /cast Enchant Bracer - Minor Health
    /use 9

`/cast` by the recipe's localised name (no craft window needed), then `/use <slot>` (worn) or
`/use <bag> <slot>` (bags) hands the glowing cursor its target on the same click. The macro is
rewritten on every paint, out of combat only, from the current step and whatever the character is
wearing; in combat the button is replaced by a disabled plain one and nothing protected is touched.
"Cast On My Own Gear" drops the `/use` line. The tooltip shows the macro, so anyone who would rather
bind it can copy it.

The replace-enchant question is the macro's third line, `/click StaticPopup1Button1`. The first
build answered it from the `REPLACE_ENCHANT` event with `ReplaceEnchant()` — the client's docs list
it as an ordinary function, and in game it raised `ADDON_ACTION_FORBIDDEN` all the same (2026-09-17).
The client raises the question synchronously inside the `/use`, so the next macro line lands on it;
and `StaticPopup_OnClick` returns at once when its dialog is not shown, so the line is a no-op on a
fresh piece. The residual risk, and the reason it is an option: whatever dialog happens to be
`StaticPopup1` at that instant is the one accepted.

Both secure buttons (Open, Craft) live inside plain holder frames that the layout shows, hides and
anchors; hiding an ordinary parent takes a protected child with it and is allowed at any time.

**Both click edges are registered.** `SecureActionButton_OnClick` (this client's
`SecureTemplates.lua`) acts on exactly one edge — the one `ActionButtonUseKeyDown` names, *down*
by default — and discards the other. The first build registered `AnyUp` alone, reasoning that a
mouse click always has an up and one edge would avoid a doubled cast; in game the button did
nothing, because the up-click it delivered was the edge the handler throws away. Registering both
is what the suite's other secure buttons do, and it is one `/cast` per click, not two.

**A key binding, and a real macro.** "Craft the current step" under Key Bindings is a `CLICK`
binding (Bindings.xml) on a second secure button, `CommanderTradecraftCraftKey`, parked off-screen
and always shown and carrying the same macro — the guide window's own button is hidden whenever
the window is, and a binding needs a live target (Commander_Armory parks its weapon-swap button the
same way). The macro `Tradecraft`, on the General tab, is created once and `EditMacro`'d whenever the
text changes, with the recipe's icon — the way RXPGuides keeps its `RXPTargeting` macro — for
anyone who would rather drag it to a bar. It is written only after `UPDATE_MACROS` (the list is not
there at `PLAYER_LOGIN`; the first build wrote at login and nothing appeared) and a failure is
printed once rather than swallowed. General rather than character-specific because the
character tab is where nobody looks (the first build put it there and it was reported missing); a
per-character one left over from that build is deleted and remade. An option, on by default; it
costs one of the 120 general slots and says so if they are full. Harness A11, A13, A14, B2–B4, F2 and F2b cover the
edges, the key button, the macro, the popup rule and the combat rule.

## D8 — Progress is per character; settings are per account; Restore Defaults cannot reach progress

Path choices, skipped steps and the recipe memory are in `CommanderTradecraftChar` (per character).
The options page only iterates `CommanderTradecraft_Defaults`, which has none of those keys. The
enchanter alt keeps their Moonglade decision whatever the main presses (harness F4).

## D9 — Two ways are two rows, and there is no skipping

A segment with two paths shows them as two radio rows under the step — the chosen one lit, the
other a click away, the guide's note under each — and only while you are in that segment. The
first build had a permanent "Alternative" button and a "Skip" button; both went on review.
Profession leveling is a fixed linear progression, so skipping a step is not a thing a player does,
and a toggle button is a worse way to present a two-way choice than the two ways themselves.
Deciding a later segment ahead of time is still possible from the Route window (same radio rows)
or `/ctc alt <range> <main|alt>`. The engine keeps its "skipped" state only so an older saved table
still loads.

## D10 — The Route window is a list, not text

Pooled rows in a scroll frame: bracket headers (done / you are here), one row per step with icon,
name, range, count and status colour, the current row on a gold bar, buy rows naming the vendor,
two-way segments as a header plus radio rows above the chosen way's indented steps. The first build
was a colour-coded text dump in an edit box and read like one. The shopping list stays text because
its whole point is being copied out. Buy steps are bracketed by where the trip sits on the route,
not by the formula's skill requirement, so a bracket header appears exactly once (the Lesser
Strength formula needs 140 but is bought at 156, on the Expert trip). Finished two-way segments
list only their steps: the other way is history.

## D11 — The route and the shopping list are grouped by trainer bracket

A bracket is one trainer rank's span (1–75, 75–150, 150–225, 225–300, 300–375) and it is the
natural shopping trip: buy for the bracket, level it, train, buy for the next. The engine tags each
step with the bracket it *starts* in for the route view, and splits its reagents at every boundary
the remaining range crosses for the shopping view — Minor Health 2–90 is listed once under
Apprentice, but its last fifteen crafts' dust is Journeyman's to buy.

What you already hold pays for the earliest bracket that wants it and only the remainder flows on,
so the first trip is the one your bank covers. The whole-route totals close the list for anyone who
shops once, and the Auctionator hand-off defaults to the current bracket ("All to Auctionator" for
the lot). Harness C15 is the split and the allocation.

## D12 — Prices decide what prices decide, and nothing else

Every alternative the guide offers is a price question ("if eight Arcane Dust is a quarter cheaper
than two Greater Planar Essence…"), so with Auctionator's scan data the engine costs each way
through a two-way segment from where you stand — planned casts × reagent prices, and per skill
point — and, with "Let Prices Pick The Path" (on by default), takes the cheaper one unless you chose
by hand. A hand choice always wins and the header says when the other way is cheaper today.

**A price-picked path is locked in once you are inside the segment.** The dust is bought; a price
moving at 330 must not flip you onto the other way and leave the dust unused. The pick is written
as a choice (so it sticks) and remembered as price-made, so the window says "chosen by the prices
when you got here" and, if it comes to that, "the other way is cheaper now" — information, not a
change. A hand choice clears the mark.

Three rules keep this honest. A vendor reagent is priced at the vendor (`buy` in the data), because
nobody buys a Copper Rod off the auction house. A path is only compared when *every* reagent on
*both* paths has a price; a half-priced path is a floor, not an estimate, and the option row says
"some reagents unpriced" instead. And without Auctionator, or without a scan, nothing is priced and
the guide's own recommendation stands exactly as before — the route never depends on prices.

The shopping list carries the same prices: each row's cost, each bracket's total (reagents and
formulas), and a "made along the way" section for the wands and oils the route produces, with a
net figure if they all sell — the rods are left out because the next rod consumes them.

## D13 — Alts are shown, and counted only when asked

Commander_Quartermaster's ledger knows what your other characters hold (it now tracks enchanting
materials for exactly this). A shopping row says "25 on your other characters" so you do not buy
them twice; "Count My Other Characters" (off by default) treats them as reachable, because a stack
on a bank alt is not in your hand until you have logged over and mailed it.

## D14 — Refresh Prices

The ledger's **Refresh Prices** button appears only while the auction house is open with
Auctionator loaded. It hands `MultiSearchExact` the exact names of every reagent on every path of
the route (alternatives are priced too), the formulas the route buys and what the crafts make, and
the route is re-priced when Auctionator's search ends (its event bus, in a pcall; a Full Scan's
completion re-prices too). The crafted goods that are sold — wand, oils — now have names in
`D.ITEMS` so the search can ask for them before the client has ever seen one. `/ctc refresh` does
the same.

## D15 — First Aid is a second guide on the same engine, and its ranks are the banner's

First Aid 1–375 (2026-09-19) is `D.GUIDES.FIRSTAID`: the cloth ladder with its two vendor trips,
after Wowhead's TBC Classic First Aid guide (Nodge), with thresholds, reagents and placements from
the same client tables and world DB as Enchanting (through Commander_Formulary's generator). The
engine did not change; D1 said this is the shape a second profession needs, and it was. The guide on
screen is the character's: the title of the guide window is the switch (click to cycle, hover for
each guide with the character's rank in it), `/ctc firstaid` and `/ctc enchanting` do the same, and
whichever profession window opens brings its guide on screen. A new character starts on the first
guide whose profession they have.

Two things First Aid does differently. It is a **trade-skill** profession (`frame = "TRADESKILL"`):
`TradeSkillFrame`, `TRADE_SKILL_SHOW / CLOSE`, `GetNumTradeSkills / GetTradeSkillInfo` and
`GetTradeSkillLine`, so the window code keeps one channel table per frame kind with the same four
operations. And **three of its ranks are not trainer-taught**: Expert is "Expert First Aid - Under
Wraps" from Deneb Walker (Stromgarde) or Balai Lok'Wein (Brackenwall), Artisan is the Triage quest
from the doctor of your faction, and Master is "Master First Aid - Doctor in the House" from Burko or
Aresella, which needs 300 — not 275, so it is offered at the cap. Per D4 these stay a banner rather
than steps: a rank row carries `book` or `quest`, and the banner names the book and its price with
the vendor and a waypoint (and says when you already hold it), or the quest with the doctor and a
waypoint. The manuals for Heavy Silk (180) and Mageweave (210) are buy steps on the 115–150 segment,
on the same vendor as the Expert book, so the preview shows the whole trip at 125 and each becomes
current at its own skill (D5).

**The published counts are generous and stand as the floor.** Heavy Linen 40–80 is listed at 70
against a model of 46; D3 makes the guide's figure the floor, so the shopping list never asks for
less cloth than the published list (190 linen, 165 wool, 150 silk, 115 mageweave, 240 runecloth,
90 netherweave) and the model is never more than twenty percent over it (harness B3c, C17).

**The secure buttons' holders are siblings of the guide, not children.** Protection walks up the
whole parent chain: after the holders were taught to stay put in combat, the guide above them was
still refused its `SetSize` from a combat rebuild (2026-09-23). A holder is therefore parented to
UIParent and pinned to the SCREEN at the guide's corner plus its row offset — not anchored to the
guide, because the frame a secure button is anchored to joins its protected family and is locked
in combat exactly like a parent (Commander_Buffs proved that the same day). The guide is then a
plain frame again that resizes and re-shows mid-fight. Nothing is inherited, so `SyncHolders`
mirrors the guide's strata and level and re-places the holders after the HUD chrome has applied
its own scale and position, a hook on `SetScale` follows the resize grip live, a 10 Hz watch on the
guide's corner follows a drag, and every path that hides the guide hides the holders with it. The
harness models parent-chain and anchor-family protection and reproduces the field message on both
earlier layouts (F2).

## D16 — Both windows are solid, and each scales by its bottom-right corner

Asked for 2026-10-03: the guide's backdrop was Dark Panel's 60% tint and the route window's the same,
and a page of small text over a snowfield is a page of small text over a snowfield. Neither window
gained a new style. The shared chrome grew two opt-in options instead (`opaque`, `scaleGrip`, and
`ApplyStyleBackdrop`'s third argument), so the guide keeps its Frame Style choice — Classic, Dark,
Solid, Window — and whichever is chosen is simply drawn solid; None is still none. Everyone else's
frames are untouched.

The grip is `Commander.UI.AttachScaleGrip`: the whole frame is scaled (SetScale), about its TOP-LEFT
corner, so the corner under the cursor is the one that moves; the scale is the cursor's projection
on the frame's own diagonal, clamped to the Frame Scale slider's 60–160%. The guide's grip drives
`GuideScale` and saves the position by that held corner; the secure buttons' holders follow through
the existing `SetScale` hook. The Window style already has a grip, so the new one stands down there.
The route and shopping window (one frame, two modes) has its own `LedgerScale`, with a slider on the
settings page that sets the same number; its Close button moved fourteen pixels left to clear the
corner. The guide is a plain frame (see the holders, above), so the grip works mid-fight.

## D17 — Go buttons and Route This Trip go to Commander Orders

1.2.0, 2026-10-04. TomTom left the suite; Commander Orders 3.0 is its navigation, and `SetWaypoint`
never tried Orders before, so the day TomTom went the Go buttons would have dropped to printing
coordinates. A Go press calls `CommanderOrders.Add` with source "Tradecraft" and key
"place:<name>@<zone>": a place owns ONE waypoint, so pressing Go again moves it rather than stacking
a second, and the waypoint takes the arrow (the player asked for it). It is session only, Orders'
default for a consumer: an errand. With Set Waypoints off (the option keeps its key, `UseWaypoints`,
and lost "Through TomTom" from its label), Orders absent or turned off, Orders refusing the place,
or a zone missing from `D.ZONES`, the place is printed with a `/way` line -- the zone by name when
there is no map id, since `/way` reads names -- and every Go tooltip says which it will be.

**Route This Trip** (the guide's Trip button, the shopping list's title strip, `/ctc trip`) is the
shopping trip D11 already defines -- the current trainer bracket -- walked: every formula that
bracket still has to buy (pending, not held, not skipped) becomes a stop at its vendor, one
Commander Orders route, nearest first, so arriving at one points the arrow at the next. A formula
sold in two places your faction can use is ONE stop with the second as an alternative (the arrow
takes the nearer); formulas with exactly the same vendors share a stop, titled with the vendor and
the first formula. The route is owned as (Tradecraft, "trip:<guide>:<bracket>"), so asking again
replaces it. The button only appears while the bracket has a vendor to visit. Without Orders the
trip prints each stop's `/way` line rather than nothing. The shopping list's button sits in the
title strip because the foot of that window is already full when Auctionator is loaded. UI harness
C3 and E1/E3.

## D18 — Every Go is the suite's one Go button (Commander Orders 3.1)

1.3.0, 2026-10-05. Commander Orders 3.1 made "Go to" one widget and one API for every Commander
module, and its DECISIONS carry the one words-and-gestures rule every consumer cites (D31): "Go" on a
row button, "Go to <Thing>" on a standalone one, "[Go]" in a chat link; click Go, Shift-click share
the place in chat, Ctrl-click copy its `/way` line; a list row with no room for a button takes
Ctrl+Right-click, with `Commander.UI.GoRowHint` in its tooltip. So every Go on the guide is now a
`Commander.UI.GoButton` (pooled like the guide's other widgets: a reused one gets its options
filled afresh and is refreshed), D17's own lookup and `SetWaypoint` are gone, and the success line
is Orders' own "Waypoint set: <title> (Zone x, y)", behind Orders' Announce setting, rather than
ours. The source, keys, titles and "takes the arrow" of D17 are unchanged; the button now greys out
with Orders' reason, and reads "Going" while the arrow is on its place.

Set Waypoints stays (Orders' critic D7 asked to keep one per-module switch or none; this one
predates the round and costs nothing): with it off a click prints the place and its `/way` line,
and Shift and Ctrl still share and copy, since they send no waypoint. Without Orders a Go prints the
place's `/way` line, the GoButton's own fallback.

Two Gos are new, both answered at runtime by Orders' locator, never by our data:

- "Learn <profession> from any trainer" and "Any <profession> trainer in a capital city" get a Go
  to the nearest trainer of the profession, `{ townsfolk = "<Profession> Trainer" }`, titled
  "Nearest <profession> trainer", key "trainer:<guide>". Where there are several, the waypoint
  carries them all and the arrow follows the nearest.
- A reagent that ordinary trade-supply vendors sell (`D.ITEMS[id].vendor`: Copper Rod, Simple
  Wood, the vials) goes to the nearest vendor of that item on Ctrl+Right-click of its row
  (`{ itemVendor = id }`, key "item:<id>"); its tooltip says so. A plain right-click does nothing.

Neither works without Questie (the locator says "Needs Questie to look that up", in Orders' words).
UI harness C3c, D4b and I1. The Trip route (D17) is unchanged, except that its printed `/way` lines
are Orders' `WayLineFor` when Orders is loaded.

Two layout rules came out of the 2026-10-05 review. The reagent row's Ctrl+Right-click registers
its pooled hover for the right button only, and a Button keeps its click registration until it is
changed again, so `NewHover` puts back `LeftButtonUp` on every reuse: otherwise a later paint that
hands that hover to a two-ways option row (the 110-135 segment after Greater Magic Wand) left the
"take this way instead" click unanswered until a /reload (UI harness I2). And a row Go is 18 high
anchored 2 above a line that may be only 14 + 2 high, so `GoRow` keeps the next row 18 below the
row's top: stacked Gos (Master trainers, a formula's vendors) no longer overlap by 2 px (D3b).


**A greyed Go promises no press** (the review's round 2, 2026-10-05). Since Orders turned the
GoButton's motion scripts on (its D31), a greyed Go shows its tooltip, and the Go's line read
"Prints the coordinates and a /way line to chat (Commander Orders is turned off)", or "(Set
Waypoints is off)" with Set Waypoints off while Orders was turned off, above the red "Commander
Orders is turned off (/corder)"; the trainer Go without Orders said it would print above "Needs
Commander Orders". 2.5.6 delivers no OnClick to a disabled Button, so `GoClicked` never ran and
nothing printed: Set Waypoints off prints only while the button is live. A Go's line is now
`GoWords(button)`: nil while Orders is turned off (Set Waypoints or not), nil for a locator Go
without Orders, nil for a place with no map id; a live Go is worded as before (the arrow, Set
Waypoints off's print, a placed Go's `/way` line without Orders). The Trip button keeps
`WaypointWords`: a plain button, live, whose press does print. UI harness C3d and D4c.
