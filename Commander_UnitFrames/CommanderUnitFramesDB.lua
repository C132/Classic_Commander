CommanderUnitFramesDB = CommanderUnitFramesDB or {}

COMMANDER_UNIT_FRAMES_EVENTS = {
    UPDATE = "COMMANDER_UNITFRAMES_UPDATE",
}

local DefaultSettings = {
    scale = 1.0,
}

local function ApplyDefaults()
    -- Remove a key accidentally persisted by pre-2.0 builds
    CommanderUnitFramesDB.callbacks = nil

    -- One-time migration: the pre-2.0 scale slider wrote values that nothing
    -- ever applied, so a surviving non-default value was never something the
    -- user actually saw. Reset it once, now that the slider is functional,
    -- so frames don't unexpectedly change size on upgrade.
    if not CommanderUnitFramesDB._scaleV2 then
        CommanderUnitFramesDB.scale = DefaultSettings.scale
        CommanderUnitFramesDB._scaleV2 = true
    end

    -- The percentage toggle now mirrors the game's Status Text CVar directly
    -- instead of shadowing it in SavedVariables (which forced the addon to
    -- overwrite the player's choice at every login)
    CommanderUnitFramesDB.showPercentage = nil

    Commander.UI.ApplyDefaults(CommanderUnitFramesDB, DefaultSettings)
end

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderUnitFramesDB, DefaultSettings)
    pcall(SetCVar, "statusTextDisplay", "PERCENT")
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
    })

    panel:AddSection("Unit Frames")
    panel:AddSlider({
        label = "Frame Scale",
        tooltip = "Overall size of the player and target frames. Applied after combat ends if changed while fighting.",
        min = 0.5, max = 2.0, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderUnitFramesDB.scale end,
        set = function(value) CommanderUnitFramesDB.scale = value end,
    })
    panel:AddCheckbox({
        label = "Show Health/Mana Percentage",
        tooltip = "Mirrors the game's Status Text option: checked selects Percent, unchecked selects None. Only written when you click it, so a Numeric or Both choice made in the game's own options is left alone (and shows here as unchecked).",
        get = function()
            local ok, value = pcall(GetCVar, "statusTextDisplay")
            return ok and value == "PERCENT"
        end,
        set = function(value)
            pcall(SetCVar, "statusTextDisplay", value and "PERCENT" or "NONE")
        end,
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
