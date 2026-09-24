-- Commander.Health: the health of people the client will only describe in
-- percent, reverse-engineered from the combat log.
--
-- On this client a hostile player's health arrives as a PERCENTAGE:
-- UnitHealthMax answers 100 and UnitHealth answers 0..100 (Blizzard's own
-- frames test exactly that -- UnitFrameHealthBar_Update raises showPercentage
-- when UnitHealthMax == 100). Nothing in the API gives the number behind it.
-- But the combat log does say how much damage landed and how much healing
-- did, and the percent moves in step -- so between two readings the maximum
-- is simply
--
--     max = health lost / (percent then - percent now) * 100
--
-- and the estimate sharpens as the span widens: a reading is a whole percent,
-- so a ten-point drop is good to a tenth and a sixty-point drop to a sixtieth.
-- A death is the best anchor of all: everything since the last full reading
-- was the whole bar (plus whatever the killing blow overshot).
--
-- Rules that keep the number honest:
--   * health LOST is amount minus overkill; absorbed damage never touched the
--     bar and is not counted
--   * healing counts against the loss, minus its overheal
--   * a percent that RISES with no heal in the log means a heal we could not
--     see (out of combat-log range, or regeneration) -- the anchor is dropped
--     and started again from here, so an unseen heal cannot inflate the max
--   * a better span replaces a worse one; an exact reading (a group member's
--     real values, or the unit joining your party) replaces everything
--   * the book is keyed by GUID and remembered across sessions, because a
--     player's maximum health barely moves between games and the first
--     reading of the next arena should not start from nothing
--
-- The estimator is pure (Commander.Health.NewBook) and runs under luajit in
-- Commander_Events/Harness/health_smoke.lua. Consumers ask
-- Commander.Health.Max(guid) / Current(unit) and call Commander.Health.Watch()
-- once so the combat-log listener is only registered when somebody wants it.

Commander = Commander or {}
Commander.Health = Commander.Health or {}
local H = Commander.Health

H.MIN_SPAN = 4          -- percent points a reading must have dropped before it is an estimate
H.GOOD_SPAN = 30        -- ...and past this the estimate is within a few percent
H.TTL = 30 * 60         -- seconds a unit is kept without being seen (session table)
H.KEEP_DAYS = 14        -- days an estimate survives in SavedVariables
H.KEEP_MAX = 400        -- most GUIDs remembered across sessions

-- ---------------------------------------------------------------------------
-- The book (pure)
-- ---------------------------------------------------------------------------
local Book = {}
Book.__index = Book

function H.NewBook()
    return setmetatable({ units = {} }, Book)
end

local function Unit(book, guid, now)
    local u = book.units[guid]
    if not u then
        u = { net = 0, healedSince = false }
        book.units[guid] = u
    end
    u.seen = now or u.seen or 0
    return u
end

-- Offer a candidate maximum measured over `span` percent points. A wider span
-- is a better ruler; an exact value beats any ruler.
local function Offer(u, candidate, span)
    if u.exact then return false end
    if not candidate or candidate <= 0 then return false end
    if u.est and (u.estSpan or 0) >= span then return false end
    u.est = math.floor(candidate + 0.5)
    u.estSpan = span
    return true
end

local function Anchor(u, pct)
    u.anchorPct = pct
    u.net = 0
    u.healedSince = false
end

-- Health actually removed from the bar (amount minus overkill; absorbs are
-- the caller's business and never reach here)
function Book:Damage(guid, hpLoss, now)
    if not guid or not hpLoss or hpLoss <= 0 then return end
    local u = Unit(self, guid, now)
    if u.anchorPct then u.net = u.net + hpLoss end
end

function Book:Heal(guid, hpGain, now)
    if not guid or not hpGain or hpGain <= 0 then return end
    local u = Unit(self, guid, now)
    if u.anchorPct then
        u.net = u.net - hpGain
        u.healedSince = true
    end
end

-- A percent reading: 0..100, as the client reports it for this unit
function Book:Percent(guid, pct, now)
    if not guid or not pct then return end
    pct = math.floor(pct + 0.5)
    local u = Unit(self, guid, now)
    local last = u.pct
    u.pct = pct
    if u.exact then return end
    if not u.anchorPct then
        Anchor(u, pct)
        return
    end
    -- Risen with no heal we saw: a heal out of range, or regeneration. The
    -- ruler is broken; start a new one here rather than stretch the old
    if last and pct > last and not u.healedSince then
        Anchor(u, pct)
        return
    end
    -- Healed above the anchor, or healed more than was lost: same answer
    if pct > u.anchorPct or u.net <= 0 then
        Anchor(u, pct)
        return
    end
    u.healedSince = false
    local span = u.anchorPct - pct
    if span >= H.MIN_SPAN then
        Offer(u, u.net * 100 / span, span)
    end
end

-- The unit died: whatever was lost since the anchor was the anchor's share of
-- the whole bar. The best ruler there is when the anchor was full.
function Book:Died(guid, now)
    if not guid then return end
    local u = Unit(self, guid, now)
    if u.anchorPct and u.anchorPct > 0 and u.net > 0 and not u.exact then
        Offer(u, u.net * 100 / u.anchorPct, u.anchorPct)
    end
    u.pct = 0
    u.anchorPct = nil
    u.net = 0
    u.healedSince = false
end

-- Real values are known (a group member, or the client simply told us)
function Book:Exact(guid, cur, max, now)
    if not guid or not max or max <= 0 then return end
    local u = Unit(self, guid, now)
    u.exact = true
    u.est = max
    u.estSpan = 100
    u.pct = math.floor((cur or 0) / max * 100 + 0.5)
    u.anchorPct = nil
end

-- max, quality ("EXACT" | "GOOD" | "ROUGH"), span -- or nil when unknown
function Book:Max(guid)
    local u = guid and self.units[guid]
    if not u or not u.est then return nil end
    if u.exact then return u.est, "EXACT", 100 end
    if (u.estSpan or 0) >= H.GOOD_SPAN then return u.est, "GOOD", u.estSpan end
    return u.est, "ROUGH", u.estSpan
end

-- Current health from a percent reading and the estimate
function Book:Current(guid, pct)
    local max = self:Max(guid)
    if not max then return nil end
    pct = pct or (self.units[guid] and self.units[guid].pct) or 0
    return math.floor(max * pct / 100 + 0.5)
end

function Book:Forget(guid)
    if guid then self.units[guid] = nil end
end

function Book:Prune(now, ttl)
    ttl = ttl or H.TTL
    for guid, u in pairs(self.units) do
        if now - (u.seen or 0) > ttl then self.units[guid] = nil end
    end
end

function Book:Count()
    local n = 0
    for _ in pairs(self.units) do n = n + 1 end
    return n
end

-- Estimates worth carrying between sessions: the max, how well it was
-- measured, and when. Exact readings are kept too -- a party member today is
-- an arena opponent tomorrow.
function Book:Export(now, out)
    out = out or {}
    for guid, u in pairs(self.units) do
        if u.est and (u.estSpan or 0) >= H.MIN_SPAN then
            out[guid] = { est = u.est, span = u.exact and 100 or u.estSpan, t = now }
        end
    end
    return out
end

function Book:Import(saved, now, keepSeconds, keepMax)
    if type(saved) ~= "table" then return 0 end
    keepSeconds = keepSeconds or (H.KEEP_DAYS * 86400)
    keepMax = keepMax or H.KEEP_MAX
    -- Newest first, so a cap trims the oldest
    local list = {}
    for guid, rec in pairs(saved) do
        if type(rec) == "table" and rec.est and rec.est > 0 and (now - (rec.t or 0)) <= keepSeconds then
            list[#list + 1] = { guid = guid, rec = rec }
        end
    end
    table.sort(list, function(a, b) return (a.rec.t or 0) > (b.rec.t or 0) end)
    local n = 0
    for i, entry in ipairs(list) do
        if i > keepMax then break end
        local u = Unit(self, entry.guid, 0)
        -- Carried over as a ruler of the recorded span, never as exact: gear
        -- changes between sessions, and a live reading should be able to beat it
        if not u.est then
            u.est = entry.rec.est
            u.estSpan = math.min(entry.rec.span or H.MIN_SPAN, 99)
            u.seen = 0
            n = n + 1
        end
    end
    return n
end

-- ---------------------------------------------------------------------------
-- Formatting shared by the consumers
-- ---------------------------------------------------------------------------
function H.Abbreviate(n)
    if not n then return "?" end
    if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
    if n >= 10000 then return string.format("%.0fk", n / 1000) end
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(math.floor(n + 0.5))
end

-- ---------------------------------------------------------------------------
-- Wiring. Nothing below registers an event until Watch() is called.
-- ---------------------------------------------------------------------------
local book = H.NewBook()
H.book = book

local watching = false
local frame
local lastPrune = 0

local DAMAGE_SUBEVENTS = {
    SWING_DAMAGE = "swing", RANGE_DAMAGE = "spell", SPELL_DAMAGE = "spell",
    SPELL_PERIODIC_DAMAGE = "spell", DAMAGE_SHIELD = "spell", DAMAGE_SPLIT = "spell",
    ENVIRONMENTAL_DAMAGE = "env",
}
local HEAL_SUBEVENTS = { SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true }

local function IsPlayerGUID(guid)
    return type(guid) == "string" and guid:sub(1, 7) == "Player-"
end

local function OnCombatLog()
    local _, sub, _, _, _, _, _, destGUID, _, destFlags = CombatLogGetCurrentEventInfo()
    if not destGUID then return end
    local kind = DAMAGE_SUBEVENTS[sub]
    local now = GetTime()
    if kind then
        -- Only players and their pets are percent-only; a mob's real health
        -- is already known and would only fill the book with noise
        if not IsPlayerGUID(destGUID) and not (destFlags and COMBATLOG_OBJECT_TYPE_PET
            and bit.band(destFlags, COMBATLOG_OBJECT_TYPE_PET) > 0) then return end
        local amount, overkill
        if kind == "swing" then
            amount, overkill = select(12, CombatLogGetCurrentEventInfo())
        elseif kind == "env" then
            amount, overkill = select(13, CombatLogGetCurrentEventInfo())
        else
            amount, overkill = select(15, CombatLogGetCurrentEventInfo())
        end
        amount = tonumber(amount) or 0
        overkill = math.max(0, tonumber(overkill) or 0)
        book:Damage(destGUID, amount - overkill, now)
    elseif HEAL_SUBEVENTS[sub] then
        if not IsPlayerGUID(destGUID) then return end
        local amount, overheal = select(15, CombatLogGetCurrentEventInfo())
        amount = tonumber(amount) or 0
        overheal = math.max(0, tonumber(overheal) or 0)
        book:Heal(destGUID, amount - overheal, now)
    elseif sub == "UNIT_DIED" then
        if IsPlayerGUID(destGUID) then book:Died(destGUID, now) end
    end
end

-- Read a unit token: a percent reading for a percent-only unit, an exact one
-- otherwise. Returns true when the token said anything.
function H.Read(unit)
    if not unit or not UnitExists or not UnitExists(unit) then return false end
    local guid = UnitGUID(unit)
    if not guid then return false end
    if not (UnitIsPlayer(unit) or (UnitPlayerControlled and UnitPlayerControlled(unit))) then return false end
    local max = UnitHealthMax(unit) or 0
    local cur = UnitHealth(unit) or 0
    local now = GetTime()
    if max == 100 then
        if cur <= 0 and UnitIsDeadOrGhost(unit) then
            book:Died(guid, now)
        else
            book:Percent(guid, cur, now)
        end
    elseif max > 0 then
        book:Exact(guid, cur, max, now)
    end
    return true
end

local WATCH_TOKENS = { "target", "focus", "mouseover" }

local function OnEvent(_, event, unit)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        H.Read(unit)
    elseif event == "PLAYER_TARGET_CHANGED" then
        H.Read("target")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        H.Read("focus")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        H.Read("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        H.Read(unit)
    elseif event == "ARENA_OPPONENT_UPDATE" then
        H.Read(unit)
    elseif event == "PLAYER_LOGOUT" then
        H.Save()
    end
    local now = GetTime()
    if now - lastPrune > 60 then
        lastPrune = now
        book:Prune(now)
    end
end

-- A consumer says it wants estimates. Idempotent; the first call registers.
function H.Watch()
    if watching then return end
    watching = true
    frame = frame or CreateFrame("Frame")
    frame:SetScript("OnEvent", OnEvent)
    frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    frame:RegisterEvent("UNIT_HEALTH")
    frame:RegisterEvent("UNIT_MAXHEALTH")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    frame:RegisterEvent("PLAYER_LOGOUT")
    pcall(frame.RegisterEvent, frame, "ARENA_OPPONENT_UPDATE")
    for _, token in ipairs(WATCH_TOKENS) do H.Read(token) end
end

function H.IsWatching() return watching end

-- Is this unit one the client only describes in percent?
function H.IsPercentOnly(unit)
    return unit ~= nil and UnitExists(unit) and (UnitHealthMax(unit) or 0) == 100
        and (UnitIsPlayer(unit) or (UnitPlayerControlled and UnitPlayerControlled(unit)))
end

function H.Max(guid) return book:Max(guid) end

-- Current and maximum for a unit token: exact when the client knows, an
-- estimate (third return = quality) when it only knows the percent, nil when
-- nothing is known yet
function H.Current(unit)
    if not unit or not UnitExists(unit) then return nil end
    local max = UnitHealthMax(unit) or 0
    if max ~= 100 then return UnitHealth(unit), max, "EXACT" end
    local guid = UnitGUID(unit)
    local est, quality = book:Max(guid)
    if not est then return nil end
    return book:Current(guid, UnitHealth(unit)), est, quality
end

-- ---------------------------------------------------------------------------
-- Persistence: CommanderHealthDB.Book, written at logout, read at load
-- ---------------------------------------------------------------------------
function H.Save()
    CommanderHealthDB = CommanderHealthDB or {}
    local now = time and time() or 0
    -- Timestamps in the book are GetTime (uptime); exported records carry
    -- wall-clock time so the age test works across sessions
    local out = {}
    for guid, rec in pairs(book:Export(now)) do out[guid] = rec end
    -- Keep what earlier sessions knew about people not seen this time
    local old = CommanderHealthDB.Book
    if type(old) == "table" then
        for guid, rec in pairs(old) do
            if not out[guid] and type(rec) == "table" and (now - (rec.t or 0)) <= H.KEEP_DAYS * 86400 then
                out[guid] = rec
            end
        end
    end
    CommanderHealthDB.Book = out
end

function H.Load()
    CommanderHealthDB = CommanderHealthDB or {}
    local now = time and time() or 0
    return book:Import(CommanderHealthDB.Book, now)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, addon)
    if addon == "Commander_Events" then
        H.Load()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
