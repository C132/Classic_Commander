-- Commander Top Bar: an RTS-style resource strip across the top of the
-- screen. Right-aligned readout cluster (like an RTS resource corner):
-- gold, bag supply, durability, XP rate, and performance. All data comes
-- from cheap read-only APIs; the bar updates on relevant events plus a 1s
-- ticker for the rates.

local BAR_HEIGHT = 20
local SEGMENT_GAP = 24
local MAX_PLAYER_LEVEL = 70

local bar = CreateFrame("Frame", "CommanderTopBar", UIParent)
bar:SetHeight(BAR_HEIGHT)
bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
bar:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
bar:SetFrameStrata("BACKGROUND")
bar:Hide()

local background = bar:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints()
background:SetColorTexture(0, 0, 0, 0.55)

local bottomEdge = bar:CreateTexture(nil, "BORDER")
bottomEdge:SetHeight(1)
bottomEdge:SetPoint("BOTTOMLEFT")
bottomEdge:SetPoint("BOTTOMRIGHT")
bottomEdge:SetColorTexture(1, 1, 1, 0.15)

-- Segments are single FontStrings (icons embedded via |T...|t escapes),
-- anchored right-to-left from the screen edge
local SEGMENT_KEYS = { "performance", "xp", "durability", "bags", "gold" }
local segments = {}
for _, key in ipairs(SEGMENT_KEYS) do
    local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    segments[key] = text
end

-- Re-anchor visible segments right-to-left with even gaps
local function LayoutSegments()
    local previous
    for _, key in ipairs(SEGMENT_KEYS) do
        local segment = segments[key]
        segment:ClearAllPoints()
        if segment:IsShown() then
            if previous then
                segment:SetPoint("RIGHT", previous, "LEFT", -SEGMENT_GAP, 0)
            else
                segment:SetPoint("RIGHT", bar, "RIGHT", -12, 0)
            end
            previous = segment
        end
    end
end

local function FormatMoney(copper)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    if gold > 0 then
        return string.format("%d|cffffd700g|r %d|cffc7c7cfs|r", gold, silver)
    end
    return string.format("%d|cffc7c7cfs|r %d|cffeda55fc|r", silver, copper % 100)
end

local function UpdateGold()
    local segment = segments.gold
    if not CommanderTopBarDB.ShowGold then segment:Hide() return end
    segment:SetText("|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t " .. FormatMoney(GetMoney()))
    segment:Show()
end

local function UpdateBags()
    local segment = segments.bags
    if not CommanderTopBarDB.ShowBags then segment:Hide() return end
    local free, total = 0, 0
    for bagID = 0, 4 do
        local slots = C_Container.GetContainerNumSlots(bagID) or 0
        if slots > 0 then
            total = total + slots
            free = free + (C_Container.GetContainerNumFreeSlots(bagID) or 0)
        end
    end
    local used = total - free
    local color = (free <= 2) and "|cffff4040" or "|cffffffff"
    segment:SetText(string.format("|TInterface\\Buttons\\Button-Backpack-Up:12:12:0:0|t %s%d/%d|r", color, used, total))
    segment:Show()
end

local function UpdateDurability()
    local segment = segments.durability
    if not CommanderTopBarDB.ShowDurability then segment:Hide() return end
    local lowest = 1
    for slot = 1, 18 do
        local current, maximum = GetInventoryItemDurability(slot)
        if current and maximum and maximum > 0 then
            local ratio = current / maximum
            if ratio < lowest then lowest = ratio end
        end
    end
    local percent = math.floor(lowest * 100 + 0.5)
    local color = (percent <= 20) and "|cffff4040" or "|cffffffff"
    segment:SetFormattedText("|TInterface\\Icons\\Trade_BlackSmithing:12:12:0:0|t %s%d%%|r", color, percent)
    segment:Show()
end

-- XP/hour is measured from login (or the last level-up) like an RTS income counter
local xpSessionStart = 0
local xpSessionGained = 0

local function ResetXPRate()
    xpSessionStart = GetTime()
    xpSessionGained = 0
end

local function UpdateXP()
    local segment = segments.xp
    if not CommanderTopBarDB.ShowXP or UnitLevel("player") >= MAX_PLAYER_LEVEL then
        segment:Hide()
        return
    end
    local elapsed = GetTime() - xpSessionStart
    local perHour = (elapsed > 60 and xpSessionGained > 0) and (xpSessionGained / elapsed * 3600) or 0
    local textValue
    if perHour > 0 then
        local remaining = (UnitXPMax("player") or 0) - (UnitXP("player") or 0)
        local hoursLeft = remaining / perHour
        if hoursLeft < 1 then
            textValue = string.format("%.1fk XP/h (%dm to lvl)", perHour / 1000, math.ceil(hoursLeft * 60))
        else
            textValue = string.format("%.1fk XP/h (%.1fh to lvl)", perHour / 1000, hoursLeft)
        end
    else
        textValue = string.format("%d%% XP", math.floor((UnitXP("player") or 0) / math.max(UnitXPMax("player") or 1, 1) * 100))
    end
    segment:SetText("|TInterface\\Icons\\Spell_Nature_EnchantArmor:12:12:0:0|t " .. textValue)
    segment:Show()
end

local function UpdatePerformance()
    local segment = segments.performance
    if not CommanderTopBarDB.ShowPerformance then segment:Hide() return end
    local _, _, home = GetNetStats()
    local fps = math.floor(GetFramerate() + 0.5)
    local latencyColor = (home or 0) > 300 and "|cffff4040" or "|cffc7c7cf"
    segment:SetFormattedText("|cffc7c7cf%d fps|r %s%d ms|r", fps, latencyColor, home or 0)
    segment:Show()
end

local function UpdateAll()
    UpdateGold()
    UpdateBags()
    UpdateDurability()
    UpdateXP()
    UpdatePerformance()
    LayoutSegments()
end

local ticker

local function ApplyEnabled()
    if CommanderTopBarDB.EnableTopBar then
        bar:Show()
        UpdateAll()
        if not ticker then
            ticker = C_Timer.NewTicker(1, UpdateAll)
        end
    else
        bar:Hide()
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
events:RegisterEvent("PLAYER_XP_UPDATE")
events:RegisterEvent("PLAYER_LEVEL_UP")
local loaded = false
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        ResetXPRate()
        Commander.AddListener(COMMANDER_TOPBAR_EVENTS.UPDATE, ApplyEnabled)
        ApplyEnabled()
        loaded = true
    elseif loaded and CommanderTopBarDB.EnableTopBar then
        if event == "PLAYER_XP_UPDATE" then
            local current = UnitXP("player") or 0
            if not events.lastXP then events.lastXP = current end
            local delta = current - events.lastXP
            if delta > 0 then
                xpSessionGained = xpSessionGained + delta
            end
            events.lastXP = current
        elseif event == "PLAYER_LEVEL_UP" then
            -- Restart the income counter each level; carry the XP watermark over
            ResetXPRate()
            events.lastXP = 0
        end
        UpdateAll()
    end
end)
