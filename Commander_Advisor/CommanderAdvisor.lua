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
local bursts = {}           -- sourceGUID -> { name, kind, until }: offensive cooldowns seen on enemies
local recentCasts = {}      -- spell name -> GetTime() of the last cast
local lastSnapshot
local lastSignals = {}
local lastReport = {}       -- rule key -> reason, from the last tick, for the report
local enemyPlayersNear = 0
local enemyClassesNear = {}   -- class token -> true, hostile players in nameplate range
local hasGroupRules = false   -- this class has a rule about a teammate
local seats = {}              -- you, then your party (your subgroup in a raid)
local jumpUnits = {}          -- everyone a Mending could land on: the whole group
local seatOf = {}             -- guid -> seat unit, for the combat log
local allyIntake = {}         -- guid -> intake book, one per teammate

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
    hasGroupRules = false
    for _, rule in ipairs(rules) do
        if rule.scope then hasGroupRules = true end
        if rule.notOutMine then watchSpells[rule.notOutMine] = true end
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
    local macroID
    if actionType == "macro" then
        macroID = id
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
        if name then
            local out = { kind = "spell", name = name, id = id, slot = slot }
            -- A macro's own targeting, for the buttons whose overlay is about
            -- the unit the button would land on
            if macroID and CommanderAdvisor.WatchKind(name) then
                out.options = CommanderAdvisor.MacroOptions(macroID, name)
            end
            return out
        end
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

    -- Offensive cooldowns running on someone who is on you: melee and spell
    -- flavours, the most recent name for the tooltip
    local burst
    for guid, b in pairs(bursts) do
        if b.until_ < now then
            bursts[guid] = nil
        elseif sum.attackerSet[b.guid or guid] or b.onMe then
            burst = burst or {}
            burst[b.kind] = true
            if not burst.at or b.at > burst.at then burst.name, burst.at = b.name, b.at end
        end
    end
    S.enemyBurst = burst

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
    if hasGroupRules or CommanderAdvisor.WatchWanted() then
        CommanderAdvisor.BuildGroup(S, now)
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
-- The group: who is on your team, and what is on them
--
-- Built every tick that something needs it -- a rule about a teammate, or
-- a Shield or Mending button on a bar -- from the seats (you, then party1-4;
-- your own subgroup in a raid). Each seat gets a small snapshot of its own:
-- health, its own intake book's answers, its buffs and debuffs, whether your
-- spells reach it. That list is what a group rule's ladder is walked
-- against (E.AssessAllies), and the same facts paint the button overlays.
-- ---------------------------------------------------------------------------

local SPELL_IDS = { PWS = 17, WS = 6788, POM = 33076 }
local SPELL_FALLBACK = { PWS = "Power Word: Shield", WS = "Weakened Soul", POM = "Prayer of Mending" }
local spellNames = {}
-- Thirty- and forty-yard friendly spells a priest may know: the only range
-- answers this client gives about a teammate when it gives no position
local RANGE30 = { "Dispel Magic", "Power Word: Fortitude", "Fear Ward", "Abolish Disease",
    "Cure Disease", "Divine Spirit", "Shadow Protection" }
local RANGE40 = { "Power Word: Shield", "Renew", "Flash Heal", "Prayer of Mending" }

local function SpellName(key)
    local n = spellNames[key]
    if n then return n end
    n = GetSpellInfo and GetSpellInfo(SPELL_IDS[key]) or nil
    n = n or SPELL_FALLBACK[key]
    spellNames[key] = n
    return n
end

-- Which overlay a spell's button wears, if any
function CommanderAdvisor.WatchKind(name)
    if name == SpellName("PWS") then return "PWS" end
    if name == SpellName("POM") then return "POM" end
    return nil
end

function CommanderAdvisor.WatchWanted()
    return db and (db.ShieldWatch or db.MendingWatch) and (known[SpellName("PWS")] or known[SpellName("POM")])
        and true or false
end

-- The conditional half of the macro line that casts `spellName`:
-- "/cast [@mouseover,help,nodead][] Power Word: Shield" gives back
-- "[@mouseover,help,nodead][] Power Word: Shield", which the client's own
-- parser can then answer for at any moment (see SubjectFor).
function CommanderAdvisor.MacroOptions(macroID, spellName)
    local body = GetMacroBody and GetMacroBody(macroID)
    if type(body) ~= "string" then return nil end
    for line in body:gmatch("[^\r\n]+") do
        local cmd, rest = line:match("^%s*(/%a+)%s+(.*)$")
        cmd = cmd and cmd:lower()
        if (cmd == "/cast" or cmd == "/use") and rest:find(spellName, 1, true) then
            return rest
        end
    end
    return nil
end

local function GroupUnits()
    wipe(seats)
    wipe(jumpUnits)
    seats[1] = "player"
    if IsInRaid and IsInRaid() and GetRaidRosterInfo then
        local n = math.min(GetNumGroupMembers and GetNumGroupMembers() or 0, 40)
        local mine
        for i = 1, n do
            jumpUnits[#jumpUnits + 1] = "raid" .. i
            if not mine and UnitIsUnit("raid" .. i, "player") then mine = select(3, GetRaidRosterInfo(i)) end
        end
        if mine then
            for i = 1, n do
                local unit = "raid" .. i
                if select(3, GetRaidRosterInfo(i)) == mine and not UnitIsUnit(unit, "player") and #seats < 5 then
                    seats[#seats + 1] = unit
                end
            end
        end
    else
        jumpUnits[1] = "player"
        for i = 1, 4 do
            if UnitExists("party" .. i) then
                seats[#seats + 1] = "party" .. i
                jumpUnits[#jumpUnits + 1] = "party" .. i
            end
        end
    end
    wipe(seatOf)
    for _, unit in ipairs(seats) do
        local guid = UnitGUID(unit)
        if guid then seatOf[guid] = unit end
    end
    for guid in pairs(allyIntake) do
        if not seatOf[guid] then allyIntake[guid] = nil end
    end
end
CommanderAdvisor.RefreshGroup = GroupUnits

-- Buffs and debuffs on one unit, by name: whose, when they end, how many.
-- Cached per GUID and read again only when UNIT_AURA says that unit changed
-- (or a second has passed, in case an event went by): five teammates at
-- five ticks a second would otherwise be two thousand aura reads a second,
-- each of them a fresh table. Expiry times are absolute, so a cached answer
-- stays right until the auras themselves change.
local auraCache = {}        -- guid -> { at, auras, debuffs, debuffTypes }
local auraDirty = {}        -- guid -> true once UNIT_AURA has fired for it
function CommanderAdvisor.AuraChanged(unit)
    -- Only someone we are holding an answer for: UNIT_AURA fires for every
    -- nameplate in a battleground, and none of those are worth remembering
    local guid = unit and auraCache and UnitGUID(unit)
    if guid and auraCache[guid] then auraDirty[guid] = true end
end
-- Forget anyone not read for a while (a target, a mouseover) -- called from
-- the once-a-second ticker
function CommanderAdvisor.PruneAuras(now)
    for guid, c in pairs(auraCache) do
        if now - c.at > 5 then
            auraCache[guid] = nil
            auraDirty[guid] = nil
        end
    end
end
local function ReadAuras(unit, f, now)
    local guid = f.guid
    local c = guid and auraCache[guid]
    if c and not auraDirty[guid] and now - c.at < 1 then
        f.auras, f.debuffs, f.debuffTypes = c.auras, c.debuffs, c.debuffTypes
        return
    end
    f.auras, f.debuffs, f.debuffTypes = {}, {}, {}
    if guid then
        auraCache[guid] = { at = now, auras = f.auras, debuffs = f.debuffs, debuffTypes = f.debuffTypes }
        auraDirty[guid] = nil
    end
    if not (C_UnitAuras and C_UnitAuras.GetBuffDataByIndex) then return end
    for i = 1, 40 do
        local a = C_UnitAuras.GetBuffDataByIndex(unit, i, "HELPFUL")
        if not a then break end
        if a.name then
            local mine = a.sourceUnit and UnitIsUnit(a.sourceUnit, "player") or false
            if not f.auras[a.name] or mine then
                f.auras[a.name] = { expire = a.expirationTime or 0, duration = a.duration,
                    mine = mine, stacks = a.applications, spellId = a.spellId }
            end
        end
    end
    for i = 1, 40 do
        local a = C_UnitAuras.GetDebuffDataByIndex(unit, i, "HARMFUL")
        if not a then break end
        if a.name then
            f.debuffs[a.name] = { expire = a.expirationTime or 0, duration = a.duration, spellId = a.spellId }
            local kind = a.dispelName
            if kind and kind ~= "" then f.debuffTypes[kind] = (f.debuffTypes[kind] or 0) + 1 end
        end
    end
end

-- Does your spell reach them? false only on a real "no": an unanswered
-- question is not a reason to go quiet
local function InRange(unit)
    if UnitIsUnit(unit, "player") then return true end
    if IsSpellInRange then
        local r = IsSpellInRange(SpellName("PWS"), unit)
        if r == 0 then return false end
        if r == 1 then return true end
    end
    if UnitInRange then
        local inRange, checked = UnitInRange(unit)
        if checked and not inRange then return false end
    end
    return true
end

-- Where a group member is, as evidence for the reach estimate (E.Between):
-- a real position when the client gives one, and range bounds from you
-- either way. Held for 0.4s: people do not move twenty yards in that.
local whereCache = {}
local function FirstKnown(list)
    for _, name in ipairs(list) do if known[name] then return name end end
end
local function Where(unit, now)
    local w = whereCache[unit]
    if w and now - w.at < 0.4 then return w end
    w = { at = now, unit = unit }
    whereCache[unit] = w
    if not UnitExists(unit) then w.dead = true return w end
    w.dead = (UnitIsDeadOrGhost(unit) or (UnitIsConnected and not UnitIsConnected(unit))) and true or false
    if UnitIsUnit(unit, "player") then w.lo, w.hi = 0, 0 end
    if UnitPosition then
        local ok, y, x, _, inst = pcall(UnitPosition, unit)
        if ok and x then w.pos = { x = x, y = y, inst = inst } end
    end
    if not w.hi and IsSpellInRange then
        local s30, s40 = FirstKnown(RANGE30), FirstKnown(RANGE40)
        local r = s30 and IsSpellInRange(s30, unit)
        if r == 1 then w.hi = 30 elseif r == 0 then w.lo = 30 end
        r = s40 and IsSpellInRange(s40, unit)
        if r == 1 then w.hi = math.min(w.hi or 40, 40) elseif r == 0 then w.lo = math.max(w.lo or 0, 40) end
    end
    return w
end

-- Can a Mending on `unit` bounce on: "YES", "NO" or nil (cannot tell)
local function ReachOf(unit, now)
    if not (unit and UnitExists(unit)) then return nil, 0 end
    if #jumpUnits < 2 then return nil, 0 end
    local holder = Where(unit, now)
    local others = {}
    for _, u in ipairs(jumpUnits) do
        if not UnitIsUnit(u, unit) then others[#others + 1] = Where(u, now) end
    end
    return E.BounceReach(holder, others)
end
CommanderAdvisor.ReachOf = ReachOf

local facts = {}            -- unit -> what the overlays know about them this tick
local pomHolder             -- the unit carrying YOUR Mending, if a seat is

local function Facts(unit, now)
    local f = facts[unit]
    if f then return f end
    f = { unit = unit }
    facts[unit] = f
    if not UnitExists(unit) then f.missing = true return f end
    f.guid = UnitGUID(unit)
    f.name = UnitName(unit)
    local _, class = UnitClass(unit)
    f.class = class
    f.isPlayer = UnitIsUnit(unit, "player") and true or false
    f.dead = (UnitIsDeadOrGhost(unit) or (UnitIsConnected and not UnitIsConnected(unit))) and true or false
    f.inRange = InRange(unit)
    ReadAuras(unit, f, now)
    local ws = f.debuffs[SpellName("WS")]
    if ws and ws.expire and ws.expire > now then f.ws = ws end
    local sh = f.auras[SpellName("PWS")]
    if sh and (not sh.expire or sh.expire == 0 or sh.expire > now) then f.shield = sh end
    local pom = f.auras[SpellName("POM")]
    if pom and pom.mine then f.pom = pom end
    return f
end

function CommanderAdvisor.BuildGroup(S, now)
    wipe(facts)
    pomHolder = nil
    if #seats == 0 then GroupUnits() end
    local allies = {}
    S.mineOut = {}
    for _, unit in ipairs(seats) do
        local f = Facts(unit, now)
        if not f.missing then
            if f.pom then
                pomHolder = unit
                S.mineOut[SpellName("POM")] = true
            end
            local a
            if f.isPlayer then
                -- You, from the snapshot the self rules already read
                a = { unit = "player", guid = playerGUID, name = f.name, class = f.class, isPlayer = true,
                    hp = S.hp, taking = S.taking, ttl = S.ttl, melee = S.melee, casters = S.casters,
                    attackers = S.attackers, enemyPlayers = S.enemyPlayers, enemyBurst = S.enemyBurst,
                    inCombat = S.inCombat, dead = S.dead, inRange = true,
                    auras = S.auras, debuffs = S.debuffs, debuffTypes = S.debuffTypes }
            else
                local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
                if not hpMax or hpMax <= 0 then hpMax = 1 end
                a = { unit = unit, guid = f.guid, name = f.name, class = f.class, isPlayer = false,
                    hp = (hp or hpMax) / hpMax, dead = f.dead, inRange = f.inRange,
                    inCombat = UnitAffectingCombat(unit) and true or false,
                    auras = f.auras, debuffs = f.debuffs, debuffTypes = f.debuffTypes }
                local book = f.guid and allyIntake[f.guid]
                if book then
                    local sum = E.IntakeSummary(book, now, hp)
                    a.taking, a.ttl, a.rate = sum.taking, sum.ttl, sum.rate
                    a.melee, a.casters, a.attackers, a.enemyPlayers =
                        sum.melee, sum.casters, sum.attackers, sum.enemyPlayers
                    -- An offensive cooldown on anyone who is hitting them
                    for guid, b in pairs(bursts) do
                        if b.until_ >= now and sum.attackerSet[b.guid or guid] then
                            a.enemyBurst = a.enemyBurst or {}
                            a.enemyBurst[b.kind] = true
                            a.enemyBurst.name = b.name
                        end
                    end
                end
            end
            -- Mending's reach from them, for the rule's tie-break and its words
            if hasGroupRules and known[SpellName("POM")] then a.reach = ReachOf(unit, now) end
            allies[#allies + 1] = a
        end
    end
    S.allies = allies
    S.seatCount = #seats
end

-- ---------------------------------------------------------------------------
-- The overlays: Weakened Soul on the Shield button, Mending on its own
--
-- An action button tells you a spell's cooldown and nothing about the
-- target. A Power Word: Shield button is pressable on a teammate who has
-- Weakened Soul -- the client will simply refuse it -- so the one fact that
-- decides the press is missing from the button you press. These put it
-- there, for the unit the button would actually land on right now: a
-- macro's own @unit when its conditions pick one (@mouseover on a frame,
-- @focus...), else your target if it is friendly, else you.
--
--   Shield    Weakened Soul as a dark red clock wipe across the button with
--             its seconds written large, red when they have no shield (you
--             cannot help them with this button), pale when the shield is
--             still holding; a red rim for the bare-and-locked case; their
--             name across the top when it is not you. Along the bottom, one
--             pip per seat -- blue shielded, red locked and bare, yellow
--             shieldable, grey dead -- with the one the Advisor wants
--             shielded standing taller.
--   Mending   where yours is (the holder's name across the top), its
--             charges along the bottom, and a rim for whether it can bounce
--             on from them: green, somebody is within twenty yards; red,
--             nobody is; no rim, no way to tell. With none out, the same
--             rim answers for whoever the button would cast it on.
--
-- Everything is drawn on our own insecure child of the button, like the
-- glow, and never on the button itself.
-- ---------------------------------------------------------------------------

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local PIP_COLORS = {
    SHIELDED = { 0.35, 0.65, 1.00 },
    EXPOSED  = { 0.95, 0.22, 0.20 },
    READY    = { 1.00, 0.90, 0.25 },
    DEAD     = { 0.30, 0.30, 0.32 },
}
local REACH_COLORS = { YES = { 0.30, 1.00, 0.40 }, NO = { 1.00, 0.22, 0.18 } }
local watch = {}            -- button -> overlay

local function Edge(parent, sublevel)
    local t = parent:CreateTexture(nil, "OVERLAY", nil, sublevel or 4)
    t:SetTexture(WHITE)
    t:Hide()
    return t
end

local function EnsureWatch(button)
    local w = watch[button]
    if w then return w end
    w = CreateFrame("Frame", nil, button)
    w:SetAllPoints(button)
    w:SetFrameLevel(math.min((button:GetFrameLevel() or 1) + 3, 126))
    w.watch = true

    w.cd = CreateFrame("Cooldown", nil, w, "CooldownFrameTemplate")
    w.cd:SetPoint("TOPLEFT", w, "TOPLEFT", 2, -2)
    w.cd:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -2, 2)
    if w.cd.SetHideCountdownNumbers then w.cd:SetHideCountdownNumbers(true) end
    if w.cd.SetDrawEdge then w.cd:SetDrawEdge(false) end
    if w.cd.SetDrawBling then w.cd:SetDrawBling(false) end
    if w.cd.SetReverse then w.cd:SetReverse(false) end
    if w.cd.SetSwipeColor then w.cd:SetSwipeColor(0.45, 0.02, 0.02, 0.72) end
    w.cd.noCooldownCount, w.cd.noOCC = true, true
    if w.cd.EnableMouse then w.cd:EnableMouse(false) end
    w.cd:Hide()

    local over = CreateFrame("Frame", nil, w)
    over:SetAllPoints(w)
    over:SetFrameLevel(math.min(w:GetFrameLevel() + 1, 127))
    w.over = over
    w.text = over:CreateFontString(nil, "OVERLAY")
    w.text:SetFont(FONT, 15, "OUTLINE")
    w.text:SetPoint("CENTER", w, "CENTER", 0, 1)
    w.name = over:CreateFontString(nil, "OVERLAY")
    w.name:SetFont(FONT, 8, "OUTLINE")
    w.name:SetPoint("TOP", w, "TOP", 0, -1)
    w.count = over:CreateFontString(nil, "OVERLAY")
    w.count:SetFont(FONT, 11, "OUTLINE")
    w.count:SetPoint("BOTTOM", w, "BOTTOM", 0, 5)

    -- The rim: four hairlines inside the button's edge
    w.rim = {}
    for i = 1, 4 do w.rim[i] = Edge(over, 5) end
    w.rim[1]:SetPoint("TOPLEFT", w, "TOPLEFT", 1, -1); w.rim[1]:SetPoint("TOPRIGHT", w, "TOPRIGHT", -1, -1)
    w.rim[2]:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 1, 1); w.rim[2]:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -1, 1)
    w.rim[3]:SetPoint("TOPLEFT", w, "TOPLEFT", 1, -1); w.rim[3]:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 1, 1)
    w.rim[4]:SetPoint("TOPRIGHT", w, "TOPRIGHT", -1, -1); w.rim[4]:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -1, 1)
    for i = 1, 2 do w.rim[i]:SetHeight(2) end
    for i = 3, 4 do w.rim[i]:SetWidth(2) end

    w.pips = {}
    for i = 1, 5 do w.pips[i] = Edge(over, 6) end
    watch[button] = w
    return w
end

local function SetRim(w, color)
    for i = 1, 4 do
        if color then
            w.rim[i]:SetVertexColor(color[1], color[2], color[3], 1)
            w.rim[i]:Show()
        else
            w.rim[i]:Hide()
        end
    end
    w.rimColor = color
end

local function HideWatch(w)
    if not w or not w.shown then return end
    w.shown = false
    w.cd:Hide()
    w.wsStop = nil
    w.text:SetText("")
    w.name:SetText("")
    w.count:SetText("")
    SetRim(w, nil)
    for i = 1, 5 do w.pips[i]:Hide() end
    w.tip = nil
    w:Hide()
end

-- The unit this button would land on right now
local function DefaultSubject()
    if UnitExists("target") and UnitCanAssist and UnitCanAssist("player", "target") then return "target" end
    return "player"
end
local function SubjectFor(slot)
    if slot.options and SecureCmdOptionParse then
        local ok, action, target = pcall(SecureCmdOptionParse, slot.options)
        if ok and action and action ~= "" and target and target ~= "" and UnitExists(target) then
            return target
        end
    end
    return DefaultSubject()
end

local function ShortName(f)
    if not f or f.missing or f.isPlayer then return "" end
    local name = f.name or ""
    if #name > 7 then name = name:sub(1, 7) end
    local c = f.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[f.class]
    if c then return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name) end
    return name
end

local function PaintShield(w, button, slot, now, signal)
    local subject = SubjectFor(slot)
    local f = Facts(subject, now)
    local tip = {}
    -- Weakened Soul across the face
    if f.ws then
        local stop = f.ws.expire
        local dur = math.max(f.ws.duration or 15, stop - now)
        if w.wsStop ~= stop or not w.cd:IsShown() then
            w.wsStop = stop
            w.cd:SetCooldown(stop - dur, dur)
            w.cd:Show()
        end
        w.text:SetText(tostring(math.ceil(stop - now)))
        if f.shield then
            w.text:SetTextColor(0.85, 0.85, 0.85)
        else
            w.text:SetTextColor(1, 0.25, 0.22)
        end
        tip[#tip + 1] = string.format("%s: Weakened Soul %ds%s", f.isPlayer and "You" or (f.name or "?"),
            math.ceil(stop - now), f.shield and ", shield still holding" or ", no shield")
    else
        w.cd:Hide()
        w.wsStop = nil
        w.text:SetText("")
        if not f.missing then
            tip[#tip + 1] = string.format("%s: %s", f.isPlayer and "You" or (f.name or "?"),
                f.shield and "shielded" or "no Weakened Soul — shield them")
        end
    end
    SetRim(w, (f.ws and not f.shield) and PIP_COLORS.EXPOSED or nil)
    w.name:SetText(db.WatchNames and ShortName(f) or "")

    -- The team, one pip a seat
    local n = (db.TeamPips and #seats > 1) and #seats or 0
    local who = signal and signal.who and signal.who.unit
    local width = (button.GetWidth and button:GetWidth()) or 36
    if width <= 0 then width = 36 end
    local pipW = math.max(3, math.floor((width - 6 - (n - 1)) / math.max(n, 1)))
    for i = 1, 5 do
        local pip = w.pips[i]
        if i <= n then
            local sf = Facts(seats[i], now)
            local key = (sf.missing or sf.dead) and "DEAD" or sf.shield and "SHIELDED"
                or sf.ws and "EXPOSED" or "READY"
            local c = PIP_COLORS[key]
            local tall = who and UnitIsUnit(who, seats[i])
            pip:SetVertexColor(c[1], c[2], c[3], (sf.inRange == false) and 0.4 or 1)
            pip:ClearAllPoints()
            pip:SetSize(pipW, tall and 6 or 3)
            pip:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 3 + (i - 1) * (pipW + 1), 2)
            pip.state, pip.tall = key, tall and true or false
            pip:Show()
        else
            pip:Hide()
        end
    end
    w.tip = tip
end

local function PaintMending(w, button, slot, now)
    local tip = {}
    local holder = pomHolder
    local f, reach
    if holder then
        f = Facts(holder, now)
        reach = ReachOf(holder, now)
        local stacks = f.pom and f.pom.stacks
        w.count:SetText((stacks and stacks > 0) and tostring(stacks) or "")
        w.name:SetText(db.WatchNames and (f.isPlayer and "|cffffffffyou|r" or ShortName(f)) or "")
        tip[#tip + 1] = string.format("Your Mending is on %s%s", f.isPlayer and "you" or (f.name or "?"),
            (stacks and stacks > 0) and string.format(" with %d charge%s", stacks, stacks == 1 and "" or "s") or "")
    else
        local subject = SubjectFor(slot)
        f = Facts(subject, now)
        reach = (#seats > 1) and ReachOf(subject, now) or nil
        w.count:SetText("")
        w.name:SetText(db.WatchNames and ShortName(f) or "")
    end
    SetRim(w, reach and REACH_COLORS[reach] or nil)
    w.reach = reach
    if reach == "YES" then
        tip[#tip + 1] = "Somebody is within 20 yd of " .. (f.isPlayer and "you" or (f.name or "them")) .. ": it can bounce"
    elseif reach == "NO" then
        tip[#tip + 1] = "Nobody is within 20 yd of " .. (f.isPlayer and "you" or (f.name or "them")) .. ": the next hit wastes the rest"
    elseif #seats > 1 then
        tip[#tip + 1] = "Bounce range: this client gives no positions here"
    end
    w.cd:Hide()
    w.text:SetText("")
    for i = 1, 5 do w.pips[i]:Hide() end
    w.tip = tip
end

local function PaintWatch(S)
    local on = IsOn() and CommanderAdvisor.WatchWanted() and not S.dead
    local now = S.now
    for _, entry in ipairs(tracked) do
        local button = entry.button
        local slot = slotMap[button]
        local kind = on and slot and slot.kind == "spell" and CommanderAdvisor.WatchKind(slot.name)
        if kind == "PWS" and not db.ShieldWatch then kind = nil end
        if kind == "POM" and not db.MendingWatch then kind = nil end
        if kind and button.IsVisible and button:IsVisible() then
            local w = EnsureWatch(button)
            if kind == "PWS" then
                PaintShield(w, button, slot, now, entry.glow.signal)
            else
                PaintMending(w, button, slot, now)
            end
            if not w.shown then
                w.shown = true
                w:Show()
            end
        else
            HideWatch(watch[button])
        end
    end
end

-- Every overlay down at once (the master switch)
function CommanderAdvisor.HideAllWatch()
    for _, w in pairs(watch) do HideWatch(w) end
end

-- What the overlay on a button knows, for its tooltip
function CommanderAdvisor.WatchLines(slot)
    for _, entry in ipairs(tracked) do
        local contents = slotMap[entry.button]
        local w = watch[entry.button]
        if contents and contents.slot == slot and w and w.shown and w.tip then return w.tip end
    end
    return nil
end

-- For the harness: the overlay a button wears, if any
function CommanderAdvisor.WatchFor(button) return watch[button] end

-- /cadv range: what the reach estimate is working from, seat by seat. The
-- one question an arena has to answer before the Mending rim can be
-- trusted there is whether this client gives group positions in one.
function CommanderAdvisor_RangeReport()
    GroupUnits()
    local now = GetTime()
    wipe(whereCache)
    print("|cff66ccffCommander Advisor|r: bounce range, seat by seat")
    for _, unit in ipairs(jumpUnits) do
        local w = Where(unit, now)
        local name = UnitName(unit) or unit
        local pos = w.pos and string.format("position %.0f, %.0f", w.pos.x, w.pos.y) or "no position"
        local bounds = string.format("%s%s", w.lo and (">=" .. w.lo .. "yd ") or "", w.hi and ("<=" .. w.hi .. "yd") or "")
        local reach, count = ReachOf(unit, now)
        print(string.format("  %s (%s): %s %s — Mending on them: %s", name, unit, pos, bounds,
            reach == "YES" and ("bounces (" .. count .. " in reach)") or reach == "NO" and "would not bounce"
            or "cannot tell"))
    end
end

-- ---------------------------------------------------------------------------
-- The tick
-- ---------------------------------------------------------------------------

local function Tick()
    if not IsOn() then
        if litCount > 0 then ClearAll() end
        CommanderAdvisor.HideAllWatch()
        return
    end
    if slotsDirty then RebuildSlots() end
    local now = GetTime()
    local S = BuildSnapshot(now)
    lastSnapshot = S
    local signals = E.Evaluate(S, rules, Config(), state)
    lastSignals = signals
    Paint(signals, S)
    PaintWatch(S)
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

    -- Your own intake, and each teammate's in a book of its own: a rule
    -- about a teammate asks the same questions of them that the self rules
    -- ask of you
    local book
    if destGUID == playerGUID then
        book = intake
    elseif destGUID and seatOf[destGUID] and hasGroupRules then
        book = allyIntake[destGUID]
        if not book then
            book = E.NewIntake()
            allyIntake[destGUID] = book
        end
    end
    if book then
        local now = GetTime()
        local isPlayer = type(sourceGUID) == "string" and sourceGUID:sub(1, 6) == "Player"
        if subevent == "SWING_DAMAGE" then
            E.IntakeObserve(book, now, a12, sourceGUID, "melee", a14 or 0x1, isPlayer)
        elseif subevent == "SWING_MISSED" then
            E.IntakeObserve(book, now, 0, sourceGUID, "melee", 0x1, isPlayer)
        elseif subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" then
            E.IntakeObserve(book, now, a15, sourceGUID, "spell", a14, isPlayer)
        elseif subevent == "RANGE_DAMAGE" then
            E.IntakeObserve(book, now, a15, sourceGUID, "ranged", a14 or 0x1, isPlayer)
        elseif subevent == "SPELL_MISSED" then
            E.IntakeObserve(book, now, 0, sourceGUID, "spell", a14, isPlayer)
        elseif subevent == "RANGE_MISSED" then
            E.IntakeObserve(book, now, 0, sourceGUID, "ranged", 0x1, isPlayer)
        elseif subevent == "ENVIRONMENTAL_DAMAGE" then
            E.IntakeObserve(book, now, a13, nil, "environment", 0x1, false)
        end
    end

    if sourceGUID == playerGUID then
        if subevent == "SPELL_CAST_SUCCESS" and type(a13) == "string" then DropSignalsFor(a13) end
        return
    end

    -- An enemy popping an offensive cooldown. Hostile by flag; counted only
    -- if they are on you already or have you targeted, which is read off any
    -- unit token they are currently held under.
    if (subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_CAST_SUCCESS") and type(a13) == "string"
        and type(sourceFlags) == "number" and sourceFlags % 0x80 >= 0x40 then
        local kind, duration
        if D.BURST_MELEE[a13] then kind, duration = "melee", D.BURST_MELEE[a13] end
        if D.BURST_SPELL[a13] then kind, duration = "spell", D.BURST_SPELL[a13] end
        if kind and sourceGUID then
            local now = GetTime()
            local onMe = false
            for _, unit in ipairs({ "target", "focus", "arena1", "arena2", "arena3", "arena4", "arena5" }) do
                if UnitGUID(unit) == sourceGUID then
                    onMe = UnitIsUnit(unit .. "target", "player") and true or false
                    break
                end
            end
            if not onMe and C_NamePlate and C_NamePlate.GetNamePlates then
                for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
                    local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
                    if unit and UnitGUID(unit) == sourceGUID then
                        onMe = UnitIsUnit(unit .. "target", "player") and true or false
                        break
                    end
                end
            end
            -- Avenging Wrath is both: a paladin swings and casts harder
            local both = D.BURST_MELEE[a13] and D.BURST_SPELL[a13]
            bursts[sourceGUID] = { name = a13, kind = kind, until_ = now + duration, at = now, onMe = onMe, both = both }
            if both then
                bursts[sourceGUID .. ":2"] = { name = a13, kind = "melee", until_ = now + duration, at = now, onMe = onMe, guid = sourceGUID }
            end
        end
    elseif subevent == "SPELL_AURA_REMOVED" and type(a13) == "string" and sourceGUID
        and (D.BURST_MELEE[a13] or D.BURST_SPELL[a13]) then
        local b = bursts[sourceGUID]
        if b and b.name == a13 then bursts[sourceGUID] = nil end
        b = bursts[sourceGUID .. ":2"]
        if b and b.name == a13 then bursts[sourceGUID .. ":2"] = nil end
    elseif subevent == "UNIT_DIED" and destGUID then
        bursts[destGUID] = nil
        bursts[destGUID .. ":2"] = nil
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
    local lines = CommanderAdvisor.WatchLines and CommanderAdvisor.WatchLines(slot)
    if not signal and not (lines and #lines > 0) then return end
    tooltip:AddLine(" ")
    tooltip:AddLine("|cffffd100\226\128\148 Advisor \226\128\148|r")
    if signal then
        tooltip:AddDoubleLine(TIER_COLORS[signal.tier] .. E.TierName(signal.tier) .. "|r",
            signal.reason or "", 1, 1, 1, 0.85, 0.85, 0.85)
    end
    for _, line in ipairs(lines or {}) do
        tooltip:AddLine(line, 0.85, 0.85, 0.85)
    end
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
        pcall(frame.RegisterEvent, frame, "GROUP_ROSTER_UPDATE")
        pcall(frame.RegisterEvent, frame, "UNIT_AURA")
        CommanderAdvisor.RefreshGroup()
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
            if IsOn() then
                pcall(CountEnemyPlayers)
                -- The roster, in case an event slipped past: cheap, and a
                -- seat list that is a second stale is a wrong pip
                if hasGroupRules or CommanderAdvisor.WatchWanted() then
                    pcall(CommanderAdvisor.RefreshGroup)
                    CommanderAdvisor.PruneAuras(GetTime())
                end
            end
        end)
        C_Timer.NewTicker(3.0, function() slotsDirty = true end)
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        E.IntakeClear(intake)
        incoming = {}
        bursts = {}
        wipe(allyIntake)
        state = E.NewState()
        slotsDirty = true
        CommanderAdvisor.RefreshGroup()
        return
    end
    if event == "GROUP_ROSTER_UPDATE" then
        CommanderAdvisor.RefreshGroup()
        return
    end
    if event == "UNIT_AURA" then
        CommanderAdvisor.AuraChanged(arg1)
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
