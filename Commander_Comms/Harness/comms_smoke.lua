-- Commander Comms smoke (luajit):
--     luajit comms_smoke.lua
--
-- Covers the 2.3.0 callout work: spell links in the interrupt, cleanse and
-- CC-break announcements (and every fallback down to a bare name), the
-- kicked-on-me callout (school, lockout seconds, kicker class), and the
-- inferred channel kick
-- — the one the combat log never reports — with its false-positive guards
-- (natural end, missed kick, dead caster, a real SPELL_INTERRUPT already
-- covering it), plus the 2.4.0 battleground rule: quiet in a BG, and
-- routed to the party you queued with when asked for (every automatic
-- callout, cleanse included), plus the 2.6.0 failed-cast callouts: range
-- and line of sight whispered to the ally after a run of four (the
-- heal-only gate, the run rules, the per-ally cooldown, cross-realm
-- addressing, separate runs per reason, and the no-cast-event fallback
-- that reads the aim off the unit tokens -- guessing for range, where the
-- client can confirm it, and never for sight), and out-of-mana and
-- crowd-controlled told to the group (the shared /oom latch and its
-- re-arm, the mana-users-only rule, the named CC state, and the
-- battleground rule the whispers are exempt from), and the 2.7.0 support
-- calls: a cooldown spent on one ally whispered to that ally with what to
-- DO about it, gated on your own spellbook, one per spell per ally, and the
-- only whisper that ships switched on, and the 2.8.0 mana burn callout:
-- a drain on any group member's mana told to the group with what is left
-- (the mana-only and group-only gates, the share-of-the-bar threshold that
-- adds small ticks up, the per-victim window that turns a chain of burns
-- into one line, the deferred read of the bar, and the battleground rule),
-- and the 2.10.0 Rally on Me call: the chat line with the zone and
-- coordinates, the spot shared through CommanderOrders.SharePoint (never a
-- waypoint of your own), its setting, Orders missing, no map position, the
-- binding and slash, and the centre button clear of the ring of calls.
-- Mock modeled on Commander_Chat/Harness.

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
            local regions = rawget(s, "__regions")
            if not regions then regions = {} rawset(s, "__regions", regions) end
            regions[#regions + 1] = t
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
    -- Anchors and sizes are remembered so the wheel's layout can be checked
    if key == "SetPoint" then
        local fn = function(s, ...) s.__point = { ... } end
        rawset(self, key, fn); return fn
    end
    if key == "SetSize" then
        local fn = function(s, w, h) s.__w, s.__h = w, h end
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
    if parent then
        -- rawget: the mock answers any unknown key with a no-op function
        local kids = rawget(parent, "__kids")
        if not kids then kids = {} rawset(parent, "__kids", kids) end
        kids[#kids + 1] = f
    end
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
-- Battleground state: the instance group is the BG raid, and inGroup is
-- the home party you queued with (it survives into the BG, or doesn't)
local inInstanceGroup, instanceType = false, "none"
LE_PARTY_CATEGORY_HOME = 1
LE_PARTY_CATEGORY_INSTANCE = 2
function IsInGroup(category)
    if category == LE_PARTY_CATEGORY_INSTANCE then return inInstanceGroup end
    return inGroup
end
function IsInRaid() return inRaid or inInstanceGroup end
function IsInInstance() return instanceType ~= "none", instanceType end
function GetNumSubgroupMembers() return inGroup and 2 or 0 end
function GetNumGroupMembers() return inGroup and 2 or 0 end

local GUIDS = { player = "Player-1", target = "Creature-9", pet = nil,
    party1 = "Player-7", party2 = "Player-8",
    -- The same two allies under the tokens a battleground raid uses
    raid1 = "Player-7", raid2 = "Player-8" }
function UnitGUID(unit) return GUIDS[unit] end
-- Class only resolves through a unit token pointing at the same GUID
local CLASSES = { focus = "Mage" }
function UnitClass(unit) return CLASSES[unit] end
local NAMES = { player = "Kicker", party1 = "Straggler", party2 = "Anchor",
    raid1 = "Straggler", raid2 = "Anchor" }
local REALMS = {}
function UnitName(unit) return NAMES[unit] or "Pillager", REALMS[unit] end
function UnitExists(unit) return GUIDS[unit] ~= nil end
function UnitIsUnit(a, b)
    local ga, gb = GUIDS[a], GUIDS[b]
    return ga ~= nil and ga == gb
end
function UnitIsPlayer(unit)
    local guid = GUIDS[unit]
    return guid ~= nil and guid:sub(1, 6) == "Player"
end
function UnitIsFriend(_, unit) return UnitIsPlayer(unit) end
-- Range state the tests drive. The second return is the load-bearing one:
-- UnitInRange only answers for group members, so "it answered no" is what
-- proves the unit is both an ally and too far away.
local rangeState = {}
function UnitInRange(unit)
    local state = rangeState[unit]
    if state == nil then return false, false end
    return state, true
end
function UnitHealth() return 100 end
function UnitHealthMax() return 100 end
-- Mana per unit token the tests drive; unset units sit on a full 100
local manaNow, manaMax = {}, {}
function UnitPower(unit) return manaNow[unit] or 100 end
function UnitPowerMax(unit) return manaMax[unit] or 100 end
local powerType = 0
function UnitPowerType() return powerType end
function UnitAffectingCombat() return true end
local dead = {}
function UnitIsDeadOrGhost(unit) return dead[unit] == true end
local emotes = {}
function DoEmote(token) emotes[#emotes + 1] = token end
local function LastEmote() return emotes[#emotes] end
local function ClearEmotes() emotes = {} end

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
    [2061] = "Flash Heal", [2060] = "Greater Heal", [17] = "Power Word: Shield",
    [331] = "Healing Wave",
    [10060] = "Power Infusion", [29166] = "Innervate", [3411] = "Intervene",
    [1022] = "Blessing of Protection", [6346] = "Fear Ward",
    [25380] = "Mana Burn", [27018] = "Viper Sting",
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

-- The spellbook, which is what decides whether a heal in the canon is one
-- the player actually knows
local spellBook = { "Flash Heal", "Greater Heal", "Power Word: Shield", "Frostbolt",
    -- Support cooldowns this character has. Innervate and Blessing of
    -- Protection are deliberately absent: they belong to other classes.
    "Power Infusion", "Intervene", "Fear Ward" }
function GetNumSpellTabs() return 1 end
function GetSpellTabInfo() return "General", "tex", 0, #spellBook end
function GetSpellBookItemName(index) return spellBook[index], "" end
function GetSpellInfo(id) return SPELL_NAMES[id] end

-- The client's own failure strings, which the addon reads rather than
-- hardcoding. Each is distinct so a test can tell which one was matched.
SPELL_FAILED_OUT_OF_RANGE = "Out of range."
SPELL_FAILED_LINE_OF_SIGHT = "Target not in line of sight."
SPELL_FAILED_NO_POWER = "Not enough mana."
SPELL_FAILED_STUNNED = "Can't do that while stunned."
SPELL_FAILED_FLEEING = "Can't do that while fleeing."
SPELL_FAILED_CONFUSED = "Can't do that while confused."
SPELL_FAILED_CHARMED = "Can't do that while charmed."
-- Deliberately NOT watched: the kicked-on-me callout owns this one
SPELL_FAILED_SILENCED = "Can't do that while silenced."

local sent = {}
function SendChatMessage(msg, channel, _, to)
    sent[#sent + 1] = { msg = msg, channel = channel, to = to }
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
    -- The drain suffix (amount, powerType, extraAmount) sits where the
    -- extra spell triplet does on every other event
    if o.amount then
        cleuArgs[15], cleuArgs[16], cleuArgs[17] = o.amount, o.powerType or 0, o.extraAmount or 0
    end
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
    BattlegroundCallouts = false, BattlegroundToParty = false,
    SupportWhisper = true,
    ManaBurnCallouts = true, ManaBurnMinPercent = 0.05, ManaBurnCooldown = 8,
}
COMMANDER_COMMS_EVENTS = { UPDATE = "COMMANDER_COMMS_UPDATE" }

-- Mutation hook: COMMS_RUNTIME=/path of a copy of CommanderComms.lua
assert(loadfile(os.getenv("COMMS_RUNTIME") or (ADDONS .. "/Commander_Comms/CommanderComms.lua")))()
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

-- A teammate's Blind is the group's problem too: announced by default,
-- with the rogue named as its owner
Scenario()
CLEU("SPELL_AURA_APPLIED", { sourceGUID = GUIDS.party1, sourceName = "Straggler",
    spellID = 2094, spellName = "Blind", auraType = "DEBUFF" })
Advance(2)
CLEU("SPELL_AURA_BROKEN_SPELL", { sourceGUID = "Player-2", sourceName = "Levira",
    spellID = 2094, spellName = "Blind",
    extraID = 845, extraName = "Cleave", auraType = "DEBUFF" })
msg = LastMessage()
CHECK(msg and msg:find("Levira broke Straggler's |cff71d5ff|Hspell:2094|h[Blind]|h|r on Pillager", 1, true),
    "cc break: a group member's Blind is announced with its owner named", msg)
CHECK(msg and msg:find("|Hspell:845|h[Cleave]|h", 1, true),
    "cc break: ...and the spell that broke it", msg)

-- The rogue breaking their own Blind
Scenario()
CLEU("SPELL_AURA_APPLIED", { sourceGUID = GUIDS.party1, sourceName = "Straggler",
    spellID = 2094, spellName = "Blind", auraType = "DEBUFF" })
Advance(2)
CLEU("SPELL_AURA_BROKEN_SPELL", { sourceGUID = GUIDS.party1, sourceName = "Straggler",
    spellID = 2094, spellName = "Blind",
    extraID = 1752, extraName = "Sinister Strike", auraType = "DEBUFF" })
msg = LastMessage()
CHECK(msg and msg:find("Straggler broke their own", 1, true),
    "cc break: a teammate breaking their own CC says so", msg)

-- A teammate's pet owns its CC the way mine does
Scenario()
GUIDS.partypet2 = "Pet-8"
CLEU("SPELL_AURA_APPLIED", { sourceGUID = "Pet-8", sourceName = "Zharvia",
    sourceFlags = COMBATLOG_OBJECT_TYPE_PET,
    spellID = 6358, spellName = "Seduction", auraType = "DEBUFF" })
Advance(2)
CLEU("SPELL_AURA_BROKEN", { sourceGUID = "Player-2", sourceName = "Levira",
    spellID = 6358, spellName = "Seduction", auraType = "DEBUFF" })
msg = LastMessage()
CHECK(msg and msg:find("Levira broke Zharvia's", 1, true) and msg:find("(melee)", 1, true),
    "cc break: a group member's pet's CC is the group's", msg)
GUIDS.partypet2 = nil

-- A stranger's sheep is nobody's business until asked for
Scenario()
CLEU("SPELL_AURA_APPLIED", { sourceGUID = "Player-5", sourceName = "Passerby",
    spellID = 118, spellName = "Polymorph", auraType = "DEBUFF" })
Advance(2)
CLEU("SPELL_AURA_BROKEN_SPELL", { sourceGUID = "Player-2", sourceName = "Levira",
    spellID = 118, spellName = "Polymorph",
    extraID = 845, extraName = "Cleave", auraType = "DEBUFF" })
CHECK(LastMessage() == nil, "cc break: a stranger's CC stays quiet by default", LastMessage())

Scenario()
CommanderCommsDB.CCBreakAll = true
CLEU("SPELL_AURA_APPLIED", { sourceGUID = "Player-5", sourceName = "Passerby",
    spellID = 118, spellName = "Polymorph", auraType = "DEBUFF" })
Advance(2)
CLEU("SPELL_AURA_BROKEN_SPELL", { sourceGUID = "Player-2", sourceName = "Levira",
    spellID = 118, spellName = "Polymorph",
    extraID = 845, extraName = "Cleave", auraType = "DEBUFF" })
msg = LastMessage()
CHECK(msg and msg:find("Levira broke Passerby's", 1, true),
    "cc break: All CC Breaks widens it to anyone in range", msg)
CommanderCommsDB.CCBreakAll = false

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

-- ===========================================================================
-- Battlegrounds: quiet by default, optionally routed to the party you
-- queued with
-- ===========================================================================

local function EnterBattleground(withParty)
    instanceType = "pvp"
    inInstanceGroup = true
    inGroup = withParty and true or false   -- the home party, if any
end
local function LeaveBattleground()
    instanceType, inInstanceGroup, inGroup, inRaid = "none", false, true, false
end

local function Dispel()
    CLEU("SPELL_DISPEL", { spellID = 4987, spellName = "Cleanse",
        destGUID = "Player-3", destName = "Healbot",
        extraID = 1714, extraName = "Curse of Tongues", auraType = "DEBUFF" })
end

local function CCBreak()
    CLEU("SPELL_AURA_APPLIED", { spellID = 118, spellName = "Polymorph" })
    CLEU("SPELL_AURA_BROKEN_SPELL", { sourceGUID = "Player-2", sourceName = "Levira",
        spellID = 118, spellName = "Polymorph", extraID = 845, extraName = "Cleave" })
end

-- Off by default: nothing goes out in a battleground
Scenario()
EnterBattleground(true)
CLEU("SPELL_INTERRUPT", { spellID = 6552, spellName = "Pummel",
    extraID = 116, extraName = "Frostbolt" })
CHECK(LastMessage() == nil, "bg: the interrupt callout is silent", LastMessage())

Scenario()
CCBreak()
CHECK(LastMessage() == nil, "bg: the CC-break callout is silent", LastMessage())

Scenario()
Dispel()
CHECK(LastMessage() == nil, "bg: the cleanse callout is silent", LastMessage())

Scenario()
lockouts = {}
Incoming("SPELL_INTERRUPT", { spellID = 2139, spellName = "Counterspell",
    extraID = 116, extraName = "Frostbolt", extraSchool = 0x10 })
Advance(0.2)
CHECK(LastMessage() == nil, "bg: the kicked-on-me callout is silent", LastMessage())

-- Turned back on: the battleground's own instance chat
Scenario()
CommanderCommsDB.BattlegroundCallouts = true
CLEU("SPELL_INTERRUPT", { spellID = 6552, spellName = "Pummel",
    extraID = 116, extraName = "Frostbolt" })
CHECK(sent[1] and sent[1].channel == "INSTANCE_CHAT",
    "bg: switched on, callouts speak to the battleground", sent[1] and sent[1].channel)

-- ...or to the party you queued with instead
Scenario()
CommanderCommsDB.BattlegroundToParty = true
CLEU("SPELL_INTERRUPT", { spellID = 6552, spellName = "Pummel",
    extraID = 116, extraName = "Frostbolt" })
CHECK(sent[1] and sent[1].channel == "PARTY",
    "bg: routed to the party, not the battleground raid", sent[1] and sent[1].channel)

Scenario()
CCBreak()
CHECK(sent[1] and sent[1].channel == "PARTY",
    "bg: the CC-break callout follows the same routing", sent[1] and sent[1].channel)

Scenario()
Dispel()
CHECK(sent[1] and sent[1].channel == "PARTY",
    "bg: the cleanse callout follows the same routing", sent[1] and sent[1].channel)

Scenario()
lockouts = {}
Incoming("SPELL_INTERRUPT", { spellID = 2139, spellName = "Counterspell",
    extraID = 116, extraName = "Frostbolt", extraSchool = 0x10 })
Advance(0.2)
CHECK(sent[1] and sent[1].channel == "PARTY",
    "bg: the kicked-on-me callout follows the same routing", sent[1] and sent[1].channel)

-- Solo-queued with party routing on: no small audience, so nothing is said
Scenario()
EnterBattleground(false)
CLEU("SPELL_INTERRUPT", { spellID = 6552, spellName = "Pummel",
    extraID = 116, extraName = "Frostbolt" })
CHECK(LastMessage() == nil,
    "bg: no party to route to falls back to silence, not the raid", LastMessage())

-- Everywhere else the settings change nothing
Scenario()
LeaveBattleground()
CommanderCommsDB.BattlegroundCallouts = false
CommanderCommsDB.BattlegroundToParty = false
CLEU("SPELL_INTERRUPT", { spellID = 6552, spellName = "Pummel",
    extraID = 116, extraName = "Frostbolt" })
CHECK(sent[1] and sent[1].channel == "PARTY",
    "bg: the world party is untouched by the battleground rule",
    sent[1] and sent[1].channel)

-- An arena is not a battleground: kick calls are the whole point there
Scenario()
instanceType = "arena"
inInstanceGroup = true
CLEU("SPELL_INTERRUPT", { spellID = 6552, spellName = "Pummel",
    extraID = 116, extraName = "Frostbolt" })
CHECK(sent[1] and sent[1].channel == "INSTANCE_CHAT",
    "arena: callouts still go out with the battleground rule on",
    sent[1] and sent[1].channel)
LeaveBattleground()

-- ===========================================================================
-- Range nag: the callout that whispers one person instead of telling the
-- group. Four failed heals in a row on the same ally, no heal landing in
-- between, and they hear about it privately.
-- ===========================================================================

-- Past the streak window AND the whisper cooldown, with both allies back on
-- a known footing: party1 too far, party2 close enough
local function RangeScenario()
    Advance(200)
    ClearMessages()
    rangeState = { party1 = false, party2 = true, raid1 = false, raid2 = true }
end

-- One press of a heal that fails for range: the client sends the cast, the
-- cast fails, and a UI error says why. The addon has to pair the three.
local castSeq = 0
local function HealPress(targetName, spellID, errorText)
    castSeq = castSeq + 1
    local castGUID = "Cast-" .. castSeq
    spellID = spellID or 2061
    Fire("UNIT_SPELLCAST_SENT", "player", targetName, castGUID, spellID)
    Fire("UNIT_SPELLCAST_FAILED_QUIET", "player", castGUID, spellID)
    Fire("UI_ERROR_MESSAGE", 1, errorText or "Out of range.")
    Advance(0.5)   -- past the pairing window: the next one is another press
end

RangeScenario()
for _ = 1, 6 do HealPress("Straggler") end
CHECK(LastMessage() == nil, "range: off by default, nothing is whispered", LastMessage())

CommanderCommsDB.RangeWhisper = true
CommanderCommsDB.RangeWhisperStreak = 4
CommanderCommsDB.RangeWhisperCooldown = 45

RangeScenario()
HealPress("Straggler"); HealPress("Straggler"); HealPress("Straggler")
CHECK(LastMessage() == nil, "range: three in a row is a bad angle, not a nag",
    LastMessage())
HealPress("Straggler")
local rangeMsg = LastMessage()
CHECK(rangeMsg ~= nil, "range: the fourth failure in a row speaks up", rangeMsg)
CHECK(sent[1] and sent[1].channel == "WHISPER",
    "range: it is a whisper, never a group callout", sent[1] and sent[1].channel)
CHECK(sent[1] and sent[1].to == "Straggler",
    "range: addressed to the ally standing too far away", sent[1] and sent[1].to)
CHECK(rangeMsg and rangeMsg:find("|Hspell:2061|h[Flash Heal]|h", 1, true),
    "range: the heal that didn't reach goes out as a link", rangeMsg)
CHECK(rangeMsg and rangeMsg:find("4 casts", 1, true),
    "range: says how many presses were lost", rangeMsg)

-- A heal that landed answers the nag: whatever the run was, it is over
RangeScenario()
HealPress("Straggler"); HealPress("Straggler"); HealPress("Straggler")
CLEU("SPELL_HEAL", { destGUID = "Player-7", destName = "Straggler",
    spellID = 2061, spellName = "Flash Heal" })
HealPress("Straggler")
CHECK(LastMessage() == nil, "range: a heal that landed resets the run", LastMessage())
HealPress("Straggler"); HealPress("Straggler"); HealPress("Straggler")
CHECK(sent[1] and sent[1].to == "Straggler",
    "range: the run restarts from zero and still gets there", sent[1] and sent[1].to)

-- The streak is a RUN, not a lifetime tally
RangeScenario()
for _ = 1, 3 do HealPress("Straggler"); Advance(25) end
HealPress("Straggler")
CHECK(LastMessage() == nil,
    "range: failures spread past the window are not a run", LastMessage())

-- Only heals count, and only the ones you actually know
RangeScenario()
for _ = 1, 6 do HealPress("Straggler", 116) end
CHECK(LastMessage() == nil,
    "range: a Frostbolt out of range is not a lost heal", LastMessage())

RangeScenario()
for _ = 1, 6 do HealPress("Straggler", 331) end
CHECK(LastMessage() == nil,
    "range: a heal missing from your spellbook never counts", LastMessage())

-- One whisper per stretch of being too far
RangeScenario()
for _ = 1, 4 do HealPress("Straggler") end
CHECK(#sent == 1, "range: one whisper per run", #sent)
for _ = 1, 4 do HealPress("Straggler") end
CHECK(#sent == 1, "range: a second run inside the cooldown stays quiet", #sent)
Advance(60)
for _ = 1, 4 do HealPress("Straggler") end
CHECK(#sent == 2, "range: past the cooldown it may speak again", #sent)

-- A cross-realm ally has to be whispered with their realm attached, and the
-- name the cast event hands over carries it too
RangeScenario()
REALMS.party1 = "Stormrage"
for _ = 1, 4 do HealPress("Straggler-Stormrage") end
CHECK(sent[1] and sent[1].to == "Straggler-Stormrage",
    "range: a cross-realm ally is whispered with their realm", sent[1] and sent[1].to)
REALMS.party1 = nil

-- The fallback: a client that reports no cast events at all still has to
-- land the nag, read off whichever unit token was actually out of range
RangeScenario()
GUIDS.target, NAMES.target = "Player-7", "Straggler"
rangeState.target = false
for _ = 1, 4 do
    Fire("UI_ERROR_MESSAGE", 1, "Out of range.")
    Advance(0.5)
end
CHECK(sent[1] and sent[1].to == "Straggler",
    "range: with no cast event, the aim is read off the unit tokens",
    sent[1] and sent[1].to)

-- ...and that fallback leans entirely on the range check, so with everybody
-- close enough there is nobody the error could be about
RangeScenario()
rangeState = { party1 = true, party2 = true, target = true }
for _ = 1, 6 do
    Fire("UI_ERROR_MESSAGE", 1, "Out of range.")
    Advance(0.5)
end
CHECK(LastMessage() == nil,
    "range: an ally the client reports as in range is never blamed", LastMessage())

-- A @party1-style macro pressed while pointing at nothing: no unit token
-- holds the target, but exactly one person in the group is too far away, so
-- there is no one else the error could have been about
RangeScenario()
rangeState = { party1 = false, party2 = true }
for _ = 1, 4 do
    Fire("UI_ERROR_MESSAGE", 1, "Out of range.")
    Advance(0.5)
end
CHECK(sent[1] and sent[1].to == "Straggler",
    "range: one ally out of range and no aim is still unambiguous",
    sent[1] and sent[1].to)

-- Two of them and the answer is a guess, so nobody is named
RangeScenario()
rangeState = { party1 = false, party2 = false }
for _ = 1, 6 do
    Fire("UI_ERROR_MESSAGE", 1, "Out of range.")
    Advance(0.5)
end
CHECK(LastMessage() == nil,
    "range: two allies out of range names neither", LastMessage())

-- A cast the client DID name, aimed at somebody outside the group: taken as
-- final and dropped, never pinned on whoever else happens to be far away
RangeScenario()
rangeState = { party1 = false, party2 = true }
for _ = 1, 6 do HealPress("Wanderer") end
CHECK(LastMessage() == nil,
    "range: a named target outside the group is dropped, not reassigned",
    LastMessage())

-- Nobody whispers themselves
RangeScenario()
GUIDS.target, NAMES.target = "Creature-9", nil
for _ = 1, 6 do HealPress("Kicker") end
CHECK(LastMessage() == nil, "range: your own name resolves to nobody", LastMessage())

-- A battleground silences the group callouts; it does not silence a line
-- addressed to one person
RangeScenario()
EnterBattleground(true)
for _ = 1, 4 do HealPress("Straggler") end
CHECK(sent[1] and sent[1].channel == "WHISPER" and sent[1].to == "Straggler",
    "range: a battleground does not silence the whisper",
    sent[1] and (sent[1].channel .. "/" .. tostring(sent[1].to)))
LeaveBattleground()

-- ===========================================================================
-- The other failures worth saying out loud. Line of sight is the ally's
-- problem like range is, so it whispers; out of mana and being crowd
-- controlled are yours, so they go to the group.
-- ===========================================================================

CommanderCommsDB.SightWhisper = true

-- The pillar half of the same run
RangeScenario()
rangeState = { party1 = true, party2 = true }   -- in range, just not visible
for _ = 1, 3 do HealPress("Straggler", nil, "Target not in line of sight.") end
CHECK(LastMessage() == nil, "los: three blocked casts stay quiet", LastMessage())
HealPress("Straggler", nil, "Target not in line of sight.")
local losMsg = LastMessage()
CHECK(losMsg and losMsg:find("No line of sight", 1, true),
    "los: the fourth blocked cast whispers", losMsg)
CHECK(sent[1] and sent[1].channel == "WHISPER" and sent[1].to == "Straggler",
    "los: whispered to the ally behind the pillar",
    sent[1] and (sent[1].channel .. "/" .. tostring(sent[1].to)))
CHECK(losMsg and losMsg:find("|Hspell:2061|h[Flash Heal]|h", 1, true),
    "los: names the heal that was blocked", losMsg)

-- Unlike range, line of sight must not require the ally to be far away --
-- the pillar case is someone standing right next to you. With no cast event
-- to name them, an ally under the cursor who is comfortably IN range still
-- has to be the one blamed for a sight error.
RangeScenario()
GUIDS.target, NAMES.target = "Player-7", "Straggler"
rangeState = { party1 = true, party2 = true, target = true }
for _ = 1, 4 do
    Fire("UI_ERROR_MESSAGE", 1, "Target not in line of sight.")
    Advance(0.5)
end
CHECK(sent[1] and sent[1].to == "Straggler",
    "los: an ally in range is still the one behind the pillar",
    sent[1] and sent[1].to)
GUIDS.target, NAMES.target = "Creature-9", nil

-- The two reasons keep separate runs: three of each is not four of either
RangeScenario()
rangeState = { party1 = false, party2 = true }
for _ = 1, 3 do HealPress("Straggler") end
for _ = 1, 3 do HealPress("Straggler", nil, "Target not in line of sight.") end
CHECK(LastMessage() == nil,
    "los: range and sight are separate runs, not one pooled tally", LastMessage())

-- The no-cast-event fallback can guess for range, because the client can
-- confirm who is too far away. It must never guess for sight.
RangeScenario()
rangeState = { party1 = false, party2 = true }
for _ = 1, 6 do
    Fire("UI_ERROR_MESSAGE", 1, "Target not in line of sight.")
    Advance(0.5)
end
CHECK(LastMessage() == nil,
    "los: with no aim and no way to confirm one, nobody is named", LastMessage())

CommanderCommsDB.SightWhisper = false

-- ===========================================================================
-- Out of mana: your own state, so it goes to the group -- through the /oom
-- call Comms already owns, sharing its cooldown and its re-arm
-- ===========================================================================

local function Recover()
    -- Mana back up: the latch the one-shot call sets has to be released
    Fire("UNIT_POWER_UPDATE", "player")
end

RangeScenario(); ClearEmotes()
Fire("UI_ERROR_MESSAGE", 1, "Not enough mana.")
CHECK(LastEmote() == nil and LastMessage() == nil,
    "oom: off by default, nothing is said", LastEmote() or LastMessage())

CommanderCommsDB.PowerCallouts = true

RangeScenario(); ClearEmotes(); Recover()
Fire("UI_ERROR_MESSAGE", 1, "Not enough mana.")
CHECK(LastEmote() == "OOM", "oom: a cast refused for mana makes the /oom call",
    LastEmote())

-- One empty bar is one announcement, however it was noticed
ClearEmotes()
Fire("UI_ERROR_MESSAGE", 1, "Not enough mana.")
CHECK(LastEmote() == nil, "oom: it does not repeat until the bar recovers",
    LastEmote())
Recover()
Advance(60)
ClearEmotes()
Fire("UI_ERROR_MESSAGE", 1, "Not enough mana.")
CHECK(LastEmote() == "OOM", "oom: drinking re-arms it", LastEmote())

-- ...and the re-arm has to work with Auto-Emote OFF, which is where the
-- latch used to stick for good
CHECK(CommanderCommsDB.AutoEmote ~= true,
    "oom: (the percentage trigger is off for this run)", CommanderCommsDB.AutoEmote)

-- Voice off means the call still gets made, in chat
RangeScenario(); ClearEmotes(); Recover()
CommanderCommsDB.UseEmotes = false
Fire("UI_ERROR_MESSAGE", 1, "Not enough mana.")
CHECK(LastEmote() == nil and LastMessage() == "I'm out of mana.",
    "oom: with voice emotes off the call goes to chat instead",
    LastEmote() or LastMessage())
CommanderCommsDB.UseEmotes = true

-- A rogue is out of energy every few seconds; that is not news
RangeScenario(); ClearEmotes(); Recover()
powerType = 3
Fire("UI_ERROR_MESSAGE", 1, "Not enough mana.")
CHECK(LastEmote() == nil and LastMessage() == nil,
    "oom: only mana users call it", LastEmote() or LastMessage())
powerType = 0

CommanderCommsDB.PowerCallouts = false

-- ===========================================================================
-- Crowd controlled: the group callout that names the state, because "peel
-- me" and "dispel me" are different requests
-- ===========================================================================

RangeScenario()
Fire("UI_ERROR_MESSAGE", 1, "Can't do that while stunned.")
CHECK(LastMessage() == nil, "cc: off by default, nothing is said", LastMessage())

CommanderCommsDB.ControlCallouts = true

RangeScenario()
Fire("UI_ERROR_MESSAGE", 1, "Can't do that while stunned.")
local ccMsg = LastMessage()
CHECK(ccMsg and ccMsg:find("stunned", 1, true), "cc: names the state it is in", ccMsg)
CHECK(sent[1] and sent[1].channel == "PARTY",
    "cc: told to the group, not whispered", sent[1] and sent[1].channel)

RangeScenario()
Fire("UI_ERROR_MESSAGE", 1, "Can't do that while fleeing.")
CHECK(LastMessage() and LastMessage():find("feared", 1, true),
    "cc: a fear is called a fear, not a generic crowd control", LastMessage())

-- Mashing the button through a six-second fear is one callout
RangeScenario()
for _ = 1, 6 do
    Fire("UI_ERROR_MESSAGE", 1, "Can't do that while feared.")
    Fire("UI_ERROR_MESSAGE", 1, "Can't do that while fleeing.")
    Advance(1)
end
CHECK(#sent == 1, "cc: the whole fear is one callout, not one per press", #sent)

-- Silence is the kicked-on-me callout's job, and it says more
RangeScenario()
for _ = 1, 4 do Fire("UI_ERROR_MESSAGE", 1, "Can't do that while silenced."); Advance(1) end
CHECK(LastMessage() == nil,
    "cc: silence is left to the callout that reports the school and the lockout",
    LastMessage())

-- These ARE group callouts, so unlike the whispers they follow the
-- battleground rule
RangeScenario()
EnterBattleground(true)
Fire("UI_ERROR_MESSAGE", 1, "Can't do that while stunned.")
CHECK(LastMessage() == nil,
    "cc: silent in a battleground like every other group callout", LastMessage())
CommanderCommsDB.BattlegroundCallouts = true
Advance(30)
Fire("UI_ERROR_MESSAGE", 1, "Can't do that while stunned.")
CHECK(sent[1] and sent[1].channel == "INSTANCE_CHAT",
    "cc: switched on, it speaks to the battleground",
    sent[1] and sent[1].channel)
CommanderCommsDB.BattlegroundCallouts = false
LeaveBattleground()

-- Solo there is no group to tell
RangeScenario()
inGroup = false
Advance(30)
Fire("UI_ERROR_MESSAGE", 1, "Can't do that while stunned.")
CHECK(LastMessage() == nil, "cc: never fires solo", LastMessage())
inGroup = true

CommanderCommsDB.ControlCallouts = false

-- ===========================================================================
-- Support calls: a cooldown spent on one ally, whispered to the ally who
-- has to act on it. The only whisper that ships switched on.
-- ===========================================================================

local function SupportCast(spellID, destGUID, destName)
    CLEU("SPELL_CAST_SUCCESS", { spellID = spellID, spellName = SPELL_NAMES[spellID],
        destGUID = destGUID or "Player-7", destName = destName or "Straggler",
        destFlags = 0 })
end

-- The shipped defaults live in CommanderCommsDB.lua, which this harness does
-- not load (that would need the whole settings framework); the claim "this
-- one is on and the others are not" is pinned against that file directly.
local dbFile = assert(io.open(ADDONS .. "/Commander_Comms/CommanderCommsDB.lua"))
local dbSource = dbFile:read("*a")
dbFile:close()
CHECK(dbSource:find("SupportWhisper = true", 1, true) ~= nil,
    "support: it ships switched on")
CHECK(dbSource:find("RangeWhisper = false", 1, true) ~= nil
    and dbSource:find("SightWhisper = false", 1, true) ~= nil,
    "support: and it is the only whisper that does")

RangeScenario()

SupportCast(10060)
local supMsg = LastMessage()
CHECK(sent[1] and sent[1].channel == "WHISPER" and sent[1].to == "Straggler",
    "support: whispered to the ally it was spent on",
    sent[1] and (sent[1].channel .. "/" .. tostring(sent[1].to)))
CHECK(supMsg and supMsg:find("|Hspell:10060|h[Power Infusion]|h", 1, true),
    "support: the spell goes out as a link they can hover", supMsg)
CHECK(supMsg and supMsg:find("burn it now", 1, true),
    "support: it says what to DO, not just what was cast", supMsg)

-- Intervene puts no aura on the ally at all, which is why this reads the
-- CAST rather than the aura events
RangeScenario()
SupportCast(3411)
CHECK(LastMessage() and LastMessage():find("taking the next hit", 1, true),
    "support: a spell that applies no aura still lands its whisper", LastMessage())

-- Each spell carries its own instruction
RangeScenario()
SupportCast(6346)
CHECK(LastMessage() and LastMessage():find("next fear is blocked", 1, true),
    "support: every spell says its own thing", LastMessage())

-- Only what YOUR spellbook holds: a priest never carries the druid line
RangeScenario()
SupportCast(29166)
CHECK(LastMessage() == nil,
    "support: a spell you do not know is never announced", LastMessage())
RangeScenario()
SupportCast(1022)
CHECK(LastMessage() == nil,
    "support: nor another class's blessing", LastMessage())

-- A double-cast is one whisper
RangeScenario()
SupportCast(10060)
SupportCast(10060)
CHECK(#sent == 1, "support: the same spell on the same ally repeats once, not twice", #sent)

-- ...but the same spell on somebody ELSE is a different message to a
-- different person
RangeScenario()
SupportCast(10060, "Player-7", "Straggler")
SupportCast(10060, "Player-8", "Anchor")
CHECK(#sent == 2 and sent[2].to == "Anchor",
    "support: a second ally gets their own whisper",
    #sent .. "/" .. tostring(sent[2] and sent[2].to))

-- Nobody whispers themselves a Fear Ward. The case that matters is a RAID,
-- where you hold a raidN token of your own and so appear in the very walk
-- that resolves an ally's GUID to a unit.
RangeScenario()
inRaid = true
local realRaid1 = GUIDS.raid1
GUIDS.raid1, NAMES.raid1 = GUIDS.player, "Kicker"
SupportCast(6346, GUIDS.player, "Kicker")
CHECK(LastMessage() == nil, "support: never whispered to yourself", LastMessage())
GUIDS.raid1, NAMES.raid1 = realRaid1, "Straggler"
inRaid = false

-- A stranger out in the world is not in the group to be told
RangeScenario()
SupportCast(10060, "Player-99", "Wanderer")
CHECK(LastMessage() == nil,
    "support: only group members are whispered", LastMessage())

-- Somebody else's Power Infusion is not yours to announce
RangeScenario()
CLEU("SPELL_CAST_SUCCESS", { sourceGUID = "Player-2", sourceName = "Levira",
    spellID = 10060, spellName = "Power Infusion",
    destGUID = "Player-7", destName = "Straggler", destFlags = 0 })
CHECK(LastMessage() == nil,
    "support: only the cooldowns YOU spend are announced", LastMessage())

-- One person, so a battleground changes nothing
RangeScenario()
EnterBattleground(true)
SupportCast(10060)
CHECK(sent[1] and sent[1].channel == "WHISPER",
    "support: a battleground does not silence it", sent[1] and sent[1].channel)
LeaveBattleground()

-- ...and it can be switched off
RangeScenario()
CommanderCommsDB.SupportWhisper = false
SupportCast(10060)
CHECK(LastMessage() == nil, "support: off means off", LastMessage())
CommanderCommsDB.SupportWhisper = true

-- ===========================================================================
-- Mana burn: a drain on any group member's mana, told to the group with
-- how much is left
-- ===========================================================================

-- Fresh victims each time: full bars, nobody dead, and past every window
local function BurnScenario()
    Advance(200)
    ClearMessages()
    manaNow, manaMax, dead = {}, {}, {}
    -- Straggler (party1) runs an 8,000 bar; the others keep the 100 default
    manaMax.party1, manaNow.party1 = 8000, 8000
end

local function Burn(amount, o)
    o = o or {}
    CLEU(o.subevent or "SPELL_DRAIN", {
        sourceGUID = o.sourceGUID or "Player-2", sourceName = o.sourceName or "Levira",
        sourceFlags = o.sourceFlags or 0,
        destGUID = o.destGUID or "Player-7", destName = o.destName or "Straggler", destFlags = 0,
        spellID = o.spellID or 25380, spellName = o.spellName or SPELL_NAMES[o.spellID or 25380],
        amount = amount, powerType = o.powerType or 0,
    })
end

-- A real Mana Burn is a line on the first cast, once the bar has caught up
BurnScenario()
manaNow.party1 = 3440
Burn(1050)
CHECK(LastMessage() == nil, "burn: nothing until the victim's bar has updated", LastMessage())
Advance(0.3)
local burnMsg = LastMessage()
CHECK(#sent == 1 and sent[1].channel == "PARTY",
    "burn: one line to the group", #sent .. "/" .. tostring(sent[1] and sent[1].channel))
CHECK(burnMsg == "Straggler mana burned for 1050 by Levira with |cff71d5ff|Hspell:25380|h[Mana Burn]|h|r — 43% mana left.",
    "burn: who, how much, by whom, with what, and what is left", burnMsg)

-- The kicker's class rides along when a unit token can supply it
BurnScenario()
GUIDS.focus = "Player-2"
Burn(1050, { sourceFlags = COMBATLOG_OBJECT_TYPE_PLAYER })
Advance(0.3)
CHECK(LastMessage() and LastMessage():find("by Levira (Mage)", 1, true),
    "burn: the drainer's class is named when readable", LastMessage())
GUIDS.focus = nil

-- The victim being YOU reads in the first person
BurnScenario()
manaNow.player = 40
Burn(30, { destGUID = GUIDS.player, destName = "Kicker" })
Advance(0.3)
CHECK(LastMessage() and LastMessage():find("^I got mana burned for 30 by Levira"),
    "burn: on you it speaks in the first person", LastMessage())
CHECK(LastMessage() and LastMessage():find("40% mana left", 1, true),
    "burn: ...and still says what is left", LastMessage())

-- Small ticks are added up, not announced one by one: four Viper Sting
-- ticks of 120 on an 8,000 bar are 1.5% each, three are still under the
-- 5% line, and four clear it together
BurnScenario()
for i = 1, 3 do
    Burn(120, { subevent = "SPELL_PERIODIC_DRAIN", spellID = 27018 })
    Advance(2)
end
CHECK(#sent == 0, "burn: ticks under the threshold say nothing on their own", #sent)
Burn(120, { subevent = "SPELL_PERIODIC_DRAIN", spellID = 27018 })
Advance(0.3)
CHECK(#sent == 1 and LastMessage():find("for 480 (4 hits in 6s)", 1, true),
    "burn: once they add up they are one line with the total", LastMessage())
CHECK(LastMessage() and LastMessage():find("[Viper Sting]", 1, true),
    "burn: ...naming the spell that did it", LastMessage())

-- A quiet stretch breaks the sum: a tick long after the last starts over
BurnScenario()
Burn(150)
Advance(20)
Burn(150)
Advance(0.3)
CHECK(#sent == 0, "burn: ticks too far apart do not add up", #sent)

-- A chain of burns is one line per window carrying everything since
BurnScenario()
Burn(1050)
Advance(0.3)
CHECK(#sent == 1, "burn: the first of a chain is immediate", #sent)
Advance(3)
Burn(1050)
Advance(3)
Burn(1050)
Advance(0.3)
CHECK(#sent == 1, "burn: the next burns inside the window wait", #sent)
manaNow.party1 = 1600
Advance(2)
CHECK(#sent == 2 and LastMessage():find("for 2100 (2 hits in ", 1, true),
    "burn: ...and go out together when the window ends", LastMessage())
CHECK(LastMessage() and LastMessage():find("20% mana left", 1, true),
    "burn: the bar is read when the line goes out, not when the burn landed", LastMessage())

-- The window is a setting
BurnScenario()
CommanderCommsDB.ManaBurnCooldown = 4
Burn(1050); Advance(0.3)
Advance(3)
Burn(1050); Advance(1.3)
CHECK(#sent == 2, "burn: the per-victim window follows the slider", #sent)
CommanderCommsDB.ManaBurnCooldown = 8

-- ...and so is the threshold
BurnScenario()
CommanderCommsDB.ManaBurnMinPercent = 0.20
Burn(1050); Advance(0.3)
CHECK(#sent == 0, "burn: a burn under the threshold share is held back", #sent)
CommanderCommsDB.ManaBurnMinPercent = 0.05

-- Different victims are different tallies
BurnScenario()
Burn(1050)
Burn(30, { destGUID = "Player-8", destName = "Anchor" })
Advance(0.3)
CHECK(#sent == 2, "burn: each victim gets their own line", #sent)

-- Only mana. A rogue drained of energy is not news, whatever the log calls it
BurnScenario()
Burn(1050, { powerType = 3 })
Advance(0.3)
CHECK(#sent == 0, "burn: a drain of any other power is ignored", #sent)

-- Only the group. An enemy burned by your own priest is their problem
BurnScenario()
Burn(1050, { destGUID = "Player-99", destName = "Wanderer" })
Advance(0.3)
CHECK(#sent == 0, "burn: a victim outside the group is not announced", #sent)

-- ...and no group, no audience
BurnScenario()
inGroup = false
Burn(30, { destGUID = GUIDS.player, destName = "Kicker" })
Advance(0.3)
CHECK(#sent == 0, "burn: never fires solo", #sent)
inGroup = true

-- A victim who died before the line went out is past caring
BurnScenario()
Burn(1050)
dead.party1 = true
Advance(0.3)
CHECK(#sent == 0, "burn: a dead victim's line is dropped", #sent)

-- Death clears the tally too, so a resurrected healer starts clean
BurnScenario()
Burn(150)
CLEU("UNIT_DIED", { destGUID = "Player-7", destName = "Straggler" })
Advance(1)
Burn(150); Burn(150)
Advance(0.3)
CHECK(#sent == 0, "burn: a death forgets what was burned before it", #sent)

-- Group callout, so the battleground rule applies
BurnScenario()
EnterBattleground(true)
Burn(1050); Advance(0.3)
CHECK(#sent == 0, "burn: quiet in a battleground by default", #sent)
CommanderCommsDB.BattlegroundCallouts = true
CommanderCommsDB.BattlegroundToParty = true
BurnScenario()
Burn(1050); Advance(0.3)
CHECK(#sent == 1 and sent[1].channel == "PARTY",
    "burn: routed to the home party when asked for", sent[1] and sent[1].channel)
CommanderCommsDB.BattlegroundCallouts = false
CommanderCommsDB.BattlegroundToParty = false
LeaveBattleground()

-- And it can be switched off
BurnScenario()
CommanderCommsDB.ManaBurnCallouts = false
Burn(1050); Advance(0.3)
CHECK(#sent == 0, "burn: off means off", #sent)
CommanderCommsDB.ManaBurnCallouts = true

-- It ships on: the arena case it exists for is exactly the one where the
-- user has not been through the settings yet
CHECK(dbSource:find("ManaBurnCallouts = true", 1, true) ~= nil,
    "burn: it ships switched on")

-- ===========================================================================
-- 2.10.0 Rally on Me: the call that carries a place
-- ===========================================================================

-- Where the player stands, and the map names the line reads
local rallySpot = { map = 1429, x = 0.421376, y = 0.655 }
local subZone = "Goldshire"
C_Map = {
    GetBestMapForUnit = function() return rallySpot.map end,
    GetPlayerMapPosition = function()
        if not rallySpot.map then return nil end
        return { x = rallySpot.x, y = rallySpot.y }
    end,
    GetMapInfo = function(id)
        if id == 1429 then return { mapID = 1429, name = "Elwynn Forest", mapType = 3 } end
        return nil
    end,
}
function GetSubZoneText() return subZone end

-- Commander Orders, as far as Comms reaches into it
local shares = {}
local function OrdersStub()
    return {
        Add = function() error("Rally on Me must never add a waypoint of your own") end,
        SharePoint = function(spec, channel)
            shares[#shares + 1] = { spec = spec, channel = channel }
            return true
        end,
    }
end
CommanderOrders = OrdersStub()

local wheelFrame = _G.CommanderCommsWheel
local rally
for _, kid in ipairs(rawget(wheelFrame, "__kids") or {}) do
    if rawget(kid, "__text") == "Rally on Me" then rally = kid end
end
CHECK(rally ~= nil, "rally: a Rally on Me button sits on the wheel")

local function ClickRally()
    ClearMessages()
    shares = {}
    wheelFrame.__shown = true
    rally.__scripts.OnClick(rally, "LeftButton")
end

-- In a party: the line names the place, the spot goes to Orders
inGroup, inRaid, inInstanceGroup, instanceType = true, false, false, "none"
ClickRally()
CHECK(#sent == 1, "rally: one chat line", #sent)
CHECK(sent[1] and sent[1].msg == "Rally on me! Goldshire, Elwynn Forest 42.1, 65.5",
    "rally: it says where, readable without any addon", sent[1] and sent[1].msg)
CHECK(sent[1] and sent[1].channel == "PARTY", "rally: to the party", sent[1] and sent[1].channel)
CHECK(#shares == 1, "rally: and the spot is shared through Commander Orders", #shares)
local share = shares[1] or { spec = {} }
CHECK(share.spec.map == 1429 and share.spec.x == 0.421376 and share.spec.y == 0.655,
    "rally: the exact spot, not the rounded one in the chat line")
CHECK(share.spec.title == "Rally on Kicker", "rally: titled with your name", share.spec.title)
CHECK(share.spec.silent == true, "rally: silently (the chat line already says it)")
CHECK(share.channel == nil, "rally: to your group, Orders picks the channel", share.channel)
CHECK(not wheelFrame.__shown, "rally: the wheel closes, like every call")

-- The subzone is the zone itself: not said twice
subZone = "Elwynn Forest"
ClickRally()
CHECK(sent[1] and sent[1].msg == "Rally on me! Elwynn Forest 42.1, 65.5",
    "rally: a subzone that is the zone is not repeated", sent[1] and sent[1].msg)
subZone = ""
ClickRally()
CHECK(sent[1] and sent[1].msg == "Rally on me! Elwynn Forest 42.1, 65.5",
    "rally: no subzone, just the zone", sent[1] and sent[1].msg)
subZone = "Goldshire"

-- The setting: the chat line goes, the waypoint does not
CommanderCommsDB.RallyWaypoint = false
ClickRally()
CHECK(#sent == 1 and #shares == 0, "rally: switched off, words only", #shares)
CommanderCommsDB.RallyWaypoint = nil
ClickRally()
CHECK(#shares == 1, "rally: an unset setting counts as on (it ships on)", #shares)

-- Orders not loaded: the words still go out, and nothing errors
CommanderOrders = nil
ClickRally()
CHECK(#sent == 1 and sent[1].msg:find("Elwynn Forest 42.1, 65.5", 1, true) ~= nil,
    "rally: without Orders the call is the chat line", sent[1] and sent[1].msg)
CommanderOrders = { Add = function() end }       -- an Orders too old to share
ClickRally()
CHECK(#sent == 1, "rally: an Orders without SharePoint is treated as absent")
CommanderOrders = OrdersStub()

-- No map position (inside an instance): words only, nothing shared
rallySpot.map = nil
ClickRally()
CHECK(sent[1] and sent[1].msg == "Rally on me!", "rally: no position, just the call", sent[1] and sent[1].msg)
CHECK(#shares == 0, "rally: and nothing to share")
rallySpot.map = 1429

-- Battleground: the instance chat, like the rest of the wheel
inInstanceGroup, instanceType = true, "pvp"
ClickRally()
CHECK(sent[1] and sent[1].channel == "INSTANCE_CHAT", "rally: in a battleground, to the instance chat",
    sent[1] and sent[1].channel)
inInstanceGroup, instanceType = false, "none"

-- The preview says what will happen, like every call's
local function WheelTexts()
    local out = {}
    for _, region in ipairs(rawget(wheelFrame, "__regions") or {}) do
        local text = rawget(region, "__text")
        if type(text) == "string" then out[#out + 1] = text end
    end
    return table.concat(out, "\n")
end
rally.__scripts.OnEnter(rally)
local preview = WheelTexts()
CHECK(preview:find('"Rally on me! Goldshire, Elwynn Forest 42.1, 65.5"', 1, true) ~= nil,
    "rally: hovering previews the exact line", preview)
CHECK(preview:find("to party, and a waypoint for the group", 1, true) ~= nil,
    "rally: and says where it goes", preview)
rally.__scripts.OnLeave(rally)
CHECK(WheelTexts():find("COMMS", 1, true) ~= nil, "rally: leaving restores the wheel's centre")
inGroup = false
rally.__scripts.OnEnter(rally)
CHECK(WheelTexts():find("to say", 1, true) ~= nil and not WheelTexts():find("waypoint for the group", 1, true),
    "rally: solo, it goes to say and promises no waypoint", WheelTexts())
rally.__scripts.OnLeave(rally)
inGroup = true

-- The binding and /ccomms rally reach the same call, and respect the switch
ClearMessages(); shares = {}
CommanderComms_Rally()
CHECK(#sent == 1 and #shares == 1, "rally: CommanderComms_Rally makes the call")
CommanderCommsDB.EnableComms = false
ClearMessages(); shares = {}
CommanderComms_Rally()
CHECK(#sent == 0 and #shares == 0, "rally: and nothing while Comms is off")
CommanderCommsDB.EnableComms = true
CHECK(BINDING_NAME_COMMANDERCOMMS_RALLY == "Rally on Me", "rally: the binding has a name")
local bindingsFile = assert(io.open(ADDONS .. "/Commander_Comms/Bindings.xml"))
local bindings = bindingsFile:read("*a")
bindingsFile:close()
CHECK(bindings:find('name="COMMANDERCOMMS_RALLY"', 1, true) and bindings:find("CommanderComms_Rally()", 1, true),
    "rally: Bindings.xml binds it")
CHECK(not bindings:find("<!%-%-.-%-%-.-%-%->"), "rally: no '--' inside an XML comment")
CHECK(dbSource:find("RallyWaypoint = true", 1, true) ~= nil, "rally: the waypoint ships on")
CHECK(dbSource:find("rally = function()", 1, true) ~= nil, "rally: /ccomms rally exists")

-- The centre button stays clear of the ring: the ten calls already fill the
-- ellipse, which is why Rally on Me is not an eleventh slot on it
local function Rect(button)
    local p = rawget(button, "__point") or {}
    local x, y = p[4] or 0, p[5] or 0
    local w, h = rawget(button, "__w") or 0, rawget(button, "__h") or 0
    return x - w / 2, x + w / 2, y - h / 2, y + h / 2
end
local function Overlap(a, b)
    local al, ar, ab, at = Rect(a)
    local bl, br, bb, bt = Rect(b)
    return al < br and bl < ar and ab < bt and bb < at
end
local ringButtons, clash = 0, nil
for _, kid in ipairs(rawget(wheelFrame, "__kids") or {}) do
    if kid ~= rally and rawget(kid, "__template") == "UIPanelButtonTemplate" then
        ringButtons = ringButtons + 1
        if Overlap(kid, rally) then clash = rawget(kid, "__text") end
    end
end
CHECK(ringButtons == 10, "rally: the ring still holds its ten calls", ringButtons)
CHECK(clash == nil, "rally: and the centre button overlaps none of them", clash)
local rallyPoint = rawget(rally, "__point")
CHECK(rallyPoint and rallyPoint[4] == 0 and rallyPoint[5] < -24,
    "rally: centred, below the preview line", rallyPoint and rallyPoint[5])

-- ===========================================================================
-- 2.11.0 Rally on Me in Commander Orders 3.1's words
-- ===========================================================================
-- The coordinates are Orders' (FormatCoords, at the player's Coordinate
-- Decimals), and a share Orders refuses is said in Orders' words (Reason),
-- except "not in a group", which is the solo case
local printedLines = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printedLines[#printedLines + 1] = table.concat(parts, " ")
end
local decimals = 0
local shareAnswer = { true }
local function Orders31()
    local o = OrdersStub()
    o.FormatCoords = function(x, y)
        local f = "%." .. decimals .. "f, %." .. decimals .. "f"
        return string.format(f, x * 100, y * 100)
    end
    o.SharePoint = function(spec, channel)
        shares[#shares + 1] = { spec = spec, channel = channel }
        return unpack(shareAnswer)
    end
    o.Reason = function(why) return "Orders says: " .. tostring(why) end
    return o
end
CommanderOrders = Orders31()
inGroup = true
ClickRally()
CHECK(sent[1] and sent[1].msg == "Rally on me! Goldshire, Elwynn Forest 42, 66",
    "rally 3.1: the coordinates are Orders' (FormatCoords, Coordinate Decimals 0)", sent[1] and sent[1].msg)
decimals = 2
ClickRally()
CHECK(sent[1] and sent[1].msg == "Rally on me! Goldshire, Elwynn Forest 42.14, 65.50",
    "rally 3.1: ...and follow the setting (2)", sent[1] and sent[1].msg)
decimals = 1
ClickRally()
CHECK(sent[1] and sent[1].msg == "Rally on me! Goldshire, Elwynn Forest 42.1, 65.5",
    "rally 3.1: at the default (1) the line is the 2.10 one", sent[1] and sent[1].msg)
CHECK(#printedLines == 0, "rally 3.1: a share that went says nothing more", printedLines[1])
shareAnswer = { nil, "chat is locked down" }
ClickRally()
CHECK(#sent == 1, "rally 3.1: a refused share: the chat line still went", #sent)
CHECK(printedLines[#printedLines] == "Commander Comms: the rally waypoint did not go out: Orders says: chat is locked down",
    "rally 3.1: ...and the refusal is said in Orders' words", printedLines[#printedLines])
printedLines = {}
shareAnswer = { nil, "not in a group" }
ClickRally()
CHECK(#printedLines == 0, "rally 3.1: \"not in a group\" (solo) is not a complaint", printedLines[1])
shareAnswer = { true }
CommanderOrders = OrdersStub()        -- an Orders without FormatCoords: the line as before
decimals = 0
ClickRally()
CHECK(sent[1] and sent[1].msg == "Rally on me! Goldshire, Elwynn Forest 42.1, 65.5",
    "rally 3.1: without FormatCoords the line is the 2.10 one", sent[1] and sent[1].msg)
print = function() end

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
