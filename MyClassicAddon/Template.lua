Template = Template or {}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

local function OnAwake() end

local function OnStart() end

local function OnDestroy() end

frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "MyClassicAddon" then
        OnAwake()
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif event == "PLAYER_ENTERING_WORLD" then
        OnStart()
    end
end)