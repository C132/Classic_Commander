# Commander_Formulary — assumptions to verify in game

Everything here passes the three headless harnesses, which prove the logic and nothing about the
live client. Numbered so a test session can report against them. Most of the client surface is
shared with Commander_Tradecraft, whose A1 (skill line by name), A3/A4/A5 (secure `/cast`, `/use`,
`/click`) and A6 (click edges) are verified in game as of 2026-09-17 and are not repeated here.

---

## A1 — `CRAFT_SHOW` arrives after Blizzard_CraftUI has loaded and populated the list

**Load bearing for reading what you know.** The module scans `GetNumCrafts` / `GetCraftInfo` in
its own `CRAFT_SHOW` handler, which runs after UIParent's (registered earlier) has loaded the
on-demand craft UI, then `HideUIPanel(CraftFrame)`. The `OnShow` hook on `CraftFrame` is the belt
to that brace.

Symptom if wrong: the Formulary opens but `/cfm status` says "seen in the craft window: 0" after
opening Enchanting. Test: open Enchanting, run `/cfm status`.

## A2 — `IsSpellKnown` answers for craft recipes, or the craft-window memory stands in

As Commander_Tradecraft A2. `/cfm status` prints both counts.

## A3 — A `GameTooltipTemplate` frame parented into a scroll child renders `SetHyperlink("enchant:…")`

**Load bearing for the briefing's effect text.** Auctionator and TSM embed tooltips this way. The
frame is moved to the window's strata ("HIGH") so it clips with the page. If it renders nothing,
the reagents and the learning lines below it still do.

Symptom if wrong: an empty box, or a tooltip floating outside the window. Test: select any known
recipe and look at the briefing.

## A4 — `HideUIPanel(CraftFrame)` from inside the `CRAFT_SHOW` handler does not throw

The Quest Log does the same to `QuestLogFrame` from its `OnShow` hook. Hiding runs the frame's
`OnHide`, which calls `CloseCraft()`; that is fine, because nothing here uses the craft session —
crafting goes through `/cast`.

Symptom if wrong: both windows open, or an error at open. Test: open Enchanting.

## A5 — `UICheckButtonTemplate` labels are a named child on this client

`_G["CommanderFormularyGearCheckText"]`, with `.Text` tried first.

Symptom if wrong: an unlabelled checkbox under the briefing. Cosmetic.

## A6 — `SetRotation` on a solid quad draws a diagonal (the chevrons)

The Quest Log's chevrons rely on the same thing and ship. Unverified per the suite's theming note.

## A7 — `GetItemInfo` returns sell price, class id and subclass id in positions 11–13

Used by the disenchant advice (quality 3, item level 4, sell price 11, class 12). Standard on this
client; `GetItemInfoInstant` would do for class and subclass if not.

Symptom if wrong: no disenchant lines on any tooltip. Test: hover a green.

## A8 — Auctionator's `GetAuctionPriceByItemID` answers in copper for items its scans have seen

Commander_Tradecraft relies on the same call. Without Auctionator, or before a scan, every gold
figure is simply absent — the Gold section, the Profit filter and the disenchant value lines do not
appear.
