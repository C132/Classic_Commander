-- Commander Muster — the client side.
--
-- Three jobs, and the arithmetic for none of them: read what the game will
-- say about a player's kit and arena record, keep a session book of it by
-- GUID, and draw it in three places — the character panel, the inspect
-- window, and the tooltip of any player under the cursor. Scoring, colour
-- and formatting live in CommanderMusterEngine.lua.
--
-- The one thing here that needs care is HOW a stranger's gear is read. The
-- client only knows another player's inventory while that player is the
-- current inspect target, and there is exactly one inspect target at a time,
-- shared with Blizzard's own inspect window. So a mouseover lookup is a
-- quiet NotifyInspect that:
--   * only goes out for a player CanInspect says yes to (own faction, ~28yd)
--   * never goes out while the inspect window is open or opening on someone,
--     because it would steal that window's answer
--   * runs one at a time, at most one every INSPECT_COOLDOWN seconds, with the
--     newest request winning (the cursor moved on; the old one is moot)
--   * reads the answer on INSPECT_READY, asks for the honor page if arena
--     ratings are wanted, reads that on INSPECT_HONOR_UPDATE, and then
--     ClearInspectPlayer()s so nothing is left dangling
--   * remembers the answer for the session, so the same player costs one
--     round trip, not one per hover
-- A failed or timed-out lookup backs off for that GUID rather than retrying
-- on the next mouse twitch.
--
-- Item links survive the inspect: they are stored with the record, so a
-- piece the item cache had not seen yet is scored later, on
-- GET_ITEM_INFO_RECEIVED, without inspecting again.
--
-- One thing outlives the session: the rating ledger, CommanderMusterBests
-- (D10, D11). For each player and bracket it keeps the last rating an
-- inspect showed and the season best (ours from the server). RatingsFor
-- merges it with the Commander_Ladder web feed, so the suite can show a
-- rating for anyone, inspected or not; that is the one rating source every
-- other addon reads. Party and raid members are looked up in the
-- background (D12).

local D = CommanderMusterData
local E = CommanderMusterEngine
E.Init(D)

local db
local playerGUID

local INSPECT_COOLDOWN = 1.5      -- seconds between NotifyInspect calls
local INSPECT_TIMEOUT = 5         -- seconds to wait for INSPECT_READY
local HONOR_TIMEOUT = 3           -- seconds to wait for INSPECT_HONOR_UPDATE
local FAIL_BACKOFF = 30           -- seconds before a GUID that failed is tried again
local BOOK_TTL = 600              -- seconds a stranger's record is trusted
local BOOK_KEEP = 200             -- most strangers remembered
local BESTS_KEEP = 2000           -- most players whose ratings are kept on disk
local LIVE_WINDOW = BOOK_TTL      -- seconds a reading counts as live rather than seen (D11)
local GROUP_REFRESH = 1800        -- seconds before a group member is looked up again
local GROUP_RETRY = 15            -- seconds between passes while a member is out of reach

local book = E.NewBook(BOOK_TTL, BOOK_KEEP)
local bests                       -- CommanderMusterBests.players: guid -> rating ledger entry
local bestsCount = 0
local byName = {}                 -- "Name-Realm" -> guid, rebuilt from the ledger at login
local playerRecord                -- our own record, kept outside the book (never expires)
local pending                     -- the in-flight quiet inspect: { guid, unit, name, stage, at }
local wanted                      -- a unit token waiting for the cooldown to pass
local lastInspectAt = -100
local failedAt = {}               -- guid -> GetTime() of the last failure
local incomplete = {}             -- guid -> record still waiting on item data
local frameTarget                 -- { guid } — who Blizzard's inspect window is looking at

local LABEL = "|cffffd100"
local DIM = "|cff9d9d9d"
local WHITE = "|cffffffff"

local function IsOn()
    return db and db.EnableMuster
end

local function Now()
    return GetTime()
end

-- ---------------------------------------------------------------------------
-- Reading a unit
-- ---------------------------------------------------------------------------

local function ItemName(link)
    if type(link) ~= "string" then return nil end
    return link:match("%[(.-)%]")
end

-- One inventory slot of `unit` as the engine wants it. nil for an empty slot.
local function ReadSlot(unit, slot)
    local link = GetInventoryItemLink(unit, slot)
    if not link then return nil end
    local itemID = C_Item.GetItemInfoInstant(link)
    local name, _, quality, ilvl, _, _, _, _, equipLoc = C_Item.GetItemInfo(link)
    if name and ilvl then
        return {
            link = link, itemID = itemID, name = name,
            quality = quality, ilvl = ilvl, equipLoc = equipLoc, loaded = true,
        }
    end
    if itemID and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
    return { link = link, itemID = itemID, name = ItemName(link), loaded = false }
end

-- Re-read an entry from its stored link, for items that finished loading
-- after the inspect target was gone
local function ReloadEntry(entry)
    if not entry or entry.loaded or not entry.link then return false end
    local name, _, quality, ilvl, _, _, _, _, equipLoc = C_Item.GetItemInfo(entry.link)
    if not (name and ilvl) then return false end
    entry.name, entry.quality, entry.ilvl, entry.equipLoc, entry.loaded = name, quality, ilvl, equipLoc, true
    return true
end

local function Rescore(record)
    record.result = E.Score(record.items, record.class)
    if record.result.complete then
        incomplete[record.guid] = nil
    else
        incomplete[record.guid] = record
    end
    return record.result
end

local function ReadUnitItems(unit)
    local items = {}
    for _, slot in ipairs(D.SLOTS) do
        items[slot] = ReadSlot(unit, slot)
    end
    return items
end

local function NewRecord(unit, guid)
    local _, classToken = UnitClass(unit)
    local name, realm = UnitName(unit)
    local record = {
        guid = guid or UnitGUID(unit),
        name = name,
        realm = realm,
        class = classToken,
        items = ReadUnitItems(unit),
        arena = { known = false },
    }
    Rescore(record)
    return record
end

-- ---------------------------------------------------------------------------
-- Arena: two season modes, two API shapes
-- ---------------------------------------------------------------------------

local function UsesTeams()
    if type(GetCurrentArenaSeasonUsesTeams) ~= "function" then return false end
    local ok, uses = pcall(GetCurrentArenaSeasonUsesTeams)
    return ok and uses and true or false
end

local MAX_TEAMS = 3

-- Our own ratings, straight from the client
local function ReadOwnArena()
    local arena = { known = true }
    if UsesTeams() then
        if type(GetArenaTeam) ~= "function" then return arena end
        for i = 1, MAX_TEAMS do
            local ok, teamName, teamSize, teamRating, _, _, seasonPlayed, seasonWins,
                _, seasonPlayerPlayed, _, playerRating = pcall(GetArenaTeam, i)
            if ok and teamName and teamSize then
                arena[teamSize] = {
                    rating = tonumber(playerRating) or tonumber(teamRating) or 0,
                    teamRating = tonumber(teamRating) or 0,
                    played = tonumber(seasonPlayed) or 0,
                    wins = tonumber(seasonWins) or 0,
                    playerPlayed = tonumber(seasonPlayerPlayed) or 0,
                    teamName = teamName,
                }
            end
        end
    else
        if type(GetPersonalRatedInfo) ~= "function" then return arena end
        for i = 1, MAX_TEAMS do
            -- The second return is the season high: Blizzard's pane skips it,
            -- but it sits where PVPPersonalRatedInfo.bestSeasonRating does
            local ok, rating, seasonBest, _, seasonPlayed, seasonWins, _, _, _, _, _, _, teamSize = pcall(GetPersonalRatedInfo, i)
            if ok and teamSize then
                arena[teamSize] = {
                    rating = tonumber(rating) or 0,
                    played = tonumber(seasonPlayed) or 0,
                    wins = tonumber(seasonWins) or 0,
                    seasonBest = tonumber(seasonBest),
                }
            end
        end
    end
    return arena
end

-- The inspected player's ratings; only meaningful after INSPECT_HONOR_UPDATE
local function ReadInspectArena()
    local arena = { known = true }
    if UsesTeams() then
        if type(GetInspectArenaTeamData) ~= "function" then return arena end
        for i = 1, MAX_TEAMS do
            local ok, teamName, teamSize, teamRating, teamPlayed, teamWins, playerPlayed, playerRating = pcall(GetInspectArenaTeamData, i)
            if ok and teamName and teamSize then
                arena[teamSize] = {
                    rating = tonumber(playerRating) or tonumber(teamRating) or 0,
                    teamRating = tonumber(teamRating) or 0,
                    played = tonumber(teamPlayed) or 0,
                    wins = tonumber(teamWins) or 0,
                    playerPlayed = tonumber(playerPlayed) or 0,
                    teamName = teamName,
                }
            end
        end
    else
        if type(GetInspectArenaData) ~= "function" then return arena end
        for i = 1, MAX_TEAMS do
            local ok, rating, played, wins, _, _, _, teamSize = pcall(GetInspectArenaData, i)
            if ok and teamSize then
                arena[teamSize] = {
                    rating = tonumber(rating) or 0,
                    played = tonumber(played) or 0,
                    wins = tonumber(wins) or 0,
                }
            end
        end
    end
    return arena
end

-- ---------------------------------------------------------------------------
-- The rating ledger (D10, D11): the one thing written to disk
-- ---------------------------------------------------------------------------

-- Our realm as GetNormalizedRealmName() writes it, for keys of bare names
local function HomeRealm()
    local realm = type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName() or nil
    if (not realm or realm == "") and type(GetRealmName) == "function" then
        realm = (GetRealmName() or ""):gsub("%s", "")
    end
    if realm == "" then return nil end
    return realm
end

local function RebuildNames()
    wipe(byName)
    for guid, entry in pairs(bests) do
        if entry.key then byName[entry.key] = guid end
    end
end

local function CurrentSeason()
    if type(GetCurrentArenaSeason) ~= "function" then return nil end
    local ok, season = pcall(GetCurrentArenaSeason)
    season = ok and tonumber(season)
    return season and season > 0 and season or nil
end

-- Binds the saved ledger, emptying it when the client names a new season.
-- Safe to call again: the season can still read 0 at login.
local function OpenBests()
    if type(CommanderMusterBests) ~= "table" then CommanderMusterBests = {} end
    local store = CommanderMusterBests
    if type(store.players) ~= "table" then store.players = {} end
    local season = CurrentSeason()
    if season then
        if store.season and store.season ~= season then store.players = {} end
        store.season = season
    end
    bests = store.players
    bestsCount = 0
    for _ in pairs(bests) do bestsCount = bestsCount + 1 end
    RebuildNames()
end

-- Folds a fresh arena read into the ledger: current rating, games and best
-- per bracket, stamped with the time, and the ledger's best back onto the
-- read (b.best). Returns the read, so a caller can assign through it.
local function Remember(guid, name, arena, realm)
    if not (bests and guid and arena and arena.known) then return arena end
    local entry = bests[guid] or {}
    E.MergeBests(entry, arena, time())
    if not E.HasBests(entry) then
        if bests[guid] then
            if entry.key then byName[entry.key] = nil end
            bests[guid] = nil
            bestsCount = bestsCount - 1
        end
        return arena
    end
    entry.name = name or entry.name
    entry.key = E.NameKey(name, realm, HomeRealm()) or entry.key
    entry.seen = time()
    if entry.key then byName[entry.key] = guid end
    if not bests[guid] then
        bests[guid] = entry
        bestsCount = bestsCount + 1
        if bestsCount > BESTS_KEEP then
            bestsCount = E.PruneBests(bests, BESTS_KEEP)
            RebuildNames()
        end
    end
    return arena
end

local function ReadInspectArenaFor(record)
    return Remember(record.guid, record.name, ReadInspectArena(), record.realm)
end

local function WantArena()
    return db.TooltipArena or db.ShowArenaOnReadout
end

-- ---------------------------------------------------------------------------
-- Our own record
-- ---------------------------------------------------------------------------

local function RefreshPlayer()
    if not playerGUID then return end
    local arena = playerRecord and playerRecord.arena
    playerRecord = NewRecord("player", playerGUID)
    playerRecord.arena = arena or { known = false }
    Commander.Notify(COMMANDER_MUSTER_EVENTS.RECORD, playerGUID)
end

local function RefreshPlayerArena()
    if not playerRecord then return end
    playerRecord.arena = Remember(playerGUID, playerRecord.name, ReadOwnArena(), playerRecord.realm)
    Commander.Notify(COMMANDER_MUSTER_EVENTS.RECORD, playerGUID)
end

-- The record for a unit, if we have one: ours, or the book's
local function RecordFor(guid)
    if not guid then return nil, false end
    if guid == playerGUID then return playerRecord, true end
    return book:Get(guid, Now())
end

CommanderMuster.RecordFor = RecordFor

-- ---------------------------------------------------------------------------
-- Ratings for anyone (D11): what we saw, merged with the web feed
-- ---------------------------------------------------------------------------

-- guid, name, realm, bare for a unit token, a GUID, or a "Name" / "Name-Realm".
-- Any of the first three may be nil: a GUID the client never cached has no
-- name, and a name nobody has been inspected under has no GUID. `bare` is
-- true when we were handed a name with no realm, so the realm returned is
-- only our guess: the group finder lists Nightslayer players that way, and
-- 28 of 37 names the feed could not find on 2026-10-17 were exactly those,
-- asked for on Dreamscythe (D14).
local function Resolve(who)
    if type(who) ~= "string" or who == "" then return nil end
    if UnitExists(who) then
        local name, realm = UnitName(who)
        return UnitGUID(who), name, realm
    end
    -- A GUID: "Type-number-...". Names hold no digits, so this never takes a
    -- "Name-Realm". Pets, creatures and the rest have no ratings.
    if who:match("^%a+%-%d+%-") and not who:match("^Player%-") then return nil end
    if who:match("^Player%-") then
        local entry = bests and bests[who]
        if entry and entry.key then
            local name, realm = E.SplitKey(entry.key)
            return who, name, realm
        end
        if type(GetPlayerInfoByGUID) == "function" then
            local ok, _, _, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, who)
            if ok and name then return who, name, realm end
        end
        return who, nil, nil
    end
    local key = E.NameKey(who, nil, HomeRealm())
    local name, realm = E.SplitKey(key)
    return byName[key], name, realm, not who:find("-", 1, true)
end

-- Commander_Ladder's entry for a player, as a source. A player the feed does
-- not have is handed to Want, so the next feed run looks them up by name.
-- `bare`: the realm is our guess, so Ladder may answer from another realm
-- and the feed tries them all (Ladder L8).
local function FeedFor(name, realm, guid, bare)
    if not name or type(CommanderLadder) ~= "table" or type(CommanderLadder.Lookup) ~= "function" then
        return nil
    end
    if realm == "" then realm = nil end
    local ok, entry = pcall(CommanderLadder.Lookup, name, realm, bare)
    if ok and type(entry) == "table" then
        local generated
        if type(CommanderLadder.Generated) == "function" then
            local okGen, at = pcall(CommanderLadder.Generated)
            generated = okGen and at or nil
        end
        return E.FeedSource(entry, generated)
    end
    if guid ~= playerGUID and type(CommanderLadder.Want) == "function" then
        pcall(CommanderLadder.Want, name, realm, bare)
    end
    return nil
end

-- { [size] = { rating, wins, played, best, at, source } } for `who` (a unit
-- token, a GUID, or "Name-Realm"), or nil when nothing rated is known
local function RatingsFor(who)
    -- The master switch reaches every surface that asks, not only Muster's own
    if not IsOn() then return nil end
    local guid, name, realm, bare = Resolve(who)
    local sources = {}
    local seen = guid and bests and E.SeenSource(bests[guid], time(), LIVE_WINDOW)
    if seen then sources[#sources + 1] = seen end
    -- A bare name that resolved to a GUID we have seen is not a guess
    local feed = FeedFor(name, realm, guid, bare and not guid)
    if feed then sources[#sources + 1] = feed end
    return E.MergeRatings(sources)
end

CommanderMuster.RatingsFor = RatingsFor

function CommanderMuster.FormatRatings(ratings)
    return E.FormatRatings(ratings, time())
end

-- The one-call form surfaces use: "2s 1534 · 3s 1531 · 5s 1605" or nil
function CommanderMuster.RatingsLine(who)
    return E.FormatRatings(RatingsFor(who), time())
end

-- ---------------------------------------------------------------------------
-- The quiet inspect
-- ---------------------------------------------------------------------------

local function InspectWindowBusy()
    -- .unit is set before NotifyInspect and cleared on hide, so it covers the
    -- window between asking and the frame appearing
    return InspectFrame and (InspectFrame:IsShown() or InspectFrame.unit) and true or false
end

local function SafeClearInspect()
    if InspectWindowBusy() then return end
    if type(ClearInspectPlayer) == "function" then pcall(ClearInspectPlayer) end
end

local CANDIDATE_TOKENS = { "mouseover", "target", "focus", "party1", "party2", "party3", "party4" }

-- A unit token that currently resolves to `guid`, trying `preferred` first
local function FindUnit(guid, preferred)
    if preferred and UnitGUID(preferred) == guid then return preferred end
    for _, token in ipairs(CANDIDATE_TOKENS) do
        if UnitGUID(token) == guid then return token end
    end
    if IsInRaid() then
        for i = 1, 40 do
            local token = "raid" .. i
            if UnitGUID(token) == guid then return token end
        end
    end
    return nil
end

local TryWanted, ScheduleGroupPump
local groupCheckedAt = {}         -- guid -> time() of its last answered lookup
local groupPumpDue                -- Now() when the queued group pass runs

-- Whoever was waiting behind the in-flight inspect goes next; with nobody
-- waiting, the group gets its turn
local function ServeWanted()
    if wanted then
        C_Timer.After(0.1, TryWanted)
    else
        ScheduleGroupPump(INSPECT_COOLDOWN + 0.1)
    end
end

local function Finish(record, notify)
    if record then
        book:Put(record.guid, record, Now())
        groupCheckedAt[record.guid] = time()
    end
    pending = nil
    SafeClearInspect()
    if notify and record then
        Commander.Notify(COMMANDER_MUSTER_EVENTS.RECORD, record.guid)
    end
    ServeWanted()
end

local function Fail(guid)
    if guid then failedAt[guid] = Now() end
    pending = nil
    SafeClearInspect()
    ServeWanted()
end

-- viaGroup: a background group lookup, which never queues behind a hover
local function Request(unit, viaGroup)
    if not IsOn() then return false end
    if viaGroup then
        if not db.InspectGroup then return false end
    elseif not db.InspectOnMouseover then
        return false
    end
    if not unit or not UnitIsPlayer(unit) then return false end
    local guid = UnitGUID(unit)
    if not guid or guid == playerGUID then return false end
    if pending and pending.guid == guid then return true end
    if InspectWindowBusy() then return false end
    if not db.InspectInCombat and InCombatLockdown() then return false end
    if failedAt[guid] and (Now() - failedAt[guid]) < FAIL_BACKOFF then return false end
    if type(CanInspect) ~= "function" or not CanInspect(unit, false) then return false end

    local since = Now() - lastInspectAt
    if pending or since < INSPECT_COOLDOWN then
        -- The group waits its turn rather than displace a hover
        if viaGroup then return false end
        -- The newest wish wins; the earlier one is where the cursor was
        wanted = unit
        C_Timer.After(math.max(INSPECT_COOLDOWN - since, 0.05) + 0.05, TryWanted)
        return true
    end

    pending = { guid = guid, unit = unit, name = UnitName(unit), stage = "gear", at = Now() }
    lastInspectAt = Now()
    NotifyInspect(unit)
    local mine = pending
    C_Timer.After(INSPECT_TIMEOUT, function()
        if pending == mine and pending.stage == "gear" then Fail(mine.guid) end
    end)
    return true
end

TryWanted = function()
    -- Still busy: keep the wish, Finish/Fail will come back for it
    if pending then return end
    local unit = wanted
    wanted = nil
    local guid = unit and UnitGUID(unit)
    local record, fresh = RecordFor(guid)
    if guid and not (record and fresh and (record.arena.known or not WantArena())) and Request(unit) then
        return
    end
    -- The hover needed nothing after all: the group's turn
    ScheduleGroupPump(0.2)
end

-- ---------------------------------------------------------------------------
-- Group lookups (D12): party and raid members, one at a time, behind hovers
-- ---------------------------------------------------------------------------

local function GroupTokens()
    local tokens = {}
    if IsInRaid() then
        for i = 1, 40 do tokens[#tokens + 1] = "raid" .. i end
    else
        for i = 1, 4 do tokens[#tokens + 1] = "party" .. i end
    end
    return tokens
end

-- Looks up the next member with no answer in GROUP_REFRESH seconds. Only
-- when nothing else is in flight or waiting; Finish and Fail come back here.
-- A member out of reach (out of range, offline, in combat) is passed over
-- and the pass repeats every GROUP_RETRY seconds until everyone is answered.
local function PumpGroup()
    if not (IsOn() and db.InspectGroup) then return end
    local outstanding = false
    for _, token in ipairs(GroupTokens()) do
        local guid = UnitGUID(token)
        if guid and guid ~= playerGUID and UnitIsPlayer(token) then
            local checked = groupCheckedAt[guid]
            if not checked or (time() - checked) >= GROUP_REFRESH then
                outstanding = true
                -- Busy: Finish, Fail or TryWanted brings us back
                if pending or wanted then return end
                local since = Now() - lastInspectAt
                if since < INSPECT_COOLDOWN then
                    ScheduleGroupPump(INSPECT_COOLDOWN - since + 0.05)
                    return
                end
                if Request(token, true) then return end
            end
        end
    end
    if outstanding then ScheduleGroupPump(GROUP_RETRY) end
end

-- One queued pass at a time; a sooner request replaces a later one
ScheduleGroupPump = function(delay)
    delay = delay or 0.2
    local due = Now() + delay
    if groupPumpDue and groupPumpDue <= due then return end
    groupPumpDue = due
    C_Timer.After(delay, function()
        if groupPumpDue ~= due then return end
        groupPumpDue = nil
        PumpGroup()
    end)
end

local function AskForHonor(record)
    if not WantArena() then
        record.arena = { known = false }
        return false
    end
    if type(HasInspectHonorData) == "function" and HasInspectHonorData() then
        record.arena = ReadInspectArenaFor(record)
        return false
    end
    if type(RequestInspectHonorData) ~= "function" then
        record.arena = { known = false }
        return false
    end
    pcall(RequestInspectHonorData)
    return true
end

-- INSPECT_READY carries the inspected GUID. Two customers: our quiet inspect
-- and Blizzard's window (which we ride along with — its answer fills the
-- book too, and gives the inspect readout its numbers).
local function OnInspectReady(guid)
    if not guid then return end

    if pending and pending.guid == guid then
        local unit = FindUnit(guid, pending.unit)
        if not unit then
            -- The cursor left and nothing else points at them; the client has
            -- their gear but we have no token to read it through
            Fail(guid)
            return
        end
        local record = NewRecord(unit, guid)
        record.name = record.name or pending.name
        pending.record = record
        if AskForHonor(record) then
            pending.stage = "honor"
            pending.at = Now()
            local mine = pending
            C_Timer.After(HONOR_TIMEOUT, function()
                if pending == mine and pending.stage == "honor" then
                    -- Gear is worth keeping even without the honor page; the
                    -- arena line simply waits for the next look
                    mine.record.arena = { known = false }
                    Finish(mine.record, true)
                end
            end)
        else
            Finish(record, true)
        end
        return
    end

    if InspectFrame and InspectFrame.unit and UnitGUID(InspectFrame.unit) == guid then
        local record = NewRecord(InspectFrame.unit, guid)
        local previous = book:Get(guid, Now())
        if previous and previous.arena and previous.arena.known then
            record.arena = previous.arena
        end
        frameTarget = { guid = guid, record = record }
        book:Put(guid, record, Now())
        if WantArena() and not record.arena.known then
            AskForHonor(record)
        end
        Commander.Notify(COMMANDER_MUSTER_EVENTS.RECORD, guid)
    end
end

local function OnInspectHonorUpdate()
    if pending and pending.stage == "honor" and pending.record then
        pending.record.arena = ReadInspectArenaFor(pending.record)
        Finish(pending.record, true)
        return
    end
    if frameTarget and frameTarget.record and InspectFrame and InspectFrame.unit
        and UnitGUID(InspectFrame.unit) == frameTarget.guid then
        frameTarget.record.arena = ReadInspectArenaFor(frameTarget.record)
        groupCheckedAt[frameTarget.guid] = time()
        book:Put(frameTarget.guid, frameTarget.record, Now())
        Commander.Notify(COMMANDER_MUSTER_EVENTS.RECORD, frameTarget.guid)
    end
end

-- An item the cache did not have when a record was made has arrived
local function OnItemInfoReceived()
    if playerRecord and not playerRecord.result.complete then
        local changed = false
        for _, entry in pairs(playerRecord.items) do
            if ReloadEntry(entry) then changed = true end
        end
        if changed then
            Rescore(playerRecord)
            Commander.Notify(COMMANDER_MUSTER_EVENTS.RECORD, playerGUID)
        end
    end
    for guid, record in pairs(incomplete) do
        if guid ~= playerGUID then
            local inBook = book:Get(guid, Now())
            local live = inBook == record
                or (pending and pending.record == record)
                or (frameTarget and frameTarget.record == record)
            if not live then
                -- Pruned from the book, or replaced by a newer inspect
                incomplete[guid] = nil
            else
                local changed = false
                for _, entry in pairs(record.items) do
                    if ReloadEntry(entry) then changed = true end
                end
                if changed then
                    Rescore(record)
                    Commander.Notify(COMMANDER_MUSTER_EVENTS.RECORD, guid)
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------

local function GearLine(record, withIlvl)
    local result = record and record.result
    if not result then return nil end
    local text = E.FormatScore(result.score)
    if withIlvl and result.count > 0 then
        text = text .. "  " .. WHITE .. "ilvl " .. result.ilvl .. "|r"
    end
    if not result.complete then
        text = text .. " " .. DIM .. "…|r"
    end
    return text
end

local function ArenaLine(record)
    local line, state = E.FormatArena(record and record.arena)
    if state == "rated" then return line, state end
    if state == "unrated" then return DIM .. "unrated|r", state end
    return DIM .. "…|r", state
end

local function QualityHex(quality)
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color and color.hex then return color.hex end
    return WHITE
end

-- The slot-by-slot breakdown, on whatever tooltip the caller hands over
local function FillBreakdown(tooltip, record)
    if not record or not record.result then return end
    local result = record.result
    tooltip:AddDoubleLine("Gear score", E.FormatScore(result.score), 1, 0.82, 0, 1, 1, 1)
    tooltip:AddDoubleLine("Average item level", tostring(result.ilvl), 1, 0.82, 0, 1, 1, 1)
    if not result.complete then
        tooltip:AddLine(DIM .. "Some pieces are still loading; the score will settle.|r")
    end
    tooltip:AddLine(" ")
    for _, row in ipairs(result.slots) do
        local slotName = D.SLOT_NAME[row.slot] or ("Slot " .. row.slot)
        local name = row.name or ItemName(row.link) or "?"
        if row.pending then
            tooltip:AddDoubleLine(DIM .. slotName .. "|r  " .. DIM .. name .. "|r", DIM .. "…|r")
        else
            tooltip:AddDoubleLine(DIM .. slotName .. "|r  " .. QualityHex(row.quality) .. name .. "|r",
                WHITE .. row.ilvl .. "|r  " .. DIM .. row.score .. "|r")
        end
    end
    if result.weakest and result.count > 1 then
        tooltip:AddLine(" ")
        tooltip:AddLine(DIM .. "Weakest piece: " .. (D.SLOT_NAME[result.weakest.slot] or "?")
            .. " (ilvl " .. result.weakest.ilvl .. ")|r")
    end
    local arena = record.arena
    if arena and arena.known then
        tooltip:AddLine(" ")
        local any, seenOnly = false, false
        for _, size in ipairs(D.BRACKETS) do
            local b = arena[size]
            if b and ((b.rating or 0) > 0 or (b.played or 0) > 0) then
                any = true
                local left = LABEL .. size .. "v" .. size .. "|r"
                if b.teamName then left = left .. "  " .. WHITE .. b.teamName .. "|r" end
                local right = E.FormatRating(b.rating or 0)
                if b.teamName and b.teamRating and b.teamRating ~= b.rating then
                    right = right .. DIM .. " (team " .. b.teamRating .. ")|r"
                end
                right = right .. "  " .. DIM .. (b.wins or 0) .. "–" .. ((b.played or 0) - (b.wins or 0)) .. "|r"
                if (b.best or 0) > 0 then
                    right = right .. "  " .. DIM .. "best|r " .. E.FormatRating(b.best)
                    if not b.bestFromServer then seenOnly = true end
                end
                tooltip:AddDoubleLine(left, right)
            end
        end
        if not any then
            tooltip:AddLine(DIM .. "Arena: unrated this season|r")
        elseif seenOnly then
            -- Only our own high comes from the server; say what the others are
            tooltip:AddLine(DIM .. "Best: the highest Muster has seen this season|r")
        end
    end
end

-- ---------------------------------------------------------------------------
-- The readout on a paper doll
-- ---------------------------------------------------------------------------

local readouts = {}

local function PaintReadout(readout)
    local record = readout.getRecord()
    readout.record = record
    if not IsOn() or not readout.enabled() or not record or not record.result then
        readout:Hide()
        return
    end
    readout.line1:SetText(LABEL .. "Gear score|r  " .. GearLine(record, db.ShowAverageItemLevel))
    if db.ShowArenaOnReadout then
        local line = ArenaLine(record)
        readout.line2:SetText(LABEL .. "Arena|r  " .. line)
        readout.line2:Show()
    else
        readout.line2:Hide()
    end
    readout:Show()
end

local function CreateReadout(name, parent, anchor, getRecord, enabled)
    local f = CreateFrame("Frame", name, parent)
    f:SetSize(170, 28)
    f:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -6, -5)
    f:SetFrameLevel((anchor:GetFrameLevel() or 1) + 5)
    f.getRecord = getRecord
    f.enabled = enabled

    f.line1 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.line1:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    f.line1:SetJustifyH("RIGHT")
    f.line2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.line2:SetPoint("TOPRIGHT", f.line1, "BOTTOMRIGHT", 0, -2)
    f.line2:SetJustifyH("RIGHT")

    -- Hover only: the model underneath still takes the drag that rotates it
    if f.EnableMouseMotion then
        f:EnableMouseMotion(true)
    else
        f:EnableMouse(true)
    end
    f:SetScript("OnEnter", function(self)
        if not self.record then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText((self.record.name or "Muster"), 1, 1, 1)
        FillBreakdown(GameTooltip, self.record)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f:Hide()
    readouts[#readouts + 1] = f
    return f
end

local characterReadout, inspectReadout

local function EnsureCharacterReadout()
    if characterReadout then return end
    if not (PaperDollFrame and CharacterModelFrame) then return end
    characterReadout = CreateReadout("CommanderMusterCharacterReadout", PaperDollFrame, CharacterModelFrame,
        function() return playerRecord end,
        function() return db.ShowOnCharacter end)
    PaperDollFrame:HookScript("OnShow", function() PaintReadout(characterReadout) end)
end

local function EnsureInspectReadout()
    if inspectReadout then return end
    if not (InspectPaperDollFrame and InspectModelFrame and InspectFrame) then return end
    inspectReadout = CreateReadout("CommanderMusterInspectReadout", InspectPaperDollFrame, InspectModelFrame,
        function()
            local unit = InspectFrame.unit
            local guid = unit and UnitGUID(unit)
            if not guid then return nil end
            if guid == playerGUID then return playerRecord end
            return (book:Get(guid, Now()))
        end,
        function() return db.ShowOnInspect end)
    InspectPaperDollFrame:HookScript("OnShow", function() PaintReadout(inspectReadout) end)
    InspectFrame:HookScript("OnHide", function()
        frameTarget = nil
        PaintReadout(inspectReadout)
    end)
end

local function RepaintAll()
    for _, readout in ipairs(readouts) do
        PaintReadout(readout)
    end
end

-- ---------------------------------------------------------------------------
-- Player tooltips
-- ---------------------------------------------------------------------------

-- The gear line needs a record of our own. The arena line takes ratings
-- from anywhere (D11), so a player we cannot inspect (the other faction, an
-- enemy, anyone out of range) still gets one when the ledger or the feed
-- knows them.
local function AddTooltipLines(tooltip, record, unit)
    if record and db.TooltipGearScore then
        local line = GearLine(record, db.TooltipItemLevel)
        if line then
            tooltip:AddDoubleLine("Gear score", line, 1, 0.82, 0, 1, 1, 1)
        end
    end
    if db.TooltipArena then
        local line = E.FormatRatings(RatingsFor(unit), time())
        if line then
            tooltip:AddDoubleLine("Arena", line, 1, 0.82, 0, 1, 1, 1)
        elseif record and record.arena and record.arena.known then
            tooltip:AddDoubleLine("Arena", DIM .. "unrated|r", 1, 0.82, 0, 1, 1, 1)
        end
    end
end

local function OnTooltipSetUnit(tooltip)
    if not IsOn() then return end
    if tooltip ~= GameTooltip then return end
    if not (db.TooltipGearScore or db.TooltipArena) then return end
    local _, unit = tooltip:GetUnit()
    if not unit or not UnitIsPlayer(unit) then return end
    local guid = UnitGUID(unit)
    if not guid then return end

    local record, fresh = RecordFor(guid)
    AddTooltipLines(tooltip, record, unit)
    if guid ~= playerGUID and (not record or not fresh or (WantArena() and not record.arena.known)) then
        Request(unit)
    end
end

-- A record arrived for the player under the cursor: rebuild the tooltip so
-- the lines appear without a second hover. SetUnit clears and refills, so
-- nothing is doubled.
local function RefreshTooltipFor(guid)
    if not GameTooltip:IsShown() then return end
    local _, unit = GameTooltip:GetUnit()
    if not unit or UnitGUID(unit) ~= guid then return end
    pcall(GameTooltip.SetUnit, GameTooltip, unit)
    GameTooltip:Show()
end

-- The classic script hook first: it is the path Commander_Tooltip's item
-- lines already ride on this client. The retail-style processor is only a
-- fallback for a build where the script stops firing.
local function HookTooltips()
    local hooked = false
    if GameTooltip and GameTooltip.HookScript then
        hooked = pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tooltip)
            pcall(OnTooltipSetUnit, tooltip)
        end)
    end
    if not hooked and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tooltip)
            pcall(OnTooltipSetUnit, tooltip)
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Slash entry points
-- ---------------------------------------------------------------------------

function CommanderMuster_Report()
    if not playerRecord or not playerRecord.result then
        print("Commander Muster: nothing scored yet")
        return
    end
    local result = playerRecord.result
    print(string.format("Commander Muster: gear score %s, average item level %d over %d pieces%s",
        E.FormatScore(result.score), result.ilvl, result.count, result.complete and "" or " (still loading)"))
    for _, row in ipairs(result.slots) do
        local slotName = D.SLOT_NAME[row.slot] or ("Slot " .. row.slot)
        if row.pending then
            print(string.format("  %-10s %s  (loading)", slotName, row.link or "?"))
        else
            print(string.format("  %-10s %s  ilvl %d  %d", slotName, row.link or row.name or "?", row.ilvl, row.score))
        end
    end
    local line, state = E.FormatArena(playerRecord.arena)
    print("  Arena: " .. (line or state))
end

function CommanderMuster_Forget()
    book = E.NewBook(BOOK_TTL, BOOK_KEEP)
    wipe(failedAt)
    for guid in pairs(incomplete) do
        if guid ~= playerGUID then incomplete[guid] = nil end
    end
    print("Commander Muster: forgot every player remembered this session")
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")

local function RegisterSafely(event)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then return end
    pcall(frame.RegisterEvent, frame, event)
end

local function OnEvent(self, event, arg1, arg2)
    if event == "PLAYER_LOGIN" then
        db = CommanderMusterDB
        playerGUID = UnitGUID("player")
        OpenBests()

        for _, e in ipairs({
            "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED",
            "GET_ITEM_INFO_RECEIVED", "INSPECT_READY", "INSPECT_HONOR_UPDATE",
            "ARENA_TEAM_UPDATE", "PVP_RATED_STATS_UPDATE", "ADDON_LOADED",
            "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED",
        }) do
            RegisterSafely(e)
        end

        HookTooltips()
        EnsureCharacterReadout()
        local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
        if isLoaded and isLoaded("Blizzard_InspectUI") then
            EnsureInspectReadout()
        end

        if not UsesTeams() and type(RequestRatedInfo) == "function" then
            pcall(RequestRatedInfo)
        end
        RefreshPlayer()
        RefreshPlayerArena()

        Commander.AddListener(COMMANDER_MUSTER_EVENTS.UPDATE, function()
            db = CommanderMusterDB
            RepaintAll()
        end)
        Commander.AddListener(COMMANDER_MUSTER_EVENTS.RECORD, function(guid)
            RepaintAll()
            if guid and guid ~= playerGUID then RefreshTooltipFor(guid) end
        end)
        return
    end

    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_InspectUI" then EnsureInspectReadout() end
        return
    end

    if not IsOn() then return end

    if event == "PLAYER_ENTERING_WORLD" then
        OpenBests()
        RefreshPlayer()
        RefreshPlayerArena()
        ScheduleGroupPump(3)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_REGEN_ENABLED" then
        ScheduleGroupPump(1)
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        RefreshPlayer()
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if arg1 == "player" then
            RefreshPlayer()
        elseif InspectFrame and InspectFrame.unit and arg1 == InspectFrame.unit then
            OnInspectReady(UnitGUID(arg1))
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        OnItemInfoReceived()
    elseif event == "INSPECT_READY" then
        OnInspectReady(arg1)
    elseif event == "INSPECT_HONOR_UPDATE" then
        OnInspectHonorUpdate()
    elseif event == "ARENA_TEAM_UPDATE" or event == "PVP_RATED_STATS_UPDATE" then
        RefreshPlayerArena()
    end
end

frame:SetScript("OnEvent", OnEvent)
