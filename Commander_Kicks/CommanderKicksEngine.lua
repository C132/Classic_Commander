-- Commander Kicks: the rules, with no WoW API in them.
--
-- Everything here is a pure function of what it was told and what time it is.
-- The module file feeds it combat-log events and a roster and asks it what to
-- draw; this file never calls GetTime, never reads a unit, never touches a
-- frame. That is what lets the whole bar be tested under plain luajit at
-- arbitrary timestamps, and it is the only reason the split exists.
--
-- Two ideas:
--
--   OWNER   whoever the cooldown belongs to. Normally the enemy player, by
--           GUID; for Spell Lock it is the warlock when the module could name
--           one and the felhunter itself when it could not. The engine does
--           not care which -- an owner is a key and a display record.
--   ROW     one icon on the bar: an owner, a book entry, and where its
--           cooldown stands. Rows come out in a FIXED order (roster order,
--           then book order) rather than sorted by time left, on purpose: an
--           icon that moves when it is used is an icon you have to read
--           instead of glance at.

CommanderKicks_Engine = CommanderKicks_Engine or {}
local E = CommanderKicks_Engine
local DATA = CommanderKicks_Data

local floor = math.floor

-- ---------------------------------------------------------------------------
-- The book, indexed
-- ---------------------------------------------------------------------------
local byId, byName = {}, {}
local byClass, byRace = {}, {}
local indexed = false

local function IndexBook()
    if indexed then return end
    indexed = true
    for order, entry in ipairs(DATA.BOOK or {}) do
        entry.order = order
        byId[entry.id] = entry
        byName[entry.name] = entry
        -- The shocks: a name that spends this entry's cooldown without being
        -- this entry. Resolves to the entry so the caller never sees the
        -- difference.
        for _, alias in ipairs(entry.also or {}) do
            byName[alias] = entry
        end
        if entry.class then
            byClass[entry.class] = byClass[entry.class] or {}
            table.insert(byClass[entry.class], entry)
        elseif entry.race then
            byRace[entry.race] = byRace[entry.race] or {}
            table.insert(byRace[entry.race], entry)
        end
    end
end

-- The book entry a cast spends, or nil. Id first, then name, because the log
-- reports the rank that was cast and the book carries one id per spell.
function E.Entry(spellId, spellName)
    IndexBook()
    local hit = spellId and byId[spellId]
    if hit then return hit end
    return spellName and byName[spellName] or nil
end

-- Every interrupt an enemy of this class and race carries, in book order.
-- Either may be nil; an unknown class contributes nothing, which is how a
-- battleground stranger whose class has not been resolved yet gets a bar
-- made only of what they have actually been seen to cast.
function E.BookFor(classToken, race)
    IndexBook()
    local out = {}
    for _, entry in ipairs((classToken and byClass[classToken]) or {}) do
        out[#out + 1] = entry
    end
    for _, entry in ipairs((race and byRace[race]) or {}) do
        out[#out + 1] = entry
    end
    return out
end

-- The whole book, in order. For the settings page and the test board.
function E.Book()
    IndexBook()
    return DATA.BOOK
end

-- ---------------------------------------------------------------------------
-- The bar
-- ---------------------------------------------------------------------------
local Bar = {}
Bar.__index = Bar

function E.NewBar()
    return setmetatable({ state = {}, seen = 0 }, Bar)
end

-- How close two stamps of one ability have to be to count as one press. A
-- Feral Charge can reach the log as its cast and again as the effect it
-- applies; the ledger does not care (the second write is identical) but a
-- caller that flashes or plays a sound on every stamp does it twice.
local RESTAMP_WINDOW = 0.5

-- Record a cast. Returns the entry and whether this was a FRESH press rather
-- than the same one arriving down a second channel; anything with a side
-- effect gates on the second return.
function Bar:Used(owner, entry, now)
    if not (owner and entry) then return nil, false end
    local perOwner = self.state[owner]
    if not perOwner then
        self.seen = self.seen + 1
        perOwner = { order = self.seen, cds = {} }
        self.state[owner] = perOwner
    end
    local previous = perOwner.cds[entry.name]
    local fresh = not (previous and (now - previous.at) < RESTAMP_WINDOW)
    if fresh or not previous then
        perOwner.cds[entry.name] = { at = now, cd = entry.cd, entry = entry }
    end
    return entry, fresh
end

-- Seconds until this owner's `entryName` is back, or nil when it is ready.
-- The second return says whether it has ever been seen used, which is the
-- difference between "ready" and "never pressed".
function Bar:Remaining(owner, entryName, now)
    local perOwner = self.state[owner]
    local used = perOwner and perOwner.cds[entryName]
    if not used then return nil, false end
    local left = used.at + used.cd - now
    if left <= 0 then return nil, true end
    return left, true
end

function Bar:Knows(owner)
    return self.state[owner] ~= nil
end

function Bar:Count()
    local n = 0
    for _ in pairs(self.state) do n = n + 1 end
    return n
end

function Bar:Clear(owner)
    self.state[owner] = nil
end

function Bar:Wipe()
    for k in pairs(self.state) do self.state[k] = nil end
    self.seen = 0
end

-- Forget owners whose every cooldown has been back for longer than `grace`.
-- An arena has five people and then ends; a battleground hands you forty
-- through one combat log, and without this the table grows all game.
function Bar:Prune(now, grace)
    for owner, perOwner in pairs(self.state) do
        local live = false
        for _, used in pairs(perOwner.cds) do
            if used.at + used.cd + grace > now then
                live = true
                break
            end
        end
        if not live then self.state[owner] = nil end
    end
end

-- One row. Reused tables: the draw loop runs ten times a second and a fresh
-- table per icon per tick is garbage for nothing.
local function FillRow(row, ownerKey, ownerInfo, entry, used, now, readyTail)
    row.owner = ownerKey
    row.info = ownerInfo
    row.entry = entry
    row.at = used and used.at or nil
    row.cd = entry.cd
    if used then
        local left = used.at + used.cd - now
        if left > 0 then
            row.remaining = left
            row.ready = false
            -- The lockout is the opening stretch of the cooldown: the kick is
            -- still doing its work for this long.
            row.locked = (now - used.at) < (entry.lock or 0)
            row.justReady = false
        else
            row.remaining = nil
            row.ready = true
            row.locked = false
            row.justReady = (-left) < (readyTail or 0)
        end
    else
        row.remaining = nil
        row.ready = true
        row.locked = false
        row.justReady = false
    end
    return row
end

-- The rows to draw, in order.
--
--   roster      ordered list of { key, name, class, race, seat } -- the
--               enemies the module can NAME (arena seats, a target, a focus).
--               Each gets their full book, so an arena bar has a fixed shape
--               from the gates: every kick they own, ready or not.
--   includeReady  whether a ready interrupt gets an icon at all. On, the bar
--               reads by position and a ready kick is a visible threat; off,
--               only what is actually on cooldown is drawn, the classic look.
--   readyTail   seconds a just-finished cooldown lingers as a "back up" flash
--               even when ready icons are off.
--
-- After the roster come the strangers: owners seen in the log who are not on
-- the roster (a battleground, world PvP). They get only what they have
-- actually spent, because a stranger has no book until their class is known
-- -- and when it is, they belong on the roster, not here.
function Bar:Rows(now, roster, includeReady, readyTail, out)
    IndexBook()
    out = out or {}
    local n = 0
    local onRoster = {}

    for _, member in ipairs(roster or {}) do
        onRoster[member.key] = true
        local perOwner = self.state[member.key]
        local book = E.BookFor(member.class, member.race)
        local covered = {}
        for _, entry in ipairs(book) do
            covered[entry.name] = true
            local used = perOwner and perOwner.cds[entry.name]
            local left = used and (used.at + used.cd - now) or 0
            local justReady = used and left <= 0 and (-left) < (readyTail or 0)
            if includeReady or left > 0 or justReady then
                n = n + 1
                out[n] = FillRow(out[n] or {}, member.key, member, entry, used, now, readyTail)
            end
        end
        -- Anything they spent that their book does not list: a class we
        -- have wrong, a racial on a race we could not resolve. Shown rather
        -- than hidden, because a cooldown that was seen is a fact.
        if perOwner then
            for _, entry in ipairs(DATA.BOOK) do
                local used = perOwner.cds[entry.name]
                if used and not covered[entry.name] then
                    local left = used.at + used.cd - now
                    if left > 0 or (-left) < (readyTail or 0) then
                        n = n + 1
                        out[n] = FillRow(out[n] or {}, member.key, member, entry, used, now, readyTail)
                    end
                end
            end
        end
    end

    -- Strangers, in the order they were first seen.
    local strangers = {}
    for owner, perOwner in pairs(self.state) do
        if not onRoster[owner] then strangers[#strangers + 1] = owner end
    end
    table.sort(strangers, function(a, b)
        return self.state[a].order < self.state[b].order
    end)
    for _, owner in ipairs(strangers) do
        local perOwner = self.state[owner]
        for _, entry in ipairs(DATA.BOOK) do
            local used = perOwner.cds[entry.name]
            if used then
                local left = used.at + used.cd - now
                if left > 0 or (-left) < (readyTail or 0) then
                    n = n + 1
                    out[n] = FillRow(out[n] or {}, owner, perOwner.info, entry, used, now, readyTail)
                end
            end
        end
    end

    for i = #out, n + 1, -1 do out[i] = nil end
    return out
end

-- Attach a display record to an owner the roster does not carry, so a
-- stranger's row can still say who they are.
function Bar:Describe(owner, info)
    local perOwner = self.state[owner]
    if perOwner then perOwner.info = info end
end

-- ---------------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------------
function E.FormatTime(seconds)
    if not seconds or seconds <= 0 then return "" end
    if seconds >= 60 then
        return string.format("%d:%02d", floor(seconds / 60), floor(seconds % 60))
    end
    if seconds >= 10 then return string.format("%d", floor(seconds + 0.5)) end
    return string.format("%.1f", seconds)
end

return E
