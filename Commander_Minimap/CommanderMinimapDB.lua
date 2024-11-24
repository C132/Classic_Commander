CommanderMinimapDB = CommanderMinimapDB or {}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")

COMMANDER_MINIMAP_EVENTS = {
    COMMANDER_MINIMAP = "COMMANDER_MINIMAP",
}

local defaultSettings = {
    ShowMinimapButton = true,
    MinimapButtonPosition = 0,
    XPDisplayMode = "PERCENTAGE",
}

for key, value in pairs(defaultSettings) do
    if CommanderMinimapDB[key] == nil then
        CommanderMinimapDB[key] = value
    end
end

local function OnAwake()
    if CommanderMinimapDB == nil then print("No Minimap DB found") end
    CommanderMinimapDB.ShowMinimapButton = CommanderMinimapDB.ShowMinimapButton or true
    CommanderMinimapDB.MinimapButtonPosition = CommanderMinimapDB.MinimapButtonPosition or 0
    CommanderMinimapDB.XPDisplayMode = CommanderMinimapDB.XPDisplayMode or "PERCENTAGE"
    CommanderMinimapDB.lastXPGain = CommanderMinimapDB.lastXPGain or 0
    CommanderMinimapDB.killsToLevel = CommanderMinimapDB.killsToLevel or 0
    CommanderMinimapDB.lastXPSource = CommanderMinimapDB.lastXPSource or ""
    LoadMinimapButtonPosition()
end

function SaveMinimapButtonPosition()
    CommanderMinimapDB.MinimapButtonPosition = CommanderMinimapButton and CommanderMinimapButton:GetAngle() or 0
end

function LoadMinimapButtonPosition()
    if CommanderMinimapButton then
        CommanderMinimapButton:SetAngle(CommanderMinimapDB.MinimapButtonPosition)
    end
end

function ToggleMinimapButton()
    CommanderMinimapDB.ShowMinimapButton = not CommanderMinimapDB.ShowMinimapButton
    Notify(COMMANDER_MINIMAP_EVENTS.COMMANDER_MINIMAP)
end

function SetXPDisplayMode(mode)
    CommanderMinimapDB.XPDisplayMode = mode
    Notify(COMMANDER_MINIMAP_EVENTS.COMMANDER_MINIMAP)
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

local function OnEvent(self, event, ...)
    if event == "PLAYER_LOGIN" then
        OnAwake()
    end
end

frame:SetScript("OnEvent", OnEvent)