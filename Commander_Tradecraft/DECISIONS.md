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
