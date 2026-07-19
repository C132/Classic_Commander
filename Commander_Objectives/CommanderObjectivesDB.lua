CommanderObjectivesDB = _G.CommanderObjectivesDB or {}

COMMANDER_OBJECTIVES_EVENTS = {
    UPDATE = "COMMANDER_OBJECTIVES_UPDATE"
}

local DefaultSettings = {
    EnableObjectives = true,
    ProgressToasts = true,
    MissionBanner = true,
    ObjectiveSound = true,
    HoldTime = 2.5,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderObjectivesDB, DefaultSettings)
    Commander.Notify(COMMANDER_OBJECTIVES_EVENTS.UPDATE)
    print("Commander Objectives: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Objectives",
        title = "Objectives",
        addonName = "Commander_Objectives",
        description = "Mission-objective announcements, RTS campaign style. Quest progress flashes as a toast at the top of the screen as you work (kills, gathers), a green OBJECTIVE SECURED line when a requirement is filled, and a MISSION ACCOMPLISHED banner when a quest is turned in.",
        event = COMMANDER_OBJECTIVES_EVENTS.UPDATE,
        slash = { "/cobj" },
        slashHandlers = {
            test = function()
                if CommanderObjectives_Test then CommanderObjectives_Test() end
            end,
        },
    })

    panel:AddSection("Mission Objectives")
    panel:AddCheckbox({
        label = "Enable Objectives",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderObjectivesDB.EnableObjectives end,
        set = function(value) CommanderObjectivesDB.EnableObjectives = value end,
    })
    panel:AddCheckbox({
        label = "Progress Toasts",
        tooltip = "Show quest objective progress (kills, gathers) as a toast at the top of the screen.",
        get = function() return CommanderObjectivesDB.ProgressToasts end,
        set = function(value) CommanderObjectivesDB.ProgressToasts = value end,
        isEnabled = function() return CommanderObjectivesDB.EnableObjectives end,
    })
    panel:AddCheckbox({
        label = "Mission Accomplished Banner",
        tooltip = "Show a banner when a quest is turned in.",
        get = function() return CommanderObjectivesDB.MissionBanner end,
        set = function(value) CommanderObjectivesDB.MissionBanner = value end,
        isEnabled = function() return CommanderObjectivesDB.EnableObjectives end,
    })
    panel:AddCheckbox({
        label = "Objective Sound",
        tooltip = "Play a chime when an objective is secured or a mission is accomplished.",
        get = function() return CommanderObjectivesDB.ObjectiveSound end,
        set = function(value) CommanderObjectivesDB.ObjectiveSound = value end,
        isEnabled = function() return CommanderObjectivesDB.EnableObjectives end,
    })
    panel:AddSlider({
        label = "Display Time",
        tooltip = "How long toasts and banners stay on screen.",
        min = 1, max = 5, step = 0.5,
        format = "%.1fs",
        get = function() return CommanderObjectivesDB.HoldTime end,
        set = function(value) CommanderObjectivesDB.HoldTime = value end,
        isEnabled = function() return CommanderObjectivesDB.EnableObjectives end,
    })
    panel:AddButtonRow({
        {
            label = "Test Banner",
            width = 120,
            tooltip = "Preview the objective toast and banner (also: /cobj test).",
            onClick = function()
                if CommanderObjectives_Test then CommanderObjectives_Test() end
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Objectives" then
        Commander.UI.ApplyDefaults(CommanderObjectivesDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
