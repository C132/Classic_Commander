-- Commander_Minimap.lua

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_INDOORS")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

-- Constants
local CLOCK_OFFSET_X = 48 -- Horizontal offset for clock position
local CLOCK_OFFSET_Y = 14 -- Vertical offset for clock position
local ZONE_TEXT_OFFSET_Y = -2 -- Vertical offset for zone text

-- Scale is a saved setting (Commander Minimap options); 1.37 is the default
local function ApplyMinimapScale()
    Minimap:SetScale((CommanderMinimapDB and CommanderMinimapDB.MinimapScale) or 1.37)
end

local ApplyTidy -- defined below; referenced by the event handler above it

-- Hide default minimap art and elements
--MinimapBackdrop:Hide()
MinimapCluster.BorderTop:Hide() -- MinimapBorderTop global no longer exists on 2.5.5
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

local function UpdateZoneText()
    zoneText:SetText(GetMinimapZoneText())
end

local function PositionLFGButton()
    if LFGMinimapFrame then
        LFGMinimapFrame:ClearAllPoints()
        LFGMinimapFrame:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 36, -6)
        --MinimapBackdrop:Hide()
    end
end

frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Minimap" then
        Minimap:SetMaskTexture("Interface\\BUTTONS\\WHITE8X8")
        -- CommanderMinimapDB.lua loads first and merges defaults in its own
        -- ADDON_LOADED handler, so the saved scale is available here
        ApplyMinimapScale()
        Commander.AddListener(COMMANDER_MINIMAP_EVENTS.COMMANDER_MINIMAP, ApplyMinimapScale)
        Commander.AddListener(COMMANDER_MINIMAP_EVENTS.COMMANDER_MINIMAP, ApplyTidy)

        -- Update zone text
        UpdateZoneText()
    
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
        UpdateZoneText()
        PositionLFGButton()
        -- Fade third-party minimap buttons now, and again shortly after —
        -- most addons create their buttons at or after PLAYER_LOGIN
        ApplyTidy()
        C_Timer.After(5, ApplyTidy)
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
        UpdateZoneText()
    end
end)

-- ---------------------------------------------------------------------------
-- Tidy addon buttons: third-party minimap buttons stay faded until the mouse
-- is over the minimap. Blizzard's own elements and the Commander information
-- button are never touched (allowlist below); everything else parented to
-- the Minimap fades to the configured opacity.
local TIDY_KEEP = {
    CommanderMinimapButton = true,
    MiniMapTracking = true,
    MiniMapTrackingFrame = true,
    MiniMapTrackingButton = true,
    MiniMapMailFrame = true,
    GameTimeFrame = true,
    TimeManagerClockButton = true,
    MinimapZoomIn = true,
    MinimapZoomOut = true,
    MinimapZoneTextButton = true,
    MinimapBackdrop = true,
    MiniMapWorldMapButton = true,
    MinimapToggleButton = true,
    LFGMinimapFrame = true,
    MiniMapBattlefieldFrame = true,
    MiniMapLFGFrame = true,
    MiniMapInstanceDifficulty = true,
    QueueStatusMinimapButton = true,
}

local tidyButtons = {}
local revealTicker
local revealed = false

local RevealButtons -- forward declaration (hooked onto collected buttons)

-- Re-enumerated on every apply/reveal so buttons created late (most addons
-- spawn theirs at PLAYER_LOGIN or later) are always picked up
local function CollectTidyButtons()
    tidyButtons = {}
    local children = { Minimap:GetChildren() }
    for _, child in ipairs(children) do
        local name = child.GetName and child:GetName()
        if not (name and TIDY_KEEP[name]) then
            tidyButtons[#tidyButtons + 1] = child
            -- Entering a rim button directly (without crossing the minimap
            -- circle) must also reveal the set
            if not child.__commanderTidyHooked then
                child.__commanderTidyHooked = true
                child:HookScript("OnEnter", RevealButtons)
            end
        end
    end
end

local function SetTidyAlpha(alpha)
    for _, button in ipairs(tidyButtons) do
        button:SetAlpha(alpha)
    end
end

local function HiddenAlpha()
    return (CommanderMinimapDB and CommanderMinimapDB.TidyFadedOpacity) or 0
end

local function ConcealButtons()
    revealed = false
    if revealTicker then
        revealTicker:Cancel()
        revealTicker = nil
    end
    SetTidyAlpha(HiddenAlpha())
end

function RevealButtons()
    if not (CommanderMinimapDB and CommanderMinimapDB.TidyAddonButtons) then return end
    CollectTidyButtons()
    SetTidyAlpha(1)
    revealed = true
    if not revealTicker then
        revealTicker = C_Timer.NewTicker(0.2, function()
            -- Generous padding so hovering rim buttons counts as "over the map"
            if not Minimap:IsMouseOver(24, -24, -24, 24) then
                ConcealButtons()
            end
        end)
    end
end

-- Applied at login, on delayed rescans, and whenever the setting changes
function ApplyTidy()
    CollectTidyButtons()
    if CommanderMinimapDB and CommanderMinimapDB.TidyAddonButtons then
        if not revealed then
            SetTidyAlpha(HiddenAlpha())
        end
    else
        if revealTicker then
            revealTicker:Cancel()
            revealTicker = nil
        end
        revealed = false
        SetTidyAlpha(1)
    end
end

Minimap:HookScript("OnEnter", RevealButtons)

-- Make Minimap draggable (gated by the Lock Minimap setting)
Minimap:SetMovable(true)
Minimap:EnableMouse(true)
Minimap:RegisterForDrag("LeftButton")
Minimap:SetScript("OnDragStart", function(self)
    if CommanderMinimapDB and CommanderMinimapDB.LockMinimap then return end
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

-- Zone text and LFG button updates are event-driven (see OnEvent above)
-- instead of running every frame in OnUpdate
