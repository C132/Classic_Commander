-- Commander Suite: the suite-level dashboard, drawn on the root "Commander"
-- settings page owned by Commander_Events. It lists every installed module
-- with its version and slash command, jumps straight to any module's settings
-- page, and flags suite addons that are installed but not loaded. Unlike the
-- module addons, it owns no gameplay settings of its own, so it duplicates
-- nothing the other pages already do.

local ROW_HEIGHT = 24
local GROUP_HEADER_HEIGHT = 30

-- The product taxonomy: every module belongs to one of five pillars, listed
-- in the order the product tells its story — how you command, what you see
-- in battle, how the game answers you, the campaign layer, and the reskinned
-- interface itself. The dashboard walks this list; a module the table does
-- not know yet falls through to Other Modules, so nothing ever vanishes.
local PILLARS = {
    { title = "Command & Control",
      keys = { "Comms", "Orders", "Ping", "Camera", "Radar" } },
    { title = "Battle HUD",
      keys = { "Production", "Afflictions", "Vitals", "Nameplate", "Casting", "Resources" } },
    { title = "Feedback & Alerts",
      keys = { "Momentum", "Impact", "Spoils", "Promotion", "Adjutant", "Idle" } },
    { title = "Operations",
      keys = { "Economy", "Logistics", "Objectives", "ObjectivesBoard", "Recovery", "Who" } },
    { title = "Interface",
      keys = { "ActionBar", "ActionBarButtons", "Bags", "Inventory", "Chat", "Minimap", "TopBar", "Tooltip", "Console" } },
}

local function AddSectionHeader(panel, anchor, text)
    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
    label:SetText(text)
    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetHeight(1)
    line:SetPoint("LEFT", label, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    return label
end

-- Suite addons that are installed but did not load (disabled, out of date,
-- dependency missing). The module registry only knows about loaded modules.
local function GetUnloadedSuiteAddons()
    local unloaded = {}
    for i = 1, C_AddOns.GetNumAddOns() do
        local name, title, _, loadable, reason = C_AddOns.GetAddOnInfo(i)
        if type(name) == "string" and name:find("^Commander_") and not C_AddOns.IsAddOnLoaded(name) then
            unloaded[#unloaded + 1] = {
                name = name,
                title = title or name,
                reason = reason and _G["ADDON_" .. reason] or reason or "Not loaded",
            }
        end
    end
    table.sort(unloaded, function(a, b) return a.title < b.title end)
    return unloaded
end

-- Pillar sub-header inside the scrolling directory
local function AddGroupHeader(panel, anchor, text)
    local row = CreateFrame("Frame", nil, panel)
    row:SetHeight(GROUP_HEADER_HEIGHT)
    row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, anchor.isRow and 0 or -8)
    row:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    row.isRow = true

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 4)
    label:SetText(text)

    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.12)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", label, "BOTTOMRIGHT", 8, 2)
    line:SetPoint("RIGHT", row, "RIGHT", -4, 0)

    return row
end

local function AddModuleRow(panel, anchor, module)
    local row = CreateFrame("Frame", nil, panel)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, anchor.isRow and 0 or -8)
    row:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    row.isRow = true

    local title = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    title:SetPoint("LEFT", row, "LEFT", 4, 0)
    title:SetWidth(160)
    title:SetJustifyH("LEFT")
    title:SetText(module.title)

    local detail = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    detail:SetPoint("LEFT", title, "RIGHT", 8, 0)
    detail:SetJustifyH("LEFT")

    if module.categoryID then
        detail:SetText((module.version and ("v" .. module.version .. "   ") or "") .. (module.slash or ""))

        local openButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        openButton:SetSize(70, 20)
        openButton:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        openButton:SetText("Settings")
        openButton:SetScript("OnClick", function()
            Settings.OpenToCategory(module.categoryID)
        end)

        if module.description then
            local text = module.description
            if module.slash then
                text = text .. "\n\nSlash command: " .. module.slash
            end
            row:EnableMouse(true)
            Commander.UI.AttachTooltip(row, module.title, text)
        end
    else
        title:SetFontObject(GameFontDisable)
        detail:SetText(module.reason or "Not loaded")
    end

    return row
end

local SCROLL_HEIGHT = 330
local CONTENT_WIDTH = 560

local function BuildDashboard(panel, anchor)
    anchor = AddSectionHeader(panel, anchor, "Modules")

    -- The directory long outgrew the page: 30+ modules overflow the canvas,
    -- so the list lives in a fixed-height scroll frame
    local scroll = CreateFrame("ScrollFrame", "CommanderSuiteModuleScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
    scroll:SetPoint("RIGHT", panel, "RIGHT", -38, 0)
    scroll:SetHeight(SCROLL_HEIGHT)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_WIDTH, 10)
    scroll:SetScrollChild(content)

    -- Seed anchor sits 8px above the content top so the first row's -8
    -- offset lands exactly at 0
    local seed = CreateFrame("Frame", nil, content)
    seed:SetSize(1, 1)
    seed:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 8)

    local byKey = {}
    for _, module in ipairs(Commander.GetModules()) do
        byKey[module.key] = module
    end

    local rowAnchor = seed
    local contentHeight = 24
    local listed = {}

    local function AddGroup(headerText, rows)
        if #rows == 0 then return end
        rowAnchor = AddGroupHeader(content, rowAnchor, headerText)
        contentHeight = contentHeight + GROUP_HEADER_HEIGHT
        for _, row in ipairs(rows) do
            rowAnchor = AddModuleRow(content, rowAnchor, row)
            contentHeight = contentHeight + ROW_HEIGHT
        end
    end

    for _, pillar in ipairs(PILLARS) do
        local rows = {}
        for _, key in ipairs(pillar.keys) do
            if byKey[key] then
                rows[#rows + 1] = byKey[key]
                listed[key] = true
            end
        end
        AddGroup(pillar.title, rows)
    end

    -- Loaded modules the taxonomy does not know yet (GetModules is already
    -- title-sorted, so this stays alphabetical)
    local other = {}
    for _, module in ipairs(Commander.GetModules()) do
        if not listed[module.key] then
            other[#other + 1] = module
        end
    end
    AddGroup("Other Modules", other)

    local unloaded = {}
    for _, addon in ipairs(GetUnloadedSuiteAddons()) do
        unloaded[#unloaded + 1] = {
            title = addon.title:gsub("^Commander ", ""),
            reason = addon.reason,
        }
    end
    AddGroup("Not Loaded", unloaded)

    content:SetHeight(contentHeight)

    anchor = AddSectionHeader(panel, anchor, "Suite")
    -- Re-anchor the Suite section below the scroll viewport
    anchor:ClearAllPoints()
    anchor:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -14)

    local reloadButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reloadButton:SetSize(100, 22)
    reloadButton:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
    reloadButton:SetText("Reload UI")
    reloadButton:SetScript("OnClick", ReloadUI)

    local telemetryButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    telemetryButton:SetSize(100, 22)
    telemetryButton:SetPoint("LEFT", reloadButton, "RIGHT", 8, 0)
    telemetryButton:SetText("Telemetry")
    telemetryButton:SetScript("OnClick", function()
        if CommanderTelemetry_Toggle then CommanderTelemetry_Toggle() end
    end)
    Commander.UI.AttachTooltip(telemetryButton, "Commander Telemetry",
        "Live memory, CPU, and event-traffic profiling for every suite module (also: /ctelemetry).")

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", telemetryButton, "RIGHT", 12, 0)
    hint:SetText("Open this page any time with /commander")
end

-- Registered with the hub's extension point, which runs builders once on the
-- root panel's first OnShow. That timing matters: PLAYER_LOGIN dispatch
-- follows addon load order, so modules loading after Commander_Suite would be
-- missing from an eagerly built list, while the settings UI cannot open
-- before login completes.
Commander.AddMainPanelContent(BuildDashboard)

SLASH_COMMANDERSUITE1 = "/commander"
SLASH_COMMANDERSUITE2 = "/cmdr"
SlashCmdList["COMMANDERSUITE"] = function()
    Settings.OpenToCategory(Commander.MainCategoryID)
end
