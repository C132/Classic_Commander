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
    SendChatMessage(message, PickChannel())
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
            PickChannel())
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
    SendChatMessage(message, PickChannel())
end

-- ---------------------------------------------------------------------------
-- CC break callouts: the "who broke my sheep?" alarm. The combat log's
-- SPELL_AURA_BROKEN(_SPELL) events name the breaker but not who owned the
-- aura, so applications of known crowd control are remembered per victim;
-- when one breaks early the announcement can say whose CC died, who killed
-- it, and with what. Two scopes: your own CC only (default), or every CC
-- broken in combat-log range. Group channels only, same as the rest.
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

local function TrackCC(sourceGUID, sourceName, destGUID, auraName)
    if not CommanderCommsDB.CCBreakCallouts then return end
    local now = GetTime()
    -- The table stays tiny (one entry per live CC), so aging it out on
    -- each new application is cheaper than owning a ticker
    SweepTrackedCC(now)
    -- The succubus casts Seduction, not the warlock: my pet's CC is mine
    local mine = sourceGUID ~= nil
        and (sourceGUID == (playerGUID or UnitGUID("player"))
            or sourceGUID == UnitGUID("pet"))
    trackedCC[destGUID] = trackedCC[destGUID] or {}
    trackedCC[destGUID][auraName] = { caster = sourceName, mine = mine, at = now }
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
    local prefix, count = "party", GetNumSubgroupMembers()
    if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
    for i = 1, count do
        if UnitGUID(prefix .. "pet" .. i) == sourceGUID then
            local owner = UnitName(prefix .. i)
            if owner then return owner .. "'s pet" end
            break
        end
    end
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
    if not (mine or CommanderCommsDB.CCBreakAll) then return end
    if not InAnyGroup() then return end
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
        SpellLink(auraID, auraName), destName or "the target", how), PickChannel())
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
    end

    local me = playerGUID or UnitGUID("player")
    -- Team comms only: solo callouts have no audience
    if not InAnyGroup() then return end

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
