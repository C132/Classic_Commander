-- Commander Suite: the suite-level dashboard, drawn on the root "Commander"
-- settings page owned by Commander_Events. It lists every installed module
-- with its version and slash command, jumps straight to any module's settings
-- page, and flags suite addons that are installed but not loaded. Unlike the
-- module addons, it owns no gameplay settings of its own, so it duplicates
-- nothing the other pages already do.

local ROW_HEIGHT = 24

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

local function BuildDashboard(panel, anchor)
    anchor = AddSectionHeader(panel, anchor, "Modules")

    for _, module in ipairs(Commander.GetModules()) do
        anchor = AddModuleRow(panel, anchor, module)
    end

    for _, addon in ipairs(GetUnloadedSuiteAddons()) do
        anchor = AddModuleRow(panel, anchor, {
            title = addon.title:gsub("^Commander ", ""),
            reason = addon.reason,
        })
    end

    anchor = AddSectionHeader(panel, anchor, "Suite")

    local reloadButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reloadButton:SetSize(100, 22)
    reloadButton:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
    reloadButton:SetText("Reload UI")
    reloadButton:SetScript("OnClick", ReloadUI)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", reloadButton, "RIGHT", 12, 0)
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
