-- Commander Muster — the arithmetic.
--
-- Pure Lua: nothing in here touches the client, so every function runs under
-- luajit in Harness/muster_engine_smoke.lua against known items. The client
-- file (CommanderMuster.lua) gathers what the game will say about a player —
-- one entry per inventory slot, plus whatever the arena API answered — and
-- hands it here to be scored, coloured and formatted.
--
-- Two numbers come out of a set of items and both are shown, because they
-- answer different questions. The gear score is a weighted sum (a chest
-- counts for more than a ring, a two-hander for both hands) that moves with
-- every upgrade, which is what makes it a ranking. The average item level is
-- the plain mean and needs no formula to trust.

CommanderMusterEngine = CommanderMusterEngine or {}
local E = CommanderMusterEngine

local D
local floor = math.floor
local max = math.max

local DIM = "|cff9d9d9d"

function E.Init(data)
    D = data
end

-- ---------------------------------------------------------------------------
-- One item
-- ---------------------------------------------------------------------------

-- Score for a single item. Returns nil when the equip location is not a
-- scored slot (a shirt, a tabard, an unknown token) — nil, not zero, so the
-- caller can tell "does not count" from "counts for nothing".
function E.ItemScore(quality, ilvl, equipLoc)
    local slotMod = equipLoc and D.SLOT_MOD[equipLoc]
    if not slotMod or slotMod == 0 then return nil end
    if type(quality) ~= "number" or type(ilvl) ~= "number" then return nil end

    local curveQuality, qualityScale = D.Normalize(quality)
    if curveQuality < 2 or curveQuality > 4 then return nil end
    local curve = D.CURVES[D.CurveFor(curveQuality, ilvl)]
    local line = curve and curve[curveQuality]
    if not line then return nil end

    local score = floor(((ilvl - line.A) / line.B) * slotMod * D.SCALE * qualityScale)
    if score < 0 then score = 0 end
    return score
end

-- ---------------------------------------------------------------------------
-- A whole character
-- ---------------------------------------------------------------------------

-- items: { [slotID] = entry } where entry carries whatever the client could
-- read: { link, itemID, name, quality, ilvl, equipLoc, loaded }. An entry with
-- loaded == false is an item the client has not cached yet; the score is
-- still produced from what IS known, and `complete` says whether every
-- equipped piece was counted.
function E.Score(items, classToken)
    local total, levelTotal, count = 0, 0, 0
    local complete = true
    local rows = {}
    local isHunter = classToken == "HUNTER"

    for _, slot in ipairs(D.SLOTS) do
        local entry = items[slot]
        if entry then
            if entry.loaded == false or type(entry.ilvl) ~= "number" then
                complete = false
                rows[#rows + 1] = { slot = slot, name = entry.name, link = entry.link, pending = true }
            else
                local score = E.ItemScore(entry.quality, entry.ilvl, entry.equipLoc) or 0
                if isHunter then
                    if slot == D.SLOT_MAIN_HAND or slot == D.SLOT_OFF_HAND then
                        score = score * D.HUNTER_MELEE_MOD
                    elseif slot == D.SLOT_RANGED then
                        score = score * D.HUNTER_RANGED_MOD
                    end
                end
                total = total + score
                levelTotal = levelTotal + entry.ilvl
                count = count + 1
                rows[#rows + 1] = {
                    slot = slot, name = entry.name, link = entry.link,
                    quality = entry.quality, ilvl = entry.ilvl, score = floor(score),
                }
            end
        end
    end

    local weakest
    for _, row in ipairs(rows) do
        if row.ilvl and (not weakest or row.ilvl < weakest.ilvl) then
            weakest = row
        end
    end

    return {
        score = floor(total),
        ilvl = count > 0 and floor(levelTotal / count) or 0,
        count = count,
        complete = complete,
        slots = rows,
        weakest = weakest,
    }
end

-- ---------------------------------------------------------------------------
-- Colour
-- ---------------------------------------------------------------------------

function E.BandColor(score)
    score = tonumber(score) or 0
    if score <= 0 then
        local band = D.BANDS[1]
        return band.r[1], band.g[1], band.b[1], band.name
    end
    if score > D.MAX_SCORE then score = D.MAX_SCORE end
    local index = floor((score - 1) / D.BRACKET) + 1
    if index > #D.BANDS then index = #D.BANDS end
    local band = D.BANDS[index]
    local from = (index - 1) * D.BRACKET
    local function channel(c)
        local v = c[1] + (score - from) * c[2]
        if v < 0 then v = 0 elseif v > 1 then v = 1 end
        return v
    end
    return channel(band.r), channel(band.g), channel(band.b), band.name
end

function E.RatingColor(rating)
    rating = tonumber(rating) or 0
    for _, tier in ipairs(D.RATING_TIERS) do
        if rating >= tier.min then return tier.r, tier.g, tier.b end
    end
    local last = D.RATING_TIERS[#D.RATING_TIERS]
    return last.r, last.g, last.b
end

function E.Hex(r, g, b)
    return string.format("ff%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

local function Colored(text, r, g, b)
    return "|c" .. E.Hex(r, g, b) .. text .. "|r"
end
E.Colored = Colored

-- ---------------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------------

-- "2043" in its band colour
function E.FormatScore(score)
    local r, g, b = E.BandColor(score)
    return Colored(tostring(floor(tonumber(score) or 0)), r, g, b)
end

-- "1850" in its tier colour
function E.FormatRating(rating)
    local r, g, b = E.RatingColor(rating)
    return Colored(tostring(floor(tonumber(rating) or 0)), r, g, b)
end

-- arena: { known = bool, [2] = { rating, played, wins, teamName, best }, [3] = ..., [5] = ... }
-- Returns the one-line summary ("2v2 1850 · 3v3 1720"), or nil when nothing
-- is rated, or "…" while the answer is still on its way.
function E.FormatArena(arena)
    if not arena or not arena.known then return nil, "pending" end
    local parts = {}
    for _, size in ipairs(D.BRACKETS) do
        local b = arena[size]
        if b and ((b.rating or 0) > 0 or (b.played or 0) > 0) then
            parts[#parts + 1] = size .. "v" .. size .. " " .. E.FormatRating(b.rating or 0)
        end
    end
    if #parts == 0 then return nil, "unrated" end
    return table.concat(parts, "  "), "rated"
end

-- The highest rating across brackets, for the tooltip's single-line mode
function E.BestRating(arena)
    if not arena or not arena.known then return nil end
    local best, bestSize
    for _, size in ipairs(D.BRACKETS) do
        local b = arena[size]
        if b and (b.rating or 0) > 0 and (not best or b.rating > best) then
            best, bestSize = b.rating, size
        end
    end
    return best, bestSize
end

-- ---------------------------------------------------------------------------
-- Season bests: the highest rating seen per bracket, kept across sessions
-- ---------------------------------------------------------------------------

-- The server tells you your own season high (GetPersonalRatedInfo's second
-- return) and nobody else's: GetInspectArenaData carries only the current
-- rating. So another player's best is the highest rating this client has
-- seen them at, a floor under their real high that is only as good as how
-- often they are looked at (D10).
--
-- entry: one player's saved ledger,
--   { [size] = { best = n, played = n, rating = n, wins = n, at = epoch } }
-- arena: a fresh read; a bracket carries seasonBest when the server said so
-- now: epoch seconds of the read, stamped on each bracket as `at` (D11)
-- Writes the merged best onto each rated bracket as b.best (b.bestFromServer
-- when it is the server's number) and returns true when the entry changed.
-- A bracket whose season games went DOWN is a new season, or in a teams
-- season a new team (a new personal rating too): its old best is dropped
-- before the new read counts.
function E.MergeBests(entry, arena, now)
    if type(entry) ~= "table" or not arena or not arena.known then return false end
    local changed = false
    for _, size in ipairs(D.BRACKETS) do
        local b = arena[size]
        if b then
            local rating = tonumber(b.rating) or 0
            local played = tonumber(b.played) or 0
            local wins = tonumber(b.wins) or 0
            local kept = entry[size]
            if kept and played < (kept.played or 0) then
                entry[size], kept, changed = nil, nil, true
            end
            if rating > 0 or played > 0 then
                local server = tonumber(b.seasonBest)
                if server and server <= 0 then server = nil end
                -- The server's high is the truth when it gives one; otherwise
                -- the highest we have seen, which never falls inside a season
                local best = server and max(rating, server) or max(rating, kept and kept.best or 0)
                if not kept then
                    kept = {}
                    entry[size] = kept
                end
                if kept.best ~= best or kept.played ~= played
                    or kept.rating ~= rating or kept.wins ~= wins then
                    kept.best, kept.played, kept.rating, kept.wins, changed = best, played, rating, wins, true
                end
                if now then kept.at = now end
                b.best = best
                b.bestFromServer = server and true or nil
            end
        end
    end
    return changed
end

-- True when a ledger entry holds a best for any bracket
function E.HasBests(entry)
    if type(entry) ~= "table" then return false end
    for _, size in ipairs(D.BRACKETS) do
        if entry[size] then return true end
    end
    return false
end

-- Trims the ledger to `keep` players, the longest unseen going first.
-- players: { [guid] = { seen = epoch seconds, ... } }. Returns the new count.
function E.PruneBests(players, keep)
    local order = {}
    for guid, entry in pairs(players) do
        order[#order + 1] = { guid = guid, seen = tonumber(entry.seen) or 0 }
    end
    if #order <= keep then return #order end
    table.sort(order, function(a, b) return a.seen < b.seen end)
    for i = 1, #order - keep do
        players[order[i].guid] = nil
    end
    return keep
end

-- ---------------------------------------------------------------------------
-- Ratings from every source (D11)
-- ---------------------------------------------------------------------------

-- "Name-Realm" for any spelling of a player. A bare name takes the home
-- realm, "Name-Realm" keeps its own, and the realm loses its spaces the way
-- GetNormalizedRealmName() writes it. nil for an empty name.
function E.NameKey(name, realm, homeRealm)
    if type(name) ~= "string" or name == "" then return nil end
    local base, own = name:match("^([^%-]+)%-(.+)$")
    if base then name, realm = base, own end
    if type(realm) ~= "string" or realm == "" then realm = homeRealm end
    if type(realm) ~= "string" or realm == "" then return name end
    return name .. "-" .. (realm:gsub("%s", ""))
end

-- The two halves of a NameKey: name, realm (realm nil when there is none)
function E.SplitKey(key)
    if type(key) ~= "string" then return nil end
    local name, realm = key:match("^([^%-]+)%-(.+)$")
    if name then return name, realm end
    return key, nil
end

local SOURCE_RANK = { live = 3, seen = 2, feed = 1 }

local function Rated(b)
    return b and ((tonumber(b.rating) or 0) > 0 or (tonumber(b.played) or 0) > 0)
end

-- A ledger entry as a source. A bracket read within `liveWindow` seconds is
-- "live"; older ones are "seen". Brackets from before 1.2.0 carry no current
-- rating and are skipped.
function E.SeenSource(entry, now, liveWindow)
    if type(entry) ~= "table" then return nil end
    local brackets, any = {}, false
    for _, size in ipairs(D.BRACKETS) do
        local kept = entry[size]
        if type(kept) == "table" and kept.rating then
            local at = tonumber(kept.at or entry.seen) or 0
            brackets[size] = {
                rating = kept.rating, wins = kept.wins, played = kept.played, best = kept.best, at = at,
                source = (now and (now - at) < (liveWindow or 0)) and "live" or "seen",
            }
            any = true
        end
    end
    return any and { source = "seen", brackets = brackets } or nil
end

-- A Commander_Ladder entry as a source: { [size] = { rating, won, lost }, t = epoch }.
-- `generated` stands in for an entry with no fetch time of its own.
function E.FeedSource(entry, generated)
    if type(entry) ~= "table" then return nil end
    local brackets, any = {}, false
    for _, size in ipairs(D.BRACKETS) do
        local v = entry[size]
        if type(v) == "table" then
            local won, lost = tonumber(v[2]) or 0, tonumber(v[3]) or 0
            brackets[size] = { rating = tonumber(v[1]) or 0, wins = won, played = won + lost }
            any = true
        end
    end
    if not any then return nil end
    return { source = "feed", at = tonumber(entry.t) or tonumber(generated) or 0, brackets = brackets }
end

-- sources: a list of { source, at, brackets = { [size] = { rating, wins,
-- played, best, at?, source? } } }; a bracket's own `at` and `source` beat
-- the source's. For each bracket the newest reading wins, a tie going to
-- live, then seen, then feed. best is the highest best or rating any source
-- holds. Returns { [size] = { rating, wins, played, best, at, source } }, or
-- nil when no source has a rated bracket.
function E.MergeRatings(sources)
    if type(sources) ~= "table" then return nil end
    local out, any = {}, false
    for _, size in ipairs(D.BRACKETS) do
        local pick, best = nil, 0
        for _, src in ipairs(sources) do
            local b = type(src) == "table" and src.brackets and src.brackets[size]
            if Rated(b) then
                local at = tonumber(b.at or src.at) or 0
                local source = b.source or src.source
                if not pick or at > pick.at
                    or (at == pick.at and (SOURCE_RANK[source] or 0) > (SOURCE_RANK[pick.source] or 0)) then
                    pick = {
                        rating = tonumber(b.rating) or 0, wins = tonumber(b.wins) or 0,
                        played = tonumber(b.played) or 0, at = at, source = source,
                    }
                end
                best = max(best, tonumber(b.best) or 0, tonumber(b.rating) or 0)
            end
        end
        if pick then
            pick.best = max(best, pick.rating)
            out[size] = pick
            any = true
        end
    end
    return any and out or nil
end

-- An age as one short word: 45m, 13h, 3d
function E.FormatAge(seconds)
    seconds = tonumber(seconds) or 0
    if seconds < 3600 then return max(1, floor(seconds / 60)) .. "m" end
    if seconds < 48 * 3600 then return floor(seconds / 3600) .. "h" end
    return floor(seconds / 86400) .. "d"
end

-- "2s 1534 · 3s 1531 · 5s 1605", each number in its tier colour, followed by
-- a dim age when the newest bracket is not live. nil when nothing is rated.
function E.FormatRatings(ratings, now)
    if type(ratings) ~= "table" then return nil end
    local parts, newest, newestSource = {}, nil, nil
    for _, size in ipairs(D.BRACKETS) do
        local b = ratings[size]
        if Rated(b) then
            parts[#parts + 1] = size .. "s " .. E.FormatRating(b.rating or 0)
            local at = tonumber(b.at) or 0
            if not newest or at > newest then newest, newestSource = at, b.source end
        end
    end
    if #parts == 0 then return nil end
    local line = table.concat(parts, DIM .. " · |r")
    if newestSource ~= "live" and newest and newest > 0 and now then
        line = line .. "  " .. DIM .. E.FormatAge(now - newest) .. "|r"
    end
    return line
end

-- ---------------------------------------------------------------------------
-- The book: what we have learned about players this session, by GUID
-- ---------------------------------------------------------------------------

local Book = {}
Book.__index = Book

-- ttl: seconds a record is trusted; keep: most records held before the oldest go
function E.NewBook(ttl, keep)
    return setmetatable({ ttl = ttl or 600, keep = keep or 200, records = {}, size = 0 }, Book)
end

function Book:Put(guid, record, now)
    if not guid or type(record) ~= "table" then return end
    record.at = now
    if not self.records[guid] then self.size = self.size + 1 end
    self.records[guid] = record
    if self.size > self.keep then self:Prune(now) end
end

-- Returns (record, fresh). A stale record is still returned — old gear is
-- better than no gear while a new inspect is on its way — with fresh false.
function Book:Get(guid, now)
    local record = guid and self.records[guid]
    if not record then return nil, false end
    return record, (now - (record.at or 0)) < self.ttl
end

function Book:Forget(guid)
    if guid and self.records[guid] then
        self.records[guid] = nil
        self.size = self.size - 1
    end
end

-- Drops everything past its TTL; if still over the keep limit, the oldest go
function Book:Prune(now)
    for guid, record in pairs(self.records) do
        if (now - (record.at or 0)) >= self.ttl then
            self.records[guid] = nil
            self.size = self.size - 1
        end
    end
    while self.size > self.keep do
        local oldestGuid, oldestAt
        for guid, record in pairs(self.records) do
            if not oldestAt or (record.at or 0) < oldestAt then
                oldestGuid, oldestAt = guid, record.at or 0
            end
        end
        if not oldestGuid then break end
        self.records[oldestGuid] = nil
        self.size = self.size - 1
    end
end

function Book:Count()
    return self.size
end
