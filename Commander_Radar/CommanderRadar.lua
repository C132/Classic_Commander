-- Commander Radar: the minimap as an early-warning system. The rotating
-- sweep is the display; nameplate appearances are the sensor. Hostile mobs
-- turn the sweep amber, a hostile PLAYER turns it red and raises a klaxon
-- callout — the alert you actually want while leveling on a contested
-- realm, where the minimap itself shows nothing until it is too late.
-- (Detection rides NAME_PLATE_UNIT_ADDED, so enemy nameplates must be
-- shown — the V key — for contacts to register.)

local PLAYER_ALERT_COOLDOWN = 30

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

local contactText = overlay:CreateFontString(nil, "OVERLAY")
contactText:SetFontObject(GameFontHighlightSmall)
contactText:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 2)
contactText:Hide()

local rotation = 0

-- ---------------------------------------------------------------------------
-- Contact tracking: nameplate tokens are transient, so remember what each
-- token pointed at when it appeared and resolve removals from that.
-- ---------------------------------------------------------------------------
local contactsByGUID = {}   -- guid -> { player = bool }
local guidByToken = {}      -- "nameplate3" -> guid
local mobCount, playerCount = 0, 0
local lastPlayerAlert = -math.huge

local function SweepColor()
    if playerCount > 0 then
        return 1, 0.25, 0.2      -- red: enemy player on the scope
    elseif mobCount > 0 then
        return 1, 0.72, 0.15     -- amber: hostile mobs around
    end
    return 0.3, 1, 0.4           -- green: clear
end

local function RefreshContactDisplay()
    sweep:SetVertexColor(SweepColor())
    sweep:SetAlpha(CommanderRadarDB.SweepOpacity or 0.25)
    if CommanderRadarDB.ContactCounter and (mobCount + playerCount) > 0 then
        if playerCount > 0 then
            contactText:SetText(string.format("|cffff4030CONTACTS: %d (%d player%s)|r",
                mobCount + playerCount, playerCount, playerCount == 1 and "" or "s"))
        else
            contactText:SetText(string.format("|cffffb830CONTACTS: %d|r", mobCount))
        end
        contactText:Show()
    else
        contactText:Hide()
    end
end

local function OnContactAdded(token)
    if not CommanderRadarDB.ContactDetection then return end
    if not (UnitGUID and UnitCanAttack("player", token)) then return end
    if UnitIsDeadOrGhost(token) then return end
    -- Attackable is not hostile: neutral mobs (yellow) and duel opponents
    -- are both attackable — only genuinely hostile reactions count as
    -- contacts (reaction 1-3; 4 is neutral)
    if UnitReaction then
        local reaction = UnitReaction("player", token)
        if reaction and reaction > 3 then return end
    end
    local guid = UnitGUID(token)
    if not guid or contactsByGUID[guid] then
        guidByToken[token] = guid
        return
    end
    local isPlayer = UnitIsPlayer(token)
    contactsByGUID[guid] = { player = isPlayer }
    guidByToken[token] = guid
    if isPlayer then
        playerCount = playerCount + 1
        if CommanderRadarDB.PlayerAlert and (GetTime() - lastPlayerAlert) >= PLAYER_ALERT_COOLDOWN then
            lastPlayerAlert = GetTime()
            PlaySound(SOUNDKIT.RAID_WARNING, "Master")
            print(string.format("|cffff4030Commander Radar:|r enemy player contact — %s",
                UnitName(token) or "unknown"))
        end
    else
        mobCount = mobCount + 1
    end
    RefreshContactDisplay()
end

local function OnContactRemoved(token)
    local guid = guidByToken[token]
    guidByToken[token] = nil
    if not guid then return end
    local contact = contactsByGUID[guid]
    if not contact then return end
    contactsByGUID[guid] = nil
    if contact.player then
        playerCount = math.max(playerCount - 1, 0)
    else
        mobCount = math.max(mobCount - 1, 0)
    end
    RefreshContactDisplay()
end

local function ResetContacts()
    wipe(contactsByGUID)
    wipe(guidByToken)
    mobCount, playerCount = 0, 0
    RefreshContactDisplay()
end

-- ---------------------------------------------------------------------------
-- Sweep + layout
-- ---------------------------------------------------------------------------
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
        overlay:SetScript("OnUpdate", nil)
        ResetContacts()
        return
    end
    Layout()
    local anyShown = false
    if CommanderRadarDB.ShowSweep then
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
    if not CommanderRadarDB.ContactDetection then
        ResetContacts()
    else
        -- Sweep already-visible nameplates so (re)enabling detection does
        -- not show a green scope with enemies plainly on screen
        if C_NamePlate and C_NamePlate.GetNamePlates then
            for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
                local token = plate.namePlateUnitToken
                    or (plate.UnitFrame and plate.UnitFrame.unit)
                if token then
                    OnContactAdded(token)
                end
            end
        end
        if CommanderRadarDB.ContactCounter then
            anyShown = true
        end
    end
    RefreshContactDisplay()
    overlay:SetShown(anyShown)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        Commander.AddListener(COMMANDER_RADAR_EVENTS.UPDATE, Apply)
        if COMMANDER_MINIMAP_EVENTS then
            Commander.AddListener(COMMANDER_MINIMAP_EVENTS.COMMANDER_MINIMAP, Apply)
        end
        Apply()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if CommanderRadarDB and CommanderRadarDB.EnableRadar then
            OnContactAdded(arg1)
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        OnContactRemoved(arg1)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Zone transition: every nameplate is gone, start a clean scope
        ResetContacts()
    end
end)
