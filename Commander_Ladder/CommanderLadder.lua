-- Commander Ladder — the web feed, in game.
--
-- CommanderLadderData.lua is written outside the game by Tools/ladder_feed.py
-- from Blizzard's web API and loaded at login; it is gitignored and may be
-- missing, in which case every lookup is simply nil. Nothing here talks to
-- the network: addons cannot.
--
-- Three calls, and Commander_Muster is the one caller (its D11). Everything
-- else in the suite asks Muster, which merges this with what it has seen:
--   CommanderLadder.Lookup(name, realm) -> { [2] = { rating, won, lost }, ..., t = epoch } or nil
--   CommanderLadder.Want(name, realm)   -- a name the feed lacks, for its next run
--   CommanderLadder.Generated()         -- epoch the data file was written, or nil
-- realm defaults to ours, and "Name-Realm" is accepted as the name.

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

function L.Lookup(name, realm)
    if not IsOn() then return nil end
    local data = Data()
    if not data then return nil end
    local key = Key(name, realm)
    return key and data.players[key] or nil
end

function L.Generated()
    local data = Data()
    return data and tonumber(data.generated) or nil
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

function L.Want(name, realm)
    if not IsOn() then return end
    local key = Key(name, realm)
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
