CommanderResourceDB = CommanderResourceDB or {}
CommanderResourceDB.callbacks = {}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

EVENTS = {
    FIVE_SECOND_RULE_CHANGED = "FIVE_SECOND_RULE_CHANGED",
}

local function OnAwake()
    if CommanderResourceDB == nil then print("No config found") end
    CommanderResourceDB.ShowFiveSecondRule = CommanderResourceDB.ShowFiveSecondRule or false
end

-- Initialize any necessary components or features
local function OnStart()
end

-- Save any necessary data before logout
local function OnDestroy()
end

frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "MyClassicAddon" then
        OnAwake()
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif event == "PLAYER_ENTERING_WORLD" then
        OnStart()
    end
end)

function AddListener(event, func)
    if not event then return end -- Guard against nil event
    if not CommanderResourceDB.callbacks[event] then
        CommanderResourceDB.callbacks[event] = {}
    end
    table.insert(CommanderResourceDB.callbacks[event], func)
end

function Raise(event)
    if event and CommanderResourceDB.callbacks[event] then
        for _, func in ipairs(CommanderResourceDB.callbacks[event]) do
            func()
        end
    end
end

-- Add debug functionality if needed
function Debug()
end