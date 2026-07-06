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
        description = "A modular interface suite. Each module has its own settings page in the list on the left.",
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
