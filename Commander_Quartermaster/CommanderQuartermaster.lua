-- Commander Quartermaster — the supply ledger.
-- A browsable database of every TBC consumable (CommanderQuartermasterData)
-- married to an account-wide inventory ledger: each character files its bags
-- as it plays, bank and mail as they are opened, and the browser reads it
-- all back with live counts on every row.

local Data = CommanderQuartermasterData
local Events = COMMANDER_QUARTERMASTER_EVENTS

local frame = CreateFrame("FRAME")
local db                      -- CommanderQuartermasterDB, bound at login
local ledger                  -- CommanderQuartermasterLedger, bound at login
local realmKey, charKey       -- this character's ledger address
local me                      -- this character's record (always exists; only
                              -- LINKED into the ledger when tracking is on)
local loaded = false
local bankOpen = false
local mailOpen = false

-- ---------------------------------------------------------------------------
-- Database index
-- ---------------------------------------------------------------------------

-- byID[itemID] = { entry = item entry, cat = category } for every item the
-- curated database knows (categories AND recommendation entries, so a
-- BoP-only recommended item still gets ledger treatment)
local byID = {}

local function BuildIndex()
    for _, cat in ipairs(Data.Categories) do
        for _, entry in ipairs(cat.items) do
            if not byID[entry.id] then
                byID[entry.id] = { entry = entry, cat = cat }
            end
        end
    end
    for _, rec in pairs(Data.Recommendations) do
        for _, spec in ipairs(rec.specs) do
            for _, pick in ipairs(spec.picks) do
                for _, e in ipairs(pick.entries) do
                    if not byID[e.id] then
                        byID[e.id] = { entry = e, cat = nil }
                    end
                end
            end
        end
    end
end

-- An item is ledger-worthy if the database knows it, or the client says it
-- is a Consumable (class 0) or Projectile (class 6)
local trackedCache = {}
local function IsTracked(itemID)
    if not itemID then return false end
    if byID[itemID] then return true end
    local cached = trackedCache[itemID]
    if cached ~= nil then return cached end
    local classID
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, _, _, cid = pcall(C_Item.GetItemInfoInstant, itemID)
        if ok then classID = cid end
    end
    local tracked = (classID == 0 or classID == 6) and true or false
    trackedCache[itemID] = tracked
    return tracked
end

-- ---------------------------------------------------------------------------
-- Ledger
-- ---------------------------------------------------------------------------

local function LinkCharacter()
    -- Create or detach this character's ledger entry per the tracking flags.
    -- `me` itself always exists so live scans (mail counts for tooltips)
    -- work even for untracked characters.
    ledger[realmKey] = ledger[realmKey] or {}
    if db.EnableQuartermaster and db.TrackThisCharacter then
        ledger[realmKey][charKey] = me
    else
        ledger[realmKey][charKey] = nil
        if next(ledger[realmKey]) == nil then
            ledger[realmKey] = nil
        end
    end
end

local function ScanContainer(bagID, into)
    local slots = (C_Container.GetContainerNumSlots(bagID)) or 0
    for slot = 1, slots do
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        local itemID = info and info.itemID
        if itemID and IsTracked(itemID) then
            into[itemID] = (into[itemID] or 0) + (info.stackCount or 1)
        end
    end
end

local function ScanBags()
    if not (db and db.EnableQuartermaster) then return end
    wipe(me.bags)
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        ScanContainer(bag, me.bags)
    end
    me.bagsAt = time()
    me.lastSeen = time()
end

local function ScanBank()
    if not (db and db.EnableQuartermaster and db.TrackBank and bankOpen) then return end
    wipe(me.bank)
    ScanContainer(BANK_CONTAINER or -1, me.bank)
    local first = (NUM_BAG_SLOTS or 4) + 1
    for bag = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do
        ScanContainer(bag, me.bank)
    end
    me.bankAt = time()
end

local function ScanMail()
    if not (db and db.EnableQuartermaster and db.TrackMail and mailOpen) then return end
    wipe(me.mail)
    local numItems = (GetInboxNumItems and GetInboxNumItems()) or 0
    for i = 1, numItems do
        for j = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
            local link = GetInboxItemLink and GetInboxItemLink(i, j)
            local itemID = link and tonumber(link:match("item:(%d+)"))
            if itemID and IsTracked(itemID) then
                -- Modern signature: name, itemID, texture, count. If the
                -- count isn't where we expect it, one is the safe floor.
                local _, r2, _, r4 = GetInboxItem(i, j)
                local count = (type(r2) == "number" and type(r4) == "number") and r4 or 1
                me.mail[itemID] = (me.mail[itemID] or 0) + count
            end
        end
    end
    me.mailAt = time()
end

-- Coalesce scan bursts (looting fires BAG_UPDATE per stack moved)
local scanQueued = false
local dirtyBags, dirtyBank, dirtyMail = false, false, false
local RefreshBrowserSoon -- forward (browser section)

local function RunQueuedScans()
    scanQueued = false
    if dirtyBags then dirtyBags = false; ScanBags() end
    if dirtyBank then dirtyBank = false; ScanBank() end
    if dirtyMail then dirtyMail = false; ScanMail() end
    Commander.Notify(Events.LEDGER)
    if RefreshBrowserSoon then RefreshBrowserSoon() end
end

local function QueueScan(bags, bank, mail)
    dirtyBags = dirtyBags or bags
    dirtyBank = dirtyBank or bank
    dirtyMail = dirtyMail or mail
    if not scanQueued then
        scanQueued = true
        C_Timer.After(0.25, RunQueuedScans)
    end
end

-- ---------------------------------------------------------------------------
-- Counts
-- ---------------------------------------------------------------------------

local function LiveCount(itemID, includeBank)
    local ok, count = pcall(C_Item.GetItemCount, itemID, includeBank)
    return (ok and count) or 0
end

-- bags, bank, mail, alts, total for one item. The current character reads
-- LIVE from the client (GetItemCount knows the bank even when closed); the
-- ledger speaks only for everyone else.
local function CountsFor(itemID)
    local bags = LiveCount(itemID, false)
    local bank = LiveCount(itemID, true) - bags
    if bank < 0 then bank = 0 end
    local mail = (me and me.mail[itemID]) or 0
    local alts = 0
    for realmName, chars in pairs(ledger) do
        if (not db.CurrentRealmOnly) or realmName == realmKey then
            for charName, rec in pairs(chars) do
                if not (realmName == realmKey and charName == charKey) then
                    alts = alts
                        + ((rec.bags and rec.bags[itemID]) or 0)
                        + ((rec.bank and rec.bank[itemID]) or 0)
                        + ((rec.mail and rec.mail[itemID]) or 0)
                end
            end
        end
    end
    return bags, bank, mail, alts, bags + bank + mail + alts
end

local function ClassColorHex(classToken)
    local color = RAID_CLASS_COLORS and classToken and RAID_CLASS_COLORS[classToken]
    return (color and color.colorStr) or "ffffffff"
end

-- Per-character holdings of one item, sorted biggest first. Allocates; call
-- on demand (tooltips), never per frame.
local function BreakdownFor(itemID)
    local rows = {}
    for realmName, chars in pairs(ledger) do
        if (not db.CurrentRealmOnly) or realmName == realmKey then
            for charName, rec in pairs(chars) do
                if not (realmName == realmKey and charName == charKey) then
                    local bags = (rec.bags and rec.bags[itemID]) or 0
                    local bank = (rec.bank and rec.bank[itemID]) or 0
                    local mail = (rec.mail and rec.mail[itemID]) or 0
                    if bags + bank + mail > 0 then
                        rows[#rows + 1] = {
                            name = charName, realm = realmName,
                            class = rec.class,
                            bags = bags, bank = bank, mail = mail,
                            total = bags + bank + mail,
                        }
                    end
                end
            end
        end
    end
    table.sort(rows, function(a, b) return a.total > b.total end)
    return rows
end

-- ---------------------------------------------------------------------------
-- Tooltip integration
-- ---------------------------------------------------------------------------

local function JoinParts(parts)
    local out
    for _, part in ipairs(parts) do
        out = out and (out .. " · " .. part) or part
    end
    return out or ""
end

local function AppendHoldings(tooltip)
    if not (loaded and db.EnableQuartermaster and db.TooltipCounts) then return end
    if not tooltip.GetItem then return end
    local ok, _, link = pcall(tooltip.GetItem, tooltip)
    if not ok or not link then return end
    local itemID = tonumber(link:match("item:(%d+)"))
    if not itemID or not IsTracked(itemID) then return end
    -- OnTooltipSetItem can fire more than once for one tooltip fill
    if tooltip._cqmItem == itemID then return end
    tooltip._cqmItem = itemID

    local bags, bank, mail, alts, total = CountsFor(itemID)
    if total == 0 then return end
    local parts = {}
    if bags > 0 then parts[#parts + 1] = ("bags %d"):format(bags) end
    if bank > 0 then parts[#parts + 1] = ("bank %d"):format(bank) end
    if mail > 0 then parts[#parts + 1] = ("mail %d"):format(mail) end
    if alts > 0 then parts[#parts + 1] = ("alts %d"):format(alts) end
    tooltip:AddLine(("|cff33ff99Quartermaster:|r %d  |cffaaaaaa(%s)|r"):format(total, JoinParts(parts)))
    if db.TooltipBreakdown and alts > 0 then
        local rows = BreakdownFor(itemID)
        for i = 1, math.min(#rows, 8) do
            local row = rows[i]
            local where = {}
            if row.bags > 0 then where[#where + 1] = ("bags %d"):format(row.bags) end
            if row.bank > 0 then where[#where + 1] = ("bank %d"):format(row.bank) end
            if row.mail > 0 then where[#where + 1] = ("mail %d"):format(row.mail) end
            tooltip:AddLine(("  |c%s%s|r %d  |cff777777%s|r"):format(
                ClassColorHex(row.class), row.name, row.total, JoinParts(where)))
        end
        if #rows > 8 then
            tooltip:AddLine(("  |cff777777…and %d more|r"):format(#rows - 8))
        end
    end
    tooltip:Show()
end

local function ClearTooltipStamp(tooltip)
    tooltip._cqmItem = nil
end

local function HookTooltip(tooltip)
    if not (tooltip and tooltip.HookScript) then return end
    pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", ClearTooltipStamp)
end

local function InstallTooltipHooks()
    -- Retail-style path first; the classic HookScript pair as fallback.
    -- Both are guarded: the hook is a nicety, never worth an error.
    local usedProcessor = false
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        local ok = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tooltip)
            if tooltip == GameTooltip or tooltip == ItemRefTooltip then
                AppendHoldings(tooltip)
            end
        end)
        usedProcessor = ok
    end
    if not usedProcessor then
        if GameTooltip and GameTooltip.HookScript then
            pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", AppendHoldings)
        end
        if ItemRefTooltip and ItemRefTooltip.HookScript then
            pcall(ItemRefTooltip.HookScript, ItemRefTooltip, "OnTooltipSetItem", AppendHoldings)
        end
    end
    HookTooltip(GameTooltip)
    HookTooltip(ItemRefTooltip)
end

-- ---------------------------------------------------------------------------
-- Browser window
-- ---------------------------------------------------------------------------

local FRAME_W, FRAME_H = 800, 560
local SIDEBAR_W = 190
local ROW_H, VISIBLE_ROWS = 30, 15
local SIDEBAR_ROW_H = 22
local MAX_SIDEBAR_ROWS = 20

-- Count column left edges within a row (right-aligned, 40 wide each)
local COL_W = 40
local COL_TOTAL, COL_ALTS, COL_BANK, COL_BAGS = -44, -90, -136, -182

local browser            -- the window frame, created lazily
local sidebarButtons = {}
local listRows = {}
local displayList = {}
local offset = 0
local searchText = ""
local updatingSlider = false
local refreshQueued = false

local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local SOURCE_COLORS = {
    AH = "ffffd100", VENDOR = "ffffffff", CREATED = "ff69ccf0",
    QUEST = "ffdcc95a", DROP = "ffff8040", BOP = "ffff4040", SEASONAL = "ff40cc40",
}

local ROLE_TAGS = {
    TANK = "|cff6699ffTank|r", HEALER = "|cff40cc40Heal|r",
    MELEE = "|cffff6060Melee|r", CASTER = "|cffcc66ffCaster|r", RANGED = "|cffff9933Ranged|r",
}

local function PlayerClassToken()
    local _, token = UnitClass("player")
    return token
end

local function CurrentClass()
    local token = db.BrowserClass
    if not (token and Data.Recommendations[token]) then
        token = PlayerClassToken()
    end
    if not (token and Data.Recommendations[token]) then
        for _, t in ipairs(CLASS_ORDER) do
            if Data.Recommendations[t] then return t end
        end
    end
    return token
end

local function CurrentSpec()
    local rec = Data.Recommendations[CurrentClass()]
    if not rec then return nil end
    for _, spec in ipairs(rec.specs) do
        if spec.key == db.BrowserSpec then return spec end
    end
    return rec.specs[1]
end

local function CategoryByKey(key)
    for _, cat in ipairs(Data.Categories) do
        if cat.key == key then return cat end
    end
end

local function ItemName(id, fallback)
    local ok, name, _, quality = pcall(C_Item.GetItemInfo, id)
    if ok and name then
        local color = ITEM_QUALITY_COLORS and quality and ITEM_QUALITY_COLORS[quality]
        if color and color.hex then
            return color.hex .. name .. "|r", true
        end
        return name, true
    end
    return fallback or ("item:" .. tostring(id)), false
end

local function ItemIcon(id)
    local ok, icon = pcall(C_Item.GetItemIconByID, id)
    return (ok and icon) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function FormatCount(n)
    if n and n > 0 then return tostring(n) end
    return "|cff444444–|r"
end

-- ------------------------------------------------------------------
-- Display list building
-- ------------------------------------------------------------------

local function PushItem(entry, cat, why)
    displayList[#displayList + 1] = { kind = "item", id = entry.id, entry = entry, cat = cat, why = why }
end

local function PushHeader(text)
    displayList[#displayList + 1] = { kind = "header", text = text }
end

local function ItemMatches(entry)
    if searchText ~= "" then
        local hay = entry.name:lower()
        if not hay:find(searchText, 1, true) then return false end
    end
    if db.OwnedOnly then
        local _, _, _, _, total = CountsFor(entry.id)
        if total == 0 then return false end
    end
    return true
end

local function BuildBrowseList()
    local searching = searchText ~= ""
    local all = searching or db.BrowserCategory == "ALL"
    if all then
        for _, cat in ipairs(Data.Categories) do
            local wrote = false
            for _, entry in ipairs(cat.items) do
                if ItemMatches(entry) then
                    if not wrote then
                        wrote = true
                        PushHeader(("|cffffd200%s|r"):format(cat.name))
                    end
                    PushItem(entry, cat)
                end
            end
        end
    else
        local cat = CategoryByKey(db.BrowserCategory) or Data.Categories[1]
        if cat then
            for _, entry in ipairs(cat.items) do
                if ItemMatches(entry) then
                    PushItem(entry, cat)
                end
            end
        end
    end
end

local function BuildLoadoutList()
    local spec = CurrentSpec()
    if not spec then
        PushHeader("|cffaaaaaaNo recommendations for this class yet.|r")
        return
    end
    for _, pick in ipairs(spec.picks) do
        local slotName = Data.SlotNames[pick.slot] or pick.slot
        if pick.note and pick.note ~= "" then
            PushHeader(("|cffffd200%s|r  |cff999999— %s|r"):format(slotName, pick.note))
        else
            PushHeader(("|cffffd200%s|r"):format(slotName))
        end
        for _, e in ipairs(pick.entries) do
            local dbEntry = byID[e.id] and byID[e.id].entry
            PushItem(dbEntry or e, byID[e.id] and byID[e.id].cat, e.why)
        end
    end
end

local function BuildList()
    wipe(displayList)
    if db.BrowserView == "LOADOUT" then
        BuildLoadoutList()
    else
        BuildBrowseList()
    end
end

-- ------------------------------------------------------------------
-- Row binding
-- ------------------------------------------------------------------

local function BindRow(row, item)
    if not item then
        row:Hide()
        return
    end
    row:Show()
    row.item = item
    if item.kind == "header" then
        row.headerFS:SetText(item.text)
        row.headerFS:Show()
        row.icon:Hide(); row.nameFS:Hide(); row.noteFS:Hide(); row.tagFS:Hide()
        row.c1:Hide(); row.c2:Hide(); row.c3:Hide(); row.c4:Hide()
        return
    end
    row.headerFS:Hide()
    row.icon:Show(); row.nameFS:Show(); row.noteFS:Show(); row.tagFS:Show()
    row.c1:Show(); row.c2:Show(); row.c3:Show(); row.c4:Show()

    local entry = item.entry
    row.icon:SetTexture(ItemIcon(item.id))
    row.nameFS:SetText(ItemName(item.id, entry.name))
    local note = item.why or entry.note or ""
    row.noteFS:SetText(note)
    local src = entry.src
    if src then
        local color = SOURCE_COLORS[src] or "ffffffff"
        local tag = (Data.SourceNames and Data.SourceNames[src]) or src
        if entry.era == "VANILLA" then
            tag = tag .. " |cff888888·V|r"
        end
        row.tagFS:SetText(("|c%s%s|r"):format(color, tag))
    else
        row.tagFS:SetText("")
    end
    local bags, bank, _, alts, total = CountsFor(item.id)
    row.c1:SetText(FormatCount(bags))
    row.c2:SetText(FormatCount(bank))
    row.c3:SetText(FormatCount(alts))
    row.c4:SetText(total > 0 and ("|cff33ff99%d|r"):format(total) or FormatCount(0))
end

local function MaxOffset()
    return math.max(0, #displayList - VISIBLE_ROWS)
end

local function RefreshList()
    if not browser then return end
    if offset > MaxOffset() then offset = MaxOffset() end
    if offset < 0 then offset = 0 end
    for i = 1, VISIBLE_ROWS do
        BindRow(listRows[i], displayList[offset + i])
    end
    updatingSlider = true
    browser.scrollbar:SetMinMaxValues(0, MaxOffset())
    browser.scrollbar:SetValue(offset)
    updatingSlider = false
    browser.scrollbar:SetShown(MaxOffset() > 0)
end

-- ------------------------------------------------------------------
-- Sidebar binding
-- ------------------------------------------------------------------

local function BindSidebarButton(btn, opts)
    btn:Show()
    btn.key = opts.key
    btn.labelFS:SetText(opts.text)
    btn.badgeFS:SetText(opts.badge or "")
    btn.selectedTex:SetShown(opts.selected or false)
    btn.onClick = opts.onClick
end

local function RefreshSidebar()
    if not browser then return end
    local used = 0
    if db.BrowserView == "LOADOUT" then
        local rec = Data.Recommendations[CurrentClass()]
        local current = CurrentSpec()
        if rec then
            for _, spec in ipairs(rec.specs) do
                used = used + 1
                if used > MAX_SIDEBAR_ROWS then break end
                BindSidebarButton(sidebarButtons[used], {
                    key = spec.key,
                    text = spec.name,
                    badge = ROLE_TAGS[spec.role] or "",
                    selected = current and current.key == spec.key,
                    onClick = function()
                        db.BrowserSpec = spec.key
                        offset = 0
                        BuildList()
                        RefreshSidebar()
                        RefreshList()
                    end,
                })
            end
        end
    else
        local function categoryButton(key, text, badge)
            used = used + 1
            if used > MAX_SIDEBAR_ROWS then return end
            BindSidebarButton(sidebarButtons[used], {
                key = key,
                text = text,
                badge = badge,
                selected = searchText == "" and db.BrowserCategory == key,
                onClick = function()
                    db.BrowserCategory = key
                    if browser.searchBox then
                        browser.searchBox:SetText("")
                    end
                    searchText = ""
                    offset = 0
                    BuildList()
                    RefreshSidebar()
                    RefreshList()
                end,
            })
        end
        categoryButton("ALL", "All Items")
        for _, cat in ipairs(Data.Categories) do
            local owned = 0
            for _, entry in ipairs(cat.items) do
                local _, _, _, _, total = CountsFor(entry.id)
                if total > 0 then owned = owned + 1 end
            end
            categoryButton(cat.key, cat.name,
                owned > 0 and ("|cff33ff99%d|r|cff666666/%d|r"):format(owned, #cat.items)
                or ("|cff666666%d|r"):format(#cat.items))
        end
    end
    for i = used + 1, #sidebarButtons do
        sidebarButtons[i]:Hide()
    end
end

local function FullRefresh()
    if not browser then return end
    BuildList()
    RefreshSidebar()
    RefreshList()
    browser.viewBrowse:SetEnabled(db.BrowserView ~= "BROWSE")
    browser.viewLoadout:SetEnabled(db.BrowserView ~= "LOADOUT")
    local loadout = db.BrowserView == "LOADOUT"
    if browser.searchBox then browser.searchBox:SetShown(not loadout) end
    if browser.ownedCheck then browser.ownedCheck:SetShown(not loadout) end
    if browser.classDrop then browser.classDrop:SetShown(loadout) end
    if browser.classDrop and loadout then
        local token = CurrentClass()
        local label = (LOCALIZED_CLASS_NAMES_MALE and token and LOCALIZED_CLASS_NAMES_MALE[token]) or token or "?"
        if UIDropDownMenu_SetText then
            UIDropDownMenu_SetText(browser.classDrop, ("|c%s%s|r"):format(ClassColorHex(token), label))
        end
    end
end

-- Coalesced refresh for scan/iteminfo bursts while the browser is open
local function RunQueuedRefresh()
    refreshQueued = false
    if browser and browser:IsShown() then
        FullRefresh()
    end
end

RefreshBrowserSoon = function()
    if not (browser and browser:IsShown()) then return end
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.1, RunQueuedRefresh)
end

-- ------------------------------------------------------------------
-- Window construction
-- ------------------------------------------------------------------

local function ApplyFraming()
    if not browser then return end
    local style = db.BrowserStyle or "WINDOW"
    local windowArt = style == "WINDOW"
    if browser.NineSlice then browser.NineSlice:SetShown(windowArt) end
    if browser.Bg then browser.Bg:SetShown(windowArt) end
    if browser.TitleBg then browser.TitleBg:SetShown(windowArt) end
    if browser.TitleText then browser.TitleText:SetShown(windowArt) end
    if browser.CloseButton then browser.CloseButton:SetShown(windowArt) end
    if browser.Inset then browser.Inset:SetShown(windowArt) end
    Commander.UI.ApplyStyleBackdrop(browser, windowArt and "NONE" or style)
end

local function ApplyPosition()
    if not browser then return end
    local scale = db.BrowserScale or 1
    browser:SetScale(scale)
    browser:ClearAllPoints()
    local pos = db.BrowserPos
    if pos and pos.point then
        -- Saved in screen space; divide the scale back out (suite convention)
        browser:SetPoint(pos.point, UIParent, pos.point, (pos.x or 0) / scale, (pos.y or 0) / scale)
    else
        browser:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    end
end

local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_H))
    row:SetPoint("RIGHT", parent, "RIGHT", -14, 0)

    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.stripe:SetVertexColor(1, 1, 1, index % 2 == 0 and 0.03 or 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.nameFS = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.nameFS:SetPoint("LEFT", row, "LEFT", 30, 0)
    row.nameFS:SetWidth(170)
    row.nameFS:SetJustifyH("LEFT")
    row.nameFS:SetWordWrap(false)

    row.noteFS = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.noteFS:SetPoint("LEFT", row, "LEFT", 204, 0)
    row.noteFS:SetPoint("RIGHT", row, "RIGHT", COL_BAGS - COL_W - 12, 0)
    row.noteFS:SetJustifyH("LEFT")
    row.noteFS:SetWordWrap(false)
    row.noteFS:SetTextColor(0.66, 0.66, 0.66)

    row.tagFS = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.tagFS:SetPoint("RIGHT", row, "RIGHT", COL_BAGS - COL_W - 14, 0)
    row.tagFS:SetJustifyH("RIGHT")

    local function CountColumn(x)
        local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("RIGHT", row, "RIGHT", x, 0)
        fs:SetWidth(COL_W)
        fs:SetJustifyH("RIGHT")
        return fs
    end
    row.c1 = CountColumn(COL_BAGS)
    row.c2 = CountColumn(COL_BANK)
    row.c3 = CountColumn(COL_ALTS)
    row.c4 = CountColumn(COL_TOTAL)

    row.headerFS = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.headerFS:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.headerFS:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.headerFS:SetJustifyH("LEFT")
    row.headerFS:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        if not (self.item and self.item.kind == "item") then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, ("item:%d"):format(self.item.id))
        if not ok then
            GameTooltip:SetText(self.item.entry.name or "?")
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnMouseUp", function(self)
        if not (self.item and self.item.kind == "item") then return end
        if IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
            local okInfo, _, link = pcall(C_Item.GetItemInfo, self.item.id)
            if okInfo and link then
                ChatEdit_InsertLink(link)
            end
        end
    end)
    return row
end

local function CreateSidebarButton(parent, index)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(SIDEBAR_ROW_H)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * SIDEBAR_ROW_H))
    btn:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    btn.selectedTex = btn:CreateTexture(nil, "BACKGROUND")
    btn.selectedTex:SetAllPoints()
    btn.selectedTex:SetTexture("Interface\\Buttons\\WHITE8X8")
    btn.selectedTex:SetVertexColor(1, 0.82, 0, 0.13)
    btn.selectedTex:Hide()

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
    highlight:SetVertexColor(1, 1, 1, 0.06)

    btn.labelFS = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    btn.labelFS:SetPoint("LEFT", btn, "LEFT", 8, 0)
    btn.labelFS:SetJustifyH("LEFT")

    btn.badgeFS = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    btn.badgeFS:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    btn.badgeFS:SetJustifyH("RIGHT")

    btn:SetScript("OnClick", function(self)
        if self.onClick then self.onClick() end
    end)
    return btn
end

local function EnsureBrowser()
    if browser then return browser end

    browser = CreateFrame("Frame", "CommanderQuartermasterFrame", UIParent, "BasicFrameTemplateWithInset")
    browser:SetSize(FRAME_W, FRAME_H)
    browser:SetFrameStrata("MEDIUM")
    browser:SetToplevel(true)
    browser:SetMovable(true)
    browser:SetClampedToScreen(true)
    browser:Hide()
    if browser.TitleText then
        browser.TitleText:SetText("Quartermaster")
    end
    if UISpecialFrames then
        table.insert(UISpecialFrames, "CommanderQuartermasterFrame")
    end

    -- Drag strip across the title bar (the window's own regions don't drag)
    local drag = CreateFrame("Frame", nil, browser)
    drag:SetPoint("TOPLEFT", browser, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", browser, "TOPRIGHT", -24, 0)
    drag:SetHeight(24)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() browser:StartMoving() end)
    drag:SetScript("OnDragStop", function()
        browser:StopMovingOrSizing()
        local point, _, _, x, y = browser:GetPoint(1)
        if point then
            local scale = browser:GetScale() or 1
            db.BrowserPos = { point = point, x = x * scale, y = y * scale }
        end
    end)

    -- Toolbar
    local toolbar = CreateFrame("Frame", nil, browser)
    toolbar:SetPoint("TOPLEFT", browser, "TOPLEFT", 10, -28)
    toolbar:SetPoint("TOPRIGHT", browser, "TOPRIGHT", -10, -28)
    toolbar:SetHeight(30)

    browser.viewBrowse = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    browser.viewBrowse:SetSize(74, 22)
    browser.viewBrowse:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
    browser.viewBrowse:SetText("Browse")
    browser.viewBrowse:SetScript("OnClick", function()
        db.BrowserView = "BROWSE"
        offset = 0
        FullRefresh()
    end)

    browser.viewLoadout = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    browser.viewLoadout:SetSize(74, 22)
    browser.viewLoadout:SetPoint("LEFT", browser.viewBrowse, "RIGHT", 4, 0)
    browser.viewLoadout:SetText("Loadout")
    browser.viewLoadout:SetScript("OnClick", function()
        db.BrowserView = "LOADOUT"
        offset = 0
        FullRefresh()
    end)

    browser.searchBox = CreateFrame("EditBox", "CommanderQuartermasterSearch", toolbar, "InputBoxTemplate")
    browser.searchBox:SetSize(160, 20)
    browser.searchBox:SetPoint("LEFT", browser.viewLoadout, "RIGHT", 16, 0)
    browser.searchBox:SetAutoFocus(false)
    browser.searchBox:SetMaxLetters(40)
    browser.searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        searchText = (self:GetText() or ""):lower()
        offset = 0
        BuildList()
        RefreshSidebar()
        RefreshList()
    end)
    browser.searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        searchText = ""
        self:ClearFocus()
        BuildList()
        RefreshSidebar()
        RefreshList()
    end)
    browser.searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local searchLabel = toolbar:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    searchLabel:SetPoint("LEFT", browser.searchBox, "LEFT", 2, 0)
    searchLabel:SetText("Search…")
    browser.searchBox:HookScript("OnTextChanged", function(self)
        searchLabel:SetShown((self:GetText() or "") == "")
    end)

    -- "Owned only" quick filter (mirrors the settings checkbox)
    browser.ownedCheck = CreateFrame("CheckButton", nil, toolbar, "InterfaceOptionsCheckButtonTemplate")
    browser.ownedCheck:SetPoint("RIGHT", toolbar, "RIGHT", -70, 0)
    browser.ownedCheck:SetSize(22, 22)
    if browser.ownedCheck.Text then
        browser.ownedCheck.Text:SetText("Owned only")
    end
    browser.ownedCheck:SetScript("OnClick", function(self)
        db.OwnedOnly = self:GetChecked() and true or false
        offset = 0
        BuildList()
        RefreshSidebar()
        RefreshList()
    end)
    browser.ownedCheck:SetScript("OnShow", function(self)
        self:SetChecked(db.OwnedOnly and true or false)
    end)

    -- Class picker (Loadout view)
    if UIDropDownMenu_Initialize then
        browser.classDrop = CreateFrame("Frame", "CommanderQuartermasterClassDrop", toolbar, "UIDropDownMenuTemplate")
        browser.classDrop:SetPoint("LEFT", browser.viewLoadout, "RIGHT", 0, -2)
        UIDropDownMenu_SetWidth(browser.classDrop, 120)
        UIDropDownMenu_Initialize(browser.classDrop, function()
            local current = CurrentClass()
            for _, token in ipairs(CLASS_ORDER) do
                if Data.Recommendations[token] then
                    local info = UIDropDownMenu_CreateInfo()
                    local label = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or token
                    info.text = ("|c%s%s|r"):format(ClassColorHex(token), label)
                    info.value = token
                    info.checked = (token == current)
                    info.func = function(button)
                        db.BrowserClass = button.value
                        db.BrowserSpec = false
                        offset = 0
                        FullRefresh()
                    end
                    UIDropDownMenu_AddButton(info)
                end
            end
        end)
    end

    -- Sidebar
    local sidebar = CreateFrame("Frame", nil, browser)
    sidebar:SetPoint("TOPLEFT", browser, "TOPLEFT", 10, -64)
    sidebar:SetSize(SIDEBAR_W, MAX_SIDEBAR_ROWS * SIDEBAR_ROW_H)
    local sidebarLine = browser:CreateTexture(nil, "ARTWORK")
    sidebarLine:SetColorTexture(1, 1, 1, 0.08)
    sidebarLine:SetWidth(1)
    sidebarLine:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 3, 0)
    sidebarLine:SetPoint("BOTTOMLEFT", browser, "BOTTOMLEFT", SIDEBAR_W + 13, 10)
    for i = 1, MAX_SIDEBAR_ROWS do
        sidebarButtons[i] = CreateSidebarButton(sidebar, i)
    end

    -- Column headers
    local listArea = CreateFrame("Frame", nil, browser)
    listArea:SetPoint("TOPLEFT", browser, "TOPLEFT", SIDEBAR_W + 18, -82)
    listArea:SetPoint("BOTTOMRIGHT", browser, "BOTTOMRIGHT", -10, 10)
    browser.listArea = listArea

    local function HeaderLabel(x, text)
        local fs = browser:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        fs:SetPoint("RIGHT", listArea, "TOPRIGHT", x - 14, 8)
        fs:SetWidth(COL_W + 4)
        fs:SetJustifyH("RIGHT")
        fs:SetText(text)
        return fs
    end
    HeaderLabel(COL_BAGS, "Bags")
    HeaderLabel(COL_BANK, "Bank")
    HeaderLabel(COL_ALTS, "Alts")
    HeaderLabel(COL_TOTAL, "Total")

    for i = 1, VISIBLE_ROWS do
        listRows[i] = CreateRow(listArea, i)
    end

    -- Hand-rolled vertical scrollbar: primitives only, no template risk
    local scrollbar = CreateFrame("Slider", nil, listArea)
    browser.scrollbar = scrollbar
    scrollbar:SetOrientation("VERTICAL")
    scrollbar:SetWidth(8)
    scrollbar:SetPoint("TOPRIGHT", listArea, "TOPRIGHT", -2, 0)
    scrollbar:SetPoint("BOTTOMRIGHT", listArea, "BOTTOMRIGHT", -2, 0)
    local track = scrollbar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetTexture("Interface\\Buttons\\WHITE8X8")
    track:SetVertexColor(0, 0, 0, 0.35)
    scrollbar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = scrollbar:GetThumbTexture()
    if thumb then
        thumb:SetSize(8, 30)
        thumb:SetVertexColor(0.55, 0.55, 0.55, 0.9)
    end
    scrollbar:SetMinMaxValues(0, 0)
    scrollbar:SetValueStep(1)
    scrollbar:SetObeyStepOnDrag(true)
    scrollbar:SetScript("OnValueChanged", function(_, value)
        if updatingSlider then return end
        offset = math.floor(value + 0.5)
        for i = 1, VISIBLE_ROWS do
            BindRow(listRows[i], displayList[offset + i])
        end
    end)

    listArea:EnableMouseWheel(true)
    listArea:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        RefreshList()
    end)

    browser:SetScript("OnShow", function()
        if browser.ownedCheck then
            browser.ownedCheck:SetChecked(db.OwnedOnly and true or false)
        end
        FullRefresh()
    end)

    -- Internal handles for the offline smoke harness
    browser._rows = listRows
    browser._sidebar = sidebarButtons
    browser._list = displayList

    ApplyFraming()
    ApplyPosition()
    return browser
end

-- ---------------------------------------------------------------------------
-- Public entry points (slash handlers live in the DB file)
-- ---------------------------------------------------------------------------

function CommanderQuartermaster_Toggle()
    if not loaded then return end
    if not db.EnableQuartermaster then
        print("Commander Quartermaster is disabled — enable it in its settings panel")
        return
    end
    EnsureBrowser()
    if browser:IsShown() then
        browser:Hide()
    else
        browser:Show()
    end
end

function CommanderQuartermaster_Scan()
    if not loaded then return end
    ScanBags()
    ScanBank()
    ScanMail()
    Commander.Notify(Events.LEDGER)
    if RefreshBrowserSoon then RefreshBrowserSoon() end
    local kinds = 0
    for _ in pairs(me.bags) do kinds = kinds + 1 end
    print(("Commander Quartermaster: rescanned — %d tracked items in bags%s%s"):format(
        kinds,
        bankOpen and ", bank updated" or "",
        mailOpen and ", mail updated" or ""))
end

function CommanderQuartermaster_Report()
    if not loaded then return end
    print("|cff33ff99Commander Quartermaster|r — holdings by category:")
    local any = false
    for _, cat in ipairs(Data.Categories) do
        local kinds, qty = 0, 0
        for _, entry in ipairs(cat.items) do
            local _, _, _, _, total = CountsFor(entry.id)
            if total > 0 then
                kinds = kinds + 1
                qty = qty + total
            end
        end
        if kinds > 0 then
            any = true
            print(("  %s: %d of %d items, %d total"):format(cat.name, kinds, #cat.items, qty))
        end
    end
    if not any then
        print("  Nothing tracked yet — play a little, open the bank, check /cqm")
    end
end

-- Panel support: the settings page's Forget Character dropdown
function CommanderQuartermaster_ListCharacters(excludeCurrent)
    local out = {}
    if not ledger then return out end
    for realmName, chars in pairs(ledger) do
        for charName, rec in pairs(chars) do
            if not (excludeCurrent and realmName == realmKey and charName == charKey) then
                out[#out + 1] = {
                    realm = realmName, name = charName,
                    class = rec.class, level = rec.level, lastSeen = rec.lastSeen,
                }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.realm ~= b.realm then return a.realm < b.realm end
        return a.name < b.name
    end)
    return out
end

function CommanderQuartermaster_ForgetCharacter(realmName, charName)
    if not (ledger and realmName and charName and ledger[realmName]) then return end
    ledger[realmName][charName] = nil
    if next(ledger[realmName]) == nil then
        ledger[realmName] = nil
    end
    Commander.Notify(Events.LEDGER)
    if RefreshBrowserSoon then RefreshBrowserSoon() end
    print(("Commander Quartermaster: forgot %s — %s"):format(charName, realmName))
end

-- ---------------------------------------------------------------------------
-- Settings application & events
-- ---------------------------------------------------------------------------

local function ApplySettings()
    if not loaded then return end
    LinkCharacter()
    if browser then
        ApplyFraming()
        ApplyPosition()
        if browser:IsShown() then
            FullRefresh()
        end
    end
end

frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        db = CommanderQuartermasterDB
        CommanderQuartermasterLedger = CommanderQuartermasterLedger or {}
        ledger = CommanderQuartermasterLedger

        realmKey = (GetRealmName and GetRealmName()) or "Unknown"
        charKey = (UnitName and UnitName("player")) or "Unknown"
        ledger[realmKey] = ledger[realmKey] or {}
        me = ledger[realmKey][charKey] or {}
        me.bags = me.bags or {}
        me.bank = me.bank or {}
        me.mail = me.mail or {}
        me.class = PlayerClassToken()
        me.level = UnitLevel and UnitLevel("player") or 0
        me.faction = UnitFactionGroup and UnitFactionGroup("player") or nil
        me.lastSeen = time()

        BuildIndex()
        loaded = true
        LinkCharacter()
        InstallTooltipHooks()

        -- BAG_UPDATE_DELAYED coalesces a whole loot burst into one event;
        -- fall back to raw BAG_UPDATE if this client refuses it (the
        -- IsEventValid guard is NOT sufficient on this engine — see the
        -- MINIMAP_PING lesson — so just try the registration)
        if not pcall(self.RegisterEvent, self, "BAG_UPDATE_DELAYED") then
            self:RegisterEvent("BAG_UPDATE")
        end
        self:RegisterEvent("BANKFRAME_OPENED")
        self:RegisterEvent("BANKFRAME_CLOSED")
        self:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
        self:RegisterEvent("MAIL_SHOW")
        self:RegisterEvent("MAIL_INBOX_UPDATE")
        self:RegisterEvent("MAIL_CLOSED")
        self:RegisterEvent("PLAYER_LEVEL_UP")
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")

        ScanBags()
        Commander.AddListener(Events.UPDATE, ApplySettings)
    elseif not loaded then
        return
    elseif event == "BAG_UPDATE_DELAYED" or event == "BAG_UPDATE" then
        QueueScan(true, bankOpen, false)
    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
        QueueScan(false, true, false)
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
    elseif event == "PLAYERBANKSLOTS_CHANGED" then
        QueueScan(false, true, false)
    elseif event == "MAIL_SHOW" then
        mailOpen = true
        QueueScan(false, false, true)
    elseif event == "MAIL_INBOX_UPDATE" then
        QueueScan(false, false, true)
    elseif event == "MAIL_CLOSED" then
        mailOpen = false
    elseif event == "PLAYER_LEVEL_UP" then
        me.level = tonumber(arg1) or me.level
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- Names/quality resolve lazily; refresh visible rows when they land
        if RefreshBrowserSoon then RefreshBrowserSoon() end
    end
end)
