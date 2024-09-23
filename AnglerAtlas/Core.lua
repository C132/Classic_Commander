
local function LoadSettings()
    if AnglerAtlasSettings == nil then 
        AnglerAtlasSettings = {}
    end
    if AnglerAtlasSettings.miniMapIcon == nil then
        AnglerAtlasSettings.miniMapIcon = {
            iconName = "AnglerAtlas",
            hide = false,
            minimapPos = 213.7
        }
    end
    if AnglerAtlasSettings.showSpellbookButton == nil then
        AnglerAtlasSettings.showSpellbookButton = true
    end
end

local EventFrame = CreateFrame("Frame")

EventFrame:RegisterEvent("ADDON_LOADED")
EventFrame:RegisterEvent("PLAYER_LOGOUT")
EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
EventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
EventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

local function On_AddonLoaded()
    LoadSettings()
    AnglerAtlas.UI:Build()
    AnglerAtlas:SelectFish(nil)
end

local function On_PlayerLogout()
end

local function On_PlayerEnteringWorld()
    AnglerAtlas:loadPlayerData()
end

local function On_SomethingInterestingChanged()
    AnglerAtlas:Reload()
end

EventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "AnglerAtlas" then
        On_AddonLoaded()
    elseif event == "PLAYER_LOGOUT" then
        On_PlayerLogout()
    elseif event == "PLAYER_ENTERING_WORLD" then
        On_PlayerEnteringWorld()
    elseif event == "UNIT_INVENTORY_CHANGED" or 
    event == "PLAYER_EQUIPMENT_CHANGED" or
    event == "SKILL_LINES_CHANGED" then
        On_SomethingInterestingChanged()
    end
end)

local function OnCommand(msg)
    AnglerAtlas.UI:ToggleUI()
end
SLASH_ANGLER_TOGGLE1 = "/aa"
SLASH_ANGLER_TOGGLE2 = "/angler"
SLASH_ANGLER_TOGGLE3 = "/angleratlas"
SlashCmdList["ANGLER_TOGGLE"] = OnCommand

