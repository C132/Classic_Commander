-- Commander_Minimap.lua

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Minimap" then
        print("Commander_Minimap loaded successfully!")
    end
end)

-- Make Minimap draggable
Minimap:SetMovable(true)
Minimap:EnableMouse(true)
Minimap:RegisterForDrag("LeftButton")
Minimap:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)
Minimap:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
end)
