CommanderLogisticsDB = _G.CommanderLogisticsDB or {}

COMMANDER_LOGISTICS_EVENTS = {
    UPDATE = "COMMANDER_LOGISTICS_UPDATE"
}

local DefaultSettings = {
    EnableLogistics = true,
    AutoSellJunk = true,
    AutoRepair = true,
    Report = true,
    -- Remember each repair vendor you open, for "Nearest repair". The book
    -- itself (RepairVendors) is data, deliberately not a default: Restore
    -- Defaults must never forget every vendor you have met.
    LearnRepairVendors = true,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderLogisticsDB, DefaultSettings)
    Commander.Notify(COMMANDER_LOGISTICS_EVENTS.UPDATE)
    print("Commander Logistics: settings restored to defaults")
end

-- Go to Nearest Repair / Go to Nearest Vendor: the suite's Go button
-- (Commander.UI.GoButton, Commander Orders' DECISIONS D31: click to go,
-- Shift-click to share the place, Ctrl-click to copy the /way line, lit
-- "Going" while the arrow is on it, greyed with the reason while there is
-- none), at the nearest place CommanderLogistics_SupplySpec finds on your
-- landmass, under (Logistics, "repair" | "vendor"): the one record /clog
-- repair and /clog vendor move too. The client reads a NEW Commander_Events
-- file only at start-up, so after an update and a /reload the widget may be
-- missing: then a plain button that makes the same request.
local GO_TO = {
    Repair = { label = "Go to Nearest Repair", key = "repair",
        tooltip = "The nearest repair vendor on this continent, on the Commander Orders arrow (also: /clog repair)." },
    Vendor = { label = "Go to Nearest Vendor", key = "vendor",
        tooltip = "The nearest vendor of any kind on this continent, to sell to or buy from (also: /clog vendor)." },
}

local function GoButton(parent, kind)
    local go = GO_TO[kind]
    local UI = Commander and Commander.UI
    if UI and type(UI.GoButton) == "function" then
        return UI.GoButton(parent, {
            label = go.label, width = 170, source = "Logistics", key = go.key, icon = "VENDOR", tooltip = go.tooltip,
            spec = function()
                if type(CommanderLogistics_SupplySpec) ~= "function" then return nil end
                return CommanderLogistics_SupplySpec(kind)
            end,
        })
    end
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(170, 22)
    button:SetText(go.label)
    button:SetScript("OnClick", function()
        if CommanderLogistics_SupplyWaypoint then CommanderLogistics_SupplyWaypoint(kind) end
    end)
    return button
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Logistics",
        title = "Logistics",
        addonName = "Commander_Logistics",
        description = "Automated supply lines, RTS-style: visit any vendor and your junk sells itself while your gear gets repaired, followed by a quartermaster's report of what it cost and what it earned. Base upkeep you never think about again.",
        event = COMMANDER_LOGISTICS_EVENTS.UPDATE,
        slash = { "/clog" },
        slashHandlers = {
            repair = function()
                if CommanderLogistics_RepairWaypoint then CommanderLogistics_RepairWaypoint() end
            end,
            vendor = function()
                if CommanderLogistics_SupplyWaypoint then CommanderLogistics_SupplyWaypoint("Vendor") end
            end,
        },
    })

    panel:AddSection("Supply Lines", "Runs automatically whenever a merchant window opens.")
    panel:AddCheckbox({
        label = "Enable Logistics",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderLogisticsDB.EnableLogistics end,
        set = function(value) CommanderLogisticsDB.EnableLogistics = value end,
    })
    panel:AddCheckbox({
        label = "Auto-Sell Junk",
        tooltip = "Sell all gray-quality items when a merchant window opens.",
        get = function() return CommanderLogisticsDB.AutoSellJunk end,
        set = function(value) CommanderLogisticsDB.AutoSellJunk = value end,
        isEnabled = function() return CommanderLogisticsDB.EnableLogistics end,
    })
    panel:AddCheckbox({
        label = "Auto-Repair",
        tooltip = "Repair all equipment at any merchant that offers repairs, using your own gold.",
        get = function() return CommanderLogisticsDB.AutoRepair end,
        set = function(value) CommanderLogisticsDB.AutoRepair = value end,
        isEnabled = function() return CommanderLogisticsDB.EnableLogistics end,
    })
    panel:AddCheckbox({
        label = "Quartermaster's Report",
        tooltip = "Print a one-line summary of what was sold and what repairs cost.",
        get = function() return CommanderLogisticsDB.Report end,
        set = function(value) CommanderLogisticsDB.Report = value end,
        isEnabled = function() return CommanderLogisticsDB.EnableLogistics end,
    })

    panel:AddSection("Repair Vendors", "Every merchant you open that offers repairs is remembered, on this account and for your faction, where the vendor stands. Commander Orders' locator merges them with the vendors Questie knows, so Go to Nearest Repair points the Commander Orders arrow at the closest repair on your continent (click to go, Shift-click to share the place, Ctrl-click to copy the /way line; without Commander Orders a click prints the /way line), and Commander Adjutant's alerts can mark the nearest repair or vendor for you. A repair waypoint clears itself when you open a repair vendor, a vendor waypoint at any merchant.")
    panel:AddCheckbox({
        label = "Remember Repair Vendors",
        tooltip = "Note where each repair vendor stands when you open their window. Vendors met inside instances are not noted: there is no map position there.",
        get = function() return CommanderLogisticsDB.LearnRepairVendors end,
        set = function(value) CommanderLogisticsDB.LearnRepairVendors = value end,
        isEnabled = function() return CommanderLogisticsDB.EnableLogistics end,
    })
    local goRow = panel:AddRow(26, 10)
    local goRepair = GoButton(goRow, "Repair")
    goRepair:SetPoint("LEFT", goRow, "LEFT", 0, 0)
    local goVendor = GoButton(goRow, "Vendor")
    goVendor:SetPoint("LEFT", goRepair, "RIGHT", 8, 0)
    panel:TagRow(goRow, GO_TO.Repair.label, GO_TO.Repair.tooltip, GO_TO.Vendor.label, GO_TO.Vendor.tooltip)
    panel:AddRefresher(function()
        if goRepair.Refresh then goRepair:Refresh() end
        if goVendor.Refresh then goVendor:Refresh() end
    end)
    panel:AddButtonRow({
        {
            label = "Forget Repair Vendors",
            width = 170,
            tooltip = function()
                local n = CommanderLogistics_RepairVendorCount and CommanderLogistics_RepairVendorCount() or 0
                return string.format("Forget the %d repair vendors remembered for your faction. They are learned again as you meet them.", n)
            end,
            onClick = function()
                if CommanderLogistics_ForgetRepairVendors then CommanderLogistics_ForgetRepairVendors() end
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Logistics" then
        Commander.UI.ApplyDefaults(CommanderLogisticsDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
