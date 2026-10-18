-- Commander Ladder — the web feed, in game.
--
-- CommanderLadderData.lua is written outside the game by Tools/ladder_feed.py
-- from Blizzard's web API and loaded at login; it is gitignored and may be
-- missing, in which case every lookup is simply nil. Nothing here talks to
-- the network: addons cannot.
--
-- Three calls, and Commander_Muster is the one caller (its D11). Everything
-- else in the suite asks Muster, which merges this with what it has seen:
--   CommanderLadder.Lookup(name, realm, anyRealm) -> { [2] = { rating, won, lost }, ..., t = epoch } or nil
--   CommanderLadder.Want(name, realm, anyRealm)   -- a name the feed lacks, for its next run
--   CommanderLadder.Generated()         -- epoch the data file was written, or nil
-- realm defaults to ours, and "Name-Realm" is accepted as the name.
--
-- A fourth call is for Commander_Recruit, which aims its /who sweep with it
-- (L9): who the home realm's rated players are.
--   CommanderLadder.Roster(realm) -> { { key, name, faction = "A"|"H", class, race,
--                                        last = epoch|nil, guild = name|nil, best = rating }, ... }
-- Only players the feed described (a `w` on their line) are listed; a file
-- written before L9 gives an empty list.
--
-- anyRealm (L8): the caller had a bare name and does not know the realm --
-- the group finder hands over Nightslayer players without one, so "ours"
-- was a guess and a wrong one. Lookup then tries our realm first and, on a
-- miss, the one other realm in the data that has that name (two realms with
-- it is a coin toss, and is left unanswered). Want files the name under
-- "Name-*OurRealm", which the feed tries on our realm first, then the rest.

CommanderLadder = _G.CommanderLadder or {}
local L = CommanderLadder

local MAX_WANTED = 1000           -- names held for the next feed run
local WANT_KEEP = 14 * 86400      -- a wish not renewed in two weeks is dropped

local wantedCount                 -- counted lazily from the saved table

local function IsOn()
    local db = CommanderLadderDB
    return not (type(db) == "table" and db.EnableLadder == false)
end

local function Data()
    local data = CommanderLadderData
    if type(data) == "table" and type(data.players) == "table" then return data end
    return nil
end

local function HomeRealm()
    local realm = type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName() or nil
    if (not realm or realm == "") and type(GetRealmName) == "function" then
        realm = (GetRealmName() or ""):gsub("%s", "")
    end
    if realm == "" then return nil end
    return realm
end

-- "Name-Realm", the feed's key: a written realm wins over the argument, the
-- realm loses its spaces, and a bare name takes ours
local function Key(name, realm)
    if type(name) ~= "string" or name == "" then return nil end
    local base, own = name:match("^([^%-]+)%-(.+)$")
    if base then name, realm = base, own end
    if type(realm) ~= "string" or realm == "" then realm = HomeRealm() end
    if type(realm) ~= "string" or realm == "" then return nil end
    return name .. "-" .. (realm:gsub("%s", ""))
end

L.Key = Key

-- Lower-case bare name -> its key, or false when two realms share it.
-- Built once per data file, the first time a realm-less name misses.
local function ByBareName(data)
    if data.byBare then return data.byBare end
    local index = {}
    for key in pairs(data.players) do
        local bare = key:match("^([^%-]+)%-")
        if bare then
            bare = bare:lower()
            if index[bare] == nil then
                index[bare] = key
            elseif index[bare] ~= key then
                index[bare] = false
            end
        end
    end
    data.byBare = index
    return index
end

function L.Lookup(name, realm, anyRealm)
    if not IsOn() then return nil end
    local data = Data()
    if not data then return nil end
    local key = Key(name, realm)
    local entry = key and data.players[key] or nil
    if entry or not anyRealm or type(name) ~= "string" or name:find("-", 1, true) then
        return entry
    end
    local other = ByBareName(data)[name:lower()]
    return other and data.players[other] or nil
end

function L.Generated()
    local data = Data()
    return data and tonumber(data.generated) or nil
end

-- The rated players of `realm` (ours by default) the feed described: each
-- line's w = { faction, class, race, last login, guild }. Built once per data
-- file and realm; callers must not change the tables.
function L.Roster(realm)
    if not IsOn() then return {} end
    local data = Data()
    if not data then return {} end
    realm = type(realm) == "string" and realm ~= "" and realm:gsub("%s", "") or HomeRealm()
    if not realm then return {} end
    data.rosters = data.rosters or {}
    if data.rosters[realm] then return data.rosters[realm] end
    local list, suffix = {}, "-" .. realm
    for key, entry in pairs(data.players) do
        local w = type(entry) == "table" and entry.w
        if type(w) == "table" and key:sub(-#suffix) == suffix and w[2] and w[3] then
            local best = 0
            for _, size in ipairs({ 2, 3, 5 }) do
                local b = entry[size]
                local rating = type(b) == "table" and tonumber(b[1]) or 0
                if rating > best then best = rating end
            end
            local last = tonumber(w[4])
            list[#list + 1] = {
                key = key, name = key:sub(1, -#suffix - 1), faction = w[1], class = w[2], race = w[3],
                last = last and last > 0 and last or nil,
                guild = type(w[5]) == "string" and w[5] ~= "" and w[5] or nil,
                best = best,
            }
        end
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    data.rosters[realm] = list
    return list
end

-- Players in the data file, for the settings page
function L.Count()
    local data = Data()
    if not data then return 0 end
    if not data.count then
        local n = 0
        for _ in pairs(data.players) do n = n + 1 end
        data.count = n
    end
    return data.count
end

local function Wanted()
    if type(CommanderLadderWanted) ~= "table" then CommanderLadderWanted = {} end
    return CommanderLadderWanted
end

-- Drops wishes older than WANT_KEEP, then the oldest until under MAX_WANTED
local function PruneWanted(now)
    local wanted = Wanted()
    local order = {}
    for key, at in pairs(wanted) do
        if type(at) ~= "number" or now - at >= WANT_KEEP then
            wanted[key] = nil
        else
            order[#order + 1] = key
        end
    end
    if #order > MAX_WANTED then
        table.sort(order, function(a, b) return wanted[a] < wanted[b] end)
        for i = 1, #order - MAX_WANTED do
            wanted[order[i]] = nil
        end
    end
    local n = 0
    for _ in pairs(wanted) do n = n + 1 end
    wantedCount = n
end

function L.Want(name, realm, anyRealm)
    if not IsOn() then return end
    local key
    if anyRealm and type(name) == "string" and name ~= "" and not name:find("-", 1, true) then
        -- The realm is not known: the feed tries the name on every realm,
        -- ours first (a friend's bare name is usually from here)
        key = name .. "-*" .. (HomeRealm() or "")
    else
        key = Key(name, realm)
    end
    if not key then return end
    local wanted = Wanted()
    local now = time()
    if wantedCount == nil then PruneWanted(now) end
    if not wanted[key] then
        wantedCount = wantedCount + 1
        if wantedCount > MAX_WANTED then
            wanted[key] = now
            PruneWanted(now)
            return
        end
    end
    wanted[key] = now
end

function L.WantedCount()
    if wantedCount == nil then PruneWanted(time()) end
    return wantedCount
end

function L.ClearWanted()
    wipe(Wanted())
    wantedCount = 0
end

-- "12,345 players, 3h old (season 3)" or the reason there is no feed
function L.Status()
    local data = Data()
    if not data then
        return "No feed yet. Run Tools/ladder_feed.py run on your Mac, then /reload."
    end
    local age = time() - (tonumber(data.generated) or 0)
    local ageText
    if age < 3600 then
        ageText = math.max(1, math.floor(age / 60)) .. "m"
    elseif age < 48 * 3600 then
        ageText = math.floor(age / 3600) .. "h"
    else
        ageText = math.floor(age / 86400) .. "d"
    end
    local text = string.format("%d players, %s old", L.Count(), ageText)
    if data.season then text = text .. string.format(" (season %d)", data.season) end
    return text
end
