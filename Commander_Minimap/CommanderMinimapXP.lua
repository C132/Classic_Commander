-- Commander Minimap XP model: everything the information button knows about
-- experience. Session pace comes from PLAYER_XP_UPDATE deltas (locale-proof,
-- and it sees every source: kills, quests, exploration). Kill credit and its
-- rested bonus come from the combat-XP chat line, parsed with the client's
-- own format strings; quest XP comes straight off QUEST_TURNED_IN.
--
-- Kill and quest history is kept per character so the averages survive a
-- relog; the session (pace, time to level) starts over at each login.

local XP = {}
CommanderMinimapXP = XP

local HISTORY = 10                   -- kills/quests averaged for the "to level" estimates
local BUBBLES = 20                   -- the experience bar is drawn in 20 bars
local RESTED_CAP = 1.5               -- rested stops accruing at one and a half levels
local REST_RATE = 0.05 / (8 * 3600)  -- 5% of a level per 8 hours in a rest area
local MIN_PACE_SECONDS = 60          -- no XP/hour until the session has a minute behind it

XP.BUBBLES = BUBBLES

-- ---------------------------------------------------------------------------
-- Chat parsing
-- ---------------------------------------------------------------------------

-- "%s dies, you gain %d experience." -> "^(.-) dies, you gain (%d+) experience%.$"
-- Positional tokens (%1$s) in other locales are captured in written order.
local function PatternFromFormat(fmt, anchorEnd)
    local p = fmt:gsub("%%%d?%$?([sd])", "\1%1")
    p = p:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    p = p:gsub("\1s", "(.-)"):gsub("\1d", "(%%d+)")
    return "^" .. p .. (anchorEnd and "$" or "")
end
XP.PatternFromFormat = PatternFromFormat

local killPattern, restedPatterns

local function BuildPatterns()
    local first = COMBATLOG_XPGAIN_FIRSTPERSON or "%s dies, you gain %d experience."
    -- Every kill line opens the same way; group bonuses and rested tails follow
    killPattern = PatternFromFormat(first:match("^(.*%%%d?%$?d)") or first, false)
    restedPatterns = {}
    local tails = {
        COMBATLOG_XPGAIN_EXHAUSTION1 or "%s dies, you gain %d experience. (%s exp %s bonus)",
        COMBATLOG_XPGAIN_EXHAUSTION1_GROUP,
        COMBATLOG_XPGAIN_EXHAUSTION1_RAID,
    }
    for _, fmt in ipairs(tails) do
        restedPatterns[#restedPatterns + 1] = PatternFromFormat(fmt, true)
    end
end

local function Digits(text)
    return tonumber((tostring(text or ""):gsub("[^%d]", "")))
end

-- Returns mobName, xp, restedBonus for a kill line; nil for anything else
function XP.ParseKill(message)
    if type(message) ~= "string" then return nil end
    if not killPattern then BuildPatterns() end
    local name, amount = message:match(killPattern)
    amount = tonumber(amount)
    if not (name and amount) then return nil end
    local bonus = 0
    for _, pattern in ipairs(restedPatterns) do
        local _, _, extra = message:match(pattern)
        if extra then
            bonus = Digits(extra) or 0
            break
        end
    end
    return name, amount, math.min(bonus, amount)
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local session, prev, history

local function NewSession(now)
    return { start = now, gained = 0, levels = 0,
             kills = 0, killXP = 0, quests = 0, questXP = 0 }
end

local function Push(list, value)
    list[#list + 1] = value
    while #list > HISTORY do table.remove(list, 1) end
end

local function Average(list)
    if not list or #list == 0 then return nil end
    local total = 0
    for _, v in ipairs(list) do total = total + v end
    return total / #list
end

local function CharacterKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

local function Capture()
    return { xp = UnitXP("player") or 0, max = UnitXPMax("player") or 0,
             level = UnitLevel("player") or 1 }
end

function XP.Init(db, now)
    db.XPHistory = db.XPHistory or {}
    local key = CharacterKey()
    history = db.XPHistory[key]
    if not history then
        history = { kills = {}, quests = {} }
        db.XPHistory[key] = history
        -- The old single-kill field seeds the average (it held the full gain)
        if (db.lastXPGain or 0) > 0 then
            Push(history.kills, db.lastXPGain)
            history.lastKill = { name = db.lastXPSource ~= "" and db.lastXPSource or nil,
                                 xp = db.lastXPGain, bonus = 0 }
        end
    end
    session = NewSession(now)
    prev = Capture()
end

function XP.ResetSession(now)
    session = NewSession(now)
    prev = Capture()
end

function XP.OnXPUpdate()
    if not session then return 0 end
    local cur = Capture()
    local delta
    if cur.level > prev.level then
        -- Finish the old level, then count what landed in the new one
        delta = (prev.max - prev.xp) + cur.xp
        session.levels = session.levels + (cur.level - prev.level)
    else
        delta = cur.xp - prev.xp
    end
    prev = cur
    if delta > 0 then
        session.gained = session.gained + delta
        return delta
    end
    return 0
end

function XP.OnKillMessage(message)
    if not session then return nil end
    local name, amount, bonus = XP.ParseKill(message)
    if not name then return nil end
    session.kills = session.kills + 1
    session.killXP = session.killXP + amount
    -- The average is of base XP: rested doubling is applied per estimate
    Push(history.kills, amount - bonus)
    history.lastKill = { name = name, xp = amount, bonus = bonus }
    return name, amount, bonus
end

function XP.OnQuestTurnedIn(xpReward)
    if not session then return end
    session.quests = session.quests + 1
    xpReward = tonumber(xpReward) or 0
    if xpReward > 0 then
        session.questXP = session.questXP + xpReward
        Push(history.quests, xpReward)
        history.lastQuest = xpReward
    end
end

-- ---------------------------------------------------------------------------
-- Estimates
-- ---------------------------------------------------------------------------

local function MaxLevel()
    if GetMaxPlayerLevel then return GetMaxPlayerLevel() end
    return 70
end

-- Rested doubles kill XP until it runs out, so it covers at most half of
-- what is left: those kills land at twice the base value
function XP.KillsToLevel(remaining, rested, base)
    if not base or base <= 0 or remaining <= 0 then return nil end
    local bonus = math.min(rested or 0, remaining / 2)
    return math.ceil((remaining - bonus) / base)
end

function XP.Snapshot(now)
    local s = {}
    s.level = UnitLevel("player") or 1
    s.maxLevel = MaxLevel()
    s.disabled = IsXPUserDisabled and IsXPUserDisabled() or false
    s.capped = s.level >= s.maxLevel
    s.xp, s.max = UnitXP("player") or 0, UnitXPMax("player") or 0
    s.remaining = math.max(s.max - s.xp, 0)
    s.pct = s.max > 0 and s.xp / s.max * 100 or 0
    s.remainingPct = s.max > 0 and s.remaining / s.max * 100 or 0
    s.bubbles = s.max > 0 and s.xp / s.max * BUBBLES or 0

    s.rested = GetXPExhaustion and GetXPExhaustion() or 0
    s.restedPct = s.max > 0 and s.rested / s.max * 100 or 0
    s.resting = IsResting and IsResting() or false
    local cap = s.max * RESTED_CAP
    if s.resting and s.max > 0 and s.rested < cap then
        s.restedFullIn = (cap - s.rested) / (s.max * REST_RATE)
    end
    if s.rested > 0 and s.max > 0 then
        -- Where the rested marker sits: past this level it spills into the next
        local mark = s.xp + s.rested
        if mark >= s.max then
            s.restedEndLevel, s.restedEndPct = s.level + 1, (mark - s.max) / s.max * 100
        else
            s.restedEndLevel, s.restedEndPct = s.level, mark / s.max * 100
        end
    end

    if session then
        s.elapsed = math.max(now - session.start, 0)
        s.gained, s.levelsGained = session.gained, session.levels
        s.sessionKills, s.sessionKillXP = session.kills, session.killXP
        s.sessionQuests, s.sessionQuestXP = session.quests, session.questXP
        s.sessionOtherXP = math.max(session.gained - session.killXP - session.questXP, 0)
        if s.elapsed >= MIN_PACE_SECONDS and s.gained > 0 then
            local rate = s.gained / s.elapsed
            s.perHour = rate * 3600
            if s.remaining > 0 then s.timeToLevel = s.remaining / rate end
        end
    end

    if history then
        s.avgKill = Average(history.kills)
        s.killSamples = #history.kills
        s.lastKill = history.lastKill
        s.killsToLevel = XP.KillsToLevel(s.remaining, s.rested, s.avgKill)
        if s.avgKill and s.avgKill > 0 and s.rested > 0 then
            s.restedKills = math.ceil(s.rested / s.avgKill)
        end
        s.avgQuest = Average(history.quests)
        s.questSamples = #history.quests
        s.lastQuest = history.lastQuest
        if s.avgQuest and s.avgQuest > 0 and s.remaining > 0 then
            s.questsToLevel = math.ceil(s.remaining / s.avgQuest)
        end
    end
    return s
end

-- ---------------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------------

function XP.Number(n)
    n = math.floor((n or 0) + 0.5)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    local s = tostring(n)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

function XP.Short(n)
    n = n or 0
    if n >= 1e6 then return string.format("%.1fm", n / 1e6) end
    if n >= 1e4 then return string.format("%.0fk", n / 1e3) end
    if n >= 1e3 then return string.format("%.1fk", n / 1e3) end
    return tostring(math.floor(n + 0.5))
end

function XP.Duration(seconds)
    if not seconds then return nil end
    seconds = math.floor(seconds + 0.5)
    if seconds < 60 then return "<1m" end
    local d = math.floor(seconds / 86400)
    local h = math.floor(seconds % 86400 / 3600)
    local m = math.floor(seconds % 3600 / 60)
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %02dm", h, m) end
    return string.format("%dm", m)
end

-- Fits the 30px button: "43m", "5h", "2d"
function XP.ShortDuration(seconds)
    if not seconds then return "--" end
    if seconds < 3600 then return math.max(math.floor(seconds / 60), 1) .. "m" end
    if seconds < 86400 then return math.floor(seconds / 3600) .. "h" end
    return math.floor(seconds / 86400) .. "d"
end

-- One chat-ready line; the player sends it, nothing is sent for them
function XP.ChatLine(s)
    if s.capped then
        return string.format("Level %d (max level)", s.level)
    end
    local parts = {
        string.format("Level %d: %.1f%% (%s XP to go)", s.level, s.pct, XP.Number(s.remaining)),
    }
    if s.rested > 0 then
        parts[#parts + 1] = string.format("%.0f%% rested", s.restedPct)
    end
    if s.perHour then
        parts[#parts + 1] = string.format("%s XP/h, level in %s", XP.Number(s.perHour), XP.Duration(s.timeToLevel))
    end
    if s.killsToLevel then
        parts[#parts + 1] = string.format("~%d kills to go", s.killsToLevel)
    end
    return table.concat(parts, ", ") -- a bare pipe is an escape in chat
end
