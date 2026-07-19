-- Commander Objectives: RTS mission-objective announcements. Progress comes
-- from UI_INFO_MESSAGE (the engine's own "Boar slain: 4/8" feed), so there
-- is no quest-log scanning or Blizzard tracker hooking to break: any info
-- message containing an n/m counter is treated as objective progress, shown
-- as a toast, and promoted to OBJECTIVE SECURED when the counter fills.
-- QUEST_TURNED_IN adds the MISSION ACCOMPLISHED banner.

local COLOR_PROGRESS = { 0.9, 0.9, 0.9 }
local COLOR_SECURED = { 0.3, 1, 0.4 }
local COLOR_MISSION = { 1, 0.82, 0.15 }

local banner = CreateFrame("Frame", "CommanderObjectivesBanner", UIParent)
banner:SetSize(600, 60)
banner:SetPoint("TOP", UIParent, "TOP", 0, -120)
banner:SetFrameStrata("HIGH")
banner:Hide()

local headline = banner:CreateFontString(nil, "OVERLAY")
headline:SetFontObject(GameFontNormalHuge)
headline:SetPoint("TOP", banner, "TOP", 0, 0)

local subline = banner:CreateFontString(nil, "OVERLAY")
subline:SetFontObject(GameFontNormal)
subline:SetPoint("TOP", headline, "BOTTOM", 0, -6)
subline:SetTextColor(0.9, 0.9, 0.9)

-- Generation token so a fresh banner is never cut short by an older hide
-- timer (same trap Adjutant hit). Priority banners (secured objectives,
-- milestones, boss kills, mission events) additionally hold the frame so
-- an ordinary per-kill progress toast cannot overwrite them mid-display.
local generation = 0
local priorityUntil = -math.huge

local function ShowBanner(title, detail, color, withSound, isPriority)
    local hold = CommanderObjectivesDB.HoldTime or 2.5
    if not isPriority and GetTime() < priorityUntil then
        return
    end
    if isPriority then
        priorityUntil = GetTime() + hold
    end
    generation = generation + 1
    local myGeneration = generation
    headline:SetText(title)
    headline:SetTextColor(color[1], color[2], color[3])
    subline:SetText(detail or "")
    banner:Show()
    if withSound and CommanderObjectivesDB.ObjectiveSound then
        PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE, "Master")
    end
    C_Timer.After(hold, function()
        if generation == myGeneration then
            banner:Hide()
        end
    end)
end

local function IsOn()
    return CommanderObjectivesDB and CommanderObjectivesDB.EnableObjectives
end

local function OnInfoMessage(message)
    if not IsOn() then return end
    if type(message) ~= "string" then return end
    local current, total = message:match("(%d+)%s*/%s*(%d+)")
    if not current then return end
    if tonumber(current) >= tonumber(total) then
        -- Secured lines are the module's headline and stay on even when
        -- the (spammier) per-kill progress toasts are turned off
        ShowBanner("OBJECTIVE SECURED", message, COLOR_SECURED, true, true)
    elseif CommanderObjectivesDB.ProgressToasts then
        ShowBanner("OBJECTIVE PROGRESS", message, COLOR_PROGRESS, false)
    end
end

local function OnQuestTurnedIn()
    if not (IsOn() and CommanderObjectivesDB.MissionBanner) then return end
    ShowBanner("MISSION ACCOMPLISHED", "Quest turned in", COLOR_MISSION, true, true)
end

function CommanderObjectives_Test()
    if not IsOn() then
        print("Commander Objectives: module is disabled (enable it in settings or /cobj)")
        return
    end
    ShowBanner("OBJECTIVE SECURED", "Test Objective: 8/8", COLOR_SECURED, true, true)
end

-- ---------------------------------------------------------------------------
-- Standing objectives: an SC2-style mission board of algorithm-generated
-- grind objectives. A small set of METRICS (kills, bosses, xp, loot,
-- rare finds, quests, honor, deathless minutes) is fed by events; the
-- ROSTER below is pure data over those metrics — tiered targets that make
-- any grind session feel like a mission, whatever the player's role.
-- Adding an objective = adding one table entry.
-- ---------------------------------------------------------------------------
local ROSTER = {
    { key = "kills10", label = "Eliminate 10 hostiles", category = "Combat", metric = "kills", target = 10 },
    { key = "kills25", label = "Eliminate 25 hostiles", category = "Combat", metric = "kills", target = 25 },
    { key = "kills50", label = "Eliminate 50 hostiles", category = "Combat", metric = "kills", target = 50 },
    { key = "kills100", label = "Eliminate 100 hostiles", category = "Combat", metric = "kills", target = 100 },
    { key = "bosses1", label = "Down a primary target", category = "Combat", metric = "bosses", target = 1 },
    { key = "bosses3", label = "Down 3 primary targets", category = "Combat", metric = "bosses", target = 3 },
    { key = "xp5k", label = "Gain 5,000 experience", category = "Growth", metric = "xp", target = 5000 },
    { key = "xp25k", label = "Gain 25,000 experience", category = "Growth", metric = "xp", target = 25000 },
    { key = "xp100k", label = "Gain 100,000 experience", category = "Growth", metric = "xp", target = 100000 },
    { key = "loot10", label = "Recover 10 supplies", category = "Supply", metric = "loot", target = 10 },
    { key = "loot25", label = "Recover 25 supplies", category = "Supply", metric = "loot", target = 25 },
    { key = "rare5", label = "Find 5 uncommon+ items", category = "Supply", metric = "rareloot", target = 5 },
    { key = "quests1", label = "Turn in a quest", category = "Duty", metric = "quests", target = 1 },
    { key = "quests5", label = "Turn in 5 quests", category = "Duty", metric = "quests", target = 5 },
    { key = "honor1", label = "Score an honorable kill", category = "Valor", metric = "honor", target = 1 },
    { key = "honor10", label = "Score 10 honorable kills", category = "Valor", metric = "honor", target = 10 },
    { key = "deathless15", label = "Stay alive 15 minutes", category = "Endurance", metric = "deathless", target = 15 },
    { key = "deathless30", label = "Stay alive 30 minutes", category = "Endurance", metric = "deathless", target = 30 },
}

-- Consumed by the DB file's roster checklist panel
function CommanderObjectives_GetRoster()
    return ROSTER
end

-- ---------------------------------------------------------------------------
-- Dungeon missions: solo questing gets objective toasts from the quest
-- system; dungeon groups get almost no feedback at all. In an instance the
-- module runs a "mission": every hostile the group drops counts, kill
-- milestones raise banners, boss kills are PRIMARY TARGET ELIMINATED, and
-- leaving prints the run's tally — incremental progress for dungeon spam.
-- ---------------------------------------------------------------------------
local mission = nil   -- { name, start, kills, nextAt, encounters }

local MILESTONES = { 10, 25, 50, 75, 100 }

local function NextMilestone(kills)
    for _, m in ipairs(MILESTONES) do
        if kills < m then return m end
    end
    return (math.floor(kills / 50) + 1) * 50
end

local function MissionsWanted()
    if not (IsOn() and CommanderObjectivesDB.DungeonMissions) then return false end
    local inInstance, instanceType = IsInInstance()
    return inInstance and (instanceType == "party" or instanceType == "raid")
end

local function StartMission()
    local name = GetInstanceInfo() or "unknown objective"
    mission = { name = name, startEpoch = time(), kills = 0, nextAt = NextMilestone(0), encounters = 0 }
    if CommanderObjectivesDB.Session then
        CommanderObjectivesDB.Session.mission = mission
    end
    ShowBanner("MISSION START", name, COLOR_MISSION, true, true)
end

local function EndMission()
    if not mission then return end
    local elapsed = mission.startEpoch and (time() - mission.startEpoch)
        or (GetTime() - (mission.start or GetTime()))
    local minutes = math.max(math.floor(elapsed / 60), 1)
    local bosses = mission.encounters > 0
        and string.format(", %d primary target%s down", mission.encounters, mission.encounters == 1 and "" or "s")
        or ""
    print(string.format("Commander Objectives: %s — %d hostiles eliminated%s in %dm",
        mission.name, mission.kills, bosses, minutes))
    mission = nil
    if CommanderObjectivesDB.Session then
        CommanderObjectivesDB.Session.mission = false
    end
end

local function IsHostileNPC(flags)
    -- Pets, guardians, and totems die noisily but are not kills
    return flags
        and bit.band(flags, COMBATLOG_OBJECT_REACTION_HOSTILE) > 0
        and bit.band(flags, COMBATLOG_OBJECT_CONTROL_NPC) > 0
        and bit.band(flags, (COMBATLOG_OBJECT_TYPE_PET or 0x1000)
            + (COMBATLOG_OBJECT_TYPE_GUARDIAN or 0x2000)) == 0
end

-- The CLEU read happens once in the event handler; this only does the
-- mission-side bookkeeping for an already-classified hostile NPC death
local function OnMissionHostileKill()
    if not mission then return end
    mission.kills = mission.kills + 1
    if mission.kills >= mission.nextAt then
        ShowBanner(string.format("%d HOSTILES ELIMINATED", mission.kills), "Squad advancing", COLOR_SECURED, true, true)
        mission.nextAt = NextMilestone(mission.kills)
    end
end

local function OnEncounterEnd(encounterName, success)
    if not mission then return end
    if success == 1 then
        mission.encounters = mission.encounters + 1
        ShowBanner("PRIMARY TARGET ELIMINATED", encounterName, COLOR_MISSION, true, true)
    end
end

-- ---------------------------------------------------------------------------
-- Operation state: one "operation" = the current grind segment. It rerolls
-- when a dungeon mission starts or ends, so every run is a fresh board;
-- outside instances it spans the session segment. Deathless progress is
-- time-based from the operation start or the last death.
-- ---------------------------------------------------------------------------
local op = nil
local session   -- reload-resilient home for op and mission

local function StartOperation()
    op = {
        start = GetTime(),
        startEpoch = time(),
        lastDeath = nil,
        counters = { kills = 0, bosses = 0, xp = 0, loot = 0, rareloot = 0, quests = 0, honor = 0 },
        completed = {},
    }
    if session then session.op = op end
end

local function ObjectiveEnabled(def)
    local enabled = CommanderObjectivesDB.EnabledObjectives
    return not enabled or enabled[def.key] ~= false
end

local function Progress(def)
    if not op then return 0 end
    if def.metric == "deathless" then
        return math.floor((GetTime() - (op.lastDeath or op.start)) / 60)
    end
    return op.counters[def.metric] or 0
end

local TouchBoard -- forward-declared; defined with the board below

-- Completed board objectives can go out as a custom emote so the group
-- watches the objectives fall as you clear — with the running board tally
local function AnnounceCompletion(def)
    if not CommanderObjectivesDB.CompleteEmotes then return end
    local done, total = 0, 0
    for _, d in ipairs(ROSTER) do
        if ObjectiveEnabled(d) then
            total = total + 1
            if op.completed[d.key] then done = done + 1 end
        end
    end
    SendChatMessage(string.format(
        "completes a mission objective — %s! (%d of %d on the board)",
        def.label, done, total), "EMOTE")
end

local function CheckCompletions()
    if not op then return end
    for _, def in ipairs(ROSTER) do
        if ObjectiveEnabled(def) and not op.completed[def.key]
            and Progress(def) >= def.target then
            op.completed[def.key] = true
            ShowBanner("OBJECTIVE COMPLETE", def.label, COLOR_SECURED, true, true)
            AnnounceCompletion(def)
        end
    end
end

local function Bump(metric, amount)
    if not (IsOn() and op) then return end
    op.counters[metric] = (op.counters[metric] or 0) + (amount or 1)
    CheckCompletions()
    if TouchBoard then TouchBoard() end
end

local function CheckMissionState()
    if MissionsWanted() then
        if not mission then
            StartMission()
            StartOperation()
            if TouchBoard then TouchBoard() end
        end
    elseif mission then
        -- A ghost release teleports outside the instance; the run is not
        -- over, the squad is regrouping. Only end missions while alive.
        if UnitIsDeadOrGhost("player") then return end
        EndMission()
        StartOperation()
        if TouchBoard then TouchBoard() end
    end
end

-- ---------------------------------------------------------------------------
-- The mission board: an SC2-style objectives window. Incomplete objectives
-- list with live progress, completed ones tick off in green. Always
-- visible, or surfacing on progress and fading BoardHold seconds later.
-- ---------------------------------------------------------------------------
local BOARD_WIDTH = 250
local BOARD_ROW_HEIGHT = 15
local BOARD_MAX_ROWS = 9

local board = CreateFrame("Frame", "CommanderObjectivesBoardFrame", UIParent)
board:SetPoint("RIGHT", UIParent, "RIGHT", -14, 170)
board:SetSize(BOARD_WIDTH, 160)
board:SetFrameStrata("MEDIUM")
board:Hide()

local boardHeader = board:CreateFontString(nil, "OVERLAY")
boardHeader:SetFontObject(GameFontNormal)
boardHeader:SetPoint("TOPLEFT", board, "TOPLEFT", 0, 0)
boardHeader:SetText("OBJECTIVES")
boardHeader:SetTextColor(1, 0.82, 0.15)

local boardRows = {}
for i = 1, BOARD_MAX_ROWS do
    local row = board:CreateFontString(nil, "OVERLAY")
    row:SetFontObject(GameFontHighlightSmall)
    row:SetPoint("TOPLEFT", board, "TOPLEFT", 4, -18 - (i - 1) * BOARD_ROW_HEIGHT)
    row:SetPoint("RIGHT", board, "RIGHT", -2, 0)
    row:SetJustifyH("LEFT")
    if row.SetWordWrap then row:SetWordWrap(false) end
    row:Hide()
    boardRows[i] = row
end

local lastProgress = -math.huge

local function BoardWanted()
    return IsOn() and (CommanderObjectivesDB.BoardAlwaysVisible
        or Commander.UI.HudUnlocked(CommanderObjectivesDB, "Board")
        or (GetTime() - lastProgress) < (CommanderObjectivesDB.BoardHold or 6))
end

local function FormatCount(n)
    if n >= 10000 then
        return string.format("%.1fk", n / 1000)
    end
    return tostring(n)
end

local function RefreshBoard()
    if not op then
        board:Hide()
        return
    end
    local shown = 0
    -- Incomplete objectives first, then completed ticks, capped
    for _, def in ipairs(ROSTER) do
        if shown >= BOARD_MAX_ROWS then break end
        if ObjectiveEnabled(def) and not op.completed[def.key] then
            shown = shown + 1
            local row = boardRows[shown]
            row:SetText(string.format("%s  —  %s/%s", def.label,
                FormatCount(math.min(Progress(def), def.target)), FormatCount(def.target)))
            row:SetTextColor(0.95, 0.95, 0.95)
            row:Show()
        end
    end
    for _, def in ipairs(ROSTER) do
        if shown >= BOARD_MAX_ROWS then break end
        if ObjectiveEnabled(def) and op.completed[def.key] then
            shown = shown + 1
            local row = boardRows[shown]
            row:SetText("+ " .. def.label)
            row:SetTextColor(0.3, 1, 0.4)
            row:Show()
        end
    end
    for i = shown + 1, BOARD_MAX_ROWS do
        boardRows[i]:Hide()
    end
    board:SetSize(BOARD_WIDTH, 20 + shown * BOARD_ROW_HEIGHT)
    Commander.UI.ApplyHudChrome(board, CommanderObjectivesDB, "Board", {
        title = "Objectives",
        defaultPoint = { point = "RIGHT", x = -14, y = 170 },
    })
    board:SetShown(BoardWanted() and shown > 0)
end

-- Deathless minutes tick and the auto-hide window both need a slow pulse
local sinceBoardTick = 0
board:SetScript("OnUpdate", function(self, elapsed)
    sinceBoardTick = sinceBoardTick + elapsed
    if sinceBoardTick < 0.5 then return end
    sinceBoardTick = 0
    CheckCompletions()
    RefreshBoard()
end)

TouchBoard = function()
    lastProgress = GetTime()
    RefreshBoard()
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local xpPrev, xpPrevMax, xpPrevLevel

local RARE_LOOT_COLORS = {
    ["ff1eff00"] = true, ["ff0070dd"] = true,
    ["ffa335ee"] = true, ["ffff8000"] = true,
}

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("UI_INFO_MESSAGE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:RegisterEvent("PLAYER_XP_UPDATE")
events:RegisterEvent("CHAT_MSG_LOOT")
events:RegisterEvent("PLAYER_DEAD")
if not C_EventUtils or (C_EventUtils.IsEventValid and C_EventUtils.IsEventValid("CHAT_MSG_COMBAT_HONOR_GAIN")) then
    pcall(events.RegisterEvent, events, "CHAT_MSG_COMBAT_HONOR_GAIN")
end
-- Same guard pattern as Commander_Economy: if a future patch moves the
-- event, banners just stop, nothing breaks
if not C_EventUtils or C_EventUtils.IsEventValid("QUEST_TURNED_IN") then
    pcall(events.RegisterEvent, events, "QUEST_TURNED_IN")
end
if not C_EventUtils or C_EventUtils.IsEventValid("ENCOUNTER_END") then
    pcall(events.RegisterEvent, events, "ENCOUNTER_END")
end
events:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4, arg5)
    if event == "PLAYER_LOGIN" then
        -- Settings changes re-evaluate the mission and re-style the board,
        -- so disabling things mid-instance actually takes effect
        Commander.AddListener(COMMANDER_OBJECTIVES_EVENTS.UPDATE, CheckMissionState)
        Commander.AddListener(COMMANDER_OBJECTIVES_EVENTS.UPDATE, RefreshBoard)
        -- A /reload resumes the running operation (and any live dungeon
        -- mission) with clocks converted from epoch back into GetTime's
        -- domain; a real break rolls a fresh board
        local fresh
        session, fresh = Commander.RestoreSession(CommanderObjectivesDB, { op = false, mission = false })
        if not fresh and session.op then
            op = session.op
            op.start = GetTime() - (time() - (op.startEpoch or time()))
            if op.lastDeathEpoch then
                op.lastDeath = GetTime() - (time() - op.lastDeathEpoch)
            else
                op.lastDeath = nil
            end
            if session.mission then
                mission = session.mission
            end
        else
            session.mission = false
            StartOperation()
        end
        xpPrev, xpPrevMax, xpPrevLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
        RefreshBoard()
        -- The board's own OnUpdate only ticks while it is shown; deathless
        -- objectives completing with the board hidden need this heartbeat
        C_Timer.NewTicker(30, function()
            if IsOn() and op then
                CheckCompletions()
            end
        end)
    elseif event == "UI_INFO_MESSAGE" then
        -- Payload is (messageType, message)
        OnInfoMessage(arg2)
    elseif event == "QUEST_TURNED_IN" then
        OnQuestTurnedIn()
        Bump("quests")
    elseif event == "PLAYER_ENTERING_WORLD" then
        CheckMissionState()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subevent, _, _, _, _, _, _, _, destFlags = CombatLogGetCurrentEventInfo()
        if subevent == "UNIT_DIED" and IsHostileNPC(destFlags) then
            Bump("kills")
            OnMissionHostileKill()
        end
    elseif event == "ENCOUNTER_END" then
        -- (encounterID, name, difficulty, groupSize, success)
        OnEncounterEnd(arg2, arg5)
        if arg5 == 1 then
            Bump("bosses")
        end
    elseif event == "PLAYER_XP_UPDATE" then
        local xp, xpMax, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
        if xpPrev then
            local delta
            if level > (xpPrevLevel or level) then
                delta = ((xpPrevMax or 0) - (xpPrev or 0)) + xp
            else
                delta = xp - xpPrev
            end
            if delta and delta > 0 then
                Bump("xp", delta)
            end
        end
        xpPrev, xpPrevMax, xpPrevLevel = xp, xpMax, level
    elseif event == "CHAT_MSG_LOOT" then
        if type(arg1) == "string"
            and (arg1:find("You receive loot") or arg1:find("You receive item")) then
            Bump("loot")
            local color = arg1:match("|c(%x%x%x%x%x%x%x%x)")
            if color and RARE_LOOT_COLORS[color:lower()] then
                Bump("rareloot")
            end
        end
    elseif event == "PLAYER_DEAD" then
        if op then
            op.lastDeath = GetTime()
            op.lastDeathEpoch = time()
            if TouchBoard then TouchBoard() end
        end
    elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        if type(arg1) == "string" and arg1:find("dies, honorable kill") then
            Bump("honor")
        end
    end
end)
