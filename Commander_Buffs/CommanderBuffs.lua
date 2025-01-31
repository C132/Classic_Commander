local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("UNIT_AURA")
local loaded = false

local function UpdateBuffFrame()
    if CommanderBuffsDB.ShowBuffFrame then
        -- Implementation for showing/updating buff frame will go here
    end
end

local function OnUpdate()
    UpdateBuffFrame()
end

local function OnAwake()
    AddListener(COMMANDER_BUFFS_EVENTS.UPDATE, OnUpdate)
    Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
end

local function OnDestroy() end

local function OnEvent(self, event, ...)
    if event == "PLAYER_LOGIN" then
        OnAwake()
        loaded = true
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif loaded then
        OnUpdate()
    end
end

frame:SetScript("OnEvent", OnEvent)
