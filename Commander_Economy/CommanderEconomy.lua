-- Commander Economy: session bookkeeping for the mission summary. Tracking
-- runs whether or not the module is enabled (same precedent as Top Bar's XP
-- bookkeeping) so enabling mid-session still yields a full-session report;
-- the flag gates the report output and the hourly ticker.

local sessionStart = 0
local goldEarned, goldSpent = 0, 0
local lastMoney = nil
local xpGained = 0
local prevXP, prevXPMax, prevLevel = nil, nil, nil
local questsTurnedIn = 0
local deaths = 0
local hourlyTicker = nil

local function Coins(copper)
    local sign = copper < 0 and "-" or ""
    copper = math.abs(copper)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    if gold > 0 then
        return string.format("%s%dg %ds", sign, gold, silver)
    end
    return string.format("%s%ds %dc", sign, silver, copper % 100)
end

local function SessionDuration()
    local elapsed = GetTime() - sessionStart
    if elapsed < 0 then elapsed = 0 end
    local hours = math.floor(elapsed / 3600)
    local minutes = math.floor((elapsed % 3600) / 60)
    if hours > 0 then
        return string.format("%dh %02dm", hours, minutes), elapsed
    end
    return string.format("%dm", minutes), elapsed
end

function CommanderEconomy_Report()
    if not (CommanderEconomyDB and CommanderEconomyDB.EnableEconomy) then
        print("Commander Economy: module is disabled (enable it in settings or /ceco)")
        return
    end
    local duration, elapsed = SessionDuration()
    print(string.format("Commander Economy — mission summary (%s):", duration))
    print(string.format("  Gold: %s earned, %s spent (net %s)",
        Coins(goldEarned), Coins(goldSpent), Coins(goldEarned - goldSpent)))
    if elapsed >= 60 and xpGained > 0 then
        print(string.format("  Experience: %d gained (%d per hour)",
            xpGained, math.floor(xpGained / (elapsed / 3600))))
    else
        print(string.format("  Experience: %d gained", xpGained))
    end
    print(string.format("  Quests turned in: %d | Casualties: %d", questsTurnedIn, deaths))
end

local function UpdateTicker()
    local wantTicker = CommanderEconomyDB
        and CommanderEconomyDB.EnableEconomy and CommanderEconomyDB.HourlyReport
    if wantTicker and not hourlyTicker then
        hourlyTicker = C_Timer.NewTicker(3600, CommanderEconomy_Report)
    elseif not wantTicker and hourlyTicker then
        hourlyTicker:Cancel()
        hourlyTicker = nil
    end
end

local function OnMoney()
    local money = GetMoney()
    if lastMoney then
        local delta = money - lastMoney
        if delta > 0 then
            goldEarned = goldEarned + delta
        elseif delta < 0 then
            goldSpent = goldSpent - delta
        end
    end
    lastMoney = money
end

local function OnXP()
    local xp, xpMax, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if prevXP then
        local delta
        if level > prevLevel then
            -- Leveled since the last update: finish the old bar, then add
            -- progress into the new one (multi-level jumps under-count the
            -- skipped bars, acceptable for a session summary)
            delta = (prevXPMax - prevXP) + xp
        else
            delta = xp - prevXP
        end
        if delta > 0 then
            xpGained = xpGained + delta
        end
    end
    prevXP, prevXPMax, prevLevel = xp, xpMax, level
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("PLAYER_XP_UPDATE")
events:RegisterEvent("PLAYER_DEAD")
-- Quest turn-in event: valid on this client, but guard like MINIMAP_PING in
-- case a future patch moves it — quests just stop counting, nothing breaks
if not C_EventUtils or C_EventUtils.IsEventValid("QUEST_TURNED_IN") then
    pcall(events.RegisterEvent, events, "QUEST_TURNED_IN")
end

events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        sessionStart = GetTime()
        lastMoney = GetMoney()
        prevXP, prevXPMax, prevLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
        Commander.AddListener(COMMANDER_ECONOMY_EVENTS.UPDATE, UpdateTicker)
        UpdateTicker()
    elseif event == "PLAYER_MONEY" then
        OnMoney()
    elseif event == "PLAYER_XP_UPDATE" then
        OnXP()
    elseif event == "PLAYER_DEAD" then
        deaths = deaths + 1
    elseif event == "QUEST_TURNED_IN" then
        questsTurnedIn = questsTurnedIn + 1
    end
end)
