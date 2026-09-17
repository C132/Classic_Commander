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

## A3 — `/cast <recipe name>` from a secure macro button casts a craft recipe

**Load bearing for the Craft button.** `DoCraft` is protected on this client — **verified in game
2026-09-17**, it raised `ADDON_ACTION_FORBIDDEN` — so the button is a `SecureActionButton` running
`/cast Enchant Bracer - Minor Health`. Casting recipes by name is how the hand-written leveling
macros have always worked, and the craft window does not need to be open.

Symptom if wrong: nothing happens on Craft, or "spell not found". Test: press Craft on a known step;
the tooltip shows the exact macro, which can also be pasted into a real macro to compare.

## A4 — `/use <slot>` on the line after the `/cast` lands the enchant on that worn piece

The second line of the same hand-written macro (`/use 9` for bracers); `/use <bag> <slot>` is the
bag form. `SecureCmdUseItem` → `UseInventoryItem` / `UseContainerItem`, which target the pending
spell at the item when one is up.

Symptom if wrong: the cursor glows and nothing happens; the enchant is still yours to place by hand.
"Cast On My Own Gear" turns the line off. Test: Craft on Minor Health with bracers equipped.

## A5 — The replace question is up as `StaticPopup1` by the time the macro's `/click StaticPopup1Button1` runs

**Verified in game 2026-09-17** with a hand-written macro of the same three lines. `ReplaceEnchant()`
is protected on this client (it raised `ADDON_ACTION_FORBIDDEN`) despite being listed as an ordinary
function in ItemDocumentation, so the answer comes from inside the secure macro. Only the
`StaticPopup1` slot is pressed; if another dialog already occupies it the replace question lands in
`StaticPopup2` and stays up for the player.

Symptom if wrong: the confirm dialog appears every cast. Test: Craft twice on the same bracers.

## A6 — A `SecureActionButton` with `type=spell, spell=<profession name>` opens the craft window

The Open button. Both click edges are registered: `SecureActionButton_OnClick` acts on the one
`ActionButtonUseKeyDown` names and discards the other (in game 2026-09-17: `AnyUp` alone did
nothing). The button is inside an ordinary holder frame so nothing protected is ever shown, hidden
or moved by the layout.

Symptom if wrong: the button does nothing. `/cast Enchanting` still works. Test: click it.

## A6b — `CreateMacro(name, icon, body, true)` / `EditMacro(name, name, icon, body)` maintain the Tradecraft macro, after `UPDATE_MACROS`

The RXPGuides pattern (`Targeting.lua`), with the per-character flag added. In game (2026-09-17)
writing it at `PLAYER_LOGIN` produced no macro and no error; it now waits for `UPDATE_MACROS` or
`PLAYER_ENTERING_WORLD`, and a failed call prints its error once. The icon passed is whatever
`GetSpellTexture` returns for the recipe (a file id on this client).

Symptom if wrong: a "could not create the Tradecraft macro" line in chat, or still no macro on the
character-specific tab of `/macro`. Test: open `/macro` after the guide has painted a craft step.

## A6c — A `CLICK` binding on an always-shown, off-screen secure button fires from a key

Commander_Armory's weapon swap is the precedent on this client. "Craft the current step" appears
under Key Bindings → Commander Tradecraft.

Symptom if wrong: the key does nothing while the Craft button works. Test: bind it, close the guide
window, press it.

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
