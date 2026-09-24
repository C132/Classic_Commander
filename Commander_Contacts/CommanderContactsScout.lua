-- Commander Contacts: the scout.
--
-- Who, out of everyone who has been in a battleground with you, would be
-- worth adding? The game hands over two kinds of evidence and this file
-- weighs them: the scoreboard at the end of every battleground (damage,
-- healing, killing blows for all forty players), and what a player's
-- arena record says -- the title they wear, or a rating read by
-- Commander_Muster's inspect. Only people from your own realm and your own
-- faction are considered, because nobody else can be added as a friend.
--
-- Pure Lua, like the store: no widgets and no client calls. The host feeds
-- it rows and names; the window asks it for the top ten and a sentence
-- explaining each. The record lives in the same SavedVariables table as
-- everything else:
--
--   db.Performers = { [shortName] = {
--       name, class,
--       games, first, last, lastMap,          -- battlegrounds seen in
--       dmgTop, dmgTop3, bestDmg, bestDmgMap, -- times top / top-3 on damage
--       healTop, healTop3, bestHeal, bestHealMap,
--       kbTop, kbTop3, bestKB, bestKBMap,
--       title, titleAt,                       -- the PvP title they wear
--       ratings = { [teamSize] = rating }, ratingAt,
--   } }
--   db.Dismissed = { [shortName] = true }     -- "not interested", for good

CommanderContactsScout = CommanderContactsScout or {}
local T = CommanderContactsScout

local db

function T.Now()
    return (type(time) == "function" and time()) or 0
end

local function Trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- ---------------------------------------------------------------------------
-- The weights
--
-- Arena evidence and battleground evidence are two different arguments for
-- the same person and are added; a title and a rating are the same argument
-- twice and only the stronger counts. The rating bands are the rough TBC
-- season shape -- Gladiator lived around 2200+, Duelist around 2000+ -- and
-- are bands, not cutoffs, which is why the sentence says "range".
-- ---------------------------------------------------------------------------

T.RATING_BANDS = {
    { min = 2200, points = 100, label = "Gladiator range" },
    { min = 2000, points = 80, label = "Duelist range" },
    { min = 1850, points = 55, label = "Rival range" },
    { min = 1650, points = 25, label = "Challenger range" },
}

-- Matched against the title as a lower-cased substring, first hit wins, so
-- the seasonal "Merciless Gladiator" lands on the Gladiator row.
T.TITLES = {
    { match = "gladiator", points = 100 },
    { match = "duelist", points = 80 },
    { match = "rival", points = 55 },
    { match = "challenger", points = 25 },
    { match = "grand marshal", points = 70 },
    { match = "high warlord", points = 70 },
    { match = "field marshal", points = 50 },
    { match = "warlord", points = 50 },
    { match = "marshal", points = 40 },
    { match = "general", points = 40 },
    { match = "commander", points = 30 },
    { match = "champion", points = 20 },
    { match = "centurion", points = 20 },
}

T.BG_POINTS = {
    dmg = { top = 30, top3 = 15 },
    heal = { top = 30, top3 = 15 },
    kb = { top = 20, top3 = 10 },
}
T.BG_CAP = 200

-- ---------------------------------------------------------------------------
-- Attach
-- ---------------------------------------------------------------------------

function T.Attach(target)
    db = target or {}
    db.Performers = type(db.Performers) == "table" and db.Performers or {}
    db.Dismissed = type(db.Dismissed) == "table" and db.Dismissed or {}
    for name, rec in pairs(db.Performers) do
        if type(rec) ~= "table" or type(name) ~= "string" then
            db.Performers[name] = nil
        else
            rec.name = name
            for _, key in ipairs({ "games", "first", "last", "dmgTop", "dmgTop3", "bestDmg",
                "healTop", "healTop3", "bestHeal", "kbTop", "kbTop3", "bestKB" }) do
                rec[key] = tonumber(rec[key]) or 0
            end
            if type(rec.ratings) ~= "table" then rec.ratings = nil end
        end
    end
    return db
end

function T.Attached()
    return db ~= nil
end

function T.Record(name)
    return db and db.Performers[name] or nil
end

function T.Count()
    local count = 0
    for _ in pairs(db.Performers) do count = count + 1 end
    return count
end

-- ---------------------------------------------------------------------------
-- Eligibility
--
-- ctx = { own = "Yourname", ownRealm = "Realm", ownFaction = "HORDE"|"ALLIANCE",
--         friends = { [name] = true }, now = epoch }
-- ---------------------------------------------------------------------------

local function SameRealm(name, ownRealm)
    local short, realm = name:match("^([^%-]+)%-(.+)$")
    if not short then return true, name end
    if ownRealm and realm:gsub("[%s%-]", ""):lower() == tostring(ownRealm):gsub("[%s%-]", ""):lower() then
        return true, short
    end
    return false, name
end
T.SameRealm = SameRealm

local function Eligible(name, ctx)
    if type(name) ~= "string" or name == "" then return nil end
    local same, short = SameRealm(Trim(name), ctx and ctx.ownRealm)
    if not same then return nil end
    if ctx and ctx.own and short == ctx.own then return nil end
    if db.Dismissed[short] then return nil end
    return short
end

local function Ensure(short, class, now)
    local rec = db.Performers[short]
    if not rec then
        rec = { name = short, games = 0, first = now, last = now,
            dmgTop = 0, dmgTop3 = 0, bestDmg = 0,
            healTop = 0, healTop3 = 0, bestHeal = 0,
            kbTop = 0, kbTop3 = 0, bestKB = 0 }
        db.Performers[short] = rec
    end
    if class and class ~= "" then rec.class = class end
    if now > (rec.last or 0) then rec.last = now end
    return rec
end

-- ---------------------------------------------------------------------------
-- A battleground's scoreboard
--
-- rows = { { name, faction = "HORDE"|"ALLIANCE", class, dmg, heal, kb }, ... }
-- ctx  = as above plus map = "Arathi Basin"
-- Ranks are taken over EVERY row, both sides: "top damage" means top of the
-- match, not top of your team. Returns how many records were touched.
-- ---------------------------------------------------------------------------

local function Ranks(rows, field)
    local order = {}
    for index, row in ipairs(rows) do
        if (tonumber(row[field]) or 0) > 0 then order[#order + 1] = index end
    end
    table.sort(order, function(a, b)
        local va, vb = tonumber(rows[a][field]) or 0, tonumber(rows[b][field]) or 0
        if va ~= vb then return va > vb end
        return tostring(rows[a].name) < tostring(rows[b].name)
    end)
    local rank = {}
    for position, index in ipairs(order) do rank[index] = position end
    return rank
end

function T.RecordMatch(rows, ctx)
    if type(rows) ~= "table" or #rows == 0 then return 0 end
    ctx = ctx or {}
    local now = ctx.now or T.Now()
    local dmgRank, healRank, kbRank = Ranks(rows, "dmg"), Ranks(rows, "heal"), Ranks(rows, "kb")
    local touched = 0
    for index, row in ipairs(rows) do
        local sameSide = not ctx.ownFaction or not row.faction or row.faction == ctx.ownFaction
        local short = sameSide and Eligible(row.name, ctx) or nil
        if short then
            local rec = Ensure(short, row.class, now)
            rec.games = rec.games + 1
            if ctx.map then rec.lastMap = ctx.map end
            local function Note(rank, value, topKey, top3Key, bestKey, mapKey)
                value = tonumber(value) or 0
                if rank == 1 then rec[topKey] = rec[topKey] + 1
                elseif rank and rank <= 3 then rec[top3Key] = rec[top3Key] + 1 end
                if value > rec[bestKey] then
                    rec[bestKey] = value
                    rec[mapKey] = ctx.map
                end
            end
            Note(dmgRank[index], row.dmg, "dmgTop", "dmgTop3", "bestDmg", "bestDmgMap")
            Note(healRank[index], row.heal, "healTop", "healTop3", "bestHeal", "bestHealMap")
            Note(kbRank[index], row.kb, "kbTop", "kbTop3", "bestKB", "bestKBMap")
            touched = touched + 1
        end
    end
    return touched
end

-- The title in front of a name, as UnitPVPName shows it. An empty title
-- clears nothing: titles are only ever learned, since a player can hide one
-- they still hold.
function T.NoteTitle(name, title, ctx)
    local short = Eligible(name, ctx)
    title = Trim(title)
    if not short or title == "" then return false end
    local rec = Ensure(short, ctx and ctx.class, (ctx and ctx.now) or T.Now())
    if rec.title == title then return false end
    rec.title = title
    rec.titleAt = (ctx and ctx.now) or T.Now()
    return true
end

-- ratings = { [teamSize] = rating }. Only a higher rating replaces a known
-- one for the same bracket, so a rating that dropped since last look does
-- not erase what they reached.
function T.NoteRatings(name, ratings, ctx)
    local short = Eligible(name, ctx)
    if not short or type(ratings) ~= "table" then return false end
    local any = false
    local rec
    for size, rating in pairs(ratings) do
        size, rating = tonumber(size), tonumber(rating)
        if size and rating and rating > 0 then
            rec = rec or Ensure(short, ctx and ctx.class, (ctx and ctx.now) or T.Now())
            rec.ratings = rec.ratings or {}
            if rating > (rec.ratings[size] or 0) then
                rec.ratings[size] = rating
                rec.ratingAt = (ctx and ctx.now) or T.Now()
                any = true
            end
        end
    end
    return any
end

-- ---------------------------------------------------------------------------
-- Scoring and the sentence
-- ---------------------------------------------------------------------------

local function TitlePoints(title)
    if type(title) ~= "string" then return 0 end
    local lower = title:lower()
    for _, entry in ipairs(T.TITLES) do
        if lower:find(entry.match, 1, true) then return entry.points end
    end
    return 10
end

local function BestRating(rec)
    local best, bestSize = 0, nil
    for size, rating in pairs(rec.ratings or {}) do
        if rating > best then best, bestSize = rating, size end
    end
    return best, bestSize
end

local function RatingBand(rating)
    for _, band in ipairs(T.RATING_BANDS) do
        if rating >= band.min then return band.points, band.label end
    end
    return 0, nil
end

local function BGPoints(rec)
    local P = T.BG_POINTS
    local points = rec.dmgTop * P.dmg.top + rec.dmgTop3 * P.dmg.top3
        + rec.healTop * P.heal.top + rec.healTop3 * P.heal.top3
        + rec.kbTop * P.kb.top + rec.kbTop3 * P.kb.top3
    return math.min(points, T.BG_CAP)
end

function T.Score(rec)
    if not rec then return 0 end
    local rating = BestRating(rec)
    local ratingPoints = RatingBand(rating)
    local arena = math.max(TitlePoints(rec.title), ratingPoints)
    return arena + BGPoints(rec), arena, BGPoints(rec)
end

local function Short(value)
    value = tonumber(value) or 0
    if value >= 1000000 then return string.format("%.1fM", value / 1000000):gsub("%.0M", "M") end
    if value >= 1000 then return string.format("%dk", math.floor(value / 1000 + 0.5)) end
    return tostring(math.floor(value))
end
T.ShortNumber = Short

local function Games(count)
    return count .. (count == 1 and " game" or " games")
end

local function BGReason(rec)
    local P = T.BG_POINTS
    local candidates = {
        { points = rec.dmgTop * P.dmg.top + rec.dmgTop3 * P.dmg.top3, top = rec.dmgTop, top3 = rec.dmgTop3,
            best = rec.bestDmg, map = rec.bestDmgMap, what = "damage", verb = "Top damage" },
        { points = rec.healTop * P.heal.top + rec.healTop3 * P.heal.top3, top = rec.healTop, top3 = rec.healTop3,
            best = rec.bestHeal, map = rec.bestHealMap, what = "healing", verb = "Top healer" },
        { points = rec.kbTop * P.kb.top + rec.kbTop3 * P.kb.top3, top = rec.kbTop, top3 = rec.kbTop3,
            best = rec.bestKB, map = rec.bestKBMap, what = "killing blows", verb = "Most killing blows" },
    }
    table.sort(candidates, function(a, b) return a.points > b.points end)
    local best = candidates[1]
    if not best or best.points <= 0 then return nil end
    local text
    if best.top > 0 then
        text = string.format("%s in %s", best.verb, best.top == rec.games and (rec.games == 1 and "their one game" or ("all " .. Games(rec.games))) or (best.top .. " of " .. Games(rec.games)))
    else
        text = string.format("Top-3 %s in %s", best.what, best.top3 .. " of " .. Games(rec.games))
    end
    local bestText = best.what == "killing blows" and tostring(math.floor(best.best)) or Short(best.best)
    text = text .. string.format(" (best %s%s)", bestText, best.map and (" in " .. best.map) or "")
    return text
end

local function ArenaReason(rec)
    local rating, size = BestRating(rec)
    local _, band = RatingBand(rating)
    local pieces = {}
    if rec.title and rec.title ~= "" then
        pieces[#pieces + 1] = "Wears the " .. rec.title .. " title"
    end
    if rating > 0 then
        local text = string.format("%d arena rating", rating)
        if size then text = text .. string.format(" in %dv%d", size, size) end
        if band then text = text .. " (" .. band .. ")" end
        pieces[#pieces + 1] = text
    end
    if #pieces == 0 then return nil end
    return table.concat(pieces, " · ")
end

local function Ago(stamp, now)
    if not stamp or stamp <= 0 then return "a while ago" end
    local diff = (now or T.Now()) - stamp
    if diff < 3600 then return "just now" end
    if diff < 86400 then return "today" end
    local days = math.floor(diff / 86400)
    if days == 1 then return "yesterday" end
    if days < 30 then return days .. " days ago" end
    return math.floor(days / 30) .. (days < 60 and " month ago" or " months ago")
end

-- Returns (headline, detail). The headline is the argument; the detail is
-- where and when they were seen.
function T.Reason(rec, now)
    if not rec then return "", "" end
    local _, arena, bg = T.Score(rec)
    local arenaText, bgText = ArenaReason(rec), BGReason(rec)
    local headline
    if arenaText and bgText then
        headline = (arena >= bg) and (arenaText .. " · " .. bgText) or (bgText .. " · " .. arenaText)
    else
        headline = arenaText or bgText or "Seen in your battlegrounds"
    end
    local pieces = {}
    if rec.games > 0 then
        pieces[#pieces + 1] = "seen in " .. rec.games .. (rec.games == 1 and " battleground" or " battlegrounds")
        if rec.lastMap then pieces[#pieces + 1] = "last " .. rec.lastMap .. ", " .. Ago(rec.last, now) end
    else
        pieces[#pieces + 1] = "last seen " .. Ago(rec.last, now)
    end
    return headline, table.concat(pieces, " · ")
end

-- The list. ctx.friends drops anyone already on the list; dismissed names
-- were never recorded in the first place. Sorted by score, then by how
-- recently they were seen, then by name so the list never flickers.
function T.Suggestions(limit, ctx)
    ctx = ctx or {}
    limit = tonumber(limit) or 10
    local friends = ctx.friends or {}
    local list = {}
    for name, rec in pairs(db.Performers) do
        if not friends[name] and not db.Dismissed[name] then
            local score, arena, bg = T.Score(rec)
            if score > 0 then
                local headline, detail = T.Reason(rec, ctx.now)
                list[#list + 1] = { name = name, class = rec.class, score = score,
                    arena = arena, bg = bg, reason = headline, detail = detail, rec = rec }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if (a.rec.last or 0) ~= (b.rec.last or 0) then return (a.rec.last or 0) > (b.rec.last or 0) end
        return a.name < b.name
    end)
    for index = #list, limit + 1, -1 do list[index] = nil end
    return list
end

function T.Dismiss(name)
    if type(name) ~= "string" or name == "" then return false end
    db.Dismissed[name] = true
    db.Performers[name] = nil
    return true
end

function T.Forget(name)
    if not db.Performers[name] then return false end
    db.Performers[name] = nil
    return true
end

function T.ForgetAll()
    local count = T.Count()
    db.Performers = {}
    return count
end

-- Records not seen for `days` are dropped (0 keeps all). Returns the count.
function T.Prune(days, now)
    days = tonumber(days) or 0
    if days <= 0 then return 0 end
    now = now or T.Now()
    local cutoff = now - days * 86400
    local dropped = 0
    for name, rec in pairs(db.Performers) do
        if (rec.last or 0) < cutoff then
            db.Performers[name] = nil
            dropped = dropped + 1
        end
    end
    return dropped
end
