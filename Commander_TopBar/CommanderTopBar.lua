-- Commander Top Bar: an RTS-style resource readout along the top of the
-- screen, SC2-style: floating icons+text with no backdrop by default,
-- right-aligned to the screen edge. Optional bar styles: a dark strip, or
-- the Commander_Console rail art (flipped onto the top edge and tinted with
-- the console's own color setting, so the two always match).
--
-- ---------------------------------------------------------------------------
-- Coordinates you can click, and where the arrow is going
-- ---------------------------------------------------------------------------
-- The coordinates readout was TomTom's coordinate block without TomTom's one
-- useful habit: clicking it. It now takes the mouse through an invisible
-- button laid over the text, and over the text only. The bar itself stays
-- mouse-free on purpose: it spans the whole top edge, and a mouse-enabled
-- strip there would swallow every camera drag that starts near the top of
-- the screen. Click marks a Commander Orders waypoint where you stand (the
-- same as /wayb), Shift-click shares where you stand with your group WITHOUT
-- adding a waypoint of your own (CommanderOrders.SharePoint), right-click
-- opens the waypoint manager. With Commander Orders missing, a click prints
-- the spot as a /way line, so the button never silently does nothing.
--
-- The optional Nav segment is the arrow's own words in the bar: the title,
-- distance and arrival time of whatever Commander Orders is pointing at, read
-- from CommanderOrders.Status() so the two can never disagree (the units, the
-- ETA switch, "in Outland" all come from Orders). It refreshes on the bar's
-- 1 s tick and shortly after Orders' CHANGED event: the arrow works out its
-- view a frame after a change, so reading inside the event would show the
-- waypoint that was just replaced.
--
-- Orders is looked up at the moment of use, every time. It can be missing,
-- switched off or still loading, and the bar must load and read the same in
-- every one of those cases.

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
-- durability, XP, waypoint, coords, performance, clock.
local SEGMENT_KEYS = { "clock", "performance", "coords", "nav", "xp", "durability", "ammo", "bags", "goldrate", "gold" }
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

-- ---------------------------------------------------------------------------
-- Commander Orders: the clickable coordinates and the Nav segment
-- ---------------------------------------------------------------------------
local NAV_ICON = "Interface\\Icons\\INV_Misc_Map_01"
local NAV_TITLE_MAX = 22             -- bytes of waypoint title in the bar
local NAV_REFRESH_DELAY = 0.2        -- after CHANGED: the arrow's view lags a frame
local HINT_R, HINT_G, HINT_B = 0.6, 0.8, 1

local here = { map = nil, x = nil, y = nil }   -- the spot the coordinates show
local hits = {}                                -- the click surfaces, by segment key
local UpdateAll                                -- assigned below

-- The Orders API, or nil when Commander Orders is not loaded
local function Orders()
    local api = CommanderOrders
    if type(api) == "table" and type(api.Add) == "function" then return api end
    return nil
end

local function Say(message)
    print("Commander Top Bar: " .. message)
end

-- Where you stand: map, x, y (0..1), or nil where the map has no position
local function PlayerPosition()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or type(mapID) ~= "number" then return nil end
    local okPos, position = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not okPos or not position then return nil end
    local x, y = position.x, position.y
    if (x == nil or y == nil) and position.GetXY then x, y = position:GetXY() end
    if type(x) ~= "number" or type(y) ~= "number" or x <= 0 or x > 1 or y < 0 or y > 1 then return nil end
    return mapID, x, y
end

local function MapName(mapID)
    if not (C_Map and C_Map.GetMapInfo and mapID) then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    return ok and type(info) == "table" and info.name or nil
end

local function WayLine(mapID, x, y)
    return string.format("/way #%d %.2f %.2f", mapID, x * 100, y * 100)
end

-- Cut to n bytes on a UTF-8 boundary, with three plain dots
local function Cut(text, n)
    if #text <= n then return text end
    local cut = n - 3
    while cut > 0 do
        local b = text:byte(cut + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end
        cut = cut - 1
    end
    return text:sub(1, cut) .. "..."
end

-- A title is somebody else's text: a stray "|" would start an escape
local function Plain(text)
    return (tostring(text or ""):gsub("|", "||"))
end

local REASONS = {
    disabled = "Commander Orders is turned off (/corder to turn it on)",
    loading = "Commander Orders is still loading",
    ["no position"] = "there is no map position here",
    ["not in a group"] = "you are not in a group, so there is nobody to share with",
}

local function Reason(why)
    return REASONS[why] or tostring(why or "unknown reason")
end

local function MarkHere()
    local api = Orders()
    if not api then
        local mapID, x, y = PlayerPosition()
        if not mapID then Say(REASONS["no position"]) return end
        Say("Commander Orders is not loaded; this spot is " .. WayLine(mapID, x, y))
        return
    end
    -- Orders reads your position itself, fresher than the 1 s readout
    local uid, why = api.Here()
    if not uid then Say("no waypoint set: " .. Reason(why)) end
end

local function ShareHere()
    local mapID, x, y = PlayerPosition()
    if not mapID then Say(REASONS["no position"]) return end
    local api = Orders()
    if not (api and api.SharePoint) then
        Say("Commander Orders is not loaded; this spot is " .. WayLine(mapID, x, y))
        return
    end
    local ok, why = api.SharePoint({ map = mapID, x = x, y = y })
    if not ok then Say("your position was not shared: " .. Reason(why)) end
end

local function OpenManager(uid)
    local api = Orders()
    if api and api.OpenManager then
        api.OpenManager(uid)
    else
        Say("Commander Orders is not loaded")
    end
end

local function Status()
    local api = Orders()
    if not (api and api.Status) then return nil end
    local st = api.Status()
    if type(st) ~= "table" then return nil end
    return st
end

-- The status line words, shared by the segment and both tooltips
local MODE_WORDS = {
    ARRIVED = "arrived",
    NOPOS = "no position here",
    NOWORLD = "no map position",
    UNIT_LOST = "not visible",
}

local function StatusWords(st)
    if st.mode == "NAV" then
        local words = st.distanceText or ""
        if st.etaText then words = words .. "  " .. st.etaText end
        return words
    end
    if st.mode == "OTHER" then return "in " .. (st.landName or "another land") end
    return MODE_WORDS[st.mode] or ""
end

local function NavText(st)
    local title = Plain(Cut(st.title or "Waypoint", NAV_TITLE_MAX))
    local words = Plain(StatusWords(st))
    local colour = st.mode == "NAV" and "|cffffffff" or (st.mode == "OTHER" and "|cffffd100" or "|cffc7c7cf")
    return string.format("%s|cffc7c7cf%s|r %s%s|r", Icon(NAV_ICON), title, colour, words)
end

local function AddStatusLines(st)
    GameTooltip:AddLine("Arrow: " .. (st.title or "Waypoint"), 1, 1, 1)
    if st.zone and st.x and st.y then
        GameTooltip:AddLine(string.format("%s %.1f, %.1f", st.zone, st.x * 100, st.y * 100), 0.8, 0.8, 0.8)
    end
    local words = StatusWords(st)
    if words ~= "" then GameTooltip:AddLine(words, 1, 0.82, 0.3) end
    if st.mode == "OTHER" and st.hopName then
        GameTooltip:AddLine("via " .. st.hopName, 0.8, 0.84, 0.9, true)
    end
end

local function CoordsTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    if here.map then
        GameTooltip:SetText(string.format("%s %.1f, %.1f", MapName(here.map) or ("Map " .. here.map),
            here.x * 100, here.y * 100), 1, 1, 1)
    else
        GameTooltip:SetText("Coordinates", 1, 1, 1)
    end
    if Orders() then
        local st = Status()
        if st then AddStatusLines(st) end
        GameTooltip:AddLine("Click: waypoint where you stand", HINT_R, HINT_G, HINT_B)
        GameTooltip:AddLine("Shift-click: share where you stand with your group", HINT_R, HINT_G, HINT_B)
        GameTooltip:AddLine("Right-click: waypoint manager", HINT_R, HINT_G, HINT_B)
    else
        GameTooltip:AddLine("Click: print this spot as a /way line", HINT_R, HINT_G, HINT_B)
        GameTooltip:AddLine("Waypoints need Commander Orders", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function NavTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Commander Orders", 1, 1, 1)
    local st = Status()
    if st then AddStatusLines(st) else GameTooltip:AddLine("No waypoint", 0.8, 0.8, 0.8) end
    GameTooltip:AddLine("Click: waypoint manager", HINT_R, HINT_G, HINT_B)
    GameTooltip:Show()
end

-- An invisible button over one segment's text; hidden with the segment
local function NewHit(key, onClick, onEnter)
    local segment = segments[key]
    local hit = CreateFrame("Button", nil, bar)
    hit:SetPoint("TOPLEFT", segment, "TOPLEFT", -4, 4)
    hit:SetPoint("BOTTOMRIGHT", segment, "BOTTOMRIGHT", 4, -4)
    hit:EnableMouse(true)
    hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    hit:SetScript("OnClick", onClick)
    hit:SetScript("OnEnter", onEnter)
    hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hit.refresh = onEnter
    hit:Hide()
    hits[key] = hit
    return hit
end

NewHit("coords", function(_, button)
    if button == "RightButton" then
        OpenManager()
    elseif IsShiftKeyDown and IsShiftKeyDown() then
        ShareHere()
    else
        MarkHere()
    end
end, CoordsTooltip)

NewHit("nav", function()
    local st = Status()
    OpenManager(st and st.uid)
end, NavTooltip)

-- A tooltip that is open over a segment follows the segment's own refresh
local function RefreshTooltips()
    if not (GameTooltip and GameTooltip.GetOwner) then return end
    local owner = GameTooltip:GetOwner()
    for _, hit in pairs(hits) do
        if owner == hit and hit:IsShown() then hit.refresh(hit) end
    end
end

local function UpdateCoords()
    local segment = segments.coords
    local mapID, x, y
    if CommanderTopBarDB.ShowCoords then mapID, x, y = PlayerPosition() end
    here.map, here.x, here.y = mapID, x, y
    if mapID then
        segment:SetFormattedText("|cffc7c7cf%.0f, %.0f|r", x * 100, y * 100)
    end
    segment:SetShown(mapID ~= nil)
    hits.coords:SetShown(mapID ~= nil)
end

local function UpdateNav()
    local segment = segments.nav
    local st = CommanderTopBarDB.ShowNav and Status() or nil
    if st then segment:SetText(NavText(st)) end
    segment:SetShown(st ~= nil)
    hits.nav:SetShown(st ~= nil)
end

-- CHANGED fires inside the change; the arrow's view settles a frame later
local navPending = false
local function OnOrdersChanged()
    if navPending or not (C_Timer and C_Timer.After) then return end
    navPending = true
    C_Timer.After(NAV_REFRESH_DELAY, function()
        navPending = false
        if CommanderTopBarDB.EnableTopBar and UpdateAll then UpdateAll() end
    end)
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

function UpdateAll()
    UpdateGold()
    UpdateGoldRate()
    UpdateBags()
    UpdateAmmo()
    UpdateDurability()
    UpdateXP()
    UpdateCoords()
    UpdateNav()
    UpdateClock()
    UpdatePerformance()
    LayoutSegments()
    RefreshTooltips()
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
        -- The Nav segment follows the arrow when a waypoint is set, moved,
        -- reached or removed, not only on the next 1 s tick
        if COMMANDER_ORDERS_EVENTS and COMMANDER_ORDERS_EVENTS.CHANGED then
            Commander.AddListener(COMMANDER_ORDERS_EVENTS.CHANGED, OnOrdersChanged)
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
