-- Commander Afflictions: live tracker for debuffs the PLAYER has applied.
-- Two sources keep the board truthful:
--   1. The combat log (APPLIED/REFRESH add, REMOVED/BROKEN/DISPEL/UNIT_DIED
--      delete) — authoritative about existence, knows nothing of durations.
--   2. C_UnitAuras scans of units we can address (target, mouseover) refine
--      entries with exact expiration times where sourceUnit == "player".
-- Entries whose duration is unknown show as full bars until the combat log
-- removes them or a scan pins them down; a 40s fallback prunes strays that
-- expire out of combat-log range.

local BAR_HEIGHT = 12
local ROW_GAP = 4
local ICON_SIZE = 26
local ICON_GAP = 4
local ICON_BAR_HEIGHT = 4
local DRAW_THROTTLE = 0.1
-- Fallback prune for entries whose expiration was never pinned by a scan;
-- generous because unscanned curses/DoTs can legitimately run 2 minutes
local UNKNOWN_MAX_AGE = 120

local active = {}   -- key destGUID..spellID -> entry
local rowPool = {}
local sinceDraw = 0

local root = CreateFrame("Frame", "CommanderAfflictionsFrame", UIParent)
root:SetPoint("LEFT", UIParent, "LEFT", 14, 120)
root:SetSize(150, 12 * (BAR_HEIGHT + ROW_GAP))
root:SetFrameStrata("MEDIUM")
root:Hide()

local function BarWidth()
    return (CommanderAfflictionsDB and CommanderAfflictionsDB.BarWidth) or 130
end

local function LayoutMode()
    return (CommanderAfflictionsDB and CommanderAfflictionsDB.Layout) or "BARS_DOWN"
end

local function AcquireRow(index)
    local row = rowPool[index]
    if row then return row end
    row = CreateFrame("Frame", nil, root)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.barBG = row:CreateTexture(nil, "BACKGROUND")
    row.barBG:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.barBG:SetVertexColor(0, 0, 0, 0.55)
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.bar:SetVertexColor(0.7, 0.35, 1, 0.9)
    row.label = row:CreateFontString(nil, "OVERLAY")
    row.label:SetFontObject(GameFontHighlightSmall)
    row.label:SetJustifyH("LEFT")

    if row.EnableMouseMotion then
        row:EnableMouseMotion(true)
    end
    Commander.UI.AttachTooltip(row, nil, function() return row.tipText end)

    rowPool[index] = row
    return row
end

-- Same layout system as Commander_Production: bars growing down or up, or
-- the SC2-style icon strip with a slim drain bar under each icon
local function ApplyRowGeometry(row, index, layout, barWidth)
    row:ClearAllPoints()
    row.icon:ClearAllPoints()
    row.barBG:ClearAllPoints()
    row.bar:ClearAllPoints()
    row.label:ClearAllPoints()
    if layout == "ICONS" then
        row:SetSize(ICON_SIZE, ICON_SIZE + ICON_BAR_HEIGHT + 2)
        row:SetPoint("TOPLEFT", root, "TOPLEFT", (index - 1) * (ICON_SIZE + ICON_GAP), 0)
        row.icon:SetSize(ICON_SIZE, ICON_SIZE)
        row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        row.barBG:SetSize(ICON_SIZE, ICON_BAR_HEIGHT)
        row.barBG:SetPoint("TOPLEFT", row.icon, "BOTTOMLEFT", 0, -2)
        row.bar:SetSize(1, ICON_BAR_HEIGHT)
        row.bar:SetPoint("LEFT", row.barBG, "LEFT", 0, 0)
        row.label:Hide()
    else
        row:SetSize(barWidth + 20, BAR_HEIGHT)
        if layout == "BARS_UP" then
            row:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, (index - 1) * (BAR_HEIGHT + ROW_GAP))
        else
            row:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -(index - 1) * (BAR_HEIGHT + ROW_GAP))
        end
        row.icon:SetSize(BAR_HEIGHT, BAR_HEIGHT)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.barBG:SetSize(barWidth, BAR_HEIGHT)
        row.barBG:SetPoint("LEFT", row, "LEFT", BAR_HEIGHT + 4, 0)
        row.bar:SetSize(1, BAR_HEIGHT)
        row.bar:SetPoint("LEFT", row.barBG, "LEFT", 0, 0)
        row.label:SetPoint("LEFT", row.barBG, "LEFT", 3, 0)
        row.label:SetPoint("RIGHT", row.barBG, "RIGHT", -3, 0)
        row.label:Show()
    end
    row.geometrySig = layout .. barWidth
end

local function Key(destGUID, spellID)
    return destGUID .. ":" .. tostring(spellID)
end

local function AddOrRefresh(destGUID, destName, spellID, spellName)
    local key = Key(destGUID, spellID)
    local entry = active[key]
    if not entry then
        entry = {
            destGUID = destGUID,
            targetName = destName,
            spellID = spellID,
            spellName = spellName,
            icon = GetSpellTexture and GetSpellTexture(spellID) or nil,
            seen = GetTime(),
        }
        active[key] = entry
    else
        entry.seen = GetTime()
        -- A refresh invalidates any previously scanned expiration; a new
        -- scan will re-pin it
        entry.expiration = nil
        entry.duration = nil
    end
end

local function RemoveByGUIDSpell(destGUID, spellID)
    active[Key(destGUID, spellID)] = nil
end

local function RemoveAllForGUID(destGUID)
    for key, entry in pairs(active) do
        if entry.destGUID == destGUID then
            active[key] = nil
        end
    end
end

-- Refine entries for a unit we can actually address: exact expiration,
-- proper icon, and removal of anything the scan proves is gone
local function ScanUnit(unit)
    if not (C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex and UnitGUID) then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    local found = {}
    for i = 1, 40 do
        local aura = C_UnitAuras.GetDebuffDataByIndex(unit, i)
        if not aura then break end
        if aura.sourceUnit and UnitIsUnit(aura.sourceUnit, "player") then
            local key = Key(guid, aura.spellId)
            found[key] = true
            local entry = active[key]
            if not entry then
                AddOrRefresh(guid, UnitName(unit), aura.spellId, aura.name)
                entry = active[key]
            end
            entry.spellName = aura.name or entry.spellName
            entry.icon = aura.icon or entry.icon
            if aura.expirationTime and aura.expirationTime > 0 then
                entry.expiration = aura.expirationTime
                entry.duration = aura.duration
            end
        end
    end
    -- The scan is authoritative for this GUID: entries it did not see are
    -- gone (dispelled before we ever caught a removal, or misattributed)
    for key, entry in pairs(active) do
        if entry.destGUID == guid and not found[key] then
            active[key] = nil
        end
    end
end

local function Draw()
    local now = GetTime()
    local queue = {}
    for key, entry in pairs(active) do
        local remaining
        if entry.expiration then
            remaining = entry.expiration - now
        end
        if remaining and remaining <= 0 then
            active[key] = nil
        elseif not entry.expiration and (now - entry.seen) > UNKNOWN_MAX_AGE then
            active[key] = nil
        else
            queue[#queue + 1] = { key = key, entry = entry, remaining = remaining }
        end
    end
    table.sort(queue, function(a, b)
        local ra, rb = a.remaining or math.huge, b.remaining or math.huge
        if ra ~= rb then return ra < rb end
        return a.key < b.key
    end)

    local maxBars = CommanderAfflictionsDB.MaxBars or 6
    local shown = math.min(#queue, maxBars)
    local layout = LayoutMode()
    local barWidth = BarWidth()
    local geometrySig = layout .. barWidth
    for i = 1, shown do
        local row = AcquireRow(i)
        if row.geometrySig ~= geometrySig then
            ApplyRowGeometry(row, i, layout, barWidth)
        end
        local item = queue[i]
        local entry = item.entry
        row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        local fillWidth = (layout == "ICONS") and ICON_SIZE or barWidth
        local fillHeight = (layout == "ICONS") and ICON_BAR_HEIGHT or BAR_HEIGHT
        if item.remaining and entry.duration and entry.duration > 0 then
            local progress = item.remaining / entry.duration
            row.bar:SetSize(math.max(fillWidth * progress, 1), fillHeight)
        else
            row.bar:SetSize(fillWidth, fillHeight)
        end
        local text = entry.spellName or "?"
        if CommanderAfflictionsDB.ShowTargetNames and entry.targetName then
            text = string.format("%s @ %s", text, entry.targetName)
        end
        if item.remaining then
            text = string.format("%s  %ds", text, math.ceil(item.remaining))
        end
        if layout ~= "ICONS" then
            row.label:SetText(text)
        end
        row.tipText = text
        row:Show()
    end
    for i = shown + 1, #rowPool do
        rowPool[i]:Hide()
    end
    -- Fixed size keeps a stable footprint for the styled backdrop
    local slots = CommanderAfflictionsDB.FixedHeight
        and (CommanderAfflictionsDB.MaxBars or 6) or math.max(shown, 1)
    if layout == "ICONS" then
        root:SetSize(slots * (ICON_SIZE + ICON_GAP) - ICON_GAP, ICON_SIZE + ICON_BAR_HEIGHT + 2)
    else
        root:SetSize(barWidth + 20, slots * (BAR_HEIGHT + ROW_GAP))
    end
    root:SetShown(shown > 0 or CommanderAfflictionsDB.AlwaysShow
        or Commander.UI.HudUnlocked(CommanderAfflictionsDB, "Hud"))
end

-- Injects fake entries so the board can be inspected without combat:
-- three decaying afflictions plus one unknown-duration entry, all pruned
-- by their own timers like the real thing
function CommanderAfflictions_Test()
    if not (CommanderAfflictionsDB and CommanderAfflictionsDB.EnableAfflictions) then
        print("Commander Afflictions: module is disabled (enable it in settings or /caff)")
        return
    end
    local now = GetTime()
    local samples = {
        { spell = "Test Corruption", duration = 18, icon = "Interface\\Icons\\Spell_Shadow_AbominationExplosion" },
        { spell = "Test Curse", duration = 12, icon = "Interface\\Icons\\Spell_Shadow_CurseOfTounges" },
        { spell = "Test Rend", duration = 8, icon = "Interface\\Icons\\Ability_Gouge" },
    }
    for i, sample in ipairs(samples) do
        active["testboard:" .. i] = {
            destGUID = "testboard",
            targetName = "Training Dummy",
            spellID = -i,
            spellName = sample.spell,
            icon = sample.icon,
            seen = now,
            expiration = now + sample.duration,
            duration = sample.duration,
        }
    end
    active["testboard:unknown"] = {
        destGUID = "testboard",
        targetName = "Training Dummy",
        spellID = -99,
        spellName = "Test Unknown Duration",
        icon = "Interface\\Icons\\INV_Misc_QuestionMark",
        seen = now - (UNKNOWN_MAX_AGE - 10),
    }
    Draw()
    print("Commander Afflictions: test board injected — bars drain and clear themselves")
end

root:SetScript("OnUpdate", function(self, elapsed)
    sinceDraw = sinceDraw + elapsed
    if sinceDraw >= DRAW_THROTTLE then
        sinceDraw = 0
        Draw()
    end
end)

local AURA_ADD_EVENTS = {
    SPELL_AURA_APPLIED = true,
    SPELL_AURA_APPLIED_DOSE = true,
    SPELL_AURA_REFRESH = true,
}
local AURA_REMOVE_EVENTS = {
    SPELL_AURA_REMOVED = true,
    SPELL_AURA_BROKEN = true,
    SPELL_AURA_BROKEN_SPELL = true,
    SPELL_STOLEN = true,
    SPELL_DISPEL = true,
}

local function OnCombatLog()
    local _, subevent, _, sourceGUID, _, _, _, destGUID, destName,
        destFlags, _, spellID, spellName, _, arg15, arg16 = CombatLogGetCurrentEventInfo()
    if subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" then
        -- Only wipe NPC deaths outright: player "deaths" include Feign
        -- Death, and real player deaths emit REMOVED for each aura anyway
        if destFlags and bit.band(destFlags, COMBATLOG_OBJECT_CONTROL_NPC) > 0 then
            RemoveAllForGUID(destGUID)
            Draw()
        end
        return
    end
    if AURA_ADD_EVENTS[subevent] then
        -- arg15 is the aura type; buffs and HoTs the player casts on
        -- friends are not afflictions
        if sourceGUID == UnitGUID("player") and arg15 == "DEBUFF" then
            AddOrRefresh(destGUID, destName, spellID, spellName)
            Draw()
        end
    elseif AURA_REMOVE_EVENTS[subevent] then
        if subevent == "SPELL_DISPEL" or subevent == "SPELL_STOLEN" then
            -- For dispels the removed aura is the EXTRA spell (arg16 name,
            -- arg15 id), and anyone may be the dispeller — match on the
            -- affected unit + aura
            RemoveByGUIDSpell(destGUID, arg15)
        else
            RemoveByGUIDSpell(destGUID, spellID)
        end
        Draw()
    end
end

local function Apply()
    if CommanderAfflictionsDB and CommanderAfflictionsDB.EnableAfflictions then
        Commander.UI.ApplyHudChrome(root, CommanderAfflictionsDB, "Hud", {
            title = "Afflictions",
            defaultPoint = { point = "LEFT", x = 14, y = 120 },
        })
        Draw()
    else
        wipe(active)
        root:Hide()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("UNIT_AURA")
events:SetScript("OnEvent", function(self, event, arg1)
    if not (CommanderAfflictionsDB and CommanderAfflictionsDB.EnableAfflictions) then
        if event == "PLAYER_LOGIN" then
            Commander.AddListener(COMMANDER_AFFLICTIONS_EVENTS.UPDATE, Apply)
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        Commander.AddListener(COMMANDER_AFFLICTIONS_EVENTS.UPDATE, Apply)
        Apply()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
    elseif event == "PLAYER_TARGET_CHANGED" then
        ScanUnit("target")
        Draw()
    elseif event == "UNIT_AURA" then
        if arg1 == "target" or arg1 == "mouseover" then
            ScanUnit(arg1)
            Draw()
        end
    end
end)
