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
-- timer (same trap Adjutant hit)
local generation = 0

local function ShowBanner(title, detail, color, withSound)
    generation = generation + 1
    local myGeneration = generation
    headline:SetText(title)
    headline:SetTextColor(color[1], color[2], color[3])
    subline:SetText(detail or "")
    banner:Show()
    if withSound and CommanderObjectivesDB.ObjectiveSound then
        PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE, "Master")
    end
    C_Timer.After(CommanderObjectivesDB.HoldTime or 2.5, function()
        if generation == myGeneration then
            banner:Hide()
        end
    end)
end

local function IsOn()
    return CommanderObjectivesDB and CommanderObjectivesDB.EnableObjectives
end

local function OnInfoMessage(message)
    if not (IsOn() and CommanderObjectivesDB.ProgressToasts) then return end
    if type(message) ~= "string" then return end
    local current, total = message:match("(%d+)%s*/%s*(%d+)")
    if not current then return end
    if tonumber(current) >= tonumber(total) then
        ShowBanner("OBJECTIVE SECURED", message, COLOR_SECURED, true)
    else
        ShowBanner("OBJECTIVE PROGRESS", message, COLOR_PROGRESS, false)
    end
end

local function OnQuestTurnedIn()
    if not (IsOn() and CommanderObjectivesDB.MissionBanner) then return end
    ShowBanner("MISSION ACCOMPLISHED", "Quest turned in", COLOR_MISSION, true)
end

function CommanderObjectives_Test()
    if not IsOn() then
        print("Commander Objectives: module is disabled (enable it in settings or /cobj)")
        return
    end
    ShowBanner("OBJECTIVE SECURED", "Test Objective: 8/8", COLOR_SECURED, true)
end

local events = CreateFrame("Frame")
events:RegisterEvent("UI_INFO_MESSAGE")
-- Same guard pattern as Commander_Economy: if a future patch moves the
-- event, banners just stop, nothing breaks
if not C_EventUtils or C_EventUtils.IsEventValid("QUEST_TURNED_IN") then
    pcall(events.RegisterEvent, events, "QUEST_TURNED_IN")
end
events:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "UI_INFO_MESSAGE" then
        -- Payload is (messageType, message)
        OnInfoMessage(arg2)
    elseif event == "QUEST_TURNED_IN" then
        OnQuestTurnedIn()
    end
end)
