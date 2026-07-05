CommanderUnitFramesDB = CommanderUnitFramesDB or {}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

COMMANDER_UNIT_FRAMES_EVENTS = {
    SCALE_CHANGED = "SCALE_CHANGED",
    PERCENTAGE_DISPLAY_CHANGED = "PERCENTAGE_DISPLAY_CHANGED"
}

local function OnAwake()
    if CommanderUnitFramesDB == nil then
        CommanderUnitFramesDB = {}
    end
    CommanderUnitFramesDB.callbacks = nil
    CommanderUnitFramesDB.scale = CommanderUnitFramesDB.scale or 1.0
    if CommanderUnitFramesDB.showPercentage == nil then
        CommanderUnitFramesDB.showPercentage = true
    end
end

-- Initialize any necessary components or features
local function OnStart()
end

-- Save any necessary data before logout
local function OnDestroy()
end

frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_UnitFrames" then
        OnAwake()
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif event == "PLAYER_ENTERING_WORLD" then
        OnStart()
    end
end)