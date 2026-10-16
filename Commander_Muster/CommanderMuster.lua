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
-- One thing outlives the session: each player's best arena rating per
-- bracket, in CommanderMusterBests (D10). Ours comes from the server; for
-- everyone else it is the highest rating any inspect has shown us.

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
local BESTS_KEEP = 2000           -- most players whose season best is kept on disk

local book = E.NewBook(BOOK_TTL, BOOK_KEEP)
local bests                       -- CommanderMusterBests.players: guid -> season-best ledger entry
local bestsCount = 0
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
    local record = {
        guid = guid or UnitGUID(unit),
        name = UnitName(unit),
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
-- Season bests (D10): the one thing written to disk
-- ---------------------------------------------------------------------------

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
end

-- Folds a fresh arena read into the ledger, and the ledger's best back onto
-- the read (b.best). Returns the read, so a caller can assign through it.
local function Remember(guid, name, arena)
    if not (bests and guid and arena and arena.known) then return arena end
    local entry = bests[guid] or {}
    E.MergeBests(entry, arena)
    if not E.HasBests(entry) then
        if bests[guid] then
            bests[guid] = nil
            bestsCount = bestsCount - 1
        end
        return arena
    end
    entry.name = name or entry.name
    entry.seen = time()
    if not bests[guid] then
        bests[guid] = entry
        bestsCount = bestsCount + 1
        if bestsCount > BESTS_KEEP then bestsCount = E.PruneBests(bests, BESTS_KEEP) end
    end
    return arena
end

local function ReadInspectArenaFor(record)
    return Remember(record.guid, record.name, ReadInspectArena())
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
    playerRecord.arena = Remember(playerGUID, playerRecord.name, ReadOwnArena())
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

local TryWanted

-- Whoever was waiting behind the in-flight inspect goes next
local function ServeWanted()
    if wanted then
        C_Timer.After(0.1, TryWanted)
    end
end

local function Finish(record, notify)
    if record then
        book:Put(record.guid, record, Now())
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

local function Request(unit)
    if not IsOn() or not db.InspectOnMouseover then return false end
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
    if not unit then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    local record, fresh = RecordFor(guid)
    if record and fresh and (record.arena.known or not WantArena()) then return end
    Request(unit)
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

local function AddTooltipLines(tooltip, record)
    if db.TooltipGearScore then
        local line = GearLine(record, db.TooltipItemLevel)
        if line then
            tooltip:AddDoubleLine("Gear score", line, 1, 0.82, 0, 1, 1, 1)
        end
    end
    if db.TooltipArena then
        local line, state = ArenaLine(record)
        if state ~= "pending" then
            tooltip:AddDoubleLine("Arena", line, 1, 0.82, 0, 1, 1, 1)
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
    if record then
        AddTooltipLines(tooltip, record)
    end
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
