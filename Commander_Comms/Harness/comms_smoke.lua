-- Commander Comms smoke (luajit):
--     luajit comms_smoke.lua
--
-- Covers the 2.3.0 callout work: spell links in the interrupt, cleanse and
-- CC-break announcements (and every fallback down to a bare name), the
-- kicked-on-me callout (school, lockout seconds, kicker class), and the
-- inferred channel kick
-- — the one the combat log never reports — with its false-positive guards
-- (natural end, missed kick, dead caster, a real SPELL_INTERRUPT already
-- covering it). Mock modeled on Commander_Chat/Harness.

local ADDONS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end

-- ===========================================================================
-- WoW mock
-- ===========================================================================

local now = 1000
function GetTime() return now end

print = function() end

local NUMERIC_GETTERS = {
    GetWidth = 0, GetHeight = 0, GetScale = 1, GetStringWidth = 10, GetNumPoints = 1,
}

local eventRegistry = {}
local NewWidget

local WidgetMT = {}
WidgetMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
    if NUMERIC_GETTERS[key] ~= nil then
        local v = NUMERIC_GETTERS[key]
        local fn = function() return v end
        rawset(self, key, fn); return fn
    end
    if key == "SetText" then
        local fn = function(s, text) s.__text = text end
        rawset(self, key, fn); return fn
    end
    if key == "GetText" then
        local fn = function(s) return s.__text end
        rawset(self, key, fn); return fn
    end
    if key == "Show" then
        local fn = function(s) s.__shown = true end
        rawset(self, key, fn); return fn
    end
    if key == "Hide" then
        local fn = function(s) s.__shown = false end
        rawset(self, key, fn); return fn
    end
    if key == "IsShown" or key == "IsVisible" then
        local fn = function(s) return s.__shown end
        rawset(self, key, fn); return fn
    end
    if key == "CreateTexture" or key == "CreateFontString" then
        local fn = function(s)
            local t = NewWidget(key == "CreateTexture" and "Texture" or "FontString")
            t.__parent = s
            return t
        end
        rawset(self, key, fn); return fn
    end
    if key == "SetScript" or key == "HookScript" then
        local fn = function(s, name, handler) s.__scripts[name] = handler end
        rawset(self, key, fn); return fn
    end
    if key == "GetScript" then
        local fn = function(s, name) return s.__scripts[name] end
        rawset(self, key, fn); return fn
    end
    if key == "RegisterEvent" or key == "RegisterUnitEvent" then
        local fn = function(s, event)
            eventRegistry[event] = eventRegistry[event] or {}
            table.insert(eventRegistry[event], s)
        end
        rawset(self, key, fn); return fn
    end
    -- Everything else a frame is asked to do is a no-op here
    local fn = function() end
    rawset(self, key, fn); return fn
end

NewWidget = function(kind, name)
    return setmetatable({ __kind = kind, __name = name, __scripts = {}, __shown = false }, WidgetMT)
end

function CreateFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name)
    f.__template = template
    f.__parent = parent
    if name then _G[name] = f end
    return f
end

UIParent = NewWidget("Frame", "UIParent")
UISpecialFrames = {}
GameFontNormalLarge = NewWidget("Font")
GameFontHighlightSmall = NewWidget("Font")
SOUNDKIT = { IG_CHARACTER_INFO_TAB = 841 }
function PlaySound() end

local timers = {}
C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end,
    NewTicker = function() return { Cancel = function() end } end,
}
local function Advance(seconds)
    now = now + seconds
    for _, t in ipairs(timers) do
        if not t.done and t.at <= now then
            t.done = true
            t.fn()
        end
    end
end

bit = bit or require("bit")
COMBATLOG_OBJECT_TYPE_PET = 0x00001000
COMBATLOG_OBJECT_TYPE_PLAYER = 0x00000400
COMBATLOG_OBJECT_REACTION_FRIENDLY = 0x00000010
local HOSTILE = 0x00000040

-- Group state the tests drive
local inGroup, inRaid = true, false
-- The instance-category form is a separate question: this mock is a party,
-- not a battleground
function IsInGroup(category) if category then return false end return inGroup end
function IsInRaid() return inRaid end
function GetNumSubgroupMembers() return inGroup and 2 or 0 end
function GetNumGroupMembers() return inGroup and 2 or 0 end
LE_PARTY_CATEGORY_INSTANCE = 2

local GUIDS = { player = "Player-1", target = "Creature-9", pet = nil }
function UnitGUID(unit) return GUIDS[unit] end
-- Class only resolves through a unit token pointing at the same GUID
local CLASSES = { focus = "Mage" }
function UnitClass(unit) return CLASSES[unit] end
function UnitName(unit) return unit == "player" and "Kicker" or "Pillager" end
function UnitExists(unit) return GUIDS[unit] ~= nil end
function UnitHealth() return 100 end
function UnitHealthMax() return 100 end
function UnitPower() return 100 end
function UnitPowerMax() return 100 end
function UnitPowerType() return 0 end
function UnitAffectingCombat() return true end
function UnitIsDeadOrGhost() return false end
function DoEmote() end

-- Channel state: what each unit token is channeling right now
local channelState = {}
function UnitChannelInfo(unit)
    local c = channelState[unit]
    if not c then return nil end
    return c.name, c.name, "tex", c.startAt * 1000, c.endsAt * 1000, false, nil, c.spellID
end
function UnitCastingInfo() return nil end

local SPELL_NAMES = {
    [6552] = "Pummel", [1766] = "Kick", [8042] = "Earth Shock",
    [116] = "Frostbolt", [15407] = "Mind Flay", [689] = "Drain Life",
    [1152] = "Purify", [1714] = "Curse of Tongues", [4987] = "Cleanse",
    [118] = "Polymorph", [845] = "Cleave", [2139] = "Counterspell",
}

-- School lockouts are readable only as a cooldown on the locked spell
local lockouts = {}   -- spellID -> { start, duration }
C_Spell = C_Spell or {}
function C_Spell.GetSpellCooldown(id)
    local cd = lockouts[id]
    if not cd then return nil end
    return { startTime = cd.start, duration = cd.duration }
end
function GetSpellCooldown(id)
    local cd = lockouts[id]
    if not cd then return 0, 0, 1 end
    return cd.start, cd.duration, 1
end
local function Lock(spellID, duration)
    lockouts[spellID] = { start = now, duration = duration }
end
local linkApi = "global"   -- "global" | "modern" | "none"
function GetSpellLink(id)
    if linkApi ~= "global" then return nil end
    local name = SPELL_NAMES[id]
    if not name then return nil end
    return string.format("|cff71d5ff|Hspell:%d|h[%s]|h|r", id, name)
end
C_Spell = C_Spell or {}
C_Spell.GetSpellLink = function(id)
    if linkApi ~= "modern" then return nil end
    local name = SPELL_NAMES[id]
    if not name then return nil end
    return string.format("|cff71d5ff|Hspell:%d|h[%s]|h|r", id, name)
end

local sent = {}
function SendChatMessage(msg, channel)
    sent[#sent + 1] = { msg = msg, channel = channel }
end
local function LastMessage()
    return sent[#sent] and sent[#sent].msg
end
local function ClearMessages() sent = {} end

-- The Commander framework surface this addon touches
Commander = { AddListener = function() end }

local cleuArgs = {}
-- Explicit length: an event with no spell id leaves a hole a plain
-- unpack() would truncate at
function CombatLogGetCurrentEventInfo() return unpack(cleuArgs, 1, cleuArgs.n or 18) end

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    local snap = {}
    for i, f in ipairs(list) do snap[i] = f end
    for _, frame in ipairs(snap) do
        local handler = frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

-- CLEU shape on this client: 11 base args, then spellId/spellName/school,
-- then the extra triplet, then auraType
local function CLEU(subevent, o)
    o = o or {}
    cleuArgs = {
        now, subevent, false,
        o.sourceGUID or GUIDS.player, o.sourceName or "Kicker", o.sourceFlags or 0, 0,
        o.destGUID or GUIDS.target, o.destName or "Pillager", o.destFlags or HOSTILE, 0,
        o.spellID, o.spellName, 0,
        o.extraID, o.extraName, o.extraSchool or 0,
        o.auraType,
    }
    -- Holes in the middle would truncate unpack; give it an explicit length
    cleuArgs.n = 18
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
end

-- ===========================================================================
-- Load
-- ===========================================================================

_G.CommanderCommsDB = {
    EnableComms = true, InterruptSilence = true, KickedCallouts = true,
    DispelCallouts = true,
    CCBreakCallouts = true, CCBreakAll = false, UseEmotes = true,
    IncludeTarget = true, CommsSound = false,
}
COMMANDER_COMMS_EVENTS = { UPDATE = "COMMANDER_COMMS_UPDATE" }

assert(loadfile(ADDONS .. "/Commander_Comms/CommanderComms.lua"))()
Fire("PLAYER_LOGIN")

local function StartChannel(unit, spellID, duration)
    channelState[unit] = {
        name = SPELL_NAMES[spellID], spellID = spellID,
        startAt = now, endsAt = now + duration,
    }
    Fire("UNIT_SPELLCAST_CHANNEL_START", unit)
end

local function StopChannel(unit)
    channelState[unit] = nil
    Fire("UNIT_SPELLCAST_CHANNEL_STOP", unit)
end

-- Each scenario starts past the 2s announce cooldown of the last one
local function Scenario()
    Advance(5)
    ClearMessages()
end

-- ===========================================================================
-- Spell links on the plain (cast-bar) interrupt
-- ===========================================================================

Scenario()
CLEU("SPELL_INTERRUPT", { spellID = 6552, spellName = "Pummel",
    extraID = 116, extraName = "Frostbolt" })
local msg = LastMessage()
CHECK(msg and msg:find("|Hspell:116|h[Frostbolt]|h", 1, true),
    "interrupt: the stopped spell goes out as a link", msg)
CHECK(msg and msg:find("|Hspell:6552|h[Pummel]|h", 1, true),
    "interrupt: the kick goes out as a link", msg)
CHECK(msg and msg:find("Pillager's", 1, true), "interrupt: still names the target", msg)
CHECK(sent[1] and sent[1].channel == "PARTY", "interrupt: routed to the group channel",
    sent[1] and sent[1].channel)

-- C_Spell.GetSpellLink is the modern spelling of the same call
Scenario()
linkApi = "modern"
CLEU("SPELL_INTERRUPT", { spellID = 6552, spellName = "Pummel",
    extraID = 116, extraName = "Frostbolt" })
msg = LastMessage()
CHECK(msg and msg:find("|Hspell:116|h[Frostbolt]|h", 1, true),
    "interrupt: falls through to C_Spell.GetSpellLink", msg)

-- Neither API answers: the link is built by hand from the id
Scenario()
linkApi = "none"
CLEU("SPELL_INTERRUPT", { spellID = 6552, spellName = "Pummel",
    extraID = 116, extraName = "Frostbolt" })
msg = LastMessage()
CHECK(msg and msg:find("|Hspell:116|h[Frostbolt]|h", 1, true),
    "interrupt: hand-built link when no API answers", msg)

-- No id at all: the callout still ships, with the bare name
Scenario()
CLEU("SPELL_INTERRUPT", { spellName = "Pummel", extraName = "Frostbolt" })
msg = LastMessage()
CHECK(msg and msg:find("Frostbolt", 1, true) and not msg:find("Hspell", 1, true),
    "interrupt: no id degrades to the plain name", msg)
linkApi = "global"

-- ===========================================================================
-- Channels: the kick the combat log never reports
-- ===========================================================================

Scenario()
StartChannel("target", 15407, 3)     -- Mind Flay, 3s
Advance(1)
CLEU("SPELL_CAST_SUCCESS", { spellID = 1766, spellName = "Kick" })
StopChannel("target")                -- kicked 2s before its end
Advance(0.5)
msg = LastMessage()
CHECK(msg and msg:find("|Hspell:15407|h[Mind Flay]|h", 1, true),
    "channel: a kicked channel is announced with its link", msg)
CHECK(msg and msg:find("|Hspell:1766|h[Kick]|h", 1, true),
    "channel: the kick is named too", msg)

-- A channel that runs its course is nobody's kick, even with an Earth
-- Shock landing on the same target in the same moment
Scenario()
StartChannel("target", 689, 5)       -- Drain Life, 5s
Advance(5)
CLEU("SPELL_CAST_SUCCESS", { spellID = 8042, spellName = "Earth Shock" })
StopChannel("target")
Advance(0.5)
CHECK(LastMessage() == nil, "channel: a natural end is not announced", LastMessage())

-- Dodged, parried, immune: cast but never landed
Scenario()
StartChannel("target", 15407, 3)
Advance(0.5)
CLEU("SPELL_CAST_SUCCESS", { spellID = 1766, spellName = "Kick" })
CLEU("SPELL_MISSED", { spellID = 1766, spellName = "Kick", extraName = "IMMUNE" })
StopChannel("target")
Advance(0.5)
CHECK(LastMessage() == nil, "channel: a missed kick is not announced", LastMessage())

-- The caster died mid-channel; the kick that landed first did not stop it
Scenario()
StartChannel("target", 689, 5)
Advance(0.5)
CLEU("SPELL_CAST_SUCCESS", { spellID = 1766, spellName = "Kick" })
CLEU("UNIT_DIED")
StopChannel("target")
Advance(0.5)
CHECK(LastMessage() == nil, "channel: a dead caster is not a kick", LastMessage())

-- If the client does report the interrupt itself, it is announced once
Scenario()
StartChannel("target", 15407, 3)
Advance(0.5)
CLEU("SPELL_CAST_SUCCESS", { spellID = 1766, spellName = "Kick" })
CLEU("SPELL_INTERRUPT", { spellID = 1766, spellName = "Kick",
    extraID = 15407, extraName = "Mind Flay" })
StopChannel("target")
Advance(0.5)
CHECK(#sent == 1, "channel: SPELL_INTERRUPT wins, no double callout", #sent)

-- The stop event never arrives (the unit lost its token), but the channel
-- had seconds left and the kick landed
Scenario()
StartChannel("target", 689, 8)
Advance(1)
CLEU("SPELL_CAST_SUCCESS", { spellID = 1766, spellName = "Kick" })
channelState.target = nil            -- no CHANNEL_STOP for us
Advance(0.5)
msg = LastMessage()
CHECK(msg and msg:find("|Hspell:689|h[Drain Life]|h", 1, true),
    "channel: a lost stop event still reads as a kick", msg)

-- A kick with no channel under it says nothing at all
Scenario()
CLEU("SPELL_CAST_SUCCESS", { spellID = 1766, spellName = "Kick" })
Advance(0.5)
CHECK(LastMessage() == nil, "channel: a kick on a non-channeler is silent", LastMessage())

-- ===========================================================================
-- Spell links on the cleanse callout
-- ===========================================================================

Scenario()
CLEU("SPELL_DISPEL", { destGUID = "Player-3", destName = "Healbot",
    spellID = 4987, spellName = "Cleanse",
    extraID = 1714, extraName = "Curse of Tongues", auraType = "DEBUFF" })
msg = LastMessage()
CHECK(msg and msg:find("|Hspell:1714|h[Curse of Tongues]|h", 1, true),
    "dispel: the debuff that came off goes out as a link", msg)
CHECK(msg and msg:find("|Hspell:4987|h[Cleanse]|h", 1, true),
    "dispel: the dispel spell goes out as a link", msg)
CHECK(msg and msg:find("from Healbot", 1, true), "dispel: still names who was cleansed", msg)

-- Same fallbacks as the interrupt callout
Scenario()
linkApi = "none"
CLEU("SPELL_DISPEL", { destGUID = "Player-3", destName = "Healbot",
    spellID = 1152, spellName = "Purify",
    extraID = 1714, extraName = "Curse of Tongues", auraType = "DEBUFF" })
msg = LastMessage()
CHECK(msg and msg:find("|Hspell:1714|h[Curse of Tongues]|h", 1, true),
    "dispel: hand-built link when no API answers", msg)
linkApi = "global"

Scenario()
CLEU("SPELL_DISPEL", { destGUID = "Player-3", destName = "Healbot",
    spellName = "Purify", extraName = "Curse of Tongues", auraType = "DEBUFF" })
msg = LastMessage()
CHECK(msg and msg:find("Curse of Tongues", 1, true) and not msg:find("Hspell", 1, true),
    "dispel: no id degrades to the plain name", msg)

-- An offensive purge (a BUFF coming off an enemy) stays quiet
Scenario()
CLEU("SPELL_DISPEL", { spellID = 4987, spellName = "Cleanse",
    extraID = 1714, extraName = "Blessing of Might", auraType = "BUFF" })
CHECK(LastMessage() == nil, "dispel: purges are not announced", LastMessage())

-- ===========================================================================
-- Spell links on the CC-break callout
-- ===========================================================================

-- My sheep, broken by a teammate's Cleave
Scenario()
CLEU("SPELL_AURA_APPLIED", { spellID = 118, spellName = "Polymorph", auraType = "DEBUFF" })
Advance(2)
CLEU("SPELL_AURA_BROKEN_SPELL", { sourceGUID = "Player-2", sourceName = "Levira",
    spellID = 118, spellName = "Polymorph",
    extraID = 845, extraName = "Cleave", auraType = "DEBUFF" })
msg = LastMessage()
CHECK(msg and msg:find("|Hspell:118|h[Polymorph]|h", 1, true),
    "cc break: the broken CC goes out as a link", msg)
CHECK(msg and msg:find("|Hspell:845|h[Cleave]|h", 1, true),
    "cc break: the breaking spell goes out as a link", msg)
CHECK(msg and msg:find("Levira broke my", 1, true), "cc break: still names the breaker", msg)

-- A melee swing carries no spell and still says so
Scenario()
CLEU("SPELL_AURA_APPLIED", { spellID = 118, spellName = "Polymorph", auraType = "DEBUFF" })
Advance(2)
CLEU("SPELL_AURA_BROKEN", { sourceGUID = "Player-2", sourceName = "Levira",
    spellID = 118, spellName = "Polymorph", auraType = "DEBUFF" })
msg = LastMessage()
CHECK(msg and msg:find("(melee)", 1, true) and msg:find("|Hspell:118|h[Polymorph]|h", 1, true),
    "cc break: a melee break links the CC and says (melee)", msg)

-- No id on the aura: the plain name still ships
Scenario()
CLEU("SPELL_AURA_APPLIED", { spellName = "Polymorph", auraType = "DEBUFF" })
Advance(2)
CLEU("SPELL_AURA_BROKEN_SPELL", { sourceGUID = "Player-2", sourceName = "Levira",
    spellName = "Polymorph", extraName = "Cleave", auraType = "DEBUFF" })
msg = LastMessage()
CHECK(msg and msg:find("broke my Polymorph on", 1, true) and not msg:find("Hspell", 1, true),
    "cc break: no id degrades to the plain name", msg)

-- ===========================================================================
-- Kicked on me: the callout going the other way
-- ===========================================================================

local ENEMY = { sourceGUID = "Player-2", sourceName = "Levira",
    sourceFlags = COMBATLOG_OBJECT_TYPE_PLAYER,
    destGUID = GUIDS.player, destName = "Kicker" }

local function Incoming(subevent, extra)
    local o = {}
    for k, v in pairs(ENEMY) do o[k] = v end
    for k, v in pairs(extra) do o[k] = v end
    CLEU(subevent, o)
end

-- The full callout: my spell, the kicker with their class, their spell,
-- the school and how long it is down
Scenario()
GUIDS.focus = "Player-2"             -- their nameplate/frame is up: class reads
Lock(116, 8)
Incoming("SPELL_INTERRUPT", { spellID = 2139, spellName = "Counterspell",
    extraID = 116, extraName = "Frostbolt", extraSchool = 0x10 })
Advance(0.2)                          -- the lockout lands a beat later
msg = LastMessage()
CHECK(msg and msg:find("|Hspell:116|h[Frostbolt]|h", 1, true),
    "kicked: my interrupted spell is linked", msg)
CHECK(msg and msg:find("|Hspell:2139|h[Counterspell]|h", 1, true),
    "kicked: their interrupt is linked", msg)
CHECK(msg and msg:find("by Levira (Mage)", 1, true),
    "kicked: the kicker is named with their class", msg)
CHECK(msg and msg:find("Frost locked 8s", 1, true),
    "kicked: the locked school and its duration are reported", msg)

-- No unit token pointing at them: the name still ships, the class doesn't
Scenario()
GUIDS.focus = nil
Lock(116, 8)
Incoming("SPELL_INTERRUPT", { spellID = 2139, spellName = "Counterspell",
    extraID = 116, extraName = "Frostbolt", extraSchool = 0x10 })
Advance(0.2)
msg = LastMessage()
CHECK(msg and msg:find("by Levira with", 1, true) and not msg:find("(Mage)", 1, true),
    "kicked: an unresolvable class is left out", msg)

-- A creature has no class worth printing
Scenario()
lockouts = {}
CLEU("SPELL_INTERRUPT", { sourceGUID = "Creature-9", sourceName = "Pillager",
    sourceFlags = 0, destGUID = GUIDS.player, destName = "Kicker",
    spellID = 2139, spellName = "Counterspell",
    extraID = 116, extraName = "Frostbolt", extraSchool = 0x10 })
Advance(0.2)
msg = LastMessage()
CHECK(msg and msg:find("by Pillager", 1, true) and msg:find("Frost locked.", 1, true),
    "kicked: no cooldown to read leaves the school without a number", msg)

-- A duration too long to be a lockout is the spell's own cooldown talking
Scenario()
Lock(116, 30)
Incoming("SPELL_INTERRUPT", { spellID = 2139, spellName = "Counterspell",
    extraID = 116, extraName = "Frostbolt", extraSchool = 0x10 })
Advance(0.2)
msg = LastMessage()
CHECK(msg and msg:find("Frost locked.", 1, true) and not msg:find("30s", 1, true),
    "kicked: a real cooldown is not reported as a lockout", msg)

-- Hybrid schools name both halves
Scenario()
lockouts = {}
Incoming("SPELL_INTERRUPT", { spellID = 2139, spellName = "Counterspell",
    extraID = 116, extraName = "Frostbolt", extraSchool = 0x14 })
Advance(0.2)
CHECK(LastMessage() and LastMessage():find("Fire/Frost locked", 1, true),
    "kicked: a hybrid school names both halves", LastMessage())

-- Kicked mid-channel: silent in the combat log, inferred the same way
Scenario()
StartChannel("player", 689, 5)       -- my Drain Life
Advance(1)
Lock(689, 6)
Incoming("SPELL_CAST_SUCCESS", { spellID = 1766, spellName = "Kick" })
StopChannel("player")
Advance(0.6)                          -- the channel confirm...
Advance(0.2)                          -- ...then its own lockout read
msg = LastMessage()
CHECK(msg and msg:find("|Hspell:689|h[Drain Life]|h", 1, true),
    "kicked: a kicked channel of mine is announced", msg)
CHECK(msg and msg:find("locked 6s", 1, true),
    "kicked: the channel lockout is reported without a school", msg)

Scenario()
lockouts = {}
CommanderCommsDB.KickedCallouts = false
Incoming("SPELL_INTERRUPT", { spellID = 2139, spellName = "Counterspell",
    extraID = 116, extraName = "Frostbolt", extraSchool = 0x10 })
Advance(0.2)
CHECK(LastMessage() == nil, "kicked: silent while the callout is off", LastMessage())
CommanderCommsDB.KickedCallouts = true

-- ===========================================================================
-- The gates the rest of the module already had
-- ===========================================================================

Scenario()
CommanderCommsDB.InterruptSilence = false
StartChannel("target", 15407, 3)
Advance(0.5)
CLEU("SPELL_CAST_SUCCESS", { spellID = 1766, spellName = "Kick" })
StopChannel("target")
Advance(0.5)
CHECK(LastMessage() == nil, "channel: silent while interrupt callouts are off", LastMessage())
CommanderCommsDB.InterruptSilence = true

Scenario()
inGroup = false
StartChannel("target", 15407, 3)
Advance(0.5)
CLEU("SPELL_CAST_SUCCESS", { spellID = 1766, spellName = "Kick" })
StopChannel("target")
Advance(0.5)
CHECK(LastMessage() == nil, "channel: never fires solo", LastMessage())
inGroup = true

-- Someone else's kick is not the player's callout
Scenario()
StartChannel("target", 15407, 3)
Advance(0.5)
CLEU("SPELL_CAST_SUCCESS", { sourceGUID = "Player-2", sourceName = "Someone",
    spellID = 1766, spellName = "Kick" })
StopChannel("target")
Advance(0.5)
CHECK(LastMessage() == nil, "channel: another player's kick stays quiet", LastMessage())

-- The raid channel still resolves the same way
Scenario()
inRaid = true
CLEU("SPELL_INTERRUPT", { spellID = 6552, spellName = "Pummel",
    extraID = 116, extraName = "Frostbolt" })
CHECK(sent[1] and sent[1].channel == "RAID", "interrupt: raid routing intact",
    sent[1] and sent[1].channel)
inRaid = false

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
