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

    panel:AddSection("Repair Vendors", "Every merchant you open that offers repairs is remembered, on this account and for your faction. Nearest Repair then points the Commander Orders arrow at the closest one on your continent (or prints the /way line without Commander Orders), and Commander Adjutant's low-durability alert can mark it for you. The waypoint clears itself when you open a repair vendor.")
    panel:AddCheckbox({
        label = "Remember Repair Vendors",
        tooltip = "Note where each repair vendor stands when you open their window. Vendors met inside instances are not noted: there is no map position there.",
        get = function() return CommanderLogisticsDB.LearnRepairVendors end,
        set = function(value) CommanderLogisticsDB.LearnRepairVendors = value end,
        isEnabled = function() return CommanderLogisticsDB.EnableLogistics end,
    })
    panel:AddButtonRow({
        {
            label = "Nearest Repair",
            width = 140,
            tooltip = "A waypoint at the nearest repair vendor you have met on this continent (also: /clog repair).",
            onClick = function()
                if CommanderLogistics_RepairWaypoint then CommanderLogistics_RepairWaypoint() end
            end,
        },
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
