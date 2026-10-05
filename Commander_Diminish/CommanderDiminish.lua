-- Commander Diminish: a diminishing-returns tracker for battlegrounds and
-- arena, tailored to whatever this character happens to be.
--
-- Commander Arena Frames already tracks DR -- on an arena board, per seat,
-- against arena1..arena5. Those unit tokens do not exist in a battleground,
-- which is where most people spend most of their PvP, so that board answers
-- nothing there. This module is the same rules with the seats taken out: state
-- keyed by GUID alone, drawn against whichever people you can actually name --
-- your target, your focus, yourself, the arena tokens when there are any, and
-- whoever you have most recently landed control on.
--
-- Three things make it worth having rather than being a second copy of the
-- same board:
--
--   TAILORED    TBC has sixteen DR categories and no character can open more
--               than a handful. The handful is read out of YOUR SPELLBOOK --
--               player book and pet book -- at login and again whenever your
--               spells change, so an arcane mage has no Dragon's Breath row,
--               a fire mage does, and nobody maintains a table of classes for
--               this to go stale.
--   BOTH WAYS   the same strip, pointed the other way, is what is being done
--               to YOU. Your own row (and a friendly target's) drops the
--               filter entirely, because "what can I cast" is the wrong
--               question about incoming CC.
--   IT FORGETS  an arena has five people and then ends. A battleground hands
--               you forty through one combat log, so the state has to prune
--               itself or it grows all game.
--
-- The rules live in CommanderDiminishEngine.lua, which touches no WoW API and
-- is tested under plain luajit. This file is the plumbing: what the client
-- says, when, and how it gets drawn.

local DATA = CommanderDiminish_Data
local E = CommanderDiminish_Engine

-- One accessor, so a nil DB (the moment before ADDON_LOADED) can never take
-- the strip down.
local function DB(key, default)
    local db = CommanderDiminishDB
    if not db then return default end
    local value = db[key]
    if value == nil then return default end
    return value
end

local function Enabled()
    return CommanderDiminishDB and CommanderDiminishDB.Enable
end

local WHITE = "Interface\\Buttons\\WHITE8X8"
local ARENA_UNITS = { "arena1", "arena2", "arena3", "arena4", "arena5" }
local PARTY_UNITS = { "party1", "party2", "party3", "party4" }
local DRAW_THROTTLE = 0.1     -- 10Hz. Nothing here is a cast bar; a reset
                              -- clock reading a tenth of a second late has
                              -- never cost anybody a kill.
local PRUNE_EVERY = 5

-- How a bracket reads in the log. Index by bracket, so DESCRIBE[2] is what the
-- NEXT cast in the category would land at.
local DESCRIBE = { "full", "half", "quarter", "immune" }

-- ---------------------------------------------------------------------------
-- Live state
-- ---------------------------------------------------------------------------
local dr = E.NewDR()
local profile = {}            -- category key -> true: what THIS character opens
local profileWhy = {}         -- category key -> the spell id that proved it
local identity = {}           -- guid -> { name, class }
local playerGUID
local testUntil = 0
local lastPrune = 0
local layoutDirty = true

-- ---------------------------------------------------------------------------
-- What this character can open.
--
-- The spellbook is the honest source, and the only one that survives a respec
-- without being told about it. Two books are walked, because the second one is
-- where half the interesting answers live: Seduction is the succubus's, not
-- the warlock's, and Intimidation is the pet's rather than the hunter's.
--
-- Ids are enough. The generated table covers every rank of every spell, so a
-- rank-two Fear resolves exactly like a rank-three one, and the untrained
-- ranks below the one you have simply never come up.
-- ---------------------------------------------------------------------------
local scratchIds = {}

local function CollectBook(bookType, count, offset, into)
    if not GetSpellBookItemInfo then return end
    for i = (offset or 0) + 1, (offset or 0) + (count or 0) do
        local ok, _, spellId = pcall(GetSpellBookItemInfo, i, bookType)
        if ok and spellId then into[#into + 1] = spellId end
    end
end

local function RefreshProfile()
    for i = #scratchIds, 1, -1 do scratchIds[i] = nil end

    if GetNumSpellTabs and GetSpellTabInfo then
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, numSlots = GetSpellTabInfo(tab)
            CollectBook("spell", numSlots, offset, scratchIds)
        end
    end

    -- The pet book. A warlock's answer changes with the demon that is out, so
    -- this is re-read on UNIT_PET as well as on SPELLS_CHANGED.
    if HasPetSpells then
        local ok, numPetSpells = pcall(HasPetSpells)
        if ok and numPetSpells then
            CollectBook("pet", numPetSpells, 0, scratchIds)
        end
    end

    local extra
    if DB("Scope", "MINE") == "CUSTOM" and CommanderDiminish_CustomCategory then
        extra = {}
        for _, group in ipairs(DATA.DR_GROUPS or {}) do
            if CommanderDiminish_CustomCategory(group.key) then extra[group.key] = true end
        end
    end

    if DB("Scope", "MINE") == "ALL" then
        for k in pairs(profile) do profile[k] = nil end
        for _, group in ipairs(DATA.DR_GROUPS or {}) do profile[group.key] = true end
    else
        local derived = E.Profile(scratchIds, extra)
        for k in pairs(profile) do profile[k] = nil end
        for k in pairs(derived) do profile[k] = true end
    end

    -- Which spell proved each category, for the report. Kept separate from the
    -- profile itself so the engine stays a pure set operation.
    for k in pairs(profileWhy) do profileWhy[k] = nil end
    for _, id in ipairs(scratchIds) do
        local cat = E.Category(id)
        if cat and not profileWhy[cat] then profileWhy[cat] = id end
    end

    layoutDirty = true
end

-- ---------------------------------------------------------------------------
-- Combat log.
--
-- Everything this module knows arrives here. Three subevents matter and
-- exactly one of them is the one people forget:
--
--   SPELL_AURA_APPLIED / _REFRESH  a CC landed (or was reapplied)
--   SPELL_AURA_REMOVED             it ran out, was dispelled, or was trinketed
--   SPELL_AURA_BROKEN / _SPELL     it was BROKEN BY DAMAGE -- and this fires
--                                  INSTEAD of _REMOVED, not as well as it
--
-- A tracker listening only for _REMOVED never learns that the polymorph it
-- watched land has ended, so the category's stack never returns to zero, the
-- fifteen-second clock never starts, and the bracket sits at half for the rest
-- of the game. In a battleground, where every CC you cast is being broken by
-- somebody's cleave, that is most of them.
--
-- Players only. A battleground combat log is mostly not players -- flags,
-- vehicles, the odd critter -- and diminishing returns are a PvP rule.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- The log.
--
-- A DR bracket that is wrong is wrong quietly: you spend a sheep finding out,
-- and by then the evidence is gone. So the last few dozen DR events are kept
-- in a ring, printable with `/cdr log` -- what arrived, when, what the ladder
-- did with it, and above all where the ladder DISAGREED with the duration the
-- server actually handed the CC. One game is then enough to settle an
-- argument about the rules instead of a season of impressions.
-- ---------------------------------------------------------------------------
local LOG_MAX = 60
local logLines, logNext, logging = {}, 1, false

local function Log(fmt, ...)
    if not logging then return end
    logLines[logNext] = string.format("%7.1f  " .. fmt, GetTime() % 10000, ...)
    logNext = logNext % LOG_MAX + 1
end

local function IsPlayerGUID(guid)
    return guid and strsub(guid, 1, 6) == "Player"
end

local function RememberName(guid, name)
    if not guid or not name then return end
    local known = identity[guid]
    if known and known.name then return end
    local class
    if GetPlayerInfoByGUID then
        local ok, token = pcall(function() return select(2, GetPlayerInfoByGUID(guid)) end)
        if ok then class = token end
    end
    identity[guid] = { name = name, class = class }
end

local function OnCombatLog()
    local _, subevent, _, _, _, _, _, destGUID, destName, _, _,
          spellId = CombatLogGetCurrentEventInfo()
    if not IsPlayerGUID(destGUID) then return end
    -- One clock reading per event. The engine takes `now` as an argument
    -- rather than calling GetTime itself, which is what lets the whole ladder
    -- be tested at arbitrary timestamps under luajit.
    local now = GetTime()

    if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
        local refresh = subevent == "SPELL_AURA_REFRESH"
        local cat = dr:Applied(destGUID, spellId, now, refresh)
        if cat then
            RememberName(destGUID, destName)
            Log("%-8s %-10s %s -> next is %s", refresh and "REFRESH" or "APPLIED",
                cat, destName or "?", DESCRIBE[dr:Bracket(destGUID, cat, now)])
        end
    elseif subevent == "SPELL_AURA_REMOVED"
        or subevent == "SPELL_AURA_BROKEN"
        or subevent == "SPELL_AURA_BROKEN_SPELL" then
        -- All three are the same fact for a DR clock: the aura is gone. The
        -- two BROKEN forms carry the broken aura's own id in the same
        -- position, which is the only reason one handler covers them.
        local cat = dr:Faded(destGUID, spellId, now)
        if cat then
            local held = dr:Held(destGUID, cat)
            Log("%-8s %-10s %s -- %s", subevent == "SPELL_AURA_REMOVED" and "FADED" or "BROKEN",
                cat, destName or "?",
                held and "still held, clock frozen"
                    or ("full again in " .. DATA.DR_RESET .. "s"))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Checking the ladder against the server.
--
-- The combat log says a CC landed; the aura on the unit says how long the
-- server actually gave it, which is the cap and the ladder already applied. On
-- any unit we can address that turns the bracket from an inference into a
-- reading -- and where the two disagree, the reading wins and the
-- disagreement is logged, because that is the thing worth knowing.
--
-- Only units the client will talk about, and only auras it will show us. This
-- can correct the ladder and can never invent one: an aura the client does not
-- report simply teaches nothing.
-- ---------------------------------------------------------------------------
local function ObserveUnit(unit)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    local now = GetTime()
    for index = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, "HARMFUL")
        if not aura then break end
        if aura.spellId and aura.duration and aura.duration > 0 then
            local level, predicted, corrected, cat =
                dr:Observe(guid, aura.spellId, aura.duration, now,
                           aura.expirationTime)
            if level and corrected then
                -- `level` and `predicted` are both RUNGS this cast came in
                -- on -- 1 is full -- not brackets for the next one, so they
                -- index DESCRIBE directly. Observe runs after Applied has
                -- already counted this cast, which is why `predicted` is the
                -- model's rung for it rather than one below.
                Log("CORRECT  %-10s %s landed at %s (%.1fs of %.1fs) -- ladder said %s",
                    cat, UnitName(unit) or "?", DESCRIBE[level] or "?",
                    aura.duration, E.LearnedDuration(aura.spellId) or 0,
                    DESCRIBE[predicted] or "full")
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- The frames.
--
-- One root, a pool of strips, a pool of cells inside each. Nothing is ever
-- destroyed -- a battleground would otherwise churn frames every time you
-- changed target -- so the pools only ever grow to the high-water mark of one
-- session and are hidden back down from there.
-- ---------------------------------------------------------------------------

local root = CreateFrame("Frame", "CommanderDiminishFrame", UIParent)
root:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
root:SetSize(200, 40)
root:SetFrameStrata("MEDIUM")
root:Hide()

local strips = {}

local function NewCell(parent)
    local cell = CreateFrame("Frame", nil, parent)

    -- The rim carries the bracket. It is a texture behind an inset icon rather
    -- than a border object because a one-pixel inset reads as a rim at every
    -- icon size the slider allows, and a real border does not.
    cell.rim = cell:CreateTexture(nil, "BACKGROUND")
    cell.rim:SetAllPoints()
    cell.rim:SetTexture(WHITE)

    -- Held: something in this category is on them RIGHT NOW. Drawn as a halo
    -- outside the rim, because this is the state where every number on the
    -- cell is blank -- the clock has not started -- and the cell would
    -- otherwise look identical to a category at rest.
    cell.glow = cell:CreateTexture(nil, "BACKGROUND", nil, -1)
    cell.glow:SetPoint("TOPLEFT", cell, "TOPLEFT", -2, 2)
    cell.glow:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 2, -2)
    cell.glow:SetTexture(WHITE)
    cell.glow:Hide()

    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 1, -1)
    cell.icon:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -1, 1)
    -- Trim the client's own icon border off, so the rim is the only edge.
    cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    cell.cd = CreateFrame("Cooldown", nil, cell, "CooldownFrameTemplate")
    cell.cd:SetAllPoints(cell.icon)
    cell.cd:SetHideCountdownNumbers(true)
    if cell.cd.SetDrawEdge then cell.cd:SetDrawEdge(false) end
    cell.cd:SetFrameLevel(cell:GetFrameLevel() + 1)

    cell.timer = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.timer:SetPoint("CENTER", cell, "CENTER", 0, 0)

    cell.badge = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.badge:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -1, 1)

    -- Both are written on a spell icon, which is as often pale as dark: a
    -- hard black shadow under the outline is what holds their edges on a
    -- white Polymorph
    for _, fs in ipairs({ cell.timer, cell.badge }) do
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    end

    return cell
end

local function AcquireStrip(index)
    local strip = strips[index]
    if strip then return strip end
    strip = CreateFrame("Frame", "CommanderDiminishStrip" .. index, root)
    strip.cells = {}
    strip.label = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    strip.label:SetPoint("BOTTOMLEFT", strip, "TOPLEFT", 1, 1)
    strip.label:SetJustifyH("LEFT")
    strips[index] = strip
    return strip
end

local function AcquireCell(strip, index)
    local cell = strip.cells[index]
    if cell then return cell end
    cell = NewCell(strip)
    strip.cells[index] = cell
    return cell
end

-- ---------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------

local function IconFor(row)
    local id = DATA.CAT_ICON[row.cat]
    if DB("IconSource", "CATEGORY") == "SPELL" or not id then id = row.last or id end
    if id and GetSpellTexture then
        local ok, texture = pcall(GetSpellTexture, id)
        if ok and texture then return texture end
    end
    if id and GetSpellInfo then
        local ok, _, _, texture = pcall(GetSpellInfo, id)
        if ok and texture then return texture end
    end
    return DATA.FALLBACK_ICON
end

-- One cell. `row` is a strip row from the engine: category, bracket, whether
-- anything is up, and when it resets.
local function PaintCell(cell, row, now)
    local texture = IconFor(row)
    if cell._tex ~= texture then
        cell._tex = texture
        cell.icon:SetTexture(texture)
    end

    local bracketTint = DATA.BRACKET_TINT[row.bracket] or DATA.BRACKET_TINT[1]

    if not row.open then
        -- Nothing has happened in this category. The cell is here to say you
        -- HAVE it, so it is drawn at rest: grey, dim, and silent.
        cell.icon:SetDesaturated(DB("DesaturateFull", true) and true or false)
        cell.icon:SetAlpha(0.45)
        cell.rim:SetVertexColor(0.25, 0.25, 0.27, 0.9)
        cell.glow:Hide()
        cell.cd:Hide()
        cell._cdStart = nil
        cell.timer:SetText("")
        cell.badge:SetText("")
        return
    end

    cell.icon:SetDesaturated(false)
    cell.icon:SetAlpha(1)
    cell.rim:SetVertexColor(bracketTint[1], bracketTint[2], bracketTint[3], 1)

    if DB("ShowBracket", true) then
        cell.badge:SetText(DATA.BRACKET_LABEL[row.bracket] or "")
        cell.badge:SetTextColor(bracketTint[1], bracketTint[2], bracketTint[3])
    else
        cell.badge:SetText("")
    end

    if row.held then
        -- The frozen clock. Nothing is counting down, because the fifteen
        -- seconds do not start until the aura fades -- so the cell says so
        -- with the halo rather than with a number that would be a lie.
        cell.glow:SetVertexColor(1, 1, 1, 0.55)
        cell.glow:SetShown(DB("HeldGlow", true) and true or false)
        cell.cd:Hide()
        cell._cdStart = nil
        cell.timer:SetText("")
        return
    end

    cell.glow:Hide()

    local remaining = row.resetAt and (row.resetAt - now) or nil
    if remaining and remaining > 0 then
        if DB("ShowSwipe", true) then
            cell.cd:Show()
            -- Only when it actually changes. SetCooldown restarts the sweep
            -- animation, so calling it every draw is a sweep that never moves:
            -- ten times a second it is told to begin again.
            if cell._cdStart ~= row.resetAt then
                cell._cdStart = row.resetAt
                cell.cd:SetCooldown(row.resetAt - DATA.DR_RESET, DATA.DR_RESET)
            end
        else
            cell.cd:Hide()
        end
        if DB("ShowTimer", true) then
            cell.timer:SetText(E.FormatTime(remaining))
            cell.timer:SetTextColor(bracketTint[1], bracketTint[2], bracketTint[3])
        else
            cell.timer:SetText("")
        end
    else
        cell.cd:Hide()
        cell._cdStart = nil
        cell.timer:SetText("")
    end
end

-- ---------------------------------------------------------------------------
-- Who gets a strip.
--
-- Priority order, deduplicated by GUID: your own row first, then the two units
-- you have chosen, then the arena seats, then whoever you have CC'd lately.
-- The order is fixed rather than sorted so a strip stays where you last looked
-- for it -- an arena opponent who happens to be your target appears once, in
-- the target's place, rather than jumping between two rows as you swap.
--
-- The `lens` is the part worth reading twice. OUT means "the ladders I can
-- open on this person", which is the tailored, greyed-in-full strip. IN means
-- "everything that has been opened on this person", filtered by nothing,
-- because what is being done to you or to your healer has nothing to do with
-- what you can cast. A friendly target gets IN for exactly that reason.
-- ---------------------------------------------------------------------------
local slots = {}
local stripRows = {}

local function AddSlot(guid, label, class, lens, unit)
    if not guid then return end
    for _, existing in ipairs(slots) do
        if existing.guid == guid then return end
    end
    -- `unit` is the token the slot was found through, when there was one: it
    -- is how an embedded strip finds a unit frame to sit on
    slots[#slots + 1] = { guid = guid, label = label, class = class, lens = lens, unit = unit }
end

local function UnitSlot(unit, fallbackLabel)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    local name = UnitName(unit)
    local _, class = UnitClass(unit)
    -- A unit token is a better source than the combat log ever was, so it is
    -- allowed to fill in a class we could not resolve from a GUID alone --
    -- otherwise a name first seen in the log stays uncoloured for the rest of
    -- the game even while you are standing on them.
    if name then
        local known = identity[guid]
        if known then
            known.name = name or known.name
            known.class = class or known.class
        else
            identity[guid] = { name = name, class = class }
        end
    end
    -- Hostile: the question is what I can land. Friendly: the question is what
    -- is landing on them.
    local hostile = UnitCanAttack("player", unit)
    AddSlot(guid, name or fallbackLabel, class, hostile and "OUT" or "IN", unit)
end

local function BuildSlots(now)
    for i = #slots, 1, -1 do slots[i] = nil end

    if GetTime() < testUntil then
        for i = 1, 3 do
            local fake = identity["Player-TEST-" .. i]
            AddSlot("Player-TEST-" .. i, fake and fake.name or ("Test " .. i),
                    fake and fake.class or nil, "OUT")
        end
        if DB("ShowSelf", true) then
            AddSlot(playerGUID, "YOU", select(2, UnitClass("player")), "IN", "player")
        end
        return
    end

    if DB("ShowSelf", true) then
        AddSlot(playerGUID, "YOU", select(2, UnitClass("player")), "IN", "player")
    end
    if DB("ShowTarget", true) then UnitSlot("target", "Target") end
    if DB("ShowFocus", true) then UnitSlot("focus", "Focus") end
    -- Your party: what is being run on the people you are standing next to.
    -- Your healer's fear ladder is the one a team plays around, and it is the
    -- one nothing else on screen shows.
    if DB("ShowParty", true) then
        for _, unit in ipairs(PARTY_UNITS) do UnitSlot(unit, unit) end
    end
    if DB("ShowArena", true) then
        for _, unit in ipairs(ARENA_UNITS) do UnitSlot(unit, unit) end
    end
    if DB("ShowRecent", false) then
        local recent = dr:Recent(now, DB("RecentMax", 3))
        for _, guid in ipairs(recent) do
            local known = identity[guid]
            AddSlot(guid, known and known.name or "?", known and known.class or nil, "OUT")
        end
    end
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

-- Whether this zone is one we draw in, CACHED.
--
-- The naive version calls IsInInstance() from the combat-log handler, which in
-- a full battleground is a few hundred calls a second to answer a question
-- whose answer changed once, on the loading screen. So it is recomputed on the
-- two events that can change it, and on any settings change.
local zoneOK = false

local function RefreshZone()
    local _, instanceType = IsInInstance()
    if instanceType == "arena" then
        zoneOK = DB("ShowInArena", true) and true or false
    elseif instanceType == "pvp" then
        zoneOK = DB("ShowInBattleground", true) and true or false
    else
        zoneOK = DB("ShowInWorld", false) and true or false
    end
    return zoneOK
end

-- Cut to a length, without cutting a character in half.
--
-- strsub counts BYTES and a realm full of names like Sylvanas' own is full of
-- multi-byte ones, so a naive cut lands mid-character and the client draws the
-- remains as a replacement glyph. Backing off over the continuation bytes
-- (0x80-0xBF) costs a loop of at most three and removes the whole class of
-- problem.
local function Truncate(name)
    if not name then return "" end
    local maxChars = DB("NameMaxChars", 10)
    if strlen(name) <= maxChars then return name end
    local cut = maxChars
    while cut > 0 do
        local byte = strbyte(name, cut + 1)
        if not byte or byte < 128 or byte >= 192 then break end
        cut = cut - 1
    end
    return strsub(name, 1, cut)
end

local function ClassColor(class)
    local colors = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
    if colors then return colors.r, colors.g, colors.b end
    return 0.9, 0.9, 0.9
end

-- ---------------------------------------------------------------------------
-- Where a strip lives.
--
-- This module was born as a window: a board of its own, floating wherever it
-- was dragged, with a name over each strip so you could tell whose it was.
-- That is the right answer to "who have I got ladders on" and the wrong one
-- to "what can I land on HIM" -- the question is about a person, and the
-- person already has a frame. A ladder drawn beside the frame it is about
-- needs no name over it and no second place to look.
--
-- So, by default, a strip is EMBEDDED: it sits on the frame of the person it
-- describes, parented to it, so it shows, hides, moves and scales with it.
--
--   an ally (you included)   on their Commander Party Frames row, past the
--                            end of that board's own dispel strip
--   an arena enemy           nowhere -- Commander Arena Frames draws that
--                            enemy's ladders on their row already, and a
--                            second copy beside it is the loose object this
--                            exists to get rid of
--   anyone else you can name on their unit frame (target, focus, yourself,
--                            Blizzard's party frames), which is the
--                            battleground case: there is no arena row for a
--                            warlock in Alterac Valley
--
-- A slot with no frame to sit on is not drawn. The window is still there for
-- whoever wants a board (Placement: Its Own Window), and it is where the test
-- strips land when there is no frame up to put them on.
-- ---------------------------------------------------------------------------
-- `inset` is where the frame's name bar starts from its left edge: the art
-- is a portrait and a bar, and a strip lines up with the bar, not with the
-- box the art is drawn in. A party member's frame is too small to have
-- sides worth choosing between, so it is `fixed`.
local UNIT_HOSTS = {
    player = { frame = "PlayerFrame", inset = 106 },
    target = { frame = "TargetFrame", inset = 7 },
    focus  = { frame = "FocusFrame", inset = 7 },
}
for index, unit in ipairs(PARTY_UNITS) do
    UNIT_HOSTS[unit] = { frame = "PartyMemberFrame" .. index,
        fixed = { point = "LEFT", rel = "RIGHT", x = 2, y = 4 } }
end

-- Which side of a unit frame the strip sits on. ABOVE is the clear band
-- Blizzard's frames keep over the name bar; BELOW hangs it from the frame's
-- bottom edge, under the bars; LEFT and RIGHT stand it beside the frame at
-- the bars' height. The nudge sliders move it from wherever this puts it.
local UNIT_SIDES = {
    ABOVE = function(inset) return "BOTTOMLEFT", "TOPLEFT", inset, -22 end,
    BELOW = function(inset) return "TOPLEFT", "BOTTOMLEFT", inset, 0 end,
    LEFT  = function() return "RIGHT", "LEFT", -2, 6 end,
    RIGHT = function() return "LEFT", "RIGHT", 2, 6 end,
}

local function HostFor(slot)
    if CommanderArenaFrames_ShowsDR and CommanderArenaFrames_ShowsDR(slot.guid) then
        return nil
    end
    if CommanderPartyFrames_RowFor then
        local row, reach = CommanderPartyFrames_RowFor(slot.guid)
        if row then return row, "LEFT", "RIGHT", reach or 4, 0 end
    end
    local spec = slot.unit and UNIT_HOSTS[slot.unit]
    local frame = spec and _G[spec.frame]
    if frame and frame.IsVisible and frame:IsVisible() then
        local point, rel, x, y
        if spec.fixed then
            point, rel, x, y = spec.fixed.point, spec.fixed.rel, spec.fixed.x, spec.fixed.y
        else
            local side = UNIT_SIDES[DB("EmbedSide", "ABOVE")] or UNIT_SIDES.ABOVE
            point, rel, x, y = side(spec.inset)
        end
        return frame, point, rel, x + DB("EmbedOffsetX", 0), y + DB("EmbedOffsetY", 0)
    end
    return nil
end

-- Everything off. Embedded strips are parented to other people's frames, so
-- hiding this module's own root no longer hides them.
local function HideAll()
    for index = 1, #strips do strips[index]:Hide() end
    root:Hide()
end

local function Draw()
    if not Enabled() then
        HideAll()
        return
    end

    local testing = GetTime() < testUntil
    if not testing then
        if not zoneOK then HideAll() return end
        if DB("CombatOnly", false) and not (InCombatLockdown and InCombatLockdown()) then
            HideAll()
            return
        end
    end

    local now = GetTime()
    BuildSlots(now)

    local embedded = DB("Placement", "EMBEDDED") == "EMBEDDED"
    local size = embedded and DB("EmbedIconSize", 20) or DB("IconSize", 30)
    local iconGap = DB("IconSpacing", 3)
    local labelHeight = DB("ShowName", true) and (DB("NameSize", 11) + 3) or 0
    local step = size + labelHeight + DB("RowSpacing", 6)
    local growUp = DB("Grow", "DOWN") == "UP"
    local showFull = DB("ShowFull", true)

    local drawn, windowed, widest = 0, 0, 0
    for _, slot in ipairs(slots) do
        -- The lens. OUT is filtered to what this character can open and drawn
        -- in full; IN is unfiltered and drawn only where something is actually
        -- open, because "every ladder that could be run on me" is sixteen
        -- icons of nothing.
        local cats = (slot.lens == "OUT") and profile or nil
        local includeFull = (slot.lens == "OUT") and showFull or false
        local rows = dr:Strip(slot.guid, now, cats, includeFull, stripRows)

        local host, point, rel, x, y
        if embedded then host, point, rel, x, y = HostFor(slot) end
        -- The window takes a strip when the window is what was asked for --
        -- and, on the test board only, when there is no frame up to put it on
        local inWindow = not embedded or (testing and not host)

        if #rows > 0 and (host or inWindow) then
            drawn = drawn + 1
            local strip = AcquireStrip(drawn)
            local width = #rows * size + (#rows - 1) * iconGap
            local parent = inWindow and root or host
            if strip._parent ~= parent then
                strip._parent = parent
                strip:SetParent(parent)
                strip:SetFrameLevel((parent:GetFrameLevel() or 1) + 5)
                strip._w = nil      -- a new parent is a new anchor
            end
            if inWindow then
                windowed = windowed + 1
                -- Geometry is re-applied only when it actually changed. The
                -- draw loop runs ten times a second and the shape of a strip
                -- changes when a setting does, which is to say almost never.
                -- Every value the anchor below is computed from has to be in
                -- this test. Packing them into one number is how a cache
                -- quietly stops noticing that the row spacing changed.
                if strip._w ~= width or strip._h ~= size or strip._step ~= step
                    or strip._label ~= labelHeight or strip._up ~= growUp
                    or strip._index ~= windowed or strip._embed then
                    strip._w, strip._h, strip._step = width, size, step
                    strip._label, strip._up, strip._index = labelHeight, growUp, windowed
                    strip._embed = nil
                    strip:SetSize(width, size)
                    strip:ClearAllPoints()
                    if growUp then
                        strip:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, (windowed - 1) * step)
                    else
                        strip:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -((windowed - 1) * step + labelHeight))
                    end
                end
                if width > widest then widest = width end
            else
                if strip._w ~= width or strip._h ~= size or strip._embed ~= point
                    or strip._rel ~= rel or strip._x ~= x or strip._y ~= y then
                    strip._w, strip._h, strip._embed, strip._x, strip._y = width, size, point, x, y
                    strip._rel = rel
                    strip:SetSize(width, size)
                    strip:ClearAllPoints()
                    strip:SetPoint(point, host, rel, x, y)
                end
            end
            strip:Show()

            -- The frame a strip sits on already says whose it is
            if inWindow and DB("ShowName", true) then
                strip.label:SetText(Truncate(slot.label))
                strip.label:SetTextColor(ClassColor(slot.class))
                local nameSize = DB("NameSize", 11)
                if strip._fontSize ~= nameSize then
                    strip._fontSize = nameSize
                    local font, _, flags = strip.label:GetFont()
                    if font then strip.label:SetFont(font, nameSize, flags) end
                end
                strip.label:Show()
            else
                strip.label:Hide()
            end

            for index, row in ipairs(rows) do
                local cell = AcquireCell(strip, index)
                if cell._size ~= size or cell._gap ~= iconGap then
                    cell._size, cell._gap = size, iconGap
                    cell:SetSize(size, size)
                    cell:ClearAllPoints()
                    cell:SetPoint("LEFT", strip, "LEFT", (index - 1) * (size + iconGap), 0)
                end
                -- OUTLINE unconditionally: this text sits on top of a spell
                -- icon, and the inherited flags from GameFontHighlightSmall
                -- are empty, which is unreadable over half the art in the
                -- game. Re-set only when the size actually changes. A strip
                -- on somebody's frame is smaller than a board's, so there its
                -- clock is never written bigger than half its own icon.
                local timerSize = DB("TimerSize", 12)
                if not inWindow then
                    timerSize = math.min(timerSize, math.max(8, math.floor(size * 0.55)))
                end
                if cell._fontSize ~= timerSize then
                    cell._fontSize = timerSize
                    local font = cell.timer:GetFont()
                    if font then
                        cell.timer:SetFont(font, timerSize, "OUTLINE")
                        cell.badge:SetFont(font, math.max(8, timerSize - 2), "OUTLINE")
                    end
                end
                PaintCell(cell, row, now)
                cell:Show()
            end
            for index = #rows + 1, #strip.cells do
                strip.cells[index]:Hide()
            end
        end
    end

    for index = drawn + 1, #strips do
        strips[index]:Hide()
    end

    if windowed == 0 then
        root:Hide()
        return
    end
    root:SetSize(math.max(widest, 1), math.max(windowed * step - DB("RowSpacing", 6), 1))
    root:Show()
end

-- ---------------------------------------------------------------------------
-- The test board.
--
-- Fabricated state run through the REAL painters, so what you place and size
-- is what you will see in a game. It stages the three states that are easy to
-- confuse and worth being able to compare side by side: a ladder counting
-- down, a ladder frozen because the CC is still on them, and a ladder all the
-- way to immune. The third strip is deliberately clean -- that is what your
-- own tailored set looks like at rest.
-- ---------------------------------------------------------------------------
local TEST_GUIDS = { "Player-TEST-1", "Player-TEST-2", "Player-TEST-3" }
local TEST_NAMES = {
    { name = "Frostpath", class = "MAGE" },
    { name = "Shivspine", class = "ROGUE" },
    { name = "Oathbinder", class = "PALADIN" },
}

function CommanderDiminish_Test()
    local now = GetTime()
    testUntil = now + 20

    for index, guid in ipairs(TEST_GUIDS) do
        dr:Clear(guid)
        identity[guid] = TEST_NAMES[index]
    end

    -- Staged out of the character's OWN ladders where there are any, so the
    -- test board is the board this character will actually have.
    local list = E.ProfileList(profile)
    if #list == 0 then list = { "STUN", "POLY", "FEAR" } end
    local first = DATA.CAT_ICON[list[1]]
    local second = DATA.CAT_ICON[list[2] or list[1]]

    -- One counting down, one still up.
    dr:Applied(TEST_GUIDS[1], first, now - 12)
    dr:Faded(TEST_GUIDS[1], first, now - 8)
    dr:Applied(TEST_GUIDS[1], second, now - 1)

    -- All the way down the ladder.
    for step = 1, 3 do
        dr:Applied(TEST_GUIDS[2], first, now - (10 - step * 2))
        dr:Faded(TEST_GUIDS[2], first, now - (9 - step * 2))
    end

    -- TEST_GUIDS[3] is left clean on purpose.
    Draw()
    print("|cff66ccffCommander Diminish|r: test strip up for 20 seconds.")
end

-- `/cdr log`. Off until asked for, because it is a diagnostic rather than a
-- feature: the point of it is to settle what the client actually reported when
-- a bracket turns out to have been wrong.
function CommanderDiminish_Log(arg)
    if arg == "off" then
        logging = false
        print("|cff66ccffCommander Diminish|r: log off.")
        return
    end
    if not logging then
        logging = true
        for i = 1, LOG_MAX do logLines[i] = nil end
        logNext = 1
        print("|cff66ccffCommander Diminish|r: recording. Play a game, then |cffffd100/cdr log|r again to read it back. |cffffd100/cdr log off|r stops.")
        return
    end
    print("|cff66ccffCommander Diminish|r: the last " .. LOG_MAX .. " events --")
    local printed = 0
    for offset = 0, LOG_MAX - 1 do
        local line = logLines[(logNext + offset - 1) % LOG_MAX + 1]
        if line then
            print("  " .. line)
            printed = printed + 1
        end
    end
    if printed == 0 then print("  nothing recorded yet.") end
end

-- The answer to "why is there no fear row".
function CommanderDiminish_Report()
    RefreshProfile()
    local scope = DB("Scope", "MINE")
    print("|cff66ccffCommander Diminish|r: ladders this character can open ("
        .. scope .. ")")
    local list = E.ProfileList(profile)
    if #list == 0 then
        print("  none -- no spell in your books opens a diminishing category")
    end
    for _, cat in ipairs(list) do
        local group = E.GroupInfo(cat)
        local why = profileWhy[cat]
        local name = why and GetSpellInfo and GetSpellInfo(why)
        print(string.format("  %-10s %s%s", cat, group and group.label or "?",
            name and ("   (" .. name .. ")") or ""))
    end
    print(string.format("  tracking %d %s right now",
        dr:Count(), dr:Count() == 1 and "person" or "people"))
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

-- The units whose auras can be read back, so the ladder can be checked
-- against them. Everyone else is inference only.
local WATCHED = { player = true, target = true, focus = true }
for _, unit in ipairs(ARENA_UNITS) do WATCHED[unit] = true end
for _, unit in ipairs(PARTY_UNITS) do WATCHED[unit] = true end

local function Apply()
    if not Enabled() then
        HideAll()
        return
    end
    -- The chrome is the WINDOW's: its backing, its drag handle, its place on
    -- screen. Embedded there is no window to dress -- and an unlocked HUD
    -- forces its frame visible, which is exactly the loose object this mode
    -- does away with. The position is still applied once, so the test strips
    -- have somewhere sensible to land.
    if DB("Placement", "EMBEDDED") ~= "EMBEDDED" or not root._placed then
        root._placed = true
        Commander.UI.ApplyHudChrome(root, CommanderDiminishDB, "Hud", {
            title = "Diminish",
            defaultPoint = { point = "CENTER", x = 0, y = -160 },
        })
    end
    if DB("Placement", "EMBEDDED") == "EMBEDDED" then root:Hide() end
    RefreshZone()
    RefreshProfile()
    Draw()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_FOCUS_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
-- The profile follows the character rather than a table, so every event that
-- can change what you are able to cast has to re-read it: a trained rank, a
-- respec, a new demon out.
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("UNIT_PET")
pcall(events.RegisterEvent, events, "CHARACTER_POINTS_CHANGED")
pcall(events.RegisterEvent, events, "PLAYER_TALENT_UPDATE")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- Tracking is gated on the ZONE, not on the display: "only in combat"
        -- hides the strip and keeps the ladders running underneath, so a strip
        -- that comes back mid-fight is still correct.
        if Enabled() and (zoneOK or GetTime() < testUntil) then OnCombatLog() end
        return
    end

    if event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player")
        RefreshProfile()
        Apply()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        -- A new instance is a new set of people. Nothing learned in the last
        -- one is true here, and a battleground's worth of stale GUIDs would
        -- otherwise ride along into the next game.
        playerGUID = playerGUID or UnitGUID("player")
        dr:Wipe()
        wipe(identity)
        RefreshZone()
        RefreshProfile()
        Draw()
    elseif event == "UNIT_AURA" then
        -- Only the units the client will talk about, and only in a zone we are
        -- drawing in. UNIT_AURA is a firehose in a battleground.
        if Enabled() and zoneOK and WATCHED[arg1] then ObserveUnit(arg1) end
    elseif event == "UNIT_PET" then
        if arg1 == "player" then RefreshProfile() end
    elseif event == "SPELLS_CHANGED" or event == "CHARACTER_POINTS_CHANGED"
        or event == "PLAYER_TALENT_UPDATE" then
        RefreshProfile()
    else
        Draw()
    end
end)

if Commander and Commander.AddListener then
    Commander.AddListener(COMMANDER_DIMINISH_EVENTS.UPDATE, Apply)
end

-- ---------------------------------------------------------------------------
-- A read-only view for other modules. Commander Plates draws the bracket on
-- its big control icon, so "that sheep landed at half" is readable on the
-- plate itself rather than only on this strip. Returns the bracket the aura
-- that is UP RIGHT NOW landed at (1 full / 2 half / 3 quarter), the bracket
-- the NEXT cast in the category would land at (1..4, 4 = immune), and the
-- category key -- or nil when the spell has no ladder, the tracker is off, or
-- this GUID has never been seen (which, outside arena and battleground with
-- the default zone settings, is everybody).
-- ---------------------------------------------------------------------------
function CommanderDiminish_Brackets(guid, spellId, now)
    if not Enabled() or not guid then return nil end
    local cat = E.Category(spellId)
    if not cat or not dr:Knows(guid) then return nil end
    now = now or GetTime()
    local nextBracket = dr:Bracket(guid, cat, now)
    local current = math.max(1, math.min(nextBracket - 1, DATA.DR_MAX))
    return current, nextBracket, cat
end

-- The picture a category wears under this module's own Icons setting, for a
-- module that draws these rows somewhere else (Commander Plates, round a
-- nameplate) -- so the same ladder is the same icon wherever it is drawn.
function CommanderDiminish_Icon(cat, last)
    return IconFor({ cat = cat, last = last })
end

-- Every category OPEN on a unit right now -- held, or counting down to reset
-- -- as the rows DR:Strip builds for this module's own board: { cat, bracket
-- (of the NEXT cast, 4 = immune), held, resetAt, last (spell id) }. Commander
-- Plates' radial plate draws these round the disc. nil when the tracker is
-- off or has never seen this GUID. `out` is reused if given.
function CommanderDiminish_Open(guid, now, out)
    if not Enabled() or not guid or not dr:Knows(guid) then return nil end
    return dr:Strip(guid, now or GetTime(), nil, false, out)
end

local ticker = CreateFrame("Frame")
ticker.since = 0
ticker.sincePrune = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
    self.since = self.since + elapsed
    if self.since < DRAW_THROTTLE then return end
    self.since = 0

    if not Enabled() then return end

    -- Forgetting people. Cheap, and the only thing standing between a
    -- battleground and a table that grows for the whole game.
    -- Not while the test board is up: its third strip is deliberately clean,
    -- and a pruner cannot tell "fabricated and quiet" from "gone".
    self.sincePrune = self.sincePrune + DRAW_THROTTLE
    if self.sincePrune >= PRUNE_EVERY and GetTime() >= testUntil then
        self.sincePrune = 0
        dr:Prune(GetTime(), 10)
        for guid in pairs(identity) do
            if not dr:Knows(guid) then identity[guid] = nil end
        end
    end

    if self.wasTesting and GetTime() >= testUntil then
        self.wasTesting = false
        for _, guid in ipairs(TEST_GUIDS) do
            dr:Clear(guid)
            identity[guid] = nil
        end
    elseif GetTime() < testUntil then
        self.wasTesting = true
    end

    Draw()
end)
