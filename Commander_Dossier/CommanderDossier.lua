-- Commander Dossier: the combat-log ingest, the diminishing-return board,
-- and the file window. The engine owns every rule; this layer owns the
-- translation from Blizzard's combat log into engine calls, and the paint.
--
-- Why the combat log and nothing else: diminishing returns are per TARGET,
-- and in TBC you cannot read an arbitrary enemy's aura list — no unit token
-- exists for "the warlock over there" outside arena. The combat log names
-- every application and every fade inside its range regardless of whether
-- anything is targeted, which makes it the only complete source. The price
-- is that coverage equals combat-log range, and the options say so.
--
-- Visual contract (the suite's RTS rule: built for someone who is NOT
-- looking at it): geometry never shifts. Class colours are identity and are
-- never overridden; the accent marks chrome only; the four diminishing
-- states carry meaning and own their colours — green FULL, yellow half,
-- orange quarter, red IMMUNE — which is the one thing on the board a player
-- reads at a glance mid-fight.

local E = CommanderDossierEngine
local D = CommanderDossierData
local db, file

local format = string.format

-- ---------------------------------------------------------------------------
-- Theme
-- ---------------------------------------------------------------------------

local THEME = {
    font = "Fonts\\ARIALN.TTF", -- condensed, uniform digit widths (no jitter)

    bg      = { 0.045, 0.055, 0.065, 0.92 },
    chrome  = { 0.09, 0.11, 0.13, 1 },
    edge    = { 0.22, 0.27, 0.31, 1 },
    accent  = { 1.0, 0.72, 0.10 },
    text    = { 0.92, 0.94, 0.95 },
    textDim = { 0.52, 0.58, 0.62 },
    pipBack = { 1, 1, 1, 0.05 },
    neutral = { 0.6, 0.65, 0.7 },

    -- The four diminishing states. These are DATA, not decoration.
    stateFull    = { 0.40, 0.85, 0.45 },
    stateHalf    = { 1.00, 0.82, 0.20 },
    stateQuarter = { 0.95, 0.55, 0.20 },
    stateImmune  = { 0.90, 0.24, 0.20 },
    stateIdle    = { 0.38, 0.42, 0.46 },
}

local ACCENTS = {
    AMBER = { 1.0, 0.72, 0.10 },
    CYAN  = { 0.25, 0.85, 0.95 },
    GREEN = { 0.35, 0.90, 0.40 },
    RED   = { 0.95, 0.35, 0.30 },
    WHITE = { 0.95, 0.95, 0.95 },
}

local function AccentByKey(key)
    if key == "CLASS" then
        local info = Commander.GetClassInfo and Commander.GetClassInfo()
        if info and info.color then
            -- Copy, never alias: GetClassInfo memoizes that table suite-wide
            return { info.color[1], info.color[2], info.color[3] }
        end
    end
    if ACCENTS[key] then return ACCENTS[key] end
    for _, color in ipairs(CommanderConsole_Colors or {}) do
        if color.value == key and color.r then
            return { color.r, color.g, color.b }
        end
    end
    return ACCENTS.AMBER
end

local function ResolveThemeOverrides()
    THEME.accent = AccentByKey(db.AccentColor)
end

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CLASS_RING = "Interface\\TargetingFrame\\UI-Classes-Circles"

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function ShortName(name)
    if not name then return "?" end
    local dash = name:find("-", 1, true)
    if dash then return name:sub(1, dash - 1) end
    return name
end

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return THEME.neutral[1], THEME.neutral[2], THEME.neutral[3]
end

local function Ago(epoch, now)
    if not epoch then return "never" end
    local delta = (now or time()) - epoch
    if delta < 60 then return "just now" end
    if delta < 3600 then return format("%dm ago", delta / 60) end
    if delta < 86400 then return format("%dh ago", delta / 3600) end
    return format("%dd ago", delta / 86400)
end

-- What the NEXT application lands at, as a label and a colour.
local FRACTION_TEXT = { [0] = "FULL", "1/2", "1/4", "IMMUNE" }
local FRACTION_COLOR = {
    [0] = THEME.stateFull, THEME.stateHalf, THEME.stateQuarter, THEME.stateImmune,
}

-- Combat-log object flags. Declared with fallbacks because a mock (and an
-- older client) may not export them, and a nil here would silently classify
-- every unit as friendly.
local FLAG_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400
local FLAG_HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040
local band = bit and bit.band

local function IsPlayerFlag(flags)
    if not flags or not band then return false end
    return band(flags, FLAG_PLAYER) ~= 0
end

local function IsHostileFlag(flags)
    if not flags or not band then return false end
    return band(flags, FLAG_HOSTILE) ~= 0
end

-- ---------------------------------------------------------------------------
-- Identity: who is behind a GUID
--
-- GetPlayerInfoByGUID answers class, race, name and realm for any player
-- GUID without a unit token, which is exactly the gap the combat log leaves.
-- It is pcall-guarded and backed by a unit sweep, so a client that lacks it
-- degrades to "whatever we can currently see" rather than erroring per event
-- (ASSUMPTIONS A1).
-- ---------------------------------------------------------------------------

local identity = {}   -- guid -> { name, realm, class, race, key }
local ownRealm
-- Cached because the record path runs on EVERY hostile combat-log line:
-- GetRealZoneText allocates a fresh string per call, which is exactly the
-- per-event churn the suite's optimisation passes went hunting for.
local currentZone

local SWEEP_UNITS = {
    "target", "focus", "mouseover", "targettarget",
    "arena1", "arena2", "arena3", "arena4", "arena5",
}

local function KeyFor(name, realm)
    if not name or name == "" then return nil end
    local base = ShortName(name)
    return base .. "-" .. (realm and realm ~= "" and realm or ownRealm or "?")
end

local function LearnFromUnit(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    local rec = identity[guid]
    if not rec then rec = {}; identity[guid] = rec end
    local name, realm = UnitName(unit)
    rec.name = rec.name or name
    if realm and realm ~= "" then rec.realm = realm end
    local _, class = UnitClass(unit)
    if class then rec.class = class end
    -- The LOCALIZED race: this is only ever displayed, and the English token
    -- would put "Scourge" on screen where the player expects "Undead"
    local race = UnitRace(unit)
    if race then rec.race = race end
    local guild = GetGuildInfo and GetGuildInfo(unit)
    if guild then rec.guild = guild end
    local level = UnitLevel(unit)
    if level and level > 0 then rec.level = level end
    rec.key = rec.key or KeyFor(rec.name, rec.realm)
    return rec
end

local function IdentityFor(guid, logName)
    if not guid then return nil end
    local rec = identity[guid]
    if rec and rec.class then return rec end
    if not rec then rec = {}; identity[guid] = rec end

    if GetPlayerInfoByGUID then
        -- localizedClass, englishClass, localizedRace, englishRace, sex,
        -- name, realm — the English CLASS (it keys the colour tables) and the
        -- localized RACE (it is only ever shown)
        local ok, _, class, race, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
        if ok and class then
            rec.class = class
            rec.race = race or rec.race
            rec.name = name or rec.name
            if realm and realm ~= "" then rec.realm = realm end
        end
    end
    if logName then
        rec.name = rec.name or ShortName(logName)
        local dash = logName:find("-", 1, true)
        if dash and not rec.realm then rec.realm = logName:sub(dash + 1) end
    end
    rec.key = KeyFor(rec.name, rec.realm)
    return rec
end

-- ---------------------------------------------------------------------------
-- The talent index: Commander_Talents' verified grid, turned into
-- name -> { tree, treeName, row } per class. Absent Talents this returns nil
-- and the module simply never names a spec (the TopBar soft-fail pattern).
-- ---------------------------------------------------------------------------

local function BuildTalentIndex()
    local source = CommanderTalentsData
    if not source or not source.Classes then return nil end
    local index, classes = {}, 0
    for class, def in pairs(source.Classes) do
        local map = {}
        for treeIndex, tree in ipairs(def.trees or {}) do
            for _, talent in ipairs(tree.talents or {}) do
                -- First writer wins: a name appearing in two trees of one
                -- class would be ambiguous evidence anyway
                if talent.name and not map[talent.name] then
                    map[talent.name] = {
                        tree = treeIndex,
                        treeName = tree.name,
                        row = talent.row or 1,
                    }
                end
            end
        end
        index[class] = map
        classes = classes + 1
    end
    if classes == 0 then return nil end
    return index
end

-- name -> category, so a rank absent from the id table still categorises.
-- Names come from the client, which is what makes this locale-safe.
local function BuildNameIndex()
    if not GetSpellInfo then return nil end
    local map, n = {}, 0
    for _, id in ipairs(D.NameSeeds) do
        local name = GetSpellInfo(id)
        local cat = D.SpellCategory[id]
        if name and cat and not map[name] then
            map[name] = cat
            n = n + 1
        end
    end
    if n == 0 then return nil end
    return map
end

-- ---------------------------------------------------------------------------
-- Board
-- ---------------------------------------------------------------------------

local root, rows = nil, {}
local flash
local testStart = 0
local playerGUID

local HEADER_H = 18
local NAME_H = 13
local PIP_H = 22
local PIP_W = 58
local PIP_GAP = 3
local ROW_GAP = 4
local PAD = 6

local function StyleFont(fs, size, color, flags)
    fs:SetFont(THEME.font, size, flags or "OUTLINE")
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
end

local function MakeTexture(parent, layer, color)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetTexture(WHITE)
    if color then t:SetVertexColor(color[1], color[2], color[3], color[4] or 1) end
    return t
end

local function PipsPerRow(width)
    local usable = width - PAD * 2 + PIP_GAP
    local n = math.floor(usable / (PIP_W + PIP_GAP))
    if n < 1 then n = 1 end
    return n
end

local function BuildPip(rowFrame)
    local pip = CreateFrame("Frame", nil, rowFrame)
    pip:SetSize(PIP_W, PIP_H)
    pip.bg = MakeTexture(pip, "BACKGROUND", THEME.pipBack)
    pip.bg:SetAllPoints(pip)
    pip.stripe = MakeTexture(pip, "ARTWORK", THEME.stateIdle)
    pip.stripe:SetPoint("TOPLEFT", pip, "TOPLEFT", 0, 0)
    pip.stripe:SetPoint("BOTTOMLEFT", pip, "BOTTOMLEFT", 0, 0)
    pip.stripe:SetWidth(2)
    pip.label = pip:CreateFontString(nil, "OVERLAY")
    StyleFont(pip.label, 8, THEME.textDim)
    pip.label:SetPoint("TOPLEFT", pip, "TOPLEFT", 4, -2)
    pip.state = pip:CreateFontString(nil, "OVERLAY")
    StyleFont(pip.state, 11, THEME.text)
    pip.state:SetPoint("BOTTOMLEFT", pip, "BOTTOMLEFT", 4, 2)
    pip.timer = pip:CreateFontString(nil, "OVERLAY")
    StyleFont(pip.timer, 10, THEME.textDim)
    pip.timer:SetPoint("BOTTOMRIGHT", pip, "BOTTOMRIGHT", -3, 2)
    return pip
end

local function BuildRow(index)
    local row = CreateFrame("Frame", nil, root)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexture(CLASS_RING)
    row.icon:SetSize(NAME_H, NAME_H)
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.name = row:CreateFontString(nil, "OVERLAY")
    StyleFont(row.name, 12, THEME.text)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.tag = row:CreateFontString(nil, "OVERLAY")
    StyleFont(row.tag, 10, THEME.textDim)
    row.tag:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -1)
    row.pips = {}
    row.index = index
    return row
end

local function BuildBoard()
    root = CreateFrame("Frame", "CommanderDossierBoard", UIParent)
    root:SetFrameStrata("MEDIUM")
    root.bg = MakeTexture(root, "BACKGROUND", THEME.bg)
    root.bg:SetAllPoints(root)

    root.header = MakeTexture(root, "BORDER", THEME.chrome)
    root.header:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    root.header:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
    root.header:SetHeight(HEADER_H)

    root.rule = MakeTexture(root, "ARTWORK", THEME.accent)
    root.rule:SetPoint("BOTTOMLEFT", root.header, "BOTTOMLEFT", 0, 0)
    root.rule:SetPoint("BOTTOMRIGHT", root.header, "BOTTOMRIGHT", 0, 0)
    root.rule:SetHeight(1)

    root.title = root:CreateFontString(nil, "OVERLAY")
    StyleFont(root.title, 11, THEME.accent)
    root.title:SetPoint("LEFT", root.header, "LEFT", PAD, 0)
    root.title:SetText("DOSSIER")

    root.count = root:CreateFontString(nil, "OVERLAY")
    StyleFont(root.count, 10, THEME.textDim)
    root.count:SetPoint("RIGHT", root.header, "RIGHT", -PAD, 0)

    root.empty = root:CreateFontString(nil, "OVERLAY")
    StyleFont(root.empty, 11, THEME.textDim)
    root.empty:SetPoint("TOP", root, "TOP", 0, -(HEADER_H + 12))
    root.empty:SetText("no diminishing returns running")
end

local function Layout()
    local width = db.FrameWidth or 300
    local count = db.BarRows or 5
    local rowH = NAME_H + 2 + PIP_H
    root:SetSize(width, HEADER_H + PAD + count * (rowH + ROW_GAP) + PAD)

    local perRow = PipsPerRow(width)
    for i = 1, count do
        local row = rows[i]
        if not row then
            row = BuildRow(i)
            rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", root, "TOPLEFT", PAD, -(HEADER_H + PAD + (i - 1) * (rowH + ROW_GAP)))
        row:SetSize(width - PAD * 2, rowH)
        for p = 1, perRow do
            local pip = row.pips[p]
            if not pip then
                pip = BuildPip(row)
                row.pips[p] = pip
            end
            pip:ClearAllPoints()
            pip:SetPoint("TOPLEFT", row, "TOPLEFT", (p - 1) * (PIP_W + PIP_GAP), -(NAME_H + 2))
            pip:SetSize(PIP_W, PIP_H)
        end
        -- Rows shrink when the board narrows: hide the pips that no longer fit
        for p = perRow + 1, #row.pips do row.pips[p]:Hide() end
        row.perRow = perRow
    end
    for i = count + 1, #rows do rows[i]:Hide() end
end

-- Categories worth drawing on a unit, most urgent first. Sorting is by
-- diminishing level (an immune category is the one you must not waste a
-- global on), then by the data file's tactical order.
local catScratch = {}
local function GatherCategories(unit, now, showAll)
    local n = 0
    for _, entry in ipairs(D.Categories) do
        local level, left, active, spell = E.Level(unit.guid, entry.key, now)
        local relevant = level > 0
        if showAll and not relevant then
            -- Only offer a category this unit could actually suffer
            relevant = unit.isPlayer or D.PvECategories[entry.key]
        end
        if relevant then
            n = n + 1
            local slot = catScratch[n]
            if not slot then slot = {}; catScratch[n] = slot end
            slot.entry, slot.level, slot.left = entry, level, left
            slot.active, slot.spell = active, spell
        end
    end
    for i = n + 1, #catScratch do catScratch[i] = nil end
    table.sort(catScratch, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return a.entry.index < b.entry.index
    end)
    return catScratch, n
end

local function PaintPip(pip, slot)
    pip.label:SetText(slot.entry.short)
    local level = slot.level
    local color = FRACTION_COLOR[level] or THEME.stateImmune
    pip.state:SetText(FRACTION_TEXT[level] or "IMMUNE")
    pip.state:SetTextColor(color[1], color[2], color[3])
    pip.stripe:SetVertexColor(color[1], color[2], color[3], level > 0 and 1 or 0.35)
    if level == 0 then
        pip.timer:SetText("")
        pip.label:SetTextColor(THEME.stateIdle[1], THEME.stateIdle[2], THEME.stateIdle[3])
        pip.bg:SetVertexColor(1, 1, 1, 0.03)
    else
        pip.label:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
        pip.bg:SetVertexColor(color[1], color[2], color[3], 0.10)
        if slot.active then
            -- The window cannot start counting down until the effect fades;
            -- saying "0s" there would promise a reset that has not begun
            pip.timer:SetText("up")
        else
            pip.timer:SetText(format("%.0fs", slot.left))
        end
    end
    pip:Show()
end

local function Paint(now)
    if not root or not root:IsShown() then return end
    local mode = db.BoardMode or "ENEMIES"
    local list, n = E.Board(now, mode)
    local shown = db.BarRows or 5
    if n > shown then n = shown end

    root.count:SetText(n > 0 and format("%d tracked", n) or "")
    root.empty:SetShown(n == 0)

    local showAll = db.ShowAllCategories
    for i = 1, (db.BarRows or 5) do
        local row = rows[i]
        if not row then break end
        local unit = i <= n and list[i] or nil
        if not unit then
            row:Hide()
        else
            row:Show()
            local r, g, b = ClassColor(unit.class)
            row.name:SetText(ShortName(unit.name) or "?")
            row.name:SetTextColor(r, g, b)
            if unit.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[unit.class] then
                local c = CLASS_ICON_TCOORDS[unit.class]
                row.icon:SetTexCoord(c[1], c[2], c[3], c[4])
                row.icon:Show()
            else
                row.icon:Hide()
            end

            local slots, count = GatherCategories(unit, now, showAll)
            local perRow = row.perRow or 1
            local draw = count < perRow and count or perRow
            for p = 1, draw do PaintPip(row.pips[p], slots[p]) end
            for p = draw + 1, perRow do row.pips[p]:Hide() end
            if count > draw then
                row.tag:SetText(format("+%d", count - draw))
            else
                row.tag:SetText(mode == "BOTH" and (unit.hostile and "enemy" or "ally") or "")
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Immunity warning: the Impact/Threat vignette language. The LowHealth art
-- is itself red, which is exactly the colour an immunity deserves.
-- ---------------------------------------------------------------------------

local function BuildFlash()
    flash = CreateFrame("Frame", nil, UIParent)
    flash:SetAllPoints(UIParent)
    flash:SetFrameStrata("BACKGROUND")
    flash:EnableMouse(false)
    local t = flash:CreateTexture(nil, "BACKGROUND")
    t:SetTexture("Interface\\FullScreenTextures\\LowHealth")
    t:SetAllPoints(flash)
    t:SetBlendMode("ADD")
    flash.tex = t
    flash:Hide()
    flash.until_ = 0
    flash:SetScript("OnUpdate", function(self)
        local left = self.until_ - GetTime()
        if left <= 0 then
            self:Hide()
            return
        end
        self.tex:SetAlpha(left * 1.4)
    end)
end

local function FireFlash()
    if not flash then return end
    flash.until_ = GetTime() + 0.5
    flash.tex:SetAlpha(0.7)
    flash:Show()
end

local function DrainAlerts()
    E.DrainAlerts(function(kind, guid)
        if kind ~= "IMMUNE" then return end
        if not db.ImmuneWarn then return end
        local unit = E.Unit(guid)
        -- An immunity only matters on somebody we are trying to control
        if unit and unit.hostile == false and db.BoardMode == "ENEMIES" then return end
        if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.RAID_WARNING) end
        FireFlash()
    end)
end

-- ---------------------------------------------------------------------------
-- Visibility
-- ---------------------------------------------------------------------------

local function BoardActive()
    return (db.EnableDossier and db.BoardMode ~= "HIDDEN") or false
end

local function UpdateVisibility(now)
    if not root then return end
    if not BoardActive() then
        root:Hide()
        return
    end
    if Commander.UI.HudUnlocked(db, "Hud") then
        root:Show()
        return
    end
    local _, n = E.Board(now, db.BoardMode or "ENEMIES")
    local show
    if db.CombatOnly then
        show = (InCombatLockdown() and n > 0) or testStart > 0
    else
        show = n > 0 or testStart > 0
    end
    root:SetShown(show and true or false)
end

-- ---------------------------------------------------------------------------
-- Combat log ingest
-- ---------------------------------------------------------------------------

-- Subevents that mean "this aura is gone". BROKEN fires INSTEAD of REMOVED
-- when damage breaks the effect, so a fear broken by a dot must still start
-- its reset clock (tbc-2-5-5-api-notes).
local FADE_EVENTS = {
    SPELL_AURA_REMOVED = true,
    SPELL_AURA_BROKEN = true,
    SPELL_AURA_BROKEN_SPELL = true,
}

-- Casts worth remembering as evidence. Damage events are deliberately absent:
-- they repeat the same names hundreds of times a fight and would drown the
-- signal without adding one.
local WITNESS_EVENTS = {
    SPELL_CAST_SUCCESS = true,
    SPELL_AURA_APPLIED = true,
    SPELL_SUMMON = true,
    SPELL_RESURRECT = true,
}

local function RecordFor(guid, logName, flags, epoch)
    if not db.RecordIntel then return nil end
    if not IsPlayerFlag(flags) or not IsHostileFlag(flags) then return nil end
    local id = IdentityFor(guid, logName)
    if not id or not id.key then return nil end
    return E.Observe(id.key, {
        name = id.name, realm = id.realm, class = id.class, race = id.race,
        guild = id.guild, level = id.level, zone = currentZone,
    }, epoch), id
end

local function HandleCombatLog()
    local _, sub, _, srcGUID, srcName, srcFlags, _,
          dstGUID, dstName, dstFlags, _, spellId, spellName, _, auraType =
        CombatLogGetCurrentEventInfo()

    local now = GetTime()
    local epoch = time()

    -- --- Diminishing returns -------------------------------------------
    if sub == "SPELL_AURA_APPLIED" and auraType == "DEBUFF" then
        local cat = E.Categorize(spellId, spellName)
        if cat then
            local isPlayer = IsPlayerFlag(dstFlags)
            if E.Diminishes(cat, isPlayer) then
                local id = isPlayer and IdentityFor(dstGUID, dstName) or nil
                E.NoteUnit(dstGUID, dstName, id and id.class, isPlayer,
                    IsHostileFlag(dstFlags), now)
                E.Apply(dstGUID, cat, now, spellName, isPlayer)
            end
        end
    elseif FADE_EVENTS[sub] then
        local cat = E.Categorize(spellId, spellName)
        if cat then E.Fade(dstGUID, cat, now) end
    end

    -- --- The file --------------------------------------------------------
    if not db.RecordIntel then return end

    if WITNESS_EVENTS[sub] then
        local rec, id = RecordFor(srcGUID, srcName, srcFlags, epoch)
        if rec and id then E.WitnessSpell(id.key, spellName, epoch) end
    end

    if dstGUID == playerGUID then
        -- Anything a hostile player does TO us makes them our last attacker,
        -- so a death a moment later has a culprit
        if IsPlayerFlag(srcFlags) and IsHostileFlag(srcFlags) and srcGUID ~= playerGUID then
            local _, id = RecordFor(srcGUID, srcName, srcFlags, epoch)
            if id and id.key then E.NoteIncoming(id.key, now) end
        end
        if sub == "UNIT_DIED" then E.NoteMyDeath(now, epoch) end
    end

    if sub == "PARTY_KILL" and srcGUID == playerGUID then
        local _, id = RecordFor(dstGUID, dstName, dstFlags, epoch)
        if id and id.key then E.CreditKill(id.key, epoch) end
    end
end

-- ---------------------------------------------------------------------------
-- The file window
-- ---------------------------------------------------------------------------

local fileWindow
local LIST_ROWS = 14
local listOffset, listSort, listSearch = 0, "LAST", ""
local selectedKey

local function SpecText(rec)
    local spec = E.SpecOf(rec)
    if not spec then
        if not E.HasTalentIndex() then
            return "|cff777777spec unknown (needs Commander_Talents)|r"
        end
        return "|cff777777spec unknown — not enough witnessed|r"
    end
    local pct = spec.confidence * 100
    local certainty = (spec.deepestRow >= 7 and pct >= 60) and "likely" or "leaning"
    return format("|cffffd100%s|r %s (%d%%)", spec.label, certainty, pct + 0.5)
end

local function MatchesSearch(rec)
    if listSearch == "" then return true end
    local needle = listSearch:lower()
    if (rec.name or ""):lower():find(needle, 1, true) then return true end
    if (rec.class or ""):lower():find(needle, 1, true) then return true end
    if (rec.guild or ""):lower():find(needle, 1, true) then return true end
    if (rec.note or ""):lower():find(needle, 1, true) then return true end
    local spec = E.SpecOf(rec)
    if spec and spec.label:lower():find(needle, 1, true) then return true end
    return false
end

local RefreshFile

local function RenderDetail(rec)
    local pane = fileWindow.detail
    if not rec then
        pane.title:SetText("No record selected")
        pane.title:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
        pane.body:SetText("Pick a name on the left.\n\nThe file fills itself: every hostile player the combat log names gets a record the first time you meet them.")
        pane.spells:SetText("")
        pane.note:SetText("")
        pane.note:Hide()
        pane.noteLabel:Hide()
        pane.forget:Hide()
        return
    end
    pane.note:Show()
    pane.noteLabel:Show()
    pane.forget:Show()

    local r, g, b = ClassColor(rec.class)
    pane.title:SetText(rec.name or rec.key or "?")
    pane.title:SetTextColor(r, g, b)

    local now = time()
    local lines = {}
    local ident = {}
    if rec.level then ident[#ident + 1] = "Level " .. rec.level end
    if rec.race then ident[#ident + 1] = rec.race end
    if rec.class then ident[#ident + 1] = rec.class:sub(1, 1) .. rec.class:sub(2):lower() end
    lines[#lines + 1] = table.concat(ident, " ")
    if rec.guild then lines[#lines + 1] = "<" .. rec.guild .. ">" end
    if rec.realm then lines[#lines + 1] = "|cff777777" .. rec.realm .. "|r" end
    lines[#lines + 1] = " "
    lines[#lines + 1] = SpecText(rec)
    local spec = E.SpecOf(rec)
    if spec and spec.deepest then
        lines[#lines + 1] = format("|cff777777strongest tell:|r %s |cff777777(%s, row %d)|r",
            spec.deepest, spec.deepestTree or "?", spec.deepestRow)
    end
    lines[#lines + 1] = " "
    lines[#lines + 1] = format("Met %d time%s", rec.met or 0, (rec.met or 0) == 1 and "" or "s")
    lines[#lines + 1] = format("You killed them |cff66dd66%d|r — they killed you |cffdd5544%d|r",
        rec.kills or 0, rec.deaths or 0)
    lines[#lines + 1] = format("|cff777777First seen|r %s", Ago(rec.first, now))
    lines[#lines + 1] = format("|cff777777Last seen|r %s%s", Ago(rec.last, now),
        rec.zone and (" |cff777777in|r " .. rec.zone) or "")
    pane.body:SetText(table.concat(lines, "\n"))

    -- Witnessed spells, most-used first, capped: the tail is noise
    local names, n = {}, 0
    for name, count in pairs(rec.spells or {}) do
        n = n + 1
        names[n] = { name = name, count = count }
    end
    table.sort(names, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    local out = {}
    for i = 1, (n < 12 and n or 12) do
        out[#out + 1] = format("|cffaaaaaa%d×|r %s", names[i].count, names[i].name)
    end
    if n > 12 then out[#out + 1] = format("|cff777777…and %d more|r", n - 12) end
    pane.spells:SetText(n > 0 and ("|cffffd100Witnessed|r\n" .. table.concat(out, "\n"))
        or "|cff777777Nothing witnessed yet.|r")

    pane.note:SetText(rec.note or "")
end

local function BuildFileWindow()
    local f = CreateFrame("Frame", "CommanderDossierFrame", UIParent,
        "BasicFrameTemplateWithInset")
    f:SetSize(740, 480)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local scale = self:GetEffectiveScale()
        db.FilePos = { x = self:GetLeft() * scale, y = self:GetBottom() * scale }
    end)
    f:SetFrameStrata("HIGH")
    if f.TitleText then f.TitleText:SetText("Commander Dossier — the file") end
    f:Hide()
    tinsert(UISpecialFrames, "CommanderDossierFrame")

    -- Search
    local search = CreateFrame("EditBox", "CommanderDossierSearch", f, "InputBoxTemplate")
    search:SetSize(190, 20)
    search:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -32)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self)
        listSearch = self:GetText() or ""
        listOffset = 0
        RefreshFile()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.search = search

    local searchHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", search, "RIGHT", 8, 0)
    searchHint:SetText("name, class, guild, spec, or your own note")

    -- Sort
    local sort = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    sort:SetSize(110, 20)
    sort:SetPoint("TOPRIGHT", f, "TOPRIGHT", -300, -32)
    local SORTS = { "LAST", "MET", "DEATHS", "KILLS", "NAME" }
    local SORT_LABEL = {
        LAST = "Last seen", MET = "Times met", DEATHS = "Their kills",
        KILLS = "Your kills", NAME = "Name",
    }
    sort:SetText(SORT_LABEL[listSort])
    sort:SetScript("OnClick", function(self)
        local at = 1
        for i, key in ipairs(SORTS) do if key == listSort then at = i end end
        listSort = SORTS[(at % #SORTS) + 1]
        self:SetText(SORT_LABEL[listSort])
        listOffset = 0
        RefreshFile()
    end)
    Commander.UI.AttachTooltip(sort, "Sort",
        "Cycle the list order. 'Their kills' puts whoever has killed you most at the top, which is the list you actually want before an arena.")

    -- List
    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -58)
    list:SetSize(300, 380)
    list:EnableMouseWheel(true)
    f.rowFrames = {}
    for i = 1, LIST_ROWS do
        local row = CreateFrame("Button", nil, list)
        row:SetSize(298, 26)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * 26)
        row.hl = MakeTexture(row, "BACKGROUND", { 1, 1, 1, 0.06 })
        row.hl:SetAllPoints(row)
        row.hl:Hide()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetTexture(CLASS_RING)
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 5)
        row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.sub:SetPoint("LEFT", row.icon, "RIGHT", 6, -6)
        row.score = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.score:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row:SetScript("OnClick", function(self)
            if self.key then
                selectedKey = self.key
                RefreshFile()
            end
        end)
        row:SetScript("OnEnter", function(self) self.hl:Show() end)
        row:SetScript("OnLeave", function(self)
            if self.key ~= selectedKey then self.hl:Hide() end
        end)
        f.rowFrames[i] = row
    end

    -- The Quartermaster scrollbar: a bare Slider with hand-drawn track and
    -- thumb. Deliberately not the settings framework's BACKDROP_SLIDER_8_8
    -- build — that one wears horizontal thumb art, and this is a vertical bar.
    local scroll = CreateFrame("Slider", nil, f)
    scroll:SetOrientation("VERTICAL")
    scroll:SetSize(8, 380)
    scroll:SetPoint("TOPLEFT", list, "TOPRIGHT", 6, 0)
    local track = scroll:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetTexture(WHITE)
    track:SetVertexColor(0, 0, 0, 0.35)
    scroll:SetThumbTexture(WHITE)
    local thumb = scroll:GetThumbTexture()
    if thumb then
        thumb:SetSize(8, 30)
        thumb:SetVertexColor(0.55, 0.55, 0.55, 0.9)
    end
    scroll:SetMinMaxValues(0, 0)
    scroll:SetValueStep(1)
    scroll:SetObeyStepOnDrag(true)
    scroll:SetValue(0)
    scroll:SetScript("OnValueChanged", function(_, value)
        listOffset = math.floor(value + 0.5)
        RefreshFile(true)
    end)
    f.scroll = scroll
    list:SetScript("OnMouseWheel", function(_, delta)
        scroll:SetValue(listOffset - delta)
    end)

    -- Detail pane
    local detail = CreateFrame("Frame", nil, f)
    detail:SetPoint("TOPLEFT", list, "TOPRIGHT", 26, 0)
    detail:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 40)
    detail.title = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    detail.title:SetPoint("TOPLEFT", detail, "TOPLEFT", 0, 0)
    detail.body = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detail.body:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -8)
    detail.body:SetWidth(360)
    detail.body:SetJustifyH("LEFT")
    detail.spells = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail.spells:SetPoint("TOPLEFT", detail.body, "BOTTOMLEFT", 0, -14)
    detail.spells:SetWidth(360)
    detail.spells:SetJustifyH("LEFT")
    f.detail = detail

    detail.noteLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detail.noteLabel:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 0, 46)
    detail.noteLabel:SetText("Your note (a noted record is never pruned)")

    local noteBox = CreateFrame("EditBox", nil, detail, "InputBoxTemplate")
    noteBox:SetSize(360, 22)
    noteBox:SetPoint("TOPLEFT", detail.noteLabel, "BOTTOMLEFT", 6, -4)
    noteBox:SetAutoFocus(false)
    noteBox:SetMaxLetters(120)
    noteBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local function CommitNote(self)
        local rec = selectedKey and E.Record(selectedKey)
        if rec then
            local text = self:GetText()
            rec.note = (text ~= "" and text) or nil
        end
        self:ClearFocus()
        RefreshFile()
    end
    noteBox:SetScript("OnEnterPressed", CommitNote)
    noteBox:SetScript("OnEditFocusLost", CommitNote)
    detail.note = noteBox

    local forget = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    forget:SetSize(90, 22)
    forget:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", 0, 4)
    forget:SetText("Forget")
    forget:SetScript("OnClick", function()
        if not selectedKey then return end
        E.Forget(selectedKey)
        selectedKey = nil
        RefreshFile()
    end)
    Commander.UI.AttachTooltip(forget, "Forget",
        "Delete this one record permanently. Everything else is kept.")
    detail.forget = forget

    local footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 14)
    f.footer = footer

    fileWindow = f

    if db.FilePos then
        local scale = f:GetEffectiveScale()
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
            db.FilePos.x / scale, db.FilePos.y / scale)
    end
end

RefreshFile = function(keepScroll)
    if not fileWindow or not fileWindow:IsShown() then return end
    local list, n = E.Sorted(listSort, function(rec) return MatchesSearch(rec) end)

    local maxOffset = n - LIST_ROWS
    if maxOffset < 0 then maxOffset = 0 end
    if listOffset > maxOffset then listOffset = maxOffset end
    if not keepScroll then
        fileWindow.scroll:SetMinMaxValues(0, maxOffset)
        fileWindow.scroll:SetValue(listOffset)
    end

    local now = time()
    for i = 1, LIST_ROWS do
        local row = fileWindow.rowFrames[i]
        local rec = list[i + listOffset]
        if not rec then
            row:Hide()
            row.key = nil
        else
            row:Show()
            row.key = rec.key
            local r, g, b = ClassColor(rec.class)
            row.name:SetText(rec.name or rec.key)
            row.name:SetTextColor(r, g, b)
            local bits = {}
            if rec.level then bits[#bits + 1] = "L" .. rec.level end
            local spec = E.SpecOf(rec)
            if spec then bits[#bits + 1] = spec.label end
            bits[#bits + 1] = Ago(rec.last, now)
            row.sub:SetText(table.concat(bits, "  "))
            if rec.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[rec.class] then
                local c = CLASS_ICON_TCOORDS[rec.class]
                row.icon:SetTexCoord(c[1], c[2], c[3], c[4])
                row.icon:Show()
            else
                row.icon:Hide()
            end
            row.score:SetText(format("|cff66dd66%d|r/|cffdd5544%d|r", rec.kills or 0, rec.deaths or 0))
            row.hl:SetShown(rec.key == selectedKey)
        end
    end

    RenderDetail(selectedKey and E.Record(selectedKey) or nil)

    local summary = E.Summary()
    local shownNote = (listSearch ~= "" or n ~= summary.total)
        and format("%d shown of %d", n, summary.total) or format("%d players", summary.total)
    fileWindow.footer:SetText(format("%s  ·  you %d — them %d", shownNote,
        summary.kills, summary.deaths))
end

-- ---------------------------------------------------------------------------
-- Test board: a scripted arena opener through the REAL ingest path
-- ---------------------------------------------------------------------------

local TEST_LEN = 16
local TEST_A = "Player-9999-TESTA"
local TEST_B = "Player-9999-TESTB"

-- (at, guid, category, "apply"|"fade")
local TEST_SCRIPT = {
    { 0.5, TEST_A, "stun", "apply" },
    { 4.5, TEST_A, "stun", "fade" },
    { 5.0, TEST_B, "fear", "apply" },
    { 6.0, TEST_A, "stun", "apply" },
    { 8.0, TEST_A, "stun", "fade" },
    { 8.5, TEST_B, "fear", "fade" },
    { 9.0, TEST_A, "kidney_shot", "apply" },
    { 10.0, TEST_B, "fear", "apply" },
    { 10.5, TEST_A, "stun", "apply" },
    { 12.0, TEST_A, "stun", "fade" },
    { 12.5, TEST_B, "fear", "fade" },
    { 13.0, TEST_B, "fear", "apply" },
    { 13.5, TEST_A, "stun", "apply" },
    { 14.0, TEST_B, "fear", "fade" },
}
local testDone = {}

local function RunTest(now)
    local t = now - testStart
    if t > TEST_LEN then
        testStart = 0
        return
    end
    E.NoteUnit(TEST_A, "Vexa", "ROGUE", true, true, now)
    E.NoteUnit(TEST_B, "Miralei", "PRIEST", true, true, now)
    for i, step in ipairs(TEST_SCRIPT) do
        if not testDone[i] and t >= step[1] then
            testDone[i] = true
            if step[4] == "apply" then
                E.Apply(step[2], step[3], now, "Test", true)
            else
                E.Fade(step[2], step[3], now)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Public entry points (slash commands and the settings panel)
-- ---------------------------------------------------------------------------

function CommanderDossier_ToggleFile()
    if not fileWindow then return end
    if fileWindow:IsShown() then
        fileWindow:Hide()
    else
        fileWindow:Show()
        RefreshFile()
    end
end

function CommanderDossier_ToggleBoard()
    db.BoardMode = (db.BoardMode == "HIDDEN") and "ENEMIES" or "HIDDEN"
    print(format("|cff66ccffCommander Dossier|r: board %s",
        db.BoardMode == "HIDDEN" and "hidden" or "shown"))
    Commander.Notify(COMMANDER_DOSSIER_EVENTS.UPDATE)
end

function CommanderDossier_Test()
    testStart = GetTime()
    for i in pairs(testDone) do testDone[i] = nil end
    E.NoteUnit(TEST_A, "Vexa", "ROGUE", true, true, testStart)
    E.NoteUnit(TEST_B, "Miralei", "PRIEST", true, true, testStart)
    print("|cff66ccffCommander Dossier|r: test board running for 16 seconds — a stun chain to immunity and a fear chain behind it.")
end

function CommanderDossier_Report()
    local s = E.Summary()
    print("|cff66ccffCommander Dossier|r — the file")
    print(format("  %d players on record; you have killed them %d times and died to them %d times.",
        s.total, s.kills, s.deaths))
    if s.nemesis and s.nemesisDeaths > 0 then
        local spec = E.SpecOf(s.nemesis)
        print(format("  Nemesis: %s%s — %d of your deaths against %d of theirs.",
            s.nemesis.name or s.nemesis.key,
            spec and (" (" .. spec.label .. ")") or "",
            s.nemesis.deaths or 0, s.nemesis.kills or 0))
    end
    if not E.HasTalentIndex() then
        print("  |cff777777Commander_Talents is not loaded, so no specialisations are being inferred.|r")
    end
end

-- Add our key to Blizzard's table; never ASSIGN the global. `StaticPopupDialogs =
-- StaticPopupDialogs or {}` looks like a harmless guard, but assigning a global
-- from addon code taints that global variable for the rest of the session, and
-- every piece of Blizzard code that later reads it inherits the taint.
--
-- What that cost: every Escape-menu button runs the same three-line closure --
-- PlaySound, HideUIPanel(GameMenuFrame), callback() (Blizzard_GameMenu/Shared/
-- GameMenuFrame.lua). HideUIPanel drags in the panel-position pass, which reads
-- widely across FrameXML globals; once it touched our tainted one the execution
-- was tainted, and Log Out / Exit Game -- protected functions reached through
-- that local `callback` -- died with ADDON_ACTION_FORBIDDEN blamed on
-- Commander_Dossier. The player could not leave the game without a reload.
--
-- Writing one new KEY into the table taints only that key, which nothing but
-- our own popup ever reads -- which is why Commander_Talents, which registers
-- four dialogs the same way, has never been named in one of these reports.
-- FrameXML always defines the table; the guard is for the offline harness.
if StaticPopupDialogs then
    StaticPopupDialogs["COMMANDER_DOSSIER_WIPE"] = {
        text = "Delete every Commander Dossier intelligence record?\n\nThis cannot be undone. Your settings are not affected.",
        button1 = "Wipe",
        button2 = "Cancel",
        OnAccept = function()
            E.Wipe()
            selectedKey = nil
            RefreshFile()
            print("|cff66ccffCommander Dossier|r: the file has been wiped.")
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

function CommanderDossier_Wipe()
    StaticPopup_Show("COMMANDER_DOSSIER_WIPE")
end

-- Cross-module read (soft contract): what specialisation, if any, we believe
-- a player runs. Other suite modules may call this; it must never error.
function CommanderDossier_SpecFor(name, realm)
    local key = KeyFor(name, realm)
    local rec = key and E.Record(key)
    local spec = rec and E.SpecOf(rec)
    if not spec then return nil end
    return spec.label, spec.confidence
end

-- ---------------------------------------------------------------------------
-- Apply / tick / events
-- ---------------------------------------------------------------------------

local function Apply()
    if not root then return end
    Layout()
    Commander.UI.ApplyHudChrome(root, db, "Hud", {
        defaultPoint = { point = "RIGHT", x = -40, y = 120 },
        title = "Commander Dossier",
    })
    local now = GetTime()
    UpdateVisibility(now)
    Paint(now)
end

local sweepAt = 0

local function Tick()
    if not db.EnableDossier then
        if root and root:IsShown() then root:Hide() end
        return
    end
    local now = GetTime()
    if testStart > 0 then RunTest(now) end
    if now - sweepAt > 5 then
        sweepAt = now
        E.Sweep(now)
    end
    UpdateVisibility(now)
    Paint(now)
    DrainAlerts()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")

local function OnEvent(_, event)
    if event == "PLAYER_LOGIN" then
        db = CommanderDossierDB
        file = CommanderDossierFile
        ownRealm = GetRealmName and GetRealmName() or ""
        playerGUID = UnitGUID and UnitGUID("player") or nil
        currentZone = GetRealZoneText and GetRealZoneText() or nil

        ResolveThemeOverrides()
        E.Init(db, file, D)
        E.SetTalentIndex(BuildTalentIndex())
        E.SetNameIndex(BuildNameIndex())
        E.Prune(time(), db.KeepDays or 0, 2000)

        BuildBoard()
        BuildFlash()
        BuildFileWindow()

        events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        events:RegisterEvent("PLAYER_TARGET_CHANGED")
        events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
        events:RegisterEvent("PLAYER_FOCUS_CHANGED")
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        C_Timer.NewTicker(0.25, Tick)
        Commander.AddListener(COMMANDER_DOSSIER_EVENTS.UPDATE, Apply)
        Apply()
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if db.EnableDossier then HandleCombatLog() end
        return
    end

    -- Every unit we can legitimately inspect teaches us a class, a race and a
    -- guild the combat log never carries
    if event == "PLAYER_TARGET_CHANGED" then
        LearnFromUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        LearnFromUnit("mouseover")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        LearnFromUnit("focus")
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        currentZone = GetRealZoneText and GetRealZoneText() or currentZone
        for _, unit in ipairs(SWEEP_UNITS) do LearnFromUnit(unit) end
        Tick()
    else
        for _, unit in ipairs(SWEEP_UNITS) do LearnFromUnit(unit) end
        Tick()
    end
end

events:SetScript("OnEvent", OnEvent)
