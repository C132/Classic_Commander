# Commander_Armory — assumptions to verify in game

Everything here passes the headless harnesses, which prove the logic and nothing about the live
client. Numbered so a test session can report against them. A1–A6 are the ones that decide whether
the module works at all; the rest degrade gracefully.

Most of these were verified against Blizzard's own 2.5.6 UI source (`Gethe/wow-ui-source`, branch
`classic_anniversary`, `version.txt` 2.5.6.69110) before a line was written. What is listed here is
specifically the residue that **source cannot settle** — runtime behaviour, server rules, and CVar
defaults.

---

## A1 — `C_EquipmentSet` is present but we never depend on it

**Not load bearing, by construction (DECISIONS D1).** The namespace is proven to exist by a
TBC-loaded call site in Blizzard's `SecureTemplates.lua`. What is unknown is whether the *server*
enables equipment sets for the TBC game type — `CanUseEquipmentSets()` is the capability gate and
nothing in the shipped UI ever calls it, so source cannot say.

The module probes it once at login and stores the answer. Nothing branches on it.

Test: `/dump C_EquipmentSet.CanUseEquipmentSets()` and `/dump C_EquipmentSet.GetNumEquipmentSets()`.
Report both numbers — if sets do work server-side there is a future optimisation available, and if
they do not, this line can be deleted from the module.

## A2 — `GetInventoryItemsForSlot(slot, tbl)` exists and includes bank locations

**Load bearing for one code path, with a fallback.** warcraft.wiki.gg lists this function under
"BC Anniversary 2.5.6 (68184)", and Blizzard's own flyout on later flavors is built on it — but it
is not exercised by any TBC-loaded FrameXML file, so its presence here is asserted by the wiki
rather than by source.

The candidate list tries it first and falls back to walking bags and the bank cache ourselves. If
it is absent the flyout still fills; what is lost is the server's own opinion about what may legally
enter a slot, which is the authority on dual-wield eligibility.

Test: `/dump type(GetInventoryItemsForSlot)`. Then open the flyout on your off-hand as a class that
cannot dual wield and confirm one-handed weapons are absent.

## A3 — The bare item globals are CVar-gated shims, and we never touch them

**Fully mitigated.** `Blizzard_DeprecatedItemScript` defines `EquipItemByName`, `GetItemInfo`,
`IsEquippableItem` and friends only when `loadDeprecationFallbacks` is on, and that CVar's default
is not discoverable from source. Every call in this module goes through `C_Item.*` and
`C_Container.*`, which are the real namespaces.

Symptom if this were wrong: nothing, because we do not call them. Listed so that nobody "helpfully"
simplifies a `C_Item.GetItemInfo` back to `GetItemInfo` later.

Test: `/dump GetCVarBool("loadDeprecationFallbacks")` — for the record, not for the module.

## A4 — The bank is unreadable while closed, and the cache is the only answer

**Load bearing for the headline feature (D9).** Blizzard's own code keeps an `_isAtBank` flag and
gates every bank path on it, and the ecosystem's entire bank-addon genre exists because container
calls return nothing for bank bags once `BANKFRAME_CLOSED` fires. That is strong evidence but it is
behavioural, not quoted from source.

If the bank turns out to be readable while closed, the cache becomes redundant and everything still
works. If it is unreadable *and* our snapshot on `BANKFRAME_OPENED` misses a container, a banked
item reports as missing — the exact failure the module exists to fix.

Test: visit the bank once with a known set piece in it, walk away, then select that set. It must say
"in your bank", not "missing". Then check the bank bags specifically, not just the main bank pane —
bank bags are containers 5..11 on this client and the shared `Enum.BagIndex` is the mainline one
where those numbers are wrong.

## A5 — Equipping calls are not protected, only combat-restricted

**Load bearing.** No evidence of taint protection on `C_Item.EquipItemByName`,
`PickupInventoryItem`, or `C_Container.PickupContainerItem` was found in source — but that is
absence of evidence. The server rule (only slots 16/17/18 in combat) is quoted and certain; the
taint question is not.

Symptom if wrong: an `ADDON_ACTION_BLOCKED` error on the first swap. Loud and immediate.

Test: equip a single item from the flyout, out of combat, with `/console scriptErrors 1`.

## A6 — The cursor method is blocked in combat for **every** slot, weapons included

**Load bearing, and it is the reason for the whole two-channel design (D7).** This comes from
ItemRack-Anniversary's own source comment — *"PickupInventoryItem is blocked by the game during
InCombatLockdown() for all items including weapons"* — a working addon on this exact client, which
is the best available evidence short of testing it.

If it is wrong and the cursor does work in combat for weapons, the secure-button channel is
unnecessary complexity but harms nothing. If it is right and we had ignored it, every in-combat
weapon swap would silently do nothing.

Test: bind the weapon-swap key, enter combat, press it — the weapon should change. Then try
equipping the same weapon from the flyout in combat; it should refuse with a queued-swap notice
rather than appearing to work.

## A7 — A sixth `CharacterFrame` tab can be added the documented way

**Load bearing for the set manager.** The recipe is read from source: `CHARACTERFRAME_SUBFRAMES` is
a global table iterated with `pairs`, `CharacterFrameTab_OnClick` is a plain global with a
string-name if/elseif chain that no-ops for unknown tabs, and `PanelTemplates_SetNumTabs` is
literally an assignment. All quoted. What is untested is the whole assembly behaving on screen.

Known rough edge, already handled: `CharacterFrame_TabBoundsCheck` loops over a *file-local*
`NUM_CHARACTERFRAME_TABS = 5`, so it neither sizes our tab nor accounts for it when computing
crowding. We size the tab ourselves with `PanelTemplates_TabResize`.

Test: open the character panel and confirm six tabs, that clicking Armory hides the paperdoll, that
clicking Character comes back cleanly, and that the tab row is not overlapping the frame edge at
default UI scale.

## A8 — `hooksecurefunc` on the paperdoll slot handlers reaches all nineteen buttons

The `PaperDollItemSlotButton_*` functions are plain globals and the XML template calls them
directly, both quoted from source. The assumption is that hooking them is enough to keep our
popout arrows in sync with every path that redraws a slot.

Symptom if incomplete: a flyout arrow that goes stale — pointing at the previous item — after some
particular refresh, most likely on login or after a `UNIT_INVENTORY_CHANGED` we did not anticipate.

Test: equip something from a bag by dragging it the normal way and confirm the arrow and its
tooltip update. Then `/reload` with the character panel open.

## A9 — `uniqueID` in an item link is an instance seed, not a stable identity

**Load bearing (D6).** The key deliberately drops it. If it were in fact a stable per-item
identifier, dropping it would mean two genuinely different copies of an item collapse to one key —
harmless, since the equipper then picks whichever it finds. If it is what we believe and we had
*kept* it, no saved entry would ever match anything again and every set would report every item
missing. The asymmetry is why we drop it.

Test: save a set, log out, log back in, and confirm the set still reports itself as equipped. Then
enchant a piece in a saved set and confirm the set reports that slot as a loose match rather than
missing.

## A10 — `GetItemStats(link, tbl)` exists and returns the TBC stat keys

Not load bearing — stat totals are a nicety. The function is undocumented in the generated API docs
and wiki-confirmed for 2.5.6, and there is no `C_Item` equivalent on any flavor.

Symptom if absent: the stat totals panel shows nothing. Everything else works.

Test: select a set and check that the stat summary lists TBC stats — and specifically that
**+Healing and +Spell Damage appear as separate lines**, since that split exists only in this
expansion and is one of the main reasons a hybrid keeps two sets.

## A11 — `EQUIP_BIND` must be accepted before the popup is hidden

Quoted from source: the dialog's `OnHide` calls `CancelPendingEquip(slot)`. So auto-confirming
requires `EquipPendingItem(slot)` **first** and `StaticPopup_Hide` **second**. Reversing the order
silently cancels the equip and strands the run with no error at all.

Test: with "auto-confirm bind on equip" on, equip a bind-on-equip item from the flyout. With it off,
the run should pause and resume correctly after you click Okay — and cancel cleanly if you press
Escape.

## A12 — Only `bagType == 0` containers count as spill space

Quoted behaviour from Blizzard's own bag bookkeeping. In TBC this is load-bearing in a way it is not
elsewhere: a hunter with two quivers and a warlock with a soul bag have far less usable space than
their bag count suggests, and the pre-flight check would promise a swap it cannot finish.

Test: as a hunter, fill your normal bags but leave the quiver empty, then try to equip a set that
needs a free slot. It must refuse up front, not fail partway.

## A13 — Equipping a two-hander displaces the off-hand to bags automatically

Documented behaviour, and the reason the planner equips the main hand first. The reverse order
throws `ERR_2HANDED_EQUIPPED`.

The planner still reserves a bag slot for the displaced off-hand rather than trusting the client to
find one, because with full bags this is exactly where a naive implementation half-applies a set.

Test: as a warrior wearing 1H + shield with exactly one free bag slot, equip a two-hander set. Then
repeat with **zero** free slots — it must refuse before touching anything.

## A14 — `C_Item.GetItemUniquenessByID` reports TBC unique-equipped families

Used to pre-empt the conflict rather than discovering it as a server refusal. Patch 2.3.0 converted
many dropped rings, trinkets and one-handers from Unique to Unique-Equipped, so this is live
content, and TBC's unique-equipped meta gems make it subtler than it looks — two pieces can conflict
through their *gems* rather than themselves.

Symptom if the call is unreliable: the plan does not pre-strip the conflicting item and the second
equip is refused by the server, which the run reports as a failed action. Recoverable, not silent.

Test: equip two of the same unique-equipped trinket by saving one into both trinket slots. The
pre-flight should refuse and name the conflict.

## A15 — `C_PaperDollInfo.IsRangedSlotShown()` is the right test for the relic slot

The namespace is proven live on TBC by an inspect-frame call site. We use it in preference to
class-checking so that any class Blizzard ever gives a relic to is handled without a code change.

Test: on a paladin, druid or shaman, confirm slot 18 is labelled Relic, that the flyout offers only
that class's librams/idols/totems, and that the ammo slot is hidden. On a hunter, confirm the
reverse.

## A17 — `GetInventoryItemsForSlot` may or may not return bank locations while away from the bank

**The highest-value single probe in this list.** Blizzard's own comment in the flyout code says the
result sorts as "inventory, backpack, bags, bank, and bank bags". If it still returns bank
locations when the player is *not* standing at the bank, then the bank cache (D9) is redundant and
a large piece of this module can be deleted. If it does not — which is what every bank addon in the
ecosystem implies — the cache is exactly right.

The code tolerates both outcomes and prints the answer under the health path, so one session
settles it.

Test: with a known item in the bank, walk away, then run the health command and read what it says
about bank visibility. Then open the flyout for that item's slot and see whether the item appears
without the cache.

## A18 — Nothing prevents equipping while shapeshifted or in a stance, out of combat

Searched for and **not found**: any citation, in either direction, for a form-specific or
stance-specific equip restriction. Every reported failure in the ecosystem traces back to combat
lockdown rather than to the form itself — druids auto-enter combat in bear form, which is what
makes it look like a form restriction.

The module therefore treats forms as irrelevant and gates only on combat. If that is wrong, the
symptom is a swap that refuses out of combat while shapeshifted, with the combat queue never
firing because combat never ends.

Test: in cat form, out of combat, equip a single item from the flyout. Then the same in bear form,
and as a warrior in defensive stance.

## A16 — The suite's own neighbours are not disturbed

`Commander_ActionBar` owns the entire micro-menu including `CharacterMicroButton`, and
`Commander_Bags` owns the container frames. This module anchors to neither.

Test: with the full suite loaded, open the character panel and confirm the micro menu has not
shifted, then open all bags and confirm nothing has moved.
