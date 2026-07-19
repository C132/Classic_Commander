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
local totalKills = 0        -- session-wide, for the milestone brags
local bestStreak = 0
local streakStart = 0       -- GetTime when the current streak began
local session   -- reload-resilient mirror of the state above

local function SyncSession()
    if session then
        session.streak = streak
        session.milestone = announcedMilestone
        session.lastKillEpoch = (streak > 0) and time() or 0
        session.totalKills = totalKills
        session.bestStreak = bestStreak
        session.streakStartEpoch = (streak > 0)
            and (time() - math.floor(GetTime() - streakStart)) or 0
    end
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
local portraitOverlay, portraitCooldown, portraitText

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
    local window = CommanderMomentumDB.Window or 20
    if streak >= 1 and (GetTime() - lastKill) < window then
        portraitCooldown:SetCooldown(lastKill, window)
    else
        ClearPortraitCooldown()
    end
end

local function EndStreak()
    streak = 0
    announcedMilestone = 0
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

local function OnKill()
    -- Enforce the window even for streaks too small to show: without this,
    -- a streak of 1 never expires (no visible frame, no drain driver) and
    -- any two kills ever would chain into a bogus x2
    local window = CommanderMomentumDB.Window or 20
    if GetTime() - lastKill > window then
        streak = 0
        announcedMilestone = 0
    end
    if streak == 0 then
        streakStart = GetTime()
    end
    streak = streak + 1
    totalKills = totalKills + 1
    if streak > bestStreak then
        bestStreak = streak
    end
    lastKill = GetTime()
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
        if CommanderMomentumDB.MilestoneEmotes then
            SendChatMessage(BuildBrag(), "EMOTE")
        end
    end
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

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- A /reload must not eat a live streak: restore it with the kill
        -- clock converted from epoch back into GetTime's domain
        local fresh
        session, fresh = Commander.RestoreSession(CommanderMomentumDB, {
            streak = 0, milestone = 0, lastKillEpoch = 0,
            totalKills = 0, bestStreak = 0, streakStartEpoch = 0,
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
        end
        Commander.AddListener(COMMANDER_MOMENTUM_EVENTS.UPDATE, Apply)
        -- Nothing notifies at startup: Always Show / unlocked-at-reload
        -- need an initial apply or the frame stays invisible until a
        -- streak or a settings touch
        Apply()
        return
    end
    if not (CommanderMomentumDB and CommanderMomentumDB.EnableMomentum) then return end
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
