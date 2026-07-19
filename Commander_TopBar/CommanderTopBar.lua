-- Commander Top Bar: an RTS-style resource readout along the top of the
-- screen, SC2-style: floating icons+text with no backdrop by default,
-- right-aligned to the screen edge. Optional bar styles: a dark strip, or
-- the Commander_Console rail art (flipped onto the top edge and tinted with
-- the console's own color setting, so the two always match).

local BAR_HEIGHT = 24
local SEGMENT_GAP = 26
local ICON = 18
local MAX_PLAYER_LEVEL = 70
local CONSOLE_TEXTURE = "Interface\\AddOns\\Commander_Console\\Textures\\Console3_LowProfile.png"

local bar = CreateFrame("Frame", "CommanderTopBar", UIParent)
bar:SetHeight(BAR_HEIGHT)
bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
bar:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
bar:SetFrameStrata("BACKGROUND")
bar:Hide()

local background = bar:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints()

local bottomEdge = bar:CreateTexture(nil, "BORDER")
bottomEdge:SetHeight(1)
bottomEdge:SetPoint("BOTTOMLEFT")
bottomEdge:SetPoint("BOTTOMRIGHT")
bottomEdge:SetColorTexture(1, 1, 1, 0.15)

-- Fallback tint palette; when Commander_Console is loaded its own palette
-- and the user's chosen console tint are used instead, keeping both bars
-- visually matched from a single setting.
local FALLBACK_COLORS = { STEEL = { r = 1, g = 1, b = 1 } }

local function ConsoleTint()
    local key = (CommanderConsoleDB and CommanderConsoleDB.ConsoleColor) or "STEEL"
    for _, color in ipairs(CommanderConsole_Colors or {}) do
        if color.value == key then
            return color.r, color.g, color.b
        end
    end
    local fallback = FALLBACK_COLORS[key] or FALLBACK_COLORS.STEEL
    return fallback.r, fallback.g, fallback.b
end

local function ApplyStyle()
    local style = CommanderTopBarDB.BarStyle or "NONE"
    if style == "CONSOLE" then
        -- Without Commander_Console installed the rail texture file doesn't
        -- exist and would render as nothing; fall back to the dark strip so
        -- the dropdown choice always does something visible
        local consoleInstalled = CommanderConsole_Colors ~= nil
            or (C_AddOns and pcall(C_AddOns.GetAddOnInfo, "Commander_Console"))
        if not consoleInstalled then
            style = "DARK"
        end
    end
    if style == "CONSOLE" then
        -- The console rail band (bottom 20% of the overlay art), flipped
        -- vertically so its finished border edge faces down
        background:SetTexture(CONSOLE_TEXTURE)
        background:SetTexCoord(0, 1, 1, 0.8)
        background:SetVertexColor(ConsoleTint())
        background:SetAlpha(1)
        background:Show()
        bottomEdge:Hide()
    elseif style == "DARK" then
        background:SetTexture(nil)
        background:SetTexCoord(0, 1, 0, 1)
        background:SetColorTexture(0, 0, 0, 0.55)
        background:Show()
        bottomEdge:Show()
    else -- NONE: SC2 look, readouts floating with no backdrop
        background:Hide()
        bottomEdge:Hide()
    end
end

-- Segments: single FontStrings (icons embedded via |T...|t escapes),
-- anchored right-to-left from the screen edge. Iteration order is
-- right-to-left, so on screen it reads: gold, income, supply, ammo,
-- durability, XP, coords, performance, clock.
local SEGMENT_KEYS = { "clock", "performance", "coords", "xp", "durability", "ammo", "bags", "goldrate", "gold" }
local segments = {}
for _, key in ipairs(SEGMENT_KEYS) do
    segments[key] = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
end

local function LayoutSegments()
    local previous
    local offset = CommanderTopBarDB.RightOffset or 12
    for _, key in ipairs(SEGMENT_KEYS) do
        local segment = segments[key]
        segment:ClearAllPoints()
        if segment:IsShown() then
            if previous then
                segment:SetPoint("RIGHT", previous, "LEFT", -SEGMENT_GAP, 0)
            else
                segment:SetPoint("RIGHT", bar, "RIGHT", -offset, 0)
            end
            previous = segment
        end
    end
end

local function Icon(path)
    return string.format("|T%s:%d:%d:0:0|t ", path, ICON, ICON)
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
    segment:SetText(Icon("Interface\\MoneyFrame\\UI-GoldIcon") .. FormatMoney(GetMoney()))
    segment:Show()
end

-- Session gold income, RTS-style: net earnings per hour since login
local moneyAtLogin = 0
local sessionStart = 0

local function UpdateGoldRate()
    local segment = segments.goldrate
    local elapsed = GetTime() - sessionStart
    if not CommanderTopBarDB.ShowGoldRate or elapsed < 60 then
        segment:Hide()
        return
    end
    local earnedPerHour = (GetMoney() - moneyAtLogin) / elapsed * 3600
    local goldPerHour = earnedPerHour / 10000
    local color = goldPerHour >= 0 and "|cff40ff40" or "|cffff4040"
    segment:SetFormattedText("%s%+.1fg/h|r", color, goldPerHour)
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
    segment:SetText(string.format("%s%s%d/%d|r", Icon("Interface\\Buttons\\Button-Backpack-Up"), color, used, total))
    segment:Show()
end

local function UpdateAmmo()
    local segment = segments.ammo
    if not CommanderTopBarDB.ShowAmmo then segment:Hide() return end
    -- Slot 0 is the ammo slot; count is 0/nil for classes without ammo.
    -- count < 1 (not <= 1): the last arrow is exactly when the red warning
    -- matters most
    local count = GetInventoryItemCount("player", 0)
    local texture = GetInventoryItemTexture("player", 0)
    if not count or count < 1 or not texture then
        segment:Hide()
        return
    end
    local color = (count < 200) and "|cffff4040" or "|cffffffff"
    segment:SetText(string.format("%s%s%d|r", Icon(texture), color, count))
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
    segment:SetFormattedText("%s%s%d%%|r", Icon("Interface\\Icons\\Trade_BlackSmithing"), color, percent)
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
    segment:SetText(Icon("Interface\\Icons\\Spell_Nature_EnchantArmor") .. textValue)
    segment:Show()
end

local function UpdateCoords()
    local segment = segments.coords
    if not CommanderTopBarDB.ShowCoords then segment:Hide() return end
    local shown = false
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if ok and mapID then
        local okPos, position = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
        if okPos and position and position.x and position.x > 0 then
            segment:SetFormattedText("|cffc7c7cf%.0f, %.0f|r", position.x * 100, position.y * 100)
            shown = true
        end
    end
    segment:SetShown(shown)
end

local function UpdateClock()
    local segment = segments.clock
    if not CommanderTopBarDB.ShowClock then segment:Hide() return end
    segment:SetText("|cffffffff" .. date("%H:%M") .. "|r")
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
    UpdateGoldRate()
    UpdateBags()
    UpdateAmmo()
    UpdateDurability()
    UpdateXP()
    UpdateCoords()
    UpdateClock()
    UpdatePerformance()
    LayoutSegments()
end

local ticker

local function ApplyEnabled()
    if CommanderTopBarDB.EnableTopBar then
        ApplyStyle()
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
local session
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Rate counters survive /reload: resume the income session where
        -- it left off instead of restarting both meters from zero
        local fresh
        session, fresh = Commander.RestoreSession(CommanderTopBarDB, {
            startEpoch = time(),
            moneyAtLogin = GetMoney(),
            xpStartEpoch = time(),
            xpGained = 0,
        })
        if fresh then
            session.startEpoch = time()
            session.moneyAtLogin = GetMoney()
            session.xpStartEpoch = time()
            session.xpGained = 0
        end
        sessionStart = GetTime() - (time() - session.startEpoch)
        moneyAtLogin = session.moneyAtLogin
        xpSessionStart = GetTime() - (time() - session.xpStartEpoch)
        xpSessionGained = session.xpGained
        -- Seed the XP watermark now, or the first gain of the session
        -- (e.g. a saved quest turn-in) would be silently uncounted
        events.lastXP = UnitXP("player") or 0
        Commander.AddListener(COMMANDER_TOPBAR_EVENTS.UPDATE, ApplyEnabled)
        -- Re-tint live when the console's color setting changes, so the
        -- CONSOLE style always matches the lower console
        if COMMANDER_CONSOLE_EVENTS then
            Commander.AddListener(COMMANDER_CONSOLE_EVENTS.UPDATE, ApplyStyle)
        end
        ApplyEnabled()
        loaded = true
        return
    end
    if not loaded then return end

    -- XP bookkeeping runs even while the bar is disabled, so the rate is
    -- accurate the moment it is re-enabled
    if event == "PLAYER_XP_UPDATE" then
        local current = UnitXP("player") or 0
        if not events.lastXP then events.lastXP = current end
        local delta = current - events.lastXP
        if delta > 0 then
            xpSessionGained = xpSessionGained + delta
            if session then session.xpGained = xpSessionGained end
        end
        events.lastXP = current
    elseif event == "PLAYER_LEVEL_UP" then
        -- Restart the income counter each level; carry the XP watermark over
        ResetXPRate()
        if session then
            session.xpStartEpoch = time()
            session.xpGained = 0
        end
        events.lastXP = 0
    end

    if CommanderTopBarDB.EnableTopBar then
        UpdateAll()
    end
end)
