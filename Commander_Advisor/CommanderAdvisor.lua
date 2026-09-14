-- Commander Advisor — the glows on the buttons.
--
-- Three jobs live here: build a SNAPSHOT of the player's situation every
-- tick (health, auras, cooldowns, who is hitting you and how, what is being
-- cast at you), hand it to the Engine with the rulebook, and light the
-- action buttons the Engine names at the tier it names. The judgement is
-- all in CommanderAdvisorEngine.lua and is tested without a client.
--
-- An action button is a PROTECTED frame: we hang our own insecure child on
-- it and draw on that child freely, and never call a setter on the button
-- itself, in or out of combat. Everything drawn here is ours.

local D = CommanderAdvisor_Data
local E = CommanderAdvisor_Engine

local db
local playerGUID
local classToken = "UNKNOWN"
local rules = {}            -- this class's rules, book order
local watchSpells = {}      -- spell name -> true, every spell any rule could offer
local watchPetSpells = {}
local itemRules = {}        -- rules with an item pattern
local known = {}            -- spell name -> spellID (highest rank in the book)
local knownPet = {}
local state = E.NewState()
local intake = E.NewIntake()
local incoming = {}         -- casterGUID -> { name, spellID, endTime, unit }
local recentCasts = {}      -- spell name -> GetTime() of the last cast
local lastSnapshot
local lastSignals = {}
local lastReport = {}       -- rule key -> reason, from the last tick, for the report
local enemyPlayersNear = 0
local enemyClassesNear = {}   -- class token -> true, hostile players in nameplate range

-- Blizzard's bars only, as in Commander Forecast: the suite's own bar
-- module reuses these frames, and a button not found simply never glows.
local BARS = {
    { prefix = "ActionButton", count = 12 },
    { prefix = "MultiBarBottomLeftButton", count = 12 },
    { prefix = "MultiBarBottomRightButton", count = 12 },
    { prefix = "MultiBarRightButton", count = 12 },
    { prefix = "MultiBarLeftButton", count = 12 },
}

local tracked = {}          -- array of { button, glow }
local slotMap = {}          -- button -> { kind = "spell"|"item", name = , id = } or false
local slotsDirty = true
local testUntil = 0
local testTiers = {}        -- button -> tier during a test

local function IsOn() return db and db.EnableAdvisor end

-- Item calls: the C_Item spellings first, the classic globals behind them
local function ItemCooldown(itemID)
    local fn = (C_Item and C_Item.GetItemCooldown) or (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not fn then return 0, 0 end
    local ok, start, duration = pcall(fn, itemID)
    if not ok then return 0, 0 end
    return start, duration
end
local function ItemCount(itemID)
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not fn then return nil end
    local ok, count = pcall(fn, itemID)
    return ok and count or nil
end
local function ItemUsable(itemID)
    local fn = (C_Item and C_Item.IsUsableItem) or IsUsableItem
    if not fn then return nil end
    local ok, usable = pcall(fn, itemID)
    if not ok then return nil end
    return usable
end
local function ItemName(itemID)
    if C_Item and C_Item.GetItemNameByID then
        local ok, name = pcall(C_Item.GetItemNameByID, itemID)
        if ok and name then return name end
    end
    if GetItemInfo then return (GetItemInfo(itemID)) end
    return nil
end

-- ---------------------------------------------------------------------------
-- The spellbook
-- ---------------------------------------------------------------------------

local function ScanSpellbook()
    known = {}
    knownPet = {}
    local tabs = GetNumSpellTabs and GetNumSpellTabs() or 0
    for tab = 1, tabs do
        local _, _, offset, count = GetSpellTabInfo(tab)
        for i = (offset or 0) + 1, (offset or 0) + (count or 0) do
            local name, _, spellID = GetSpellBookItemName(i, "spell")
            if name and not (IsPassiveSpell and IsPassiveSpell(i, "spell")) then
                -- Ranks list ascending; the last one seen is the highest
                known[name] = spellID or known[name] or true
            end
        end
    end
    local petCount = HasPetSpells and HasPetSpells()
    if type(petCount) == "number" then
        for i = 1, petCount do
            local name, _, spellID = GetSpellBookItemName(i, "pet")
            if name and not (IsPassiveSpell and IsPassiveSpell(i, "pet")) then
                knownPet[name] = spellID or true
            end
        end
    end
end

local function BuildBook()
    local _, token = UnitClass("player")
    classToken = token or "UNKNOWN"
    rules = D.RulesForClass(classToken)
    watchSpells, watchPetSpells, itemRules = {}, {}, {}
    for _, rule in ipairs(rules) do
        if rule.item then
            itemRules[#itemRules + 1] = rule
        else
            local set = rule.petSpell and watchPetSpells or watchSpells
            for _, name in ipairs(E.SpellList(rule)) do set[name] = true end
            if rule.notReady then watchSpells[rule.notReady] = true end
            for _, name in ipairs(rule.requiresReady or {}) do watchSpells[name] = true end
        end
    end
end

-- ---------------------------------------------------------------------------
-- The buttons
-- ---------------------------------------------------------------------------

local ATLAS_LOOP = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
local ATLAS_START = "UI-HUD-ActionBar-Proc-Start-Flipbook"
local BORDER_FILE = "Interface\\Buttons\\UI-ActionButton-Border"
local procArtAvailable

local function ProcArtAvailable()
    if procArtAvailable ~= nil then return procArtAvailable end
    procArtAvailable = false
    if C_Texture and C_Texture.GetAtlasInfo then
        local ok, info = pcall(C_Texture.GetAtlasInfo, ATLAS_LOOP)
        procArtAvailable = ok and info ~= nil
    end
    return procArtAvailable
end

local function MakeFlipbook(holder, texture, duration, looping)
    local group = holder:CreateAnimationGroup()
    local ok = pcall(function()
        local anim = group:CreateAnimation("FlipBook")
        anim:SetTarget(texture)
        anim:SetDuration(duration)
        anim:SetFlipBookRows(6)
        anim:SetFlipBookColumns(5)
        anim:SetFlipBookFrames(30)
        anim:SetFlipBookFrameWidth(0)
        anim:SetFlipBookFrameHeight(0)
    end)
    if not ok then return nil end
    if looping then group:SetLooping("REPEAT") end
    return group
end

local function EnsureGlow(button)
    local holder = CreateFrame("Frame", nil, button)
    holder:SetPoint("CENTER", button, "CENTER", 0, 0)
    holder:SetFrameLevel(math.min((button:GetFrameLevel() or 1) + 5, 128))
    holder:Hide()

    -- The proc art: the client's own looping flipbook, tinted per tier
    if ProcArtAvailable() then
        local loop = holder:CreateTexture(nil, "OVERLAY")
        loop:SetAllPoints(holder)
        local okAtlas = pcall(loop.SetAtlas, loop, ATLAS_LOOP)
        if okAtlas then
            local anim = MakeFlipbook(holder, loop, 1, true)
            if anim then
                holder.loop, holder.loopAnim = loop, anim
                local start = holder:CreateTexture(nil, "OVERLAY", nil, 1)
                start:SetPoint("CENTER", holder, "CENTER", 0, 0)
                if pcall(start.SetAtlas, start, ATLAS_START) then
                    local startAnim = MakeFlipbook(holder, start, 0.7, false)
                    if startAnim then
                        holder.start, holder.startAnim = start, startAnim
                        startAnim:SetScript("OnFinished", function() start:Hide() end)
                    end
                end
                start:Hide()
            else
                loop:Hide()
            end
        else
            loop:Hide()
        end
    end

    -- The border: a plain rim in additive blend, for the quieter style and
    -- as the fallback when the atlas is not there
    local border = holder:CreateTexture(nil, "OVERLAY")
    border:SetPoint("CENTER", holder, "CENTER", 0, 0)
    border:SetTexture(BORDER_FILE)
    border:SetBlendMode("ADD")
    border:Hide()
    holder.border = border

    -- Tier pips, top-left, out of the way of the keybind (top-right), the
    -- count (bottom-right) and the macro name (bottom)
    holder.pips = {}
    for i = 1, 3 do
        local pip = holder:CreateTexture(nil, "OVERLAY", nil, 2)
        pip:SetColorTexture(1, 1, 1, 1)
        pip:Hide()
        holder.pips[i] = pip
    end

    holder.tier = nil
    return holder
end

local function DiscoverButtons()
    if #tracked > 0 then return end
    for _, bar in ipairs(BARS) do
        for index = 1, bar.count do
            local button = _G[bar.prefix .. index]
            if button and button.CreateTexture then
                tracked[#tracked + 1] = { button = button, glow = EnsureGlow(button) }
            end
        end
    end
end

local function LayoutGlow(entry)
    local button, holder = entry.button, entry.glow
    local w, h = button:GetSize()
    if not w or w <= 0 then w, h = 36, 36 end
    local scale = (db.GlowScale or 100) / 100
    holder:SetSize(w * 1.4 * scale, h * 1.4 * scale)
    if holder.start then holder.start:SetSize(w * 1.4 * scale * 2.4, h * 1.4 * scale * 2.4) end
    holder.border:SetSize(w * 1.75 * scale, h * 1.75 * scale)
    local size = db.PipSize or 5
    for i, pip in ipairs(holder.pips) do
        pip:SetSize(size, size)
        pip:ClearAllPoints()
        pip:SetPoint("TOPLEFT", button, "TOPLEFT", 2 + (i - 1) * (size + 1), -2)
    end
end

-- What a slot is really pointed at: a spell or an item, by NAME, because a
-- rule names spells and a slot holds one particular rank.
local function SlotContents(button)
    local slot = button.action
    if type(slot) ~= "number" and button.GetAttribute then
        slot = button:GetAttribute("action")
    end
    if type(slot) ~= "number" or not HasAction(slot) then return nil end

    local actionType, id = GetActionInfo(slot)
    if actionType == "macro" then
        local spell = GetMacroSpell and GetMacroSpell(id)
        if type(spell) == "number" then
            actionType, id = "spell", spell
        elseif type(spell) == "string" then
            local resolved = select(7, GetSpellInfo(spell))
            if resolved then actionType, id = "spell", resolved end
        else
            local itemName, itemLink = GetMacroItem and GetMacroItem(id)
            if itemName then
                local itemID = itemLink and tonumber(itemLink:match("item:(%d+)"))
                return { kind = "item", name = itemName, id = itemID, slot = slot }
            end
        end
    end
    if actionType == "spell" and type(id) == "number" and id > 0 then
        local name = GetSpellInfo(id)
        if name then return { kind = "spell", name = name, id = id, slot = slot } end
    elseif actionType == "item" and type(id) == "number" and id > 0 then
        local name = ItemName(id)
        if name then return { kind = "item", name = name, id = id, slot = slot } end
    end
    return nil
end

local function RebuildSlots()
    for _, entry in ipairs(tracked) do
        slotMap[entry.button] = SlotContents(entry.button) or false
    end
    slotsDirty = false
end

local function ItemMatches(rule, name)
    for pattern in rule.item:gmatch("[^|]+") do
        if name:find(pattern) then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- The snapshot
-- ---------------------------------------------------------------------------

local GCD_MAX = 1.5

-- Usable: the classic global, else the modern spelling (same two returns)
local function SpellUsable(nameOrID)
    if IsUsableSpell then return IsUsableSpell(nameOrID) end
    if C_Spell and C_Spell.IsSpellUsable then return C_Spell.IsSpellUsable(nameOrID) end
    return true, false
end

local function SpellEntry(name, id)
    local entry = { known = true, id = id }
    -- By id where the book gave one (the exact rank), by name otherwise
    local okCD, start, duration, enabled = pcall(GetSpellCooldown, type(id) == "number" and id or name)
    if not okCD or type(start) ~= "number" then
        start, duration, enabled = 0, 0, 1
    end
    local remaining = (duration and duration > 0) and (start + duration - GetTime()) or 0
    -- The client reports the longer of the global and the real cooldown;
    -- a global is not "on cooldown" for our purposes
    entry.ready = remaining <= 0 or (duration or 0) <= GCD_MAX
    entry.remaining = remaining > 0 and remaining or 0
    if enabled == 0 then entry.ready = false end
    local okU, usable, noMana = pcall(SpellUsable, type(id) == "number" and id or name)
    if not okU then usable, noMana = true, false end
    entry.usable = usable and true or false
    entry.noMana = noMana and true or false
    return entry
end

-- The first ready, usable item on a bar that matches the rule; failing
-- that, the first match at all, so the report can say why it is quiet.
local function ItemEntry(rule)
    local fallback
    for _, entry in ipairs(tracked) do
        local slot = slotMap[entry.button]
        if slot and slot.kind == "item" and ItemMatches(rule, slot.name) then
            local out = { name = slot.name, id = slot.id, ready = true, usable = true }
            if slot.id then
                local start, duration = ItemCooldown(slot.id)
                if type(start) == "number" and type(duration) == "number" and duration > 0 then
                    local remaining = start + duration - GetTime()
                    if remaining > 0 and duration > GCD_MAX then out.ready = false end
                end
                local count = ItemCount(slot.id)
                if type(count) == "number" and count <= 0 then out.usable = false end
                if ItemUsable(slot.id) == false then out.usable = false end
            end
            if out.ready and out.usable then return out end
            fallback = fallback or out
        end
    end
    return fallback
end

local LOC_MAP = {
    STUN = "stunned", STUN_MECHANIC = "stunned",
    FEAR = "feared", FEAR_MECHANIC = "feared", CONFUSE = "feared", DISORIENT = "feared",
    CHARM = "incapacitated", POSSESS = "incapacitated", BANISH = "incapacitated", SLEEP = "incapacitated",
    SILENCE = "silenced", PACIFYSILENCE = "silenced",
    ROOT = "rooted", DISARM = "disarmed",
}

local function ReadControl(control)
    if not C_LossOfControl then return end
    local count = C_LossOfControl.GetActiveLossOfControlDataCount
        and C_LossOfControl.GetActiveLossOfControlDataCount()
    if type(count) ~= "number" then return end
    for i = 1, count do
        -- Modern: one table with locType. Older: a tuple whose first value is it.
        local ok, data = pcall(C_LossOfControl.GetActiveLossOfControlData, i)
        local locType
        if ok and type(data) == "table" then locType = data.locType
        elseif ok and type(data) == "string" then locType = data end
        local word = locType and LOC_MAP[locType]
        if word then control[word] = true end
    end
end

local function FormName()
    local index = GetShapeshiftForm and GetShapeshiftForm()
    if not index or index == 0 then return nil end
    local a, b, c, d = GetShapeshiftFormInfo(index)
    -- Old signature: icon, name, active, castable. New: icon, active, castable, spellID.
    if type(b) == "string" then return b end
    if type(d) == "number" then return GetSpellInfo(d) end
    return nil
end

local function BuildSnapshot(now)
    local hpNow, hpMax = UnitHealth("player"), UnitHealthMax("player")
    if not hpMax or hpMax <= 0 then hpMax = 1 end
    local S = {
        now = now,
        class = classToken,
        hp = hpNow / hpMax,
        hpAbs = hpNow,
        inCombat = UnitAffectingCombat("player") and true or false,
        dead = UnitIsDeadOrGhost("player") and true or false,
        mounted = IsMounted() and true or false,
        taxi = UnitOnTaxi("player") and true or false,
        resting = IsResting() and true or false,
        stealthed = IsStealthed and IsStealthed() or false,
        auras = {}, debuffs = {}, debuffTypes = {}, control = {},
        spells = {}, petSpells = {}, items = {}, recentCasts = recentCasts,
        inGroup = IsInGroup() and true or false,
        hasTarget = UnitExists("target") and UnitCanAttack("player", "target") and true or false,
        hasShield = IsEquippedItemType and IsEquippedItemType("Shields") or false,
        outdoors = IsOutdoors and IsOutdoors() or false,
        form = FormName(),
        enemyPlayersNear = enemyPlayersNear,
        enemyClassesNear = enemyClassesNear,
    }

    if UnitPowerType("player") == 0 then
        local m, mMax = UnitPower("player", 0), UnitPowerMax("player", 0)
        S.mana = (mMax and mMax > 0) and (m / mMax) or nil
    end
    if UnitExists("pet") and not UnitIsDeadOrGhost("pet") then
        S.pet = true
        local p, pMax = UnitHealth("pet"), UnitHealthMax("pet")
        S.petHp = (pMax and pMax > 0) and (p / pMax) or 1
    end
    local _, instanceType = IsInInstance()
    S.zone = instanceType or "none"

    local castName = UnitCastingInfo("player")
    if not castName then castName = UnitChannelInfo("player") end
    S.casting = castName and true or false
    S.castingName = castName

    -- Auras: every buff by name (with whether it is yours and when it ends),
    -- every debuff by name and by dispel type
    if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
        for i = 1, 40 do
            local aura = C_UnitAuras.GetBuffDataByIndex("player", i, "HELPFUL")
            if not aura then break end
            if aura.name and not S.auras[aura.name] then
                S.auras[aura.name] = {
                    expire = aura.expirationTime or 0,
                    mine = aura.sourceUnit and UnitIsUnit(aura.sourceUnit, "player") or false,
                    spellId = aura.spellId,
                }
            elseif aura.name and aura.sourceUnit and UnitIsUnit(aura.sourceUnit, "player") then
                S.auras[aura.name].mine = true
            end
        end
        for i = 1, 40 do
            local aura = C_UnitAuras.GetDebuffDataByIndex("player", i, "HARMFUL")
            if not aura then break end
            if aura.name then
                S.debuffs[aura.name] = { expire = aura.expirationTime or 0, spellId = aura.spellId }
                local kind = aura.dispelName
                if kind and kind ~= "" then
                    S.debuffTypes[kind] = (S.debuffTypes[kind] or 0) + 1
                end
                if D.SNARE_SET[aura.name] then S.control.snared = true end
            end
        end
    end
    ReadControl(S.control)

    -- Incoming damage
    local sum = E.IntakeSummary(intake, now, hpNow)
    S.taking, S.ttl, S.rate = sum.taking, sum.ttl, sum.rate
    S.melee, S.casters, S.attackers, S.enemyPlayers = sum.melee, sum.casters, sum.attackers, sum.enemyPlayers
    S.school, S.schoolShare = sum.school, sum.schoolShare

    -- Casts aimed at you, pruned by their own end time
    local casts = {}
    for guid, cast in pairs(incoming) do
        if cast.endTime and cast.endTime < now then
            incoming[guid] = nil
        else
            casts[#casts + 1] = cast
        end
    end
    S.incomingCasts = casts

    -- The spells the rules could offer
    for name in pairs(watchSpells) do
        local id = known[name]
        if id then S.spells[name] = SpellEntry(name, id) end
    end
    for name in pairs(watchPetSpells) do
        local id = knownPet[name]
        if id then S.petSpells[name] = SpellEntry(name, id) end
    end
    for _, rule in ipairs(itemRules) do
        local entry = ItemEntry(rule)
        if entry then S.items[rule.key] = entry end
    end
    return S
end

local cachedConfig

local function Config()
    if cachedConfig then return cachedConfig end
    local modes = {}
    for _, rule in ipairs(rules) do modes[rule.key] = CommanderAdvisor.RuleMode(rule) end
    cachedConfig = {
        modes = modes,
        reticence = CommanderAdvisor.Reticence(),
        ttlCeiling = (db.TTLCeiling or 75) / 100,
        riseSeconds = { db.RiseLow or 1.0, db.RiseMedium or 0.4, 0 },
        holdSeconds = db.HoldSeconds or 1.0,
        castGrace = db.CastGrace or 2.0,
        expiringSoon = db.ExpiringSoon or 0,
        missingGrace = db.MissingGrace or 0,
        remindInCombat = db.RemindInCombat,
        remindOutOfCombat = db.RemindOutOfCombat,
        quietWhileResting = db.QuietWhileResting,
        quietInStealth = db.QuietInStealth,
        remindWhileMounted = db.RemindWhileMounted,
        maxSignals = 0,     -- capped here, after the bar filter
    }
    return cachedConfig
end

-- ---------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------

local PULSE_PERIOD = { SLOW = 2.4, MEDIUM = 1.2, FAST = 0.55 }
local lit = {}              -- holder -> true while shown
local litCount = 0

local function TierStyle(tier)
    local prefix = "Tier" .. tier
    return {
        color = CommanderAdvisor.ColorFor(db[prefix .. "Color"]),
        intensity = (db[prefix .. "Intensity"] or 100) / 100,
        period = PULSE_PERIOD[db[prefix .. "Pulse"] or "NONE"],
    }
end

local function ShowGlow(holder, tier, isNew)
    local style = TierStyle(tier)
    local r, g, b = style.color[1], style.color[2], style.color[3]
    local useProc = db.GlowStyle ~= "BORDER" and holder.loop ~= nil
    holder.tier = tier
    holder.style = style
    holder.usingProc = useProc

    if useProc then
        holder.loop:SetVertexColor(r, g, b)
        holder.loop:Show()
        holder.border:Hide()
        if not holder.loopAnim:IsPlaying() then holder.loopAnim:Play() end
        if isNew and tier == 3 and db.StartBurst and holder.start then
            holder.start:SetVertexColor(r, g, b)
            holder.start:Show()
            holder.startAnim:Stop()
            holder.startAnim:Play()
        end
    else
        if holder.loop then
            holder.loop:Hide()
            holder.loopAnim:Stop()
        end
        holder.border:SetVertexColor(r, g, b)
        holder.border:Show()
    end
    for i, pip in ipairs(holder.pips) do
        if db.ShowPips and i <= tier then
            pip:SetColorTexture(r, g, b, 1)
            pip:Show()
        else
            pip:Hide()
        end
    end
    holder:SetAlpha(style.intensity)
    if not holder:IsShown() then holder:Show() end
    if not lit[holder] then
        lit[holder] = true
        litCount = litCount + 1
    end
end

local function HideGlow(holder)
    if not holder.tier then return end
    holder.tier = nil
    if holder.loop then
        holder.loop:Hide()
        holder.loopAnim:Stop()
    end
    if holder.start then
        holder.start:Hide()
        holder.startAnim:Stop()
    end
    holder.border:Hide()
    for _, pip in ipairs(holder.pips) do pip:Hide() end
    holder:Hide()
    if lit[holder] then
        lit[holder] = nil
        litCount = litCount - 1
    end
end

-- One OnUpdate for every lit button: the pulse
local pulseDriver = CreateFrame("Frame")
pulseDriver:SetScript("OnUpdate", function()
    if litCount == 0 then return end
    local t = GetTime()
    for holder in pairs(lit) do
        local style = holder.style
        if style and style.period then
            local phase = (t % style.period) / style.period
            local wave = 0.5 + 0.5 * math.sin(phase * 2 * math.pi)
            holder:SetAlpha(style.intensity * (0.55 + 0.45 * wave))
        end
    end
end)

-- Which buttons a signal lights: every button whose slot holds one of the
-- rule's spells that is known and ready, or an item matching its pattern.
local function ButtonsFor(signal, S)
    local out = {}
    local rule = signal.rule
    for _, entry in ipairs(tracked) do
        local slot = slotMap[entry.button]
        if slot then
            if rule.item then
                if slot.kind == "item" and ItemMatches(rule, slot.name) and signal.spell == slot.name then
                    out[#out + 1] = entry
                end
            elseif slot.kind == "spell" then
                if rule.schoolBySpell then
                    if slot.name == signal.spell then out[#out + 1] = entry end
                else
                    local book = rule.petSpell and S.petSpells or S.spells
                    local spell = book[slot.name]
                    if spell and spell.ready and spell.usable ~= false then
                        for _, name in ipairs(E.SpellList(rule)) do
                            if name == slot.name then
                                out[#out + 1] = entry
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    return out
end

local lastSoundAt = {}
local lastTierByKey = {}

local function MaybeSound(signal, S)
    local tier = signal.tier
    local was = lastTierByKey[signal.rule.key]
    lastTierByKey[signal.rule.key] = tier
    if was and was >= tier then return end
    if db.SoundOnlyInCombat and not S.inCombat then return end
    local option = CommanderAdvisor.SoundFor(db["Tier" .. tier .. "Sound"])
    if not option or option.value == "NONE" then return end
    local now = GetTime()
    if lastSoundAt[tier] and (now - lastSoundAt[tier]) < (db.SoundCooldown or 0) then return end
    lastSoundAt[tier] = now
    CommanderAdvisor.PlaySoundOption(option)
end

local function Paint(signals, S)
    local desired = {}      -- holder -> { tier, signal, isNew }
    local shown = 0
    local limit = db.MaxSignals or 3
    local now = GetTime()

    if now < testUntil then
        for _, entry in ipairs(tracked) do
            local tier = testTiers[entry.button]
            if tier then desired[entry.glow] = { tier = tier, isNew = false } end
        end
    else
        local seenKeys = {}
        for _, signal in ipairs(signals) do
            if db["Tier" .. signal.tier .. "Enabled"] then
                local buttons = ButtonsFor(signal, S)
                if #buttons > 0 then
                    if shown >= limit then break end
                    shown = shown + 1
                    signal.onBar = true
                    for _, entry in ipairs(buttons) do
                        local cur = desired[entry.glow]
                        if not cur or cur.tier < signal.tier then
                            desired[entry.glow] = { tier = signal.tier, signal = signal, isNew = signal.isNew }
                        end
                    end
                    MaybeSound(signal, S)
                end
            end
            seenKeys[signal.rule.key] = true
        end
        for key in pairs(lastTierByKey) do
            if not seenKeys[key] then lastTierByKey[key] = nil end
        end
    end

    for _, entry in ipairs(tracked) do
        local want = desired[entry.glow]
        if want then
            local holder = entry.glow
            local changed = holder.tier ~= want.tier
            if changed or want.isNew then
                ShowGlow(holder, want.tier, want.isNew or (changed and want.tier == 3))
            end
            holder.signal = want.signal
        else
            HideGlow(entry.glow)
            entry.glow.signal = nil
        end
    end
end

local function ClearAll()
    for _, entry in ipairs(tracked) do
        HideGlow(entry.glow)
        entry.glow.signal = nil
    end
end

-- ---------------------------------------------------------------------------
-- The tick
-- ---------------------------------------------------------------------------

local function Tick()
    if not IsOn() then
        if litCount > 0 then ClearAll() end
        return
    end
    if slotsDirty then RebuildSlots() end
    local now = GetTime()
    local S = BuildSnapshot(now)
    lastSnapshot = S
    local signals = E.Evaluate(S, rules, Config(), state)
    lastSignals = signals
    Paint(signals, S)
end

-- ---------------------------------------------------------------------------
-- Combat log: what is hitting you, and what you cast
-- ---------------------------------------------------------------------------

local GetCLEU = (C_CombatLog and C_CombatLog.GetCurrentEventInfo)
    or CombatLogGetCurrentEventInfo

local function DropSignalsFor(spellName)
    recentCasts[spellName] = GetTime()
    for _, rule in ipairs(rules) do
        for _, name in ipairs(E.SpellList(rule)) do
            if name == spellName then E.Drop(state, rule.key) end
        end
    end
end

local function OnCleu()
    if not IsOn() then return end
    local _, subevent, _, sourceGUID, _, sourceFlags, _, destGUID, _, _, _,
        a12, a13, a14, a15 = GetCLEU()

    if destGUID == playerGUID then
        local now = GetTime()
        local isPlayer = type(sourceGUID) == "string" and sourceGUID:sub(1, 6) == "Player"
        if subevent == "SWING_DAMAGE" then
            E.IntakeObserve(intake, now, a12, sourceGUID, "melee", a14 or 0x1, isPlayer)
        elseif subevent == "SWING_MISSED" then
            E.IntakeObserve(intake, now, 0, sourceGUID, "melee", 0x1, isPlayer)
        elseif subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" then
            E.IntakeObserve(intake, now, a15, sourceGUID, "spell", a14, isPlayer)
        elseif subevent == "RANGE_DAMAGE" then
            E.IntakeObserve(intake, now, a15, sourceGUID, "ranged", a14 or 0x1, isPlayer)
        elseif subevent == "SPELL_MISSED" then
            E.IntakeObserve(intake, now, 0, sourceGUID, "spell", a14, isPlayer)
        elseif subevent == "RANGE_MISSED" then
            E.IntakeObserve(intake, now, 0, sourceGUID, "ranged", 0x1, isPlayer)
        elseif subevent == "ENVIRONMENTAL_DAMAGE" then
            E.IntakeObserve(intake, now, a13, nil, "environment", 0x1, false)
        end
    end

    if sourceGUID == playerGUID and subevent == "SPELL_CAST_SUCCESS" and type(a13) == "string" then
        DropSignalsFor(a13)
    end
end

-- ---------------------------------------------------------------------------
-- Casts aimed at you
-- ---------------------------------------------------------------------------

local function NoteIncoming(unit)
    if not unit or unit == "player" or unit == "pet" then return end
    if not UnitExists(unit) or not UnitCanAttack("player", unit) then return end
    if not UnitIsUnit(unit .. "target", "player") then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    local name, _, _, _, endMS, _, _, _, spellID = UnitCastingInfo(unit)
    if not name then
        name, _, _, _, endMS, _, _, spellID = UnitChannelInfo(unit)
    end
    if not name then return end
    incoming[guid] = {
        name = name, spellID = spellID, unit = unit,
        endTime = endMS and (endMS / 1000) or (GetTime() + 3),
    }
end

local function ForgetIncoming(unit)
    local guid = unit and UnitGUID(unit)
    if guid then incoming[guid] = nil end
end

local function CountEnemyPlayers()
    local count = 0
    local classes = {}
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
            if unit and UnitIsPlayer(unit) and UnitCanAttack("player", unit) then
                count = count + 1
                local _, token = UnitClass(unit)
                if token then classes[token] = true end
            end
        end
    end
    enemyPlayersNear = count
    enemyClassesNear = classes
end

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------

local TIER_COLORS = { "|cff88bbff", "|cffffcc44", "|cffff4444" }

local function SignalForSlot(slot)
    for _, entry in ipairs(tracked) do
        local contents = slotMap[entry.button]
        if contents and contents.slot == slot and entry.glow.signal then
            return entry.glow.signal
        end
    end
    return nil
end

local function AddTooltip(tooltip, slot)
    if not (IsOn() and db.ShowTooltip) then return end
    local signal = SignalForSlot(slot)
    if not signal then return end
    tooltip:AddLine(" ")
    tooltip:AddLine("|cffffd100\226\128\148 Advisor \226\128\148|r")
    tooltip:AddDoubleLine(TIER_COLORS[signal.tier] .. E.TierName(signal.tier) .. "|r",
        signal.reason or "", 1, 1, 1, 0.85, 0.85, 0.85)
    tooltip:Show()
end

-- ---------------------------------------------------------------------------
-- Slash surface
-- ---------------------------------------------------------------------------

local function Say(text) print("|cff66ccffCommander Advisor|r: " .. text) end

function CommanderAdvisor_Report()
    if not IsOn() then Say("off.") return end
    local S = lastSnapshot or BuildSnapshot(GetTime())
    local cfg = Config()
    Say(string.format("%s — health %d%%%s%s, %d melee / %d caster%s on you%s",
        S.inCombat and "in combat" or "out of combat",
        math.floor(S.hp * 100 + 0.5),
        S.taking and ", taking damage" or "",
        S.ttl and string.format(", ~%.0fs to live at this rate", S.ttl) or "",
        S.melee or 0, S.casters or 0, (S.casters or 0) == 1 and "" or "s",
        #S.incomingCasts > 0 and (", " .. S.incomingCasts[1].name .. " being cast at you") or ""))
    if #lastSignals > 0 then
        Say("speaking now:")
        for _, signal in ipairs(lastSignals) do
            print(string.format("  %s%s|r  %s — %s%s", TIER_COLORS[signal.tier], E.TierName(signal.tier),
                signal.spell or signal.rule.key, signal.reason or "",
                signal.onBar and "" or " |cff888888(not on a bar)|r"))
        end
    else
        Say("nothing to say right now.")
    end
    Say("every rule for this character:")
    for _, rule in ipairs(rules) do
        local mode = CommanderAdvisor.RuleMode(rule)
        local tier, reason, spellName = E.Assess(rule, S, cfg, state)
        local label = rule.item and rule.key or (spellName or E.SpellList(rule)[1] or rule.key)
        local status
        if tier then
            status = TIER_COLORS[tier] .. E.TierName(tier) .. "|r — " .. reason
        else
            status = "|cff888888" .. tostring(reason) .. "|r"
        end
        print(string.format("  %s |cffaaaaaa[%s]|r %s", label, mode, status))
    end
end

-- What the advisor sees right now, for the settings page: one short line
-- of situation and the signals it is raising.
function CommanderAdvisor.Status()
    if not IsOn() then return "Off.", "" end
    local S = lastSnapshot
    if not S then return "Waiting for the first tick.", "" end
    local situation = string.format("%s · health %d%%%s%s · %d melee, %d caster%s on you%s%s",
        S.inCombat and "In combat" or "Out of combat",
        math.floor(S.hp * 100 + 0.5),
        S.taking and " · taking damage" or "",
        S.ttl and string.format(" · ~%.0fs to live at this rate", S.ttl) or "",
        S.melee or 0, S.casters or 0, (S.casters or 0) == 1 and "" or "s",
        #S.incomingCasts > 0 and (" · " .. S.incomingCasts[1].name .. " being cast at you") or "",
        (S.control.stunned and " · stunned") or (S.control.feared and " · feared")
            or (S.control.silenced and " · silenced") or (S.control.rooted and " · rooted")
            or (S.control.snared and " · snared") or "")
    local lines = {}
    for _, signal in ipairs(lastSignals) do
        lines[#lines + 1] = string.format("%s%s|r %s — %s%s", TIER_COLORS[signal.tier], E.TierName(signal.tier),
            signal.spell or signal.rule.key, signal.reason or "",
            signal.onBar and "" or " |cff888888(not on a bar)|r")
    end
    return situation, #lines > 0 and table.concat(lines, "\n") or "|cff888888Nothing to say right now.|r"
end

function CommanderAdvisor_Test()
    if not IsOn() then Say("off.") return end
    if slotsDirty then RebuildSlots() end
    testTiers = {}
    local picked = 0
    for _, entry in ipairs(tracked) do
        if slotMap[entry.button] and entry.button:IsVisible() then
            picked = picked + 1
            testTiers[entry.button] = picked
            if picked == 3 then break end
        end
    end
    if picked == 0 then Say("no visible buttons with anything on them to light.") return end
    testUntil = GetTime() + 6
    for _, entry in ipairs(tracked) do
        local tier = testTiers[entry.button]
        if tier then
            LayoutGlow(entry)
            ShowGlow(entry.glow, tier, true)
        end
    end
    Say("lighting " .. picked .. " button" .. (picked == 1 and "" or "s") .. " — low, medium, high — for six seconds.")
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")

local SLOT_EVENTS = {
    ACTIONBAR_SLOT_CHANGED = true,
    ACTIONBAR_PAGE_CHANGED = true,
    UPDATE_BONUS_ACTIONBAR = true,
    UPDATE_SHAPESHIFT_FORM = true,
    UPDATE_MACROS = true,
    BAG_UPDATE_DELAYED = true,
}
local BOOK_EVENTS = {
    SPELLS_CHANGED = true,
    LEARNED_SPELL_IN_TAB = true,
    PET_BAR_UPDATE = true,
    UNIT_PET = true,
}
local CAST_EVENTS = {
    UNIT_SPELLCAST_START = "start",
    UNIT_SPELLCAST_CHANNEL_START = "start",
    UNIT_SPELLCAST_STOP = "stop",
    UNIT_SPELLCAST_CHANNEL_STOP = "stop",
    UNIT_SPELLCAST_INTERRUPTED = "stop",
    UNIT_SPELLCAST_FAILED = "stop",
    UNIT_SPELLCAST_SUCCEEDED = "stop",
}

local function OnSettingsUpdate()
    cachedConfig = nil
    for _, entry in ipairs(tracked) do LayoutGlow(entry) end
    -- Repaint from scratch so a colour or style change shows at once
    for _, entry in ipairs(tracked) do
        local holder = entry.glow
        if holder.tier then
            local tier = holder.tier
            HideGlow(holder)
            ShowGlow(holder, tier, false)
        end
    end
    if not IsOn() then ClearAll() end
end

local function OnEvent(_, event, arg1, arg2, arg3, arg4)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCleu()
        return
    end
    if event == "PLAYER_LOGIN" then
        db = CommanderAdvisorDB
        playerGUID = UnitGUID("player")
        BuildBook()
        cachedConfig = nil
        ScanSpellbook()
        DiscoverButtons()
        for _, entry in ipairs(tracked) do LayoutGlow(entry) end

        for name in pairs(SLOT_EVENTS) do pcall(frame.RegisterEvent, frame, name) end
        for name in pairs(BOOK_EVENTS) do pcall(frame.RegisterEvent, frame, name) end
        for name in pairs(CAST_EVENTS) do pcall(frame.RegisterEvent, frame, name) end
        pcall(frame.RegisterEvent, frame, "UNIT_SPELLCAST_SENT")
        pcall(frame.RegisterEvent, frame, "PLAYER_ENTERING_WORLD")
        pcall(frame.RegisterEvent, frame, "PLAYER_REGEN_DISABLED")
        pcall(frame.RegisterEvent, frame, "PLAYER_REGEN_ENABLED")
        -- The player's health only: UNIT_HEALTH unfiltered fires for every
        -- unit in a raid
        if frame.RegisterUnitEvent then
            pcall(frame.RegisterUnitEvent, frame, "UNIT_HEALTH", "player")
        else
            pcall(frame.RegisterEvent, frame, "UNIT_HEALTH")
        end
        if GetCLEU then
            local ok = pcall(frame.RegisterEvent, frame, "COMBAT_LOG_EVENT_UNFILTERED")
            if not ok and frame.RegisterEventCallback then
                pcall(frame.RegisterEventCallback, frame, "COMBAT_LOG_EVENT_UNFILTERED")
            end
        else
            Say("|cffff4433this client exposes no combat-log getter|r — the advisor cannot see what is hitting you; only missing buffs will be mentioned.")
        end

        Commander.AddListener(COMMANDER_ADVISOR_EVENTS.UPDATE, OnSettingsUpdate)

        -- Five ticks a second is plenty for a glow; a sharp health drop
        -- forces one early (below)
        C_Timer.NewTicker(0.2, Tick)
        C_Timer.NewTicker(1.0, function()
            if IsOn() then pcall(CountEnemyPlayers) end
        end)
        C_Timer.NewTicker(3.0, function() slotsDirty = true end)
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        E.IntakeClear(intake)
        incoming = {}
        state = E.NewState()
        slotsDirty = true
        return
    end
    if not IsOn() then return end

    if SLOT_EVENTS[event] then
        slotsDirty = true
    elseif BOOK_EVENTS[event] then
        ScanSpellbook()
        slotsDirty = true
    elseif event == "UNIT_SPELLCAST_SENT" then
        if arg1 == "player" then
            local name = type(arg4) == "number" and GetSpellInfo(arg4) or nil
            if name then
                DropSignalsFor(name)
                Tick()
            end
        end
    elseif CAST_EVENTS[event] then
        if arg1 ~= "player" and arg1 ~= "pet" then
            if CAST_EVENTS[event] == "start" then
                pcall(NoteIncoming, arg1)
            else
                pcall(ForgetIncoming, arg1)
            end
        end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        Tick()
    elseif event == "UNIT_HEALTH" and arg1 == "player" then
        -- A hit that takes a big bite runs the judgement now rather than
        -- up to a fifth of a second from now
        local hpNow, hpMax = UnitHealth("player"), UnitHealthMax("player")
        if lastSnapshot and hpMax and hpMax > 0 then
            local frac = hpNow / hpMax
            if lastSnapshot.hp - frac >= 0.10 then Tick() end
        end
    end
end

frame:SetScript("OnEvent", OnEvent)

-- The reason rides Blizzard's own action tooltip; SetAction is the single
-- entry point every bar uses.
local hooked = false
local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
hookFrame:SetScript("OnEvent", function()
    if hooked then return end
    hooked = true
    hooksecurefunc(GameTooltip, "SetAction", function(tooltip, slot)
        pcall(AddTooltip, tooltip, slot)
    end)
end)
