-- Commander Comms: a radial wheel of eight quick battle calls. Opened by
-- keybind (Bindings.xml), slash, or the settings button; each call routes
-- to the widest channel that fits the group (raid > party > say). Clicking
-- a call sends and closes; Escape or a second toggle also closes.

BINDING_HEADER_COMMANDERCOMMS = "Commander Comms"
BINDING_NAME_COMMANDERCOMMS_TOGGLE = "Open Comms Wheel"

local RADIUS = 110

-- emote = voiced client emote token played via DoEmote when Use Voice
-- Emotes is on (the classic /incoming, /healme, /oom... voice lines)
local CALLS = {
    { label = "On My Way", msg = "On my way." },
    { label = "Attack", msg = "Attack my target!", targetMsg = "Attack %s!", emote = "ATTACKTARGET" },
    { label = "Need Healing", msg = "I need healing!", emote = "HEALME" },
    { label = "Fall Back", msg = "Fall back and regroup!", emote = "FLEE" },
    { label = "Incoming", msg = "Incoming enemies - get ready!", emote = "INCOMING" },
    { label = "Out of Mana", msg = "I'm out of mana.", emote = "OOM" },
    { label = "Charge", msg = "Charge!", emote = "CHARGE" },
    { label = "Help", msg = "Help me!", targetMsg = "Help me with %s!", emote = "HELPME" },
    { label = "Thank You", msg = "Thank you!", targetMsg = "Thank you, %s!", emote = "THANK" },
    { label = "Cheer", msg = "Well played, team!", targetMsg = "Well played, %s!", emote = "CHEER" },
}

local function PickChannel()
    -- Battlegrounds and arenas are instance-category groups on this
    -- engine: IsInRaid() is true in a BG but "RAID" fails there — the
    -- instance group speaks INSTANCE_CHAT
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
    return "SAY"
end

local function ClickSound()
    if CommanderCommsDB.CommsSound then
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB, "Master")
    end
end

local wheel = CreateFrame("Frame", "CommanderCommsWheel", UIParent)
wheel:SetPoint("CENTER")
wheel:SetSize((RADIUS + 60) * 2, (RADIUS + 30) * 2)
wheel:SetFrameStrata("DIALOG")
-- Swallow clicks between the buttons: a miss must not fall through to the
-- world and retarget right before a targeted call
wheel:EnableMouse(true)
wheel:Hide()
if UISpecialFrames then
    table.insert(UISpecialFrames, "CommanderCommsWheel")
end

local center = wheel:CreateFontString(nil, "OVERLAY")
center:SetFontObject(GameFontNormalLarge)
center:SetPoint("CENTER")
center:SetText("COMMS")
center:SetTextColor(0.3, 1, 0.4)

local function InAnyGroup()
    return IsInGroup()
        or (LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE))
end

local function SendCall(call)
    local message = call.msg
    if call.targetMsg and CommanderCommsDB.IncludeTarget and UnitExists("target") then
        local targetName = UnitName("target")
        if targetName then
            message = string.format(call.targetMsg, targetName)
        end
    end
    local voiced = call.emote and CommanderCommsDB.UseEmotes
    if voiced then
        DoEmote(call.emote)
    end
    -- The voiced emote already announces locally; the channel message is
    -- for the group. Solo with a voice line, skip the redundant /say.
    if InAnyGroup() or not voiced then
        SendChatMessage(message, PickChannel())
    end
    ClickSound()
    wheel:Hide()
end

-- ---------------------------------------------------------------------------
-- Auto-emote: smart battlefield callouts with spam protection. Each trigger
-- has a per-emote cooldown AND hysteresis — it re-arms only after the stat
-- recovers well above its threshold, so hovering at 29% health cannot spam.
-- ---------------------------------------------------------------------------
local REARM_MARGIN = 0.15

local autoState = {
    HEALME = { firedAt = -math.huge, armed = true },
    OOM = { firedAt = -math.huge, armed = true },
}

local function TryAutoEmote(token)
    local state = autoState[token]
    if not state.armed then return end
    local cooldown = CommanderCommsDB.AutoEmoteCooldown or 30
    local now = GetTime()
    if now - state.firedAt < cooldown then return end
    state.firedAt = now
    state.armed = false
    DoEmote(token)
end

local function CheckAutoEmotes()
    if not (CommanderCommsDB and CommanderCommsDB.EnableComms
        and CommanderCommsDB.AutoEmote) then return end
    -- Dead units don't call for heals; death also re-arms both triggers so
    -- a battle res or run-back starts with fresh alarms
    if UnitIsDeadOrGhost("player") then
        autoState.HEALME.armed = true
        autoState.OOM.armed = true
        return
    end
    if not UnitAffectingCombat("player") then return end

    local health = UnitHealth("player")
    local healthMax = UnitHealthMax("player")
    if healthMax and healthMax > 0 then
        local pct = health / healthMax
        local threshold = CommanderCommsDB.AutoHealThreshold or 0.3
        if pct <= threshold and InAnyGroup() then
            TryAutoEmote("HEALME")
        elseif pct >= threshold + REARM_MARGIN then
            autoState.HEALME.armed = true
        end
    end

    -- Only mana users call out OOM
    if UnitPowerType("player") == 0 then
        local mana = UnitPower("player")
        local manaMax = UnitPowerMax("player")
        if manaMax and manaMax > 0 then
            local pct = mana / manaMax
            local threshold = CommanderCommsDB.AutoOOMThreshold or 0.2
            if pct <= threshold then
                TryAutoEmote("OOM")
            elseif pct >= threshold + REARM_MARGIN then
                autoState.OOM.armed = true
            end
        end
    end
end

for i, call in ipairs(CALLS) do
    local button = CreateFrame("Button", nil, wheel, "UIPanelButtonTemplate")
    button:SetSize(110, 24)
    button:SetText(call.label)
    -- Slot 1 at the top, remaining calls clockwise at even steps around
    -- the wheel (the step follows the call count)
    local angle = math.rad(90 - (i - 1) * (360 / #CALLS))
    button:SetPoint("CENTER", wheel, "CENTER", math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
    button:SetScript("OnClick", function() SendCall(call) end)
end

function CommanderComms_Toggle()
    if not (CommanderCommsDB and CommanderCommsDB.EnableComms) then
        print("Commander Comms: module is disabled (enable it in settings or /ccomms)")
        return
    end
    if wheel:IsShown() then
        wheel:Hide()
    else
        wheel:Show()
        ClickSound()
    end
end

-- ---------------------------------------------------------------------------
-- Interrupt callouts: a successful kick is announced to the group — who
-- you kicked, which cast you stopped, and with what ability — so the team
-- knows interrupts are covered without anyone typing. (The old targeted
-- /silence emote resolved unreliably from combat-log names and fell back
-- to shushing everyone nearby.) Short dedupe window so AoE interrupts
-- hitting several casters don't burst-spam the channel.
-- ---------------------------------------------------------------------------
local INTERRUPT_ANNOUNCE_COOLDOWN = 2
local lastInterruptAnnounce = -math.huge
local playerGUID

local function OnInterrupt()
    if not (CommanderCommsDB and CommanderCommsDB.EnableComms
        and CommanderCommsDB.InterruptSilence) then return end
    local _, subevent, _, sourceGUID, _, _, _, _, destName, _, _,
        _, kickName, _, _, stoppedName = CombatLogGetCurrentEventInfo()
    if subevent ~= "SPELL_INTERRUPT" then return end
    if sourceGUID ~= (playerGUID or UnitGUID("player")) then return end
    -- Team comms only: solo interrupts need no announcement
    if not InAnyGroup() then return end
    if GetTime() - lastInterruptAnnounce < INTERRUPT_ANNOUNCE_COOLDOWN then return end
    lastInterruptAnnounce = GetTime()
    local message
    if stoppedName and destName then
        message = string.format("Interrupted %s's %s%s", destName, stoppedName,
            kickName and (" with " .. kickName .. ".") or ".")
    elseif destName then
        message = string.format("Interrupted %s.", destName)
    else
        message = "Interrupt landed."
    end
    SendChatMessage(message, PickChannel())
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
-- Player-only registration: these fire constantly for every visible unit
if events.RegisterUnitEvent then
    events:RegisterUnitEvent("UNIT_HEALTH", "player")
    events:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
else
    events:RegisterEvent("UNIT_HEALTH")
    events:RegisterEvent("UNIT_POWER_UPDATE")
end
events:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player")
        Commander.AddListener(COMMANDER_COMMS_EVENTS.UPDATE, function()
            if not CommanderCommsDB.EnableComms then
                wheel:Hide()
            end
        end)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnInterrupt()
    elseif unit == "player" then
        CheckAutoEmotes()
    end
end)
