-- Commander Quest Log: the Reputations tab.
--
-- The third tab of the quest log window. Pick a faction -- or let it follow
-- the one you watch in the game's Reputation pane -- and see every quest that
-- pays it, for this character: what each one is worth to you NOW (the rules
-- engine's number, the same one every other surface shows), what is done,
-- what is left and what it adds up to, whether quests alone reach the next
-- standing or Exalted, the quests to do before their door shuts, and the
-- repeatables and dailies that carry on where the quests stop. It was asked
-- for by a player sweeping Hellfire Peninsula for Honor Hold who found, too
-- late, that some quests paid next to nothing and some paid nothing at all.
--
-- The machinery is the catalogue's (CommanderQuestLogCatalogue.lua), the same
-- as the Zones tab's: toolbar, card, rows, briefing pools, actions, search,
-- folds and reveal. This file only says what is particular to a FACTION, and
-- every number in it comes from two places: the Questie adapter's faction
-- view (adapter.FactionView: the engine's view of the faction's quests plus
-- view.rep, its standing, sums, sources and projection) and the rules engine
-- (Q.Standing) for words and formatting. Nothing here works reputation out
-- for itself, so nothing here can disagree with another surface.
--
-- The traps:
--
--   * Faction ids collide with area ids (faction 47 Ironforge, area 47 the
--     Hinterlands). The tab never hands a faction id to anything zone-keyed:
--     a quest's detail is read with viewKind "FACTION", Show on Map opens the
--     zone the quest starts in, and the ignore list is quest-keyed.
--   * Membership is a DIRECT row for the faction. A quest that reaches it
--     only by spillover is summarised in the overview, not listed -- except
--     the Sha'tar's window on the Aldor and Scryers quests, which the adapter
--     lists (layer EXTRA, fact.repVia = the source) and this tab puts in a
--     group of its own, never counted.
--   * A sum is not a projection. "Left" and "reaches" are the engine's
--     ordered, capped simulation (R.Project): a quest offered only below
--     Friendly is worth its value only if it is done first, and the Sha'tar's
--     spillover only lands while it is Friendly or below. The overview says
--     "in the best order" and lists the quests that have to come first.
--   * Done quests cannot be split out of a standing (it mixes quests, kills
--     and items), so their worth is called an estimate, never standing.
--   * Rotating dailies (the Wanted ones: one normal and one heroic a day)
--     are never summed as income; only today's, when it can be told. The
--     engine's count for a pool is how many of the rotation pay THIS faction
--     (Honor Hold: one normal of seven), never the rotation's size, so the
--     words never say "one of 1 a day".
--   * RepPicked is account-wide: a pin of the other side's faction (an
--     alt's) is passed over, not shown as a dead end.
--   * A quest's REPUTATION section is the Zones tab's painter, so both tabs
--     word it alike; here it comes straight under the quest's reason.
--   * The watched faction is read, never set from a guess: Watch Faction
--     finds the faction's row in the client's Reputation list by a read-only
--     walk and watches it, and a faction under a folded heading is reported,
--     not unfolded (ExpandFactionHeader would rewrite the player's pane).
--   * Words for a standing come from the client (GetText with the player's
--     sex: some locales have female forms), English only as the fallback.
--   * No glyphs (D11), every colour on the sheet through Paper (D16): the
--     catalogue's Line does it for text; the standing bar, the one colour of
--     this tab's own (FACTION_BAR_COLORS, as the game's own pane draws it),
--     goes through the kit's Paper here.

CommanderQuestLog = CommanderQuestLog or {}
local Q = CommanderQuestLog

local C = Q.Catalogue
-- A catalogue that failed to load leaves the window with the Log alone
if not (C and C.New) then return end

local Kit, Engine, Adapter, DB = C.Kit, C.Engine, C.Adapter, C.DB
local InkT = C.InkT
local SEP, ELLIPSIS = C.SEP, C.ELLIPSIS

-- The tab button's width: "Reputations" in GameFontNormalSmall is about 60
-- px, and the label wants the strip's margin on either side
local TAB_W = 78
local MAX_LISTED = 6            -- lines a section lists before "and N more"
local EXALTED = 42000
local STANDING_BAR_H = 6

-- The game's own reputation bar colours by standingID (FrameXML's
-- FACTION_BAR_COLORS, read live), in case a client has none
local BAR_FALLBACK = {
    { 0.80, 0.30, 0.22 }, { 0.80, 0.30, 0.22 }, { 0.75, 0.27, 0.00 }, { 0.90, 0.70, 0.00 },
    { 0.00, 0.60, 0.10 }, { 0.00, 0.60, 0.10 }, { 0.00, 0.60, 0.10 }, { 0.00, 0.60, 0.10 },
}

-- The Wanted dailies' two pools (the generated data's `rotating`)
local POOL_WORDS = { NORMAL = "Wanted (normal)", HEROIC = "Wanted (heroic)" }
local POOL_ORDER = { "NORMAL", "HEROIC" }
local CONDITION_WORDS = { HALAA = "only while your side holds Halaa" }

-- Group modes (the dropdown) and the Guide's fixed titles. The titles are
-- what RepCollapsed is keyed by, so they are constants.
local GROUPS = { "GUIDE", "BYZONE", "BYVALUE", "STATUS", "CHAIN" }
local GROUP_LABELS = {
    GUIDE = "Guide", BYZONE = "By zone", BYVALUE = "By value", STATUS = "By status", CHAIN = "By chain",
}
local T = {
    TURN_IN = "Turn in", IN_PROGRESS = "In progress", WILL_LOCK = "Will lock soon",
    PICK_UP = "Pick up now", UNLOCKS_LEVEL = "Unlocks with level", AFTER_QUEST = "After another quest",
    NEEDS_REP_SKILL = "Needs reputation or skill", DONE = "Done",
    MISSED = "Missed", RIVAL = "Other faction", REPEATABLE = "Repeatable sources", DAILY = "Dailies",
    SEASONAL = "Seasonal", OPTIONAL = "Optional", EXTRA = "Also listed", IGNORED = "Ignored",
}
-- The Guide's to-do groups, then Done, then the uncounted tail (VIA is the
-- spill window's group, titled by its sources)
local GUIDE_ORDER = { "TURN_IN", "IN_PROGRESS", "WILL_LOCK", "PICK_UP", "UNLOCKS_LEVEL", "AFTER_QUEST", "NEEDS_REP_SKILL" }
local TAIL_ORDER = { "MISSED", "RIVAL", "REPEATABLE", "DAILY", "VIA", "SEASONAL", "OPTIONAL", "EXTRA", "IGNORED" }
local COUNTED = { DONE = true, LOG = true, AVAILABLE = true, LOCKED = true }
local GONE = { DONE = true, MISSED = true, RIVAL = true }

local FILTER_SPECS = {
    ALL = { label = "All", tooltip = "Every quest that pays this faction, counted or not: once-only quests, repeatables, dailies and the quests that reach it by spillover." },
    OPEN = { label = "Open", tooltip = "Quests you can work on now: in your log, or ready to pick up." },
    LOCKED = { label = "Locked", tooltip = "Quests waiting on your level, an earlier quest, reputation, a skill or a choice." },
    DONE = { label = "Done", tooltip = "Quests you have turned in." },
    MISSED = { label = "Missed", tooltip = "Quests this character can no longer get, each with the reason." },
}

-- ---------------------------------------------------------------------------
-- Reaching the rules and the data
-- ---------------------------------------------------------------------------

-- The rules engine, or nil: without it the adapter has no faction view
-- either, and every painter here says so rather than guessing
local function Rules()
    local R = Q.Standing
    if type(R) == "table" and type(R.Rank) == "function" and type(R.FormatRep) == "function"
        and type(R.StandingWord) == "function" then
        return R
    end
    return nil
end

-- The generated data (factions, groups); read for which ids are factions at
-- all, never for a number -- the numbers are the adapter's
local function Data()
    local D = CommanderQuestLogReputationData
    if type(D) == "table" and type(D.factions) == "table" then return D end
    return nil
end

local function Fmt(n)
    local R = Rules()
    if R and R.FormatNumber then return R.FormatNumber(n) or tostring(n) end
    return tostring(n)
end

local function FmtRep(n)
    local R = Rules()
    if R then return R.FormatRep(n) or tostring(n) end
    return tostring(n)
end

-- The client's standing words for this character (GetText picks a _FEMALE
-- form where the locale has one), English filling any gap
local labels
local function Labels()
    if labels then return labels end
    local out, sex = {}, nil
    if UnitSex then
        local ok, value = pcall(UnitSex, "player")
        if ok then sex = value end
    end
    for n = 1, 8 do
        local text
        if GetText then
            local ok, value = pcall(GetText, "FACTION_STANDING_LABEL" .. n, sex)
            if ok then text = value end
        end
        if type(text) ~= "string" or text == "" then text = _G["FACTION_STANDING_LABEL" .. n] end
        if type(text) == "string" and text ~= "" then out[n] = text end
    end
    labels = out
    return out
end

local function RankWord(rank)
    local R = Rules()
    return R and R.StandingWord(rank, Labels()) or nil
end

local function WordFor(value)
    local R = Rules()
    if not (R and value) then return nil end
    return R.StandingWord((R.Rank(value)), Labels())
end

local function Progress(value)
    local R = Rules()
    if not (R and value) then return nil end
    return R.FormatProgress(value, Labels())
end

-- At the ceiling (Exalted 999 / 1,000, the rules engine's R.CAP) every
-- quest and daily pays 0, and the sections say that once instead of
-- listing zeros (2026-10-05 review: "up to 0", "worth 0", and a Wanted pick
-- blamed for a day that pays nothing whatever is offered)
local function AtCeiling(value)
    local R = Rules()
    local cap = R and tonumber(R.CAP) or 42999
    return (tonumber(value) or 0) >= cap
end

-- A faction's name: the client's (localised) once met, this locale's from
-- the data before that, else English (the adapter's FactionName)
local function NameOf(factionId)
    local adapter = Adapter()
    if adapter and adapter.FactionName then
        local ok, name = pcall(adapter.FactionName, factionId)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    local D = Data()
    local row = D and D.factions[factionId]
    if type(row) == "table" and type(row.name) == "string" then return row.name end
    return "Faction " .. tostring(factionId)
end

-- "The Aldor" -> "Aldor", for a title made of names ("Via Aldor/Scryers")
local function ShortName(name)
    return (tostring(name or ""):gsub("^[Tt]he%s+", ""))
end

-- "The Aldor" -> "the Aldor", for a name inside a sentence of ours; "the
-- Aldor's", "the Scryers'" (the catalogue's, which the Zones tab uses too)
local InSentence, Possessive = C.InSentence, C.Possessive

-- A value where a quest stops paying: "the top of Friendly" when it is the
-- last point of a rank (8,999), else the point and its rank
local function CapWords(cap)
    local R = Rules()
    if not (R and cap) then return tostring(cap) end
    local rank = R.Rank(cap)
    if R.RankTop and R.RankTop(rank) == cap then return "the top of " .. (RankWord(rank) or "the rank") end
    return Fmt(cap) .. " (" .. (RankWord(rank) or "") .. ")"
end

-- "half", "a quarter": a spill rate as words
local function RateWord(rate)
    rate = tonumber(rate) or 0
    if rate == 0.5 then return "half" end
    if rate == 0.25 then return "a quarter" end
    if rate == 1 then return "all" end
    return string.format("%d%%", math.floor(math.abs(rate) * 100 + 0.5))
end

local function Plural(count, one, many)
    return count == 1 and ("1 " .. one) or (count .. " " .. (many or (one .. "s")))
end

-- The player's side: what the adapter worked out, else the client's word
local function PlayerSide(cat)
    local char = cat and cat.S.char
    if type(char) == "table" and char.repSide then return char.repSide end
    if UnitFactionGroup then
        local ok, side = pcall(UnitFactionGroup, "player")
        if ok and (side == "Alliance" or side == "Horde") then return side end
    end
    return nil
end

-- A faction this tab can show: in the data, not a heading, not the other
-- side's
local function Listable(factionId, side)
    local D = Data()
    local row = D and factionId and D.factions[factionId]
    if type(row) ~= "table" or row.header then return false end
    if side and row.side and row.side ~= side then return false end
    return true
end

-- The other side's faction (Thrallmar to an Alliance character)
local function OtherSide(factionId, side)
    local D = Data()
    local row = D and factionId and D.factions[factionId]
    return type(row) == "table" and side ~= nil and row.side ~= nil and row.side ~= side
end

-- ---------------------------------------------------------------------------
-- The client's Reputation pane, read only
-- ---------------------------------------------------------------------------

-- name, isHeader, isCollapsed, isWatched, factionID of the pane's row
local function PaneRow(index)
    local ok, name, _, _, _, _, _, _, _, isHeader, isCollapsed, _, isWatched, _, factionId =
        pcall(GetFactionInfo, index)
    if not ok then return nil end
    return name, isHeader, isCollapsed, isWatched, tonumber(factionId)
end

local function PaneSize()
    if not (GetNumFactions and GetFactionInfo) then return 0 end
    local ok, count = pcall(GetNumFactions)
    return (ok and tonumber(count)) or 0
end

-- The faction on the game's reputation bar, or nil. The 2.5.6 client has
-- C_Reputation.GetWatchedFactionData (GetWatchedFactionInfo is not in it);
-- the pane's own isWatched is the last resort.
local function WatchedFaction()
    local reputation = C_Reputation
    if type(reputation) == "table" and type(reputation.GetWatchedFactionData) == "function" then
        local ok, data = pcall(reputation.GetWatchedFactionData)
        if ok then
            local id = type(data) == "table" and tonumber(data.factionID) or nil
            if id and id > 0 then return id end
            return nil
        end
    end
    if GetWatchedFactionInfo then
        local ok, name, _, _, _, _, id = pcall(GetWatchedFactionInfo)
        if ok then
            if name and tonumber(id) and tonumber(id) > 0 then return tonumber(id) end
            return nil
        end
    end
    for index = 1, PaneSize() do
        local name, _, _, isWatched, factionId = PaneRow(index)
        if name and isWatched and factionId then return factionId end
    end
    return nil
end

-- The pane's row for a faction: index, or nil and why ("FOLDED" when some
-- heading is folded shut and it could be under it, "ABSENT", "NO_API")
local function PaneIndex(factionId)
    if not (GetNumFactions and GetFactionInfo and SetWatchedFactionIndex) then return nil, "NO_API" end
    local folded = false
    for index = 1, PaneSize() do
        local name, isHeader, isCollapsed, _, id = PaneRow(index)
        if name and id == factionId then return index end
        if isHeader and isCollapsed then folded = true end
    end
    return nil, folded and "FOLDED" or "ABSENT"
end

local function IsMet(factionId)
    if not GetFactionInfoByID then return false end
    local ok, name = pcall(GetFactionInfoByID, factionId)
    return ok and type(name) == "string" and name ~= ""
end

-- Watch Faction: the faction's own row, found without unfolding anything,
-- watched the way the pane's "Show as experience bar" box does it
local function WatchFaction(cat)
    local factionId = cat.S.key
    if not factionId then return end
    local name = cat.S.keyName or NameOf(factionId)
    if not IsMet(factionId) then
        print("Commander Quest Log: you have not met " .. name .. " yet, so the game has nothing to watch.")
        return
    end
    local index, why = PaneIndex(factionId)
    if not index then
        if why == "FOLDED" then
            print("Commander Quest Log: " .. name .. " is under a folded heading in the game's Reputation pane. Unfold it there and try again; this window leaves the pane as you arranged it.")
        elseif why == "NO_API" then
            print("Commander Quest Log: this client cannot set the watched faction.")
        else
            print("Commander Quest Log: " .. name .. " is not in the game's Reputation pane.")
        end
        return
    end
    pcall(SetWatchedFactionIndex, index)
    if Q.QueueRefresh then Q.QueueRefresh() end
end

-- ---------------------------------------------------------------------------
-- Which faction
--
-- Following: the faction you watch (the game's reputation bar) when the tab
-- can show it; else the faction the quests in your log pay most, summed over
-- their direct gains; else whatever was last pinned. Pinned: RepPicked.
-- ---------------------------------------------------------------------------

local function LogFaction(cat, side)
    local adapter = Adapter()
    if not (adapter and adapter.RepEffects) then return nil end
    local totals, best, bestTotal = {}, nil, 0
    for _, logEntry in pairs(cat.S.logByKey or {}) do
        local questId = tonumber(logEntry.questID)
        local effects = questId and adapter.RepEffects(questId)
        for _, effect in ipairs(type(effects) == "table" and effects or {}) do
            local factionId = effect.factionId
            if effect.kind == "DIRECT" and (effect.delta or 0) > 0 and Listable(factionId, side) then
                totals[factionId] = (totals[factionId] or 0) + effect.delta
            end
        end
    end
    for factionId, total in pairs(totals) do
        if total > bestTotal or (total == bestTotal and best and factionId < best) then
            best, bestTotal = factionId, total
        end
    end
    return best
end

-- RepPicked is account-wide (CommanderQuestLogDB), so a pin can come from an
-- alt of the other side: that one is passed over, never shown as a dead end
-- this character could not have picked (S.pinnedOther says whose it was)
local function ResolveFaction(cat)
    local db = DB()
    local S = cat.S
    local side = PlayerSide(cat)
    S.followedBy, S.pinnedOther = nil, nil
    if db.RepFollow ~= false then
        local watched = WatchedFaction()
        if watched and Listable(watched, side) then
            S.followedBy = "WATCHED"
            return watched, NameOf(watched)
        end
        local fromLog = LogFaction(cat, side)
        if fromLog then
            S.followedBy = "LOG"
            return fromLog, NameOf(fromLog)
        end
        S.followedBy = "NONE"
    end
    local picked = tonumber(db.RepPicked)
    if picked and picked ~= 0 then
        if OtherSide(picked, side) then
            S.pinnedOther = picked
            return nil, nil
        end
        return picked, NameOf(picked)
    end
    return nil, nil
end

-- ---------------------------------------------------------------------------
-- An entry's reputation
-- ---------------------------------------------------------------------------

-- The engine's effect of this quest on the faction on the card (the adapter
-- sets entry.repEffect on every entry of a faction view)
local function EffectOf(entry)
    local effect = entry and entry.repEffect
    if type(effect) == "table" and type(effect.delta) == "number" then return effect end
    return nil
end

local function DeltaOf(entry)
    local effect = EffectOf(entry)
    return effect and effect.delta or 0
end

-- The faction's own gate on a quest: offered while F < gateMax, once F >=
-- gateMin (Questie's pairs)
local function GatesOf(entry, factionId)
    local fact = entry and entry.fact or {}
    local maxRep, minRep = fact.maxRep, fact.minRep
    local gateMax = type(maxRep) == "table" and maxRep[1] == factionId and tonumber(maxRep[2]) or nil
    local gateMin = type(minRep) == "table" and minRep[1] == factionId and tonumber(minRep[2]) or nil
    return gateMax, gateMin
end

-- "before Friendly" for a gate one short of a rank or on it, else the point
-- ("below Friendly 1,500")
local function GateWords(gateMax)
    local R = Rules()
    if not (R and gateMax) then return tostring(gateMax) end
    local rank, rankMin = R.Rank(gateMax + 1)
    if gateMax + 1 == rankMin or gateMax == rankMin then return RankWord(rank) end
    local ownRank, ownMin = R.Rank(gateMax)
    return (RankWord(ownRank) or "") .. " " .. Fmt(gateMax - ownMin)
end

-- Counted, not done, and its door shuts as the faction rises: offered only
-- below a standing it has not reached yet
local function WillLock(entry, factionId, value)
    if not (entry.counted and (entry.base == "AVAILABLE" or entry.base == "LOCKED")) then return false end
    if entry.reasonKey == "REP_HIGH" then return false end
    local gateMax = GatesOf(entry, factionId)
    return gateMax ~= nil and (value or 0) < gateMax
end

-- ---------------------------------------------------------------------------
-- Grouping
--
-- The Guide is the engine's, retold for a faction: what can be locked out
-- comes before what can wait, a quest worth more comes before one worth
-- less, repeatables and dailies are sources (two groups of their own, not
-- "Dailies and repeatables"), and the spill window's quests are a group of
-- their own. By zone and by value are new; by status and by chain are the
-- engine's. Every grouping writes entry.header through cat.Emit, the last
-- word on the headings (see the catalogue's header).
-- ---------------------------------------------------------------------------

local function Num(value) return tonumber(value) or 0 end

local function LevelNameBefore(a, b)
    local la, lb = Num(a.level), Num(b.level)
    if la ~= lb then return la < lb end
    local ta, tb = (a.title or ""):lower(), (b.title or ""):lower()
    if ta ~= tb then return ta < tb end
    return a.id < b.id
end

local function ValueBefore(a, b)
    local da, db = DeltaOf(a), DeltaOf(b)
    if da ~= db then return da > db end
    return LevelNameBefore(a, b)
end

local function LockLevel(entry)
    return Num(entry.lock and entry.lock.level or entry.requiredLevel)
end

-- The spill window's group title: "Via Aldor/Scryers (until Honored)"
local function ViaTitle(view)
    local rep = view.rep or {}
    local sources, seen, maxRankIn = {}, {}, nil
    for _, entry in ipairs(view.entries or {}) do
        local source = entry.fact and entry.fact.repVia
        if source and not seen[source] then
            seen[source] = true
            sources[#sources + 1] = source
        end
    end
    table.sort(sources)
    for _, window in ipairs(rep.spill and rep.spill.windows or {}) do
        if seen[window.source] then maxRankIn = window.maxRankIn end
    end
    local names = {}
    for _, source in ipairs(sources) do names[#names + 1] = ShortName(NameOf(source)) end
    local title = "Via " .. (#names > 0 and table.concat(names, "/") or "spillover")
    local word = maxRankIn and RankWord(maxRankIn + 1)
    if word then title = title .. " (until " .. word .. ")" end
    return title
end

-- The Guide's key for one entry (the engine's GuideKey, plus the new groups)
local function GuideKey(entry, factionId, value)
    local status = entry.status
    if status == "IGNORED" then return "IGNORED" end
    if entry.fact and entry.fact.repVia then return "VIA" end
    if status == "LOG" then return entry.ready and "TURN_IN" or "IN_PROGRESS" end
    if (status == "AVAILABLE" or status == "LOCKED") and WillLock(entry, factionId, value) then return "WILL_LOCK" end
    if status == "AVAILABLE" then return "PICK_UP" end
    if status == "LOCKED" then
        local kind = entry.lockKind
        if kind == "LEVEL" then return "UNLOCKS_LEVEL" end
        if kind == "PREREQ" or kind == "CHOICE" then return "AFTER_QUEST" end
        return "NEEDS_REP_SKILL"
    end
    if status == "REPEATABLE" then return (entry.fact and entry.fact.daily) and "DAILY" or "REPEATABLE" end
    return status
end

local function Buckets(view, factionId, value)
    local buckets = {}
    for _, entry in ipairs(view.entries or {}) do
        local key = GuideKey(entry, factionId, value)
        buckets[key] = buckets[key] or {}
        table.insert(buckets[key], entry)
    end
    local chainIndex = {}
    for index, chain in ipairs(view.chains or {}) do chainIndex[chain.id] = index end
    for key, list in pairs(buckets) do
        if key == "PICK_UP" or key == "REPEATABLE" or key == "DAILY" or key == "VIA" then
            table.sort(list, ValueBefore)
        elseif key == "WILL_LOCK" then
            table.sort(list, function(a, b)
                local ga, gb = GatesOf(a, factionId), GatesOf(b, factionId)
                if ga ~= gb then return (ga or 0) < (gb or 0) end
                return ValueBefore(a, b)
            end)
        elseif key == "UNLOCKS_LEVEL" then
            table.sort(list, function(a, b)
                local la, lb = LockLevel(a), LockLevel(b)
                if la ~= lb then return la < lb end
                return LevelNameBefore(a, b)
            end)
        elseif key == "AFTER_QUEST" then
            table.sort(list, function(a, b)
                local ca, cb = chainIndex[a.chain] or math.huge, chainIndex[b.chain] or math.huge
                if ca ~= cb then return ca < cb end
                local pa, pb = a.chainPos or 0, b.chainPos or 0
                if pa ~= pb then return pa < pb end
                return LevelNameBefore(a, b)
            end)
        else
            table.sort(list, LevelNameBefore)
        end
    end
    return buckets
end

local function EmitTail(cat, list, buckets, view)
    for _, key in ipairs(TAIL_ORDER) do
        local members = buckets[key]
        if members and #members > 0 then
            cat.Emit(list, key, key == "VIA" and ViaTitle(view) or T[key], members)
        end
    end
end

local function GroupGuide(cat, view, factionId, value)
    local list = {}
    local buckets = Buckets(view, factionId, value)
    for _, key in ipairs(GUIDE_ORDER) do
        if buckets[key] then cat.Emit(list, key, T[key], buckets[key]) end
    end
    if buckets.DONE then cat.Emit(list, "DONE", T.DONE, buckets.DONE) end
    EmitTail(cat, list, buckets, view)
    return list
end

-- The zone a quest is filed under (its quest-log heading), by name
local function ZoneOf(entry)
    local adapter = Adapter()
    local zone = entry.fact and tonumber(entry.fact.zoneOrSort)
    if zone and zone ~= 0 and adapter and adapter.ZoneName then return adapter.ZoneName(zone) end
    return entry.startZoneName or "Elsewhere"
end

local function GroupByZone(cat, view)
    local list, byZone, names = {}, {}, {}
    for _, entry in ipairs(view.entries or {}) do
        local name = ZoneOf(entry)
        if not byZone[name] then
            byZone[name] = {}
            names[#names + 1] = name
        end
        table.insert(byZone[name], entry)
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    for _, name in ipairs(names) do
        local members = byZone[name]
        -- the quests that count first, each part by level
        table.sort(members, function(a, b)
            if (a.counted and true or false) ~= (b.counted and true or false) then return a.counted and true or false end
            return LevelNameBefore(a, b)
        end)
        cat.Emit(list, "ZONE:" .. name, name, members)
    end
    return list
end

-- Still to gain, by what each pays now (highest first); then Done; then the
-- uncounted groups, as the Guide has them
local function GroupByValue(cat, view, factionId, value)
    local list, byValue, values = {}, {}, {}
    local buckets = Buckets(view, factionId, value)
    for _, entry in ipairs(view.entries or {}) do
        if COUNTED[entry.status] and entry.status ~= "DONE" then
            local delta = DeltaOf(entry)
            if not byValue[delta] then
                byValue[delta] = {}
                values[#values + 1] = delta
            end
            table.insert(byValue[delta], entry)
        end
    end
    table.sort(values, function(a, b) return a > b end)
    for _, delta in ipairs(values) do
        local members = byValue[delta]
        table.sort(members, LevelNameBefore)
        local capped = false
        for _, entry in ipairs(members) do
            local effect = EffectOf(entry)
            if effect and effect.capped then capped = true end
        end
        local title = FmtRep(delta) .. ((delta == 0 and capped) and " (capped)" or "")
        cat.Emit(list, "VALUE:" .. delta, title, members)
    end
    if buckets.DONE then
        table.sort(buckets.DONE, ValueBefore)
        cat.Emit(list, "DONE", T.DONE, buckets.DONE)
    end
    EmitTail(cat, list, buckets, view)
    return list
end

local function GroupFaction(cat, view, mode)
    local rep = view.rep or {}
    local factionId, value = rep.factionId or cat.S.key, rep.value
    if mode == "GUIDE" then return GroupGuide(cat, view, factionId, value) end
    if mode == "BYZONE" then return GroupByZone(cat, view) end
    if mode == "BYVALUE" then return GroupByValue(cat, view, factionId, value) end
    -- STATUS, CHAIN (and anything unknown): the engine's
    return nil
end

-- ---------------------------------------------------------------------------
-- Rows: a badge with what the quest pays this faction, words for sources
-- ---------------------------------------------------------------------------

local function RowRight(cat, entry)
    local effect = EffectOf(entry)
    if not effect then return nil end
    local delta = effect.delta
    if delta == 0 then
        if effect.capped then return "0 capped", "faint", true end
        return "0", "faint", true
    end
    if delta < 0 then return FmtRep(delta), "bad" end
    -- the console accent, on the paper like every colour here (the
    -- catalogue puts it through Paper)
    local kit = Kit()
    return FmtRep(delta), kit and { kit.Accent() } or "good"
end

-- Repeatables are sources here, so they say what their bucket would: a
-- repeatable you can do is "open", one behind a standing says which ("Honored",
-- where the engine says "daily"), one behind a level, a chain or the other
-- side says so too. A daily you can do is the engine's "today".
local function StateWord(cat, entry)
    if entry.status ~= "REPEATABLE" then return nil end
    local fact = entry.fact or {}
    local base = entry.base
    if base == "LOG" or base == "DONE" or entry.reasonKey == "NOT_TODAY" then return nil end
    if base == "AVAILABLE" then
        if fact.daily then return nil end
        return "open", "open"
    end
    if base == "LOCKED" and entry.lockKind == "REP" and not entry.rival then
        local gateMax, gateMin = GatesOf(entry, cat.S.key)
        local value = cat.S.view and cat.S.view.rep and cat.S.view.rep.value
        if gateMax and value and value >= gateMax then return "closed", "faint" end
        local pair = gateMin or (type(fact.minRep) == "table" and tonumber(fact.minRep[2])) or nil
        local word = pair and WordFor(pair)
        if word and #word <= 8 then return word, "warn" end
        return "rep", "warn"
    end
    -- the engine's word for the bucket underneath (lv 64, chain, rival, missed)
    local engine = Engine()
    if not engine then return nil end
    local under = setmetatable({ status = base }, { __index = entry })
    return engine.StateWord(under)
end

-- The repeatable's own line from view.rep.repeatables
local function RepeatableInfo(cat, questId)
    local rep = cat.S.view and cat.S.view.rep
    for _, info in ipairs(rep and rep.repeatables or {}) do
        if info.questId == questId then return info end
    end
    return nil
end

local function SpillSentence(cat, entry)
    local rep = cat.S.view and cat.S.view.rep or {}
    local source = entry.fact and entry.fact.repVia
    local window
    for _, candidate in ipairs(rep.spill and rep.spill.windows or {}) do
        if candidate.source == source then window = candidate end
    end
    local name = InSentence(rep.name or cat.S.keyName or "this faction")
    local text = "Pays " .. name .. " only as spillover: " .. RateWord(window and window.rate or 0.5)
        .. " of what it pays " .. InSentence(NameOf(source))
    if window then
        text = text .. ", while " .. name .. " is " .. (RankWord(window.maxRankIn) or "low enough") .. " or below"
    end
    return text .. "; not counted here."
end

-- The engine's sentence for the bucket underneath a source's own (a
-- repeatable behind a standing: "Needs Friendly with the Aldor.")
local function BaseReason(cat, entry)
    local engine = Engine()
    if not engine then return "" end
    local under = setmetatable({ status = entry.base }, { __index = entry })
    return engine.Reason(under, cat.S.char or {}, cat.S.view) or ""
end

local function Reason(cat, entry)
    local fact = entry.fact or {}
    if fact.repVia then
        local sentence = BaseReason(cat, entry)
        return (sentence ~= "" and (sentence .. " ") or "") .. SpillSentence(cat, entry)
    end
    if entry.status ~= "REPEATABLE" or entry.reasonKey == "NOT_TODAY" or entry.base == "LOG" or entry.base == "DONE" then
        return nil
    end
    local gain = DeltaOf(entry)
    if entry.base ~= "AVAILABLE" then
        local kind = fact.daily and "a daily" or "a repeatable source"
        if entry.base == "LOCKED" and not entry.rival then
            return BaseReason(cat, entry) .. " Then " .. kind .. ": " .. FmtRep(gain) .. " a turn-in; not counted here."
        end
        return BaseReason(cat, entry) .. " " .. (fact.daily and "A daily" or "A repeatable") .. "; not counted here."
    end
    if fact.daily then
        local D = Data()
        if D and type(D.rotating) == "table" and D.rotating[entry.id] then
            return "A Wanted daily: " .. FmtRep(gain) .. ", on the days it is offered (one normal and one heroic a day, in rotation); not counted here."
        end
        return "A daily: " .. FmtRep(gain) .. " a turn-in, once a day; not counted here."
    end
    local info = RepeatableInfo(cat, entry.id)
    local text = "A repeatable source: " .. FmtRep(gain) .. " a turn-in"
    if info and info.toNext and info.nextRank then
        text = text .. ", " .. Plural(info.toNext, "turn-in") .. " to " .. (RankWord(info.nextRank) or "the next standing")
    elseif info and info.capped then
        text = text .. ", but it pays nothing more at your standing"
    elseif info and info.toCap and info.toCap > 0 and (info.cap or 0) < EXALTED then
        text = text .. ", " .. Plural(info.toCap, "turn-in") .. " before it stops"
    end
    return text .. ". Not counted here."
end

-- The full line in the row's tooltip, the same words the briefing and every
-- other surface use
local function RowTooltip(cat, entry)
    local adapter = Adapter()
    if not (adapter and adapter.RepLine) then return end
    local effects = entry.fact and entry.fact.repEffects
    local line = adapter.RepLine(entry.id, type(effects) == "table" and { effects = effects } or nil)
    if not line then return end
    -- "No reputation" stands alone, as on every other surface
    local R = Rules()
    GameTooltip:AddLine((R and line == R.NO_REPUTATION) and line or ("Reputation: " .. line), 0.85, 0.85, 0.85, true)
    local effect = EffectOf(entry)
    if effect and effect.capNote then GameTooltip:AddLine("Capped: " .. effect.capNote .. ".", 0.7, 0.7, 0.75, true) end
    for _, other in ipairs(type(effects) == "table" and effects or {}) do
        if other.observed then
            GameTooltip:AddLine("Seen in game: what the game paid you, not the quest data.", 0.7, 0.7, 0.75, true)
            break
        end
    end
end

-- Level, requires, the quest's own zone, its kind; the faction is the card's
local function Facts(cat, entry)
    local facts = {}
    local fact = entry.fact or {}
    if (entry.level or 0) > 0 then facts[#facts + 1] = "Level " .. entry.level end
    if (entry.requiredLevel or 0) > 0 then facts[#facts + 1] = "requires " .. entry.requiredLevel end
    local zone = ZoneOf(entry)
    if zone then facts[#facts + 1] = zone end
    if entry.tag and C.TAG_WORDS[entry.tag] then facts[#facts + 1] = C.TAG_WORDS[entry.tag] end
    if entry.startZoneName and entry.startZoneName ~= zone then
        facts[#facts + 1] = "starts in " .. entry.startZoneName
    end
    if fact.daily then
        facts[#facts + 1] = "daily"
    elseif fact.repeatable then
        facts[#facts + 1] = "repeatable"
    end
    if not entry.counted then facts[#facts + 1] = "not counted" end
    return facts
end

-- ---------------------------------------------------------------------------
-- The faction menu: the generated groups (Outland, Shattrath, the other TBC
-- factions, then the classic headings), paged by the catalogue where one
-- outruns a screen. Each faction says its standing; its tooltip says how
-- many quests pay it.
-- ---------------------------------------------------------------------------

local function MenuSummaryArrived() end

-- "Honor Hold  Honored  ·  31/49 done": the count says what it counts (once-
-- only quests done), where a bare percentage beside the standing word read as
-- progress through the standing
local function MenuText(item)
    local adapter = Adapter()
    local text = item.name or ("Faction " .. tostring(item.factionId))
    if item.word then text = text .. "  " .. item.word end
    local summary = adapter and adapter.FactionSummary and adapter.FactionSummary(item.factionId, true)
    local counted = summary and tonumber(summary.counted) or 0
    if counted > 0 then
        text = text .. SEP .. string.format("%d/%d done", tonumber(summary.done) or 0, counted)
    elseif item.quests == 0 and (item.phaseHidden or 0) == 0 then
        text = text .. SEP .. "no quests"
    end
    return text
end

local function MenuInit(cat, level, menuList)
    level = level or 1
    local adapter = Adapter()
    local db = DB()
    if level == 1 then
        local info = UIDropDownMenu_CreateInfo()
        info.text = "The faction I watch"
        info.checked = db.RepFollow ~= false
        info.func = cat.Follow
        UIDropDownMenu_AddButton(info, level)
        local menu = adapter and adapter.FactionMenu and adapter.FactionMenu() or {}
        cat.S.menu = menu
        for _, group in ipairs(menu) do cat.AddCategoryPages(group) end
        return
    end
    local page = type(menuList) == "table" and menuList or nil
    local key = page and page.key or menuList
    local picked = db.RepFollow == false and tonumber(db.RepPicked) or nil
    for _, group in ipairs(cat.S.menu or {}) do
        if group.key == key then
            local items = group.items or {}
            local ids = {}
            for index = (page and page.first or 1), (page and page.last or #items) do
                local item = items[index]
                if item then
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = MenuText(item)
                    info.checked = picked == item.factionId
                    info.arg1 = item.factionId
                    info.func = cat.Pick
                    if item.note then
                        info.tooltipTitle = item.name
                        info.tooltipText = item.note
                        info.tooltipOnButton = true
                    end
                    UIDropDownMenu_AddButton(info, level)
                    ids[#ids + 1] = item.factionId
                end
            end
            if adapter and adapter.RequestSummaries and #ids > 0 then
                adapter.RequestSummaries(ids, MenuSummaryArrived, "FACTION")
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- The card: name, standing, a bar in the standing's colour, and how far the
-- quests take it
-- ---------------------------------------------------------------------------

local function StandingRGB(rank)
    local colours = FACTION_BAR_COLORS
    local colour = type(colours) == "table" and colours[(rank or 3) + 1] or nil
    if type(colour) == "table" and tonumber(colour.r) then return colour.r, colour.g, colour.b end
    colour = BAR_FALLBACK[(rank or 3) + 1] or BAR_FALLBACK[4]
    return colour[1], colour[2], colour[3]
end

-- How far into its rank a value is (Exalted at the cap: 999 of 1000)
local function RankFraction(value)
    local R = Rules()
    if not (R and value) then return 0 end
    local rank, rankMin, rankMax = R.Rank(value)
    if not rank or rankMax <= rankMin then return 0 end
    local clamped = math.max(math.min(value, 42999), -42000)
    return math.max(0, math.min(1, (clamped - rankMin) / (rankMax - rankMin))), rank
end

-- The standing the card and the overview stand on: the view's, else the
-- adapter's reading without a view (no quests, the other side, indexing)
local function StandingOf(cat)
    local S = cat.S
    local rep = S.view and S.view.rep
    if rep then return rep end
    local adapter = Adapter()
    if S.key and adapter and adapter.FactionStanding then
        local ok, standing = pcall(adapter.FactionStanding, S.key)
        if ok and type(standing) == "table" then return standing end
    end
    return nil
end

-- The card's second line, short enough for the card: "+4,250 in quests
-- ·  reaches Revered", "No quests left  ·  repeatables reach Honored". The
-- tooltip and the overview say it in full.
local function ReachWords(rep)
    local projection = rep and rep.projection
    if not projection then return nil end
    if (rep.value or 0) >= EXALTED then return "Exalted: nothing more to earn" end
    local left = projection.left or 0
    if left <= 0 then
        if (projection.repeatReach or 0) > (projection.reach or 0) then
            return "No quests left" .. SEP .. "repeatables reach " .. ((projection.repeatReach >= EXALTED)
                and "Exalted" or (WordFor(projection.repeatReach) or "further"))
        end
        return "No quests left"
    end
    local reachRank = projection.rank
    local word = (projection.reach or 0) >= EXALTED and RankWord(7) or RankWord(reachRank)
    if reachRank and rep.rank and reachRank > rep.rank and word then
        return FmtRep(left) .. " in quests" .. SEP .. "reaches " .. word
    end
    return FmtRep(left) .. " in quests" .. SEP .. "stays " .. (word or "where it is")
end

-- The same in full, for the tooltip
local function ReachSentence(rep)
    local projection = rep and rep.projection
    if not projection then return nil end
    if (rep.value or 0) >= EXALTED then return "Exalted: nothing more to earn." end
    local left = projection.left or 0
    if left <= 0 then return "No once-only quest left that pays it." end
    if (projection.reach or 0) >= EXALTED then
        return FmtRep(left) .. " left in quests, and quests alone reach Exalted (in the best order)."
    end
    return FmtRep(left) .. " left in quests, which reach " .. (Progress(projection.reach) or Fmt(projection.reach))
        .. " in the best order."
end

local function CardTooltip(cat, owner)
    local S = cat.S
    local rep = StandingOf(cat)
    local engine = Engine()
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(S.keyName or "Reputations", 1, 1, 1)
    if rep and rep.progress then
        GameTooltip:AddLine(rep.progress .. (rep.met == false and "  (not met yet)" or ""), 0.85, 0.85, 0.85)
    end
    if S.view and engine then
        GameTooltip:AddLine(engine.TotalsText(S.view.totals) .. " of the once-only quests that pay it.", 0.85, 0.85, 0.85)
    end
    local reach = S.view and ReachSentence(S.view.rep)
    if reach then GameTooltip:AddLine(reach, 0.85, 0.85, 0.85, true) end
    local follow
    if DB().RepFollow == false then
        follow = "Pinned to this faction."
    elseif S.followedBy == "WATCHED" then
        follow = "Following the faction you watch (the game's reputation bar)."
    elseif S.followedBy == "LOG" then
        follow = "Following: you watch no faction this tab lists, so this is the one your log's quests pay most."
    else
        follow = "Following the faction you watch."
    end
    GameTooltip:AddLine(follow, 0.7, 0.7, 0.75, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to pick a faction, or to go back to this one's overview. Right-click to follow the faction you watch.",
        0.55, 0.55, 0.6, true)
    GameTooltip:Show()
end

local function PaintCard(cat, card)
    local kit = Kit()
    local S = cat.S
    local rep = S.key and StandingOf(cat) or nil
    card.name:SetText(S.keyName or "Reputations")
    card.name:SetTextColor(kit.InkAccent())
    -- The standing sits where the Zones tab keeps its count, and the name
    -- gives way to it (a standing is wider than a percentage)
    if not card._repAnchored then
        card._repAnchored = true
        card.name:ClearAllPoints()
        card.name:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -6)
        card.name:SetPoint("RIGHT", card.totals, "LEFT", -8, 0)
        if card.name.SetWordWrap then card.name:SetWordWrap(false) end
    end
    card.totals:SetText(rep and rep.progress or "")
    card.totals:SetTextColor(kit.Paper(kit.Ink("primary")))

    local span = (card:GetWidth() or 0) - 16
    if span <= 0 then span = kit.NAV_W - 16 end
    local fraction, rank = RankFraction(rep and rep.value)
    if rep and fraction and fraction > 0 then
        card.bar:SetWidth(math.max(1, span * fraction))
        local r, g, b = kit.Paper(StandingRGB(rank))
        card.bar:SetVertexColor(r, g, b, 0.9)
        card.bar:Show()
    else
        card.bar:Hide()
    end

    local note
    if not S.key then
        note = DB().RepFollow ~= false and "You watch no faction. Click to pick one." or "Click to pick a faction."
    elseif S.err == "INDEXING" then
        note = "Reading Questie's reputation rewards" .. ELLIPSIS
    elseif S.view then
        note = ReachWords(S.view.rep) or ""
    elseif rep and rep.met == false then
        note = "Not met yet"
    else
        note = ""
    end
    -- Following is the default and the tooltip says what; a pin is the news
    if S.key and DB().RepFollow == false then
        note = note .. (note ~= "" and SEP or "") .. "pinned"
    end
    card.note:SetText(note)
    card.note:SetTextColor(kit.Paper(kit.Ink("faint")))
end

-- ---------------------------------------------------------------------------
-- The overview: nothing selected
-- ---------------------------------------------------------------------------

-- A bar in the standing's colour: the catalogue's Bar, its fill re-tinted
-- (the fill is the last quad Bar took from the pool)
local function StandingBar(cat, value, gap)
    local kit = Kit()
    local fraction, rank = RankFraction(value)
    cat.Bar(0, STANDING_BAR_H, fraction or 0, gap)
    if fraction and fraction > 0 then
        local fill = cat.W.quads[cat.P.quad - 1]
        if fill then
            local r, g, b = kit.Paper(StandingRGB(rank))
            fill:SetVertexColor(r, g, b, 0.9)
        end
    end
end

local function TitleOfQuest(cat, questId)
    local view = cat.S.view
    local entry = view and view.byId and view.byId[questId]
    if entry and entry.title then return entry.title end
    local char = cat.S.char
    if type(char) == "table" and type(char.questName) == "function" then
        local ok, name = pcall(char.questName, questId)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return "Quest " .. tostring(questId)
end

-- An item's name: the adapter's (the client's cache, then Questie's), else
-- the client's now (it may have arrived since), else asked for and redrawn
-- when it comes (GET_ITEM_INFO_RECEIVED below)
local pendingItems = {}
local function ItemName(itemId, known)
    if type(known) == "string" and known ~= "" then return known end
    if GetItemInfo then
        local ok, name = pcall(GetItemInfo, itemId)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    pendingItems[itemId] = true
    return "item " .. tostring(itemId)
end

local function PaintStanding(cat, rep)
    local kit = Kit()
    local Line = cat.Line
    Line(rep.name or cat.S.keyName or "", "GameFontNormalLarge", kit.InkSet().title)
    Line((rep.progress or "") .. (rep.met == false and "  (not met yet)" or ""), "GameFontHighlight", InkT("primary"))
    StandingBar(cat, rep.value)
    local parts = {}
    if (rep.value or 0) >= EXALTED then
        parts[#parts + 1] = "Exalted: the top of the bar"
    else
        if rep.toNext and rep.rank then
            parts[#parts + 1] = Fmt(rep.toNext) .. " to " .. (RankWord(rep.rank + 1) or "the next standing")
        end
        if rep.toExalted and rep.rank and rep.rank < 6 then parts[#parts + 1] = Fmt(rep.toExalted) .. " to Exalted" end
    end
    if #parts > 0 then Line(table.concat(parts, SEP), "GameFontHighlightSmall", InkT("secondary")) end
    if rep.met == false then
        Line("Not met yet: every character of your race and class starts at " .. (WordFor(rep.base or rep.value) or "its base")
            .. " " .. Fmt(rep.base or rep.value) .. ".", "GameFontDisableSmall", InkT("faint"))
    end
    local mods = rep.mods
    if rep.pct and rep.pct ~= 100 then
        local why = {}
        if type(mods) == "table" and mods.human then why[#why + 1] = "Diplomacy" end
        if type(mods) == "table" and mods.wickerman then why[#why + 1] = "Invocation of the Wickerman" end
        Line("Every gain is paid at " .. rep.pct .. "%" .. (#why > 0 and (": " .. table.concat(why, " and ")) or "") .. ".",
            "GameFontDisableSmall", InkT("faint"))
    end
end

local function PaintQuests(cat, rep)
    local Line, Rule, Heading = cat.Line, cat.Rule, cat.Heading
    local totals, projection = rep.totals or {}, rep.projection or {}
    Rule()
    Heading("QUESTS")
    local leftCount, doneCount = totals.leftCount or 0, totals.doneCount or 0
    -- the once-only quests that reach it by a spill window are in the
    -- projection too (the Sha'tar's from the Aldor), so they are named
    local spilling = 0
    local view = cat.S.view
    for _, member in ipairs(rep.spill and rep.spill.members or {}) do
        local entry = view and view.byId and view.byId[member.questId]
        local fact = entry and entry.fact or {}
        if not GONE[member.base or ""] and not fact.repeatable and not fact.daily then spilling = spilling + 1 end
    end
    if leftCount > 0 or spilling > 0 then
        local what = Plural(leftCount, "quest") .. " left"
        if spilling > 0 then what = what .. ", and " .. spilling .. " more by spillover" end
        if AtCeiling(rep.value) then
            Line(what .. ", none pays anything more", "GameFontHighlightSmall", InkT("primary"), 4)
        else
            Line(string.format("%s: worth %s in the best order", what, Fmt(projection.left or 0)),
                "GameFontHighlightSmall", InkT("primary"), 4)
        end
    else
        Line("No once-only quest left that pays it.", "GameFontHighlightSmall", InkT("primary"), 4)
    end
    if doneCount > 0 then
        Line(string.format("%s done, worth about %s at today's rates (an estimate: your standing mixes quests, kills and items)",
            Plural(doneCount, "quest"), Fmt(totals.doneOnce or 0)), "GameFontHighlightSmall", InkT("secondary"), 4)
    end
    local reach = projection.reach
    if (rep.value or 0) >= EXALTED then
        Line("Already Exalted.", "GameFontHighlightSmall", InkT("secondary"), 4)
    elseif reach and reach >= EXALTED then
        Line("Quests alone reach Exalted.", "GameFontNormalSmall", C.ToneT("good"), 4)
    elseif reach and (projection.left or 0) > 0 then
        Line("Quests alone reach " .. (Progress(reach) or Fmt(reach)) .. ".", "GameFontNormalSmall", InkT("primary"), 4)
    end
    local repeatReach = projection.repeatReach
    if repeatReach and reach and repeatReach > reach and (rep.value or 0) < EXALTED then
        Line("Repeatables can carry it on to " .. (repeatReach >= EXALTED and "Exalted" or (Progress(repeatReach) or Fmt(repeatReach))) .. ".",
            "GameFontHighlightSmall", InkT("secondary"), 4)
    end
    if #(projection.lockedOut or {}) > 0 then
        Line(Plural(#projection.lockedOut, "quest is", "quests are") .. " offered only below where you stand now.",
            "GameFontHighlightSmall", InkT("faint"), 4)
    end
    if #(projection.unreached or {}) > 0 then
        Line(Plural(#projection.unreached, "more waits", "more wait") .. " on a standing quests alone do not reach.",
            "GameFontHighlightSmall", InkT("faint"), 4)
    end
end

local function PaintOrder(cat, rep)
    local hints = rep.projection and rep.projection.hints or {}
    if #hints == 0 then return end
    cat.Rule()
    cat.Heading("WILL LOCK SOON")
    for _, hint in ipairs(hints) do
        cat.Line(hint.text, "GameFontHighlightSmall", C.ToneT("warn"), 4)
    end
    cat.Line("Each is offered only below that standing: the climb shuts it, so it comes first.",
        "GameFontDisableSmall", InkT("faint"), 4)
end

-- "3 turn-ins to Friendly  ·  offered only below Friendly  ·  Oshu'gun
-- Crystal Fragment x10 a turn-in (30 to Friendly)" -- an item's name is
-- never pluralised by hand ("Pair of Ivory Tusks"), so the count follows it
local function RepeatableDetail(info)
    local parts = {}
    if info.open then
        -- where its turn-ins stop: a gate (offered only below), the quest's
        -- own reward clamp, or nothing short of the ceiling
        local stops, untilWords
        if (info.cap or EXALTED) < EXALTED then
            if info.gateMax and info.cap >= info.gateMax then
                stops = "offered only below " .. GateWords(info.gateMax)
                untilWords = " while it is " .. stops
            elseif info.rewardCap and info.cap >= info.rewardCap then
                stops = "pays nothing past " .. CapWords(info.cap)
                untilWords = ", then it " .. stops
            else
                stops = "stops at " .. CapWords(info.cap)
                untilWords = ", then it " .. stops
            end
        end
        if info.toNext and info.nextRank then
            parts[#parts + 1] = Plural(info.toNext, "turn-in") .. " to " .. (RankWord(info.nextRank) or "the next standing")
            if info.toExalted and info.toExalted > info.toNext then parts[#parts + 1] = info.toExalted .. " to Exalted" end
            if stops then parts[#parts + 1] = stops end
        elseif info.toExalted and info.toExalted > 0 then
            parts[#parts + 1] = Plural(info.toExalted, "turn-in") .. " to Exalted"
        elseif info.toCap and info.toCap > 0 then
            parts[#parts + 1] = Plural(info.toCap, "turn-in") .. (untilWords or "")
        end
    elseif info.capped then
        parts[#parts + 1] = "pays nothing more at your standing"
    elseif info.gateMax and info.cap and info.cap >= info.gateMax then
        parts[#parts + 1] = "closed: offered only below " .. GateWords(info.gateMax)
    elseif info.gateMin then
        parts[#parts + 1] = "opens at " .. (WordFor(info.gateMin) or Fmt(info.gateMin))
    end
    for index, cost in ipairs(info.costs or {}) do
        local name = ItemName(cost[1], cost.name)
        local text = name .. " x" .. tostring(cost[2]) .. " a turn-in"
        if index == 1 and info.costToNext and info.nextRank then
            text = text .. " (" .. Fmt(info.costToNext) .. " to " .. (RankWord(info.nextRank) or "the next") .. ")"
        end
        parts[#parts + 1] = text
    end
    return table.concat(parts, SEP)
end

local function PaintRepeatables(cat, rep)
    local list = {}
    for _, info in ipairs(rep.repeatables or {}) do
        if not GONE[info.base or ""] then list[#list + 1] = info end
    end
    if #list == 0 then return end
    table.sort(list, function(a, b)
        if (a.open and true or false) ~= (b.open and true or false) then return a.open and true or false end
        if (a.perTurnIn or 0) ~= (b.perTurnIn or 0) then return (a.perTurnIn or 0) > (b.perTurnIn or 0) end
        return (a.questId or 0) < (b.questId or 0)
    end)
    cat.Rule()
    cat.Heading("REPEATABLE SOURCES")
    for index, info in ipairs(list) do
        if index > MAX_LISTED then
            cat.Line("and " .. (#list - MAX_LISTED) .. " more under Repeatable sources", "GameFontDisableSmall", InkT("faint"), 4)
            break
        end
        local gain = info.open and (info.nextGain or info.perTurnIn) or info.perTurnIn
        cat.Line((info.name or ("Quest " .. tostring(info.questId))) .. "  " .. FmtRep(gain or 0) .. " a turn-in",
            "GameFontHighlightSmall", InkT(info.open and "primary" or "faint"), 4)
        local detail = RepeatableDetail(info)
        if detail ~= "" then cat.Line(detail, "GameFontHighlightSmall", InkT("secondary"), 12) end
    end
end

-- A Wanted pool whose pick today is not known, in words that never promise
-- it every day: pool.candidates is how many of the rotation pay THIS faction
-- (Honor Hold's normal one is 1 of 7), not the rotation's size. With the
-- rotation's size (pool.poolSize, when the engine hands it) the odds are
-- named; without it, only that it pays on a day it is the one offered --
-- true of Honor Hold's one in seven and of the Consortium's seven in seven.
local function UnknownPoolWords(pool)
    local mine, size = tonumber(pool.candidates) or 0, tonumber(pool.poolSize)
    -- none of them pays anything from here (a reward clamp): whichever is
    -- offered, never "up to 0"
    if (tonumber(pool.best) or 0) <= 0 then
        return mine == 1 and ": pays nothing more at your standing"
            or ": none in the rotation pays anything more at your standing"
    end
    local best = FmtRep(pool.best or 0)
    if size and size > 0 and mine >= size then
        return string.format(": every one in rotation pays it, so one a day, up to %s; today's not known yet", best)
    elseif size and size > 0 then
        return string.format(": %d of the %d in rotation %s it (one is offered a day), up to %s; today's not known yet",
            mine, size, mine == 1 and "pays" or "pay", best)
    end
    if mine == 1 then
        return string.format(": 1 in the rotation pays it, %s on a day it is offered; today's not known yet", best)
    end
    return string.format(": %d in the rotation pay it, up to %s on a day one of them is offered; today's not known yet",
        mine, best)
end

local function PaintDailies(cat, rep)
    local quests = rep.dailyQuests or {}
    local income = rep.dailies
    if #quests == 0 or type(income) ~= "table" then return end
    local Line = cat.Line
    cat.Rule()
    cat.Heading("DAILIES")
    -- At the ceiling the engine holds the day to 0 (R.DailyIncome): every
    -- daily is open and pays nothing, so one line, never "None you can do
    -- today", a Wanted pick blamed, or a list of zeros
    if AtCeiling(rep.value) then
        Line((Progress(rep.value) or "Exalted") .. ": dailies pay nothing more.", "GameFontHighlightSmall",
            InkT("primary"), 4)
        return
    end
    -- A rotation whose pick is not known yet is not "none today": the
    -- Consortium has a normal and a heroic Wanted every day (one that pays
    -- nothing from here whichever is offered is no reason to wait)
    local unknownPick = false
    for _, kind in ipairs(POOL_ORDER) do
        local pool = income.rotating and income.rotating[kind]
        if pool and not pool.today and not pool.elsewhere and (tonumber(pool.best) or 0) > 0 then unknownPick = true end
    end
    if (income.perDay or 0) > 0 then
        Line(string.format("%s a day from %s (the game allows %d dailies a day)", FmtRep(income.perDay),
            Plural(income.count or 0, "daily", "dailies"), income.max or 25), "GameFontHighlightSmall", InkT("primary"), 4)
    elseif unknownPick then
        Line("Nothing to count on yet: today's Wanted dailies are not known.", "GameFontHighlightSmall", InkT("primary"), 4)
    elseif (income.count or 0) > 0 then
        -- open, but held to nothing by their reward clamps
        Line("None of today's pays anything more at your standing.", "GameFontHighlightSmall", InkT("primary"), 4)
    else
        Line("None you can do today.", "GameFontHighlightSmall", InkT("primary"), 4)
    end
    for _, daily in ipairs(income.steady or {}) do
        Line(TitleOfQuest(cat, daily.questId) .. "  " .. FmtRep(daily.gain), "GameFontHighlightSmall", InkT("secondary"), 12)
    end
    for _, kind in ipairs(POOL_ORDER) do
        local pool = income.rotating and income.rotating[kind]
        if pool then
            local text = POOL_WORDS[kind] or kind
            if pool.today then
                text = text .. ": today's is " .. TitleOfQuest(cat, pool.today) .. ", " .. FmtRep(pool.gain or 0)
            elseif pool.elsewhere then
                text = text .. ": today's pays another faction"
            else
                text = text .. UnknownPoolWords(pool)
            end
            Line(text, "GameFontHighlightSmall", InkT("secondary"), 12)
        end
    end
    -- the dailies behind a standing (or a level, or a chain): what each will
    -- pay and when it opens
    local view = cat.S.view
    local listed = 0
    for _, daily in ipairs(quests) do
        local entry = view and view.byId and view.byId[daily.questId]
        if entry and entry.base == "LOCKED" and not entry.rival and not daily.rotating then
            listed = listed + 1
            if listed > MAX_LISTED then break end
            local _, gateMin = GatesOf(entry, rep.factionId)
            local opens = gateMin and ("from " .. (WordFor(gateMin) or Fmt(gateMin))) or "not open to you yet"
            Line(entry.title .. "  " .. FmtRep(DeltaOf(entry)) .. ", " .. opens, "GameFontHighlightSmall", InkT("faint"), 12)
        end
    end
    for _, item in ipairs(income.conditional or {}) do
        Line(TitleOfQuest(cat, item.questId) .. "  " .. FmtRep(item.gain) .. ", "
            .. (CONDITION_WORDS[item.condition] or ("only when " .. tostring(item.condition))),
            "GameFontHighlightSmall", InkT("secondary"), 12)
    end
end

local function PaintSpill(cat, rep)
    local spill = rep.spill or {}
    local projection = rep.projection or {}
    local lines = {}
    local name = rep.name or cat.S.keyName or "this faction"
    local D = Data()
    local shut, shutRank = {}, nil
    for _, window in ipairs(spill.windows or {}) do
        local members, left, repeats, worth = 0, 0, 0, 0
        for _, member in ipairs(spill.members or {}) do
            if member.source == window.source then
                members = members + 1
                if not GONE[member.base or ""] then
                    local entry = cat.S.view and cat.S.view.byId and cat.S.view.byId[member.questId]
                    local fact = entry and entry.fact or {}
                    if fact.repeatable or fact.daily then repeats = repeats + 1 else left = left + 1 end
                    worth = worth + (member.delta or 0)
                end
            end
        end
        -- A heading's window (Shattrath City into the Sha'tar) has no quests
        -- of its own to speak of
        local heading = D and type(D.factions[window.source]) == "table" and D.factions[window.source].header
        if not window.open then
            if not heading then
                shut[#shut + 1] = ShortName(NameOf(window.source))
                shutRank = window.maxRankIn
            end
        elseif left + repeats > 0 then
            local head = string.format("From %s quests: %s of each, while %s is %s or below", Possessive(NameOf(window.source)),
                RateWord(window.rate), InSentence(name), RankWord(window.maxRankIn) or "low enough")
            local todo = Plural(left, "quest")
            if repeats > 0 then todo = todo .. " and " .. Plural(repeats, "repeatable") end
            local tail
            if left > 0 and projection.spillWindow and projection.spillSource == window.source then
                tail = string.format("%s still to do; in the best order about %s lands from the quests before it stops at %s.",
                    todo, FmtRep(projection.spillWindow.landed or 0), Fmt(window.top or 0))
            else
                tail = string.format("%s still to do; it stops at %s.", todo, Fmt(window.top or 0))
            end
            lines[#lines + 1] = { head, tail }
        end
    end
    if #shut > 0 then
        lines[#lines + 1] = {
            "Spillover from the " .. table.concat(shut, " and the ") .. " has stopped",
            name .. " is past " .. (RankWord(shutRank) or "the window") .. ", where that spillover ends.",
        }
    end
    -- the quarter (capitals) and the half (goblin towns): one line per rate
    local byRate, rates = {}, {}
    for _, share in ipairs(spill.shares or {}) do
        local key = tostring(share.rate)
        if not byRate[key] then
            byRate[key] = { rate = share.rate, quests = 0, total = 0, names = {} }
            rates[#rates + 1] = key
        end
        local group = byRate[key]
        group.quests = group.quests + (share.quests or 0)
        group.total = group.total + (share.total or 0)
        group.names[#group.names + 1] = NameOf(share.source)
    end
    table.sort(rates)
    for _, key in ipairs(rates) do
        local group = byRate[key]
        local names = group.names
        for index, other in ipairs(names) do names[index] = InSentence(other) end
        local who
        if #names == 1 then
            who = Possessive(names[1]) .. " quests"
        elseif #names <= 3 then
            who = "the quests of " .. table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
        else
            who = "the quests of " .. names[1] .. ", " .. names[2] .. " and " .. (#names - 2) .. " more"
        end
        lines[#lines + 1] = {
            string.format("From %s: %s of each", who, RateWord(group.rate)),
            string.format("%s from %s not done yet, with no cap.", FmtRep(group.total), Plural(group.quests, "quest")),
        }
    end
    if #lines == 0 then return end
    cat.Rule()
    cat.Heading("VIA SPILLOVER")
    for _, line in ipairs(lines) do
        cat.Line(line[1], "GameFontHighlightSmall", InkT("primary"), 4)
        cat.Line(line[2], "GameFontHighlightSmall", InkT("secondary"), 12)
    end
end

local function PaintCosts(cat, rep)
    local costs = rep.costs or {}
    if #costs == 0 then return end
    local open, done, gone = {}, 0, 0
    local char = cat.S.char
    local isGone = type(char) == "table" and type(char.isGone) == "function" and char.isGone or nil
    for _, cost in ipairs(costs) do
        if cost.done then
            done = done + 1
        elseif isGone and isGone(cost.questId) then
            gone = gone + 1
        else
            open[#open + 1] = cost
        end
    end
    table.sort(open, function(a, b)
        if (a.delta or 0) ~= (b.delta or 0) then return (a.delta or 0) < (b.delta or 0) end
        return (a.questId or 0) < (b.questId or 0)
    end)
    cat.Rule()
    cat.Heading("COSTS")
    local aside = {}
    if done > 0 then aside[#aside + 1] = done .. " done" end
    if gone > 0 then aside[#aside + 1] = gone .. " no longer open to you" end
    cat.Line(string.format("%s lower %s%s", Plural(#costs, "quest"), InSentence(rep.name or "it"),
        #aside > 0 and (" (" .. table.concat(aside, ", ") .. ")") or ""), "GameFontHighlightSmall", InkT("primary"), 4)
    for index, cost in ipairs(open) do
        if index > MAX_LISTED then
            cat.Line("and " .. (#open - MAX_LISTED) .. " more", "GameFontDisableSmall", InkT("faint"), 12)
            break
        end
        local pays = cost.source ~= rep.factionId and (" (pays " .. InSentence(NameOf(cost.source)) .. ")") or ""
        cat.Line(FmtRep(cost.delta or 0) .. "  " .. TitleOfQuest(cat, cost.questId) .. pays,
            "GameFontHighlightSmall", C.ToneT("bad"), 12)
    end
end

local function PaintPhaseAndCalibration(cat, rep)
    if (rep.phaseHidden or 0) > 0 then
        cat.Rule()
        cat.Heading("NOT IN THIS PHASE")
        cat.Line(Plural(rep.phaseHidden, "quest", "quests") .. " that would pay " .. InSentence(rep.name or "it")
            .. (rep.phaseKnown == false and " Questie holds back for now." or " come with a later content phase; Questie lists them then."),
            "GameFontHighlightSmall", InkT("secondary"), 4)
    end
    cat.Rule()
    cat.Heading("CALIBRATION")
    if (rep.observed or 0) > 0 then
        cat.Line("Seen in game on " .. Plural(rep.observed, "quest") .. ": those numbers are what the game paid you, not the quest data.",
            "GameFontHighlightSmall", InkT("secondary"), 4)
    else
        cat.Line("None of these seen in game yet: the numbers are the quest data's, through the rules. A turn-in replaces its quest's with what the game paid.",
            "GameFontHighlightSmall", InkT("faint"), 4)
    end
end

local function PaintOverview(cat, view)
    local rep = view.rep
    if type(rep) ~= "table" then
        cat.Line(view.name or cat.S.keyName or "", "GameFontNormalLarge", Kit().InkSet().title)
        return
    end
    PaintStanding(cat, rep)
    PaintQuests(cat, rep)
    PaintOrder(cat, rep)
    PaintRepeatables(cat, rep)
    PaintDailies(cat, rep)
    PaintSpill(cat, rep)
    PaintCosts(cat, rep)
    PaintPhaseAndCalibration(cat, rep)
end

-- ---------------------------------------------------------------------------
-- The quest briefing: every effect, then the quest as a source
-- ---------------------------------------------------------------------------

-- The REPUTATION section is the Zones tab's own painter (Z.PaintReputation):
-- the same quest reads the same, in the same words, on both tabs. This
-- faction's line is in the strong ink, and the section is drawn whatever
-- Reputation on Every Quest says (reputation is this tab's whole point).
local function Reputation(cat, entry, detail)
    local zones = Q.Zones
    if zones and type(zones.PaintReputation) == "function" then
        return zones.PaintReputation(cat, entry, detail, { emphasis = cat.S.key, always = true })
    end
    -- (no Zones tab: it loads before this one from the same catalogue, so
    -- this is a broken install, and the section says only what is known)
    cat.Rule()
    cat.Heading("REPUTATION")
    local adapter = Adapter()
    local line = adapter and adapter.RepLine and adapter.RepLine(entry.id) or nil
    cat.Line(line or "Not known: the reputation rules are not loaded.", "GameFontHighlightSmall", InkT("faint"), 4)
end

local function BriefingSections(cat, entry)
    local factionId = cat.S.key
    local rep = cat.S.view and cat.S.view.rep
    local fact = entry.fact or {}
    if fact.repeatable and not fact.daily then
        local info = RepeatableInfo(cat, entry.id)
        if info then
            cat.Rule()
            cat.Heading("AS A SOURCE")
            cat.Line(FmtRep((info.open and info.nextGain) or info.perTurnIn or 0) .. " a turn-in to "
                .. InSentence(rep and rep.name or cat.S.keyName or "this faction"), "GameFontHighlightSmall", InkT("primary"), 4)
            local detail = RepeatableDetail(info)
            if detail ~= "" then cat.Line(detail, "GameFontHighlightSmall", InkT("secondary"), 4) end
        end
        return
    end
    local gateMax = GatesOf(entry, factionId)
    if gateMax and WillLock(entry, factionId, rep and rep.value) then
        cat.Rule()
        cat.Heading("WILL LOCK SOON")
        cat.Line("Do it before " .. GateWords(gateMax) .. ": it is offered only below " .. Fmt(gateMax) .. ".",
            "GameFontHighlightSmall", C.ToneT("warn"), 4)
    end
end

-- ---------------------------------------------------------------------------
-- The navigator's sentence when there is nothing to list
-- ---------------------------------------------------------------------------

local function EmptyMessage(cat)
    local S = cat.S
    local name = S.keyName or "this faction"
    if not S.key then
        if DB().RepFollow ~= false then
            return "You watch no faction this tab lists, and nothing in your log pays one. Pick a faction from the card above, or tick \"Show as experience bar\" for one in the game's Reputation pane."
        end
        if S.pinnedOther then
            return NameOf(S.pinnedOther) .. ", pinned on another character, is the other side's faction. Pick one from the card above."
        end
        return "Pick a faction from the card above."
    end
    local err = S.err
    if err == "INDEXING" then return "Reading Questie's reputation rewards" .. ELLIPSIS end
    if err == "OTHER_SIDE" then return name .. " is the other side's faction: its quests are theirs." end
    if err == "NO_RULES" then
        return "The reputation rules are not loaded, so there is nothing to work out. /cql status has the detail."
    end
    if err == "NO_FACTION" then return "Faction " .. tostring(S.key) .. " is not one this tab knows. Pick another from the card above." end
    if err == "NO_QUESTS" then
        return "Questie lists no quest that pays " .. name .. " for this character. Pick another faction from the card above."
    end
    if not S.view then
        return "This faction could not be read (" .. tostring(err or "no answer") .. "). /cql status has the detail."
    end
    -- Nothing in the view at all is not the search's doing: every quest held
    -- back by a later content phase (the Shattered Sun before its phase), or
    -- none this character can take
    if #(S.view.entries or {}) == 0 then
        local hidden = S.view.rep and tonumber(S.view.rep.phaseHidden) or 0
        if hidden > 0 then
            return "Every quest that pays " .. InSentence(name) .. " comes with a later content phase ("
                .. Plural(hidden, "quest") .. "); Questie lists them then."
        end
        return "No quest that pays " .. InSentence(name) .. " is listed for this character."
    end
    return "Nothing that pays " .. name .. " matches this search and filter."
end

-- ---------------------------------------------------------------------------
-- The spec
-- ---------------------------------------------------------------------------

local function StartArea(_, entry)
    if not entry then return nil end
    for _, record in ipairs(entry.starters or {}) do
        if record.zone then return record.zone end
    end
    for _, record in ipairs(entry.finishers or {}) do
        if record.zone then return record.zone end
    end
    local zone = entry.fact and tonumber(entry.fact.zoneOrSort)
    if zone and zone > 0 then return zone end
    return nil
end

local REP_SPEC = {
    id = "REP", label = "Reputations", title = "Reputations",
    order = 30, width = TAB_W,
    tooltip = "Every quest that pays a faction, read from Questie and worked out for this character: what each is worth now, what is left, how far quests alone take you, and the repeatables and dailies after that.",
    prefix = "Rep", showKey = "ShowRepTab",
    offMessage = "Commander Quest Log: the Reputations tab is switched off (settings, Reputation).",
    searchTip = "Matches a quest's name, among the quests that pay the faction on the card.",
    countTip = "How many of this faction's quests the search and the filter leave on the list. The card's standing and the overview count every quest, whatever is shown.",
    -- A new watched faction comes with UPDATE_FACTION (the adapter steps its
    -- generation on it too; the window draws once a frame either way)
    followEvents = { "UPDATE_FACTION" },

    Resolve = ResolveFaction,
    View = function(_, factionId)
        local adapter = Adapter()
        if not (adapter and adapter.FactionView) then return nil, "NO_RULES" end
        return adapter.FactionView(factionId)
    end,
    KeyName = function(_, factionId, current) return NameOf(factionId) or current end,
    -- No nearest-first: a faction's quests are spread over a dozen zones
    MapArea = StartArea,
    -- Never a faction id where an area id is expected: the detail is read
    -- from the faction cache by kind
    QuestDetail = function(cat, entry)
        local adapter = Adapter()
        if not (adapter and adapter.QuestDetail) then return nil end
        return adapter.QuestDetail(entry.id, cat.S.key, "FACTION")
    end,

    groups = GROUPS, groupLabels = GROUP_LABELS,
    Group = GroupFaction,
    filterSpecs = FILTER_SPECS,

    MenuInit = MenuInit,
    CardTooltip = CardTooltip,
    PaintCard = PaintCard,
    PaintOverview = PaintOverview,
    Facts = Facts,
    -- What the quest pays, and the quest as a source (or its closing door),
    -- straight under its reason: a 22-quest chain must not push them out of
    -- the pane on the tab that is about reputation
    Reputation = Reputation,
    BriefingSections = BriefingSections,
    reputationFirst = true,
    -- The faction view holds only the quests that pay it, so its chains
    -- break at a step that pays nothing: the count says what it counts, or
    -- "18 of 22" here would read as the Zones tab's "22 of 31" for the same
    -- quest (2026-10-05 review)
    chainLabel = function(cat)
        local name = cat.S.keyName
        if type(name) ~= "string" or name == "" then return nil end
        return "CHAIN (quests that pay " .. InSentence(name) .. ")"
    end,
    StateWord = StateWord,
    Reason = Reason,
    RowRight = RowRight,
    RowTooltip = RowTooltip,
    EmptyMessage = EmptyMessage,

    -- Waypoint, Show on Map (the zone the quest starts in), Open in Log,
    -- Watch Faction, and the Ignore / Count toggle at the right
    actions = {
        "WAYPOINT",
        {
            stock = "MAP",
            tooltip = "Open the world map on the zone the selected quest starts in, with its givers marked. Not from here in combat.",
        },
        "LOG",
        {
            -- A faction action, not a quest one: live with nothing selected
            field = "watchBtn", label = "Watch Faction", width = 104,
            tooltip = function(cat)
                local name = cat.S.keyName or "this faction"
                local text = "Show " .. name .. " on the game's reputation bar, as \"Show as experience bar\" does in the Reputation pane. While this tab follows, it then follows that faction."
                if cat.S.key and WatchedFaction() == cat.S.key then return text .. " It is the one you watch now." end
                if cat.S.key and not IsMet(cat.S.key) then return text .. " You have not met it yet." end
                return text .. " A faction under a folded heading there is not unfolded: unfold it first."
            end,
            onClick = WatchFaction,
            Update = function(cat, button)
                local key = cat.S.key
                button:SetEnabled(key ~= nil and IsMet(key) and SetWatchedFactionIndex ~= nil and WatchedFaction() ~= key)
            end,
        },
        {
            stock = "IGNORE",
            tooltip = function(cat)
                local entry = cat.S.selectedEntry
                if entry and C.IsIgnored(entry.id) then
                    return "Count this quest again, here and on the Zones tab."
                end
                return "Leave this quest out of the counts for this character, here and on the Zones tab, for a quest you will never do. It stays on the list, under Ignored, and Count puts it back."
            end,
        },
    },
}

local Reps = C.New(REP_SPEC)
Q.Reps = Reps

-- ---------------------------------------------------------------------------
-- From outside: /cql rep [name]
-- ---------------------------------------------------------------------------

-- "The Sha'tar" -> "shatar": what a typed name is compared on
local function Fold(text)
    text = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    text = text:gsub("^the%s+", "")
    return (text:gsub("[%s%p]", ""))
end

-- A faction for a typed name or id: exact, then the start of a name, then
-- anywhere in one; the picker's factions (this side, client names) before
-- the data's English names. Returns factionId, name or nil.
function Reps.FindFaction(text)
    local number = tonumber(text)
    local side = PlayerSide(nil)
    if number then
        if Listable(number, side) then return number, NameOf(number) end
        return nil
    end
    local wanted = Fold(text)
    if wanted == "" then return nil end
    local candidates, seen = {}, {}
    local adapter = Adapter()
    local menu = adapter and adapter.FactionMenu and adapter.FactionMenu() or {}
    for _, group in ipairs(menu) do
        for _, item in ipairs(group.items or {}) do
            if not seen[item.factionId] then
                seen[item.factionId] = true
                candidates[#candidates + 1] = { id = item.factionId, names = { item.name } }
            end
        end
    end
    local D = Data()
    local ids = {}
    for id in pairs(D and D.factions or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        if Listable(id, side) then
            local row = D.factions[id]
            if seen[id] then
                for _, candidate in ipairs(candidates) do
                    if candidate.id == id then candidate.names[#candidate.names + 1] = row.name end
                end
            else
                seen[id] = true
                candidates[#candidates + 1] = { id = id, names = { NameOf(id), row.name } }
            end
        end
    end
    for pass = 1, 3 do
        for _, candidate in ipairs(candidates) do
            for _, name in ipairs(candidate.names) do
                local folded = Fold(name)
                local hit = (pass == 1 and folded == wanted) or (pass == 2 and folded:sub(1, #wanted) == wanted)
                    or (pass == 3 and folded:find(wanted, 1, true) ~= nil)
                if hit then return candidate.id, NameOf(candidate.id) end
            end
        end
    end
    return nil
end

-- The tab on a faction by name or id; nothing follows the watched faction
function Reps.OpenTo(text)
    if not Q.OpenToTab then return end
    if text == nil or tostring(text):match("^%s*$") then
        Q.OpenToTab("REP", nil)
        return
    end
    local factionId = Reps.FindFaction(text)
    if not factionId then
        print("Commander Quest Log: no faction called \"" .. tostring(text) .. "\". The Reputations tab's card lists them.")
        return
    end
    Q.OpenToTab("REP", factionId)
end

-- ---------------------------------------------------------------------------
-- An item cost whose name the client did not have yet: redrawn when it comes
-- ---------------------------------------------------------------------------

if CreateFrame then
    local events = CreateFrame("Frame")
    events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    events:SetScript("OnEvent", function(_, _, itemId)
        itemId = tonumber(itemId)
        if not (itemId and pendingItems[itemId]) then return end
        pendingItems[itemId] = nil
        if Reps.IsActive() and Q.QueueRefresh then Q.QueueRefresh() end
    end)
end

-- Harness accessors. Nothing in the game reads these.
Reps._Labels = function() labels = nil end
Reps._WatchedFaction = WatchedFaction
Reps._PaneIndex = PaneIndex
