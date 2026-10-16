-- Commander Meters: what a dispel IS — one answer for both engines.
--
-- The group engine (CommanderMetersEngine) and the arena match engine
-- (CommanderMetersArena) both count dispels. They used to decide two
-- things on their own, and both decisions were wrong somewhere:
--
--   * OFFENSIVE or DEFENSIVE. The arena engine compared the two seats'
--     teams, which has no answer when the far end is a pet (Purge on a
--     felhunter has no seat) and fell through to "defensive". The group
--     engine never split them at all. The removed aura's TYPE is the
--     answer the log already gives (SPELL_DISPEL's 18th argument): a BUFF
--     taken off someone is offensive — a purge, a steal, Mass Dispel's
--     enemy half — and a DEBUFF taken off someone is defensive, a cleanse.
--     SPELL_STOLEN only ever takes buffs.
--
--   * What MASS DISPEL shattered. On this client Mass Dispel is three
--     spells (SpellEffect, build 2.5.6.69795):
--       32375  the cast — effect 38 DISPEL Magic on allies in the area
--              (their harmful magic), and it triggers 32592
--       32592  effect 38 DISPEL Magic on ENEMIES in the area (their
--              helpful magic), and it triggers 39897
--       39897  effect 108 DISPEL_MECHANIC, mechanic 29 (IMMUNE_SHIELD) on
--              enemies in the area: Divine Shield, Ice Block, Blessing of
--              Protection, Divine Protection
--     The first two report themselves as SPELL_DISPEL like any dispel. A
--     MECHANIC removal is not a dispel to the combat log (ASSUMPTIONS 40):
--     the shield just fades, a SPELL_AURA_REMOVED that names nobody. So the
--     biggest thing a Mass Dispel does — the bubble or the block it breaks
--     — never reached either meter. The correlator below pairs a shield
--     fading off one side with a Mass Dispel landing from the other, in
--     either log order, and refuses to count one twice if the log does name
--     the removal after all.
--
-- Pure: no frames, no WoW API, timing from the log's own timestamps.

CommanderMetersDispel = {}
local D = CommanderMetersDispel

-- ---------------------------------------------------------------------------
-- Data (every id from the client's own DB2 tables, build 2.5.6.69795)
-- ---------------------------------------------------------------------------

-- The Mass Dispel family; 32375 is the one the caster's bar casts
D.MASS_DISPEL_CAST = 32375
D.MASS_DISPEL = { [32375] = true, [32592] = true, [39897] = true }

-- What 39897 removes — SpellCategories.Mechanic = 29 on a class aura — and
-- each aura's full length in seconds (SpellMisc.DurationIndex →
-- SpellDuration), so a shield that simply ran out is never called broken
D.SHATTERABLE = {
    [642] = 10, [1020] = 12,                -- Divine Shield
    [45438] = 10,                           -- Ice Block
    [1022] = 6, [5599] = 8, [10278] = 10,   -- Blessing of Protection
    [498] = 6, [5573] = 8,                  -- Divine Protection
}

-- The dispels aimed at an ENEMY, which can therefore miss (resisted,
-- immune under Cloak of Shadows, eaten by a Grounding Totem): a
-- SPELL_MISSED of one of these is an attempt that took nothing. Class
-- spells with a DISPEL (38) or STEAL (126) effect on an enemy target
-- (SpellEffect × SkillLineAbility). Arcane Shot and Shield Slam carry a
-- dispel too, but a miss of either is a missed attack, not a dispel.
D.TOOLS = {
    [527] = true, [988] = true,             -- Dispel Magic
    [32375] = true, [32592] = true,         -- Mass Dispel
    [370] = true, [8012] = true,            -- Purge
    [30449] = true,                         -- Spellsteal
    [19505] = true, [19731] = true, [19734] = true,
    [19736] = true, [27276] = true, [27277] = true, -- Devour Magic (felhunter)
    [19801] = true,                         -- Tranquilizing Shot
}

-- ---------------------------------------------------------------------------
-- Offensive or defensive
-- ---------------------------------------------------------------------------

-- true = offensive (a buff came off), false = defensive (a debuff came
-- off), nil = the log did not say — the caller's own sides decide then.
function D.Offensive(sub, auraType)
    if sub == "SPELL_STOLEN" then return true end
    if auraType == "BUFF" then return true end
    if auraType == "DEBUFF" then return false end
    return nil
end

-- ---------------------------------------------------------------------------
-- The Mass Dispel correlator
-- ---------------------------------------------------------------------------

-- A shield fade and the Mass Dispel that caused it are one server event,
-- so the log stamps them alike; the window only absorbs which of the two
-- the log printed first. It is lopsided on purpose: a mage who cancels an
-- Ice Block while the Mass Dispel is still being CAST (1.5 s) fades well
-- before it lands and must not be credited to it.
local EARLY = 0.3       -- s: the fade logged before the landing
local LATE = 0.6        -- s: the fade logged after the landing
local EXPIRY_SLACK = 0.5 -- s: a fade this close to the aura's full length is its expiry
local HOLD = 8          -- pending records kept (a Mass Dispel hits ten)

local Corr = {}
Corr.__index = Corr

function D.NewCorrelator()
    local c = setmetatable({}, Corr)
    c:Reset()
    return c
end

function Corr:Reset()
    self.lands = {}     -- { src, side, ts, info } newest last
    self.fades = {}     -- { dst, side, id, name, ts } waiting for a landing
    self.applied = {}   -- key -> ts the shield went on
    self.named = {}     -- key -> ts a SPELL_DISPEL named this shield's removal
    self.inferred = {}  -- key -> { ts, ref } a shatter credited from a fade
end

local function Key(dst, id) return dst .. "\0" .. id end

local function Prune(list, ts, keep)
    local j = 0
    for i = 1, #list do
        local e = list[i]
        if ts - e.ts <= keep then
            j = j + 1
            list[j] = e
        end
    end
    for i = #list, j + 1, -1 do list[i] = nil end
end

local function Push(list, e)
    if #list >= HOLD then table.remove(list, 1) end
    list[#list + 1] = e
end

-- A shatterable aura went on `dst`. Only SPELL_AURA_APPLIED, never a
-- refresh: the clock is the application's.
function Corr:Applied(dst, id, ts)
    if not (dst and id and D.SHATTERABLE[id]) then return end
    self.applied[Key(dst, id)] = ts
end

-- A Mass Dispel landed: its cast success, or any SPELL_DISPEL it made.
-- `src` is the caster's key, `side` its team, `info` whatever the engine
-- needs back when a fade is paired with it. Returns the fades that were
-- already waiting (logged just before), each now the caller's to credit,
-- or nil.
function Corr:Landed(src, side, ts, info)
    if not src then return nil end
    Prune(self.lands, ts, LATE)
    local rec
    for i = #self.lands, 1, -1 do
        if self.lands[i].src == src then rec = self.lands[i]; break end
    end
    if rec then
        rec.ts = ts
        rec.info = rec.info or info
    else
        rec = { src = src, side = side, ts = ts, info = info }
        Push(self.lands, rec)
    end
    Prune(self.fades, ts, EARLY)
    local claimed
    for i = #self.fades, 1, -1 do
        local f = self.fades[i]
        if f.side ~= side then
            claimed = claimed or {}
            claimed[#claimed + 1] = f
            table.remove(self.fades, i)
        end
    end
    if claimed and #claimed > 1 then
        -- Credit in the order the shields fell
        table.sort(claimed, function(x, y) return x.ts < y.ts end)
    end
    return claimed, rec
end

-- A shatterable aura faded off `dst` (on `side`). Returns the landing
-- record that explains it — a Mass Dispel from the OTHER side within the
-- window — or nil, in which case the fade waits a moment for a landing
-- the log has not printed yet.
function Corr:Faded(dst, side, id, name, ts)
    local full = id and D.SHATTERABLE[id]
    if not (dst and full) then return nil end
    local key = Key(dst, id)
    local at = self.applied[key]
    self.applied[key] = nil
    -- Ran its full length: an expiry, whatever else happened that second
    if at and ts - at >= full - EXPIRY_SLACK then return nil end
    -- The log already named who removed it
    local named = self.named[key]
    if named then
        self.named[key] = nil
        if math.abs(ts - named) <= LATE then return nil end
    end
    Prune(self.lands, ts, LATE)
    for i = #self.lands, 1, -1 do
        local l = self.lands[i]
        if l.side ~= side then return l end
    end
    Prune(self.fades, ts, EARLY)
    Push(self.fades, { dst = dst, side = side, id = id, name = name, ts = ts })
    return nil
end

-- The engine credited a shatter it inferred; `ref` is its own handle on
-- the record, handed back by Named if the log names the removal after all.
function Corr:Credited(dst, id, ts, ref)
    if not (dst and id) then return end
    self.inferred[Key(dst, id)] = { ts = ts, ref = ref }
end

-- A SPELL_DISPEL / SPELL_STOLEN named a shatterable aura's removal. If the
-- engine already credited it from the fade, returns that credit's `ref`
-- (upgrade it — never count it again); otherwise remembers the name so
-- the fade that follows is not inferred a second time.
function Corr:Named(dst, id, ts)
    if not (dst and id and D.SHATTERABLE[id]) then return nil end
    local key = Key(dst, id)
    local inf = self.inferred[key]
    if inf then
        self.inferred[key] = nil
        if math.abs(ts - inf.ts) <= LATE then return inf.ref end
    end
    -- The removal is the log's own: nothing for a pending fade to wait on
    for i = #self.fades, 1, -1 do
        local f = self.fades[i]
        if f.dst == dst and f.id == id then table.remove(self.fades, i) end
    end
    self.named[key] = ts
    return nil
end
