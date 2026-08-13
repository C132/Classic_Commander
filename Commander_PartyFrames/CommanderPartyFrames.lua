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
-- DRUID layer ("HOT"): bar = HEALTH with a mana strip under it, same chassis
--   as INT; what the row MANAGES is YOUR hots on that ally — Rejuvenation,
--   Regrowth and Lifebloom (with its stack count) as a strip of swept icons,
--   the row's number being the soonest of them to fall off. States are the
--   reshield grammar read for hots: READY (a damaged ally carrying none of
--   yours), REFRESH (one inside the refresh window — the Lifebloom about to
--   bloom is exactly this), SHIELDED (rolling). A removable debuff still
--   outranks all of it, and a druid removes TWO schools, so the row says
--   which: purple CURSED, green POISONED. The header is the druid's upkeep
--   banner: current form (red when it blocks healing), Innervate / Nature's
--   Swiftness / Rebirth / Barkskin, hot uptime, team alerts.
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
SDATA.FORBEARANCE_MAX = 60      -- Forbearance duration, the BLESS layer's drain scale
SDATA.PWS_ICON = "Interface\\Icons\\Spell_Holy_PowerWordShield"

-- IDs 17 / 6788 / 139 are stable everywhere, so the localized names resolve
-- without a locale table.
local PWS_NAME, WS_NAME              -- resolved at login
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
--   DRUID layer "HOT": your rolling hots vs removable Curses AND Poisons,
--     with Mark of the Wild riding the same upkeep slot Int does on INT.
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
-- Druid hots, in the order they ride a row's strip. `duration` is the
-- fallback scale for the radial sweep — the aura's own duration always wins;
-- it only matters for a hot seen on a unit whose aura we could not read.
-- Lifebloom is the one that STACKS, and its stack count is the whole reason
-- the strip carries a number: three stacks about to bloom is a different
-- decision from one.
-- Each hot owns a fixed slot and carries the same three facts every other
-- trackable does: a key the settings toggle by, whether it is on out of the
-- box, and whether this character has actually TRAINED it. A druid who has
-- never specced far enough for Lifebloom must not be shown a Lifebloom slot,
-- dark or otherwise — the strip is supposed to answer "what could I cast
-- here", and a spell that is not in the book is not an answer.
SDATA.DRUID_HOTS = {
    { key = "REJUV",  label = "Rejuv", baseId = 774, duration = 12, default = true,
      icon = "Interface\\Icons\\Spell_Nature_Rejuvenation" },
    { key = "REGROWTH", label = "Regrowth", baseId = 8936, duration = 21, default = true,
      icon = "Interface\\Icons\\Spell_Nature_ResistNature" },
    { key = "LIFEBLOOM", label = "Lifebloom", baseId = 33763, duration = 7, stacking = true,
      default = true, icon = "Interface\\Icons\\INV_Misc_Herb_Felblossom" },
}
for _, def in ipairs(SDATA.DRUID_HOTS) do def.dbKey = "HOT:" .. def.key end

-- Paladin Hands, in the order they ride a row's strip. They answer the same
-- question the druid's hots do — "what have I got on this ally right now" —
-- but a paladin's are EMERGENCY spells rather than upkeep. Ten seconds of
-- Freedom is the difference between a healer kiting and a healer dead, and
-- the reason the slot has to read at a glance is that you get one of these
-- every twenty-five seconds at best: the strip is not asking you to top
-- something up, it is telling you what you have already spent.
--
-- Blessing of Protection is the one that costs something. It stamps
-- Forbearance on the target for a minute, which locks out the next BoP and
-- their own Divine Shield with it — so Forbearance is this layer's drain bar,
-- exactly as Weakened Soul is the priest board's. Lay on Hands and a friendly
-- Divine Shield stamp it too, which is why the row reads the debuff itself
-- rather than remembering what it cast.
--
-- `cooldown` is the spell's own recharge. It is not the strip's clock (the
-- aura's is), but it is what turns an empty slot from an invitation into a
-- fact: a dark Freedom slot on a snared healer means something very different
-- when Freedom has eighteen seconds left on it.
SDATA.PALADIN_HANDS = {
    { key = "FREEDOM", label = "Freedom", baseId = 1044, duration = 10,
      cooldown = 25, default = true,
      icon = "Interface\\Icons\\Spell_Holy_SealOfValor" },
    { key = "BOP", label = "Protection", baseId = 1022, duration = 10,
      cooldown = 300, forbears = true, default = true,
      icon = "Interface\\Icons\\Spell_Holy_SealOfProtection" },
    { key = "SACRIFICE", label = "Sacrifice", baseId = 6940, duration = 30,
      cooldown = 120, default = true,
      icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice" },
}
for _, def in ipairs(SDATA.PALADIN_HANDS) do def.dbKey = "HAND:" .. def.key end

-- The priest's own hots. Renew is the one every priest has and the one this
-- board used to show as a lone icon bolted to the right edge of the row, with
-- its own setting, its own flash and its own refresh window — a second
-- vocabulary for exactly what the strip already says everywhere else. Prayer
-- of Mending never had a slot at all, which on a TBC arena board is a strange
-- thing to leave out.
--
-- The priest is the one strip layer whose ROW STATE is not read from here
-- (see SDATA.STRIP_STATE_LAYERS): its bar is the absorb and its lockout is
-- Weakened Soul, and no hot outranks that. So the strip is purely a readout,
-- and the per-slot refresh cue does the work the row colour does elsewhere.
SDATA.PRIEST_HOTS = {
    { key = "RENEW", label = "Renew", baseId = 139, duration = 15, default = true,
      icon = "Interface\\Icons\\Spell_Holy_Renew" },
    { key = "POM", label = "Mending", baseId = 33076, duration = 30, default = true,
      stacking = true, icon = "Interface\\Icons\\Spell_Holy_PrayerOfMendingtga" },
}
for _, def in ipairs(SDATA.PRIEST_HOTS) do def.dbKey = "PWS:" .. def.key end

-- The own-aura strip is CHASSIS, not druid code. A layer names a book of
-- auras it puts on allies and watches ours-only; the strip renders that book
-- in fixed slots with radial sweeps and stack counts. Two layers fill it so
-- far, and the shape of the entries is identical (key, label, baseId,
-- duration, default, dbKey) precisely so a third costs nothing but its data.
SDATA.STRIP_BOOKS = {
    PWS   = SDATA.PRIEST_HOTS,
    HOT   = SDATA.DRUID_HOTS,
    BLESS = SDATA.PALADIN_HANDS,
}
-- ...and the layers whose ROW STATE is read off that strip. Having a strip and
-- being driven by one are different questions: the priest board shows its
-- hots and still ranks every row by the absorb and the Weakened Soul lockout,
-- because that is what a priest is deciding between.
SDATA.STRIP_STATE_LAYERS = { HOT = true, BLESS = true }
SDATA.MAX_STRIP_ICONS = 3
SDATA.STRIP_ACTIVE = {}       -- the active book's entries, tracked AND trained

-- ---------------------------------------------------------------------------
-- The ally-buff registry: every buff a supported class maintains on OTHER
-- people, one entry each, with its own tracking toggle.
--
-- Every rank of a buff shares one localized name, so a single base ID resolves
-- the whole line — and `groupId` is the raid version, which satisfies exactly
-- the same slot (Prayer of Fortitude is Fortitude; Gift of the Wild is Mark).
-- Membership is ANY CASTER on purpose: the question a row answers is "is this
-- buff on them", not "did I put it there". That is the opposite of the hot
-- strip's ours-only rule, and for the same reason — another druid's Rejuv does
-- not stop your global, but their Mark absolutely stops you recasting.
--
--   targets   who the buff is even FOR. "MANA" entries never take a slot on a
--             rogue, so the strip does not nag about Intellect on a warrior.
--   duration  fallback sweep scale only; the aura's own duration always wins.
--   default   tracked out of the box. The always-cast raid buffs are on; the
--             situational ones (Shadow Protection, Amplify, Dampen) are off,
--             because a slot that is dark on every row all match is width the
--             health bar wants back.
--   advise    which urgency rule the slot asks when it is missing (see
--             SDATA.BUFF_ADVICE) — the difference between "not there" and
--             "not there and that is costing you the game".
-- ---------------------------------------------------------------------------
-- The pool's ceiling, not a budget: a priest can now track five ally buffs at
-- once if they want to, and the row simply gets wider. Slots past what the
-- settings ask for are never laid out, so this costs nothing when unused.
SDATA.MAX_BUFF_SLOTS = 6
SDATA.CLASS_BUFFS = {
    PWS = {
        { key = "FORT", label = "Fortitude", id = 1243, groupId = 21562,
          duration = 1800, targets = "ALL", default = true, advise = "ALWAYS",
          icon = "Interface\\Icons\\Spell_Holy_WordFortitude" },
        { key = "SPIRIT", label = "Spirit", id = 14752, groupId = 27681,
          duration = 1800, targets = "MANA", default = true, advise = "ALWAYS",
          icon = "Interface\\Icons\\Spell_Holy_DivineSpirit" },
        { key = "SHADOWPROT", label = "Shadow Prot.", id = 976, groupId = 27683,
          duration = 600, targets = "ALL", default = false, advise = "VS_SHADOW",
          icon = "Interface\\Icons\\Spell_Shadow_AntiShadow" },
        -- Fear Ward is a race-gated arena cooldown (dwarf and draenei only),
        -- which is exactly why it is worth a slot when you HAVE it: one
        -- pre-warded healer is the difference in a fear comp. Untrained on
        -- everyone else, so the known gate keeps it off their boards.
        { key = "FEARWARD", label = "Fear Ward", id = 6346, duration = 600,
          targets = "ALL", default = false, advise = "VS_FEAR",
          icon = "Interface\\Icons\\Spell_Holy_Excorcism" },
        { key = "POM", label = "Mending", id = 33076, duration = 30,
          targets = "ALL", default = false, advise = "ALWAYS",
          icon = "Interface\\Icons\\Spell_Holy_PrayerOfMendingtga" },
    },
    INT = {
        { key = "AI", label = "Intellect", id = 1459, groupId = 23028,
          duration = 1800, targets = "MANA", default = true, advise = "ALWAYS",
          icon = "Interface\\Icons\\Spell_Holy_MagicalSentry" },
        -- The two halves of one decision: they overwrite each other on the
        -- target, so whichever is up makes the other's absence CORRECT rather
        -- than a mistake, and neither may nag while its sibling is doing the
        -- job. `excludes` is what tells the advisor that.
        { key = "AMP", label = "Amplify", id = 1008, duration = 600,
          targets = "ALL", default = false, advise = "VS_PHYSICAL",
          excludes = "DAMPEN",
          icon = "Interface\\Icons\\Spell_Holy_FlashHeal" },
        { key = "DAMPEN", label = "Dampen", id = 604, duration = 600,
          targets = "ALL", default = false, advise = "VS_CASTER",
          excludes = "AMP",
          icon = "Interface\\Icons\\Spell_Nature_AbolishMagic" },
        -- Castable on others and occasionally match-relevant, but never
        -- something a slot should nag about: no advice rule, so it can be
        -- watched without ever going red.
        { key = "SLOWFALL", label = "Slow Fall", id = 130, duration = 30,
          targets = "ALL", default = false,
          icon = "Interface\\Icons\\Spell_Magic_FeatherFall" },
    },
    HOT = {
        { key = "MOTW", label = "Mark", id = 1126, groupId = 21849,
          duration = 1800, targets = "ALL", default = true, advise = "ALWAYS",
          icon = "Interface\\Icons\\Spell_Nature_Regeneration" },
        { key = "THORNS", label = "Thorns", id = 467, duration = 600,
          targets = "ALL", default = true, advise = "VS_MELEE",
          icon = "Interface\\Icons\\Spell_Nature_Thorns" },
        -- Innervate is a cooldown you spend ON somebody, and knowing whether
        -- it is currently riding a teammate is a real question. No advice
        -- rule: a slot that reddens because nobody has your six-minute
        -- cooldown on them right now would be lying.
        { key = "INNERVATE", label = "Innervate", id = 29166, duration = 20,
          targets = "MANA", default = false,
          icon = "Interface\\Icons\\Spell_Nature_Lightning" },
        { key = "ABOLISHPOISON", label = "Abolish Poison", id = 2893, duration = 8,
          targets = "ALL", default = false,
          icon = "Interface\\Icons\\Spell_Nature_NullifyPoison" },
    },
    -- The paladin's blessings. A paladin may have exactly ONE blessing on a
    -- given target, which is what `oneOf` says: an ally already carrying your
    -- Kings is not MISSING Might, they are spent, and a slot that reddens
    -- about it is lying. That is the same superseded grammar Amplify and
    -- Dampen use (`excludes`), widened from a pair to a whole family.
    --
    -- `groupId` is the Greater version, which satisfies the slot exactly the
    -- way Prayer of Fortitude satisfies Fortitude — and is what a paladin
    -- actually presses once they have it, so a board that only knew the
    -- single would call a fully-blessed team naked.
    --
    -- Kings, Might and Wisdom are on out of the box because they are the
    -- three an arena paladin really hands out; Salvation, Sanctuary and Light
    -- are off, being either a PvE threat tool or a choice you make once per
    -- match rather than a slot you watch.
    BLESS = {
        { key = "KINGS", label = "Kings", id = 20217, groupId = 25898,
          duration = 600, targets = "ALL", default = true, advise = "ALWAYS",
          oneOf = "BLESSING", icon = "Interface\\Icons\\Spell_Magic_MageArmor" },
        -- Might is strength and it is for people who swing things. A mage's
        -- row should no more carry a dark Might slot than a rogue's should
        -- carry Intellect, which is what targets = "MELEE" buys.
        { key = "MIGHT", label = "Might", id = 19740, groupId = 25782,
          duration = 600, targets = "MELEE", default = true, advise = "ALWAYS",
          oneOf = "BLESSING", icon = "Interface\\Icons\\Spell_Holy_FistOfJustice" },
        { key = "WISDOM", label = "Wisdom", id = 19742, groupId = 25894,
          duration = 600, targets = "MANA", default = true, advise = "ALWAYS",
          oneOf = "BLESSING", icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom" },
        -- Threat management: real in a raid, close to noise in an arena. It
        -- gets a slot for the player who wants it and never an opinion.
        { key = "SALVATION", label = "Salvation", id = 1038, groupId = 25895,
          duration = 600, targets = "ALL", default = false,
          oneOf = "BLESSING", icon = "Interface\\Icons\\Spell_Holy_SealOfSalvation" },
        { key = "SANCTUARY", label = "Sanctuary", id = 20911, groupId = 25899,
          duration = 600, targets = "ALL", default = false, advise = "VS_MELEE",
          oneOf = "BLESSING", icon = "Interface\\Icons\\Spell_Nature_LightningShield" },
        { key = "LIGHT", label = "Light", id = 19977, groupId = 25890,
          duration = 600, targets = "ALL", default = false,
          oneOf = "BLESSING", icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02" },
    },
}
-- ---------------------------------------------------------------------------
-- Click bindings: the full modifier x button matrix, per talent build.
--
-- MODIFIERS. Blizzard's secure buttons build their attribute prefix in a fixed
-- order — alt, then ctrl, then shift — so "alt-ctrl-shift-type1" is the only
-- spelling the client will look up. Getting that order wrong produces a
-- binding that saves fine and silently never fires, so the canonical strings
-- live here rather than being assembled at each call site.
SDATA.CLICK_MODS = {
    { key = "",                 label = "No modifier" },
    { key = "shift-",           label = "Shift" },
    { key = "ctrl-",            label = "Ctrl" },
    { key = "alt-",             label = "Alt" },
    { key = "ctrl-shift-",      label = "Ctrl + Shift" },
    { key = "alt-shift-",       label = "Alt + Shift" },
    { key = "alt-ctrl-",        label = "Alt + Ctrl" },
    { key = "alt-ctrl-shift-",  label = "Alt + Ctrl + Shift" },
}
SDATA.CLICK_BUTTONS = {
    { key = "1", label = "Left" },
    { key = "2", label = "Right" },
    { key = "3", label = "Middle" },
    { key = "4", label = "Button 4" },
    { key = "5", label = "Button 5" },
}

-- The two bindings that are not spells. Both resolve live off the row's unit
-- token, so neither can go stale as the roster shuffles.
SDATA.CLICK_ACTIONS = {
    { value = "TARGET", label = "Target them",
      icon = "Interface\\Icons\\Ability_Hunter_SniperShot" },
    { value = "TARGETTARGET", label = "Assist (target their target)",
      icon = "Interface\\Icons\\Ability_Hunter_MasterMarksman" },
}

-- What a cell may be bound to, per layer: the spells this class actually
-- casts at a friendly unit, curated rather than scraped. A raw spellbook dump
-- would offer Fireball for a left-click on your healer, which is not a menu,
-- it is a haystack. Each entry is filtered against the spellbook at login, so
-- the picker only ever offers what this character can really cast.
SDATA.BINDABLE = {
    PWS = {
        { id = 17, group = "Absorbs" }, { id = 33076, group = "Heals" },
        { id = 2061, group = "Heals" }, { id = 2060, group = "Heals" },
        { id = 2054, group = "Heals" }, { id = 139, group = "Heals" },
        { id = 596, group = "Heals" }, { id = 34861, group = "Heals" },
        { id = 32546, group = "Heals" }, { id = 2006, group = "Utility" },
        { id = 527, group = "Dispels" }, { id = 528, group = "Dispels" },
        { id = 552, group = "Dispels" }, { id = 32375, group = "Dispels" },
        { id = 1243, group = "Buffs" }, { id = 21562, group = "Buffs" },
        { id = 14752, group = "Buffs" }, { id = 27681, group = "Buffs" },
        { id = 976, group = "Buffs" }, { id = 27683, group = "Buffs" },
        { id = 6346, group = "Buffs" }, { id = 33206, group = "Cooldowns" },
        { id = 10060, group = "Cooldowns" },
    },
    INT = {
        { id = 1459, group = "Buffs" }, { id = 23028, group = "Buffs" },
        { id = 1008, group = "Buffs" }, { id = 604, group = "Buffs" },
        { id = 130, group = "Utility" }, { id = 475, group = "Dispels" },
    },
    HOT = {
        { id = 774, group = "Hots" }, { id = 8936, group = "Hots" },
        { id = 33763, group = "Hots" }, { id = 5185, group = "Heals" },
        { id = 18562, group = "Heals" }, { id = 20484, group = "Utility" },
        { id = 1126, group = "Buffs" }, { id = 21849, group = "Buffs" },
        { id = 467, group = "Buffs" }, { id = 29166, group = "Cooldowns" },
        { id = 2782, group = "Dispels" }, { id = 2893, group = "Dispels" },
        { id = 8946, group = "Dispels" }, { id = 17116, group = "Cooldowns" },
    },
    -- The paladin's friendly-target book. Both halves of every blessing are
    -- listed because both are real keys a paladin binds: the single for the
    -- ally who just died and came back, the Greater for the pre-game pass.
    BLESS = {
        { id = 635, group = "Heals" }, { id = 19750, group = "Heals" },
        { id = 20473, group = "Heals" }, { id = 633, group = "Cooldowns" },
        { id = 1044, group = "Cooldowns" }, { id = 1022, group = "Cooldowns" },
        { id = 6940, group = "Cooldowns" }, { id = 19752, group = "Cooldowns" },
        { id = 4987, group = "Dispels" }, { id = 1152, group = "Dispels" },
        { id = 20217, group = "Buffs" }, { id = 25898, group = "Buffs" },
        { id = 19740, group = "Buffs" }, { id = 25782, group = "Buffs" },
        { id = 19742, group = "Buffs" }, { id = 25894, group = "Buffs" },
        { id = 1038, group = "Buffs" },  { id = 25895, group = "Buffs" },
        { id = 20911, group = "Buffs" }, { id = 25899, group = "Buffs" },
        { id = 19977, group = "Buffs" }, { id = 25890, group = "Buffs" },
        { id = 7328, group = "Utility" },
    },
}
SDATA.BIND_GROUPS = { "Heals", "Absorbs", "Hots", "Buffs", "Dispels", "Cooldowns", "Utility" }
SDATA.BIND_LIST = {}        -- the active layer's known bindables, resolved at login
SDATA.BOOK_LIST = {}        -- every spell in the book, deduped by name, for the picker

-- Stamped once, for every layer rather than just the active one, so the
-- settings panel can key its checkboxes without waiting for login.
for lkey, list in pairs(SDATA.CLASS_BUFFS) do
    for _, def in ipairs(list) do def.dbKey = lkey .. ":" .. def.key end
end

SDATA.BUFF_BY_NAME = {}     -- localized aura name -> def, ACTIVE layer only
SDATA.BUFF_LIST = {}        -- the active layer's defs, in strip order
SDATA.BUFF_ACTIVE = {}      -- the subset actually tracked; rebuilt on Apply
SDATA.BUFF_SIG = ""         -- layout signature for the strip's shape

-- The druid banner's cooldown segments, in banner order. Shown only for
-- spells this druid actually knows; lit = ready, desaturated + time = cooling.
SDATA.DRUID_BANNER_CDS = {
    { key = "INNERVATE", id = 29166, cd = 360, icon = "Interface\\Icons\\Spell_Nature_Lightning" },
    { key = "NS",        id = 17116, cd = 180, icon = "Interface\\Icons\\Spell_Nature_RavenForm" },
    { key = "REBIRTH",   id = 20484, cd = 1200, icon = "Interface\\Icons\\Spell_Nature_Reincarnation" },
    { key = "BARKSKIN",  id = 22812, cd = 60, icon = "Interface\\Icons\\Spell_Nature_StoneClawTotem" },
}
-- Shapeshift forms, and whether the druid can cast a HEAL while wearing one.
-- That is the banner segment's whole question: Tree of Life is a resto
-- druid's home and casts the entire hot kit, but bear/cat/travel — and
-- Moonkin, which blocks healing outright — mean the board's advice is
-- unreachable until you shift out.
SDATA.DRUID_FORMS = {
    [5487]  = { key = "BEAR",    heals = false },
    [9634]  = { key = "DIRE",    heals = false },
    [768]   = { key = "CAT",     heals = false },
    [783]   = { key = "TRAVEL",  heals = false },
    [1066]  = { key = "AQUATIC", heals = false },
    [33943] = { key = "FLIGHT",  heals = false },
    [40120] = { key = "SWIFTFLIGHT", heals = false },
    [24858] = { key = "MOONKIN", heals = false },
    [33891] = { key = "TREE",    heals = true },
}
-- ---------------------------------------------------------------------------
-- The paladin's self-upkeep, for the banner: the aura you are running and the
-- seal you are holding. Both are permanent-ish states a paladin is supposed to
-- have chosen deliberately and neither is visible anywhere else on the board,
-- which is exactly the druid form segment's job description.
--
-- Ranks are listed best-first per line, the same shape SDATA.ARMOR_LINES uses,
-- so a later aura/seal switcher can cast the top one you know. Every rank of a
-- line shares one localized name, so detection only ever needs the line — and
-- unlike the mage's armor, these names are registered ONLY for ids this
-- character actually knows. A paladin can only be running an aura they have,
-- so nothing is lost, and a rank id that turns out to be wrong can never
-- quietly map some unrelated spell's name onto an aura icon.
SDATA.PALADIN_AURAS = {
    { key = "DEVOTION",    ids = { 27149, 10293, 10292, 10291, 10290, 643, 465 } },
    { key = "RETRIBUTION", ids = { 27150, 10301, 10300, 10299, 10298, 7294 } },
    { key = "CONCENTRATION", ids = { 19746 } },
    { key = "CRUSADER",    ids = { 32223 } },
    { key = "SANCTITY",    ids = { 20218 } },
    { key = "FIRERES",     ids = { 27153, 19900, 19899, 19891 } },
    { key = "FROSTRES",    ids = { 27152, 19898, 19897, 19888 } },
    { key = "SHADOWRES",   ids = { 27151, 19896, 19895, 19876 } },
}
SDATA.PALADIN_SEALS = {
    { key = "COMMAND",      ids = { 20375 } },
    { key = "BLOOD",        ids = { 31892 } },
    { key = "VENGEANCE",    ids = { 31801 } },
    { key = "CRUSADER",     ids = { 27158, 20307, 20306, 20305, 20162, 21082 } },
    { key = "RIGHTEOUSNESS", ids = { 27155, 20293, 20292, 20291, 20290, 20289, 20288, 20287, 21084 } },
    { key = "JUSTICE",      ids = { 20164 } },
    { key = "LIGHT",        ids = { 20165 } },
    { key = "WISDOM",       ids = { 20166 } },
}
-- The paladin banner's cooldown segments, in banner order — the ones that
-- decide a game, then the Hands, whose cooldowns are the other half of what
-- the row strip shows (the strip says where a Hand IS, this says whether you
-- have one to give). Filtered at login to what this paladin actually trained,
-- so a holy paladin never sees a Repentance slot.
SDATA.PALADIN_BANNER_CDS = {
    { key = "LOH",       id = 633,   cd = 1200, icon = "Interface\\Icons\\Spell_Holy_LayOnHands" },
    { key = "BUBBLE",    id = 642,   cd = 300,  icon = "Interface\\Icons\\Spell_Holy_DivineIntervention" },
    { key = "DPROT",     id = 498,   cd = 300,  icon = "Interface\\Icons\\Spell_Holy_Restoration" },
    { key = "BOP",       id = 1022,  cd = 300,  icon = "Interface\\Icons\\Spell_Holy_SealOfProtection" },
    { key = "FREEDOM",   id = 1044,  cd = 25,   icon = "Interface\\Icons\\Spell_Holy_SealOfValor" },
    { key = "SACRIFICE", id = 6940,  cd = 120,  icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice" },
    { key = "FAVOR",     id = 20216, cd = 120,  icon = "Interface\\Icons\\Spell_Holy_Heal" },
    { key = "WINGS",     id = 31884, cd = 180,  icon = "Interface\\Icons\\Spell_Holy_AvengineWrath" },
    { key = "HOJ",       id = 853,   cd = 60,   icon = "Interface\\Icons\\Spell_Holy_SealOfMight" },
    { key = "ILLUM",     id = 31842, cd = 180,  icon = "Interface\\Icons\\Spell_Holy_DivineIllumination" },
    { key = "REPENT",    id = 20066, cd = 60,   icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing" },
}
-- Which book of banner cooldowns the active layer draws, so the segment loop
-- is one loop rather than one per class.
-- The priest banner's cooldown segments, in banner order: the two that decide
-- a game outright, then the ones you spend every fight, then the rest.
-- Filtered at login to what this priest actually trained, so a holy priest
-- never sees a Pain Suppression slot.
SDATA.PRIEST_BANNER_CDS = {
    { key = "PAINSUPP", id = 33206, cd = 120, icon = "Interface\\Icons\\Spell_Holy_PainSupression" },
    { key = "PI",       id = 10060, cd = 180, icon = "Interface\\Icons\\Spell_Holy_PowerInfusion" },
    { key = "FEARWARD", id = 6346,  cd = 180, icon = "Interface\\Icons\\Spell_Holy_Excorcism" },
    { key = "SCREAM",   id = 8122,  cd = 30,  icon = "Interface\\Icons\\Spell_Shadow_PsychicScream" },
    { key = "SILENCE",  id = 15487, cd = 45,  icon = "Interface\\Icons\\Spell_Shadow_ImpPhaseShift" },
    { key = "INNERFOCUS", id = 14751, cd = 180, icon = "Interface\\Icons\\Spell_Frost_WindWalkOn" },
    { key = "FIEND",    id = 34433, cd = 300, icon = "Interface\\Icons\\Spell_Shadow_Shadowfiend" },
    { key = "MASSDISPEL", id = 32375, cd = 15, icon = "Interface\\Icons\\Spell_Arcane_MassDispel" },
    { key = "DESPERATE", id = 19236, cd = 600, icon = "Interface\\Icons\\Spell_Holy_Restoration" },
}
-- The mage banner's cooldown segments. Ice Block and Cold Snap lead because
-- they are the two that decide whether you are alive in ten seconds; the
-- shorter ones trail, where the width truncation reaches them first.
--
-- Ice Barrier and the Water Elemental are deliberately absent: the barrier
-- already has a My Shields row carrying its real remaining absorb, and the
-- elemental has a richer personal row than a segment could ever be. A banner
-- that repeats what is two inches below it is width spent twice.
--
-- The ids and icons are the ones the party ability book already uses, which
-- is the only list in this addon that has been checked against the live
-- client rather than written from memory.
SDATA.MAGE_BANNER_CDS = {
    { key = "BLOCK",    id = 45438, cd = 300, icon = "Interface\\Icons\\Spell_Frost_Frost" },
    { key = "COLDSNAP", id = 11958, cd = 480, icon = "Interface\\Icons\\Spell_Frost_WizardMark" },
    { key = "EVOC",     id = 12051, cd = 480, icon = "Interface\\Icons\\Spell_Nature_Purge" },
    { key = "CS",       id = 2139,  cd = 24,  icon = "Interface\\Icons\\Spell_Frost_IceShock" },
    { key = "ICYVEINS", id = 12472, cd = 180, icon = "Interface\\Icons\\Spell_Frost_ColdHearted" },
    { key = "POM",      id = 12043, cd = 180, icon = "Interface\\Icons\\Spell_Nature_EnchantArmor" },
    { key = "AP",       id = 12042, cd = 180, icon = "Interface\\Icons\\Spell_Nature_Lightning" },
    { key = "COMBUST",  id = 11129, cd = 180, icon = "Interface\\Icons\\Spell_Fire_SealOfFire" },
    { key = "INVIS",    id = 66,    cd = 300, icon = "Interface\\Icons\\Ability_Mage_Invisibility" },
    { key = "NOVA",     id = 122,   cd = 25,  icon = "Interface\\Icons\\Spell_Frost_FrostNova" },
}
SDATA.BANNER_CDS = {
    PWS   = SDATA.PRIEST_BANNER_CDS,
    INT   = SDATA.MAGE_BANNER_CDS,
    HOT   = SDATA.DRUID_BANNER_CDS,
    BLESS = SDATA.PALADIN_BANNER_CDS,
}
-- Which saved-variable key each layer's banner-cooldown toggle lives under.
-- Four separate keys because the DB is account-wide and a mage turning their
-- segments off has no business turning a druid's off with them.
-- Which saved-variable key each strip layer's refresh window lives under. The
-- per-slot "about to drop" cue was reading the priest's key on every layer,
-- which left a druid and a paladin governed by a slider only a priest can see.
-- One key per layer, the same shape SDATA.BANNER_CD_KEY uses.
SDATA.STRIP_REFRESH_KEY = {
    PWS   = "RenewRefreshAt",
    HOT   = "HotRefreshAt",
    BLESS = "BlessRefreshAt",
}
SDATA.BANNER_CD_KEY = {
    PWS   = "PriestBannerCooldowns",
    INT   = "MageBannerCooldowns",
    HOT   = "HotBannerCooldowns",
    BLESS = "BlessBannerCooldowns",
}
-- Inner Fire, the priest's answer to the mage's armor: one permanent-ish self
-- buff that is always meant to be up and is the easiest thing on the board to
-- lose without noticing. Same line shape SDATA.ARMOR_LINES uses, so the same
-- scan and the same banner segment serve both.
SDATA.PRIEST_ARMOR = {
    { key = "INNERFIRE", ids = { 25431, 10952, 10951, 1006, 602, 7128, 588 } },
}

local CLASS_PROFILES = {
    PRIEST  = { layer = "PWS" },
    MAGE    = { layer = "INT", selfSpells = SDATA.MAGE_SPELLS },
    DRUID   = { layer = "HOT" },
    PALADIN = { layer = "BLESS" },
}
-- Which layers draw the party-frame chassis — health as the main bar, mana as
-- a strip beneath it, no own-status icon slot because their upkeep lives on
-- the buff strip instead. The priest board is the odd one out: its main bar is
-- an absorb, not health, so it keeps the spell-icon slot and spends no width
-- on mana. Asked by name rather than spelled out at each site, because "is
-- this a health-bar layer" is one question and it was being answered in seven
-- places.
SDATA.HEALTH_LAYERS = { INT = true, HOT = true, BLESS = true }
local profile               -- resolved at login; nil = unsupported class (module inert)
local layer                 -- the active profile's layer ("PWS" / "INT"), nil when inert
local playerClass           -- our class token, for self-row name coloring
local trackedSpells = {}    -- INT self extra: known tracked spells, in profile order
local trackedByName = {}    -- localized spell name -> tracked-spell def
local SELF_KEY = "cself"    -- shieldState/wsState key prefix for self-spell rows

-- Ally buffs are the registry's job now (see SDATA.CLASS_BUFFS above): every
-- class's, one entry each, with its own toggle and its own urgency rule.

-- Self armor (Frost/Ice/Mage/Molten Armor): the upkeep banner's first segment
-- AND the armor-switch popout. Ranks listed best-first per line; a line whose
-- superseding line is known (Frost once Ice exists) stays out of the popout.
SDATA.ARMOR_LINES = {
    { key = "MOLTEN", ids = { 30482 } },
    { key = "MAGE",   ids = { 27125, 22783, 22782, 6117 } },
    { key = "ICE",    ids = { 27124, 10220, 10219, 7320, 7302 } },
    { key = "FROST",  ids = { 7301, 7300, 168 }, supersededBy = "ICE" },
}
-- Which self-buff line book the active layer watches. The mage has four and a
-- switcher; the priest has one and no choice to make about it, and both are
-- read by the same pass and drawn by the same banner segment.
SDATA.SELF_ARMOR = {
    INT = SDATA.ARMOR_LINES,
    PWS = SDATA.PRIEST_ARMOR,
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

-- Conjured consumables, best rank first (banner conjure/consume buttons).
-- The Manna Biscuit heads BOTH lists because it is both food and drink —
-- without it there, a level-70 mage carrying only biscuits would have a
-- dead eat button now that drink and eat are separate clicks.
SDATA.CONJURED_WATER = { 30703, 8079, 8078, 8077, 3772, 2136, 2288, 5350 }
SDATA.CONJURED_FOOD  = { 30703, 22019, 22895, 8076, 8075, 1487, 1114, 1113, 5349 }
SDATA.CONJURE_WATER_ID, SDATA.CONJURE_FOOD_ID = 5504, 587
-- Mana gems, best rank first: the conjure spell and the item it makes. The
-- button mirrors the classic castsequence macro — plain click uses the best
-- gem in the bags, modifier or right-click walks a reset=10 castsequence over
-- every rank you know. Each gem is its own unique item, so the sequence is
-- what fills the bags: re-casting the top rank on a mage already holding one
-- only earns "you already have that item".
SDATA.MANA_GEMS = {
    { spell = 27101, item = 22044 },   -- Mana Emerald
    { spell = 10054, item = 8008 },    -- Mana Ruby
    { spell = 10053, item = 8007 },    -- Mana Citrine
    { spell = 3552,  item = 5513 },    -- Mana Jade
    { spell = 759,   item = 5514 },    -- Mana Agate
}
-- Teleports and portals. Both factions live in one list — IsSpellKnown
-- filters to what this mage actually has, so no faction branch is needed.
SDATA.TELEPORTS = {
    3561, 3562, 3565, 32271, 33690,    -- Stormwind, Ironforge, Darnassus, Exodar, Shattrath
    3567, 3563, 3566, 32272, 35715,    -- Orgrimmar, Undercity, Thunder Bluff, Silvermoon, Shattrath
}
SDATA.PORTALS = {
    10059, 11416, 11419, 32266, 33691,
    11417, 11418, 11420, 32267, 35717,
}
-- First Aid (every class): bandages best-first, the lockout debuff that says
-- a unit cannot be bandaged again yet, and the tradeskill middle-click opens.
-- Heavy ranks outrank their plain sibling.
SDATA.BANDAGES = { 21991, 21990, 14530, 14529, 8545, 8544,
                   6451, 6450, 3531, 3530, 2581, 1251 }
SDATA.RECENT_BANDAGE_ID = 11196    -- Recently Bandaged
SDATA.FIRST_AID_ID = 3273
local mageUtil, conjureBtn, consumeBtn, armorPop, armorBtn
local gemBtn, bandageBtn
local armorButtons = {}
-- Everything the newer banner utilities need, in ONE table: this chunk sits
-- close to Lua's 200-local cap (see the SDATA note above), so new state goes
-- in here rather than adding chunk locals.
--   gemBtn/portalBtn/bandageBtn  the secure buttons themselves
--   portalPop                    insecure popout frame (armorPop's pattern)
--   portalButtons                pooled popout children
--   counts                       cached bag tallies (water/food/gem/bandage)
local util = {
    portalButtons = {}, counts = {},
    bandageUntil = 0, bandageUnit = "player", nextBandageScan = 0,
}
local mageBtnsDirty = false     -- attribute binds queued for after combat
local settingsBtn               -- header gear opening the settings page (any class)

-- HOT layer state, in ONE table for the same reason `util` is one (Lua's
-- 200-local chunk cap — see the SDATA note above).
--   state       guid -> { [hotKey] = { expire, duration, stacks, icon } }, OURS only
--   names       localized hot name -> its SDATA.DRUID_HOTS def
--   scan        per-scan scratch, wiped per unit like scanAbsorbs
--   cds         banner cooldowns we know -> { name, icon, cd }
--   forms       localized form name -> SDATA.DRUID_FORMS entry
--   form        the form we are wearing right now (nil = caster form)
-- Ally buffs (Mark of the Wild, Thorns) are NOT here: they live on the shared
-- registry with every other class's, because they are any-caster facts while
-- `state` is ours-only — another druid's Rejuvenation does not gate your next
-- global, but their Mark absolutely means you do not recast it.
local strip = { state = {}, names = {}, scan = {}, cds = {}, forms = {}, form = nil,
                auraNames = {}, sealNames = {}, aura = nil, seal = nil }

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
-- The settings panel builds its per-buff controls from this. Pure registry
-- data, so it answers correctly before login has resolved anything.
function CommanderPartyFrames_GetBuffBook(layerKey)
    return SDATA.CLASS_BUFFS[layerKey or ""]
end

-- The hot strip's book, for the same settings grid. Flagged so the grid can
-- word its tooltip correctly: hots are YOURS-only, ally buffs are any-caster.
-- The settings grid's window onto the binding model. Kept as thin accessors
-- so the panel file never has to reach into SDATA or util directly.
function CommanderPartyFrames_GetClickMods() return SDATA.CLICK_MODS end
function CommanderPartyFrames_GetClickButtons() return SDATA.CLICK_BUTTONS end
function CommanderPartyFrames_GetClickActions() return SDATA.CLICK_ACTIONS end
function CommanderPartyFrames_GetBind(key) return util.GetBind(key) end
function CommanderPartyFrames_BindDisplay(v) return util.BindDisplay(v) end
function CommanderPartyFrames_ActiveProfile() return util.TalentProfile() end

function CommanderPartyFrames_SetBind(key, value)
    util.SetBind(key, value)
    -- Secure attributes are out-of-combat only; SetupSecureRows defers itself
    -- when it has to, so the caller does not have to care
    if CommanderPartyFrames_RebindRows then CommanderPartyFrames_RebindRows() end
end

-- Bindables grouped for the picker, so twenty priest spells arrive as five
-- readable submenus rather than one wall.
function CommanderPartyFrames_GetBindables()
    local byGroup, order = {}, {}
    for _, sp in ipairs(SDATA.BIND_LIST) do
        local g = sp.group
        if not byGroup[g] then byGroup[g] = {}; end
        byGroup[g][#byGroup[g] + 1] = sp
    end
    for _, g in ipairs(SDATA.BIND_GROUPS) do
        if byGroup[g] then order[#order + 1] = g end
    end
    return byGroup, order
end

function CommanderPartyFrames_ProfileLabel(p) return util.ProfileLabel(p) end
function CommanderPartyFrames_ListProfiles(out) return util.ListProfiles(out) end
function CommanderPartyFrames_GetSpellBook() return SDATA.BOOK_LIST end

function CommanderPartyFrames_CopyProfile(from, to)
    local ok = util.CopyProfile(from, to)
    if ok and CommanderPartyFrames_RebindRows then CommanderPartyFrames_RebindRows() end
    return ok
end

function CommanderPartyFrames_ResetProfile(p)
    util.ResetProfile(p or util.TalentProfile())
    if CommanderPartyFrames_RebindRows then CommanderPartyFrames_RebindRows() end
end

function CommanderPartyFrames_GetStripBook(layerKey)
    local book = SDATA.STRIP_BOOKS[layerKey or ""]
    if not book then return nil end
    -- Flagged so the settings grid can word its tooltip correctly: strip
    -- entries are YOURS-only, ally buffs are any-caster, and that distinction
    -- is the single most confusing thing about the two grids sharing a page.
    for _, def in ipairs(book) do def.isHot = true end
    return book
end

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

-- Icon shading. The art and the drawing are Commander_Events' (a RequiredDep,
-- so it is always loaded); what belongs here is remembering which icons were
-- styled, because half of them are built once in a constructor that never runs
-- again -- a setting changed mid-session has to reach those too.
--
-- On the table rather than as chunk locals for the same reason as everything
-- else in this file: it is close to Lua's 200-local ceiling.
util.styledIcons = {}

function util.StyleIcon(icon, round)
    if not icon then return end
    util.styledIcons[icon] = round and "ROUND" or "SQUARE"
    if Commander.DebossIcon then
        Commander.DebossIcon(icon, DB("IconRecess", "SOFT"), round)
    end
end

-- The one look every MISSING tracker wears, board-wide: the real icon, drained
-- of color and sunk dark, sitting in the slot it will occupy once the buff is
-- up. A tracker that vanishes when the thing it tracks is gone leaves a hole
-- exactly where the answer should be, and makes the row's icons shuffle every
-- time a hot ticks off — so nothing is ever absent from a strip, it is only
-- ever dark. The shape and position tell you WHICH buff; the tint tells you it
-- is not there.
SDATA.GHOST_TINT = { 0.30, 0.30, 0.34, 0.9 }

-- The advisor's louder cousin. Same dark placeholder, bled red: this buff is
-- missing AND the target's situation says a good player would have put it
-- there already. Red is reserved for that judgement — a neutral dark slot
-- means "not up", a red one means "not up and it matters right now".
SDATA.URGENT_TINT = { 0.62, 0.11, 0.13, 0.95 }

function util.UrgentIcon(icon, tex)
    if tex then icon:SetTexture(tex) end
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if icon.SetDesaturated then icon:SetDesaturated(true) end
    local u = SDATA.URGENT_TINT
    icon:SetVertexColor(u[1], u[2], u[3], u[4])
    icon:Show()
end

function util.GhostIcon(icon, tex)
    if tex then icon:SetTexture(tex) end
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if icon.SetDesaturated then icon:SetDesaturated(true) end
    local g = SDATA.GHOST_TINT
    icon:SetVertexColor(g[1], g[2], g[3], g[4])
    icon:Show()
end

function util.RestyleIcons()
    if not Commander.DebossIcon then return end
    local style = DB("IconRecess", "SOFT")
    for icon, kind in pairs(util.styledIcons) do
        Commander.DebossIcon(icon, style, kind == "ROUND")
    end
end

-- Radial timers that may wear the leading-edge spark, remembered for exactly
-- the reason above: they are built in the row constructor, so a setting
-- flipped mid-session would otherwise only reach rows nobody has built yet.
--
-- Membership is the whole point of this table, and it is deliberately narrow:
-- what is in here is how long an AURA has left -- the own-aura strip, the
-- ally-buff strip, the dispellable debuffs. The ability bar's sweeps are elsewhere and
-- stay plain: those count down a cooldown, where the only question is ready
-- or not, and six sparks orbiting under every row answer a question nobody
-- asked.
util.edgeSweeps = {}

-- Register a sweep that measures a DURATION (an aura draining) rather than a
-- COOLDOWN (an ability coming back).
--
-- The two want opposite shading, and Blizzard's Cooldown draws the cooldown
-- one: the wedge starts covering the icon and retreats as the spell becomes
-- ready, so the art brightens on its way to "usable". Point that at a buff and
-- it reads exactly backwards — the icon gets LIGHTER as the buff runs out, at
-- its brightest the instant before it falls off. SetReverse flips it, so the
-- lit art is what is LEFT and the dark wedge is what is spent: a full buff is
-- a full-color icon, an expiring one is nearly all shadow. That is the
-- direction every duration on this board reads in — hots, absorbs, debuffs and
-- the ally-buff slots alike. Real cooldowns (the ability strip, Freeze on the
-- elemental row, the armor segment) deliberately keep the stock direction.
function util.TrackSweep(cd)
    if not cd then return end
    util.edgeSweeps[cd] = true
    if cd.SetReverse then cd:SetReverse(true) end
    -- At construction as well as on Apply, so a row acquired after the toggle
    -- is born matching the board it joins
    if cd.SetDrawEdge then cd:SetDrawEdge(DB("SweepEdge", false)) end
end

-- ---------------------------------------------------------------------------
-- Ally-buff registry helpers. All on `util` rather than as chunk locals: this
-- file sits a handful of locals under Lua's 200-per-chunk ceiling (see the
-- SDATA note at the top).
-- ---------------------------------------------------------------------------
util.buffExp, util.buffDur = {}, {}   -- per-scan scratch, wiped per unit

-- What the other side is made of, refreshed by the quarter-second hostile
-- scan. `enemySeen` is how many enemies we could actually read: zero means we
-- know nothing, which is NOT the same as "no casters" and is why the physical
-- test below insists on having seen somebody.
util.enemyClasses, util.meleeOn, util.enemySeen = {}, {}, 0
util.enemyShadowUntil = 0   -- last time hostile shadow damage landed, + 60s

-- Classes that bring the damage school each situational buff answers. Priests
-- are the awkward one: a shadow priest is exactly what Shadow Protection is
-- for, a disc priest is not, so they only count once their spec has actually
-- been inferred from a cast.
SDATA.ENEMY_KINDS = {
    -- SHADOW lists only the class that is shadow by definition; the shadow
    -- PRIEST arrives through the combat log instead (see util.EnemyHas),
    -- because a disc priest is not what Shadow Protection is for and their
    -- class alone cannot tell you which one you are facing.
    SHADOW = { WARLOCK = true },
    CASTER = { MAGE = true, WARLOCK = true, PRIEST = true },
    FEAR = { WARLOCK = true, PRIEST = true, WARRIOR = true },
}

-- The queries themselves live below specState/groupGuids, which they read.

-- Is this buff tracked? An explicit per-buff toggle wins; absent falls back to
-- the registry's default, so a fresh install gets the sane set without the DB
-- carrying a row for every buff in the game.
function util.BuffTracked(def)
    local ov = CommanderPartyFramesDB and CommanderPartyFramesDB.BuffTrack
        and CommanderPartyFramesDB.BuffTrack[def.dbKey]
    if ov ~= nil then return ov end
    return def.default and true or false
end

-- Does the urgency advisor run for this slot? Same override-then-default
-- shape, under its own master switch.
function util.BuffAdvised(def)
    if not DB("BuffAdvisor", true) then return false end
    local ov = CommanderPartyFramesDB and CommanderPartyFramesDB.BuffAdvise
        and CommanderPartyFramesDB.BuffAdvise[def.dbKey]
    if ov ~= nil then return ov end
    return def.advise and true or false
end

-- Rebuild the tracked subset and the layout signature. Called from Apply, so
-- a toggle in the settings panel re-shapes every row on the next draw rather
-- than on the next reload.
function util.RefreshBuffs()
    wipe(SDATA.BUFF_ACTIVE)
    local sig = {}
    for _, def in ipairs(SDATA.BUFF_LIST) do
        -- A spell you have not trained earns no slot. A level-20 mage has no
        -- Dampen Magic, and a permanent dark reminder of a spell that is not
        -- in the book is the emptiest pixel on the board.
        if def.known and util.BuffTracked(def) then
            SDATA.BUFF_ACTIVE[#SDATA.BUFF_ACTIVE + 1] = def
            sig[#sig + 1] = def.key
        end
    end
    -- The own-aura strip answers to exactly the same two questions, whichever
    -- book the active layer put in it (druid hots, paladin Hands)
    wipe(SDATA.STRIP_ACTIVE)
    local book = SDATA.STRIP_BOOKS[layer or ""]
    if book then
        sig[#sig + 1] = "|"
        for _, def in ipairs(book) do
            if def.known and util.BuffTracked(def) then
                SDATA.STRIP_ACTIVE[#SDATA.STRIP_ACTIVE + 1] = def
                sig[#sig + 1] = def.key
            end
        end
    end
    SDATA.BUFF_SIG = table.concat(sig, ",")
end

-- util.ResolveBuffBook lives below knownSpells, whose spellbook scan it reads.
function util.RestyleSweeps()
    local edge = DB("SweepEdge", false)
    for cd in pairs(util.edgeSweeps) do
        if cd.SetDrawEdge then cd:SetDrawEdge(edge) end
    end
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
local NAME_W = 60
local SHORT_NAME_W = 44
local PAD = 6
local HEADER_H = 15
local DRAW_THROTTLE = 0.1
local UPTIME_SAMPLE = 1.0

-- Personal rows (Water Elemental, My Shields) render at half an ally row's
-- height: they are YOUR upkeep, read at a glance, and they now sit ABOVE the
-- ally board where every pixel is charged to the thing you actually heal.
-- Kept in SDATA rather than as chunk locals (see the 200-local note above).
SDATA.PERSONAL_ROW_H = 11
SDATA.PERSONAL_ICON = 10
SDATA.PERSONAL_BAR_H = 6
SDATA.PERSONAL_WS_H = 2
SDATA.PERSONAL_NAME_W = 44

-- In SDATA rather than a chunk local, like everything else here: the file is
-- close enough to Lua's 200-local ceiling that new constants pay rent
SDATA.TEXTURES = "Interface\\AddOns\\Commander_PartyFrames\\Textures\\"

-- Bar fill art. Flat is the board's own look — a solid block, which is what
-- reads fastest at a glance and stays honest at 6px. Blizzard is the unit
-- frame gloss: `UI-StatusBar` is the texture the default health bars have
-- worn since 1.0 (and the one Commander_Nameplate already draws with, so it
-- is known good on this client). Both take SetVertexColor identically, so
-- every tint the board applies survives the swap untouched.
-- The four after those are the board's own art (Harness/make_bars.py): shading
-- that runs down the bar's height and is uniform across its width, because a
-- fill is this texture SQUEEZED into the fraction of the row it has earned --
-- anything with horizontal shape would stretch differently at every health
-- value. White art throughout, so every tint still lands unchanged.
SDATA.BAR_TEXTURES = {
    FLAT = "Interface\\Buttons\\WHITE8X8",
    BLIZZARD = "Interface\\TargetingFrame\\UI-StatusBar",
    GLOSS = SDATA.TEXTURES .. "BarGloss.png",
    BEVEL = SDATA.TEXTURES .. "BarBevel.png",
    RIDGE = SDATA.TEXTURES .. "BarRidge.png",
    GLASS = SDATA.TEXTURES .. "BarGlass.png",
}

-- What the empty part of a bar is drawn with. Flat and Blizzard keep the plain
-- black wash the board has always had; the board's own styles get a groove --
-- shadow gathering under the top lip -- so an empty bar reads as a track the
-- fill runs in rather than a rectangle of nothing.
-- A track with no file of its own is the fill art washed black, which is what
-- the board has always drawn and is indistinguishable whatever art it is given
SDATA.BAR_TRACKS = {
    FLAT = { 0, 0, 0, 0.55 },
    SOCKET = { 0.38, 0.38, 0.42, 0.55, file = SDATA.TEXTURES .. "BarSocket.png" },
}
SDATA.BAR_TRACK_OF = {
    GLOSS = "SOCKET", BEVEL = "SOCKET", RIDGE = "SOCKET", GLASS = "SOCKET",
}

-- state -> { rank (sort, lower = more urgent), color (accent stripe) }
local STATES = {
    CURSED   = { rank = -2, color = { 0.65, 0.30, 0.95 } },-- INT/HOT: removable curse, decurse NOW
    POISONED = { rank = -2, color = { 0.25, 0.85, 0.35 } },-- HOT: removable poison, abolish NOW
    CCED     = { rank = -1, color = { 1.00, 0.55, 0.15 } },-- INT/HOT: teammate in crowd control
    READY    = { rank = 0, color = { 1.00, 0.90, 0.25 } }, -- no shield/hot/buff, castable NOW
    EXPOSED  = { rank = 1, color = { 0.95, 0.25, 0.25 } }, -- no shield, still lockout-bound
    REFRESH  = { rank = 2, color = { 0.35, 0.85, 1.00 } }, -- low/expiring, can recast
    FADING   = { rank = 3, color = { 1.00, 0.55, 0.15 } }, -- low/expiring, but locked
    SHIELDED = { rank = 4, color = { 0.35, 0.85, 0.40 } }, -- healthy shield/hot/buff of ours
    OTHER    = { rank = 5, color = { 0.55, 0.60, 0.78 } }, -- an ally priest's shield / no buff target
    DEAD     = { rank = 9, color = { 0.42, 0.42, 0.42 } }, -- dead / offline
    EMPTY    = { rank = 10, color = { 0, 0, 0 } },          -- an empty secure slot
    -- The other two removal schools, added when the paladin layer arrived and
    -- a Magic debuff started reading as "CURSED" on a board whose owner
    -- cannot remove a curse at all. A row's colour has to be the colour of
    -- the thing you are about to press, so each school gets its own — and
    -- they all share the CURSED rank, because "there is something on them I
    -- can take off" outranks everything else whichever school it is.
    MAGIC    = { rank = -2, color = DISPEL_COLORS.Magic },  -- PWS/BLESS: removable magic
    DISEASED = { rank = -2, color = DISPEL_COLORS.Disease },-- PWS/BLESS: removable disease
}
-- Every state that means "an ally is carrying something you can remove". One
-- table rather than four comparisons, because three separate places ask.
local DISPEL_STATES = { CURSED = true, POISONED = true, MAGIC = true, DISEASED = true }
-- What each removable school escalates to, and the word the row wears.
local DISPEL_STATE_BY_SCHOOL = {
    Curse   = { state = "CURSED",   word = "CURSED" },
    Poison  = { state = "POISONED", word = "POISON" },
    Magic   = { state = "MAGIC",    word = "MAGIC" },
    Disease = { state = "DISEASED", word = "DISEASE" },
}
-- Rows the player usually acts on; the rest are hidden by Only Show Alerts
local ALERT_STATES = { CCED = true, READY = true,
    EXPOSED = true, REFRESH = true, FADING = true }
-- The recast/act window is open (castable and wanted) in these states
local CASTABLE_STATES = { READY = true, REFRESH = true }
for k in pairs(DISPEL_STATES) do ALERT_STATES[k] = true; CASTABLE_STATES[k] = true end

-- Persistent per-unit state, keyed by GUID so every token that points at a unit
-- (party3, target, mouseover) refines one record.
local shieldState = {}   -- guid -> { spellId, expire, capacity, absorbed, mine }
local wsState = {}        -- guid -> weakened-soul expirationTime
local intState = {}       -- guid -> { expire, duration } for the layer's ally buff
local curseState = {}     -- guid -> { expire, duration, dispelName } first removable debuff
local ccState = {}        -- guid -> { expire, duration, icon, name } first CC debuff
-- Live header tallies for the buff layers (INT/HOT), rebuilt every draw pass
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
function util.EnemyHas(kind)
    -- Shadow has a second, better witness than anybody's class: damage of that
    -- school actually landing. It catches the shadow priest a class read
    -- cannot tell from a healer, and it survives them going quiet for a while.
    if kind == "SHADOW" and util.enemyShadowUntil > GetTime() then return true end
    local set = SDATA.ENEMY_KINDS[kind]
    if not set then return false end
    for class in pairs(util.enemyClasses) do
        if set[class] then return true end
    end
    return false
end

-- Have we seen ANYTHING of the other side? The comp scan and the shadow log
-- are separate witnesses, and either one counts as having looked.
function util.EnemySeen()
    return util.enemySeen > 0 or util.enemyShadowUntil > GetTime()
end

-- Amplify Magic's condition: the enemy deals no magic damage worth speaking
-- of, so the extra healing taken is free and the extra magic damage taken
-- costs nothing. Requires having SEEN the other team — an empty scan means we
-- do not know, and "do not know" must never read as "safe".
function util.EnemyIsPhysical()
    if not util.EnemySeen() then return false end
    return not util.EnemyHas("CASTER")
end


-- ---------------------------------------------------------------------------
-- Party Ability Bar: the curated cooldown book (see
-- prompts/commander-party-ability-bar.md). Tier 1 = always on the strip;
-- tier 2 = only while cooling down. kind ranks eviction: DEF > CC > KICK >
-- OFF > UTIL. spec limits an entry to a known spec (nil = whole class).
-- lock = "hypo"/"forb" ties the icon to that debuff (red rim, longer sweep).
-- resets = keys this ability refunds when cast (Cold Snap, Preparation).
-- off = ships untracked: in the book as an option, not on the default
-- strip. Every entry is toggleable per class in the Tracked Abilities
-- window (/cpf abilities); overrides live in DB.AbilityTrack keyed by
-- entry.tok ("CLASS:KEY", "*:KEY" for shared).
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
        { key = "NOVA", id = 122, name = "Frost Nova", icon = "Interface\\Icons\\Spell_Frost_FrostNova",
          cd = 25, tier = 1, kind = "CC", off = true },
        { key = "INVIS", id = 66, name = "Invisibility", icon = "Interface\\Icons\\Ability_Mage_Invisibility",
          cd = 300, tier = 2, kind = "DEF", off = true },
        { key = "BARRIER", id = 11426, name = "Ice Barrier", icon = "Interface\\Icons\\Spell_Ice_Lament",
          cd = 30, tier = 2, kind = "DEF", spec = "FROST", off = true },
        { key = "FIREBLAST", id = 2136, name = "Fire Blast", icon = "Interface\\Icons\\Spell_Fire_Fireball",
          cd = 8, tier = 2, kind = "OFF", off = true },
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
        { key = "SWD", id = 32379, name = "Shadow Word: Death", icon = "Interface\\Icons\\Spell_Shadow_DemonicFortitude",
          cd = 12, tier = 2, kind = "OFF", off = true },
        { key = "DESPERATE", id = 13908, name = "Desperate Prayer", icon = "Interface\\Icons\\Spell_Holy_Restoration",
          cd = 600, tier = 2, kind = "DEF", off = true },
        { key = "CHASTISE", id = 44041, name = "Chastise", icon = "Interface\\Icons\\Spell_Holy_Chastise",
          cd = 30, tier = 2, kind = "CC", off = true },
        { key = "DPLAGUE", id = 2944, name = "Devouring Plague", icon = "Interface\\Icons\\Spell_Shadow_CallofBone",
          cd = 180, tier = 2, kind = "OFF", off = true },
        { key = "LIGHTWELL", id = 724, name = "Lightwell", icon = "Interface\\Icons\\Spell_Holy_SummonLightwell",
          cd = 360, tier = 2, kind = "UTIL", spec = "HOLY", off = true },
        { key = "SYMBOL", id = 32548, name = "Symbol of Hope", icon = "Interface\\Icons\\Spell_Holy_SymbolOfHope",
          cd = 300, tier = 2, kind = "UTIL", off = true },
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
        { key = "GOUGE", id = 1776, name = "Gouge", icon = "Interface\\Icons\\Ability_Gouge",
          cd = 10, tier = 2, kind = "CC", off = true },
        { key = "BLADEFLURRY", id = 13877, name = "Blade Flurry", icon = "Interface\\Icons\\Ability_Warrior_PunishingBlow",
          cd = 120, tier = 2, kind = "OFF", spec = "COMBAT", off = true },
        { key = "PREMED", id = 14183, name = "Premeditation", icon = "Interface\\Icons\\Spell_Shadow_Possession",
          cd = 120, tier = 2, kind = "UTIL", spec = "SUBTLETY", off = true },
        { key = "GHOSTLY", id = 14278, name = "Ghostly Strike", icon = "Interface\\Icons\\Spell_Shadow_Curse",
          cd = 20, tier = 2, kind = "DEF", spec = "SUBTLETY", off = true },
        { key = "DISTRACT", id = 1725, name = "Distract", icon = "Interface\\Icons\\Ability_Rogue_Distract",
          cd = 30, tier = 2, kind = "UTIL", off = true },
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
        { key = "AWRATH", id = 31884, name = "Avenging Wrath", icon = "Interface\\Icons\\Spell_Holy_AvengineWrath",
          cd = 180, tier = 1, kind = "OFF", lock = "forb", off = true },
        { key = "HSHOCK", id = 20473, name = "Holy Shock", icon = "Interface\\Icons\\Spell_Holy_SearingLight",
          cd = 15, tier = 2, kind = "UTIL", spec = "HOLY", off = true },
        { key = "DILLUM", id = 31842, name = "Divine Illumination", icon = "Interface\\Icons\\Spell_Holy_DivineIllumination",
          cd = 180, tier = 2, kind = "UTIL", spec = "HOLY", off = true },
        { key = "DI", id = 19752, name = "Divine Intervention", icon = "Interface\\Icons\\Spell_Nature_TimeStop",
          cd = 3600, tier = 2, kind = "UTIL", off = true },
        { key = "ASHIELD", id = 31935, name = "Avenger's Shield", icon = "Interface\\Icons\\Spell_Holy_AvengersShield",
          cd = 30, tier = 2, kind = "KICK", spec = "PROTECTION", off = true },
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
        { key = "CHARGE", id = 100, name = "Charge", icon = "Interface\\Icons\\Ability_Warrior_Charge",
          cd = 15, tier = 2, kind = "CC", off = true },
        { key = "DISARM", id = 676, name = "Disarm", icon = "Interface\\Icons\\Ability_Warrior_Disarm",
          cd = 60, tier = 2, kind = "CC", off = true },
        { key = "CONCBLOW", id = 12809, name = "Concussion Blow", icon = "Interface\\Icons\\Ability_ThunderBolt",
          cd = 45, tier = 2, kind = "CC", spec = "PROTECTION", off = true },
        { key = "SWEEPING", id = 12328, name = "Sweeping Strikes", icon = "Interface\\Icons\\Ability_Rogue_SliceDice",
          cd = 30, tier = 2, kind = "OFF", spec = "ARMS", off = true },
        { key = "RETAL", id = 20230, name = "Retaliation", icon = "Interface\\Icons\\Ability_Warrior_Challange",
          cd = 1800, tier = 2, kind = "OFF", off = true },
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
        { key = "DASH", id = 1850, name = "Dash", icon = "Interface\\Icons\\Ability_Druid_Dash",
          cd = 300, tier = 2, kind = "UTIL", off = true },
        { key = "SWIFTMEND", id = 18562, name = "Swiftmend", icon = "Interface\\Icons\\INV_Relics_IdolofRejuvenation",
          cd = 15, tier = 2, kind = "UTIL", spec = "RESTORATION", off = true },
        { key = "TREANTS", id = 33831, name = "Force of Nature", icon = "Interface\\Icons\\Ability_Druid_ForceofNature",
          cd = 180, tier = 2, kind = "OFF", spec = "BALANCE", off = true },
        { key = "TRANQ", id = 740, name = "Tranquility", icon = "Interface\\Icons\\Spell_Nature_Tranquility",
          cd = 600, tier = 2, kind = "UTIL", off = true },
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
        { key = "SOULSHATTER", id = 29858, name = "Soulshatter", icon = "Interface\\Icons\\Spell_Arcane_Arcane01",
          cd = 300, tier = 2, kind = "UTIL", off = true },
        { key = "SHADOWBURN", id = 17877, name = "Shadowburn", icon = "Interface\\Icons\\Spell_Shadow_ScourgeBuild",
          cd = 15, tier = 2, kind = "OFF", spec = "DESTRUCTION", off = true },
        { key = "RITSOULS", id = 29893, name = "Ritual of Souls", icon = "Interface\\Icons\\Spell_Shadow_Shadesofdarkness",
          cd = 300, tier = 2, kind = "UTIL", off = true },
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
        { key = "FD", id = 5384, name = "Feign Death", icon = "Interface\\Icons\\Ability_Rogue_FeignDeath",
          cd = 30, tier = 2, kind = "UTIL", off = true },
        { key = "MISDIR", id = 34477, name = "Misdirection", icon = "Interface\\Icons\\Ability_Hunter_Misdirection",
          cd = 120, tier = 2, kind = "UTIL", off = true },
        { key = "FLARE", id = 1543, name = "Flare", icon = "Interface\\Icons\\Spell_Fire_Flare",
          cd = 20, tier = 2, kind = "UTIL", off = true },
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
        { key = "ESHOCK", id = 8042, name = "Earth Shock", icon = "Interface\\Icons\\Spell_Nature_EarthShock",
          cd = 6, tier = 1, kind = "KICK", off = true },
        { key = "FIREELE", id = 2894, name = "Fire Elemental Totem", icon = "Interface\\Icons\\Spell_Fire_Elemental_Totem",
          cd = 1200, tier = 2, kind = "OFF", off = true },
        { key = "EARTHELE", id = 2062, name = "Earth Elemental Totem", icon = "Interface\\Icons\\Spell_Nature_EarthElemental_Totem",
          cd = 1200, tier = 2, kind = "DEF", off = true },
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
    { key = "BERSERKING", id = 26297, name = "Berserking", icon = "Interface\\Icons\\Racial_Troll_Berserk",
      cd = 180, tier = 2, kind = "OFF", off = true },
    { key = "ESCAPE", id = 20589, name = "Escape Artist", icon = "Interface\\Icons\\Ability_Rogue_Trip",
      cd = 105, tier = 2, kind = "UTIL", off = true },
    { key = "PERCEPTION", id = 20600, name = "Perception", icon = "Interface\\Icons\\Spell_Nature_Sleep",
      cd = 180, tier = 2, kind = "UTIL", off = true },
    { key = "GIFT", id = 28880, name = "Gift of the Naaru", icon = "Interface\\Icons\\Spell_Holy_HolyProtection",
      cd = 180, tier = 2, kind = "UTIL", off = true },
}
SDATA.HYPO_ID, SDATA.FORB_ID = 41425, 25771   -- Hypothermia, Forbearance
SDATA.ABILITY_H = 16            -- ability strip height (icons are H-2)
SDATA.MAX_ABILITY_CELLS = 8
SDATA.KIND_RANK = { DEF = 1, CC = 2, KICK = 3, OFF = 4, UTIL = 5 }
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
        local byKey = {}
        for i, entry in ipairs(list) do
            entry.ord = i
            entry.tok = class .. ":" .. entry.key
            byKey[entry.key] = entry
            local n, _, ic = nil, nil, nil
            if entry.id and GetSpellInfo then n, _, ic = GetSpellInfo(entry.id) end
            entry.dispName = n or entry.name
            entry.dispIcon = ic or entry.icon
            register(entry.dispName, class, entry)
            if entry.name ~= entry.dispName then register(entry.name, class, entry) end
        end
        -- Reverse reset links: the target icon wears the gold pip while its
        -- resetter is ready
        for _, entry in ipairs(list) do
            if entry.resets then
                for _, tk in ipairs(entry.resets) do
                    if byKey[tk] then byKey[tk].resetBy = entry end
                end
            end
        end
    end
    for i, entry in ipairs(SDATA.ABILITY_SHARED) do
        entry.ord = 50 + i
        entry.tok = "*:" .. entry.key
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

-- The Tracked Abilities window (settings side) iterates the book to build
-- its per-class toggle menus
function CommanderPartyFrames_GetAbilityBook()
    return SDATA.ABILITY_BOOK, SDATA.ABILITY_SHARED
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
    -- A spec-gated ability's own cast IS proof of the spec (Cold Snap,
    -- Scatter Shot… aren't all in the marker table)
    if entry.spec then specState[guid] = entry.spec end
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
-- Pets on the ally board (Include Pets). Every pet in the group has its own
-- fixed token, so "is this a pet, and whose" is a static lookup rather than a
-- UnitIsUnit walk — and the owner is what a pet row borrows for the two
-- things a pet has none of: a class color and a class icon. It lives in SDATA
-- because this chunk sits within a few locals of Lua's 200-per-chunk ceiling
-- (see the SDATA note at the top).
SDATA.PET_OWNER = { pet = "player" }
for i = 1, 4 do SDATA.PET_OWNER["partypet" .. i] = "party" .. i end
for i = 1, 40 do SDATA.PET_OWNER["raidpet" .. i] = "raid" .. i end
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

-- Forward declaration: the default-party-frame toggle is built far below
-- (next to EnsureSettingsButton), but the mage button cluster has to chain
-- off it, and util.Layout is defined before it exists.
local blizz

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

-- Show/Hide is a PROTECTED call on any frame that CARRIES secure children,
-- not just on one built from a secure template: the engine walks up from the
-- secure button, because hiding an ancestor would hide the button. That makes
-- both `root` and the banner's utility container protected — the same rule
-- the default-party-frame toggle already respects — and calling either in
-- combat is blocked outright (ADDON_ACTION_BLOCKED, the field report).
--
-- So: a visibility change is a no-op when the frame is already in the wanted
-- state (the common case, once per draw), and one that would really flip a
-- protected frame mid-fight is skipped rather than attempted. Nothing has to
-- be queued — PLAYER_REGEN_ENABLED re-draws, and the draw re-derives every
-- one of these from scratch. Returns whether the frame ended up as asked, so
-- a caller that measures the result can ask instead of assume.
local function SafeSetShown(frame, want)
    want = want and true or false
    if (frame:IsShown() and true or false) == want then return true end
    if InCombat() and frame.IsProtected and frame:IsProtected() then return false end
    frame:SetShown(want)
    return true
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

-- ---------------------------------------------------------------------------
-- Click-binding profiles, keyed by TALENT BUILD.
--
-- This is a TBC client: dual spec is a Wrath feature, so there is no spec API
-- to hook and no in-game switch to listen for. What there IS is the talent
-- tree itself — which tab you have sunk the most points into — and that is
-- the thing a player actually changes when they respec between arena and PvE.
-- So the profile follows the build: respec, and the board comes back bound the
-- way you left it for that build. The tab INDEX keys it, not the tab name,
-- because names are localized and a saved profile has to survive a client in
-- another language.
-- ---------------------------------------------------------------------------
function util.TalentProfile()
    local cls = playerClass or "UNKNOWN"
    if DB("ClickProfileMode", "TALENT") == "FIXED" then
        local fixed = DB("ClickProfileFixed", "")
        if fixed ~= "" then return fixed end
    end
    if not (GetNumTalentTabs and GetTalentTabInfo) then return cls .. ":1" end
    local bestTab, bestPts = 1, -1
    for i = 1, (GetNumTalentTabs() or 0) do
        local ok, _, _, pts = pcall(GetTalentTabInfo, i)
        if ok and type(pts) == "number" and pts > bestPts then bestTab, bestPts = i, pts end
    end
    -- A fresh character with nothing spent gets one shared profile rather than
    -- an arbitrary tree's, so early bindings do not scatter across three of them
    if bestPts <= 0 then return cls .. ":0" end
    return cls .. ":" .. bestTab
end

function util.BindStore(profile, create)
    local all = CommanderPartyFramesDB and CommanderPartyFramesDB.ClickBinds
    if not all then
        if not create then return nil end
        all = {}
        CommanderPartyFramesDB.ClickBinds = all
    end
    local rec = all[profile]
    if not rec and create then rec = {}; all[profile] = rec end
    return rec
end

function util.GetBind(key, profile)
    local rec = util.BindStore(profile or util.TalentProfile(), false)
    if rec then
        local v = rec[key]
        -- An explicit false is how the grid records "deliberately cleared",
        -- which has to beat the default rather than fall back through it
        if v == false then return nil end
        if v ~= nil then return v end
        if rec.__touched then return nil end
    end
    local d = layer and SDATA.BIND_DEFAULTS[layer]
    return d and d[key] or nil
end

function util.SetBind(key, value, profile)
    local rec = util.BindStore(profile or util.TalentProfile(), true)
    -- The first edit takes this profile off the shared defaults entirely, so
    -- clearing a cell means cleared rather than "fall back to Flash Heal"
    if not rec.__touched then
        rec.__touched = true
        local d = layer and SDATA.BIND_DEFAULTS[layer]
        if d then for k, v in pairs(d) do if rec[k] == nil then rec[k] = v end end end
    end
    if value == nil or value == "NONE" then rec[key] = false else rec[key] = value end
end

-- One-time migration off the old flat keys. The bindings a player already set
-- are theirs; silently resetting everyone to defaults because the storage
-- shape changed is the rudest possible upgrade. Seeds the profile that is
-- active at first login and marks the DB so it never runs twice.
-- What a brand-new profile starts as, per layer. Not written to the DB —
-- they are what GetBind falls back to, so a player who never opens the grid
-- still has a working board, and re-tuning these later reaches everyone who
-- never overrode them.
SDATA.BIND_DEFAULTS = {
    PWS = { ["1"] = 17, ["2"] = 139, ["3"] = 2061, ["shift-1"] = 2060 },
    INT = { ["1"] = 1459, ["2"] = 475, ["3"] = "TARGET", ["shift-1"] = 1008 },
    HOT = { ["1"] = 774, ["2"] = 33763, ["3"] = "TARGET", ["shift-1"] = 8936 },
    -- Flash of Light and Cleanse are what a paladin's hands are on all match;
    -- Freedom takes the modifier because it is the one you press without
    -- looking, at the exact moment you cannot afford to go hunting for it.
    BLESS = { ["1"] = 19750, ["2"] = 4987, ["3"] = "TARGET", ["shift-1"] = 1044 },
}

function util.MigrateBinds()
    if not CommanderPartyFramesDB then return end
    if CommanderPartyFramesDB.ClickBindsMigrated then return end
    CommanderPartyFramesDB.ClickBindsMigrated = true
    local old
    if layer == "INT" then
        old = { CommanderPartyFramesDB.MageClickLeft, CommanderPartyFramesDB.MageClickRight,
            CommanderPartyFramesDB.MageClickMiddle, CommanderPartyFramesDB.MageClickModLeft }
    elseif layer == "HOT" then
        old = { CommanderPartyFramesDB.DruidClickLeft, CommanderPartyFramesDB.DruidClickRight,
            CommanderPartyFramesDB.DruidClickMiddle, CommanderPartyFramesDB.DruidClickModLeft }
    elseif layer == "PWS" then
        old = { CommanderPartyFramesDB.ClickLeft, CommanderPartyFramesDB.ClickRight,
            CommanderPartyFramesDB.ClickMiddle, CommanderPartyFramesDB.ClickModLeft }
    else
        return
    end
    local profile = util.TalentProfile()
    local rec = util.BindStore(profile, true)
    if next(rec) then return end   -- already populated: leave it alone
    if old[1] then rec["1"] = old[1] end
    if old[2] then rec["2"] = old[2] end
    if old[3] then rec["3"] = old[3] end
    if old[4] then
        local mod = (CommanderPartyFramesDB.ClickModifier or "shift") .. "-"
        rec[mod .. "1"] = old[4]
    end
end

-- A profile key is CLASS:tabIndex — locale-proof, and meaningless to read.
-- This turns it back into the tree's own name for the settings header, which
-- is the only place a player should ever have to see a profile identified.
function util.ProfileLabel(profile)
    if not profile then return "?" end
    local cls, tab = profile:match("^(.+):(%d+)$")
    tab = tonumber(tab)
    if not tab then return profile end
    if tab == 0 then return "No talents spent" end
    if GetTalentTabInfo then
        local ok, name = pcall(GetTalentTabInfo, tab)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return (cls or "?") .. " tree " .. tab
end

-- Every profile that exists, with the active one guaranteed present even
-- before it has been written to. Sorted so the settings list does not
-- reshuffle between openings.
function util.ListProfiles(out)
    wipe(out)
    local seen = {}
    local active = util.TalentProfile()
    out[#out + 1] = active
    seen[active] = true
    local all = CommanderPartyFramesDB and CommanderPartyFramesDB.ClickBinds
    if all then
        for key in pairs(all) do
            if not seen[key] then seen[key] = true; out[#out + 1] = key end
        end
    end
    table.sort(out)
    return out
end

-- Copy every binding from one profile onto another, replacing it wholesale.
-- Marked touched, so the copy is the copy — a cell the source deliberately
-- cleared stays cleared rather than reverting to the layer default.
function util.CopyProfile(from, to)
    if not from or not to or from == to then return false end
    local src = util.BindStore(from, false)
    if not src then return false end
    local dst = util.BindStore(to, true)
    wipe(dst)
    for k, v in pairs(src) do dst[k] = v end
    dst.__touched = true
    return true
end

-- Back to the layer's defaults: the profile is dropped entirely rather than
-- filled with default values, so it keeps following the defaults if they are
-- ever re-tuned.
function util.ResetProfile(profile)
    local all = CommanderPartyFramesDB and CommanderPartyFramesDB.ClickBinds
    if all then all[profile] = nil end
end

-- Every bindable this class knows, resolved against the spellbook. The picker
-- is only as honest as this list: offering a spell the character cannot cast
-- produces a binding that saves and then does nothing.
function util.ResolveBindables()
    wipe(SDATA.BIND_LIST)
    local list = layer and SDATA.BINDABLE[layer]
    if not (list and GetSpellInfo) then return end
    for _, e in ipairs(list) do
        local name, _, icon = GetSpellInfo(e.id)
        if name and (knownSpells[name] or (IsSpellKnown and IsSpellKnown(e.id))) then
            SDATA.BIND_LIST[#SDATA.BIND_LIST + 1] = {
                id = e.id, name = name, icon = icon, group = e.group or "Utility",
            }
        end
    end
end

-- What a bound value looks like in the UI: its icon and a readable label.
function util.BindDisplay(value)
    if value == nil or value == "NONE" then
        return nil, "Unbound"
    end
    for _, a in ipairs(SDATA.CLICK_ACTIONS) do
        if a.value == value then return a.icon, a.label end
    end
    local id = tonumber(value)
    if id and GetSpellInfo then
        local name, _, icon = GetSpellInfo(id)
        if name then
            local known = knownSpells[name] or (IsSpellKnown and IsSpellKnown(id))
            return icon, name, not known
        end
    end
    return nil, "Unknown spell (" .. tostring(value) .. ")", true
end


-- Resolve the active layer's buff names and icons from the spellbook. Only the
-- ACTIVE layer goes into the name map, so a mage's board can never count a
-- druid's Mark of the Wild as "buffed" and vice versa.
function util.ResolveBuffBook()
    wipe(SDATA.BUFF_BY_NAME)
    wipe(SDATA.BUFF_LIST)
    local list = layer and SDATA.CLASS_BUFFS[layer]
    if not list then util.RefreshBuffs(); return end
    for _, def in ipairs(list) do
        SDATA.BUFF_LIST[#SDATA.BUFF_LIST + 1] = def
        def.known = false
        if GetSpellInfo then
            -- Knowing EITHER version counts: a raid-buffing priest who only
            -- ever presses Prayer of Fortitude still maintains Fortitude.
            -- knownSpells is the spellbook scan; IsSpellKnown is the backstop
            -- for a rank it has not indexed (the same pair the armor popout
            -- and the druid banner use).
            local n, _, icon = GetSpellInfo(def.id)
            if n then
                SDATA.BUFF_BY_NAME[n] = def
                if icon then def.icon = icon end
                if knownSpells[n] or (IsSpellKnown and IsSpellKnown(def.id)) then
                    def.known = true
                end
            end
            if def.groupId then
                local gn, _, gicon = GetSpellInfo(def.groupId)
                if gn then
                    SDATA.BUFF_BY_NAME[gn] = def
                    if knownSpells[gn] or (IsSpellKnown and IsSpellKnown(def.groupId)) then
                        def.known = true
                        if not def.icon and gicon then def.icon = gicon end
                    end
                end
            end
        end
    end
    util.RefreshBuffs()
end

-- The spellbook, twice over: a name set for every "do I know this" question
-- on the board, and an ordered list with icons for the binding picker.
--
-- Deduped by NAME rather than by id, because that is the unit the game itself
-- binds in: BindClick writes a spell NAME into the secure attribute, and the
-- client then casts your highest known rank of it. So five ranks of Flash Heal
-- are one entry in the picker, not five, and the entry never goes stale as you
-- train the next rank.
local function RefreshKnownSpells()
    wipe(knownSpells)
    wipe(SDATA.BOOK_LIST)
    if not (GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName) then return end
    local seen = {}
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, numSlots = GetSpellTabInfo(tab)
        for i = (offset or 0) + 1, (offset or 0) + (numSlots or 0) do
            local name = GetSpellBookItemName(i, "spell")
            if name then
                knownSpells[name] = true
                if not seen[name] then
                    seen[name] = true
                    local id, icon
                    if GetSpellBookItemInfo then
                        local _, sid = GetSpellBookItemInfo(i, "spell")
                        id = sid
                    end
                    if id and GetSpellInfo then icon = select(3, GetSpellInfo(id)) end
                    SDATA.BOOK_LIST[#SDATA.BOOK_LIST + 1] =
                        { id = id, name = name, icon = icon }
                end
            end
        end
    end
    table.sort(SDATA.BOOK_LIST, function(x, y) return x.name < y.name end)
end

-- ---------------------------------------------------------------------------
-- Mage banner utilities: conjure/consume secure buttons, the armor-switch
-- popout, and Water Elemental info. Secure attributes only change out of
-- combat (mageBtnsDirty defers to PLAYER_REGEN_ENABLED); the popout and the
-- button CONTAINER are insecure frames, so showing/hiding them stays legal
-- mid-combat even though the buttons themselves are protected.
-- ---------------------------------------------------------------------------
-- Strip-layer name resolution (login + respec/SPELLS_CHANGED). Every lookup
-- a strip layer does at runtime is by LOCALIZED NAME — the auras of ours on
-- an ally, the form we are wearing — so the whole locale problem is solved
-- once, here, from stable base IDs. Banner cooldowns are filtered to what the
-- character actually knows, so a feral never sees a Nature's Swiftness
-- segment and a retribution paladin never sees Divine Illumination.
local function ResolveStripInfo()
    if not GetSpellInfo then return end
    -- The banner-cooldown pass runs for every layer that brought a book,
    -- including the priest's, which has no per-ally strip at all.
    wipe(strip.names)
    for _, def in ipairs(SDATA.STRIP_BOOKS[layer or ""] or {}) do
        local n, _, icon = GetSpellInfo(def.baseId)
        def.known = false
        if n then
            strip.names[n] = def
            if icon then def.icon = icon end
            -- knownSpells is the spellbook scan; IsSpellKnown is the backstop
            -- for a rank it has not indexed yet (same pair the rest use)
            if knownSpells[n] or (IsSpellKnown and IsSpellKnown(def.baseId)) then
                def.known = true
            end
        end
    end
    -- The banner's cooldown segments, from whichever book this layer brought
    wipe(strip.cds)
    for _, e in ipairs(SDATA.BANNER_CDS[layer] or {}) do
        local n, _, icon = GetSpellInfo(e.id)
        -- knownSpells is the spellbook scan; IsSpellKnown is the backstop for
        -- a rank we have not indexed yet (same pair the armor popout uses)
        if n and ((knownSpells and knownSpells[n]) or (IsSpellKnown and IsSpellKnown(e.id))) then
            strip.cds[#strip.cds + 1] = { key = e.key, name = n, icon = icon or e.icon, cd = e.cd }
        end
    end

    if layer == "HOT" then
        wipe(strip.forms)
        for id, form in pairs(SDATA.DRUID_FORMS) do
            local n, _, icon = GetSpellInfo(id)
            if n then
                strip.forms[n] = form
                form.icon = icon or form.icon
            end
        end
    elseif layer == "BLESS" then
        -- Aura and seal names, KNOWN LINES ONLY (see SDATA.PALADIN_AURAS):
        -- you cannot be running one you have not trained, so gating on the
        -- spellbook costs nothing and makes a bad rank id inert instead of
        -- dangerous.
        local function fill(out, lines)
            wipe(out)
            for _, line in ipairs(lines) do
                for _, id in ipairs(line.ids) do
                    local n, _, icon = GetSpellInfo(id)
                    if n and ((knownSpells and knownSpells[n])
                        or (IsSpellKnown and IsSpellKnown(id))) then
                        out[n] = { key = line.key, icon = icon }
                        break
                    end
                end
            end
        end
        fill(strip.auraNames, SDATA.PALADIN_AURAS)
        fill(strip.sealNames, SDATA.PALADIN_SEALS)
    end
end

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

-- Bag tallies drive both the secure binds and the optional counters. One
-- GetItemCount per rank beats walking every bag slot, and the same call
-- answers "how many" for the counter text.
--
-- These helpers hang off `util` rather than being chunk locals: this file
-- is at Lua's 200-local ceiling (see the SDATA note at the top), so new
-- functions live in the table too.
function util.ItemCount(id)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) or 0 end
    if GetItemCount then return GetItemCount(id) or 0 end
    return 0
end

function util.ItemIcon(id)
    if not id then return nil end
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    if GetItemIcon then return GetItemIcon(id) end
    return nil
end

-- Walk a best-first item list: returns the best rank held and the total
-- across every rank, and fills `out` with the present ranks (best first,
-- capped at 4). The /use lines are built from that list, so one click still
-- fires the next rank down when the best runs out mid-combat — secure
-- attributes cannot be rebound in combat, but a multi-line macro needs no
-- rebind. Same idiom as a hand-written multi-/use macro.
function util.ScanItems(list, out)
    local best, total = nil, 0
    if out then wipe(out) end
    for _, id in ipairs(list) do
        local c = util.ItemCount(id)
        if c > 0 then
            total = total + c
            if not best then best = id end
            if out and #out < 4 then out[#out + 1] = id end
        end
    end
    return best, total
end

-- `limit` caps how many ranks the macro reaches for. Every /use line in a
-- macro fires, so a cascade is only safe when the items share a cooldown (mana
-- gems do — the first usable one wins and the rest are skipped). Food and
-- drink share nothing, so an uncapped cascade ate one of EVERY rank held on a
-- single click; those callers pass 1.
function util.UseLines(ids, cond, limit)
    local text = ""
    for i, id in ipairs(ids) do
        if limit and i > limit then break end
        text = text .. (text ~= "" and "\n" or "")
            .. "/use " .. (cond and (cond .. " ") or "") .. "item:" .. id
    end
    return text
end

-- The mage's own conjure castsequence, best rank first and only the ranks
-- trained: "reset=10 Conjure Mana Ruby, Conjure Mana Citrine, ...". Returned
-- without the /castsequence prefix so both the modifier line and the
-- right-click line can share it — identical sequence text means the client
-- keeps ONE position for the pair, so the two ways of pressing it stay in
-- step. nil when no gem spell is trained.
function util.GemSequence()
    local names = {}
    for _, id in ipairs(util.gemSpells or {}) do
        local n = GetSpellInfo and GetSpellInfo(id)
        if n and (knownSpells[n] or (IsSpellKnown and IsSpellKnown(id))) then
            names[#names + 1] = n
        end
    end
    if #names == 0 then return nil end
    return "reset=10 " .. table.concat(names, ", ")
end

-- Bag tallies behind both the counters and the /use lines. Cheap enough to
-- redo on every bag update; the counters are insecure font strings, so they
-- keep refreshing mid-combat when the secure binds cannot.
function util.RefreshCounts()
    local c = util.counts
    c.waterIds = c.waterIds or {}
    c.foodIds = c.foodIds or {}
    c.gemIds = c.gemIds or {}
    c.bandIds = c.bandIds or {}
    if not util.gemItems then
        util.gemItems, util.gemSpells = {}, {}
        for _, g in ipairs(SDATA.MANA_GEMS) do
            util.gemItems[#util.gemItems + 1] = g.item
            util.gemSpells[#util.gemSpells + 1] = g.spell
        end
    end
    c.water, c.waterN = util.ScanItems(SDATA.CONJURED_WATER, c.waterIds)
    c.food, c.foodN = util.ScanItems(SDATA.CONJURED_FOOD, c.foodIds)
    c.gem, c.gemN = util.ScanItems(util.gemItems, c.gemIds)
    c.band, c.bandN = util.ScanItems(SDATA.BANDAGES, c.bandIds)
end

-- Lay the utility cluster out right-to-left, skipping buttons the config
-- turns off so no gap is left behind. Only ever called from the bind pass,
-- which is combat-deferred: these are protected frames and may neither move
-- nor change visibility mid-fight.
-- Width the class cluster occupies, so the banner's readout segments know
-- where to start. Zero when every button is switched off.
--
-- Measured from what is ON SCREEN, not from what the config wants. These are
-- secure buttons: a fight freezes them in whatever state it caught them in,
-- and the readout — plain textures, free to move — is the half of the pair
-- that adapts. Reading `wanted` here would reserve a left margin for a
-- cluster that is not drawn, which is precisely the gap that showed up.
-- The cluster in banner order. Walked by INDEX, never with ipairs: four of
-- these five are mage-only and stay nil on any other layer, and ipairs stops
-- dead at the first hole — which on a priest or druid banner is index 1. That
-- ended the walk before it began, so ClusterWidth reported 0 and Layout never
-- re-anchored anything, leaving the bandage button parked on the provisional
-- top-right anchor mkBtn gives it: directly under the settings gear.
SDATA.CLUSTER_N = 5
local function ClusterAt(i)
    if i == 1 then return consumeBtn end
    if i == 2 then return conjureBtn end
    if i == 3 then return gemBtn end
    if i == 4 then return util.portalBtn end
    if i == 5 then return bandageBtn end
    return nil
end

function util.ClusterWidth()
    if mageUtil and not mageUtil:IsShown() then return 0 end
    local w, any = 0, false
    for i = 1, SDATA.CLUSTER_N do
        local b = ClusterAt(i)
        if b and b:IsShown() then
            w = w + (b:GetWidth() or 13) + (any and 3 or 0)
            any = true
        end
    end
    return w
end

-- Where the banner's own content starts: after the cluster, or hard left when
-- every button is off. Shared by both segment banners AND the priest board's
-- plain text header, so none of them can drift onto the buttons.
function util.ClusterOffset()
    local cw = util.ClusterWidth()
    return STRIPE_W + 4 + (cw > 0 and (cw + 5) or 0)
end

-- Header convention: everything CLASS-specific is left-aligned, everything
-- Commander is right-aligned.
--
-- Within the left block the cluster leads and the readout segments flow after
-- it, which looks backwards until you notice these buttons are SECURE: a
-- fixed left anchor is the only placement that never needs a protected
-- SetPoint mid-fight. The segments are plain textures, so they are the half
-- of the pair that can safely move every draw.
function util.Layout()
    local prev
    for i = 1, SDATA.CLUSTER_N do
        local b = ClusterAt(i)
        if b then
            b:SetShown(b.wanted and true or false)
            if b.wanted then
                b:ClearAllPoints()
                if prev then
                    b:SetPoint("LEFT", prev, "RIGHT", 3, 0)
                else
                    b:SetPoint("TOPLEFT", root, "TOPLEFT", STRIPE_W + 3, -1)
                end
                prev = b
            end
        end
    end
    -- The portals popout hangs under its own button, wherever that ended up
    if util.portalPop and util.portalBtn then
        util.portalPop:ClearAllPoints()
        util.portalPop:SetPoint("TOPLEFT", util.portalBtn, "BOTTOMLEFT", 0, -3)
    end
end

-- One secure button per known destination, in a two-row popout: teleports on
-- top, portals below. Same shape as the armor popout — pooled children,
-- anchored to the popout frame, never re-anchored in combat.
function util.BuildPortalRow(ids, row, count)
    local shown = 0
    for _, id in ipairs(ids) do
        local name, _, icon = GetSpellInfo(id)
        if name and ((knownSpells[name]) or (IsSpellKnown and IsSpellKnown(id))) then
            shown = shown + 1
            count = count + 1
            local b = util.portalButtons[count]
            if not b then
                b = CreateFrame("Button", "CommanderPartyFramesPortalBtn" .. count,
                    util.portalPop, "SecureActionButtonTemplate")
                b:SetSize(18, 18)
                b:RegisterForClicks("AnyDown", "AnyUp")
                b.icon = b:CreateTexture(nil, "ARTWORK")
                b.icon:SetAllPoints(b)
                b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                util.StyleIcon(b.icon)
                local hl = b:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(b)
                hl:SetTexture("Interface\\Buttons\\WHITE8X8")
                hl:SetVertexColor(1, 1, 1, 0.25)
                b:SetScript("PostClick", function() SafeSetShown(util.portalPop, false) end)
                b:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
                    GameTooltip:SetText(self.tipName or "")
                    GameTooltip:Show()
                end)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                util.portalButtons[count] = b
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", util.portalPop, "TOPLEFT",
                3 + (shown - 1) * 21, -(3 + row * 21))
            b:SetAttribute("type", "spell")
            b:SetAttribute("spell", name)
            b.tipName = name
            b.icon:SetTexture(icon)
            b:Show()
        end
    end
    return shown, count
end

local function BindMageUtilityButtons()
    if not (conjureBtn or bandageBtn) then return end
    if InCombat() then mageBtnsDirty = true; return end
    mageBtnsDirty = false
    util.RefreshCounts()
    local c = util.counts

    -- Bandage (every class): left = use the best held rank on a friendly
    -- target or yourself, right = same, middle opens the First Aid window
    -- (PostClick, so the secure path is untouched).
    if bandageBtn then
        local lines = util.UseLines(c.bandIds, "[help,nodead][@player]")
        bandageBtn:SetAttribute("type1", "macro")
        bandageBtn:SetAttribute("macrotext1", lines)
        bandageBtn:SetAttribute("type2", "macro")
        bandageBtn:SetAttribute("macrotext2", lines)
        bandageBtn.icon:SetTexture(util.ItemIcon(c.band) or "Interface\\Icons\\INV_Misc_Bandage_12")
        bandageBtn.wanted = DB("ShowBandageButton", true) and true or false
    end

    if layer ~= "INT" or not conjureBtn then
        util.Layout()
        return
    end

    -- Conjure: left = water, right = food (cast by name = highest rank)
    local cwName, _, cwIcon = GetSpellInfo(SDATA.CONJURE_WATER_ID)
    local cfName = GetSpellInfo(SDATA.CONJURE_FOOD_ID)
    conjureBtn:SetAttribute("type1", "spell")
    conjureBtn:SetAttribute("spell1", cwName)
    conjureBtn:SetAttribute("type2", "spell")
    conjureBtn:SetAttribute("spell2", cfName)
    conjureBtn.icon:SetTexture(cwIcon or "Interface\\Icons\\INV_Drink_18")

    -- Consume: left = drink, right = eat. Kept separate on purpose — hitting
    -- both buttons is how you ask for both, and that beats a combined click
    -- that always burns one of each. Best rank only, one item per click: the
    -- rank cascade belongs on cooldown-sharing items, and food and drink share
    -- no cooldown, so every line landed and a click swallowed one of each rank
    -- in the bags. Nothing is lost by capping it — you cannot eat or drink in
    -- combat anyway, and BAG_UPDATE_DELAYED re-aims the button on the next
    -- rank the moment the best one runs dry.
    consumeBtn:SetAttribute("type1", "macro")
    consumeBtn:SetAttribute("macrotext1", util.UseLines(c.waterIds, nil, 1))
    consumeBtn:SetAttribute("type2", "macro")
    consumeBtn:SetAttribute("macrotext2", util.UseLines(c.foodIds, nil, 1))
    consumeBtn.icon:SetTexture(util.ItemIcon(c.water) or util.ItemIcon(c.food)
        or "Interface\\Icons\\INV_Drink_18")
    consumeBtn.icon:SetDesaturated(not (c.food or c.water))

    -- Mana gem: the hand-written castsequence macro, line for line. Left-click
    -- consumes — the /use cascade is safe here because every gem shares one
    -- two-minute cooldown, so the first usable rank fires and the rest are
    -- skipped. Modifier + left, or right-click, walks the conjure sequence:
    -- Ruby, Citrine, Jade, Agate, one per press, so a run of clicks ends with
    -- one of every gem rather than four failed re-casts of the top rank.
    if gemBtn then
        local seq = util.GemSequence()
        local useText = util.UseLines(c.gemIds, "[nomod]")
        if seq then
            useText = "/castsequence [mod] " .. seq
                .. (useText ~= "" and "\n" or "") .. useText
        end
        gemBtn:SetAttribute("type1", "macro")
        gemBtn:SetAttribute("macrotext1", useText)
        gemBtn:SetAttribute("type2", "macro")
        gemBtn:SetAttribute("macrotext2", seq and ("/castsequence " .. seq) or "")
        gemBtn.icon:SetTexture(util.ItemIcon(c.gem) or "Interface\\Icons\\INV_Misc_Gem_Emerald_01")
        gemBtn.icon:SetDesaturated(not c.gem)
        gemBtn.wanted = DB("ShowGemButton", true)
            and (c.gem ~= nil or seq ~= nil) or false
    end

    -- Portals & teleports: two rows of known destinations
    if util.portalPop then
        local count = 0
        local tp, count1 = util.BuildPortalRow(SDATA.TELEPORTS, 0, count)
        local po, count2 = util.BuildPortalRow(SDATA.PORTALS, tp > 0 and 1 or 0, count1)
        count = count2
        for i = count + 1, #util.portalButtons do util.portalButtons[i]:Hide() end
        local cols = math.max(tp, po, 1)
        local rows = (tp > 0 and 1 or 0) + (po > 0 and 1 or 0)
        util.portalPop:SetSize(cols * 21 + 3, math.max(rows, 1) * 21 + 3)
        util.portalKnown = count > 0
        -- A mage with no teleport trained yet gets no button rather than an
        -- empty popout
        util.portalBtn.wanted = DB("ShowPortalButton", true) and util.portalKnown or false
        if not util.portalKnown then util.portalPop:Hide() end
    end
    util.Layout()

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
                util.StyleIcon(b.icon)
                local hl = b:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(b)
                hl:SetTexture("Interface\\Buttons\\WHITE8X8")
                hl:SetVertexColor(1, 1, 1, 0.25)
                b:SetScript("PostClick", function() SafeSetShown(armorPop, false) end)
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

-- The cluster and its popouts are siblings of the board, so root's scale no
-- longer reaches them by inheritance. The HUD chrome writes that scale
-- directly on root (the resize grip does it live, mid-drag, without telling
-- the module), so this is checked per draw rather than on a settings event —
-- a number compare, with the protected SetScale only ever reached on change
-- and out of combat.
function util.SyncCluster()
    if not mageUtil or InCombat() then return end
    local s = root:GetScale() or 1
    for _, f in ipairs({ mageUtil, armorPop, util.portalPop }) do
        if f and (f:GetScale() or 1) ~= s then f:SetScale(s) end
    end
    -- Stacking order is the other thing a child got free. Above the board's
    -- rows, below the HUD chrome's drag overlay (root + 20), so a banner
    -- button never steals the drag handle while the frame is unlocked.
    local want = (root:GetFrameLevel() or 1) + 5
    if (mageUtil:GetFrameLevel() or 0) ~= want then mageUtil:SetFrameLevel(want) end
end

-- ---------------------------------------------------------------------------
-- The upkeep banner's readout: a row of icon+text segments. Every class layer
-- that HAS a banner draws the same shape, so the pool, the placement and the
-- truncation live here once and each layer only decides what the segments SAY.
--
-- The pool GROWS on demand rather than sitting at a fixed size. It was eight,
-- which comfortably covered the mage and druid banners and is nowhere near
-- what a paladin asks for: aura, seal, up to eleven trained cooldowns, uptime
-- and the alert segment is fifteen. Textures and font strings are unprotected,
-- so growing one mid-combat is legal.
-- ---------------------------------------------------------------------------
util.segN = 0
SDATA.MIN_SEGS = 8      -- what every banner gets up front
SDATA.MAX_SEGS = 24     -- runaway backstop; width truncates long before this

function util.EnsureSegs(want)
    local segs = root.hdrSegs
    if not segs then segs = {}; root.hdrSegs = segs end
    want = math.min(math.max(want or SDATA.MIN_SEGS, SDATA.MIN_SEGS), SDATA.MAX_SEGS)
    if #segs >= want then return segs end
    for i = #segs + 1, want do
        local icon = root:CreateTexture(nil, "OVERLAY")
        icon:SetSize(12, 12)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local text = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetJustifyH("LEFT")
        if i > 1 then
            icon:SetPoint("LEFT", segs[i - 1].text, "RIGHT", 8, 0)
        else
            -- PlaceSegs owns the first segment's x and only re-anchors it when
            -- the cluster width changes, so a pool built after it last ran has
            -- to start from the offset it settled on rather than the default.
            icon:SetPoint("TOPLEFT", root, "TOPLEFT", root._segX or (STRIPE_W + 4), -1)
        end
        text:SetPoint("LEFT", icon, "RIGHT", 2, 0)
        segs[i] = { icon = icon, text = text }
    end
    return segs
end

-- Segments start after the class button cluster. Re-anchored only when that
-- width changes: this runs at the draw rate, and they are textures, so combat
-- is no obstacle. Returns the x the readout begins at.
function util.PlaceSegs()
    local segX = util.ClusterOffset()
    if root._segX ~= segX then
        root._segX = segX
        local segs = util.EnsureSegs()
        segs[1].icon:ClearAllPoints()
        segs[1].icon:SetPoint("TOPLEFT", root, "TOPLEFT", segX, -1)
    end
    return segX
end

function util.Seg(icon, desat, text, tint)
    util.segN = util.segN + 1
    -- Grow to meet the ask. Past MAX_SEGS this returns nothing and the segment
    -- is dropped — and segN keeps counting, which is exactly why TruncSegs
    -- clamps to the pool rather than trusting it.
    local s = util.EnsureSegs(util.segN)[util.segN]
    if not s then return end
    s.icon:SetTexture(icon)
    if s.icon.SetDesaturated then s.icon:SetDesaturated(desat or false) end
    s.icon:SetAlpha(desat and 0.5 or 1)
    if tint then
        s.icon:SetVertexColor(tint[1], tint[2], tint[3], 1)
    else
        s.icon:SetVertexColor(1, 1, 1, 1)
    end
    s.text:SetText(text or "")
    s.icon:Show()
    s.text:Show()
end

-- The right-aligned Commander chrome is a hard wall, and the cluster shares
-- the left block, so a segment that would run under the gear is dropped along
-- with everything after it — a truncated banner beats an overlapping one.
-- Layers fill segments most-urgent-first, so what survives is what matters.
function util.TruncSegs(segX)
    local segs = root.hdrSegs
    if not segs then return end
    local chromeW = 0
    if blizz and blizz.btn and blizz.btn:IsShown() then chromeW = chromeW + 12 + 3 end
    if settingsBtn and settingsBtn:IsShown() then chromeW = chromeW + 12 + 3 end
    local limit = FrameWidth() - (PAD - 3) - chromeW
    -- segN is what the layer ASKED for; #segs is what it actually got. They
    -- diverge whenever a banner runs past MAX_SEGS, and walking segN over the
    -- pool is an index into nil.
    local n, x = math.min(util.segN, #segs), segX
    for i = 1, n do
        local s = segs[i]
        local tw = (s.text.GetStringWidth and s.text:GetStringWidth()) or 0
        local w = 12 + 2 + tw
        if x + w > limit then n = i - 1; break end
        x = x + w + 8
    end
    for i = n + 1, #segs do
        segs[i].icon:Hide()
        segs[i].text:Hide()
    end
end

-- A cooldown as one banner segment: lit and bare when it is ready, dimmed
-- with the time left when it is not. The mage banner's armor ring is its own
-- special case; everything else reads better as the ability strip's grammar.
function util.SegCooldown(name, icon, cd, now)
    local start, duration = GetSpellCooldown and GetSpellCooldown(name)
    local left = 0
    if start and duration and duration > 1.5 then left = start + duration - now end
    if left <= 0 then
        util.Seg(icon, false, nil)
        return
    end
    local txt = left >= 90 and string.format("%dm", math.floor(left / 60 + 0.5))
        or string.format("%d", math.floor(left + 0.5))
    util.Seg(icon, true, txt)
end

-- The banner's whole cooldown run, shared by every layer that has one. The
-- book was filtered to trained spells at login and each layer owns its own
-- toggle (SDATA.BANNER_CD_KEY), so what was four identical loops is one.
function util.SegCds(now)
    local key = SDATA.BANNER_CD_KEY[layer or ""]
    if key and not DB(key, true) then return end
    for _, e in ipairs(strip.cds) do
        util.SegCooldown(e.name, e.icon, e.cd, now)
    end
end

-- Per-draw refresh of everything insecure on the utility cluster: the
-- inventory counters and the bandage lockout. Deliberately separate from the
-- bind pass — these keep updating mid-combat, exactly when a frozen binding
-- would otherwise leave the button lying about what it will do.
function util.Paint(now)
    local show = DB("ShowUtilityCounts", true)
    local c = util.counts
    local function put(fs, n)
        if not fs then return end
        if show and n and n > 0 then
            fs:SetText(n > 99 and "99+" or tostring(n))
            fs:Show()
        else
            fs:Hide()
        end
    end
    if consumeBtn then
        put(consumeBtn.count, c.foodN)
        consumeBtn.tip1 = string.format("Left-click: drink  (%d)", c.waterN or 0)
        consumeBtn.tip2 = string.format("Right-click: eat  (%d)", c.foodN or 0)
    end
    if conjureBtn then
        put(conjureBtn.count, c.waterN)
        conjureBtn.tip1 = string.format("Left-click: Conjure Water  (%d held)", c.waterN or 0)
        conjureBtn.tip2 = string.format("Right-click: Conjure Food  (%d held)", c.foodN or 0)
    end
    if gemBtn then
        put(gemBtn.count, c.gemN)
        gemBtn.tip1 = (c.gemN or 0) > 0
            and string.format("Left-click: use your best gem  (%d held)", c.gemN)
            or "Left-click: no gem in your bags"
        gemBtn.tip2 = "Right-click (or modifier + left): conjure the next gem in the sequence"
    end
    if not (bandageBtn and bandageBtn.wanted) then return end
    put(bandageBtn.count, c.bandN)
    -- Whoever the click would land on: a living friendly target, else you
    if now >= util.nextBandageScan then
        util.nextBandageScan = now + 0.25
        local unit = "player"
        if UnitExists("target") and UnitIsFriend("player", "target")
            and not UnitIsDeadOrGhost("target") then
            unit = "target"
        end
        util.bandageUnit = unit
        util.bandageUntil = 0
        if util.recentName and C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
            for i = 1, 40 do
                local aura = C_UnitAuras.GetDebuffDataByIndex(unit, i, "HARMFUL")
                if not aura then break end
                if aura.name == util.recentName then
                    util.bandageUntil = aura.expirationTime or 0
                    break
                end
            end
        end
    end
    local left = util.bandageUntil - now
    if left > 0 then
        if bandageBtn._bandEnd ~= util.bandageUntil then
            bandageBtn._bandEnd = util.bandageUntil
            bandageBtn.cd:SetCooldown(util.bandageUntil - 60, 60)
        end
        bandageBtn.cd:Show()
        bandageBtn.icon:SetVertexColor(1, 0.55, 0.55, 1)
    else
        bandageBtn._bandEnd = nil
        bandageBtn.cd:Hide()
        bandageBtn.icon:SetVertexColor(1, 1, 1, 1)
    end
    if bandageBtn.icon.SetDesaturated then
        bandageBtn.icon:SetDesaturated((c.bandN or 0) == 0)
    end
    local who = util.bandageUnit == "target" and (UnitName("target") or "your target") or "you"
    if left > 0 then
        bandageBtn.tip1 = string.format("|cffff8080Recently Bandaged|r on %s — %ds", who, math.ceil(left))
    else
        bandageBtn.tip1 = "Left/Right-click: bandage " .. who
    end
    bandageBtn.tip2 = string.format("%d bandage%s in your bags",
        c.bandN or 0, (c.bandN or 0) == 1 and "" or "s")
    bandageBtn.tip3 = "Middle-click: open First Aid"
end

-- Header gear (any class): opens the settings page through the framework's
-- own bare-slash handler; hideable via the Settings Button option.
-- ---------------------------------------------------------------------------
-- The default party frames. This client runs the retail-style UI framework,
-- so the old PartyMemberFrame1..4 globals DO NOT exist here: the party frames
-- are pooled member frames living inside ONE PartyFrame container (verified
-- against Blizzard_UnitFrame/Shared/PartyFrame.lua and the Classic TOC's
-- file list on wow-ui-source's classic_anniversary branch).
--
-- Hiding that container is the whole job, and it is what keeps this safe: the
-- member frames are protected unit buttons, but we never touch one. They may
-- Show() themselves as often as Blizzard likes behind a hidden parent.
--
-- PartyFrame is the ONLY thing to touch. The raid-style party frame is
-- CompactPartyFrame, and CompactPartyFrame_Generate builds it lazily as a
-- CHILD of PartyFrame ("CreateFrame('Frame', 'CompactPartyFrame', PartyFrame,
-- ...)"), so hiding the parent covers both styles. Naming it separately is
-- not just redundant, it is actively harmful: its template ships
-- hidden="true" and Blizzard only shows it when raid-style party frames are
-- switched on, so anyone calling Show() on it conjures raid frames out of
-- nowhere for everybody else.
--
-- Hence the rule this code follows: only ever re-show a frame we hid
-- ourselves, while it was showing. We never decide that something Blizzard
-- was keeping hidden ought to be visible.
--
-- Everything here is gated on combat. PartyFrame itself is insecure, but it
-- parents secure buttons, and a settings toggle has no business finding out
-- exactly where the engine draws that line.
--
-- One chunk local, holding both state and functions: this file sits close to
-- Lua's 200-local cap (see the SDATA note at the top).
-- ---------------------------------------------------------------------------
blizz = { names = { "PartyFrame" }, hooked = {}, hidByUs = {}, dirty = false }

-- Effective state, not the raw setting: with the module switched off the
-- board is gone, so leaving the default frames hidden would leave the player
-- with no party frames at all.
function blizz.Hidden()
    return (CommanderPartyFramesDB and CommanderPartyFramesDB.EnableShield
        and DB("HideBlizzardParty", false)) and true or false
end

-- Glyph: three stacked rows (the default frames), struck through when they
-- are hidden. Drawn from tinted quads rather than a texture file — the suite
-- convention, since art paths move across patches. The lit tint is the gear's
-- exact grey so the two read as one set of controls.
function blizz.Paint()
    local b = blizz.btn
    if not b then return end
    local hidden = blizz.Hidden()
    for _, bar in ipairs(b.bars) do
        bar:SetColorTexture(0.8, 0.8, 0.8, hidden and 0.22 or 0.9)
    end
    b.slash:SetShown(hidden)
end

function blizz.Apply()
    if InCombat() then blizz.dirty = true; blizz.Paint(); return end
    blizz.dirty = false
    local hide = blizz.Hidden()
    for _, name in ipairs(blizz.names) do
        local f = _G[name]
        if f then
            if not blizz.hooked[name] then
                blizz.hooked[name] = true
                -- Blizzard re-shows the container on its own (roster changes,
                -- leaving Edit Mode). The hook makes the setting stick without
                -- us having to know every path that calls Show().
                f:HookScript("OnShow", function(self)
                    if blizz.Hidden() and not InCombat() then
                        -- Marked as ours, or a frame Blizzard raised while
                        -- the toggle was on could never be given back
                        blizz.hidByUs[name] = true
                        self:Hide()
                    end
                end)
            end
            -- Strictly symmetric: hide only what is currently showing, and
            -- restore only what that hid. A frame already down when we got
            -- here stays down — it is not ours to reveal.
            if hide then
                if f:IsShown() then blizz.hidByUs[name] = true; f:Hide() end
            elseif blizz.hidByUs[name] then
                blizz.hidByUs[name] = nil
                f:Show()   -- PartyFrame's own OnShow re-initializes its members
            end
        end
    end
    blizz.Paint()
end

function blizz.Toggle()
    if InCombat() then
        print("|cff66ccffCommander Party Frames|r: the default party frames can only be toggled out of combat.")
        return
    end
    if not CommanderPartyFramesDB then return end
    CommanderPartyFramesDB.HideBlizzardParty = not DB("HideBlizzardParty", false)
    blizz.Apply()
    print(blizz.Hidden()
        and "|cff66ccffCommander Party Frames|r: default party frames |cffff7f50hidden|r."
        or "|cff66ccffCommander Party Frames|r: default party frames |cff33ff33shown|r.")
end

-- Escape hatch for the settings page and /cpf blizzard: the header button
-- rides the board, and the board is Priest/Mage/Druid/Paladin only (and can
-- hide itself).
function CommanderPartyFrames_ToggleBlizzardParty()
    blizz.Toggle()
end

function blizz.EnsureButton()
    if blizz.btn or not profile then return end
    -- Sized and tinted to sit beside the gear as a matching pair: same 12x12
    -- footprint, same grey, same highlight. Each row spans the button via
    -- LEFT+RIGHT anchors (inset a little) rather than a width — two
    -- horizontal anchors settle the width however the size resolves, which is
    -- what turns these into rows instead of specks. SetColorTexture needs no
    -- art file, so there is no path to go stale.
    local b = CreateFrame("Button", nil, root)
    b:SetSize(12, 12)
    b.bars = {}
    for i = 1, 3 do
        local t = b:CreateTexture(nil, "ARTWORK")
        local y = 3 - (i - 1) * 3
        t:SetPoint("LEFT", b, "LEFT", 1, y)
        t:SetPoint("RIGHT", b, "RIGHT", -1, y)
        t:SetHeight(2)
        b.bars[i] = t
    end
    b.slash = b:CreateTexture(nil, "OVERLAY")
    b.slash:SetColorTexture(0.85, 0.40, 0.35, 0.9)
    b.slash:SetWidth(15)
    b.slash:SetHeight(1.5)
    b.slash:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.slash:SetRotation(math.rad(-40))
    b.slash:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.25)
    b:SetScript("OnClick", function() blizz.Toggle() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText(blizz.Hidden() and "Default party frames: hidden"
            or "Default party frames: shown")
        GameTooltip:AddLine("Click to toggle. Out of combat only; also |cffffd100/cpf blizzard|r.",
            0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    blizz.btn = b
    blizz.Paint()
end

local function EnsureSettingsButton()
    if settingsBtn or not profile then return end
    settingsBtn = CreateFrame("Button", nil, root)
    settingsBtn:SetSize(12, 12)
    settingsBtn:SetPoint("TOPRIGHT", root, "TOPRIGHT", -(PAD - 3), -1.5)
    -- The cog is DRAWN, not loaded. It used to be Interface\WorldMap\
    -- Gear_64Grey, which is Cataclysm-era world-map art: this client runs the
    -- retail-style UI framework, that folder no longer ships it, and a texture
    -- path that does not resolve draws nothing at all — leaving a button that
    -- was present, positioned and clickable but completely invisible. Every
    -- other piece of chrome on this header (the stacked-rows toggle beside it)
    -- already builds its glyph from SetColorTexture quads, which need no art
    -- file and so have no path to go stale. This one now matches.
    --
    -- Four bars through the center at 45-degree steps give eight teeth; the
    -- hub sits on top. They overlap at the middle, and the extra blend there
    -- is wanted — it is what reads as the cog's hub rather than an asterisk.
    settingsBtn.cog = {}
    for i = 1, 4 do
        local t = settingsBtn:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(0.8, 0.8, 0.8, 0.75)
        t:SetSize(2.5, 12)
        t:SetPoint("CENTER", settingsBtn, "CENTER", 0, 0)
        t:SetRotation(math.rad((i - 1) * 45))
        settingsBtn.cog[i] = t
    end
    settingsBtn.hub = settingsBtn:CreateTexture(nil, "OVERLAY")
    settingsBtn.hub:SetColorTexture(0.8, 0.8, 0.8, 0.9)
    settingsBtn.hub:SetSize(6, 6)
    settingsBtn.hub:SetPoint("CENTER", settingsBtn, "CENTER", 0, 0)
    local hl = settingsBtn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(settingsBtn)
    hl:SetColorTexture(1, 1, 1, 0.25)
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

-- Middle-click opens First Aid itself. A craft popout used to sit here, but
-- the tradeskill list can only be read while that window is already open —
-- with it shut the popout offered exactly one line, "Open First Aid", and
-- with it open the real window was already on screen. So: skip the middleman.
function util.FirstAidName()
    return (GetSpellInfo and GetSpellInfo(SDATA.FIRST_AID_ID)) or "First Aid"
end

function util.OpenFirstAid()
    if InCombat() then return end
    if CastSpellByName then CastSpellByName(util.FirstAidName()) end
end

local function EnsureMageUtilButtons()
    if mageUtil or not profile then return end
    -- The container is a SIBLING of the board, not a child of it — pinned to
    -- root's rect, so it still behaves like one.
    --
    -- Parenting it to root would hang secure buttons under the board, and
    -- protection walks UP: root would inherit it and could then be neither
    -- resized nor shown mid-fight. That is not academic — a party member
    -- appearing during a fight made the rows outgrow a frame that could not
    -- follow them, and the bottom row hung outside its own border until
    -- combat dropped. As a sibling it takes its protection with it and leaves
    -- root a plain frame (Click-Cast is the exception, and there the row set
    -- is already fixed out of combat, so root never needs to resize).
    --
    -- The cost of not being a child is that root's scale and visibility no
    -- longer arrive for free: SyncCluster below carries the scale, and the
    -- draw pass folds the board's own visibility into the header flag.
    mageUtil = CreateFrame("Frame", nil, UIParent)
    mageUtil:SetAllPoints(root)
    mageUtil:SetFrameStrata(root:GetFrameStrata() or "MEDIUM")
    -- Above the board's rows, below the HUD chrome's drag overlay (root + 20)
    mageUtil:SetFrameLevel((root:GetFrameLevel() or 1) + 5)
    local function mkBtn(name, tipTitle, tip1, tip2, width)
        local b = CreateFrame("Button", name, mageUtil, "SecureActionButtonTemplate")
        b:SetSize(width or 13, 13)
        -- Release only. Registering both edges fires the click TWICE per tap,
        -- which double-cast the secure buttons and made the popout toggles
        -- flip twice — open-then-shut on a clean tap, and stuck open whenever
        -- the mouse drifted off the button before release, so only the press
        -- landed. The armor toggle never had it: it is a plain Button.
        b:RegisterForClicks("AnyUp")
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(13, 13)
        b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        util.StyleIcon(b.icon)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(b)
        hl:SetTexture("Interface\\Buttons\\WHITE8X8")
        hl:SetVertexColor(1, 1, 1, 0.25)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:SetText(tipTitle)
            GameTooltip:AddLine(self.tip1 or tip1, 0.8, 0.8, 0.8)
            GameTooltip:AddLine(self.tip2 or tip2, 0.8, 0.8, 0.8)
            if self.tip3 then GameTooltip:AddLine(self.tip3, 0.8, 0.8, 0.8) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Provisional anchor so a button is never unpositioned; the real
        -- right-to-left layout replaces it on the first bind pass
        b:SetPoint("TOPRIGHT", root, "TOPRIGHT", -(PAD - 2), -1)
        b.wanted = true
        return b
    end
    -- Counter text over an icon corner: outlined so it stays legible on the
    -- art, and insecure, so it keeps updating while the binds are frozen.
    -- The template's own size buries a 13px icon, so it is shrunk to 8 — with
    -- the font object kept as the fallback if the face fails to load.
    local function mkCount(b, point, r, g, bl)
        local fs = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        local face = fs:GetFont()
        if face then
            fs:SetFont(face, 8, "OUTLINE")
            if not fs:GetFont() then fs:SetFontObject("NumberFontNormalSmall") end
        end
        fs:SetPoint(point, b, point, point == "BOTTOMLEFT" and -1 or 1, -1)
        fs:SetTextColor(r, g, bl)
        fs:Hide()
        return fs
    end

    -- Bandage: every class gets it (First Aid is universal)
    bandageBtn = mkBtn("CommanderPartyFramesBandage", "Bandage",
        "Left/Right-click: bandage your friendly target, else yourself",
        "Middle-click: open First Aid")
    bandageBtn.count = mkCount(bandageBtn, "BOTTOMRIGHT", 1, 1, 1)
    bandageBtn.cd = CreateFrame("Cooldown", nil, bandageBtn, "CooldownFrameTemplate")
    bandageBtn.cd:SetAllPoints(bandageBtn.icon)
    if bandageBtn.cd.SetHideCountdownNumbers then bandageBtn.cd:SetHideCountdownNumbers(true) end
    bandageBtn.cd:Hide()

    -- PostClick, never OnClick: the template owns OnClick and overwriting it
    -- would silently kill the secure use
    bandageBtn:SetScript("PostClick", function(_, button)
        if button == "MiddleButton" then
            if util.portalPop then SafeSetShown(util.portalPop, false) end
            util.OpenFirstAid()
        end
    end)

    if layer == "INT" then
        -- One tally per button rather than both on Consume, where they
        -- collided: water (blue) rides Conjure, food (amber) rides Consume
        consumeBtn = mkBtn("CommanderPartyFramesConsume", "Consume",
            "Left-click: drink", "Right-click: eat", 16)
        consumeBtn.count = mkCount(consumeBtn, "BOTTOMRIGHT", 1, 0.82, 0.45)
        conjureBtn = mkBtn("CommanderPartyFramesConjure", "Conjure",
            "Left-click: Conjure Water", "Right-click: Conjure Food")
        conjureBtn.count = mkCount(conjureBtn, "BOTTOMRIGHT", 0.45, 0.75, 1)
        gemBtn = mkBtn("CommanderPartyFramesGem", "Mana Gem",
            "Left-click: use your best gem",
            "Right-click (or modifier + left): conjure the next gem in the sequence")
        gemBtn.count = mkCount(gemBtn, "BOTTOMRIGHT", 1, 1, 1)
        util.portalBtn = mkBtn("CommanderPartyFramesPortal", "Portals & Teleports",
            "Click: open the destination list", "Top row teleports, bottom row portals")
        -- The portal button opens an insecure popout; PostClick keeps the
        -- (unused) secure path intact
        util.portalBtn:SetScript("PostClick", function()
            SafeSetShown(util.portalPop, not util.portalPop:IsShown())
        end)
        util.portalBtn.icon:SetTexture("Interface\\Icons\\Spell_Arcane_PortalStormwind")

        -- Siblings for the same reason as the container: secure children
        util.portalPop = CreateFrame("Frame", nil, UIParent)
        util.portalPop:SetFrameStrata("DIALOG")
        util.portalPop:SetSize(24, 45)
        util.portalPop:SetPoint("TOPRIGHT", root, "TOPRIGHT", -(PAD - 2), -(HEADER_H + 3))
        local ppbg = util.portalPop:CreateTexture(nil, "BACKGROUND")
        ppbg:SetAllPoints(util.portalPop)
        ppbg:SetTexture("Interface\\Buttons\\WHITE8X8")
        ppbg:SetVertexColor(0, 0, 0, 0.75)
        util.portalPop:Hide()

        armorPop = CreateFrame("Frame", nil, UIParent)
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
    end
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
    -- Every supported layer gets the removable-debuff and CC escalation now:
    -- what a row is FOR differs per class, but "there is something on them I
    -- can take off" and "a teammate is in crowd control" are the same two
    -- facts on every board. The own-aura strip runs for whichever layers
    -- brought a book to fill it.
    local intOn = layer and true or false
    local stripOn = SDATA.STRIP_BOOKS[layer or ""] and true or false
    local isPlayer = guid == playerGUID
    -- Ally buffs are read off the registry now: one pass fills a scratch pair
    -- keyed by buff, whatever class this is (see SDATA.CLASS_BUFFS)
    local buffOn = #SDATA.BUFF_ACTIVE > 0
    local armorFound, formFound, auraFound, sealFound
    wipe(scanAbsorbs)
    if buffOn then wipe(util.buffExp); wipe(util.buffDur) end
    if stripOn then wipe(strip.scan) end
    for i = 1, 40 do
        local aura = C_UnitAuras.GetBuffDataByIndex(unit, i, "HELPFUL")
        if not aura then break end
        if aura.name == PWS_NAME and not pwsExpire then
            pwsExpire = aura.expirationTime
            pwsSpellId = aura.spellId
            pwsMine = aura.sourceUnit and UnitIsUnit(aura.sourceUnit, "player") or false
            pwsIndex = i
        elseif buffOn and SDATA.BUFF_BY_NAME[aura.name]
            and not util.buffExp[SDATA.BUFF_BY_NAME[aura.name].key] then
            -- Any caster's buff counts as covered, and the group version
            -- satisfies the same slot as the single (both map to one def)
            local bkey = SDATA.BUFF_BY_NAME[aura.name].key
            util.buffExp[bkey] = aura.expirationTime or 0
            util.buffDur[bkey] = aura.duration
        elseif isPlayer and not armorFound and armorNames[aura.name] then
            armorFound = { icon = armorNames[aura.name], expire = aura.expirationTime,
                duration = aura.duration }
        end
        -- The paladin's own aura and seal (banner segments). Read off
        -- ourselves like the mage's armor and the druid's form, and for the
        -- same reason: they are states you chose that nothing else on the
        -- board would ever tell you about.
        if layer == "BLESS" and isPlayer then
            if not auraFound and strip.auraNames[aura.name] then
                local a = strip.auraNames[aura.name]
                auraFound = { key = a.key, icon = aura.icon or a.icon }
            elseif not sealFound and strip.sealNames[aura.name] then
                local s = strip.sealNames[aura.name]
                sealFound = { key = s.key, icon = aura.icon or s.icon,
                    expire = aura.expirationTime, duration = aura.duration }
            end
        end
        -- OURS only: the strip exists to answer "what have I got on this ally
        -- right now" — another druid's Rejuvenation does not gate our next
        -- global, and another paladin's Freedom does not spend our cooldown —
        -- so sourceUnit decides membership exactly the way the Renew tracker
        -- does. No early break: these sit anywhere in the aura list.
        local stripDef = stripOn and strip.names[aura.name]
        if stripDef and not strip.scan[stripDef.key]
            and aura.sourceUnit and UnitIsUnit(aura.sourceUnit, "player") then
            strip.scan[stripDef.key] = { expire = aura.expirationTime, duration = aura.duration,
                icon = aura.icon or stripDef.icon,
                stacks = aura.applications or aura.charges or 0 }
        end
        -- The player's own form (HOT layer): the banner's first segment, and
        -- the only aura on this pass we read off ourselves rather than an ally
        if layer == "HOT" and isPlayer and not formFound and strip.forms[aura.name] then
            formFound = strip.forms[aura.name]
        end
        -- Spec inference from visible marker auras (Shadowform, forms, Tree…)
        -- Self-sourced only: party-wide/target-castable markers (Trueshot
        -- Aura, Power Infusion) would stamp their CARRIER otherwise
        if specMarkerNames[aura.name] and aura.sourceUnit and UnitIsUnit(aura.sourceUnit, unit) then
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

    -- Our armor / our form (upkeep banners); the player's own scan is always
    -- reliable, so absence here genuinely means "naked" / "caster form"
    -- The mage's armor and the priest's Inner Fire commit through one slot:
    -- both are "the self-buff this layer's banner watches", and only one
    -- layer's names are ever in the map (see SDATA.SELF_ARMOR).
    if SDATA.SELF_ARMOR[layer or ""] and isPlayer then
        selfArmor = armorFound
    elseif layer == "HOT" and isPlayer then
        strip.form = formFound
    elseif layer == "BLESS" and isPlayer then
        strip.aura, strip.seal = auraFound, sealFound
    end

    -- Our hots on this unit, under the same reliable contract as everything
    -- else: a scan that could not see the unit returns no auras, and that
    -- must not wipe a live record. A scan that COULD see them is the whole
    -- truth, so the record is rebuilt rather than merged — otherwise a hot
    -- that ticked away would linger on the strip forever.
    if stripOn then
        if next(strip.scan) then
            local rec = strip.state[guid]
            if not rec then rec = {}; strip.state[guid] = rec end
            wipe(rec)
            for key, e in pairs(strip.scan) do rec[key] = e end
        elseif reliable then
            strip.state[guid] = nil
        end
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

    -- Ally-buff upkeep, under the same reliable contract as everything else:
    -- absence only prunes when the scan could actually see the unit. Entry
    -- tables are reused rather than rebuilt, because this runs per unit on
    -- every UNIT_AURA.
    if buffOn then
        if next(util.buffExp) then
            local rec = intState[guid]
            if not rec then rec = {}; intState[guid] = rec end
            for k, exp in pairs(util.buffExp) do
                local slot = rec[k]
                if not slot then slot = {}; rec[k] = slot end
                slot.expire, slot.duration = exp, util.buffDur[k]
            end
            if reliable then
                for k in pairs(rec) do
                    if util.buffExp[k] == nil then rec[k] = nil end
                end
            end
        elseif reliable then
            intState[guid] = nil
        end
    end

    local wsExpire
    local dispelOn = DB("ShowDispels", false)
    local showAllDebuffs = DB("DispelShowAll", false)
    local showImportant = DB("DispelShowImportant", true)
    local curseExpire, curseDuration, curseSchool
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
            -- No early break: lockout debuffs (Hypothermia/Forbearance) can
            -- sit anywhere in the list on ANY layer
        end
        -- CURSED state feed: track the first removable debuff independently of
        -- the strip, which caps at MAX_DISPEL_ICONS — a curse buried under a
        -- full strip (or with the strip off) must still turn the row purple
        if intOn and not curseExpire then
            local dt = aura.dispelName
            if dt and dt ~= "" and myDispelTypes[dt] then
                curseExpire = aura.expirationTime or 0
                curseDuration = aura.duration
                -- A mage removes one school so this is always "Curse"; a
                -- druid removes two, and which one it is changes the row's
                -- color and the spell you press, so the school is kept
                curseSchool = dt
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
            c.expire, c.duration, c.dispelName = curseExpire, curseDuration, curseSchool
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

    -- Ability-bar lockouts commit with the same reliable contract (chassis:
    -- the priest board needs its paladin's Forbearance too)
    if hypoExpire or forbExpire then
        local l = lockState[guid]
        if not l then l = {}; lockState[guid] = l end
        l.hypo, l.forb = hypoExpire, forbExpire
    elseif reliable then
        lockState[guid] = nil
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
    -- Pets are scanned like any other ally (their shields, their buff, the
    -- curse on them) but deliberately stay OUT of groupGuids: that table feeds
    -- the combat log's class-keyed ability inference, and a pet has no class
    -- ability book to stamp.
    local pets = DB("IncludePets", true)
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists(u) then
                local g = UnitGUID and UnitGUID(u)
                if g then groupGuids[g] = select(2, UnitClass(u)) or true end
                ScanUnit(u, IsReliable(u))
                local p = "raidpet" .. i
                if pets and UnitExists(p) then ScanUnit(p, IsReliable(p)) end
            end
        end
    elseif IsInGroup and IsInGroup() then
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) then
                local g = UnitGUID and UnitGUID(u)
                if g then groupGuids[g] = select(2, UnitClass(u)) or true end
                ScanUnit(u, IsReliable(u))
                local p = "partypet" .. i
                if pets and UnitExists(p) then ScanUnit(p, IsReliable(p)) end
            end
        end
    end
    ScanUnit("player", true)
    if pets and UnitExists("pet") then ScanUnit("pet", IsReliable("pet")) end
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
    -- Shadow damage from OFF the team. Reading the school off the log is the
    -- only detection that works on both halves of the problem: a warlock is
    -- obvious from their class, but a shadow priest looks exactly like a
    -- healer until they cast, and Shadow Protection is for both. Sixty seconds
    -- of memory, because an arena team does not stop being a shadow team
    -- between casts.
    if (subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE")
        and a3 and sourceGUID and not groupGuids[sourceGUID] then
        local shadow = a3 == 32
        if not shadow and bit and bit.band then
            shadow = bit.band(a3, 32) ~= 0
        end
        if shadow then util.enemyShadowUntil = GetTime() + 60 end
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
        -- Fortitude / Spirit / Shadow Protection ride the same registry strip
        -- the other two layers use
        util.ResolveBuffs(r, now)
    end

    local ws = wsState[guid]
    if ws and ws <= now then wsState[guid], ws = nil, nil end
    r.wsLeft = ws and (ws - now) or 0

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

-- Absorb totals: compact thousands
local function FormatAmount(v)
    if v >= 10000 then return string.format("%.0fk", v / 1000) end
    if v >= 1000 then return string.format("%.1fk", v / 1000) end
    return tostring(math.floor(v + 0.5))
end

-- The alert ladder shared by both buff layers (INT and HOT), applied on top
-- of whatever the layer already decided the row was. Two things outrank a
-- board's own subject matter, in this order:
--   1. A debuff YOU can remove. That is your action, right now, and it is the
--      loudest thing on the row. A mage removes one school, so the row is
--      always purple; a druid removes two, and green POISONED vs purple
--      CURSED is the difference between Abolish Poison and Remove Curse.
--   2. A teammate in crowd control — awareness rather than an action, so it
--      yields to the dispel above it, but in arena it reshapes the next three
--      seconds and must escalate even with the icon strip switched off.
-- Both feeds are cap-independent (ScanUnit fills them regardless of how many
-- icons the strip can show); expire == 0 means "no readable clock" and stays
-- live until a reliable rescan clears it.
local function ApplyAlertStates(r, now)
    local c = curseState[r.guid]
    if c and c.expire and c.expire > 0 and c.expire <= now then
        curseState[r.guid], c = nil, nil
    end
    if c then
        -- Whichever school it is, in its own colour and its own word. An
        -- unrecognised school still escalates — the point is that something
        -- removable is on them — and falls back to the purple the board has
        -- always used for "there is a debuff here you can take off".
        local kind = DISPEL_STATE_BY_SCHOOL[c.dispelName or ""]
            or DISPEL_STATE_BY_SCHOOL.Curse
        r.state = kind.state
        r.mainText = kind.word
        if c.expire and c.expire > now then
            r.wsLeft = c.expire - now
            if c.duration and c.duration > 0 then r.lockMax = c.duration end
            r.rightText = string.format("%ds", math.ceil(r.wsLeft))
        end
        intCurses = intCurses + 1
    end

    local cc = ccState[r.guid]
    if cc and cc.expire and cc.expire > 0 and cc.expire <= now then
        ccState[r.guid], cc = nil, nil
    end
    if cc then
        intCCs = intCCs + 1
        if not DISPEL_STATES[r.state] then
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
end

-- ---------------------------------------------------------------------------
-- The buff advisor. A missing buff is one fact; whether a good player would
-- have cast it BY NOW is a different one, and it is the second that deserves
-- red. Each registry entry names the rule its slot asks, and every rule
-- answers the same question: given this target and this fight, is the absence
-- of this buff currently costing us something?
--
-- The rules are deliberately conservative. A slot that reddens on everyone all
-- match is a slot nobody reads, so the situational buffs stay neutral-dark
-- until their condition is actually observed — never red on a guess. Anything
-- the client cannot tell us yet reads as "not urgent".
--
-- Melee classes for the Thorns rule: Thorns pays out per melee swing taken, so
-- it belongs on whoever is being hit, which in arena is the target the enemy
-- melee has picked.
SDATA.MELEE_CLASSES = {
    WARRIOR = true, ROGUE = true, PALADIN = true, SHAMAN = true,
    DRUID = true, HUNTER = true,
}
--
-- Every rule returns (urgent, reason). The reason is not decoration: a slot
-- that turns red without being able to say why is a slot you learn to ignore,
-- and it is what /cpf buffs prints back.
SDATA.BUFF_ADVICE = {
    -- The raid buffs: there is no situation where you would rather not have
    -- them, so missing IS urgent. This is the honest answer for Fortitude,
    -- Intellect, Spirit and Mark — a pro does not leave them off.
    ALWAYS = function() return true, "always worth a global" end,

    -- Thorns: worth a global on whoever is actually eating melee swings. That
    -- is the ally an enemy is parked on, or failing that a wounded melee ally,
    -- who is trading hits by default. A caster nobody is touching is not it.
    VS_MELEE = function(r)
        if r.meleeOnMe then return true, "an enemy melee is on them" end
        if r.class and SDATA.MELEE_CLASSES[r.class] and (r.health or 1) < 1 then
            return true, "a wounded melee ally is trading hits"
        end
        return false, "nothing is meleeing them"
    end,

    -- The three comp-reading rules. Shadow Protection only pays against a
    -- shadow team; Amplify Magic is free healing ONLY when the enemy deals no
    -- magic damage to punish it; Dampen Magic is the answer to burst casters.
    -- Each needs to know what the other side is made of (see the enemy-comp
    -- scanner) — until it has an answer they stay neutral rather than guess.
    -- Fear Ward: worth pre-casting against anything that fears. Warlocks and
    -- priests both bring it, and a warrior's Intimidating Shout counts too.
    VS_FEAR = function()
        if util.EnemyHas("FEAR") then return true, "the enemy team brings a fear" end
        return false, not util.EnemySeen() and "enemy team unknown"
            or "nothing on the other side fears"
    end,

    VS_SHADOW = function()
        if util.EnemyHas("SHADOW") then return true, "the enemy deals shadow damage" end
        return false, not util.EnemySeen() and "enemy team unknown"
            or "no shadow damage on the other side"
    end,
    VS_PHYSICAL = function()
        if util.EnemyIsPhysical() then return true, "the enemy team is all physical" end
        return false, not util.EnemySeen() and "enemy team unknown"
            or "an enemy caster would punish it"
    end,
    VS_CASTER = function()
        if util.EnemyHas("CASTER") then return true, "there are enemy casters to blunt" end
        return false, not util.EnemySeen() and "enemy team unknown"
            or "no enemy casters to blunt"
    end,
}

-- Ask one slot's rule whether its absence is urgent. Wrapped so a rule that
-- errors can never take the board down with it: a bad advisor degrades to
-- "not urgent", which is the same as having the feature off.
-- Is the CASTER, rather than the target, the reason this cannot happen? Right
-- now that means one thing: a druid in bear, cat or travel form cannot cast
-- any of this, and the upkeep banner is already showing them a red form
-- segment about it. Reddening every buff on every row on top of that is the
-- same complaint six more times.
function util.CastBlocked()
    if layer == "HOT" and strip.form and not strip.form.heals then
        return "you are shifted out of caster form"
    end
    return nil
end

-- Is this buff even FOR this ally? Three answers so far, and each of them is
-- the difference between a strip that reads and one that nags:
--   MANA   the mana users (Intellect, Spirit, Wisdom)
--   MELEE  whoever swings a weapon (Might). A pet always counts — every pet
--          in the game melees, and a pet has no class of its own to ask.
--   ALL    everybody, which is most of the registry.
function util.BuffApplies(def, r)
    local t = def.targets
    if t == "MANA" then return r.manaUser and true or false end
    if t == "MELEE" then
        if r.isPet then return true end
        return (r.class and SDATA.MELEE_CLASSES[r.class]) and true or false
    end
    return true
end

function util.AdviseBuff(def, r, rec)
    -- Urgency you cannot act on is not urgency. Three ways that happens, and
    -- all of them mean the same thing to a slot: report the absence, do not
    -- demand anything about it.
    --
    --   1. The ally is out of range — red there is a slot crying about
    --      physics, and it trains you to ignore the colour.
    --   2. You are in a form that cannot cast (druid).
    --   3. The spell itself is cooling down. Only a REAL cooldown counts: the
    --      global is on everything you press and would blink every slot dark
    --      twice a second, so anything at or under two seconds is ignored.
    if r.outOfCastRange then return false, "out of range" end
    local blocked = util.CastBlocked()
    if blocked then return false, blocked end
    if def.id and GetSpellCooldown then
        local ok, start, dur = pcall(GetSpellCooldown, def.id)
        if ok and start and start > 0 and dur and dur > 2
            and (start + dur) > GetTime() then
            return false, "on cooldown"
        end
    end
    -- A buff whose sibling is doing the job is not missing, it is SUPERSEDED:
    -- Amplify and Dampen overwrite each other, so a target carrying one must
    -- never light up asking for the other.
    if def.excludes and rec and rec[def.excludes] then
        local sib = rec[def.excludes]
        if not (sib.expire and sib.expire > 0 and sib.expire <= GetTime()) then
            return false, "its sibling is already up"
        end
    end
    -- Same idea one size up: a whole FAMILY where only one member may be on a
    -- target at a time. A paladin gets exactly one blessing per ally, so an
    -- ally carrying Kings is not missing Might — asking for both would be
    -- asking for something the game will not let you have.
    if def.oneOf and rec then
        for _, other in ipairs(SDATA.BUFF_ACTIVE) do
            if other ~= def and other.oneOf == def.oneOf then
                local sib = rec[other.key]
                if sib and not (sib.expire and sib.expire > 0 and sib.expire <= GetTime()) then
                    return false, "they already carry your " .. (other.label or other.key)
                end
            end
        end
    end
    local rule = def.advise and SDATA.BUFF_ADVICE[def.advise]
    if not rule then return false end
    local ok, urgent, why = pcall(rule, r)
    if not ok then return false, "rule errored" end
    return urgent and true or false, why
end

-- Resolve this row's ally-buff strip: one entry per TRACKED buff, in registry
-- order, present whether or not the buff is up. A slot that vanishes when its
-- buff falls off leaves a hole exactly where the answer should be, and shuffles
-- every icon to its right — so the strip's shape is fixed by the settings, not
-- by what happens to be running.
--
-- `r.buffMissing` is the row-level summary the action glow reads: anything
-- tracked that is absent or inside its rebuff window.
function util.ResolveBuffs(r, now)
    local n = #SDATA.BUFF_ACTIVE
    if n == 0 or r.selfSpell then r.buffCount = 0; return end
    local rec = intState[r.guid]
    local rebuffAt = DB("IntRefreshAt", 300)
    r.buffs = r.buffs or {}
    local shown = 0
    for i = 1, n do
        local def = SDATA.BUFF_ACTIVE[i]
        -- A buff nobody would cast here earns no slot at all: Intellect and
        -- Spirit are for mana users, Blessing of Might is for people who swing
        -- things, and a rogue's row should not carry a permanent dark reminder
        -- of a spell that does nothing for them.
        if util.BuffApplies(def, r) then
            shown = shown + 1
            local slot = r.buffs[shown]
            if not slot then slot = {}; r.buffs[shown] = slot end
            local e = rec and rec[def.key]
            local left
            if e and e.expire and e.expire > 0 then
                left = e.expire - now
                if left <= 0 then rec[def.key], e, left = nil, nil, nil end
            end
            slot.def = def
            slot.icon = def.icon
            slot.up = e and true or false
            -- expire 0 is a permanent aura (no readable clock): up, no sweep
            slot.expire = e and e.expire or nil
            slot.duration = (e and e.duration and e.duration > 0) and e.duration or def.duration
            slot.due = (left and left <= rebuffAt) or false
            if not slot.up then
                r.buffMissing = true
                if util.BuffAdvised(def) then
                    slot.urgent, slot.why = util.AdviseBuff(def, r, rec)
                else
                    slot.urgent, slot.why = false, "advisor off for this buff"
                end
                if slot.urgent then r.buffUrgent = true end
            else
                slot.urgent = false
                if slot.due then r.buffMissing = true end
            end
        end
    end
    if rec and not next(rec) then intState[r.guid] = nil end
    r.buffCount = shown
end

-- Resolve this row's OWN-aura strip: one entry per tracked book entry, in book
-- order, present whether or not the aura is up. Returns how many are up and
-- how long the soonest has left — the two facts a layer needs whether or not
-- it lets them drive the row's state.
--
-- Each entry owns a FIXED slot — Rejuvenation, Regrowth, Lifebloom; Freedom,
-- Protection, Sacrifice; Renew, Prayer of Mending — always in that order, so a
-- missing one leaves a dark placeholder of itself rather than a hole and the
-- strip never reshuffles as things tick off. Position alone then tells you
-- what you are looking at, which is what makes it readable at a glance
-- instead of something you re-parse every time something falls.
--
-- `due` is the per-slot version of the refresh window: on the two layers whose
-- STATE reads the strip it is redundant with the row colour, but the priest
-- board's state is its shield, so the slot itself has to say when a Renew is
-- about to drop. That was the old right-edge Renew icon's whole job.
function util.ResolveStrip(r, now)
    local rec = strip.state[r.guid]
    local n, soonest = 0, nil
    local refreshAt = DB(SDATA.STRIP_REFRESH_KEY[layer or ""] or "RenewRefreshAt", 4)
    r.strip = r.strip or {}
    for i, def in ipairs(SDATA.STRIP_ACTIVE) do
        local slot = r.strip[i]
        if not slot then slot = {}; r.strip[i] = slot end
        local h = rec and rec[def.key]
        if h and h.expire and h.expire > 0 and h.expire <= now then
            rec[def.key], h = nil, nil
        end
        slot.icon = (h and h.icon) or def.icon
        slot.up = h and true or false
        slot.expire = h and h.expire or nil
        slot.duration = h and ((h.duration and h.duration > 0) and h.duration or def.duration) or nil
        slot.stacks = (h and def.stacking) and (h.stacks or 0) or 0
        slot.due = false
        if h then
            n = n + 1
            local tl = h.expire and (h.expire - now) or math.huge
            slot.due = tl <= refreshAt
            if not soonest or tl < soonest then soonest = tl end
        end
    end
    if rec and not next(rec) then strip.state[r.guid] = nil end
    r.stripCount = n
    r.stripSlots = #SDATA.STRIP_ACTIVE
    return n, soonest
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

    -- Ally buffs (Intellect, and Amplify/Dampen when tracked) -> the strip on
    -- the row's left. Deliberately icon-sized: raid upkeep never earns a bar.
    util.ResolveBuffs(r, now)

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

    ApplyAlertStates(r, now)
    return r
end

-- The strip layers (Druid ally rows, Paladin ally rows). Same chassis as INT
-- — health is the bar, mana rides the strip under it, the ally-buff slots
-- carry the class's upkeep — and the same alert ladder tops it. What differs
-- is the middle: the row's managed thing is YOUR auras on that ally, and the
-- states are the priest board's reshield grammar read for them.
--
-- HOT (Druid): READY means a hurt ally is carrying none of yours (cast one
-- now); REFRESH means one is inside the refresh window, which is also exactly
-- the Lifebloom-about-to-bloom case; SHIELDED means it is rolling and you can
-- look elsewhere. A full-health ally with no hots is not a decision, so it
-- stays quiet at OTHER rather than lighting the board up yellow.
--
-- BLESS (Paladin): the same ladder, but the Hands are emergency spells rather
-- than upkeep, so READY is deliberately much stingier — an ally has to be in
-- actual trouble before an empty Freedom slot is a decision. What the paladin
-- board adds is the LOCKOUT half of the priest's grammar, which no other
-- strip layer has: Forbearance. A target carrying it cannot be given
-- Protection and cannot bubble themselves, so a row with nothing up AND
-- Forbearance ticking is EXPOSED (red, drain = the minute running down), and
-- one whose Hand is falling off while locked is FADING. That is the exact
-- Weakened Soul reading the PWS board does, and it is worth just as much
-- here: knowing you cannot BoP is what makes you peel instead.
local function ResolveStripState(r, now)
    if r.dead then
        r.state = "DEAD"
        r.mainText = r.deadText or "DEAD"
        return r
    end

    -- Mark of the Wild, Thorns, the blessings: they ride the same registry
    -- strip every other layer's ally buffs do — a permanent slot each, the
    -- icon never leaving, its sweep carrying what is left and the art going
    -- dark when it is gone.
    util.ResolveBuffs(r, now)

    -- A druid and a paladin both heal through absorbs, so an ally's shields
    -- stay embedded
    ResolveAbsorbSegs(r, now)
    -- ...and the Shield Broke Flash arms off the same edge it does on INT:
    -- the moment an ally's last absorb breaks is the moment to pre-hot them,
    -- so the alert is worth as much here as it is on the mage board
    if r.inShield then r.shieldUp, r.mine = true, true end
    ApplyHealthEmbed(r)
    if r.health and r.health < 1 then
        r.rightText = string.format("%d%%", math.floor(r.health * 100 + 0.5))
    end

    local n, soonest = util.ResolveStrip(r, now)

    -- The paladin's lockout. Forbearance is read off the target rather than
    -- remembered from what we cast, because three different spells stamp it
    -- (Protection, Lay on Hands, their own Divine Shield) and only two of
    -- them are ours. The chassis already scans it for the ability bar, so
    -- this is a lookup, not a second pass.
    local lockLeft = 0
    if layer == "BLESS" then
        local l = lockState[r.guid]
        local forb = l and l.forb
        if forb and forb > now then lockLeft = forb - now end
    end

    -- Is an empty strip a decision on this layer? On HOT, yes for anyone
    -- taking damage: a hot is upkeep and there is always room for another.
    -- On BLESS the Hands are a cooldown you get once a fight, so the bar is
    -- much higher — genuinely hurt, or being chewed on by a melee, which is
    -- the case Protection and Freedom actually answer.
    local wants
    if layer == "BLESS" then
        local hp = r.health or 1
        wants = hp <= (DB("BlessReadyAt", 50) / 100)
            or (r.meleeOnMe and hp <= 0.85)
    else
        wants = (r.health or 1) <= (DB("HotReadyAt", 90) / 100)
    end
    local refreshAt = layer == "BLESS" and DB("BlessRefreshAt", 3)
        or DB("HotRefreshAt", 4)
    local emptyWord = layer == "BLESS" and "HAND" or "HOT"

    if n == 0 then
        -- Nothing of ours here. Only an ally who wants something is a
        -- decision; everyone else is quiet, and among the quiet rows the
        -- sort's time key floats the lowest health to the top.
        if lockLeft > 0 then
            -- Forbearance with nothing up: the priest board's EXPOSED, and it
            -- means the same thing — the answer you would reach for is locked
            -- out, so plan around it rather than pressing it.
            r.state, r.mainText = "EXPOSED", "FORB"
            r.wsLeft, r.lockMax = lockLeft, SDATA.FORBEARANCE_MAX
            r.rightText = string.format("%ds", math.ceil(lockLeft))
            r.tLeft = lockLeft
        elseif wants then
            r.state, r.mainText = "READY", emptyWord
            r.tLeft = (r.health or 1) * 1000
        else
            r.state, r.mainText = "OTHER", ""
            r.tLeft = (r.health or 1) * 1000
        end
    elseif soonest and soonest <= refreshAt then
        -- Urgent rows sort by how long is actually left, not by health.
        -- Expiring while locked out is FADING rather than REFRESH: you can
        -- see it going and you cannot replace it.
        r.state = (lockLeft > 0) and "FADING" or "REFRESH"
        r.tLeft = soonest
        r.mainText = string.format("%ds", math.max(0, math.ceil(soonest)))
    else
        r.state = "SHIELDED"
        r.tLeft = (r.health or 1) * 1000
        r.mainText = soonest and string.format("%ds", math.ceil(soonest)) or ""
    end
    -- A locked-out row still shows the lockout on its drain even when the
    -- state above it came from something up: the minute is the fact.
    if lockLeft > 0 and not r.wsLeft then
        r.wsLeft, r.lockMax = lockLeft, SDATA.FORBEARANCE_MAX
    end

    ApplyAlertStates(r, now)
    return r
end

local function ResolveState(r, now)
    -- Self-spell rows always take the shield resolver whatever the layer:
    -- their bar IS an absorb and their lockout IS a cooldown
    if not r.selfSpell then
        if layer == "INT" then return ResolveIntState(r, now) end
        if SDATA.STRIP_STATE_LAYERS[layer or ""] then return ResolveStripState(r, now) end
        -- PWS ally rows: the shield grammar, and then the same alert ladder
        -- every other board tops itself with. The priest board went without
        -- it for three layers' worth of releases, which meant the one class
        -- on this board that removes Magic was also the only one whose row
        -- never said so — and a teammate in a fear did not reshape the board
        -- for the healer it was aimed at.
        local res = ResolveShieldState(r, now)
        if res then
            -- The strip is a readout here, not the state: fill it, ignore
            -- what it would have ranked the row as.
            util.ResolveStrip(res, now)
            ApplyAlertStates(res, now)
        end
        return res
    end
    return ResolveShieldState(r, now)
end

-- Live path: pull identity/liveness/health/range off the unit token.
local function ResolveRow(unit, now)
    local guid = UnitGUID and UnitGUID(unit)
    if not guid then return nil end
    -- A pet row is an ally row in every respect the chassis cares about —
    -- health, absorbs, dispels, targeters, click-cast — so it goes through
    -- this same resolver. What it BORROWS from its owner is identity: a pet
    -- has no class of its own, and the owner's is both the row's name tint
    -- and the icon that answers "whose pet is that".
    local owner = SDATA.PET_OWNER[unit]
    local className = select(2, UnitClass(owner or unit))
    -- Buff layers: mana users get the mana strip. For a player that is a
    -- question of class (see MANA_CLASSES — a shapeshifted druid must not
    -- flap in and out of it); for a pet there is no class to ask, so it is
    -- the pet's own power bar, which also correctly excludes a hunter's
    -- focus and a shadowfiend's energy.
    -- Resolved on EVERY layer, not just the two that draw a mana strip: the
    -- buff registry asks it to decide whether a mana-only buff (Intellect,
    -- Divine Spirit) earns a slot on this row at all.
    local manaUser
    if owner then
        manaUser = (UnitPowerType and UnitPowerType(unit) == 0) or nil
    else
        manaUser = MANA_CLASSES[className or ""] or nil
    end
    local r = {
        guid = guid,
        unit = unit,
        name = UnitName(unit) or "?",
        class = className,
        isSelf = (not owner) and UnitIsUnit(unit, "player") or false,
        isPet = owner and true or nil,
        petOwner = owner,
        -- Whether the ally-BUFF icon applies is a separate question — Int is
        -- for casters, Mark of the Wild is for everyone — so it is answered
        -- per layer in the resolvers as r.buffTarget, not here.
        manaUser = manaUser,
    }
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
        r.dead, r.deadText = true, "DEAD"
    elseif not owner and UnitIsConnected and not UnitIsConnected(unit) then
        -- Pets are never "offline": UnitIsConnected has no meaning for one,
        -- and a falsy answer would gray out every pet on the board
        r.dead, r.deadText = true, "OFFLINE"
    end
    -- Health is every ally row's main bar now; hpMax also scales the
    -- embedded shield segments.
    --
    -- CLAMPED, because the client does not promise hp <= hpMax. A group
    -- member the client has not fully synced yet — someone who just joined,
    -- or is in another zone — reports a PLACEHOLDER max (1) alongside a real
    -- current health, and the honest-looking division then yields a fraction
    -- in the thousands. Downstream that is a bar width in the thousands: the
    -- last row's health running clean off the side of the screen.
    if UnitHealthMax then
        local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
        if hpMax and hpMax > 0 then
            r.health = math.min(1, math.max(0, hp / hpMax))
            r.hpMax = hpMax
        end
    end
    -- Buff layers: mana strip for mana users (read live; the ticker repaints).
    -- Same contract, same clamp.
    if SDATA.HEALTH_LAYERS[layer or ""] and r.manaUser and UnitPower and UnitPowerMax then
        local m, mMax = UnitPower(unit, 0), UnitPowerMax(unit, 0)
        if mMax and mMax > 0 then r.mana = math.min(1, math.max(0, m / mMax)) end
    end
    -- Their target's raid mark: watch the tank hold (or leave) skull
    if DB("ShowTargetMarks", true) and GetRaidTargetIndex then
        r.raidMark = GetRaidTargetIndex(unit .. "target")
    end
    -- Is an enemy melee parked on them? The Thorns rule's whole question.
    r.meleeOnMe = util.meleeOn[guid] or false
    -- Can we even reach them? Read separately from the Range Fade SETTING,
    -- which is about dimming the row: the advisor needs this whether or not
    -- the player wants the visual, because urgency you cannot act on is not
    -- urgency. UnitInRange only answers for group members, and an unanswered
    -- question reads as in-range rather than as an excuse to go quiet.
    if not r.isSelf and UnitInRange then
        local inRange, checked = UnitInRange(unit)
        r.outOfCastRange = (checked and not inRange) or false
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
-- its health as the main bar, lifespan on the thin drain strip below, and
-- Freeze riding the second icon slot with its cooldown sweep.
--
-- The tick on the lifespan strip is the Freeze planner, and it answers
-- whichever question is still open. While Freeze is ready it is the gold
-- spend-by deadline: the last moment a cast still leaves room for a second
-- one before despawn (45s life vs ~25s cooldown). The moment Freeze is spent
-- that deadline is settled, so the tick moves to where the draining strip
-- will be when Freeze comes back up, in frost blue. If the cooldown outlasts
-- the elemental there is no second cast to plan and the tick clears.
local lastFreezeDur = 25    -- observed Freeze CD duration; 25s until seen
local function EleRow(now)
    local left = eleExpire > now and (eleExpire - now) or nil
    local hp
    if UnitHealth and UnitHealthMax then
        local h, hm = UnitHealth("pet"), UnitHealthMax("pet")
        if hm and hm > 0 then hp = h / hm end
    end
    local fcd, fdur, fstart = FreezeCooldown()
    if fdur and fdur > 1.5 then lastFreezeDur = fdur end
    local mark, markNext
    if fcd and fcd > 0 then
        -- Spent: point at the next window instead of a deadline already met
        markNext = true
        if left and left > fcd then mark = (left - fcd) / SDATA.ELE_DURATION end
    else
        mark = math.min(lastFreezeDur / SDATA.ELE_DURATION, 1)
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
        -- Main bar = the pet's HEALTH; the lifespan runs on the thin drain
        -- strip below, exactly like Ice Barrier's cooldown on My Shields
        healthMain = true,
        health = hp,
        ratio = hp or 1,
        wsLeft = left,
        lockMax = SDATA.ELE_DURATION,
        rightText = left and string.format("%ds", math.ceil(left)) or "",
        mainText = "",
        tLeft = left,
        freezeMark = mark,
        freezeMarkNext = markNext,
        freezeCd = fcd,
        freezeDur = fdur,
        freezeStart = fstart,
    }
    return r
end

-- ---------------------------------------------------------------------------
-- Class icon helpers
-- ---------------------------------------------------------------------------
-- `petUnit` is set only where the row shows ONE identity icon. A pet has no
-- class of its own, and its owner's icon alone cannot tell two warlocks'
-- minions apart, so that single slot becomes the pet's portrait — the same
-- answer the Water Elemental's row already gives. Where the display mode
-- carries a second, portrait slot the caller leaves this nil and slot one
-- stays the OWNER's class icon, which is the more useful half of "whose pet".
local function SetClassIcon(tex, classToken, guid, petUnit)
    if petUnit and UnitExists and UnitExists(petUnit) and SetPortraitTexture then
        SetPortraitTexture(tex, petUnit)
        tex:SetTexCoord(0.12, 0.88, 0.12, 0.88)
        return true
    end
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

-- Spec icon when the spec has been learned, class icon until then. A pet has
-- no spec to learn, so it takes the identity rule above instead.
local function SetSpecOrClassIcon(tex, r, petPortrait)
    if r.isPet then
        return SetClassIcon(tex, r.class, nil, petPortrait and r.unit or nil)
    end
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
    util.TrackSweep(row.swipe)
    row.swipe:Hide()

    -- Second left status slot (INT layer): an incoming priest shield, with a
    -- 30s sweep for its remaining duration
    row.inShield = row:CreateTexture(nil, "ARTWORK")
    row.inShield:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.inShield:Hide()
    row.inShieldCd = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
    if row.inShieldCd.SetHideCountdownNumbers then row.inShieldCd:SetHideCountdownNumbers(true) end
    util.TrackSweep(row.inShieldCd)
    row.inShieldCd:Hide()


    -- Ally-buff strip: one slot per TRACKED buff from the registry, leading
    -- the row. Built at the pool's maximum and laid out to whatever the
    -- settings actually ask for, so toggling a buff re-shapes the row without
    -- ever building a widget mid-combat.
    row.buffs = {}
    for n = 1, SDATA.MAX_BUFF_SLOTS do
        local b = {}
        b.icon = row:CreateTexture(nil, "ARTWORK")
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        util.StyleIcon(b.icon)
        b.icon:Hide()
        b.cd = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
        if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
        util.TrackSweep(b.cd)
        b.cd:Hide()
        row.buffs[n] = b
    end

    -- The own-aura strip: up to three auras of OURS on this ally, each a
    -- small icon with a radial sweep for what is left of it. Lifebloom and
    -- Prayer of Mending stack, so every slot carries a stack count that only
    -- shows when there is a stack worth reading — three about to bloom is a
    -- different decision from one.
    row.strip = {}
    for n = 1, SDATA.MAX_STRIP_ICONS do
        local h = {}
        h.icon = row:CreateTexture(nil, "ARTWORK")
        h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        util.StyleIcon(h.icon)
        h.icon:Hide()
        h.cd = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
        if h.cd.SetHideCountdownNumbers then h.cd:SetHideCountdownNumbers(true) end
        util.TrackSweep(h.cd)
        h.cd:Hide()
        -- NumberFontNormalSmall carries its own outline, so the digit stays
        -- readable over the herb art whatever the sweep is doing behind it
        h.count = row:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        h.count:Hide()
        row.strip[n] = h
    end

    row.unitIcon = row:CreateTexture(nil, "ARTWORK")
    row.unitIcon2 = row:CreateTexture(nil, "ARTWORK")   -- ICON_PORTRAIT's portrait slot
    -- Shaded square even in Portrait mode: this one slot carries a class icon
    -- or a live portrait depending on the setting and the unit, and a circular
    -- mask is permanent -- it would round the class symbols too
    util.StyleIcon(row.unitIcon)
    util.StyleIcon(row.unitIcon2)
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

    -- Raid mark of the unit THIS ally is targeting (assist awareness)
    row.raidMark = row:CreateTexture(nil, "OVERLAY")
    row.raidMark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    row.raidMark:Hide()

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
        util.StyleIcon(d.icon)
        d.icon:Hide()
        d.cd = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
        if d.cd.SetHideCountdownNumbers then d.cd:SetHideCountdownNumbers(true) end
        util.TrackSweep(d.cd)
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

-- Ability strips: one insecure row of icon cells under each player row.
-- Each cell = a small hoverable frame carrying icon + cooldown sweep + red
-- lockout rim + gold reset pip + remaining-time text, with a tooltip that
-- explains the whole grammar in words.
local function AbilityCellEnter(self)
    local e = self._e
    if not e then return end
    local now = GetTime()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(e.dispName, 1, 1, 1)
    if self._lockExp and self._lockExp > now then
        local lockName = (e.lock == "hypo")
            and ((GetSpellInfo and GetSpellInfo(SDATA.HYPO_ID)) or "Hypothermia")
            or ((GetSpellInfo and GetSpellInfo(SDATA.FORB_ID)) or "Forbearance")
        GameTooltip:AddLine(string.format("Locked by %s — %ds", lockName,
            math.ceil(self._lockExp - now)), 1, 0.35, 0.35)
    end
    if self._cdEnd and self._cdEnd > now then
        GameTooltip:AddLine(string.format("Cooldown: %ds left (of %ds)",
            math.ceil(self._cdEnd - now), e.cd), 0.9, 0.75, 0.4)
    else
        GameTooltip:AddLine("Ready", 0.4, 0.9, 0.4)
    end
    if self._pip and e.resetBy then
        GameTooltip:AddLine(e.resetBy.dispName .. " is ready — this cooldown is refundable",
            1, 0.85, 0.25)
    end
    GameTooltip:Show()
end
local function AbilityCellLeave() GameTooltip:Hide() end

local abilityRowPool = {}
local function AcquireAbilityRow(index)
    local row = abilityRowPool[index]
    if row then return row end
    row = CreateFrame("Frame", nil, root)
    row:SetSize(FrameWidth(), SDATA.ABILITY_H)
    -- Optional panel behind the strip. Width is set per paint so it hugs the
    -- icons actually shown; sublevel -1 puts it under the lockout rims.
    row.bg = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.bg:SetVertexColor(0, 0, 0, 0.5)
    row.bg:SetPoint("TOPLEFT", row, "TOPLEFT", STRIPE_W + 2, 0)
    row.bg:SetHeight(SDATA.ABILITY_H)
    row.bg:Hide()
    row.cells = {}
    for n = 1, SDATA.MAX_ABILITY_CELLS do
        local c = {}
        local x = STRIPE_W + 3 + (n - 1) * (SDATA.ABILITY_H - 1)
        c.rim = row:CreateTexture(nil, "BACKGROUND")
        c.rim:SetTexture("Interface\\Buttons\\WHITE8X8")
        c.rim:SetVertexColor(0.95, 0.2, 0.2, 0.95)
        c.rim:SetSize(SDATA.ABILITY_H, SDATA.ABILITY_H)
        c.rim:SetPoint("TOPLEFT", row, "TOPLEFT", x - 1, 0)
        c.rim:Hide()
        local cf = CreateFrame("Frame", nil, row)
        cf:SetSize(SDATA.ABILITY_H - 2, SDATA.ABILITY_H - 2)
        cf:SetPoint("TOPLEFT", row, "TOPLEFT", x, -1)
        cf:EnableMouse(true)
        cf:SetScript("OnEnter", AbilityCellEnter)
        cf:SetScript("OnLeave", AbilityCellLeave)
        cf:Hide()
        c.frame = cf
        c.icon = cf:CreateTexture(nil, "ARTWORK")
        c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        util.StyleIcon(c.icon)
        c.icon:SetAllPoints(cf)
        c.cd = CreateFrame("Cooldown", nil, cf, "CooldownFrameTemplate")
        if c.cd.SetHideCountdownNumbers then c.cd:SetHideCountdownNumbers(true) end
        if c.cd.SetDrawEdge then c.cd:SetDrawEdge(false) end
        c.cd:SetAllPoints(cf)
        c.cd:Hide()
        c.pip = cf:CreateTexture(nil, "OVERLAY")
        c.pip:SetTexture("Interface\\Buttons\\WHITE8X8")
        c.pip:SetVertexColor(1, 0.85, 0.25, 1)
        c.pip:SetSize(5, 5)
        c.pip:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 1, 1)
        c.pip:Hide()
        c.txt = cf:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        c.txt:SetPoint("CENTER", cf, "CENTER", 0, 0)
        c.txt:Hide()
        row.cells[n] = c
    end
    abilityRowPool[index] = row
    return row
end

-- Lay out a row's inner pieces for the current settings. Horizontal flow packs
-- only the enabled identity elements (spell icon, class icon / portrait, name);
-- the bar fills the rest. Cached by a signature so it runs only on change.
local function LayoutRow(row, width, sig, compact, secondSlot)
    local showIcon = DB("ShowSpellIcon", true)
    local mode = DB("UnitDisplay", "CLASS_ICON")
    -- Compact personal rows: half an ally row's height, carrying only the
    -- spell icon, its label and the bar. None of the ally chrome applies —
    -- no portrait, no target mark, no Renew, and no dispel strip (your own
    -- debuffs already ride your ally row, so they were duplicated per shield).
    -- `secondSlot` is the one exception, asked for by the elemental row alone:
    -- Freeze is its whole reason to exist, and a slot nobody reserved is a
    -- slot the icon cannot be drawn in.
    local rowH = compact and SDATA.PERSONAL_ROW_H or ROW_H
    local barH = compact and SDATA.PERSONAL_BAR_H or BAR_H
    local wsH = compact and SDATA.PERSONAL_WS_H or WS_H
    -- Health is the main bar on every layer now; the underlay slot carries
    -- MANA on the mage board and is retired on the priest board
    local showHealth
    if compact or not SDATA.HEALTH_LAYERS[layer or ""] then
        showHealth = false
    else
        showHealth = DB("ShowManaBar", true)
    end
    local showUnitIcon = not compact and (mode == "CLASS_ICON" or mode == "PORTRAIT"
        or mode == "ICON_NAME" or mode == "ICON_PORTRAIT" or mode == "SPEC"
        or mode == "SPEC_PORTRAIT")
    local showUnitIcon2 = not compact and (mode == "ICON_PORTRAIT" or mode == "SPEC_PORTRAIT")
    local showName = compact or (mode == "NAME" or mode == "ICON_NAME")

    row:SetSize(width, rowH)
    local x = STRIPE_W + 3

    -- The ally-buff strip leads the row. Slots are reserved from the SETTINGS,
    -- not from what is currently up, so the row's geometry is stable for a
    -- whole fight — which is also what keeps Click-Cast legal, since a secure
    -- row cannot be re-laid-out mid-combat.
    local buffSlots = (not compact and showIcon) and #SDATA.BUFF_ACTIVE or 0
    for n = 1, SDATA.MAX_BUFF_SLOTS do
        local b = row.buffs[n]
        if n <= buffSlots then
            b.icon:ClearAllPoints()
            b.icon:SetSize(SMALL_ICON, SMALL_ICON)
            b.icon:SetPoint("LEFT", row, "LEFT", x, 0)
            b.cd:ClearAllPoints()
            b.cd:SetAllPoints(b.icon)
            x = x + SMALL_ICON + 3
        else
            b.icon:Hide(); b.cd:Hide()
        end
    end

    -- The layer's OWN status slot, which is a different job from the buff
    -- strip above: the priest board's Power Word: Shield tracker, or a
    -- personal row's spell icon. The two buff layers have nothing left to put
    -- here now that their upkeep moved to the strip, so they spend no width.
    local ownSlot = showIcon and (compact or not SDATA.HEALTH_LAYERS[layer or ""])
    if ownSlot then
        local iconSize = compact and SDATA.PERSONAL_ICON or ICON_SIZE
        row.spellIcon:ClearAllPoints()
        row.spellIcon:SetSize(iconSize, iconSize)
        row.spellIcon:SetPoint("LEFT", row, "LEFT", x, 0)
        row.spellIcon:Show()
        row.swipe:ClearAllPoints()
        row.swipe:SetAllPoints(row.spellIcon)
        x = x + iconSize + 3
    else
        row.spellIcon:Hide()
        row.swipe:Hide()
    end
    -- Second status slot: an incoming priest shield on the mage board, or
    -- Freeze on the elemental's compact row.
    if showIcon then
        if (layer == "INT" and not compact) or secondSlot then
            local slotSize = compact and SDATA.PERSONAL_ICON or SMALL_ICON
            row.inShield:ClearAllPoints()
            row.inShield:SetSize(slotSize, slotSize)
            row.inShield:SetPoint("LEFT", row, "LEFT", x, 0)
            row.inShieldCd:ClearAllPoints()
            row.inShieldCd:SetAllPoints(row.inShield)
            x = x + slotSize + 3
        else
            row.inShield:Hide()
            row.inShieldCd:Hide()
        end
    else
        row.inShield:Hide()
        row.inShieldCd:Hide()
    end

    -- Hot strip (HOT layer, ally rows): slots are RESERVED whether or not a
    -- hot is up, so the bar never shifts left and right as hots come and go —
    -- a row that jitters mid-fight is a row you cannot read. Unlike the
    -- dispel strip this lives INSIDE the frame: it is the board's subject, not
    -- an annotation, so it is worth the width it costs.
    local stripSlots = (not compact and SDATA.STRIP_BOOKS[layer or ""]) and #SDATA.STRIP_ACTIVE or 0
    for n = 1, SDATA.MAX_STRIP_ICONS do
        local h = row.strip[n]
        if n <= stripSlots then
            h.icon:ClearAllPoints()
            h.icon:SetSize(SMALL_ICON, SMALL_ICON)
            h.icon:SetPoint("LEFT", row, "LEFT", x, 0)
            h.cd:ClearAllPoints()
            h.cd:SetAllPoints(h.icon)
            h.count:ClearAllPoints()
            h.count:SetPoint("BOTTOMRIGHT", h.icon, "BOTTOMRIGHT", 2, -1)
            x = x + SMALL_ICON + 2
        else
            h.icon:Hide(); h.cd:Hide(); h.count:Hide()
        end
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
        local nw = compact and SDATA.PERSONAL_NAME_W
            or ((mode == "ICON_NAME") and SHORT_NAME_W or NAME_W)
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", row, "LEFT", x, 0)
        row.name:SetWidth(nw)
        row.name:Show()
        x = x + nw + 3
    else
        row.name:Hide()
    end

    -- Reserve room at the right for the raid-mark watcher
    local marksOn = not compact and DB("ShowTargetMarks", true)
    local rightReserve = marksOn and 16 or 0
    if marksOn then
        row.raidMark:ClearAllPoints()
        row.raidMark:SetSize(14, 14)
        row.raidMark:SetPoint("RIGHT", row, "RIGHT", -(PAD - 2), 0)
    else
        row.raidMark:Hide()
    end
    local barX = x
    local barW = width - barX - PAD - rightReserve
    if barW < 40 then barW = 40 end
    -- Vertical stack: absorb bar on top, optional health, then WS drain
    local barTop = -(rowH - barH - (showHealth and HEALTH_H or 0) - wsH) / 2
    row.barBG:ClearAllPoints()
    row.barBG:SetPoint("TOPLEFT", row, "TOPLEFT", barX, barTop)
    row.barBG:SetSize(barW, barH)
    row.bar:ClearAllPoints()
    row.bar:SetPoint("TOPLEFT", row.barBG, "TOPLEFT", 0, 0)
    row.bar:SetSize(barW, barH)

    local y = barTop - barH
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
    row.wsBar:SetSize(barW, wsH)

    row.left:ClearAllPoints()
    row.left:SetPoint("LEFT", row.barBG, "LEFT", 3, 0)
    row.right:ClearAllPoints()
    row.right:SetPoint("RIGHT", row.barBG, "RIGHT", -3, 0)


    -- Dispel strip: marches rightward OUTSIDE the frame so it never eats board width
    local dispelOn = not compact and DB("ShowDispels", false)
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

    -- Bar art. Applied here rather than at build time so the setting can be
    -- changed live: it rides the layout signature, so a swap re-lays every
    -- pooled row exactly once. The stripe and the icons are deliberately
    -- left out — the stripe is a state accent, not a bar.
    local barStyle = DB("BarTexture", "FLAT")
    local barTex = SDATA.BAR_TEXTURES[barStyle] or SDATA.BAR_TEXTURES.FLAT
    -- The empty track is the fill's opposite number, so it comes from the style
    -- rather than being painted black once at build time and forgotten
    local track = SDATA.BAR_TRACKS[SDATA.BAR_TRACK_OF[barStyle] or "FLAT"]
    row.barBG:SetTexture(track.file or barTex)
    row.barBG:SetVertexColor(track[1], track[2], track[3], track[4])
    row.bar:SetTexture(barTex)
    row.healthBar:SetTexture(barTex)
    row.wsBar:SetTexture(barTex)
    for n = 1, SDATA.MAX_SHIELD_SEGS do row.shieldSegs[n]:SetTexture(barTex) end

    row._barW = barW
    -- What the layout actually granted this row, for the paint pass to read
    -- back: whether a name slot was reserved (a compact row always gets one,
    -- whatever UnitDisplay says, or its label would leave a hole where the
    -- bar should start), and how tall its lockout strip is.
    row._nameSlot = showName and true or false
    row._wsH = wsH
    row._sig = sig
end

local function LayoutSig(width)
    return width .. "|" .. tostring(DB("ShowSpellIcon", true)) .. "|"
        .. DB("UnitDisplay", "CLASS_ICON")
        .. "|" .. tostring(DB("ShowDispels", false)) .. "|" .. DB("DispelMaxIcons", 3)
        .. "|" .. DB("DispelIconSize", 16) .. "|" .. tostring(DB("ShowManaBar", true))
        .. "|" .. tostring(DB("ShowTargetMarks", true))
        .. "|" .. DB("BarTexture", "FLAT") .. "|" .. SDATA.BUFF_SIG
end

-- Player rows stride taller when each carries an ability strip beneath it
local function RowStride()
    local s = ROW_H + ROW_GAP
    if DB("ShowAbilityBar", true) then s = s + SDATA.ABILITY_H + 1 end
    return s
end

-- Height the personal block takes above the ally board. Growing DOWN, `base`
-- pushes the ally rows past it; growing UP the ally board already starts at
-- the bottom and the personal block stacks on top of it, so base is unused.
local function PersonalStride()
    return SDATA.PERSONAL_ROW_H + ROW_GAP
end

-- How many personal rows the block can EVER hold. The ally board is offset by
-- this reserve rather than by the live count, so an Ice Barrier dropping
-- mid-fight never shifts the party rows underneath it — which is also what
-- keeps Click-Cast legal, since moving a secure row in combat is a protected
-- call we would be forced to skip.
local function PersonalReserve()
    if layer ~= "INT" then return 0 end
    local n = eleKnown and 1 or 0
    if DB("SelfShieldRows", true) then
        for _, def in ipairs(trackedSpells) do
            if SelfTrackEnabled(def) then n = n + 1 end
        end
    end
    return n
end

local function PositionRow(row, index, topOffset, grow, base)
    row:ClearAllPoints()
    if grow == "UP" then
        local lift = DB("ShowAbilityBar", true) and (SDATA.ABILITY_H + 1) or 0
        row:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, (index - 1) * RowStride() + lift)
    else
        row:SetPoint("TOPLEFT", root, "TOPLEFT", 0,
            -topOffset - (base or 0) - (index - 1) * RowStride())
    end
end

local function PositionAbilityRow(row, index, topOffset, grow, base)
    row:ClearAllPoints()
    if grow == "UP" then
        row:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, (index - 1) * RowStride())
    else
        row:SetPoint("TOPLEFT", root, "TOPLEFT", 0,
            -topOffset - (base or 0) - (index - 1) * RowStride() - ROW_H - 1)
    end
end

-- One ally-upkeep status slot: Arcane Intellect on the mage board, Mark of
-- the Wild and Thorns on the druid's. The icon is ALWAYS on screen — that is
-- the whole contract, and the reason a healer can read a row's buffs without
-- hovering it. Dark ghost means missing (cast it); amber means the rebuff
-- window is open; lit means healthy, with the radial sweep carrying what is
-- left exactly the way a hot's does.
--
-- Lives on `util` rather than as a chunk local: this file sits a handful of
-- locals under Lua's 200-per-chunk ceiling (see the SDATA note at the top).
function util.PaintUpkeep(row, cache, icon, cd, tex, up, due, duration, expire, urgent)
    if not up then
        cache._exp = nil
        cd:Hide()
        if urgent then util.UrgentIcon(icon, tex) else util.GhostIcon(icon, tex) end
        return
    end
    icon:SetTexture(tex)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if icon.SetDesaturated then icon:SetDesaturated(false) end
    if due then
        icon:SetVertexColor(1, 0.65, 0.3, 1)    -- amber: rebuff window is open
    else
        icon:SetVertexColor(1, 1, 1, 1)
    end
    icon:Show()
    -- Cached against the expiry, like every other sweep on this row:
    -- SetCooldown restarts the animation, so calling it per frame would leave
    -- the sweep permanently stuck at full.
    if expire and expire > 0 and duration and duration > 0 then
        -- A buff DRAINS: lit art is what is left (see util.TrackSweep). Stated
        -- here as well as at construction because the elemental row borrows
        -- this same slot for Freeze, which is a cooldown and flips it back.
        if cd.SetReverse then cd:SetReverse(true) end
        if cache._exp ~= expire then
            cache._exp = expire
            cd:SetCooldown(expire - duration, duration)
        end
        cd:Show()
    else
        cache._exp = nil
        cd:Hide()
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
        row.markTick:Hide(); row.raidMark:Hide()
        for i = 1, SDATA.MAX_SHIELD_SEGS do row.shieldSegs[i]:Hide() end
        for i = 1, SDATA.MAX_STRIP_ICONS do
            local h = row.strip[i]
            h._exp = nil
            h.icon:Hide(); h.cd:Hide(); h.count:Hide()
        end
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

    -- The ally-buff strip. Every tracked buff holds its slot whether or not it
    -- is up: lit with its draining sweep while healthy, amber inside the
    -- rebuff window, dark when it is gone — and dark RED when the advisor says
    -- its absence is actually costing you (see util.AdviseBuff).
    --
    -- "Permanent" stops at a corpse, the same place the hot strip stops: a
    -- dark Mark on a dead ally still reads as "cast this", and the answer
    -- there is a battle rez, not a buff.
    local buffShown = 0
    if DB("ShowSpellIcon", true) and not r.selfSpell and not r.dead
        and r.state ~= "EMPTY" then
        for i = 1, math.min(r.buffCount or 0, #SDATA.BUFF_ACTIVE) do
            local e = r.buffs[i]
            buffShown = i
            local b = row.buffs[i]
            util.PaintUpkeep(row, b, b.icon, b.cd, e.icon, e.up, e.due,
                e.duration, e.expire, e.urgent)
        end
    end
    for i = buffShown + 1, SDATA.MAX_BUFF_SLOTS do
        local b = row.buffs[i]
        b._exp = nil
        b.icon:Hide(); b.cd:Hide()
    end

    -- The layer's own status slot: Power Word: Shield on the priest board, the
    -- spell icon on a personal row, an incoming shield / Freeze beside it.
    if DB("ShowSpellIcon", true) then
        if layer == "INT" and not r.selfSpell then
            if r.inShield and r.inShieldExpire then
                row.inShield:SetTexture(r.inShieldIcon or SDATA.PWS_ICON)
                row.inShield:Show()
                if row.inShieldCd.SetReverse then row.inShieldCd:SetReverse(true) end
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
            row.spellIcon:Hide()
            row.swipe:Hide()
        elseif SDATA.STRIP_STATE_LAYERS[layer or ""] and not r.selfSpell then
            -- The druid and paladin boards have nothing to put here: their
            -- upkeep all lives on the strips. The priest board is NOT in this
            -- branch even though it has a strip — its own status slot is the
            -- Power Word: Shield tracker, which is the whole board.
            row.spellIcon:Hide(); row.swipe:Hide()
            row.inShield:Hide(); row.inShieldCd:Hide()
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
                    -- Freeze is a COOLDOWN, not a duration: the wedge should
                    -- retreat as it comes back up. This slot is shared with
                    -- Thorns and the incoming-shield tracker, which are
                    -- durations, so the direction is set per paint.
                    if row.inShieldCd.SetReverse then row.inShieldCd:SetReverse(false) end
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
            if r.shieldUp and r.mine then
                row.spellIcon:SetTexture(r.icon or SDATA.PWS_ICON)
                row.spellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                row.spellIcon:SetVertexColor(1, 1, 1, 1)
                if row.spellIcon.SetDesaturated then row.spellIcon:SetDesaturated(false) end
                row.spellIcon:Show()
            else
                -- No shield of ours here: the same dark placeholder every
                -- other missing tracker on the board wears
                util.GhostIcon(row.spellIcon, r.icon or SDATA.PWS_ICON)
            end
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

    -- The own-aura strip: one lit icon per aura of ours, its sweep running
    -- that aura's own remaining time, and a stack count on the ones that
    -- stack. The slots were reserved by the layout, so an empty one leaves a
    -- gap rather than sliding the rest of the row around.
    local stripShown = 0
    if SDATA.STRIP_BOOKS[layer or ""] and not r.selfSpell and DB("ShowSpellIcon", true)
        and r.state ~= "EMPTY" and not r.dead then
        for i = 1, (r.stripSlots or 0) do
            local e = r.strip and r.strip[i]
            if e then
                stripShown = i
                local h = row.strip[i]
                if not e.up then
                    -- Missing: the aura's own art, dark, holding its place.
                    -- The slot is the answer to "what could I cast here".
                    h._exp = nil
                    h.cd:Hide()
                    h.count:Hide()
                    util.GhostIcon(h.icon, e.icon)
                else
                    h.icon:SetTexture(e.icon)
                    -- Inside the refresh window the slot itself says so. On
                    -- the two layers whose STATE reads the strip this only
                    -- agrees with the row colour; on the priest board, whose
                    -- state is its shield, the slot is the ONLY thing that can
                    -- tell you a Renew is about to drop — which is the job the
                    -- old right-edge Renew icon existed to do.
                    if e.due and DB("RenewFlash", true) then
                        local pulse = 0.55 + 0.45 * math.abs(math.sin(now * 4))
                        h.icon:SetVertexColor(1, 0.45, 0.45, pulse)
                    elseif e.due then
                        h.icon:SetVertexColor(1, 0.65, 0.3, 1)
                    else
                        h.icon:SetVertexColor(1, 1, 1, 1)
                    end
                    if h.icon.SetDesaturated then h.icon:SetDesaturated(false) end
                    h.icon:Show()
                    if e.expire and e.expire > 0 and e.duration and e.duration > 0 then
                        if h._exp ~= e.expire then
                            h._exp = e.expire
                            h.cd:SetCooldown(e.expire - e.duration, e.duration)
                        end
                        h.cd:Show()
                    else
                        h._exp = nil
                        h.cd:Hide()
                    end
                    -- Only worth a digit once it actually stacks: a Lifebloom
                    -- at one is the common case and a "1" on every row is noise
                    if (e.stacks or 0) > 1 then
                        h.count:SetText(e.stacks)
                        h.count:Show()
                    else
                        h.count:Hide()
                    end
                end
            end
        end
    end
    for i = stripShown + 1, SDATA.MAX_STRIP_ICONS do
        local h = row.strip[i]
        h._exp = nil
        h.icon:Hide(); h.cd:Hide(); h.count:Hide()
    end

    -- Identity: class icon / portrait / name per UnitDisplay. Self-spell rows
    -- have no unit to show — their identity is the spell icon, plus the spell's
    -- short name whenever the layout has a name slot.
    local mode = DB("UnitDisplay", "CLASS_ICON")
    if r.selfSpell then
        row.unitIcon:Hide()
        row.unitIcon2:Hide()
        if row._nameSlot then
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
        SetSpecOrClassIcon(row.unitIcon, r, true)
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
        SetClassIcon(row.unitIcon, r.class, r.guid, r.isPet and r.unit or nil)
        row.unitIcon:Show()
        row.unitIcon2:Hide()
    else
        row.unitIcon:Hide()
        row.unitIcon2:Hide()
    end

    if r.selfSpell then
        -- name already set above; nothing to do here
    elseif row._nameSlot then
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
    -- A fill may never outrun its own track. The resolvers all intend to hand
    -- over a 0..1 fraction, but they draw on numbers the client supplies, and
    -- one bad ratio here is not a slightly-wrong bar — it is a texture
    -- thousands of pixels wide laid across the whole screen, because nothing
    -- clips a texture to its parent. So the paint pass refuses to trust the
    -- fraction rather than trusting every present and future producer of it.
    local barW = row._barW or 100
    if r.ratio then
        local h = math.min(1, math.max(0, r.ratio))
        if r.healthMain then
            -- Health-colored main bar: green at full through amber to red
            row.bar:SetVertexColor(math.min(1, 1.6 - h * 1.4), math.min(0.75, 0.15 + h * 0.75), 0.2, 0.9)
        elseif r.state == "OTHER" then
            row.bar:SetVertexColor(0.45, 0.5, 0.7, 0.9)
        else
            row.bar:SetVertexColor(0.44, 0.44, 0.46, 0.95)
        end
        row.bar:SetWidth(math.max(barW * h, 1))
        row.bar:Show()
    else
        row.bar:Hide()
    end

    -- Embedded shield segments, chained off the health fill: cream PW:S,
    -- vibrant blue Barrier, muted blue-grey Mana Shield, school-tinted
    -- wards, dark grey Sacrifice — all on the same scale as the health
    local nSegs = 0
    if r.healthMain and r.segs and r.segScale and r.segScale > 0 and row.bar:IsShown() then
        -- The segments CHAIN off the fill's right edge, so the budget they
        -- share is whatever the fill left behind. Spending it down as they go
        -- means the run can never reach past the track even if the scale it
        -- was measured against turns out to be wrong.
        local budget = barW - (row.bar:GetWidth() or 0)
        for i = 1, #r.segs do
            local s = r.segs[i]
            local w = math.min(barW * (s.amount / r.segScale), budget)
            if w >= 1 and nSegs < SDATA.MAX_SHIELD_SEGS then
                nSegs = nSegs + 1
                budget = budget - w
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

    -- Underlay strip: MANA on the buff boards' ally rows, the elemental's
    -- HEALTH on its row (health is the main bar everywhere else now)
    if SDATA.HEALTH_LAYERS[layer or ""] and not r.selfSpell and r.mana
        and DB("ShowManaBar", true) then
        row.healthBar:SetVertexColor(0.25, 0.5, 0.95, 0.9)
        row.healthBar:SetWidth(math.max(barW * math.min(1, math.max(0, r.mana)), 1))
        row.healthBar:Show()
    else
        row.healthBar:Hide()
    end

    -- Raid mark of THEIR target: see the tank hold skull — or leave it —
    -- at a glance, and know who to assist onto what
    if r.raidMark and DB("ShowTargetMarks", true) then
        local mi = r.raidMark - 1
        local mx, my = (mi % 4) * 0.25, math.floor(mi / 4) * 0.25
        row.raidMark:SetTexCoord(mx, mx + 0.25, my, my + 0.25)
        row.raidMark:Show()
    else
        row.raidMark:Hide()
    end

    -- Freeze planner tick (elemental row only), riding the lifespan DRAIN
    -- strip. Gold while Freeze is ready: the point past which a cast no
    -- longer leaves room for a second one. Frost blue once Freeze is spent:
    -- where the drain will be when it is up again. Hidden when the cooldown
    -- outlasts the elemental — there is no second cast left to plan.
    if r.eleRow and r.freezeMark and row._barW then
        local x = math.max(0, math.min((row._barW or 100) - 2, (row._barW or 100) * r.freezeMark))
        if r.freezeMarkNext then
            row.markTick:SetVertexColor(0.45, 0.85, 1, 0.95)
        else
            row.markTick:SetVertexColor(1, 0.85, 0.25, 0.95)
        end
        row.markTick:ClearAllPoints()
        row.markTick:SetPoint("CENTER", row.wsBar, "LEFT", x, 0)
        -- Overhangs the strip it rides, at whatever height that strip is
        row.markTick:SetSize(2, (row._wsH or WS_H) + 4)
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

    -- Action glow (castable & wanted) and shield-broke flash. On the buff
    -- boards' ally rows the open actions are: remove what you can remove
    -- (CURSED/POISONED), start or refresh a hot, cast a missing Int/Mark, or
    -- rebuff one that is due.
    local glowOn = DB("WSReadyGlow", false) and (CASTABLE_STATES[r.state]
        or (SDATA.HEALTH_LAYERS[layer or ""] and not r.selfSpell and not r.dead
            and r.buffMissing))
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
    -- Pet tokens are as fixed as their owners' — "partypet2" follows whoever
    -- fills slot 2 — so a pet row click-casts under exactly the same contract
    -- and each one is bound directly after its owner.
    local pets = DB("IncludePets", true)
    -- Your own pet on the mage layer never takes an ALLY slot — the elemental
    -- has its own personal row below the board — and in raid scope it would
    -- otherwise arrive a second time as raidpetN, so it is matched by GUID.
    local skipGuid = pets and layer == "INT" and UnitExists("pet")
        and UnitGUID and UnitGUID("pet") or nil
    local function addPet(unit)
        if not (pets and UnitExists(unit)) then return end
        if skipGuid and UnitGUID and UnitGUID(unit) == skipGuid then return end
        out[#out + 1] = unit
    end
    -- Bind only units that currently exist (a tight board), but rebind only
    -- out of combat — so the token->slot mapping never shifts mid-fight.
    if DB("Scope", "PARTY") == "RAID" and IsInRaid and IsInRaid() then
        for i = 1, 40 do
            if #out >= maxRows then break end
            if UnitExists("raid" .. i) then
                out[#out + 1] = "raid" .. i
                if #out < maxRows then addPet("raidpet" .. i) end
            end
        end
    else
        if DB("IncludeSelf", true) then
            out[#out + 1] = "player"
            addPet("pet")
        end
        for i = 1, 4 do
            if #out >= maxRows then break end
            if UnitExists("party" .. i) then
                out[#out + 1] = "party" .. i
                if #out < maxRows then addPet("partypet" .. i) end
            end
        end
    end
end

-- Bind one mouse button (optionally with a modifier prefix like "shift-") on a
-- secure row to a spell cast, a plain target, or nothing. dbval is a spell ID,
-- "TARGET", or "NONE". The name resolves from the ID so it stays locale-safe and
-- always casts the highest rank you know.
local function BindClick(row, prefix, button, dbval, token)
    local typeAttr, spellAttr = prefix .. "type" .. button, prefix .. "spell" .. button
    local unitAttr = prefix .. "unit" .. button
    if dbval == "TARGET" then
        row:SetAttribute(typeAttr, "target")
        row:SetAttribute(spellAttr, nil)
        row:SetAttribute(unitAttr, nil)
    elseif dbval == "TARGETTARGET" then
        -- Assist: target what THEY are targeting. The token chain
        -- ("party1target") resolves live, so the binding never goes stale.
        row:SetAttribute(typeAttr, "target")
        row:SetAttribute(spellAttr, nil)
        row:SetAttribute(unitAttr, token and (token .. "target") or nil)
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
        row:SetAttribute(unitAttr, nil)
    else
        row:SetAttribute(typeAttr, nil)
        row:SetAttribute(spellAttr, nil)
        row:SetAttribute(unitAttr, nil)
    end
end

-- Exposed so the settings grid can push a binding change straight onto the
-- live rows. Named rather than anonymous because it is declared before
-- SetupSecureRows exists and filled in just after.
function CommanderPartyFrames_RebindRows() end

local function SetupSecureRows()
    if InCombat() then secureDirty = true; return end
    secureDirty = false
    BuildSecureTokens(secureTokens)
    local width = FrameWidth()
    local sig = LayoutSig(width)
    local showHeader = DB("ShowHeader", true)
    local topOffset = showHeader and HEADER_H or 0
    local grow = DB("Grow", "DOWN")
    local personalBase = PersonalReserve() * PersonalStride()
    -- Resolved once per pass, not per row: the talent scan is cheap but there
    -- is no reason for forty rows to each ask which spec we are
    local profile = util.TalentProfile()
    for i, token in ipairs(secureTokens) do
        local row = AcquireRow(i)
        if row._sig ~= sig then LayoutRow(row, width, sig) end
        PositionRow(row, i, topOffset, grow, personalBase)
        if row.SetAttribute then
            -- Raw token drives mouseover for @mouseover macros; each mouse button
            -- (and the modifier+left combo) casts its bound spell or targets. Both
            -- click phases are registered so the action fires whatever the
            -- ActionButtonUseKeyDown CVar is set to; re-applied here so rows built
            -- before a settings change update too. Secure -> out of combat only.
            if row.RegisterForClicks then row:RegisterForClicks("AnyDown", "AnyUp") end
            row:SetAttribute("unit", token)
            -- The whole modifier x button matrix, from the profile that
            -- matches this talent build. Every cell is written on every pass,
            -- including the empty ones: a binding cleared in the settings has
            -- to actually clear the attribute, or the old spell keeps firing
            -- until reload. Out of combat only, like everything secure here.
            for _, mod in ipairs(SDATA.CLICK_MODS) do
                for _, btn in ipairs(SDATA.CLICK_BUTTONS) do
                    BindClick(row, mod.key, btn.key,
                        util.GetBind(mod.key .. btn.key, profile), token)
                end
            end
        end
        row.unitToken = token
        row:Show()
    end
    for i = #secureTokens + 1, #rowPool do
        rowPool[i]:Hide()
    end
    local slots = DB("FixedHeight", false) and DB("MaxRows", 6) or math.max(#secureTokens, 1)
    root:SetSize(width, topOffset + personalBase
        + math.max(slots * RowStride() - ROW_GAP, ROW_H))
end

function CommanderPartyFrames_RebindRows()
    if securePool then SetupSecureRows() end
end

-- ---------------------------------------------------------------------------
-- Uptime sampling (Track Shield Uptime). One number, three questions —
-- each layer measures the coverage that actually decides its fights:
--   PWS  the share of living allies carrying OUR Power Word: Shield
--   INT  the share of the session YOU had any absorb up (arena survival)
--   HOT  the share of living allies carrying one of OUR hots
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
    if layer == "BLESS" then
        -- The paladin's version is the BLESSINGS, not the Hands. Hand uptime
        -- would be a number near zero that means nothing — they are
        -- emergencies, and spending them constantly is not the goal. Blessing
        -- coverage is the thing a paladin is actually judged on, and it is
        -- the one upkeep number on this board worth a percentage.
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
                local rec = intState[UnitGUID(unit)]
                if rec then
                    for _, e in pairs(rec) do
                        if not (e.expire and e.expire > 0 and e.expire <= now) then
                            covered = covered + 1
                            break
                        end
                    end
                end
            end
        end
        if total > 0 then
            uptime.coverageSamples = (uptime.coverageSamples or 0) + 1
            uptime.coverageSum = (uptime.coverageSum or 0) + covered / total
        end
        return
    end
    if layer == "HOT" then
        -- The druid's version of the same question the priest board asks:
        -- what share of the living team is carrying a hot of YOURS. Reads the
        -- hot records rather than the units, so an ally who drifted out of
        -- range still counts until a reliable scan says otherwise.
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
                local rec = strip.state[UnitGUID(unit)]
                if rec and next(rec) then covered = covered + 1 end
            end
        end
        if total > 0 then
            uptime.coverageSamples = (uptime.coverageSamples or 0) + 1
            uptime.coverageSum = (uptime.coverageSum or 0) + covered / total
        end
        return
    end
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
    local pets = DB("IncludePets", true)
    -- Your own pet on the mage layer is deliberately absent from the ALLY
    -- board: the elemental already has a richer personal row below it
    -- (lifespan, the Freeze planner), and two rows for one unit is noise.
    -- Marking its GUID taken here is what also stops the raid loop from
    -- re-adding it as raidpetN.
    if layer == "INT" and UnitExists("pet") then
        local g = UnitGUID("pet")
        if g then seen[g] = true end
    end
    if DB("IncludeSelf", true) then
        add("player")
        if pets then add("pet") end
    end
    -- Each pet follows its owner, so the Click-Cast board keeps the pair
    -- adjacent; the sorted board re-orders by urgency anyway.
    if DB("Scope", "PARTY") == "RAID" and IsInRaid and IsInRaid() then
        for i = 1, 40 do
            add("raid" .. i)
            if pets then add("raidpet" .. i) end
        end
    else
        for i = 1, 4 do
            add("party" .. i)
            if pets then add("partypet" .. i) end
        end
    end
end

local function SortRows(a, b)
    local sa, sb = STATES[a.state].rank, STATES[b.state].rank
    if sa ~= sb then return sa < sb end
    -- A player outranks an EQUALLY urgent pet. A pet is worth buffing and
    -- worth healing — that is the whole point of putting it on the board —
    -- but it is never the row that decides the fight, and with Max Rows tight
    -- it must be the one that gives way. Urgency still wins across the two:
    -- a cursed pet outranks a quiet player, exactly as it should.
    if (a.isPet or false) ~= (b.isPet or false) then return not a.isPet end
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

-- Optional dark panel behind the top bar, so the banner reads as a bar
-- against the world instead of text floating over it. BACKGROUND sublevel -1
-- keeps it under everything the header itself draws.
local function HeaderBackdrop()
    if not root.headerBG then
        root.headerBG = root:CreateTexture(nil, "BACKGROUND", nil, -1)
        root.headerBG:SetTexture("Interface\\Buttons\\WHITE8X8")
        root.headerBG:SetVertexColor(0, 0, 0, 0.55)
        root.headerBG:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
        root.headerBG:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
        root.headerBG:SetHeight(HEADER_H)
    end
    return root.headerBG
end

-- The team-alert segment's text, shared by both banners: how many allies are
-- carrying something you can remove, and how many are in crowd control.
-- Purple for the removable (the row color it matches), orange for the CC.
local function AlertText()
    local t = ""
    if intCurses > 0 then t = string.format("|cffa64dffC%d|r", intCurses) end
    if intCCs > 0 then
        t = t .. (t ~= "" and " " or "") .. string.format("|cffff8c26CC%d|r", intCCs)
    end
    return t
end

local function DrawHeader(now, showHeader)
    -- Ahead of the layer split: the mage banner branch returns early
    if showHeader and DB("HeaderBackdrop", true) then
        HeaderBackdrop():Show()
    elseif root.headerBG then
        root.headerBG:Hide()
    end
    if settingsBtn then
        settingsBtn:SetShown(showHeader and DB("ShowSettingsButton", true))
    end
    if blizz.btn then
        -- Sits left of the gear, or takes its slot when the gear is off.
        -- Re-anchored only when that changes: this runs at the draw rate.
        local gearOn = (settingsBtn and settingsBtn:IsShown()) and true or false
        if blizz.gearOn ~= gearOn then
            blizz.gearOn = gearOn
            blizz.btn:ClearAllPoints()
            blizz.btn:SetPoint("TOPRIGHT", root, "TOPRIGHT",
                -(PAD - 3) - (gearOn and 15 or 0), -1.5)
        end
        blizz.btn:SetShown(showHeader)
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
            local segs = util.EnsureSegs()
            -- The segment pool is shared; these two extras are the mage
            -- banner's alone and hang off its first segment, so they are
            -- built once here rather than in EnsureSegs.
            if not root.armorBuilt then
                root.armorBuilt = true
                -- Armor wears its remaining time as a radial sweep instead of
                -- a countdown string: the ring IS the duration, and the
                -- banner keeps its icon clean
                root.armorCd = CreateFrame("Cooldown", nil, root, "CooldownFrameTemplate")
                root.armorCd:SetAllPoints(segs[1].icon)
                if root.armorCd.SetHideCountdownNumbers then
                    root.armorCd:SetHideCountdownNumbers(true)
                end
                if root.armorCd.SetDrawEdge then root.armorCd:SetDrawEdge(false) end
                -- Never eat the click: the icon under it is the armor toggle
                root.armorCd:EnableMouse(false)
                root.armorCd:Hide()
                -- The armor segment doubles as the armor-switch popout toggle
                if armorPop and not armorBtn then
                    armorBtn = CreateFrame("Button", nil, root)
                    armorBtn:SetSize(16, 16)
                    armorBtn:SetPoint("CENTER", segs[1].icon, "CENTER", 0, 0)
                    armorBtn:SetScript("OnClick", function()
                        SafeSetShown(armorPop, not armorPop:IsShown())
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
            if mageUtil then SafeSetShown(mageUtil, true) end
            if armorBtn then armorBtn:Show() end
            util.Paint(now)
            local segX = util.PlaceSegs()
            util.segN = 0
            -- The armor popout hangs under the armor segment, which moved. It
            -- may only follow by tracking the segment's offset off ROOT: the
            -- popout's secure children pull it into their protected anchor
            -- family, and a protected family may not attach to a region like
            -- segs[1].icon (see the creation anchor). Moving it at all is a
            -- protected call, so it keeps its OWN record of where it was last
            -- put — sharing the segment's would have a deferred popout report
            -- the segment as unplaced too, and the segment (a texture, free to
            -- move in combat) would then be stranded wherever the fight caught
            -- it once its cache finally caught up.
            if armorPop and root._popX ~= segX and not InCombat() then
                root._popX = segX
                armorPop:ClearAllPoints()
                armorPop:SetPoint("TOPLEFT", root, "TOPLEFT", segX,
                    -(1 + segs[1].icon:GetHeight() + 3))
            end
            -- 1) Armor upkeep, text-free: the radial carries the time left,
            -- the icon goes amber inside the last five minutes, and a naked
            -- mage gets the dim red icon that used to read OFF
            local armorLeft = selfArmor and selfArmor.expire and selfArmor.expire > 0
                and (selfArmor.expire - now) or nil
            if selfArmor and (not armorLeft or armorLeft > 0) then
                util.Seg(selfArmor.icon, false, nil,
                    (armorLeft and armorLeft <= 300) and { 1, 0.65, 0.3 } or nil)
                local dur = selfArmor.duration
                if root.armorCd and armorLeft and dur and dur > 0 then
                    if root._armorExp ~= selfArmor.expire then
                        root._armorExp = selfArmor.expire
                        root.armorCd:SetCooldown(selfArmor.expire - dur, dur)
                    end
                    root.armorCd:Show()
                elseif root.armorCd then
                    -- No duration to scale a ring against (a permanent or
                    -- unscannable buff): the plain icon says it is up
                    root._armorExp = nil
                    root.armorCd:Hide()
                end
            else
                util.Seg("Interface\\Icons\\Spell_Frost_FrostArmor02", true, nil, { 1, 0.25, 0.25 })
                if root.armorCd then root._armorExp = nil; root.armorCd:Hide() end
            end
            -- 2) The cooldowns that decide games, filtered at login to what
            -- this mage actually trained — an arcane mage never sees a Cold
            -- Snap slot. Ice Barrier and the elemental stay off the banner:
            -- both already have a personal row saying more than a segment
            -- could (see SDATA.MAGE_BANNER_CDS).
            util.SegCds(now)
            -- 3) Session shield uptime — the live shield tracking itself
            -- (Barrier state, absorb totals) lives on the My Shields rows now
            if DB("TrackUptime", false) and uptime and (uptime.coverageSamples or 0) > 0 then
                util.Seg("Interface\\Icons\\Spell_Shadow_DetectLesserInvisibility", false,
                    string.format("%d%%", math.floor(uptime.coverageSum / uptime.coverageSamples * 100 + 0.5)))
            end
            -- 4) Team alerts: curses you can remove, teammates in CC
            if intCurses > 0 or intCCs > 0 then
                util.Seg(intCurses > 0 and "Interface\\Icons\\Spell_Shadow_CurseOfTounges"
                    or "Interface\\Icons\\Spell_Nature_Polymorph", false, AlertText())
            end
            util.TruncSegs(segX)
            return
        end
        -- HOT layer: the druid's upkeep banner. Same segment grammar as the
        -- mage's, answering a druid's questions in the order they bite:
        -- can I even cast right now (form), are my match-deciding cooldowns
        -- up, how well have I kept the team covered, and what needs removing.
        if layer == "HOT" then
            root.header:Hide()
            util.EnsureSegs()
            if mageUtil then SafeSetShown(mageUtil, true) end
            util.Paint(now)
            local segX = util.PlaceSegs()
            util.segN = 0
            -- 1) Form. Caster form says nothing worth a slot, so it gets none;
            -- a form that BLOCKS healing gets the red icon, because every
            -- other segment on this banner is advice you cannot take until
            -- you shift out. Tree of Life casts the whole hot kit, so it is
            -- shown plain — it is a resto druid's home, not a warning.
            if strip.form then
                util.Seg(strip.form.icon or "Interface\\Icons\\Ability_Racial_BearForm",
                    not strip.form.heals, nil,
                    (not strip.form.heals) and { 1, 0.25, 0.25 } or nil)
            end
            -- 2) The cooldowns that decide games, in book order and filtered
            -- at login to what this druid actually trained — a feral never
            -- sees a Nature's Swiftness slot
            util.SegCds(now)
            -- 3) Session hot uptime
            if DB("TrackUptime", false) and uptime and (uptime.coverageSamples or 0) > 0 then
                util.Seg(SDATA.DRUID_HOTS[1].icon, false,
                    string.format("%d%%", math.floor(uptime.coverageSum / uptime.coverageSamples * 100 + 0.5)))
            end
            -- 4) Team alerts: what you can remove, teammates in CC
            if intCurses > 0 or intCCs > 0 then
                util.Seg(intCurses > 0 and "Interface\\Icons\\Spell_Nature_RemoveCurse"
                    or "Interface\\Icons\\Spell_Nature_Polymorph", false, AlertText())
            end
            util.TruncSegs(segX)
            return
        end
        -- BLESS layer: the paladin's upkeep banner. Same segment grammar
        -- again, asking a paladin's questions in the order they bite: am I
        -- actually running the two things I am supposed to be running, what
        -- have I got to give, how well is the team blessed, what needs
        -- removing.
        if layer == "BLESS" then
            root.header:Hide()
            util.EnsureSegs()
            if mageUtil then SafeSetShown(mageUtil, true) end
            util.Paint(now)
            local segX = util.PlaceSegs()
            util.segN = 0
            -- 1) Aura. Unlike a druid's form there is no neutral state here:
            -- a paladin is always meant to be running one, so a missing aura
            -- gets the dim red icon a naked mage's armor slot gets rather
            -- than no slot at all.
            if strip.aura then
                util.Seg(strip.aura.icon or "Interface\\Icons\\Spell_Holy_DevotionAura", false)
            else
                util.Seg("Interface\\Icons\\Spell_Holy_DevotionAura", true, nil, { 1, 0.25, 0.25 })
            end
            -- 2) Seal. Thirty seconds long and dropped constantly, which is
            -- exactly why it earns a slot: the sweep IS the timer, and a
            -- sealless paladin is a paladin doing nothing. Amber inside the
            -- last five seconds, red when there is no seal at all.
            local sealLeft = strip.seal and strip.seal.expire and strip.seal.expire > 0
                and (strip.seal.expire - now) or nil
            if strip.seal and (not sealLeft or sealLeft > 0) then
                util.Seg(strip.seal.icon or "Interface\\Icons\\Spell_Holy_HolySmite", false,
                    sealLeft and string.format("%d", math.ceil(sealLeft)) or nil,
                    (sealLeft and sealLeft <= 5) and { 1, 0.65, 0.3 } or nil)
            else
                util.Seg("Interface\\Icons\\Spell_Holy_HolySmite", true, nil, { 1, 0.25, 0.25 })
            end
            -- 3) The cooldowns that decide games, in book order and filtered
            -- at login to what this paladin actually trained
            util.SegCds(now)
            -- 4) Session blessing uptime
            if DB("TrackUptime", false) and uptime and (uptime.coverageSamples or 0) > 0 then
                util.Seg("Interface\\Icons\\Spell_Magic_MageArmor", false,
                    string.format("%d%%", math.floor(uptime.coverageSum / uptime.coverageSamples * 100 + 0.5)))
            end
            -- 5) Team alerts: what you can remove, teammates in CC. A paladin
            -- cleanses Magic, so the icon is Cleanse rather than Remove Curse.
            if intCurses > 0 or intCCs > 0 then
                util.Seg(intCurses > 0 and "Interface\\Icons\\Spell_Holy_Renew"
                    or "Interface\\Icons\\Spell_Nature_Polymorph", false, AlertText())
            end
            util.TruncSegs(segX)
            return
        end
        -- The bandage control is chassis, not a class layer — it rides the
        -- priest banner too (the class-layer branches above returned already)
        if mageUtil then SafeSetShown(mageUtil, true) end
        util.Paint(now)
        -- Everything below is the PRIEST banner. A layer with no banner of
        -- its own gets the utility cluster and the gear and nothing else,
        -- rather than somebody else's numbers.
        if layer ~= "PWS" then
            root.header:Hide()
            return
        end
        -- PWS layer: the priest's upkeep banner. This was a one-line string
        -- ("PW:S CD Ready ~1265") long after the other three layers had grown
        -- segment banners, which meant the class the board was BUILT for was
        -- the one that could not see its own cooldowns. Same grammar as the
        -- others now, asking a priest's questions in the order they bite.
        root.header:Hide()
        util.EnsureSegs()
        local segX = util.PlaceSegs()
        util.segN = 0
        -- 1) Inner Fire. The priest's armor: a buff you are supposed to have
        -- on at all times and the one nobody notices falling off, so it wears
        -- the naked mage's dim red icon when it is gone.
        if selfArmor then
            util.Seg(selfArmor.icon or "Interface\\Icons\\Spell_Holy_InnerFire", false)
        else
            util.Seg("Interface\\Icons\\Spell_Holy_InnerFire", true, nil, { 1, 0.25, 0.25 })
        end
        -- 2) The shield itself: its cooldown while it is running, and its
        -- current absorb estimate once it is back. That estimate is the one
        -- number the old text header carried that nothing else on the board
        -- shows, so it keeps a home.
        do
            local left = 0
            if GetSpellCooldown and PWS_NAME then
                local start, duration = GetSpellCooldown(PWS_NAME)
                if start and duration and duration > 1.5 then
                    left = start + duration - now
                end
            end
            if left > 0 then
                util.Seg(SDATA.PWS_ICON, true, string.format("%.1f", left))
            else
                util.Seg(SDATA.PWS_ICON, false, FormatAmount(myShieldValue))
            end
        end
        -- 3) The cooldowns that decide games, filtered at login to what this
        -- priest actually trained — a disc priest never sees Shadowfiend
        util.SegCds(now)
        -- 4) Session shield uptime
        if DB("TrackUptime", false) and uptime and (uptime.coverageSamples or 0) > 0 then
            util.Seg(SDATA.PWS_ICON, false,
                string.format("%d%%", math.floor(uptime.coverageSum / uptime.coverageSamples * 100 + 0.5)))
        end
        -- 5) Team alerts: what you can remove, teammates in CC
        if intCurses > 0 or intCCs > 0 then
            util.Seg(intCurses > 0 and "Interface\\Icons\\Spell_Holy_DispelMagic"
                or "Interface\\Icons\\Spell_Nature_Polymorph", false, AlertText())
        end
        util.TruncSegs(segX)
    else
        if root.header then root.header:Hide() end
        if root.hdrSegs then
            for _, s in ipairs(root.hdrSegs) do s.icon:Hide(); s.text:Hide() end
        end
        if root.armorCd then root._armorExp = nil; root.armorCd:Hide() end
        -- The container and the popouts carry secure children, so taking them
        -- down is protected and waits for combat to drop; the plain toggles
        -- and textures go immediately.
        if mageUtil then SafeSetShown(mageUtil, false) end
        if armorBtn then armorBtn:Hide() end
        if armorPop then SafeSetShown(armorPop, false) end
        if util.portalPop then SafeSetShown(util.portalPop, false) end
    end
end

-- Count how many enemy NPCs have each board unit targeted, by walking the
-- visible enemy nameplates (the only honest source: unit tokens exist only
-- for units the client shows plates for, so coverage follows the player's
-- nameplate settings). Throttled to 4 Hz; the table is tiny and rebuilt in
-- place. Skipped during the test board so the tester's fake counts survive.
-- One quarter-second pass over everything hostile we can currently address,
-- feeding two consumers:
--   1. the targeted-by counter (enemy NPCs parked on an ally), and
--   2. the enemy composition, which is what lets the buff advisor tell a
--      caster team from a physical one.
--
-- Two sources, because neither is complete on its own. Arena unit tokens are
-- exact but only exist in an arena; nameplates work everywhere but only cover
-- what is rendered nearby. Whatever they agree on is what the advisor gets,
-- and a rule with no answer stays quiet rather than guessing (see
-- SDATA.BUFF_ADVICE). Everything here soft-fails: a client without
-- C_NamePlate or arena tokens simply contributes nothing.
local function ScanTargeters(now)
    if testUntil > 0 then return end
    if now < nextTargeterScan then return end
    nextTargeterScan = now + 0.25
    local tally = DB("ShowTargeters", true)
    if tally then wipe(targeters) end
    wipe(util.enemyClasses)
    wipe(util.meleeOn)
    util.enemySeen = 0

    -- What an enemy unit contributes, whichever source found it
    local function note(unit)
        local _, class = UnitClass(unit)
        if class then
            util.enemyClasses[class] = true
            util.enemySeen = util.enemySeen + 1
        end
        -- Who they are on. A melee parked on an ally is the whole Thorns
        -- question, and it is the same token walk the counter already does.
        local tgt = unit .. "target"
        if UnitExists(tgt) then
            local guid = UnitGUID(tgt)
            if guid and class and SDATA.MELEE_CLASSES[class] then
                util.meleeOn[guid] = true
            end
        end
    end

    -- Arena tokens first: exact classes, and they resolve whether or not the
    -- enemy is on screen
    if UnitExists then
        for i = 1, 5 do
            local u = "arena" .. i
            if UnitExists(u) and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost(u)) then
                note(u)
            end
        end
    end

    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    local plates = C_NamePlate.GetNamePlates()
    if not plates then return end
    for i = 1, #plates do
        local plate = plates[i]
        local unit = plate and (plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
        if unit and UnitCanAttack("player", unit) then
            if UnitIsPlayer(unit) then
                note(unit)
            else
                -- The counter is about enemy NPCs specifically: a pet or a
                -- add parked on an ally is the pressure it exists to show
                local tgt = unit .. "target"
                if tally and UnitExists(tgt) then
                    local guid = UnitGUID(tgt)
                    if guid then targeters[guid] = (targeters[guid] or 0) + 1 end
                end
            end
        end
    end
end

-- Drop every injected test entry from the shared state tables
local function ClearTestState()
    for _, t in ipairs({ shieldState, wsState, dispelState, intState, curseState, ccState, allyAbsorbs, specState, abilityState, lockState, targeters, strip.state }) do
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

-- Personal rows lead the board: your own upkeep on top, at half an ally
-- row's height, with the party rows below it.
local function PaintPersonalRows(now, shownPlayers, topOffset, grow, width, sig)
    -- Their own layout signature: the compact metrics must not be cached
    -- against (or clobber) the ally rows' full-height layout
    local psig = sig .. "|P"
    -- Growing UP the ally board rises from the bottom, so the personal block
    -- stacks above it; growing DOWN it leads from under the header.
    local base = (grow == "UP") and (shownPlayers * RowStride()) or 0
    for i = 1, #personalRows do
        local row = AcquirePersonalRow(i)
        -- The elemental row reserves a second status slot for Freeze; the
        -- shield rows do not, so it rides the signature rather than the row
        -- index (the pet coming and going re-lays out one row, not the block)
        local ele = personalRows[i].eleRow and true or false
        local rsig = ele and (psig .. "E") or psig
        if row._sig ~= rsig then LayoutRow(row, width, rsig, true, ele) end
        local off = base + (i - 1) * PersonalStride()
        row:ClearAllPoints()
        if grow == "UP" then
            row:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, off)
        else
            row:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -topOffset - off)
        end
        local r = personalRows[i]
        CheckExposeAlert(r, shownPlayers + i, now)
        PaintRow(row, r, now, shownPlayers + i)
        row:Show()
    end
    for i = #personalRows + 1, #personalPool do personalPool[i]:Hide() end
end

-- Strip ordering: match-deciders first, then the book's own order
local stripScratch = {}
local function StripOrder(a, b)
    local ka = SDATA.KIND_RANK[a.e.kind] or 9
    local kb = SDATA.KIND_RANK[b.e.kind] or 9
    if ka ~= kb then return ka < kb end
    return (a.e.ord or 99) < (b.e.ord or 99)
end

-- Hoisted strip selection (runs per row per draw — no closures, pooled
-- slots): stripSpec/stripSt/stripLs/stripN carry the current row's context
local stripSpec, stripSt, stripLs, stripN, stripTrack
local function StripConsider(entry, now)
    if entry.spec and entry.spec ~= stripSpec then return end
    -- Tracked filter: explicit AbilityTrack override wins, else book default
    local ov = stripTrack and stripTrack[entry.tok]
    if ov == false or (ov == nil and entry.off) then return end
    local cdEnd = stripSt and stripSt[entry.key]
    if cdEnd and cdEnd <= now then cdEnd = nil; stripSt[entry.key] = nil end
    local lockExp = entry.lock and stripLs and stripLs[entry.lock]
    if lockExp and lockExp <= now then lockExp = nil end
    if entry.tier == 1 or cdEnd or lockExp then
        stripN = stripN + 1
        local slot = stripScratch[stripN]
        if not slot then slot = {}; stripScratch[stripN] = slot end
        slot.e, slot.cdEnd, slot.lockExp = entry, cdEnd, lockExp
    end
end

-- Fill one ability strip from the book + live state. Tier 1 shows always;
-- tier 2 only while cooling; spec-gated entries appear once the spec is
-- known. Lockouts (Hypothermia/Forbearance) wear the red rim and extend the
-- sweep; a ready resetter (Cold Snap/Prep) pips its cooling targets gold.
local function PaintAbilityStrip(arow, r, now)
    local n = 0
    local guid, class = r.guid, r.class
    -- Pets carry their OWNER's class for color and icon, which is exactly the
    -- reason they must be excluded here: the book is a class's cooldowns, and
    -- stamping a warlock's Death Coil under their felhunter would be a lie.
    if guid and class and r.state ~= "EMPTY" and not r.dead and not r.isPet
        and (not r.isSelf or DB("AbilityBarSelf", true))
        -- Mine only: your own cooldowns under your own row, and nothing under
        -- anybody else's. The narrowest the strip goes without switching it
        -- off, for a player who wants the reminder but not the wall.
        and (r.isSelf or not DB("AbilityBarOnlySelf", false)) then
        local spec = specState[guid]
        stripSpec, stripSt, stripLs, stripN = spec, abilityState[guid], lockState[guid], 0
        stripTrack = CommanderPartyFramesDB.AbilityTrack
        local list = SDATA.ABILITY_BOOK[class]
        if list then for _, e in ipairs(list) do StripConsider(e, now) end end
        for _, e in ipairs(SDATA.ABILITY_SHARED) do StripConsider(e, now) end
        -- Trim pooled slots past the live count so the sort sees a dense array
        for i = stripN + 1, #stripScratch do stripScratch[i] = nil end
        table.sort(stripScratch, StripOrder)
        local st = stripSt

        local maxIcons = math.min(DB("AbilityMaxIcons", 6), SDATA.MAX_ABILITY_CELLS)
        local showTxt = DB("AbilityCdText", true)
        for i = 1, math.min(stripN, maxIcons) do
            n = n + 1
            local cell = arow.cells[n]
            local s = stripScratch[i]
            local e = s.e
            cell.icon:SetTexture(e.dispIcon)
            local effEnd, effDur = s.cdEnd, e.cd
            if s.lockExp and (not effEnd or s.lockExp > effEnd) then
                effEnd = s.lockExp
                effDur = (e.lock == "hypo") and 30 or 60
            end
            if effEnd then
                if cell.icon.SetDesaturated then cell.icon:SetDesaturated(true) end
                cell.icon:SetVertexColor(0.75, 0.75, 0.75, 0.9)
                if cell._end ~= effEnd then
                    cell._end = effEnd
                    cell.cd:SetCooldown(effEnd - effDur, effDur)
                end
                cell.cd:Show()
                local left = effEnd - now
                if showTxt and left >= 10 then
                    cell.txt:SetText(left >= 90 and string.format("%dm", math.floor(left / 60 + 0.5))
                        or tostring(math.floor(left)))
                    cell.txt:Show()
                else
                    cell.txt:Hide()
                end
            else
                if cell.icon.SetDesaturated then cell.icon:SetDesaturated(false) end
                cell.icon:SetVertexColor(1, 1, 1, 1)
                cell._end = nil
                cell.cd:Hide()
                cell.txt:Hide()
            end
            if s.lockExp then cell.rim:Show() else cell.rim:Hide() end
            local rb = e.resetBy
            local pip = false
            if rb and s.cdEnd and not (rb.spec and rb.spec ~= spec) then
                local rbEnd = st and st[rb.key]
                if not rbEnd or rbEnd <= now then pip = true end
            end
            if pip then cell.pip:Show() else cell.pip:Hide() end
            -- Tooltip payload rides the hoverable cell frame
            cell.frame._e, cell.frame._cdEnd, cell.frame._lockExp, cell.frame._pip
                = e, s.cdEnd, s.lockExp, pip
            cell.frame:Show()
        end
    end
    for i = n + 1, SDATA.MAX_ABILITY_CELLS do
        local cell = arow.cells[i]
        cell.frame._e = nil
        cell.frame:Hide()
        cell.rim:Hide()
    end
    -- Hug the live icons: a strip with nothing to show (or a short one) must
    -- not leave a dark bar hanging under the row
    if n > 0 and DB("AbilityBarBackdrop", true) then
        arow.bg:SetWidth(n * (SDATA.ABILITY_H - 1) + 1)
        arow.bg:Show()
    else
        arow.bg:Hide()
    end
end

local function Draw()
    local now = GetTime()
    ScanTargeters(now)
    -- Buff-layer header tallies rebuild as this pass resolves rows
    if layer then intCurses, intCCs = 0, 0 end
    local showHeader = DB("ShowHeader", true)
    local topOffset = showHeader and HEADER_H or 0
    local grow = DB("Grow", "DOWN")
    local width = FrameWidth()
    local sig = LayoutSig(width)
    -- Height held for the personal block that now leads the board
    local personalBase = PersonalReserve() * PersonalStride()

    -- Combat-only visibility applies to both modes. With the secure buttons
    -- moved off root this is a legal call again in either direction — the
    -- board can come UP at the start of a fight, which is the whole point of
    -- the option and was impossible while root wore their protection.
    local combatHidden = DB("CombatOnly", false) and not InCombat()
        and not Commander.UI.HudUnlocked(CommanderPartyFramesDB, "Hud")
    -- The cluster is a sibling now, so it neither scales nor hides with the
    -- board unless it is told to
    util.SyncCluster()

    -- Test board upkeep
    if testUntil > 0 and now > testUntil then
        testUntil = 0
        wipe(testRows)
        ClearTestState()
    end

    -- ---- Secure mode: fixed token rows, visuals only in combat ----
    if securePool and testUntil == 0 then
        if secureDirty and not InCombat() then SetupSecureRows() end
        local barsOn = DB("ShowAbilityBar", true)
        for i, token in ipairs(secureTokens) do
            local row = rowPool[i]
            if row then
                local r = UnitExists(token) and ResolveRow(token, now) or { state = "EMPTY" }
                if r.guid then CheckExposeAlert(r, i, now) end
                PaintRow(row, r, now, i)
                if barsOn then
                    -- Ability strips are insecure: positionable mid-combat
                    local ar = AcquireAbilityRow(i)
                    PositionAbilityRow(ar, i, topOffset, grow, personalBase)
                    PaintAbilityStrip(ar, r, now)
                    ar:Show()
                end
            end
        end
        for i = (barsOn and #secureTokens or 0) + 1, #abilityRowPool do abilityRowPool[i]:Hide() end
        -- Personal rows LEAD the secure block from their own insecure pool —
        -- Click-Cast must not cost the mage their own rows
        wipe(personalRows)
        AppendLivePersonalRows(now)
        PaintPersonalRows(now, #secureTokens, topOffset, grow, width, sig)
        -- The banner rides the board's visibility, not just the header
        -- setting: its container is no longer root's child to hide with it
        local boardOn = not combatHidden and (#secureTokens > 0 or #personalRows > 0
            or DB("AlwaysShow", false)
            or Commander.UI.HudUnlocked(CommanderPartyFramesDB, "Hud"))
        DrawHeader(now, showHeader and boardOn)
        -- Root resizes out of combat only (protected rows anchor to it; not
        -- worth the mid-combat taint risk). The personal block is charged at
        -- its RESERVE, not its live count, so the box never breathes.
        if not InCombat() then
            local mainSlots = DB("FixedHeight", false) and DB("MaxRows", 6)
                or math.max(#secureTokens, 1)
            local bodyH = mainSlots * RowStride() + personalBase - ROW_GAP
            root:SetSize(width, topOffset + math.max(bodyH, ROW_H))
        end
        SafeSetShown(root, boardOn)
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
                    dispelKey = tr.dispelKey, tgtKey = tr.tgtKey, manaUser = tr.manaUser, mana = tr.mana,
                    raidMark = tr.raidMark, isPet = tr.isPet, petOwner = tr.petOwner }
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
    local barsOn = DB("ShowAbilityBar", true)
    -- These rows are insecure, so the block can be sized to whichever is
    -- larger — the reserve, or what is actually up. The test board builds
    -- personal rows the reserve knows nothing about.
    local base = math.max(personalBase, #personalRows * PersonalStride())
    for i = 1, shown do
        local row = AcquireRow(i)
        if row._sig ~= sig then LayoutRow(row, width, sig) end
        PositionRow(row, i, topOffset, grow, base)
        local r = rowData[i]
        CheckExposeAlert(r, i, now)
        PaintRow(row, r, now, i)
        row:Show()
        if barsOn then
            local ar = AcquireAbilityRow(i)
            PositionAbilityRow(ar, i, topOffset, grow, base)
            PaintAbilityStrip(ar, r, now)
            ar:Show()
        end
    end
    for i = shown + 1, #rowPool do rowPool[i]:Hide() end
    for i = (barsOn and shown or 0) + 1, #abilityRowPool do abilityRowPool[i]:Hide() end
    PaintPersonalRows(now, shown, topOffset, grow, width, sig)

    local boardOn = not combatHidden and (shown + #personalRows > 0 or DB("AlwaysShow", false)
        or Commander.UI.HudUnlocked(CommanderPartyFramesDB, "Hud"))
    DrawHeader(now, showHeader and boardOn)

    -- This board's row count moves mid-fight (a member joining, a row
    -- alerting in), so the frame has to be able to follow it — which it can,
    -- now that nothing secure hangs off root. Still guarded: Click-Cast puts
    -- secure rows back under it, and there the token set only changes out of
    -- combat, so the frozen size is always the right one anyway.
    local mainSlots = DB("FixedHeight", false) and math.max(maxRows, shown) or shown
    local bodyH = mainSlots * RowStride() + base - ROW_GAP
    if not (InCombat() and root.IsProtected and root:IsProtected()) then
        root:SetSize(width, topOffset + math.max(bodyH, ROW_H))
    end
    SafeSetShown(root, boardOn)
end

-- ---------------------------------------------------------------------------
-- Test board (non-secure preview): one row in every state.
-- ---------------------------------------------------------------------------
function CommanderPartyFrames_Test()
    if not profile then
        print("Commander Party Frames: no board for this class (boards exist for Priests, Mages, Druids and Paladins)")
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
        intState["cshieldtest1"] = { AI = { expire = now + 1500, duration = 1800 } }
        intState["cshieldtest2"] = { AI = { expire = now + 150, duration = 1800 } }  -- amber
        intState["cshieldtest3"] = { AI = { expire = now + 900, duration = 1800 } }  -- buffed, cursed
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
        -- Ability strips: Mage2 shows the whole grammar (Ice Block cooling
        -- under Hypothermia's red rim with Cold Snap's gold pip), the priest
        -- a spent Fear + trinket (tier 2 surfacing), the warrior Last Stand
        abilityState["cshieldtest1"] = { BLOCK = now + 120, CS = now + 12 }
        lockState["cshieldtest1"] = { hypo = now + 18 }
        abilityState["cshieldtest2"] = { FEAR = now + 14, TRINKET = now + 80 }
        abilityState["cshieldtest5"] = { LASTSTAND = now + 60, PUMMEL = now + 4 }
        testRows = {
            { guid = "cshieldtest1", name = "Mage2", class = "MAGE", manaUser = true, health = 0.9, mana = 0.55, hpMax = 3800 },
            { guid = "cshieldtest2", name = "Priest", class = "PRIEST", manaUser = true, health = 0.85, mana = 0.7, hpMax = 4100 },
            { guid = "cshieldtest3", name = "Druid", class = "DRUID", manaUser = true, health = 0.6, mana = 0.4, hpMax = 4600 },
            { guid = "cshieldtest4", name = "Pally", class = "PALADIN", manaUser = true, health = 1.0, mana = 0.92, hpMax = 5200 },
            { guid = "cshieldtest5", name = "Tank", class = "WARRIOR", health = 0.42, hpMax = 6200, raidMark = 8 },
            { guid = "cshieldtest6", name = "You", class = playerClass, isSelf = true, manaUser = true, health = 0.75, mana = 0.8, hpMax = 4000 },
        }
        -- An ally's pet (Include Pets): a mana pet, so it takes the mana strip
        -- and the Intellect slot — unbuffed here, which is the ghost icon that
        -- says "cast it". It carries no ability strip and no spec, and it
        -- sorts under an equally quiet player.
        if DB("IncludePets", true) then
            allyAbsorbs["cshieldtest7"] = {
                [PWS_NAME or "Power Word: Shield"] = { expire = now + 19, duration = 30,
                  capacity = 1265, absorbed = 780,
                  icon = "Interface\\Icons\\Spell_Holy_PowerWordShield" },
            }
            testRows[#testRows + 1] = { guid = "cshieldtest7", name = "Felhunter",
                class = "WARLOCK", isPet = true, petOwner = "party4",
                manaUser = true, health = 0.68, mana = 0.35, hpMax = 2900 }
        end
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
        -- Elemental sample row: portrait slot, health as the main bar, the
        -- lifespan on the drain strip. Freeze is mid-cooldown here, so the
        -- tick is the frost-blue next-window mark at 22s of life left
        testRows[#testRows + 1] = { guid = "cshieldtestE", name = "Elemental",
            class = playerClass, isSelf = true, selfSpell = true, eleRow = true,
            icon = eleIcon or "Interface\\Icons\\Spell_Frost_SummonWaterElemental_2",
            state = "SHIELDED", healthMain = true, health = 0.85, ratio = 0.85,
            wsLeft = 31, lockMax = 45, rightText = "31s", mainText = "",
            freezeMark = 22 / 45, freezeMarkNext = true,
            freezeCd = 9, freezeDur = 25, freezeStart = now - 16 }
        Draw()
        print("Commander Party Frames: test board injected — rows drain and clear themselves")
        return
    end

    -- HOT layer (Druid): a party across the whole hot grammar — rolling,
    -- about to fall off, bare and hurt, bare and healthy — plus the two
    -- removable schools side by side (that pairing is the point: purple and
    -- green have to be tellable apart at a glance) and a teammate in CC.
    if layer == "HOT" then
        local defs = {}
        for _, d in ipairs(SDATA.DRUID_HOTS) do defs[d.key] = d end
        -- The upkeep strip across every reading it has: healthy, inside the
        -- rebuff window (amber), and missing. Row 4 keeps both slots empty,
        -- which is what an ally who just walked in looks like — and with the
        -- advisor on, Mark's slot there is the dark RED one.
        intState["cshieldtest1"] = { MOTW = { expire = now + 1500, duration = 1800 },
            THORNS = { expire = now + 480, duration = 600 } }
        intState["cshieldtest2"] = { MOTW = { expire = now + 150, duration = 1800 },
            THORNS = { expire = now + 40, duration = 600 } }
        intState["cshieldtest3"] = { MOTW = { expire = now + 900, duration = 1800 } }
        intState["cshieldtest5"] = { MOTW = { expire = now + 1200, duration = 1800 },
            THORNS = { expire = now + 220, duration = 600 } }
        -- Rolling: all three up, the full strip with Lifebloom at three stacks
        strip.state["cshieldtest1"] = {
            REJUV = { expire = now + 9, duration = 12, icon = defs.REJUV.icon, stacks = 0 },
            REGROWTH = { expire = now + 17, duration = 21, icon = defs.REGROWTH.icon, stacks = 0 },
            LIFEBLOOM = { expire = now + 6, duration = 7, icon = defs.LIFEBLOOM.icon, stacks = 3 },
        }
        -- About to bloom: one stack, inside the refresh window -> REFRESH
        strip.state["cshieldtest2"] = {
            LIFEBLOOM = { expire = now + 3, duration = 7, icon = defs.LIFEBLOOM.icon, stacks = 1 },
        }
        -- Rejuv only, healthy clock
        strip.state["cshieldtest5"] = {
            REJUV = { expire = now + 11, duration = 12, icon = defs.REJUV.icon, stacks = 0 },
        }
        -- The two schools a druid removes, so both row colors are on screen
        curseState["cshieldtest3"] = { expire = now + 18, duration = 30, dispelName = "Curse" }
        curseState["cshieldtest4"] = { expire = now + 11, duration = 20, dispelName = "Poison" }
        dispelState["cshieldtest3"] = { n = 1,
            { icon = "Interface\\Icons\\Spell_Shadow_CurseOfTounges", name = "Test Curse",
              dispelName = "Curse", expire = now + 18, duration = 30, cc = false, canDispel = true },
        }
        dispelState["cshieldtest4"] = { n = 1,
            { icon = "Interface\\Icons\\Ability_Creature_Poison_06", name = "Test Poison",
              dispelName = "Poison", expire = now + 11, duration = 20, cc = false, canDispel = true },
        }
        ccState["cshieldtest6"] = { expire = now + 7, duration = 10, name = "Test Polymorph",
            icon = "Interface\\Icons\\Spell_Nature_Polymorph" }
        -- A priest bubble on the hurt one: absorbs stay embedded on this layer
        allyAbsorbs["cshieldtest5"] = {
            [PWS_NAME or "Power Word: Shield"] = { expire = now + 22, duration = 30,
              capacity = 1265, absorbed = 315,
              icon = "Interface\\Icons\\Spell_Holy_PowerWordShield" },
        }
        targeters["cshieldtest5"] = 2
        specState["cshieldtest1"] = "DISC"
        specState["cshieldtest3"] = "FROST"
        specState["cshieldtest5"] = "PROTECTION"
        abilityState["cshieldtest3"] = { BLOCK = now + 120, CS = now + 12 }
        lockState["cshieldtest3"] = { hypo = now + 18 }
        abilityState["cshieldtest5"] = { LASTSTAND = now + 60, PUMMEL = now + 4 }
        testRows = {
            { guid = "cshieldtest1", name = "Priest", class = "PRIEST", manaUser = true, health = 0.72, mana = 0.6, hpMax = 4100 },
            { guid = "cshieldtest2", name = "Rogue", class = "ROGUE", health = 0.66, hpMax = 4300 },
            { guid = "cshieldtest3", name = "Mage", class = "MAGE", manaUser = true, health = 0.9, mana = 0.45, hpMax = 3800 },
            { guid = "cshieldtest4", name = "Hunter", class = "HUNTER", manaUser = true, health = 0.83, mana = 0.7, hpMax = 4800 },
            { guid = "cshieldtest5", name = "Tank", class = "WARRIOR", health = 0.38, hpMax = 6200, raidMark = 8 },
            { guid = "cshieldtest6", name = "Pally", class = "PALADIN", manaUser = true, health = 0.55, mana = 0.5, hpMax = 5200 },
            { guid = "cshieldtest7", name = "You", class = playerClass, isSelf = true, manaUser = true, health = 0.95, mana = 0.8, hpMax = 4400 },
        }
        -- The hunter's pet (Include Pets). Mark of the Wild lands on a pet
        -- whatever it runs on, so the buff slot applies even though a boar
        -- has no mana strip — and a hot of yours rolls on it like any ally.
        if DB("IncludePets", true) then
            strip.state["cshieldtest8"] = {
                REJUV = { expire = now + 5, duration = 12, icon = defs.REJUV.icon, stacks = 0 },
            }
            testRows[#testRows + 1] = { guid = "cshieldtest8", name = "Boar",
                class = "HUNTER", isPet = true, petOwner = "party4",
                health = 0.47, hpMax = 3300 }
        end
        Draw()
        print("Commander Party Frames: test board injected — rows drain and clear themselves")
        return
    end

    -- BLESS layer (Paladin): the whole grammar at once, and specifically the
    -- half no other board has — Forbearance. Row 3 is EXPOSED (locked with
    -- nothing up), row 5 is FADING (a Hand running out while locked), and the
    -- pair sitting next to each other is the point: red and orange have to be
    -- tellable apart at a glance the same way purple and green do on the hot
    -- board. The blessing slots run the full range too, including the case
    -- that ONLY this layer has: an ally carrying Kings whose Might slot must
    -- stay quiet, because the game will not give them both.
    if layer == "BLESS" then
        local defs = {}
        for _, d in ipairs(SDATA.PALADIN_HANDS) do defs[d.key] = d end
        -- Blessings: healthy, inside the rebuff window (amber), one-per-target
        -- suppression, and outright missing (the dark RED slot with the
        -- advisor on, because a naked ally is never correct)
        intState["cshieldtest1"] = { KINGS = { expire = now + 1500, duration = 1800 } }
        intState["cshieldtest2"] = { MIGHT = { expire = now + 150, duration = 600 } }
        intState["cshieldtest3"] = { WISDOM = { expire = now + 900, duration = 1800 } }
        intState["cshieldtest5"] = { KINGS = { expire = now + 240, duration = 600 } }
        -- Hands. Row 1 is covered and quiet; row 2 has a Freedom about to run
        -- out (REFRESH); row 5 has one running out while Forbearance-locked,
        -- which is FADING.
        strip.state["cshieldtest1"] = {
            SACRIFICE = { expire = now + 22, duration = 30, icon = defs.SACRIFICE.icon, stacks = 0 },
        }
        strip.state["cshieldtest2"] = {
            FREEDOM = { expire = now + 2, duration = 10, icon = defs.FREEDOM.icon, stacks = 0 },
        }
        strip.state["cshieldtest5"] = {
            BOP = { expire = now + 2, duration = 10, icon = defs.BOP.icon, stacks = 0 },
        }
        -- The lockout itself. Row 3 carries it with nothing up (EXPOSED);
        -- row 5 carries it under a Hand that is falling off (FADING). The
        -- ability bar reads the same record, so both rows also show its rim.
        lockState["cshieldtest3"] = { forb = now + 41 }
        lockState["cshieldtest5"] = { forb = now + 27 }
        -- Two of the three schools a paladin cleanses, so both row colors show
        curseState["cshieldtest4"] = { expire = now + 11, duration = 20, dispelName = "Poison" }
        dispelState["cshieldtest4"] = { n = 1,
            { icon = "Interface\\Icons\\Ability_Creature_Poison_06", name = "Test Poison",
              dispelName = "Poison", expire = now + 11, duration = 20, cc = false, canDispel = true },
        }
        dispelState["cshieldtest3"] = { n = 1,
            { icon = "Interface\\Icons\\Spell_Shadow_UnholyStrength", name = "Test Curse",
              dispelName = "Magic", expire = now + 14, duration = 20, cc = false, canDispel = true },
        }
        ccState["cshieldtest6"] = { expire = now + 7, duration = 10, name = "Test Polymorph",
            icon = "Interface\\Icons\\Spell_Nature_Polymorph" }
        -- A priest bubble on the hurt one: absorbs stay embedded on this layer
        allyAbsorbs["cshieldtest5"] = {
            [PWS_NAME or "Power Word: Shield"] = { expire = now + 22, duration = 30,
              capacity = 1265, absorbed = 315,
              icon = "Interface\\Icons\\Spell_Holy_PowerWordShield" },
        }
        targeters["cshieldtest5"] = 2
        specState["cshieldtest1"] = "DISC"
        specState["cshieldtest5"] = "PROTECTION"
        abilityState["cshieldtest5"] = { LASTSTAND = now + 60, PUMMEL = now + 4 }
        testRows = {
            { guid = "cshieldtest1", name = "Priest", class = "PRIEST", manaUser = true, health = 0.88, mana = 0.6, hpMax = 4100 },
            { guid = "cshieldtest2", name = "Rogue", class = "ROGUE", health = 0.44, hpMax = 4300 },
            { guid = "cshieldtest3", name = "Mage", class = "MAGE", manaUser = true, health = 0.9, mana = 0.45, hpMax = 3800 },
            { guid = "cshieldtest4", name = "Hunter", class = "HUNTER", manaUser = true, health = 0.83, mana = 0.7, hpMax = 4800 },
            { guid = "cshieldtest5", name = "Tank", class = "WARRIOR", health = 0.31, hpMax = 6200, raidMark = 8 },
            { guid = "cshieldtest6", name = "Druid", class = "DRUID", manaUser = true, health = 0.55, mana = 0.5, hpMax = 4600 },
            { guid = "cshieldtest7", name = "You", class = playerClass, isSelf = true, manaUser = true, health = 0.95, mana = 0.8, hpMax = 5200 },
        }
        -- The hunter's pet (Include Pets). Might applies to anything that
        -- swings, so a boar keeps that slot with no mana strip at all — and a
        -- Freedom of yours rides it like any ally row.
        if DB("IncludePets", true) then
            intState["cshieldtest8"] = { MIGHT = { expire = now + 400, duration = 600 } }
            strip.state["cshieldtest8"] = {
                FREEDOM = { expire = now + 6, duration = 10, icon = defs.FREEDOM.icon, stacks = 0 },
            }
            testRows[#testRows + 1] = { guid = "cshieldtest8", name = "Boar",
                class = "HUNTER", isPet = true, petOwner = "party4",
                health = 0.47, hpMax = 3300 }
        end
        Draw()
        print("Commander Party Frames: test board injected — rows drain and clear themselves")
        return
    end

    -- Ally-buff strip samples: Fortitude healthy on most of the party, inside
    -- the rebuff window on one, and missing on the tank — which with the
    -- advisor on is the dark RED slot, because Fortitude is never not worth
    -- casting. Divine Spirit only reaches the mana users' rows at all.
    intState["cshieldtest2"] = { FORT = { expire = now + 1500, duration = 1800 } }
    intState["cshieldtest3"] = { FORT = { expire = now + 1400, duration = 1800 },
        SPIRIT = { expire = now + 1200, duration = 1800 } }
    intState["cshieldtest4"] = { FORT = { expire = now + 120, duration = 1800 },
        SPIRIT = { expire = now + 900, duration = 1800 } }
    intState["cshieldtest6"] = { FORT = { expire = now + 1700, duration = 1800 },
        SPIRIT = { expire = now + 1700, duration = 1800 } }

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
    -- Ability strips (priest board gets them too — chassis)
    abilityState["cshieldtest1"] = { LASTSTAND = now + 90 }
    abilityState["cshieldtest2"] = { VANISH = now + 45, BLIND = now + 120 }
    abilityState["cshieldtest3"] = { BLOCK = now + 100 }
    lockState["cshieldtest3"] = { hypo = now + 20 }

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
    -- The priest's own hots on the strip, across every reading it has:
    -- rolling, inside the refresh window (the tinted/pulsing slot, which on
    -- this board is the ONLY warning an expiring hot gets), and a Prayer of
    -- Mending carrying its charge count.
    do
        local defs = {}
        for _, d in ipairs(SDATA.PRIEST_HOTS) do defs[d.key] = d end
        strip.state["cshieldtest1"] = {
            RENEW = { expire = now + 12, duration = 15, icon = defs.RENEW.icon, stacks = 0 },
            POM = { expire = now + 26, duration = 30, icon = defs.POM.icon, stacks = 5 },
        }
        strip.state["cshieldtest2"] = {
            RENEW = { expire = now + 3, duration = 15, icon = defs.RENEW.icon, stacks = 0 },
        }
        strip.state["cshieldtest4"] = {
            POM = { expire = now + 9, duration = 30, icon = defs.POM.icon, stacks = 2 },
        }
    end
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
        { guid = "cshieldtest1", name = "Tank", class = "WARRIOR", health = 0.42, hpMax = 6200, raidMark = 8 },
        { guid = "cshieldtest2", name = "Rogue", class = "ROGUE", health = 0.78, hpMax = 4300, raidMark = 7 },
        { guid = "cshieldtest3", name = "Mage", class = "MAGE", manaUser = true, health = 1.0, hpMax = 3800 },  -- full: shields extend the scale
        { guid = "cshieldtest4", name = "Druid", class = "DRUID", manaUser = true, health = 0.6, hpMax = 4600 },
        { guid = "cshieldtest5", name = "Hunter", class = "HUNTER", health = 0.9, hpMax = 4800 },
        { guid = "cshieldtest6", name = "You", class = select(2, UnitClass("player")), isSelf = true, manaUser = true, health = 0.85, hpMax = 4000 },
    }
    -- The warlock's pet (Include Pets): a shieldable ally like any other —
    -- one of yours is on it here, draining — with no ability strip of its own.
    if DB("IncludePets", true) then
        shieldState["cshieldtest7"] = { spellId = 25218, expire = now + 15, mine = true,
            absorbed = cap * 0.5, capacity = cap }
        allyAbsorbs["cshieldtest7"] = { [PWS_NAME or "Power Word: Shield"] =
            { expire = now + 15, duration = 30, capacity = cap, absorbed = cap * 0.5 } }
        testRows[#testRows + 1] = { guid = "cshieldtest7", name = "Voidwalker",
            class = "WARLOCK", isPet = true, petOwner = "party4",
            health = 0.55, hpMax = 3100 }
    end
    Draw()
    print("Commander Party Frames: test board injected — rows drain and clear themselves")
end

-- Ally-buff diagnostic (/cpf buffs). The advisor's whole credibility rests on
-- being able to answer "why is that red" — and the strip itself has no room to
-- say so, so it says it here: every tracked buff on every ally, its state, and
-- the rule's own words for the verdict it reached.
function CommanderPartyFrames_Buffs()
    if not layer then
        print("Commander Party Frames: no board for this class (Priest, Mage, Druid, Paladin)")
        return
    end
    print(string.format("|cff66ccffCPF buffs|r: layer=%s  advisor=%s", layer,
        tostring(DB("BuffAdvisor", true))))
    for _, def in ipairs(SDATA.BUFF_LIST) do
        print(string.format("  %-13s known=%-5s tracked=%-5s advised=%s",
            def.label, tostring(def.known and true or false),
            tostring(util.BuffTracked(def)), tostring(util.BuffAdvised(def))))
    end
    -- What the advisor currently believes about the other side, which is what
    -- the three situational rules are reading
    local seen = {}
    for class in pairs(util.enemyClasses) do seen[#seen + 1] = class end
    table.sort(seen)
    print(string.format("  enemy: %s%s",
        #seen > 0 and table.concat(seen, ", ") or "none seen",
        util.enemyShadowUntil > GetTime() and "  (+shadow damage observed)" or ""))
    if #SDATA.BUFF_ACTIVE == 0 then
        print("  no buffs are taking a slot right now")
        return
    end
    local now = GetTime()
    BuildRoster(rosterUnits)
    for _, unit in ipairs(rosterUnits) do
        local r = ResolveRow(unit, now)
        if r and (r.buffCount or 0) > 0 then
            for i = 1, r.buffCount do
                local slot = r.buffs[i]
                local state
                if slot.up then
                    local left = slot.expire and (slot.expire - now)
                    state = left and left > 0
                        and string.format("|cff40dd40up %dm|r", math.max(1, math.floor(left / 60 + 0.5)))
                        or "|cff40dd40up|r"
                    if slot.due then state = "|cffffa64dREBUFF|r" end
                elseif slot.urgent then
                    state = "|cffff4040MISSING - CAST IT|r"
                else
                    state = "|cff999999missing|r"
                end
                print(string.format("    %-10s %-13s %s%s", r.name or "?",
                    slot.def.label, state,
                    (not slot.up and slot.why) and ("  (" .. slot.why .. ")") or ""))
            end
        end
    end
end

-- Click-binding diagnostic (/cpf binds). Forty cells across eight modifier
-- rows is more than a settings page shows at a glance, and a binding that
-- silently never fires looks identical to one that was never set — so this
-- prints what is actually stored, flags anything bound to a spell this
-- character cannot cast, and names the profile it came from.
function CommanderPartyFrames_Binds()
    if not layer then
        print("Commander Party Frames: no board for this class (Priest, Mage, Druid, Paladin)")
        return
    end
    local profile = util.TalentProfile()
    print(string.format("|cff66ccffCPF binds|r: profile=%s (%s)  clickcast=%s",
        util.ProfileLabel(profile), profile, tostring(DB("ClickCast", false))))
    if not DB("ClickCast", false) then
        print("  Click-Cast is off, so none of these are live yet.")
    end
    local shown = 0
    for _, mod in ipairs(SDATA.CLICK_MODS) do
        for _, btn in ipairs(SDATA.CLICK_BUTTONS) do
            local v = util.GetBind(mod.key .. btn.key, profile)
            if v ~= nil then
                local _, label, missing = util.BindDisplay(v)
                shown = shown + 1
                print(string.format("  %-22s %-8s %s%s",
                    mod.label, btn.label, label,
                    missing and "  |cffff4040(you cannot cast this)|r" or ""))
            end
        end
    end
    if shown == 0 then print("  nothing bound in this profile") end
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
    elseif SDATA.STRIP_BOOKS[layer or ""] then
        local names, cds, units = 0, #strip.cds, 0
        for _ in pairs(strip.names) do names = names + 1 end
        for _ in pairs(strip.state) do units = units + 1 end
        print(string.format("  stripNames=%d  bannerCds=%d  unitsCarrying=%d",
            names, cds, units))
        if layer == "HOT" then
            print(string.format("  form=%s", tostring(strip.form and strip.form.key or "caster")))
        else
            print(string.format("  aura=%s  seal=%s",
                tostring(strip.aura and strip.aura.key or "none"),
                tostring(strip.seal and strip.seal.key or "none")))
        end
        local tracked = {}
        for _, def in ipairs(SDATA.BUFF_ACTIVE) do tracked[#tracked + 1] = def.key end
        print(string.format("  buffs tracked: %s",
            #tracked > 0 and table.concat(tracked, ", ") or "none"))
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
    -- What "coverage" counted differs by layer, so the line has to say which
    if layer == "HOT" then
        print(string.format("|cff66ccffCommander Party Frames|r: session hot uptime |cff33ff33%d%%|r over %dm%02ds — the share of your living team carrying one of your hots.",
            math.floor(pct + 0.5), mins, dur - mins * 60))
        return
    end
    if layer == "BLESS" then
        print(string.format("|cff66ccffCommander Party Frames|r: session blessing uptime |cff33ff33%d%%|r over %dm%02ds — the share of your living team carrying one of your blessings.",
            math.floor(pct + 0.5), mins, dur - mins * 60))
        return
    end
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
    -- Ahead of the enabled check: switching the module off must give the
    -- default party frames back (blizz.Hidden reads EnableShield too)
    blizz.Apply()
    if profile and CommanderPartyFramesDB and CommanderPartyFramesDB.EnableShield then
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
        -- A per-buff toggle changes the strip's SHAPE, so the tracked subset
        -- and the layout signature have to be rebuilt before anything redraws
        util.RefreshBuffs()
        if layer == "INT" then
            -- Always scanned (not just when the rows are on): the upkeep
            -- banner's Barrier segment reads the same state
            ResolveTrackedSpells()
            ScanSelfShields()
        end
        -- Reaches the icons built once in a constructor, which a redraw of the
        -- rows would never touch -- and the duration sweeps, which are built
        -- in the same place and are just as far out of a redraw's reach
        util.RestyleIcons()
        util.RestyleSweeps()
        -- Utility toggles changed which buttons belong on the banner
        BindMageUtilityButtons()
        ScanGroup()
        if securePool then SetupSecureRows() end
        Draw()
    else
        wipe(shieldState)
        wipe(wsState)
        wipe(dispelState)
        wipe(intState)
        wipe(curseState)
        wipe(ccState)
        wipe(allyAbsorbs)
        wipe(strip.state)
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
-- A respec changes which binding profile is live, so the secure rows have to
-- be rewritten. Soft-registered: a client without the event must not stop the
-- rest of the board from loading.
pcall(events.RegisterEvent, events, "CHARACTER_POINTS_CHANGED")
pcall(events.RegisterEvent, events, "PLAYER_TALENT_UPDATE")
pcall(events.RegisterEvent, events, "BAG_UPDATE_DELAYED")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player")
        PWS_NAME = (GetSpellInfo and GetSpellInfo(17)) or "Power Word: Shield"
        WS_NAME = (GetSpellInfo and GetSpellInfo(6788)) or "Weakened Soul"
        -- Which layer (if any) this class gets, what we can dispel, and the
        -- CC names worth glowing
        local _, classToken = UnitClass("player")
        playerClass = classToken
        profile = CLASS_PROFILES[classToken or ""]
        layer = profile and profile.layer or nil
        myDispelTypes = DISPEL_BY_CLASS[classToken or ""] or {}
        -- The ally-buff pair for THIS layer, resolved from stable base IDs.
        -- Only the active layer's pair goes in the set, so a mage's board can
        -- never count a druid's Mark of the Wild as "buffed" and vice versa.
        -- Order matters: every `known` flag below is read off knownSpells,
        -- so the spellbook has to be scanned before anything asks it
        RefreshKnownSpells()
        util.ResolveBuffBook()
        util.ResolveBindables()
        util.MigrateBinds()
        EnsureSettingsButton()
        blizz.EnsureButton()
        -- The self-buff this layer's banner watches: the mage's armor line,
        -- or the priest's Inner Fire. One map, whichever book applies, so the
        -- scan and the banner segment do not have to know which class they
        -- are looking at.
        if SDATA.SELF_ARMOR[layer or ""] and GetSpellInfo then
            for _, line in ipairs(SDATA.SELF_ARMOR[layer]) do
                for _, id in ipairs(line.ids) do
                    local n, _, icon = GetSpellInfo(id)
                    if n and not armorNames[n] then
                        armorNames[n] = icon
                            or (layer == "PWS" and "Interface\\Icons\\Spell_Holy_InnerFire"
                                or "Interface\\Icons\\Spell_Frost_FrostArmor02")
                    end
                end
            end
        end
        -- The Water Elemental is the mage's alone; it rode the armor block
        -- until Inner Fire moved in there
        if layer == "INT" then ResolveEleInfo() end
        -- Strip / form / aura / seal / banner-cooldown names, per layer
        ResolveStripInfo()
        -- Banner utilities exist for every supported class (the bandage
        -- control is chassis); the mage-only ones self-gate inside
        util.recentName = (GetSpellInfo and GetSpellInfo(SDATA.RECENT_BANDAGE_ID))
            or "Recently Bandaged"
        EnsureMageUtilButtons()
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
    -- Default-party-frame upkeep runs AHEAD of the profile gate: the setting
    -- is class-independent, so a class with no board must still be able to
    -- get its default frames back. Zoning re-creates/re-shows the container,
    -- and a toggle asked for mid-fight lands the moment combat drops.
    if event == "PLAYER_ENTERING_WORLD" or (event == "PLAYER_REGEN_ENABLED" and blizz.dirty) then
        blizz.Apply()
    end
    if not (profile and CommanderPartyFramesDB and CommanderPartyFramesDB.EnableShield) then return end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
    elseif event == "UNIT_AURA" then
        -- Pet tokens ride the same path as their owners': a shield landing on
        -- someone's felhunter, or a curse on it, has to repaint that row.
        if arg1 == "player" or GROUP_UNITS[arg1]
            or (SDATA.PET_OWNER[arg1] and DB("IncludePets", true)) then
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
        -- A new zone is a new enemy team: the shadow-damage memory is sticky
        -- on purpose within a fight (60s, so a quiet warlock still counts) and
        -- must not survive being carried into the next arena.
        if event == "PLAYER_ENTERING_WORLD" then util.enemyShadowUntil = 0 end
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
        -- Elemental appearing/despawning re-draws the banner promptly. With
        -- Include Pets on, ANY owner's pet coming or going is a roster change:
        -- the new unit wants a first aura scan, and the secure token map has
        -- to be rebuilt (out of combat — SetupSecureRows defers it otherwise).
        local pets = DB("IncludePets", true)
        if pets and arg1 then
            local u = (arg1 == "player" and "pet")
                or (arg1:find("^party%d") and ("partypet" .. arg1:sub(6)))
                or (arg1:find("^raid%d") and ("raidpet" .. arg1:sub(5)))
                or nil
            if u and UnitExists(u) then ScanUnit(u, IsReliable(u)) end
            if securePool then SetupSecureRows() end
        end
        if testUntil == 0 and (pets or (arg1 == "player" and layer == "INT")) then Draw() end
    elseif event == "BAG_UPDATE_DELAYED" then
        -- Conjures landed / consumables ran out: re-aim the use buttons and
        -- refresh the counters (counters alone if a fight froze the binds)
        BindMageUtilityButtons()
        if mageBtnsDirty then util.RefreshCounts() end
    elseif event == "CHARACTER_POINTS_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
        -- Respec: a different profile is live now. Out of combat this rebinds
        -- immediately; in combat SetupSecureRows defers it, which is correct —
        -- you cannot respec mid-fight anyway.
        if securePool then SetupSecureRows() end
    elseif event == "SPELLS_CHANGED" then
        RefreshKnownSpells()
        UpdateMyShieldValue()
        -- Training a buff (or its group version) adds its slot; the registry
        -- re-reads the book rather than waiting for a reload
        util.ResolveBuffBook()
        util.ResolveBindables()
        if layer == "INT" then
            ResolveTrackedSpells()
            ResolveEleInfo()
        end
        -- A respec can hand a druid Nature's Swiftness (or take it away), so
        -- the banner's cooldown segments re-filter with the spellbook
        ResolveStripInfo()
        BindMageUtilityButtons()
    end
end)
