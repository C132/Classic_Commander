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
--
-- A third layer keeps history: a 60-second background sampler maintains
-- per-addon session aggregates in CommanderTelemetryDB (last 20 sessions),
-- and /ctelemetry report builds a copy-paste plaintext report — memory,
-- CPU, event traffic, session history, and generated optimization
-- insights (leak suspects, hogs, chatty events, trends).

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

local metricsResetAt   -- epoch of the last mid-session stats reset

function Commander.Telemetry.ResetStats()
    wipe(eventStats)
    if ResetCPUUsage then
        pcall(ResetCPUUsage)
    end
    -- Rates must divide since-reset counts by a since-reset window — the
    -- report and viewer read this marker instead of assuming "since login"
    metricsResetAt = time()
end

-- ---------------------------------------------------------------------------
-- Sampling
-- ---------------------------------------------------------------------------
local function ProfilingOn()
    return GetCVar and GetCVar("scriptProfile") == "1"
end

-- The engine honors scriptProfile only at UI load: arming the CVar
-- mid-session changes nothing until the next /reload — GetAddOnCPUUsage
-- keeps returning zero. Load-time state is the truth about whether CPU
-- numbers are real this session; the live CVar only drives the toggle.
local profilingActive = (GetCVar and GetCVar("scriptProfile") == "1") or false

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
    local profiling = profilingActive
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
    -- 528, not 540: the scroll frame clips its child at window-x 530, so
    -- right-anchored cells past that lose their trailing digits
    { label = "CPU ms/s", x = 528, justify = "RIGHT" },
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

local reportButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
reportButton:SetSize(90, 22)
reportButton:SetPoint("LEFT", resetButton, "RIGHT", 8, 0)
reportButton:SetText("Report")

local profileHint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
profileHint:SetPoint("LEFT", reportButton, "RIGHT", 10, 0)
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
        "%d modules · %s total · %d UI frames · dispatch metrics %s",
        #rows, FormatKB(totalKB), CountFrames(),
        metricsResetAt and "since stats reset" or "since login"))

    for i, e in ipairs(TopEvents(EVENT_ROWS)) do
        eventRows[i]:SetText(string.format("%s   %d · %d · %.2f · %.2f",
            e.event, e.count, e.listeners, e.avgMs, e.maxMs))
        eventRows[i]:Show()
    end
    for i = #TopEvents(EVENT_ROWS) + 1, EVENT_ROWS do
        eventRows[i]:SetText("")
    end

    if profilingActive then
        profileButton:SetText("Disable CPU Profiling")
        profileHint:SetText("CPU numbers are live (scriptProfile on)")
    elseif ProfilingOn() then
        profileButton:SetText("Disable CPU Profiling")
        profileHint:SetText("profiling armed — /reload to start collecting")
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

-- ---------------------------------------------------------------------------
-- Historical record: a 60-second background sampler keeps per-addon session
-- aggregates in CommanderTelemetryDB.Sessions (last SESSION_CAP sessions) —
-- start/peak/last memory, CPU totals while profiling, frame counts, top
-- event traffic. The live session's record is mutated in place every tick,
-- so whenever the client next writes SavedVariables (logout, quit, /reload)
-- the freshest data reaches disk. A hard crash loses the session — the
-- client never flushes SavedVariables mid-play.
-- ---------------------------------------------------------------------------
local SAMPLE_INTERVAL = 60
local SESSION_CAP = 20

local sessionRecord

local function BackgroundSample()
    if not sessionRecord then return end
    UpdateAddOnMemoryUsage()
    local profiling = profilingActive
    if profiling and UpdateAddOnCPUUsage then
        pcall(UpdateAddOnCPUUsage)
    end
    local total = 0
    for _, name in ipairs(SuiteAddons()) do
        local mem = GetAddOnMemoryUsage(name) or 0
        total = total + mem
        local a = sessionRecord.addons[name]
        if not a then
            a = { start = mem, peak = mem, last = mem }
            sessionRecord.addons[name] = a
        end
        a.last = mem
        if mem > a.peak then a.peak = mem end
        if profiling and GetAddOnCPUUsage then
            a.cpu = GetAddOnCPUUsage(name) or a.cpu
        end
    end
    sessionRecord.totalStart = sessionRecord.totalStart or total
    if total > (sessionRecord.totalPeak or 0) then
        sessionRecord.totalPeak = total
    end
    sessionRecord.totalEnd = total
    local frames = CountFrames()
    sessionRecord.framesStart = sessionRecord.framesStart or frames
    sessionRecord.frames = frames
    sessionRecord.duration = time() - sessionRecord.startedAt
    sessionRecord.metricsSince = metricsResetAt
    sessionRecord.profiled = sessionRecord.profiled or profiling or nil
    sessionRecord.events = TopEvents(12)
end

-- Seconds covered by the event/CPU counters: login, or the last Reset
-- Stats, or the last /reload-resume — never longer than the counters
-- themselves have been running
local function MetricsWindow(record)
    local windowStart = record.metricsSince or record.startedAt or 0
    return math.max((record.startedAt or 0) + (record.duration or 0) - windowStart, 1)
end

-- ---------------------------------------------------------------------------
-- Report: plaintext, column-aligned, built for copy-paste out of the game
-- ---------------------------------------------------------------------------
local function FormatDuration(seconds)
    seconds = math.max(seconds or 0, 0)
    if seconds >= 3600 then
        return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
    elseif seconds >= 60 then
        return string.format("%dm", math.floor(seconds / 60))
    end
    return string.format("%ds", math.floor(seconds))
end

local function SortedSessionAddons(record)
    local rows = {}
    for name, a in pairs(record.addons or {}) do
        rows[#rows + 1] = {
            name = name:gsub("^Commander_", ""),
            start = a.start or 0, peak = a.peak or 0,
            last = a.last or 0, cpu = a.cpu,
        }
    end
    table.sort(rows, function(x, y) return x.last > y.last end)
    return rows
end

-- A GC probe forces a full collection and measures what each module gives
-- back — separating allocation churn (hot loops making garbage) from truly
-- retained memory. GetAddOnMemoryUsage counts uncollected garbage, so
-- without this a churny module reads as a hog.
local lastGCProbe

local function RunGCProbe()
    UpdateAddOnMemoryUsage()
    local before, per = 0, {}
    for _, name in ipairs(SuiteAddons()) do
        local mem = GetAddOnMemoryUsage(name) or 0
        per[name] = mem
        before = before + mem
    end
    collectgarbage("collect")
    UpdateAddOnMemoryUsage()
    local after, perAddon = 0, {}
    for _, name in ipairs(SuiteAddons()) do
        local mem = GetAddOnMemoryUsage(name) or 0
        after = after + mem
        local reclaimed = (per[name] or 0) - mem
        if reclaimed > 1 then
            perAddon[name:gsub("^Commander_", "")] = reclaimed
        end
    end
    lastGCProbe = {
        at = time(), before = before, after = after,
        reclaimed = before - after, perAddon = perAddon,
    }
end

local function SortedProbeRows()
    if not lastGCProbe then return {} end
    local rows = {}
    for name, kb in pairs(lastGCProbe.perAddon) do
        rows[#rows + 1] = { name = name, kb = kb }
    end
    table.sort(rows, function(x, y) return x.kb > y.kb end)
    return rows
end

-- The heuristics that turn raw numbers into "go look here" — each with the
-- threshold it tripped, so the report reads as findings, not vibes
local function GenerateInsights(record, priors)
    local insights = {}
    local minutes = math.max((record.duration or 0) / 60, 1 / 60)
    local windowSeconds = MetricsWindow(record)
    local rows = SortedSessionAddons(record)
    local total = record.totalEnd or 0

    if (record.duration or 0) >= 600 then
        for _, row in ipairs(rows) do
            local grown = row.last - row.start
            local perMin = grown / minutes
            if perMin >= 3 and grown >= 50 then
                insights[#insights + 1] = string.format(
                    "[LEAK?] %s grew %+.0f KB over %s (%.1f KB/min sustained) — look for tables that only append: session logs, uncapped ring buffers, per-event allocations.",
                    row.name, grown, FormatDuration(record.duration), perMin)
            end
        end
    else
        insights[#insights + 1] =
            "[INFO] Session under 10 minutes — drift and leak analysis needs a longer run to mean anything."
    end

    if total > 0 and rows[1] and (rows[1].last / total) > 0.25 then
        insights[#insights + 1] = string.format(
            "[HOG] %s alone holds %.0f%% of suite memory (%s of %s) — audit its caches and textures first.",
            rows[1].name, rows[1].last / total * 100, FormatKB(rows[1].last), FormatKB(total))
    end
    if total > 10240 then
        insights[#insights + 1] = string.format(
            "[HOG] Suite total %s — over the 10 MB comfort line for a UI suite on this client.", FormatKB(total))
    end

    if lastGCProbe then
        local probeRows = SortedProbeRows()
        local top = probeRows[1]
        if top and top.kb >= 256 then
            insights[#insights + 1] = string.format(
                "[CHURN] %s gave back %s at the last GC probe — a hot path is allocating every tick (per-frame string.format, fresh tables per draw); reuse buffers and skip unchanged updates.",
                top.name, FormatKB(top.kb))
        end
        if lastGCProbe.before > 0 and (lastGCProbe.reclaimed / lastGCProbe.before) >= 0.4 then
            insights[#insights + 1] = string.format(
                "[CHURN] %.0f%% of suite memory (%s) was collectible garbage, not data — the footprint problem is allocation rate, not retention.",
                lastGCProbe.reclaimed / lastGCProbe.before * 100, FormatKB(lastGCProbe.reclaimed))
        end
    else
        insights[#insights + 1] =
            "[CHURN] Run the GC Probe (report window) before chasing any [HOG] finding — memory numbers include uncollected garbage, and a churny module reads as a hog."
    end

    -- Rate-based event findings need a settled window: the login burst
    -- divided by a tiny elapsed time reads as sustained chatter
    for _, e in ipairs(record.events or {}) do
        local perMin = e.count / math.max(windowSeconds / 60, 1 / 60)
        if windowSeconds >= 300 and perMin >= 30 then
            insights[#insights + 1] = string.format(
                "[BUS] %s fires %.0f times/min across %d listeners — throttle the notifier or coalesce updates.",
                e.event, perMin, e.listeners)
        end
        if (e.maxMs or 0) >= 8 then
            insights[#insights + 1] = string.format(
                "[SLOW] %s peaked at %.1f ms for a single dispatch — a listener is doing heavy work inline; defer or chunk it.",
                e.event, e.maxMs)
        end
        if windowSeconds >= 300 and (e.avgMs or 0) >= 1 and e.count >= 50 then
            insights[#insights + 1] = string.format(
                "[SLOW] %s averages %.2f ms per dispatch over %d fires — that cost is paid on every notify.",
                e.event, e.avgMs, e.count)
        end
    end

    if record.profiled then
        local top
        for _, row in ipairs(rows) do
            if row.cpu and (not top or row.cpu > top.cpu) then top = row end
        end
        if top and (top.cpu or 0) > 0 then
            insights[#insights + 1] = string.format(
                "[CPU] %s is the top CPU consumer: %.0f ms total, %.2f ms/s averaged — check its OnUpdate throttles and event fan-in.",
                top.name, top.cpu, top.cpu / windowSeconds)
        end
    else
        insights[#insights + 1] =
            "[CPU] CPU has not been profiled this session — Enable CPU Profiling, /reload, and play a while for per-module CPU insight."
    end

    if record.frames and record.framesStart and (record.frames - record.framesStart) > 500 then
        insights[#insights + 1] = string.format(
            "[FRAMES] UI-wide frame count grew by %d since login — this counts Blizzard panels and other addons too; if it climbs steadily during ordinary play, suspect frames created per event instead of pooled.",
            record.frames - record.framesStart)
    end

    -- Trend baseline: only sessions long enough to have reached a real
    -- peak — /reload stubs would systematically drag the average down
    if #priors >= 3 and record.totalPeak then
        local sum, n = 0, 0
        for _, p in ipairs(priors) do
            if p.totalPeak and (p.duration or 0) >= 600 then
                sum = sum + p.totalPeak
                n = n + 1
            end
        end
        if n >= 3 then
            local avg = sum / n
            local delta = (record.totalPeak - avg) / avg * 100
            if math.abs(delta) >= 15 then
                insights[#insights + 1] = string.format(
                    "[TREND] Peak memory this session (%s) is %+.0f%% against your previous %d-session average (%s).",
                    FormatKB(record.totalPeak), delta, n, FormatKB(avg))
            end
        end
    end

    if #insights == 0 then
        insights[1] = "[OK] Nothing exceeds thresholds — memory flat, dispatches quick, no chatty events. The suite is healthy."
    end
    return insights
end

local function BuildReport()
    local record = sessionRecord
    if not record then
        return "No telemetry session yet — data collection starts at login."
    end
    local out = {}
    local function line(fmt, ...)
        if select("#", ...) > 0 then
            out[#out + 1] = string.format(fmt, ...)
        else
            out[#out + 1] = fmt
        end
    end
    local sessions = (CommanderTelemetryDB and CommanderTelemetryDB.Sessions) or {}
    local priors = {}
    for i = 1, #sessions do
        if sessions[i] ~= record then
            priors[#priors + 1] = sessions[i]
        end
    end
    local rows = SortedSessionAddons(record)
    local windowSeconds = MetricsWindow(record)
    local windowMinutes = math.max(windowSeconds / 60, 1 / 60)
    local windowLabel = record.metricsSince and "since stats reset" or "since login"

    line("COMMANDER TELEMETRY REPORT — %s", date("%Y-%m-%d %H:%M"))
    line("Session %s · %d modules · %s now · peak %s · %d UI frames (%+d since login)",
        FormatDuration(record.duration), #rows,
        FormatKB(record.totalEnd or 0), FormatKB(record.totalPeak or 0),
        record.frames or 0, (record.frames or 0) - (record.framesStart or 0))
    line("")

    line("== MEMORY (per module) ==")
    line("%-16s %10s %10s %12s %7s", "module", "now", "peak", "drift", "share")
    local total = record.totalEnd or 0
    for i = 1, math.min(#rows, 15) do
        local row = rows[i]
        line("%-16s %10s %10s %+9.0f KB %6.1f%%",
            row.name, FormatKB(row.last), FormatKB(row.peak),
            row.last - row.start, total > 0 and (row.last / total * 100) or 0)
    end
    if #rows > 15 then
        line("… %d more below the fold", #rows - 15)
    end
    line("note: module numbers include uncollected garbage — the GC Probe splits churn from retained")
    line("")

    line("== CHURN (GC probe) ==")
    if lastGCProbe then
        line("probe at %s: reclaimed %s of %s (%.0f%%) — collectible garbage by module:",
            date("%H:%M", lastGCProbe.at), FormatKB(lastGCProbe.reclaimed),
            FormatKB(lastGCProbe.before),
            lastGCProbe.before > 0 and (lastGCProbe.reclaimed / lastGCProbe.before * 100) or 0)
        local probeRows = SortedProbeRows()
        for i = 1, math.min(#probeRows, 10) do
            line("%-16s %10s", probeRows[i].name, FormatKB(probeRows[i].kb))
        end
        if #probeRows == 0 then
            line("nothing collectible above 1 KB — the memory shown is genuinely retained")
        end
    else
        line("no probe run yet — press GC Probe in this window (brief hitch while GC runs)")
    end
    line("")

    line("== CPU ==")
    if record.profiled then
        line("%-16s %12s %10s", "module", "total ms", "ms/s avg")
        local cpuRows = {}
        for _, row in ipairs(rows) do
            if row.cpu then cpuRows[#cpuRows + 1] = row end
        end
        table.sort(cpuRows, function(x, y) return x.cpu > y.cpu end)
        for i = 1, math.min(#cpuRows, 10) do
            local row = cpuRows[i]
            line("%-16s %12.0f %10.2f", row.name, row.cpu, row.cpu / windowSeconds)
        end
        if #cpuRows == 0 then
            line("profiling is on but no CPU samples have landed yet — give it a minute")
        end
    else
        line("not profiled this session — Enable CPU Profiling in /ctelemetry, then /reload")
    end
    line("")

    line("== EVENT TRAFFIC (%s) ==", windowLabel)
    line("%-34s %7s %6s %4s %8s %8s", "event", "count", "/min", "lst", "avg ms", "max ms")
    for _, e in ipairs(record.events or {}) do
        line("%-34s %7d %6.1f %4d %8.2f %8.2f",
            e.event, e.count, e.count / windowMinutes, e.listeners, e.avgMs or 0, e.maxMs or 0)
    end
    line("")

    line("== SESSION HISTORY (newest first) ==")
    if #priors == 0 then
        line("no prior sessions recorded yet — history builds from here")
    else
        line("%-18s %8s %10s %10s %6s", "date", "length", "peak", "end", "cpu")
        for i = #priors, math.max(#priors - 9, 1), -1 do
            local p = priors[i]
            line("%-18s %8s %10s %10s %6s",
                date("%Y-%m-%d %H:%M", p.startedAt or 0),
                FormatDuration(p.duration),
                FormatKB(p.totalPeak or 0), FormatKB(p.totalEnd or 0),
                p.profiled and "yes" or "-")
        end
    end
    line("")

    line("== INSIGHTS ==")
    for _, insight in ipairs(GenerateInsights(record, priors)) do
        line("%s", insight)
    end
    line("")
    line("Generated by Commander Telemetry · /ctelemetry report · window: /ctelemetry")
    return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- Report window: the text in a multiline edit box, ready to copy out
-- ---------------------------------------------------------------------------
local reportFrame = CreateFrame("Frame", "CommanderTelemetryReport", UIParent, "BackdropTemplate")
reportFrame:SetSize(620, 480)
reportFrame:SetPoint("CENTER", 0, 20)
reportFrame:SetFrameStrata("DIALOG")
reportFrame:SetMovable(true)
reportFrame:EnableMouse(true)
reportFrame:RegisterForDrag("LeftButton")
reportFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
reportFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
reportFrame:SetClampedToScreen(true)
reportFrame:Hide()
Commander.UI.ApplyStyleBackdrop(reportFrame, "DARK")
if UISpecialFrames then
    table.insert(UISpecialFrames, "CommanderTelemetryReport")
end

local reportTitle = reportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
reportTitle:SetPoint("TOPLEFT", 12, -10)
reportTitle:SetText("Commander Telemetry — Report")

local reportClose = CreateFrame("Button", nil, reportFrame, "UIPanelCloseButton")
reportClose:SetPoint("TOPRIGHT", 2, 2)

local reportHint = reportFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
reportHint:SetPoint("TOPLEFT", reportTitle, "BOTTOMLEFT", 0, -4)
reportHint:SetText("Select All, then Ctrl+C — paste anywhere for analysis")

local reportScroll = CreateFrame("ScrollFrame", "CommanderTelemetryReportScroll", reportFrame, "UIPanelScrollFrameTemplate")
reportScroll:SetPoint("TOPLEFT", 12, -48)
reportScroll:SetPoint("BOTTOMRIGHT", reportFrame, "BOTTOMRIGHT", -30, 42)

local reportEdit = CreateFrame("EditBox", nil, reportScroll)
reportEdit:SetMultiLine(true)
reportEdit:SetAutoFocus(false)
reportEdit:SetMaxLetters(0)
reportEdit:SetFontObject(GameFontHighlightSmall)
reportEdit:SetWidth(560)
reportEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
reportScroll:SetScrollChild(reportEdit)

local function RefreshReport()
    BackgroundSample()
    reportEdit:SetText(BuildReport())
    if reportEdit.SetCursorPosition then
        reportEdit:SetCursorPosition(0)
    end
end

local selectAllButton = CreateFrame("Button", nil, reportFrame, "UIPanelButtonTemplate")
selectAllButton:SetSize(110, 22)
selectAllButton:SetPoint("BOTTOMLEFT", 12, 10)
selectAllButton:SetText("Select All")
selectAllButton:SetScript("OnClick", function()
    reportEdit:SetFocus()
    reportEdit:HighlightText()
end)

local regenButton = CreateFrame("Button", nil, reportFrame, "UIPanelButtonTemplate")
regenButton:SetSize(110, 22)
regenButton:SetPoint("LEFT", selectAllButton, "RIGHT", 8, 0)
regenButton:SetText("Regenerate")
regenButton:SetScript("OnClick", RefreshReport)

local gcButton = CreateFrame("Button", nil, reportFrame, "UIPanelButtonTemplate")
gcButton:SetSize(100, 22)
gcButton:SetPoint("LEFT", regenButton, "RIGHT", 8, 0)
gcButton:SetText("GC Probe")
gcButton:SetScript("OnClick", function()
    RunGCProbe()
    RefreshReport()
end)
Commander.UI.AttachTooltip(gcButton, "GC Probe",
    "Force a full garbage collection and measure what each module gives back — separating allocation churn (hot loops making garbage) from truly retained memory. Brief hitch while GC runs.")

reportFrame:SetScript("OnShow", RefreshReport)

function CommanderTelemetry_Report()
    reportFrame:Show()
    RefreshReport()
end

reportButton:SetScript("OnClick", function()
    CommanderTelemetry_Report()
end)

-- ---------------------------------------------------------------------------
-- Lifecycle: SavedVariables init, session record, background ticker
-- ---------------------------------------------------------------------------
local lifecycle = CreateFrame("Frame")
lifecycle:RegisterEvent("ADDON_LOADED")
lifecycle:RegisterEvent("PLAYER_LOGIN")
lifecycle:RegisterEvent("PLAYER_LOGOUT")
lifecycle:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Events" then
        CommanderTelemetryDB = _G.CommanderTelemetryDB or {}
        if type(CommanderTelemetryDB.Sessions) ~= "table" then
            CommanderTelemetryDB.Sessions = {}
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CommanderTelemetryDB = CommanderTelemetryDB or {}
        CommanderTelemetryDB.Sessions = CommanderTelemetryDB.Sessions or {}
        local sessions = CommanderTelemetryDB.Sessions
        local last = sessions[#sessions]
        local now = time()
        if last and last.startedAt and last.duration
            and type(last.addons) == "table"
            and (now - (last.startedAt + last.duration)) < 600 then
            -- Quick /reload or relog: continue the same session record
            -- instead of burning a history slot on a fragment (the CPU
            -- enable->reload workflow would litter the trend baseline).
            -- Event/CPU counters restarted with the UI, so the metrics
            -- window marker moves to now.
            sessionRecord = last
            metricsResetAt = now
            if not profilingActive then
                -- Stale CPU totals from before the reload would be divided
                -- by the fresh window — drop them unless still collecting
                sessionRecord.profiled = nil
                for _, a in pairs(sessionRecord.addons) do
                    a.cpu = nil
                end
            end
        else
            sessionRecord = {
                startedAt = now,
                duration = 0,
                addons = {},
            }
            table.insert(sessions, sessionRecord)
            while #sessions > SESSION_CAP do
                table.remove(sessions, 1)
            end
        end
        BackgroundSample()
        C_Timer.NewTicker(SAMPLE_INTERVAL, BackgroundSample)
    elseif event == "PLAYER_LOGOUT" then
        -- Final stamp so the record's end state is exact, not a minute stale
        BackgroundSample()
    end
end)

SLASH_COMMANDERTELEMETRY1 = "/ctelemetry"
SLASH_COMMANDERTELEMETRY2 = "/ctelem"
SlashCmdList["COMMANDERTELEMETRY"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "report" or msg == "export" then
        CommanderTelemetry_Report()
    else
        CommanderTelemetry_Toggle()
    end
end
