-- Commander Afflictions: live tracker for debuffs the PLAYER has applied.
-- Two sources keep the board truthful:
--   1. The combat log (APPLIED/REFRESH add, REMOVED/BROKEN/DISPEL/UNIT_DIED
--      delete) — authoritative about existence, knows nothing of durations.
--   2. C_UnitAuras scans of units we can address (target, mouseover) refine
--      entries with exact expiration times where sourceUnit == "player".
-- Entries whose duration is unknown show as full bars until the combat log
-- removes them or a scan pins them down; a 40s fallback prunes strays that
-- expire out of combat-log range.

local BAR_WIDTH = 130
local BAR_HEIGHT = 12
local ROW_GAP = 4
local DRAW_THROTTLE = 0.1
local UNKNOWN_MAX_AGE = 40

local active = {}   -- key destGUID..spellID -> entry
local rowPool = {}
local sinceDraw = 0

local root = CreateFrame("Frame", "CommanderAfflictionsFrame", UIParent)
root:SetPoint("LEFT", UIParent, "LEFT", 14, 120)
root:SetSize(BAR_WIDTH + 20, 12 * (BAR_HEIGHT + ROW_GAP))
root:SetFrameStrata("MEDIUM")
root:Hide()

local function AcquireRow(index)
    local row = rowPool[index]
    if row then return row end
    row = CreateFrame("Frame", nil, root)
    row:SetSize(BAR_WIDTH + 20, BAR_HEIGHT)
    row:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -(index - 1) * (BAR_HEIGHT + ROW_GAP))

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(BAR_HEIGHT, BAR_HEIGHT)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.barBG = row:CreateTexture(nil, "BACKGROUND")
    row.barBG:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.barBG:SetVertexColor(0, 0, 0, 0.55)
    row.barBG:SetSize(BAR_WIDTH, BAR_HEIGHT)
    row.barBG:SetPoint("LEFT", row, "LEFT", BAR_HEIGHT + 4, 0)

    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.bar:SetVertexColor(0.7, 0.35, 1, 0.9)
    row.bar:SetSize(1, BAR_HEIGHT)
    row.bar:SetPoint("LEFT", row.barBG, "LEFT", 0, 0)

    row.label = row:CreateFontString(nil, "OVERLAY")
    row.label:SetFontObject(GameFontHighlightSmall)
    row.label:SetPoint("LEFT", row.barBG, "LEFT", 3, 0)
    row.label:SetPoint("RIGHT", row.barBG, "RIGHT", -3, 0)
    row.label:SetJustifyH("LEFT")

    rowPool[index] = row
    return row
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
    for i = 1, shown do
        local row = AcquireRow(i)
        local item = queue[i]
        local entry = item.entry
        row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        if item.remaining and entry.duration and entry.duration > 0 then
            local progress = item.remaining / entry.duration
            row.bar:SetSize(math.max(BAR_WIDTH * progress, 1), BAR_HEIGHT)
        else
            row.bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
        end
        local text = entry.spellName or "?"
        if CommanderAfflictionsDB.ShowTargetNames and entry.targetName then
            text = string.format("%s @ %s", text, entry.targetName)
        end
        if item.remaining then
            text = string.format("%s  %ds", text, math.ceil(item.remaining))
        end
        row.label:SetText(text)
        row:Show()
    end
    for i = shown + 1, #rowPool do
        rowPool[i]:Hide()
    end
    root:SetShown(shown > 0)
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
    SPELL_AURA_STOLEN = true,
    SPELL_DISPEL = true,
}

local function OnCombatLog()
    local _, subevent, _, sourceGUID, _, _, _, destGUID, destName,
        _, _, spellID, spellName, _, extraID, extraName = CombatLogGetCurrentEventInfo()
    if subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" then
        RemoveAllForGUID(destGUID)
        return
    end
    if AURA_ADD_EVENTS[subevent] then
        if sourceGUID == UnitGUID("player") then
            AddOrRefresh(destGUID, destName, spellID, spellName)
        end
    elseif AURA_REMOVE_EVENTS[subevent] then
        if subevent == "SPELL_DISPEL" or subevent == "SPELL_AURA_STOLEN" then
            -- For dispels the removed aura is the EXTRA spell, and anyone
            -- may be the dispeller — match on the affected unit + aura
            RemoveByGUIDSpell(destGUID, extraID)
        else
            RemoveByGUIDSpell(destGUID, spellID)
        end
    end
end

local function Apply()
    if CommanderAfflictionsDB and CommanderAfflictionsDB.EnableAfflictions then
        Commander.UI.ApplyHudChrome(root, CommanderAfflictionsDB, "Hud", {
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
    elseif event == "UNIT_AURA" then
        if arg1 == "target" or arg1 == "mouseover" then
            ScanUnit(arg1)
        end
    end
end)
