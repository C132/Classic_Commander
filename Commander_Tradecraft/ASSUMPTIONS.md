# Commander_Tradecraft — assumptions to verify in game

Everything here passes the three headless harnesses, which prove the logic and nothing about the
live client. Numbered so a test session can report against them. A1–A3 decide whether the module
works at all; the rest degrade gracefully.

---

## A1 — `GetSkillLineInfo` finds Enchanting by the name `GetSpellInfo(7411)` returns

**Load bearing.** The rank and max rank come from the skill list, matched by name against the
profession spell's own name so the match survives localisation. RXPGuides does exactly this on this
client (`RXPGuides.lua`, `GetProfessionNames`), which is the evidence.

If the line is not found (collapsed header) the module calls `ExpandSkillHeader(0)` once and rescans,
as Questie does.

Symptom if wrong: the window says "Learn Enchanting" to an enchanter. Test: `/ctc status` prints the
rank the skills window shows.

## A2 — `IsSpellKnown(recipeSpellId)` is true for craft recipes the character knows

**Load bearing for buy steps, with a fallback.** Formula steps resolve when the recipe is known. If
`IsSpellKnown` (or `IsPlayerSpell`) does not answer for tradeskill recipes on this client, the
fallback is the craft-window memory: every `CRAFT_SHOW` / `CRAFT_UPDATE` records the list into
`CommanderTradecraftChar.knownRecipes`, so the step resolves the next time the window opens.

Symptom if wrong: after learning a formula the buy step stays current until you open Enchanting.
Not a data bug. Test: learn a formula with the craft window closed and watch whether the step moves
before you open it.

## A3 — Enchanting uses the CRAFT frame and `DoCraft(index)` crafts once

**Load bearing for the Craft button.** Auctionator gates its `CraftFrame` / `GetCraftInfo` path on
`tbc` and this client's `Blizzard_CraftUI/TBC` wires its Create button to
`DoCraft(GetCraftSelectionIndex())`, so both are settled from source. What is not settled from
source: whether `DoCraft` is callable from an addon click (it is not on the protected list anywhere
in the suite's notes, and Skillet-Classic calls it).

Symptom if wrong: an "action blocked" error on Craft. Test: press Craft on any step with reagents.

## A4 — After `DoCraft` on an enchant, `SpellIsTargeting()` is true and `PickupInventoryItem(slot)` casts it on that slot

This is what the character sheet does when you click a slot with the glowing cursor
(`PaperDollItemSlotButton_OnClick` → `PickupInventoryItem`), and `PickupContainerItem` is the bag
equivalent. The module waits 0.05s after `DoCraft` before checking, in case targeting is not up on
the same frame.

Symptom if wrong: the cursor glows and nothing happens; the enchant is still yours to place by hand.
"Cast On My Own Gear" turns the attempt off. Test: Craft on Minor Health with bracers equipped.

## A5 — The replace question is `StaticPopup "REPLACE_ENCHANT"` and `ReplaceEnchant()` answers it

Answered only within three seconds of a cast the module started, and hidden afterwards. If the popup
has another name on this client the question simply stays up for the player.

Symptom if wrong: the confirm dialog appears every cast. Test: Craft twice on the same bracers.

## A6 — A `SecureActionButton` with `type=spell, spell=<profession name>` opens the craft window

The Open button. `RegisterForClicks("AnyDown", "AnyUp")` so it fires whichever way
`ActionButtonUseKeyDown` points (same as Commander_Inventory). The button is inside an ordinary
holder frame so nothing protected is ever shown, hidden or moved by the layout.

Symptom if wrong: the button does nothing. `/cast Enchanting` still works. Test: click it.

## A7 — `GetItemCount(id, true)` includes the bank once the bank has been opened this session

Standard Classic behaviour: bank contents are cached by the client after a visit. Before the first
visit of a session the bank share reads as zero and the shopping list over-asks by that much. The
option's tooltip says so.

## A8 — `GetItemInfo(id)` returns the equip location in the ninth slot and `C_Container` exists

Both are how Commander_Bags reads bags on this client. The module carries the pre-`C_Container`
names as fallbacks anyway.

## A9 — TomTom's `AddWaypoint(uiMapID, x, y, opts)` takes fractions and the uiMapIDs in `D.ZONES` are this build's

The zone ids came from this build's `UiMap` table (Ashenvale 1440 … Shattrath 1955). Without TomTom
the Go button prints the coordinates to chat, which is the same information.

## A10 — `GetFactionInfoByID` returns the standing index as its third value

Used only to colour the Keepers of Time / Consortium requirement red when short. A nil answer leaves
it orange.

## A11 — Coordinates

Vendor and trainer coordinates were converted from world-DB spawn points through `UiMapAssignment`
boxes and agree with the published guide to within a point everywhere both have a figure. The two
that have no published figure to check against: Karaaz at Netherstorm 43.6, 34.3 and High Enchanter
Bardolan at Shattrath 43.4, 92.4. Lower City is at the bottom of the Shattrath map, so the 92 is
plausible; look once.
