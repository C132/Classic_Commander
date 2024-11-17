CommanderMinimapDB = CommanderMinimapDB or {}
CommanderMinimapDB.callbacks = {}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

EVENTS = {
    MINIMAP_BUTTON_VISIBILITY_CHANGED = "MINIMAP_BUTTON_VISIBILITY_CHANGED",
    XP_DISPLAY_MODE_CHANGED = "XP_DISPLAY_MODE_CHANGED",
}

local function OnAwake()
    if CommanderMinimapDB == nil then print("No Minimap DB found") end
    CommanderMinimapDB.ShowMinimapButton = CommanderMinimapDB.ShowMinimapButton or true
    CommanderMinimapDB.MinimapButtonPosition = CommanderMinimapDB.MinimapButtonPosition or 0
    CommanderMinimapDB.XPDisplayMode = CommanderMinimapDB.XPDisplayMode or "PERCENTAGE"
    CommanderMinimapDB.lastXPGain = CommanderMinimapDB.lastXPGain or 0
    CommanderMinimapDB.killsToLevel = CommanderMinimapDB.killsToLevel or 0
    CommanderMinimapDB.lastXPSource = CommanderMinimapDB.lastXPSource or ""
end

-- Initialize any necessary components or features
local function OnStart()
    LoadMinimapButtonPosition()
end

-- Save any necessary data before logout
local function OnDestroy()
    SaveMinimapButtonPosition()
end

frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Minimap" then
        OnAwake()
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif event == "PLAYER_ENTERING_WORLD" then
        OnStart()
    end
end)

function AddListener(event, func)
    if not CommanderMinimapDB.callbacks[event] then
        CommanderMinimapDB.callbacks[event] = {}
    end
    table.insert(CommanderMinimapDB.callbacks[event], func)
end

function Raise(event)
    if CommanderMinimapDB.callbacks[event] then
        for _, func in ipairs(CommanderMinimapDB.callbacks[event]) do
            func()
        end
    end
end

function SaveMinimapButtonPosition()
    CommanderMinimapDB.MinimapButtonPosition = CommanderMinimapButton and CommanderMinimapButton:GetAngle() or 0
end

function LoadMinimapButtonPosition()
    if CommanderMinimapButton then
        CommanderMinimapButton:SetAngle(CommanderMinimapDB.MinimapButtonPosition)
    end
end

-- Add debug functionality if needed
function Debug()
    print("CommanderMinimapDB:", CommanderMinimapDB)
end

function ToggleMinimapButton()
    CommanderMinimapDB.ShowMinimapButton = not CommanderMinimapDB.ShowMinimapButton
    Raise(EVENTS.MINIMAP_BUTTON_VISIBILITY_CHANGED)
end

function SetXPDisplayMode(mode)
    CommanderMinimapDB.XPDisplayMode = mode
    Raise(EVENTS.XP_DISPLAY_MODE_CHANGED)
end

function GetXPDisplayMode()
    return CommanderMinimapDB.XPDisplayMode
end

function UpdateLastXPGain(xpGained, source)
    CommanderMinimapDB.lastXPGain = xpGained
    CommanderMinimapDB.lastXPSource = source
    UpdateKillsToLevel()
end

function UpdateKillsToLevel()
    if CommanderMinimapDB.lastXPGain > 0 then
        local currentXP = UnitXP("player")
        local maxXP = UnitXPMax("player")
        local xpNeeded = maxXP - currentXP
        CommanderMinimapDB.killsToLevel = math.ceil(xpNeeded / CommanderMinimapDB.lastXPGain)
    end
end

function GetKillsToLevel()
    return CommanderMinimapDB.killsToLevel
end

function GetLastXPSource()
    return CommanderMinimapDB.lastXPSource
end