-- Commander Momentum: a decaying kill-streak meter. Killing blows (CLEU
-- PARTY_KILL with the player as source) push the streak up and refill the
-- drain bar; when the bar empties the streak is gone. Colors escalate at
-- milestones. Shown only while a streak of 2+ is alive, so the HUD stays
-- clean between pulls. Best chains persist per zone/instance, and the end
-- of a session-best chain recaps how it stacks against those records.

local BAR_WIDTH = 120
local BAR_HEIGHT = 8

local streak = 0
local lastKill = -math.huge
local announcedMilestone = 0
local totalKills = 0        -- session-wide, for the milestone brags
local bestStreak = 0
local streakStart = 0       -- GetTime when the current streak began
local testFeeding = false   -- the tester never sends public emotes
local streakIsTest = false  -- chain fed only by the tester: no break lament
local session   -- reload-resilient mirror of the state above

-- Chain record bookkeeping: which zone the live chain is scoring in and
-- what the records were before it started, so the end-of-chain recap can
-- tell "broke the record" from "the record stands".
local chainZone            -- zone/instance name of the chain's latest kill
local chainZoneBase = 0    -- that zone's record before this chain touched it
local chainAllTimeBase = 0 -- the all-time high before this chain began
local chainAllTimeBaseZone -- ...and the zone that held it
local chainBasesCaptured = false

local function SyncSession()
    if session then
        session.streak = streak
        session.milestone = announcedMilestone
        session.lastKillEpoch = (streak > 0) and time() or 0
        session.totalKills = totalKills
        session.bestStreak = bestStreak
        session.streakStartEpoch = (streak > 0)
            and (time() - math.floor(GetTime() - streakStart)) or 0
        session.chainZone = chainZone or false
        session.chainZoneBase = chainZoneBase
        session.chainAllTimeBase = chainAllTimeBase
        session.chainAllTimeBaseZone = chainAllTimeBaseZone or false
        session.chainBasesCaptured = chainBasesCaptured
    end
end

-- ---------------------------------------------------------------------------
-- Zone records: the best chain ever landed in each zone or instance, kept
-- in CommanderMomentumDB.Records — deliberately outside DefaultSettings so
-- a settings reset never erases history. Written live on each kill (a
-- crash can't eat a record); the celebration waits for the chain to end.
-- ---------------------------------------------------------------------------

local function Records()
    if not CommanderMomentumDB.Records then
        CommanderMomentumDB.Records = {}
    end
    return CommanderMomentumDB.Records
end

-- Instances score under their instance name; the open world under the zone
-- the player is standing in (GetInstanceInfo only knows the continent there)
local function RecordZoneName()
    local name, instanceType = GetInstanceInfo()
    if instanceType and instanceType ~= "none" and name and name ~= "" then
        return name
    end
    local zone = GetRealZoneText()
    if zone and zone ~= "" then
        return zone
    end
    return name or "Parts Unknown"
end

local function ZoneBest(zone)
    local rec = zone and CommanderMomentumDB.Records
        and CommanderMomentumDB.Records[zone]
    return (rec and tonumber(rec.best)) or 0
end

-- Highest recorded chain across every zone; ties go to whoever held it first
local function AllTimeRecord()
    local best, zone, when = 0, nil, math.huge
    for name, rec in pairs(CommanderMomentumDB.Records or {}) do
        local b = tonumber(rec and rec.best) or 0
        local w = tonumber(rec and rec.when) or math.huge
        if b > best or (b == best and b > 0 and w < when) then
            best, zone, when = b, name, w
        end
    end
    return best, zone
end

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

-- ---------------------------------------------------------------------------
-- Player-portrait overlay mode: the streak lives on the default player
-- frame instead of a floating meter — a radial cooldown sweep over the
-- portrait counts down the momentum window, with the multiplier centered.
-- ---------------------------------------------------------------------------
local portraitOverlay, portraitCooldown, portraitText, portraitTint

local function DisplayMode()
    return (CommanderMomentumDB and CommanderMomentumDB.Display) or "HUD"
end

local function EnsurePortraitOverlay()
    if portraitOverlay then return true end
    local anchor = PlayerPortrait or PlayerFrame
    if not anchor then return false end
    portraitOverlay = CreateFrame("Frame", "CommanderMomentumPortrait", PlayerFrame or UIParent)
    if PlayerPortrait then
        portraitOverlay:SetAllPoints(PlayerPortrait)
    else
        portraitOverlay:SetSize(60, 60)
        portraitOverlay:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    end
    -- Circular tint over the portrait while a streak is alive: the round
    -- alpha-mask art used as a texture gives a clean disc, additive so the
    -- face glows in the streak's color instead of being painted over
    portraitTint = portraitOverlay:CreateTexture(nil, "ARTWORK")
    portraitTint:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    portraitTint:SetAllPoints(portraitOverlay)
    portraitTint:SetBlendMode("ADD")
    portraitTint:Hide()

    portraitCooldown = CreateFrame("Cooldown", nil, portraitOverlay, "CooldownFrameTemplate")
    -- Slightly larger than the portrait so the ring wraps its rim
    portraitCooldown:SetPoint("TOPLEFT", portraitOverlay, "TOPLEFT", -4, 4)
    portraitCooldown:SetPoint("BOTTOMRIGHT", portraitOverlay, "BOTTOMRIGHT", 4, -4)
    -- The swipe texture is a ring, so the radial sweep only ever draws
    -- ring pixels: a blue progress ring around the portrait instead of a
    -- dark wedge over the face. No client countdown numbers or edge line.
    if portraitCooldown.SetHideCountdownNumbers then
        portraitCooldown:SetHideCountdownNumbers(true)
    end
    if portraitCooldown.SetDrawEdge then
        portraitCooldown:SetDrawEdge(false)
    end
    if portraitCooldown.SetSwipeTexture then
        portraitCooldown:SetSwipeTexture("Interface\\AddOns\\Commander_Momentum\\Textures\\Ring")
        if portraitCooldown.SetSwipeColor then
            portraitCooldown:SetSwipeColor(0.25, 0.55, 1, 0.95)
        end
    elseif portraitCooldown.SetUseCircularEdge then
        -- Old-style fallback: at least clip the default wedge round
        portraitCooldown:SetUseCircularEdge(true)
    end
    -- Text must sit above the cooldown sweep, so it lives on its own
    -- higher-level frame
    local textHolder = CreateFrame("Frame", nil, portraitOverlay)
    textHolder:SetAllPoints(portraitOverlay)
    textHolder:SetFrameLevel((portraitCooldown:GetFrameLevel() or 1) + 2)
    portraitText = textHolder:CreateFontString(nil, "OVERLAY")
    portraitText:SetFontObject(GameFontNormalLarge)
    -- Outlined so the multiplier stays readable over the portrait art
    do
        local fontPath, fontSize = portraitText:GetFont()
        if fontPath then
            portraitText:SetFont(fontPath, fontSize or 16, "OUTLINE")
        end
    end
    portraitText:SetPoint("CENTER")
    portraitOverlay:Hide()
    return true
end

local function ClearPortraitCooldown()
    if not portraitCooldown then return end
    if portraitCooldown.Clear then
        portraitCooldown:Clear()
    else
        portraitCooldown:SetCooldown(0, 0)
    end
end

local function UpdatePortrait()
    if DisplayMode() ~= "PORTRAIT"
        or not (CommanderMomentumDB and CommanderMomentumDB.EnableMomentum) then
        if portraitOverlay then
            portraitOverlay:Hide()
            ClearPortraitCooldown()
        end
        return
    end
    if not EnsurePortraitOverlay() then return end
    local show = streak >= 2 or CommanderMomentumDB.AlwaysShow
    portraitOverlay:SetShown(show)
    if not show then
        ClearPortraitCooldown()
        return
    end
    local r, g, b = StreakColor()
    if streak < 2 then
        r, g, b = 0.6, 0.6, 0.6
    end
    portraitText:SetText(string.format("x%d", streak))
    portraitText:SetTextColor(r, g, b)
    -- Streak alive: glow the portrait in the streak's color, a touch
    -- stronger as the chain climbs
    if streak >= 2 then
        portraitTint:SetVertexColor(r, g, b, 0.18 + math.min(streak, 20) / 20 * 0.17)
        portraitTint:Show()
    else
        portraitTint:Hide()
    end
    local window = CommanderMomentumDB.Window or 20
    if streak >= 1 and (GetTime() - lastKill) < window then
        portraitCooldown:SetCooldown(lastKill, window)
    else
        ClearPortraitCooldown()
    end
end

-- Public lament when a real streak dies on the clock; only chains over
-- x10 are worth announcing, and only chains over x15 earn the audible
-- /cry sob (sent after the lament so the chat log reads in order)
local BREAK_LINES = {
    "loses momentum — the x%d chain is broken! (%s)",
    "watches a x%d streak slip away... (%s)",
}

local function EndStreak(announceBreak)
    local endedStreak = streak
    streak = 0
    announcedMilestone = 0
    local wasTestChain = streakIsTest
    streakIsTest = false
    local enabled = CommanderMomentumDB and CommanderMomentumDB.EnableMomentum
    -- Local record recap when a milestone-worthy chain ends: broken records
    -- always report; otherwise the session's best chain gets the standing —
    -- zone record and all-time high — as its epitaph. Record claims compare
    -- against pre-chain baselines and require the chain to actually hold the
    -- written record, so test-inflated chains can never take credit.
    local newAllTime = false
    if enabled and not wasTestChain and endedStreak >= 5 then
        local zone = chainZone or RecordZoneName()
        local zoneBest = ZoneBest(zone)
        local atBest, atZone = AllTimeRecord()
        -- A chain restored from a pre-records session never captured its
        -- baselines; treat the current records as the baseline (no claims)
        local zoneBase = chainBasesCaptured and chainZoneBase or zoneBest
        local atBase = chainBasesCaptured and chainAllTimeBase or atBest
        local atBaseZone = chainBasesCaptured and chainAllTimeBaseZone or atZone
        newAllTime = endedStreak == atBest and endedStreak > atBase
        local standing
        if newAllTime then
            if atBase >= 2 and atBaseZone then
                standing = string.format("NEW ALL-TIME HIGH in %s! (previous x%d — %s)",
                    zone, atBase, atBaseZone == zone and "set right here" or atBaseZone)
            else
                standing = string.format("a new all-time high — the record books open in %s", zone)
            end
        elseif endedStreak == zoneBest and endedStreak > zoneBase then
            if zoneBase >= 2 then
                standing = string.format("new record for %s (was x%d) — all-time high x%d (%s)",
                    zone, zoneBase, atBest, atZone)
            else
                standing = string.format("first record for %s — all-time high x%d (%s)",
                    zone, atBest, atZone)
            end
        elseif endedStreak == bestStreak and zoneBest >= 2 then
            if atZone == zone then
                standing = string.format("%s record x%d is the all-time high", zone, zoneBest)
            else
                standing = string.format("%s record x%d, all-time high x%d (%s)",
                    zone, zoneBest, atBest, atZone)
            end
        end
        if standing then
            print(string.format("|cffffb830Commander Momentum:|r %sx%d chain ends — %s",
                endedStreak == bestStreak and "session best " or "", endedStreak, standing))
        end
    end
    if announceBreak and not wasTestChain
        and enabled
        and CommanderMomentumDB.BreakEmotes
        and endedStreak > 10 then
        local atBest = AllTimeRecord()
        local stats = string.format("%d kills this session, best chain x%d",
            totalKills, bestStreak)
        if newAllTime then
            stats = string.format("%s, a NEW all-time high x%d", stats, atBest)
        elseif atBest >= 2 then
            stats = string.format("%s, all-time high x%d", stats, atBest)
        end
        SendChatMessage(string.format(BREAK_LINES[math.random(#BREAK_LINES)],
            endedStreak, stats), "EMOTE")
        if endedStreak > 15 then
            DoEmote("CRY")
        end
    end
    -- Chain bookkeeping dies with the chain; the next one recaptures fresh
    chainZone = nil
    chainZoneBase = 0
    chainAllTimeBase = 0
    chainAllTimeBaseZone = nil
    chainBasesCaptured = false
    SyncSession()
    local keepShown = CommanderMomentumDB and CommanderMomentumDB.EnableMomentum
        and DisplayMode() == "HUD"
        and (CommanderMomentumDB.AlwaysShow
            or Commander.UI.HudUnlocked(CommanderMomentumDB, "Hud"))
    root:SetShown(keepShown or false)
    root:SetScript("OnUpdate", nil)
    if keepShown then
        streakText:SetText("x0")
        streakText:SetTextColor(0.6, 0.6, 0.6)
        bar:SetSize(1, BAR_HEIGHT)
    end
    if portraitOverlay then
        portraitOverlay:SetScript("OnUpdate", nil)
        UpdatePortrait()
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
        -- The clock ran out on a live streak: the one true "broken" path
        EndStreak(true)
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

-- Public: current streak and seconds left on its window (nil remaining
-- when no live streak). Commander_Comms' auto charge rally reads this.
function CommanderMomentum_GetStreakInfo()
    if not (CommanderMomentumDB and CommanderMomentumDB.EnableMomentum) then
        return 0, nil
    end
    if streak < 2 then
        return streak, nil
    end
    local window = CommanderMomentumDB.Window or 20
    local remaining = (lastKill + window) - GetTime()
    if remaining <= 0 then
        return streak, nil
    end
    return streak, remaining
end

-- Public brag at each milestone: a flavor line escalating with the tier
-- plus the session's numbers, sent as a custom emote for everyone nearby
local FLAVOR_TIERS = {
    { min = 20, lines = { "erupts in TOTAL ANNIHILATION!", "is beyond containment!" } },
    { min = 15, lines = { "is absolutely unstoppable!", "has become the battlefield!" } },
    { min = 10, lines = { "is on a full rampage!", "carves through the enemy line!" } },
    { min = 0, lines = { "is heating up!", "builds deadly momentum!" } },
}

local function BuildBrag()
    local flavor
    for _, tier in ipairs(FLAVOR_TIERS) do
        if streak >= tier.min then
            flavor = tier.lines[math.random(#tier.lines)]
            break
        end
    end
    local pace = ""
    local elapsed = GetTime() - streakStart
    if elapsed > 10 then
        pace = string.format(", %.1f kills/min", streak / (elapsed / 60))
    end
    return string.format("%s (x%d chain%s — %d kills this session, best chain x%d)",
        flavor, streak, pace, totalKills, math.max(bestStreak, streak))
end

local warnedThisWindow = false

local function OnKill()
    -- Enforce the window even for streaks too small to show: without this,
    -- a streak of 1 never expires (no visible frame, no drain driver) and
    -- any two kills ever would chain into a bogus x2
    local window = CommanderMomentumDB.Window or 20
    if GetTime() - lastKill > window then
        streak = 0
        announcedMilestone = 0
        -- A chain of 1 dies silently (no EndStreak); scrub its bookkeeping
        -- here so the new chain recaptures fresh baselines
        chainZone = nil
        chainBasesCaptured = false
    end
    warnedThisWindow = false
    if streak == 0 then
        streakStart = GetTime()
    end
    streak = streak + 1
    if testFeeding then
        if streak <= 2 then streakIsTest = true end
    else
        streakIsTest = false
    end
    totalKills = totalKills + 1
    if streak > bestStreak then
        bestStreak = streak
    end
    lastKill = GetTime()
    -- Zone-record bookkeeping: baselines captured on the chain's first real
    -- kill (before this kill can move a record), then records written live.
    -- Test kills never touch the books.
    if not testFeeding then
        if not chainBasesCaptured then
            chainBasesCaptured = true
            chainAllTimeBase, chainAllTimeBaseZone = AllTimeRecord()
        end
        local zone = RecordZoneName()
        if zone ~= chainZone then
            chainZone = zone
            chainZoneBase = ZoneBest(zone)
        end
        if streak >= 2 and streak > ZoneBest(zone) then
            local rec = Records()[zone]
            if rec then
                rec.best, rec.when = streak, time()
            else
                Records()[zone] = { best = streak, when = time() }
            end
        end
    end
    SyncSession()
    if streak >= 2 then
        if DisplayMode() == "PORTRAIT" then
            -- The drain driver rides the overlay so window expiry still
            -- ends the streak while the floating meter stays hidden
            root:Hide()
            UpdatePortrait()
            if portraitOverlay then
                portraitOverlay:SetScript("OnUpdate", OnDrain)
            end
        else
            Refresh()
            Commander.UI.ApplyHudChrome(root, CommanderMomentumDB, "Hud", {
                defaultPoint = { point = "TOP", x = 0, y = -260 },
            })
            root:Show()
            root:SetScript("OnUpdate", OnDrain)
        end
    end
    if DisplayMode() == "PORTRAIT" then
        UpdatePortrait()
    end
    local milestone = math.floor(streak / 5) * 5
    if milestone >= 5 and milestone > announcedMilestone then
        announcedMilestone = milestone
        SyncSession()
        if CommanderMomentumDB.MilestoneSound then
            PlaySound(SOUNDKIT.READY_CHECK, "Master")
        end
        print(string.format("|cffffb830Commander Momentum:|r x%d streak", streak))
        if CommanderMomentumDB.MilestoneEmotes and not testFeeding then
            SendChatMessage(BuildBrag(), "EMOTE")
        end
    end
end

-- Standard suite report and tester
function CommanderMomentum_Report()
    local zone = RecordZoneName()
    local zoneBest = ZoneBest(zone)
    local atBest, atZone = AllTimeRecord()
    local standing
    if atBest < 2 then
        standing = "no zone records on the books yet"
    elseif zone == atZone then
        standing = string.format("%s record x%d is the all-time high", zone, zoneBest)
    elseif zoneBest >= 2 then
        standing = string.format("%s record x%d, all-time high x%d (%s)",
            zone, zoneBest, atBest, atZone)
    else
        standing = string.format("no record for %s yet — all-time high x%d (%s)",
            zone, atBest, atZone)
    end
    print(string.format(
        "Commander Momentum: %d kill%s this session, best chain x%d%s — %s",
        totalKills, totalKills == 1 and "" or "s", bestStreak,
        streak >= 2 and string.format(" (live streak x%d)", streak) or "",
        standing))
end

-- The record books: every zone's best chain, top score first
function CommanderMomentum_Records()
    local list = {}
    for name, rec in pairs(CommanderMomentumDB.Records or {}) do
        local best = tonumber(rec and rec.best) or 0
        if best >= 2 then
            list[#list + 1] = { zone = name, best = best, when = tonumber(rec.when) }
        end
    end
    if #list == 0 then
        print("Commander Momentum: no zone records yet — chain two kills somewhere and the books open")
        return
    end
    table.sort(list, function(a, b)
        if a.best ~= b.best then return a.best > b.best end
        return (a.when or math.huge) < (b.when or math.huge)
    end)
    print(string.format("|cffffb830Commander Momentum:|r zone records (%d zone%s)",
        #list, #list == 1 and "" or "s"))
    local shown = math.min(#list, 15)
    for i = 1, shown do
        local entry = list[i]
        print(string.format("  x%d — %s%s%s",
            entry.best, entry.zone,
            entry.when and date(" (%m/%d/%y)", entry.when) or "",
            i == 1 and " |cffffb830— all-time high|r" or ""))
    end
    if #list > shown then
        print(string.format("  ...and %d more", #list - shown))
    end
end

function CommanderMomentum_Test()
    if not (CommanderMomentumDB and CommanderMomentumDB.EnableMomentum) then
        print("Commander Momentum: module is disabled (enable it in settings or /cmom)")
        return
    end
    -- Feed two kills through the real pipeline so the live display and
    -- drain are genuine, but keep session stats and public emotes clean
    local savedKills, savedBest = totalKills, bestStreak
    testFeeding = true
    OnKill()
    OnKill()
    testFeeding = false
    totalKills, bestStreak = savedKills, savedBest
    SyncSession()
    print(string.format("Commander Momentum: test kills fed — live x%d streak, watch it drain", streak))
end

local function Apply()
    if not (CommanderMomentumDB and CommanderMomentumDB.EnableMomentum) then
        EndStreak()
        root:Hide()
        return
    end
    UpdatePortrait()
    if DisplayMode() == "PORTRAIT" then
        -- Portrait mode owns the display; keep the floating meter down but
        -- move its drain driver to the overlay if a streak is live
        root:Hide()
        root:SetScript("OnUpdate", nil)
        if streak >= 2 and portraitOverlay then
            portraitOverlay:SetScript("OnUpdate", OnDrain)
        end
        return
    end
    if portraitOverlay then
        portraitOverlay:SetScript("OnUpdate", nil)
    end
    if streak >= 2 then
        root:SetScript("OnUpdate", OnDrain)
    end
    local unlocked = Commander.UI.HudUnlocked(CommanderMomentumDB, "Hud")
    -- Visibility derives from state, never from the sticky IsShown():
    -- re-locking or turning Always Show off must actually hide an idle meter
    local shouldShow = streak >= 2 or unlocked or CommanderMomentumDB.AlwaysShow
    if shouldShow then
        Commander.UI.ApplyHudChrome(root, CommanderMomentumDB, "Hud", {
            title = "Momentum",
            defaultPoint = { point = "TOP", x = 0, y = -260 },
        })
        root:Show()
        Refresh()
        if streak < 2 then
            streakText:SetText(string.format("x%d", streak))
            streakText:SetTextColor(0.6, 0.6, 0.6)
            bar:SetSize(unlocked and BAR_WIDTH or 1, BAR_HEIGHT)
        end
    else
        root:Hide()
    end
end

-- Display-independent watchdog: streak expiry and the near-break warning
-- must fire even when no meter frame happens to be visible — game logic
-- can never ride an OnUpdate driver alone. The frame drivers still handle
-- the smooth bar drain; this catches what they miss.
C_Timer.NewTicker(1, function()
    if not (CommanderMomentumDB and CommanderMomentumDB.EnableMomentum) then return end
    if streak < 2 then return end
    local window = CommanderMomentumDB.Window or 20
    local remaining = (lastKill + window) - GetTime()
    if remaining <= 0 then
        EndStreak(true)
        return
    end
    -- Local heads-up before the chain dies (the public Charge rally is
    -- Commander_Comms' Auto Charge Rally option)
    if CommanderMomentumDB.BreakWarning and not warnedThisWindow and remaining <= 5 then
        warnedThisWindow = true
        PlaySound(SOUNDKIT.READY_CHECK, "Master")
        print(string.format("|cffff4030Commander Momentum:|r x%d streak breaking in %d seconds!",
            streak, math.ceil(remaining)))
        local flashRed = function(text)
            if text then text:SetTextColor(1, 0.25, 0.2) end
        end
        flashRed(streakText)
        flashRed(portraitText)
    end
end)

-- Session resets: the momentum "session" is a fighting stretch, not the
-- whole login — death ends it, and so does a loading-screen transition
-- (instance entry/exit, continent change). Zone identity is tracked in
-- the persisted session, so a /reload in place never counts as a change.
local function ResetSessionStats()
    totalKills, bestStreak = 0, 0
    SyncSession()
end

local function CurrentZoneKey()
    local _, instanceType, _, _, _, _, _, instanceMapID = GetInstanceInfo()
    return tostring(instanceType or "none") .. ":" .. tostring(instanceMapID or 0)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_DEAD")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- A /reload must not eat a live streak: restore it with the kill
        -- clock converted from epoch back into GetTime's domain
        local fresh
        session, fresh = Commander.RestoreSession(CommanderMomentumDB, {
            streak = 0, milestone = 0, lastKillEpoch = 0,
            totalKills = 0, bestStreak = 0, streakStartEpoch = 0,
            zoneKey = false,
            chainZone = false, chainZoneBase = 0,
            chainAllTimeBase = 0, chainAllTimeBaseZone = false,
            chainBasesCaptured = false,
        })
        totalKills = session.totalKills or 0
        bestStreak = session.bestStreak or 0
        if not fresh and session.streak > 0 and session.lastKillEpoch > 0 then
            streak = session.streak
            announcedMilestone = session.milestone
            lastKill = GetTime() - math.max(time() - session.lastKillEpoch, 0)
            if session.streakStartEpoch > 0 then
                streakStart = GetTime() - math.max(time() - session.streakStartEpoch, 0)
            end
            -- Record bookkeeping rides along so a /reload mid-chain still
            -- knows what the chain has to beat
            chainZone = session.chainZone or nil
            chainZoneBase = session.chainZoneBase or 0
            chainAllTimeBase = session.chainAllTimeBase or 0
            chainAllTimeBaseZone = session.chainAllTimeBaseZone or nil
            chainBasesCaptured = session.chainBasesCaptured or false
        end
        Commander.AddListener(COMMANDER_MOMENTUM_EVENTS.UPDATE, Apply)
        -- Nothing notifies at startup: Always Show / unlocked-at-reload
        -- need an initial apply or the frame stays invisible until a
        -- streak or a settings touch
        Apply()
        return
    end
    if not (CommanderMomentumDB and CommanderMomentumDB.EnableMomentum) then return end
    if event == "PLAYER_DEAD" then
        if CommanderMomentumDB.ResetOnDeath then
            -- Dying breaks the chain (lament rules apply) and zeroes the
            -- session numbers: the next fight starts a fresh story
            EndStreak(true)
            ResetSessionStats()
        end
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        if session then
            local key = CurrentZoneKey()
            if CommanderMomentumDB.ResetOnZone and session.zoneKey and session.zoneKey ~= key then
                -- The loading screen already broke the flow; end quietly
                EndStreak()
                ResetSessionStats()
            end
            session.zoneKey = key
        end
        return
    end
    local _, subevent, _, sourceGUID, _, _, _, _, _, destFlags = CombatLogGetCurrentEventInfo()
    if CommanderMomentumDB.KillSource == "SQUAD" then
        -- Any hostile NPC death nearby feeds the meter — momentum for
        -- healers and tanks, not just whoever lands the killing blow.
        -- Pets, guardians, and totems die noisily but are not kills.
        if subevent == "UNIT_DIED" and destFlags
            and bit.band(destFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) > 0
            and bit.band(destFlags, COMBATLOG_OBJECT_CONTROL_NPC) > 0
            and bit.band(destFlags, (COMBATLOG_OBJECT_TYPE_PET or 0x1000)
                + (COMBATLOG_OBJECT_TYPE_GUARDIAN or 0x2000)) == 0 then
            OnKill()
        end
    elseif subevent == "PARTY_KILL" and sourceGUID == UnitGUID("player") then
        OnKill()
    end
end)
