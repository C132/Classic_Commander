-- Commander Forecast — the numbers on the icons.
--
-- Three jobs live here and nothing else: find the action buttons and hang a
-- font string on each, ask the Model what the slot's spell is worth right now,
-- and feed the Model everything your combat log says about what your spells
-- actually landed for. The arithmetic is all in CommanderForecastModel.lua.
--
-- Two rules shape the repaint. First, the estimate for a spell only changes
-- when your gear, your buffs, your target or the log changes — so it is cached
-- and the cache is dropped wholesale on those events rather than recomputed on
-- a timer. Second, an action button is a PROTECTED frame: we may hang our own
-- insecure child on it and write to that child freely, but we never call a
-- setter on the button itself, in or out of combat. Everything drawn here is
-- ours.

local M = CommanderForecast.Model

local db
local playerGUID
local playerLevel = 1

-- Blizzard's bars only. The suite ships its own action bar module and there is
-- no third-party bar here to test against; a button we do not find simply
-- never gets a number, which is a visible, self-explaining failure.
local BARS = {
    { prefix = "ActionButton", count = 12 },
    { prefix = "MultiBarBottomLeftButton", count = 12 },
    { prefix = "MultiBarBottomRightButton", count = 12 },
    { prefix = "MultiBarRightButton", count = 12 },
    { prefix = "MultiBarLeftButton", count = 12 },
}

local tracked = {}          -- array of { button = frame, text = fontstring }
local overlays = {}         -- button -> our holder frame
local cache = {}            -- "s<id>" / "i<id>" -> { text, r, g, b } or false
local details = {}          -- same key -> the estimate table, for the tooltip
local stats, targetCtx
local bucketKey = "n0"
local dirty = true
local layoutDirty = true
local contextDirty = false

local COLOR_MEASURED = { 1.00, 1.00, 1.00 }
local COLOR_MODELED = { 0.62, 0.80, 1.00 }
local COLOR_PLAIN = { 1.00, 0.93, 0.55 }

local function IsOn()
    return db and db.EnableForecast
end

-- ---------------------------------------------------------------------------
-- The learned log
-- ---------------------------------------------------------------------------

local function Log()
    local log = CommanderForecastLog
    if not log.spells then
        log.version = 1
        log.spells = {}
    end
    return log
end

local function RecordFor(spellID, bucket, create)
    local spells = Log().spells
    local spell = spells[spellID]
    if not spell then
        if not create then return nil end
        spell = { name = GetSpellInfo(spellID) or ("Spell " .. spellID) }
        spells[spellID] = spell
    end
    local record = spell[bucket]
    if not record then
        if not create then return nil end
        record = M.NewRecord()
        spell[bucket] = record
    end
    return record
end

-- The bucket you are standing in, then the fullest bucket there is. A spell
-- learned on a training dummy is still the best guess for a mob you have
-- never hit — better, at least, than the model that knows no talents.
--
-- `suffix` selects a conditional variant of every bucket ("f" = the target
-- was frozen): the exact bucket in that variant first, then the fullest
-- bucket in that variant, and nothing from the other variant — a hit into a
-- frozen target is not evidence about an unfrozen one, or the reverse.
local function BestRecord(spellID, suffix)
    local spell = Log().spells[spellID]
    if not spell then return nil end
    suffix = suffix or ""
    local exact = spell[bucketKey .. suffix]
    if type(exact) == "table" and ((exact.n or 0) + (exact.tickN or 0)) > 0 then
        return exact, true
    end
    local best, bestCount
    for key, record in pairs(spell) do
        local isVariant = key:find("f$") ~= nil
        if type(record) == "table" and key ~= "name"
            and isVariant == (suffix ~= "") then
            local count = (record.n or 0) + (record.tickN or 0)
            if count > 0 and (not bestCount or count > bestCount) then
                best, bestCount = record, count
            end
        end
    end
    return best, false
end

-- ---------------------------------------------------------------------------
-- Estimating one slot
-- ---------------------------------------------------------------------------

local function Invalidate()
    cache = {}
    details = {}
    dirty = true
end

local Repaint   -- defined with the overlay code below; needed by SetFrozen

-- Who is frozen right now, by GUID, learned from the combat log — any
-- caster's Frost Nova counts, so this is read before the own-source filter.
-- Kept off the aura API on purpose: an Ice Lance's own damage event arrives
-- BEFORE the SPELL_AURA_BROKEN that its hit causes, so at the moment the hit
-- is recorded the map still says frozen, which is the truth about that hit.
local frozen = {}
local frozenCount = 0

local FREEZE_AURAS = {
    ["Frost Nova"] = true,
    ["Frostbite"] = true,
    ["Freeze"] = true,                  -- the Water Elemental's
    ["Freezing Trap Effect"] = true,    -- a hunter's, and Shatter counts it
}

local function SetFrozen(guid, state)
    if not guid then return end
    if state and not frozen[guid] then
        if frozenCount > 200 then frozen, frozenCount = {}, 0 end
        frozen[guid] = true
        frozenCount = frozenCount + 1
    elseif not state and frozen[guid] then
        frozen[guid] = nil
        frozenCount = frozenCount - 1
    else
        return
    end
    -- Only the target's own state is on screen. Repaint it without waiting
    -- for the tick: the freeze is exactly the moment the number matters.
    if targetCtx and targetCtx.guid == guid then
        targetCtx.frozen = state and true or false
        Invalidate()
        Repaint()
    end
end

local function RefreshContext()
    stats = M.PlayerStats()
    targetCtx = M.TargetContext()
    targetCtx.frozen = (targetCtx.guid and frozen[targetCtx.guid]) and true or false
    playerLevel = stats.level
    bucketKey = M.LevelBucket(playerLevel, targetCtx.level, targetCtx.isPlayer)
end

-- Returns the estimate table (never formatted) or nil when this slot has
-- nothing sayable about it.
local function Estimate(kind, id)
    local profile, castSeconds, mana
    if kind == "spell" then
        profile = M.SpellProfile(id)
        castSeconds = M.CastSeconds(id)
        mana = M.ManaCost(id)
    else
        if not db.ShowOnItems then return nil end
        profile = M.ItemProfile(id)
        castSeconds, mana = 0, 0
    end

    local opts = {
        number = db.Number,
        applyHit = db.ApplyHitChance,
        castSeconds = castSeconds,
    }

    local modeled = profile and M.ModelEstimate(profile, stats, targetCtx, opts) or nil
    local measured, exactBucket
    if kind == "spell" then
        local conditional = profile and profile.frozenMult and targetCtx.frozen
        local record
        if conditional then
            -- Hits measured INTO frozen targets first; failing those, the
            -- unfrozen measurement with the tooltip's multiplier on top.
            record, exactBucket = BestRecord(id, "f")
            if record then
                measured = M.MeasuredEstimate(record, profile, opts)
            else
                record, exactBucket = BestRecord(id)
                if record then
                    opts.multiplier = profile.frozenMult
                    measured = M.MeasuredEstimate(record, profile, opts)
                end
            end
        else
            record, exactBucket = BestRecord(id)
            if record then
                measured = M.MeasuredEstimate(record, profile, opts)
            end
        end
    end

    local chosen = M.Compose(modeled, measured, db.Source, db.MinSamples)
    if not chosen or not chosen.value or chosen.value <= 0 then return nil end

    chosen.castSeconds = castSeconds
    chosen.mana = mana
    chosen.exactBucket = exactBucket
    return chosen
end

-- The estimate turned into the string on the icon, under the chosen metric.
local function Present(estimate)
    local value, decimals = estimate.value, false
    if db.Metric == "PER_SECOND" then
        local seconds = estimate.castSeconds
        if not seconds or seconds <= 0 then seconds = M.GCD end
        value = value / seconds
    elseif db.Metric == "PER_MANA" then
        if not estimate.mana or estimate.mana <= 0 then return nil end
        value = value / estimate.mana
        decimals = true
    end
    return M.Format(value, db.CompactNumbers and not decimals, decimals)
end

local function Lookup(kind, id)
    local key = (kind == "spell" and "s" or "i") .. id
    local cached = cache[key]
    if cached ~= nil then return cached or nil end

    local estimate = Estimate(kind, id)
    local text = estimate and Present(estimate) or nil
    if not text then
        cache[key] = false
        return nil
    end

    local color = COLOR_PLAIN
    if db.ColorBySource then
        color = estimate.source == "measured" and COLOR_MEASURED or COLOR_MODELED
    end
    local entry = { text = text, color = color }
    cache[key] = entry
    details[key] = estimate
    return entry
end

-- ---------------------------------------------------------------------------
-- The overlay on a button
-- ---------------------------------------------------------------------------

local function FontPath()
    if NumberFontNormal then
        local path = NumberFontNormal:GetFont()
        if path then return path end
    end
    return STANDARD_TEXT_FONT
end

local function EnsureOverlay(button)
    local holder = overlays[button]
    if holder then return holder end

    -- Our own frame, parented to the button so it follows every move Blizzard
    -- (or Commander_ActionBar) makes. Protection propagates from secure
    -- CHILDREN upward; an insecure child of a protected frame is free.
    holder = CreateFrame("Frame", nil, button)
    holder:SetAllPoints(button)
    holder:SetFrameLevel(math.min((button:GetFrameLevel() or 1) + 4, 128))

    local text = holder:CreateFontString(nil, "OVERLAY")
    text:SetJustifyH("CENTER")
    holder.text = text
    overlays[button] = holder
    return holder
end

local function ApplyLayout()
    local size = db.FontSize or 12
    local offset = db.OffsetY or 0
    local path = FontPath()
    for _, entry in ipairs(tracked) do
        local text = entry.text
        -- A font object first, so a SetFont that does not take still leaves a
        -- readable string: SetFont's return is not a reliable success flag on
        -- this client, and branching on it would silently drop the size on
        -- every button instead of on none of them.
        text:SetFontObject(NumberFontNormalSmall)
        pcall(text.SetFont, text, path, size, "OUTLINE")
        text:ClearAllPoints()
        if db.Anchor == "TOP" then
            text:SetPoint("TOP", entry.holder, "TOP", 0, -offset)
        elseif db.Anchor == "CENTER" then
            text:SetPoint("CENTER", entry.holder, "CENTER", 0, offset)
        else
            text:SetPoint("BOTTOM", entry.holder, "BOTTOM", 0, offset)
        end
    end
    layoutDirty = false
end

local function DiscoverButtons()
    if #tracked > 0 then return end
    for _, bar in ipairs(BARS) do
        for index = 1, bar.count do
            local button = _G[bar.prefix .. index]
            if button and button.CreateFontString then
                local holder = EnsureOverlay(button)
                tracked[#tracked + 1] = {
                    button = button,
                    holder = holder,
                    text = holder.text,
                }
            end
        end
    end
    layoutDirty = true
end

-- What spell (or item) a slot is really pointed at. A macro is whatever the
-- macro resolves to right now, which is the whole reason this is re-read
-- rather than cached against the slot.
local function SlotContents(button)
    local slot = button.action
    if type(slot) ~= "number" and button.GetAttribute then
        slot = button:GetAttribute("action")
    end
    if type(slot) ~= "number" or not HasAction(slot) then return nil end

    local actionType, id = GetActionInfo(slot)
    if actionType == "spell" and type(id) == "number" and id > 0 then
        return "spell", id
    elseif actionType == "item" and type(id) == "number" and id > 0 then
        return "item", id
    elseif actionType == "macro" then
        local spell = GetMacroSpell and GetMacroSpell(id)
        if type(spell) == "number" then
            return "spell", spell
        elseif type(spell) == "string" then
            local resolved = select(7, GetSpellInfo(spell))
            if resolved then return "spell", resolved end
        end
    end
    -- Flyouts, companions and equipment sets deal no damage and heal nobody.
    return nil
end

function Repaint()
    if not IsOn() then
        for _, entry in ipairs(tracked) do entry.text:SetText("") end
        return
    end
    if layoutDirty then ApplyLayout() end
    if db.RequireTarget and not (targetCtx and targetCtx.exists) then
        for _, entry in ipairs(tracked) do entry.text:SetText("") end
        return
    end

    for _, entry in ipairs(tracked) do
        local kind, id = SlotContents(entry.button)
        local shown
        if kind then shown = Lookup(kind, id) end
        if shown then
            entry.text:SetText(shown.text)
            entry.text:SetTextColor(shown.color[1], shown.color[2], shown.color[3])
        else
            entry.text:SetText("")
        end
    end
    dirty = false
end

-- ---------------------------------------------------------------------------
-- Learning from the combat log
-- ---------------------------------------------------------------------------

local GetCLEU = (C_CombatLog and C_CombatLog.GetCurrentEventInfo)
    or CombatLogGetCurrentEventInfo

-- One in-flight periodic aura per spell per victim, so ticks per application
-- can be COUNTED rather than derived from a duration the tooltip may not even
-- state. Bounded: a long session in a battleground would otherwise accumulate
-- an entry per enemy per DoT and never let go.
local pending = {}
local pendingCount = 0

local function DropPending()
    pending, pendingCount = {}, 0
end

local function FinishApplication(key)
    local entry = pending[key]
    if not entry then return end
    pending[key] = nil
    pendingCount = pendingCount - 1
    if entry.count > 0 and entry.record then
        M.ObserveTickCount(entry.record, entry.count, db.LearnWindow)
    end
end

-- The victim's level is only knowable while we are holding a token on them.
-- In practice that is nearly always true — you cast at what you target — and
-- when it is not, the cast lands in the same-level bucket, which is the one
-- the fallback in BestRecord would have reached for anyway.
local function BucketForDest(destGUID, spellID)
    local isPlayer = type(destGUID) == "string" and destGUID:sub(1, 6) == "Player"
    local level
    for _, unit in ipairs({ "target", "focus", "mouseover" }) do
        if UnitGUID(unit) == destGUID then
            level = UnitLevel(unit)
            break
        end
    end
    local bucket = M.LevelBucket(playerLevel, level or playerLevel, isPlayer)
    -- A conditional spell files its conditional hits separately
    if frozen[destGUID] then
        local profile = M.SpellProfile(spellID)
        if profile and profile.frozenMult then
            bucket = bucket .. "f"
        end
    end
    return bucket
end

local MISS_TYPES = {
    MISS = true, RESIST = true, DODGE = true, PARRY = true,
    IMMUNE = true, EVADE = true, DEFLECT = true,
}

local function OnCleu()
    if not IsOn() then return end
    local _, subevent, _, sourceGUID, _, _, _, destGUID, _, _, _,
        a12, a13, _, a15, _, _, a18, _, a20, a21 = GetCLEU()

    -- Freezes from anyone, on anyone
    if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
        if FREEZE_AURAS[a13] then SetFrozen(destGUID, true) end
    elseif subevent == "SPELL_AURA_REMOVED" or subevent == "SPELL_AURA_BROKEN"
        or subevent == "SPELL_AURA_BROKEN_SPELL" then
        if FREEZE_AURAS[a13] then SetFrozen(destGUID, false) end
    elseif subevent == "UNIT_DIED" then
        SetFrozen(destGUID, false)
    end

    if not db.Learn then return end
    if sourceGUID ~= playerGUID then return end
    local spellID = a12
    if type(spellID) ~= "number" or spellID <= 0 then return end

    local window = db.LearnWindow
    local key = spellID .. ":" .. tostring(destGUID)

    if subevent == "SPELL_DAMAGE" or subevent == "RANGE_DAMAGE" then
        -- Absorbed damage is still damage this spell produced; the shield is
        -- the target's problem, not a smaller cast.
        local amount = (type(a15) == "number" and a15 or 0)
            + (type(a20) == "number" and a20 or 0)
        local record = RecordFor(spellID, BucketForDest(destGUID, spellID), true)
        M.Observe(record, amount, a21 and true or false, window)
        cache["s" .. spellID] = nil

    elseif subevent == "SPELL_HEAL" then
        -- The full heal, overheal included: "what would this cast do" is not
        -- a question about the target's current health.
        local record = RecordFor(spellID, BucketForDest(destGUID, spellID), true)
        M.Observe(record, type(a15) == "number" and a15 or 0, a18 and true or false, window)
        cache["s" .. spellID] = nil

    elseif subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "SPELL_PERIODIC_HEAL" then
        local amount = (type(a15) == "number" and a15 or 0)
        if subevent == "SPELL_PERIODIC_DAMAGE" then
            amount = amount + (type(a20) == "number" and a20 or 0)
        end
        local record = RecordFor(spellID, BucketForDest(destGUID, spellID), true)
        M.ObserveTick(record, amount, window)
        local entry = pending[key]
        if not entry then
            if pendingCount > 200 then DropPending() end
            entry = { count = 0, record = record }
            pending[key] = entry
            pendingCount = pendingCount + 1
        end
        entry.count = entry.count + 1
        entry.record = record
        cache["s" .. spellID] = nil

    elseif subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
        -- A refresh ends the run of ticks we were counting and starts another.
        FinishApplication(key)

    elseif subevent == "SPELL_AURA_REMOVED" or subevent == "SPELL_AURA_BROKEN"
        or subevent == "SPELL_AURA_BROKEN_SPELL" then
        FinishApplication(key)

    elseif subevent == "SPELL_MISSED" or subevent == "RANGE_MISSED" then
        if MISS_TYPES[a15] then
            local record = RecordFor(spellID, BucketForDest(destGUID, spellID), true)
            M.ObserveMiss(record)
            cache["s" .. spellID] = nil
        end
    end
end

-- ---------------------------------------------------------------------------
-- Tooltip breakdown
-- ---------------------------------------------------------------------------

local function MetricLabel()
    if db.Metric == "PER_SECOND" then return "per second" end
    if db.Metric == "PER_MANA" then return "per mana" end
    return "per cast"
end

local function AddBreakdown(tooltip, slot)
    if not (IsOn() and db.ShowTooltipBreakdown) then return end
    if type(slot) ~= "number" or not HasAction(slot) then return end

    local actionType, id = GetActionInfo(slot)
    local kind
    if actionType == "spell" then
        kind = "spell"
    elseif actionType == "item" then
        kind = "item"
    elseif actionType == "macro" then
        local spell = GetMacroSpell and GetMacroSpell(id)
        if type(spell) == "number" then kind, id = "spell", spell end
    end
    if not kind or type(id) ~= "number" then return end

    local entry = Lookup(kind, id)
    if not entry then return end
    local estimate = details[(kind == "spell" and "s" or "i") .. id]
    if not estimate then return end

    tooltip:AddLine(" ")
    tooltip:AddLine("|cffffd100\226\128\148 Forecast \226\128\148|r")

    local against = targetCtx and targetCtx.exists and (UnitName("target") or "your target")
        or "no target"
    tooltip:AddDoubleLine(
        estimate.source == "measured" and "Measured against" or "Modeled against",
        against, 0.8, 0.8, 0.8, 1, 1, 1)

    tooltip:AddDoubleLine(MetricLabel(), entry.text, 0.8, 0.8, 0.8, 1, 0.9, 0.4)

    if estimate.multiplier and estimate.multiplier > 1 then
        tooltip:AddDoubleLine("Target is Frozen",
            string.format("\195\151%d", estimate.multiplier),
            0.8, 0.8, 0.8, 0.5, 0.85, 1)
    end

    if estimate.source == "measured" then
        tooltip:AddDoubleLine("Samples",
            string.format("%d cast%s%s", estimate.samples,
                estimate.samples == 1 and "" or "s",
                estimate.exactBucket and "" or " (other targets)"),
            0.8, 0.8, 0.8, 0.6, 1, 0.6)
        if estimate.critRate then
            tooltip:AddDoubleLine("Observed crit rate",
                string.format("%.0f%%", estimate.critRate * 100),
                0.8, 0.8, 0.8, 1, 1, 1)
        end
        if estimate.missChance then
            tooltip:AddDoubleLine("Observed miss rate",
                string.format("%.1f%%", estimate.missChance * 100),
                0.8, 0.8, 0.8, 1, 1, 1)
        end
    else
        if estimate.direct and estimate.direct > 0 then
            tooltip:AddDoubleLine("Direct", string.format("%d", estimate.direct + 0.5),
                0.8, 0.8, 0.8, 1, 1, 1)
        end
        if estimate.dot and estimate.dot > 0 then
            tooltip:AddDoubleLine("Over time", string.format("%d", estimate.dot + 0.5),
                0.8, 0.8, 0.8, 1, 1, 1)
        end
        if estimate.power and estimate.power > 0 then
            tooltip:AddDoubleLine("Power \195\151 coefficient",
                string.format("%d \195\151 %.0f%%%s", estimate.power,
                    estimate.directCoef * 100,
                    estimate.dotCoef > 0
                        and string.format(" + %.0f%%", estimate.dotCoef * 100) or ""),
                0.8, 0.8, 0.8, 0.4, 0.8, 1)
        end
        tooltip:AddDoubleLine("Crit",
            string.format("%.1f%% for \195\151%.1f", (estimate.critChance or 0) * 100,
                estimate.critMult or 1.5),
            0.8, 0.8, 0.8, 1, 1, 1)
        if estimate.missChance and estimate.missChance > 0 then
            tooltip:AddDoubleLine("Miss chance",
                string.format("%.1f%%", estimate.missChance * 100),
                0.8, 0.8, 0.8, 1, 1, 1)
        end
        tooltip:AddLine("Modeled: no API reports your talents or buff percentages, so this reads low until the log takes over.",
            0.6, 0.6, 0.6, true)
    end

    tooltip:Show()
end

-- ---------------------------------------------------------------------------
-- Slash surface
-- ---------------------------------------------------------------------------

function CommanderForecast_Report()
    local rows = {}
    for spellID, spell in pairs(Log().spells) do
        local record, exact = BestRecord(spellID)
        if record then
            rows[#rows + 1] = {
                name = spell.name or ("Spell " .. spellID),
                avg = record.avg or 0,
                n = (record.n or 0) + (record.tickN or 0),
                label = exact and bucketKey or "other targets",
            }
        end
    end
    table.sort(rows, function(a, b) return a.avg > b.avg end)

    if #rows == 0 then
        print("|cff66ccffCommander Forecast|r: nothing measured yet — cast something.")
        return
    end
    print(string.format("|cff66ccffCommander Forecast|r: %d spell%s measured on this character",
        #rows, #rows == 1 and "" or "s"))
    for _, row in ipairs(rows) do
        print(string.format("  %s |cffffffff%s|r from %d cast%s |cff888888(%s)|r",
            row.name, M.Format(row.avg, true), row.n, row.n == 1 and "" or "s", row.label))
    end
end

function CommanderForecast_Forget()
    CommanderForecastLog.spells = {}
    DropPending()
    Invalidate()
    Repaint()
    print("|cff66ccffCommander Forecast|r: everything measured on this character has been forgotten.")
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")

-- Events that change what a spell is worth (and therefore drop the cache)
local CONTEXT_EVENTS = {
    PLAYER_TARGET_CHANGED = true,
    PLAYER_EQUIPMENT_CHANGED = true,
    PLAYER_LEVEL_UP = true,
    UNIT_STATS = true,
    UNIT_ATTACK_POWER = true,
    UNIT_RANGED_ATTACK_POWER = true,
    UNIT_DAMAGE = true,
    UNIT_AURA = true,
    SPELL_POWER_CHANGED = true,
    PLAYER_ENTERING_WORLD = true,
}

-- Spell text arriving after we scanned it (see M.SpellProfile)
local TEXT_EVENTS = {
    SPELL_TEXT_UPDATE = true,
    SPELL_DATA_LOAD_RESULT = true,
}

-- Events that change which spell a slot points at
local SLOT_EVENTS = {
    ACTIONBAR_SLOT_CHANGED = true,
    ACTIONBAR_PAGE_CHANGED = true,
    UPDATE_BONUS_ACTIONBAR = true,
    UPDATE_SHAPESHIFT_FORM = true,
    UPDATE_MACROS = true,
    SPELLS_CHANGED = true,
    LEARNED_SPELL_IN_TAB = true,
}

local function OnSettingsUpdate()
    layoutDirty = true
    Invalidate()
    Repaint()
end

local function OnEvent(_, event, arg1)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCleu()
        return
    end
    if event == "PLAYER_LOGIN" then
        db = CommanderForecastDB
        playerGUID = UnitGUID("player")
        DiscoverButtons()
        RefreshContext()
        Invalidate()

        for name in pairs(CONTEXT_EVENTS) do
            pcall(frame.RegisterEvent, frame, name)
        end
        for name in pairs(SLOT_EVENTS) do
            pcall(frame.RegisterEvent, frame, name)
        end
        for name in pairs(TEXT_EVENTS) do
            pcall(frame.RegisterEvent, frame, name)
        end
        if GetCLEU then
            local ok = pcall(frame.RegisterEvent, frame, "COMBAT_LOG_EVENT_UNFILTERED")
            if not ok and frame.RegisterEventCallback then
                pcall(frame.RegisterEventCallback, frame, "COMBAT_LOG_EVENT_UNFILTERED")
            end
        else
            print("|cff66ccffCommander Forecast|r: |cffff4433this client exposes no combat-log getter|r — the measured half of the forecast is unavailable, and every number will stay modeled.")
        end

        Commander.AddListener(COMMANDER_FORECAST_EVENTS.UPDATE, OnSettingsUpdate)

        -- One coalescing repaint. Events only mark work; nothing redraws a
        -- bar sixty times a second because a raid is applying auras.
        local sweeps = 0
        C_Timer.NewTicker(0.3, function()
            if not IsOn() then return end
            sweeps = sweeps + 1
            if contextDirty then
                contextDirty = false
                RefreshContext()
                Invalidate()
            end
            -- A slot can change under us without an event we registered for
            -- (a paging bar in a form, a macro whose condition flipped), so a
            -- full pass runs every ~3s regardless of the dirty flag.
            if dirty or sweeps % 10 == 0 then
                Repaint()
            end
        end)
        Repaint()
        return
    end

    if not IsOn() then return end

    if event == "UNIT_AURA" or event == "UNIT_STATS" or event == "UNIT_DAMAGE"
        or event == "UNIT_ATTACK_POWER" or event == "UNIT_RANGED_ATTACK_POWER" then
        if arg1 ~= "player" then return end
    end

    if CONTEXT_EVENTS[event] then
        if event == "PLAYER_ENTERING_WORLD" then
            frozen, frozenCount = {}, 0
            DropPending()
        end
        if event == "PLAYER_TARGET_CHANGED" then
            -- The one change the eye is waiting on; do not make it wait a tick.
            contextDirty = false
            RefreshContext()
            Invalidate()
            Repaint()
        else
            -- Everything else only marks. UNIT_AURA alone fires several times
            -- a second on a buffed character in a raid, and each pass would
            -- otherwise re-read nine character-sheet stats and throw away
            -- every cached estimate on the bars.
            contextDirty = true
        end
    elseif SLOT_EVENTS[event] then
        dirty = true
    elseif TEXT_EVENTS[event] then
        if type(arg1) == "number" then
            M.ForgetProfile(arg1)
            cache["s" .. arg1] = nil
            details["s" .. arg1] = nil
        end
        dirty = true
    end
end

frame:SetScript("OnEvent", OnEvent)

-- The breakdown rides Blizzard's own action tooltip. SetAction is the single
-- entry point every bar uses, so one hook covers all of them.
local hooked = false
local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
hookFrame:SetScript("OnEvent", function()
    if hooked then return end
    hooked = true
    hooksecurefunc(GameTooltip, "SetAction", function(tooltip, slot)
        -- Never let a data gap break an action button's tooltip.
        pcall(AddBreakdown, tooltip, slot)
    end)
end)
