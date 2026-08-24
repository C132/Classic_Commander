-- Commander Dossier: the data layer — pure Lua, zero frames, zero WoW API.
-- The UI translates the combat log into plain calls on this engine; the
-- engine owns everything that must be exact and testable: the diminishing
-- return windows, the persistent intelligence records, and the spec
-- inference. Nothing in here reads a unit, draws a pixel, or knows what a
-- frame is — which is why the fixture harness can drive a whole arena game
-- through it in a second with no client attached.
--
-- Two clocks, deliberately different. DR windows run on `now` in GetTime
-- seconds (monotonic within a session, and windows never outlive a session).
-- Everything persisted to the file runs on epoch time() — the suite rule,
-- since GetTime resets on client restart.

CommanderDossierEngine = {}
local E = CommanderDossierEngine

local ENCOUNTER_GAP = 300  -- seconds of silence before we call it a new meeting
local KILL_WINDOW = 10     -- credit a death to whoever hit us this recently
local MIN_EVIDENCE = 3     -- talent-row points before we will name a spec
local UNIT_STALE = 60      -- forget a board unit with no live window this long
local ALERT_GAP = 3        -- seconds between repeats of the same alert

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local db, file, data
local talentIndex, indexGen = nil, 0
local nameIndex = nil       -- localized spell name -> category (rank fallback)

local units, unitCount = {}, 0   -- guid -> live board unit
local board, boardN = {}, 0      -- dense scratch, rebuilt by E.Board

local lastAttacker, lastAttackerAt = nil, 0

local alerts, alertsN = {}, 0
local lastAlertAt = {}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function E.Init(database, fileStore, dataset)
    db = database
    file = fileStore
    data = dataset or CommanderDossierData
    file.Chars = file.Chars or {}
    E.Reset()
end

-- Clears LIVE state only. The file is intelligence; it is never reset from
-- here, only by the explicit wipe command.
function E.Reset()
    for guid in pairs(units) do units[guid] = nil end
    unitCount = 0
    boardN = 0
    lastAttacker, lastAttackerAt = nil, 0
    alertsN = 0
    for k in pairs(lastAlertAt) do lastAlertAt[k] = nil end
end

-- Index built by the UI from Commander_Talents' verified grid:
--   idx[CLASS][talentName] = { tree = 1..3, treeName = "Subtlety", row = 1..9 }
-- Passing nil (Talents not installed) simply means no spec is ever named.
function E.SetTalentIndex(index)
    talentIndex = index
    indexGen = indexGen + 1
end

function E.HasTalentIndex()
    return talentIndex ~= nil
end

-- name -> category, built at login from the data file's seeds through the
-- client's own GetSpellInfo, so an unlisted rank still categorises and the
-- match stays locale-safe.
function E.SetNameIndex(index)
    nameIndex = index
end

-- ---------------------------------------------------------------------------
-- Alerts (edge events drained by the UI each tick)
-- ---------------------------------------------------------------------------

local function TakeAlert(kind, guid, cat, now)
    local key = kind .. (guid or "") .. (cat or "")
    local last = lastAlertAt[key]
    if last and (now - last) < ALERT_GAP then return end
    lastAlertAt[key] = now
    alertsN = alertsN + 1
    local a = alerts[alertsN]
    if not a then a = {}; alerts[alertsN] = a end
    a.kind, a.guid, a.cat = kind, guid, cat
end

function E.DrainAlerts(handler)
    for i = 1, alertsN do
        handler(alerts[i].kind, alerts[i].guid, alerts[i].cat)
    end
    alertsN = 0
end

-- ---------------------------------------------------------------------------
-- Categorisation
-- ---------------------------------------------------------------------------

-- id first (exact, rank-precise), name second (covers ranks the table misses)
function E.Categorize(spellId, spellName)
    if not data then return nil end
    local byId = spellId and data.SpellCategory[spellId]
    if byId then return byId end
    if spellName and nameIndex then return nameIndex[spellName] end
    return nil
end

-- TBC diminishes almost nothing against NPCs; the board must not pretend
-- otherwise, so a non-diminishing pair never opens a window at all.
function E.Diminishes(cat, isPlayer)
    if not cat then return false end
    if isPlayer then return data.CategoryByKey[cat] ~= nil end
    return data.PvECategories[cat] == true
end

-- What the NEXT application in this category will land at, as a fraction.
function E.NextFraction(level)
    local list = data.DIMINISH
    local step = list[(level or 0) + 1]
    return step or 0
end

-- ---------------------------------------------------------------------------
-- Live units and their DR windows
-- ---------------------------------------------------------------------------

function E.NoteUnit(guid, name, class, isPlayer, hostile, now)
    if not guid then return nil end
    local u = units[guid]
    if not u then
        u = { guid = guid, cats = {}, catCount = 0 }
        units[guid] = u
        unitCount = unitCount + 1
    end
    if name then u.name = name end
    if class then u.class = class end
    if isPlayer ~= nil then u.isPlayer = isPlayer end
    if hostile ~= nil then u.hostile = hostile end
    u.seen = now
    return u
end

function E.Unit(guid)
    return units[guid]
end

function E.UnitCount()
    return unitCount
end

-- Resolve a window to its CURRENT truth: an expired window is level 0 again,
-- and a window whose fade we never witnessed (target left log range) is
-- treated as having faded at the guard, not as pinned open forever.
local function Settle(w, now)
    if w.active then
        if now - w.appliedAt >= data.MAX_ACTIVE then
            w.active = false
            w.expiresAt = w.appliedAt + data.MAX_ACTIVE + data.RESET_TIME
        else
            return w
        end
    end
    if w.level > 0 and now >= w.expiresAt then
        w.level = 0
        w.spell = nil
    end
    return w
end

-- A crowd control landed. Returns the new level (applications inside the
-- window), or nil when this pair does not diminish at all.
function E.Apply(guid, cat, now, spellName, isPlayer)
    local u = units[guid]
    if not u then return nil end
    if isPlayer == nil then isPlayer = u.isPlayer end
    if not E.Diminishes(cat, isPlayer) then return nil end

    local w = u.cats[cat]
    if not w then
        w = { level = 0, active = false, appliedAt = 0, expiresAt = 0 }
        u.cats[cat] = w
        u.catCount = u.catCount + 1
    end
    Settle(w, now)

    -- Three applications exhaust the ladder: the third lands at a quarter and
    -- the fourth would be an immunity. Level 3 therefore means "the next one
    -- does not land", which is both the cap and the moment worth warning on.
    local max = #data.DIMINISH
    if w.level < max then w.level = w.level + 1 end
    w.active = true
    w.appliedAt = now
    w.expiresAt = now + data.RESET_TIME
    w.spell = spellName
    u.seen = now

    if w.level >= max then
        TakeAlert("IMMUNE", guid, cat, now)
    end
    return w.level
end

-- The crowd control fell off. THIS is when the reset clock actually starts.
function E.Fade(guid, cat, now)
    local u = units[guid]
    local w = u and u.cats[cat]
    if not w or not w.active then return end
    w.active = false
    w.expiresAt = now + data.RESET_TIME
    u.seen = now
end

-- level, secondsLeft, active, spellName. secondsLeft is 0 while the effect is
-- still up: the window cannot begin counting down until it fades.
function E.Level(guid, cat, now)
    local u = units[guid]
    local w = u and u.cats[cat]
    if not w then return 0, 0, false, nil end
    Settle(w, now)
    if w.level == 0 then return 0, 0, false, nil end
    if w.active then return w.level, 0, true, w.spell end
    local left = w.expiresAt - now
    if left < 0 then left = 0 end
    return w.level, left, false, w.spell
end

-- Does this unit carry anything worth a row right now?
function E.LiveCategories(guid, now)
    local u = units[guid]
    if not u then return 0 end
    local n = 0
    for cat in pairs(u.cats) do
        local level = E.Level(guid, cat, now)
        if level > 0 then n = n + 1 end
    end
    return n
end

-- Board rows, most-recently-touched first. `want` filters by side:
-- "ENEMIES", "ALLIES", "BOTH". Units with no live window are omitted; the
-- returned array is the engine's own scratch and must be consumed at once.
function E.Board(now, want)
    -- The array is dense on entry (every exit below leaves it so), which is
    -- what makes this length trustworthy.
    local previous = #board
    boardN = 0
    for guid, u in pairs(units) do
        local live = E.LiveCategories(guid, now)
        local sideOk = (want == "BOTH")
            or (want == "ALLIES" and not u.hostile)
            or (want ~= "ALLIES" and u.hostile)
        if live > 0 and sideOk then
            boardN = boardN + 1
            board[boardN] = u
            u.liveCount = live
        end
    end
    -- Truncate BEFORE sorting. table.sort works on the whole array, so a
    -- leftover unit from a busier tick would otherwise take part in the sort
    -- and could land inside the rows we are about to draw.
    for i = boardN + 1, previous do board[i] = nil end
    table.sort(board, function(a, b)
        if a.liveCount ~= b.liveCount then return a.liveCount > b.liveCount end
        if a.seen ~= b.seen then return a.seen > b.seen end
        return (a.name or a.guid) < (b.name or b.guid)
    end)
    return board, boardN
end

-- Drop units that have gone quiet with nothing live left on them.
function E.Sweep(now)
    for guid, u in pairs(units) do
        if (now - (u.seen or 0)) > UNIT_STALE and E.LiveCategories(guid, now) == 0 then
            units[guid] = nil
            unitCount = unitCount - 1
        end
    end
end

-- ---------------------------------------------------------------------------
-- The file: persistent records, keyed Name-Realm
-- ---------------------------------------------------------------------------

function E.Records()
    return file and file.Chars or {}
end

function E.Record(key)
    return file and file.Chars and file.Chars[key] or nil
end

function E.RecordCount()
    local n = 0
    for _ in pairs(E.Records()) do n = n + 1 end
    return n
end

-- info: name, realm, class, race, guild, level, faction, zone. Every field is
-- optional and a nil never overwrites something we already learned — the
-- combat log knows a name long before we ever inspect the unit.
function E.Observe(key, info, epoch)
    if not key or key == "" then return nil end
    if db and db.RecordIntel == false then return nil end
    local chars = file.Chars
    local rec = chars[key]
    if not rec then
        rec = {
            key = key, first = epoch, met = 0,
            kills = 0, deaths = 0, spells = {},
        }
        chars[key] = rec
    end
    if info then
        if info.name then rec.name = info.name end
        if info.realm then rec.realm = info.realm end
        if info.class then rec.class = info.class end
        if info.race then rec.race = info.race end
        if info.guild then rec.guild = info.guild end
        if info.level and info.level > 0 then rec.level = info.level end
        if info.faction then rec.faction = info.faction end
        if info.zone then rec.zone = info.zone end
    end
    -- A meeting, not a message: the same fight must not count twice, and a
    -- name seen again next week must not read as one long encounter.
    if not rec.last or (epoch - rec.last) > ENCOUNTER_GAP then
        rec.met = (rec.met or 0) + 1
    end
    rec.last = epoch
    return rec
end

function E.WitnessSpell(key, spellName, epoch)
    if not spellName then return end
    local rec = E.Record(key)
    if not rec then return end
    rec.spells = rec.spells or {}
    rec.spells[spellName] = (rec.spells[spellName] or 0) + 1
    rec.spellsSeen = (rec.spellsSeen or 0) + 1
    rec.last = epoch or rec.last
    rec._specGen = nil -- new evidence: the cached verdict is stale
end

function E.CreditKill(key, epoch)
    local rec = E.Record(key)
    if not rec then return end
    rec.kills = (rec.kills or 0) + 1
    rec.last = epoch or rec.last
end

-- Somebody hit us. Remembered so that our death a moment later has a culprit.
function E.NoteIncoming(key, now)
    if not key then return end
    lastAttacker, lastAttackerAt = key, now
end

-- We died. Credit whoever last touched us, if it was recent enough to mean
-- anything — a fall death half a minute after an arena is nobody's kill.
function E.NoteMyDeath(now, epoch)
    if not lastAttacker or (now - lastAttackerAt) > KILL_WINDOW then return nil end
    local rec = E.Record(lastAttacker)
    if not rec then return nil end
    rec.deaths = (rec.deaths or 0) + 1
    rec.last = epoch or rec.last
    local who = lastAttacker
    lastAttacker = nil
    return who
end

function E.Forget(key)
    if file and file.Chars then file.Chars[key] = nil end
end

function E.Wipe()
    if file then file.Chars = {} end
end

-- Age out the file. keepDays <= 0 keeps everything; maxRecords trims the
-- oldest beyond a ceiling so a lifetime of battlegrounds cannot grow the
-- SavedVariables without bound.
function E.Prune(epoch, keepDays, maxRecords)
    local chars = file and file.Chars
    if not chars then return 0 end
    local dropped = 0
    if keepDays and keepDays > 0 then
        local cutoff = epoch - keepDays * 86400
        for key, rec in pairs(chars) do
            -- A record you annotated yourself is kept: the note IS the value.
            if (rec.last or 0) < cutoff and not (rec.note and rec.note ~= "") then
                chars[key] = nil
                dropped = dropped + 1
            end
        end
    end
    if maxRecords and maxRecords > 0 then
        local list, n = {}, 0
        for key, rec in pairs(chars) do
            n = n + 1
            list[n] = { key = key, last = rec.last or 0, noted = rec.note and rec.note ~= "" }
        end
        if n > maxRecords then
            table.sort(list, function(a, b)
                if a.noted ~= b.noted then return b.noted end
                return a.last < b.last
            end)
            for i = 1, n - maxRecords do
                chars[list[i].key] = nil
                dropped = dropped + 1
            end
        end
    end
    return dropped
end

-- ---------------------------------------------------------------------------
-- Spec inference
--
-- Reuses Commander_Talents' DBC-verified grid instead of inventing a
-- signature table: a talent that grants an ability shares its name, so a
-- witnessed cast that matches a talent name in the target's class is a vote
-- for that tree, weighted by the talent's ROW. Depth is the whole point —
-- anybody can have a row-1 talent, and a row-9 talent is very nearly proof.
-- Derived lazily so records written before Talents was installed gain their
-- verdict the moment it appears.
-- ---------------------------------------------------------------------------

function E.SpecOf(record)
    if not record or not record.class then return nil end
    if not talentIndex then return nil end
    local seen = record.spellsSeen or 0
    if record._specGen == indexGen and record._specSeen == seen then
        return record._spec
    end
    record._specGen, record._specSeen = indexGen, seen

    local idx = talentIndex[record.class]
    if not idx then record._spec = nil; return nil end

    local scores = { 0, 0, 0 }
    local names = { nil, nil, nil }
    local total = 0
    local deepRow, deepName, deepTree = 0, nil, nil
    -- Scored per DISTINCT talent, never per cast: seeing Adrenaline Rush ten
    -- times is exactly as much proof that they took it as seeing it once, and
    -- weighting by frequency would let a spammed filler outvote a 41-pointer.
    for spellName in pairs(record.spells or {}) do
        local hit = idx[spellName]
        if hit then
            local weight = hit.row
            scores[hit.tree] = scores[hit.tree] + weight
            names[hit.tree] = hit.treeName
            total = total + weight
            if hit.row > deepRow then
                deepRow, deepName, deepTree = hit.row, spellName, hit.treeName
            end
        end
    end
    if total < MIN_EVIDENCE then record._spec = nil; return nil end

    local bestTree, bestScore = 1, scores[1]
    for i = 2, 3 do
        if scores[i] > bestScore then bestTree, bestScore = i, scores[i] end
    end
    record._spec = {
        tree = bestTree,
        label = names[bestTree] or "?",
        points = bestScore,
        total = total,
        confidence = bestScore / total,
        deepest = deepName,
        deepestRow = deepRow,
        deepestTree = deepTree,
    }
    return record._spec
end

-- ---------------------------------------------------------------------------
-- Reads for the file window and the report
-- ---------------------------------------------------------------------------

local sortScratch = {}

-- key = "LAST" | "MET" | "KILLS" | "DEATHS" | "NAME" | "SCORE"
function E.Sorted(sortKey, filterFn)
    local n = 0
    for key, rec in pairs(E.Records()) do
        if not filterFn or filterFn(rec, key) then
            n = n + 1
            sortScratch[n] = rec
        end
    end
    for i = n + 1, #sortScratch do sortScratch[i] = nil end
    local function score(r) return (r.kills or 0) - (r.deaths or 0) end
    table.sort(sortScratch, function(a, b)
        if sortKey == "NAME" then
            return (a.name or a.key or "") < (b.name or b.key or "")
        elseif sortKey == "MET" then
            if (a.met or 0) ~= (b.met or 0) then return (a.met or 0) > (b.met or 0) end
        elseif sortKey == "KILLS" then
            if (a.kills or 0) ~= (b.kills or 0) then return (a.kills or 0) > (b.kills or 0) end
        elseif sortKey == "DEATHS" then
            if (a.deaths or 0) ~= (b.deaths or 0) then return (a.deaths or 0) > (b.deaths or 0) end
        elseif sortKey == "SCORE" then
            if score(a) ~= score(b) then return score(a) < score(b) end
        end
        if (a.last or 0) ~= (b.last or 0) then return (a.last or 0) > (b.last or 0) end
        return (a.name or a.key or "") < (b.name or b.key or "")
    end)
    return sortScratch, n
end

-- Headline numbers for the report and the window's footer.
function E.Summary()
    local total, kills, deaths, nemesis = 0, 0, 0, nil
    local best = 0
    local classes = {}
    for _, rec in pairs(E.Records()) do
        total = total + 1
        kills = kills + (rec.kills or 0)
        deaths = deaths + (rec.deaths or 0)
        if rec.class then classes[rec.class] = (classes[rec.class] or 0) + 1 end
        -- The nemesis is whoever has killed you MOST, not whoever leads on
        -- net: someone you trade evenly with twenty times is a rival worth
        -- naming, and a net score would hide them behind a one-off gank.
        local theirs = rec.deaths or 0
        if theirs > best
            or (theirs == best and theirs > 0 and nemesis and (rec.kills or 0) < (nemesis.kills or 0))
        then
            nemesis, best = rec, theirs
        end
    end
    return {
        total = total, kills = kills, deaths = deaths,
        nemesis = nemesis,
        nemesisDeaths = best,
        nemesisNet = nemesis and ((nemesis.deaths or 0) - (nemesis.kills or 0)) or 0,
        classes = classes,
    }
end
