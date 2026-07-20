Commander = Commander or {}

local callbacks = {}

function Commander.AddListener(event, func)
    if not event then
        error("Event cannot be nil")
        return
    end

    if not func then
        error("Callback function cannot be nil")
        return
    end

    if not callbacks[event] then
        callbacks[event] = {}
    end

    for _, existing in ipairs(callbacks[event]) do
        if existing == func then
            return
        end
    end

    table.insert(callbacks[event], func)
end

function Commander.Notify(event, ...)
    if event and callbacks[event] then
        for _, func in ipairs(callbacks[event]) do
            local ok, err = pcall(func, ...)
            if not ok then
                geterrorhandler()(err)
            end
        end
    end
end

-- Legacy aliases so existing call sites keep working
AddListener = Commander.AddListener
Notify = Commander.Notify

local function CreateMainPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander"

    -- Same header the module pages get from UI.NewPanel
    local divider = Commander.UI.BuildPanelHeader(panel, {
        titleText = "Commander",
        addonName = "Commander_Events",
        description = "A modular, RTS-inspired command layer for the whole game, built on five pillars: Command & Control (comms, orders, rally points), Battle HUD (production, afflictions, vitals), Feedback & Alerts (momentum, impact, ceremony), Operations (economy, logistics, the mission board), and Interface (command card, bags, map, chat). Every module stands alone behind its own master switch and settings page in the list on the left; open this page any time with /commander.",
    })
    panel.ContentAnchor = divider

    return panel
end

-- Extension point for suite-level addons (Commander_Suite) to draw content on
-- the root Commander page. Builders run once, on the panel's first OnShow, so
-- they can rely on every module having registered by then; buildFn receives
-- (panel, anchor) where anchor is the header divider to build below.
local mainPanelBuilders = {}
local mainPanelBuilt = false

function Commander.AddMainPanelContent(buildFn)
    if type(buildFn) ~= "function" then
        error("Commander.AddMainPanelContent expects a function")
        return
    end
    table.insert(mainPanelBuilders, buildFn)
end

local function RunMainPanelBuilders()
    if mainPanelBuilt then return end
    mainPanelBuilt = true
    for _, buildFn in ipairs(mainPanelBuilders) do
        local ok, err = pcall(buildFn, Commander.MainPanel, Commander.MainPanel.ContentAnchor)
        if not ok then
            geterrorhandler()(err)
        end
    end
end

Commander.MainPanel = CreateMainPanel()
Commander.MainPanel:HookScript("OnShow", RunMainPanelBuilders)
Commander.MainCategory = Settings.RegisterCanvasLayoutCategory(Commander.MainPanel, "Commander")
Commander.MainCategoryID = Commander.MainCategory:GetID()
Settings.RegisterAddOnCategory(Commander.MainCategory)

-- Legacy aliases so existing call sites keep working
MainPanel = Commander.MainPanel
MainCategory = Commander.MainCategory
MainCategoryID = Commander.MainCategoryID

-- ---------------------------------------------------------------------------
-- Reload-resilient session state. A module keeps its session-scoped
-- counters in db.Session and restores them through here: a brief
-- interruption (/reload, a quick relog) resumes the same session, a real
-- break starts fresh. Timestamps stored inside MUST be epoch time() —
-- GetTime() resets on client restart; convert at the call site. The hub
-- stamps every registered table at PLAYER_LOGOUT (which fires on /reload
-- too) and once a minute as a crash guard.
-- ---------------------------------------------------------------------------
local SESSION_RESUME_WINDOW = 600
local sessionTables = {}

local function StampSessions()
    local now = time()
    for _, db in ipairs(sessionTables) do
        if db.Session then
            db.Session.savedAt = now
        end
    end
end

-- Returns (session, fresh). fresh is true when a new session block was
-- started; false means the previous session resumed. defaults fills any
-- missing keys either way, so adding fields later is safe.
function Commander.RestoreSession(db, defaults)
    local session = db.Session
    local fresh = not (type(session) == "table" and session.savedAt
        and (time() - session.savedAt) < SESSION_RESUME_WINDOW)
    if fresh then
        session = {}
        db.Session = session
    end
    for key, value in pairs(defaults) do
        if session[key] == nil then
            session[key] = Commander.UI.CopyValue(value)
        end
    end
    session.savedAt = time()
    sessionTables[#sessionTables + 1] = db
    return session, fresh
end

local sessionStamper = CreateFrame("Frame")
sessionStamper:RegisterEvent("PLAYER_LOGOUT")
sessionStamper:SetScript("OnEvent", StampSessions)
C_Timer.NewTicker(60, StampSessions)
