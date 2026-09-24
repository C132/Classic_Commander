-- Commander Plates: the rules, with no client attached.
--
-- Everything in this file is a pure function of its arguments -- what the
-- auras on a unit are, who the unit is, what the settings say -- and returns
-- what the plate should draw. It never calls a WoW API, which is what lets
-- Harness/plates_engine_smoke.lua run it under plain luajit and assert, for
-- instance, that a Polymorph beats a Hamstring for the big slot, that a
-- friendly plate's debuff row shows the Curse the druid can lift and not the
-- Rend she cannot, and that a whitelist entry survives every filter.
--
-- The runtime (CommanderPlates.lua) turns C_UnitAuras records into the plain
-- aura tables this file expects, and turns the answer into textures.

CommanderPlates_Engine = CommanderPlates_Engine or {}
local E = CommanderPlates_Engine

local DATA = CommanderPlates_Data

-- ---------------------------------------------------------------------------
-- Lists typed by the user. "Polymorph, 118, Sap" -> names lower-cased, ids as
-- numbers. Tolerant of every separator people reach for.
-- ---------------------------------------------------------------------------
function E.ParseList(text)
    local list = { names = {}, ids = {}, count = 0 }
    if type(text) ~= "string" then return list end
    for token in text:gmatch("[^,;\n]+") do
        token = token:gsub("^%s+", ""):gsub("%s+$", "")
        if token ~= "" then
            local id = tonumber(token)
            if id then
                list.ids[id] = true
            else
                list.names[token:lower()] = true
            end
            list.count = list.count + 1
        end
    end
    return list
end

function E.InList(list, name, spellId)
    if not list or list.count == 0 then return false end
    if spellId and list.ids[spellId] then return true end
    if name and list.names[name:lower()] then return true end
    return false
end

-- ---------------------------------------------------------------------------
-- What IS this aura. The DR table by id first (every rank, the server's own
-- word on what is control), then the hand-written names.
-- ---------------------------------------------------------------------------
function E.Classify(aura)
    local kind = aura.spellId and DATA.CC_BY_SPELL[aura.spellId]
    if not kind and aura.name then
        kind = DATA.NOTABLE[aura.name]
    end
    return kind
end

local function KindEnabled(kind, S)
    local spec = DATA.KIND[kind]
    if not spec then return false end
    if spec.toggle and S(spec.toggle) == false then return false end
    return true
end

local function IsControl(kind)
    return kind ~= nil and DATA.CONTROL_KINDS[kind] == true
end

-- Larger priority wins. Ties: the one that ends LATER, since that is the
-- control you will still be sitting in when the other drops. A 0 expiration
-- means "no duration known" and sorts as if it ended last.
local function BigBetter(a, b)
    local pa = DATA.KIND[a.kind].priority
    local pb = DATA.KIND[b.kind].priority
    if pa ~= pb then return pa > pb end
    local ea = (a.expirationTime and a.expirationTime > 0) and a.expirationTime or math.huge
    local eb = (b.expirationTime and b.expirationTime > 0) and b.expirationTime or math.huge
    return ea > eb
end

-- ---------------------------------------------------------------------------
-- Sorting a row.
-- ---------------------------------------------------------------------------
local function ExpiryKey(aura)
    if aura.expirationTime and aura.expirationTime > 0 then return aura.expirationTime end
    return math.huge
end

local SORTS = {
    -- What matters most first, soonest-ending first within that
    PRIORITY = function(a, b)
        local pa = a.kind and DATA.KIND[a.kind].priority or 0
        local pb = b.kind and DATA.KIND[b.kind].priority or 0
        if pa ~= pb then return pa > pb end
        if a.isMine ~= b.isMine then return a.isMine == true end
        local ea, eb = ExpiryKey(a), ExpiryKey(b)
        if ea ~= eb then return ea < eb end
        return (a.name or "") < (b.name or "")
    end,
    -- Soonest-ending first, permanents last
    TIME = function(a, b)
        local ea, eb = ExpiryKey(a), ExpiryKey(b)
        if ea ~= eb then return ea < eb end
        return (a.name or "") < (b.name or "")
    end,
    -- Longest remaining first
    TIME_DESC = function(a, b)
        local ea, eb = ExpiryKey(a), ExpiryKey(b)
        if ea ~= eb then return ea > eb end
        return (a.name or "") < (b.name or "")
    end,
    NAME = function(a, b)
        return (a.name or "") < (b.name or "")
    end,
}

-- ---------------------------------------------------------------------------
-- The decision. auras is a list of plain tables:
--   name, spellId, icon, isHarmful, isMine, isStealable, dispelName,
--   applications, duration, expirationTime
-- ctx:
--   isFriend, isPlayer, canDispel (set of dispel types), canPurge (bool),
--   S (settings accessor), whitelist, blacklist (parsed lists)
-- Returns { big = aura|nil, debuffs = {...}, buffs = {...} }; every aura
-- returned carries .kind and .tint (nil tint = draw plain).
-- ---------------------------------------------------------------------------
function E.Select(auras, ctx)
    local S = ctx.S
    local out = { debuffs = {}, buffs = {} }
    local isFriend = ctx.isFriend == true
    local canDispel = ctx.canDispel or {}

    local debuffMode = isFriend and S("FriendDebuffs") or S("EnemyDebuffs")
    local buffMode = isFriend and S("FriendBuffs") or S("EnemyBuffs")
    -- Duration caps: anything that lasts longer than this is scenery (the
    -- half-hour raid buffs) and leaves the row. A duration of 0 -- permanent,
    -- or unknown to the client -- counts as over any cap. The whitelist, the
    -- big slot and purgeable enemy buffs are exempt.
    local debuffCap = tonumber(S("DebuffMaxDuration")) or 0
    local buffCap = tonumber(S("BuffMaxDuration")) or 0
    local function OverCap(aura, cap)
        if cap <= 0 then return false end
        local d = aura.duration or 0
        return d <= 0 or d > cap
    end
    local bigAllowed = S("CcEnable") ~= false
        and ((isFriend and S("CcOnFriends") ~= false) or (not isFriend and S("CcOnEnemies") ~= false))

    local big
    for _, aura in ipairs(auras) do
        local listed = E.InList(ctx.whitelist, aura.name, aura.spellId)
        local banned = (not listed) and E.InList(ctx.blacklist, aura.name, aura.spellId)
        if not banned then
            local kind = E.Classify(aura)
            if kind and not KindEnabled(kind, S) then kind = nil end
            aura.kind = kind
            local spec = kind and DATA.KIND[kind]
            aura.tint = spec and spec.tint or nil

            -- The big slot: control on anyone, immunity only if asked
            if bigAllowed and spec and spec.big then
                if IsControl(kind) or (kind == "IMMUNITY" and S("CcImmunities") ~= false) then
                    if not big or BigBetter(aura, big) then big = aura end
                end
            end

            if aura.isHarmful then
                local show
                if listed then
                    show = true
                elseif debuffMode == "OFF" then
                    show = false
                elseif debuffMode == "ALL" then
                    show = true
                elseif isFriend then
                    local dispellable = aura.dispelName and canDispel[aura.dispelName] == true
                    if dispellable then
                        aura.dispellable = true
                        aura.tint = DATA.DISPEL_TINT[aura.dispelName] or aura.tint
                    end
                    if debuffMode == "DISPELLABLE" then
                        show = dispellable
                    else -- NOTABLE
                        show = dispellable or kind ~= nil
                    end
                else
                    if debuffMode == "MINE" then
                        show = aura.isMine == true
                    else -- MINE_NOTABLE
                        show = aura.isMine == true or kind ~= nil
                    end
                end
                if show and not listed and OverCap(aura, debuffCap) then show = false end
                if show then out.debuffs[#out.debuffs + 1] = aura end
            else
                local show
                local purgeable = (not isFriend) and aura.isStealable == true and ctx.canPurge == true
                if purgeable then aura.purgeable = true end
                if listed then
                    show = true
                elseif buffMode == "OFF" then
                    show = false
                elseif buffMode == "ALL" then
                    show = true
                elseif isFriend then
                    if buffMode == "MINE" then
                        show = aura.isMine == true
                    else -- MINE_NOTABLE
                        show = aura.isMine == true or kind ~= nil
                    end
                else
                    if buffMode == "NOTABLE" then
                        show = kind ~= nil
                    elseif buffMode == "PURGEABLE" then
                        show = purgeable
                    else -- NOTABLE_PURGEABLE
                        show = kind ~= nil or purgeable
                    end
                end
                -- A purgeable buff is exempt: the long ones (Fortitude, Intellect)
                -- are precisely what a priest or shaman is looking to strip
                if show and not listed and not purgeable and OverCap(aura, buffCap) then show = false end
                if show then out.buffs[#out.buffs + 1] = aura end
            end
        end
    end

    out.big = big

    -- The big icon is already on screen once; drawing it again in the row is
    -- clutter, unless the user wants the row complete.
    if big and S("CcHideDuplicate") ~= false then
        for _, row in ipairs({ out.debuffs, out.buffs }) do
            for i = #row, 1, -1 do
                if row[i] == big then table.remove(row, i) end
            end
        end
    end

    local sorter = SORTS[S("AuraSort") or "PRIORITY"] or SORTS.PRIORITY
    table.sort(out.debuffs, sorter)
    table.sort(out.buffs, sorter)

    local maxDebuffs = tonumber(S("DebuffMax")) or 8
    local maxBuffs = tonumber(S("BuffMax")) or 4
    while #out.debuffs > maxDebuffs do table.remove(out.debuffs) end
    while #out.buffs > maxBuffs do table.remove(out.buffs) end

    return out
end

-- ---------------------------------------------------------------------------
-- Where the icons of a row go: offsets from the row's anchor, so the runtime
-- only has to SetPoint. Returns { {x, y}, ... } for count icons.
--   grow   CENTER | LEFT | RIGHT   (which way the row extends)
--   perRow how many before wrapping to a second line ABOVE the first
-- ---------------------------------------------------------------------------
function E.RowLayout(count, size, spacing, grow, perRow)
    local slots = {}
    perRow = math.max(1, perRow or count)
    for i = 1, count do
        local col = (i - 1) % perRow
        local line = math.floor((i - 1) / perRow)
        local inLine = math.min(perRow, count - line * perRow)
        local x
        if grow == "LEFT" then
            x = -(col * (size + spacing)) - size / 2
        elseif grow == "RIGHT" then
            x = col * (size + spacing) + size / 2
        else
            local total = inLine * size + (inLine - 1) * spacing
            x = -total / 2 + col * (size + spacing) + size / 2
        end
        slots[i] = { x, line * (size + spacing) + size / 2 }
    end
    return slots
end

-- ---------------------------------------------------------------------------
-- The clickable region. Blizzard's own hit box is the health bar plus ten
-- pixels each side and half the bar's height above and below; this returns
-- the offsets to add on top of it, or a zero-area box for a plate the mouse
-- should pass straight through.
-- Returns { top, bottom, sides } in pixels (all 0 and clickThrough = false
-- means "leave Blizzard's alone").
-- ---------------------------------------------------------------------------
function E.HitBox(S, isFriend, inInstance)
    local through = false
    if isFriend then
        local mode = S("FriendlyClickThrough") or "NEVER"
        through = mode == "ALWAYS" or (mode == "INSTANCES" and inInstance == true)
    end
    if through then
        return { clickThrough = true, top = 0, bottom = 0, sides = 0 }
    end
    return {
        clickThrough = false,
        top = tonumber(S("HitBoxTop")) or 0,
        bottom = tonumber(S("HitBoxBottom")) or 0,
        sides = tonumber(S("HitBoxSides")) or 0,
    }
end

-- ---------------------------------------------------------------------------
-- NPC plates worth not having at all. A Snake Trap puts up to ten plates on
-- the screen at once, every one of them between you and the hunter.
-- ---------------------------------------------------------------------------
function E.IsHiddenNpc(unitName, isPlayer, list)
    if isPlayer or type(unitName) ~= "string" then return false end
    return E.InList(list, unitName, nil)
end

-- ---------------------------------------------------------------------------
-- Totems. "Searing Totem IV" -> the Searing Totem entry.
-- ---------------------------------------------------------------------------
function E.TotemInfo(unitName)
    if type(unitName) ~= "string" then return nil end
    local base = unitName:gsub("%s+[IVX]+$", "")
    local info = DATA.TOTEMS[base]
    if info then return info, base end
    return nil
end

-- ---------------------------------------------------------------------------
-- Timers. Under three seconds a tenth matters (a Sap about to break, a Fear
-- you can pre-cast into); above that whole seconds; above a minute, minutes.
-- ---------------------------------------------------------------------------
function E.FormatTime(remaining)
    if not remaining or remaining <= 0 then return "" end
    if remaining < 3 then return string.format("%.1f", remaining) end
    if remaining < 60 then return string.format("%d", math.floor(remaining + 0.5)) end
    return string.format("%dm", math.floor(remaining / 60 + 0.5))
end

-- ---------------------------------------------------------------------------
-- Healers, remembered by GUID. A combat log tells you a shaman healed once;
-- it does not tell you when they stopped being a healer, so the memory
-- expires rather than persists -- long enough for a game, short enough that a
-- hybrid who healed once in the opener is not marked all evening.
-- ---------------------------------------------------------------------------
local HealerBook = {}
HealerBook.__index = HealerBook

function E.NewHealerBook(ttl)
    return setmetatable({ seen = {}, ttl = ttl or 600 }, HealerBook)
end

function HealerBook:Mark(guid, now)
    if guid then self.seen[guid] = now end
end

function HealerBook:Is(guid, now)
    local at = guid and self.seen[guid]
    if not at then return false end
    if now - at > self.ttl then
        self.seen[guid] = nil
        return false
    end
    return true
end

function HealerBook:Prune(now)
    for guid, at in pairs(self.seen) do
        if now - at > self.ttl then self.seen[guid] = nil end
    end
end

function HealerBook:Count()
    local n = 0
    for _ in pairs(self.seen) do n = n + 1 end
    return n
end

function E.IsHealerSpell(name)
    return name ~= nil and DATA.HEALER_SPELLS[name] == true
end

-- ---------------------------------------------------------------------------
-- Cast emphasis: the default list plus whatever the user added, minus what
-- they removed.
-- ---------------------------------------------------------------------------
function E.BuildEmphasis(extraText, removeText)
    local set = {}
    for _, name in ipairs(DATA.CAST_EMPHASIS) do set[name:lower()] = true end
    local extra = E.ParseList(extraText)
    for name in pairs(extra.names) do set[name] = true end
    local remove = E.ParseList(removeText)
    for name in pairs(remove.names) do set[name] = nil end
    return set
end

function E.IsEmphasised(set, spellName)
    return spellName ~= nil and set[spellName:lower()] == true
end

-- ---------------------------------------------------------------------------
-- Which dispel types a class can lift, and whether it can purge.
-- ---------------------------------------------------------------------------
function E.DispelSet(class)
    return DATA.CLASS_DISPEL[class] or {}
end

function E.CanPurge(class)
    return DATA.CLASS_PURGE[class] == true
end

-- ===========================================================================
-- The radial plate: the rules behind it, still with no client attached.
--
-- A radial plate is a disc. The unit's face (class, portrait) sits in the
-- middle, the health bar is an arc around it, power an arc inside that, the
-- cast an arc outside, and the auras orbit the whole thing. Angles here run
-- the way the client's own Cooldown sweep runs -- CLOCKWISE FROM TWELVE
-- O'CLOCK, in degrees. A health or power arc ENDS at twelve and begins
-- (1 - f) of the way round, so as health drops its edge walks clockwise and
-- a marker at "20% health" sits at 288 degrees, a little before ten.
-- ===========================================================================

-- Where an aura orbit is centred, as a clock position
E.RADIAL_ARCS = {
    TOP = 0, TOP_RIGHT = 45, RIGHT = 90, BOTTOM_RIGHT = 135,
    BOTTOM = 180, BOTTOM_LEFT = 225, LEFT = 270, TOP_LEFT = 315,
}

-- The fixed places on the rim a badge sits, chosen to clear the default
-- orbits (debuffs over the top, buffs down the right) and the name beneath
-- They sit just OUTSIDE the rings, never on them: a badge on the health band
-- hides the very health it sits on. The class badge and the level share a
-- place because only players get the one and only NPCs the other.
E.RADIAL_BADGES = { raid = 225, healer = 315, level = 135, class = 135, trinket = 45 }

-- Which plates go radial. A totem never does: its icon IS the plate, and
-- the totem path stays exactly as it was.
function E.WantRadial(S, isPlayer, isFriend, isTotem)
    if isTotem then return false end
    if S("PlateStyle") ~= "RADIAL" then return false end
    local scope = S("RadialUnits") or "ALL"
    if scope == "PLAYERS" then return isPlayer == true end
    if scope == "ENEMIES" then return isFriend ~= true end
    if scope == "ENEMY_PLAYERS" then return isPlayer == true and isFriend ~= true end
    return true
end

-- A point on a circle, fraction of the way round clockwise from twelve.
-- Returns x, y (y up, the client's convention) and the angle in radians,
-- which is also what Texture:SetRotation wants negated.
function E.ArcPoint(radius, fraction)
    local theta = (fraction or 0) * math.pi * 2
    return math.sin(theta) * radius, math.cos(theta) * radius, theta
end

-- The ring art ships in six weights with the thickness baked in as the
-- inner radius over the outer. For a band `thickness` pixels thick with its
-- outer edge at `outer`, the nearest weight.
function E.RingWeight(outer, thickness, ratios)
    if not outer or outer <= 0 then return 3 end
    local wanted = 1 - (thickness or 0) / outer
    local best, bestDiff = 1, math.huge
    for i = 1, #ratios do
        local diff = math.abs(ratios[i] - wanted)
        if diff < bestDiff then best, bestDiff = i, diff end
    end
    return best
end

-- The radii, from the middle out. cfg: size (diameter to the health ring's
-- outer edge), healthThick, power (bool), powerThick, cast (bool), castThick,
-- auraSize, auraGap. Every band keeps a pixel of air either side so two
-- colours never bleed into one.
function E.RadialRadii(cfg)
    local r = {}
    r.health = cfg.size / 2
    r.healthInner = r.health - cfg.healthThick
    local inner = r.healthInner - 1
    if cfg.power then
        r.power = inner
        r.powerInner = inner - cfg.powerThick
        inner = r.powerInner - 1
    end
    r.core = math.max(4, inner)
    local outer = r.health
    if cfg.cast then
        r.castInner = outer + 1
        r.cast = r.castInner + cfg.castThick
        outer = r.cast
    end
    r.outer = outer
    r.orbit = outer + (cfg.auraGap or 2) + (cfg.auraSize or 16) / 2
    return r
end

-- Aura icons round an orbit. `count` icons `size` across, `spacing` apart
-- along the circle, starting from the clock angle `center`. `grow` says
-- which way: CENTER fans them out both ways from it, CLOCKWISE and
-- COUNTERCLOCKWISE start ON it and run one way. An orbit may span at most
-- `maxArc` degrees; the rest start a second orbit one icon further out,
-- laid the same way. Returns { { x, y, deg, orbit }, ... }.
function E.OrbitLayout(count, radius, size, spacing, center, maxArc, grow)
    local slots = {}
    if count <= 0 then return slots end
    maxArc = math.max(0, math.min(360, maxArc or 180))
    center = center or 0
    local placed, orbit = 0, 1
    while placed < count do
        local chord = math.min(size + spacing, radius * 2 - 0.001)
        local step = math.deg(2 * math.asin(chord / (2 * radius)))
        local capacity = math.floor(maxArc / step) + 1
        if capacity * step > 360 then capacity = math.max(1, math.floor(360 / step)) end
        local n = math.min(capacity, count - placed)
        for i = 1, n do
            local deg
            if grow == "CLOCKWISE" then
                deg = center + (i - 1) * step
            elseif grow == "COUNTERCLOCKWISE" then
                deg = center - (i - 1) * step
            else
                deg = center + (i - (n + 1) / 2) * step
            end
            local theta = math.rad(deg)
            slots[#slots + 1] = { math.sin(theta) * radius, math.cos(theta) * radius, deg % 360, orbit }
        end
        placed = placed + n
        radius = radius + size + spacing
        orbit = orbit + 1
    end
    return slots
end

-- How far the placed icons reach out to the left and right in a horizontal
-- band `band` pixels either side of the centre line: where a target arrow
-- can go without landing on an aura
function E.OrbitSideExtents(slots, size, band)
    local left, right = 0, 0
    for _, s in ipairs(slots) do
        if math.abs(s[2]) < band + size / 2 then
            if s[1] > 0 then right = math.max(right, s[1] + size / 2) end
            if s[1] < 0 then left = math.max(left, -s[1] + size / 2) end
        end
    end
    return left, right
end

-- A fraction, safely. Health of 0/0 (a unit the client has not filled in
-- yet) is FULL rather than empty: an empty ring means dead.
function E.Fraction(cur, max)
    if not cur or not max or max <= 0 then return 1 end
    local f = cur / max
    if f < 0 then return 0 end
    if f > 1 then return 1 end
    return f
end

-- What the middle of the disc says.
--   SMART    the arena number in an arena, the percent once hurt, else nothing
--   PERCENT  always the percent
--   HEALTH   the health value (the combat-log estimate for enemy players)
--   ARENA    the arena number only
--   NONE
function E.CoreText(mode, fraction, value, arena)
    if mode == "NONE" then return "" end
    if mode == "ARENA" then return arena and tostring(arena) or "" end
    if mode == "SMART" then
        if arena then return tostring(arena) end
        if fraction >= 0.995 then return "" end
        return string.format("%d", math.floor(fraction * 100 + 0.5))
    end
    if mode == "HEALTH" and value then
        if value >= 1e6 then return string.format("%.1fm", value / 1e6) end
        if value >= 1e4 then return string.format("%dk", math.floor(value / 1e3 + 0.5)) end
        if value >= 1e3 then return string.format("%.1fk", value / 1e3) end
        return string.format("%d", value)
    end
    return string.format("%d%%", math.floor(fraction * 100 + 0.5))
end

-- Threat as a warning colour, or nil for "nothing to say". status is
-- UnitThreatSituation("player", unit): nil off the table, 0 not tanking and
-- below the tank, 1 not tanking but above it, 2 tanking insecurely, 3 tanking.
--   DPS   warn as it turns toward YOU
--   TANK  warn as it turns AWAY
function E.ThreatTint(mode, status)
    if status == nil or mode == "OFF" or mode == nil then return nil end
    if mode == "TANK" then
        if status == 3 then return nil end
        if status == 2 then return "ORANGE" end
        return "RED"
    end
    if status == 3 or status == 2 then return "RED" end
    if status == 1 then return "ORANGE" end
    return nil
end

-- The damage trail: the ghost of health just lost, catching up at `rate`
-- (share of the ring per second) after holding for `hold` seconds. Healing
-- snaps it straight to the new value -- a trail says "this is what the last
-- hit took", and there is nothing to say about a heal.
-- Returns the new trail value and whether it is still moving.
function E.TrailStep(trail, target, since, dt, hold, rate)
    if not trail or target >= trail then return target, false end
    if since < hold then return trail, true end
    local nextValue = trail - rate * dt
    if nextValue <= target then return target, false end
    return nextValue, true
end

-- Combo points: grey to gold, and red on the finisher's full five
function E.ComboTint(n, max)
    if n >= (max or 5) then return 1.0, 0.25, 0.2 end
    return 1.0, 0.82, 0.2
end

-- Diminishing returns as the disc draws them: Commander Diminish's open
-- categories (its DR:Strip rows) turned into icons. The label is what the
-- NEXT cast in the category would do -- half, a quarter, or nothing at all --
-- because that is the question a sheep or a stun is waiting on. The sweep is
-- the reset: `reset` seconds from the aura fading, frozen (no sweep) while
-- something in the category is still up. `iconFor(spellId)` names the art.
E.DR_NEXT_LABEL = { [2] = "\194\189", [3] = "\194\188", [4] = "X" }
E.DR_NEXT_TINT = {
    [2] = { 0.98, 0.86, 0.35 },
    [3] = { 0.98, 0.55, 0.28 },
    [4] = { 0.92, 0.26, 0.26 },
}

function E.DrRows(open, reset, iconFor, out)
    out = out or {}
    local n = 0
    for _, o in ipairs(open or {}) do
        if (o.bracket or 1) > 1 or o.held then
            local b = math.max(2, math.min(4, o.bracket or 2))
            local tint = E.DR_NEXT_TINT[b]
            n = n + 1
            local row = out[n] or {}
            out[n] = row
            row.cat = o.cat
            row.icon = iconFor and iconFor(o.last) or nil
            row.label = E.DR_NEXT_LABEL[b]
            row.r, row.g, row.b = tint[1], tint[2], tint[3]
            if o.resetAt and not o.held then
                row.start, row.duration = o.resetAt - reset, reset
            else
                row.start, row.duration = nil, nil
            end
        end
    end
    for i = #out, n + 1, -1 do out[i] = nil end
    return out
end

-- Whose target is worth a ring: "is that one looking at ME" is the question
-- an arena answers with a hard switch and a battleground with a gank
function E.WantTargetsYou(mode, isPlayer, isFriend)
    if isFriend or mode == "OFF" or mode == nil then return false end
    if mode == "ENEMY_PLAYERS" then return isPlayer == true end
    return true
end

-- The masked clock wipe over the face: fraction `p` darkened, clockwise from
-- twelve. It is drawn with two copies of a right-half disc -- the first
-- clipped to the right half of the face, the second to the left -- each turned
-- CLOCKWISE by the degrees returned. At p = 0 both halves are turned out of
-- their clips; at 0.5 the right one fills its half; at 1 both do.
function E.WipeAngles(p)
    if not p or p < 0 then p = 0 elseif p > 1 then p = 1 end
    return math.min(p, 0.5) * 360 - 180, math.max(p, 0.5) * 360 - 180
end
