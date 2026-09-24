-- Commander Arena Frames: the enemy team, and the other half of Commander
-- Party Frames. That board answers "what does my team need"; this one answers
-- "what are they about to do to us, and what can I still land on them".
--
-- The design bar is the same one: what would the world's best RMP want on
-- screen. The answers are different, because everything about an enemy is
-- something the client would rather not tell you. Four of the five instruments
-- here are INFERRED, and the module is deliberately explicit about which:
--
--   HEALTH / POWER   read straight off the unit. A healer's mana is the number
--                    an arena is most often decided by and the one thing the
--                    enemy cannot hide, so the power strip is on by default,
--                    tall enough to read, and carries a percentage of its own.
--   CAST             read straight off the unit. The reason to look at an
--                    enemy frame at all is to kick what is on it.
--   TRINKET          the client's own answer (C_PvP.GetArenaCrowdControlInfo),
--                    so it is right from the first second rather than from the
--                    first time you watch them press it. The only enemy
--                    cooldown on this board that is KNOWN rather than seen.
--   DIMINISHING      inferred from the combat log against the client's own
--   RETURNS          spell data. See the DR section: the two things that make
--                    it correct rather than approximately correct are that the
--                    reset clock starts on the aura FADING (and freezes while
--                    anything in the category is up), and that a CC broken by
--                    damage arrives as SPELL_AURA_BROKEN rather than
--                    SPELL_AURA_REMOVED -- miss that and every stun that gets
--                    broken leaves its bracket stuck forever.
--   COOLDOWNS        inferred from the combat log alone. Never seen used is
--                    drawn as UNKNOWN rather than READY, because "we have not
--                    seen their Ice Block" and "their Ice Block is up" are
--                    different bets and a board that conflates them is lying.
--
-- The reasoning lives in CommanderArenaFramesEngine.lua, which touches no WoW
-- API at all and is tested under plain luajit. This file is the plumbing: what
-- the client says, when, and how it gets drawn. The split is not tidiness --
-- it is what makes a DR bracket something that can be argued about without
-- queueing for a game.
--
-- Everything the client might not have is reached through a pcall or a
-- presence check. This is a 2.5.6 Anniversary client running a retail-era UI
-- framework over TBC content, and the arena API is exactly the surface where
-- that seam shows.

local DATA = CommanderArenaFrames_Data
local E = CommanderArenaFrames_Engine

-- ---------------------------------------------------------------------------
-- Saved-variable access. One accessor, so a nil DB (the moment before
-- ADDON_LOADED) can never take the board down.
-- ---------------------------------------------------------------------------
local function DB(key, default)
    local db = CommanderArenaFramesDB
    if not db then return default end
    local value = db[key]
    if value == nil then return default end
    return value
end

local function Enabled()
    return CommanderArenaFramesDB and CommanderArenaFramesDB.Enable
end

-- ---------------------------------------------------------------------------
-- Layout and art constants. Kept tight: this is a HUD, not a window.
-- ---------------------------------------------------------------------------
local TEXTURES = "Interface\\AddOns\\Commander_ArenaFrames\\Textures\\"
local BAR_TEXTURES = {
    FLAT     = "Interface\\Buttons\\WHITE8X8",
    BLIZZARD = "Interface\\TargetingFrame\\UI-StatusBar",
    GLOSS    = TEXTURES .. "BarGloss.png",
    BEVEL    = TEXTURES .. "BarBevel.png",
    RIDGE    = TEXTURES .. "BarRidge.png",
    GLASS    = TEXTURES .. "BarGlass.png",
}
local BAR_TRACK = { 0.08, 0.08, 0.09, 0.85 }
local WHITE = "Interface\\Buttons\\WHITE8X8"
local CLASS_ICON_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

-- Padding is ONE number the player owns, not a scatter of literals. Every gap
-- inside a row derives from it: between the class icon and the bar, between
-- one band and the next, between icons in a strip, and the inset that keeps
-- text off the edge of its bar. At 0 the board is genuinely flush.
--
-- It is deliberately not scaled by density. Density shrinks the CONTENT, and
-- shrinking a one-pixel gap has nowhere to go.
local function Pad()
    local value = tonumber(DB("Padding", 1)) or 1
    if value < 0 then return 0 end
    if value > 6 then return 6 end
    return value
end

-- How much the board tightens as the bracket gets bigger. A 2v2 board can
-- afford to be roomy; a 5v5 board with the same sizes is half the screen.
-- Applied to every VERTICAL and icon dimension, never to the frame width --
-- the width is a number the player chose and a board that changes width
-- between games is a board you have to re-find.
local DENSITY_SCALE = { ROOMY = 1.0, TIGHT = 0.8 }
local DENSITY_SPACING = { ROOMY = 1.0, TIGHT = 0.5 }
local AUTO_TIGHT_AT = 4   -- enemies; 4v4 and 5v5 get the tight board

local MAX_ENEMIES = 5
local ARENA_UNITS = { "arena1", "arena2", "arena3", "arena4", "arena5" }

-- The classes that bring a pet through the gates. The pet band is part of
-- the row's SHAPE, and a row cannot be reshaped mid-fight with click-cast on
-- -- so the band is reserved by class rather than by whether a pet exists
-- right now, and a warlock whose Felhunter is dead shows an empty track
-- rather than a row that changes height the moment they resummon. A
-- priest's Shadowfiend and a shaman's totems are not pets in this sense.
local PET_CLASSES = { HUNTER = true, WARLOCK = true, MAGE = true }

-- Power colours, by the client's own power-type index.
local POWER_TINT = {
    [0] = { 0.30, 0.52, 0.92 },   -- mana
    [1] = { 0.85, 0.28, 0.24 },   -- rage
    [2] = { 1.00, 0.62, 0.24 },   -- focus
    [3] = { 0.98, 0.86, 0.32 },   -- energy
    [4] = { 0.42, 0.82, 0.55 },   -- happiness
}

local STATE_TINT = {
    EXECUTE  = { 0.90, 0.16, 0.16 },
    IMMUNE   = { 0.98, 0.92, 0.55 },
    WALL     = { 0.45, 0.70, 0.98 },
    DRINK    = { 0.40, 0.85, 0.95 },
    STEALTH  = { 0.62, 0.55, 0.85 },
    CAST     = { 0.95, 0.82, 0.35 },
    CHANNEL  = { 0.55, 0.85, 0.60 },
    TARGET   = { 1.00, 0.90, 0.35 },
    FOCUS    = { 0.45, 0.90, 1.00 },
    DEAD     = { 0.35, 0.35, 0.35 },
}

-- ---------------------------------------------------------------------------
-- Live state. All keyed by GUID rather than by unit token, because a token is
-- a slot and a GUID is a person: an arena unit can go "unseen" and come back,
-- and everything learned about them in between has to survive that.
-- ---------------------------------------------------------------------------
local dr = E.NewDR()
local book = E.NewBook()

local seat = {}          -- unit token -> { guid, class, race, name, spec, ... }
local guidSeat = {}      -- guid -> the same table, for combat-log lookups
local liveCount = 0      -- how many enemies the client is currently reporting
local trinket = {}       -- guid -> { spellId, usedAt, cd }
local flash = {}         -- guid -> expiry of an alert flash
local playerGUID
local inArena = false
local testUntil = 0

-- Auras we resolved this pass, per seat. Rebuilt on UNIT_AURA rather than on
-- every draw: a scan is the expensive part and the auras do not change at
-- sixty hertz.
local function NewSeat(unit)
    return {
        unit = unit, auras = {}, debuffs = {}, notes = {},
        drRows = {}, cdRows = {},
    }
end

local function NoteFlash(guid, seconds)
    if not guid then return end
    flash[guid] = GetTime() + (seconds or 0.6)
end

-- ---------------------------------------------------------------------------
-- Alerts and calls.
--
-- An alert is a claim on attention and a call is a claim on your team's chat,
-- so every one of these is off by default and each is its own switch.
--
-- The channel is the part that is easy to get wrong and fails silently. An
-- arena party is an INSTANCE-category group on this engine, exactly like a
-- battleground: SendChatMessage(msg, "PARTY") is refused there and the call
-- simply never appears. The same resolver Commander Comms uses is the right
-- one -- ask for the instance category first, and only fall back to an
-- ordinary party.
-- ---------------------------------------------------------------------------

local function PickChannel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
    return nil        -- alone: there is nobody to tell
end

local function Say(message)
    if DB("AnnounceChannel", "PARTY") == "SELF" then
        print("|cff66ccffArena|r: " .. message)
        return
    end
    local channel = PickChannel()
    if not channel then
        print("|cff66ccffArena|r: " .. message)
        return
    end
    pcall(SendChatMessage, message, channel)
end

local function AlertSound()
    if not DB("AlertSound", false) then return end
    if PlaySound and SOUNDKIT then
        pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master")
    end
end

-- The alert path proper: a flash on the row, optionally a sound, and -- only
-- when the caller says so -- a line in chat. Every caller decides the last one
-- separately, because a thing worth SEEING is very often not a thing worth
-- saying out loud to two other people mid-fight.
local function Alert(entry, message, announce)
    if not entry then return end
    NoteFlash(entry.guid, 1.2)
    AlertSound()
    if announce and message then Say(message) end
end

-- ---------------------------------------------------------------------------
-- Combat log. The whole inference layer arrives here.
--
-- Three subevents matter for diminishing returns and exactly one of them is
-- the one everybody forgets:
--
--   SPELL_AURA_APPLIED / _REFRESH  a CC landed (or was reapplied)
--   SPELL_AURA_REMOVED             it ran out, was dispelled, or was trinketed
--   SPELL_AURA_BROKEN / _SPELL     it was BROKEN BY DAMAGE -- and this fires
--                                  INSTEAD of _REMOVED, not as well as it
--
-- A tracker that listens only for _REMOVED never learns that the Polymorph it
-- watched land has ended, so the category's stack never returns to zero, the
-- fifteen-second clock never starts, and the bracket sits at half for the rest
-- of the game. Broken CC is the NORMAL case in an arena. It is handled here.
-- ---------------------------------------------------------------------------

local function SeatByGUID(guid)
    return guid and guidSeat[guid] or nil
end

local function OnCombatLog()
    local _, subevent, _, sourceGUID, _, _, _, destGUID, _, _, _,
          spellId, spellName = CombatLogGetCurrentEventInfo()
    -- One clock reading per event. The engine takes `now` as an argument
    -- rather than calling GetTime itself, which is what lets the whole ladder
    -- be tested at arbitrary timestamps under luajit.
    local now = GetTime()

    -- Diminishing returns and control state, on the RECEIVING enemy.
    local victim = SeatByGUID(destGUID)
    if victim then
        if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
            dr:Applied(destGUID, spellId, now)
        elseif subevent == "SPELL_AURA_REMOVED"
            or subevent == "SPELL_AURA_BROKEN"
            or subevent == "SPELL_AURA_BROKEN_SPELL" then
            -- All three are the same fact for a DR clock: the aura is gone.
            -- The two BROKEN forms carry the broken aura's own id in the same
            -- position, which is the only reason one handler covers them.
            dr:Faded(destGUID, spellId, now)
        end
    end

    -- Cooldowns, on the enemy who SPENT one. SPELL_CAST_SUCCESS is the right
    -- signal rather than _START: a cast that gets kicked has still spent the
    -- cooldown on some abilities and not on others, and success is the only
    -- one of the two that is unambiguous.
    local caster = SeatByGUID(sourceGUID)
    if caster and (subevent == "SPELL_CAST_SUCCESS" or subevent == "SPELL_AURA_APPLIED") then
        -- `fresh` is the guard against saying it twice: one press of Ice Block
        -- arrives as a SPELL_CAST_SUCCESS and again as the SPELL_AURA_APPLIED
        -- that follows, and both reach this branch.
        local entry, fresh = book:Used(sourceGUID, caster.class, caster.race,
                                       spellId, spellName, now)
        if entry and fresh then
            if entry.role == "DEF" then
                if DB("AlertDefensive", false) then
                    NoteFlash(sourceGUID, 1.2)
                    AlertSound()
                end
                if DB("AnnounceDefensive", false) then
                    Say(string.format("%s used %s (%s)", caster.name or "enemy",
                        entry.name, E.FormatTime(entry.cd)))
                end
            end
        end
        -- A spec is proved by a cast, not by a class. One marker is enough and
        -- the answer never changes back.
        if not caster.spec then
            caster.spec = E.SpecFromSpell(caster.class, spellId)
        end
    end
end

-- ---------------------------------------------------------------------------
-- The trinket. The one enemy cooldown the client will actually answer for --
-- C_PvP.GetArenaCrowdControlInfo reports the unit's PvP trinket and, once it
-- has been used, when it comes back. Requested per unit as they appear, then
-- refreshed on ARENA_CROWD_CONTROL_SPELL_UPDATE.
--
-- Fully guarded: the whole C_PvP surface is reached through pcall, and a
-- client that answers nothing leaves the slot empty rather than erroring. The
-- combat-log fallback below still catches the moment it is pressed.
-- ---------------------------------------------------------------------------

local function RequestTrinket(unit)
    if not (C_PvP and C_PvP.RequestCrowdControlSpell) then return end
    pcall(C_PvP.RequestCrowdControlSpell, unit)
end

local function ReadTrinket(unit)
    if not (C_PvP and C_PvP.GetArenaCrowdControlInfo) then return end
    local ok, spellId, startTime, duration = pcall(C_PvP.GetArenaCrowdControlInfo, unit)
    if not ok or not spellId then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    local record = trinket[guid] or {}
    -- "Was ready a moment ago" only means something if we had actually read
    -- this trinket before. On the FIRST read of a game a record is empty, so
    -- an enemy whose trinket is already down -- they used it out of our sight,
    -- or we are reading late -- would otherwise be announced as having just
    -- pressed it.
    local seenBefore = record.spellId ~= nil
    local wasReady = record.readyAt == nil
    record.spellId = spellId
    -- start/duration arrive in milliseconds and are zero when it is ready.
    if startTime and duration and startTime > 0 and duration > 0 then
        record.readyAt = (startTime + duration) / 1000
        record.cd = duration / 1000
    else
        record.readyAt = nil
    end
    trinket[guid] = record

    -- The transition from ready to counting IS the trinket being used, and it
    -- is a better signal than watching for the cast: it comes from the client
    -- rather than from the combat log, so it cannot be missed to range or to a
    -- log the player has filtered.
    if seenBefore and wasReady and record.readyAt then
        local entry = guidSeat[guid]
        if entry and DB("Trinket", true) then
            if DB("TrinketAlert", true) or DB("AlertTrinket", false) then
                NoteFlash(guid, 1.4)
                if DB("AlertTrinket", false) then AlertSound() end
            end
            if DB("AnnounceTrinket", false) then
                Say(string.format("%s trinketed -- back in %s",
                    entry.name or "enemy", E.FormatTime(record.cd or 120)))
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Roster. Arena unit tokens exist only inside an arena, so the board's whole
-- life cycle hangs off two questions: are we in one, and how many opponents
-- does the client admit to.
-- ---------------------------------------------------------------------------

-- Everything learned about a seat is STICKY for the length of the match, and
-- that is the whole point of this function.
--
-- An arena enemy goes "unseen" constantly -- a rogue vanishes, a mage blinks a
-- room away -- and while they are unseen the client will happily answer nil to
-- UnitGUID, UnitName and UnitClass. Writing those nils back would erase the
-- seat's identity, and everything hanging off it goes with it: the combat log
-- can no longer find the seat, so their diminishing returns stop being
-- recorded, and the board stops drawing the ladder for the one enemy who just
-- disappeared -- which is precisely the enemy it is being consulted about.
--
-- So a nil answer is read as "not right now", never as "not any more". Only a
-- DIFFERENT, non-nil GUID is a real change of occupant.
local function ReadSeat(unit, index)
    local entry = seat[unit]
    if not entry then
        entry = NewSeat(unit)
        seat[unit] = entry
    end
    entry.index = index

    local guid = UnitGUID(unit)
    if guid then
        if entry.guid and entry.guid ~= guid then
            -- A genuinely different person in this slot: what was learned
            -- about the previous occupant belongs to them, not to this seat.
            guidSeat[entry.guid] = nil
            entry.spec = nil
            -- Everything else learned about the previous occupant goes with
            -- them: their last known health would otherwise be drawn as this
            -- person's, and their crowd control as this person's clock.
            entry.lastHealth, entry.lastMax = nil, nil
            entry.control, entry.immunity, entry.drinking, entry.stealth = nil, nil, nil, nil
        end
        entry.guid = guid
        guidSeat[guid] = entry
        entry.name = UnitName(unit) or entry.name
        local _, classToken = UnitClass(unit)
        entry.class = classToken or entry.class
        local _, raceToken = UnitRace(unit)
        entry.race = raceToken or entry.race
    end

    -- Once an enemy has been seen at all they keep their row for the rest of
    -- the match. A board that drops a row when a rogue stealths has removed
    -- the row you were about to use to find the rogue -- and it takes the
    -- muscle memory of every slot below it along with it.
    if UnitExists(unit) then
        entry.exists = true
        entry.prep = nil        -- the real unit supersedes the gates' announcement
    end
    return entry
end

local function ScanRoster()
    liveCount = 0
    if not inArena then
        for _, unit in ipairs(ARENA_UNITS) do
            local entry = seat[unit]
            if entry then entry.exists = false end
        end
        return
    end
    local count = 0
    if GetNumArenaOpponents then
        local ok, value = pcall(GetNumArenaOpponents)
        if ok and value then count = value end
    end
    -- GetNumArenaOpponents can lag a unit appearing, so the tokens are the
    -- authority and the count is only a floor.
    for index, unit in ipairs(ARENA_UNITS) do
        local entry = ReadSeat(unit, index)
        if entry.exists then
            count = math.max(count, index)
            liveCount = index
        end
    end
    liveCount = math.max(liveCount, math.min(count, MAX_ENEMIES))
end

-- The gates. Before the doors open there are no unit tokens at all, but the
-- client does announce the comp -- which is when a team decides its opener, so
-- it is worth drawing. Everything here is guarded: on a client that never
-- ships the prep API the board simply starts when the gates do.
local function ReadPrep()
    if not DB("ShowInPrep", true) then return 0 end
    if not GetNumArenaOpponentSpecs then return 0 end
    local ok, count = pcall(GetNumArenaOpponentSpecs)
    if not ok or not count or count == 0 then return 0 end
    for index = 1, math.min(count, MAX_ENEMIES) do
        local unit = ARENA_UNITS[index]
        local entry = seat[unit]
        if not entry then
            entry = NewSeat(unit)
            seat[unit] = entry
        end
        entry.index = index
        entry.prep = true
        local okSpec, specId = pcall(GetArenaOpponentSpec, index)
        if okSpec and specId and specId > 0 and GetSpecializationInfoByID then
            local okInfo, _, specName, _, _, _, classToken = pcall(GetSpecializationInfoByID, specId)
            if okInfo then
                entry.class = classToken or entry.class
                entry.prepSpec = specName
            end
        end
    end
    return math.min(count, MAX_ENEMIES)
end

-- ---------------------------------------------------------------------------
-- Widgets.
--
-- Bars are a track texture plus a fill texture whose WIDTH is set, rather than
-- StatusBar frames. Two reasons, both learned on the party board: a StatusBar
-- cannot be given an arbitrary art file per style without fighting its own
-- texture coordinates, and a HUD that redraws a dozen bars several times a
-- second is measurably cheaper as textures on one frame than as a dozen
-- frames. The cost is that every fill has to be told its own width, which is
-- what SetFill exists for.
-- ---------------------------------------------------------------------------

local root = CreateFrame("Frame", "CommanderArenaFramesFrame", UIParent)
root:SetPoint("RIGHT", UIParent, "RIGHT", -220, 120)
root:SetSize(210, 40)
root:SetFrameStrata("MEDIUM")
root:Hide()

local rows = {}

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

-- Show/Hide is PROTECTED on any frame CARRYING a secure child, not only on one
-- built from a secure template -- the engine walks up from the button, because
-- hiding an ancestor would hide it. With click-cast on, `root` is exactly such
-- a frame. So a visibility change is a no-op when it is already in the wanted
-- state (the common case, once per draw), and one that would really flip a
-- protected frame mid-fight is skipped rather than attempted: PLAYER_REGEN_ENABLED
-- redraws, and the draw re-derives all of this from scratch.
local function SafeSetShown(frame, want)
    want = want and true or false
    if (frame:IsShown() and true or false) == want then return true end
    if InCombat() and frame.IsProtected and frame:IsProtected() then return false end
    frame:SetShown(want)
    return true
end

local function BarTexture()
    return BAR_TEXTURES[DB("BarTexture", "GLOSS")] or BAR_TEXTURES.FLAT
end

-- A track + fill pair anchored inside `parent`. The fill is left-anchored and
-- sized by SetFill, so an empty bar is a zero-width texture rather than a
-- hidden one -- which keeps its draw layer stable across redraws.
local function NewBar(parent, layer)
    local bar = {}
    bar.bg = parent:CreateTexture(nil, layer or "BACKGROUND")
    bar.bg:SetTexture(WHITE)
    bar.bg:SetVertexColor(BAR_TRACK[1], BAR_TRACK[2], BAR_TRACK[3], BAR_TRACK[4])
    bar.fill = parent:CreateTexture(nil, layer or "BACKGROUND", nil, 1)
    bar.fill:SetTexture(WHITE)
    return bar
end

local function PlaceBar(bar, parent, x, y, width, height)
    bar.bg:ClearAllPoints()
    bar.bg:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    bar.bg:SetSize(width, height)
    bar.fill:ClearAllPoints()
    bar.fill:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    bar.fill:SetSize(1, height)
    bar._w, bar._h = width, height
end

local function SetFill(bar, fraction)
    local width = (bar._w or 1) * math.max(0, math.min(1, fraction or 0))
    if width < 0.5 then
        bar.fill:Hide()
    else
        bar.fill:Show()
        bar.fill:SetWidth(width)
    end
end

local function SetBarTint(bar, tint, alpha)
    bar.fill:SetVertexColor(tint[1], tint[2], tint[3], alpha or 1)
end

-- The value colour: green at full, amber at half, red as it empties. The
-- fill already says how much is left; the colour says it again in a way
-- that reads from the corner of the eye, which is how an arena board is
-- actually looked at. Execute red still takes over at the kill window.
local HEALTH_FULL = { 0.22, 0.82, 0.30 }
local HEALTH_HALF = { 0.95, 0.80, 0.20 }
local HEALTH_LOW  = { 0.90, 0.22, 0.16 }
local function HealthTint(fraction)
    fraction = math.max(0, math.min(1, fraction or 0))
    local a, b, t
    if fraction >= 0.5 then
        a, b, t = HEALTH_HALF, HEALTH_FULL, (fraction - 0.5) * 2
    else
        a, b, t = HEALTH_LOW, HEALTH_HALF, fraction * 2
    end
    return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end

-- The STATE STRIP: the word, the clock and the icon for the handful of things
-- that have to stop what you are doing rather than be noticed -- a crowd
-- control, an immunity, a lockout, a drink -- laid OVER the health bar
-- without covering it.
--
-- It used to be a bar of its own across the health bar, with a near-opaque
-- backing and its own copy of the health number. That deleted the health
-- BAR -- the fill, its colour, the execute red -- for exactly as long as the
-- loudest thing on the row was true, which in an arena is most of the time
-- that matters. Replaced 2026-09-13: the backing is gone, the health bar
-- and its number stay exactly as they are, and the state is said three ways
-- that leave the bar alone -- the word in the tint where the name was, a
-- tinted rim around the bar, and a thin line under the bar that DRAINS.
-- What is left of the line is what you are playing around.
--
-- `hp` is kept as an invisible anchor only: the timer hangs off its left
-- edge so it lands beside the row's own health number, which is now the
-- number you read.
local function NewOverlay(parent, level)
    local o = CreateFrame("Frame", nil, parent)
    o:SetFrameLevel((parent:GetFrameLevel() or 0) + (level or 1))
    o.rim = {}
    for i = 1, 4 do
        local t = o:CreateTexture(nil, "BORDER")
        t:SetTexture(WHITE)
        o.rim[i] = t
    end
    o.drain = o:CreateTexture(nil, "BORDER")
    o.drain:SetTexture(WHITE)
    o.icon = o:CreateTexture(nil, "ARTWORK")
    o.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    o.label = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    o.label:SetJustifyH("LEFT")
    o.timer = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    o.timer:SetJustifyH("RIGHT")
    o.hp = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    o.hp:SetJustifyH("RIGHT")
    o.hp:SetAlpha(0)
    o:Hide()
    return o
end

-- Lay a state strip over a rectangle of the row, with the health number in the
-- same place it occupies when the strip is down -- so the eye never has to
-- move to find it.
local function PlaceOverlay(o, parent, x, y, width, height, pad, inset, numberSize)
    o:ClearAllPoints()
    o:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    o:SetSize(width, height)
    -- The drain is a line along the bottom edge of the bar, never the bar
    local drainH = math.max(2, math.floor(height * 0.18 + 0.5))
    o.drain:ClearAllPoints()
    o.drain:SetPoint("BOTTOMLEFT", o, "BOTTOMLEFT", 0, 0)
    o.drain:SetSize(width, drainH)
    o._w = width
    -- A one-pixel rim just outside the bar, so the state frames the health
    -- without sitting on it
    local r = o.rim
    r[1]:ClearAllPoints(); r[1]:SetPoint("BOTTOMLEFT", o, "TOPLEFT", -1, 0);   r[1]:SetPoint("BOTTOMRIGHT", o, "TOPRIGHT", 1, 0);   r[1]:SetHeight(1)
    r[2]:ClearAllPoints(); r[2]:SetPoint("TOPLEFT", o, "BOTTOMLEFT", -1, 0);   r[2]:SetPoint("TOPRIGHT", o, "BOTTOMRIGHT", 1, 0);   r[2]:SetHeight(1)
    r[3]:ClearAllPoints(); r[3]:SetPoint("TOPRIGHT", o, "TOPLEFT", 0, 0);      r[3]:SetPoint("BOTTOMRIGHT", o, "BOTTOMLEFT", 0, 0); r[3]:SetWidth(1)
    r[4]:ClearAllPoints(); r[4]:SetPoint("TOPLEFT", o, "TOPRIGHT", 0, 0);      r[4]:SetPoint("BOTTOMLEFT", o, "BOTTOMRIGHT", 0, 0); r[4]:SetWidth(1)
    -- The icon is small and sits at the left edge, above the drain line
    local iconSize = math.max(8, height - drainH - 1)
    o.icon:ClearAllPoints()
    o.icon:SetPoint("TOPLEFT", o, "TOPLEFT", 0, 0)
    o.icon:SetSize(iconSize, iconSize)
    o.hp:ClearAllPoints()
    o.hp:SetPoint("RIGHT", o, "RIGHT", -inset, 0)
    o.timer:ClearAllPoints()
    o.timer:SetPoint("RIGHT", o.hp, "LEFT", -(pad + 3), 0)
    o._labelInset, o._flushInset = iconSize + pad + inset, inset
    o._hadIcon = true
    o.label:ClearAllPoints()
    o.label:SetPoint("LEFT", o, "LEFT", o._labelInset, 0)
    o.label:SetPoint("RIGHT", o.timer, "LEFT", -(pad + 2), 0)
    -- The word is sized to the bar; the clock and the (invisible) number
    -- are sized to the row's own health number, because they sit on the
    -- same line as it and two sizes of digit a few pixels apart read as a
    -- mistake.
    local size = math.max(8, math.min(15, math.floor(height * 0.58 + 0.5)))
    local digits = numberSize or size
    for _, fs in ipairs({ o.label, o.timer, o.hp }) do
        local file = fs:GetFont()
        if file then
            pcall(fs.SetFont, fs, file, fs == o.label and size or digits, "OUTLINE")
            fs:SetShadowOffset(1, -1)
            fs:SetShadowColor(0, 0, 0, 1)
        end
    end
end

-- Drive one. `fraction` nil means "no clock" -- a stealth, an aura with no
-- duration -- and draws the whole strip filled rather than empty, because an
-- empty drain reads as "about to end".
local function SetOverlay(o, tint, fraction)
    for i = 1, 4 do o.rim[i]:SetVertexColor(tint[1], tint[2], tint[3], 0.9) end
    local width = (o._w or 1) * math.max(0, math.min(1, fraction or 1))
    if width < 0.5 then
        o.drain:Hide()
    else
        o.drain:Show()
        o.drain:SetWidth(width)
        o.drain:SetVertexColor(tint[1], tint[2], tint[3], 0.95)
    end
    o.label:SetTextColor(tint[1], tint[2], tint[3])
    o.timer:SetTextColor(1, 1, 1)
end

-- A ring of four edge textures on `parent`, placed by PlaceEdge around any
-- rectangle of the row. This is the line that makes the board read as one
-- object rather than a scatter of bars and icons: Gladdy draws a black border
-- around every element it has, and the eye groups by borders before it
-- groups by anything else. The same ring, tinted, is the target and focus
-- highlight -- a 2-pixel frame in gold or cyan, which reads from the corner
-- of the eye where a translucent wash over the whole row never did.
local function NewEdge(parent, layer, sublevel)
    local edge = { edges = {} }
    for i = 1, 4 do
        local t = parent:CreateTexture(nil, layer or "BORDER", nil, sublevel or 0)
        t:SetTexture(WHITE)
        edge.edges[i] = t
    end
    function edge:SetVertexColor(r, g, b, a)
        for i = 1, 4 do self.edges[i]:SetVertexColor(r, g, b, a) end
    end
    function edge:SetShown(shown)
        for i = 1, 4 do self.edges[i]:SetShown(shown) end
    end
    function edge:Hide() self:SetShown(false) end
    function edge:Show() self:SetShown(true) end
    edge:Hide()
    return edge
end

-- Frame the rectangle (x, y, w, h) -- TOPLEFT-relative to `parent`, y
-- negative downwards as everywhere in this file -- with a ring `thick` pixels
-- wide sitting `outset` pixels OUTSIDE it.
local function PlaceEdge(edge, parent, x, y, w, h, thick, outset)
    thick, outset = thick or 1, outset or 0
    local e = edge.edges
    local l, t = x - outset, y + outset
    local r, b = x + w + outset, y - h - outset
    e[1]:ClearAllPoints(); e[1]:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", l - thick, t);       e[1]:SetSize(r - l + 2 * thick, thick)
    e[2]:ClearAllPoints(); e[2]:SetPoint("TOPLEFT", parent, "TOPLEFT", l - thick, b);          e[2]:SetSize(r - l + 2 * thick, thick)
    e[3]:ClearAllPoints(); e[3]:SetPoint("TOPRIGHT", parent, "TOPLEFT", l, t);                 e[3]:SetSize(thick, t - b)
    e[4]:ClearAllPoints(); e[4]:SetPoint("TOPLEFT", parent, "TOPLEFT", r, t);                  e[4]:SetSize(thick, t - b)
end

-- A ring of four edge textures that answers SetVertexColor as one region.
-- Sits just outside the art on the same footprint the backing overhangs, plus
-- one pixel over the art's edge on a slot big enough to spare it, so a strong
-- tint frames the icon rather than replacing it.
local function NewSlotRim(slot)
    local rim = { edges = {} }
    for i = 1, 4 do
        -- On the slot's TOP frame, not the slot: a child Cooldown frame draws
        -- over every region of its parent whatever their layer, so a rim on
        -- the slot itself would sit UNDER the sweep and go dark with it.
        local t = slot.top:CreateTexture(nil, "OVERLAY")
        t:SetTexture(WHITE)
        rim.edges[i] = t
    end
    function rim:SetVertexColor(r, g, b, a)
        for i = 1, 4 do self.edges[i]:SetVertexColor(r, g, b, a) end
    end
    rim:SetVertexColor(1, 1, 1, 0)
    return rim
end

local function SizeSlotRim(slot, size)
    local thick = (size or 0) >= 16 and 2 or 1
    local e = slot.rim.edges
    e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT", slot, "TOPLEFT", -1, 1);      e[1]:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 1, 1);        e[1]:SetHeight(thick)
    e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", -1, -1); e[2]:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 1, -1); e[2]:SetHeight(thick)
    e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT", slot, "TOPLEFT", -1, 1);      e[3]:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", -1, -1);  e[3]:SetWidth(thick)
    e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 1, 1);     e[4]:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 1, -1); e[4]:SetWidth(thick)
end

-- An icon slot: art, a dark backing, a cooldown sweep, and a line of text over
-- it. Used by every strip on the board, so a change to how a slot reads is one
-- change rather than four.
local function NewSlot(parent, size, fontObject)
    local slot = CreateFrame("Frame", nil, parent)
    slot:SetSize(size, size)

    slot.backing = slot:CreateTexture(nil, "BACKGROUND")
    slot.backing:SetTexture(WHITE)
    slot.backing:SetVertexColor(0, 0, 0, 0.75)
    slot.backing:SetPoint("TOPLEFT", -1, 1)
    slot.backing:SetPoint("BOTTOMRIGHT", 1, -1)

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetAllPoints()
    -- Trim the stock icon border so a strip of icons reads as a strip rather
    -- than as a row of little framed pictures.
    slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    slot.sweep = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    slot.sweep:SetAllPoints()
    -- The Cooldown frame's modern setters are not all guaranteed on a client
    -- running a retail-era UI over TBC content, and the strip is perfectly
    -- readable without any of them -- so none is allowed to be fatal.
    pcall(slot.sweep.SetDrawEdge, slot.sweep, false)
    pcall(slot.sweep.SetHideCountdownNumbers, slot.sweep, true)
    pcall(slot.sweep.SetReverse, slot.sweep, false)
    slot.sweep:Hide()

    -- Everything that must stay legible OVER the sweep lives on a frame above
    -- it: the seconds, the count, the rim. A Cooldown frame is a child frame,
    -- and a child frame draws over every region of its parent regardless of
    -- layer -- so text written straight onto the slot went dark under its
    -- own timer, which is the one moment it is being read.
    slot.top = CreateFrame("Frame", nil, slot)
    slot.top:SetAllPoints()
    slot.top:SetFrameLevel(slot.sweep:GetFrameLevel() + 1)

    -- The rim is a RING, never a face: four edge textures around the art,
    -- driven through one SetVertexColor so the painters read like they colour
    -- a border -- because they do. It was a single full-face texture once,
    -- and a "rim" at alpha 1 was a coloured block with no icon under it.
    slot.rim = NewSlotRim(slot)
    SizeSlotRim(slot, size)

    slot.text = slot.top:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlightSmall")
    slot.text:SetPoint("CENTER", slot, "CENTER", 0, 0)
    slot.text:SetJustifyH("CENTER")
    slot.text:SetShadowOffset(1, -1)
    slot.text:SetShadowColor(0, 0, 0, 1)

    slot.sub = slot.top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slot.sub:SetPoint("BOTTOM", slot, "BOTTOM", 0, -1)
    slot.sub:SetJustifyH("CENTER")
    slot.sub:SetShadowOffset(1, -1)
    slot.sub:SetShadowColor(0, 0, 0, 1)

    slot:Hide()
    return slot
end

-- The sweep on a slot: the clock face every arena board draws, set ONCE per
-- application and keyed on when it ends. A Cooldown frame restarted on every
-- paint never gets to draw, so the key is what makes it move. `readyAt` nil
-- takes the sweep down.
local function SetSweep(slot, readyAt, duration)
    if not readyAt or not duration or duration <= 0 or not DB("Sweeps", true) then
        if slot._sweepKey then
            slot._sweepKey = nil
            slot.sweep:Hide()
        end
        return
    end
    -- Rounded, because a value derived from `now` drifts by a rounding error
    -- between paints, and a key that never matches is a sweep restarted at
    -- 20Hz -- the exact failure the key exists to prevent.
    local key = math.floor(readyAt * 10 + 0.5)
    if slot._sweepKey ~= key then
        slot._sweepKey = key
        pcall(slot.sweep.SetCooldown, slot.sweep, readyAt - duration, duration)
        slot.sweep:Show()
    end
end

-- The moment a cooldown comes BACK is worth more than the whole time it was
-- down: "their trinket is up again" is the fact that ends a setup. So a slot
-- that was counting for this enemy and has just stopped pulses its rim white
-- for a second, then hands the rim back to whoever normally paints it.
-- Returns true while the pulse owns the rim.
local READY_PULSE = 1.2
local function ReadyPulse(slot, guid, down, now)
    if down then
        slot._downFor = guid
        slot._readyAt = nil
    elseif slot._downFor == guid then
        -- Came back on THIS enemy. A slot inherited from a different enemy
        -- with a different book says nothing about anyone.
        slot._downFor = nil
        slot._readyAt = DB("ReadyPulse", true) and now or nil
    end
    local since = slot._readyAt and (now - slot._readyAt)
    if since and since < READY_PULSE then
        local pulse = 0.5 + 0.5 * math.sin(since * 16)
        slot.rim:SetVertexColor(1, 1, 1, 0.45 + 0.55 * pulse)
        return true
    end
    slot._readyAt = nil
    return false
end

-- Size a slot's text to the slot. Fit can take an icon down to twelve pixels
-- to land a whole class book on one line, and a fixed 10pt countdown on a
-- twelve-pixel icon spills over its neighbours -- so the font follows the art.
-- Outlined, because small text over a spell icon has no contrast otherwise.
-- Guarded end to end: a client that refuses the SetFont keeps the inherited
-- font rather than losing the strip (and "OUTLINE" is used deliberately --
-- an invalid flag string hard-errors and takes the whole file with it).
local function SizeSlotText(slot, size)
    local main = math.max(7, math.min(14, math.floor(size * 0.62 + 0.5)))
    local sub = math.max(6, main - 2)
    local file = slot.text:GetFont()
    if not file then return end
    pcall(slot.text.SetFont, slot.text, file, main, "OUTLINE")
    pcall(slot.sub.SetFont, slot.sub, file, sub, "OUTLINE")
end

-- The recess treatment every Commander board uses, applied to a whole strip.
local function ShadeSlots(list, round)
    if not Commander.DebossIcon then return end
    local style = DB("IconRecess", "SOFT")
    for _, slot in ipairs(list) do
        Commander.DebossIcon(slot.icon, style ~= "OFF" and style or nil, round)
    end
end

-- ---------------------------------------------------------------------------
-- Row construction. Built once per seat and then only repainted -- a HUD that
-- creates frames while a fight is running is a HUD that stutters, and with
-- click-cast on it is also one that cannot legally do so.
-- ---------------------------------------------------------------------------

local securePool   -- true when the rows were built as secure unit buttons
local secureDirty  -- a binding changed while protected; rewrite once combat ends

-- Forward-declared: the tooltip needs the bracket labels and the painters'
-- scratch tables, which are defined further down, but the hover has to be
-- wired at construction time.
local ShowRowTooltip

local function NewRow(index)
    local frame
    if securePool then
        -- Bound once, out of combat, to a RAW token. Nothing secure ever
        -- changes mid-fight; only the insecure art on top of it does.
        frame = CreateFrame("Button", "CommanderArenaFramesRow" .. index, root,
            "SecureUnitButtonTemplate")
        -- Attributes are NOT set here. SetupSecureRows owns the whole matrix
        -- and rewrites it on every pass, so there is exactly one place that
        -- decides what a click does -- and one place that has to be careful
        -- about combat.
        frame:RegisterForClicks("AnyDown", "AnyUp")
    else
        frame = CreateFrame("Frame", "CommanderArenaFramesRow" .. index, root)
    end
    frame.index = index

    -- The row's own floor: one dark plate under everything the row draws,
    -- so a cast bar, a strip of twelve cooldowns and a strip of auras read
    -- as ONE enemy rather than as five things that happen to be near each
    -- other. Gladdy's frame has the same plate behind it; this one is per
    -- row, so the space between enemies stays open.
    frame.backdrop = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.backdrop:SetTexture(WHITE)
    frame.backdrop:SetAllPoints()
    frame.backdrop:Hide()

    -- Identity
    frame.classIcon = frame:CreateTexture(nil, "ARTWORK")
    frame.classIcon:SetTexture(CLASS_ICON_SHEET)
    frame.classPlate = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    frame.classPlate:SetTexture(WHITE)
    frame.classPlate:SetVertexColor(0, 0, 0, 0.75)
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.name:SetJustifyH("LEFT")
    frame.spec = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.spec:SetJustifyH("LEFT")

    -- Vitals
    frame.health = NewBar(frame, "BACKGROUND")
    frame.healthText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.healthText:SetJustifyH("RIGHT")
    frame.power = NewBar(frame, "BACKGROUND")
    frame.powerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.powerText:SetJustifyH("RIGHT")

    -- The black lines. One ring each around the class square, the bar group
    -- and the trinket -- the three elements that share the row's top block --
    -- and one around the cast bar when it has its own band. Drawn on BORDER,
    -- which is above every bar fill and below every icon.
    frame.edgeClass = NewEdge(frame, "BORDER")
    frame.edgeBars = NewEdge(frame, "BORDER")
    frame.edgeTrinket = NewEdge(frame, "BORDER")

    -- Small text over a lit bar needs a floor of its own. The outline gives
    -- it a shape; the shadow gives it a shadow, and the two together are what
    -- every arena addon's text has had since Gladius.
    for _, fs in ipairs({ frame.name, frame.spec, frame.healthText, frame.powerText }) do
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    end

    -- Cast bar. Its own frame so it can be hidden as a unit, and so the
    -- OVERLAY placement can sit above the health bar's draw layer without
    -- reordering everything else on the row.
    frame.cast = CreateFrame("Frame", nil, frame)
    frame.cast:SetFrameLevel(frame:GetFrameLevel() + 1)
    -- Shown only in OVERLAY mode, where the cast bar lies on the health bar
    -- and would otherwise sit on top of the name and the health number with
    -- no backing at all -- two lines of text over each other in the middle of
    -- a fight. The wash gives it a floor and `hp` gives the number back.
    frame.cast.wash = frame.cast:CreateTexture(nil, "BACKGROUND")
    frame.cast.wash:SetTexture(WHITE)
    frame.cast.wash:SetAllPoints()
    frame.cast.wash:Hide()
    frame.cast.bar = NewBar(frame.cast, "ARTWORK")
    frame.cast.icon = frame.cast:CreateTexture(nil, "OVERLAY")
    frame.cast.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame.cast.label = frame.cast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.cast.label:SetJustifyH("LEFT")
    frame.cast.timer = frame.cast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.cast.timer:SetJustifyH("RIGHT")
    frame.cast.hp = frame.cast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.cast.hp:SetJustifyH("RIGHT")
    frame.cast.hp:Hide()
    for _, fs in ipairs({ frame.cast.label, frame.cast.timer, frame.cast.hp }) do
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    end
    -- The spark: the bright edge on the fill that says WHERE the cast is
    -- without reading the number. Additive, so it lights the bar under it
    -- rather than painting over it.
    frame.cast.spark = frame.cast:CreateTexture(nil, "OVERLAY")
    frame.cast.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    frame.cast.spark:SetBlendMode("ADD")
    frame.cast.spark:Hide()
    frame.cast.edge = NewEdge(frame.cast, "BORDER")
    frame.cast.iconPlate = frame.cast:CreateTexture(nil, "BACKGROUND", nil, -1)
    frame.cast.iconPlate:SetTexture(WHITE)
    frame.cast.iconPlate:SetVertexColor(0, 0, 0, 0.75)
    frame.cast:Hide()

    -- The state strip. One bar across the health bar for the five states that
    -- must stop a cast rather than be noticed, and the first of them is the
    -- one this board exists to show: WHO IS IN CROWD CONTROL, and for how
    -- long. Deliberately louder than any icon, because "they are sapped for
    -- six more seconds" is not a glance-level message and an 16-pixel icon at
    -- the bottom of a strip is not a way to say it.
    frame.state = NewOverlay(frame, 3)

    -- Highlights: target and focus get their own colours because they are
    -- different jobs, and one highlight for both is worse than neither. A
    -- RING, two pixels, around the top block -- it was a translucent wash
    -- over the whole row once, and a wash is part of the board within a
    -- second and stops being a highlight.
    frame.ring = NewEdge(frame, "OVERLAY", 6)

    -- The alert flash, drawn over everything.
    frame.flash = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    frame.flash:SetTexture(WHITE)
    frame.flash:SetAllPoints()
    frame.flash:Hide()

    -- Who this enemy is on. A single small class icon; the "it is YOU" case
    -- gets its own tint, because that is the one worth interrupting for.
    frame.targetOf = frame:CreateTexture(nil, "OVERLAY")
    frame.targetOf:SetTexture(CLASS_ICON_SHEET)
    frame.targetOf:Hide()

    -- The pet. A thin bar under the row for the enemy's Felhunter, Succubus,
    -- Water Elemental or hunter pet: what it is and how much of it is left.
    -- Killing the Felhunter is a decision an arena is made of, and it is one
    -- no other element on the board can inform.
    frame.pet = {}
    frame.pet.bar = NewBar(frame, "BACKGROUND")
    frame.pet.name = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.pet.name:SetJustifyH("LEFT")
    frame.pet.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.pet.text:SetJustifyH("RIGHT")
    frame.pet.edge = NewEdge(frame, "BORDER")
    for _, fs in ipairs({ frame.pet.name, frame.pet.text }) do
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    end

    -- Strips. Slot counts are capped by the settings' own maxima so the pool
    -- is allocated once and never grows.
    frame.trinket = NewSlot(frame, 22, "GameFontHighlightSmall")
    frame.drSlots, frame.cdSlots, frame.auraSlots = {}, {}, {}
    for i = 1, 8 do frame.drSlots[i] = NewSlot(frame, 20) end
    for i = 1, 24 do frame.cdSlots[i] = NewSlot(frame, 18) end
    for i = 1, 10 do frame.auraSlots[i] = NewSlot(frame, 18) end

    -- The class square while they are controlled. The class is the one thing
    -- about an enemy that never changes, so its square is the one place on
    -- the row that can be borrowed without losing anything: the control's
    -- own icon takes it, with a sweep that empties as the control runs out
    -- and the seconds left written large across it. That is the picture
    -- that decides a chain -- the sap is at four seconds, the next one goes
    -- NOW -- and a word on the bar cannot be read from across the screen the
    -- way an icon and a number can.
    frame.ccBox = NewSlot(frame, 28, "GameFontHighlightSmall")

    -- Hover. Insecure throughout -- OnEnter/OnLeave scripts never touch the
    -- unit attribute, so click-cast and @mouseover macros are unaffected by
    -- anything the tooltip does or by switching it off.
    --
    -- A click-cast row NEEDS the mouse, because that is the whole point of it.
    -- A plain one must not take it: a board sitting over the middle of the
    -- screen that swallows every click through it is worse than no tooltip.
    -- EnableMouseMotion exists on this engine and gives hover WITHOUT
    -- capturing clicks, which is exactly the difference.
    if securePool then
        frame:EnableMouse(true)
    elseif frame.EnableMouseMotion then
        frame:EnableMouseMotion(true)
    end
    frame:SetScript("OnEnter", function(self)
        if ShowRowTooltip then ShowRowTooltip(self) end
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame:Hide()
    return frame
end

-- ---------------------------------------------------------------------------
-- Layout. Runs when the SHAPE of a row could have changed -- a setting, or the
-- enemy's class (which decides how many cooldown slots there are) -- and never
-- on a redraw. Returns the row's total height so the board can stack them.
--
-- The row is a top block plus a stack of bands:
--
--   [class icon] name              spec        HP%   [trinket]
--   [class icon] ===== health ==========================
--   [class icon] ----- power ------------------------
--   ======== cast bar ================================    (band, optional)
--   [dr][dr][dr]                                          (band, optional)
--   [cd][cd][cd][cd][cd][cd][cd][cd]                      (band, optional)
--   [aura][aura][aura]                                    (band, optional)
--
-- The DR brackets can instead sit OUTSIDE the row to the left or right, which
-- is where a player used to other arena addons will look for them; the board's
-- own width does not change either way, so moving them never reflows anything.
-- ---------------------------------------------------------------------------

-- A shared empty table for the "setting missing" case. DB(key, {}) would hand
-- back a fresh one on every call, and these two run per enemy at 20Hz.
local NO_ROLES = {}

local function ClassBookLength(entry)
    if not entry or not entry.class then return 0 end
    local roles = DB("CooldownRoles", NO_ROLES)
    local count = 0
    for _, def in ipairs(E.BookFor(entry.class, entry.race)) do
        if roles[def.role] and CommanderArenaFrames_CooldownTracked(entry.class, def.name) then
            count = count + 1
        end
    end
    return count
end

-- Scale a pixel dimension by the board's density, never below what is still
-- legible: a 9-pixel icon is not a smaller icon, it is a smudge.
local function Px(value, scale, floorAt)
    local out = math.floor((value or 0) * (scale or 1) + 0.5)
    local low = floorAt or 6
    return out < low and low or out
end

local function LayoutRow(frame, entry, scale)
    scale = scale or 1
    local W = DB("FrameWidth", 200)
    local pad = Pad()
    -- The text inset is always at least a pixel clear of the bar edge: a
    -- number touching the end of its own bar reads as clipped, not as tight.
    local inset = pad + 1
    local H = Px(DB("RowHeight", 28), scale, 16)
    local tex = BarTexture()

    local iconOn = DB("ShowClassIcon", true)
    local iconW = iconOn and H or 0
    local trinkOn = DB("Trinket", true)
    -- The trinket is the row's height by default, exactly as the class
    -- square is: three elements on one block at one height is the single
    -- biggest thing that makes Gladdy's row read as a row. A smaller trinket
    -- is still a slider away.
    local trinkSize = 0
    if trinkOn then
        trinkSize = DB("TrinketFillRow", true) and H or Px(DB("TrinketSize", 20), scale, 10)
        if trinkSize > H then trinkSize = H end
    end
    -- Borders eat a pixel of gap on each side of every element they frame:
    -- two bordered elements a pixel apart share a line, which is the look.
    local borders = DB("ElementBorders", true)
    local edgeGap = borders and math.max(pad, 1) or pad

    local barLeft = iconW + (iconOn and edgeGap or 0)
    local barRight = W - (trinkOn and (trinkSize + edgeGap) or 0)
    local barW = math.max(20, barRight - barLeft)

    frame:SetWidth(W)

    if iconOn then
        frame.classIcon:Show()
        frame.classIcon:ClearAllPoints()
        frame.classIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.classIcon:SetSize(H, H)
        frame.classPlate:ClearAllPoints()
        frame.classPlate:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.classPlate:SetSize(H, H)
        frame.classPlate:Show()
        if Commander.DebossIcon then
            local style = DB("IconRecess", "SOFT")
            Commander.DebossIcon(frame.classIcon, style ~= "OFF" and style or nil)
        end
        PlaceEdge(frame.edgeClass, frame, 0, 0, H, H, 1, 0)
        frame.edgeClass:SetVertexColor(0, 0, 0, 1)
        frame.edgeClass:SetShown(borders)
        -- The control square sits exactly on the class square. Its number
        -- runs bigger than a strip's: it is the one figure on the row that
        -- is read from the corner of the eye, and a row is two of a strip.
        frame.ccBox:ClearAllPoints()
        frame.ccBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.ccBox:SetSize(H, H)
        SizeSlotText(frame.ccBox, H)
        SizeSlotRim(frame.ccBox, H)
        local file = frame.ccBox.text:GetFont()
        if file then
            pcall(frame.ccBox.text.SetFont, frame.ccBox.text, file,
                math.max(9, math.min(20, math.floor(H * 0.55 + 0.5))), "OUTLINE")
        end
    else
        frame.classIcon:Hide()
        frame.classPlate:Hide()
        frame.edgeClass:Hide()
        frame.ccBox:Hide()
    end

    -- Identity sits ON the health bar, not above it.
    --
    -- It used to have its own 13-pixel line, which is a third of the row spent
    -- on text -- and it came out of the health bar, leaving an 8-pixel bar
    -- under a 28-pixel class icon. Worse, that 13 was a fixed number while
    -- everything around it scaled, so a tight board computed a NEGATIVE health
    -- height and clamped to a 6-pixel minimum, overflowing its own row and
    -- putting the bands below it on top of the power strip.
    --
    -- Overlaying is both the fix and the better design: name on the left of
    -- the bar, health on the right, spec between them. It is what every arena
    -- board does, and it gives the bar back two thirds of the row.
    local sideOn = DB("ShowSpec", true) or DB("ShowRace", false)
    local powerOn = DB("PowerBar", true)
    local powerH = powerOn and Px(DB("PowerBarHeight", 6), scale, 3) or 0
    local healthH = math.max(8, H - powerH - (powerOn and pad or 0))
    local textSize = math.max(8, math.min(14, math.floor(healthH * 0.55 + 0.5)))

    local function SetFontSize(fontString, size)
        local file = fontString:GetFont()
        if file then pcall(fontString.SetFont, fontString, file, size, "OUTLINE") end
    end

    frame.name:ClearAllPoints()
    frame.name:SetPoint("LEFT", frame, "TOPLEFT", barLeft + inset, -healthH / 2)
    frame.name:SetShown(DB("ShowName", true))
    SetFontSize(frame.name, textSize)

    frame.healthText:ClearAllPoints()
    frame.healthText:SetPoint("RIGHT", frame, "TOPLEFT", barRight - inset, -healthH / 2)
    frame.healthText:SetShown(DB("HealthText", "PERCENT") ~= "NONE")
    SetFontSize(frame.healthText, math.max(8, math.min(18, DB("HealthTextSize", 11))))

    frame.spec:ClearAllPoints()
    frame.spec:SetPoint("RIGHT", frame.healthText, "LEFT", -(pad + 3), 0)
    frame.spec:SetShown(sideOn)
    SetFontSize(frame.spec, math.max(7, textSize - 1))
    -- The name yields to the spec, and the spec to the number: on a narrow
    -- frame a long name must be what gets clipped, never the health.
    frame.name:SetPoint("RIGHT", frame.spec, "LEFT", -(pad + 2), 0)

    PlaceBar(frame.health, frame, barLeft, 0, barW, healthH)
    frame.health.bg:SetTexture(tex)
    frame.health.fill:SetTexture(tex)
    frame.health.bg:SetVertexColor(BAR_TRACK[1], BAR_TRACK[2], BAR_TRACK[3], BAR_TRACK[4])
    -- One line around the health AND power bars together: they are one
    -- instrument with two readings, and a line between them would say
    -- otherwise.
    PlaceEdge(frame.edgeBars, frame, barLeft, 0, barW, H, 1, 0)
    frame.edgeBars:SetVertexColor(0, 0, 0, 1)
    frame.edgeBars:SetShown(borders)

    if powerOn then
        PlaceBar(frame.power, frame, barLeft, -(healthH + pad), barW, powerH)
        frame.power.bg:SetTexture(tex)
        frame.power.fill:SetTexture(tex)
        frame.power.bg:SetVertexColor(BAR_TRACK[1], BAR_TRACK[2], BAR_TRACK[3], BAR_TRACK[4])
        frame.power.bg:Show()
        frame.powerText:ClearAllPoints()
        frame.powerText:SetPoint("RIGHT", frame, "TOPLEFT", barRight - inset, -(healthH + pad + powerH / 2))
        SetFontSize(frame.powerText, math.max(7, math.floor(powerH * 1.2 + 0.5)))
    else
        frame.power.bg:Hide()
        frame.power.fill:Hide()
        frame.powerText:Hide()
    end

    if trinkOn then
        frame.trinket:SetSize(trinkSize, trinkSize)
        SizeSlotText(frame.trinket, trinkSize)
        SizeSlotRim(frame.trinket, trinkSize)
        frame.trinket:ClearAllPoints()
        frame.trinket:SetPoint("TOPRIGHT", frame, "TOPLEFT", W, -math.floor((H - trinkSize) / 2))
        PlaceEdge(frame.edgeTrinket, frame, W - trinkSize, -math.floor((H - trinkSize) / 2),
            trinkSize, trinkSize, 1, 0)
        frame.edgeTrinket:SetVertexColor(0, 0, 0, 1)
        frame.edgeTrinket:SetShown(borders)
    else
        frame.edgeTrinket:Hide()
    end

    -- The highlight rings the whole top block, one pixel outside the black
    -- line, so the two never fight for the same pixels.
    PlaceEdge(frame.ring, frame, 0, 0, W, H, 2, borders and 1 or 0)

    PlaceOverlay(frame.state, frame, barLeft, 0, barW, healthH, pad, inset,
        math.max(8, math.min(18, DB("HealthTextSize", 11))))

    frame.targetOf:ClearAllPoints()
    -- Rides the bottom-left corner of the class icon, so it scales with it.
    local targetOfSize = math.max(8, math.floor(H * 0.38 + 0.5))
    frame.targetOf:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 1, -(H - 1))
    frame.targetOf:SetSize(targetOfSize, targetOfSize)

    -- ---- bands ----------------------------------------------------------
    local y = -H

    -- Cast bar
    local castOn = DB("CastBar", true)
    local castH = Px(DB("CastBarHeight", 10), scale, 7)
    if castOn then
        frame.cast:Show()
        frame.cast:ClearAllPoints()
        local overlayCast = DB("CastBarPosition", "BELOW") == "OVERLAY"
        frame.cast.wash:SetShown(overlayCast)
        frame.cast.hp:SetShown(overlayCast and DB("HealthText", "PERCENT") ~= "NONE")
        if overlayCast then
            frame.cast:SetPoint("TOPLEFT", frame, "TOPLEFT", barLeft, 0)
            frame.cast:SetSize(barW, healthH)
            PlaceBar(frame.cast.bar, frame.cast, 0, 0, barW, healthH)
            frame.cast.wash:SetVertexColor(0.05, 0.05, 0.06, 0.80)
            frame.cast.hp:ClearAllPoints()
            frame.cast.hp:SetPoint("RIGHT", frame.cast, "RIGHT", -inset, 0)
            SetFontSize(frame.cast.hp, math.max(8, math.min(18, DB("HealthTextSize", 11))))
        else
            frame.cast:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y - pad)
            frame.cast:SetSize(W, castH)
            PlaceBar(frame.cast.bar, frame.cast, castH + pad, 0, W - castH - pad, castH)
            y = y - castH - pad
        end
        frame.cast.bar.bg:SetTexture(tex)
        frame.cast.bar.fill:SetTexture(tex)
        local castIconH = overlayCast and healthH or castH
        frame.cast.icon:ClearAllPoints()
        frame.cast.icon:SetPoint("TOPLEFT", frame.cast, "TOPLEFT", 0, 0)
        frame.cast.icon:SetSize(castIconH, castIconH)
        frame.cast.icon:SetShown(DB("CastIcon", true))
        frame.cast.iconPlate:ClearAllPoints()
        frame.cast.iconPlate:SetAllPoints(frame.cast.icon)
        frame.cast.iconPlate:SetShown(DB("CastIcon", true) and not overlayCast)
        if Commander.DebossIcon then
            local style = DB("IconRecess", "SOFT")
            Commander.DebossIcon(frame.cast.icon, style ~= "OFF" and style or nil)
        end
        -- Its own band gets its own line, around the bar and the icon as one
        -- piece; laid on the health bar it borrows the health bar's.
        if borders and not overlayCast then
            PlaceEdge(frame.cast.edge, frame.cast, 0, 0, W, castH, 1, 0)
            frame.cast.edge:SetVertexColor(0, 0, 0, 1)
            frame.cast.edge:Show()
        else
            frame.cast.edge:Hide()
        end
        -- The spark rides the fill's leading edge. Its height overshoots the
        -- bar on purpose -- that is what the stock art is drawn for.
        frame.cast.spark:ClearAllPoints()
        frame.cast.spark:SetPoint("CENTER", frame.cast.bar.fill, "RIGHT", 0, 0)
        -- ...but never by more than three pixels a side: on a health bar
        -- it would otherwise stand clear of the row.
        frame.cast.spark:SetSize(math.max(8, math.floor(castIconH * 0.9)),
            math.min(math.floor(castIconH * 1.6), castIconH + 6))
        -- Text follows the band: a 10pt name on an 18-pixel bar is a
        -- whisper, and on an 8-pixel one it is taller than the bar.
        local castText = math.max(8, math.min(14, math.floor(castIconH * 0.8 + 0.5)))
        SetFontSize(frame.cast.label, castText)
        SetFontSize(frame.cast.timer, castText)
        frame.cast.label:ClearAllPoints()
        frame.cast.label:SetPoint("LEFT", frame.cast, "LEFT", castIconH + pad + inset, 0)
        frame.cast.timer:ClearAllPoints()
        if overlayCast and frame.cast.hp:IsShown() then
            frame.cast.timer:SetPoint("RIGHT", frame.cast.hp, "LEFT", -(pad + 3), 0)
        else
            frame.cast.timer:SetPoint("RIGHT", frame.cast, "RIGHT", -inset, 0)
        end
        frame.cast.label:SetPoint("RIGHT", frame.cast.timer, "LEFT", -(pad + 2), 0)
    else
        frame.cast:Hide()
    end

    -- Diminishing-returns brackets
    local drOn = DB("DR", true)
    local drSize = Px(DB("DRIconSize", 18), scale, 12)
    local drMax = DB("DRMax", 5)
    local drWhere = DB("DRPosition", "RIGHT")
    for i, slot in ipairs(frame.drSlots) do
        slot:SetSize(drSize, drSize)
        SizeSlotText(slot, drSize)
        SizeSlotRim(slot, drSize)
        slot:ClearAllPoints()
        if not drOn or i > drMax then
            slot:Hide()
        elseif drWhere == "BELOW" then
            slot:SetPoint("TOPLEFT", frame, "TOPLEFT", (i - 1) * (drSize + pad), y - pad)
        elseif drWhere == "LEFT" then
            -- Beside the row, centred on the top block: a strip that hangs
            -- off the top edge of a taller row reads as misaligned.
            slot:SetPoint("TOPRIGHT", frame, "TOPLEFT", -(pad + 2) - (i - 1) * (drSize + pad),
                -math.floor(math.max(0, H - drSize) / 2))
        else
            slot:SetPoint("TOPLEFT", frame, "TOPLEFT", W + pad + 2 + (i - 1) * (drSize + pad),
                -math.floor(math.max(0, H - drSize) / 2))
        end
    end
    if drOn and drWhere == "BELOW" then y = y - drSize - pad end

    -- Enemy cooldowns
    -- The cooldown strip was the single biggest thing on the board: a paladin
    -- has twelve tracked abilities, eight fit on a line, so the strip wrapped
    -- to two rows and became TALLER than the enemy's own health bar -- forty
    -- pixels of it, five times over in a 5v5.
    --
    -- Fit solves it without dropping anything: shrink the icons just enough
    -- that the whole book lands on ONE line. Twelve icons across a 200-pixel
    -- frame is sixteen pixels each, which is the size they were anyway. Only
    -- when that would push them below legibility does the strip wrap, and the
    -- player can ask for wrapping outright.
    local cdOn = DB("Cooldowns", true)
    local cdSize = Px(DB("CooldownSize", 16), scale, 10)
    local cdCount = cdOn and math.min(ClassBookLength(entry), #frame.cdSlots) or 0
    local perRow = DB("CooldownPerRow", 8)
    if cdOn and cdCount > 0 and DB("CooldownFit", "FIT") == "FIT" then
        local fits = math.floor((W + pad) / (cdSize + pad))
        if fits < cdCount then
            -- Shrink to fit, but never past the legibility floor.
            local wanted = math.floor((W - (cdCount - 1) * pad) / cdCount)
            if wanted >= 10 then
                cdSize = wanted
                perRow = cdCount
            else
                perRow = math.max(1, math.floor((W + pad) / (10 + pad)))
                cdSize = 10
            end
        else
            perRow = cdCount
        end
    end
    for i, slot in ipairs(frame.cdSlots) do
        slot:SetSize(cdSize, cdSize)
        SizeSlotText(slot, cdSize)
        SizeSlotRim(slot, cdSize)
        slot:ClearAllPoints()
        if i > cdCount then
            slot:Hide()
        else
            local col, line = (i - 1) % perRow, math.floor((i - 1) / perRow)
            slot:SetPoint("TOPLEFT", frame, "TOPLEFT",
                col * (cdSize + pad), y - pad - line * (cdSize + pad))
        end
    end
    if cdCount > 0 then
        y = y - pad - math.ceil(cdCount / perRow) * (cdSize + pad)
    end

    -- Auras
    local auraOn = DB("Auras", true)
    local auraSize = Px(DB("AuraSize", 16), scale, 10)
    local auraMax = DB("AuraMax", 5)
    for i, slot in ipairs(frame.auraSlots) do
        slot:SetSize(auraSize, auraSize)
        SizeSlotText(slot, auraSize)
        SizeSlotRim(slot, auraSize)
        slot:ClearAllPoints()
        if not auraOn or i > auraMax then
            slot:Hide()
        else
            slot:SetPoint("TOPLEFT", frame, "TOPLEFT", (i - 1) * (auraSize + pad), y - pad)
        end
    end
    if auraOn then y = y - auraSize - pad end

    -- The pet band, last: it is a second unit, and the row's own instruments
    -- come first.
    local petOn = DB("PetBars", true) and entry and PET_CLASSES[entry.class] or false
    frame._petOn = petOn
    if petOn then
        local petH = Px(DB("PetBarHeight", 8), scale, 5)
        PlaceBar(frame.pet.bar, frame, barLeft, y - pad, barW, petH)
        frame.pet.bar.bg:SetTexture(tex)
        frame.pet.bar.fill:SetTexture(tex)
        frame.pet.bar.bg:SetVertexColor(BAR_TRACK[1], BAR_TRACK[2], BAR_TRACK[3], BAR_TRACK[4])
        frame.pet.bar.bg:Show()
        local petText = math.max(7, math.min(12, math.floor(petH * 0.9 + 0.5)))
        frame.pet.name:ClearAllPoints()
        frame.pet.name:SetPoint("LEFT", frame, "TOPLEFT", barLeft + inset, y - pad - petH / 2)
        frame.pet.name:Show()
        SetFontSize(frame.pet.name, petText)
        frame.pet.text:ClearAllPoints()
        frame.pet.text:SetPoint("RIGHT", frame, "TOPLEFT", barRight - inset, y - pad - petH / 2)
        frame.pet.text:Show()
        SetFontSize(frame.pet.text, petText)
        frame.pet.name:SetPoint("RIGHT", frame.pet.text, "LEFT", -(pad + 2), 0)
        PlaceEdge(frame.pet.edge, frame, barLeft, y - pad, barW, petH, 1, 0)
        frame.pet.edge:SetVertexColor(0, 0, 0, 1)
        frame.pet.edge:SetShown(borders)
        y = y - pad - petH
    else
        frame.pet.bar.bg:Hide()
        frame.pet.bar.fill:Hide()
        frame.pet.name:Hide()
        frame.pet.text:Hide()
        frame.pet.edge:Hide()
    end

    ShadeSlots(frame.drSlots)
    ShadeSlots(frame.cdSlots)
    ShadeSlots(frame.auraSlots)
    ShadeSlots({ frame.trinket, frame.ccBox })

    local height = -y
    frame:SetHeight(height)
    -- The plate under the row, sized to whatever the row turned out to be.
    -- One pixel out on every side, so the black lines around the top block
    -- sit ON the plate rather than on its edge -- and no further, so two
    -- rows at the default spacing keep a hairline of world between them.
    local plate = DB("RowBackdrop", "DARK")
    if plate ~= "NONE" then
        local alpha = plate == "DARKER" and 0.65 or 0.35
        frame.backdrop:ClearAllPoints()
        frame.backdrop:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
        frame.backdrop:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
        frame.backdrop:SetVertexColor(0, 0, 0, alpha)
        frame.backdrop:Show()
    else
        frame.backdrop:Hide()
    end
    frame._barLeft, frame._barW, frame._healthH = barLeft, barW, healthH
    frame._cdCount = cdCount
    return height
end

-- ---------------------------------------------------------------------------
-- Aura scanning. Driven by UNIT_AURA rather than by the draw loop: a scan is
-- the expensive part of this module and an enemy's auras do not change sixty
-- times a second.
--
-- The scan answers three separate questions and keeps them apart, because they
-- have different consequences:
--   * is this enemy UNTOUCHABLE right now (stop the cast)
--   * are they out of the fight (drinking, stealthed)
--   * what is worth a slot on the strip
-- ---------------------------------------------------------------------------

local AURA_RESCAN = 1.0   -- seconds; the safety net, not the mechanism

local function ScanAuras(entry)
    local unit = entry.unit
    entry.scanAt = GetTime()

    -- Both bail-outs come BEFORE anything is cleared, and the ordering is the
    -- point. The test board fills `notes` itself and must not be scanned away;
    -- and a unit the client will not answer for right now is "cannot read",
    -- not "has nothing". Wiping first and returning would blank the strip for
    -- exactly the enemy who just went out of sight -- the one whose last known
    -- state is most worth keeping. The icons carry their own countdowns, so a
    -- stale entry ages out on its own rather than lying indefinitely.
    if entry.test then return end
    if not (entry.guid and UnitExists(unit)) then return end

    local notes = entry.notes
    for i = #notes, 1, -1 do notes[i] = nil end
    local wasDrinking = entry.drinking ~= nil
    entry.immunity, entry.drinking, entry.stealth, entry.control = nil, nil, nil, nil

    -- A corpse has no auras worth carrying. Without this the last thing that
    -- was on them -- a Polymorph, a Divine Shield -- stays on the row for the
    -- rest of the game, because the scan below reads an empty aura list and
    -- the sticky-seat rule keeps the row.
    if UnitIsDeadOrGhost(unit) then return end

    local mode = DB("AuraShow", "NOTED")
    local mineOnly = DB("AuraMineOnly", false)

    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        for index = 1, 40 do
            local aura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
            if not aura then break end
            local spellId = aura.spellId
            local note = E.AuraNote(spellId)

            -- The states that change what you should be DOING are recorded
            -- whatever the strip is set to show: an immunity you filtered out
            -- of a strip is still an immunity.
            if note then
                if note.kind == "IMMUNE" then
                    entry.immunity = { note = note, expires = aura.expirationTime,
                                       duration = aura.duration, icon = aura.icon }
                elseif note.kind == "STEALTH" then
                    entry.stealth = { icon = aura.icon }
                end
            end
            if E.IsDrink(spellId) then
                entry.drinking = { expires = aura.expirationTime, icon = aura.icon }
            end

            -- CROWD CONTROL. The headline of the whole board: whether this
            -- enemy can act right now, and for how long they cannot.
            --
            -- Only ever taken from a DEBUFF. A helpful aura can share an id
            -- family with a control one (Seduction's channel on the succubus,
            -- a self-cast Ice Block), and reading one as control would draw a
            -- mage who just saved himself as a mage who has been sapped.
            --
            -- Roots and disarms are deliberately NOT control here -- a rooted
            -- caster is still casting at you and a disarmed warrior is still
            -- intercepting. They stay on the aura strip where they belong;
            -- Engine.ControlKind is the single place that rule lives.
            local ckind = (filter == "HARMFUL") and E.ControlKind(spellId) or nil
            if ckind == "ROOT" or ckind == "DISARM" then ckind = nil end
            if ckind then
                local rank = E.ControlRank(ckind)
                local best = entry.control
                -- Worst kind first, and within a kind the one that lasts
                -- LONGEST -- that is the clock you are actually playing
                -- around when two land together.
                if not best or rank < best.rank
                    or (rank == best.rank
                        and (aura.expirationTime or math.huge) > (best.expires or 0)) then
                    entry.control = {
                        id = spellId, kind = ckind, rank = rank,
                        icon = aura.icon, name = aura.name,
                        word = E.ControlWord(spellId, ckind),
                        cat = E.Category(spellId),
                        expires = aura.expirationTime, duration = aura.duration,
                    }
                end
            end

            local wanted
            if mode == "ALL" then
                wanted = true
            elseif mode == "PURGEABLE" then
                wanted = (filter == "HELPFUL") and aura.dispelName == "Magic"
            else
                -- Control is in the curated set whatever else is: TBC gives
                -- silence no diminishing returns at all, so a lockout carries
                -- neither a note nor a DR category and a strip keyed on those
                -- two alone would never show one.
                wanted = note ~= nil or E.Category(spellId) ~= nil or ckind ~= nil
            end
            if wanted and filter == "HARMFUL" and mineOnly
                and aura.sourceUnit and UnitGUID(aura.sourceUnit) ~= playerGUID then
                wanted = false
            end

            if wanted then
                notes[#notes + 1] = {
                    id = spellId, icon = aura.icon, count = aura.applications,
                    expires = aura.expirationTime, duration = aura.duration,
                    helpful = filter == "HELPFUL", note = note, control = ckind,
                    mine = aura.sourceUnit and UnitGUID(aura.sourceUnit) == playerGUID,
                }
            end
        end
    end

    -- Sitting down to drink is a transition, not a state, and the moment is
    -- the whole value: an enemy who has just started drinking is out of the
    -- game for exactly as long as you allow.
    if entry.drinking and not wasDrinking and DB("AlertDrink", false) then
        Alert(entry, (entry.name or "An enemy") .. " is drinking",
              DB("AnnounceDefensive", false))
    end

    -- Worst first, and within a tier the one about to run out matters more.
    --
    -- CONTROL leads, above the immunity that used to, and that is a change of
    -- mind rather than a tweak. A control aura carries no `note`, so the old
    -- ordering dropped it into the "no opinion" bucket at the BOTTOM -- where
    -- five of the enemy's own buffs would push a Sap off a five-slot strip
    -- entirely. The one thing the board most needed to say was the one thing
    -- it discarded first.
    --
    -- After that: an immunity outranks a wall outranks anything you put on
    -- them.
    local RANK = { IMMUNE = 1, WALL = 2, REFLECT = 2, FREEDOM = 3, EMPOWER = 3, SPEED = 4, STEALTH = 4 }
    table.sort(notes, function(a, b)
        local ra = a.control and 0 or (a.note and RANK[a.note.kind] or 5)
        local rb = b.control and 0 or (b.note and RANK[b.note.kind] or 5)
        if ra ~= rb then return ra < rb end
        return (a.expires or math.huge) < (b.expires or math.huge)
    end)
end

-- ---------------------------------------------------------------------------
-- Painting. INSECURE ONLY -- textures, fontstrings and colours. Nothing here
-- may touch a secure attribute or a protected method, because it runs every
-- frame including mid-combat, which is exactly when the client refuses.
-- ---------------------------------------------------------------------------

local function ClassTint(classToken)
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if color then return color.r, color.g, color.b end
    return 0.75, 0.35, 0.35
end

local function SetClassIcon(texture, classToken)
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken]
    if coords then
        texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        texture:Show()
    else
        texture:Hide()
    end
end

-- Cut a name to `limit` CHARACTERS, not bytes. `#name` counts bytes, so a
-- ten-byte cut through an accented EU name lands mid-sequence and the row
-- draws a replacement glyph -- and it is precisely the long names that get
-- cut. The byte pattern below is UTF-8's own: a lead byte is anything that is
-- not a 10xxxxxx continuation.
local function TrimName(name, limit)
    if not name or limit == nil or limit <= 0 then return name end
    local count, cut = 0, nil
    for index = 1, #name do
        local byte = name:byte(index)
        if byte < 128 or byte >= 192 then      -- a lead byte: a new character
            count = count + 1
            if count > limit then
                cut = index - 1
                break
            end
        end
    end
    if not cut then return name end
    return name:sub(1, cut)
end

local function ShortNumber(value)
    if not value or value <= 0 then return "0" end
    if value >= 1000000 then return string.format("%.1fm", value / 1000000) end
    if value >= 10000 then return string.format("%.0fk", value / 1000) end
    if value >= 1000 then return string.format("%.1fk", value / 1000) end
    return string.format("%d", value)
end

local function HealthLabel(cur, maximum)
    local mode = DB("HealthText", "PERCENT")
    if mode == "NONE" or not maximum or maximum <= 0 then return "" end
    local pct = math.floor(cur / maximum * 100 + 0.5)
    if mode == "PERCENT" then return pct .. "%" end
    if mode == "CURRENT" then return ShortNumber(cur) end
    if mode == "DEFICIT" then
        local missing = maximum - cur
        return missing > 0 and ("-" .. ShortNumber(missing)) or ""
    end
    return ShortNumber(cur) .. "  " .. pct .. "%"
end

-- The health for THIS seat, from whichever of the three sources can answer:
-- the fabricated test state, the live unit, or -- for an enemy the client has
-- stopped answering for -- the last reading taken before they went out of
-- sight. Three elements print this number (the bar's own text, the state
-- strip, an overlaid cast bar) and they have to agree, including on the
-- stealthed rogue where a live read returns a flat zero.
local function ReadHealth(entry)
    local T = entry.test
    if T then return T.health or 0, T.healthMax or 0 end
    if UnitExists(entry.unit) then
        local maximum = UnitHealthMax(entry.unit) or 0
        if maximum > 0 then return UnitHealth(entry.unit) or 0, maximum end
    end
    return entry.lastHealth or 0, entry.lastMax or 0
end

local function PaintIdentity(frame, entry)
    if DB("ShowClassIcon", true) then
        SetClassIcon(frame.classIcon, entry.class)
    end
    if DB("ShowName", true) then
        local name = TrimName(entry.name or ("Enemy " .. (entry.index or "?")),
                              DB("NameMaxChars", 10))
        frame.name:SetText(name)
        if DB("ClassColorName", false) then
            frame.name:SetTextColor(ClassTint(entry.class))
        else
            frame.name:SetTextColor(1, 1, 1)
        end
    end
    -- The spec is shown only once it has been PROVEN. Before that the slot
    -- says nothing rather than guessing; the prep phase's own announcement is
    -- allowed to stand in, because that came from the client. Race, when asked
    -- for, is shown ALONGSIDE the spec rather than instead of it -- the switch
    -- says "show the race", and a setting that quietly only applies while
    -- something else is unknown is a setting nobody can predict.
    local parts
    if DB("ShowSpec", true) then
        parts = entry.spec or entry.prepSpec
    end
    if DB("ShowRace", false) and entry.race then
        parts = parts and (entry.race .. " " .. parts) or entry.race
    end
    frame.spec:SetText(parts or "")
end

local function PaintVitals(frame, entry, now)
    local unit = entry.unit
    -- The test board has no unit behind it, so the three painters that read
    -- one take their numbers from `entry.test` instead. Everything downstream
    -- -- the ladder, the strips, the banner -- runs the real code path on
    -- fabricated state, which is the point: a test board that draws itself by
    -- a separate route proves nothing about the board.
    local T = entry.test
    local visible = T or UnitExists(unit)
    local maxHealth = T and T.healthMax or UnitHealthMax(unit) or 0
    local health = T and T.health or UnitHealth(unit) or 0

    -- Last known. A rogue vanishes, a mage blinks a room away, and the client
    -- stops answering for them -- but what they were at when they left is the
    -- most useful thing on the board about the one enemy you cannot see.
    if visible and maxHealth > 0 then
        entry.lastHealth, entry.lastMax = health, maxHealth
    end

    local dead = not T and UnitExists(unit) and UnitIsDeadOrGhost(unit)

    if not visible then
        -- Two different unreadable states, and drawing them the same was a
        -- lie the board told constantly. A seat announced at the gates has
        -- never been read at all, so it gets a flat neutral bar. An enemy who
        -- HAS been read and has since gone out of sight gets their last known
        -- health, dimmed -- because a stealthed rogue used to be drawn as a
        -- FULL bar, which is the single most misleading thing an arena frame
        -- can show about the enemy who just disappeared at 20%.
        if entry.lastMax and entry.lastMax > 0 then
            local lastFraction = entry.lastHealth / entry.lastMax
            SetFill(frame.health, lastFraction)
            local r, g, b = ClassTint(entry.class)
            SetBarTint(frame.health, { r * 0.45, g * 0.45, b * 0.45 })
            frame.healthText:SetText(HealthLabel(entry.lastHealth, entry.lastMax))
            frame.healthText:SetTextColor(0.55, 0.55, 0.58)
        else
            SetFill(frame.health, 1)
            SetBarTint(frame.health, { 0.35, 0.35, 0.38 })
            frame.healthText:SetText("")
        end
        frame.powerText:SetText("")
        SetFill(frame.power, 0)
        return
    end
    frame.healthText:SetTextColor(1, 1, 1)

    local fraction = maxHealth > 0 and (health / maxHealth) or 0
    SetFill(frame.health, fraction)
    local execute = DB("ShowExecute", true) and maxHealth > 0
        and fraction * 100 <= DB("ExecuteRange", 20)
    if dead then
        SetBarTint(frame.health, STATE_TINT.DEAD)
        SetFill(frame.health, 1)
    elseif execute then
        SetBarTint(frame.health, STATE_TINT.EXECUTE)
    else
        local mode = DB("HealthBarColor", "VALUE")
        if mode == "CLASS" then
            local r, g, b = ClassTint(entry.class)
            SetBarTint(frame.health, { r, g, b })
        elseif mode == "VALUE" then
            SetBarTint(frame.health, { HealthTint(fraction) })
        else
            SetBarTint(frame.health, { 0.72, 0.24, 0.24 })
        end
    end
    frame.healthText:SetText(dead and "DEAD" or HealthLabel(health, maxHealth))

    if DB("PowerBar", true) then
        local powerType = T and T.powerType or UnitPowerType(unit) or 0
        local maxPower = T and T.powerMax or UnitPowerMax(unit) or 0
        local power = T and T.power or UnitPower(unit) or 0
        SetFill(frame.power, maxPower > 0 and (power / maxPower) or 0)
        if DB("PowerBarColor", "TYPE") == "CLASS" then
            local r, g, b = ClassTint(entry.class)
            SetBarTint(frame.power, { r, g, b })
        else
            SetBarTint(frame.power, POWER_TINT[powerType] or POWER_TINT[0])
        end
        local mode = DB("PowerText", "MANA")
        if mode == "ALL" or (mode == "MANA" and powerType == 0) then
            frame.powerText:Show()
            frame.powerText:SetText(maxPower > 0
                and (math.floor(power / maxPower * 100 + 0.5) .. "%") or "")
        else
            frame.powerText:Hide()
        end
    end
end

local function PaintCast(frame, entry, now)
    if not DB("CastBar", true) then
        frame.cast:Hide()
        return
    end
    local unit = entry.unit
    local T = entry.test
    local name, icon, startTime, endTime, channeling
    if T then
        name, icon, startTime, endTime = T.castName, T.castIcon, T.castStart, T.castEnd
        channeling = T.channel
    else
        local _
        name, _, icon, startTime, endTime = UnitCastingInfo(unit)
        channeling = false
        if not name then
            name, _, icon, startTime, endTime = UnitChannelInfo(unit)
            channeling = name and true or false
        end
    end
    if not name or not startTime or not endTime then
        frame.cast:Hide()
        return
    end
    -- Laid over the health bar, the cast bar and the state strip write on
    -- the same line, and two labels on one line is neither. The strip wins:
    -- a sapped, silenced or untouchable enemy is not casting anything that
    -- matters more than that, and the fill can come back when it clears.
    if frame.cast.wash:IsShown() and frame.state:IsShown() then
        frame.cast:Hide()
        return
    end
    frame.cast:Show()
    local total = (endTime - startTime) / 1000
    local elapsed = now - startTime / 1000
    local fraction = total > 0 and (elapsed / total) or 0
    -- A channel DRAINS: what is left is what you still have time to stop.
    SetFill(frame.cast.bar, channeling and (1 - fraction) or fraction)
    SetBarTint(frame.cast.bar, channeling and STATE_TINT.CHANNEL or STATE_TINT.CAST)
    -- The spark sits on the fill's edge, and goes with the fill when there
    -- is no edge to sit on.
    frame.cast.spark:SetShown(DB("CastSpark", true) and frame.cast.bar.fill:IsShown())
    if DB("CastIcon", true) and icon then frame.cast.icon:SetTexture(icon) end
    local label = DB("CastText", true) and name or ""
    if DB("CastTarget", false) and not T then
        -- There is no API for "what is that player's spell aimed at", so this
        -- is their TARGET -- right for a direct cast, wrong for a smart heal,
        -- and the setting's own tooltip says so rather than letting the row
        -- imply a certainty it does not have.
        local castTarget = unit .. "target"
        if UnitExists(castTarget) then
            local targetName = UnitName(castTarget)
            if targetName then
                label = (label ~= "" and (label .. " ") or "")
                    .. "|cff9a9a9a> " .. targetName .. "|r"
            end
        end
    end
    frame.cast.label:SetText(label)
    if DB("CastTimer", true) then
        local left = math.max(0, (endTime / 1000) - now)
        frame.cast.timer:SetText(string.format("%.1f", left))
    else
        frame.cast.timer:SetText("")
    end
    -- Only laid out and shown in OVERLAY mode, where the cast bar is sitting
    -- on the health bar and has taken the number with it.
    if frame.cast.hp:IsShown() then
        frame.cast.hp:SetText(HealthLabel(ReadHealth(entry)))
        frame.cast.hp:SetTextColor(0.80, 0.80, 0.82)
    end
end

-- The bracket ladder, as it reads on a 20-pixel slot. Three cues so it
-- survives a glance and colourblindness alike: the rim colour, the fraction
-- itself, and (when it is counting) the seconds to reset.
local BRACKET_LABEL = { [1] = "", [2] = "1/2", [3] = "1/4", [4] = "IMM" }
local BRACKET_RIM = {
    [1] = { 0.45, 0.85, 0.45 },   -- full: they will eat the whole thing
    [2] = { 0.95, 0.85, 0.35 },
    [3] = { 0.98, 0.58, 0.25 },
    [4] = { 0.92, 0.24, 0.24 },   -- immune: do not spend it
}

local drScratch = {}

local function PaintDR(frame, entry, now)
    if not DB("DR", true) then return end
    local rows_ = dr:Open(entry.guid, now, drScratch)
    local slotIndex = 0
    local maxSlots = math.min(DB("DRMax", 5), #frame.drSlots)
    local showText = DB("DRText", true)
    local showTimer = DB("DRTimer", true)
    local holdColor = DB("DRHoldColor", true)

    for _, info in ipairs(rows_) do
        if slotIndex >= maxSlots then break end
        if CommanderArenaFrames_DRTracked(info.cat) then
            slotIndex = slotIndex + 1
            local slot = frame.drSlots[slotIndex]
            slot:Show()

            local icon = info.last and GetSpellTexture and GetSpellTexture(info.last)
            slot.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")

            local tint = CommanderArenaFrames_DRTint[info.cat] or { 1, 1, 1 }
            slot.icon:SetVertexColor(tint[1], tint[2], tint[3])

            local rim = BRACKET_RIM[info.bracket] or BRACKET_RIM[1]
            slot.rim:SetVertexColor(rim[1], rim[2], rim[3], 0.9)

            slot.text:SetText(showText and (BRACKET_LABEL[info.bracket] or "") or "")
            slot.text:SetTextColor(rim[1], rim[2], rim[3])

            -- A held category and a finished one both have no timer, and they
            -- mean opposite things: held is "the clock has not started", clear
            -- is "the clock ran out". The tint is what tells them apart.
            if info.held then
                -- "ON": the aura is on them and the clock has not started.
                -- Two letters, because "HELD" spills off an 18-pixel icon.
                slot.sub:SetText(showTimer and "ON" or "")
                if holdColor then
                    slot.icon:SetVertexColor(tint[1] * 0.6, tint[2] * 0.6, tint[3] * 1.0)
                end
                -- Held: the clock has not started, so there is nothing to sweep.
                SetSweep(slot, nil)
            elseif info.resetAt then
                slot.sub:SetText(showTimer and E.FormatTime(info.resetAt - now) or "")
                -- The reset clock as a face: what is left of the fifteen
                -- seconds before this bracket goes back to full.
                SetSweep(slot, info.resetAt, DATA.DR_RESET)
            else
                slot.sub:SetText("")
                SetSweep(slot, nil)
            end
            slot.sub:SetTextColor(0.85, 0.85, 0.85)
        end
    end
    for i = slotIndex + 1, #frame.drSlots do frame.drSlots[i]:Hide() end
end

local cdScratch = {}

local function PaintCooldowns(frame, entry, now)
    if not DB("Cooldowns", true) or not entry.class then return end
    local roles = DB("CooldownRoles", NO_ROLES)
    local unseenMode = DB("CooldownUnseen", "GHOST")
    local showText = DB("CooldownText", true)
    local strip = book:Strip(entry.guid, entry.class, entry.race, now, cdScratch)
    local slotIndex = 0

    for _, info in ipairs(strip) do
        if slotIndex >= #frame.cdSlots then break end
        local wanted = roles[info.role]
            and CommanderArenaFrames_CooldownTracked(entry.class, info.name)
        if wanted and info.unseen and unseenMode == "HIDE" then wanted = false end
        if wanted then
            slotIndex = slotIndex + 1
            local slot = frame.cdSlots[slotIndex]
            slot:Show()
            slot.icon:SetTexture((GetSpellTexture and GetSpellTexture(info.id))
                or "Interface\\Icons\\INV_Misc_QuestionMark")

            local tint = CommanderArenaFrames_RoleTint[info.role] or { 1, 1, 1 }
            local pulsing = ReadyPulse(slot, entry.guid, info.remaining and true or false, now)
            if not pulsing then
                slot.rim:SetVertexColor(tint[1], tint[2], tint[3], 0.75)
            end

            if info.remaining then
                slot.icon:SetVertexColor(0.42, 0.42, 0.42)
                slot.icon:SetDesaturated(true)
                slot.text:SetText(showText and E.FormatSlotTime(info.remaining) or "")
                slot.text:SetTextColor(1, 0.82, 0)
                -- The clock face over the icon: how much of the cooldown is
                -- still to run, readable before the number is.
                SetSweep(slot, now + info.remaining, info.entry and info.entry.cd)
            elseif info.unseen and unseenMode == "GHOST" then
                SetSweep(slot, nil)
                -- Never seen used. Deliberately NOT drawn as ready: "we have
                -- not seen their Ice Block" and "their Ice Block is up" are
                -- different bets, and a board that shows them the same is
                -- claiming knowledge it does not have.
                slot.icon:SetVertexColor(0.55, 0.55, 0.55)
                slot.icon:SetDesaturated(true)
                slot.text:SetText("")
                if not pulsing then
                    slot.rim:SetVertexColor(tint[1], tint[2], tint[3], 0.2)
                end
            else
                slot.icon:SetVertexColor(1, 1, 1)
                slot.icon:SetDesaturated(false)
                slot.text:SetText("")
                SetSweep(slot, nil)
            end
            slot.sub:SetText("")
        end
    end
    for i = slotIndex + 1, #frame.cdSlots do frame.cdSlots[i]:Hide() end
end

local function PaintAuras(frame, entry, now)
    if not DB("Auras", true) then return end
    local maxSlots = math.min(DB("AuraMax", 5), #frame.auraSlots)
    local shown = 0
    for _, aura in ipairs(entry.notes) do
        if shown >= maxSlots then break end
        shown = shown + 1
        local slot = frame.auraSlots[shown]
        slot:Show()
        slot.icon:SetTexture(aura.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        slot.icon:SetVertexColor(1, 1, 1)
        slot.icon:SetDesaturated(false)
        -- Control first, in its own colour and at full strength: on a strip
        -- that also carries the enemy's buffs, the one aura that says they
        -- cannot act should not have to be found. A debuff YOU applied is
        -- next, because that is the part you are steering.
        if aura.control then
            local tint = E.ControlTint(aura.control)
            slot.rim:SetVertexColor(tint[1], tint[2], tint[3], 1)
        elseif aura.helpful then
            slot.rim:SetVertexColor(0.45, 0.70, 0.98, 0.7)
        elseif aura.mine then
            slot.rim:SetVertexColor(0.98, 0.85, 0.35, 0.95)
        else
            slot.rim:SetVertexColor(0.7, 0.35, 0.35, 0.6)
        end
        if aura.expires and aura.expires > 0 then
            slot.text:SetText(E.FormatSlotTime(aura.expires - now))
            SetSweep(slot, aura.expires, aura.duration)
        else
            slot.text:SetText("")
            SetSweep(slot, nil)
        end
        slot.sub:SetText((aura.count and aura.count > 1) and tostring(aura.count) or "")
    end
    for i = shown + 1, #frame.auraSlots do frame.auraSlots[i]:Hide() end
end

local function PaintTrinket(frame, entry, now)
    if not DB("Trinket", true) then
        frame.trinket:Hide()
        return
    end
    local record = trinket[entry.guid]
    frame.trinket:Show()
    if not record or not record.spellId then
        -- Nothing reported yet. Shown as an empty socket rather than hidden,
        -- so the row's shape never changes when the answer arrives.
        frame.trinket.icon:SetTexture("Interface\\Icons\\INV_Jewelry_TrinketPVP_01")
        frame.trinket.icon:SetDesaturated(true)
        frame.trinket.icon:SetVertexColor(0.4, 0.4, 0.4)
        frame.trinket.text:SetText("")
        frame.trinket.rim:SetVertexColor(1, 1, 1, 0.15)
        SetSweep(frame.trinket, nil)
        return
    end
    frame.trinket.icon:SetTexture((GetSpellTexture and GetSpellTexture(record.spellId))
        or "Interface\\Icons\\INV_Jewelry_TrinketPVP_01")
    local left = record.readyAt and (record.readyAt - now) or nil
    local down = (left and left > 0) and true or false
    local pulsing = ReadyPulse(frame.trinket, entry.guid, down, now)
    if down then
        frame.trinket.icon:SetDesaturated(true)
        frame.trinket.icon:SetVertexColor(0.45, 0.45, 0.45)
        frame.trinket.text:SetText(E.FormatSlotTime(left))
        frame.trinket.text:SetTextColor(1, 0.82, 0)
        if not pulsing then frame.trinket.rim:SetVertexColor(0.9, 0.3, 0.3, 0.8) end
        SetSweep(frame.trinket, record.readyAt, record.cd or 120)
    else
        frame.trinket.icon:SetDesaturated(false)
        frame.trinket.icon:SetVertexColor(1, 1, 1)
        frame.trinket.text:SetText("")
        if not pulsing then frame.trinket.rim:SetVertexColor(0.4, 0.95, 0.45, 0.85) end
        SetSweep(frame.trinket, nil)
    end
end

-- The state strip. Five things earn it, and every one of them is "stop what
-- you are doing" rather than "be aware of".
--
-- CROWD CONTROL LEADS, and that ordering is the point of the whole element.
-- Who is sapped, who is feared, who is in a trap and for how much longer is
-- the question an arena board is consulted about more than any other, and it
-- used to be answerable here only by finding a 16-pixel icon at the bottom of
-- a strip that sorted it last. Now it is a bar across the enemy's own health
-- with the word on it and a clock running down.
--
-- The rest of the ladder, and why:
--   IMMUNE   above a lockout: do not spend the cooldown at all beats spend it
--            now. It is also the only state on this list you can walk into
--            from full tempo.
--   SILENCE  above a drink, because it is a window with a short clock you
--            have to act INSIDE. TBC gives silence no diminishing returns, so
--            this is also the one state the DR ladder can never show.
--   DRINK    they are out of the game for as long as you allow.
--   STEALTH  the slot stays, the enemy does not.
--
-- Roots and disarms are not here on purpose -- see ScanAuras.
local BRACKET_ARROW = { [1] = "", [2] = "|cffe0d45f>1/2|r", [3] = "|cfffa9440>1/4|r", [4] = "|cffeb3b3b>IMM|r" }

-- A state whose own clock has run out, and which the scan has not been able
-- to clear. That happens for real: the scan bails out on a unit the client
-- will not answer for, deliberately, so the strip keeps its last known state
-- rather than blanking on the enemy who just went out of sight. Without this
-- an expired one would then sit on the row for the rest of the match with no
-- timer under it, which is the same bug wearing a different hat.
local function Lapsed(record, now)
    if not record then return true end
    local expires = record.expires
    return expires ~= nil and expires > 0 and expires <= now
end

-- The class square, borrowed for the control that is on them. Independent of
-- the banner's ladder on purpose: an immunity outranks a lockout on the bar,
-- but a locked-out healer inside a bubble is still locked out, and the square
-- is where that stays readable.
local function PaintControlIcon(frame, control, now)
    local box = frame.ccBox
    if not control or not DB("ShowClassIcon", true) or not DB("CCOnClassIcon", true) then
        if box:IsShown() then
            box:Hide()
            SetSweep(box, nil)
        end
        return
    end
    box:Show()
    frame.classIcon:Hide()
    box.icon:SetTexture(control.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    box.icon:SetVertexColor(1, 1, 1)
    box.icon:SetDesaturated(false)
    local tint = E.ControlTint(control.kind)
    box.rim:SetVertexColor(tint[1], tint[2], tint[3], 1)

    local left = control.expires and control.expires > 0 and (control.expires - now) or nil
    box.text:SetText(left and E.FormatSlotTime(left) or "")
    box.text:SetTextColor(1, 1, 1)
    box.sub:SetText("")

    -- `duration` is the length the aura actually landed at, so a half-bracket
    -- Polymorph starts the sweep at half and does not pretend to be a full one.
    SetSweep(box, left and control.expires or nil, control.duration)
end

local function PaintState(frame, entry, now)
    local o = frame.state
    local control = not Lapsed(entry.control, now) and entry.control or nil
    PaintControlIcon(frame, control, now)
    local immunity = not Lapsed(entry.immunity, now) and entry.immunity or nil
    local drinking = not Lapsed(entry.drinking, now) and entry.drinking or nil
    local ccOn = DB("CCBanner", true)
    local kind, label, icon, expires, duration, tint

    if control and ccOn and control.kind == "FULL" then
        kind, label, icon = "CONTROL", control.word, control.icon
        expires, duration = control.expires, control.duration
        tint = E.ControlTint("FULL")
    elseif immunity and DB("ImmunityBanner", true) then
        kind, label, icon = "IMMUNE", immunity.note.label, immunity.icon
        expires, duration = immunity.expires, immunity.duration
        tint = STATE_TINT.IMMUNE
    elseif control and ccOn then
        kind, label, icon = "SILENCE", control.word, control.icon
        expires, duration = control.expires, control.duration
        tint = E.ControlTint(control.kind)
    elseif drinking and DB("DrinkBanner", true) then
        kind, label, icon = "DRINK", "DRINKING", drinking.icon
        expires = drinking.expires
        tint = STATE_TINT.DRINK
    elseif entry.stealth and DB("StealthBanner", true) then
        kind, label = "STEALTH", "STEALTHED"
        icon = type(entry.stealth) == "table" and entry.stealth.icon or nil
        tint = STATE_TINT.STEALTH
    end

    -- The word takes the name's place on the bar and the clock sits beside
    -- the health number; the number itself is the row's own, untouched.
    frame.name:SetShown(DB("ShowName", true) and not kind)
    frame.spec:SetShown((DB("ShowSpec", true) or DB("ShowRace", false)) and not kind)
    if not kind then
        o:Hide()
        return
    end
    o:Show()

    -- The clock. `duration` is what the aura ACTUALLY landed at -- already
    -- capped and already diminished -- so the drain is honest about a second
    -- Polymorph being half a bar rather than drawing it as a full one that
    -- empties twice as fast.
    local left = expires and expires > 0 and (expires - now) or nil
    local fraction
    if left and duration and duration > 0 then
        fraction = left / duration
    end
    SetOverlay(o, tint, fraction)

    -- The label starts after the icon, so a strip with no icon to show has to
    -- reclaim the space rather than leave a square hole where one would be.
    -- Re-anchored only on the frames where it actually changes.
    -- ...and it does not repeat the icon the class square is already
    -- carrying: the word and the clock are what the bar is for.
    if icon and frame.ccBox:IsShown() and control and icon == control.icon then
        icon = nil
    end
    local hasIcon = icon and true or false
    if hasIcon then o.icon:SetTexture(icon) end
    o.icon:SetShown(hasIcon)
    if o._hadIcon ~= hasIcon then
        o._hadIcon = hasIcon
        o.label:SetPoint("LEFT", o, "LEFT", hasIcon and o._labelInset or o._flushInset, 0)
    end

    -- What the NEXT one in this category would land at, which is the question
    -- being asked the whole time a CC is running: can I re-stun out of this,
    -- or is the next one a quarter and not worth the setup. The tracker
    -- already counted this application, so the bracket shown is genuinely the
    -- next cast rather than this one.
    local suffix = ""
    if control and kind ~= "IMMUNE" and control.cat and DB("CCNextBracket", true) then
        suffix = BRACKET_ARROW[dr:Bracket(entry.guid, control.cat, now)] or ""
        if suffix ~= "" then suffix = "  " .. suffix end
    end
    o.label:SetText((label or "") .. suffix)
    o.timer:SetText(left and E.FormatTime(left) or "")

    -- Invisible: only here so the timer anchors beside the row's own number
    o.hp:SetText(HealthLabel(ReadHealth(entry)))
end

-- Who this enemy is on. There is no API for "what is that player's spell
-- aimed at", so the honest reading is their TARGET -- right for a direct cast,
-- wrong for a smart heal, and said plainly in the setting's own tooltip.
local function PaintTargetOf(frame, entry)
    if entry.test then
        frame.targetOf:Hide()
        return
    end
    local showAll = DB("ShowTargetOf", false)
    local flagSelf = DB("ShowTargetOfSelf", true)
    if not (showAll or flagSelf) then
        frame.targetOf:Hide()
        return
    end
    local targetUnit = entry.unit .. "target"
    if not UnitExists(targetUnit) then
        frame.targetOf:Hide()
        return
    end
    local onMe = UnitIsUnit(targetUnit, "player")
    if not showAll and not (onMe and flagSelf) then
        frame.targetOf:Hide()
        return
    end
    local _, classToken = UnitClass(targetUnit)
    SetClassIcon(frame.targetOf, classToken)
    -- The one case worth interrupting attention for gets a colour of its own;
    -- everyone else's icon stays plain.
    if onMe then
        frame.targetOf:SetVertexColor(1, 0.35, 0.35)
    else
        frame.targetOf:SetVertexColor(1, 1, 1)
    end
end

-- The enemy's pet, read off its own token. `arenapetN` is arenaN's pet; the
-- family ("Felhunter", "Succubus") is the name that matters, because the
-- pet's own name is whatever the warlock's random generator said.
local PET_TINT = { 0.55, 0.78, 0.45 }
local function PaintPet(frame, entry, now)
    if not frame._petOn then return end
    local pet = frame.pet
    local T = entry.test and entry.test.pet
    local unit = "arenapet" .. (entry.index or 0)
    local exists = T or UnitExists(unit)
    if not exists then
        SetFill(pet.bar, 0)
        pet.name:SetText("no pet")
        pet.name:SetTextColor(0.5, 0.5, 0.52)
        pet.text:SetText("")
        return
    end
    local label, health, maximum, dead
    if T then
        label, health, maximum = T.name, T.health, T.healthMax
    else
        label = (UnitCreatureFamily and UnitCreatureFamily(unit)) or UnitName(unit) or "Pet"
        health, maximum = UnitHealth(unit) or 0, UnitHealthMax(unit) or 0
        dead = UnitIsDeadOrGhost(unit)
    end
    local fraction = (maximum and maximum > 0) and (health / maximum) or 0
    -- Cut long, not to the name budget: "Water Elemental" is the family and
    -- the family is the whole message.
    pet.name:SetText(TrimName(label, 18))
    if dead then
        SetFill(pet.bar, 1)
        SetBarTint(pet.bar, STATE_TINT.DEAD)
        pet.name:SetTextColor(0.6, 0.6, 0.6)
        pet.text:SetText("DEAD")
    else
        SetFill(pet.bar, fraction)
        SetBarTint(pet.bar, PET_TINT)
        pet.name:SetTextColor(1, 1, 1)
        pet.text:SetText(math.floor(fraction * 100 + 0.5) .. "%")
    end
    pet.text:SetTextColor(1, 1, 1)
end

local function PaintHighlights(frame, entry, now)
    local unit = entry.unit
    local tint
    if entry.test then
        tint = entry.test.ring and STATE_TINT[entry.test.ring] or nil
    elseif DB("TargetHighlight", true) and UnitIsUnit(unit, "target") then
        tint = STATE_TINT.TARGET
    elseif DB("FocusHighlight", true) and UnitExists("focus") and UnitIsUnit(unit, "focus") then
        tint = STATE_TINT.FOCUS
    end
    if tint then
        frame.ring:SetVertexColor(tint[1], tint[2], tint[3], 1)
        frame.ring:Show()
    else
        frame.ring:Hide()
    end

    local until_ = flash[entry.guid]
    if until_ and until_ > now then
        -- A short pulse rather than a steady wash: a steady one becomes part
        -- of the board within a second and stops being an alert.
        local pulse = 0.5 + 0.5 * math.sin((until_ - now) * 18)
        frame.flash:Show()
        frame.flash:SetVertexColor(1, 0.85, 0.3, 0.16 + 0.20 * pulse)
    else
        frame.flash:Hide()
        if until_ then flash[entry.guid] = nil end
    end
end

local function PaintRow(frame, entry, now)
    PaintIdentity(frame, entry)
    PaintVitals(frame, entry, now)
    -- The state before the cast: an overlaid cast bar yields to the strip,
    -- so the strip has to have decided first.
    PaintState(frame, entry, now)
    PaintCast(frame, entry, now)
    PaintDR(frame, entry, now)
    PaintCooldowns(frame, entry, now)
    PaintAuras(frame, entry, now)
    PaintTrinket(frame, entry, now)
    PaintTargetOf(frame, entry)
    PaintPet(frame, entry, now)
    PaintHighlights(frame, entry, now)

    -- Whole-row alpha, cheapest signal last. Dead outranks out-of-range: a
    -- corpse is not somewhere you failed to reach.
    local alpha = 1
    if entry.test then
        alpha = entry.test.alpha or 1
    elseif DB("DeadFade", true) and UnitIsDeadOrGhost(entry.unit) then
        alpha = 0.35
    end
    -- Range fade used to live here, over CheckInteractDistance. That function
    -- is PROTECTED on this client (2.5.6): the call is blocked and returns
    -- nothing, and the test was `not inRange` -- so a blocked call read as OUT
    -- of range and every enemy row was faded, permanently, while the paint path
    -- raised ADDON_ACTION_BLOCKED. The feature was not degraded, it was
    -- inverted. It stays out until there is an unprotected way to range an
    -- ENEMY in combat, which UnitInRange (group only) and IsItemInRange
    -- (refused on friendlies in combat, and these are not friendlies) are not.
    frame:SetAlpha(alpha)
end

-- ---------------------------------------------------------------------------
-- The row tooltip. Three answers, and the default is the middle one.
--
-- FULL is the game's unit tooltip with the board's notes under it. EXTRAS
-- drops the unit half, because a row that is already showing the name, the
-- class, the health and the auras has little to gain from a box repeating
-- them -- what it cannot show at a glance is the FULL ladder and the FULL
-- cooldown book, which is what this adds. OFF shows nothing.
--
-- None of the three touches the secure unit attribute.
-- ---------------------------------------------------------------------------

local tipDR, tipCD = {}, {}

function ShowRowTooltip(frame)
    local mode = DB("RowTooltip", "EXTRAS")
    if mode == "OFF" then return end
    -- Whatever this slot most recently PAINTED, which is the only reliable
    -- answer: under a live sort the row's slot and the seat's own index
    -- diverge, so deriving the seat from the slot number finds the wrong
    -- enemy exactly when the board is busiest.
    local entry = frame._entry
    if not entry or not entry.guid then return end

    local now = GetTime()
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    if mode == "FULL" and UnitExists(entry.unit) then
        GameTooltip:SetUnit(entry.unit)
        GameTooltip:AddLine(" ")
    else
        GameTooltip:SetText(entry.name or "Enemy", 1, 1, 1)
        local r, g, b = ClassTint(entry.class)
        GameTooltip:AddLine(string.format("%s%s", entry.class or "?",
            entry.spec and (" / " .. entry.spec) or ""), r, g, b)
    end

    if not entry.spec then
        GameTooltip:AddLine("Specialization not yet revealed.", 0.6, 0.6, 0.6)
    end

    -- Control first, because it is the only line here with a clock running.
    local control = entry.control
    if control and (not control.expires or control.expires <= 0 or control.expires > now) then
        local tint = E.ControlTint(control.kind)
        local left = control.expires and control.expires > 0 and (control.expires - now)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(
            string.format("%s -- %s", control.word, control.name or "?"),
            left and E.FormatTime(left) or "", tint[1], tint[2], tint[3], 1, 1, 1)
        if control.cat then
            local bracket = dr:Bracket(entry.guid, control.cat, now)
            local rim = BRACKET_RIM[bracket] or BRACKET_RIM[1]
            GameTooltip:AddLine(string.format("   next %s lands at %s", control.cat,
                bracket == 1 and "full" or (BRACKET_LABEL[bracket] or "?")),
                rim[1], rim[2], rim[3])
        else
            GameTooltip:AddLine("   no diminishing returns on this in TBC", 0.6, 0.6, 0.6)
        end
    end

    local open = dr:Open(entry.guid, now, tipDR)
    if #open > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Diminishing returns", 1, 0.82, 0)
        for _, info in ipairs(open) do
            local right
            if info.held then
                right = "held"
            elseif info.resetAt then
                right = "resets " .. E.FormatTime(info.resetAt - now)
            else
                right = ""
            end
            local rim = BRACKET_RIM[info.bracket] or BRACKET_RIM[1]
            GameTooltip:AddDoubleLine(
                string.format("%s  %s", info.cat, BRACKET_LABEL[info.bracket] or "full"),
                right, rim[1], rim[2], rim[3], 0.8, 0.8, 0.8)
        end
    end

    if entry.class then
        local spent = {}
        for _, info in ipairs(book:Strip(entry.guid, entry.class, entry.race, now, tipCD)) do
            if info.remaining then spent[#spent + 1] = info end
        end
        if #spent > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("On cooldown", 1, 0.82, 0)
            for _, info in ipairs(spent) do
                GameTooltip:AddDoubleLine(info.name, E.FormatTime(info.remaining),
                    0.9, 0.9, 0.9, 1, 0.82, 0)
                if info.entry.talent then
                    GameTooltip:AddLine(string.format("   %s can shorten this",
                        info.entry.talent), 0.55, 0.55, 0.55)
                end
            end
        end
    end

    local record = trinket[entry.guid]
    if record and record.spellId then
        GameTooltip:AddLine(" ")
        local left = record.readyAt and (record.readyAt - now)
        if left and left > 0 then
            GameTooltip:AddDoubleLine("Trinket", E.FormatTime(left), 0.9, 0.5, 0.5, 1, 0.82, 0)
        else
            GameTooltip:AddDoubleLine("Trinket", "ready", 0.9, 0.9, 0.9, 0.4, 0.95, 0.45)
        end
    end

    GameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- Blizzard's own arena frames. Hidden rather than removed, and given straight
-- back the moment this module is switched off -- an addon that permanently
-- disables part of the default UI has made a decision that is not its to make.
-- ---------------------------------------------------------------------------

local blizzHidden = false

-- The CVar's value from BEFORE this module first touched it. Kept in the saved
-- variables rather than in a local, because a local is lost on /reload -- and
-- the failure that causes is the one no addon is allowed to have: the player
-- switches the module off, the CVar is still 0 from a previous session with
-- nothing left that remembers what it used to be, and Blizzard's own arena
-- frames are gone for good with no way to explain why.
local function BlizzRestoreValue()
    local db = CommanderArenaFramesDB
    return db and db.BlizzArenaCVar
end

local function SetBlizzRestoreValue(value)
    if CommanderArenaFramesDB then CommanderArenaFramesDB.BlizzArenaCVar = value end
end

local function ApplyBlizzardFrames()
    local want = Enabled() and DB("HideBlizzardArena", true)
    if want == blizzHidden then return end
    -- Container names differ between UI revisions and the arena UI is a
    -- load-on-demand addon, so every step is guarded: a client that never had
    -- these frames must lose nothing.
    for _, name in ipairs({ "ArenaEnemyFrames", "ArenaPrepFrames", "ArenaEnemyPrepFrames" }) do
        local frame = _G[name]
        if frame then
            if want then
                if not InCombat() then
                    frame:Hide()
                    frame._commanderHidden = true
                end
            elseif frame._commanderHidden then
                frame._commanderHidden = nil
                if not InCombat() then frame:Show() end
            end
        end
    end
    -- The CVar is the part that actually stops them being rebuilt. Saved and
    -- restored rather than forced, so a player who had them off keeps them off.
    if SetCVar and GetCVar then
        if want then
            if BlizzRestoreValue() == nil then
                local ok, current = pcall(GetCVar, "showArenaEnemyFrames")
                -- "1" as the fallback is deliberate: it is the shipped default,
                -- so a client that will not answer still gets its frames back.
                SetBlizzRestoreValue((ok and current) or "1")
            end
            pcall(SetCVar, "showArenaEnemyFrames", "0")
        else
            local saved = BlizzRestoreValue()
            if saved ~= nil then
                pcall(SetCVar, "showArenaEnemyFrames", saved)
                SetBlizzRestoreValue(nil)
            end
        end
    end
    blizzHidden = want
end

-- ---------------------------------------------------------------------------
-- The draw. Everything above produces state; this decides what is on screen.
-- ---------------------------------------------------------------------------

local layoutDirty = true
local order = {}

-- Can the board be RESHAPED right now -- resized, re-anchored, re-laid out?
--
-- With click-cast on, every row is a SecureActionButton and therefore a
-- PROTECTED frame, and the client refuses SetPoint, SetWidth and SetHeight on
-- one of those once a fight has started. Painting is untouched (textures and
-- fontstrings are never protected), so the board keeps updating at full speed;
-- only its geometry has to wait. Nothing needs queueing beyond a flag:
-- PLAYER_REGEN_ENABLED marks the layout dirty and the next draw finishes the
-- job.
--
-- Without click-cast the rows are plain frames, nothing is protected, and this
-- is always true.
local function CanReshape()
    return not (securePool and InCombat())
end

local function ActiveSeats(now)
    for i = #order, 1, -1 do order[i] = nil end
    if now < testUntil then
        for _, unit in ipairs(ARENA_UNITS) do
            local entry = seat[unit]
            if entry and entry.test then
                -- Re-arm the fabricated clocks so the test board stays a full
                -- board for its whole thirty seconds. A Sap that really lasts
                -- ten of them would leave the strip -- the element the board
                -- is being placed AROUND -- blank for the last twenty.
                local control = entry.control
                if control and control.expires and control.expires <= now then
                    control.expires = now + (control.duration or 10)
                    for _, note in ipairs(entry.notes) do
                        if note.id == control.id then note.expires = control.expires end
                    end
                end
                if entry.immunity and entry.immunity.expires
                    and entry.immunity.expires <= now then
                    entry.immunity.expires = now + (entry.immunity.duration or 10)
                end
                order[#order + 1] = entry
            end
        end
        return order
    end
    for index = 1, math.min(liveCount, MAX_ENEMIES) do
        local entry = seat[ARENA_UNITS[index]]
        if entry and (entry.exists or entry.prep) then order[#order + 1] = entry end
    end

    -- A live sort and click-cast are incompatible, and the failure is the bad
    -- kind: a secure row's unit attribute is bound once, out of combat, to a
    -- RAW token, so re-ordering the art over it would leave a row showing one
    -- enemy and TARGETING another. The client will not let the attribute be
    -- rewritten mid-fight to fix it, so the order is pinned instead.
    local mode = securePool and "FIXED" or DB("SortMode", "FIXED")
    if mode == "HEALTH" then
        -- Keyed once per seat rather than read inside the comparator: a sort
        -- calls its comparator O(n log n) times and the old one made four unit
        -- reads per call. It also has to be STABLE against a unit answering
        -- differently mid-sort -- table.sort raises "invalid order function"
        -- on an inconsistent comparator, which would take the draw down.
        for _, entry in ipairs(order) do
            local maximum = UnitHealthMax(entry.unit) or 0
            entry._sortKey = maximum > 0 and ((UnitHealth(entry.unit) or 0) / maximum) or 1
        end
        table.sort(order, function(a, b)
            if a._sortKey ~= b._sortKey then return a._sortKey < b._sortKey end
            return (a.index or 0) < (b.index or 0)
        end)
    elseif mode == "ROLE" then
        -- Healers first. "Healer" is only knowable once a spec has been
        -- proven, so before that everyone keeps their slot -- which is the
        -- same honesty the spec label itself is held to.
        local HEALER = { Holy = true, Disc = true, Resto = true }
        table.sort(order, function(a, b)
            local ra = (a.spec and HEALER[a.spec]) and 0 or 1
            local rb = (b.spec and HEALER[b.spec]) and 0 or 1
            if ra ~= rb then return ra < rb end
            return (a.index or 0) < (b.index or 0)
        end)
    end
    return order
end

local function Draw()
    if not Enabled() then
        SafeSetShown(root, false)
        return
    end
    local now = GetTime()
    local list = ActiveSeats(now)

    if #list == 0 then
        SafeSetShown(root, false)
        return
    end
    if DB("CombatOnly", false) and now >= testUntil and not InCombat() then
        SafeSetShown(root, false)
        return
    end

    local down = DB("Grow", "DOWN") == "DOWN"

    -- Density is decided by how many enemies are actually on the board, which
    -- is the whole point: the same settings that read well against two enemies
    -- are half a screen against five.
    local mode = DB("Density", "AUTO")
    if mode == "AUTO" then
        mode = (#list >= AUTO_TIGHT_AT) and "TIGHT" or "ROOMY"
    end
    local scale = DENSITY_SCALE[mode] or 1
    local spacing = math.floor(DB("RowSpacing", 6) * (DENSITY_SPACING[mode] or 1) + 0.5)
    local offset, width = 0, DB("FrameWidth", 200)
    local reshape = CanReshape()
    local deferred = false

    for slot, entry in ipairs(list) do
        local frame = rows[slot]
        if not frame then
            -- Only reachable in insecure mode: the secure pool is built whole
            -- at login, precisely so this can never happen mid-fight.
            if securePool and InCombat() then
                -- Cannot build a secure row mid-fight. Leave the layout dirty
                -- so the next draw after combat finishes the job.
                return
            end
            frame = NewRow(slot)
            rows[slot] = frame
        end
        -- Shape is recomputed when a setting changed, or when this slot is
        -- showing a different enemy KIND than it was. Class and race both
        -- count: the cooldown strip is the enemy's book, and racials ride it,
        -- so two mages of different races have strips of different lengths.
        -- The density is part of the shape key: going from a 3v3 to a 5v5
        -- changes every dimension on the row, and a cached layout would carry
        -- the roomy one into the tight board.
        local kind = (entry.class or "?") .. "/" .. (entry.race or "?") .. "/" .. mode
        if layoutDirty or frame._kind ~= kind then
            if reshape then
                frame._kind = kind
                LayoutRow(frame, entry, scale)
            else
                deferred = true
            end
        end
        -- UNIT_AURA is the mechanism and it is reliable, but it says nothing
        -- about auras that were already up when the board first saw this
        -- enemy -- the opener's Ice Block, a pre-cast Barrier. A once-a-second
        -- sweep costs nothing at five units and removes the whole class of
        -- "the board did not notice it was already there".
        if not entry.test and (not entry.scanAt or (now - entry.scanAt) > AURA_RESCAN) then
            ScanAuras(entry)
        end
        -- Re-anchored only when the position actually changed. Under the
        -- default fixed order that is once, at the start of a game -- which
        -- is what keeps a protected row from needing a forbidden SetPoint on
        -- every frame of a fight.
        if frame._offset ~= offset or frame._grow ~= down then
            if reshape then
                frame._offset, frame._grow = offset, down
                frame:ClearAllPoints()
                if down then
                    frame:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -offset)
                else
                    frame:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, offset)
                end
            else
                deferred = true
            end
        end
        offset = offset + (frame:GetHeight() or 0) + spacing
        frame._entry = entry
        PaintRow(frame, entry, now)
        SafeSetShown(frame, true)
    end
    for slot = #list + 1, #rows do
        SafeSetShown(rows[slot], false)
    end

    -- Anything that had to wait keeps the board dirty, so the first draw
    -- after combat picks it up rather than the change being lost.
    layoutDirty = deferred
    if reshape then
        root:SetSize(width, math.max(1, offset - spacing))
    end
    SafeSetShown(root, true)
end

-- ---------------------------------------------------------------------------
-- The test board. Three enemies with every instrument populated, so the board
-- can be placed, sized and argued with anywhere -- no queue, no partner.
--
-- It fabricates STATE and then runs the real painters over it. That is the
-- whole design: a test board drawn by its own code path proves that the test
-- board works, which is not the question anyone is asking.
-- ---------------------------------------------------------------------------

local TEST_CAST = {
    { name = "Polymorph", icon = "Interface\\Icons\\Spell_Nature_Polymorph", length = 1.5 },
    { name = "Greater Heal", icon = "Interface\\Icons\\Spell_Holy_GreaterHeal", length = 2.5 },
    { name = "Mind Flay", icon = "Interface\\Icons\\Spell_Shadow_SiphonMana", length = 3, channel = true },
}

local TEST_SEATS = {
    { class = "MAGE",   race = "Gnome",  name = "Frostspite", spec = "Frost",
      health = 0.62, power = 0.44, cast = 1, ring = "TARGET", pet = "Water Elemental",
      dr = { { cat = "POLY", bracket = 2, reset = 9 }, { cat = "STUN", bracket = 3, reset = 4 } },
      auras = { { id = 45438, kind = "IMMUNE" } },
      used = { "Ice Block", "Counterspell", "Blink" } },
    { class = "PRIEST", race = "Human",  name = "Mendicant", spec = "Disc",
      health = 0.88, power = 0.19, cast = 2, ring = "FOCUS",
      dr = { { cat = "FEAR", bracket = 4, reset = nil, held = true },
             { cat = "KIDNEY", bracket = 2, reset = 12 } },
      auras = { { id = 33206, kind = "WALL" } },
      -- A locked-out healer: the state the DR ladder can never draw, because
      -- silence has no diminishing returns at all in TBC.
      control = { id = 15487, left = 3.4, duration = 5 },
      used = { "Psychic Scream", "Pain Suppression" } },
    { class = "ROGUE",  race = "Orc",    name = "Nightfall",  spec = nil,
      health = 0.17, power = 0.90, cast = nil, alpha = 1,
      dr = { { cat = "POLY", bracket = 2, reset = 7 } },
      auras = {},
      -- Sapped, one bracket down, with the clock running. This is the row the
      -- board is really for.
      control = { id = 6770, left = 6.2, duration = 10 },
      used = { "Cloak of Shadows", "Kick" } },
}

function CommanderArenaFrames_Test()
    if not Enabled() then
        print("|cff66ccffCommander Arena Frames|r: switch the module on first (|cffffd100/caf|r).")
        return
    end
    local now = GetTime()
    testUntil = now + 30

    dr:Wipe()
    book:Wipe()
    wipe(trinket)

    for index, spec in ipairs(TEST_SEATS) do
        local unit = ARENA_UNITS[index]
        local entry = NewSeat(unit)
        entry.index = index
        entry.guid = "TestEnemy" .. index
        entry.name, entry.class, entry.race, entry.spec = spec.name, spec.class, spec.race, spec.spec
        entry.exists = true

        local maxHealth = 8000 + index * 700
        local maxPower = 9000
        entry.test = {
            healthMax = maxHealth, health = math.floor(maxHealth * spec.health),
            powerMax = maxPower, power = math.floor(maxPower * spec.power),
            powerType = spec.class == "ROGUE" and 3 or 0,
            ring = spec.ring, alpha = spec.alpha,
            pet = spec.pet and { name = spec.pet, health = 2100, healthMax = 3000 } or nil,
        }
        local cast = spec.cast and TEST_CAST[spec.cast]
        if cast then
            entry.test.castName, entry.test.castIcon = cast.name, cast.icon
            entry.test.castStart = (now - cast.length * 0.4) * 1000
            entry.test.castEnd = (now + cast.length * 0.6) * 1000
            entry.test.channel = cast.channel
        end

        -- The ladder is driven through the REAL tracker, at real timestamps,
        -- so what the board shows is what the engine computes rather than a
        -- picture of what it ought to.
        for _, want in ipairs(spec.dr) do
            local sample
            for id, cat in pairs(DATA.DR_BY_SPELL) do
                if cat == want.cat then sample = id break end
            end
            if sample then
                local fade = want.reset and (now - (DATA.DR_RESET - want.reset)) or now
                for _ = 1, want.bracket - 1 do
                    dr:Applied(entry.guid, sample, fade - 1)
                    if not want.held then dr:Faded(entry.guid, sample, fade) end
                end
                if want.held then dr:Applied(entry.guid, sample, now) end
            end
        end

        for _, name in ipairs(spec.used) do
            local def = E.BookEntry(spec.class, spec.race, nil, name)
            if def then
                book:Used(entry.guid, spec.class, spec.race, def.id, name,
                          now - (def.cd or 60) * 0.55)
            end
        end

        if spec.control then
            local kind = E.ControlKind(spec.control.id)
            local icon = GetSpellTexture and GetSpellTexture(spec.control.id)
            local name = GetSpellInfo and GetSpellInfo(spec.control.id)
            entry.control = {
                id = spec.control.id, kind = kind, rank = E.ControlRank(kind),
                icon = icon, name = name,
                word = E.ControlWord(spec.control.id, kind),
                cat = E.Category(spec.control.id),
                expires = now + spec.control.left, duration = spec.control.duration,
            }
            entry.notes[#entry.notes + 1] = {
                id = spec.control.id, icon = icon, control = kind,
                expires = entry.control.expires, duration = spec.control.duration,
                helpful = false, mine = true,
            }
        end

        for _, aura in ipairs(spec.auras) do
            local note = E.AuraNote(aura.id)
            entry.notes[#entry.notes + 1] = {
                id = aura.id, icon = GetSpellTexture and GetSpellTexture(aura.id),
                expires = now + 6, duration = 10, helpful = true, note = note, mine = false,
            }
            if note and note.kind == "IMMUNE" then
                entry.immunity = { note = note, expires = now + 6, duration = 10,
                                   icon = GetSpellTexture and GetSpellTexture(aura.id) }
            elseif note and note.kind == "STEALTH" then
                entry.stealth = true
            end
        end

        trinket[entry.guid] = {
            spellId = 42292,
            readyAt = index == 2 and (now + 96) or nil,
            cd = 120,
        }
        seat[unit] = entry
        guidSeat[entry.guid] = entry
    end
    liveCount = #TEST_SEATS
    layoutDirty = true
    Draw()
    print("|cff66ccffCommander Arena Frames|r: test board up for 30 seconds. "
        .. "Drag it with |cffffd100/caf lock|r, or from the settings page.")
end

local function ClearTest()
    if testUntil == 0 then return end
    testUntil = 0
    for _, unit in ipairs(ARENA_UNITS) do
        local entry = seat[unit]
        if entry and entry.test then
            if entry.guid then guidSeat[entry.guid] = nil end
            seat[unit] = nil
        end
    end
    dr:Wipe()
    book:Wipe()
    wipe(trinket)
    liveCount = 0
    layoutDirty = true
end

-- What the board has learned this game, in text. The one place that says out
-- loud which numbers are known and which are inferred.
function CommanderArenaFrames_Report()
    local now = GetTime()
    print("|cff66ccffCommander Arena Frames|r report:")
    local any = false
    for index = 1, MAX_ENEMIES do
        local entry = seat[ARENA_UNITS[index]]
        if entry and entry.guid then
            any = true
            print(string.format("  |cffffd100%s|r  %s%s", entry.name or "?",
                entry.class or "?", entry.spec and (" / " .. entry.spec) or " / spec not yet shown"))
            local open = dr:Open(entry.guid, now, {})
            for _, info in ipairs(open) do
                print(string.format("      DR %-10s %-4s %s", info.cat,
                    BRACKET_LABEL[info.bracket] or "full",
                    info.held and "(held)" or (info.resetAt
                        and ("resets in " .. E.FormatTime(info.resetAt - now)) or "")))
            end
            for _, info in ipairs(book:Strip(entry.guid, entry.class, entry.race, now, {})) do
                if info.remaining then
                    print(string.format("      CD %-22s %s", info.name, E.FormatTime(info.remaining)))
                end
            end
        end
    end
    if not any then print("  no enemies on the board.") end
end

-- ---------------------------------------------------------------------------
-- Click-casting: the full modifier x button matrix, on an ENEMY unit.
--
-- The party board's matrix is about what you cast ON someone. This one is
-- about what you do TO them, which changes the useful defaults completely:
-- left-click targets, right-click sets focus (the two an arena player presses
-- a hundred times a game), and shift+left assists -- targets what THEY are
-- targeting, which is how you find out who the enemy is actually on.
--
-- Everything here is written ONCE, out of combat, onto raw tokens. Secure
-- attributes cannot be changed mid-fight, so a settings change made during a
-- game is held until it ends; the insecure art on top keeps updating either
-- way. That is also why the board's row ORDER is pinned to fixed while this is
-- on -- see ActiveSeats.
-- ---------------------------------------------------------------------------

local CLICK_MODS = {
    { key = "",                 label = "No modifier" },
    { key = "shift-",           label = "Shift" },
    { key = "ctrl-",            label = "Ctrl" },
    { key = "alt-",             label = "Alt" },
    { key = "ctrl-shift-",      label = "Ctrl + Shift" },
    { key = "alt-shift-",       label = "Alt + Shift" },
    { key = "alt-ctrl-",        label = "Alt + Ctrl" },
    { key = "alt-ctrl-shift-",  label = "Alt + Ctrl + Shift" },
}
local CLICK_BUTTONS = {
    { key = "1", label = "Left" },
    { key = "2", label = "Right" },
    { key = "3", label = "Middle" },
    { key = "4", label = "Button 4" },
    { key = "5", label = "Button 5" },
}

-- The bindings that are not spells. All three resolve live off the row's unit
-- token, so none of them can go stale as the board fills up.
local CLICK_ACTIONS = {
    { value = "TARGET", label = "Target them",
      icon = "Interface\\Icons\\Ability_Hunter_SniperShot" },
    { value = "FOCUS", label = "Set focus",
      icon = "Interface\\Icons\\Ability_Hunter_MasterMarksman" },
    { value = "TARGETTARGET", label = "Assist (target their target)",
      icon = "Interface\\Icons\\Ability_Warrior_BattleShout" },
}

-- Out of the box: the two clicks an arena player makes constantly, plus the
-- one that answers "who are they on".
local CLICK_DEFAULTS = {
    ["1"] = "TARGET",
    ["2"] = "FOCUS",
    ["shift-1"] = "TARGETTARGET",
}

-- A binding is: a stored value, or the default, or nothing. `false` is stored
-- for a binding the player deliberately CLEARED, which is what stops a default
-- coming back the next time the board loads.
function CommanderArenaFrames_GetBind(key)
    local binds = DB("ClickBinds", nil)
    local stored = binds and binds[key]
    if stored == false then return nil end
    if stored ~= nil then return stored end
    return CLICK_DEFAULTS[key]
end

function CommanderArenaFrames_SetBind(key, value)
    local db = CommanderArenaFramesDB
    if not db then return end
    db.ClickBinds = db.ClickBinds or {}
    if value == nil then
        -- Clearing a binding that HAS a default has to be recorded, or the
        -- default simply returns. Clearing one that does not can just forget.
        db.ClickBinds[key] = CLICK_DEFAULTS[key] and false or nil
    else
        db.ClickBinds[key] = value
    end
    secureDirty = true
end

function CommanderArenaFrames_GetClickMods() return CLICK_MODS end
function CommanderArenaFrames_GetClickButtons() return CLICK_BUTTONS end
function CommanderArenaFrames_GetClickActions() return CLICK_ACTIONS end

-- The live spellbook, deduplicated by name and alphabetical. Built from what
-- this character has actually TRAINED rather than from a shipped list, so the
-- picker can never offer a spell that would silently do nothing -- and never
-- needs updating when a class changes.
local spellBookCache

function CommanderArenaFrames_GetSpellBook(refresh)
    if spellBookCache and not refresh then return spellBookCache end
    local byName = {}
    local ok = pcall(function()
        for tab = 1, (GetNumSpellTabs and GetNumSpellTabs() or 0) do
            local _, _, offset, count = GetSpellTabInfo(tab)
            for index = (offset or 0) + 1, (offset or 0) + (count or 0) do
                local name = GetSpellBookItemName(index, "spell")
                if name then
                    local _, id = GetSpellBookItemInfo(index, "spell")
                    -- Later entries are higher ranks, and the client casts the
                    -- highest known rank of a name anyway, so last wins.
                    byName[name] = {
                        name = name, id = id,
                        icon = GetSpellBookItemTexture and GetSpellBookItemTexture(index, "spell"),
                    }
                end
            end
        end
    end)
    local book = {}
    if ok then
        for _, entry in pairs(byName) do book[#book + 1] = entry end
        table.sort(book, function(a, b) return a.name < b.name end)
    end
    -- An EMPTY result is never cached. The settings page is built at
    -- PLAYER_LOGIN, which can land before the spellbook is populated, and a
    -- cached empty book would mark every single binding as "you cannot cast
    -- that" -- forty red rims, all wrong, until the next reload. Not caching
    -- it means the next caller simply asks again.
    if #book > 0 then spellBookCache = book end
    return book
end

-- How a bound value reads in the grid: an icon, a label, and whether it is
-- BROKEN -- bound to something this character cannot cast, which is a click
-- that saves perfectly and then silently does nothing in a game.
function CommanderArenaFrames_BindDisplay(value)
    if value == nil then return nil, "Unbound", false end
    for _, action in ipairs(CLICK_ACTIONS) do
        if action.value == value then return action.icon, action.label, false end
    end
    local id = tonumber(value)
    if not id then return nil, tostring(value), true end
    local name, _, icon = GetSpellInfo and GetSpellInfo(id)
    if not name then return nil, "Spell " .. id, true end
    local known = false
    for _, entry in ipairs(CommanderArenaFrames_GetSpellBook()) do
        if entry.name == name then known = true break end
    end
    return icon, name, not known
end

local function BindClick(row, prefix, button, value, token)
    local typeAttr = prefix .. "type" .. button
    local spellAttr = prefix .. "spell" .. button
    local unitAttr = prefix .. "unit" .. button
    if value == "TARGET" then
        row:SetAttribute(typeAttr, "target")
        row:SetAttribute(spellAttr, nil)
        row:SetAttribute(unitAttr, nil)
    elseif value == "FOCUS" then
        row:SetAttribute(typeAttr, "focus")
        row:SetAttribute(spellAttr, nil)
        row:SetAttribute(unitAttr, nil)
    elseif value == "TARGETTARGET" then
        -- Assist. The token chain ("arena1target") resolves live, so this
        -- never goes stale as they swap.
        row:SetAttribute(typeAttr, "target")
        row:SetAttribute(spellAttr, nil)
        row:SetAttribute(unitAttr, token and (token .. "target") or nil)
    elseif value ~= nil then
        local id = tonumber(value)
        local name = id and GetSpellInfo and GetSpellInfo(id)
        if name then
            row:SetAttribute(typeAttr, "spell")
            row:SetAttribute(spellAttr, name)
        else
            row:SetAttribute(typeAttr, nil)
            row:SetAttribute(spellAttr, nil)
        end
        row:SetAttribute(unitAttr, nil)
    else
        row:SetAttribute(typeAttr, nil)
        row:SetAttribute(spellAttr, nil)
        row:SetAttribute(unitAttr, nil)
    end
end

-- Write the whole matrix onto every row. Out of combat only -- and rather than
-- queueing anything, a call made in combat just raises the dirty flag and the
-- PLAYER_REGEN_ENABLED handler calls it again.
local function SetupSecureRows()
    if not securePool then return end
    if InCombat() then secureDirty = true; return end
    secureDirty = false
    for index = 1, MAX_ENEMIES do
        local row = rows[index]
        local token = ARENA_UNITS[index]
        if row and row.SetAttribute then
            -- Both click phases, so the action fires whichever way the
            -- ActionButtonUseKeyDown CVar is set.
            if row.RegisterForClicks then row:RegisterForClicks("AnyDown", "AnyUp") end
            row:SetAttribute("unit", token)
            -- EVERY cell is written on every pass, including the empty ones: a
            -- binding cleared in the settings has to actually clear the
            -- attribute, or the old spell keeps firing until the next reload.
            for _, mod in ipairs(CLICK_MODS) do
                for _, btn in ipairs(CLICK_BUTTONS) do
                    BindClick(row, mod.key, btn.key,
                        CommanderArenaFrames_GetBind(mod.key .. btn.key), token)
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

local DRAW_THROTTLE = 0.05   -- 20Hz: a cast bar has to be smooth enough to
                             -- time a kick against, and nothing else here is
                             -- expensive enough to want a slower loop

local function InArenaNow()
    if IsActiveBattlefieldArena then
        local ok, isArena = pcall(IsActiveBattlefieldArena)
        if ok and isArena then return true end
    end
    local _, instanceType = IsInInstance()
    return instanceType == "arena"
end

local function Apply()
    ApplyBlizzardFrames()
    if not Enabled() then
        dr:Wipe()
        book:Wipe()
        wipe(trinket)
        wipe(flash)
        SafeSetShown(root, false)
        return
    end
    Commander.UI.ApplyHudChrome(root, CommanderArenaFramesDB, "Hud", {
        title = "Arena",
        defaultPoint = { point = "RIGHT", x = -220, y = 120 },
    })
    -- Click-cast changes the row's frame TYPE, which cannot be swapped live.
    if securePool ~= (DB("ClickCast", true) and true or false) then
        print("|cff66ccffCommander Arena Frames|r: the Click-Cast change takes effect after |cffffd100/reload|r.")
    end
    layoutDirty = true
    -- Every row's cached geometry is now suspect: a width or a growth
    -- direction may have changed under it, and the cache is what decides
    -- whether it gets re-anchored at all.
    for _, frame in ipairs(rows) do
        frame._offset, frame._kind = nil, nil
    end
    -- Give every existing row a valid base shape while we are certainly
    -- allowed to. A secure row cannot be resized once a fight starts, and the
    -- one path that reaches combat without a laid-out row -- click-cast with
    -- Combat Only, where the first draw of a match happens after the fight has
    -- begun -- would otherwise show a game's worth of zero-sized rows. Laying
    -- them out against no enemy costs one pass and closes it.
    if CanReshape() then
        for _, frame in ipairs(rows) do
            if not frame._kind then LayoutRow(frame, nil, 1) end
        end
    end
    SetupSecureRows()
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
events:RegisterEvent("SPELLS_CHANGED")
-- Every arena event is soft-registered: this client runs a retail-era UI over
-- TBC content, and the arena surface is exactly where that seam shows. A
-- client missing one of these must lose that instrument, not the board.
for _, name in ipairs({
    "ARENA_OPPONENT_UPDATE",
    "ARENA_PREP_OPPONENT_SPECIALIZATIONS",
    "ARENA_CROWD_CONTROL_SPELL_UPDATE",
    "ARENA_COOLDOWNS_UPDATE",
}) do
    pcall(events.RegisterEvent, events, name)
end

events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if Enabled() and (inArena or GetTime() < testUntil) then OnCombatLog() end
        return
    end

    if event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player")
        securePool = DB("ClickCast", true) and true or false
        inArena = InArenaNow()
        -- With click-cast on, every row is built ONCE here, out of combat.
        -- Creating a secure button and giving it its unit attribute are both
        -- refused once a fight has started, and a row created lazily on the
        -- first draw of a game would be created in exactly that moment. The
        -- tokens are fixed (arena1..arena5), so there is nothing to defer.
        if securePool then
            for index = 1, MAX_ENEMIES do
                rows[index] = rows[index] or NewRow(index)
            end
            SetupSecureRows()
        end
        Commander.AddListener(COMMANDER_ARENAFRAMES_EVENTS.UPDATE, Apply)
        Apply()

    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        local wasArena = inArena
        inArena = InArenaNow()
        if wasArena and not inArena then
            -- Leaving. Everything learned belonged to that match; carrying it
            -- into the next one would show the previous team's cooldowns on
            -- whoever inherits the slot.
            dr:Wipe(); book:Wipe(); wipe(trinket); wipe(flash); wipe(guidSeat)
            for _, unit in ipairs(ARENA_UNITS) do seat[unit] = nil end
            liveCount = 0
        end
        ApplyBlizzardFrames()
        ScanRoster()
        layoutDirty = true

    elseif event == "ARENA_OPPONENT_UPDATE" then
        -- "cleared" is the one reason that really retires a seat; "unseen" is
        -- a rogue in stealth and must leave the row exactly where it is.
        if arg2 == "cleared" and arg1 and seat[arg1] then
            local entry = seat[arg1]
            entry.exists, entry.prep = false, nil
        end
        ScanRoster()
        layoutDirty = true
        if arg1 and arg2 ~= "cleared" then
            local entry = seat[arg1]
            if entry then ScanAuras(entry) end
            RequestTrinket(arg1)
            ReadTrinket(arg1)
        end

    elseif event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" then
        local count = ReadPrep()
        if count > 0 then
            liveCount = math.max(liveCount, count)
            layoutDirty = true
        end

    elseif event == "ARENA_CROWD_CONTROL_SPELL_UPDATE" or event == "ARENA_COOLDOWNS_UPDATE" then
        -- The payload's shape has differed across UI revisions, so the unit is
        -- taken from arg1 when it looks like one and every unit is re-read
        -- otherwise. Cheap either way: there are at most five.
        if type(arg1) == "string" and seat[arg1] then
            ReadTrinket(arg1)
        else
            for _, unit in ipairs(ARENA_UNITS) do
                if seat[unit] and seat[unit].exists then ReadTrinket(unit) end
            end
        end

    elseif event == "UNIT_AURA" then
        local entry = arg1 and seat[arg1]
        if entry then ScanAuras(entry) end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Anything that had to wait for combat to end: a secure rebind, a
        -- protected Show/Hide, Blizzard's frames going back.
        if secureDirty then SetupSecureRows() end
        ApplyBlizzardFrames()
        layoutDirty = true

    elseif event == "SPELLS_CHANGED" then
        -- A new rank, a respec, a fresh login: the picker is built from the
        -- spellbook, so its cache has to go.
        CommanderArenaFrames_GetSpellBook(true)

    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_TARGET_CHANGED"
        or event == "PLAYER_FOCUS_CHANGED" then
        -- Purely visual; the next draw picks them up.
    end
end)

local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(self, elapsed)
    if not Enabled() then return end
    self.since = (self.since or 0) + elapsed
    if self.since < DRAW_THROTTLE then return end
    self.since = 0
    if testUntil > 0 and GetTime() >= testUntil then ClearTest() end
    -- `root:IsShown()` is the third condition and it is the one that was
    -- missing: leaving an arena flips `inArena` and wipes the state, but
    -- nothing then called Draw -- so the board stayed on screen, frozen on the
    -- last frame of the game that just ended, until a setting changed or the
    -- player reloaded. One more draw after the flag drops is all it takes,
    -- and Draw's own empty-list branch does the rest.
    if inArena or testUntil > 0 or root:IsShown() then Draw() end
end)
