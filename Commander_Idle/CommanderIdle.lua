-- Commander Idle: the RTS idle-worker alert. When the character has been
-- completely inactive (not moving, not in combat, not casting, not dead)
-- for the configured time, a pulsing pocket-watch button appears in the
-- lower-left corner — click it to open the quest log ("check your orders").
-- Any activity hides it instantly.

local CHECK_INTERVAL = 1

local button = CreateFrame("Button", "CommanderIdleButton", UIParent)
button:SetSize(44, 44)
button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 16, 180)
button:SetFrameStrata("HIGH")
button:Hide()

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetAllPoints()
icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")

local ringHighlight = button:CreateTexture(nil, "OVERLAY")
ringHighlight:SetPoint("TOPLEFT", -6, 6)
ringHighlight:SetPoint("BOTTOMRIGHT", 6, -6)
ringHighlight:SetTexture("Interface\\Minimap\\UI-Minimap-Ping-Expand")
ringHighlight:SetVertexColor(1, 0.85, 0.2, 0.9)

button:SetScript("OnClick", function()
    button:Hide()
    ToggleQuestLog()
end)
button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Idle", 1, 1, 1)
    GameTooltip:AddLine("Your character is standing around. Click to review your orders (quest log).", nil, nil, nil, true)
    -- A line of class flavor from the shared identity layer, in class color
    local info = Commander.GetClassInfo and Commander.GetClassInfo()
    if info and info.line then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(info.line, info.color[1], info.color[2], info.color[3], true)
    end
    GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Gentle pulse while shown
local pulseTime = 0
button:SetScript("OnUpdate", function(self, elapsed)
    pulseTime = pulseTime + elapsed
    local pulse = 0.65 + 0.35 * math.abs(math.sin(pulseTime * 2))
    ringHighlight:SetAlpha(pulse)
end)

local idleSince
local alerted = false

-- Standing at a vendor, mailbox, auctioneer, quest giver, bank, trainer, or
-- flight master is work, not idling — suppress while any of these are open
-- (AuctionFrame is load-on-demand, hence the nil guards)
local INTERACTION_FRAMES = {
    "MerchantFrame", "MailFrame", "AuctionFrame", "TradeFrame",
    "GossipFrame", "QuestFrame", "BankFrame", "TaxiFrame",
    "ClassTrainerFrame", "CraftFrame", "TradeSkillFrame",
}

local function IsInteracting()
    for _, name in ipairs(INTERACTION_FRAMES) do
        local interactionFrame = _G[name]
        if interactionFrame and interactionFrame.IsShown and interactionFrame:IsShown() then
            return true
        end
    end
    return false
end

local function IsIdleNow()
    if UnitAffectingCombat("player") then return false end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return false end
    if UnitCastingInfo("player") or UnitChannelInfo("player") then return false end
    if (GetUnitSpeed("player") or 0) > 0 then return false end
    if IsInteracting() then return false end
    if IsResting() and not CommanderIdleDB.IdleWhileResting then return false end
    return true
end

local function HideAlert()
    if alerted then
        alerted = false
        button:Hide()
    end
end

-- Opt-in class flavor: one short class-appropriate emote when the alert first
-- appears (default off; it is a visible /emote). Idle alerts only fire out of
-- combat, so DoEmote is always safe here; pcall guards an unknown token.
local function IdleEmote()
    if not (CommanderIdleDB and CommanderIdleDB.RPEmote) then return end
    if not (Commander.GetClassInfo and DoEmote) then return end
    local info = Commander.GetClassInfo()
    if info and info.emote then
        pcall(DoEmote, info.emote)
    end
end

local ticker

local function Check()
    if not CommanderIdleDB.EnableIdle then
        HideAlert()
        return
    end
    if IsIdleNow() then
        idleSince = idleSince or GetTime()
        if not alerted and (GetTime() - idleSince) >= (CommanderIdleDB.IdleSeconds or 30) then
            alerted = true
            pulseTime = 0
            button:Show()
            if CommanderIdleDB.IdleSound then
                PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB, "Master")
            end
            IdleEmote()
        end
    else
        idleSince = nil
        HideAlert()
    end
end

-- Standard suite tester: show the alert immediately. Real activity (or
-- the click itself) dismisses it exactly like a genuine idle alert.
function CommanderIdle_Test()
    if not (CommanderIdleDB and CommanderIdleDB.EnableIdle) then
        print("Commander Idle: module is disabled (enable it in settings or /cidle)")
        return
    end
    alerted = true
    pulseTime = 0
    button:Show()
    if CommanderIdleDB.IdleSound then
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB, "Master")
    end
    IdleEmote()
    print("Commander Idle: test alert — click the pocket watch or start moving to dismiss")
end

local function ApplyEnabled()
    if CommanderIdleDB.EnableIdle then
        if not ticker then
            ticker = C_Timer.NewTicker(CHECK_INTERVAL, Check)
        end
    else
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        idleSince = nil
        HideAlert()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        Commander.AddListener(COMMANDER_IDLE_EVENTS.UPDATE, ApplyEnabled)
        ApplyEnabled()
    end
end)

-- ===========================================================================
-- The AFK clock
--
-- The world half above nudges you when you have stopped playing. This half is
-- the opposite problem, and it answers exactly one question: how long until
-- the battleground throws me out.
--
-- The rungs and the wording live in CommanderIdleClock. This half owns the
-- three things that need the client: watching for input, scanning the three
-- auras, and drawing one bar.
--
-- ON WATCHING FOR INPUT
--
-- The five-minute auto-AFK kick is the one that catches a defender, and this
-- client has NO api for "seconds since last input" — so the clock has to be
-- rebuilt from the input an addon can actually see: the cursor moving, the
-- camera being dragged (during mouselook the cursor is pinned, so that needs
-- its own check), the character moving, and any spell you send.
--
-- That set can only ever UNDER-count: a keypress that does nothing visible is
-- invisible to an addon. So the bar can warn early, never late. Erring toward
-- a needless warning is the right direction when the other outcome is a
-- fifteen-minute lockout, and the warning window is small enough that in
-- practice you never see it while your hand is on the mouse.
-- ===========================================================================

local Clock = CommanderIdleClock

local CLOCK_TICK = 0.1
local INPUT_TICK = 0.25
local BAR_WIDTH = 240
local BAR_HEIGHT = 46
-- Seconds left to chime at, descending
local WARN_MARKS = { 30, 10 }

local inBattleground = false
local playerGUID
local lastInput = 0
local lastCursorX, lastCursorY
local clockBar, clockChromed
local clockTicker
local lastStage, lastRemaining
local demoUntil, demoStarted

local function ClockEnabled()
    return CommanderIdleDB.EnableIdle and CommanderIdleDB.WatchBattleground
end

-- ---------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------

local function NoteInput()
    lastInput = GetTime()
end

-- Polled, not evented: there is no "mouse moved" event, and the two cases
-- have to be checked separately — while the right button is held for
-- mouselook the cursor does not move at all, which would otherwise read as a
-- player who has walked away from the keyboard.
local function PollInput()
    if IsMouselooking and IsMouselooking() then
        NoteInput()
        return
    end
    if (GetUnitSpeed and (GetUnitSpeed("player") or 0) > 0) then
        NoteInput()
        return
    end
    if GetCursorPosition then
        local x, y = GetCursorPosition()
        if x and y then
            if lastCursorX and (x ~= lastCursorX or y ~= lastCursorY) then
                NoteInput()
            end
            lastCursorX, lastCursorY = x, y
        end
    end
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

-- Cached: the answer changes once, on a loading screen.
local function RefreshZone()
    local _, instanceType = IsInInstance()
    local was = inBattleground
    inBattleground = (instanceType == "pvp")
    if inBattleground and not was then NoteInput() end
end

-- Cached, and refreshed only on UNIT_AURA. An aura's expirationTime is an
-- absolute point on GetTime()'s clock, so a countdown ticking at 10 Hz needs
-- the scan exactly once — when the debuff row actually changes.
local auraCache

local function RefreshAuras()
    auraCache = nil
    if not (C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex) then return nil end
    for index = 1, 40 do
        local aura = C_UnitAuras.GetDebuffDataByIndex("player", index, "HARMFUL")
        if not aura then break end
        if Clock.WATCHED[aura.spellId] then
            auraCache = auraCache or {}
            auraCache[aura.spellId] = aura
        end
    end
    return auraCache
end

local function Snapshot()
    return {
        now = GetTime(),
        inBattleground = inBattleground,
        -- The client's own answer, and the only one that needs no spell id.
        -- Blizzard uses it to grey out Report AFK, so it is true for both
        -- report rungs; it backs the id scan up, it does not lead it.
        pvpInactive = type(PlayerIsPVPInactive) == "function"
            and PlayerIsPVPInactive("player") or false,
        auras = auraCache,
        sinceInput = GetTime() - lastInput,
        autoAfkLimit = Clock.AUTO_AFK_LIMIT,
        warnUnder = CommanderIdleDB.ClockWarnUnder or 60,
        watchBattleground = true,
    }
end

-- ---------------------------------------------------------------------------
-- The bar: a title, a number, and one short line saying what clears it
-- ---------------------------------------------------------------------------

local function BuildClockBar()
    local bar = CreateFrame("Frame", "CommanderIdleClockBar", UIParent)
    bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
    bar:SetFrameStrata("HIGH")
    bar:Hide()

    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("TOPLEFT", bar, "TOPLEFT", 4, -4)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local timer = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    timer:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -6, -4)
    timer:SetJustifyH("RIGHT")

    -- The title shares its line with the number, so it ends where the number
    -- begins rather than running underneath it
    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -2)
    title:SetPoint("RIGHT", timer, "LEFT", -6, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)

    local hint = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -3)
    hint:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(false)

    local track = bar:CreateTexture(nil, "ARTWORK")
    track:SetColorTexture(1, 1, 1, 0.12)
    track:SetHeight(3)
    track:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 5, 4)
    track:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -5, 4)

    local fill = bar:CreateTexture(nil, "OVERLAY")
    fill:SetHeight(3)
    fill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 0, 0)

    -- Hover surface is a CHILD frame: a locked HUD frame passes left-clicks
    -- straight through, so the root itself can never carry a tooltip
    local hover = CreateFrame("Frame", nil, bar)
    hover:SetAllPoints(bar)
    hover:EnableMouse(false)
    hover:EnableMouseMotion(true)
    hover:SetScript("OnEnter", function(self)
        local state = bar.state
        if not state then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(state.title, 1, 1, 1)
        GameTooltip:AddLine(state.detail, 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    hover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    bar.icon, bar.title, bar.timer, bar.hint = icon, title, timer, hint
    bar.track, bar.fill, bar.hover = track, fill, hover
    return bar
end

local function EnsureClockBar()
    if clockBar then return end
    clockBar = BuildClockBar()
end

local function ApplyClockChrome()
    if not clockBar then return end
    Commander.UI.ApplyHudChrome(clockBar, CommanderIdleDB, "Clock", {
        title = "AFK Clock",
        defaultPoint = { point = "TOP", x = 0, y = -230 },
    })
    clockChromed = true
end

local function PaintClock(state)
    local color = Clock.SEVERITY_COLOR[state.severity] or Clock.SEVERITY_COLOR.INFO
    local r, g, b = color[1], color[2], color[3]

    clockBar.state = state
    clockBar.icon:SetTexture(state.icon)
    clockBar.title:SetText(state.title)
    clockBar.title:SetTextColor(r, g, b)
    clockBar.hint:SetText(state.hint or "")
    clockBar.hint:SetTextColor(0.75, 0.75, 0.75)

    if state.seconds then
        clockBar.timer:SetText(Clock.Format(state.seconds))
        clockBar.timer:SetTextColor(r, g, b)
        clockBar.timer:Show()
    else
        clockBar.timer:Hide()
    end

    local usable = math.max((clockBar:GetWidth() or BAR_WIDTH) - 10, 1)
    clockBar.fill:SetColorTexture(r, g, b, 0.9)
    clockBar.fill:SetWidth(math.max(usable * (state.fraction or 0), 1))
    clockBar.fill:SetShown(state.fraction ~= nil)
end

-- ---------------------------------------------------------------------------
-- Noise
-- ---------------------------------------------------------------------------

local function Chime(severity)
    if not CommanderIdleDB.ClockSound then return end
    local key = (severity == "CRITICAL") and "RAID_WARNING" or "IG_CHARACTER_INFO_TAB"
    local kit = SOUNDKIT and SOUNDKIT[key]
    if kit then PlaySound(kit, "Master") end
end

local function Reactions(state)
    local stage = state and state.stage
    if stage ~= lastStage then
        lastStage = stage
        lastRemaining = nil
        if state and state.severity ~= "INFO" then
            Chime(state.severity)
            if CommanderIdleDB.ClockAnnounce then
                print("|cff33ff99Commander Idle|r: " .. Clock.Line(state))
            end
        end
    end
    -- Marks only on a countdown to a real consequence
    if state and state.severity == "CRITICAL" and state.seconds then
        if Clock.CrossedMark(WARN_MARKS, lastRemaining, state.seconds) then
            Chime("CRITICAL")
        end
        lastRemaining = state.seconds
    else
        lastRemaining = nil
    end
end

-- ---------------------------------------------------------------------------
-- Tick
-- ---------------------------------------------------------------------------

-- The demo walks the rungs without a battleground so the bar can be seen and
-- placed from a chair.
local DEMO_HOLD = 4
local DEMO_STAGES = { "AUTOAFK", "IDLE", "INACTIVE" }
local DEMO_SPAN = { AUTOAFK = 60, IDLE = 180, INACTIVE = 180 }

local function DemoState()
    if not demoUntil or GetTime() >= demoUntil then
        demoUntil, demoStarted = nil, nil
        return nil
    end
    local elapsed = GetTime() - demoStarted
    local index = math.min(math.floor(elapsed / DEMO_HOLD) + 1, #DEMO_STAGES)
    local key = DEMO_STAGES[index]
    local stage = Clock.StageByKey[key]
    local span = DEMO_SPAN[key]
    local seconds = span * ((DEMO_HOLD - (elapsed % DEMO_HOLD)) / DEMO_HOLD)
    return {
        stage = key, title = stage.title, hint = stage.hint, detail = stage.detail,
        severity = stage.severity, icon = stage.icon,
        seconds = seconds, span = span, fraction = seconds / span, exact = true,
    }
end

local function HideClock()
    if clockBar then
        clockBar.state = nil
        clockBar:Hide()
    end
end

-- Draws the clock; returns whether anything still needs ticking.
local function UpdateClock()
    if not ClockEnabled() then
        HideClock()
        lastStage, lastRemaining = nil, nil
        return false
    end
    EnsureClockBar()

    local state = demoUntil and DemoState() or Clock.Evaluate(Snapshot())
    Reactions(state)

    if not state then
        -- Unlocked with nothing to say still has to be on screen, or there is
        -- nothing to drag
        if Commander.UI.HudUnlocked(CommanderIdleDB, "Clock") then
            ApplyClockChrome()
            PaintClock({
                stage = "AUTOAFK", title = "AFK Clock", hint = "Nothing counting down.",
                detail = "In a battleground this shows the one number that matters: how long until you are thrown out.",
                severity = "INFO", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
            })
            clockBar:Show()
            return true
        end
        HideClock()
        -- Nothing drawn means nothing to animate: stand the 10 Hz driver down
        -- and let the one-second heartbeat pick the clock back up
        return false
    end

    ApplyClockChrome()
    PaintClock(state)
    clockBar:Show()
    return true
end

local clockDriver = CreateFrame("Frame")
local sinceClockTick = 0
local sinceInputTick = 0

local function TickClock(self, elapsed)
    sinceInputTick = sinceInputTick + elapsed
    if sinceInputTick >= INPUT_TICK then
        sinceInputTick = 0
        PollInput()
    end
    sinceClockTick = sinceClockTick + elapsed
    if sinceClockTick < CLOCK_TICK then return end
    sinceClockTick = 0
    if not UpdateClock() then
        self:SetScript("OnUpdate", nil)
    end
end

local function StartClock()
    sinceClockTick = CLOCK_TICK   -- paint on the next frame, not in a tenth of a second
    clockDriver:SetScript("OnUpdate", TickClock)
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

function CommanderIdle_ClockReport()
    if not ClockEnabled() then
        print("|cff33ff99Commander Idle|r: the AFK clock is switched off (/cidle)")
        return
    end
    print("|cff33ff99Commander Idle|r: " .. Clock.Line(Clock.Evaluate(Snapshot())))
    if inBattleground then
        local left = math.max(Clock.AUTO_AFK_LIMIT - (GetTime() - lastInput), 0)
        print(string.format("|cff33ff99Commander Idle|r: auto-AFK kick in %s. Any input resets it — fighting does not.",
            Clock.Format(left)))
    else
        print("|cff33ff99Commander Idle|r: not in a battleground — nothing can kick you here.")
    end
end

function CommanderIdle_ClockTest()
    if not ClockEnabled() then
        print("|cff33ff99Commander Idle|r: the AFK clock is switched off (/cidle)")
        return
    end
    demoStarted = GetTime()
    demoUntil = demoStarted + (#DEMO_STAGES * DEMO_HOLD)
    StartClock()
    print("|cff33ff99Commander Idle|r: AFK clock demo — auto-AFK, idle, inactive.")
end

local function ApplyClock()
    if not ClockEnabled() then
        if clockTicker then clockTicker:Cancel(); clockTicker = nil end
        clockDriver:SetScript("OnUpdate", nil)
        HideClock()
        return
    end
    if clockChromed then ApplyClockChrome() end
    -- A one-second heartbeat is what picks the clock back up: the input clock
    -- running down and the unlock checkbox both fire nothing the driver
    -- would hear while it is stood down
    if not clockTicker then
        clockTicker = C_Timer.NewTicker(1, function()
            if clockDriver:GetScript("OnUpdate") then return end
            PollInput()
            if inBattleground or demoUntil
                or Commander.UI.HudUnlocked(CommanderIdleDB, "Clock") then
                StartClock()
            end
        end)
    end
    StartClock()
end

local clockEvents = CreateFrame("Frame")
clockEvents:RegisterEvent("PLAYER_LOGIN")
clockEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
clockEvents:RegisterEvent("ZONE_CHANGED_NEW_AREA")
clockEvents:RegisterEvent("UNIT_AURA")
-- Anything you actually send is input, and covers the case of a player
-- fighting with keybinds while the mouse sits perfectly still
clockEvents:RegisterEvent("UNIT_SPELLCAST_SENT")
clockEvents:RegisterEvent("PLAYER_STARTED_MOVING")
clockEvents:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" then
        if unit and unit ~= "player" then return end
        RefreshAuras()
    elseif event == "UNIT_SPELLCAST_SENT" or event == "PLAYER_STARTED_MOVING" then
        if unit and unit ~= "player" then return end
        NoteInput()
    else
        if event == "PLAYER_LOGIN" then
            playerGUID = UnitGUID("player")
            NoteInput()
            Commander.AddListener(COMMANDER_IDLE_EVENTS.UPDATE, ApplyClock)
        end
        RefreshZone()
        RefreshAuras()
        if event == "PLAYER_LOGIN" then ApplyClock() end
    end
    if ClockEnabled() then StartClock() end
end)
