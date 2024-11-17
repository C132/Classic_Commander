CommanderUnitFramesDB = CommanderUnitFramesDB or {}
CommanderUnitFramesDB.callbacks = {}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

EVENTS = {
    SCALE_CHANGED = "SCALE_CHANGED",
    PERCENTAGE_DISPLAY_CHANGED = "PERCENTAGE_DISPLAY_CHANGED"
}

local function OnAwake()
    if CommanderUnitFramesDB == nil then print("No CommanderUnitFramesDB found") end
    CommanderUnitFramesDB.scale = CommanderUnitFramesDB.scale or 1.0
    CommanderUnitFramesDB.showPercentage = CommanderUnitFramesDB.showPercentage or true
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

function AddListener(event, func)
    if not event then return end -- Guard against nil event
    if not CommanderUnitFramesDB.callbacks[event] then
        CommanderUnitFramesDB.callbacks[event] = {}
    end
    table.insert(CommanderUnitFramesDB.callbacks[event], func)
end

function Raise(event)
    if event and CommanderUnitFramesDB.callbacks[event] then
        for _, func in ipairs(CommanderUnitFramesDB.callbacks[event]) do
            func()
        end
    end
end

-- Add debug functionality if needed
function Debug()
    print("CommanderUnitFramesDB:", CommanderUnitFramesDB)
end