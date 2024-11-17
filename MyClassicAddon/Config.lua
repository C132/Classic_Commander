Config = Config or {}
Config.callbacks = {}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

EVENTS = {
    CHAT_VISIBILITY_CHANGED = "CHAT_VISIBILITY_CHANGED",
    ACTIONBAR_UNLOCKED = "ACTIONBAR_UNLOCKED", 
    FIVE_SECOND_RULE_CHANGED = "FIVE_SECOND_RULE_CHANGED",
    BAG_BUTTONS_VISIBILITY_CHANGED = "BAG_BUTTONS_VISIBILITY_CHANGED",
    FADE_BAGS_WHILE_MOVING_CHANGED = "FADE_BAGS_WHILE_MOVING_CHANGED",
    ACTIONBAR_COST_MODE_CHANGED = "ACTIONBAR_COST_MODE_CHANGED",
    UNIT_FRAMES_VISIBILITY_CHANGED = "UNIT_FRAMES_VISIBILITY_CHANGED",
}

local function OnAwake()
    if Config == nil then print("No config found") end
    Config.ShowChatWindow = Config.ShowChatWindow or false
    Config.ActionBarPosition = Config.ActionBarPosition or {}
    Config.UnlockActionBar = Config.UnlockActionBar or false
    Config.ShowFiveSecondRule = Config.ShowFiveSecondRule or false
    Config.ShowBagButtons = Config.ShowBagButtons or true
    Config.FadeBagsWhileMoving = Config.FadeBagsWhileMoving or false
    Config.BagPositions = Config.BagPositions or {}
    Config.ActionBarCostMode = Config.ActionBarCostMode or "RAW_COST"
    Config.cachedOutputs = Config.cachedOutputs or {}
    Config.HideUnitFrames = Config.HideUnitFrames or false
end

local function OnStart()
    -- Initialize any necessary components or features
end

local function OnDestroy()
    -- Save any necessary data before logout
    for i = 0, 4 do
        SaveBagPosition(i)
    end
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
    if not Config.callbacks[event] then
        Config.callbacks[event] = {}
    end
    table.insert(Config.callbacks[event], func)
end

function Raise(event)
    if event and Config.callbacks[event] then
        for _, func in ipairs(Config.callbacks[event]) do
            func()
        end
    end
end

function SaveBagPosition(bagID)
    local bagFrame = _G["ContainerFrame"..bagID]
    if bagFrame then
        local point, _, relativePoint, xOfs, yOfs = bagFrame:GetPoint()
        Config.BagPositions[bagID] = {point = point, relativePoint = relativePoint, xOfs = xOfs, yOfs = yOfs}
    end
end

function LoadBagPosition(bagID)
    if Config.BagPositions[bagID] then
        local pos = Config.BagPositions[bagID]
        local bagFrame = _G["ContainerFrame"..bagID]
        if bagFrame then
            bagFrame:ClearAllPoints()
            if pos.point and pos.relativePoint and pos.xOfs and pos.yOfs then
                bagFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOfs, pos.yOfs)
            else
                bagFrame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -50, 50)
            end
        end
    end
end

function Debug()
    -- Add debug functionality if needed
    print("Config:", Config)
    print("Cached Outputs:", Config.cachedOutputs)
end

function UpdateCachedOutputs(newCachedOutputs)
    Config.cachedOutputs = newCachedOutputs
end

function GetCachedOutputs()
    return Config.cachedOutputs
end

function ToggleUnitFrames()
    Config.HideUnitFrames = not Config.HideUnitFrames
    Raise(EVENTS.UNIT_FRAMES_VISIBILITY_CHANGED)
end

function GetUnitFramesVisibility()
    return not Config.HideUnitFrames
end