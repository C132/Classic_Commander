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

## D7 — The Craft button does the three things you would do a hundred times

`DoCraft(index)`, then for an enchant `PickupInventoryItem(slot)` on the matching worn piece (or
`PickupContainerItem` on the first one in the bags), then `ReplaceEnchant()` if the replace question
is up. The last two are options, on by default, and the popup is answered only within three seconds
of a cast this module started — a replace question from anywhere else is left for the player.

The Open button is a `SecureActionButton` casting the profession, because `CastSpellByName` is not
ours to call. It lives inside a plain holder frame that the layout shows, hides and anchors; the
protected button itself is never touched after creation, so combat cannot throw. Harness F2 is the
combat case.

## D8 — Progress is per character; settings are per account; Restore Defaults cannot reach progress

Path choices, skipped steps and the recipe memory are in `CommanderTradecraftChar` (per character).
The options page only iterates `CommanderTradecraft_Defaults`, which has none of those keys. The
enchanter alt keeps their Moonglade decision whatever the main presses (harness F4).

## D9 — "Alternative" applies to the next segment that has one

The current step's segment if it has more than one path, otherwise the first one ahead that does.
The choice for 156–185 is worth making while the vendor trip is still in the preview, standing in
town, not on arrival at 156.

## D10 — ASCII marks in the ledger

`+` done, `>` current, `-` skipped, `–` (en dash) for ranges. The client's fonts drop shape glyphs
(the suite learned this the hard way with `‖`), so ✓ and ▸ and → never went in.

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
