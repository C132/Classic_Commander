-- Commander Quest Log: the model.
--
-- Everything this module knows about the quest log is read here and nowhere
-- else, so the window draws a table rather than calling the API from inside a
-- layout pass. That split is not cosmetic: reading a quest's detail requires
-- SelectQuestLogEntry, which moves a GLOBAL selection the stock quest log and
-- every other addon reads. A model pass takes that selection, reads what it
-- needs and puts it back; a layout pass that called the API ad hoc would leave
-- the selection wherever the last drawn row happened to land.
--
-- Two more traps this file exists to contain:
--
--   * Collapsed headers REMOVE their quests from the index space. Indices are
--     therefore only stable while everything is expanded, so the scan expands
--     first (once, and only when something is actually collapsed -- calling
--     ExpandQuestHeader unconditionally fires QUEST_LOG_UPDATE, which is what
--     drove the scan, which is a loop). Collapsing in the window is our own
--     display state and never touches the client's.
--   * GetQuestLogTitle's index is a LOG index, not a quest id, and it is
--     invalidated by any quest being accepted or turned in. Nothing here holds
--     an index across an event; the selected quest is remembered by questID
--     (or by title on a client that answers 0) and re-found on every scan.

CommanderQuestLog = CommanderQuestLog or {}
local Q = CommanderQuestLog

-- The client's own cap. Only used for the "how full is the log" readout, and
-- read from the global when the client publishes one.
Q.MAX_QUESTS = MAX_QUESTS or 25

-- ---------------------------------------------------------------------------
-- Difficulty
--
-- GetQuestDifficultyColor is FrameXML's, not the API's, so it is treated as
-- optional and the delta table below is the real answer. The thresholds are
-- the era's: +5 red, +3 orange, -0 yellow, then green down to the grey line,
-- which itself moves with the player's level.
-- ---------------------------------------------------------------------------

local function GreyLevel(playerLevel)
    if playerLevel <= 5 then return 0 end
    if playerLevel <= 39 then return playerLevel - math.floor(playerLevel / 10) - 5 end
    if playerLevel <= 59 then return playerLevel - math.floor(playerLevel / 5) - 1 end
    return playerLevel - 9
end

function Q.DifficultyColor(questLevel, playerLevel)
    playerLevel = playerLevel or (UnitLevel and UnitLevel("player")) or 70
    questLevel = questLevel or playerLevel
    local delta = questLevel - playerLevel
    if delta >= 5 then return 1, 0.1, 0.1 end
    if delta >= 3 then return 1, 0.5, 0.25 end
    if delta >= -2 then return 1, 1, 0 end
    if questLevel > GreyLevel(playerLevel) then return 0.25, 0.75, 0.25 end
    return 0.6, 0.6, 0.6
end

-- ---------------------------------------------------------------------------
-- Scanning
-- ---------------------------------------------------------------------------

-- True while our own ExpandQuestHeader is in flight, so the QUEST_LOG_UPDATE
-- it provokes does not re-enter the scan
local expanding = false

function Q.IsExpanding() return expanding end

local function ExpandAll()
    if not (GetNumQuestLogEntries and ExpandQuestHeader) then return end
    local numEntries = GetNumQuestLogEntries()
    for index = 1, numEntries do
        local _, _, _, isHeader, isCollapsed = GetQuestLogTitle(index)
        if isHeader and isCollapsed then
            expanding = true
            ExpandQuestHeader(0)
            expanding = false
            return
        end
    end
end

-- A quest's stable identity. questID is right when the client answers one;
-- some entries answer 0 (and the era's own tracker has the same problem), so
-- the title is the fallback key rather than the log index, which moves.
function Q.KeyFor(entry)
    if not entry then return nil end
    if entry.questID and entry.questID > 0 then return "id:" .. entry.questID end
    return "t:" .. (entry.title or "?")
end

-- Reads the whole log into a flat list of header and quest entries, in log
-- order. Returns entries, numQuests.
function Q.Scan()
    local entries, numQuests = {}, 0
    if not (GetNumQuestLogEntries and GetQuestLogTitle) then
        return entries, 0
    end

    ExpandAll()

    local restore = GetQuestLogSelection and GetQuestLogSelection() or nil
    local total, quests = GetNumQuestLogEntries()
    local header = nil

    for index = 1, (total or 0) do
        local title, level, suggestedGroup, isHeader, _, isComplete, frequency, questID = GetQuestLogTitle(index)
        if not title then break end
        if isHeader then
            header = {
                isHeader = true,
                title = title,
                index = index,
                quests = 0,
                complete = 0,
            }
            entries[#entries + 1] = header
        else
            numQuests = numQuests + 1
            local entry = {
                isHeader = false,
                index = index,
                title = title,
                level = level,
                questID = questID,
                -- The era overloads this: 1 is complete, -1 is failed, nil is
                -- neither. A plain truth test calls a failed quest done.
                isComplete = (isComplete == 1) or (isComplete == true),
                isFailed = (isComplete == -1),
                daily = (frequency == 2),
                -- Vanilla answered a tag string here; the Burning Crusade
                -- client answers a suggested party size. Both are carried
                -- rather than one being assumed.
                tag = (type(suggestedGroup) == "string" and suggestedGroup ~= "" ) and suggestedGroup or nil,
                group = (type(suggestedGroup) == "number" and suggestedGroup > 0) and suggestedGroup or nil,
                header = header and header.title or nil,
                objectives = {},
            }
            entry.key = Q.KeyFor(entry)

            local numObjectives = (GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(index)) or 0
            local done = 0
            for objective = 1, numObjectives do
                local text, objectiveType, finished = GetQuestLogLeaderBoard(objective, index)
                if text then
                    local have, need = text:match("(%d+)%s*/%s*(%d+)")
                    local row = {
                        text = text,
                        objectiveType = objectiveType,
                        finished = finished and true or false,
                        have = have and tonumber(have) or nil,
                        need = need and tonumber(need) or nil,
                    }
                    if row.finished then done = done + 1 end
                    entry.objectives[#entry.objectives + 1] = row
                end
            end
            entry.numObjectives = #entry.objectives
            entry.numFinished = done
            -- An "event" objective reads as unfinished even on a quest the
            -- server calls complete, so the quest's own word wins over the
            -- objective tally, never the other way round.
            if entry.isComplete then entry.numFinished = entry.numObjectives end

            entry.watched = (IsQuestWatched and IsQuestWatched(index)) and true or false

            if header then
                header.quests = header.quests + 1
                if entry.isComplete then header.complete = header.complete + 1 end
            end
            entries[#entries + 1] = entry
        end
    end

    if restore and restore > 0 and SelectQuestLogEntry then
        SelectQuestLogEntry(restore)
    end

    return entries, (quests or numQuests)
end

-- ---------------------------------------------------------------------------
-- Detail
--
-- Selects the entry, reads everything the briefing pane draws, and puts the
-- selection back. Every reward getter is guarded: this client ships some of
-- them and not others, and a missing one must cost a section, not the pane.
-- ---------------------------------------------------------------------------

function Q.ReadDetail(index)
    if not (index and SelectQuestLogEntry and GetQuestLogQuestText) then return nil end
    local restore = GetQuestLogSelection and GetQuestLogSelection() or nil

    SelectQuestLogEntry(index)

    local detail = { index = index }
    detail.description, detail.objectivesText = GetQuestLogQuestText()

    if GetQuestLogTimeLeft then
        local left = GetQuestLogTimeLeft()
        if left and left > 0 then detail.timeLeft = left end
    end

    detail.pushable = (GetQuestLogPushable and GetQuestLogPushable()) and true or false

    detail.money = (GetQuestLogRewardMoney and GetQuestLogRewardMoney()) or 0
    detail.requiredMoney = (GetQuestLogRequiredMoney and GetQuestLogRequiredMoney()) or 0

    detail.choices, detail.rewards = {}, {}
    local numChoices = (GetNumQuestLogChoices and GetNumQuestLogChoices()) or 0
    for slot = 1, numChoices do
        local name, texture, numItems, quality, isUsable = GetQuestLogChoiceInfo(slot)
        if name then
            detail.choices[#detail.choices + 1] = {
                kind = "choice", slot = slot, name = name, texture = texture,
                count = numItems or 1, quality = quality or 1, usable = isUsable and true or false,
                link = GetQuestLogItemLink and GetQuestLogItemLink("choice", slot) or nil,
            }
        end
    end
    local numRewards = (GetNumQuestLogRewards and GetNumQuestLogRewards()) or 0
    for slot = 1, numRewards do
        local name, texture, numItems, quality, isUsable = GetQuestLogRewardInfo(slot)
        if name then
            detail.rewards[#detail.rewards + 1] = {
                kind = "reward", slot = slot, name = name, texture = texture,
                count = numItems or 1, quality = quality or 1, usable = isUsable and true or false,
                link = GetQuestLogItemLink and GetQuestLogItemLink("reward", slot) or nil,
            }
        end
    end

    if GetQuestLogRewardSpell then
        local texture, name = GetQuestLogRewardSpell()
        if name then detail.spell = { name = name, texture = texture } end
    end

    if restore and restore > 0 then SelectQuestLogEntry(restore) end
    return detail
end

-- ---------------------------------------------------------------------------
-- The display list
--
-- The scan's flat log order is the source; this turns it into what the
-- navigator actually draws, applying the search, the filter, the sort and the
-- window's own collapse state. Headers survive only if something under them
-- did, so filtering never leaves a zone heading with nothing beneath it.
-- ---------------------------------------------------------------------------

Q.FILTERS = {
    ALL = { label = "All", tooltip = "Every quest in the log." },
    ACTIVE = { label = "Active", tooltip = "Quests still being worked." },
    COMPLETE = { label = "Ready", tooltip = "Quests whose objectives are filled and are waiting to be turned in." },
    TRACKED = { label = "Tracked", tooltip = "Quests on the objective tracker." },
}

Q.SORTS = {
    { value = "LOG", text = "Zone (log order)" },
    { value = "LEVEL", text = "Level" },
    { value = "NAME", text = "Name" },
    { value = "PROGRESS", text = "Progress" },
}

local function Matches(entry, needle)
    if not needle or needle == "" then return true end
    if (entry.title or ""):lower():find(needle, 1, true) then return true end
    if (entry.header or ""):lower():find(needle, 1, true) then return true end
    for _, objective in ipairs(entry.objectives) do
        if (objective.text or ""):lower():find(needle, 1, true) then return true end
    end
    return false
end

local function PassesFilter(entry, filter)
    if filter == "ACTIVE" then return not entry.isComplete end
    if filter == "COMPLETE" then return entry.isComplete end
    if filter == "TRACKED" then return entry.watched end
    return true
end

-- Fraction of the way done, used by the PROGRESS sort and the row's bar. A
-- quest with no countable objectives is 0 or 1, never a fraction of nothing.
function Q.Progress(entry)
    if entry.isComplete then return 1 end
    if entry.numObjectives == 0 then return 0 end
    local have, need = 0, 0
    for _, objective in ipairs(entry.objectives) do
        if objective.need and objective.need > 0 then
            have = have + math.min(objective.have or 0, objective.need)
            need = need + objective.need
        else
            need = need + 1
            if objective.finished then have = have + 1 end
        end
    end
    if need == 0 then return 0 end
    return have / need
end

-- collapsed is a set keyed by header title (our display state, never the
-- client's). Returns a flat list of rows: headers and quests interleaved.
function Q.BuildList(entries, opts)
    opts = opts or {}
    local needle = (opts.search or ""):lower()
    local filter = opts.filter or "ALL"
    local sort = opts.sort or "LOG"
    local collapsed = opts.collapsed or {}
    local rows, shown = {}, 0

    -- Pass one: which quests survive the search and the filter
    local kept, keptByHeader = {}, {}
    for _, entry in ipairs(entries) do
        if not entry.isHeader and Matches(entry, needle) and PassesFilter(entry, filter) then
            kept[#kept + 1] = entry
            local key = entry.header or ""
            keptByHeader[key] = (keptByHeader[key] or 0) + 1
        end
    end
    shown = #kept

    if sort ~= "LOG" then
        -- A sort abandons the zone grouping outright rather than sorting
        -- inside each zone: the point of picking "Level" is one ordered list.
        local ordered = {}
        for index, entry in ipairs(kept) do ordered[index] = entry end
        table.sort(ordered, function(a, b)
            if sort == "LEVEL" then
                if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
            elseif sort == "PROGRESS" then
                local pa, pb = Q.Progress(a), Q.Progress(b)
                if pa ~= pb then return pa > pb end
            end
            return (a.title or "") < (b.title or "")
        end)
        for _, entry in ipairs(ordered) do
            rows[#rows + 1] = { entry = entry }
        end
        return rows, shown
    end

    local keptSet = {}
    for _, entry in ipairs(kept) do keptSet[entry] = true end

    for _, entry in ipairs(entries) do
        if entry.isHeader then
            local surviving = keptByHeader[entry.title] or 0
            if surviving > 0 then
                rows[#rows + 1] = {
                    header = entry,
                    collapsed = collapsed[entry.title] and true or false,
                    shownCount = surviving,
                }
            end
        elseif keptSet[entry] then
            local headerTitle = entry.header
            if not (headerTitle and collapsed[headerTitle]) then
                rows[#rows + 1] = { entry = entry }
            end
        end
    end

    -- A log with no headers at all (every quest loose, which the client does
    -- allow) still lists its quests: the loop above already handled that,
    -- because a quest with no header can never be collapsed away.
    return rows, shown
end
