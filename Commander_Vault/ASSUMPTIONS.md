# Commander_Vault — untested in the client

Everything here passes the harness, which means it is right about the model it
was tested against. The list below is what the harness *cannot* know, because
it mocks the client rather than being one. Each entry names the symptom to look
for, so a five-minute visit to a banker settles it.

Numbered so a later session can tick them off.

## The takeover

1. **The banker session survives the takeover.** `BankFrame` is moved to
   (-4000, 4000) at alpha 0 rather than hidden, because its `OnHide` calls
   `CloseBankFrame()`. *Symptom if wrong:* the vault opens and instantly
   closes, or withdrawing says you are not at a bank.
2. **The UI panel system does not drag it back.** `BankFrame` is registered in
   `UIPanelWindows`, so `ShowUIPanel` positions it — the offset is applied on
   `BANKFRAME_OPENED`, after that. *Symptom if wrong:* the stock bank window
   flickers back into view on top of the vault, or reappears the second time
   you visit a banker in one session.
3. **Its position is restored intact.** Turning the takeover off mid-session,
   or closing the bank, must leave Blizzard's frame exactly where it was.
   *Symptom if wrong:* the stock bank window opens off-screen afterwards.

## Item buttons

4. **A hand-built `Button` can pick up, split, use and link a container item.**
   Container items are not protected on this client, but the buttons here
   inherit no template at all. *Symptom if wrong:* clicking a vault slot does
   nothing, or throws an action-blocked error.
5. **`OpenStackSplitFrame(count, button, ...)` calls back into
   `button.SplitStack`.** That is the contract Blizzard's own container buttons
   rely on; the vault's buttons implement the method but have never been handed
   a real split frame. *Symptom if wrong:* shift-clicking a stack opens the
   split dialog and confirming does nothing.
6. ~~**`GameTooltip:SetBagItem` accepts `BANK_CONTAINER` (-1).**~~ **CONFIRMED
   FALSE, in the field, 2026-09-06.** It does not fill the tooltip for bank
   containers — and worse, it still *fires* `OnTooltipSetItem`, so every other
   addon hooked there (auction price addons, Commander_Tooltip) appends its
   lines to an empty tooltip. The result is a tooltip with a vendor price and
   no item on it. The fill is now verified by asking the tooltip which item it
   is showing and matching it against the one we asked for, which is the only
   signal a foreign addon cannot forge, and the link is used instead.

## Transfers

7. **`UseContainerItem` with the bank open moves the item rather than using
   it.** This is the whole basis of Deposit and of right-click withdraw.
   *Symptom if wrong (and it is the worst failure in this list):* the Deposit
   button drinks your potions. `BankIsUsable()` is re-checked every tick
   specifically to bound this, but the first live test should be with a stack
   of something worthless.
8. **`C_Container.SplitContainerItem` + `PickupContainerItem` merges cleanly.**
   The sort's merge phase splits exactly the amount the destination can take.
   *Symptom if wrong:* a stack left on the cursor and the sort stopping itself
   with "something is on your cursor".

27. **The TBC Trade Goods subclasses are numbered 2 Explosives, 3 Devices and
   12 Enchanting, and class 5 Reagent holds spell reagents only.** The mats
   deposit leaves Explosives and Devices behind, protects the runed rods by
   item id, and never touches class 5. *Symptom if wrong:* Deposit Mats banks a
   sapper charge or a jeweler's kit (subclass numbers off), or banks a priest's
   candles (a crafting reagent turns up in class 5). The rods are safe either
   way — they are named by id, not by subclass.

## Bank bags

9. **`C_Container.ContainerIDToInventoryID(bag)` is the right inventory slot
   for bank bags 5..11**, and `GetInventoryItemTexture("player", id)` draws
   them. *Symptom if wrong:* the bag strip along the bottom is blank or shows
   the wrong bags.
10. **`GetNumBankSlots()` returns purchased bank bag slots, not base slots, and
    a second value meaning "there is nothing left to buy".** The purchase row
    is gated on both. *Symptom if wrong:* every slot reads as unpurchased, or
    the row stays offered after the seventh.
11. **`GetBankSlotCost(bought)` prices the NEXT slot** — it takes the number
    already owned. *Symptom if wrong:* the row prices the wrong slot.
11a. **`StaticPopupDialogs.CONFIRM_BUY_BANK_SLOT` exists and its `OnAccept`
    calls `PurchaseSlot()`.** *Symptom if wrong:* Purchase opens nothing. (With
    the dialog missing, `PurchaseSlot` is called directly.)
11b. **`BankFrame.nextSlotCost` is what that dialog's `OnShow` reads**, not the
    API — the module writes it before raising the dialog. *Symptom if wrong:*
    harmless, one redundant assignment.
11c. **`Interface\PaperDoll\UI-PaperDoll-Slot-Bag` is the empty-bag art**, the
    same file `GetInventorySlotInfo("Bag"..i)` hands back. *Symptom if wrong:*
    an unbought slot draws as a red rectangle rather than a red bag.

## The tooltip line

12. **`OnTooltipSetItem` fires for auction house, merchant and quest-reward
    tooltips**, not only bag ones. *Symptom if wrong:* the count appears on
    bags but not where it matters most, at a vendor.
13. **`tooltip:GetItem()` returns a link on all of them.** *Symptom if wrong:*
    silence on the tooltips that do not.
14. **The stamp survives a tooltip that is re-Set without being cleared.**
    *Symptom if wrong:* duplicated Vault/Alts lines stacking up on one hover.

## Framing

20. **`Textures/BankStone.png` loads and tiles at 256.** The client takes PNG
    textures — the rest of the suite ships them — and the tile is seamless by
    construction. *Symptom if wrong:* the bank style draws with no background
    at all. (It replaced `Interface\BankFrame\Bank-Background`, which is the
    *modern* bank's dark tile and never was this window's stone — see D38.)
21. **`Interface\DialogFrame\UI-DialogBox-Header` is 256x64 with the title
    sitting ~14px below its top.** *Symptom if wrong:* the title floats off the
    plate or is clipped by it.
22. **`Interface\BankFrame\Bank-Parts` still carries `Bank-Slot-BG` at the
    TexCoords `BankFrame.xml` gives it**, and stretches acceptably across the
    Slot Size slider — it is authored 51x50 for a 37x38 button. *Symptom if
    wrong:* every slot draws the wrong crop of that sheet, a rivet or nothing.
22a. **The regions listed in `TEMPLATE_REGIONS` are all
    `BasicFrameTemplateWithInset` draws.** Taken from this client's
    `UIPanelTemplates.xml`; each is guarded, so a name that stops existing
    costs nothing. *Symptom if wrong:* a piece of the template's steel frame
    shows through the bank dressing — the bug the list was written for (D39).
22b. **Resizing:** `GetCursorPosition()` is in screen units, so the drag
    divides by `frame:GetEffectiveScale()`, and an anchor offset against
    UIParent is in the anchored frame's own units, so `GetLeft`/`GetTop` are
    the right numbers to re-anchor with. *Symptom if wrong:* the window jumps
    or runs away from the cursor on the first drag at a non-default scale.

## Keys

18. **`Bindings.xml` is picked up from the addon folder without a TOC entry.**
    Listing it in the TOC loads it twice and the second pass silently wins.
    *Symptom if wrong:* no Commander Vault section in the key bindings list.
19. **`CommanderVault_FocusSearch` can take focus from a keypress.** *Symptom
    if wrong:* the window opens on the bound key but typing goes to the game.

## The guild bank

23. **`GUILDBANKBAGSLOTS_CHANGED` fires with the current tab's data ready**, and
    `GetCurrentGuildBankTab()` names it. *Symptom if wrong:* tabs record as
    empty, or as the previous tab's contents.
24. **`GetGuildBankTabInfo(tab)` returns `isViewable` third.** The rank check
    depends on it. *Symptom if wrong:* a tab you cannot see recorded as empty,
    and the tooltip then claiming the guild has none.
25. **`QueryGuildBankTab` moves the selected tab** (which is why the sweep
    restores it). *Symptom if wrong:* harmless — the restore is a no-op.
26. **`GetGuildBankItemLink(tab, slot)` is stable across builds** where
    `GetGuildBankItemInfo`'s tuple may not be; the link is what identity is
    read from. *Symptom if wrong:* an empty guild bank however many tabs are
    opened.

## Everything else

15. **`ITEM_SPELL_KNOWN` is the exact string the recipe tooltip uses.** The
    "recipes you already know" rule matches the line exactly. *Symptom if
    wrong:* that finding never appears even with known patterns banked.
16. **Bank containers really do read empty after `BANKFRAME_CLOSED`.** The
    module is built around it; if a future patch keeps them readable, the
    caching is merely redundant rather than wrong.
17. **The armour-class table is right about every class at 70.** `RowUsable`
    calls plate for warriors and paladins, mail for hunters and shamans,
    leather for rogues and druids, cloth for the rest. *Symptom if wrong:* the
    "gear you cannot use" finding names something you can.
