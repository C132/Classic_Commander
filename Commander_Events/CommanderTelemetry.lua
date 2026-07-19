-- Commander Telemetry: instrumentation and a live profiling viewer for the
-- whole suite. Two layers:
--
--  * Always-on dispatch metrics. Commander.Notify and Commander.AddListener
--    are wrapped here — this file loads inside Commander_Events, before any
--    module addon, so every listener registration and every dispatch in the
--    suite is counted and timed (debugprofilestop, sub-ms). The overhead is
--    one clock pair and a table bump per dispatch.
--
--  * Viewer-gated sampling. While the telemetry window is open, a 2-second
--    ticker snapshots per-addon memory (UpdateAddOnMemoryUsage) and — when
--    the scriptProfile CVar is enabled — per-addon CPU. Closed, the suite
--    pays nothing.
--
-- Open with /ctelemetry (or the Telemetry button on the Commander page).
-- CPU profiling needs the scriptProfile CVar plus a /reload; the toggle
-- button in the window handles the CVar and tells you when to reload.

local REFRESH_INTERVAL = 2

Commander.Telemetry = {}

-- ---------------------------------------------------------------------------
-- Dispatch metrics: wrap the hub bus
-- ---------------------------------------------------------------------------
local eventStats = {}
local listenerCounts = {}

local function StatFor(event)
    local s = eventStats[event]
    if not s then
        s = { count = 0, ms = 0, maxMs = 0 }
        eventStats[event] = s
    end
    return s
end

local originalNotify = Commander.Notify
function Commander.Notify(event, ...)
    local t0 = debugprofilestop and debugprofilestop() or 0
    originalNotify(event, ...)
    local ms = debugprofilestop and (debugprofilestop() - t0) or 0
    local s = StatFor(event)
    s.count = s.count + 1
    s.ms = s.ms + ms
    if ms > s.maxMs then s.maxMs = ms end
end

local originalAddListener = Commander.AddListener
function Commander.AddListener(event, fn)
    listenerCounts[event] = (listenerCounts[event] or 0) + 1
    return originalAddListener(event, fn)
end

function Commander.Telemetry.ResetStats()
    wipe(eventStats)
    if ResetCPUUsage then
        pcall(ResetCPUUsage)
    end
end

-- ---------------------------------------------------------------------------
-- Sampling
-- ---------------------------------------------------------------------------
local function ProfilingOn()
    return GetCVar and GetCVar("scriptProfile") == "1"
end

local function SuiteAddons()
    local list = {}
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if type(name) == "string" and name:find("^Commander_")
            and C_AddOns.IsAddOnLoaded(name) then
            list[#list + 1] = name
        end
    end
    return list
end

-- baseline[name] = { mem = KB, at = GetTime() } — reset each time the
-- window opens, so the drift column reads "since opened"
local baseline = {}
local lastCPU = {}
local lastCPUAt

local function Sample()
    UpdateAddOnMemoryUsage()
    local profiling = ProfilingOn()
    if profiling and UpdateAddOnCPUUsage then
        UpdateAddOnCPUUsage()
    end
    local now = GetTime()
    local rows = {}
    for _, name in ipairs(SuiteAddons()) do
        local mem = GetAddOnMemoryUsage(name) or 0
        if not baseline[name] then
            baseline[name] = { mem = mem, at = now }
        end
        local elapsed = now - baseline[name].at
        local drift = elapsed > 0 and ((mem - baseline[name].mem) / elapsed) * 60 or 0
        local cpuRate
        if profiling and GetAddOnCPUUsage then
            local total = GetAddOnCPUUsage(name) or 0
            if lastCPU[name] and lastCPUAt and now > lastCPUAt then
                cpuRate = (total - lastCPU[name]) / (now - lastCPUAt)
            end
            lastCPU[name] = total
        end
        rows[#rows + 1] = { name = name, mem = mem, drift = drift, cpuRate = cpuRate }
    end
    lastCPUAt = now
    table.sort(rows, function(a, b) return a.mem > b.mem end)
    return rows, profiling
end

local function TopEvents(limit)
    local list = {}
    for event, s in pairs(eventStats) do
        list[#list + 1] = {
            event = event, count = s.count,
            avgMs = s.count > 0 and (s.ms / s.count) or 0,
            maxMs = s.maxMs,
            listeners = listenerCounts[event] or 0,
        }
    end
    table.sort(list, function(a, b) return a.count > b.count end)
    while #list > limit do
        table.remove(list)
    end
    return list
end

local function CountFrames()
    if not EnumerateFrames then return 0 end
    local count, frame = 0, EnumerateFrames()
    while frame do
        count = count + 1
        frame = EnumerateFrames(frame)
    end
    return count
end

-- ---------------------------------------------------------------------------
-- Viewer window
-- ---------------------------------------------------------------------------
local MODULE_ROWS_HEIGHT = 190
local EVENT_ROWS = 6
local ROW_H = 15

local window = CreateFrame("Frame", "CommanderTelemetryFrame", UIParent, "BackdropTemplate")
window:SetSize(560, 470)
window:SetPoint("CENTER")
window:SetFrameStrata("DIALOG")
window:SetMovable(true)
window:EnableMouse(true)
window:RegisterForDrag("LeftButton")
window:SetScript("OnDragStart", function(self) self:StartMoving() end)
window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
window:SetClampedToScreen(true)
window:Hide()
Commander.UI.ApplyStyleBackdrop(window, "DARK")
if UISpecialFrames then
    table.insert(UISpecialFrames, "CommanderTelemetryFrame")
end

local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", 12, -10)
title:SetText("Commander Telemetry")

local closeButton = CreateFrame("Button", nil, window, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", 2, 2)

local summary = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
summary:SetJustifyH("LEFT")

-- Column headers
local COLS = {
    { label = "Module", x = 12, justify = "LEFT" },
    { label = "Memory", x = 330, justify = "RIGHT" },
    { label = "Drift/min", x = 420, justify = "RIGHT" },
    { label = "CPU ms/s", x = 540, justify = "RIGHT" },
}
local headerY = -52
for _, col in ipairs(COLS) do
    local h = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if col.justify == "LEFT" then
        h:SetPoint("TOPLEFT", col.x, headerY)
    else
        h:SetPoint("TOPRIGHT", window, "TOPLEFT", col.x, headerY)
    end
    h:SetText(col.label)
end

-- Scrolling module list
local scroll = CreateFrame("ScrollFrame", "CommanderTelemetryScroll", window, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 12, headerY - 16)
scroll:SetPoint("RIGHT", window, "RIGHT", -30, 0)
scroll:SetHeight(MODULE_ROWS_HEIGHT)

local listContent = CreateFrame("Frame", nil, scroll)
listContent:SetSize(500, 10)
scroll:SetScrollChild(listContent)

local moduleRows = {}
local function AcquireModuleRow(index)
    local row = moduleRows[index]
    if row then return row end
    row = {}
    for c, col in ipairs(COLS) do
        local text = listContent:CreateFontString(nil, "OVERLAY",
            c == 1 and "GameFontHighlightSmall" or "GameFontDisableSmall")
        local y = -(index - 1) * ROW_H
        if col.justify == "LEFT" then
            text:SetPoint("TOPLEFT", col.x - 12, y)
        else
            text:SetPoint("TOPRIGHT", listContent, "TOPLEFT", col.x - 12, y)
        end
        row[c] = text
    end
    moduleRows[index] = row
    return row
end

-- Event traffic section
local eventsHeader = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
eventsHeader:SetPoint("TOPLEFT", 12, headerY - 16 - MODULE_ROWS_HEIGHT - 12)
eventsHeader:SetText("Event Traffic (count · listeners · avg ms · max ms)")

local eventRows = {}
for i = 1, EVENT_ROWS do
    local text = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    text:SetPoint("TOPLEFT", eventsHeader, "BOTTOMLEFT", 0, -4 - (i - 1) * ROW_H)
    text:SetJustifyH("LEFT")
    eventRows[i] = text
end

-- Footer buttons
local profileButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
profileButton:SetSize(170, 22)
profileButton:SetPoint("BOTTOMLEFT", 12, 10)

local resetButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
resetButton:SetSize(110, 22)
resetButton:SetPoint("LEFT", profileButton, "RIGHT", 8, 0)
resetButton:SetText("Reset Stats")

local profileHint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
profileHint:SetPoint("LEFT", resetButton, "RIGHT", 10, 0)
profileHint:SetJustifyH("LEFT")

local function FormatKB(kb)
    if kb >= 1024 then
        return string.format("%.1f MB", kb / 1024)
    end
    return string.format("%.0f KB", kb)
end

local function Refresh()
    local rows, profiling = Sample()
    local totalKB = 0
    for i, data in ipairs(rows) do
        local row = AcquireModuleRow(i)
        totalKB = totalKB + data.mem
        row[1]:SetText((data.name:gsub("^Commander_", "")))
        row[2]:SetText(FormatKB(data.mem))
        local drift = data.drift or 0
        row[3]:SetText(math.abs(drift) < 0.5 and "—"
            or string.format("%+.0f KB", drift))
        row[4]:SetText(data.cpuRate and string.format("%.2f", data.cpuRate)
            or (profiling and "…" or "—"))
        for c = 1, 4 do row[c]:Show() end
    end
    for i = #rows + 1, #moduleRows do
        for c = 1, 4 do moduleRows[i][c]:Hide() end
    end
    listContent:SetHeight(math.max(#rows * ROW_H, 10))

    summary:SetText(string.format(
        "%d modules · %s total · %d UI frames · dispatch metrics since login",
        #rows, FormatKB(totalKB), CountFrames()))

    for i, e in ipairs(TopEvents(EVENT_ROWS)) do
        eventRows[i]:SetText(string.format("%s   %d · %d · %.2f · %.2f",
            e.event, e.count, e.listeners, e.avgMs, e.maxMs))
        eventRows[i]:Show()
    end
    for i = #TopEvents(EVENT_ROWS) + 1, EVENT_ROWS do
        eventRows[i]:SetText("")
    end

    if ProfilingOn() then
        profileButton:SetText("Disable CPU Profiling")
        profileHint:SetText("CPU numbers are live (scriptProfile on)")
    else
        profileButton:SetText("Enable CPU Profiling")
        profileHint:SetText("CPU column needs scriptProfile + /reload")
    end
end

profileButton:SetScript("OnClick", function()
    if ProfilingOn() then
        SetCVar("scriptProfile", "0")
        print("Commander Telemetry: CPU profiling off — /reload to stop paying its overhead")
    else
        SetCVar("scriptProfile", "1")
        print("Commander Telemetry: CPU profiling armed — /reload to start collecting CPU per addon")
    end
    Refresh()
end)

resetButton:SetScript("OnClick", function()
    Commander.Telemetry.ResetStats()
    wipe(baseline)
    wipe(lastCPU)
    lastCPUAt = nil
    Refresh()
end)

local ticker
window:SetScript("OnShow", function()
    -- Fresh baselines each open: the drift column reads "since opened"
    wipe(baseline)
    wipe(lastCPU)
    lastCPUAt = nil
    Refresh()
    if not ticker then
        ticker = C_Timer.NewTicker(REFRESH_INTERVAL, Refresh)
    end
end)
window:SetScript("OnHide", function()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end)

function CommanderTelemetry_Toggle()
    window:SetShown(not window:IsShown())
end

SLASH_COMMANDERTELEMETRY1 = "/ctelemetry"
SLASH_COMMANDERTELEMETRY2 = "/ctelem"
SlashCmdList["COMMANDERTELEMETRY"] = function()
    CommanderTelemetry_Toggle()
end
