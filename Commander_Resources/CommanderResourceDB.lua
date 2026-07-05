CommanderResourceDB = CommanderResourceDB or {}
CommanderResourceDB.callbacks = {}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

COMMANDER_RESOURCE_EVENTS = {
    FIVE_SECOND_RULE_CHANGED = "FIVE_SECOND_RULE_CHANGED",
}

local function OnAwake()
    if CommanderResourceDB == nil then print("No config found") end
    -- SavedVariables replace the global after this file runs, so re-ensure the table here
    CommanderResourceDB = CommanderResourceDB or {}
    CommanderResourceDB.callbacks = CommanderResourceDB.callbacks or {}
    CommanderResourceDB.ShowFiveSecondRule = CommanderResourceDB.ShowFiveSecondRule or false
end

-- Initialize any necessary components or features
local function OnStart()
end

-- Save any necessary data before logout
local function OnDestroy()
end

frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Resources" then
        OnAwake()
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif event == "PLAYER_ENTERING_WORLD" then
        OnStart()
    end
end)

-- Add debug functionality if needed
function Debug()
end