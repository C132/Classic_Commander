-- Commander Radar: cosmetic radar overlay for the (square) Commander
-- minimap — a rotating sweep line and an optional crosshair. The sweep is
-- a thin full-diameter line rotating about the map center, sized to the
-- inscribed circle so it never pokes past the square's edges.

local overlay = CreateFrame("Frame", "CommanderRadarOverlay", Minimap)
overlay:SetAllPoints(Minimap)
overlay:SetFrameStrata("LOW")
overlay:Hide()

local sweep = overlay:CreateTexture(nil, "OVERLAY")
sweep:SetTexture("Interface\\Buttons\\WHITE8X8")
sweep:SetVertexColor(0.3, 1, 0.4)
sweep:SetPoint("CENTER")

local crosshairH = overlay:CreateTexture(nil, "OVERLAY")
crosshairH:SetTexture("Interface\\Buttons\\WHITE8X8")
crosshairH:SetVertexColor(0.3, 1, 0.4, 0.1)
crosshairH:SetPoint("CENTER")

local crosshairV = overlay:CreateTexture(nil, "OVERLAY")
crosshairV:SetTexture("Interface\\Buttons\\WHITE8X8")
crosshairV:SetVertexColor(0.3, 1, 0.4, 0.1)
crosshairV:SetPoint("CENTER")

local rotation = 0

local function Layout()
    local side = math.min(Minimap:GetWidth() or 140, Minimap:GetHeight() or 140)
    local length = side * 0.95
    sweep:SetSize(length, 1.2)
    crosshairH:SetSize(length, 1)
    crosshairV:SetSize(1, length)
end

local function OnSweepUpdate(self, elapsed)
    rotation = rotation + elapsed * (CommanderRadarDB.SweepSpeed or 0.5) * math.pi * 2
    if rotation > math.pi * 2 then
        rotation = rotation - math.pi * 2
    end
    sweep:SetRotation(rotation)
end

local function Apply()
    if not (CommanderRadarDB and CommanderRadarDB.EnableRadar) then
        overlay:Hide()
        return
    end
    Layout()
    local anyShown = false
    if CommanderRadarDB.ShowSweep then
        sweep:SetVertexColor(0.3, 1, 0.4, CommanderRadarDB.SweepOpacity or 0.25)
        sweep:Show()
        anyShown = true
    else
        sweep:Hide()
    end
    -- Only drive the rotation while the sweep is actually shown; a
    -- crosshair-only radar is static and needs no per-frame work
    overlay:SetScript("OnUpdate", CommanderRadarDB.ShowSweep and OnSweepUpdate or nil)
    crosshairH:SetShown(CommanderRadarDB.ShowCrosshair)
    crosshairV:SetShown(CommanderRadarDB.ShowCrosshair)
    if CommanderRadarDB.ShowCrosshair then
        anyShown = true
    end
    overlay:SetShown(anyShown)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        Commander.AddListener(COMMANDER_RADAR_EVENTS.UPDATE, Apply)
        -- Re-fit when the minimap scale setting changes
        if COMMANDER_MINIMAP_EVENTS then
            Commander.AddListener(COMMANDER_MINIMAP_EVENTS.COMMANDER_MINIMAP, Apply)
        end
        Apply()
    end
end)
