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

## A6b — `CreateMacro(name, icon, body)` / `EditMacro(name, name, icon, body)` maintain the Tradecraft macro (General tab), after `UPDATE_MACROS`

The RXPGuides pattern (`Targeting.lua`). `GetMacroIndexByName` past `MAX_ACCOUNT_MACROS` (120)
means a character-specific one, which is deleted and remade on the General tab. In game (2026-09-17)
writing it at `PLAYER_LOGIN` produced no macro and no error; it now waits for `UPDATE_MACROS` or
`PLAYER_ENTERING_WORLD`, and a failed call prints its error once. The icon passed is whatever
`GetSpellTexture` returns for the recipe (a file id on this client).

Symptom if wrong: a "could not create the Tradecraft macro" line in chat, or no macro on the
General tab of `/macro`. Test: open `/macro` after the guide has painted a craft step.

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

## A9 — The uiMapIDs in `D.ZONES` are this build's, and Commander Orders takes them with 0..1 coordinates

The zone ids came from this build's `UiMap` table (Ashenvale 1440 … Shattrath 1955); the Go buttons
and Route This Trip hand them to `CommanderOrders.Add` / `AddRoute` with the coordinates divided by
100 (Orders' convention, which was TomTom's). A wrong id is not silent: Orders refuses a map with no
world position, and the button then prints the place and its `/way` line instead. Without Commander
Orders, or with Set Waypoints off, the same line is printed, which is the same information. Check
by pressing Go on Kulwia (Horde, Stonetalon) or Dalria (Alliance, Ashenvale): the arrow should
point at Sun Rock Retreat or Astranaar.

## A10 — `GetFactionInfoByID` returns the standing index as its third value

Used only to colour the Keepers of Time / Consortium requirement red when short. A nil answer leaves
it orange.

## A11 — Coordinates

Vendor and trainer coordinates were converted from world-DB spawn points through `UiMapAssignment`
boxes and agree with the published guide to within a point everywhere both have a figure. The two
that have no published figure to check against: Karaaz at Netherstorm 43.6, 34.3 and High Enchanter
Bardolan at Shattrath 43.4, 92.4. Lower City is at the bottom of the Shattrath map, so the 92 is
plausible; look once.

## A12 — The trade skill window behaves like the craft window (First Aid)

`TRADE_SKILL_SHOW` arrives after UIParent has loaded `Blizzard_TradeSkillUI`; `GetTradeSkillLine()`
answers the localised profession name (the one `GetSpellInfo(3273)` gives) with rank and max rank;
`GetNumTradeSkills` / `GetTradeSkillInfo(i)` list the recipes with `"header"` rows. Read from this
client's own `Blizzard_TradeSkillUI/TBC` code 2026-09-19. Cooking and Fishing use the same frame and
are ignored by name, as Beast Training is on the craft frame (harness B0, G7).

Symptom if wrong: opening First Aid does not switch the guide, or a manual step stays current after
the recipe was learned until `/ctc status` is run. Test: open First Aid with the Enchanting guide
on screen.

## A13 — `IsSpellKnown` answers for the rank spells, or the cap does

Nothing depends on it: a book or quest rank is done when the max rank rises past its cap, which
`GetSkillLineInfo` reports (A1). Listed only because the banner's "You have it — right-click it to
read it" line reads the book from the bags with `GetItemCount`, which is A7.

## A14 — The guide's rect answers right after the HUD chrome anchors it

The holders are pinned to the screen off `guide:GetLeft()`/`GetTop()` at the end of each paint
(anchoring them to the guide would lock the guide in combat: anchor targets join the protected
family, field-verified in Commander_Buffs 2026-09-24). A nil rect is skipped and caught by the
drift watch a tenth of a second later; a stale one would leave the Craft and Open buttons beside
their row. *Test:* drag the guide and rescale it with the grip: the buttons must follow within a
blink and sit on their row. If `CommanderTradecraftGuide` ever shows up again in an
`ADDON_ACTION_BLOCKED`, something secure is anchored to it after all.

## A15 — The scale grips' arithmetic matches the client's coordinate spaces

`AttachScaleGrip` (Commander_Events) takes `GetCursorPosition()` as screen pixels, a frame's
`GetLeft()`/`GetTop()` times its `GetEffectiveScale()` as the same pixels, and a `SetPoint` offset as
being in the frame's own scaled units — the three facts the suite's Window-style grip and drag code
already lean on, but never before all at once. It also sets the anchor and then the scale inside one
`OnUpdate`. *Test:* drag the corner of the guide and of the route window, slowly, in every direction:
the top-left corner must not move at all, the grabbed corner must stay under the cursor along the
diagonal, and letting go must not make either window jump. Then `/reload`: both come back the size
and place they were left. If the top-left drifts, the offset division is wrong; if the window jumps on
release, the saved `GuidePos` (TOPLEFT, screen units, measured down from the top) is.

## A16 — Dark Panel's tooltip border looks right over a solid fill

The guide and the route window keep Dark Panel's rounded tooltip edge, now over opaque black instead
of a 60% tint. *Test:* look at the corners: the edge art has transparent notches outside its curve,
and a solid fill that reaches under them shows as four dark squares. The fill is inset three pixels
for exactly this, as it always was; if squares show, Solid Dark's hairline edge is the fix.
