local function CreateConsoleBackdrop()
    local backdrop = CreateFrame("Frame", "CAB_ConsoleBackdrop", UIParent)
    backdrop:SetFrameStrata("BACKGROUND")
    backdrop:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    backdrop:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)  -- Adjust bottom by 100 pixels
    
    local texture = backdrop:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(backdrop)  -- Set texture to fill the backdrop
    texture:SetTexture("Interface\\AddOns\\Commander_ActionBar\\Textures\\Console2.png")
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetAlpha(1)
    
    -- Adjust the game's viewport
    local worldFrame = WorldFrame
    worldFrame:ClearAllPoints()
    worldFrame:SetPoint("TOPLEFT", 0, 0)
    worldFrame:SetPoint("BOTTOMRIGHT", 0, 150)  -- Leave 100 pixels at the bottom
    
    return backdrop
end

local consoleBackdrop = CreateConsoleBackdrop()

function ToggleConsoleBackdrop()
    if consoleBackdrop:IsShown() then
        consoleBackdrop:Hide()
        WorldFrame:SetPoint("BOTTOMRIGHT", 0, 0)  -- Reset viewport when hiding
    else
        consoleBackdrop:Show()
        WorldFrame:SetPoint("BOTTOMRIGHT", 0, 150)  -- Adjust viewport when showing
    end
end

SLASH_TOGGLECONSOLE1 = "/toggleconsole"
SlashCmdList["TOGGLECONSOLE"] = ToggleConsoleBackdrop

-- Optionally, you can show the backdrop by default
-- consoleBackdrop:Show()
-- WorldFrame:SetPoint("BOTTOMRIGHT", 0, 100)  -- Adjust viewport if showing by default
