-- Commander Tracer: the rules.
--
-- Everything that can be decided without a client is decided here: what a
-- combat-log event IS (a hit of yours, a tick on you, a kill), which lane it
-- goes to, what the text says, what colour it is, and where on the screen a
-- number is at any moment of its life. The runtime feeds this file events
-- and paints what it answers; the harness feeds it the same events and
-- asserts on the answers. No WoW API is touched here.

CommanderTracer_Engine = CommanderTracer_Engine or {}
local E = CommanderTracer_Engine
local DATA = CommanderTracer_Data

-- Replaceable, so the harness can pin the scatter
E.random = math.random

-- Combat-log flag bits (the client's constants, spelled out so this file
-- loads with nothing attached)
local AFFIL_MINE = 0x00000001
local TYPE_PET = 0x00001000
local TYPE_GUARDIAN = 0x00002000
local band = bit and bit.band or function(a, b)
    local r, m = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + m end
        a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2
    end
    return r
end

-- ---------------------------------------------------------------------------
-- Numbers
-- ---------------------------------------------------------------------------
local function Separate(n)
    local s = tostring(n)
    local k
    repeat
        s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return s
end

local function Trim(s)
    return (s:gsub("%.0([km])$", "%1"))
end

function E.FormatNumber(n, style)
    n = math.floor((tonumber(n) or 0) + 0.5)
    if style == "SHORT" then
        if math.abs(n) >= 1000000 then return Trim(string.format("%.1fm", n / 1000000)) end
        if math.abs(n) >= 10000 then return Trim(string.format("%.1fk", n / 1000)) end
        return Separate(n)
    end
    if style == "PLAIN" then return tostring(n) end
    return Separate(n)
end

-- ---------------------------------------------------------------------------
-- Colours
-- ---------------------------------------------------------------------------
function E.SchoolColor(mask)
    mask = tonumber(mask) or 1
    local r, g, b, n = 0, 0, 0, 0
    for _, school in ipairs(DATA.SCHOOLS) do
        if band(mask, school.bit) ~= 0 then
            r, g, b, n = r + school.color[1], g + school.color[2], b + school.color[3], n + 1
        end
    end
    if n == 0 then
        local c = DATA.SCHOOLS[1].color
        return c[1], c[2], c[3]
    end
    return r / n, g / n, b / n
end

function E.SchoolName(mask)
    mask = tonumber(mask) or 1
    local names = {}
    for _, school in ipairs(DATA.SCHOOLS) do
        if band(mask, school.bit) ~= 0 then names[#names + 1] = school.name end
    end
    if #names == 0 then return "Physical" end
    return table.concat(names, "")
end

function E.PowerColor(powerType)
    local p = DATA.POWERS[tonumber(powerType) or -1]
    if p then return p.color[1], p.color[2], p.color[3] end
    return 0.4, 0.55, 1
end

function E.PowerName(powerType)
    local p = DATA.POWERS[tonumber(powerType) or -1]
    return p and p.name or "Power"
end

function E.KindColor(kindKey)
    local kind = DATA.KIND_BY_KEY[kindKey]
    if kind and kind.color then return kind.color[1], kind.color[2], kind.color[3] end
    return 1, 1, 1
end

-- The flat palette: the module's own, then any extra list the runtime hands
-- over (Console's, when it is loaded), so a key saved while Console was
-- present still resolves after it is gone.
function E.FlatColor(key, extra)
    for _, c in ipairs(DATA.COLORS) do
        if c.value == key then return c.r, c.g, c.b end
    end
    for _, c in ipairs(extra or {}) do
        if c.value == key and c.r then return c.r, c.g, c.b end
    end
    return 1, 1, 1
end

local GREY = { 0.72, 0.72, 0.72 }

-- cfg: the lane's resolved settings. classColor: {r,g,b} or nil.
function E.Color(cfg, rec, classColor, extraPalette)
    local mode = cfg.ColorMode or "SCHOOL"
    if mode == "CLASS" then
        if classColor then return classColor[1], classColor[2], classColor[3] end
        return 1, 1, 1
    end
    if mode == "FLAT" then
        return E.FlatColor(cfg.FlatColor or "STEEL", extraPalette)
    end
    -- Centre-screen text keeps the colour its old frame would have drawn
    -- it in (a red error, a raid warning's orange, a sanctuary's blue)
    if rec.color then return rec.color[1] or 1, rec.color[2] or 1, rec.color[3] or 1 end
    if rec.missType then return GREY[1], GREY[2], GREY[3] end
    if rec.kind == "Energize" then return E.PowerColor(rec.powerType) end
    if mode == "SCHOOL" and rec.damage then
        return E.SchoolColor(rec.school)
    end
    return E.KindColor(rec.kind)
end

-- ---------------------------------------------------------------------------
-- Classification. One combat-log event in, one record out (or nil when it is
-- nobody's business). ctx = { player = guid, pet = guid }.
--
-- Field layout is the 2.5.x one Commander Meters decodes: a spell prefix is
-- (spellId, spellName, school) at a12..a14 with the suffix from a15; a swing
-- has no prefix (suffix from a12); environmental damage has the type at a12
-- and its suffix from a13.
-- ---------------------------------------------------------------------------
local DAMAGE = {
    SWING_DAMAGE = 0, RANGE_DAMAGE = 3, SPELL_DAMAGE = 3, SPELL_PERIODIC_DAMAGE = 3,
    DAMAGE_SHIELD = 3, DAMAGE_SPLIT = 3, ENVIRONMENTAL_DAMAGE = 1,
}
local MISSED = {
    SWING_MISSED = 0, RANGE_MISSED = 3, SPELL_MISSED = 3, SPELL_PERIODIC_MISSED = 3,
    DAMAGE_SHIELD_MISSED = 3,
}
local HEAL = { SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true }
local ENERGIZE = { SPELL_ENERGIZE = true, SPELL_PERIODIC_ENERGIZE = true }

local function Cap(s)
    s = tostring(s or ""):lower()
    return (s:gsub("^%l", string.upper))
end

local function IsMyPet(ctx, guid, flags)
    if ctx.pet and guid == ctx.pet then return true end
    if type(flags) == "number" and band(flags, AFFIL_MINE) ~= 0
        and (band(flags, TYPE_PET) ~= 0 or band(flags, TYPE_GUARDIAN) ~= 0) then
        return true
    end
    return false
end

function E.Classify(ctx, ts, sub, _, sg, sn, sf, _, dg, dn, df, _,
        a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24)
    if not sub then return nil end
    local me = ctx.player
    local fromMe = sg ~= nil and sg == me
    local fromPet = not fromMe and IsMyPet(ctx, sg, sf)
    local toMe = dg ~= nil and dg == me

    local prefix = DAMAGE[sub]
    if prefix then
        if not (fromMe or fromPet or toMe) then return nil end
        local spellId, spellName, school
        local amount, overkill, resisted, blocked, absorbed, crit
        if prefix == 0 then
            spellName, school = "Melee", 1
            amount, overkill, school, resisted, blocked, absorbed, crit = a12, a13, a14, a15, a16, a17, a18
        elseif prefix == 1 then
            spellName, school = Cap(a12), 1
            amount, overkill, school, resisted, blocked, absorbed, crit = a13, a14, a15, a16, a17, a18, a19
        else
            spellId, spellName, school = a12, a13, a14
            amount, overkill, _, resisted, blocked, absorbed, crit = a15, a16, a17, a18, a19, a20, a21
        end
        if type(amount) ~= "number" then return nil end
        local periodic = (sub == "SPELL_PERIODIC_DAMAGE")
        local kind
        if toMe then
            -- On you, from anyone (self-damage lands here too: Hellfire is
            -- damage taken before it is damage done)
            kind = periodic and "PeriodicTaken" or "DamageTaken"
        elseif fromPet then
            kind = "PetDamage"
        elseif sub == "SWING_DAMAGE" then
            kind = "AutoAttack"
        elseif periodic then
            kind = "PeriodicDone"
        else
            kind = "DamageDone"
        end
        return {
            kind = kind, damage = true, amount = amount, spellId = spellId, spellName = spellName,
            school = tonumber(school) or 1, crit = crit and true or false, periodic = periodic,
            overkill = (type(overkill) == "number" and overkill > 0) and overkill or nil,
            resisted = (type(resisted) == "number" and resisted > 0) and resisted or nil,
            blocked = (type(blocked) == "number" and blocked > 0) and blocked or nil,
            absorbed = (type(absorbed) == "number" and absorbed > 0) and absorbed or nil,
            target = dn, targetGUID = dg, source = sn, sourceGUID = sg, pet = fromPet or nil,
            mergeKey = kind .. "|" .. tostring(spellName),
        }
    end

    prefix = MISSED[sub]
    if prefix then
        if not (fromMe or toMe) then return nil end
        local spellId, spellName, school, missType, amountMissed
        if prefix == 0 then
            spellName, school = "Melee", 1
            missType, amountMissed = a12, a14
        else
            spellId, spellName, school = a12, a13, a14
            missType, amountMissed = a15, a17
        end
        if type(missType) ~= "string" then return nil end
        local kind = toMe and "MissTaken" or "MissDone"
        return {
            kind = kind, missType = missType, amount = type(amountMissed) == "number" and amountMissed or nil,
            spellId = spellId, spellName = spellName, school = tonumber(school) or 1,
            target = dn, targetGUID = dg, source = sn, sourceGUID = sg,
            mergeKey = kind .. "|" .. tostring(spellName) .. "|" .. missType,
        }
    end

    if HEAL[sub] then
        if not (fromMe or toMe) then return nil end
        local amount, overheal, absorbed, crit = a15, a16, a17, a18
        if type(amount) ~= "number" then return nil end
        local periodic = (sub == "SPELL_PERIODIC_HEAL")
        local kind
        if fromMe then
            kind = periodic and "PeriodicHeal" or "HealDone"
        else
            kind = "HealTaken"
        end
        return {
            kind = kind, heal = true, amount = amount, spellId = a12, spellName = a13, school = tonumber(a14) or 2,
            crit = crit and true or false, periodic = periodic,
            overheal = (type(overheal) == "number" and overheal > 0) and overheal or nil,
            absorbed = (type(absorbed) == "number" and absorbed > 0) and absorbed or nil,
            target = dn, targetGUID = dg, source = sn, sourceGUID = sg,
            mergeKey = kind .. "|" .. tostring(a13),
        }
    end

    if ENERGIZE[sub] then
        if not toMe then return nil end
        local amount = a15
        if type(amount) ~= "number" then return nil end
        -- (amount, overEnergize, powerType) on this client; (amount,
        -- powerType) on older layouts. Told apart by whether a third
        -- number is there.
        local powerType
        if type(a17) == "number" then powerType = a17 else powerType = a16 end
        return {
            kind = "Energize", amount = amount, spellId = a12, spellName = a13, school = tonumber(a14) or 1,
            powerType = tonumber(powerType) or 0, periodic = (sub == "SPELL_PERIODIC_ENERGIZE"),
            target = dn, targetGUID = dg, source = sn, sourceGUID = sg,
            mergeKey = "Energize|" .. tostring(a13),
        }
    end

    if sub == "SPELL_ABSORBED" then
        if not toMe then return nil end
        local attackName, shieldId, shieldName, amount, crit
        if type(a12) == "number" then
            attackName = a13
            shieldId, shieldName, amount, crit = a19, a20, a22, a23
        else
            attackName = "Melee"
            shieldId, shieldName, amount, crit = a16, a17, a19, a20
        end
        if type(amount) ~= "number" or type(shieldName) ~= "string" then return nil end
        return {
            kind = "AbsorbTaken", amount = amount, spellId = shieldId, spellName = shieldName,
            school = 1, crit = crit and true or false, attack = attackName,
            target = dn, targetGUID = dg, source = sn, sourceGUID = sg,
            mergeKey = "AbsorbTaken|" .. shieldName,
        }
    end

    if sub == "SPELL_INTERRUPT" then
        if not fromMe then return nil end
        return {
            kind = "Interrupt", spellId = a15, spellName = a16, school = tonumber(a17) or 1,
            tool = a13, toolId = a12, target = dn, targetGUID = dg, source = sn, sourceGUID = sg,
        }
    end

    if sub == "SPELL_DISPEL" or sub == "SPELL_STOLEN" then
        if not fromMe then return nil end
        return {
            kind = "Dispel", spellId = a15, spellName = a16, school = tonumber(a17) or 1,
            tool = a13, toolId = a12, stolen = (sub == "SPELL_STOLEN") or nil,
            target = dn, targetGUID = dg, source = sn, sourceGUID = sg,
        }
    end

    if sub == "PARTY_KILL" then
        if not fromMe then return nil end
        return { kind = "KillingBlow", target = dn, targetGUID = dg, source = sn, sourceGUID = sg }
    end

    if sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REMOVED" then
        if not toMe then return nil end
        local auraType = a15
        local kind
        if sub == "SPELL_AURA_APPLIED" then
            kind = (auraType == "DEBUFF") and "DebuffGained" or "BuffGained"
        else
            if auraType == "DEBUFF" then return nil end
            kind = "BuffFaded"
        end
        return {
            kind = kind, spellId = a12, spellName = a13, school = tonumber(a14) or 1,
            auraType = auraType, source = sn, sourceGUID = sg, target = dn, targetGUID = dg,
            mergeKey = kind .. "|" .. tostring(a13),
        }
    end

    return nil
end

-- The two records that come from the client's own combat-text feed rather
-- than the log
function E.ProcRecord(spellName)
    return { kind = "ProcReady", spellName = spellName, mergeKey = "ProcReady|" .. tostring(spellName) }
end
function E.HonorRecord(amount)
    return { kind = "HonorGained", amount = tonumber(amount) or 0, mergeKey = "HonorGained" }
end
function E.CombatRecord(entering)
    return { kind = "CombatState", entering = entering and true or false }
end

-- Centre-screen text taken off another frame: the zone name, the red and
-- yellow lines, a raid warning, a boss emote, a Commander banner. `text` is
-- the line as the old frame would have written it, `sub` an optional second
-- line, the colour the old frame's (0..1, or 0..255 as the hardcore death
-- notice passes it), `icon` a texture path. Nil when there is nothing to say.
local function Unit(v)
    v = tonumber(v)
    if not v then return nil end
    if v > 1 then v = v / 255 end
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    return v
end

function E.NoticeRecord(kindKey, text, sub, r, g, b, icon)
    if type(text) ~= "string" then return nil end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    if type(sub) ~= "string" or sub:gsub("%s", "") == "" then sub = nil end
    local color
    r, g, b = Unit(r), Unit(g), Unit(b)
    if r and g and b then color = { r, g, b } end
    local kind = DATA.KIND_BY_KEY[kindKey]
    return {
        kind = kindKey, notice = true, text = text, sub = sub, color = color,
        icon = icon or (kind and kind.icon) or nil,
        mergeKey = kindKey .. "|" .. text,
    }
end

-- The zone frames' three lines folded into one record: the zone (or the
-- subzone alone when only it changed) on top, the rest underneath
function E.ZoneRecord(zone, subzone, pvp, r, g, b)
    if zone == "" then zone = nil end
    if subzone == "" or subzone == zone then subzone = nil end
    if pvp == "" then pvp = nil end
    local main, rest = zone, subzone
    if not main then main, rest = subzone, nil end
    if not main then return nil end
    local sub = rest
    if pvp then sub = sub and (sub .. " - " .. pvp) or pvp end
    return E.NoticeRecord("ZoneText", main, sub, r, g, b)
end

-- The red line from the yellow one, by the colour the client gave it
-- (RED_FONT_COLOR is 1, 0.1, 0.1; YELLOW_FONT_COLOR 1, 1, 0)
function E.IsErrorColor(r, g, b)
    r, g, b = tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1
    return r > 0.8 and g < 0.4 and b < 0.4
end

-- ---------------------------------------------------------------------------
-- Routing: which lane, and whether the ledger gets a row too
-- ---------------------------------------------------------------------------
function E.Route(db, rec)
    if not (db and rec and rec.kind) then return nil, false end
    local lane = db[rec.kind .. "Lane"]
    if lane == "OFF" or lane == nil or lane == false then lane = nil end
    local ledger = db[rec.kind .. "Ledger"] and true or false
    -- A kind routed to the ledger lane itself does not need the flag twice
    if lane == "Log" then ledger = false end
    return lane, ledger
end

-- Whether a kind is drawn anywhere at all. A kind that is not is handed back
-- to the frame that drew it before (Blizzard's zone text, a module's banner).
function E.Routed(db, kindKey)
    local lane, ledger = E.Route(db, { kind = kindKey })
    return (lane ~= nil) or ledger
end

-- ---------------------------------------------------------------------------
-- Text. Returns the main line and, for stack lanes, a sub line.
-- ---------------------------------------------------------------------------
local function Mark(amountText, rec, cfg)
    if not rec.crit then return amountText end
    local mark = cfg.CritMark or "BANG"
    if mark == "BANG" then return amountText .. "!" end
    if mark == "WORD" then return amountText .. " crit" end
    if mark == "STARS" then return "*" .. amountText .. "*" end
    return amountText
end

local function Partials(rec, style)
    local parts = {}
    if rec.absorbed then parts[#parts + 1] = E.FormatNumber(rec.absorbed, style) .. " absorbed" end
    if rec.resisted then parts[#parts + 1] = E.FormatNumber(rec.resisted, style) .. " resisted" end
    if rec.blocked then parts[#parts + 1] = E.FormatNumber(rec.blocked, style) .. " blocked" end
    if rec.overheal then parts[#parts + 1] = E.FormatNumber(rec.overheal, style) .. " over" end
    if rec.overkill then parts[#parts + 1] = "overkill" end
    if #parts == 0 then return "" end
    return " (" .. table.concat(parts, ", ") .. ")"
end

local function Count(rec)
    if rec.count and rec.count > 1 then return " x" .. rec.count end
    return ""
end

-- petTag false drops the "Pet: " prefix a pet's numbers otherwise carry
function E.Text(cfg, rec, numberStyle, petTag)
    local fmt = cfg.Format or "AMOUNT"
    local kind = rec.kind
    local style = numberStyle or "SEPARATED"
    local spell = rec.spellName or ""
    local target = rec.target
    local wantSpell = (fmt ~= "AMOUNT" and fmt ~= "AMOUNT_TARGET")
    local wantTarget = (fmt == "AMOUNT_TARGET" or fmt == "FULL")
    local pet = (rec.pet and petTag ~= false) and "Pet: " or ""

    -- Centre-screen text is already a sentence
    if rec.notice then
        return (rec.text or "") .. Count(rec), rec.sub
    end
    -- The moments have their own grammar
    if kind == "KillingBlow" then
        local main = "Killing Blow"
        if target then main = main .. ": " .. target end
        return main, nil
    elseif kind == "Interrupt" then
        local main = "Interrupted " .. spell
        return main, target
    elseif kind == "Dispel" then
        local main = (rec.stolen and "Stole " or "Dispelled ") .. spell
        return main, target
    elseif kind == "ProcReady" then
        return spell .. " ready", nil
    elseif kind == "HonorGained" then
        return "+" .. E.FormatNumber(rec.amount, style) .. " Honor" .. Count(rec), nil
    elseif kind == "CombatState" then
        return rec.entering and "Entering combat" or "Leaving combat", nil
    elseif kind == "BuffGained" then
        return "+ " .. spell .. Count(rec), nil
    elseif kind == "BuffFaded" then
        return "- " .. spell, nil
    elseif kind == "DebuffGained" then
        return spell .. Count(rec), rec.source
    elseif kind == "Energize" then
        local main = "+" .. E.FormatNumber(rec.amount, style) .. " " .. E.PowerName(rec.powerType) .. Count(rec)
        if wantSpell and spell ~= "" then main = main .. " (" .. spell .. ")" end
        return main, nil
    elseif rec.missType then
        local word = DATA.MISS_WORDS[rec.missType] or Cap(rec.missType)
        local main = word
        if wantSpell and spell ~= "" then
            main = (fmt == "SPELL_AMOUNT" or fmt == "FULL") and (spell .. " " .. word) or (word .. " " .. spell)
        end
        if rec.amount and cfg.ShowPartials then main = main .. " (" .. E.FormatNumber(rec.amount, style) .. ")" end
        if wantTarget and target then main = main .. " on " .. target end
        return pet .. main .. Count(rec), (not wantTarget) and target or nil
    elseif kind == "AbsorbTaken" then
        local amount = E.FormatNumber(rec.amount, style)
        local main = amount .. " absorbed" .. Count(rec)
        if wantSpell then main = main .. " (" .. spell .. ")" end
        return main, rec.attack
    end

    -- The numbers
    local amount = Mark(E.FormatNumber(rec.amount or 0, style), rec, cfg)
    local main
    if fmt == "AMOUNT" or fmt == "AMOUNT_TARGET" then
        main = amount
    elseif fmt == "AMOUNT_SPELL" then
        main = amount .. " " .. spell
    else
        main = spell .. " " .. amount
    end
    if wantTarget and target then main = main .. " on " .. target end
    if cfg.ShowPartials then main = main .. Partials(rec, style) end
    main = pet .. main .. Count(rec)
    local sub
    if not wantTarget then sub = target end
    return main, sub
end

-- ---------------------------------------------------------------------------
-- Lanes: the entries in flight and where each one is right now
-- ---------------------------------------------------------------------------
function E.NewLane(key)
    return { key = key, entries = {}, lastSpawn = -1e9, stagger = 0, side = 1, serial = 0 }
end

local STAGGER_WINDOW = 0.3   -- two spawns closer than this get pushed apart
local PUNCH = 0.15           -- seconds a merge or a pop takes to settle

local function Newest(a, b)
    if a.born ~= b.born then return a.born > b.born end
    return a.serial > b.serial
end

-- Returns the entry and whether it was merged into an existing one
function E.Spawn(lane, rec, now, cfg)
    local entries = lane.entries
    local merge = tonumber(cfg.Merge) or 0
    if merge > 0 and rec.mergeKey then
        for _, e in ipairs(entries) do
            if e.mergeKey == rec.mergeKey and (now - e.born) <= merge and not e.dying then
                e.rec.amount = (e.rec.amount or 0) + (rec.amount or 0)
                e.rec.count = (e.rec.count or 1) + 1
                e.rec.crit = e.rec.crit or rec.crit or false
                e.rec.target = rec.target or e.rec.target
                e.punchAt = now
                e.dirty = true
                if cfg.Motion == "STACK" then e.born = now end
                return e, true
            end
        end
    end
    local max = tonumber(cfg.MaxLines) or 12
    while #entries >= max and #entries > 0 do
        local oldest, at = nil, nil
        for i, e in ipairs(entries) do
            if not oldest or e.born < oldest.born or (e.born == oldest.born and e.serial < oldest.serial) then
                oldest, at = e, i
            end
        end
        table.remove(entries, at)
    end
    lane.serial = lane.serial + 1
    if now - lane.lastSpawn < STAGGER_WINDOW then
        lane.stagger = lane.stagger + 1
    else
        lane.stagger = 0
    end
    lane.lastSpawn = now
    local side
    if cfg.Side == "LEFT" then side = -1
    elseif cfg.Side == "RIGHT" then side = 1
    else lane.side = -lane.side; side = lane.side end
    local e = {
        rec = rec, born = now, mergeKey = rec.mergeKey, serial = lane.serial, dirty = true,
        stagger = lane.stagger, side = side,
        jitter = (E.random() * 2 - 1) * (tonumber(cfg.Spread) or 0),
        x = 0, y = 0, alpha = 0, scale = 1,
    }
    if cfg.Motion == "STACK" then
        e.x = -(tonumber(cfg.SlideIn) or 0)
        e.y = nil   -- takes its slot on the first step
    end
    entries[#entries + 1] = e
    return e, false
end

local function Ease(t)
    if t < 0 then return 0 elseif t > 1 then return 1 end
    return 1 - (1 - t) * (1 - t)
end

-- Advance every entry in the lane to `now`. lineH is the height one entry
-- occupies (the stagger and the stack use it). Expired entries are removed.
-- Returns how many are left.
function E.Step(lane, now, cfg, lineH)
    local entries = lane.entries
    local dt = now - (lane.lastStep or now)
    if dt < 0 then dt = 0 end
    if dt > 0.25 then dt = 0.25 end
    lane.lastStep = now
    local motion = cfg.Motion or "SCROLL"
    local dur = tonumber(cfg.Duration) or 2
    local fade = math.min(0.6, dur * 0.3)
    local speed = tonumber(cfg.Speed) or 70
    local dir = (cfg.Direction == "DOWN") and -1 or 1
    local critScale = tonumber(cfg.CritScale) or 1.5
    lineH = lineH or 20

    -- expire
    for i = #entries, 1, -1 do
        if now - entries[i].born >= dur then table.remove(entries, i) end
    end

    if motion == "STACK" then
        table.sort(entries, Newest)
    end

    for i, e in ipairs(entries) do
        local age = now - e.born
        local alpha = 1
        if age > dur - fade then alpha = (dur - age) / fade end
        if age < 0.08 then alpha = math.min(alpha, age / 0.08) end
        local scale = 1
        if e.rec.crit and critScale > 1 then
            scale = critScale
            if cfg.CritPunch ~= false and age < 0.12 then
                scale = critScale * (1 + 0.45 * (1 - age / 0.12))
            end
        end
        if e.punchAt and now - e.punchAt < PUNCH then
            scale = scale * (1 + 0.3 * (1 - (now - e.punchAt) / PUNCH))
        end

        if motion == "SCROLL" then
            e.x = e.jitter
            e.y = dir * speed * age - dir * e.stagger * lineH
        elseif motion == "FOUNTAIN" then
            local vx = e.side * speed * 1.1
            local vy = speed * 2.4
            local g = speed * 3.2
            e.x = e.jitter * 0.3 + vx * age
            e.y = dir * (vy * age - 0.5 * g * age * age)
        elseif motion == "POP" then
            e.x = 0
            e.y = dir * e.stagger * lineH
            if age < PUNCH then scale = scale * (1 + 0.35 * (1 - age / PUNCH)) end
        else -- STACK
            local slot = i - 1
            local ty = dir * slot * lineH
            if e.y == nil then e.y = ty end
            e.y = e.y + (ty - e.y) * math.min(1, dt * 14)
            local slide = tonumber(cfg.SlideIn) or 0
            e.x = -slide * (1 - Ease(age / 0.2))
        end
        e.alpha = alpha
        e.scale = scale
    end
    return #entries
end

-- The height one entry takes in a lane, from its text size and icon
function E.LineHeight(cfg)
    local size = tonumber(cfg.FontSize) or 16
    local h = size * 1.25
    if cfg.Motion == "STACK" then
        if cfg.Sub ~= false then h = h + size * 0.85 end
        h = h + 8
        local icon = (cfg.Icon ~= "NONE") and (tonumber(cfg.IconSize) or 16) or 0
        if icon + 8 > h then h = icon + 8 end
    end
    return h
end

-- ---------------------------------------------------------------------------
-- The test volley: a scripted few seconds of fabricated events, one of
-- everything, so every lane can be placed and sized without a target dummy.
-- Times are offsets from the moment the volley starts.
-- ---------------------------------------------------------------------------
function E.TestVolley()
    local v = {}
    local function at(t, rec) v[#v + 1] = { at = t, rec = rec } end
    at(0.0, { kind = "DamageDone", damage = true, amount = 1204, spellName = "Fireball", spellId = 27070, school = 4, target = "Gankmage", mergeKey = "DamageDone|Fireball" })
    at(0.0, { kind = "DamageTaken", damage = true, amount = 618, spellName = "Mortal Strike", spellId = 30330, school = 1, source = "Bonecrush", mergeKey = "DamageTaken|Mortal Strike" })
    at(0.3, { kind = "HealTaken", heal = true, amount = 1450, spellName = "Flash of Light", spellId = 27137, school = 2, source = "Lightbringer", mergeKey = "HealTaken|Flash of Light" })
    at(0.5, { kind = "AutoAttack", damage = true, amount = 212, spellName = "Melee", school = 1, target = "Gankmage", mergeKey = "AutoAttack|Melee" })
    at(0.8, { kind = "DamageDone", damage = true, amount = 2410, crit = true, spellName = "Fireball", spellId = 27070, school = 4, target = "Gankmage", mergeKey = "DamageDone|Fireball" })
    at(0.9, { kind = "PeriodicTaken", damage = true, amount = 96, spellName = "Corruption", spellId = 27216, school = 32, source = "Dotlord", periodic = true, mergeKey = "PeriodicTaken|Corruption" })
    at(1.1, { kind = "HealDone", heal = true, amount = 1730, spellName = "Flash Heal", spellId = 25235, school = 2, target = "Leafheal", mergeKey = "HealDone|Flash Heal" })
    at(1.3, { kind = "MissDone", missType = "RESIST", spellName = "Frostbolt", spellId = 27072, school = 16, target = "Gankmage", mergeKey = "MissDone|Frostbolt|RESIST" })
    at(1.5, { kind = "Energize", amount = 240, spellName = "Judgement of Wisdom", spellId = 27164, powerType = 0, mergeKey = "Energize|Judgement of Wisdom" })
    at(1.6, { kind = "PeriodicHeal", heal = true, amount = 250, spellName = "Renew", spellId = 25222, school = 2, periodic = true, target = "Leafheal", mergeKey = "PeriodicHeal|Renew" })
    at(1.7, { kind = "PeriodicDone", damage = true, amount = 187, spellName = "Immolate", spellId = 27215, school = 4, periodic = true, target = "Gankmage", mergeKey = "PeriodicDone|Immolate" })
    at(1.9, { kind = "MissTaken", missType = "DODGE", spellName = "Melee", school = 1, source = "Bonecrush", mergeKey = "MissTaken|Melee|DODGE" })
    at(2.1, { kind = "AbsorbTaken", amount = 402, spellName = "Power Word: Shield", spellId = 25218, attack = "Sinister Strike", mergeKey = "AbsorbTaken|Power Word: Shield" })
    at(2.3, { kind = "Interrupt", spellName = "Polymorph", spellId = 12826, tool = "Kick", target = "Gankmage" })
    at(2.6, { kind = "DebuffGained", spellName = "Polymorph", spellId = 12826, auraType = "DEBUFF", source = "Gankmage", mergeKey = "DebuffGained|Polymorph" })
    at(2.9, { kind = "PetDamage", damage = true, amount = 310, spellName = "Claw", spellId = 27049, school = 1, pet = true, target = "Gankmage", mergeKey = "PetDamage|Claw" })
    at(3.1, { kind = "HealDone", heal = true, amount = 3120, crit = true, spellName = "Flash Heal", spellId = 25235, school = 2, target = "Leafheal", mergeKey = "HealDone|Flash Heal" })
    at(3.3, { kind = "ProcReady", spellName = "Overpower", mergeKey = "ProcReady|Overpower" })
    at(3.6, { kind = "Dispel", spellName = "Renew", spellId = 25222, tool = "Purge", target = "Leafheal" })
    at(3.8, { kind = "BuffGained", spellName = "Inner Fire", spellId = 10952, auraType = "BUFF", mergeKey = "BuffGained|Inner Fire" })
    at(4.0, { kind = "HonorGained", amount = 15, mergeKey = "HonorGained" })
    at(4.3, { kind = "DamageDone", damage = true, amount = 1180, spellName = "Fireball", spellId = 27070, school = 4, target = "Gankmage", mergeKey = "DamageDone|Fireball" })
    at(4.5, { kind = "KillingBlow", target = "Gankmage" })
    at(4.8, E.NoticeRecord("ZoneText", "Shattrath City", "Sanctuary", 0.41, 0.8, 0.94))
    at(5.0, E.NoticeRecord("ErrorText", "Not enough mana", nil, 1, 0.1, 0.1))
    at(5.2, E.NoticeRecord("InfoText", "Boar Ribs: 3/6", nil, 1, 1, 0))
    at(5.4, E.NoticeRecord("RaidWarning", "Interrupt the Priest", nil, 1, 0.28, 0))
    at(5.6, E.NoticeRecord("BossEmote", "Gruul grows in size!", nil, 1, 0.5, 0))
    at(5.8, E.NoticeRecord("CommanderAlert", "Production ready", "Production", 0.3, 1, 0.4))
    return v
end
