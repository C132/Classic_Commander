-- Commander Comms: a radial wheel of ten quick battle calls. Opened by
-- keybind (Bindings.xml), slash, or the settings button. Voiced calls play
-- the real emote — the voice line and its text ARE the announcement — the
-- rest route to the widest channel that fits the group (raid > party >
-- say). Clicking a call sends and closes; Escape or a toggle also closes.
--
-- Alongside the wheel sit the automatic callouts: interrupts, kicks landed
-- on you, cleanses and broken crowd control, all to a group channel — plus
-- the failed-cast callouts, which route by whose problem the failure is:
-- out of range and out of sight whisper the one ally who can move, while
-- out of mana and crowd controlled tell the group. The support calls run
-- the other way: a cooldown you spend ON somebody, whispered to them with
-- what it is for. The mana burn callout watches the whole group: a drain
-- landing on any teammate's mana is announced with how much is left.

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

-- ---------------------------------------------------------------------------
-- Battlegrounds are the one place the automatic callouts stop being comms
-- and turn into noise: forty strangers, a chat window scrolling past
-- reading speed, and nobody coordinating off your kicks. So every
-- automatic callout — interrupt, kicked-on-me, cleanse, CC break — holds
-- its tongue inside a BG unless asked for, and when asked for they can go
-- to the party you
-- queued with instead of the whole battleground. Arenas and dungeons are
-- untouched: there the callouts are the point.
-- ---------------------------------------------------------------------------
local function InBattleground()
    local _, instanceType = IsInInstance()
    return instanceType == "pvp"
end

-- The party you queued with is a HOME-category group living alongside the
-- battleground's own instance raid, so it is asked for by category rather
-- than by IsInGroup()'s default
local function InHomeParty()
    if LE_PARTY_CATEGORY_HOME then return IsInGroup(LE_PARTY_CATEGORY_HOME) end
    return IsInGroup()
end

-- Channel for the automatic combat callouts (interrupt, kicked-on-me,
-- cleanse, CC break). The comms wheel is a deliberate keypress and routes
-- itself. nil means say nothing: either the battleground silence is on, or
-- the callouts were routed to a party that isn't in the battleground with
-- you — and the raid is exactly what that routing exists to avoid.
local function CalloutChannel()
    if not InBattleground() then return PickChannel() end
    if not CommanderCommsDB.BattlegroundCallouts then return nil end
    if CommanderCommsDB.BattlegroundToParty then
        return InHomeParty() and "PARTY" or nil
    end
    return PickChannel()
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

-- The chat line each voiced call falls back to, for the same reason the
-- wheel has one: with Use Voice Emotes off, a call that would have been a
-- voice line is still a call and still has to be made.
local AUTO_EMOTE_TEXT = {
    HEALME = "I need healing!",
    OOM = "I'm out of mana.",
}

local function TryAutoEmote(token)
    local state = autoState[token]
    if not state.armed then return end
    local cooldown = CommanderCommsDB.AutoEmoteCooldown or 30
    local now = GetTime()
    if now - state.firedAt < cooldown then return end
    state.firedAt = now
    state.armed = false
    if CommanderCommsDB.UseEmotes then
        DoEmote(token)
    else
        SendChatMessage(AUTO_EMOTE_TEXT[token] or token, PickChannel())
    end
end

-- Releasing the latch is NOT part of the auto-emote feature, and keeping it
-- there was a trap: the failed-cast callout fires the same one-shot /oom
-- through the same latch, so with Auto-Emote switched off nothing would ever
-- re-arm it and the call could be made exactly once per session. The re-arm
-- runs whenever Comms is on; only the firing side below is the auto-emote's.
local function RearmAutoEmotes()
    -- Death re-arms both, so a battle res or a run-back starts with fresh
    -- alarms rather than the ones the corpse left latched
    if UnitIsDeadOrGhost("player") then
        autoState.HEALME.armed = true
        autoState.OOM.armed = true
        return
    end
    local healthMax = UnitHealthMax("player")
    if healthMax and healthMax > 0 then
        local pct = UnitHealth("player") / healthMax
        if pct >= (CommanderCommsDB.AutoHealThreshold or 0.3) + REARM_MARGIN then
            autoState.HEALME.armed = true
        end
    end
    if UnitPowerType("player") == 0 then
        local manaMax = UnitPowerMax("player")
        if manaMax and manaMax > 0 then
            local pct = UnitPower("player") / manaMax
            if pct >= (CommanderCommsDB.AutoOOMThreshold or 0.2) + REARM_MARGIN then
                autoState.OOM.armed = true
            end
        end
    end
end

local function CheckAutoEmotes()
    if not (CommanderCommsDB and CommanderCommsDB.EnableComms) then return end
    RearmAutoEmotes()
    if not CommanderCommsDB.AutoEmote then return end
    -- Dead units don't call for heals
    if UnitIsDeadOrGhost("player") then return end
    if not UnitAffectingCombat("player") then return end

    local healthMax = UnitHealthMax("player")
    if healthMax and healthMax > 0 then
        local pct = UnitHealth("player") / healthMax
        if pct <= (CommanderCommsDB.AutoHealThreshold or 0.3) and InAnyGroup() then
            TryAutoEmote("HEALME")
        end
    end

    -- Only mana users call out OOM
    if UnitPowerType("player") == 0 then
        local manaMax = UnitPowerMax("player")
        if manaMax and manaMax > 0 then
            local pct = UnitPower("player") / manaMax
            if pct <= (CommanderCommsDB.AutoOOMThreshold or 0.2) then
                TryAutoEmote("OOM")
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
-- knows interrupts are covered without anyone typing. Both spells go out
-- as real spell links, so the group can hover the callout and read what
-- was stopped instead of taking a bare name on faith. (The old targeted
-- /silence emote resolved unreliably from combat-log names and fell back
-- to shushing everyone nearby.) Short dedupe window so AoE interrupts
-- hitting several casters don't burst-spam the channel.
-- ---------------------------------------------------------------------------
local ANNOUNCE_COOLDOWN = 2
local lastInterruptAnnounce = -math.huge
local lastKickedAnnounce = -math.huge
local lastDispelAnnounce = -math.huge
local playerGUID

-- Spell links survive the trip through SendChatMessage, so a callout can
-- hand the group a clickable spell instead of a bare name. The global
-- GetSpellLink is still native on this client; C_Spell.GetSpellLink is the
-- modern spelling, and the hand-built link is the floor when an id
-- resolves through neither. With no id at all (an event that stops
-- carrying one) the plain name still ships — a callout is never lost to
-- a missing link.
local function SpellLink(spellID, spellName)
    if spellID then
        local link = (GetSpellLink and GetSpellLink(spellID))
            or (C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(spellID))
        if type(link) == "string" and link ~= "" then return link end
        if spellName then
            return string.format("|cff71d5ff|Hspell:%d|h[%s]|h|r", spellID, spellName)
        end
    end
    return spellName
end

local function OnInterrupt(destName, kickName, kickID, stoppedName, stoppedID)
    if not CommanderCommsDB.InterruptSilence then return end
    local channel = CalloutChannel()
    if not channel then return end
    if GetTime() - lastInterruptAnnounce < ANNOUNCE_COOLDOWN then return end
    lastInterruptAnnounce = GetTime()
    local kickLink = SpellLink(kickID, kickName)
    local stoppedLink = SpellLink(stoppedID, stoppedName)
    local message
    if stoppedLink and destName then
        message = string.format("Interrupted %s's %s%s", destName, stoppedLink,
            kickLink and (" with " .. kickLink .. ".") or ".")
    elseif destName then
        message = string.format("Interrupted %s.", destName)
    else
        message = "Interrupt landed."
    end
    SendChatMessage(message, channel)
end

-- ---------------------------------------------------------------------------
-- Kicked on me: the callout going the other way. When a kick lands on
-- YOU the team needs more than "I got countered" — which of your spells
-- died, which school went down with it and for how long (that is what
-- decides whether you can still heal, sheep or dispel), who did it, and
-- with what. Everything here is read off the one combat-log event plus
-- what the client already knows; nothing is guessed.
-- ---------------------------------------------------------------------------

-- Combat-log school masks. The singles cover every TBC cast; hybrids
-- (Frostfire, Shadowflame) are named by joining their bits, so a hybrid
-- still reports what it actually locked.
local SCHOOL_NAMES = {
    [0x01] = "Physical", [0x02] = "Holy", [0x04] = "Fire", [0x08] = "Nature",
    [0x10] = "Frost", [0x20] = "Shadow", [0x40] = "Arcane",
}
local SCHOOL_BITS = { 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40 }

local function SchoolName(mask)
    if not mask or mask == 0 then return nil end
    if SCHOOL_NAMES[mask] then return SCHOOL_NAMES[mask] end
    local parts
    for _, schoolBit in ipairs(SCHOOL_BITS) do
        if bit.band(mask, schoolBit) > 0 then
            parts = parts and (parts .. "/" .. SCHOOL_NAMES[schoolBit])
                or SCHOOL_NAMES[schoolBit]
        end
    end
    return parts
end

local PLAYER_FLAG = COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400

-- The class is the most useful thing about the kicker ("Levira (Mage)"
-- says what is coming next as much as what just happened), and the combat
-- log does not carry it — it has to be resolved from whichever unit token
-- happens to point at the same GUID. Built once; only ever walked on an
-- interrupt, so the length costs nothing.
local classScan
local function ClassOfGUID(guid)
    if not guid then return nil end
    if not classScan then
        classScan = { "target", "focus", "mouseover", "targettarget" }
        for i = 1, 5 do classScan[#classScan + 1] = "arena" .. i end
        for i = 1, 40 do classScan[#classScan + 1] = "nameplate" .. i end
        for i = 1, 4 do classScan[#classScan + 1] = "party" .. i end
    end
    for _, unit in ipairs(classScan) do
        if UnitGUID(unit) == guid then
            local class = UnitClass(unit)
            if class and class ~= "" then return class end
            return nil
        end
    end
    return nil
end

-- A creature has no class worth printing, so only players get the suffix
local function DescribeSource(guid, name, flags)
    if not name then return nil end
    if not (flags and bit.band(flags, PLAYER_FLAG) > 0) then return name end
    local class = ClassOfGUID(guid)
    return class and (name .. " (" .. class .. ")") or name
end

-- A school lockout is reported by the client as a COOLDOWN on the spells
-- it covers, which is the only place the duration is readable at all.
-- Anything longer than the longest TBC lock is the spell's own cooldown
-- answering instead, and gets dropped rather than announced as a lie.
local MAX_LOCKOUT = 10.5
local LOCKOUT_READ_DELAY = 0.1   -- the cooldown lands a beat after the event

local function LockoutSeconds(spellID)
    if not spellID then return nil end
    local start, duration
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellID)
        if type(info) == "table" then start, duration = info.startTime, info.duration end
    end
    if not duration and GetSpellCooldown then
        start, duration = GetSpellCooldown(spellID)
    end
    if type(start) ~= "number" or type(duration) ~= "number" then return nil end
    if duration <= 0 or duration > MAX_LOCKOUT then return nil end
    if start + duration <= GetTime() then return nil end
    return math.floor(duration + 0.5)
end

-- info: sourceGUID, sourceName, sourceFlags, kickName, kickID,
--       spellName, spellID, school
local function OnKickedOnMe(info)
    if not CommanderCommsDB.KickedCallouts then return end
    -- Resolved now rather than inside the timer: the callout belongs to
    -- the fight that produced it, not to wherever you are a beat later
    local channel = CalloutChannel()
    if not channel then return end
    if GetTime() - lastKickedAnnounce < ANNOUNCE_COOLDOWN then return end
    lastKickedAnnounce = GetTime()
    -- The lockout arrives as a cooldown a beat after the combat-log event;
    -- waiting for it is the difference between "Frost locked" and the
    -- number the team actually plans around
    C_Timer.After(LOCKOUT_READ_DELAY, function()
        local stopped = SpellLink(info.spellID, info.spellName) or "my cast"
        local by = DescribeSource(info.sourceGUID, info.sourceName, info.sourceFlags)
        local kick = SpellLink(info.kickID, info.kickName)
        local school = SchoolName(info.school)
        local seconds = LockoutSeconds(info.spellID)
        local lock = ""
        if school and seconds then
            lock = string.format(" — %s locked %ds", school, seconds)
        elseif school then
            lock = " — " .. school .. " locked"
        elseif seconds then
            lock = string.format(" — locked %ds", seconds)
        end
        SendChatMessage(string.format("Interrupted on %s%s%s%s.", stopped,
            by and (" by " .. by) or "", kick and (" with " .. kick) or "", lock),
            channel)
    end)
end

-- ---------------------------------------------------------------------------
-- Channels: interrupting one is silent in the combat log. SPELL_INTERRUPT
-- is a cast-bar event — a kicked channel simply stops — so Drain Life,
-- Mind Flay, Evocation, Tranquility and every other channel got no
-- callout at all, which is exactly backwards: the channels are the casts
-- worth kicking. They are caught from the other side instead.
-- UNIT_SPELLCAST_CHANNEL_* remembers what each unit carrying a unit token
-- (your target, your focus, a nameplate) is channeling and when it should
-- end, and an interrupt of yours that lands on such a unit while its
-- channel dies EARLY is announced like any other kick. Whatever the
-- client does report through SPELL_INTERRUPT still wins: the inferred
-- path stands down for a moment per target, so a channel that somehow
-- emits both is announced once.
-- ---------------------------------------------------------------------------

-- Name-keyed so every rank matches. Only true interrupts are listed:
-- stuns cut a channel short too, but announcing every Cheap Shot as an
-- interrupt would bury the callouts that matter. Spell Lock is absent for
-- a different reason — a felhunter's kick is sourced to the PET, and
-- every callout in this file is about what YOU did.
local INTERRUPT_SPELLS = {
    ["Kick"] = true, ["Pummel"] = true, ["Shield Bash"] = true,
    ["Counterspell"] = true, ["Earth Shock"] = true,
    ["Feral Charge"] = true, ["Arcane Torrent"] = true,
}

local CHANNEL_MEMORY = 3         -- how long a finished channel stays askable
local KICK_CONFIRM_DELAY = 0.35  -- the kick's CLEU and the channel's stop
                                 -- race each other; let both land first
local KICK_WINDOW = 1            -- kick and stop this far apart are unrelated
local EARLY_MARGIN = 0.25        -- a channel that ends this close to its own
                                 -- end time ran out; nobody kicked it

local channels = {}         -- destGUID -> { name, spellID, endsAt, stoppedAt }
local realInterruptAt = {}  -- destGUID -> when SPELL_INTERRUPT already told it
local kickMissedAt = {}     -- destGUID -> when an interrupt of ours failed

local function SweepChannelWatch(now)
    -- Three tiny tables (one live channel per visible caster), so aging
    -- them on each new channel is cheaper than owning a ticker
    for guid, channel in pairs(channels) do
        local finishedAt = channel.stoppedAt or channel.endsAt
        if finishedAt and now - finishedAt > CHANNEL_MEMORY then channels[guid] = nil end
    end
    for guid, at in pairs(realInterruptAt) do
        if now - at > CHANNEL_MEMORY then realInterruptAt[guid] = nil end
    end
    for guid, at in pairs(kickMissedAt) do
        if now - at > CHANNEL_MEMORY then kickMissedAt[guid] = nil end
    end
end

local function NoteChannelStart(unit)
    if not (CommanderCommsDB and CommanderCommsDB.EnableComms
        and CommanderCommsDB.InterruptSilence) then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    local name, _, _, _, endTime, _, _, spellID = UnitChannelInfo(unit)
    if not name then return end
    local now = GetTime()
    SweepChannelWatch(now)
    -- Only the end time matters afterwards: "was this channel killed early"
    -- is the whole question the kick asks
    channels[guid] = { name = name, spellID = spellID,
        endsAt = endTime and (endTime / 1000) or now }
end

local function NoteChannelUpdate(unit)
    local guid = UnitGUID(unit)
    local channel = guid and channels[guid]
    if not channel then return NoteChannelStart(unit) end
    local name, _, _, _, endTime = UnitChannelInfo(unit)
    -- Pushback shortens a channel, and the end time is what "ended early"
    -- is measured against — keep it current or a pushed-back channel
    -- finishing normally reads as a kick
    if name == channel.name and endTime then channel.endsAt = endTime / 1000 end
end

local function NoteChannelStop(unit)
    local guid = UnitGUID(unit)
    local channel = guid and channels[guid]
    if not channel or channel.stoppedAt then return end
    channel.stoppedAt = GetTime()
end

-- Runs a beat after the kick's own combat-log event, once the channel has
-- had time to report its stop. Serves both directions: `ctx.incoming` is
-- a channel of YOURS that an enemy kicked, and the victim GUID is the key
-- either way.
local function ConfirmChannelKick(ctx)
    local victimGUID = ctx.victimGUID
    if not victimGUID then return end
    -- Runs once per kick, which is the other place worth aging the tables
    -- (a session of missed kicks without a single channel would otherwise
    -- keep every stamp)
    SweepChannelWatch(GetTime())
    local channel = channels[victimGUID]
    if not channel then return end
    local castAt = ctx.castAt
    -- The client's own event already announced this one
    if (realInterruptAt[victimGUID] or -math.huge) >= castAt - KICK_WINDOW then return end
    -- Dodged, parried, immune: the kick was cast but never landed
    if (kickMissedAt[victimGUID] or -math.huge) >= castAt - KICK_WINDOW then return end
    if channel.stoppedAt then
        -- Unrelated: the channel died before the kick, or well after it
        if math.abs(channel.stoppedAt - castAt) > KICK_WINDOW then return end
        -- Ran its course on its own. Earth Shock in particular lands on
        -- channelers who were finishing anyway, and that is not a kick
        if channel.stoppedAt >= channel.endsAt - EARLY_MARGIN then return end
    elseif GetTime() >= channel.endsAt then
        -- No stop seen and the channel is past its end time: it finished
        return
    end
    -- (No stop seen while the channel still had time left means the unit
    -- lost its token before reporting — a nameplate that scrolled away.
    -- The channel cannot have finished, and the kick landed, so it died.)
    channels[victimGUID] = nil
    if ctx.incoming then
        -- No school on this path: the combat log never described the
        -- channel, so the lockout is reported by duration alone
        OnKickedOnMe({ sourceGUID = ctx.sourceGUID, sourceName = ctx.sourceName,
            sourceFlags = ctx.sourceFlags, kickName = ctx.kickName, kickID = ctx.kickID,
            spellName = channel.name, spellID = channel.spellID })
    else
        OnInterrupt(ctx.victimName, ctx.kickName, ctx.kickID, channel.name, channel.spellID)
    end
end

-- Cleanse callouts mirror the interrupt ones: dispelling a debuff off a
-- friendly target announces who was cleansed and what came off, so the
-- invisible support work is visible. Both spells are links, same as the
-- interrupt callout — the debuff that came off is the one worth reading,
-- since it says what the group is actually being hit with. DEBUFF-only
-- keeps offensive purges (stripping enemy buffs) out of the channel.
local function OnDispel(destName, dispelName, dispelID, removedName, removedID, auraType)
    if not CommanderCommsDB.DispelCallouts then return end
    if auraType ~= "DEBUFF" then return end
    local channel = CalloutChannel()
    if not channel then return end
    if GetTime() - lastDispelAnnounce < ANNOUNCE_COOLDOWN then return end
    lastDispelAnnounce = GetTime()
    if destName == UnitName("player") then destName = "myself" end
    local dispelLink = SpellLink(dispelID, dispelName)
    local removedLink = SpellLink(removedID, removedName)
    local message
    if removedLink then
        message = string.format("Removed %s from %s%s", removedLink,
            destName or "the target",
            dispelLink and (" (" .. dispelLink .. ").") or ".")
    else
        message = string.format("Cleansed %s.", destName or "the target")
    end
    SendChatMessage(message, channel)
end

-- ---------------------------------------------------------------------------
-- CC break callouts: the "who broke my sheep?" alarm. The combat log's
-- SPELL_AURA_BROKEN(_SPELL) events name the breaker but not who owned the
-- aura, so applications of known crowd control are remembered per victim;
-- when one breaks early the announcement can say whose CC died, who killed
-- it, and with what. Two scopes: the GROUP's CC (default -- your own sheep
-- and your partner's Blind are the same problem for the same three
-- people), or every CC broken in combat-log range. Group channels only,
-- same as the rest.
-- ---------------------------------------------------------------------------

-- Name-keyed so every rank matches. Only CC that damage can actually break
-- is listed — stuns just run their course and Banish can't take hits, so
-- neither ever emits a BROKEN event. Freezing Trap's debuff is named
-- "Freezing Trap Effect" on this client; both names stay in case a patch
-- normalizes it.
local CC_AURAS = {
    ["Polymorph"] = true, ["Polymorph: Pig"] = true, ["Polymorph: Turtle"] = true,
    ["Sap"] = true, ["Blind"] = true, ["Gouge"] = true,
    ["Fear"] = true, ["Howl of Terror"] = true, ["Seduction"] = true,
    ["Psychic Scream"] = true, ["Intimidating Shout"] = true,
    ["Freezing Trap"] = true, ["Freezing Trap Effect"] = true,
    ["Scare Beast"] = true, ["Wyvern Sting"] = true, ["Hibernate"] = true,
    ["Shackle Undead"] = true, ["Repentance"] = true,
    ["Turn Evil"] = true, ["Turn Undead"] = true,
    ["Entangling Roots"] = true, ["Frost Nova"] = true,
}

local MAX_CC_AGE = 60   -- longest breakable TBC CC (PvE Polymorph) runs 50s
local trackedCC = {}    -- destGUID -> { [auraName] = { caster, mine, at } }

local function SweepTrackedCC(now)
    for guid, auras in pairs(trackedCC) do
        for auraName, cc in pairs(auras) do
            if now - cc.at > MAX_CC_AGE then auras[auraName] = nil end
        end
        if not next(auras) then trackedCC[guid] = nil end
    end
end

-- The group member who IS this guid, or whose pet it is, as a unit token;
-- nil for anyone outside the group. The succubus casts Seduction, not the
-- warlock, so a pet's CC belongs to its owner
local function GroupUnitByGUID(guid)
    if not guid then return nil end
    local prefix, count = "party", GetNumSubgroupMembers()
    if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
    for i = 1, (count or 0) do
        if UnitGUID(prefix .. i) == guid or UnitGUID(prefix .. "pet" .. i) == guid then
            return prefix .. i
        end
    end
    return nil
end

local function TrackCC(sourceGUID, sourceName, destGUID, auraName)
    if not CommanderCommsDB.CCBreakCallouts then return end
    local now = GetTime()
    -- The table stays tiny (one entry per live CC), so aging it out on
    -- each new application is cheaper than owning a ticker
    SweepTrackedCC(now)
    local mine = sourceGUID ~= nil
        and (sourceGUID == (playerGUID or UnitGUID("player"))
            or sourceGUID == UnitGUID("pet"))
    -- Resolved NOW rather than at the break: the rogue whose Blind this is
    -- may have left the group (or died and been released) by then
    local group = mine or GroupUnitByGUID(sourceGUID) ~= nil
    trackedCC[destGUID] = trackedCC[destGUID] or {}
    trackedCC[destGUID][auraName] = { caster = sourceName, mine = mine, group = group, at = now }
end

local function UntrackCC(destGUID, auraName)
    local auras = trackedCC[destGUID]
    if not auras then return end
    auras[auraName] = nil
    if not next(auras) then trackedCC[destGUID] = nil end
end

-- A pet's own name is useless for blame ("Fluffy broke..."), so a pet
-- breaker resolves to its owner when a group member's pet matches
local function ResolveBreaker(sourceGUID, sourceName, sourceFlags)
    if not sourceName then return "Something" end
    if not (sourceFlags and bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_PET) > 0) then
        return sourceName
    end
    if UnitGUID("pet") == sourceGUID then return "My pet" end
    local unit = GroupUnitByGUID(sourceGUID)
    local owner = unit and UnitName(unit)
    if owner then return owner .. "'s pet" end
    return sourceName .. " (pet)"
end

local lastCCBreakAnnounce = -math.huge

local function OnCCBroken(sourceGUID, sourceName, sourceFlags, destGUID, destName,
        destFlags, auraName, auraID, breakerSpell, breakerID)
    if not CommanderCommsDB.CCBreakCallouts then return end
    -- Only CC parked on enemies is guarded: a mob's fear breaking off a
    -- teammate is good news and needs no blame
    if destFlags and bit.band(destFlags, COMBATLOG_OBJECT_REACTION_FRIENDLY) > 0 then
        UntrackCC(destGUID, auraName)
        return
    end
    local cc = trackedCC[destGUID] and trackedCC[destGUID][auraName]
    -- An entry older than any real CC belongs to an application whose
    -- removal was missed — its owner can't be trusted
    if cc and GetTime() - cc.at > MAX_CC_AGE then cc = nil end
    UntrackCC(destGUID, auraName)
    local mine = cc and cc.mine
    -- Yours and your group's by default; anyone's only when asked. A CC
    -- nobody was seen applying has no known owner and is a stranger's
    if not (mine or (cc and cc.group) or CommanderCommsDB.CCBreakAll) then return end
    if not InAnyGroup() then return end
    local channel = CalloutChannel()
    if not channel then return end
    if GetTime() - lastCCBreakAnnounce < ANNOUNCE_COOLDOWN then return end
    lastCCBreakAnnounce = GetTime()

    local me = playerGUID or UnitGUID("player")
    local breaker = (sourceGUID == me) and "I"
        or ResolveBreaker(sourceGUID, sourceName, sourceFlags)
    local whose
    if mine then
        whose = (sourceGUID == me) and "my own " or "my "
    elseif cc and cc.caster then
        whose = (cc.caster == sourceName) and "their own " or (cc.caster .. "'s ")
    else
        whose = ""
    end
    -- Both spells link, same as the interrupt and cleanse callouts: the CC
    -- so nobody has to guess which one died, the breaker so the blame is
    -- checkable rather than a name someone has to take on faith
    local breakerLink = SpellLink(breakerID, breakerSpell)
    local how = breakerLink and (" (" .. breakerLink .. ")") or " (melee)"
    SendChatMessage(string.format("%s broke %s%s on %s%s.", breaker, whose,
        SpellLink(auraID, auraName), destName or "the target", how), channel)
end

-- ---------------------------------------------------------------------------
-- Failed-cast callouts: the things the client tells YOU in the red text at
-- the top of the screen, said out loud to the people who could act on them.
--
-- A cast that fails names a problem somebody usually needs to hear about,
-- and who that somebody is depends entirely on whose problem it is:
--
--   * Out of range, no line of sight — the ALLY's problem. Nobody else in
--     the group can fix a person standing behind a pillar, and telling the
--     raid about it helps nobody, so these WHISPER the one person who can
--     move. And only after a RUN of them: one missed cast while somebody
--     rounds a corner is normal and two is a bad angle. Four is a person
--     who has not noticed.
--   * Out of mana, crowd controlled — YOUR problem, and the group's to
--     adapt to. These go to the group like every other automatic callout.
--
-- Adding another is a table entry: the client's own string keys, who is to
-- blame, and the line to say.
--
-- Whispers are directed at exactly one person and cost the channel nothing,
-- so unlike the group callouts they are NOT silenced in a battleground: a
-- flag carrier drifting out of your range is precisely the case worth a
-- private line. The group half follows the battleground rule like the rest.
--
-- Getting there needs two things the client reports separately: WHY the
-- cast failed (a UI error string) and WHO it was aimed at (the cast
-- events). They arrive in either order within the same frame, so both
-- stamp and whichever lands second does the pairing. Where the cast events
-- say nothing at all — a client-side refusal need not emit them — the aim
-- is recovered from the units you could have been pointing at, confirmed
-- against UnitInRange so only a real group member can be blamed.
-- ---------------------------------------------------------------------------
local FAIL_PAIR_WINDOW = 0.4     -- error and cast failure race; this far
                                 -- apart they belong to the same press
local FAIL_STREAK_WINDOW = 20    -- a streak is a run, not a lifetime tally:
                                 -- this quiet and the count starts over
local FAIL_MIN_GAP = 0.15        -- one press cannot count twice
local SENT_MEMORY = 3            -- how long a sent cast stays askable

-- The heals worth nagging about, by base id (so the localized name is the
-- client's own) with the English name as the floor when an id does not
-- resolve. Absorbs count: from the far end of the room a Power Word:
-- Shield that never lands is the same problem as a Flash Heal that
-- doesn't. Only single-target-at-a-friendly spells are listed — a
-- self-centered Holy Nova or Tranquility has no ally to be out of range
-- of, so it can never produce this error.
local HEAL_SPELLS = {
    -- Priest
    { 2050, "Lesser Heal" }, { 2054, "Heal" }, { 2060, "Greater Heal" },
    { 2061, "Flash Heal" }, { 139, "Renew" }, { 596, "Prayer of Healing" },
    { 33076, "Prayer of Mending" }, { 32546, "Binding Heal" },
    { 34861, "Circle of Healing" }, { 17, "Power Word: Shield" },
    -- Druid
    { 5185, "Healing Touch" }, { 8936, "Regrowth" }, { 774, "Rejuvenation" },
    { 18562, "Swiftmend" }, { 33763, "Lifebloom" },
    -- Paladin
    { 635, "Holy Light" }, { 19750, "Flash of Light" },
    { 20473, "Holy Shock" }, { 633, "Lay on Hands" },
    -- Shaman
    { 331, "Healing Wave" }, { 8004, "Lesser Healing Wave" },
    { 1064, "Chain Heal" }, { 974, "Earth Shield" },
}

-- Every watched failure. `errors` are GLOBAL STRING KEYS, read off the
-- client so the match is locale-safe, each with the word that describes
-- the state when the line names it; `floor` is the English text used only
-- when the client answered for none of that entry's keys.
--
-- ALLY entries whisper the person the cast was aimed at and are heals-only:
-- you whisper an ally about a blocked heal, not about a blocked Frostbolt.
-- SELF entries speak to the group and apply to any cast, because running
-- dry is running dry whatever you were pressing.
local FAILURES = {
    {
        key = "RANGE", setting = "RangeWhisper", blame = "ALLY",
        -- The one reason with a second opinion available: UnitInRange can
        -- confirm the blame before it is assigned
        confirm = "OUT_OF_RANGE",
        errors = { { "SPELL_FAILED_OUT_OF_RANGE" }, { "ERR_OUT_OF_RANGE" },
                   { "ERR_SPELL_OUT_OF_RANGE" } },
        floor = "Out of range.",
        Message = function(count, link)
            if link then
                return string.format(
                    "Out of healing range — %d casts didn't reach you (last: %s). Move closer!",
                    count, link)
            end
            return string.format(
                "Out of healing range — %d heals didn't reach you. Move closer!", count)
        end,
    },
    {
        key = "SIGHT", setting = "SightWhisper", blame = "ALLY",
        -- Nothing in the API answers "can I see that unit", so this one
        -- rests on group membership alone
        confirm = "IN_GROUP",
        errors = { { "SPELL_FAILED_LINE_OF_SIGHT" }, { "ERR_SPELL_OUT_OF_RANGE_LOS" } },
        floor = "Target not in line of sight.",
        Message = function(count, link)
            if link then
                return string.format(
                    "No line of sight — %d casts blocked (last: %s). I can't see you!",
                    count, link)
            end
            return string.format(
                "No line of sight — %d heals blocked. I can't see you!", count)
        end,
    },
    {
        key = "POWER", setting = "PowerCallouts", blame = "SELF",
        -- A rogue is out of energy every few seconds and a warrior lives
        -- there; only a mana bar running dry is news
        manaOnly = true,
        -- Comms already knows how to say this: the voiced /oom, with the
        -- cooldown and the re-arm the auto-emote uses. An empty bar is the
        -- same announcement whether a percentage or a refused cast noticed
        -- it first, so it goes out through the same door and cannot be
        -- said twice.
        emote = "OOM",
        errors = { { "SPELL_FAILED_NO_POWER" }, { "ERR_OUT_OF_MANA" },
                   { "SPELL_FAILED_NO_MANA" } },
        floor = "Not enough mana.",
        Message = function() return "Out of mana — I can't cast." end,
    },
    {
        key = "CONTROL", setting = "ControlCallouts", blame = "SELF",
        cooldown = 15,
        -- Named, because "peel me" and "dispel me" are different requests.
        -- Silence is absent on purpose: the kicked-on-me callout already
        -- reports it with the school and how long it lasts, which is
        -- strictly more than this could say.
        errors = { { "SPELL_FAILED_STUNNED", "stunned" },
                   { "SPELL_FAILED_CONFUSED", "confused" },
                   { "SPELL_FAILED_FLEEING", "feared" },
                   { "SPELL_FAILED_CHARMED", "charmed" } },
        Message = function(_, _, detail)
            return string.format("Can't cast — I'm %s. Peel!", detail or "crowd controlled")
        end,
    },
}

local SELF_COOLDOWN = 30    -- default gap between repeats of a SELF callout

local healSpells = {}     -- localized spell name -> true, of the ones you KNOW
local failureByError = {} -- the client's own error text -> { def, detail }
local sentCasts = {}      -- castGUID -> { target, spellID, at }
local streaks = {}        -- def.key .. guid -> { count, at, whisperedAt, spell... }
local selfSpokeAt = {}    -- def.key -> when that callout last went out
local pendingFail         -- a failed cast waiting to learn why it failed
local pendingError        -- a watched failure waiting to learn whose cast

-- Name-keyed like the rest of the suite: BindClick and the spellbook both
-- work in names, and one entry per spell beats five entries per rank that
-- go stale every time you train the next one.
local function RefreshHealSpells()
    healSpells = {}
    local known, readable = {}, false
    if GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName then
        readable = true
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, numSlots = GetSpellTabInfo(tab)
            for i = (offset or 0) + 1, (offset or 0) + (numSlots or 0) do
                local name = GetSpellBookItemName(i, "spell")
                if name then known[name] = true end
            end
        end
    end
    for _, def in ipairs(HEAL_SPELLS) do
        local name = (GetSpellInfo and GetSpellInfo(def[1])) or def[2]
        -- A spellbook we could not read at all must not silently disarm the
        -- whole feature: fall back to the canon, which no non-healer knows
        if name and (known[name] or not readable) then healSpells[name] = true end
    end
end

-- Resolved from the client's own localized strings, so every match survives
-- a non-English client. The English floor is used only for an entry the
-- client answered for not at all — a key a future patch renames.
local function BuildFailureIndex()
    failureByError = {}
    for _, def in ipairs(FAILURES) do
        local resolved = false
        for _, entry in ipairs(def.errors) do
            local text = _G[entry[1]]
            if type(text) == "string" and text ~= "" then
                failureByError[text] = { def = def, detail = entry[2] }
                resolved = true
            end
        end
        if not resolved and def.floor then
            failureByError[def.floor] = { def = def }
        end
    end
end

-- UnitInRange answers for group members only, and its SECOND return says
-- whether it answered at all — which makes it two tests in one call: "is
-- this someone in my group" and "are they too far away"
local function RangeState(unit)
    if not UnitInRange then return nil end
    local inRange, checked = UnitInRange(unit)
    if not checked then return nil end
    return inRange and true or false
end

local function PassesConfirm(def, unit)
    local inRange = RangeState(unit)
    if inRange == nil then return false end          -- not a group member
    if def.confirm == "OUT_OF_RANGE" then return inRange == false end
    return true                                       -- IN_GROUP is enough
end

-- Cross-realm allies come through as Name-Realm from some callers and bare
-- from others; the part before the dash is the half both agree on
local function BareName(name)
    if not name then return nil end
    local cut = string.find(name, "-", 1, true)
    return cut and string.sub(name, 1, cut - 1) or name
end

-- ...but the whisper itself has to carry the realm, or a battleground ally
-- from another server never receives it
local function WhisperName(unit)
    local name, realm = UnitName(unit)
    if not name then return nil end
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

local function EachGroupUnit(fn)
    local prefix, count = "party", GetNumSubgroupMembers()
    if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
    for i = 1, (count or 0) do
        local unit = prefix .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local result = fn(unit)
            if result then return result end
        end
    end
    return nil
end

local function AllyByName(name)
    local want = BareName(name)
    if not want then return nil end
    return EachGroupUnit(function(unit)
        if BareName(UnitName(unit)) == want then return unit end
    end)
end

-- The fallback aim: no cast event named the target, so it has to be
-- inferred. The three unit tokens come first because they are the ones a
-- press can actually have been aimed through: @mouseover (including
-- hovering a party frame, which sets the token), @target and @focus.
local function AimedAlly(def)
    for _, unit in ipairs({ "mouseover", "target", "focus" }) do
        if UnitExists(unit) and UnitIsPlayer(unit) and not UnitIsUnit(unit, "player")
            and UnitIsFriend and UnitIsFriend("player", unit) and PassesConfirm(def, unit) then
            return unit
        end
    end
    -- Last resort for a @party1-style macro pressed while pointing at
    -- nothing, and only where the client can confirm the blame: if exactly
    -- ONE person in the group is out of range there is no one else the
    -- error could have been about. Two and the answer is a guess, so nobody
    -- is named — a whisper to the wrong person is worse than no whisper at
    -- all. Line of sight has no such test, so it never guesses.
    if def.confirm ~= "OUT_OF_RANGE" then return nil end
    local only
    EachGroupUnit(function(unit)
        if UnitIsPlayer(unit) and RangeState(unit) == false then
            if only then only = false; return true end
            only = unit
        end
    end)
    return only or nil
end

local function SweepStreaks(now)
    for id, streak in pairs(streaks) do
        -- Kept past the streak window until the whisper cooldown has also
        -- run out, or resetting the run would forget that we just spoke
        if now - streak.at > FAIL_STREAK_WINDOW
            and now - streak.whisperedAt > (CommanderCommsDB.RangeWhisperCooldown or 45) then
            streaks[id] = nil
        end
    end
end

-- A heal that lands is the answer to every nag on that ally: whatever the
-- runs were, they are over. Called for direct heals and HoT ticks alike.
local function NoteHealLanded(destGUID)
    if not destGUID then return end
    for _, def in ipairs(FAILURES) do
        local streak = streaks[def.key .. destGUID]
        if streak then streak.count = 0 end
    end
end

local function ForgetAlly(destGUID)
    if not destGUID then return end
    for _, def in ipairs(FAILURES) do
        streaks[def.key .. destGUID] = nil
    end
end

local function OnAllyFailure(def, unit, spellID, spellName)
    local guid = UnitGUID(unit)
    if not guid then return end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then return end
    local now = GetTime()
    SweepStreaks(now)
    local id = def.key .. guid
    local streak = streaks[id]
    if not streak or now - streak.at > FAIL_STREAK_WINDOW then
        streak = { count = 0, whisperedAt = -math.huge }
        streaks[id] = streak
    elseif now - streak.at < FAIL_MIN_GAP then
        -- The same press reported twice (the error and the cast failure can
        -- both reach the fallback path); it is still one press
        return
    end
    streak.count = streak.count + 1
    streak.at = now

    local needed = CommanderCommsDB.RangeWhisperStreak or 4
    if streak.count < needed then return end
    if now - streak.whisperedAt < (CommanderCommsDB.RangeWhisperCooldown or 45) then return end
    local to = WhisperName(unit)
    if not to then return end
    streak.whisperedAt = now
    -- The run resets on the nag: one whisper per stretch of being blocked,
    -- not one per press from here on
    local count = streak.count
    streak.count = 0

    SendChatMessage(def.Message(count, SpellLink(spellID, spellName)), "WHISPER", nil, to)
end

-- Your own state, so there is nobody to whisper: it goes to the group like
-- every other automatic callout, battleground rule and all.
local function OnSelfFailure(def, detail)
    if not InAnyGroup() then return end
    -- A rogue out of energy is not news; a healer's empty mana bar is
    if def.manaOnly and UnitPowerType and UnitPowerType("player") ~= 0 then return end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
    if def.emote then
        -- Straight into the voiced call Comms already owns, which carries
        -- its own cooldown and its own re-arm (and so cannot repeat what
        -- the mana-percentage trigger has just said)
        TryAutoEmote(def.emote)
        return
    end
    local now = GetTime()
    if now - (selfSpokeAt[def.key] or -math.huge) < (def.cooldown or SELF_COOLDOWN) then return end
    local channel = CalloutChannel()
    if not channel then return end
    selfSpokeAt[def.key] = now
    SendChatMessage(def.Message(1, nil, detail), channel)
end

local function FailureOn(def)
    return CommanderCommsDB and CommanderCommsDB.EnableComms
        and CommanderCommsDB[def.setting]
end

-- Both halves of the evidence are in: a cast of ours failed, and the reason
-- was one we watch. Fires once and clears both stamps.
local function ResolvePairedFail()
    if not (pendingError and pendingFail) then return end
    local now = GetTime()
    if math.abs(pendingError.at - pendingFail.at) > FAIL_PAIR_WINDOW then return end
    if now - pendingError.at > FAIL_PAIR_WINDOW then return end
    local def, fail = pendingError.def, pendingFail
    pendingError, pendingFail = nil, nil
    if not healSpells[fail.spellName or ""] then return end
    -- A named target is the client's own answer and is taken as final: if it
    -- resolves to nobody in the group (healing a stranger in the world) the
    -- nag is dropped rather than pinned on whoever else happens to be
    -- blocked. Only a cast that named no one at all falls through to the aim.
    local unit
    if fail.target and fail.target ~= "" then
        unit = AllyByName(fail.target)
    else
        unit = AimedAlly(def)
    end
    if unit then OnAllyFailure(def, unit, fail.spellID, fail.spellName) end
end

-- No cast event ever paired with the error. The spell is unknown on this
-- path, so the nag rests entirely on the aim: a group member the client
-- itself confirms is blocked, which a heal is the overwhelmingly likely
-- thing to have been aimed at.
local function ResolveLoneError(stamp)
    if pendingError ~= stamp then return end
    local def = stamp.def
    pendingError = nil
    if not FailureOn(def) then return end
    local unit = AimedAlly(def)
    if unit then OnAllyFailure(def, unit, nil, nil) end
end

local function AnyAllyFailureOn()
    for _, def in ipairs(FAILURES) do
        if def.blame == "ALLY" and FailureOn(def) then return true end
    end
    return false
end

local function OnCastSent(target, castGUID, spellID)
    if not AnyAllyFailureOn() then return end
    local now = GetTime()
    for guid, cast in pairs(sentCasts) do
        if now - cast.at > SENT_MEMORY then sentCasts[guid] = nil end
    end
    if castGUID then
        sentCasts[castGUID] = { target = target, spellID = spellID, at = now }
    end
end

local function OnCastFailed(castGUID, spellID)
    if not AnyAllyFailureOn() then return end
    local sent = castGUID and sentCasts[castGUID]
    if sent then sentCasts[castGUID] = nil end
    local id = spellID or (sent and sent.spellID)
    local name = id and GetSpellInfo and GetSpellInfo(id) or nil
    pendingFail = { target = sent and sent.target, spellID = id, spellName = name,
        at = GetTime() }
    ResolvePairedFail()
end

local function OnUIError(message)
    local hit = failureByError[message or ""]
    if not hit then return end
    local def = hit.def
    if not FailureOn(def) then return end
    if def.blame == "SELF" then
        OnSelfFailure(def, hit.detail)
        return
    end
    local stamp = { at = GetTime(), def = def }
    pendingError = stamp
    ResolvePairedFail()
    -- Give the cast events their chance to arrive before falling back to
    -- reading the aim off the unit tokens
    C_Timer.After(FAIL_PAIR_WINDOW, function() ResolveLoneError(stamp) end)
end


-- ---------------------------------------------------------------------------
-- Support calls: the other direction. The callouts above are about what
-- went wrong; this is about something you did FOR one person that only
-- works if they notice.
--
-- Power Infusion is twenty seconds of haste that does nothing if the mage
-- is drinking. Innervate is mana handed to someone who has stopped casting
-- because they had none. Intervene is a hit you are about to take for
-- somebody who is still running. Every spell in the list is deliberate,
-- situational, spent on ONE named ally, and useless unless that ally acts
-- on it — which is exactly the shape of a whisper, and exactly why this is
-- the one whisper that ships switched on.
--
-- Each says what it MEANS rather than just naming itself: "stop attacking"
-- and "burn it now" are the message, and the spell link is there so they
-- can hover it. Drawn from your own spellbook like the heals, so a priest
-- never carries the paladin lines.
-- ---------------------------------------------------------------------------
local SUPPORT_REPEAT = 20   -- same spell on the same ally inside this is one

-- { base id, English floor, the line }. The line is what the ally has to
-- DO; naming the spell alone would make them read the tooltip mid-fight.
local SUPPORT_CASTS = {
    -- Priest
    { 10060, "Power Infusion", "%s on you — burn it now!" },
    { 33206, "Pain Suppression", "%s on you — big damage cut, hold on." },
    { 6346, "Fear Ward", "%s on you — the next fear is blocked." },
    -- Druid
    { 29166, "Innervate", "%s on you — cast freely, the mana is on me." },
    -- Warrior
    { 3411, "Intervene", "%s — I'm taking the next hit for you." },
    -- Paladin
    { 1022, "Blessing of Protection", "%s on you — physical immune, stop attacking." },
    { 1044, "Blessing of Freedom", "%s on you — you're free to move." },
    { 6940, "Blessing of Sacrifice", "%s on you — I'm eating a share of your damage." },
    { 19752, "Divine Intervention", "%s on you — you're safe, I'm out. Res us." },
    { 633, "Lay on Hands", "%s on you — that was the big one, it's gone now." },
    -- Hunter
    { 34477, "Misdirection", "%s on you — threat is coming your way, be ready." },
    -- Warlock
    { 20707, "Soulstone Resurrection", "%s on you — take it if we go down." },
}

local supportCasts = {}   -- localized spell name -> the line to whisper
local supportSaidAt = {}  -- spell name .. ally GUID -> when

local function RefreshSupportCasts()
    supportCasts = {}
    local known, readable = {}, false
    if GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName then
        readable = true
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, numSlots = GetSpellTabInfo(tab)
            for i = (offset or 0) + 1, (offset or 0) + (numSlots or 0) do
                local name = GetSpellBookItemName(i, "spell")
                if name then known[name] = true end
            end
        end
    end
    for _, def in ipairs(SUPPORT_CASTS) do
        local name = (GetSpellInfo and GetSpellInfo(def[1])) or def[2]
        if name and (known[name] or not readable) then supportCasts[name] = def[3] end
    end
end

local function AllyByGUID(guid)
    if not guid then return nil end
    return EachGroupUnit(function(unit)
        if UnitGUID(unit) == guid then return unit end
    end)
end

local function OnSupportCast(destGUID, spellName, spellID)
    if not (CommanderCommsDB.SupportWhisper and spellName) then return end
    local line = supportCasts[spellName]
    if not line then return end
    -- Only a real group member, and never yourself: a Fear Ward on your own
    -- head is not news to you
    local me = playerGUID or UnitGUID("player")
    if not destGUID or destGUID == me then return end
    local unit = AllyByGUID(destGUID)
    if not unit then return end
    local now = GetTime()
    local id = spellName .. destGUID
    -- Sweep as we go: one entry per spell per ally, aged on use
    for key, at in pairs(supportSaidAt) do
        if now - at > SUPPORT_REPEAT then supportSaidAt[key] = nil end
    end
    if now - (supportSaidAt[id] or -math.huge) < SUPPORT_REPEAT then return end
    local to = WhisperName(unit)
    if not to then return end
    supportSaidAt[id] = now
    SendChatMessage(string.format(line, SpellLink(spellID, spellName)), "WHISPER", nil, to)
end

-- ---------------------------------------------------------------------------
-- Mana burn callouts: the arena's quietest kill. Nobody dies — the healer
-- just runs dry — and a Mana Burn landing on a teammate puts nothing in
-- YOUR chat, so the DPS partner finds out when the heals stop. The combat
-- log does report it: every drain of a unit's power is a SPELL_DRAIN (or
-- LEECH, or the periodic pair for Viper Sting and Drain Mana) carrying
-- the amount and the power type at args 15 and 16, the same three-arg
-- suffix on this client as on the old one. Any of those on a group
-- member's MANA is announced: who, how much, by whom and with what, and
-- the number that actually decides the game — how much they have left,
-- read off their unit frame a beat after the event so the bar has caught
-- up.
--
-- Two guards keep it a callout and not a ticker. Drains under a share of
-- the victim's bar are accumulated rather than announced, so a Viper
-- Sting is one line when its ticks add up and a Mana Burn is one line on
-- the first cast; and each victim gets one line per cooldown window
-- carrying the total of everything burned since the last, so a priest
-- chaining burns every three seconds reads as a trend rather than a
-- scroll. Same audience rules as the other group callouts, including the
-- battleground silence.
-- ---------------------------------------------------------------------------
local BURN_EVENTS = {
    SPELL_DRAIN = true, SPELL_LEECH = true,
    SPELL_PERIODIC_DRAIN = true, SPELL_PERIODIC_LEECH = true,
}
local MANA_POWER = 0            -- Enum.PowerType.Mana, the log's powerType arg
local BURN_WINDOW = 6           -- ticks this close together are one drain
local BURN_READ_DELAY = 0.2     -- the victim's bar updates a beat after the log
local BURN_FLOOR = 250          -- threshold when the victim's max mana can't be read

local burns = {}   -- victimGUID -> { unit, name, total, hits, since, saidAt,
                   --                 pending, source, spellName, spellID }

local function FormatAmount(amount)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(amount) end
    return tostring(amount)
end

-- The share of the bar a drain has to reach before it is worth a line
local function BurnThreshold(unit)
    local max = UnitPowerMax(unit, MANA_POWER) or 0
    if max <= 0 then return BURN_FLOOR end
    return max * (CommanderCommsDB.ManaBurnMinPercent or 0.05)
end

local function ManaLeftPercent(unit)
    local max = UnitPowerMax(unit, MANA_POWER) or 0
    if max <= 0 then return nil end
    return math.floor((UnitPower(unit, MANA_POWER) or 0) / max * 100 + 0.5)
end

local function AnnounceBurn(guid)
    local burn = burns[guid]
    if not burn then return end
    burn.pending = false
    local total, hits, since = burn.total, burn.hits, burn.since
    burn.total, burn.hits, burn.since = 0, 0, nil
    if total <= 0 or not CommanderCommsDB.ManaBurnCallouts then return end
    local channel = CalloutChannel()
    if not channel then return end
    -- The unit token can have moved since the event (a raid reshuffle);
    -- resolve the victim again rather than reporting somebody else's bar
    local me = playerGUID or UnitGUID("player")
    local unit = guid == me and "player" or AllyByGUID(guid)
    if not unit or (UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)) then return end
    burn.saidAt = GetTime()

    local who = guid == me and "I got mana burned" or ((burn.name or UnitName(unit)) .. " mana burned")
    local amount = FormatAmount(total)
    if hits > 1 then
        local span = since and math.max(1, math.floor(GetTime() - since + 0.5)) or nil
        amount = amount .. (span and string.format(" (%d hits in %ds)", hits, span)
            or string.format(" (%d hits)", hits))
    end
    local by = burn.source and (" by " .. burn.source) or ""
    local link = SpellLink(burn.spellID, burn.spellName)
    local with = link and (" with " .. link) or ""
    local left = ManaLeftPercent(unit)
    local tail = left and string.format(" — %d%% mana left.", left) or "."
    SendChatMessage(string.format("%s for %s%s%s%s", who, amount, by, with, tail), channel)
end

local function OnManaBurn(sourceGUID, sourceName, sourceFlags, destGUID, destName,
                          spellID, spellName, amount, powerType)
    if not CommanderCommsDB.ManaBurnCallouts then return end
    if powerType ~= MANA_POWER or type(amount) ~= "number" or amount <= 0 then return end
    local me = playerGUID or UnitGUID("player")
    local unit = destGUID == me and "player" or AllyByGUID(destGUID)
    if not unit then return end
    local now = GetTime()
    local burn = burns[destGUID]
    if not burn then
        burn = { total = 0, hits = 0, saidAt = -math.huge }
        burns[destGUID] = burn
    end
    -- A quiet stretch between two drains makes the second one a fresh
    -- drain, not a continuation — unless a line is already on its way, in
    -- which case it rides along
    if not burn.pending and burn.since and now - burn.since > BURN_WINDOW then
        burn.total, burn.hits = 0, 0
    end
    if burn.hits == 0 then burn.since = now end
    burn.total = burn.total + amount
    burn.hits = burn.hits + 1
    burn.name = destName
    -- The latest drainer is the one worth naming: it is the one still casting
    burn.source = DescribeSource(sourceGUID, sourceName, sourceFlags)
    burn.spellName, burn.spellID = spellName, spellID
    if burn.pending or burn.total < BurnThreshold(unit) then return end
    -- Say it as soon as the bar has caught up, or at the end of this
    -- victim's cooldown window with everything burned by then
    local cooldown = CommanderCommsDB.ManaBurnCooldown or 8
    local delay = math.max(BURN_READ_DELAY, burn.saidAt + cooldown - now)
    burn.pending = true
    C_Timer.After(delay, function() AnnounceBurn(destGUID) end)
end

local function OnCombatLog()
    if not (CommanderCommsDB and CommanderCommsDB.EnableComms) then return end
    local _, subevent, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags, _,
        actionID, actionName, _, extraID, extraName, extraSchool, auraType = CombatLogGetCurrentEventInfo()

    -- CC bookkeeping watches everyone's events, not just the player's —
    -- the whole point is catching OTHER people's breaks
    if actionName and CC_AURAS[actionName] then
        if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
            TrackCC(sourceGUID, sourceName, destGUID, actionName)
        elseif subevent == "SPELL_AURA_REMOVED" then
            UntrackCC(destGUID, actionName)
        elseif subevent == "SPELL_AURA_BROKEN" or subevent == "SPELL_AURA_BROKEN_SPELL" then
            -- Plain BROKEN is a melee-swing break and carries no extra
            -- spell (arg16 is nil there anyway, but be explicit)
            OnCCBroken(sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags,
                actionName, actionID,
                subevent == "SPELL_AURA_BROKEN_SPELL" and extraName or nil,
                subevent == "SPELL_AURA_BROKEN_SPELL" and extraID or nil)
        end
    elseif subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" then
        trackedCC[destGUID] = nil
        -- A channel that stopped because its caster died is not a kick
        channels[destGUID] = nil
        -- ...and an ally who died was not ignoring you, whatever the run said
        ForgetAlly(destGUID)
        -- ...nor is a dead healer's mana anybody's concern now
        burns[destGUID] = nil
    end

    local me = playerGUID or UnitGUID("player")
    -- Team comms only: solo callouts have no audience
    if not InAnyGroup() then return end

    -- A drain on a teammate's mana is anybody's event against anybody in
    -- the group, so it is checked before either GUID gate. The drain suffix
    -- puts amount and powerType where the extra spell usually sits.
    if BURN_EVENTS[subevent] then
        OnManaBurn(sourceGUID, sourceName, sourceFlags, destGUID, destName,
            actionID, actionName, extraID, extraName)
        return
    end

    -- The kicked-on-me callout is the mirror image — the source is the
    -- enemy — so it is handled before the player-source gate below
    if destGUID == me and sourceGUID ~= me then
        if subevent == "SPELL_INTERRUPT" then
            realInterruptAt[me] = GetTime()
            channels[me] = nil
            OnKickedOnMe({ sourceGUID = sourceGUID, sourceName = sourceName,
                sourceFlags = sourceFlags, kickName = actionName, kickID = actionID,
                spellName = extraName, spellID = extraID, school = extraSchool })
        elseif actionName and INTERRUPT_SPELLS[actionName] then
            -- ...and a kick on a channel of yours is as silent in the log
            -- as one of your own, so it is inferred the same way
            if subevent == "SPELL_CAST_SUCCESS" then
                local ctx = { victimGUID = me, incoming = true, castAt = GetTime(),
                    sourceGUID = sourceGUID, sourceName = sourceName,
                    sourceFlags = sourceFlags, kickName = actionName, kickID = actionID }
                C_Timer.After(KICK_CONFIRM_DELAY, function() ConfirmChannelKick(ctx) end)
            elseif subevent == "SPELL_MISSED" then
                kickMissedAt[me] = GetTime()
            end
        end
    end

    if sourceGUID ~= me then return end
    if subevent == "SPELL_INTERRUPT" then
        if destGUID then
            realInterruptAt[destGUID] = GetTime()
            channels[destGUID] = nil
        end
        OnInterrupt(destName, actionName, actionID, extraName, extraID)
    elseif subevent == "SPELL_DISPEL" then
        OnDispel(destName, actionName, actionID, extraName, extraID, auraType)
    elseif subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
        -- A heal that landed answers the range nag: the run is over
        NoteHealLanded(destGUID)
    elseif subevent == "SPELL_CAST_SUCCESS" and actionName and supportCasts[actionName] then
        -- The cast, not the aura: Intervene and Misdirection put nothing on
        -- the ally at all, so the aura events would miss exactly the two
        -- that matter most
        OnSupportCast(destGUID, actionName, actionID)
    elseif actionName and INTERRUPT_SPELLS[actionName] and destGUID then
        -- The channel half of the interrupt callouts: the kick reports
        -- itself, the stopped channel has to be inferred
        if subevent == "SPELL_CAST_SUCCESS" then
            local ctx = { victimGUID = destGUID, victimName = destName, castAt = GetTime(),
                kickName = actionName, kickID = actionID }
            C_Timer.After(KICK_CONFIRM_DELAY, function() ConfirmChannelKick(ctx) end)
        elseif subevent == "SPELL_MISSED" then
            kickMissedAt[destGUID] = GetTime()
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
-- Deliberately unfiltered: the channels worth kicking belong to whoever
-- currently has a unit token, not to the player
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
-- The range nag's two halves: why a cast failed (the UI error) and whose
-- cast it was (the cast events). FAILED_QUIET is the client refusing a cast
-- it never sent, which is exactly the shape an out-of-range press takes, so
-- it matters as much as FAILED — soft-registered along with SPELLS_CHANGED
-- so a client missing either still loads the rest of the file.
events:RegisterEvent("UI_ERROR_MESSAGE")
for _, e in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_FAILED",
                     "UNIT_SPELLCAST_FAILED_QUIET", "SPELLS_CHANGED" }) do
    pcall(events.RegisterEvent, events, e)
end
-- Player-only registration: these fire constantly for every visible unit
if events.RegisterUnitEvent then
    events:RegisterUnitEvent("UNIT_HEALTH", "player")
    events:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
else
    events:RegisterEvent("UNIT_HEALTH")
    events:RegisterEvent("UNIT_POWER_UPDATE")
end
-- arg2/arg3 exist for two events only: UNIT_SPELLCAST_SENT hands over
-- (unit, targetName, castGUID, spellID) — the target name is the ONLY place
-- the client says who a cast was aimed at — and the FAILED pair reports
-- (unit, castGUID, spellID), which is how a failure finds its target again.
events:SetScript("OnEvent", function(self, event, unit, arg2, arg3, arg4)
    if event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player")
        BuildFailureIndex()
        RefreshHealSpells()
        RefreshSupportCasts()
        Commander.AddListener(COMMANDER_COMMS_EVENTS.UPDATE, function()
            if not CommanderCommsDB.EnableComms then
                wheel:Hide()
            end
        end)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
    elseif event == "SPELLS_CHANGED" then
        -- Training a rank, respeccing, or a fresh login's spellbook arriving
        RefreshHealSpells()
        RefreshSupportCasts()
    elseif event == "UI_ERROR_MESSAGE" then
        -- (unit, arg2) is really (messageType, message) for this one
        OnUIError(arg2)
    elseif event == "UNIT_SPELLCAST_SENT" then
        if unit == "player" then OnCastSent(arg2, arg3, arg4) end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
        if unit == "player" then OnCastFailed(arg2, arg3) end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        NoteChannelStart(unit)
    elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        NoteChannelUpdate(unit)
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        NoteChannelStop(unit)
    elseif unit == "player" then
        CheckAutoEmotes()
    end
end)
