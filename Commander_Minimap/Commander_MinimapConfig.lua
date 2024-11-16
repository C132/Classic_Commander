MinimapConfig = MinimapConfig or {}
MinimapConfig.callbacks = {}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

EVENTS = {
    MINIMAP_BUTTON_VISIBILITY_CHANGED = "MINIMAP_BUTTON_VISIBILITY_CHANGED",
    XP_DISPLAY_MODE_CHANGED = "XP_DISPLAY_MODE_CHANGED",
}

local function OnAwake()
    if MinimapConfig == nil then print("No config found") end
    MinimapConfig.ShowMinimapButton = MinimapConfig.ShowMinimapButton or true
    MinimapConfig.MinimapButtonPosition = MinimapConfig.MinimapButtonPosition or 0
    MinimapConfig.XPDisplayMode = MinimapConfig.XPDisplayMode or "PERCENTAGE"
    MinimapConfig.lastXPGain = MinimapConfig.lastXPGain or 0
    MinimapConfig.killsToLevel = MinimapConfig.killsToLevel or 0
    MinimapConfig.lastXPSource = MinimapConfig.lastXPSource or ""
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
    if not MinimapConfig.callbacks[event] then
        MinimapConfig.callbacks[event] = {}
    end
    table.insert(MinimapConfig.callbacks[event], func)
end

function Raise(event)
    if MinimapConfig.callbacks[event] then
        for _, func in ipairs(MinimapConfig.callbacks[event]) do
            func()
        end
    end
end

function SaveMinimapButtonPosition()
    MinimapConfig.MinimapButtonPosition = MyClassicAddonMinimapButton and MyClassicAddonMinimapButton:GetAngle() or 0
end

function LoadMinimapButtonPosition()
    if MyClassicAddonMinimapButton then
        MyClassicAddonMinimapButton:SetAngle(Config.MinimapButtonPosition)
    end
end

function Debug()
    -- Add debug functionality if needed
    print("MinimapConfig:", MinimapConfig)
end

function ToggleMinimapButton()
    MinimapConfig.ShowMinimapButton = not MinimapConfig.ShowMinimapButton
    Raise(EVENTS.MINIMAP_BUTTON_VISIBILITY_CHANGED)
end

function SetXPDisplayMode(mode)
    MinimapConfig.XPDisplayMode = mode
    Raise(EVENTS.XP_DISPLAY_MODE_CHANGED)
end

function GetXPDisplayMode()
    return MinimapConfig.XPDisplayMode
end

function UpdateLastXPGain(xpGained, source)
    MinimapConfig.lastXPGain = xpGained
    MinimapConfig.lastXPSource = source
    UpdateKillsToLevel()
end

function UpdateKillsToLevel()
    if MinimapConfig.lastXPGain > 0 then
        local currentXP = UnitXP("player")
        local maxXP = UnitXPMax("player")
        local xpNeeded = maxXP - currentXP
        MinimapConfig.killsToLevel = math.ceil(xpNeeded / MinimapConfig.lastXPGain)
    end
end

function GetKillsToLevel()
    return MinimapConfig.killsToLevel
end

function GetLastXPSource()
    return MinimapConfig.lastXPSource
end