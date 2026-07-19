-- Commander Comms: a radial wheel of ten quick battle calls. Opened by
-- keybind (Bindings.xml), slash, or the settings button. Voiced calls play
-- the real emote — the voice line and its text ARE the announcement — the
-- rest route to the widest channel that fits the group (raid > party >
-- say). Clicking a call sends and closes; Escape or a toggle also closes.

BINDING_HEADER_COMMANDERCOMMS = "Commander Comms"
BINDING_NAME_COMMANDERCOMMS_TOGGLE = "Open Comms Wheel"

local RADIUS = 110      -- vertical radius of the wheel ellipse
local RADIUS_X = 180    -- horizontal radius: wide ring for wide screens
local STAGGER = 1.22    -- every second call sits on an outer ring — ten
                        -- 110px buttons on one circle overlap at the poles

-- emote = voiced client emote token played via DoEmote when Use Voice
-- Emotes is on (the classic /incoming, /healme, /oom... voice lines)
local CALLS = {
    { label = "On My Way", msg = "On my way." },
    -- OPENFIRE, not ATTACKTARGET: /attack is the auto-attack command, not
    -- a communication — /openfire is the voiced call
    { label = "Attack", msg = "Attack my target!", targetMsg = "Attack %s!", emote = "OPENFIRE" },
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
wheel:SetSize((RADIUS_X * STAGGER + 65) * 2, (RADIUS * STAGGER + 45) * 2)
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
center:SetWidth(210)
center:SetText("COMMS")
center:SetTextColor(0.3, 1, 0.4)

-- Delivery line under the hovered call's preview: voiced or which channel
local centerSub = wheel:CreateFontString(nil, "OVERLAY")
centerSub:SetFontObject(GameFontHighlightSmall)
centerSub:SetPoint("TOP", center, "BOTTOM", 0, -5)
centerSub:SetText("")

local function InAnyGroup()
    return IsInGroup()
        or (LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE))
end

local function BuildMessage(call)
    local message = call.msg
    if call.targetMsg and CommanderCommsDB.IncludeTarget and UnitExists("target") then
        local targetName = UnitName("target")
        if targetName then
            message = string.format(call.targetMsg, targetName)
        end
    end
    return message
end

local function SendCall(call)
    -- A voiced call IS the announcement — the real emote carries the voice
    -- line and its own text, so doubling it with a chat message is noise.
    -- Calls without a voice line (or with voice emotes off) go to chat.
    if call.emote and CommanderCommsDB.UseEmotes then
        DoEmote(call.emote)
    else
        SendChatMessage(BuildMessage(call), PickChannel())
    end
    ClickSound()
    wheel:Hide()
end

-- ---------------------------------------------------------------------------
-- Auto charge rally: when Commander Momentum's streak clock is about to
-- run out, fire the Charge com automatically — keep the group moving and
-- the chain alive. Re-arms only after a kill refills the window (or the
-- streak dies), plus an absolute cooldown, so it calls once per stall.
-- ---------------------------------------------------------------------------
local AUTO_CHARGE_COOLDOWN = 20
local chargeArmed = true
local lastAutoCharge = -math.huge

C_Timer.NewTicker(1, function()
    if not (CommanderCommsDB and CommanderCommsDB.EnableComms
        and CommanderCommsDB.AutoCharge) then return end
    if not CommanderMomentum_GetStreakInfo then return end
    local streak, remaining = CommanderMomentum_GetStreakInfo()
    if not remaining then
        chargeArmed = true
        return
    end
    local threshold = CommanderCommsDB.AutoChargeThreshold or 8
    if remaining >= threshold then
        chargeArmed = true
        return
    end
    if not chargeArmed then return end
    if GetTime() - lastAutoCharge < AUTO_CHARGE_COOLDOWN then return end
    chargeArmed = false
    lastAutoCharge = GetTime()
    for _, call in ipairs(CALLS) do
        if call.label == "Charge" then
            SendCall(call)
            break
        end
    end
end)

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

-- Hovering a call previews exactly what firing it will do: the outgoing
-- line in the middle of the wheel, plus whether it goes out as your
-- character's voice or as a chat message (and to which channel)
local function PreviewCall(call)
    center:SetText("\"" .. BuildMessage(call) .. "\"")
    center:SetTextColor(1, 1, 1)
    if call.emote and CommanderCommsDB.UseEmotes then
        centerSub:SetText("voiced emote")
        centerSub:SetTextColor(0.3, 1, 0.4)
    else
        centerSub:SetText("to " .. PickChannel():lower():gsub("_", " "))
        centerSub:SetTextColor(0.7, 0.7, 0.7)
    end
end

local function ClearPreview()
    center:SetText("COMMS")
    center:SetTextColor(0.3, 1, 0.4)
    centerSub:SetText("")
end

for i, call in ipairs(CALLS) do
    local button = CreateFrame("Button", nil, wheel, "UIPanelButtonTemplate")
    button:SetSize(110, 24)
    button:SetText(call.label)
    -- Slot 1 at the top, remaining calls clockwise at even steps around
    -- the ellipse, alternating between the inner and outer ring
    local angle = math.rad(90 - (i - 1) * (360 / #CALLS))
    local ring = (i % 2 == 0) and STAGGER or 1
    button:SetPoint("CENTER", wheel, "CENTER",
        math.cos(angle) * RADIUS_X * ring, math.sin(angle) * RADIUS * ring)
    if call.emote then
        -- Speaker badge: this call carries a voice line
        local speaker = button:CreateTexture(nil, "OVERLAY")
        speaker:SetSize(14, 14)
        speaker:SetPoint("LEFT", button, "LEFT", 4, 0)
        speaker:SetTexture("Interface\\Common\\VoiceChat-Speaker")
    end
    button:SetScript("OnClick", function() SendCall(call) end)
    button:SetScript("OnEnter", function() PreviewCall(call) end)
    button:SetScript("OnLeave", ClearPreview)
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
local ANNOUNCE_COOLDOWN = 2
local lastInterruptAnnounce = -math.huge
local lastDispelAnnounce = -math.huge
local playerGUID

local function OnInterrupt(destName, kickName, stoppedName)
    if not CommanderCommsDB.InterruptSilence then return end
    if GetTime() - lastInterruptAnnounce < ANNOUNCE_COOLDOWN then return end
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

-- Cleanse callouts mirror the interrupt ones: dispelling a debuff off a
-- friendly target announces who was cleansed and what came off, so the
-- invisible support work is visible. DEBUFF-only keeps offensive purges
-- (stripping enemy buffs) out of the channel.
local function OnDispel(destName, dispelName, removedName, auraType)
    if not CommanderCommsDB.DispelCallouts then return end
    if auraType ~= "DEBUFF" then return end
    if GetTime() - lastDispelAnnounce < ANNOUNCE_COOLDOWN then return end
    lastDispelAnnounce = GetTime()
    if destName == UnitName("player") then destName = "myself" end
    local message
    if removedName then
        message = string.format("Removed %s from %s%s", removedName,
            destName or "the target",
            dispelName and (" (" .. dispelName .. ").") or ".")
    else
        message = string.format("Cleansed %s.", destName or "the target")
    end
    SendChatMessage(message, PickChannel())
end

local function OnCombatLog()
    if not (CommanderCommsDB and CommanderCommsDB.EnableComms) then return end
    local _, subevent, _, sourceGUID, _, _, _, _, destName, _, _,
        _, actionName, _, _, extraName, _, auraType = CombatLogGetCurrentEventInfo()
    if sourceGUID ~= (playerGUID or UnitGUID("player")) then return end
    -- Team comms only: solo callouts have no audience
    if not InAnyGroup() then return end
    if subevent == "SPELL_INTERRUPT" then
        OnInterrupt(destName, actionName, extraName)
    elseif subevent == "SPELL_DISPEL" then
        OnDispel(destName, actionName, extraName, auraType)
    end
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
        OnCombatLog()
    elseif unit == "player" then
        CheckAutoEmotes()
    end
end)
