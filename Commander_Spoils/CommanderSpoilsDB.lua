CommanderSpoilsDB = _G.CommanderSpoilsDB or {}

COMMANDER_SPOILS_EVENTS = {
    UPDATE = "COMMANDER_SPOILS_UPDATE"
}

local DefaultSettings = {
    EnableSpoils = true,
    MinQuality = 2,
    EpicFlash = true,
    SpoilsSound = false,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderSpoilsDB, DefaultSettings)
    Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
    print("Commander Spoils: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Spoils",
        title = "Spoils",
        addonName = "Commander_Spoils",
        description = "Every worthwhile pickup announced like acquired supply: a toast with the item's icon and quality-colored name slides in as you loot, rare finds chime, and epics flash the whole screen. The quality bar for what counts as worthwhile is yours to set.",
        event = COMMANDER_SPOILS_EVENTS.UPDATE,
        slash = { "/cspoils" },
        slashHandlers = {
            report = function()
                if CommanderSpoils_Report then CommanderSpoils_Report() end
            end,
            test = function()
                if CommanderSpoils_Test then CommanderSpoils_Test() end
            end,
        },
    })

    panel:AddSection("Supply Toasts")
    panel:AddCheckbox({
        label = "Enable Spoils",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderSpoilsDB.EnableSpoils end,
        set = function(value) CommanderSpoilsDB.EnableSpoils = value end,
    })
    panel:AddDropdown({
        label = "Minimum Quality",
        tooltip = "Only loot of this quality or better raises a toast.",
        options = {
            { text = "Poor and up (everything)", value = 0 },
            { text = "Common and up", value = 1 },
            { text = "Uncommon and up", value = 2 },
            { text = "Rare and up", value = 3 },
            { text = "Epic and up", value = 4 },
        },
        width = 180,
        get = function() return CommanderSpoilsDB.MinQuality end,
        set = function(value) CommanderSpoilsDB.MinQuality = value end,
        isEnabled = function() return CommanderSpoilsDB.EnableSpoils end,
    })
    panel:AddCheckboxPair({
        label = "Epic Screen Flash",
        tooltip = "Epic or better loot flashes the screen edge purple. You earned it.",
        get = function() return CommanderSpoilsDB.EpicFlash end,
        set = function(value) CommanderSpoilsDB.EpicFlash = value end,
        isEnabled = function() return CommanderSpoilsDB.EnableSpoils end,
    }, {
        label = "Rare Chime",
        tooltip = "Play a chime for rare-or-better pickups.",
        get = function() return CommanderSpoilsDB.SpoilsSound end,
        set = function(value) CommanderSpoilsDB.SpoilsSound = value end,
        isEnabled = function() return CommanderSpoilsDB.EnableSpoils end,
    })
    panel:AddButtonRow({
        {
            label = "Session Tally",
            width = 120,
            tooltip = "Print this session's spoils by quality (also: /cspoils report).",
            onClick = function()
                if CommanderSpoils_Report then CommanderSpoils_Report() end
            end,
        },
        {
            label = "Test Toast",
            width = 110,
            tooltip = "Preview a supply toast (also: /cspoils test).",
            onClick = function()
                if CommanderSpoils_Test then CommanderSpoils_Test() end
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Spoils" then
        Commander.UI.ApplyDefaults(CommanderSpoilsDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
