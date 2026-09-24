-- Commander Adjutant: RTS-style battle announcer. Shows a top-center banner
-- (and optionally a stock alert sound) for commander-relevant events. Every
-- alert is throttled so the adjutant informs rather than nags: attacks only
-- after a stretch of peace, critical damage once per fight, repair/storage
-- once per threshold crossing.

local BANNER_HOLD = 3.0
local BANNER_FADE_STEP = 0.06
local UNDER_ATTACK_COOLDOWN = 30

-- All keys verified against this client's SOUNDKIT table
local ALERT_SOUNDS = {
    UNDER_ATTACK = "RAID_WARNING",
    LOW_HEALTH = "RAID_BOSS_EMOTE_WARNING",
    REPAIR = "IG_CHARACTER_INFO_TAB",
    BAGS_FULL = "IG_CHARACTER_INFO_TAB",
    LEVEL_UP = "IG_QUEST_LIST_COMPLETE",
    REINFORCEMENTS = "READY_CHECK",
    QUEUE_CLOSING = "RAID_WARNING",
    -- QUEUE_POP deliberately has no entry: the client already plays its own
    -- sound when a battleground invite arrives, and stacking a second one on
    -- top of it is noise, not an alert
}

-- ---------------------------------------------------------------------------
-- Banner
-- ---------------------------------------------------------------------------
local banner = CreateFrame("Frame", "CommanderAdjutantBanner", UIParent)
banner:SetSize(600, 40)
banner:SetPoint("TOP", UIParent, "TOP", 0, -140)
banner:SetFrameStrata("HIGH")
banner:Hide()

local bannerText = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
bannerText:SetPoint("CENTER")
bannerText:SetTextColor(1, 0.85, 0.2)

local fadeTicker
local bannerGeneration = 0

local function StopFade()
    if fadeTicker then
        fadeTicker:Cancel()
        fadeTicker = nil
    end
end

local function ShowBanner(text, r, g, b)
    StopFade()
    -- Generation token invalidates hold callbacks from earlier banners:
    -- without it, banner A's uncancellable After() would start fading
    -- banner B partway through B's own hold
    bannerGeneration = bannerGeneration + 1
    local generation = bannerGeneration
    bannerText:SetText(text)
    bannerText:SetTextColor(r or 1, g or 0.85, b or 0.2)
    banner:SetAlpha(1)
    banner:Show()
    C_Timer.After(BANNER_HOLD, function()
        if generation ~= bannerGeneration then return end
        StopFade()
        fadeTicker = C_Timer.NewTicker(0.05, function()
            local alpha = banner:GetAlpha() - BANNER_FADE_STEP
            if alpha <= 0 then
                banner:Hide()
                banner:SetAlpha(1)
                StopFade()
            else
                banner:SetAlpha(alpha)
            end
        end)
    end)
end

local function Announce(alertKey, text, r, g, b)
    if not CommanderAdjutantDB.EnableAdjutant then return end
    ShowBanner(text, r, g, b)
    if CommanderAdjutantDB.PlaySounds then
        local soundKit = SOUNDKIT[ALERT_SOUNDS[alertKey] or ""]
        if soundKit then
            PlaySound(soundKit, "Master")
        end
    end
end

-- Shared with the settings panel's /cadj test subcommand
function CommanderAdjutant_TestAlert()
    Announce("UNDER_ATTACK", "Our forces are under attack!", 1, 0.3, 0.2)
end

-- ---------------------------------------------------------------------------
-- Alert state and triggers
-- ---------------------------------------------------------------------------
local lastCombatEnd = 0
local lowHealthAnnounced = false
local repairAnnounced = false
local bagsFullAnnounced = false
local lastGroupSize = 0
local lastReinforcement = 0
local loginTime = 0
local REINFORCEMENT_COOLDOWN = 30
local LOGIN_GRACE = 10

local function GroupSize()
    return (GetNumGroupMembers and GetNumGroupMembers()) or 0
end

local function CheckLowHealth()
    if not CommanderAdjutantDB.AlertLowHealth then return end
    local health, maxHealth = UnitHealth("player"), UnitHealthMax("player")
    if maxHealth <= 0 then return end
    local ratio = health / maxHealth
    -- Hysteresis: re-arm only after recovering comfortably above the
    -- threshold, so a fight that ENDS below 25% can't re-announce on the
    -- first out-of-combat regen tick
    if lowHealthAnnounced then
        if ratio >= 0.35 then
            lowHealthAnnounced = false
        end
        return
    end
    if ratio < 0.25 and health > 0 then
        lowHealthAnnounced = true
        Announce("LOW_HEALTH", "We're taking critical damage!", 1, 0.2, 0.2)
    end
end

local function CheckDurability()
    if not CommanderAdjutantDB.AlertRepair then return end
    local lowest = 1
    for slot = 1, 18 do
        local current, maximum = GetInventoryItemDurability(slot)
        if current and maximum and maximum > 0 then
            local ratio = current / maximum
            if ratio < lowest then lowest = ratio end
        end
    end
    if lowest < 0.2 then
        if not repairAnnounced then
            repairAnnounced = true
            Announce("REPAIR", "Units require repair", 1, 0.85, 0.2)
        end
    else
        repairAnnounced = false
    end
end

local function CheckBags()
    if not CommanderAdjutantDB.AlertBagsFull then return end
    local free = 0
    for bagID = 0, 4 do
        if (C_Container.GetContainerNumSlots(bagID) or 0) > 0 then
            free = free + (C_Container.GetContainerNumFreeSlots(bagID) or 0)
        end
    end
    if free == 0 then
        if not bagsFullAnnounced then
            bagsFullAnnounced = true
            Announce("BAGS_FULL", "Storage at full capacity", 1, 0.85, 0.2)
        end
    else
        bagsFullAnnounced = false
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterUnitEvent("UNIT_HEALTH", "player")
events:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
local loaded = false

events:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        lastGroupSize = GroupSize()
        lastCombatEnd = 0
        loginTime = GetTime()
        loaded = true
        return
    end
    if not loaded or not CommanderAdjutantDB.EnableAdjutant then return end

    if event == "PLAYER_REGEN_DISABLED" then
        -- A fresh engagement, not chained pulls: announce only after peace
        if CommanderAdjutantDB.AlertUnderAttack and (GetTime() - lastCombatEnd) > UNDER_ATTACK_COOLDOWN then
            Announce("UNDER_ATTACK", "Our forces are under attack!", 1, 0.3, 0.2)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        lastCombatEnd = GetTime()
        -- lowHealthAnnounced deliberately NOT cleared here; CheckLowHealth's
        -- hysteresis re-arms it once health recovers above 35%
    elseif event == "UNIT_HEALTH" then
        CheckLowHealth()
    elseif event == "UPDATE_INVENTORY_DURABILITY" then
        CheckDurability()
    elseif event == "BAG_UPDATE_DELAYED" then
        CheckBags()
    elseif event == "PLAYER_LEVEL_UP" then
        if CommanderAdjutantDB.AlertLevelUp then
            Announce("LEVEL_UP", "Upgrade complete", 0.3, 1, 0.4)
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        local size = GroupSize()
        -- Throttled (one announce per 30s window) so a filling battleground
        -- or raid announces once, not once per joiner — and never during
        -- the first seconds after login, when the roster is still settling
        if CommanderAdjutantDB.AlertReinforcements and size > lastGroupSize and size > 1
            and (GetTime() - loginTime) > LOGIN_GRACE
            and (GetTime() - lastReinforcement) > REINFORCEMENT_COOLDOWN then
            lastReinforcement = GetTime()
            Announce("REINFORCEMENTS", "Reinforcements have arrived", 0.4, 0.8, 1)
        end
        lastGroupSize = size
    end
end)

-- ---------------------------------------------------------------------------
-- Deployment countdown
--
-- The battleground invite hands you two buttons and no clock. The client
-- knows exactly how long the port stays open -- GetBattlefieldPortExpiration
-- reports it -- but the only place that number ever surfaces is the minimap
-- battlefield icon, and only inside the last ten seconds. So: a draining bar
-- under the invite saying how long you can keep doing what you were doing,
-- one that SURVIVES the Hide button (Hide is what you press when you want to
-- finish something first, which is exactly when you need the clock), and a
-- warning shout before the window shuts.
--
-- On this client the invite is PVPReadyDialog (Blizzard_GroupFinder's
-- PVPHelper.lua, loaded for tbc). CONFIRM_BATTLEFIELD_ENTRY is still defined
-- as a static popup here too, so whichever one is up gets the bar.
--
-- This half owns its own event frame rather than joining the announcer's:
-- the pop banner and the countdown answer to different switches, and the
-- queue slots have to be scanned even when the countdown is turned off.
-- ---------------------------------------------------------------------------

local QUEUE_TICK = 0.1
local BAR_HEIGHT = 26
local FLOAT_WIDTH = 190
local DEMO_LENGTH = 20
-- Only reached when the client will not report an expiration at all. TBC's
-- invite window is 80 seconds; a bar drawn against the wrong span is still
-- better than a dialog with no clock on it.
local FALLBACK_WINDOW = 80

local pendingPorts = {}   -- battlefield index -> { mapName, span, started, left, warned }
local demoPort            -- the same shape, driven by /cadj timer
local attachBar, floatBar
local floatChromed = false

local function QueueSlots()
    return (GetMaxBattlefieldID and GetMaxBattlefieldID()) or MAX_BATTLEFIELD_QUEUES or 3
end

local function PortSeconds(index)
    if type(GetBattlefieldPortExpiration) ~= "function" then return nil end
    local seconds = GetBattlefieldPortExpiration(index)
    if type(seconds) ~= "number" or seconds <= 0 then return nil end
    -- Blizzard's own battlefield timer reads this as seconds. Anything that
    -- large can only be milliseconds, and a twenty-hour countdown on a
    -- minute-and-a-bit window helps nobody
    if seconds > 3600 then seconds = seconds / 1000 end
    return seconds
end

-- Keeps pendingPorts in step with the client's queue slots and returns the
-- port closing soonest, or nil. Announcing the pop lives here because this is
-- the one place a new invite is first seen, whether or not the bar is on.
local function ScanPorts()
    local now = GetTime()
    local soonest
    for index = 1, QueueSlots() do
        local status, mapName = GetBattlefieldStatus(index)
        if status == "confirm" then
            local reported = PortSeconds(index)
            local state = pendingPorts[index]
            if not state then
                -- span is the window this bar drains across: whatever the
                -- first sighting reported, so an invite picked up late (a
                -- /reload mid-pop) drains from where it was found instead of
                -- pretending to be full
                state = { index = index, started = now, span = reported or FALLBACK_WINDOW }
                pendingPorts[index] = state
                if CommanderAdjutantDB.AlertQueuePop and (now - loginTime) > LOGIN_GRACE then
                    Announce("QUEUE_POP", string.format("Transport ready: %s", mapName or "the front"),
                        0.4, 0.8, 1)
                end
            end
            state.mapName = mapName
            if reported then
                state.left = reported
                state.reported = true
                if reported > state.span then state.span = reported end
            elseif state.reported then
                -- It was reporting a moment ago and now reports nothing: that
                -- is a closed window, not a reason to fall back to a clock of
                -- our own and jump the number back up
                state.left = 0
            else
                state.left = math.max(state.span - (now - state.started), 0)
            end
            -- A window that has run out stops being drawn but KEEPS its entry:
            -- dropping it here would have the next scan read the same slot as a
            -- brand new invite and announce the pop all over again
            if state.left > 0 and (not soonest or state.left < soonest.left) then
                soonest = state
            end
        else
            pendingPorts[index] = nil
        end
    end
    return soonest
end

-- ---------------------------------------------------------------------------
-- The bar
-- ---------------------------------------------------------------------------

local function BuildBar(name, strata)
    local bar = CreateFrame("Frame", name, UIParent)
    bar:SetSize(FLOAT_WIDTH, BAR_HEIGHT)
    bar:SetFrameStrata(strata)
    bar:Hide()

    local track = bar:CreateTexture(nil, "ARTWORK")
    track:SetColorTexture(1, 1, 1, 0.12)
    track:SetHeight(3)
    track:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 6, 5)
    track:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -6, 5)

    local fill = bar:CreateTexture(nil, "OVERLAY")
    fill:SetHeight(3)
    fill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 0, 0)

    local text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOP", bar, "TOP", 0, -5)

    bar.track, bar.fill, bar.text = track, fill, text
    return bar
end

local function PaintBar(bar, label, left, span)
    local warnAt = CommanderAdjutantDB.QueueTimerWarning or 0
    -- Ceiling, so the bar reads 0:00 only when the port really is gone
    local seconds = math.max(math.ceil(left or 0), 0)
    local r, g, b = 1, 0.85, 0.2
    -- span 0 is the parked placeholder an unlocked frame draws so it can be
    -- dragged; that one is not an invite running out, so it stays amber
    if warnAt > 0 and span and span > 0 and seconds <= warnAt then
        r, g, b = 1, 0.3, 0.2
    end
    bar.text:SetText(string.format("%s  %d:%02d", label, math.floor(seconds / 60), seconds % 60))
    bar.text:SetTextColor(r, g, b)
    bar.fill:SetColorTexture(r, g, b, 0.9)
    local usable = math.max((bar:GetWidth() or 0) - 12, 1)
    local fraction = 0
    if span and span > 0 then
        fraction = math.min(math.max((left or 0) / span, 0), 1)
    end
    bar.fill:SetWidth(math.max(usable * fraction, 1))
end

-- Point the secure click at Blizzard's Enter button. A secure attribute
-- cannot be written in combat, so a port that arrives mid-fight waits for
-- the lockdown to lift; the dialog itself is loaded with the UI, so the
-- target is normally there the first time this runs.
local enterWired = false

local function WireEnterButton()
    if enterWired or not (floatBar and floatBar.enter) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local dialog = _G.PVPReadyDialog
    local button = dialog and (dialog.enterButton or _G.PVPReadyDialogEnterBattleButton)
    if not button then return end
    floatBar.enter:SetAttribute("clickbutton1", button)
    enterWired = true
end

local function EnsureBars()
    if attachBar then return end
    -- Above the invite it hangs off, whatever strata that dialog claims
    attachBar = BuildBar("CommanderAdjutantPortBar", "FULLSCREEN_DIALOG")
    Commander.UI.ApplyStyleBackdrop(attachBar, "DARK")

    floatBar = BuildBar("CommanderAdjutantQueueTimer", "HIGH")
    Commander.UI.ApplyStyleBackdrop(floatBar, "DARK")

    -- The click surface is a CHILD, not the frame itself: HUD chrome passes
    -- left-clicks straight through a locked frame (so a parked HUD never eats
    -- a click meant for the world), which would make a clickable locked
    -- timer impossible. A child is not passed through.
    --
    -- And it is a SECURE button. AcceptBattlefieldPort is protected on this
    -- client -- calling it from addon code is an ADDON_ACTION_FORBIDDEN, not
    -- a port -- so the only way in is the way Blizzard's own dialog goes:
    -- this button's secure "click" action presses PVPReadyDialog's real
    -- Enter button, whose XML OnClick makes the protected call from secure
    -- code. That button keeps working after the dialog is hidden (its
    -- activeIndex survives the hide; only battlefieldIndex is cleared), which
    -- is exactly the case the floating timer exists for.
    local enter = CreateFrame("Button", "CommanderAdjutantEnterButton", floatBar,
        "SecureActionButtonTemplate")
    enter:SetAllPoints(floatBar)
    -- Both phases, or the click no-ops under the cast-on-key-down CVar
    enter:RegisterForClicks("AnyDown", "AnyUp")
    enter:SetAttribute("type1", "click")
    enter:HookScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            -- Hand right-clicks back to the chrome so its triple-right-click
            -- unlock still works through the button covering the frame
            local handler = floatBar:GetScript("OnMouseUp")
            if handler then handler(floatBar, mouseButton) end
        end
    end)
    enter:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Deployment")
        GameTooltip:AddLine("Time left on your battleground invite.", 1, 1, 1)
        GameTooltip:AddLine("Click to enter battle.", 0.4, 0.8, 1)
        GameTooltip:Show()
    end)
    enter:SetScript("OnLeave", function() GameTooltip:Hide() end)
    floatBar.enter = enter
    WireEnterButton()
end

-- The floating timer PARENTS a secure button (the click that enters the
-- battle), which makes it a protected frame: in combat the client refuses
-- to show, hide, move or resize it (ADDON_ACTION_BLOCKED, fourteen of them
-- in one battleground, 2026-09-23). The countdown keeps running through a
-- fight, so in combat the timer is never shown or hidden: a hide is carried
-- by its alpha (allowed on a protected frame), a show by the plain attach bar
-- standing in on the same spot, and the real state is put right the moment
-- combat ends (PLAYER_REGEN_ENABLED re-runs the countdown).
local function FloatLocked()
    return floatBar ~= nil and InCombatLockdown ~= nil and InCombatLockdown() and true or false
end

local function SetFloatShown(shown)
    if not floatBar then return end
    if FloatLocked() then
        if floatBar:IsShown() then floatBar:SetAlpha(shown and 1 or 0) end
        return
    end
    floatBar:SetAlpha(1)
    floatBar:SetShown(shown)
end

-- In combat, with the timer wanted and the protected frame down: the attach
-- bar, which is an ordinary frame, draws it where the timer would be
local function StandIn(label, left, span)
    attachBar:ClearAllPoints()
    attachBar:SetPoint("CENTER", floatBar, "CENTER", 0, 0)
    attachBar:SetWidth(floatBar:GetWidth() or FLOAT_WIDTH)
    PaintBar(attachBar, label, left, span)
    attachBar:Show()
end

local function ApplyFloatChrome()
    if not floatBar or FloatLocked() then return end
    Commander.UI.ApplyHudChrome(floatBar, CommanderAdjutantDB, "QueueTimer", {
        title = "Deployment",
        defaultPoint = { point = "TOP", x = 0, y = -190 },
    })
    floatChromed = true
end

-- Whichever invite window is currently up for this queue slot, or nil
local function InviteDialog(index)
    if not index then return nil end
    local dialog = _G.PVPReadyDialog
    if dialog and dialog.IsShown and dialog:IsShown()
        and (dialog.activeIndex == index or dialog.battlefieldIndex == index) then
        return dialog
    end
    if type(StaticPopup_FindVisible) == "function" then
        local ok, popup = pcall(StaticPopup_FindVisible, "CONFIRM_BATTLEFIELD_ENTRY", index)
        if ok and popup then return popup end
    end
    return nil
end

-- Draws the countdown; returns whether anything still needs ticking.
local function UpdateCountdown()
    if not (CommanderAdjutantDB.EnableAdjutant and CommanderAdjutantDB.ShowQueueTimer) then
        if attachBar then attachBar:Hide() end
        SetFloatShown(false)
        return false
    end
    EnsureBars()

    local state = ScanPorts()
    if not state and demoPort then
        demoPort.left = math.max(demoPort.span - (GetTime() - demoPort.started), 0)
        if demoPort.left > 0 then state = demoPort else demoPort = nil end
    end

    local unlocked = Commander.UI.HudUnlocked(CommanderAdjutantDB, "QueueTimer")
    WireEnterButton()

    if not state then
        attachBar:Hide()
        floatBar.portIndex = nil
        -- Unlocked with nothing pending: the timer has to stay on screen or
        -- there is nothing to drag
        if unlocked then
            ApplyFloatChrome()
            PaintBar(floatBar, "Deployment", 0, 0)
            SetFloatShown(true)
        else
            SetFloatShown(false)
        end
        return false
    end

    -- One warning per invite, and never for a window that already ran out
    local warnAt = CommanderAdjutantDB.QueueTimerWarning or 0
    if warnAt > 0 and not state.warned and state.left > 0 and state.left <= warnAt then
        state.warned = true
        Announce("QUEUE_CLOSING", string.format("Transport leaving: %s", state.mapName or "the front"),
            1, 0.3, 0.2)
    end

    local dialog = InviteDialog(state.index)
    if dialog then
        SetFloatShown(false)
        floatBar.portIndex = nil
        attachBar:ClearAllPoints()
        attachBar:SetPoint("TOP", dialog, "BOTTOM", 0, -4)
        attachBar:SetWidth(math.max(dialog:GetWidth() or 0, FLOAT_WIDTH))
        PaintBar(attachBar, "Enter within", state.left, state.span)
        attachBar:Show()
    else
        attachBar:Hide()
        if CommanderAdjutantDB.KeepQueueTimer or unlocked then
            ApplyFloatChrome()
            floatBar.portIndex = state.index
            PaintBar(floatBar, state.mapName or "Deployment", state.left, state.span)
            if FloatLocked() and not floatBar:IsShown() then
                StandIn(state.mapName or "Deployment", state.left, state.span)
            else
                SetFloatShown(true)
            end
        else
            floatBar.portIndex = nil
            SetFloatShown(false)
        end
    end
    return true
end

local countdown = CreateFrame("Frame")
local sinceTick = 0

local function TickCountdown(self, elapsed)
    sinceTick = sinceTick + elapsed
    if sinceTick < QUEUE_TICK then return end
    sinceTick = 0
    if not UpdateCountdown() then
        self:SetScript("OnUpdate", nil)
    end
end

local function StartCountdown()
    sinceTick = QUEUE_TICK   -- paint on the very next frame, not in a tenth of a second
    countdown:SetScript("OnUpdate", TickCountdown)
end

-- Shared with the settings panel's /cadj timer subcommand
function CommanderAdjutant_TestQueueTimer()
    if not (CommanderAdjutantDB.EnableAdjutant and CommanderAdjutantDB.ShowQueueTimer) then
        print("Commander Adjutant: the deployment countdown is switched off (/cadj)")
        return
    end
    demoPort = { mapName = "Alterac Valley", span = DEMO_LENGTH, started = GetTime(), left = DEMO_LENGTH }
    StartCountdown()
    print(string.format("Commander Adjutant: deployment countdown demo, %d seconds", DEMO_LENGTH))
end

local queueEvents = CreateFrame("Frame")
queueEvents:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
queueEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
-- Whatever combat kept the protected timer from doing, it does now
queueEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
queueEvents:SetScript("OnEvent", function()
    if not loaded or not CommanderAdjutantDB.EnableAdjutant then return end
    -- Scan first: the pop banner does not wait on the countdown's own switch
    ScanPorts()
    StartCountdown()
end)

Commander.AddListener(COMMANDER_ADJUTANT_EVENTS.UPDATE, function()
    if floatChromed then ApplyFloatChrome() end
    StartCountdown()
end)
