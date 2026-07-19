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
    mission = { name = name, start = GetTime(), kills = 0, nextAt = NextMilestone(0), encounters = 0 }
    ShowBanner("MISSION START", name, COLOR_MISSION, true, true)
end

local function EndMission()
    if not mission then return end
    local minutes = math.max(math.floor((GetTime() - mission.start) / 60), 1)
    local bosses = mission.encounters > 0
        and string.format(", %d primary target%s down", mission.encounters, mission.encounters == 1 and "" or "s")
        or ""
    print(string.format("Commander Objectives: %s — %d hostiles eliminated%s in %dm",
        mission.name, mission.kills, bosses, minutes))
    mission = nil
end

local function IsHostileNPC(flags)
    return flags
        and bit.band(flags, COMBATLOG_OBJECT_REACTION_HOSTILE) > 0
        and bit.band(flags, COMBATLOG_OBJECT_CONTROL_NPC) > 0
end

local function OnMissionCombatLog()
    if not mission then return end
    local _, subevent, _, _, _, _, _, _, _, destFlags = CombatLogGetCurrentEventInfo()
    if subevent ~= "UNIT_DIED" then return end
    if not IsHostileNPC(destFlags) then return end
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

local function CheckMissionState()
    if MissionsWanted() then
        if not mission then StartMission() end
    elseif mission then
        -- A ghost release teleports outside the instance; the run is not
        -- over, the squad is regrouping. Only end missions while alive.
        if UnitIsDeadOrGhost("player") then return end
        EndMission()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("UI_INFO_MESSAGE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
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
        -- Settings changes re-evaluate the mission, so disabling the
        -- module (or Dungeon Missions) mid-instance actually stops it
        Commander.AddListener(COMMANDER_OBJECTIVES_EVENTS.UPDATE, CheckMissionState)
    elseif event == "UI_INFO_MESSAGE" then
        -- Payload is (messageType, message)
        OnInfoMessage(arg2)
    elseif event == "QUEST_TURNED_IN" then
        OnQuestTurnedIn()
    elseif event == "PLAYER_ENTERING_WORLD" then
        CheckMissionState()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnMissionCombatLog()
    elseif event == "ENCOUNTER_END" then
        -- (encounterID, name, difficulty, groupSize, success)
        OnEncounterEnd(arg2, arg5)
    end
end)
