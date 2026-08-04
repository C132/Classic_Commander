-- Commander Party Frames: combat-first party frames built for arena — the
-- design bar is "what would the world's best RMP want on screen", answered
-- per class. PvP information wins fights: shields and their exact remaining
-- absorb, shield uptime, dispels, CC status — raid upkeep (Int/Fort timers)
-- is deliberately icon-sized, never a bar. The chassis is one compact row
-- per ally — health, mana, identity, range, who the enemies are targeting,
-- dispellable debuffs, secure click-cast — and a CLASS LAYER decides what
-- the row's main bar and urgency states mean. Three cues triangulate every row so
-- it reads at a glance and survives colorblindness — an accent stripe (the
-- state), a strength bar, and a thin red drain (the thing blocking/afflicting).
-- PRIEST layer ("PWS"): shield = Power Word: Shield (absorb remaining), drain
--   = Weakened Soul, states = who to reshield next. The original board.
-- MAGE layer ("INT"): bar = HEALTH with a mana strip under it; the row's
--   number is the ally's TOTAL shielding (PW:S + Ice Barrier + Mana Shield +
--   wards + Sacrifice, any caster, tooltip-calibrated and drained live by
--   SPELL_ABSORBED); left status icons = Arcane Intellect state + the biggest
--   shield; a removable Curse turns the row purple (drain = curse remaining).
--   The header is the mage's upkeep banner: armor (with a switch popout),
--   Ice Barrier, own total shielding, Water Elemental, shield uptime, team
--   alerts, plus conjure/consume buttons. An opt-in extra appends own-shield
--   rows.
-- Other classes: the module sits inert (see CLASS_PROFILES).
--
-- Two signals keep the absorb number honest, each with a clear job:
--   1. C_UnitAuras scans of a unit we can address (self always; party/raid via
--      UNIT_AURA; anyone we target/mouseover) tell us a shield EXISTS, whose it
--      is (sourceUnit), and its exact 30s expiration. They also seed capacity
--      from a best-effort tooltip read the moment a fresh shield appears.
--   2. The combat log's SPELL_ABSORBED events subtract real damage from OUR
--      shields' remaining absorb. The parse is validated three ways (the
--      absorbing caster is us, the shield is Power Word: Shield, the victim is
--      a unit we track) so a mis-parse degrades to "no decrement", never to a
--      garbage number — the 30s timer and aura-removal still clear the row.
-- Weakened Soul is read from ANY caster's shield, because it gates OUR reshield.
--
-- Identity is icon-first by default (spell icon + class icon, name optional).
-- Optional secure mode makes each row a fixed-token unit button so mouseover
-- and click-cast macros work — bound to raw tokens (party1, raid3, ...) set once
-- out of combat, so nothing secure ever changes mid-combat while the insecure
-- visuals keep updating. Ten further features live behind their own flags.

-- ---------------------------------------------------------------------------
-- Spell data. IDs 17 and 6788 are stable across every client, so the localized
-- names resolve without hardcoding a locale; the rank table feeds the capacity
-- estimate for shields we cannot tooltip-scan (an out-of-range ally we buffed).
-- ---------------------------------------------------------------------------
local SDATA = {}   -- cold spell-data constants (one local: Lua's 200-local chunk cap)
SDATA.PWS_RANKS = {
    [17]    = 44,   [592]   = 88,   [600]   = 158,  [3747]  = 234,
    [6065]  = 301,  [6066]  = 381,  [10898] = 484,  [10899] = 605,
    [10900] = 763,  [10901] = 942,  [25217] = 1125, [25218] = 1265,
}
SDATA.SP_COEFF = 0.1            -- TBC PW:S bonus-healing coefficient (estimate)
SDATA.SHIELD_DURATION = 30      -- fallback only; the aura's real expiration wins
SDATA.WEAKENED_SOUL_MAX = 15    -- Weakened Soul duration, for the drain bar scale
SDATA.PWS_ICON = "Interface\\Icons\\Spell_Holy_PowerWordShield"
SDATA.RENEW_ICON = "Interface\\Icons\\Spell_Holy_Renew"
SDATA.RENEW_DURATION = 15       -- Renew HoT duration, for the sweep scale

-- IDs 17 / 6788 / 139 are stable everywhere, so the localized names resolve
-- without a locale table.
local PWS_NAME, WS_NAME, RENEW_NAME  -- resolved at login
local playerGUID
local myShieldValue = 0         -- nominal capacity of our own max-rank shield
local capObserved = {}          -- spellId -> real full absorb seen via tooltip

local CLASS_ICON_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

-- ---------------------------------------------------------------------------
-- Class profiles. The party-frame chassis (rows, health, dispel strip,
-- targeters, click-cast, urgency sort) is class-agnostic; the profile's LAYER
-- decides what the main bar/states mean:
--   PRIEST layer "PWS": Power Word: Shield absorb vs the Weakened Soul lockout.
--   MAGE layer "INT": Arcane Intellect/Brilliance upkeep vs removable Curses,
--     plus an opt-in self-shield extra (selfSpells below) whose recast lockout
--     is each spell's own cooldown.
-- Any other class gets no layer, so the module goes inert for it at login.
-- The gate is runtime-only on purpose: the saved DB is account-wide, so
-- writing EnableShield=false here would disable the board on an alt too.
-- Base absorb values are trainer-tooltip numbers per rank; they only feed the
-- fallback capacity — a live tooltip read of the actual aura always wins.
-- ---------------------------------------------------------------------------
SDATA.MAGE_SPELLS = {
    { key = "BARRIER", label = "Barrier", baseId = 11426, duration = 60, cooldown = 30,
      school = 5, coeff = 0.1, icon = "Interface\\Icons\\Spell_Ice_Lament",
      ranks = { [11426] = 438, [13031] = 549, [13032] = 678, [13033] = 818,
                [27134] = 925, [33405] = 1075 } },
    { key = "MANA", label = "Mana Sh.", baseId = 1463, duration = 60, cooldown = 0,
      icon = "Interface\\Icons\\Spell_Shadow_DetectLesserInvisibility",
      ranks = { [1463] = 120, [8494] = 210, [8495] = 300, [10191] = 390,
                [10192] = 480, [10193] = 570, [27131] = 710 } },
    { key = "FWARD", label = "Fire W.", baseId = 543, duration = 30, cooldown = 30, ward = true,
      icon = "Interface\\Icons\\Spell_Fire_FireArmor",
      ranks = { [543] = 165, [8457] = 290, [8458] = 470, [10223] = 675,
                [10225] = 875, [27128] = 1125 } },
    { key = "FRWARD", label = "Frost W.", baseId = 6143, duration = 30, cooldown = 30, ward = true,
      icon = "Interface\\Icons\\Spell_Frost_FrostWard",
      ranks = { [6143] = 165, [8461] = 290, [8462] = 470, [10177] = 675,
                [28609] = 875, [32796] = 1125 } },
}
local CLASS_PROFILES = {
    PRIEST = { layer = "PWS" },
    MAGE   = { layer = "INT", selfSpells = SDATA.MAGE_SPELLS },
}
local profile               -- resolved at login; nil = unsupported class (module inert)
local layer                 -- the active profile's layer ("PWS" / "INT"), nil when inert
local playerClass           -- our class token, for self-row name coloring
local trackedSpells = {}    -- INT self extra: known tracked spells, in profile order
local trackedByName = {}    -- localized spell name -> tracked-spell def
local SELF_KEY = "cself"    -- shieldState/wsState key prefix for self-spell rows

-- Mage buff layer: Arcane Intellect (single) and Arcane Brilliance (group)
-- both satisfy "buffed"; names resolve from stable base IDs at login.
SDATA.AI_ID, SDATA.BRILLIANCE_ID = 1459, 23028
local AI_NAME, BRILLIANCE_NAME
local AI_ICON = "Interface\\Icons\\Spell_Holy_MagicalSentry"
SDATA.AI_DURATION = 1800    -- fallback scale; the aura's real duration wins

-- Self armor (Frost/Ice/Mage/Molten Armor): the upkeep banner's first segment
-- AND the armor-switch popout. Ranks listed best-first per line; a line whose
-- superseding line is known (Frost once Ice exists) stays out of the popout.
SDATA.ARMOR_LINES = {
    { key = "MOLTEN", ids = { 30482 } },
    { key = "MAGE",   ids = { 27125, 22783, 22782, 6117 } },
    { key = "ICE",    ids = { 27124, 10220, 10219, 7320, 7302 } },
    { key = "FROST",  ids = { 7301, 7300, 168 }, supersededBy = "ICE" },
}
local armorNames = {}   -- localized armor name -> spell icon (resolved at login)
local selfArmor         -- { icon, expire } our current armor buff, nil when naked
local barrierDef        -- Ice Barrier's tracked-spell def once known (debug info)

-- Water Elemental (frost talent): lifespan + Freeze cooldown on the banner
-- while it is in play
SDATA.WATER_ELE_ID, SDATA.FREEZE_ID = 31687, 33395
SDATA.ELE_DURATION = 45
local eleKnown, eleIcon, freezeName, freezeIcon
local eleExpire = 0             -- lifespan clock, armed by SPELL_SUMMON

-- Conjured consumables, best rank first (banner conjure/consume buttons)
SDATA.CONJURED_WATER = { 30703, 8079, 8078, 8077, 3772, 2136, 2288, 5350 }
SDATA.CONJURED_FOOD  = { 22019, 22895, 8076, 8075, 1487, 1114, 1113, 5349 }
SDATA.CONJURE_WATER_ID, SDATA.CONJURE_FOOD_ID = 5504, 587
local mageUtil, conjureBtn, consumeBtn, armorPop, armorBtn
local armorButtons = {}
local mageBtnsDirty = false     -- attribute binds queued for after combat
local settingsBtn               -- header gear opening the settings page (any class)

-- Aggregate shielding (both layers): every absorb aura we can name — PW:S,
-- Ice Barrier, Mana Shield, the wards, warlock Sacrifice — from ANY caster,
-- summed per ally and EMBEDDED into the health bar as colored segments.
-- Capacity comes from a tooltip read when the unit is addressable, else the
-- rank tables; SPELL_ABSORBED drains it live.
SDATA.SAC_ID = 7812             -- warlock Sacrifice (absorb bubble)
local absorbNames = {}          -- localized absorb-aura name -> true
local allyAbsorbs = {}          -- guid -> { [name] = {expire, duration, icon, capacity, absorbed} }
local scanAbsorbs = {}          -- per-scan scratch: name -> {expire, duration, icon, spellId, index}
SDATA.SHIELD_COLORS = {}        -- localized absorb name -> segment tint
SDATA.SHIELD_ORDER = {}         -- localized absorb name -> fixed segment order
SDATA.SHIELD_COLOR_DEFAULT = { 0.55, 0.55, 0.58 }
SDATA.SHIELD_UNIFORM = { 0.93, 0.90, 0.82 }   -- one-color mode: classic cream absorb
SDATA.MAX_SHIELD_SEGS = 5

-- Fallback capacity per rank for EVERY tracked absorb, layer-independent —
-- the aggregate tracker and the own-shield tracker must never disagree just
-- because one of them lacked a rank table.
SDATA.ABSORB_RANKS = {}
for id, base in pairs(SDATA.PWS_RANKS) do SDATA.ABSORB_RANKS[id] = base end
for _, def in ipairs(SDATA.MAGE_SPELLS) do
    for id, base in pairs(def.ranks) do SDATA.ABSORB_RANKS[id] = base end
end

-- The settings panel builds per-class too; it lives in the other file, so it
-- asks the engine which layer (if any) this character gets.
function CommanderPartyFrames_GetProfileMode()
    local _, classToken = UnitClass("player")
    local p = CLASS_PROFILES[classToken or ""]
    return p and p.layer or nil, classToken
end

-- ---------------------------------------------------------------------------
-- Dispels. What each class can actually remove from a friendly target on this
-- client (TBC): Priest Magic+Disease, Paladin Magic+Poison+Disease, Druid
-- Curse+Poison, Mage Curse, Shaman Poison+Disease. Everyone else dispels
-- nothing, so the strip simply stays empty for them.
-- ---------------------------------------------------------------------------
local DISPEL_BY_CLASS = {
    PRIEST  = { Magic = true, Disease = true },
    PALADIN = { Magic = true, Poison = true, Disease = true },
    DRUID   = { Curse = true, Poison = true },
    MAGE    = { Curse = true },
    SHAMAN  = { Poison = true, Disease = true },
}
local DISPEL_COLORS = {
    Magic   = { 0.25, 0.60, 1.00 },
    Curse   = { 0.65, 0.30, 0.95 },
    Disease = { 0.62, 0.46, 0.22 },
    Poison  = { 0.20, 0.80, 0.25 },
    None    = { 0.70, 0.70, 0.70 },
}
-- Crowd control worth a glow. One base ID per spell — every rank shares the
-- base name, so matching resolved names catches them all, locale-safe.
local CC_SPELL_IDS = {
    118,    -- Polymorph
    5782,   -- Fear
    5484,   -- Howl of Terror
    6358,   -- Seduction
    710,    -- Banish
    1098,   -- Enslave Demon
    605,    -- Mind Control
    8122,   -- Psychic Scream
    9484,   -- Shackle Undead
    2637,   -- Hibernate
    339,    -- Entangling Roots
    122,    -- Frost Nova
    3355,   -- Freezing Trap Effect
    19386,  -- Wyvern Sting
    1513,   -- Scare Beast
    853,    -- Hammer of Justice
    20066,  -- Repentance
    10326,  -- Turn Undead
    6789,   -- Death Coil
    700,    -- Sleep
    33786,  -- Cyclone
    15487,  -- Silence
    2094,   -- Blind
    5246,   -- Intimidating Shout
    12494,  -- Frostbite
    33395,  -- Freeze (Water Elemental)
}
-- Debuffs that matter to a healer even though they usually cannot be dispelled.
-- HEAL = cuts healing received (absorbs are NOT reduced, so these argue for a
-- shield over a heal), CC = undispellable crowd control / stuns, SILENCE = the
-- ally cannot cast. Anything tagged CC also joins the glow set below.
local IMPORTANT_IDS = {
    -- Healing reduction
    [12294] = "HEAL",   -- Mortal Strike
    [19434] = "HEAL",   -- Aimed Shot
    [13218] = "HEAL",   -- Wound Poison
    -- Undispellable crowd control / stuns
    [2094]  = "CC",     -- Blind
    [6770]  = "CC",     -- Sap
    [1776]  = "CC",     -- Gouge
    [408]   = "CC",     -- Kidney Shot
    [1833]  = "CC",     -- Cheap Shot
    [5211]  = "CC",     -- Bash
    [9005]  = "CC",     -- Pounce
    [22570] = "CC",     -- Maim
    [19503] = "CC",     -- Scatter Shot
    [12809] = "CC",     -- Concussion Blow
    [7922]  = "CC",     -- Charge Stun
    [20253] = "CC",     -- Intercept Stun
    [20549] = "CC",     -- War Stomp
    [30283] = "CC",     -- Shadowfury
    [12355] = "CC",     -- Impact
    [5246]  = "CC",     -- Intimidating Shout
    [33786] = "CC",     -- Cyclone
    -- Silences
    [1330]  = "SILENCE",-- Garrote - Silence
    [18469] = "SILENCE",-- Counterspell - Silenced
    [24259] = "SILENCE",-- Spell Lock
    [34490] = "SILENCE",-- Silencing Shot
    [28730] = "SILENCE",-- Arcane Torrent
}
local IMPORTANT_COLORS = {
    HEAL    = { 0.95, 0.25, 0.25 },
    CC      = { 1.00, 0.55, 0.15 },
    SILENCE = { 0.85, 0.55, 0.30 },
}
local MAX_DISPEL_ICONS = 5

local myDispelTypes = {}   -- dispel types OUR class can remove (resolved at login)
local ccNames = {}          -- localized CC spell names -> true (resolved at login)
local importantNames = {}   -- localized name -> category (HEAL / CC / SILENCE)

-- CommanderPartyFramesDB accessor with a fallback, so every read is nil-safe even
-- before defaults are applied.
local function DB(key, default)
    local v = CommanderPartyFramesDB and CommanderPartyFramesDB[key]
    if v == nil then return default end
    return v
end

-- ---------------------------------------------------------------------------
-- Layout constants. Kept tight on purpose: this is a HUD, not a window.
-- ---------------------------------------------------------------------------
local ROW_H = 22
local ROW_GAP = 2
local BAR_H = 12
local HEALTH_H = 6
local WS_H = 3
local STRIPE_W = 3
local ICON_SIZE = 18
local SMALL_ICON = 15   -- INT layer: two status icons share the left slot
local RENEW_ICON_SIZE = 16
local NAME_W = 60
local SHORT_NAME_W = 44
local PAD = 6
local HEADER_H = 15
local DRAW_THROTTLE = 0.1
local UPTIME_SAMPLE = 1.0

-- state -> { rank (sort, lower = more urgent), color (accent stripe) }
local STATES = {
    CURSED   = { rank = -2, color = { 0.65, 0.30, 0.95 } },-- INT: removable curse, decurse NOW
    CCED     = { rank = -1, color = { 1.00, 0.55, 0.15 } },-- INT: teammate in crowd control
    READY    = { rank = 0, color = { 1.00, 0.90, 0.25 } }, -- no shield/buff, castable NOW
    EXPOSED  = { rank = 1, color = { 0.95, 0.25, 0.25 } }, -- no shield, still lockout-bound
    REFRESH  = { rank = 2, color = { 0.35, 0.85, 1.00 } }, -- low/expiring, can recast
    FADING   = { rank = 3, color = { 1.00, 0.55, 0.15 } }, -- low/expiring, but locked
    SHIELDED = { rank = 4, color = { 0.35, 0.85, 0.40 } }, -- healthy shield/buff of ours
    OTHER    = { rank = 5, color = { 0.55, 0.60, 0.78 } }, -- an ally priest's shield / no buff target
    DEAD     = { rank = 9, color = { 0.42, 0.42, 0.42 } }, -- dead / offline
    EMPTY    = { rank = 10, color = { 0, 0, 0 } },          -- an empty secure slot
}
-- Rows the player usually acts on; the rest are hidden by Only Show Alerts
local ALERT_STATES = { CURSED = true, CCED = true, READY = true, EXPOSED = true, REFRESH = true, FADING = true }
-- The recast/act window is open (castable and wanted) in these states
local CASTABLE_STATES = { CURSED = true, READY = true, REFRESH = true }

-- Persistent per-unit state, keyed by GUID so every token that points at a unit
-- (party3, target, mouseover) refines one record.
local shieldState = {}   -- guid -> { spellId, expire, capacity, absorbed, mine }
local wsState = {}        -- guid -> weakened-soul expirationTime
local renewState = {}     -- guid -> OUR Renew expirationTime (Renew tracking)
local intState = {}       -- guid -> { expire, duration } for Arcane Int/Brilliance
local curseState = {}     -- guid -> { expire, duration } first removable debuff (INT layer)
local ccState = {}        -- guid -> { expire, duration, icon, name } first CC debuff (INT layer)
-- Live header tallies for the INT layer, rebuilt every draw pass
local intCurses, intCCs = 0, 0

-- ---------------------------------------------------------------------------
-- Specialization inference (chassis, both layers). TBC has no spec API for
-- other players, so specs are learned from spec-defining spells: CLEU
-- SPELL_CAST_SUCCESS from group members and marker auras seen in our own
-- scans (Shadowform, Moonkin/Tree, …). Names resolve at login (locale- and
-- rank-safe); first marker stamps the spec, later conflicting markers
-- overwrite (respec). Session-local by design.
-- ---------------------------------------------------------------------------
SDATA.SPEC_MARKER_IDS = {
    -- Mage
    [31687] = "FROST", [11426] = "FROST", [12472] = "FROST",   -- Elemental, Ice Barrier, Icy Veins
    [11129] = "FIRE", [31661] = "FIRE", [11113] = "FIRE",      -- Combustion, Dragon's Breath, Blast Wave
    [12043] = "ARCANE", [12042] = "ARCANE", [31589] = "ARCANE",-- PoM, Arcane Power, Slow
    -- Priest
    [33206] = "DISC", [10060] = "DISC", [14751] = "DISC",      -- Pain Suppression, Power Infusion, Inner Focus
    [15473] = "SHADOW", [15286] = "SHADOW", [15487] = "SHADOW",-- Shadowform, Vampiric Embrace, Silence
    [724] = "HOLY", [34861] = "HOLY",                          -- Lightwell, Circle of Healing
    -- Warlock
    [30108] = "AFFLICTION", [18220] = "AFFLICTION",            -- Unstable Affliction, Dark Pact
    [30146] = "DEMONOLOGY", [19028] = "DEMONOLOGY",            -- Summon Felguard, Soul Link
    [30283] = "DESTRUCTION", [17962] = "DESTRUCTION",          -- Shadowfury, Conflagrate
    -- Druid
    [33891] = "RESTORATION", [18562] = "RESTORATION", [17116] = "RESTORATION", -- Tree, Swiftmend, NS
    [24858] = "BALANCE", [33831] = "BALANCE", [5570] = "BALANCE",              -- Moonkin, Treants, Insect Swarm
    [33878] = "FERAL", [33876] = "FERAL", [16979] = "FERAL",                   -- Mangle x2, Feral Charge
    -- Rogue
    [1329] = "ASSASSINATION", [14177] = "ASSASSINATION",       -- Mutilate, Cold Blood
    [13877] = "COMBAT", [13750] = "COMBAT",                    -- Blade Flurry, Adrenaline Rush
    [36554] = "SUBTLETY", [14185] = "SUBTLETY", [16511] = "SUBTLETY", -- Shadowstep, Preparation, Hemorrhage
    -- Warrior
    [12294] = "ARMS", [12328] = "ARMS",                        -- Mortal Strike, Sweeping Strikes
    [23881] = "FURY", [29801] = "FURY", [12292] = "FURY",      -- Bloodthirst, Rampage, Death Wish
    [23922] = "PROTECTION", [20243] = "PROTECTION", [12975] = "PROTECTION", -- Shield Slam, Devastate, Last Stand
    -- Paladin
    [20473] = "HOLY", [20216] = "HOLY", [31842] = "HOLY",      -- Holy Shock, Divine Favor, Divine Illumination
    [20925] = "PROTECTION", [31935] = "PROTECTION",            -- Holy Shield, Avenger's Shield
    [35395] = "RETRIBUTION", [20066] = "RETRIBUTION",          -- Crusader Strike, Repentance
    -- Hunter
    [19574] = "BEASTMASTERY", [19577] = "BEASTMASTERY",        -- Bestial Wrath, Intimidation
    [19506] = "MARKSMANSHIP", [34490] = "MARKSMANSHIP",        -- Trueshot Aura, Silencing Shot
    [19386] = "SURVIVAL", [19306] = "SURVIVAL",                -- Wyvern Sting, Counterattack
    -- Shaman
    [16166] = "ELEMENTAL", [30706] = "ELEMENTAL",              -- Elemental Mastery, Totem of Wrath
    [17364] = "ENHANCEMENT", [30823] = "ENHANCEMENT",          -- Stormstrike, Shamanistic Rage
    [16190] = "RESTORATION", [16188] = "RESTORATION", [974] = "RESTORATION", -- Mana Tide, NS, Earth Shield
}
-- Talent-tab icons per class+spec (the Specialization display modes)
SDATA.SPEC_ICONS = {
    MAGE    = { ARCANE = "Interface\\Icons\\Spell_Holy_MagicalSentry", FIRE = "Interface\\Icons\\Spell_Fire_FireBolt02", FROST = "Interface\\Icons\\Spell_Frost_FrostBolt02" },
    PRIEST  = { DISC = "Interface\\Icons\\Spell_Holy_WordFortitude", HOLY = "Interface\\Icons\\Spell_Holy_HolyBolt", SHADOW = "Interface\\Icons\\Spell_Shadow_ShadowWordPain" },
    WARLOCK = { AFFLICTION = "Interface\\Icons\\Spell_Shadow_DeathCoil", DEMONOLOGY = "Interface\\Icons\\Spell_Shadow_Metamorphosis", DESTRUCTION = "Interface\\Icons\\Spell_Shadow_RainOfFire" },
    DRUID   = { BALANCE = "Interface\\Icons\\Spell_Nature_StarFall", FERAL = "Interface\\Icons\\Ability_Racial_BearForm", RESTORATION = "Interface\\Icons\\Spell_Nature_HealingTouch" },
    ROGUE   = { ASSASSINATION = "Interface\\Icons\\Ability_Rogue_Eviscerate", COMBAT = "Interface\\Icons\\Ability_BackStab", SUBTLETY = "Interface\\Icons\\Ability_Stealth" },
    WARRIOR = { ARMS = "Interface\\Icons\\Ability_Warrior_SavageBlow", FURY = "Interface\\Icons\\Ability_Warrior_InnerRage", PROTECTION = "Interface\\Icons\\Ability_Warrior_DefensiveStance" },
    PALADIN = { HOLY = "Interface\\Icons\\Spell_Holy_HolyBolt", PROTECTION = "Interface\\Icons\\Spell_Holy_DevotionAura", RETRIBUTION = "Interface\\Icons\\Spell_Holy_AuraOfLight" },
    HUNTER  = { BEASTMASTERY = "Interface\\Icons\\Ability_Hunter_BeastTaming", MARKSMANSHIP = "Interface\\Icons\\Ability_Marksmanship", SURVIVAL = "Interface\\Icons\\Ability_Hunter_SwiftStrike" },
    SHAMAN  = { ELEMENTAL = "Interface\\Icons\\Spell_Nature_Lightning", ENHANCEMENT = "Interface\\Icons\\Spell_Nature_LightningShield", RESTORATION = "Interface\\Icons\\Spell_Nature_MagicImmunity" },
}
local specMarkerNames = {}  -- localized marker spell name -> spec token
local specState = {}        -- guid -> spec token (session cache, never pruned)
local groupGuids = {}       -- guid -> classToken for the current roster (CLEU filter)

-- ---------------------------------------------------------------------------
-- Party Ability Bar: the curated cooldown book (see
-- prompts/commander-party-ability-bar.md). Tier 1 = always on the strip;
-- tier 2 = only while cooling down. kind ranks eviction: DEF > CC > KICK >
-- OFF > UTIL. spec limits an entry to a known spec (nil = whole class).
-- lock = "hypo"/"forb" ties the icon to that debuff (red rim, longer sweep).
-- resets = keys this ability refunds when cast (Cold Snap, Preparation).
-- Cooldowns are BASE values; talent reductions self-correct on the next
-- observed cast. Matching is by localized NAME (rank-safe); `id` resolves
-- the name/icon at login with the literal fallbacks for safety.
-- ---------------------------------------------------------------------------
SDATA.ABILITY_BOOK = {
    MAGE = {
        { key = "BLOCK", id = 45438, name = "Ice Block", icon = "Interface\\Icons\\Spell_Frost_Frost",
          cd = 300, tier = 1, kind = "DEF", lock = "hypo" },
        { key = "COLDSNAP", id = 11958, name = "Cold Snap", icon = "Interface\\Icons\\Spell_Frost_WizardMark",
          cd = 480, tier = 1, kind = "UTIL", spec = "FROST", resets = { "BLOCK", "WATERELE" } },
        { key = "CS", id = 2139, name = "Counterspell", icon = "Interface\\Icons\\Spell_Frost_IceShock",
          cd = 24, tier = 1, kind = "KICK" },
        { key = "BLINK", id = 1953, name = "Blink", icon = "Interface\\Icons\\Spell_Arcane_Blink",
          cd = 15, tier = 1, kind = "DEF" },
        { key = "WATERELE", id = 31687, name = "Summon Water Elemental", icon = "Interface\\Icons\\Spell_Frost_SummonWaterElemental_2",
          cd = 180, tier = 1, kind = "OFF", spec = "FROST" },
        { key = "COMBUST", id = 11129, name = "Combustion", icon = "Interface\\Icons\\Spell_Fire_SealOfFire",
          cd = 180, tier = 1, kind = "OFF", spec = "FIRE" },
        { key = "DBREATH", id = 31661, name = "Dragon's Breath", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
          cd = 20, tier = 1, kind = "CC", spec = "FIRE" },
        { key = "POM", id = 12043, name = "Presence of Mind", icon = "Interface\\Icons\\Spell_Nature_EnchantArmor",
          cd = 180, tier = 1, kind = "UTIL", spec = "ARCANE" },
        { key = "AP", id = 12042, name = "Arcane Power", icon = "Interface\\Icons\\Spell_Nature_Lightning",
          cd = 180, tier = 1, kind = "OFF", spec = "ARCANE" },
        { key = "EVOC", id = 12051, name = "Evocation", icon = "Interface\\Icons\\Spell_Nature_Purge",
          cd = 480, tier = 2, kind = "UTIL" },
    },
    PRIEST = {
        { key = "FEAR", id = 8122, name = "Psychic Scream", icon = "Interface\\Icons\\Spell_Shadow_PsychicScream",
          cd = 30, tier = 1, kind = "CC" },
        { key = "PAINSUP", id = 33206, name = "Pain Suppression", icon = "Interface\\Icons\\Spell_Holy_PainSupression",
          cd = 120, tier = 1, kind = "DEF", spec = "DISC" },
        { key = "PI", id = 10060, name = "Power Infusion", icon = "Interface\\Icons\\Spell_Holy_PowerInfusion",
          cd = 180, tier = 1, kind = "OFF", spec = "DISC" },
        { key = "FEARWARD", id = 6346, name = "Fear Ward", icon = "Interface\\Icons\\Spell_Holy_Excorcism",
          cd = 180, tier = 1, kind = "DEF" },
        { key = "SILENCE", id = 15487, name = "Silence", icon = "Interface\\Icons\\Spell_Shadow_ImpPhaseShift",
          cd = 45, tier = 1, kind = "KICK", spec = "SHADOW" },
        { key = "FIEND", id = 34433, name = "Shadowfiend", icon = "Interface\\Icons\\Spell_Shadow_Shadowfiend",
          cd = 300, tier = 2, kind = "UTIL" },
        { key = "IF", id = 14751, name = "Inner Focus", icon = "Interface\\Icons\\Spell_Frost_WindWalkOn",
          cd = 180, tier = 2, kind = "UTIL" },
    },
    ROGUE = {
        { key = "VANISH", id = 1856, name = "Vanish", icon = "Interface\\Icons\\Ability_Vanish",
          cd = 300, tier = 1, kind = "DEF" },
        { key = "BLIND", id = 2094, name = "Blind", icon = "Interface\\Icons\\Spell_Shadow_MindSteal",
          cd = 300, tier = 1, kind = "CC" },
        { key = "KICK", id = 1766, name = "Kick", icon = "Interface\\Icons\\Ability_Kick",
          cd = 10, tier = 1, kind = "KICK" },
        { key = "EVASION", id = 5277, name = "Evasion", icon = "Interface\\Icons\\Spell_Shadow_ShadowWard",
          cd = 300, tier = 1, kind = "DEF" },
        { key = "CLOAK", id = 31224, name = "Cloak of Shadows", icon = "Interface\\Icons\\Spell_Shadow_NetherCloak",
          cd = 60, tier = 1, kind = "DEF" },
        { key = "PREP", id = 14185, name = "Preparation", icon = "Interface\\Icons\\Spell_Shadow_AntiShadow",
          cd = 600, tier = 1, kind = "UTIL", spec = "SUBTLETY", resets = { "VANISH", "EVASION", "SPRINT" } },
        { key = "SPRINT", id = 2983, name = "Sprint", icon = "Interface\\Icons\\Ability_Rogue_Sprint",
          cd = 300, tier = 2, kind = "UTIL" },
        { key = "SSTEP", id = 36554, name = "Shadowstep", icon = "Interface\\Icons\\Ability_Rogue_Shadowstep",
          cd = 30, tier = 1, kind = "UTIL", spec = "SUBTLETY" },
        { key = "AR", id = 13750, name = "Adrenaline Rush", icon = "Interface\\Icons\\Spell_Shadow_ShadowWordDominate",
          cd = 300, tier = 1, kind = "OFF", spec = "COMBAT" },
        { key = "CB", id = 14177, name = "Cold Blood", icon = "Interface\\Icons\\Spell_Ice_Lament",
          cd = 180, tier = 2, kind = "OFF", spec = "ASSASSINATION" },
    },
    PALADIN = {
        { key = "BUBBLE", id = 642, name = "Divine Shield", icon = "Interface\\Icons\\Spell_Holy_DivineIntervention",
          cd = 300, tier = 1, kind = "DEF", lock = "forb" },
        { key = "BOP", id = 1022, name = "Blessing of Protection", icon = "Interface\\Icons\\Spell_Holy_SealOfProtection",
          cd = 300, tier = 1, kind = "DEF", lock = "forb" },
        { key = "HOJ", id = 853, name = "Hammer of Justice", icon = "Interface\\Icons\\Spell_Holy_SealOfMight",
          cd = 60, tier = 1, kind = "CC" },
        { key = "FREEDOM", id = 1044, name = "Blessing of Freedom", icon = "Interface\\Icons\\Spell_Holy_SealOfValor",
          cd = 25, tier = 1, kind = "UTIL" },
        { key = "REPENT", id = 20066, name = "Repentance", icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing",
          cd = 60, tier = 1, kind = "CC", spec = "RETRIBUTION" },
        { key = "DFAVOR", id = 20216, name = "Divine Favor", icon = "Interface\\Icons\\Spell_Holy_Heal",
          cd = 120, tier = 2, kind = "UTIL", spec = "HOLY" },
        { key = "LOH", id = 633, name = "Lay on Hands", icon = "Interface\\Icons\\Spell_Holy_LayOnHands",
          cd = 3600, tier = 2, kind = "UTIL" },
    },
    WARRIOR = {
        { key = "INTERCEPT", id = 20252, name = "Intercept", icon = "Interface\\Icons\\Ability_Rogue_Sprint",
          cd = 30, tier = 1, kind = "CC" },
        { key = "PUMMEL", id = 6552, name = "Pummel", icon = "Interface\\Icons\\INV_Gauntlets_04",
          cd = 10, tier = 1, kind = "KICK" },
        { key = "BERSRAGE", id = 18499, name = "Berserker Rage", icon = "Interface\\Icons\\Spell_Nature_AncestralGuardian",
          cd = 30, tier = 1, kind = "UTIL" },
        { key = "INTIM", id = 5246, name = "Intimidating Shout", icon = "Interface\\Icons\\Ability_GolemThunderClap",
          cd = 180, tier = 1, kind = "CC" },
        { key = "REFLECT", id = 23920, name = "Spell Reflection", icon = "Interface\\Icons\\Ability_Warrior_ShieldReflection",
          cd = 10, tier = 1, kind = "DEF" },
        { key = "DEATHWISH", id = 12292, name = "Death Wish", icon = "Interface\\Icons\\Spell_Shadow_DeathPact",
          cd = 180, tier = 1, kind = "OFF", spec = "FURY" },
        { key = "LASTSTAND", id = 12975, name = "Last Stand", icon = "Interface\\Icons\\Spell_Holy_AshesToAshes",
          cd = 480, tier = 1, kind = "DEF", spec = "PROTECTION" },
        { key = "SWALL", id = 871, name = "Shield Wall", icon = "Interface\\Icons\\Ability_Warrior_ShieldWall",
          cd = 1800, tier = 2, kind = "DEF" },
        { key = "RECK", id = 1719, name = "Recklessness", icon = "Interface\\Icons\\Ability_CriticalStrike",
          cd = 1800, tier = 2, kind = "OFF" },
    },
    DRUID = {
        { key = "BASH", id = 5211, name = "Bash", icon = "Interface\\Icons\\Ability_Druid_Bash",
          cd = 60, tier = 1, kind = "CC" },
        { key = "FCHARGE", id = 16979, name = "Feral Charge", icon = "Interface\\Icons\\Ability_Hunter_Pet_Bear",
          cd = 15, tier = 1, kind = "KICK", spec = "FERAL" },
        { key = "NS", id = 17116, name = "Nature's Swiftness", icon = "Interface\\Icons\\Spell_Nature_RavenForm",
          cd = 180, tier = 1, kind = "UTIL", spec = "RESTORATION" },
        { key = "INNERVATE", id = 29166, name = "Innervate", icon = "Interface\\Icons\\Spell_Nature_Lightning",
          cd = 360, tier = 1, kind = "UTIL" },
        { key = "BARKSKIN", id = 22812, name = "Barkskin", icon = "Interface\\Icons\\Spell_Nature_StoneClawTotem",
          cd = 60, tier = 1, kind = "DEF" },
        { key = "REBIRTH", id = 20484, name = "Rebirth", icon = "Interface\\Icons\\Spell_Nature_Reincarnation",
          cd = 1200, tier = 2, kind = "UTIL" },
        { key = "FRENZIED", id = 22842, name = "Frenzied Regeneration", icon = "Interface\\Icons\\Ability_BullRush",
          cd = 180, tier = 2, kind = "DEF", spec = "FERAL" },
    },
    WARLOCK = {
        { key = "COIL", id = 6789, name = "Death Coil", icon = "Interface\\Icons\\Spell_Shadow_DeathCoil",
          cd = 120, tier = 1, kind = "CC" },
        { key = "HOWL", id = 5484, name = "Howl of Terror", icon = "Interface\\Icons\\Spell_Shadow_DeathScream",
          cd = 40, tier = 1, kind = "CC" },
        { key = "SHADOWFURY", id = 30283, name = "Shadowfury", icon = "Interface\\Icons\\Spell_Shadow_Shadowfury",
          cd = 20, tier = 1, kind = "CC", spec = "DESTRUCTION" },
        { key = "FELDOM", id = 18708, name = "Fel Domination", icon = "Interface\\Icons\\Spell_Nature_RemoveCurse",
          cd = 900, tier = 2, kind = "UTIL", spec = "DEMONOLOGY" },
    },
    HUNTER = {
        { key = "SCATTER", id = 19503, name = "Scatter Shot", icon = "Interface\\Icons\\Ability_GolemStormBolt",
          cd = 30, tier = 1, kind = "CC", spec = "MARKSMANSHIP" },
        { key = "SILSHOT", id = 34490, name = "Silencing Shot", icon = "Interface\\Icons\\Ability_TheBlackArrow",
          cd = 20, tier = 1, kind = "KICK", spec = "MARKSMANSHIP" },
        { key = "INTIMID", id = 19577, name = "Intimidation", icon = "Interface\\Icons\\Ability_Devour",
          cd = 60, tier = 1, kind = "CC", spec = "BEASTMASTERY" },
        { key = "BW", id = 19574, name = "Bestial Wrath", icon = "Interface\\Icons\\Ability_Druid_FerociousBite",
          cd = 120, tier = 1, kind = "OFF", spec = "BEASTMASTERY" },
        { key = "TRAP", id = 1499, name = "Freezing Trap", icon = "Interface\\Icons\\Spell_Frost_ChainsOfIce",
          cd = 30, tier = 1, kind = "CC" },
        { key = "WYVERN", id = 19386, name = "Wyvern Sting", icon = "Interface\\Icons\\INV_Spear_02",
          cd = 180, tier = 1, kind = "CC", spec = "SURVIVAL" },
        { key = "DETER", id = 19263, name = "Deterrence", icon = "Interface\\Icons\\Ability_Whirlwind",
          cd = 300, tier = 1, kind = "DEF", spec = "SURVIVAL" },
        { key = "RAPID", id = 3045, name = "Rapid Fire", icon = "Interface\\Icons\\Ability_Hunter_RunningShot",
          cd = 300, tier = 2, kind = "OFF" },
    },
    SHAMAN = {
        { key = "GROUNDING", id = 8177, name = "Grounding Totem", icon = "Interface\\Icons\\Spell_Nature_GroundingTotem",
          cd = 15, tier = 1, kind = "DEF" },
        { key = "NS", id = 16188, name = "Nature's Swiftness", icon = "Interface\\Icons\\Spell_Nature_RavenForm",
          cd = 180, tier = 1, kind = "UTIL", spec = "RESTORATION" },
        { key = "ELEMASTERY", id = 16166, name = "Elemental Mastery", icon = "Interface\\Icons\\Spell_Nature_WispHeal",
          cd = 180, tier = 1, kind = "OFF", spec = "ELEMENTAL" },
        { key = "HEROISM", id = 32182, name = "Heroism", icon = "Interface\\Icons\\Ability_Shaman_Heroism",
          cd = 600, tier = 1, kind = "OFF" },
        { key = "BLOODLUST", id = 2825, name = "Bloodlust", icon = "Interface\\Icons\\Spell_Nature_BloodLust",
          cd = 600, tier = 1, kind = "OFF" },
        { key = "MANATIDE", id = 16190, name = "Mana Tide Totem", icon = "Interface\\Icons\\Spell_Frost_SummonWaterElemental",
          cd = 300, tier = 2, kind = "UTIL", spec = "RESTORATION" },
        { key = "SHAMRAGE", id = 30823, name = "Shamanistic Rage", icon = "Interface\\Icons\\Spell_Nature_ShamanRage",
          cd = 120, tier = 2, kind = "DEF", spec = "ENHANCEMENT" },
    },
}
-- Entries every class gets: the PvP trinket (several item-effect names) and
-- the meaningful racials — tier 2, so they surface only once spent.
SDATA.ABILITY_SHARED = {
    { key = "TRINKET", name = "PvP Trinket", icon = "Interface\\Icons\\INV_Jewelry_TrinketPVP_01",
      cd = 120, tier = 2, kind = "UTIL",
      names = { "PvP Trinket", "Medallion of the Alliance", "Medallion of the Horde",
                "Insignia of the Alliance", "Insignia of the Horde" } },
    { key = "WOTF", id = 7744, name = "Will of the Forsaken", icon = "Interface\\Icons\\Spell_Shadow_RaiseDead",
      cd = 120, tier = 2, kind = "UTIL" },
    { key = "STONEFORM", id = 20594, name = "Stoneform", icon = "Interface\\Icons\\Spell_Shadow_UnholyStrength",
      cd = 180, tier = 2, kind = "DEF" },
    { key = "BLOODFURY", id = 20572, name = "Blood Fury", icon = "Interface\\Icons\\Racial_Orc_BerserkerStrength",
      cd = 120, tier = 2, kind = "OFF" },
    { key = "WARSTOMP", id = 20549, name = "War Stomp", icon = "Interface\\Icons\\Ability_WarStomp",
      cd = 120, tier = 2, kind = "CC" },
    { key = "TORRENT", id = 28730, name = "Arcane Torrent", icon = "Interface\\Icons\\Spell_Shadow_Teleport",
      cd = 120, tier = 2, kind = "KICK" },
}
SDATA.HYPO_ID, SDATA.FORB_ID = 41425, 25771   -- Hypothermia, Forbearance
local abilityByName = {}    -- localized name -> { [classToken] = entry } ("*" = shared)
local abilityState = {}     -- guid -> { [entry.key] = cdEnd }
local lockNames = {}        -- localized lockout debuff name -> "hypo"/"forb"
local lockState = {}        -- guid -> { hypo = expire, forb = expire }

-- Resolve display names/icons and build the name index (login + respec)
local function ResolveAbilityBook()
    wipe(abilityByName)
    local function register(name, class, entry)
        if not name then return end
        local slot = abilityByName[name]
        if not slot then slot = {}; abilityByName[name] = slot end
        slot[class] = entry
    end
    for class, list in pairs(SDATA.ABILITY_BOOK) do
        for _, entry in ipairs(list) do
            local n, _, ic = nil, nil, nil
            if entry.id and GetSpellInfo then n, _, ic = GetSpellInfo(entry.id) end
            entry.dispName = n or entry.name
            entry.dispIcon = ic or entry.icon
            register(entry.dispName, class, entry)
            if entry.name ~= entry.dispName then register(entry.name, class, entry) end
        end
    end
    for _, entry in ipairs(SDATA.ABILITY_SHARED) do
        local n, _, ic = nil, nil, nil
        if entry.id and GetSpellInfo then n, _, ic = GetSpellInfo(entry.id) end
        entry.dispName = n or entry.name
        entry.dispIcon = ic or entry.icon
        register(entry.dispName, "*", entry)
        if entry.names then
            for _, alias in ipairs(entry.names) do register(alias, "*", entry) end
        end
    end
    wipe(lockNames)
    local hn = GetSpellInfo and GetSpellInfo(SDATA.HYPO_ID)
    lockNames[hn or "Hypothermia"] = "hypo"
    local fn = GetSpellInfo and GetSpellInfo(SDATA.FORB_ID)
    lockNames[fn or "Forbearance"] = "forb"
end

-- A group member cast something: stamp its cooldown, apply its resets
local function NoteAbilityCast(guid, class, spellName, now)
    local slot = abilityByName[spellName]
    if not slot then return end
    local entry = (class and slot[class]) or slot["*"]
    if not entry then return end
    local st = abilityState[guid]
    if not st then st = {}; abilityState[guid] = st end
    st[entry.key] = now + entry.cd
    -- The reset link is literal: Cold Snap/Preparation REFUND the linked CDs
    if entry.resets then
        for _, tk in ipairs(entry.resets) do st[tk] = nil end
    end
end

-- Classes whose members run on mana (TBC): the INT layer's buff targets.
-- Judged by class, not live power type, so a shapeshifted druid stays a
-- target instead of flapping between target and not each form change.
local MANA_CLASSES = {
    MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true,
    SHAMAN = true, PALADIN = true, HUNTER = true,
}
-- guid -> pooled array of dispellable debuffs; list.n is the live count so the
-- entry tables are reused instead of reallocated on every aura event
local dispelState = {}
local prevMyShield = {}   -- guid -> had my shield last tick (Expose Alert edge)
local rowFlash = {}       -- rowIndex -> GetTime() the flash ends

local rowPool = {}
local personalPool = {}   -- always-insecure rows for the elemental / My Shields
local sinceDraw = 0
local sinceSample = 0
local testUntil = 0       -- test board lives until this GetTime()
local targeters = {}      -- [guid] = enemy NPCs currently targeting that unit
local nextTargeterScan = 0
local securePool          -- true if rows were created as secure unit buttons
local secureTokens = {}   -- rowIndex -> raw unit token (secure mode)
local secureDirty = false -- secure layout needs a rebuild once out of combat
local uptime              -- session table from Commander.RestoreSession

local root = CreateFrame("Frame", "CommanderPartyFramesFrame", UIParent)
root:SetPoint("LEFT", UIParent, "LEFT", 14, 40)
root:SetSize(214, ROW_H)
root:SetFrameStrata("MEDIUM")
root:Hide()

-- Hidden tooltip used to read "Absorbs N damage" off a fresh shield. Best-effort
-- and fully guarded: a client that will not cooperate just falls back to the
-- computed capacity, so the bar always has a number to draw.
local scanTip = CreateFrame("GameTooltip", "CommanderPartyFramesScanTip", nil, "GameTooltipTemplate")

local function FrameWidth()
    return DB("FrameWidth", 214)
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

-- ---------------------------------------------------------------------------
-- Capacity: how much a fresh shield can absorb. Tooltip read (exact, includes
-- talents + spell power) is preferred and cached per rank; a cached observation
-- or the rank table + our spell power stand in when no tooltip is available.
-- ---------------------------------------------------------------------------
local function ReadAbsorbFromAura(unit, index)
    if not (scanTip and scanTip.SetUnitBuff) then return nil end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    local ok = pcall(scanTip.SetUnitBuff, scanTip, unit, index, "HELPFUL")
    if not ok then return nil end
    for i = 1, scanTip:NumLines() do
        local fs = _G["CommanderPartyFramesScanTipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text then
            local num = text:match("[Aa]bsorbs%s*([%d,]+)")
            if num then
                local value = tonumber((num:gsub(",", "")))
                if value and value > 0 then return value end
            end
        end
    end
    return nil
end

local function ComputeCapacity(spellId)
    local base = SDATA.PWS_RANKS[spellId] or myShieldValue
    local sp = (GetSpellBonusHealing and GetSpellBonusHealing()) or 0
    return base + sp * SDATA.SP_COEFF
end

local function CapacityFor(spellId, mine, unit, index)
    if not mine then return nil end
    if unit and index then
        local scanned = ReadAbsorbFromAura(unit, index)
        if scanned then
            capObserved[spellId] = scanned
            return scanned
        end
    end
    return capObserved[spellId] or ComputeCapacity(spellId)
end

local function UpdateMyShieldValue()
    local best = 0
    for id, base in pairs(SDATA.PWS_RANKS) do
        if base > best and (not IsSpellKnown or IsSpellKnown(id)) then best = base end
    end
    if best == 0 then
        for _, base in pairs(SDATA.PWS_RANKS) do best = math.max(best, base) end
    end
    local sp = (GetSpellBonusHealing and GetSpellBonusHealing()) or 0
    myShieldValue = best + sp * SDATA.SP_COEFF
end

-- ---------------------------------------------------------------------------
-- Spell knowledge. IsSpellKnown(rankId) is unreliable on this client for
-- ranked spells, so the truth comes from walking the spellbook by NAME
-- (rank-agnostic — any trained rank lists the base name). IsSpellKnown is
-- kept as a bonus signal where it happens to work.
-- ---------------------------------------------------------------------------
local knownSpells = {}   -- localized spell name -> true (spellbook contents)
local function RefreshKnownSpells()
    wipe(knownSpells)
    if not (GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName) then return end
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, numSlots = GetSpellTabInfo(tab)
        for i = (offset or 0) + 1, (offset or 0) + (numSlots or 0) do
            local name = GetSpellBookItemName(i, "spell")
            if name then knownSpells[name] = true end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Mage banner utilities: conjure/consume secure buttons, the armor-switch
-- popout, and Water Elemental info. Secure attributes only change out of
-- combat (mageBtnsDirty defers to PLAYER_REGEN_ENABLED); the popout and the
-- button CONTAINER are insecure frames, so showing/hiding them stays legal
-- mid-combat even though the buttons themselves are protected.
-- ---------------------------------------------------------------------------
local function ResolveEleInfo()
    eleKnown = false
    if layer ~= "INT" or not GetSpellInfo then return end
    local _, _, ic = GetSpellInfo(SDATA.WATER_ELE_ID)
    eleIcon = ic or "Interface\\Icons\\Spell_Frost_SummonWaterElemental_2"
    local fn, _, fic = GetSpellInfo(SDATA.FREEZE_ID)
    freezeName = fn
    freezeIcon = fic or "Interface\\Icons\\Spell_Frost_FrostShock"
    local eleName = GetSpellInfo(SDATA.WATER_ELE_ID)
    eleKnown = (eleName and knownSpells[eleName])
        or (IsSpellKnown and IsSpellKnown(SDATA.WATER_ELE_ID)) or false
end

-- Freeze's cooldown off the pet action bar (only meaningful while the
-- elemental is out). Returns remaining, cdDuration, cdStart — remaining 0
-- when ready, nil when no Freeze slot exists.
local function FreezeCooldown()
    if not (freezeName and GetPetActionInfo and GetPetActionCooldown) then return nil end
    for i = 1, (NUM_PET_ACTION_SLOTS or 10) do
        if GetPetActionInfo(i) == freezeName then
            local start, duration = GetPetActionCooldown(i)
            if start and duration and start > 0 and duration > 1.5 then
                return math.max(0, start + duration - GetTime()), duration, start
            end
            return 0
        end
    end
    return nil
end

-- Best conjured item of a kind currently in the bags (list is best-first)
local function FindConjured(list)
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID) then return nil end
    local bestRank, bestId
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id then
                for rank, want in ipairs(list) do
                    if id == want and (not bestRank or rank < bestRank) then
                        bestRank, bestId = rank, id
                    end
                end
            end
        end
    end
    return bestId
end

local function BindMageUtilityButtons()
    if layer ~= "INT" or not conjureBtn then return end
    if InCombat() then mageBtnsDirty = true; return end
    mageBtnsDirty = false

    -- Conjure: left = water, right = food (cast by name = highest rank)
    local cwName, _, cwIcon = GetSpellInfo(SDATA.CONJURE_WATER_ID)
    local cfName = GetSpellInfo(SDATA.CONJURE_FOOD_ID)
    conjureBtn:SetAttribute("type1", "spell")
    conjureBtn:SetAttribute("spell1", cwName)
    conjureBtn:SetAttribute("type2", "spell")
    conjureBtn:SetAttribute("spell2", cfName)
    conjureBtn.icon:SetTexture(cwIcon or "Interface\\Icons\\INV_Drink_18")

    -- Consume: left = eat AND drink (both /use lines fire together),
    -- right = drink only
    local water = FindConjured(SDATA.CONJURED_WATER)
    local food = FindConjured(SDATA.CONJURED_FOOD)
    local both = ""
    if food then both = "/use item:" .. food end
    if water then both = both .. (both ~= "" and "\n" or "") .. "/use item:" .. water end
    consumeBtn:SetAttribute("type1", "macro")
    consumeBtn:SetAttribute("macrotext1", both)
    consumeBtn:SetAttribute("type2", "macro")
    consumeBtn:SetAttribute("macrotext2", water and ("/use item:" .. water) or "")
    local function itemIcon(id)
        if not id then return nil end
        if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
        if GetItemIcon then return GetItemIcon(id) end
        return nil
    end
    local ci = itemIcon(food) or itemIcon(water) or "Interface\\Icons\\INV_Misc_Food_11"
    consumeBtn.icon:SetTexture(ci)
    consumeBtn.icon:SetDesaturated(not (food or water))

    -- Armor popout: one secure cast button per known armor line
    local shown = 0
    local known = {}
    for _, line in ipairs(SDATA.ARMOR_LINES) do
        for _, id in ipairs(line.ids) do
            local n = GetSpellInfo(id)
            if (n and knownSpells[n]) or (IsSpellKnown and IsSpellKnown(id)) then
                known[line.key] = id
                break
            end
        end
    end
    for _, line in ipairs(SDATA.ARMOR_LINES) do
        local bestId = known[line.key]
        if bestId and not (line.supersededBy and known[line.supersededBy]) then
            shown = shown + 1
            local b = armorButtons[shown]
            if not b then
                b = CreateFrame("Button", "CommanderPartyFramesArmorBtn" .. shown, armorPop, "SecureActionButtonTemplate")
                b:SetSize(18, 18)
                b:SetPoint("LEFT", armorPop, "LEFT", 3 + (shown - 1) * 21, 0)
                b:RegisterForClicks("AnyDown", "AnyUp")
                b.icon = b:CreateTexture(nil, "ARTWORK")
                b.icon:SetAllPoints(b)
                b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                local hl = b:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(b)
                hl:SetTexture("Interface\\Buttons\\WHITE8X8")
                hl:SetVertexColor(1, 1, 1, 0.25)
                b:SetScript("PostClick", function() armorPop:Hide() end)
                armorButtons[shown] = b
            end
            local name, _, icon = GetSpellInfo(bestId)
            b:SetAttribute("type", "spell")
            b:SetAttribute("spell", name)
            b.icon:SetTexture(icon)
            b:Show()
        end
    end
    for i = shown + 1, #armorButtons do armorButtons[i]:Hide() end
    armorPop:SetSize(math.max(shown, 1) * 21 + 3, 24)
end

-- Header gear (any class): opens the settings page through the framework's
-- own bare-slash handler; hideable via the Settings Button option.
local function EnsureSettingsButton()
    if settingsBtn or not profile then return end
    settingsBtn = CreateFrame("Button", nil, root)
    settingsBtn:SetSize(12, 12)
    settingsBtn:SetPoint("TOPRIGHT", root, "TOPRIGHT", -(PAD - 3), -1.5)
    settingsBtn.icon = settingsBtn:CreateTexture(nil, "ARTWORK")
    settingsBtn.icon:SetAllPoints(settingsBtn)
    settingsBtn.icon:SetTexture("Interface\\WorldMap\\Gear_64Grey")
    settingsBtn.icon:SetVertexColor(0.8, 0.8, 0.8, 0.9)
    local hl = settingsBtn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(settingsBtn)
    hl:SetTexture("Interface\\Buttons\\WHITE8X8")
    hl:SetVertexColor(1, 1, 1, 0.25)
    settingsBtn:SetScript("OnClick", function()
        local f = SlashCmdList and SlashCmdList["COMMANDERUI_PARTYFRAMES"]
        if f then f("") end
    end)
    settingsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText("Party Frames settings")
        GameTooltip:Show()
    end)
    settingsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function EnsureMageUtilButtons()
    if mageUtil or layer ~= "INT" then return end
    -- Insecure container: toggling IT (not the protected buttons) keeps the
    -- banner's show/hide legal in combat
    mageUtil = CreateFrame("Frame", nil, root)
    mageUtil:SetAllPoints(root)
    local function mkBtn(name, tipTitle, tip1, tip2)
        local b = CreateFrame("Button", name, mageUtil, "SecureActionButtonTemplate")
        b:SetSize(13, 13)
        b:RegisterForClicks("AnyDown", "AnyUp")
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints(b)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(b)
        hl:SetTexture("Interface\\Buttons\\WHITE8X8")
        hl:SetVertexColor(1, 1, 1, 0.25)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:SetText(tipTitle)
            GameTooltip:AddLine(tip1, 0.8, 0.8, 0.8)
            GameTooltip:AddLine(tip2, 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    consumeBtn = mkBtn("CommanderPartyFramesConsume", "Consume",
        "Left-click: eat + drink", "Right-click: drink only")
    if settingsBtn then
        consumeBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -3, 0)
    else
        consumeBtn:SetPoint("TOPRIGHT", root, "TOPRIGHT", -(PAD - 2), -1)
    end
    conjureBtn = mkBtn("CommanderPartyFramesConjure", "Conjure",
        "Left-click: Conjure Water", "Right-click: Conjure Food")
    conjureBtn:SetPoint("RIGHT", consumeBtn, "LEFT", -3, 0)

    armorPop = CreateFrame("Frame", nil, root)
    armorPop:SetFrameStrata("DIALOG")
    armorPop:SetSize(24, 24)
    -- Anchored ONCE to root (a Frame): the popout carries protected children,
    -- and protected anchor families may not attach to regions like the banner
    -- textures — re-anchoring at click time is what threw in the field.
    armorPop:SetPoint("TOPLEFT", root, "TOPLEFT", STRIPE_W + 1, -(HEADER_H + 3))
    local bg = armorPop:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(armorPop)
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0, 0, 0, 0.75)
    armorPop:Hide()
    BindMageUtilityButtons()
end

-- ---------------------------------------------------------------------------
-- Self-shield extra (INT layer opt-in): tracked-spell resolution, capacity,
-- and scanning. Shields live in the same shieldState table under "cself<KEY>"
-- pseudo-GUIDs, and the spell's cooldown is written into wsState under the
-- same key — so the shield resolver treats a cooldown lockout exactly like a
-- Weakened Soul lockout.
-- ---------------------------------------------------------------------------
local function SelfBonus(def)
    if def.coeff and def.coeff > 0 and def.school and GetSpellBonusDamage then
        return (GetSpellBonusDamage(def.school) or 0) * def.coeff
    end
    return 0
end

local function SelfCapacity(def, spellId)
    local base = spellId and def.ranks[spellId]
    if base then return base + SelfBonus(def) end
    return def.nominal or 0
end

-- Which tracked spells this character actually knows (any rank), plus each
-- one's localized name and nominal full-capacity estimate. Re-run on
-- SPELLS_CHANGED so a fresh talent or trained rank shows up.
local function ResolveTrackedSpells()
    wipe(trackedSpells)
    wipe(trackedByName)
    if not (profile and profile.selfSpells) then return end
    -- If the spellbook walk produced nothing (API hiccup), fail PERMISSIVE:
    -- a row for an untrained ward beats silently losing My Shields entirely
    local bookOk = next(knownSpells) ~= nil
    for _, def in ipairs(profile.selfSpells) do
        local name = GetSpellInfo and GetSpellInfo(def.baseId)
        if name then
            def.name = name
            trackedByName[name] = def
            absorbNames[name] = true
            -- Known when the spellbook lists the name; per-rank IsSpellKnown
            -- refines the base value where it works
            local known, bestBase = (((not bookOk) or knownSpells[name]) and true or false), 0
            for id, base in pairs(def.ranks) do
                if IsSpellKnown and IsSpellKnown(id) then
                    known = true
                    if base > bestBase then bestBase = base end
                end
            end
            if known and bestBase == 0 then
                for _, base in pairs(def.ranks) do
                    if base > bestBase then bestBase = base end
                end
            end
            def.known = known
            def.nominal = bestBase + SelfBonus(def)
            if def.key == "BARRIER" then barrierDef = known and def or nil end
            if known then trackedSpells[#trackedSpells + 1] = def end
        end
    end
end

-- Cooldown -> lockout drain. Only real cooldowns count (dur > 1.5 skips the
-- GCD); the stored value is the same "locked until" timestamp Weakened Soul
-- uses, so the shared resolver needs no special case.
local function RefreshSelfCooldowns()
    if not GetSpellCooldown then return end
    for _, def in ipairs(trackedSpells) do
        if def.cooldown and def.cooldown > 0 and def.name then
            local key = SELF_KEY .. def.key
            local start, dur = GetSpellCooldown(def.name)
            if start and dur and start > 0 and dur > 1.5 then
                wsState[key] = start + dur
            else
                wsState[key] = nil
            end
        end
    end
end

local function ScanSelfShields()
    if not (C_UnitAuras and C_UnitAuras.GetBuffDataByIndex) then return end
    local found = {}   -- def -> { expire, spellId, index }; player auras are always reliable
    for i = 1, 40 do
        local aura = C_UnitAuras.GetBuffDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        local def = aura.name and trackedByName[aura.name]
        if def and not found[def] then
            found[def] = { expire = aura.expirationTime, spellId = aura.spellId, index = i }
        end
    end
    for _, def in ipairs(trackedSpells) do
        local key = SELF_KEY .. def.key
        local hit = found[def]
        if hit then
            local st = shieldState[key]
            if not st or st.expire ~= hit.expire or st.spellId ~= hit.spellId then
                local cap = ReadAbsorbFromAura("player", hit.index)
                if cap and hit.spellId then
                    capObserved[hit.spellId] = cap
                else
                    cap = (hit.spellId and capObserved[hit.spellId]) or SelfCapacity(def, hit.spellId)
                end
                shieldState[key] = {
                    spellId = hit.spellId, expire = hit.expire, mine = true,
                    absorbed = 0, capacity = cap, duration = def.duration,
                }
                -- A fresh self-shield counts toward the session cast tally
                if uptime then uptime.shieldsCast = (uptime.shieldsCast or 0) + 1 end
            end
        else
            shieldState[key] = nil
        end
    end
    RefreshSelfCooldowns()
end

-- ---------------------------------------------------------------------------
-- Aura scanning (unchanged core). reliable = the unit's aura data can be trusted
-- right now; only then may an absence prune a tracked shield or debuff.
-- ---------------------------------------------------------------------------
local function IsReliable(unit)
    if unit == "player" then return true end
    if not (UnitIsVisible and UnitIsVisible(unit)) then return false end
    if UnitInRange then
        local inRange, checked = UnitInRange(unit)
        if checked and not inRange then return false end
    end
    return true
end

-- Reused scratch for ordering a unit's debuff strip (sorting a sub-range of the
-- pooled list in place is not possible, so refs are copied out and back)
local dispelSort, dispelSortN = {}, 0
local function DispelCompare(a, b)
    if a.prio ~= b.prio then return a.prio < b.prio end
    return (a.expire or math.huge) < (b.expire or math.huge)
end

local function ScanUnit(unit, reliable)
    if not (C_UnitAuras and C_UnitAuras.GetBuffDataByIndex and UnitGUID) then return end
    local guid = UnitGUID(unit)
    if not guid then return end

    local pwsExpire, pwsSpellId, pwsMine, pwsIndex
    local renewExpire
    local renewOn = DB("RenewTrack", false)
    local intOn = layer == "INT"
    local isPlayer = guid == playerGUID
    local intExpire, intDuration
    local armorFound
    wipe(scanAbsorbs)
    for i = 1, 40 do
        local aura = C_UnitAuras.GetBuffDataByIndex(unit, i, "HELPFUL")
        if not aura then break end
        if aura.name == PWS_NAME and not pwsExpire then
            pwsExpire = aura.expirationTime
            pwsSpellId = aura.spellId
            pwsMine = aura.sourceUnit and UnitIsUnit(aura.sourceUnit, "player") or false
            pwsIndex = i
        elseif renewOn and aura.name == RENEW_NAME and not renewExpire
            and aura.sourceUnit and UnitIsUnit(aura.sourceUnit, "player") then
            renewExpire = aura.expirationTime   -- only OUR Renew is tracked
        elseif intOn and not intExpire
            and (aura.name == AI_NAME or aura.name == BRILLIANCE_NAME) then
            intExpire = aura.expirationTime     -- any caster's Int counts as covered
            intDuration = aura.duration
        elseif intOn and isPlayer and not armorFound and armorNames[aura.name] then
            armorFound = { icon = armorNames[aura.name], expire = aura.expirationTime }
        end
        -- Spec inference from visible marker auras (Shadowform, forms, Tree…)
        if specMarkerNames[aura.name] then
            specState[guid] = specMarkerNames[aura.name]
        end
        -- Aggregate shielding: catch every named absorb aura, whoever cast it
        -- (PW:S lands in the branch above, so this is a separate check).
        -- No early break: absorbs (and armor) can sit anywhere in the list.
        if absorbNames[aura.name] and not scanAbsorbs[aura.name] then
            scanAbsorbs[aura.name] = { expire = aura.expirationTime, duration = aura.duration,
                icon = aura.icon, spellId = aura.spellId, index = i }
        end
    end

    -- Our Renew (tracked only when the feature is on); reliable scans prune it
    if renewOn then
        if renewExpire then
            renewState[guid] = renewExpire
        elseif reliable then
            renewState[guid] = nil
        end
    end

    -- Our armor (upkeep banner); the player's own scan is always reliable
    if intOn and isPlayer then
        selfArmor = armorFound
    end

    -- Aggregate shielding: refresh this unit's absorb records. A new or
    -- refreshed aura re-reads capacity (tooltip first, rank table fallback);
    -- an unchanged one keeps its running absorbed tally.
    do
        local rec = allyAbsorbs[guid]
        for name, hit in pairs(scanAbsorbs) do
            if not rec then rec = {}; allyAbsorbs[guid] = rec end
            local e = rec[name]
            if not e or e.expire ~= hit.expire then
                -- Capacity, best source first: exact tooltip read; the same
                -- aura's measurement in the own-shield tracker (so the row
                -- number and the segment can never disagree); the last full
                -- value ever observed for this rank; the trainer rank table.
                local cap = reliable and ReadAbsorbFromAura(unit, hit.index) or nil
                if not cap and name == PWS_NAME then
                    local own = shieldState[guid]
                    if own and own.capacity and own.expire == hit.expire then
                        cap = own.capacity
                    end
                end
                if not cap and hit.spellId then
                    cap = capObserved[hit.spellId] or SDATA.ABSORB_RANKS[hit.spellId]
                end
                rec[name] = { expire = hit.expire, duration = hit.duration,
                    icon = hit.icon, capacity = cap, absorbed = 0 }
            elseif not e.capacity and reliable then
                -- Late calibration: the aura outlived an out-of-range cast
                e.capacity = ReadAbsorbFromAura(unit, hit.index)
                    or (hit.spellId and (capObserved[hit.spellId] or SDATA.ABSORB_RANKS[hit.spellId]))
                    or nil
            end
        end
        if rec and reliable then
            for name in pairs(rec) do
                if not scanAbsorbs[name] then rec[name] = nil end
            end
        end
    end

    -- Int/Brilliance upkeep (INT layer); same reliable pruning contract
    if intOn then
        if intExpire then
            local e = intState[guid]
            if not e then e = {}; intState[guid] = e end
            e.expire, e.duration = intExpire, intDuration
        elseif reliable then
            intState[guid] = nil
        end
    end

    local wsExpire
    local dispelOn = DB("ShowDispels", false)
    local showAllDebuffs = DB("DispelShowAll", false)
    local showImportant = DB("DispelShowImportant", true)
    local curseExpire, curseDuration
    local ccExpire, ccDuration, ccIcon, ccName
    local hypoExpire, forbExpire
    local list, dispelCount = nil, 0
    if dispelOn then
        list = dispelState[guid]
        if not list then list = { n = 0 }; dispelState[guid] = list end
    end
    for i = 1, 40 do
        local aura = C_UnitAuras.GetDebuffDataByIndex(unit, i, "HARMFUL")
        if not aura then break end
        if aura.name == WS_NAME and not wsExpire then
            wsExpire = aura.expirationTime
            -- nothing else to collect (the INT layer still hunts for a curse)
            if not dispelOn and not intOn then break end
        end
        -- CURSED state feed: track the first removable debuff independently of
        -- the strip, which caps at MAX_DISPEL_ICONS — a curse buried under a
        -- full strip (or with the strip off) must still turn the row purple
        if intOn and not curseExpire then
            local dt = aura.dispelName
            if dt and dt ~= "" and myDispelTypes[dt] then
                curseExpire = aura.expirationTime or 0
                curseDuration = aura.duration
            end
        end
        -- CC status feed (same cap-independence): a sheeped/feared/stunned
        -- teammate must escalate even with the icon strip off
        if intOn and not ccName and ccNames[aura.name] then
            ccExpire = aura.expirationTime or 0
            ccDuration = aura.duration
            ccIcon = aura.icon
            ccName = aura.name
        end
        -- Ability-bar lockout debuffs (Hypothermia / Forbearance) — chassis
        local lockKind = lockNames[aura.name]
        if lockKind == "hypo" then
            hypoExpire = aura.expirationTime or 0
        elseif lockKind == "forb" then
            forbExpire = aura.expirationTime or 0
        end
        if dispelOn and dispelCount < MAX_DISPEL_ICONS then
            local dt = aura.dispelName
            if dt == "" then dt = nil end
            local canDispel = (dt and myDispelTypes[dt]) and true or false
            local important = showImportant and importantNames[aura.name] or nil
            if canDispel or important or showAllDebuffs then
                local slot = dispelCount + 1
                local e = list[slot]
                if not e then e = {}; list[slot] = e end
                e.icon = aura.icon
                e.name = aura.name
                e.dispelName = dt
                e.expire = aura.expirationTime
                e.duration = aura.duration
                e.cc = ccNames[aura.name] or false
                e.canDispel = canDispel
                e.important = important
                -- Healing reduction first, then CC, then what we can actually
                -- dispel, then the rest — so a short strip shows what matters
                e.prio = (important == "HEAL" and 1) or (e.cc and 2)
                    or (canDispel and 3) or (important and 4) or 5
                dispelCount = slot
            end
        end
    end

    if dispelOn and dispelCount > 1 then
        for i = 1, dispelCount do dispelSort[i] = list[i] end
        for i = dispelCount + 1, dispelSortN do dispelSort[i] = nil end
        dispelSortN = dispelCount
        table.sort(dispelSort, DispelCompare)
        for i = 1, dispelCount do list[i] = dispelSort[i] end
    end
    -- Commit the count only when we can trust the scan: an out-of-range unit
    -- returns no auras, which must not wipe a live list (same reliable contract
    -- as the shield/Weakened Soul above).
    if dispelOn and (dispelCount > 0 or reliable) then
        list.n = dispelCount
    end

    -- Commit the curse/CC records with the same reliable contract as
    -- everything else: absence only prunes when the scan could see the unit
    if intOn then
        if curseExpire then
            local c = curseState[guid]
            if not c then c = {}; curseState[guid] = c end
            c.expire, c.duration = curseExpire, curseDuration
        elseif reliable then
            curseState[guid] = nil
        end
        if ccName then
            local c = ccState[guid]
            if not c then c = {}; ccState[guid] = c end
            c.expire, c.duration, c.icon, c.name = ccExpire, ccDuration, ccIcon, ccName
        elseif reliable then
            ccState[guid] = nil
        end
    end

    if wsExpire then
        wsState[guid] = wsExpire
    elseif reliable then
        wsState[guid] = nil
    end

    if pwsExpire then
        local st = shieldState[guid]
        if not st or st.expire ~= pwsExpire or st.spellId ~= pwsSpellId then
            shieldState[guid] = {
                spellId = pwsSpellId,
                expire = pwsExpire,
                mine = pwsMine,
                absorbed = 0,
                capacity = CapacityFor(pwsSpellId, pwsMine, reliable and unit or nil, reliable and pwsIndex or nil),
            }
            -- A brand-new shield of ours counts toward the session cast tally
            if pwsMine and uptime then uptime.shieldsCast = (uptime.shieldsCast or 0) + 1 end
        else
            st.mine = pwsMine
            if not st.capacity and pwsMine and reliable then
                st.capacity = CapacityFor(pwsSpellId, true, unit, pwsIndex)
            end
        end
    elseif reliable then
        shieldState[guid] = nil
    end
end

local GROUP_UNITS = {}
for i = 1, 4 do GROUP_UNITS["party" .. i] = true end
for i = 1, 40 do GROUP_UNITS["raid" .. i] = true end
local LOOK_UNITS = { target = true, focus = true, mouseover = true }

local function ScanGroup()
    wipe(groupGuids)
    if playerGUID then groupGuids[playerGUID] = playerClass or true end
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists(u) then
                local g = UnitGUID and UnitGUID(u)
                if g then groupGuids[g] = select(2, UnitClass(u)) or true end
                ScanUnit(u, IsReliable(u))
            end
        end
    elseif IsInGroup and IsInGroup() then
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) then
                local g = UnitGUID and UnitGUID(u)
                if g then groupGuids[g] = select(2, UnitClass(u)) or true end
                ScanUnit(u, IsReliable(u))
            end
        end
    end
    ScanUnit("player", true)
end

-- SPELL_ABSORBED: subtract real absorbs from our own shields (unchanged).
local function OnCombatLog()
    local _, subevent, _, sourceGUID, _, _, _, destGUID, _, _, _,
        a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11 = CombatLogGetCurrentEventInfo()
    if subevent == "SPELL_CAST_SUCCESS" or subevent == "SPELL_AURA_APPLIED" then
        -- Group member activity (a2 = spellName, rank- and locale-safe):
        -- spec inference plus ability-bar cooldown stamping. AURA_APPLIED is
        -- the fallback for the few abilities whose cast event is unreliable;
        -- double-stamping the same cast is harmless (same cd, same second).
        local class = sourceGUID and groupGuids[sourceGUID]
        if class and a2 then
            local spec = specMarkerNames[a2]
            if spec then specState[sourceGUID] = spec end
            NoteAbilityCast(sourceGUID, class, a2, GetTime())
        end
        if subevent == "SPELL_CAST_SUCCESS" then return end
        -- AURA_APPLIED falls through: SPELL_ABSORBED filtering below ignores it
    end
    if subevent == "SPELL_SUMMON" then
        -- Water Elemental lifespan clock (elemental row)
        if layer == "INT" and sourceGUID == playerGUID and a1 == SDATA.WATER_ELE_ID then
            eleExpire = GetTime() + SDATA.ELE_DURATION
        end
        return
    end
    if subevent ~= "SPELL_ABSORBED" then return end

    local casterGUID, absorbName, amount
    if type(a1) == "number" then
        casterGUID, absorbName, amount = a4, a9, a11
    else
        casterGUID, absorbName, amount = a1, a6, a8
    end

    if type(amount) ~= "number" or amount <= 0 then return end

    -- Aggregate records first (both layers): ANY caster's shield on a
    -- tracked unit drains its embedded segment.
    local rec = destGUID and allyAbsorbs[destGUID]
    if rec and absorbName then
        local e = rec[absorbName]
        if e and e.capacity then e.absorbed = e.absorbed + amount end
    end

    if layer == "INT" then
        -- Our own self-shield rows keep their private tally alongside
        if destGUID == playerGUID and casterGUID == playerGUID then
            local def = absorbName and trackedByName[absorbName]
            local st = def and shieldState[SELF_KEY .. def.key]
            if st and st.mine and st.capacity then st.absorbed = st.absorbed + amount end
        end
        return
    end

    if casterGUID ~= playerGUID then return end
    if absorbName ~= PWS_NAME then return end
    local st = shieldState[destGUID]
    if st and st.mine and st.capacity then
        st.absorbed = st.absorbed + amount
    end
end

-- ---------------------------------------------------------------------------
-- Row resolution. The resolvers read only GUID-keyed state tables so the live
-- path and the test board share one core; ResolveState dispatches to the
-- active layer's resolver (self-spell rows always use the shield resolver —
-- their cooldown lockout lives in wsState like Weakened Soul does).
-- ---------------------------------------------------------------------------
local function SegOrder(a, b) return a.order < b.order end

-- Collect this row's absorbs into segments (fixed color order), pruning
-- expired records, and remember the biggest shield for the status slot.
local function ResolveAbsorbSegs(r, now)
    local rec = allyAbsorbs[r.guid]
    if not rec then return end
    local total, best, bestRem = 0, nil, -1
    local segs
    for name, e in pairs(rec) do
        if e.expire and e.expire > 0 and e.expire <= now then
            rec[name] = nil
        else
            r.inShield = true
            local rem = e.capacity and math.max(0, e.capacity - (e.absorbed or 0)) or 0
            total = total + rem
            if rem > bestRem then bestRem = rem; best = e end
            if rem > 0 then
                if not segs then segs = {}; r.segs = segs end
                segs[#segs + 1] = { amount = rem, name = name, order = SDATA.SHIELD_ORDER[name] or 9 }
            end
        end
    end
    if best then
        r.inShieldExpire = best.expire
        r.inShieldDuration = (best.duration and best.duration > 0) and best.duration or SDATA.SHIELD_DURATION
        r.inShieldIcon = best.icon
        if total > 0 then r.shieldTotal = total end
    end
    if segs and #segs > 1 then table.sort(segs, SegOrder) end
    if not next(rec) then allyAbsorbs[r.guid] = nil end
end

-- The embedded-shield health bar (Devin's spec): the bar's scale is
-- max(maxHp, hp + shields) — shields extend the fill past current health,
-- stretching the scale only once hp + shields would overflow the bar.
local function ApplyHealthEmbed(r)
    r.healthMain = true
    local H = r.health or 1
    if r.shieldTotal and r.hpMax and r.hpMax > 0 then
        local scale = math.max(1, H + r.shieldTotal / r.hpMax)
        r.ratio = H / scale
        r.segScale = r.hpMax * scale   -- divisor turning absorb points into bar fraction
    else
        r.ratio = H
    end
end

local function ResolveShieldState(r, now)
    local guid = r.guid
    local lowPct = DB("LowAbsorbPct", 25) / 100
    local lowTime = DB("LowTimeSecs", 5)

    if r.dead then
        r.state = "DEAD"
        r.mainText = r.deadText or "DEAD"
        return r
    end

    -- Ally rows carry the embedded-shield health bar; self-spell rows keep
    -- their per-spell absorb-vs-capacity bar
    if not r.selfSpell then
        ResolveAbsorbSegs(r, now)
        ApplyHealthEmbed(r)
    end

    local ws = wsState[guid]
    if ws and ws <= now then wsState[guid], ws = nil, nil end
    r.wsLeft = ws and (ws - now) or 0

    local renew = renewState[guid]
    if renew and renew <= now then renewState[guid], renew = nil, nil end
    r.renewLeft = renew and (renew - now) or 0
    r.renewExpire = renew

    local st = shieldState[guid]
    if st and st.expire and st.expire <= now then
        shieldState[guid] = nil
        st = nil
    end

    if not st then
        if r.wsLeft > 0 then
            r.state, r.mainText = "EXPOSED", "EXPOSED"
            r.rightText = string.format("%ds", math.ceil(r.wsLeft))
        else
            r.state, r.mainText = "READY", "READY"
        end
        return r
    end

    local tLeft = st.expire and (st.expire - now) or (st.duration or SDATA.SHIELD_DURATION)
    r.tLeft = tLeft
    r.rightText = string.format("%ds", math.max(0, math.ceil(tLeft)))
    r.shieldUp = true
    r.mine = st.mine and true or false

    if not st.mine then
        r.state, r.mainText = "OTHER", "SHIELDED*"
        if r.selfSpell then r.ratio = 1 end
        return r
    end

    local capacity = st.capacity or 0
    local remaining = capacity > 0 and math.max(0, capacity - st.absorbed) or 0
    -- Absorb-vs-capacity now drives only the LOW threshold (and the
    -- self-spell bar); ally bars show health + embedded segments instead
    local strengthRatio = capacity > 0 and (remaining / capacity) or 1
    if r.selfSpell then r.ratio = strengthRatio end
    r.remaining = remaining
    r.mainText = capacity > 0 and tostring(math.floor(remaining + 0.5)) or "UP"

    local low = (capacity > 0 and strengthRatio <= lowPct) or (tLeft <= lowTime)
    if low then
        if r.wsLeft > 0 then
            r.state = "FADING"
            r.rightText = string.format("%ds", math.ceil(r.wsLeft))
        else
            r.state = "REFRESH"
        end
    else
        r.state = "SHIELDED"
    end
    return r
end

-- Long durations (buff upkeep) read better in minutes
local function FormatLong(secs)
    if not secs or secs <= 0 then return "" end
    if secs >= 90 then return string.format("%dm", math.floor(secs / 60 + 0.5)) end
    return string.format("%ds", math.ceil(secs))
end

-- Absorb totals: compact thousands
local function FormatAmount(v)
    if v >= 10000 then return string.format("%.0fk", v / 1000) end
    if v >= 1000 then return string.format("%.1fk", v / 1000) end
    return tostring(math.floor(v + 0.5))
end

-- INT layer (Mage ally rows): these are party frames first, so the main bar
-- is plain HEALTH (lowest sorts first among the quiet rows). Buff upkeep is
-- deliberately icon-sized — Arcane Intellect state rides the left status
-- icon, an incoming priest shield rides the second — and only a removable
-- Curse escalates the whole row (purple, drain = curse remaining).
local function ResolveIntState(r, now)
    if r.dead then
        r.state = "DEAD"
        r.mainText = r.deadText or "DEAD"
        return r
    end

    -- Int upkeep -> left status icon + header tally (never the bar)
    local e = intState[r.guid]
    local left
    if e and e.expire and e.expire > 0 then
        left = e.expire - now
        if left <= 0 then intState[r.guid], e, left = nil, nil, nil end
    end
    r.intUp = e and true or false
    r.intDue = (left and left <= DB("IntRefreshAt", 300)) or false

    -- Everything shielding this ally — a priest's PW:S, their own Ice
    -- Barrier / Mana Shield, a warlock's Sacrifice — as embedded segments.
    ResolveAbsorbSegs(r, now)
    -- Shield Broke Flash edges on absorbs: the moment an ally's last shield
    -- breaks is exactly when they get trained
    if r.inShield then r.shieldUp, r.mine = true, true end

    -- Main bar: health with the shields embedded. Quiet rows share a rank,
    -- so the sort's time key bubbles the lowest-health ally to the top. The
    -- left number is the ally's total shielding; the right is their health.
    r.state = "OTHER"
    ApplyHealthEmbed(r)
    r.tLeft = (r.health or 1) * 1000
    r.mainText = r.shieldTotal and FormatAmount(r.shieldTotal) or ""
    if r.health and r.health < 1 then
        r.rightText = string.format("%d%%", math.floor(r.health * 100 + 0.5))
    end

    -- Removable curse: the row's loudest problem, whatever the buff says.
    -- curseState is fed cap-independently by ScanUnit; expire == 0 means "no
    -- readable clock" and stays live until a reliable rescan clears it.
    local c = curseState[r.guid]
    if c and c.expire and c.expire > 0 and c.expire <= now then
        curseState[r.guid], c = nil, nil
    end
    if c then
        r.state, r.mainText = "CURSED", "CURSED"
        if c.expire and c.expire > now then
            r.wsLeft = c.expire - now
            if c.duration and c.duration > 0 then r.lockMax = c.duration end
            r.rightText = string.format("%ds", math.ceil(r.wsLeft))
        end
        intCurses = intCurses + 1
    end

    -- Crowd control on this teammate (sheep, fear, stun, blind...): loud
    -- awareness — in arena a CC'd partner reshapes the next three seconds.
    -- A removable curse still outranks it (that one is YOUR action).
    local cc = ccState[r.guid]
    if cc and cc.expire and cc.expire > 0 and cc.expire <= now then
        ccState[r.guid], cc = nil, nil
    end
    if cc then
        intCCs = intCCs + 1
        if r.state ~= "CURSED" then
            r.state = "CCED"
            local nm = cc.name
            r.mainText = (nm and #nm > 10) and nm:sub(1, 10) or nm or "CC"
            if cc.expire and cc.expire > now then
                r.wsLeft = cc.expire - now
                if cc.duration and cc.duration > 0 then r.lockMax = cc.duration end
                r.rightText = string.format("%ds", math.ceil(r.wsLeft))
            end
        end
    end
    return r
end

local function ResolveState(r, now)
    if layer == "INT" and not r.selfSpell then return ResolveIntState(r, now) end
    return ResolveShieldState(r, now)
end

-- Live path: pull identity/liveness/health/range off the unit token.
local function ResolveRow(unit, now)
    local guid = UnitGUID and UnitGUID(unit)
    if not guid then return nil end
    local className = select(2, UnitClass(unit))
    local r = {
        guid = guid,
        unit = unit,
        name = UnitName(unit) or "?",
        class = className,
        isSelf = UnitIsUnit(unit, "player"),
        -- INT layer: mana classes are Int-buff targets (see MANA_CLASSES)
        manaUser = (layer == "INT") and MANA_CLASSES[className or ""] or nil,
    }
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
        r.dead, r.deadText = true, "DEAD"
    elseif UnitIsConnected and not UnitIsConnected(unit) then
        r.dead, r.deadText = true, "OFFLINE"
    end
    -- Health is every ally row's main bar now; hpMax also scales the
    -- embedded shield segments
    if UnitHealthMax then
        local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
        if hpMax and hpMax > 0 then
            r.health = hp / hpMax
            r.hpMax = hpMax
        end
    end
    -- INT layer: mana strip for mana users (read live; the ticker repaints)
    if layer == "INT" and r.manaUser and UnitPower and UnitPowerMax then
        local m, mMax = UnitPower(unit, 0), UnitPowerMax(unit, 0)
        if mMax and mMax > 0 then r.mana = m / mMax end
    end
    if DB("RangeFade", false) and not r.isSelf and UnitInRange then
        local inRange, checked = UnitInRange(unit)
        r.outOfRange = checked and not inRange or false
    end
    return ResolveState(r, now)
end

-- Self-shield extra: one row per tracked spell, all riding the player unit.
-- The pseudo-GUID keys the shared state tables; dispel/targeter data stays
-- keyed by the real player GUID, so those extras read through dispelKey/tgtKey.
local function SelfRow(def, now)
    local r = {
        guid = SELF_KEY .. def.key,
        unit = "player",
        name = def.label,
        class = playerClass,
        isSelf = true,
        selfSpell = def,
        icon = def.icon,
        duration = def.duration,
        lockMax = def.cooldown,
        dispelKey = playerGUID,
        tgtKey = playerGUID,
    }
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        r.dead, r.deadText = true, "DEAD"
    end
    return ResolveState(r, now)
end

local function SelfTrackEnabled(def)
    if def.key == "MANA" then return DB("TrackManaShield", true) end
    if def.ward then return DB("TrackWards", true) end
    return true
end

-- The Water Elemental's own row (INT layer, while it is in play): portrait,
-- lifespan as a draining bar — same language as the self-shield rows — its
-- health on the underlay strip, and Freeze riding the second icon slot with
-- its cooldown sweep. The gold tick on the lifespan bar marks the last
-- moment a Freeze still leaves room for a second cast before despawn (45s
-- life vs ~25s cooldown); past the tick the bar turns amber: one cast left.
local lastFreezeDur = 25    -- observed Freeze CD duration; 25s until seen
local function EleRow(now)
    local left = eleExpire > now and (eleExpire - now) or nil
    local hp
    if UnitHealth and UnitHealthMax then
        local h, hm = UnitHealth("pet"), UnitHealthMax("pet")
        if hm and hm > 0 then hp = h / hm end
    end
    local r = {
        guid = "cselfELE",
        unit = "pet",
        name = "Elemental",
        class = playerClass,
        isSelf = true,
        selfSpell = true,
        eleRow = true,
        icon = eleIcon,
        state = (left and left <= 10) and "REFRESH" or "SHIELDED",
        ratio = left and math.min(left / SDATA.ELE_DURATION, 1) or nil,
        rightText = left and string.format("%ds", math.ceil(left)) or "",
        mainText = "",
        tLeft = left,
        eleHealth = hp,
        freezeMark = math.min(lastFreezeDur / SDATA.ELE_DURATION, 1),
        eleUrgent = (left and left <= lastFreezeDur) or false,
    }
    local fcd, fdur, fstart = FreezeCooldown()
    if fdur and fdur > 1.5 then lastFreezeDur = fdur end
    r.freezeCd, r.freezeDur, r.freezeStart = fcd, fdur, fstart
    return r
end

-- ---------------------------------------------------------------------------
-- Class icon helpers
-- ---------------------------------------------------------------------------
local function SetClassIcon(tex, classToken, guid)
    if not classToken and guid and GetPlayerInfoByGUID then
        local _, token = GetPlayerInfoByGUID(guid)
        classToken = token
    end
    local coords = classToken and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken]
    if coords then
        tex:SetTexture(CLASS_ICON_TEXTURE)
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        return true
    end
    tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return false
end

local function ShortName(name, maxc)
    if not name then return "" end
    if maxc and maxc > 0 and #name > maxc then return name:sub(1, maxc) end
    return name
end

-- Spec icon when the spec has been learned, class icon until then
local function SetSpecOrClassIcon(tex, r)
    local spec = r.guid and specState[r.guid]
    local icon = spec and r.class and SDATA.SPEC_ICONS[r.class] and SDATA.SPEC_ICONS[r.class][spec]
    if icon then
        tex:SetTexture(icon)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        return
    end
    SetClassIcon(tex, r.class, r.guid)
end


-- ---------------------------------------------------------------------------
-- Row widgets. Rows are secure unit buttons when Click-Cast was on at load
-- (bound to a fixed token so nothing secure changes in combat), plain frames
-- otherwise. Every visual is an insecure child so it can update mid-combat.
-- ---------------------------------------------------------------------------
local function BuildRowTooltip(self)
    if not self.unitToken or not UnitExists(self.unitToken) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetUnit(self.unitToken)
    GameTooltip:Show()
end

-- Widget construction shared by ally rows (secure or plain) and the
-- personal-row pool (always plain)
local function BuildRowWidgets(row)
    row:SetSize(FrameWidth(), ROW_H)

    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.stripe:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.stripe:SetWidth(STRIPE_W)

    row.spellIcon = row:CreateTexture(nil, "ARTWORK")
    row.spellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.swipe = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
    if row.swipe.SetHideCountdownNumbers then row.swipe:SetHideCountdownNumbers(true) end
    if row.swipe.SetDrawEdge then row.swipe:SetDrawEdge(false) end
    row.swipe:Hide()

    -- Second left status slot (INT layer): an incoming priest shield, with a
    -- 30s sweep for its remaining duration
    row.inShield = row:CreateTexture(nil, "ARTWORK")
    row.inShield:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.inShield:Hide()
    row.inShieldCd = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
    if row.inShieldCd.SetHideCountdownNumbers then row.inShieldCd:SetHideCountdownNumbers(true) end
    if row.inShieldCd.SetDrawEdge then row.inShieldCd:SetDrawEdge(false) end
    row.inShieldCd:Hide()

    row.unitIcon = row:CreateTexture(nil, "ARTWORK")
    row.unitIcon2 = row:CreateTexture(nil, "ARTWORK")   -- ICON_PORTRAIT's portrait slot
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetJustifyH("LEFT")

    -- Targeted-by counter: rides the class icon / portrait, so it follows
    -- wherever LayoutRow packs the identity element. NumberFontNormal has
    -- its own outline, which keeps the digit readable over any class art.
    row.tgtCount = row:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    row.tgtCount:SetPoint("CENTER", row.unitIcon, "CENTER", 0, 0)
    row.tgtCount:Hide()

    row.barBG = row:CreateTexture(nil, "BACKGROUND")
    row.barBG:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.barBG:SetVertexColor(0, 0, 0, 0.55)
    row.healthBar = row:CreateTexture(nil, "ARTWORK")
    row.healthBar:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.healthBar:SetVertexColor(0.2, 0.7, 0.3, 0.9)
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
    -- Embedded shield segments: colored slices chained off the health fill's
    -- right edge, one per absorb type, widths set every paint
    row.shieldSegs = {}
    for n = 1, SDATA.MAX_SHIELD_SEGS do
        local t = row:CreateTexture(nil, "ARTWORK")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetSize(1, BAR_H)
        t:SetPoint("TOPLEFT", n == 1 and row.bar or row.shieldSegs[n - 1], "TOPRIGHT", 0, 0)
        t:Hide()
        row.shieldSegs[n] = t
    end
    row.wsBar = row:CreateTexture(nil, "OVERLAY")
    row.wsBar:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.wsBar:SetVertexColor(0.9, 0.2, 0.2, 0.9)

    -- Vertical threshold tick on the main bar (the elemental's Freeze window)
    row.markTick = row:CreateTexture(nil, "OVERLAY")
    row.markTick:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.markTick:SetVertexColor(1, 0.85, 0.25, 0.95)
    row.markTick:Hide()

    row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.left:SetJustifyH("LEFT")
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetJustifyH("RIGHT")

    -- Glow (reshield window) and flash (shield broke) overlays
    row.glow = row:CreateTexture(nil, "OVERLAY")
    row.glow:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.glow:SetAllPoints(row)
    row.glow:SetVertexColor(0.4, 0.9, 1, 0.15)
    row.glow:Hide()
    row.flash = row:CreateTexture(nil, "OVERLAY")
    row.flash:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.flash:SetAllPoints(row)
    row.flash:SetVertexColor(1, 0.2, 0.2, 1)
    row.flash:Hide()

    -- Renew indicator (optional): a small icon at the row's right edge with a
    -- radial sweep for the HoT's remaining duration
    row.renewIcon = row:CreateTexture(nil, "ARTWORK")
    row.renewIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.renewIcon:Hide()
    row.renewSwipe = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
    if row.renewSwipe.SetHideCountdownNumbers then row.renewSwipe:SetHideCountdownNumbers(true) end
    if row.renewSwipe.SetDrawEdge then row.renewSwipe:SetDrawEdge(false) end
    row.renewSwipe:Hide()

    -- Dispellable-debuff strip, hanging off the row's right edge. Each slot is
    -- a CC glow (behind), a dispel-type rim, the icon, and a duration sweep.
    row.dispels = {}
    for n = 1, MAX_DISPEL_ICONS do
        local d = {}
        d.glow = row:CreateTexture(nil, "BACKGROUND")
        d.glow:SetTexture("Interface\\Buttons\\WHITE8X8")
        d.glow:SetVertexColor(1, 0.95, 0.4, 0.6)
        d.glow:Hide()
        d.rim = row:CreateTexture(nil, "BORDER")
        d.rim:SetTexture("Interface\\Buttons\\WHITE8X8")
        d.rim:Hide()
        d.icon = row:CreateTexture(nil, "ARTWORK")
        d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        d.icon:Hide()
        d.cd = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
        if d.cd.SetHideCountdownNumbers then d.cd:SetHideCountdownNumbers(true) end
        if d.cd.SetDrawEdge then d.cd:SetDrawEdge(false) end
        d.cd:Hide()
        row.dispels[n] = d
    end
end

local function AcquireRow(index)
    local row = rowPool[index]
    if row then return row end
    if securePool then
        row = CreateFrame("Button", "CommanderPartyFramesRow" .. index, root, "SecureUnitButtonTemplate")
        -- Both phases so the click fires whatever ActionButtonUseKeyDown is set to
        row:RegisterForClicks("AnyDown", "AnyUp")
        row:SetScript("OnEnter", BuildRowTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        row = CreateFrame("Frame", nil, root)
    end
    BuildRowWidgets(row)
    rowPool[index] = row
    return row
end

-- Personal rows (Water Elemental, My Shields): ALWAYS plain insecure frames
-- in their own pool, so they exist on the Click-Cast board too and can be
-- created and positioned freely even mid-combat.
local function AcquirePersonalRow(index)
    local row = personalPool[index]
    if row then return row end
    row = CreateFrame("Frame", nil, root)
    BuildRowWidgets(row)
    personalPool[index] = row
    return row
end

-- Lay out a row's inner pieces for the current settings. Horizontal flow packs
-- only the enabled identity elements (spell icon, class icon / portrait, name);
-- the bar fills the rest. Cached by a signature so it runs only on change.
local function LayoutRow(row, width, sig)
    local showIcon = DB("ShowSpellIcon", true)
    local mode = DB("UnitDisplay", "CLASS_ICON")
    -- Health is the main bar on every layer now; the underlay slot carries
    -- MANA on the mage board and is retired on the priest board
    local showHealth
    if layer == "INT" then
        showHealth = DB("ShowManaBar", true)
    else
        showHealth = false
    end
    local showUnitIcon = (mode == "CLASS_ICON" or mode == "PORTRAIT" or mode == "ICON_NAME"
        or mode == "ICON_PORTRAIT" or mode == "SPEC" or mode == "SPEC_PORTRAIT")
    local showUnitIcon2 = (mode == "ICON_PORTRAIT" or mode == "SPEC_PORTRAIT")
    local showName = (mode == "NAME" or mode == "ICON_NAME")

    row:SetSize(width, ROW_H)
    local x = STRIPE_W + 3

    if showIcon then
        local iconSize = (layer == "INT") and SMALL_ICON or ICON_SIZE
        row.spellIcon:ClearAllPoints()
        row.spellIcon:SetSize(iconSize, iconSize)
        row.spellIcon:SetPoint("LEFT", row, "LEFT", x, 0)
        row.spellIcon:Show()
        row.swipe:ClearAllPoints()
        row.swipe:SetAllPoints(row.spellIcon)
        x = x + iconSize + 3
        if layer == "INT" then
            -- Second status slot: the incoming-shield icon
            row.inShield:ClearAllPoints()
            row.inShield:SetSize(SMALL_ICON, SMALL_ICON)
            row.inShield:SetPoint("LEFT", row, "LEFT", x, 0)
            row.inShieldCd:ClearAllPoints()
            row.inShieldCd:SetAllPoints(row.inShield)
            x = x + SMALL_ICON + 3
        else
            row.inShield:Hide()
            row.inShieldCd:Hide()
        end
    else
        row.spellIcon:Hide()
        row.swipe:Hide()
        row.inShield:Hide()
        row.inShieldCd:Hide()
    end

    if showUnitIcon then
        row.unitIcon:ClearAllPoints()
        row.unitIcon:SetSize(ICON_SIZE, ICON_SIZE)
        row.unitIcon:SetPoint("LEFT", row, "LEFT", x, 0)
        row.unitIcon:Show()
        x = x + ICON_SIZE + 3
    else
        row.unitIcon:Hide()
    end
    if showUnitIcon2 then
        row.unitIcon2:ClearAllPoints()
        row.unitIcon2:SetSize(ICON_SIZE, ICON_SIZE)
        row.unitIcon2:SetPoint("LEFT", row, "LEFT", x, 0)
        row.unitIcon2:Show()
        x = x + ICON_SIZE + 3
    else
        row.unitIcon2:Hide()
    end

    if showName then
        local nw = (mode == "ICON_NAME") and SHORT_NAME_W or NAME_W
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", row, "LEFT", x, 0)
        row.name:SetWidth(nw)
        row.name:Show()
        x = x + nw + 3
    else
        row.name:Hide()
    end

    -- Reserve room at the right for the Renew icon when it is tracked
    -- (Priest-only: a shared account DB can carry the flag onto a Mage)
    local renewOn = DB("RenewTrack", false) and layer == "PWS"
    local rightReserve = renewOn and (RENEW_ICON_SIZE + 4) or 0
    local barX = x
    local barW = width - barX - PAD - rightReserve
    if barW < 40 then barW = 40 end
    -- Vertical stack: absorb bar on top, optional health, then WS drain
    local barTop = -(ROW_H - BAR_H - (showHealth and HEALTH_H or 0) - WS_H) / 2
    row.barBG:ClearAllPoints()
    row.barBG:SetPoint("TOPLEFT", row, "TOPLEFT", barX, barTop)
    row.barBG:SetSize(barW, BAR_H)
    row.bar:ClearAllPoints()
    row.bar:SetPoint("TOPLEFT", row.barBG, "TOPLEFT", 0, 0)
    row.bar:SetSize(barW, BAR_H)

    local y = barTop - BAR_H
    if showHealth then
        row.healthBar:ClearAllPoints()
        row.healthBar:SetPoint("TOPLEFT", row, "TOPLEFT", barX, y)
        row.healthBar:SetSize(barW, HEALTH_H)
        y = y - HEALTH_H
    else
        row.healthBar:Hide()
    end
    row.wsBar:ClearAllPoints()
    row.wsBar:SetPoint("TOPLEFT", row, "TOPLEFT", barX, y)
    row.wsBar:SetSize(barW, WS_H)

    row.left:ClearAllPoints()
    row.left:SetPoint("LEFT", row.barBG, "LEFT", 3, 0)
    row.right:ClearAllPoints()
    row.right:SetPoint("RIGHT", row.barBG, "RIGHT", -3, 0)

    if renewOn then
        row.renewIcon:ClearAllPoints()
        row.renewIcon:SetSize(RENEW_ICON_SIZE, RENEW_ICON_SIZE)
        row.renewIcon:SetPoint("RIGHT", row, "RIGHT", -(PAD - 2), 0)
        row.renewSwipe:ClearAllPoints()
        row.renewSwipe:SetAllPoints(row.renewIcon)
    else
        row.renewIcon:Hide()
        row.renewSwipe:Hide()
    end

    -- Dispel strip: marches rightward OUTSIDE the frame so it never eats board width
    local dispelOn = DB("ShowDispels", false)
    local dSize = DB("DispelIconSize", 16)
    local dMax = DB("DispelMaxIcons", 3)
    for n = 1, MAX_DISPEL_ICONS do
        local d = row.dispels[n]
        if dispelOn and n <= dMax then
            d.icon:ClearAllPoints()
            d.icon:SetSize(dSize, dSize)
            d.icon:SetPoint("LEFT", row, "RIGHT", 5 + (n - 1) * (dSize + 4), 0)
            d.rim:ClearAllPoints()
            d.rim:SetPoint("TOPLEFT", d.icon, "TOPLEFT", -2, 2)
            d.rim:SetPoint("BOTTOMRIGHT", d.icon, "BOTTOMRIGHT", 2, -2)
            d.glow:ClearAllPoints()
            d.glow:SetPoint("TOPLEFT", d.icon, "TOPLEFT", -5, 5)
            d.glow:SetPoint("BOTTOMRIGHT", d.icon, "BOTTOMRIGHT", 5, -5)
            d.cd:ClearAllPoints()
            d.cd:SetAllPoints(d.icon)
        else
            d.icon:Hide(); d.rim:Hide(); d.glow:Hide(); d.cd:Hide()
        end
    end

    row._barW = barW
    row._sig = sig
end

local function LayoutSig(width)
    return width .. "|" .. tostring(DB("ShowSpellIcon", true)) .. "|"
        .. DB("UnitDisplay", "CLASS_ICON") .. "|" .. tostring(DB("ShowHealth", false))
        .. "|" .. tostring(DB("RenewTrack", false))
        .. "|" .. tostring(DB("ShowDispels", false)) .. "|" .. DB("DispelMaxIcons", 3)
        .. "|" .. DB("DispelIconSize", 16) .. "|" .. tostring(DB("ShowManaBar", true))
end

local function PositionRow(row, index, topOffset, grow)
    row:ClearAllPoints()
    if grow == "UP" then
        row:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, (index - 1) * (ROW_H + ROW_GAP))
    else
        row:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -topOffset - (index - 1) * (ROW_H + ROW_GAP))
    end
end

-- ---------------------------------------------------------------------------
-- Paint a row from resolved data. INSECURE ONLY (textures / fontstrings /
-- alpha) so it is always safe, even on a secure row mid-combat.
-- ---------------------------------------------------------------------------
local function PaintRow(row, r, now, index)
    if not r or r.state == "EMPTY" then
        row:SetAlpha(0)
        row.spellIcon:Hide(); row.swipe:Hide(); row.unitIcon:Hide(); row.unitIcon2:Hide(); row.name:Hide()
        row.inShield:Hide(); row.inShieldCd:Hide()
        row.bar:Hide(); row.barBG:Hide(); row.healthBar:Hide(); row.wsBar:Hide()
        row.markTick:Hide()
        for i = 1, SDATA.MAX_SHIELD_SEGS do row.shieldSegs[i]:Hide() end
        row.left:SetText(""); row.right:SetText(""); row.glow:Hide(); row.flash:Hide()
        row.tgtCount:Hide()
        row.stripe:SetAlpha(0)
        return
    end
    row:SetAlpha(r.outOfRange and 0.4 or 1)
    row.barBG:Show()

    local def = STATES[r.state] or STATES.SHIELDED
    row.stripe:SetVertexColor(def.color[1], def.color[2], def.color[3], 1)
    row.stripe:SetAlpha(r.state == "READY" and (0.55 + 0.45 * math.abs(math.sin(now * 3))) or 1)

    -- Left status slot. INT ally rows: Int state icon (lit / amber when due /
    -- ghost when missing) + an incoming priest shield with its 30s sweep.
    -- Everything else: the spell icon, desaturated when no shield is up.
    if DB("ShowSpellIcon", true) then
        if layer == "INT" and not r.selfSpell then
            if r.manaUser then
                row.spellIcon:SetTexture(AI_ICON)
                row.spellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                if row.spellIcon.SetDesaturated then row.spellIcon:SetDesaturated(not r.intUp) end
                if not r.intUp then
                    row.spellIcon:SetVertexColor(1, 1, 1, 0.35)      -- ghost: cast Int
                elseif r.intDue then
                    row.spellIcon:SetVertexColor(1, 0.65, 0.3, 1)    -- amber: rebuff soon
                else
                    row.spellIcon:SetVertexColor(1, 1, 1, 1)
                end
                row.spellIcon:Show()
            else
                row.spellIcon:Hide()   -- no Int slot for rage/energy allies
            end
            row._swExp = nil
            row.swipe:Hide()
            if r.inShield and r.inShieldExpire then
                row.inShield:SetTexture(r.inShieldIcon or SDATA.PWS_ICON)
                row.inShield:Show()
                if row._inExp ~= r.inShieldExpire then
                    row._inExp = r.inShieldExpire
                    local dur = r.inShieldDuration or SDATA.SHIELD_DURATION
                    row.inShieldCd:SetCooldown(r.inShieldExpire - dur, dur)
                end
                row.inShieldCd:Show()
            else
                row._inExp = nil
                row.inShield:Hide()
                row.inShieldCd:Hide()
            end
        elseif r.eleRow then
            -- Elemental row: the pet's portrait, Freeze on the second slot
            -- with its cooldown sweep (lit the moment it is ready)
            if r.unit and UnitExists(r.unit) and SetPortraitTexture then
                SetPortraitTexture(row.spellIcon, r.unit)
                row.spellIcon:SetTexCoord(0.12, 0.88, 0.12, 0.88)
            else
                row.spellIcon:SetTexture(r.icon)
                row.spellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            row.spellIcon:SetVertexColor(1, 1, 1, 1)
            if row.spellIcon.SetDesaturated then row.spellIcon:SetDesaturated(false) end
            row.spellIcon:Show()
            row._swExp = nil
            row.swipe:Hide()
            if freezeIcon then
                row.inShield:SetTexture(freezeIcon)
                if row.inShield.SetDesaturated then row.inShield:SetDesaturated((r.freezeCd or 0) > 0) end
                row.inShield:Show()
                if r.freezeCd and r.freezeCd > 0 and r.freezeStart and r.freezeDur then
                    if row._inExp ~= r.freezeStart then
                        row._inExp = r.freezeStart
                        row.inShieldCd:SetCooldown(r.freezeStart, r.freezeDur)
                    end
                    row.inShieldCd:Show()
                else
                    row._inExp = nil
                    row.inShieldCd:Hide()
                end
            else
                row.inShield:Hide(); row.inShieldCd:Hide()
            end
        else
            row.spellIcon:SetTexture(r.icon or SDATA.PWS_ICON)
            row.spellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.spellIcon:SetVertexColor(1, 1, 1, 1)
            if row.spellIcon.SetDesaturated then row.spellIcon:SetDesaturated(not (r.shieldUp and r.mine)) end
            row.spellIcon:Show()
            row.inShield:Hide(); row.inShieldCd:Hide()
            -- Duration sweep comes from shieldState, which on the INT layer
            -- only self-spell rows own (an ally's entry would be a priest's PW:S)
            local st = (layer ~= "INT" or r.selfSpell) and shieldState[r.guid] or nil
            if DB("ShieldSwipe", false) and r.shieldUp and r.mine and st and st.expire then
                if row._swExp ~= st.expire then
                    row._swExp = st.expire
                    local dur = st.duration or SDATA.SHIELD_DURATION
                    row.swipe:SetCooldown(st.expire - dur, dur)
                end
                row.swipe:Show()
            else
                row._swExp = nil
                row.swipe:Hide()
            end
        end
    else
        row.spellIcon:Hide(); row.swipe:Hide()
        row.inShield:Hide(); row.inShieldCd:Hide()
    end

    -- Identity: class icon / portrait / name per UnitDisplay. Self-spell rows
    -- have no unit to show — their identity is the spell icon, plus the spell's
    -- short name whenever the layout has a name slot.
    local mode = DB("UnitDisplay", "CLASS_ICON")
    if r.selfSpell then
        row.unitIcon:Hide()
        row.unitIcon2:Hide()
        if mode == "NAME" or mode == "ICON_NAME" then
            local cc = r.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[r.class]
            row.name:SetTextColor(cc and cc.r or 0.9, cc and cc.g or 0.9, cc and cc.b or 0.9)
            row.name:SetText(r.name or "")
            row.name:Show()
        else
            row.name:Hide()
        end
    elseif mode == "PORTRAIT" then
        if r.unit and UnitExists(r.unit) and SetPortraitTexture then
            SetPortraitTexture(row.unitIcon, r.unit)
            row.unitIcon:SetTexCoord(0.12, 0.88, 0.12, 0.88)
        else
            SetClassIcon(row.unitIcon, r.class, r.guid)
        end
        row.unitIcon:Show()
        row.unitIcon2:Hide()
    elseif mode == "ICON_PORTRAIT" then
        -- Class icon first, the live portrait beside it
        SetClassIcon(row.unitIcon, r.class, r.guid)
        row.unitIcon:Show()
        if r.unit and UnitExists(r.unit) and SetPortraitTexture then
            SetPortraitTexture(row.unitIcon2, r.unit)
            row.unitIcon2:SetTexCoord(0.12, 0.88, 0.12, 0.88)
        else
            SetClassIcon(row.unitIcon2, r.class, r.guid)
        end
        row.unitIcon2:Show()
    elseif mode == "SPEC" then
        SetSpecOrClassIcon(row.unitIcon, r)
        row.unitIcon:Show()
        row.unitIcon2:Hide()
    elseif mode == "SPEC_PORTRAIT" then
        SetSpecOrClassIcon(row.unitIcon, r)
        row.unitIcon:Show()
        if r.unit and UnitExists(r.unit) and SetPortraitTexture then
            SetPortraitTexture(row.unitIcon2, r.unit)
            row.unitIcon2:SetTexCoord(0.12, 0.88, 0.12, 0.88)
        else
            SetSpecOrClassIcon(row.unitIcon2, r)
        end
        row.unitIcon2:Show()
    elseif mode == "CLASS_ICON" or mode == "ICON_NAME" then
        SetClassIcon(row.unitIcon, r.class, r.guid)
        row.unitIcon:Show()
        row.unitIcon2:Hide()
    else
        row.unitIcon:Hide()
        row.unitIcon2:Hide()
    end

    if r.selfSpell then
        -- name already set above; nothing to do here
    elseif mode == "NAME" or mode == "ICON_NAME" then
        local cc = r.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[r.class]
        row.name:SetTextColor(cc and cc.r or 0.9, cc and cc.g or 0.9, cc and cc.b or 0.9)
        row.name:SetText(ShortName(r.name, DB("NameMaxChars", 6)))
        row.name:Show()
    else
        row.name:Hide()
    end

    -- Targeted-by counter over the identity icon: white 1, amber 2, red 3+.
    -- Only meaningful when the icon is drawn (Name-only rows have no anchor).
    -- Self boards ride the spell icon instead and only mark the top row —
    -- every row is the same person, so once is enough.
    local tgtAnchor = r.selfSpell and row.spellIcon or row.unitIcon
    local nTgt = DB("ShowTargeters", true) and (not r.selfSpell or index == 1)
        and r.guid and targeters[r.tgtKey or r.guid]
    if nTgt and nTgt > 0 and tgtAnchor:IsShown() then
        if row._tgtAnchor ~= tgtAnchor then
            row._tgtAnchor = tgtAnchor
            row.tgtCount:ClearAllPoints()
            row.tgtCount:SetPoint("CENTER", tgtAnchor, "CENTER", 0, 0)
        end
        row.tgtCount:SetText(nTgt)
        if nTgt >= 3 then
            row.tgtCount:SetTextColor(1, 0.25, 0.25)
        elseif nTgt == 2 then
            row.tgtCount:SetTextColor(1, 0.8, 0.2)
        else
            row.tgtCount:SetTextColor(1, 1, 1)
        end
        row.tgtCount:Show()
    else
        row.tgtCount:Hide()
    end

    -- Shield (absorb) bar — a light grey ("darkened white"), so it reads clearly
    -- apart from the green health underlay while the white number/timer on top
    -- stays legible. Others' shields stay blue-grey; remaining strength is shown
    -- by the bar's width and the state stripe rather than its color.
    if r.ratio then
        if r.healthMain then
            -- Health-colored main bar: green at full through amber to red
            local h = r.ratio
            row.bar:SetVertexColor(math.min(1, 1.6 - h * 1.4), math.min(0.75, 0.15 + h * 0.75), 0.2, 0.9)
        elseif r.eleRow then
            -- Lifespan bar: elemental blue while a double-Freeze still fits,
            -- amber once only one more cast can land before despawn
            if r.eleUrgent then
                row.bar:SetVertexColor(0.88, 0.58, 0.25, 0.95)
            else
                row.bar:SetVertexColor(0.45, 0.70, 0.90, 0.95)
            end
        elseif r.state == "OTHER" then
            row.bar:SetVertexColor(0.45, 0.5, 0.7, 0.9)
        else
            row.bar:SetVertexColor(0.44, 0.44, 0.46, 0.95)
        end
        row.bar:SetWidth(math.max((row._barW or 100) * r.ratio, 1))
        row.bar:Show()
    else
        row.bar:Hide()
    end

    -- Embedded shield segments, chained off the health fill: cream PW:S,
    -- vibrant blue Barrier, muted blue-grey Mana Shield, school-tinted
    -- wards, dark grey Sacrifice — all on the same scale as the health
    local nSegs = 0
    if r.healthMain and r.segs and r.segScale and r.segScale > 0 and row.bar:IsShown() then
        local barW = row._barW or 100
        for i = 1, #r.segs do
            local s = r.segs[i]
            local w = barW * (s.amount / r.segScale)
            if w >= 1 and nSegs < SDATA.MAX_SHIELD_SEGS then
                nSegs = nSegs + 1
                local tex = row.shieldSegs[nSegs]
                -- Per-type tints, or one classic cream when the minute
                -- differences between shields aren't wanted
                local c = DB("ColorShieldTypes", true)
                    and (SDATA.SHIELD_COLORS[s.name] or SDATA.SHIELD_COLOR_DEFAULT)
                    or SDATA.SHIELD_UNIFORM
                tex:SetVertexColor(c[1], c[2], c[3], 0.95)
                tex:SetWidth(w)
                tex:Show()
            end
        end
    end
    for i = nSegs + 1, SDATA.MAX_SHIELD_SEGS do row.shieldSegs[i]:Hide() end

    -- Underlay strip: MANA on the mage board's ally rows, the elemental's
    -- HEALTH on its row (health is the main bar everywhere else now)
    if layer == "INT" and not r.selfSpell and r.mana and DB("ShowManaBar", true) then
        row.healthBar:SetVertexColor(0.25, 0.5, 0.95, 0.9)
        row.healthBar:SetWidth(math.max((row._barW or 100) * r.mana, 1))
        row.healthBar:Show()
    elseif r.eleRow and r.eleHealth and DB("ShowManaBar", true) then
        row.healthBar:SetVertexColor(0.2, 0.7, 0.3, 0.9)
        row.healthBar:SetWidth(math.max((row._barW or 100) * r.eleHealth, 1))
        row.healthBar:Show()
    else
        row.healthBar:Hide()
    end

    -- Freeze-window tick (elemental row only): sits at the point on the
    -- lifespan bar where a Freeze cast stops leaving room for a second one
    if r.eleRow and r.freezeMark and row._barW then
        local x = math.max(0, math.min((row._barW or 100) - 2, (row._barW or 100) * r.freezeMark))
        row.markTick:ClearAllPoints()
        row.markTick:SetPoint("TOPLEFT", row.barBG, "TOPLEFT", x, 0)
        row.markTick:SetSize(2, BAR_H)
        row.markTick:Show()
    else
        row.markTick:Hide()
    end

    -- Recast-lockout drain: Weakened Soul on ally rows, the spell's own
    -- cooldown on self-spell rows (r.lockMax carries that spell's full CD)
    if r.wsLeft and r.wsLeft > 0 then
        local lockMax = (r.lockMax and r.lockMax > 0) and r.lockMax or SDATA.WEAKENED_SOUL_MAX
        row.wsBar:SetWidth(math.max((row._barW or 100) * math.min(r.wsLeft / lockMax, 1), 1))
        row.wsBar:Show()
    else
        row.wsBar:Hide()
    end

    row.left:SetText(r.mainText or "")
    row.right:SetText(r.rightText or "")

    -- Renew indicator: bright + radial sweep while our Renew ticks, a red pulse
    -- when it is about to fall off, a dim ghost icon when it is missing.
    -- Priest-only; the shared account DB can carry the flag onto a Mage.
    if DB("RenewTrack", false) and layer == "PWS" and r.state ~= "EMPTY" and not r.dead then
        row.renewIcon:SetTexture(SDATA.RENEW_ICON)
        local rl = r.renewLeft or 0
        if rl > 0 and r.renewExpire then
            if row.renewIcon.SetDesaturated then row.renewIcon:SetDesaturated(false) end
            if row._rnExp ~= r.renewExpire then
                row._rnExp = r.renewExpire
                row.renewSwipe:SetCooldown(r.renewExpire - SDATA.RENEW_DURATION, SDATA.RENEW_DURATION)
            end
            row.renewSwipe:Show()
            local expiring = rl <= DB("RenewRefreshAt", 4)
            if expiring and DB("RenewFlash", true) then
                row.renewIcon:SetVertexColor(1, 0.4, 0.4, 0.55 + 0.45 * math.abs(math.sin(now * 4)))
            elseif expiring then
                row.renewIcon:SetVertexColor(1, 0.55, 0.55, 1)
            else
                row.renewIcon:SetVertexColor(1, 1, 1, 1)
            end
        else
            row._rnExp = nil
            row.renewSwipe:Hide()
            if row.renewIcon.SetDesaturated then row.renewIcon:SetDesaturated(true) end
            row.renewIcon:SetVertexColor(1, 1, 1, 0.3)   -- ghost: Renew missing
        end
        row.renewIcon:Show()
    else
        row.renewIcon:Hide()
        row.renewSwipe:Hide()
    end

    -- Dispellable debuffs, marching right of the frame. Rim is colored by dispel
    -- school; crowd control pulses a glow so it jumps out of a busy strip.
    local dShown = 0
    if DB("ShowDispels", false) and r.state ~= "EMPTY" and not r.dead
        and (not r.selfSpell or index == 1) then
        local list = dispelState[r.dispelKey or r.guid]
        local dMax = DB("DispelMaxIcons", 3)
        local ccGlow = DB("DispelCCGlow", true)
        local healGlow = DB("DispelHealGlow", true)
        local sweep = DB("DispelSweep", true)
        if list then
            for n = 1, math.min(list.n or 0, dMax) do
                local e = list[n]
                -- Skip anything that has already run out (the list only
                -- refreshes on aura events, which stop for far-away allies)
                if e and (not e.expire or e.expire == 0 or e.expire > now) then
                    dShown = dShown + 1
                    local d = row.dispels[dShown]
                    d.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    d.icon:Show()
                    -- Rim: dispel school when we can actually remove it, else
                    -- the category color for a contextually important debuff
                    local c
                    if e.canDispel then
                        c = DISPEL_COLORS[e.dispelName or "None"]
                    elseif e.important then
                        c = IMPORTANT_COLORS[e.important]
                    end
                    c = c or DISPEL_COLORS[e.dispelName or "None"] or DISPEL_COLORS.None
                    d.rim:SetVertexColor(c[1], c[2], c[3], 0.95)
                    d.rim:Show()
                    if sweep and e.expire and e.duration and e.duration > 0 then
                        d.cd:SetCooldown(e.expire - e.duration, e.duration)
                        d.cd:Show()
                    else
                        d.cd:Hide()
                    end
                    -- Glow: yellow pulse for crowd control, red for anything
                    -- cutting healing received (shield beats heal there)
                    if e.cc and ccGlow then
                        d.glow:SetVertexColor(1, 0.95, 0.4, 0.6)
                        d.glow:SetAlpha(0.35 + 0.45 * math.abs(math.sin(now * 4)))
                        d.glow:Show()
                    elseif e.important == "HEAL" and healGlow then
                        d.glow:SetVertexColor(1, 0.25, 0.25, 0.7)
                        d.glow:SetAlpha(0.4 + 0.45 * math.abs(math.sin(now * 4)))
                        d.glow:Show()
                    else
                        d.glow:Hide()
                    end
                end
            end
        end
    end
    for n = dShown + 1, MAX_DISPEL_ICONS do
        local d = row.dispels[n]
        d.icon:Hide(); d.rim:Hide(); d.glow:Hide(); d.cd:Hide()
    end

    -- Action glow (castable & wanted) and shield-broke flash. On INT ally
    -- rows the open actions are: decurse (CURSED), cast a missing Int, or
    -- rebuff one that is due.
    local glowOn = DB("WSReadyGlow", false) and (CASTABLE_STATES[r.state]
        or (layer == "INT" and not r.selfSpell and not r.dead
            and r.manaUser and (not r.intUp or r.intDue)))
    if glowOn then
        row.glow:SetAlpha(0.1 + 0.18 * math.abs(math.sin(now * 4)))
        row.glow:Show()
    else
        row.glow:Hide()
    end
    local flashEnd = rowFlash[index]
    if flashEnd and flashEnd > now then
        row.flash:SetAlpha(0.55 * (flashEnd - now) / 0.9)
        row.flash:Show()
    else
        rowFlash[index] = nil
        row.flash:Hide()
    end
end

-- Expose Alert: fire when an ally we were shielding just lost our shield while
-- still alive (they need a reshield). Edge-triggered per GUID.
local function CheckExposeAlert(r, index, now)
    if not DB("ExposeAlert", false) then return end
    local has = r.shieldUp and r.mine or false
    local was = prevMyShield[r.guid]
    prevMyShield[r.guid] = has
    -- Ally boards skip the self row (you feel your own shield break); on a
    -- self board the whole point is your own shield breaking.
    if was and not has and not r.dead and (r.selfSpell or not r.isSelf) then
        rowFlash[index] = now + 0.9
        if DB("ExposeAlertSound", false) and PlaySound then
            pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
        end
    end
end

-- ---------------------------------------------------------------------------
-- Secure mode: fixed-token rows. Bound once (out of combat) to raw tokens that
-- auto-follow whoever fills the slot, so mouseover/click-cast keep working all
-- fight without ever touching a secure attribute in combat.
-- ---------------------------------------------------------------------------
local function BuildSecureTokens(out)
    wipe(out)
    local maxRows = DB("MaxRows", 6)
    -- Bind only units that currently exist (a tight board), but rebind only
    -- out of combat — so the token->slot mapping never shifts mid-fight.
    if DB("Scope", "PARTY") == "RAID" and IsInRaid and IsInRaid() then
        for i = 1, 40 do
            if #out >= maxRows then break end
            if UnitExists("raid" .. i) then out[#out + 1] = "raid" .. i end
        end
    else
        if DB("IncludeSelf", true) then out[#out + 1] = "player" end
        for i = 1, 4 do
            if #out >= maxRows then break end
            if UnitExists("party" .. i) then out[#out + 1] = "party" .. i end
        end
    end
end

-- Bind one mouse button (optionally with a modifier prefix like "shift-") on a
-- secure row to a spell cast, a plain target, or nothing. dbval is a spell ID,
-- "TARGET", or "NONE". The name resolves from the ID so it stays locale-safe and
-- always casts the highest rank you know.
local function BindClick(row, prefix, button, dbval)
    local typeAttr, spellAttr = prefix .. "type" .. button, prefix .. "spell" .. button
    if dbval == "TARGET" then
        row:SetAttribute(typeAttr, "target")
        row:SetAttribute(spellAttr, nil)
    elseif dbval and dbval ~= "NONE" then
        local id = tonumber(dbval)
        local name = id and GetSpellInfo and GetSpellInfo(id)
        if name then
            row:SetAttribute(typeAttr, "spell")
            row:SetAttribute(spellAttr, name)
        else
            row:SetAttribute(typeAttr, nil)
            row:SetAttribute(spellAttr, nil)
        end
    else
        row:SetAttribute(typeAttr, nil)
        row:SetAttribute(spellAttr, nil)
    end
end

local function SetupSecureRows()
    if InCombat() then secureDirty = true; return end
    secureDirty = false
    BuildSecureTokens(secureTokens)
    local width = FrameWidth()
    local sig = LayoutSig(width)
    local showHeader = DB("ShowHeader", true)
    local topOffset = showHeader and HEADER_H or 0
    local grow = DB("Grow", "DOWN")
    local modPrefix = (DB("ClickModifier", "shift")) .. "-"
    for i, token in ipairs(secureTokens) do
        local row = AcquireRow(i)
        if row._sig ~= sig then LayoutRow(row, width, sig) end
        PositionRow(row, i, topOffset, grow)
        if row.SetAttribute then
            -- Raw token drives mouseover for @mouseover macros; each mouse button
            -- (and the modifier+left combo) casts its bound spell or targets. Both
            -- click phases are registered so the action fires whatever the
            -- ActionButtonUseKeyDown CVar is set to; re-applied here so rows built
            -- before a settings change update too. Secure -> out of combat only.
            if row.RegisterForClicks then row:RegisterForClicks("AnyDown", "AnyUp") end
            row:SetAttribute("unit", token)
            -- Each layer keeps its own binding keys: the DB is account-wide,
            -- so a priest's spell IDs must not leak onto a mage's buttons.
            if layer == "INT" then
                BindClick(row, "", "1", DB("MageClickLeft", 1459))          -- left   = Arcane Intellect
                BindClick(row, "", "2", DB("MageClickRight", 475))          -- right  = Remove Curse
                BindClick(row, "", "3", DB("MageClickMiddle", "TARGET"))    -- middle = target
                BindClick(row, modPrefix, "1", DB("MageClickModLeft", 1008))-- mod+left = Amplify Magic
            else
                BindClick(row, "", "1", DB("ClickLeft", 17))            -- left   = Power Word: Shield
                BindClick(row, "", "2", DB("ClickRight", 139))          -- right  = Renew
                BindClick(row, "", "3", DB("ClickMiddle", 2061))        -- middle = Flash Heal
                BindClick(row, modPrefix, "1", DB("ClickModLeft", 2060))-- mod+left = Greater Heal
            end
        end
        row.unitToken = token
        row:Show()
    end
    for i = #secureTokens + 1, #rowPool do
        rowPool[i]:Hide()
    end
    local slots = DB("FixedHeight", false) and DB("MaxRows", 6) or math.max(#secureTokens, 1)
    root:SetSize(width, topOffset + math.max(slots * (ROW_H + ROW_GAP) - ROW_GAP, ROW_H))
end

-- ---------------------------------------------------------------------------
-- Uptime sampling (Track Shield Uptime). Averages, per sample, the share of
-- shieldable allies currently carrying our shield.
-- ---------------------------------------------------------------------------
local sampleUnits = {}
local function SampleUptime(now)
    if not (uptime and DB("TrackUptime", false)) then return end
    if layer == "INT" then
        -- Combat metric that actually matters in arena: the share of the
        -- session YOU have an absorb up (Mana Shield / Ice Barrier / a
        -- priest's bubble) — not raid-buff coverage
        if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
        local covered = 0
        local rec = playerGUID and allyAbsorbs[playerGUID]
        if rec then
            for _, e in pairs(rec) do
                if not (e.expire and e.expire > 0 and e.expire <= now) then covered = 1; break end
            end
        end
        uptime.coverageSamples = (uptime.coverageSamples or 0) + 1
        uptime.coverageSum = (uptime.coverageSum or 0) + covered
        return
    end
    wipe(sampleUnits)
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do if UnitExists("raid" .. i) then sampleUnits[#sampleUnits + 1] = "raid" .. i end end
    elseif IsInGroup and IsInGroup() then
        sampleUnits[#sampleUnits + 1] = "player"
        for i = 1, 4 do if UnitExists("party" .. i) then sampleUnits[#sampleUnits + 1] = "party" .. i end end
    end
    local total, covered = 0, 0
    for _, unit in ipairs(sampleUnits) do
        if not (UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)) then
            total = total + 1
            local st = shieldState[UnitGUID(unit)]
            if st and st.mine then covered = covered + 1 end
        end
    end
    if total > 0 then
        uptime.coverageSamples = (uptime.coverageSamples or 0) + 1
        uptime.coverageSum = (uptime.coverageSum or 0) + covered / total
    end
end

-- ---------------------------------------------------------------------------
-- Roster -> resolved rows -> sorted -> drawn (non-secure mode)
-- ---------------------------------------------------------------------------
local rowData = {}
local personalRows = {}   -- resolved elemental / My Shields rows, both boards
local testRows = {}
local rosterUnits = {}

local function BuildRoster(out)
    wipe(out)
    local seen = {}
    local function add(unit)
        if not UnitExists(unit) then return end
        local guid = UnitGUID(unit)
        if not guid or seen[guid] then return end
        seen[guid] = true
        out[#out + 1] = unit
    end
    if DB("IncludeSelf", true) then add("player") end
    if DB("Scope", "PARTY") == "RAID" and IsInRaid and IsInRaid() then
        for i = 1, 40 do add("raid" .. i) end
    else
        for i = 1, 4 do add("party" .. i) end
    end
end

local function SortRows(a, b)
    local sa, sb = STATES[a.state].rank, STATES[b.state].rank
    if sa ~= sb then return sa < sb end
    local ka = a.wsLeft and a.wsLeft > 0 and a.wsLeft or (a.tLeft or math.huge)
    local kb = b.wsLeft and b.wsLeft > 0 and b.wsLeft or (b.tLeft or math.huge)
    if ka ~= kb then return ka < kb end
    return a.name < b.name
end

local function PinToTop(pred)
    for i, r in ipairs(rowData) do
        if pred(r) then
            if i > 1 then table.remove(rowData, i); table.insert(rowData, 1, r) end
            return
        end
    end
end

local function DrawHeader(now, showHeader)
    if settingsBtn then
        settingsBtn:SetShown(showHeader and DB("ShowSettingsButton", true))
    end
    if showHeader then
        if not root.header then
            root.header = root:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            root.header:SetPoint("TOPLEFT", root, "TOPLEFT", STRIPE_W + 4, -1)
            root.header:SetJustifyH("LEFT")
        end
        -- INT layer: the upkeep banner — YOUR class management as icon+text
        -- segments: armor (alarms when missing), Ice Barrier, your total
        -- shielding (or the Weakened Soul lockout), the Water Elemental,
        -- session shield uptime, and team alerts.
        if layer == "INT" then
            root.header:Hide()
            if not root.mageHdr then
                local segs, prev = {}, nil
                for i = 1, 7 do
                    local icon = root:CreateTexture(nil, "OVERLAY")
                    icon:SetSize(12, 12)
                    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    local text = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    text:SetJustifyH("LEFT")
                    if prev then
                        icon:SetPoint("LEFT", prev, "RIGHT", 8, 0)
                    else
                        icon:SetPoint("TOPLEFT", root, "TOPLEFT", STRIPE_W + 4, -1)
                    end
                    text:SetPoint("LEFT", icon, "RIGHT", 2, 0)
                    segs[i] = { icon = icon, text = text }
                    prev = text
                end
                root.mageHdr = segs
                -- The armor segment doubles as the armor-switch popout toggle
                if armorPop and not armorBtn then
                    armorBtn = CreateFrame("Button", nil, root)
                    armorBtn:SetSize(16, 16)
                    armorBtn:SetPoint("CENTER", segs[1].icon, "CENTER", 0, 0)
                    armorBtn:SetScript("OnClick", function()
                        armorPop:SetShown(not armorPop:IsShown())
                    end)
                    armorBtn:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
                        GameTooltip:SetText("Armor")
                        GameTooltip:AddLine("Click to switch armors", 0.8, 0.8, 0.8)
                        GameTooltip:Show()
                    end)
                    armorBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                end
            end
            if mageUtil then mageUtil:Show() end
            if armorBtn then armorBtn:Show() end
            local segs = root.mageHdr
            local n = 0
            local function seg(icon, desat, text)
                n = n + 1
                local s = segs[n]
                if not s then return end
                s.icon:SetTexture(icon)
                if s.icon.SetDesaturated then s.icon:SetDesaturated(desat or false) end
                s.icon:SetAlpha(desat and 0.5 or 1)
                s.text:SetText(text or "")
                s.icon:Show()
                s.text:Show()
            end
            -- 1) Armor upkeep: time left, amber when closing, loud when naked
            local armorLeft = selfArmor and selfArmor.expire and selfArmor.expire > 0
                and (selfArmor.expire - now) or nil
            if selfArmor and (not armorLeft or armorLeft > 0) then
                local t = armorLeft and FormatLong(armorLeft) or ""
                if armorLeft and armorLeft <= 300 then t = "|cffffa64d" .. t .. "|r" end
                seg(selfArmor.icon, false, t)
            else
                seg("Interface\\Icons\\Spell_Frost_FrostArmor02", true, "|cffff4040OFF|r")
            end
            -- 2) Session shield uptime — the live shield tracking itself
            -- (Barrier state, absorb totals) lives on the My Shields rows now
            if DB("TrackUptime", false) and uptime and (uptime.coverageSamples or 0) > 0 then
                seg("Interface\\Icons\\Spell_Shadow_DetectLesserInvisibility", false,
                    string.format("%d%%", math.floor(uptime.coverageSum / uptime.coverageSamples * 100 + 0.5)))
            end
            -- 3) Team alerts: curses you can remove, teammates in CC
            if intCurses > 0 or intCCs > 0 then
                local t = ""
                if intCurses > 0 then t = string.format("|cffa64dffC%d|r", intCurses) end
                if intCCs > 0 then
                    t = t .. (t ~= "" and " " or "") .. string.format("|cffff8c26CC%d|r", intCCs)
                end
                local icon = intCurses > 0 and "Interface\\Icons\\Spell_Shadow_CurseOfTounges"
                    or "Interface\\Icons\\Spell_Nature_Polymorph"
                seg(icon, false, t)
            end
            for i = n + 1, #segs do
                segs[i].icon:Hide()
                segs[i].text:Hide()
            end
            return
        end
        local cdText = "Ready"
        if GetSpellCooldown and PWS_NAME then
            local start, duration = GetSpellCooldown(PWS_NAME)
            if start and duration and duration > 1.5 then
                local left = start + duration - now
                if left > 0 then cdText = string.format("%.1fs", left) end
            end
        end
        local text = string.format("|cff66ccffPW:S|r  CD %s   ~%d", cdText, math.floor(myShieldValue + 0.5))
        if DB("TrackUptime", false) and uptime and (uptime.coverageSamples or 0) > 0 then
            text = text .. string.format("   Up %d%%", math.floor(uptime.coverageSum / uptime.coverageSamples * 100 + 0.5))
        end
        root.header:SetText(text)
        root.header:Show()
    else
        if root.header then root.header:Hide() end
        if root.mageHdr then
            for _, s in ipairs(root.mageHdr) do s.icon:Hide(); s.text:Hide() end
        end
        -- Insecure container/toggles, so this stays legal in combat
        if mageUtil then mageUtil:Hide() end
        if armorBtn then armorBtn:Hide() end
        if armorPop then armorPop:Hide() end
    end
end

-- Count how many enemy NPCs have each board unit targeted, by walking the
-- visible enemy nameplates (the only honest source: unit tokens exist only
-- for units the client shows plates for, so coverage follows the player's
-- nameplate settings). Throttled to 4 Hz; the table is tiny and rebuilt in
-- place. Skipped during the test board so the tester's fake counts survive.
local function ScanTargeters(now)
    if not DB("ShowTargeters", true) then return end
    if testUntil > 0 then return end
    if now < nextTargeterScan then return end
    nextTargeterScan = now + 0.25
    wipe(targeters)
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    local plates = C_NamePlate.GetNamePlates()
    if not plates then return end
    for i = 1, #plates do
        local plate = plates[i]
        local unit = plate and (plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
        if unit and UnitCanAttack("player", unit) and not UnitIsPlayer(unit) then
            local tgt = unit .. "target"
            if UnitExists(tgt) then
                local guid = UnitGUID(tgt)
                if guid then
                    targeters[guid] = (targeters[guid] or 0) + 1
                end
            end
        end
    end
end

-- Drop every injected test entry from the shared state tables
local function ClearTestState()
    for _, t in ipairs({ shieldState, wsState, renewState, dispelState, intState, curseState, ccState, allyAbsorbs, specState, targeters }) do
        for guid in pairs(t) do
            if type(guid) == "string" and guid:find("^cshieldtest") then t[guid] = nil end
        end
    end
end

-- Personal rows (INT layer): the Water Elemental while it is in play, then
-- the My Shields extra. Shared by the sorted AND the Click-Cast boards.
local function AppendLivePersonalRows(now)
    if layer ~= "INT" then return end
    if UnitExists and UnitExists("pet") then
        personalRows[#personalRows + 1] = EleRow(now)
    end
    if DB("SelfShieldRows", true)
        and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then
        local alertsOnly = DB("OnlyAlerts", false)
        for _, def in ipairs(trackedSpells) do
            if SelfTrackEnabled(def) then
                local sr = SelfRow(def, now)
                if not (alertsOnly and not ALERT_STATES[sr.state]) then
                    personalRows[#personalRows + 1] = sr
                end
            end
        end
    end
end

local function PaintPersonalRows(now, baseIndex, topOffset, grow, width, sig)
    for i = 1, #personalRows do
        local row = AcquirePersonalRow(i)
        if row._sig ~= sig then LayoutRow(row, width, sig) end
        PositionRow(row, baseIndex + i, topOffset, grow)
        local r = personalRows[i]
        CheckExposeAlert(r, baseIndex + i, now)
        PaintRow(row, r, now, baseIndex + i)
        row:Show()
    end
    for i = #personalRows + 1, #personalPool do personalPool[i]:Hide() end
end

local function Draw()
    local now = GetTime()
    ScanTargeters(now)
    -- INT header tallies rebuild as this pass resolves rows
    if layer == "INT" then intCurses, intCCs = 0, 0 end
    local showHeader = DB("ShowHeader", true)
    local topOffset = showHeader and HEADER_H or 0
    local grow = DB("Grow", "DOWN")
    local width = FrameWidth()
    local sig = LayoutSig(width)

    -- Combat-only visibility applies to both modes (root is not a secure frame)
    local combatHidden = DB("CombatOnly", false) and not InCombat()
        and not Commander.UI.HudUnlocked(CommanderPartyFramesDB, "Hud")

    -- Test board upkeep
    if testUntil > 0 and now > testUntil then
        testUntil = 0
        wipe(testRows)
        ClearTestState()
    end

    -- ---- Secure mode: fixed token rows, visuals only in combat ----
    if securePool and testUntil == 0 then
        if secureDirty and not InCombat() then SetupSecureRows() end
        for i, token in ipairs(secureTokens) do
            local row = rowPool[i]
            if row then
                local r = UnitExists(token) and ResolveRow(token, now) or { state = "EMPTY" }
                if r.guid then CheckExposeAlert(r, i, now) end
                PaintRow(row, r, now, i)
            end
        end
        -- Personal rows ride below the secure block from their own insecure
        -- pool — Click-Cast must not cost the mage their own rows
        wipe(personalRows)
        AppendLivePersonalRows(now)
        PaintPersonalRows(now, #secureTokens, topOffset, grow, width, sig)
        DrawHeader(now, showHeader)
        -- Root resizes for personal rows out of combat only (protected rows
        -- anchor to it; not worth the mid-combat taint risk)
        if not InCombat() then
            local slots = (DB("FixedHeight", false) and DB("MaxRows", 6)
                or math.max(#secureTokens, 1)) + #personalRows
            root:SetSize(width, topOffset + math.max(slots * (ROW_H + ROW_GAP) - ROW_GAP, ROW_H))
        end
        root:SetShown(not combatHidden and (#secureTokens > 0 or #personalRows > 0
            or DB("AlwaysShow", false)
            or Commander.UI.HudUnlocked(CommanderPartyFramesDB, "Hud")))
        return
    end

    -- ---- Non-secure mode: dynamic urgency-sorted rows ----
    wipe(rowData)
    if testUntil > 0 then
        for _, tr in ipairs(testRows) do
            if tr.eleRow then
                -- Prebuilt static sample (the elemental row resolves nothing)
                rowData[#rowData + 1] = tr
            else
                local r = { guid = tr.guid, name = tr.name, class = tr.class, isSelf = tr.isSelf, unit = tr.unit,
                    selfSpell = tr.selfSpell, icon = tr.icon, duration = tr.duration, lockMax = tr.lockMax,
                    dispelKey = tr.dispelKey, tgtKey = tr.tgtKey, manaUser = tr.manaUser, mana = tr.mana }
                r.health = tr.health
                r.hpMax = tr.hpMax
                ResolveState(r, now)
                rowData[#rowData + 1] = r
            end
        end
    else
        BuildRoster(rosterUnits)
        for _, unit in ipairs(rosterUnits) do
            local r = ResolveRow(unit, now)
            if r then rowData[#rowData + 1] = r end
        end
    end

    if DB("OnlyAlerts", false) then
        for i = #rowData, 1, -1 do
            local r = rowData[i]
            if not ALERT_STATES[r.state] and not r.isSelf then table.remove(rowData, i) end
        end
    end

    table.sort(rowData, SortRows)
    if DB("PinFocus", false) and UnitExists("focus") then
        local fg = UnitGUID("focus")
        if fg then PinToTop(function(r) return r.guid == fg end) end
    end
    if DB("SelfFirst", false) then PinToTop(function(r) return r.isSelf end) end

    -- Personal rows live in their own list and pool: test rows built as such
    -- pull out of the sorted list here, live ones generate fresh. Max Rows
    -- then bounds only the ALLY board — a full raid can never push YOUR rows
    -- off the frame.
    wipe(personalRows)
    for i = #rowData, 1, -1 do
        local r = rowData[i]
        if r.selfSpell or r.eleRow then
            table.insert(personalRows, 1, table.remove(rowData, i))
        end
    end
    if testUntil == 0 then AppendLivePersonalRows(now) end

    local maxRows = DB("MaxRows", 6)
    for i = #rowData, maxRows + 1, -1 do rowData[i] = nil end

    local shown = #rowData
    for i = 1, shown do
        local row = AcquireRow(i)
        if row._sig ~= sig then LayoutRow(row, width, sig) end
        PositionRow(row, i, topOffset, grow)
        local r = rowData[i]
        CheckExposeAlert(r, i, now)
        PaintRow(row, r, now, i)
        row:Show()
    end
    for i = shown + 1, #rowPool do rowPool[i]:Hide() end
    PaintPersonalRows(now, shown, topOffset, grow, width, sig)

    DrawHeader(now, showHeader)

    local totalRows = shown + #personalRows
    local slots = DB("FixedHeight", false) and (maxRows + #personalRows) or math.max(totalRows, 1)
    local bodyH = slots * (ROW_H + ROW_GAP) - ROW_GAP
    root:SetSize(width, topOffset + math.max(bodyH, ROW_H))
    root:SetShown(not combatHidden and (totalRows > 0 or DB("AlwaysShow", false)
        or Commander.UI.HudUnlocked(CommanderPartyFramesDB, "Hud")))
end

-- ---------------------------------------------------------------------------
-- Test board (non-secure preview): one row in every state.
-- ---------------------------------------------------------------------------
function CommanderPartyFrames_Test()
    if not profile then
        print("Commander Party Frames: no shield profile for this class (boards exist for Priests and Mages)")
        return
    end
    if not (CommanderPartyFramesDB and CommanderPartyFramesDB.EnableShield) then
        print("Commander Party Frames: module is disabled (enable it in settings or /cpf)")
        return
    end
    local now = GetTime()
    testUntil = now + 30
    ClearTestState()
    wipe(testRows)

    -- INT layer (Mage): a party in every state — buffed, rebuff window,
    -- cursed, unbuffed, a non-mana ally (pure chassis row), you — plus
    -- self-shield sample rows when that extra is switched on.
    if layer == "INT" then
        intState["cshieldtest1"] = { expire = now + 1500, duration = 1800 }  -- healthy
        intState["cshieldtest2"] = { expire = now + 150, duration = 1800 }   -- amber: rebuff due
        intState["cshieldtest3"] = { expire = now + 900, duration = 1800 }   -- buffed but cursed
        curseState["cshieldtest3"] = { expire = now + 18, duration = 30 }
        dispelState["cshieldtest3"] = { n = 1,   -- strip preview (when it is on)
            { icon = "Interface\\Icons\\Spell_Shadow_CurseOfTounges", name = "Test Curse",
              dispelName = "Curse", expire = now + 18, duration = 30, cc = false, canDispel = true },
        }
        -- Aggregate shielding samples (real localized names so the embedded
        -- palette applies): a priest bubble, and a mage stacking Ice Barrier
        -- over Mana Shield — both segments ride that row's health bar
        local pwsN = PWS_NAME or "Power Word: Shield"
        local ibN = (GetSpellInfo and GetSpellInfo(11426)) or "Ice Barrier"
        local msN = (GetSpellInfo and GetSpellInfo(1463)) or "Mana Shield"
        allyAbsorbs["cshieldtest2"] = {
            [pwsN] = { expire = now + 22, duration = 30, capacity = 1265,
              absorbed = 315, icon = "Interface\\Icons\\Spell_Holy_PowerWordShield" },
        }
        allyAbsorbs["cshieldtest1"] = {
            [ibN] = { expire = now + 40, duration = 60, capacity = 1075,
              absorbed = 200, icon = "Interface\\Icons\\Spell_Ice_Lament" },
            [msN] = { expire = now + 30, duration = 60, capacity = 710,
              absorbed = 0, icon = "Interface\\Icons\\Spell_Shadow_DetectLesserInvisibility" },
        }
        -- A sheeped teammate: the loud CCED row
        ccState["cshieldtest4"] = { expire = now + 7, duration = 10, name = "Test Polymorph",
            icon = "Interface\\Icons\\Spell_Nature_Polymorph" }
        targeters["cshieldtest5"] = 2
        -- Learned specs, so the Specialization display modes preview
        specState["cshieldtest1"] = "FROST"
        specState["cshieldtest2"] = "DISC"
        specState["cshieldtest3"] = "RESTORATION"
        specState["cshieldtest5"] = "PROTECTION"
        testRows = {
            { guid = "cshieldtest1", name = "Mage2", class = "MAGE", manaUser = true, health = 0.9, mana = 0.55, hpMax = 3800 },
            { guid = "cshieldtest2", name = "Priest", class = "PRIEST", manaUser = true, health = 0.85, mana = 0.7, hpMax = 4100 },
            { guid = "cshieldtest3", name = "Druid", class = "DRUID", manaUser = true, health = 0.6, mana = 0.4, hpMax = 4600 },
            { guid = "cshieldtest4", name = "Pally", class = "PALADIN", manaUser = true, health = 1.0, mana = 0.92, hpMax = 5200 },
            { guid = "cshieldtest5", name = "Tank", class = "WARRIOR", health = 0.42, hpMax = 6200 },
            { guid = "cshieldtest6", name = "You", class = playerClass, isSelf = true, manaUser = true, health = 0.75, mana = 0.8, hpMax = 4000 },
        }
        if DB("SelfShieldRows", true) then
            local defs = {}
            for _, def in ipairs(SDATA.MAGE_SPELLS) do defs[def.key] = def end
            shieldState["cshieldtestB"] = { spellId = 33405, expire = now + 42, mine = true,
                absorbed = 260, capacity = 1075, duration = 60 }
            wsState["cshieldtestB"] = now + 14      -- Barrier up, cooldown draining
            wsState["cshieldtestW"] = now + 9        -- Fire Ward down, on cooldown
            testRows[#testRows + 1] = { guid = "cshieldtestB", name = defs.BARRIER.label,
                class = playerClass, isSelf = true, selfSpell = true, icon = defs.BARRIER.icon,
                duration = 60, lockMax = 30 }
            testRows[#testRows + 1] = { guid = "cshieldtestW", name = defs.FWARD.label,
                class = playerClass, isSelf = true, selfSpell = true, icon = defs.FWARD.icon,
                duration = 30, lockMax = 30 }
        end
        -- Elemental sample row: portrait slot, lifespan bar with the gold
        -- double-Freeze tick, health underlay, Freeze mid-cooldown
        testRows[#testRows + 1] = { guid = "cshieldtestE", name = "Elemental",
            class = playerClass, isSelf = true, selfSpell = true, eleRow = true,
            icon = eleIcon or "Interface\\Icons\\Spell_Frost_SummonWaterElemental_2",
            state = "SHIELDED", ratio = 0.7, rightText = "31s", mainText = "",
            eleHealth = 0.85, freezeMark = 25 / 45, eleUrgent = false,
            freezeCd = 9, freezeDur = 25, freezeStart = now - 16 }
        Draw()
        print("Commander Party Frames: test board injected — rows drain and clear themselves")
        return
    end

    -- Fake targeted-by counts so the counter can be judged from the tester
    -- (ScanTargeters pauses while the test board is live)
    targeters["cshieldtest1"] = 3
    targeters["cshieldtest2"] = 1
    targeters["cshieldtest4"] = 2
    -- Learned specs for the Specialization display modes
    specState["cshieldtest1"] = "PROTECTION"
    specState["cshieldtest2"] = "SUBTLETY"
    specState["cshieldtest3"] = "FROST"
    specState["cshieldtest4"] = "RESTORATION"

    local cap = myShieldValue > 0 and myShieldValue or 1265
    shieldState["cshieldtest1"] = { spellId = 25218, expire = now + 24, mine = true, absorbed = cap * 0.1, capacity = cap }
    wsState["cshieldtest1"] = now + 9
    shieldState["cshieldtest2"] = { spellId = 25218, expire = now + 18, mine = true, absorbed = cap * 0.85, capacity = cap }
    shieldState["cshieldtest3"] = { spellId = 25218, expire = now + 12, mine = true, absorbed = cap * 0.9, capacity = cap }
    wsState["cshieldtest3"] = now + 6
    shieldState["cshieldtest4"] = { spellId = 25218, expire = now + 20, mine = false, absorbed = 0, capacity = nil }
    wsState["cshieldtest4"] = now + 11
    wsState["cshieldtest5"] = now + 7
    -- Embedded-segment mirrors of the shields above (real localized names so
    -- the palette applies), plus the mage's own Ice Barrier stacked on top
    local ibName = (GetSpellInfo and GetSpellInfo(11426)) or "Ice Barrier"
    allyAbsorbs["cshieldtest1"] = { [PWS_NAME or "Power Word: Shield"] =
        { expire = now + 24, duration = 30, capacity = cap, absorbed = cap * 0.1 } }
    allyAbsorbs["cshieldtest2"] = { [PWS_NAME or "Power Word: Shield"] =
        { expire = now + 18, duration = 30, capacity = cap, absorbed = cap * 0.85 } }
    allyAbsorbs["cshieldtest3"] = {
        [PWS_NAME or "Power Word: Shield"] = { expire = now + 12, duration = 30, capacity = cap, absorbed = cap * 0.9 },
        [ibName] = { expire = now + 35, duration = 60, capacity = 1075, absorbed = 150 },
    }
    allyAbsorbs["cshieldtest4"] = { [PWS_NAME or "Power Word: Shield"] =
        { expire = now + 20, duration = 30, capacity = cap, absorbed = cap * 0.4 } }
    -- Renew samples (shown when Track Renew is on): healthy, expiring, missing
    renewState["cshieldtest1"] = now + 12
    renewState["cshieldtest2"] = now + 3
    renewState["cshieldtest4"] = now + 9
    renewState["cshieldtest6"] = now + 7
    -- Dispellable-debuff samples (shown when the strip is on); the Polymorph and
    -- Fear entries are flagged CC so the glow can be previewed
    dispelState["cshieldtest1"] = { n = 3,
        { icon = "Interface\\Icons\\Ability_Warrior_SavageBlow", name = "Test Mortal Strike",
          expire = now + 8, duration = 10, cc = false, canDispel = false, important = "HEAL" },
        { icon = "Interface\\Icons\\Spell_Shadow_CurseOfTounges", name = "Test Curse",
          dispelName = "Curse", expire = now + 18, duration = 30, cc = false, canDispel = true },
        { icon = "Interface\\Icons\\Spell_Nature_NullifyDisease", name = "Test Disease",
          dispelName = "Disease", expire = now + 9, duration = 20, cc = false, canDispel = true },
    }
    dispelState["cshieldtest2"] = { n = 1,
        { icon = "Interface\\Icons\\Spell_Nature_Polymorph", name = "Test Polymorph",
          dispelName = "Magic", expire = now + 12, duration = 20, cc = true, canDispel = true },
    }
    dispelState["cshieldtest4"] = { n = 1,
        { icon = "Interface\\Icons\\Spell_Shadow_Possession", name = "Test Fear",
          dispelName = "Magic", expire = now + 7, duration = 15, cc = true, canDispel = true },
    }
    dispelState["cshieldtest5"] = { n = 1,   -- undispellable CC (orange rim, glows)
        { icon = "Interface\\Icons\\Spell_Shadow_MindSteal", name = "Test Blind",
          expire = now + 6, duration = 10, cc = true, canDispel = false, important = "CC" },
    }

    testRows = {
        { guid = "cshieldtest1", name = "Tank", class = "WARRIOR", health = 0.42, hpMax = 6200 },
        { guid = "cshieldtest2", name = "Rogue", class = "ROGUE", health = 0.78, hpMax = 4300 },
        { guid = "cshieldtest3", name = "Mage", class = "MAGE", health = 1.0, hpMax = 3800 },  -- full: shields extend the scale
        { guid = "cshieldtest4", name = "Druid", class = "DRUID", health = 0.6, hpMax = 4600 },
        { guid = "cshieldtest5", name = "Hunter", class = "HUNTER", health = 0.9, hpMax = 4800 },
        { guid = "cshieldtest6", name = "You", class = select(2, UnitClass("player")), isSelf = true, health = 0.85, hpMax = 4000 },
    }
    Draw()
    print("Commander Party Frames: test board injected — rows drain and clear themselves")
end

-- Live-state diagnostic (/cpf debug): why rows are or aren't appearing
function CommanderPartyFrames_Debug()
    local bookN = 0
    for _ in pairs(knownSpells) do bookN = bookN + 1 end
    print(string.format(
        "|cff66ccffCPF debug|r: layer=%s  enabled=%s  selfRows=%s  spellbook=%d names  tracked=%d",
        tostring(layer),
        tostring(CommanderPartyFramesDB and CommanderPartyFramesDB.EnableShield),
        tostring(DB("SelfShieldRows", true)), bookN, #trackedSpells))
    for _, def in ipairs(trackedSpells) do
        print(string.format("  tracked: %s (nominal %d)", def.name or def.key, def.nominal or 0))
    end
    if layer == "INT" then
        print(string.format("  barrier=%s  elemental=%s  armor=%s",
            tostring(barrierDef and barrierDef.name or "unknown"),
            tostring(eleKnown), tostring(selfArmor and "up" or "none/unseen")))
    end
    local bookNames = 0
    for _ in pairs(abilityByName) do bookNames = bookNames + 1 end
    local watched = 0
    for guid, st in pairs(abilityState) do
        for _, cdEnd in pairs(st) do
            if cdEnd > GetTime() then watched = watched + 1 end
        end
    end
    print(string.format("  abilityBook=%d names  cooldownsRunning=%d", bookNames, watched))
end

-- Session shield-coverage report (/cpf report)
function CommanderPartyFrames_Report()
    if not uptime then print("Commander Party Frames: uptime tracking not started."); return end
    local samples = uptime.coverageSamples or 0
    local pct = samples > 0 and (uptime.coverageSum / samples * 100) or 0
    local dur = uptime.startedAt and (time() - uptime.startedAt) or 0
    local mins = math.floor(dur / 60)
    print(string.format("|cff66ccffCommander Party Frames|r: session shield uptime |cff33ff33%d%%|r over %dm%02ds — %d shields cast.",
        math.floor(pct + 0.5), mins, dur - mins * 60, uptime.shieldsCast or 0))
end

-- The ticker rides its own always-shown frame, NOT root: a board hidden by
-- Only Show Alerts must still notice absorb- and clock-driven transitions —
-- a shield chewed low by SPELL_ABSORBED fires no aura event, and "expiring
-- soon" is pure clock — so it can reappear the moment a row turns urgent.
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(self, elapsed)
    if not (profile and CommanderPartyFramesDB and CommanderPartyFramesDB.EnableShield) then return end
    sinceDraw = sinceDraw + elapsed
    if sinceDraw >= DRAW_THROTTLE then sinceDraw = 0; Draw() end
    sinceSample = sinceSample + elapsed
    if sinceSample >= UPTIME_SAMPLE then sinceSample = 0; SampleUptime(GetTime()) end
end)

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
local function Apply()
    if profile and CommanderPartyFramesDB and CommanderPartyFramesDB.EnableShield then
        if not DB("RenewTrack", false) then wipe(renewState) end
        if not DB("ShowDispels", false) then wipe(dispelState) end
        if not DB("ShowTargeters", true) then wipe(targeters) end
        Commander.UI.ApplyHudChrome(root, CommanderPartyFramesDB, "Hud", {
            title = "Party",
            defaultPoint = { point = "LEFT", x = 14, y = 40 },
        })
        -- Toggling Click-Cast changes the row frame type, which cannot be
        -- swapped live — ask for a reload if it differs from what we built.
        if securePool ~= (DB("ClickCast", false) and true or false) then
            print("|cff66ccffCommander Party Frames|r: Click-Cast change takes effect after |cffffd100/reload|r.")
        end
        UpdateMyShieldValue()
        if layer == "INT" then
            -- Always scanned (not just when the rows are on): the upkeep
            -- banner's Barrier segment reads the same state
            ResolveTrackedSpells()
            ScanSelfShields()
        end
        ScanGroup()
        if securePool then SetupSecureRows() end
        Draw()
    else
        wipe(shieldState)
        wipe(wsState)
        wipe(renewState)
        wipe(dispelState)
        wipe(intState)
        wipe(curseState)
        wipe(ccState)
        wipe(allyAbsorbs)
        root:Hide()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_FOCUS_CHANGED")
events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
events:RegisterEvent("UNIT_PET")
pcall(events.RegisterEvent, events, "BAG_UPDATE_DELAYED")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player")
        PWS_NAME = (GetSpellInfo and GetSpellInfo(17)) or "Power Word: Shield"
        WS_NAME = (GetSpellInfo and GetSpellInfo(6788)) or "Weakened Soul"
        RENEW_NAME = (GetSpellInfo and GetSpellInfo(139)) or "Renew"
        AI_NAME = (GetSpellInfo and GetSpellInfo(SDATA.AI_ID)) or "Arcane Intellect"
        BRILLIANCE_NAME = (GetSpellInfo and GetSpellInfo(SDATA.BRILLIANCE_ID)) or "Arcane Brilliance"
        -- Which layer (if any) this class gets, what we can dispel, and the
        -- CC names worth glowing
        local _, classToken = UnitClass("player")
        playerClass = classToken
        profile = CLASS_PROFILES[classToken or ""]
        layer = profile and profile.layer or nil
        myDispelTypes = DISPEL_BY_CLASS[classToken or ""] or {}
        RefreshKnownSpells()
        EnsureSettingsButton()
        -- Armor names/icons for the upkeep banner (INT layer only)
        if layer == "INT" and GetSpellInfo then
            for _, line in ipairs(SDATA.ARMOR_LINES) do
                for _, id in ipairs(line.ids) do
                    local n, _, icon = GetSpellInfo(id)
                    if n and not armorNames[n] then
                        armorNames[n] = icon or "Interface\\Icons\\Spell_Frost_FrostArmor02"
                    end
                end
            end
            ResolveEleInfo()
            EnsureMageUtilButtons()
        end
        -- Absorb name set + embedded-segment tints/order (both layers).
        -- Devin's palette: cream PW:S, vibrant light-blue Barrier, muted
        -- blue-grey Mana Shield, per-school ward tints, dark-grey Sacrifice.
        if GetSpellInfo then
            local function RegisterAbsorb(id, order, color)
                local n = GetSpellInfo(id)
                if n then
                    absorbNames[n] = true
                    SDATA.SHIELD_ORDER[n] = order
                    SDATA.SHIELD_COLORS[n] = color
                end
            end
            RegisterAbsorb(17, 1, { 0.93, 0.90, 0.82 })     -- PW:S: light cream grey
            RegisterAbsorb(11426, 2, { 0.40, 0.78, 1.00 })  -- Ice Barrier: vibrant light blue
            RegisterAbsorb(1463, 3, { 0.55, 0.62, 0.74 })   -- Mana Shield: muted soft blue-grey
            RegisterAbsorb(543, 4, { 0.95, 0.55, 0.30 })    -- Fire Ward: soft ember
            RegisterAbsorb(6143, 5, { 0.62, 0.84, 0.95 })   -- Frost Ward: pale ice
            RegisterAbsorb(SDATA.SAC_ID, 6, { 0.42, 0.42, 0.46 }) -- Sacrifice: slight dark grey
            -- Spec-marker names (chassis: both layers drive spec displays)
            for id, spec in pairs(SDATA.SPEC_MARKER_IDS) do
                local n = GetSpellInfo(id)
                if n then specMarkerNames[n] = spec end
            end
            -- The ability book (party ability bar) resolves alongside
            ResolveAbilityBook()
        end
        if GetSpellInfo then
            for _, id in ipairs(CC_SPELL_IDS) do
                local n = GetSpellInfo(id)
                if n then ccNames[n] = true end
            end
            for id, category in pairs(IMPORTANT_IDS) do
                local n = GetSpellInfo(id)
                if n then
                    importantNames[n] = category
                    if category == "CC" then ccNames[n] = true end
                end
            end
        end
        securePool = DB("ClickCast", false) and true or false
        if layer == "INT" then ResolveTrackedSpells() end
        if Commander.RestoreSession then
            uptime = Commander.RestoreSession(CommanderPartyFramesDB, { coverageSamples = 0, coverageSum = 0, shieldsCast = 0 })
            if not uptime.startedAt then uptime.startedAt = time() end
        end
        UpdateMyShieldValue()
        Commander.AddListener(COMMANDER_PARTYFRAMES_EVENTS.UPDATE, Apply)
        Apply()
        return
    end
    if not (profile and CommanderPartyFramesDB and CommanderPartyFramesDB.EnableShield) then return end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
    elseif event == "UNIT_AURA" then
        if arg1 == "player" or GROUP_UNITS[arg1] then
            ScanUnit(arg1, IsReliable(arg1))
            if arg1 == "player" and layer == "INT" then ScanSelfShields() end
            if testUntil == 0 then Draw() end
        elseif LOOK_UNITS[arg1] then
            ScanUnit(arg1, IsReliable(arg1))
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        -- Self-shield cooldowns feed the banner's Barrier segment and the
        -- opt-in rows alike
        if layer == "INT" then
            RefreshSelfCooldowns()
            if testUntil == 0 then Draw() end
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if UnitExists("target") then ScanUnit("target", IsReliable("target")); if testUntil == 0 then Draw() end end
    elseif event == "PLAYER_FOCUS_CHANGED" then
        if UnitExists("focus") then ScanUnit("focus", IsReliable("focus")) end
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        if UnitExists("mouseover") then ScanUnit("mouseover", IsReliable("mouseover")) end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        ScanGroup()
        if layer == "INT" then ScanSelfShields() end
        if securePool then SetupSecureRows() end
        if testUntil == 0 then Draw() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Left combat: safe to reconfigure secure rows/buttons queued mid-fight
        if securePool and secureDirty then SetupSecureRows() end
        if mageBtnsDirty then BindMageUtilityButtons() end
        if testUntil == 0 then Draw() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entering combat: wake a board that Combat Only kept hidden
        if testUntil == 0 then Draw() end
    elseif event == "UNIT_PET" then
        -- Elemental appearing/despawning re-draws the banner promptly
        if arg1 == "player" and layer == "INT" and testUntil == 0 then Draw() end
    elseif event == "BAG_UPDATE_DELAYED" then
        -- Conjures landed / consumables ran out: re-aim the consume button
        if layer == "INT" then BindMageUtilityButtons() end
    elseif event == "SPELLS_CHANGED" then
        RefreshKnownSpells()
        UpdateMyShieldValue()
        if layer == "INT" then
            ResolveTrackedSpells()
            ResolveEleInfo()
            BindMageUtilityButtons()
        end
    end
end)
