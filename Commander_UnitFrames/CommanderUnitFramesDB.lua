CommanderUnitFramesDB = CommanderUnitFramesDB or {}

COMMANDER_UNIT_FRAMES_EVENTS = {
    UPDATE = "COMMANDER_UNITFRAMES_UPDATE",
}

local DefaultSettings = {
    scale = 1.0,
    showPercentage = true,
}

local function ApplyDefaults()
    -- Remove a key accidentally persisted by pre-2.0 builds
    CommanderUnitFramesDB.callbacks = nil
    for key, value in pairs(DefaultSettings) do
        if CommanderUnitFramesDB[key] == nil then
            CommanderUnitFramesDB[key] = value
        end
    end
end

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    for key, value in pairs(DefaultSettings) do
        CommanderUnitFramesDB[key] = value
    end
    Commander.Notify(COMMANDER_UNIT_FRAMES_EVENTS.UPDATE)
    print("Commander Unit Frames: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "UnitFrames",
        title = "Unit Frames",
        addonName = "Commander_UnitFrames",
        description = "Adjusts the player and target unit frames: scale them up or down and control whether health and mana show percentage text.",
        event = COMMANDER_UNIT_FRAMES_EVENTS.UPDATE,
        slash = { "/cuf" },
        slashHandlers = {
            reset = Reset,
        },
    })

    panel:AddSection("Unit Frames")
    panel:AddSlider({
        label = "Frame Scale",
        tooltip = "Overall size of the player and target frames. Applied after combat ends if changed while fighting.",
        min = 0.5, max = 2.0, step = 0.05,
        format = function(value) return string.format("%d%%", value * 100 + 0.5) end,
        get = function() return CommanderUnitFramesDB.scale end,
        set = function(value) CommanderUnitFramesDB.scale = value end,
    })
    panel:AddCheckbox({
        label = "Show Health/Mana Percentage",
        tooltip = "Display health and mana as percentages on status bars. This drives the game's Status Text setting: checked selects Percent, unchecked selects None.",
        get = function() return CommanderUnitFramesDB.showPercentage end,
        set = function(value) CommanderUnitFramesDB.showPercentage = value end,
    })

    panel:Finalize({ onDefaults = Reset })
end

frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_UnitFrames" then
        ApplyDefaults()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end)
