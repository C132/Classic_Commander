# Commander Spoils — client findings (TBC Anniversary 2.5.6, build 68502)

Verified against `Gethe/wow-ui-source` branch `classic_anniversary` (HEAD reads
2.5.6/69110) and the exact-build GlobalStrings from wago.tools. Anything not
verified is marked UNVERIFIED and must not be built on.

## 1. The API rename wave — write against `C_*`, never the globals

On 2.5.6 a large set of globals exist **only** inside `Blizzard_Deprecated*`
addons, every one of which opens with:

```lua
if not GetCVarBool("loadDeprecationFallbacks") then return end
```

If a user flips that CVar off, they are all `nil`. Affected and relevant here:
`GetItemInfo`, `GetItemInfoInstant`, `GetItemCount`, `GetItemQualityColor`,
`GetCoinTextureString`, `GetCoinText`, `ChatFrame_AddMessageEventFilter`,
`ChatFrame_RemoveMessageEventFilter`, `ChatFrame_RemoveMessageGroup`,
`GetLootMethod`, `SetLootMethod`.

Correct forms:

| Instead of | Use |
| --- | --- |
| `GetItemInfo` / `GetItemInfoInstant` / `GetItemCount` | `C_Item.*` (tuple-identical) |
| `GetContainerItemInfo` | `C_Container.GetContainerItemInfo` → **single table**, no global shim exists at all |
| `GetCoinTextureString(amount, height)` | `C_CurrencyInfo.GetCoinTextureString` |
| `GetLootMethod()` | `C_PartyInfo.GetLootMethod()` → `method (Enum.LootMethod), masterLootPartyID, masterLooterRaidID` |
| `ChatFrame_AddMessageEventFilter` | `ChatFrameUtil.AddMessageEventFilter(event, fn)` |
| `ChatFrame_RemoveMessageEventFilter` | `ChatFrameUtil.RemoveMessageEventFilter(event, fn)` |
| `ChatFrame_RemoveMessageGroup(frame, g)` | `chatFrame:RemoveMessageGroup(g)` |

The loot slot/roll functions themselves (`GetNumLootItems`, `GetLootSlotInfo`,
`LootSlot`, `RollOnLoot`, …) are **native globals**, not shims. `C_Loot` has
exactly one member: `C_Loot.IsLegacyLootModeEnabled()`.

## 2. Events that exist here (payloads from the client's own generated docs)

| Event | Payload |
| --- | --- |
| `LOOT_READY` | `autoloot` |
| `LOOT_OPENED` | `autoLoot` |
| `LOOT_SLOT_CLEARED` | `lootSlot` |
| `LOOT_SLOT_CHANGED` | `lootSlot` |
| `LOOT_CLOSED` | — |
| `LOOT_BIND_CONFIRM` | `lootSlot` |
| `LOOT_ITEM_AVAILABLE` | `itemTooltip, lootHandle` |
| `LOOT_ROLLS_COMPLETE` | `lootHandle` |
| `START_LOOT_ROLL` | `rollID, rollTime (**ms**), lootHandle` |
| `CANCEL_LOOT_ROLL` | `rollID` |
| `CONFIRM_LOOT_ROLL` | `rollID, rollType, confirmReason` (**a format string**) |
| `LOOT_ITEM_ROLL_WON` | `itemLink, rollQuantity, rollType, roll, upgraded` |
| `OPEN_MASTER_LOOT_LIST` / `UPDATE_MASTER_LOOT_LIST` | — |
| `LOOT_HISTORY_FULL_UPDATE` / `_ROLL_COMPLETE` | — |
| `LOOT_HISTORY_ROLL_CHANGED` | `historyIndex, playerIndex` |
| `LOOT_HISTORY_AUTO_SHOW` | `rollID, isMasterLoot` |
| `ITEM_PUSH` | `bagSlot (bag BUTTON id, 0 = backpack), iconFileID` |
| `CHAT_MSG_LOOT` / `_MONEY` / `_CURRENCY` | the standard 17-arg chat payload |
| `PLAYER_MONEY`, `BAG_UPDATE(bagID)`, `BAG_UPDATE_DELAYED`, `ITEM_LOCKED/UNLOCKED` | — |
| `GET_ITEM_INFO_RECEIVED` | `itemID, success` |
| `UNIT_LOOT` | `unitGUID, hasLoot` |
| `PARTY_LOOT_METHOD_CHANGED` | — |

**Absent on 2.5.6:** `ENCOUNTER_LOOT_RECEIVED` (does not exist).
`CONFIRM_DISENCHANT_ROLL` has a handler body in UIParent but is registered
nowhere and is missing from the API docs — dead. `GetNumRaidMembers` is gone
(removed in 5.0.4) — use `GetNumGroupMembers`.

**`GetLootSourceInfo(lootSlot)` DOES exist here** (second-pass verification
against `Ketho/BlizzardInterfaceResources` branch `classic_anniversary`
`GlobalAPI.lua`, and `0xF` in the wiki's per-flavor compat table). FrameXML
never calls it, which is why it looked absent. It returns variable-length
GUID/quantity pairs — `guid1, quantity1, guid2, quantity2, …` — where the GUID
may be a Creature, a GameObject (ore veins, herb nodes) or an Item (lockboxes).
Idiom: `local s = {GetLootSourceInfo(i)}; for j = 1, #s, 2 do … end`. This is
exact per-slot source attribution and it beats the `UnitName("target")`
heuristic on every AoE-looted pile. Still `pcall`-probe it once and memoize the
answer, since FrameXML exercises no code path through it.

**Loot toasts are dead here.** `AlertFrameMixin:OnLoad` registers only
`ACHIEVEMENT_EARNED`, `STORE_PRODUCT_DELIVERED`, `NEW_TOY_ADDED`,
`CHALLENGE_MODE_COMPLETED_REWARDS`. `LootAlertSystem` exists but nothing feeds
it — there is nothing to suppress.

## 3. Roll mechanics

`GetLootRollItemInfo(rollID)` → `texture, name, count, quality, bindOnPickUp,
canNeed, canGreed, canDisenchant, reasonNeed, reasonGreed, reasonDisenchant,
deSkillRequired`. A false `canNeed`/`canGreed` pairs with an integer index into
`_G["LOOT_ROLL_INELIGIBLE_REASON"..n]`.

`GetLootRollTimeLeft(rollID)` → ms. `RollOnLoot(rollID, rollType)` with
`LOOT_ROLL_TYPE_PASS=0 / NEED=1 / GREED=2 / DISENCHANT=3`.

**Disenchant rolls do not exist on TBC.** No `DisenchantButton` in any XML in
the tree, `GroupLootFrame_OnShow` reads only `canNeed`/`canGreed`, the
`DISENCHANT` GlobalString is absent from this build's table, and
`CONFIRM_DISENCHANT_ROLL` is never registered. `LOOT_ROLL_TYPE_DISENCHANT = 3`
still exists as a constant; treat it as unreachable.

`GetActiveLootRollIDs()` returns a **table** of live rollIDs — this is how a
replacement UI rebuilds pending rolls after `/reload` or a zone-in.

Other players' rolls come from `C_LootHistory`, which is live on 2.5.6
(`Classic/LootHistory.lua` loads):

```
C_LootHistory.GetNumItems()                    -> n
C_LootHistory.GetItem(i)                       -> rollID, itemLink, numPlayers, isDone, winnerIdx, isMasterLoot, isCurrency
C_LootHistory.GetPlayerInfo(i, playerIdx)      -> name, class, rollType, roll, isWinner, isMe
C_LootHistory.CanMasterLoot(i, playerIdx)      -> bool
C_LootHistory.GiveMasterLoot(i, playerIdx)
```

This is the correct source for who rolled what — not chat parsing. Chat is the
fallback for entries the server has expired (`ERR_LOOT_HISTORY_EXPIRED`).

## 4. Blizzard surfaces to suppress

None of these are secure/protected frames. Plain `:Hide()` /
`:UnregisterAllEvents()` on them is taint-free in and out of combat.

| Surface | How | Why |
| --- | --- | --- |
| `LootFrame` (classic paged, `LootButton1..4`) | `:UnregisterAllEvents()` — **never `:Hide()` while shown** | `LootFrame_OnHide` calls `CloseLoot()`, which would close the server-side session out from under us. With events off it never shows, so `OnHide` never fires. |
| `GroupLootFrame1..4` + `GroupLootContainer` | replace the plain global `GroupLootFrame_OpenNewFrame(id, rollTime)`, then hide the frames | UIParent (not the frames) handles `START_LOOT_ROLL` and calls that global. **Never** `UIParent:UnregisterEvent` — known taint vector. |
| `StaticPopupDialogs["LOOT_BIND"]`, `["CONFIRM_LOOT_ROLL"]`, `["CONFIRM_LOOT_DISTRIBUTION"]` | handle `LOOT_BIND_CONFIRM`/`CONFIRM_LOOT_ROLL` ourselves and call `StaticPopup_Hide(...)`; drive `ConfirmLootSlot`/`ConfirmLootRoll` from our own UI | plain Lua tables, not taint-relevant; hide rather than nil out so the exclusive slot frees cleanly |
| `ITEM_PUSH` flying icon | `UnregisterEvent("ITEM_PUSH")` on `MainMenuBarBackpackButton` and `CharacterBag0Slot..3Slot` | plain CheckButtons, event registration only — combat safe. Do not hide or reparent. |
| `LootHistoryFrame` | `:UnregisterAllEvents(); :Hide()` | |
| `MasterLooterFrame` | `:Hide()` (never opens once LootFrame is silenced) | |
| `BonusRollFrame` | `:UnregisterAllEvents()` — free insurance, its events never fire on TBC | |
| chat loot lines | `ChatFrameUtil.AddMessageEventFilter(e, fn)` returning `true` for `CHAT_MSG_LOOT` / `_MONEY` / `_CURRENCY` | fully reversible, touches no user state, and **filters do not affect addon event handlers** — our own registrations still fire. `chatFrame:RemoveMessageGroup("LOOT")` is destructive (writes the character's saved chat settings) — avoid. |

`ChatTypeGroup["LOOT"] = {"CHAT_MSG_LOOT"}`, `["MONEY"] = {"CHAT_MSG_MONEY"}`,
`["CURRENCY"] = {"CHAT_MSG_CURRENCY"}`. `CHAT_MSG_GUILD_ITEM_LOOTED` is in the
`GUILD` group, not `LOOT`.

`ToggleGameMenu` has an explicit `elseif LootFrame:IsShown() then LootFrame:Hide()`
escape-key fallback — irrelevant once it never shows, but it means Escape will
not reach a replacement window unless it registers `UISpecialFrames`.

## 5. Constants

```
LOOT_SLOT_NONE=0 LOOT_SLOT_ITEM=1 LOOT_SLOT_MONEY=2 LOOT_SLOT_CURRENCY=3
LOOT_ROLL_TYPE_PASS=0 NEED=1 GREED=2 DISENCHANT=3   (DE unreachable on TBC)
LOOTFRAME_NUMBUTTONS=4  NUM_GROUP_LOOT_FRAMES=4  MASTER_LOOT_THREHOLD=4 (sic)
Enum.LootMethod = {Freeforall=0, Roundrobin=1, Masterlooter=2, Group=3, Needbeforegreed=4, Personal=5}
Enum.ItemQuality = {Poor=0, Standard=1, Good=2, Rare=3, Epic=4, Legendary=5, Artifact=6, Heirloom=7}
```

`Constants.LootConsts.MasterLootQualityThreshold = 5` contradicts
`MASTER_LOOT_THREHOLD = 4`; FrameXML's own confirm gate uses the global `4`.

## 6. Chat format strings (literal enUS, this build)

```
LOOT_ITEM                = "%s receives loot: %s."
LOOT_ITEM_MULTIPLE       = "%s receives loot: %sx%d."
LOOT_ITEM_SELF           = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE  = "You receive loot: %sx%d."
LOOT_ITEM_PUSHED_SELF    = "You receive item: %s."
LOOT_ITEM_CREATED_SELF   = "You create: %s."
YOU_LOOT_MONEY           = "You loot %s"            -- no trailing period
LOOT_MONEY_SPLIT         = "Your share of the loot is %s."
CURRENCY_GAINED_MULTIPLE = "You receive currency: %s x%d."   -- SPACE before x%d
LOOT_ROLL_ROLLED_NEED    = "|HlootHistory:%d|h[Loot]|h: Need Roll - %d for %s by %s"
LOOT_ROLL_WON            = "|HlootHistory:%d|h[Loot]|h: %s won: %s"
LOOT_ROLL_ALL_PASSED     = "|HlootHistory:%d|h[Loot]|h: Everyone passed on: %s"
```

Every live roll string carries the `|HlootHistory:%d|h[Loot]|h: ` prefix.
`LOOT_ROLL_ROLLED_*` argument order is **roll, item, player**.

Pattern conversion rules that actually matter: escape every Lua magic char
except `%` first (the `[` `]` in the lootHistory prefix bite); handle positional
`%1$s` specifiers (deDE/frFR/ruRU reorder these); use non-greedy `(.-)` anchored
`^…$` for `%s` — greedy `(.+)` mis-splits `LOOT_ITEM_MULTIPLE` on item names
containing `x`; test longest variant first (`…_SELF_MULTIPLE` before `…_SELF`).
For item identity re-derive from the captured link via
`C_Item.GetItemInfoInstant`, never trust the captured display name.

## 7. Gotchas

1. `GetLootSlotInfo` returns a nil name/texture for uncached items, and its
   **quality (return 5) can be nil** — `ITEM_QUALITY_COLORS[nil]` errors.
   Blizzard does not guard this; we must. Resolve via
   `GetLootSlotLink` → `C_Item.GetItemInfoInstant` →
   `C_Item.RequestLoadItemDataByID` and refresh on `GET_ITEM_INFO_RECEIVED`.
2. `GetLootSlotInfo`'s 4th return is **`currencyID`, not itemID**, despite
   UIParent naming it `itemID`. Gate on
   `GetLootSlotType(slot) == LOOT_SLOT_CURRENCY` and re-derive through
   `CurrencyContainerUtil.GetCurrencyContainerInfo`.
3. Loot slot indices are **not compacted** on `LOOT_SLOT_CLEARED` —
   `GetNumLootItems()` does not shrink. Key rows by slot index and test
   `LootSlotHasItem(slot)`.
4. Build the slot model on `LOOT_READY`, present on `LOOT_OPENED` — that buys a
   frame of cache warm-up.
5. Autoloot is a **modified click** (`IsModifiedClick("AUTOLOOTTOGGLE")`,
   default SHIFT) that *inverts* `autoLootDefault`. Don't reimplement the
   polarity; trust the `autoLoot` bool the server sends with `LOOT_OPENED`.
6. Range/facing failures never reach `LOOT_OPENED`; they arrive as
   `UI_ERROR_MESSAGE` with `ERR_LOOT_TOO_FAR` / `ERR_LOOT_BAD_FACING` /
   `ERR_LOOT_LOCKED` / `ERR_LOOT_DIDNT_KILL`.
7. Master-loot candidate indices are **sparse** — probe `1..MAX_RAID_MEMBERS`
   (40); the index passed to `GiveMasterLoot(slot, i)` is the raw probe index,
   not a position in your sorted list. Candidates are per-slot; refresh on
   `UPDATE_MASTER_LOOT_LIST`.
8. `ITEM_PUSH`'s `bagSlot` is the bag *button* id (backpack = 0), not a
   `C_Container` bag index.
9. `ITEM_LOCKED`'s `slotIndex` is nilable — bare `bagOrSlotIndex` means an
   equipment slot.
10. `BAG_UPDATE_DELAYED` is a coalesced `UniqueEvent`; use it as the single
    "bags settled" tick after a loot burst instead of reacting to every
    `BAG_UPDATE`.

## 8. CVars

Verified in source: `lootUnderMouse`, `autoLootDefault`, `autoOpenLootHistory`,
`loadDeprecationFallbacks`. UNVERIFIED for 2.5.6 (present in Classic Era's
list): `autoLootRate`, `showLootSpam` — probe with `GetCVar()` before use.

## 9. Suite collision map

Three modules already parse `CHAT_MSG_LOOT` with near-identical regexes:
`Commander_Spoils`, `Commander_Economy` (`CommanderEconomy.lua:735`),
`Commander_Objectives` (`CommanderObjectives.lua:487`). Spoils becomes the
single authoritative parser and publishes `COMMANDER_SPOILS_LOOT`; the others
can subscribe rather than drift.

Spoils must **not** re-implement, because a sibling owns it:

| Owned by | Domain |
| --- | --- |
| Commander_Quartermaster | account-wide bag/bank/mail ledger, item-count tooltip lines, watchlist targets |
| Commander_Logistics | junk vendoring + repair on `MERCHANT_SHOW` (a second sell loop races item locks) |
| Commander_Bags | bag button coloring, bag frame positions, the cursor-swap sort engine |
| Commander_Economy | session gold ledger, loot vendor-value totals, best-find |
| Commander_TopBar / Commander_Adjutant | bag free-slot readouts |

Read-only globals worth consuming (soft-probe, never hard-depend):
`CommanderQuartermaster_GetWatchTarget/_SetWatchTarget/_Toggle/_ListCharacters`,
`CommanderQuartermasterLedger`, `CommanderBags_SortBags()`.

Use `BAG_UPDATE_DELAYED`, never raw `BAG_UPDATE` — Inventory and Bags already
take the raw event, and a loot burst is the suite's worst CPU case.
