-- Commander Momentum: a decaying kill-streak meter. Killing blows (CLEU
-- PARTY_KILL with the player as source) push the streak up and refill the
-- drain bar; when the bar empties the streak is gone. Colors escalate at
-- milestones. Shown only while a streak of 2+ is alive, so the HUD stays
-- clean between pulls.

local BAR_WIDTH = 120
local BAR_HEIGHT = 8

local streak = 0
local lastKill = -math.huge
local announcedMilestone = 0

local root = CreateFrame("Frame", "CommanderMomentumFrame", UIParent)
root:SetPoint("TOP", UIParent, "TOP", 0, -260)
root:SetSize(BAR_WIDTH + 10, 44)
root:SetFrameStrata("MEDIUM")
root:Hide()

local streakText = root:CreateFontString(nil, "OVERLAY")
streakText:SetFontObject(GameFontNormalHuge)
streakText:SetPoint("TOP", root, "TOP", 0, 0)

local labelText = root:CreateFontString(nil, "OVERLAY")
labelText:SetFontObject(GameFontHighlightSmall)
labelText:SetPoint("TOP", streakText, "BOTTOM", 0, -1)
labelText:SetText("MOMENTUM")
labelText:SetTextColor(0.8, 0.8, 0.8)

local barBG = root:CreateTexture(nil, "BACKGROUND")
barBG:SetTexture("Interface\\Buttons\\WHITE8X8")
barBG:SetVertexColor(0, 0, 0, 0.55)
barBG:SetSize(BAR_WIDTH, BAR_HEIGHT)
barBG:SetPoint("BOTTOM", root, "BOTTOM", 0, 0)

local bar = root:CreateTexture(nil, "ARTWORK")
bar:SetTexture("Interface\\Buttons\\WHITE8X8")
bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
bar:SetPoint("LEFT", barBG, "LEFT", 0, 0)

-- Escalating streak colors: white -> green -> blue -> purple -> orange
local function StreakColor()
    if streak >= 20 then
        return 1, 0.5, 0.1
    elseif streak >= 15 then
        return 0.7, 0.35, 1
    elseif streak >= 10 then
        return 0.35, 0.65, 1
    elseif streak >= 5 then
        return 0.3, 1, 0.4
    end
    return 0.95, 0.95, 0.95
end

local function EndStreak()
    streak = 0
    announcedMilestone = 0
    local keepShown = CommanderMomentumDB and CommanderMomentumDB.EnableMomentum
        and (CommanderMomentumDB.AlwaysShow
            or Commander.UI.HudUnlocked(CommanderMomentumDB, "Hud"))
    root:SetShown(keepShown or false)
    root:SetScript("OnUpdate", nil)
    if keepShown then
        streakText:SetText("x0")
        streakText:SetTextColor(0.6, 0.6, 0.6)
        bar:SetSize(1, BAR_HEIGHT)
    end
end

local sinceDraw = 0
local function OnDrain(self, elapsed)
    sinceDraw = sinceDraw + elapsed
    if sinceDraw < 0.05 then return end
    sinceDraw = 0
    local window = CommanderMomentumDB.Window or 20
    local remaining = (lastKill + window) - GetTime()
    if remaining <= 0 then
        EndStreak()
        return
    end
    bar:SetSize(math.max(BAR_WIDTH * (remaining / window), 1), BAR_HEIGHT)
end

local function Refresh()
    local r, g, b = StreakColor()
    streakText:SetText(string.format("x%d", streak))
    streakText:SetTextColor(r, g, b)
    bar:SetVertexColor(r, g, b, 0.9)
end

local function OnKill()
    -- Enforce the window even for streaks too small to show: without this,
    -- a streak of 1 never expires (no visible frame, no drain driver) and
    -- any two kills ever would chain into a bogus x2
    local window = CommanderMomentumDB.Window or 20
    if GetTime() - lastKill > window then
        streak = 0
        announcedMilestone = 0
    end
    streak = streak + 1
    lastKill = GetTime()
    if streak >= 2 then
        Refresh()
        Commander.UI.ApplyHudChrome(root, CommanderMomentumDB, "Hud", {
            defaultPoint = { point = "TOP", x = 0, y = -260 },
        })
        root:Show()
        root:SetScript("OnUpdate", OnDrain)
    end
    local milestone = math.floor(streak / 5) * 5
    if milestone >= 5 and milestone > announcedMilestone then
        announcedMilestone = milestone
        if CommanderMomentumDB.MilestoneSound then
            PlaySound(SOUNDKIT.READY_CHECK, "Master")
        end
        print(string.format("|cffffb830Commander Momentum:|r x%d streak", streak))
    end
end

local function Apply()
    if not (CommanderMomentumDB and CommanderMomentumDB.EnableMomentum) then
        EndStreak()
        return
    end
    -- Unlocked or Always Show: keep the meter on screen with no streak
    local unlocked = Commander.UI.HudUnlocked(CommanderMomentumDB, "Hud")
    if root:IsShown() or unlocked or CommanderMomentumDB.AlwaysShow then
        Commander.UI.ApplyHudChrome(root, CommanderMomentumDB, "Hud", {
            defaultPoint = { point = "TOP", x = 0, y = -260 },
        })
        root:Show()
        Refresh()
        if streak < 2 then
            streakText:SetText(string.format("x%d", streak))
            streakText:SetTextColor(0.6, 0.6, 0.6)
            bar:SetSize(unlocked and BAR_WIDTH or 1, BAR_HEIGHT)
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        Commander.AddListener(COMMANDER_MOMENTUM_EVENTS.UPDATE, Apply)
        return
    end
    if not (CommanderMomentumDB and CommanderMomentumDB.EnableMomentum) then return end
    local _, subevent, _, sourceGUID, _, _, _, _, _, destFlags = CombatLogGetCurrentEventInfo()
    if CommanderMomentumDB.KillSource == "SQUAD" then
        -- Any hostile NPC death nearby feeds the meter — momentum for
        -- healers and tanks, not just whoever lands the killing blow
        if subevent == "UNIT_DIED" and destFlags
            and bit.band(destFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) > 0
            and bit.band(destFlags, COMBATLOG_OBJECT_CONTROL_NPC) > 0 then
            OnKill()
        end
    elseif subevent == "PARTY_KILL" and sourceGUID == UnitGUID("player") then
        OnKill()
    end
end)
