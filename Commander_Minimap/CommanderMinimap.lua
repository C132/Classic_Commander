-- Commander_Minimap.lua

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Constants
local MINIMAP_SCALE = 1.37 -- Adjust this value to change minimap size (1.0 is default)
local CLOCK_OFFSET_X = 48 -- Horizontal offset for clock position
local CLOCK_OFFSET_Y = 14 -- Vertical offset for clock position
local ZONE_TEXT_OFFSET_Y = -2 -- Vertical offset for zone text

-- Hide default minimap art and elements
--MinimapBackdrop:Hide()
MinimapBorderTop:Hide()
MinimapZoomOut:Hide()
MinimapZoomIn:Hide()
MinimapToggleButton:Hide()
MinimapNorthTag:Hide()
MinimapBorder:Hide()
GameTimeFrame:Hide()
MinimapZoneTextButton:Hide()

-- Create custom zone text
local zoneText = Minimap:CreateFontString(nil, "OVERLAY")
zoneText:SetFontObject(GameFontNormal)
zoneText:SetPoint("TOP", Minimap, "TOP", 0, ZONE_TEXT_OFFSET_Y)

frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Minimap" then
        print("Commander_Minimap loaded successfully!")
        Minimap:SetMaskTexture("Interface\\BUTTONS\\WHITE8X8")
        Minimap:SetScale(MINIMAP_SCALE)
        
        -- Update zone text
        zoneText:SetText(GetMinimapZoneText())
    
        -- Position clock like SC2 style - top right corner of minimap
        if TimeManagerClockButton then
            TimeManagerClockButton:SetParent(UIParent)
            TimeManagerClockButton:ClearAllPoints()
            TimeManagerClockButton:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", CLOCK_OFFSET_X, CLOCK_OFFSET_Y)
            TimeManagerClockButton:SetFrameStrata("HIGH")
            -- Make clock text more visible
            local regions = {TimeManagerClockButton:GetRegions()}
            for _, region in ipairs(regions) do
                if region:GetObjectType() == "FontString" then
                    region:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
                    region:SetTextColor(1, 1, 1)
                end
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Reposition clock after entering world to ensure it stays in position
        if TimeManagerClockButton then
            TimeManagerClockButton:ClearAllPoints()
            TimeManagerClockButton:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", CLOCK_OFFSET_X, CLOCK_OFFSET_Y)
            TimeManagerClockButton:SetAlpha(0.77)
        end
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

-- Add scroll zoom functionality
Minimap:EnableMouseWheel(true)
Minimap:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then
        Minimap_ZoomIn()
    else
        Minimap_ZoomOut()
    end
end)

-- Update zone text when zone changes
Minimap:SetScript("OnUpdate", function()
    zoneText:SetText(GetMinimapZoneText())

    if LFGMinimapFrame then
        LFGMinimapFrame:ClearAllPoints()
        LFGMinimapFrame:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 36, -6)
        --MinimapBackdrop:Hide()
    end
end)
