-- Commander Party Frames: combat-first party frames built for arena — the
-- design bar is "what would the world's best RMP want on screen", answered
-- per class. PvP information wins fights: shields and their exact remaining
-- absorb, shield uptime, dispels, CC status — raid upkeep (Int/Fort timers)
-- is deliberately icon-sized, never a bar. The chassis is one compact row
-- per ally — health, power, identity, range, who the enemies are targeting,
-- dispellable debuffs, secure click-cast — and a CLASS LAYER decides what
-- the row's main bar and urgency states mean. Three cues triangulate every row so
-- it reads at a glance and survives colorblindness — an accent stripe (the
-- state), a strength bar, and a thin red drain (the thing blocking/afflicting).
-- PRIEST layer ("PWS"): shield = Power Word: Shield (absorb remaining), drain
--   = Weakened Soul, states = who to reshield next. The original board.
-- MAGE layer ("INT"): bar = HEALTH with a power strip under it; the row's
--   number is the ally's TOTAL shielding (PW:S + Ice Barrier + Mana Shield +
--   wards + Sacrifice, any caster, tooltip-calibrated and drained live by
--   SPELL_ABSORBED); left status icons = Arcane Intellect state + the biggest
--   shield; a removable Curse turns the row purple (drain = curse remaining).
--   The header is the mage's upkeep banner, and it is deliberately FOUR
--   things: armor (with a switch popout), Ice Block, Cold Snap, and the team
--   alert. Nothing goes on it that your action bar already tells you — every
--   spell you press wears a cooldown swipe three times this size, right where
--   you are looking to press it again — so the banner carries only the buff
--   you lose without noticing, the survival pair you check when there is no
--   time to look anywhere, and the two counts about your TEAM (curses you can
--   remove, allies in CC). Session uptime is opt-in, and the conjure /
--   consume / gem / portal cluster is opt-in as a group: between-games
--   convenience does not get to crowd in-game information. An opt-in extra
--   appends own-shield rows.
-- DRUID layer ("HOT"): bar = HEALTH with a power strip under it, same chassis
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
--   Lifebloom is a ROLL rather than a hot and gets its own instruments (see
--   the `roll` flag on SDATA.DRUID_HOTS): its own refresh window, a readable
--   clock in place of a radial sweep, stack pips, the drain strip this layer
--   never otherwise uses, and a late warning fired on the edge.
-- Other classes: the module sits inert (see CLASS_PROFILES).
--
-- Two things are CHASSIS rather than a layer's, because they mean the same
-- thing whatever you cast:
--   * the power strip under each health bar — the ally's LIVE resource, so a
--     rogue's energy and a warrior's rage are on the board and a druid's
--     strip changes when it shifts (settings: PowerBar / PowerBarColor)
--   * the FORECAST — pending dot damage, rolling hot healing, and a heal in
--     the air from anyone in the group, drawn on the bar that is going to
--     move. TBC exposes none of it, so all three are learned from the combat
--     log; see the FORECAST block below for the whole argument.
--   * the OVERHEAL RING — the forecast's other half, and the one part of the
--     healing accounting the log reports outright: a hairline ring just
--     inside a row when healing on that ally spilled, brightening with how
--     much of it did (settings: Overheal*)
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
    -- Lifebloom is not a hot with a stack count on it. It is a ROLL: seven
    -- seconds, one-second ticks, three stacks, and a refresh that resets the
    -- whole duration — so keeping it up is a decision you make every five
    -- seconds forever, and missing one costs three globals to rebuild (or
    -- pops the bloom you were saving). Everything else on this strip runs
    -- twelve to twenty-one seconds and forgives a late refresh.
    --
    -- `roll` is what earns it its own instruments: its own refresh window
    -- (a four-second window on a seven-second buff is most of its life), a
    -- readable clock instead of a radial sweep nobody can read at two
    -- seconds on a fifteen-pixel icon, stack pips, a drain bar, and a
    -- late-warning. See SDATA.ROLL_* and the Lifebloom settings section.
    { key = "LIFEBLOOM", label = "Lifebloom", baseId = 33763, duration = 7, stacking = true,
      roll = true, maxStacks = 3,
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
    -- `lowHot` marks the cheap rolling heal this layer puts on somebody who
    -- is dropping — the one whose ABSENCE on a low ally is worth saying out
    -- loud. One per book; the row's low-health ring reads it (see r.hotUp).
    { key = "RENEW", label = "Renew", baseId = 139, duration = 15, default = true,
      lowHot = true, icon = "Interface\\Icons\\Spell_Holy_Renew" },
    -- Prayer of Mending is the one entry on any strip that is not a per-ally
    -- aura at all. It is a single travelling object with five charges: it
    -- lands on one ally, heals, and JUMPS to the next, and the priest owns
    -- exactly one of them at a time. Every row's slot is therefore a view of
    -- the same thing, which is why it carries `charges` (pips read as a
    -- countdown of what is left of the object, not a stack that grew) and
    -- why the interesting events -- spent, expired, dispelled -- belong to
    -- the OBJECT rather than to any row. See util.pom.
    { key = "POM", label = "Mending", baseId = 33076, duration = 30, default = true,
      stacking = true, charges = true, maxStacks = 5,
      icon = "Interface\\Icons\\Spell_Holy_PrayerOfMendingtga" },
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
-- Pip lights along a strip icon's bottom edge. Three was Lifebloom's
-- number; Prayer of Mending needs five, and a slot only ever lights as
-- many as its own def asks for, so the extra two cost nothing on a roll.
SDATA.MAX_PIPS = 5
SDATA.STRIP_ACTIVE = {}       -- the active book's entries, tracked AND trained

-- The combat mark's art: the crossed-swords quadrant of the client's own
-- state icon — the same file and the same corner of it the stock player
-- portrait lights when you are in combat. Named here rather than written at
-- the call site so that if a client patch ever moves the file, the mark is
-- one line to re-point instead of a hunt through the paint pass.
SDATA.COMBAT_TEXTURE = "Interface\\CharacterFrame\\UI-StateIcon"
SDATA.COMBAT_TEXCOORD = { 0.5, 1.0, 0.0, 0.49 }

-- ---------------------------------------------------------------------------
-- The battleground marks: the short list of auras that change what an ally IS
-- on a battleground board, drawn beside the combat mark at the same size and
-- read the same way — a positive claim only, about someone you can see.
--
-- The combat mark answers "is this ally fighting". These answer the question
-- a battleground asks INSTEAD, which is "which of these ten people is the one
-- the next thirty seconds are about": the flag carrier is a healing target
-- with a different price on it than anyone else on the board, and a carrier
-- who has just picked up Berserking is taking a third more damage while a
-- carrier on Restoration needs a global less from you than the bar says.
--
-- Six entries and no toggles per entry, deliberately. This is not the ally
-- buff registry — there is nothing to maintain here, nothing to cast, and no
-- version of a battleground where a player wants the flag hidden but the
-- speed berry shown. One switch covers the set.
--
--   prio   which mark wins a slot when an ally holds more than one. The flag
--          outranks everything: a carrier with Berserking is still, first,
--          the carrier. Below it the powerups rank by how much they change
--          what you would do next — Berserking (they are taking 10% more and
--          dealing 30% more), Restoration (healing they are getting without
--          you), Speed (they are leaving).
--
-- IDs verified against this client's own spell data (2026-09-08).
-- ---------------------------------------------------------------------------
SDATA.MAX_BG_MARKS = 2      -- slots per row: the flag, and the best powerup
-- The stacked mark seat (Mark Layout = GRID): one two-by-two cell block to
-- the right of the bar, every mark in its own fixed cell, so a row carrying
-- all four at once still reads at a glance --
--     [ their target's raid mark | in combat ]
--     [ carrying the flag        | powerup   ]
SDATA.MARK_CELL = 10        -- one cell's edge; two rows of them fit a 22px row
SDATA.MARK_SEAT = 2 * 10 + 1  -- the seat's width: two cells and a hairline gap
SDATA.BG_BUFFS = {
    -- The three flags. Which one an ally wears says which battleground you
    -- are in, not which team they are on: you only ever hold the ENEMY flag,
    -- so a Silverwing Flag on your row means a Horde player took ours.
    { key = "WSG_H",  id = 23333, prio = 1, label = "Carrying the flag",
      icon = "Interface\\Icons\\INV_BannerPVP_01" },
    { key = "WSG_A",  id = 23335, prio = 1, label = "Carrying the flag",
      icon = "Interface\\Icons\\INV_BannerPVP_02" },
    { key = "EOTS",   id = 34976, prio = 1, label = "Carrying the flag",
      icon = "Interface\\Icons\\INV_Misc_SummerFest_BrazierGreen" },
    -- The three battleground powerups, on the ground in Warsong Gulch and
    -- Arathi Basin alike
    { key = "BERSERK", id = 23505, prio = 2, label = "Berserking",
      icon = "Interface\\Icons\\Spell_Nature_BloodLust" },
    { key = "RESTO",   id = 23493, prio = 3, label = "Restoration",
      icon = "Interface\\Icons\\INV_Misc_Fork&Knife" },
    { key = "SPEED",   id = 23451, prio = 4, label = "Speed",
      icon = "Interface\\Icons\\INV_Enchant_EssenceNetherLarge" },
}
SDATA.BG_BY_NAME = {}       -- localized aura name -> def, resolved from the client
-- The icon face without its border: these are item/spell art rather than the
-- flat quadrant the combat mark cuts out of UI-StateIcon, and at thirteen
-- pixels the stock 5%-per-side frame is a quarter of the mark.
SDATA.BG_TEXCOORD = { 0.08, 0.92, 0.08, 0.92 }

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
    -- `mine` is the one place this family breaks the registry's any-caster
    -- rule, and it is not a preference — it is the game. Two paladins may each
    -- hold a DIFFERENT blessing on the same target at the same time, so the
    -- other paladin's Kings neither satisfies your slot nor stops your global.
    -- A board that counted it would tell you a target is handled when your own
    -- blessing has been off them for ten minutes. See util.BuffMineOnly.
    --
    -- Sanctuary is `default = true` like the other three you actually hand out:
    -- it is a 31-point Protection talent, so the TRAINED gate is already the
    -- only switch that matters, and a prot paladin who has spent those points
    -- wants it watched. Salvation and Light stay off — both are choices you
    -- make once rather than upkeep you watch — but in combined mode every
    -- trained blessing is offered as an assignment regardless, because a line
    -- in a dropdown costs no width (see util.BlessOptions).
    BLESS = {
        { key = "KINGS", label = "Kings", id = 20217, groupId = 25898,
          duration = 600, targets = "ALL", default = true, advise = "ALWAYS",
          oneOf = "BLESSING", mine = true, icon = "Interface\\Icons\\Spell_Magic_MageArmor" },
        -- Might is strength and it is for people who swing things. A mage's
        -- row should no more carry a dark Might slot than a rogue's should
        -- carry Intellect, which is what targets = "MELEE" buys.
        { key = "MIGHT", label = "Might", id = 19740, groupId = 25782,
          duration = 600, targets = "MELEE", default = true, advise = "ALWAYS",
          oneOf = "BLESSING", mine = true, icon = "Interface\\Icons\\Spell_Holy_FistOfJustice" },
        { key = "WISDOM", label = "Wisdom", id = 19742, groupId = 25894,
          duration = 600, targets = "MANA", default = true, advise = "ALWAYS",
          oneOf = "BLESSING", mine = true, icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom" },
        -- Threat management: real in a raid, close to noise in an arena. It
        -- gets a slot for the player who wants it and never an opinion.
        { key = "SALVATION", label = "Salvation", id = 1038, groupId = 25895,
          duration = 600, targets = "ALL", default = false,
          oneOf = "BLESSING", mine = true, icon = "Interface\\Icons\\Spell_Holy_SealOfSalvation" },
        { key = "SANCTUARY", label = "Sanctuary", id = 20911, groupId = 25899,
          duration = 600, targets = "ALL", default = true, advise = "VS_MELEE",
          oneOf = "BLESSING", mine = true, icon = "Interface\\Icons\\Spell_Nature_LightningShield" },
        { key = "LIGHT", label = "Light", id = 19977, groupId = 25890,
          duration = 600, targets = "ALL", default = false,
          oneOf = "BLESSING", mine = true, icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02" },
    },
}

-- ---------------------------------------------------------------------------
-- The combined blessing slot: Pally Power's answer, in this board's grammar.
--
-- Six blessings sharing one exclusive slot on the target is six icons asking a
-- question that only ever has ONE answer, and five of them are always dark. So
-- the family collapses into a single slot per ally that shows the blessing you
-- decided that ally should be carrying, and reads lit / amber / dark against
-- THAT — the same three states every other upkeep slot on this board uses.
--
-- What the slot shows is an ASSIGNMENT, resolved per row in this order:
--
--   1. a per-player override    (BlessAssign, keyed by name — "Grimtusk")
--   2. a per-class default      (BlessClass,  keyed by class token)
--   3. BLESS_CLASS_DEFAULT below
--   4. the first trained blessing that suits the target at all
--
-- Steps 2-4 are what make a stranger who just joined show something sensible
-- instead of nothing, and step 1 is the exception you actually reach for.
SDATA.BLESS_FAMILY = "BLESSING"
SDATA.BLESS_NONE = "NONE"       -- an assignment of "leave this one alone"

-- Kings across the board, because in TBC it simply is the best blessing for
-- every class that can hold one — this is a starting point you are meant to
-- edit, not a claim about your comp. Pets get Might: they swing, they have no
-- stats worth a percentage, and Kings on a pet is a wasted global.
SDATA.BLESS_CLASS_DEFAULT = {
    WARRIOR = "KINGS", PALADIN = "KINGS", HUNTER = "KINGS", ROGUE = "KINGS",
    PRIEST  = "KINGS", SHAMAN  = "KINGS", MAGE   = "KINGS", WARLOCK = "KINGS",
    DRUID   = "KINGS",
    PET     = "MIGHT",
}
-- The classes the assignment grid offers, plus the pet pseudo-class. Ordered
-- rather than pairs()'d so the settings grid is stable between draws.
SDATA.BLESS_CLASS_ORDER = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID", "PET",
}

-- The class-grouped row order's rank per class: the same canon order the
-- blessing grid uses, so a board read top to bottom lists classes the way
-- every other class list in this suite does. Built once rather than searched
-- per comparison — the sort runs at draw rate. A pet carries its OWNER's
-- class token (see ResolveRow), so it groups under its owner; "PET" is the
-- grid's pseudo-class and never reaches a row.
SDATA.CLASS_SORT_RANK = {}
for i, classKey in ipairs(SDATA.BLESS_CLASS_ORDER) do
    if classKey ~= "PET" then SDATA.CLASS_SORT_RANK[classKey] = i end
end

-- The synthetic def that stands in for the whole family in SDATA.BUFF_ACTIVE.
-- It carries no `oneOf`: the supersede rule exists to stop six slots nagging
-- past each other, and with one slot there is nothing to supersede — an ally
-- carrying the wrong blessing of yours is a slot that should be asking.
SDATA.BLESS_SLOT = {
    key = "BLESSING", label = "Blessing", dbKey = "BLESS:BLESSING",
    combined = true, targets = "ALL", duration = 600,
    default = true, advise = "ALWAYS", mine = true,
    icon = "Interface\\Icons\\Spell_Magic_MageArmor",
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
-- The mage banner's cooldown segments — TWO of them, and the shortness of
-- this list is the whole point.
--
-- It was ten (Evocation, Counterspell, Icy Veins, Presence of Mind, Arcane
-- Power, Combustion, Invisibility, Frost Nova on top of these two), which
-- made the banner a second action bar drawn in 12px icons. The filter that
-- cut it is the one this board is built on: a segment earns its width only
-- if it says something your ACTION BAR cannot. Every spell you press has a
-- cooldown swipe already, three times the size, exactly where your eyes go
-- to press it again — repeating it up here buys nothing and costs the room
-- the things that ARE unique to this banner need.
--
-- What survives is the pair you check when there is no time to look at
-- anything: can I Block, and can I Cold Snap it back. Cold Snap is here on
-- its own merits too — its value is entirely relative to the other two
-- (Block and Barrier), so it is the one mage cooldown that genuinely reads
-- better next to them than alone on a bar.
--
-- Ice Barrier and the Water Elemental stay absent for the older version of
-- the same rule: the barrier already has a My Shields row carrying its real
-- remaining absorb, and the elemental has a richer personal row than a
-- segment could ever be. A banner that repeats what is two inches below it
-- is width spent twice.
--
-- The ids and icons are the ones the party ability book already uses, which
-- is the only list in this addon that has been checked against the live
-- client rather than written from memory.
SDATA.MAGE_BANNER_CDS = {
    { key = "BLOCK",    id = 45438, cd = 300, icon = "Interface\\Icons\\Spell_Frost_Frost" },
    { key = "COLDSNAP", id = 11958, cd = 480, icon = "Interface\\Icons\\Spell_Frost_WizardMark" },
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
-- The roll's own settings, so the engine never spells out "Lifebloom" at a
-- call site. Only the druid book has a roll today; a second one (a monk's
-- Renewing Mist, in another expansion) would cost its def flag and nothing
-- else. Colours are the roll bar's three states, which are also the clock's.
SDATA.ROLL_SAFE   = { 0.35, 0.85, 0.45 }   -- plenty of time: leave it alone
SDATA.ROLL_DUE    = { 1.00, 0.72, 0.20 }   -- inside the window: refresh now
SDATA.ROLL_LATE   = { 1.00, 0.25, 0.22 }   -- you are late; the stacks are going
SDATA.ROLL_BLOOM  = { 0.75, 0.55, 1.00 }   -- at max stacks: refresh, or let it pop

-- Prayer of Mending's charge pips. A charge count is a fuel gauge, not a
-- stack that grew, so it reads the other way round from the roll's: full is
-- calm and empty is the thing you want to see coming, because the last
-- charge is the one that ends the object and puts a global back on you.
-- The health bar's colour ramp, as anchors rather than as arithmetic.
--
-- It used to be one linear expression per channel, which had two problems.
-- The first was that a straight RGB line from green to red runs through a
-- muddy olive, so the interesting middle of the range -- the part where you
-- decide who to heal -- was the part that read worst. The second was that it
-- was simply too forgiving: green held its full value until eighty percent
-- and the slide to red was linear all the way down, so a teammate at sixty
-- percent looked about as calm as one at eighty. In an arena sixty percent is
-- one connect from dead.
--
-- So: anchors, spaced by how much each band actually MATTERS rather than
-- evenly. Green survives the top fifteen percent (nobody needs a warning at
-- 90%), the seventies are already yellow, sixty-five is amber outright, and
-- it is properly red by a quarter -- while the path between them goes green
-- to yellow to orange to red, the way a health bar is read everywhere else,
-- instead of cutting the corner through olive.
SDATA.HP_RAMP = {
    { 0.00, 0.95, 0.13, 0.13 },   -- about to die: deep red
    { 0.25, 1.00, 0.22, 0.16 },   -- red
    { 0.45, 1.00, 0.48, 0.16 },   -- orange
    { 0.65, 1.00, 0.76, 0.20 },   -- amber
    { 0.85, 0.55, 0.80, 0.26 },   -- yellow-green
    { 1.00, 0.20, 0.80, 0.30 },   -- untouched: green
}

SDATA.CHARGE_FULL = { 1.00, 0.92, 0.62 }   -- four or five left: it is working
SDATA.CHARGE_MID  = { 1.00, 0.72, 0.30 }   -- two or three: plan the recast
SDATA.CHARGE_LAST = { 1.00, 0.38, 0.26 }   -- one: the next tick spends it

-- Why Prayer of Mending needs a tracker of its own, and what it is watching.
--
-- Every other entry on any strip is an aura on ONE ally: it lands, it runs
-- down, it drops, and the row it sat on is the only row that ever had an
-- opinion about it. Mending is a single object with five charges that MOVES.
-- It heals whoever holds it, jumps to the next ally, and does that until the
-- charges run out or the thirty seconds do. A priest owns exactly one.
--
-- From any single row's point of view every one of these looks identical —
-- "the aura left this GUID":
--
--     it bounced to someone else          (nothing happened; this is the spell working)
--     the last charge was spent           (it did its job; recast)
--     the thirty seconds ran out          (it was wasted; recast)
--     a dispel took it                    (it was stolen; recast NOW)
--     the holder died                     (it went with them)
--
-- Only the first of those is not worth a sound, and it is by far the most
-- common — a five-charge Mending bounces four times per cast. So an alert
-- hung off "the aura left this row" would fire four times for every one time
-- it should, which is the same as an alert that never fires, because you
-- stop hearing it.
--
-- The tracker therefore follows the OBJECT rather than the rows. When the
-- aura leaves its holder we do not declare anything: we arm a short grace
-- (SDATA.POM_GRACE) and wait. If it reappears on ANY ally inside that grace
-- it bounced — cancel silently, and light the hop. If the grace lapses with
-- the object nowhere, it is genuinely gone, and by then we know WHY: what
-- the combat log said last decides between spent, expired, dispelled and
-- lost. That single wait is the whole trick, and it is why the alert cannot
-- fire on a bounce even in principle.
--
-- The grace is deliberately not a setting. A bounce's REMOVED and APPLIED
-- arrive in the same combat-log flush, so anything above a few frames is
-- already generous; exposing it would only offer a knob whose wrong settings
-- are "alerts on every bounce" and "alerts arrive late".
-- ---------------------------------------------------------------------------
-- Alert sounds: every noise this board can make, in one place.
--
-- There were three of these hardcoded at their call sites, two of them the
-- same stock RAID_WARNING, which is also what half the addons on the client
-- use — so "something happened" was the most any of them could tell you
-- before you looked. A sound is only worth playing if you can name it without
-- looking, and that means the board has to make FEWER kinds of noise, each
-- one distinct, and let you pick which is which.
--
-- Two channels, tried in order, because neither is universally safe: a
-- SOUNDKIT constant is the sanctioned route but the table is client-version
-- dependent, and a file path is stable across those versions but only for
-- files that actually shipped. Every play is pcall'd, so an entry this client
-- does not have degrades to silence rather than to an error — and the Test
-- buttons in the settings page are how you find that out in ten seconds
-- instead of mid-arena.
SDATA.ALERT_SOUNDS = {
    { key = "WARNING", label = "Raid Warning",
      kit = "RAID_WARNING", id = 8959, file = "Sound\\Interface\\RaidWarning.wav" },
    { key = "READY",   label = "Ready Check",
      kit = "READY_CHECK", id = 8960, file = "Sound\\Interface\\ReadyCheck.wav" },
    { key = "QUEST",   label = "Quest Chime",
      kit = "IG_QUEST_LIST_COMPLETE", id = 883 },
    -- The two tolls are the Mending pair. Same instrument, two pitches: one
    -- object, two outcomes, and you can tell which without looking at the
    -- board — which is the entire reason the alert exists.
    { key = "TOLL_HI", label = "Bell — High",
      file = "Sound\\Doodad\\BellTollAlliance.wav" },
    { key = "TOLL_LO", label = "Bell — Low",
      file = "Sound\\Doodad\\BellTollHorde.wav" },
    { key = "DOCK",    label = "Docking Bell",
      file = "Sound\\Doodad\\BoatDockedWarning.wav" },
    { key = "PING",    label = "Map Ping",
      file = "Sound\\Interface\\MapPing.wav" },
    { key = "OPEN",    label = "Window Open",
      file = "Sound\\Interface\\AuctionWindowOpen.wav" },
    { key = "LEVEL",   label = "Level Up",
      file = "Sound\\Interface\\LevelUp.wav" },
    { key = "NONE",    label = "Silent", silent = true },
}
SDATA.ALERT_SOUND_BY_KEY = {}
for _, e in ipairs(SDATA.ALERT_SOUNDS) do SDATA.ALERT_SOUND_BY_KEY[e.key] = e end

-- Which saved variable each alert's chosen sound lives under. A key table for
-- the same reason SDATA.BANNER_CD_KEY is one: the engine never spells a saved
-- variable at a call site, and the settings-reach check can read this and
-- know these four are real reads.
SDATA.ALERT_SOUND_KEY = {
    EXPOSE   = "SoundExpose",
    LBLATE   = "SoundLBLate",
    POMSPENT = "SoundPoMSpent",
    POMLOST  = "SoundPoMLost",
}

-- The alerts themselves, in the order the settings page lists them.
--   layer     which board can even make this noise (nil = every board)
--   onKey     the alert's own on/off switch, which lives with the feature it
--             belongs to rather than here; the sounds page reads it so a
--             muted alert is visibly greyed rather than silently dead
--   default   the sound it makes out of the box
SDATA.ALERT_LINES = {
    { key = "EXPOSE", label = "Shield Break", default = "WARNING",
      onKey = "ExposeAlertSound",
      tip = "Your shield breaking off an ally who is still alive — a reshield you owe right now." },
    { key = "LBLATE", label = "Lifebloom Late", default = "QUEST", layer = "HOT",
      onKey = "LBAlertSound",
      tip = "A Lifebloom of yours going late: past the point where you are refreshing early and into refreshing behind." },
    { key = "POMSPENT", label = "Mending Spent", default = "TOLL_HI", layer = "PWS",
      onKey = "PoMAlertSound",
      tip = "Your Prayer of Mending spending its last charge. It did the job it was cast for, and only the cooldown is left to wait on." },
    { key = "POMLOST", label = "Mending Lost", default = "TOLL_LO", layer = "PWS",
      onKey = "PoMAlertSound",
      tip = "Your Prayer of Mending ending early — the thirty seconds run out, a dispel taking it, or the holder dying with it. A recast you owe now." },
}
SDATA.ALERT_BY_KEY = {}
for _, e in ipairs(SDATA.ALERT_LINES) do
    e.dbKey = SDATA.ALERT_SOUND_KEY[e.key]
    SDATA.ALERT_BY_KEY[e.key] = e
end

SDATA.POM_GRACE = 0.7           -- seconds to wait for a bounce before declaring a loss
SDATA.POM_DURATION = 30         -- fallback scale only; the aura's own expiry wins
SDATA.POM_CHARGES = 5
SDATA.POM_HOP_HOLD = 0.55       -- how long the arrival flare and the departure ghost last
-- Why it ended, and how each one reads. `alert` is whether it earns a sound:
-- BOUNCE and RECAST never do, and they are the two that end a session
-- without anything having gone wrong.
SDATA.POM_REASONS = {
    SPENT    = { label = "spent",     alert = true,  tint = { 0.55, 0.95, 0.70 } },
    EXPIRED  = { label = "expired",   alert = true,  tint = { 1.00, 0.72, 0.20 } },
    DISPELLED= { label = "dispelled", alert = true,  tint = { 0.85, 0.55, 1.00 } },
    DIED     = { label = "lost",      alert = true,  tint = { 0.80, 0.80, 0.85 } },
    LOST     = { label = "lost",      alert = true,  tint = { 1.00, 0.38, 0.26 } },
    BOUNCE   = { label = "bounced",   alert = false },
    RECAST   = { label = "recast",    alert = false },
}
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
-- The power strip under the health bar. It used to be a MANA strip, drawn for
-- mana users on the three health-bar layers only, which left a rogue's energy
-- and a warrior's rage — the two resources an arena actually plans around —
-- with nothing at all, and gave the priest board no strip on any class. It is
-- now every class's live power, on every layer, off a setting that still has
-- "mana users only" as an option for anyone who liked the old board.
--
-- Keyed by the TOKEN UnitPowerType returns as its second value, so a druid
-- that shifts reads as RAGE or ENERGY the moment it does. Happiness is a
-- hunter pet's, and it is drawn because a pet row is an ally row.
SDATA.POWER_COLORS = {
    MANA      = { 0.25, 0.5,  0.95 },
    RAGE      = { 0.85, 0.2,  0.2  },
    ENERGY    = { 0.95, 0.85, 0.25 },
    FOCUS     = { 0.9,  0.55, 0.25 },
    HAPPINESS = { 0.35, 0.8,  0.4  },
    RUNIC_POWER = { 0.35, 0.7, 0.9 },
}
SDATA.POWER_COLOR_DEFAULT = { 0.25, 0.5, 0.95 }   -- the classic blue strip
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

-- Banner segments that double as a SWITCHER: click the segment, get a popout
-- of secure cast buttons for every line of that kind you have trained.
--
-- The mage's armor switcher was the first, and for a long time the only one,
-- because a mage picks an armor and leaves it. A paladin is the case that
-- actually wanted this: eight auras and eight seals, the seal running out
-- every thirty seconds, and both of them things you change BETWEEN pulls and
-- sometimes during one. Two switchers on one banner, so each names the
-- segment it hangs under.
--
--   seg    which banner segment is the toggle. Both banners put their
--          switchable state first, which is what makes this a fixed index
--          rather than a search.
--   lines  the same best-first rank lists the scan already reads, so the
--          button casts the top rank you know and nothing has to agree twice.
SDATA.SWITCHERS = {
    INT = {
        { key = "ARMOR", label = "Armor", seg = 1, lines = SDATA.ARMOR_LINES },
    },
    BLESS = {
        { key = "AURA", label = "Aura", seg = 1, lines = SDATA.PALADIN_AURAS },
        { key = "SEAL", label = "Seal", seg = 2, lines = SDATA.PALADIN_SEALS },
    },
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
local mageUtil, conjureBtn, consumeBtn
local gemBtn, bandageBtn
-- Everything the newer banner utilities need, in ONE table: this chunk sits
-- close to Lua's 200-local cap (see the SDATA note above), so new state goes
-- in here rather than adding chunk locals.
--   gemBtn/portalBtn/bandageBtn  the secure buttons themselves
--   portalPop                    insecure popout frame (a switcher's pattern)
--   portalButtons                pooled popout children
--   counts                       cached bag tallies (water/food/gem/bandage)
local util = {
    portalButtons = {}, counts = {},
    bandageUntil = 0, bandageUnit = "player", nextBandageScan = 0,
    -- Row-flash colour overrides, parallel to rowFlash. On `util` rather than
    -- a chunk local for the reason everything else here is (Lua's 200-local
    -- cap); nil for a row means the flash's own red.
    rowFlashTint = {},
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
-- Per-scan scratch for the battleground marks. A COUNTED array rather than a
-- wiped table: at most a couple of entries per unit, on every UNIT_AURA, for
-- forty people — the entry tables are reused and the count is the wipe. On
-- `util` rather than as chunk locals for the reason stated above (the 200-local
-- cap), which this feature reached exactly.
util.bgScan = { n = 0 }
function util.BGCompare(x, y) return x.prio < y.prio end
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

-- The banner switchers, for the harness. Nothing in the game reads this: the
-- popouts carry secure children and are their own business, but a test has no
-- other way to ask whether two of them got built and where they landed.
function CommanderPartyFrames_GetSwitchers() return util.switchers end

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

-- Alert sounds, for the settings page's Alert Sounds section. Filtered to the
-- layer here rather than there, so "which noises can THIS board make" is
-- answered once, by the file that owns the answer.
function CommanderPartyFrames_GetAlertLines(layerKey, out)
    out = out or {}
    for i = #out, 1, -1 do out[i] = nil end
    for _, line in ipairs(SDATA.ALERT_LINES) do
        if not line.layer or line.layer == layerKey then out[#out + 1] = line end
    end
    return out
end

function CommanderPartyFrames_GetAlertSounds() return SDATA.ALERT_SOUNDS end

-- Auditioning one from the settings page deliberately ignores that alert's
-- own mute: hearing a sound you have currently switched off is exactly how
-- you decide whether to switch it back on.
function CommanderPartyFrames_PlayAlert(key) util.PlayAlert(key) end

function CommanderPartyFrames_GetProfileMode()
    local _, classToken = UnitClass("player")
    local p = CLASS_PROFILES[classToken or ""]
    return p and p.layer or nil, classToken
end

-- ---------------------------------------------------------------------------
-- The blessing assignment, as the settings page sees it. Everything here is a
-- thin wrapper over util.Bless* so the two ways in — the row's menu and the
-- settings grid — cannot drift apart on what "assigned" means.
-- ---------------------------------------------------------------------------

-- One table rather than half a dozen file locals: the main chunk of this file
-- is within sight of Lua 5.1's 200-local ceiling, and a feature that wants
-- several scratch tables is exactly how a file walks into it. Everything the
-- blessing UI keeps between calls lives in here, on both sides of the export
-- boundary — the row's menu below reaches the same table.
local bless = {
    optScratch = {},    -- the row menu's option list
    optOut = {},        -- the settings grid's option list (same shape, other caller)
    probe = {},         -- a stand-in row for a whole class
    roster = {}, seen = {},
}

-- ---------------------------------------------------------------------------
-- FORECAST: what is already on its way to an ally, before anything lands.
--
-- Three questions the board could never answer, and every one of them decides
-- a global:
--   * their DOTS      how much damage is still queued in what is ticking on
--                     them — a rogue at 40% with a full Corruption on him is
--                     not a rogue at 40%
--   * their HOTS      how much healing is already rolling — the reason NOT to
--                     spend a big heal on someone who is about to be fine
--   * an INBOUND cast a heal in the air from anyone in the group, you
--                     included, so two healers stop landing on the same target
--
-- TBC gives none of this. There is no API for what a dot will do, no API for
-- what a heal will land for, and no API at all for who another player is
-- casting on. So all three are LEARNED, from the two things the client does
-- tell us:
--
--   the combat log       every periodic tick and every completed heal arrives
--                        with its exact amount. Watch them and you know what
--                        THIS warlock's Corruption does to THIS target and
--                        what THAT priest's Greater Heal lands for — better
--                        numbers than any static table, because they already
--                        include gear, talents, resistances and buffs.
--   the aura list        what is currently on the ally, and when it falls off.
--                        Ticks remaining = time remaining / tick interval.
--
-- Learning has one cost — an unseen spell is worth nothing until its first
-- tick lands — so the shapes (is this a dot or a hot, how often does it tick)
-- are SEEDED for the spells an arena actually runs into, and only the amounts
-- wait on the log. In practice the first tick of anything fills the rest in.
--
-- Amounts are held per (target, spell) rather than per caster: the number
-- that matters is what this spell is doing to THIS ally, which already folds
-- in their resistances and their damage reduction. A cross-target average is
-- the fallback for a dot that was applied but has not ticked yet.
-- ---------------------------------------------------------------------------

-- Tick shapes, by interval. Every rank of a TBC periodic shares one localized
-- name, so one id per spell resolves the whole family.
SDATA.PERIODIC_SEED = {
    { kind = "DOT", interval = 3, ids = {
        172,    -- Corruption
        348,    -- Immolate
        18265,  -- Siphon Life
        30108,  -- Unstable Affliction
        589,    -- Shadow Word: Pain
        2944,   -- Devouring Plague
        34914,  -- Vampiric Touch
        8921,   -- Moonfire
        1978,   -- Serpent Sting
        8050,   -- Flame Shock
        772,    -- Rend
        703,    -- Garrote
        1822,   -- Rake
        2818,   -- Deadly Poison
        11366,  -- Pyroblast (the burn)
        12162,  -- Deep Wounds
        13218,  -- Wound Poison
    } },
    { kind = "DOT", interval = 2, ids = {
        980,    -- Curse of Agony
        5570,   -- Insect Swarm
        1943,   -- Rupture
        1079,   -- Rip
    } },
    { kind = "HOT", interval = 3, ids = {
        139,    -- Renew
        774,    -- Rejuvenation
        8936,   -- Regrowth
    } },
    { kind = "HOT", interval = 1, ids = {
        33763,  -- Lifebloom
    } },
}
-- Direct heals, so a cast can be recognised as a heal on its very first
-- frame — before the log has ever shown us one land. The AMOUNT still waits
-- on the log; until then an inbound cast is a fact without a number, which
-- is still worth knowing ("someone else has them").
SDATA.HEAL_SEED = {
    2050, 2060, 2061, 596,          -- Priest: Lesser Heal, Greater Heal, Flash Heal, Prayer of Healing
    25314, 33076,                   -- Priest: Greater Heal (TBC rank), Prayer of Mending
    5185, 5186, 8936, 18562,        -- Druid: Healing Touch, ..., Regrowth, Swiftmend
    331, 8004, 1064, 25357,         -- Shaman: Healing Wave, Lesser Healing Wave, Chain Heal
    635, 19750, 633, 2800,          -- Paladin: Holy Light, Flash of Light, Lay on Hands
    755,                            -- Warlock: Health Funnel
}
SDATA.FORECAST_MAX = 12     -- periodic auras tracked per ally (pooled, never grown)
SDATA.HEAL_BURST = 0.4      -- heals this close together are one multi-target cast

-- Everything the forecast keeps between calls, in ONE table for the same
-- reason `util`, `strip` and `bless` are one each (Lua's 200-local chunk cap).
--   kind      localized aura name -> { dot = bool, interval = seconds }
--   heal      localized spell name -> true (a direct heal, seeded and learned)
--   on        guid -> pooled array of live periodics; list.n is the live count
--   amtOn     guid .. "\30" .. name -> last tick seen on THAT unit
--   amtAny    name -> rolling mean across every target (the fallback)
--   healAmt   srcGUID .. "\30" .. name -> that caster's rolling mean heal
--   healAny   name -> rolling mean across every caster (the fallback)
--   casts     casterGUID -> { dest, amt, endTime, name, icon } (one cast each)
--   last      guid .. "\30" .. name -> last tick time, for learning the interval
--   detail    scratch list for the row tooltip's breakdown
-- On `util` rather than as a chunk local because this file sits ON Lua 5.1's
-- 200-local ceiling — a new local here is a load error, not a style question.
-- Every function that touches it opens with `local fc = util.fc`, so the
-- indirection is paid once per call and never inside a loop.
util.fc = {
    kind = {}, heal = {}, on = {}, amtOn = {}, amtAny = {},
    healAmt = {}, healAny = {}, healPend = {}, casts = {}, last = {}, detail = {},
}

-- Resolve the seeds into localized names. Called at login beside the CC and
-- absorb name tables, and for the same reason: an aura arrives named, not
-- numbered, and every rank of one spell answers to one name.
function util.ResolveForecast()
    local fc = util.fc
    if not GetSpellInfo then return end
    for _, grp in ipairs(SDATA.PERIODIC_SEED) do
        for _, id in ipairs(grp.ids) do
            local n = GetSpellInfo(id)
            if n and not fc.kind[n] then
                fc.kind[n] = { dot = grp.kind == "DOT", interval = grp.interval,
                               seeded = true }
            end
        end
    end
    for _, id in ipairs(SDATA.HEAL_SEED) do
        local n = GetSpellInfo(id)
        if n then fc.heal[n] = true end
    end
end

-- Rolling mean, seeded by its first sample. Weighted toward history (a crit
-- we failed to normalise, or a partial resist, should nudge the number rather
-- than become it) but light enough that a real gear change lands within a
-- fight or two.
local function Blend(old, new)
    if not old then return new end
    return old * 0.75 + new * 0.25
end

-- One periodic tick, straight off the log. `dot` says which side it is; the
-- amount is normalised out of a crit so a lucky tick does not double the
-- forecast for everyone downstream.
function util.NotePeriodic(destGUID, name, amount, crit, dot, now)
    local fc = util.fc
    if not (destGUID and name) or type(amount) ~= "number" or amount <= 0 then return end
    if crit then amount = amount / 1.5 end
    local shape = fc.kind[name]
    if not shape then
        shape = { dot = dot, interval = 3 }
        fc.kind[name] = shape
    else
        shape.dot = dot
    end
    -- Learn the interval from consecutive ticks — but only for a spell the
    -- seed table does not already know. TBC lets two casters keep the same
    -- dot on one target, and their tick streams interleave: watched naively
    -- that reads as half the real interval, which would double the forecast
    -- for the spells an arena runs into most. A seeded interval is a fact, so
    -- it is never overwritten by an observation that might be two casters.
    -- Periodics all tick on whole seconds, so the observation is rounded to
    -- one, which also absorbs the latency jitter in a raw delta.
    local key = destGUID .. "\30" .. name
    local prev = fc.last[key]
    fc.last[key] = now
    if prev and not shape.seeded then
        local dt = now - prev
        if dt >= 0.75 and dt <= 10.5 then
            local iv = math.floor(dt + 0.5)
            if iv >= 1 then shape.interval = iv end
        end
    end
    fc.amtOn[key] = amount
    fc.amtAny[name] = Blend(fc.amtAny[name], amount)
end

-- One completed direct heal. Kept per caster because THIS is the number that
-- differs by who is casting: a fresh priest's Flash Heal and a geared one's
-- are not the same heal, and the inbound-cast read is per caster.
--
-- Keyed by SPELL ID, not by name, and that is not a detail. Every rank of one
-- spell answers to one name, and TBC healers downrank constantly — a priest
-- spamming rank 2 Flash Heal for efficiency and then landing a rank 7 is two
-- wildly different numbers wearing the same label. Averaging them produced a
-- prediction that matched neither and looked, from the outside, exactly like
-- a spell-power bug.
--
-- The name is still recorded, both as the "is this spell a heal" test the
-- cast read uses and as a last-resort bucket for a cast whose id the client
-- did not hand us.
function util.NoteHeal(srcGUID, spellId, name, amount, crit, now)
    local fc = util.fc
    if not srcGUID or type(amount) ~= "number" or amount <= 0 then return end
    if name then fc.heal[name] = true end
    if crit then amount = amount / 1.5 end
    local key = srcGUID .. "\30" .. tostring(spellId or name)
    -- MULTI-TARGET casts arrive as several heal events in one breath — Chain
    -- Heal's three, Prayer of Healing's five, Circle of Healing's — each
    -- smaller than the last. Blending all of them teaches a number well below
    -- what the caster's TARGET actually receives, which is the number this
    -- forecast is about. So a burst is held and only its LARGEST sample is
    -- committed: one cast, one measurement, taken at the primary target.
    local pend = fc.healPend[key]
    if not pend then pend = {}; fc.healPend[key] = pend end
    if pend.at and (now - pend.at) < SDATA.HEAL_BURST then
        if amount > (pend.amt or 0) then pend.amt = amount end
        return
    end
    if pend.at then util.CommitHeal(key, pend.amt, pend.name) end
    pend.amt, pend.at, pend.name = amount, now, name
end

function util.CommitHeal(key, amt, name)
    local fc = util.fc
    if not amt or amt <= 0 then return end
    fc.healAmt[key] = Blend(fc.healAmt[key], amt)
    if name then fc.healAny[name] = Blend(fc.healAny[name], amt) end
end

-- Commit any burst whose breath has passed. Called when the numbers are about
-- to be READ (a cast starting), which is the only moment their freshness
-- matters — a burst nobody has flushed is committed by the next heal of the
-- same spell anyway.
function util.FlushHeals(now)
    local fc = util.fc
    for key, pend in pairs(fc.healPend) do
        if pend.at and (now - pend.at) >= SDATA.HEAL_BURST then
            util.CommitHeal(key, pend.amt, pend.name)
            pend.at = nil
        end
    end
end

-- OVERHEAL. The other half of the healing accounting, and the only one the
-- log reports directly: every heal event carries what it actually restored
-- and what spilled. Wasted healing is a fact you can only learn AFTER the
-- fact, which is exactly why it belongs on the row rather than in a meter —
-- the useful moment is the one right after it happens, while the next global
-- is still yours to spend somewhere else.
--
-- Stored as a FRACTION and a deadline rather than a running total. Nobody
-- reads a number here; what the row has to say is "that one was mostly
-- wasted", and how mostly decides how loud it says it.
-- guid -> { until_, frac }. The table is declared here with the rest of the
-- healing accounting; the two functions that use it live further down beside
-- util.Forecast, because both read settings and `DB` is not declared yet at
-- this point in the file — calling it from here resolves it as a nil global.
util.overheal = {}

-- What one tick of `name` is worth on `guid`: what it actually did to THEM if
-- we have seen it, else what it does on average to anyone. Zero when neither
-- is known — a dot we have never watched tick contributes nothing rather than
-- a guess, because a wrong number here is worse than a missing one.
function util.TickValue(guid, name)
    local fc = util.fc
    return fc.amtOn[guid .. "\30" .. name] or fc.amtAny[name] or 0
end

-- Record what the aura scan found, into the pooled per-ally list. Entry
-- tables are reused rather than rebuilt: this runs per unit on every
-- UNIT_AURA, and the whole point of the pool is that it never allocates.
function util.NotePeriodicAura(guid, name, icon, expire, duration, dot)
    local fc = util.fc
    local shape = fc.kind[name]
    if not shape or shape.dot ~= dot then return end
    local list = fc.on[guid]
    if not list then list = { n = 0 }; fc.on[guid] = list end
    local slot = list.n + 1
    if slot > SDATA.FORECAST_MAX then return end
    local e = list[slot]
    if not e then e = {}; list[slot] = e end
    e.name, e.icon, e.expire, e.duration = name, icon, expire, duration
    e.interval = shape.interval or 3
    e.dot = dot
    list.n = slot
end

-- A stand-in row for a whole CLASS, so the class grid can ask exactly the
-- questions a real row asks: does Wisdom do a warrior any good (no), does
-- Might do a mage any good (no).
function CommanderPartyFrames_BlessProbe(classKey)
    local probe = bless.probe
    wipe(probe)
    if classKey == "PET" then
        -- Every pet in the game melees and drinks from a mana bar it does not
        -- spend on your buffs, so a pet is MELEE and not a mana user.
        probe.isPet, probe.manaUser = true, nil
    else
        probe.class = classKey
        probe.manaUser = SDATA.MANA_CLASSES[classKey or ""] or nil
    end
    return probe
end

function CommanderPartyFrames_BlessClassOrder() return SDATA.BLESS_CLASS_ORDER end
function CommanderPartyFrames_BlessNone() return SDATA.BLESS_NONE end

-- Which blessings this character can put on that class at all.
function CommanderPartyFrames_BlessOptions(classKey)
    return util.BlessOptions(CommanderPartyFrames_BlessProbe(classKey), bless.optOut)
end

function CommanderPartyFrames_BlessGet(field, key)
    return util.BlessStored(field, key)
end

function CommanderPartyFrames_BlessSet(field, key, value)
    util.BlessAssign(field, key, value)
end

-- What a class row actually resolves to right now, and whether that came from
-- a stored choice or the built-in table. The grid draws the resolved icon
-- either way — a class showing nothing because you never touched it would be
-- a lie about what the board is going to do.
function CommanderPartyFrames_BlessResolve(classKey)
    local probe = CommanderPartyFrames_BlessProbe(classKey)
    local stored = util.BlessStored("BlessClass", classKey)
    if stored == SDATA.BLESS_NONE then return nil, true end
    -- Deliberately NOT util.BlessFor(probe): that would consult BlessAssign
    -- with the probe's (absent) name and could only ever miss, but reading a
    -- class cell through the player ladder is the kind of thing that becomes
    -- true by accident later. The class ladder is stored -> built-in, full stop.
    local def = bless.DefFor(stored, probe)
        or bless.DefFor(SDATA.BLESS_CLASS_DEFAULT[classKey or ""], probe)
    return def, stored ~= nil
end

-- The same question for a NAMED player: what will their row actually show?
-- The settings list needs the resolved answer, not the stored one, or a name
-- you have never touched would draw blank while the board blesses them fine.
function CommanderPartyFrames_BlessResolveFor(assignKey, classKey)
    local probe = CommanderPartyFrames_BlessProbe(classKey)
    local stored = util.BlessStored("BlessAssign", assignKey)
    if stored == SDATA.BLESS_NONE then return nil end
    local def = bless.DefFor(stored, probe)
    if def then return def end
    local byClass = util.BlessStored("BlessClass", classKey)
    if byClass == SDATA.BLESS_NONE then return nil end
    return bless.DefFor(byClass, probe)
        or bless.DefFor(SDATA.BLESS_CLASS_DEFAULT[classKey or ""], probe)
end

-- The people a per-player override could name: everyone in the group now,
-- plus everyone who already has one saved (they may be offline, and an
-- override you cannot see is an override you cannot clear).
function CommanderPartyFrames_BlessRoster()
    local list, seen = bless.roster, bless.seen
    wipe(list); wipe(seen)
    local function add(unit)
        if not (unit and UnitExists(unit)) then return end
        local name, realm = UnitName(unit)
        if not name then return end
        local key = (realm and realm ~= "") and (name .. "-" .. realm) or name
        if seen[key] then return end
        seen[key] = true
        list[#list + 1] = {
            key = key, name = name,
            class = select(2, UnitClass(unit)),
            online = true,
        }
    end
    add("player")
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do add("raid" .. i) end
    else
        for i = 1, 4 do add("party" .. i) end
    end
    local stored = CommanderPartyFramesDB and CommanderPartyFramesDB.BlessAssign
    if stored then
        for key in pairs(stored) do
            -- Pet overrides are keyed "pet:Owner" and belong to the owner's
            -- row conceptually, but they are still assignments you may want
            -- back — listed under their own readable name rather than hidden.
            if not seen[key] then
                seen[key] = true
                local pet = key:match("^pet:(.+)$")
                list[#list + 1] = {
                    key = key, name = pet and (pet .. "'s pet") or key,
                    isPet = pet and true or nil,
                    online = false,
                }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.name < b.name
    end)
    return list
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
-- Debuffs that never earn an icon, whatever the strip is set to show. The
-- ten minutes after a Bloodlust or Heroism sit on every row at once and tell
-- a healer nothing they can act on; with Show All Debuffs on they would take
-- a strip slot on the whole party for the rest of the fight.
local MUTED_IDS = {
    57724,  -- Sated (Bloodlust)
    57723,  -- Exhaustion (Heroism)
}
-- Upper bound of the Debuff Icons setting; each row pre-builds this many slots
local MAX_DISPEL_ICONS = 16

local myDispelTypes = {}   -- dispel types OUR class can remove (resolved at login)
local ccNames = {}          -- localized CC spell names -> true (resolved at login)
local importantNames = {}   -- localized name -> category (HEAL / CC / SILENCE)
local mutedNames = {}       -- localized names the strip never shows (resolved at login)

-- CommanderPartyFramesDB accessor with a fallback, so every read is nil-safe even
-- before defaults are applied.
local function DB(key, default)
    local v = CommanderPartyFramesDB and CommanderPartyFramesDB[key]
    if v == nil then return default end
    return v
end

-- ---------------------------------------------------------------------------
-- Nearby Raid (flagged off by default)
--
-- Inside a raid or a battleground the roster is forty people and the board is
-- unreadable, but the four allies who actually matter to a healer are the four
-- standing next to them. This picks exactly that: you, plus the closest N-1
-- raid members, on the same rows, with the same layers, as a party.
--
-- It is a SNAPSHOT rather than a live sort: the picked set holds still until
-- something asks it to change — the header button, the auto-refresh timer, or
-- the roster itself. Every one of those re-picks SORTS. An earlier version had
-- the timer keep people on the rows they already held and only refill what
-- emptied, on the theory that rows moving under the cursor cost you clicks;
-- what that actually produced was a board that looked frozen, because the
-- membership of "the four closest" rarely changes even while all four of them
-- are moving. Auto-refresh that does not visibly re-sort is auto-refresh that
-- appears broken, so it re-sorts.
--
-- What survives of that idea is `sticky`, and only where it is invisible: an
-- automatic pick gives whoever is already on the board a few yards of credit
-- on MEMBERSHIP, so two allies drifting either side of the cutoff do not swap
-- in and out every tick. The order they are drawn in is always pure distance.
--
-- Everything lives in one table because this file is near Lua's 200-local
-- chunk cap (see the SDATA note at the top).
-- ---------------------------------------------------------------------------
local near = {
    slots = {},     -- ordered "raidN" tokens of the current pick (never "player")
    held = {},      -- guid -> slot index, read only for the membership head start
    order = {},     -- unit token -> board position, for the fixed row order
    scratch = {},   -- per-pick candidate list, reused
    pool = {},      -- candidate records, reused (a pick allocates nothing)
    stamp = 0,      -- GetTime() of the last pick (0 = never picked)
    exact = false,  -- the last pick had real coordinates, not range bands
    since = 0,      -- auto-refresh accumulator
    dirty = true,   -- something invalidated the pick; take a new one on demand
    pending = false,-- a pick is waiting on combat to end (secure rows only)
}

-- An incumbent's head start, in yards, applied on automatic picks only. Two
-- allies drifting either side of the cutoff would otherwise trade the last
-- slot every single tick; this says a newcomer has to be meaningfully closer,
-- not marginally, before it is worth moving somebody off the board. It biases
-- WHO is on the board, never the order they are drawn in.
-- (Constants and helpers hang off `near` rather than standing as file locals
-- for the same 200-local reason the table itself does.)
near.STICKY = 5
near.FAR = 200              -- further than anything we can measure

-- How far away an ally is, in yards, and whether that number is real.
--
-- UnitPosition is the only source that gives an actual distance, and it is
-- also the one that can be taken away underneath us: the client blanks it
-- inside instanced content on some builds, which is precisely where this
-- feature is meant to live.
--
-- The fallback used to be an interact-distance ladder over CheckInteractDistance.
-- That function is PROTECTED on this client (2.5.6): every call from addon code
-- raises ADDON_ACTION_BLOCKED and returns nothing, so the ladder was already
-- ranking nothing -- it fell through to UnitInRange every time, while spamming
-- the error log from inside the picker's refresh. Do not put it back. Bands
-- would have to come from an unprotected source (a spell- or item-range check),
-- which is real work, not a one-liner.
--
-- So the fallback is UnitInRange: group members only, which is exactly who is
-- being ranked, and one rung rather than three. The board still says which of
-- the two it used, so a coarse pick never passes itself off as a measured one.
function near.Yards(unit)
    if UnitIsUnit and UnitIsUnit(unit, "player") then return 0, true end
    -- A released ghost is standing at the graveyard, not where their corpse
    -- is, and there is nothing on them to heal, buff or dispel anyway -- so a
    -- nearby board treats them as infinitely far (Ghosts Count As Far). A
    -- dead ally who has NOT released is still a body at a real distance: a
    -- Rebirth or a Redemption is a decision about exactly that body, so their
    -- yards stay honest.
    if DB("NearGhostsFar", true) and UnitIsGhost and UnitIsGhost(unit) then
        return near.FAR * 2, true
    end
    if UnitPosition then
        local py, px, _, pInst = UnitPosition("player")
        local uy, ux, _, uInst = UnitPosition(unit)
        -- Coordinates from two different instances are two different worlds;
        -- subtracting them would rank a stranger as adjacent (the same trap
        -- Commander_Orders hits between Kalimdor and the Eastern Kingdoms).
        if px and ux and pInst == uInst then
            local dx, dy = ux - px, uy - py
            return math.sqrt(dx * dx + dy * dy), true
        end
    end
    -- UnitInRange answers for group members only, which is exactly who is
    -- being ranked here. Its 40y is the last rung before "somewhere else".
    if UnitInRange then
        local inRange, checked = UnitInRange(unit)
        if checked and inRange then return 40, false end
    end
    return near.FAR, false
end

-- Exposed for the harness, which has no other way to ask the ranker a
-- question without standing up a forty-person raid
function CommanderPartyFrames_NearYards(unit) return near.Yards(unit) end

-- On only when the flag is set AND we are actually in a raid. A five-man
-- party already IS this board, so the feature has nothing to do there and
-- must not quietly reorder it.
function near.Active()
    if not DB("NearMode", false) then return false end
    return (IsInRaid and IsInRaid()) and true or false
end

-- People on the board, you included. This is what bounds the board in nearby
-- mode — Max Rows is the whole-raid control and would silently clip a pick of
-- fifteen down to six.
function near.Count()
    local n = tonumber(DB("NearCount", 5)) or 5
    if n < 2 then n = 2 elseif n > 15 then n = 15 end
    return math.floor(n)
end

function near.Candidate(i, unit, guid, yards)
    local rec = near.pool[i]
    if not rec then rec = {}; near.pool[i] = rec end
    rec.unit, rec.guid, rec.yards = unit, guid, yards
    return rec
end

-- Closest first. The tie-break is the GUID rather than the name or the raid
-- index: two allies at an identical distance must land in the same order on
-- every pick, or the board flickers between two equally correct answers.
function near.Compare(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.guid < b.guid
end

-- Re-pick the snapshot, always nearest-first. `sticky` is the automatic pick's
-- membership hysteresis (see near.STICKY); a pick you asked for by hand has
-- none, because "give me a fresh collection" should mean exactly that. Returns
-- true when the token list actually changed — the caller only has to redraw,
-- or touch secure attributes, when it did.
function near.Pick(sticky)
    near.dirty = false
    near.stamp = GetTime()
    local slots, held, scratch = near.slots, near.held, near.scratch
    local wanted = near.Count() - (DB("IncludeSelf", true) and 1 or 0)
    if wanted < 0 then wanted = 0 end

    wipe(scratch)
    local exact = true
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists(u) and not (UnitIsUnit and UnitIsUnit(u, "player")) then
                -- A disconnected ally cannot be healed, buffed or dispelled,
                -- and their last known position is wherever they dropped —
                -- so they are not a candidate for a slot that is about to be
                -- spent on somebody you can actually act on.
                local online = (UnitIsConnected == nil) or UnitIsConnected(u)
                local guid = UnitGUID and UnitGUID(u)
                if online and guid then
                    local yards, measured = near.Yards(u)
                    if not measured then exact = false end
                    local rec = near.Candidate(#scratch + 1, u, guid, yards)
                    -- Incumbents are ranked with their head start applied, so
                    -- the sort itself carries the hysteresis
                    rec.rank = yards - (sticky and held[guid] and near.STICKY or 0)
                    scratch[#scratch + 1] = rec
                end
            end
        end
    end
    near.exact = exact
    table.sort(scratch, near.Compare)
    if #scratch > wanted then
        for i = #scratch, wanted + 1, -1 do scratch[i] = nil end
    end

    -- The board IS the sorted order. Nothing is held back to preserve a row.
    local before = table.concat(slots, ",")
    wipe(slots)
    for i = 1, #scratch do slots[i] = scratch[i].unit end

    -- Recorded for the next automatic pick's head start, and nothing else
    wipe(held)
    for i = 1, #slots do
        local g = UnitGUID and UnitGUID(slots[i])
        if g then held[g] = i end
    end
    return table.concat(slots, ",") ~= before
end

-- Take a pick if one is owed. Cheap enough to sit on the roster path: it
-- short-circuits on a flag rather than re-scanning forty units per draw.
function near.Ensure()
    -- An implicit pick (a roster change, a settings change, the first draw)
    -- is the automatic kind: it carries the membership head start, unless
    -- there is no previous board for anyone to be an incumbent of.
    if near.dirty or near.stamp == 0 then near.Pick(near.stamp ~= 0) end
end

-- Invalidate without picking — the roster changed, the zone changed, or a
-- setting that decides the pick's shape did. The next draw takes the new one.
function near.Invalidate()
    near.dirty = true
end

-- The pet token that follows a picked ally.
function near.PetOf(unit)
    return "raidpet" .. string.sub(unit, 5)
end

-- The board's row bound: nearby mode is sized by its own count, everything
-- else by Max Rows.
function near.Max()
    return near.Active() and near.Count() or DB("MaxRows", 6)
end

-- The row alpha Range Fade dims an out-of-range ally to: the Strength
-- setting is how much is taken AWAY, so 0.6 leaves the 0.4 the fade always
-- used. Clamped so a hand-edited value can neither hide a row outright nor
-- turn the fade into a no-op.
function util.RangeFadeAlpha()
    local s = tonumber(DB("RangeFadeStrength", 0.6)) or 0.6
    if s < 0.1 then s = 0.1 elseif s > 0.9 then s = 0.9 end
    return 1 - s
end

-- Which rows get the power strip: OFF, MANA (the old board — mana users
-- only), or ALL (every class, every resource). Asked in four places, and one
-- of them is the layout pass, so it is a function rather than four copies of
-- the same legacy fallback.
--
-- The fallback IS the migration: PowerBar is absent for anyone upgrading, and
-- their old ShowManaBar answers the question they actually gave — off stays
-- off, on becomes the mana-only board they already had. New installs get ALL
-- from the defaults table, so nobody's board changes under them.
function util.PowerMode()
    local m = CommanderPartyFramesDB and CommanderPartyFramesDB.PowerBar
    if m == "OFF" or m == "MANA" or m == "ALL" then return m end
    if CommanderPartyFramesDB and CommanderPartyFramesDB.ShowManaBar == false then return "OFF" end
    return "MANA"
end

-- Does THIS row take the strip? Mode plus the row's own resource. Compact
-- personal rows (My Shields, the elemental) never do: they are half height
-- and the slot is spoken for.
function util.PowerOn(r)
    local m = util.PowerMode()
    if m == "OFF" or not r or not r.power then return false end
    if m == "MANA" then return r.powerType == 0 end
    return true
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
util.buffMine = {}                    -- ...and who cast it (blessings care)

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

-- ---------------------------------------------------------------------------
-- The blessing family's own questions. All three are cheap and asked per row
-- per frame, so they stay lookups rather than scans.
-- ---------------------------------------------------------------------------

-- Is the family collapsed into one assigned slot? Paladin board only: on every
-- other layer there is no family to collapse and the setting means nothing.
function util.BlessCombined()
    return layer == "BLESS" and DB("BlessCombine", true) or false
end

-- Does this def only count when WE cast it? Blessings do (two paladins can
-- each hold a different one on the same target, so another paladin's is not
-- yours and never satisfies your slot); everything else in the registry is
-- deliberately any-caster, because another druid's Mark really does stop you
-- recasting. The setting exists to turn the strict read off, not to turn a
-- wrong one on — leave it alone unless you are the only paladin, ever.
function util.BuffMineOnly(def)
    if not (def and def.mine) then return false end
    return DB("BlessMineOnly", true) and true or false
end

-- The blessings this character can actually put on THIS row, in registry
-- order. Trained is the hard gate; `targets` drops the ones that would do
-- nothing (Wisdom on a rogue, Might on a mage). In combined mode the per-buff
-- track toggle deliberately does NOT filter this: it decides which blessings
-- earn a SLOT, and there is only one slot now, so using it to shorten a
-- dropdown would just hide the blessing you reached for.
function util.BlessOptions(r, out)
    out = out or {}
    wipe(out)
    for _, def in ipairs(SDATA.CLASS_BUFFS.BLESS) do
        if def.known and (not r or util.BuffApplies(def, r)) then
            out[#out + 1] = def
        end
    end
    return out
end

-- The key a per-player override is stored under. Name, plus realm when the
-- ally is from another one — the same identity the client itself shows, and
-- stable across sessions in a way a GUID would be to read but not to edit.
function util.BlessAssignKey(r)
    if not r then return nil end
    if r.isPet then
        -- A pet's name is whatever its owner named it, which is stable enough
        -- to key on, but its OWNER is what you actually think about. Keyed by
        -- owner so "Grimtusk's pet" survives a Call Pet of a different beast.
        return r.petOwnerName and ("pet:" .. r.petOwnerName) or nil
    end
    return r.fullName
end

-- Which class bucket answers for this row. Pets have no class of their own,
-- and borrowing the owner's would put Kings on a warlock's felguard because
-- the warlock wants it — so they get a bucket of their own.
function util.BlessClassKey(r)
    if not r then return nil end
    if r.isPet then return "PET" end
    return r.class
end

-- Read a stored assignment (nil = nothing stored). Split out because the
-- settings grid needs the RAW answer — "is there an override here" is a
-- different question from "what will this row be told to cast".
function util.BlessStored(field, key)
    if not key then return nil end
    local tbl = CommanderPartyFramesDB and CommanderPartyFramesDB[field]
    return tbl and tbl[key] or nil
end

function util.BlessSetStored(field, key, value)
    if not key then return end
    local tbl = CommanderPartyFramesDB and CommanderPartyFramesDB[field]
    if not tbl then
        if not CommanderPartyFramesDB then return end
        tbl = {}
        CommanderPartyFramesDB[field] = tbl
    end
    tbl[key] = value
end

-- Resolve a blessing key to its def, but only if this character can cast it
-- and it would do the target any good. A stored assignment that fails either
-- test is not an error — you respecced out of Sanctuary, or the warrior you
-- had Wisdom on left and a mage took the slot — so it falls through to the
-- next step of the ladder rather than leaving the row blank.
function bless.DefFor(key, r)
    if not key or key == SDATA.BLESS_NONE then return nil end
    for _, def in ipairs(SDATA.CLASS_BUFFS.BLESS) do
        if def.key == key then
            if not def.known then return nil end
            if r and not util.BuffApplies(def, r) then return nil end
            return def
        end
    end
    return nil
end

-- What should I be casting on this ally? Returns the def and where the answer
-- came from ("player" / "class" / "default" / "any"), or nil when the answer
-- is genuinely "nothing" — either an explicit NONE, or a character with no
-- blessing trained at all.
function util.BlessFor(r)
    if not r then return nil end
    local pk = util.BlessAssignKey(r)
    local stored = util.BlessStored("BlessAssign", pk)
    if stored == SDATA.BLESS_NONE then return nil, "player" end
    local def = bless.DefFor(stored, r)
    if def then return def, "player" end

    local ck = util.BlessClassKey(r)
    local byClass = util.BlessStored("BlessClass", ck)
    if byClass == SDATA.BLESS_NONE then return nil, "class" end
    def = bless.DefFor(byClass, r)
    if def then return def, "class" end

    def = bless.DefFor(SDATA.BLESS_CLASS_DEFAULT[ck or ""], r)
    if def then return def, "default" end

    -- Last resort: anything at all this paladin can put on them. A level-20
    -- paladin with only Might trained still gets a working board.
    for _, d in ipairs(SDATA.CLASS_BUFFS.BLESS) do
        if d.known and util.BuffApplies(d, r) then return d, "any" end
    end
    return nil, "none"
end

-- ---------------------------------------------------------------------------
-- The row's assignment menu. Right-click the blessing slot for the list, left
-- for the same list — both buttons open it, because a slot that answers one
-- click and ignores the other is a slot you click twice.
--
-- Live only out of combat (see the note where row.blessBtn is built), and only
-- while the family is actually collapsed into one slot: with six separate
-- slots there is no assignment to make.
-- ---------------------------------------------------------------------------
function util.BlessMenuLive()
    if not util.BlessCombined() then return false end
    if not DB("BlessRowMenu", true) then return false end
    return not (InCombatLockdown and InCombatLockdown())
end

-- Where the assignment lands. The per-player row writes an override; the class
-- row writes the class default; both clear back to "inherit" when you pick the
-- entry they already resolve to, so the DB never fills with rows that say
-- exactly what the fallback already said.
function util.BlessAssign(field, key, value)
    if not key then return end
    util.BlessSetStored(field, key, value)
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
end

function bless.MenuInit(_, level)
    local btn = bless.menuBtn
    if not btn then return end
    level = level or 1
    local who = btn.who
    local pk, ck = btn.assignKey, btn.classKey
    local stored = util.BlessStored("BlessAssign", pk)
    local info

    info = UIDropDownMenu_CreateInfo()
    info.text = btn.rowName and ("Bless " .. btn.rowName) or "Blessing"
    info.isTitle, info.notCheckable = true, true
    UIDropDownMenu_AddButton(info, level)

    for _, def in ipairs(util.BlessOptions(who, bless.optScratch)) do
        info = UIDropDownMenu_CreateInfo()
        info.text, info.icon = def.label, def.icon
        info.checked = (stored == def.key)
        info.func = function()
            util.BlessAssign("BlessAssign", pk, def.key)
            CloseDropDownMenus()
        end
        UIDropDownMenu_AddButton(info, level)
    end

    info = UIDropDownMenu_CreateInfo()
    info.text, info.notCheckable = "Don't bless them", true
    info.checked = (stored == SDATA.BLESS_NONE)
    info.func = function()
        util.BlessAssign("BlessAssign", pk, SDATA.BLESS_NONE)
        CloseDropDownMenus()
    end
    UIDropDownMenu_AddButton(info, level)

    -- Clearing is a separate verb from picking, and it has to say what you
    -- fall back TO — otherwise "Use the class default" is a promise with no
    -- content and you clear it just to find out.
    local fallback = util.BlessStored("BlessClass", ck)
        or SDATA.BLESS_CLASS_DEFAULT[ck or ""]
    local fbLabel
    for _, def in ipairs(SDATA.CLASS_BUFFS.BLESS) do
        if def.key == fallback then fbLabel = def.label end
    end
    info = UIDropDownMenu_CreateInfo()
    info.text = fbLabel and (ck == "PET" and ("Follow pets (" .. fbLabel .. ")")
            or ("Follow " .. (ck or "class") .. " (" .. fbLabel .. ")"))
        or "Follow the class default"
    info.notCheckable = true
    info.disabled = (stored == nil)
    info.func = function()
        util.BlessAssign("BlessAssign", pk, nil)
        CloseDropDownMenus()
    end
    UIDropDownMenu_AddButton(info, level)
end

function util.BlessSlotClick(self)
    if not util.BlessMenuLive() then return end
    if not self.assignKey then return end
    bless.menuBtn = self
    if not bless.menu then
        bless.menu = CreateFrame("Frame", "CommanderPartyFramesBlessMenu", UIParent,
            "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(bless.menu, bless.MenuInit, "MENU")
    ToggleDropDownMenu(1, nil, bless.menu, self, 0, 0)
end

function util.BlessSlotTooltip(self)
    local want, have = self.blessWant, self.blessHave
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.rowName or "Blessing", 1, 1, 1)
    if want then
        GameTooltip:AddLine("Assigned: " .. want.label, 1, 0.82, 0.25)
    else
        GameTooltip:AddLine("Assigned: nothing — leave them alone", 0.7, 0.7, 0.7)
    end
    -- WHERE the assignment came from, because "why is this Kings" is the first
    -- question the slot provokes and the answer is three tables deep.
    local why = self.blessWhy
    if why == "player" then
        GameTooltip:AddLine("Set on them by name.", 0.6, 0.6, 0.6, true)
    elseif why == "class" then
        GameTooltip:AddLine("From your class default.", 0.6, 0.6, 0.6, true)
    elseif why == "default" then
        GameTooltip:AddLine("From the built-in class default.", 0.6, 0.6, 0.6, true)
    elseif why == "any" then
        GameTooltip:AddLine("Nothing assigned — this is the only blessing you have for them.",
            0.6, 0.6, 0.6, true)
    end
    GameTooltip:AddLine(" ")
    if have and want and have.key == want.key then
        GameTooltip:AddLine("Yours is up.", 0.4, 0.9, 0.4)
    elseif have then
        -- The case this whole rework exists for: covered, but not with what
        -- you decided, so the slot is dark and this says exactly why.
        GameTooltip:AddLine("They are carrying your " .. have.label .. " instead.", 1, 0.65, 0.3, true)
        GameTooltip:AddLine("The slot reads dark because that is not the assignment.",
            0.6, 0.6, 0.6, true)
    else
        GameTooltip:AddLine("None of your blessings are on them.", 1, 0.4, 0.4)
    end
    if DB("BlessMineOnly", true) then
        GameTooltip:AddLine("Only blessings YOU cast count here.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:AddLine(" ")
    if util.BlessMenuLive() then
        GameTooltip:AddLine("Click to reassign.", 0.6, 0.6, 0.6)
    elseif util.BlessCombined() and DB("BlessRowMenu", true) then
        GameTooltip:AddLine("Reassign out of combat.", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

-- Rebuild the tracked subset and the layout signature. Called from Apply, so
-- a toggle in the settings panel re-shapes every row on the next draw rather
-- than on the next reload.
function util.RefreshBuffs()
    wipe(SDATA.BUFF_ACTIVE)
    local sig = {}
    -- Combined mode spends ONE slot on the whole family, whatever is tracked
    -- inside it: which blessing that slot shows is a per-row assignment, not a
    -- layout question, so the strip's shape stops depending on it entirely.
    -- Anything in the book that is not a blessing still gets its own slot —
    -- there is nothing like that today, and the day there is, it works.
    local combined = util.BlessCombined()
    local anyBlessing = false
    for _, def in ipairs(SDATA.BUFF_LIST) do
        -- A spell you have not trained earns no slot. A level-20 mage has no
        -- Dampen Magic, and a permanent dark reminder of a spell that is not
        -- in the book is the emptiest pixel on the board.
        if combined and def.oneOf == SDATA.BLESS_FAMILY then
            if def.known then anyBlessing = true end
        elseif def.known and util.BuffTracked(def) then
            SDATA.BUFF_ACTIVE[#SDATA.BUFF_ACTIVE + 1] = def
            sig[#sig + 1] = def.key
        end
    end
    SDATA.BLESS_SLOT.known = anyBlessing
    if anyBlessing then
        table.insert(SDATA.BUFF_ACTIVE, 1, SDATA.BLESS_SLOT)
        table.insert(sig, 1, SDATA.BLESS_SLOT.key)
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
-- Folded into SDATA (2026-09-12) to buy this file room under Lua's 200-local
-- ceiling: fifteen constants were fifteen chunk locals, and the file had 199.
-- ---------------------------------------------------------------------------
SDATA.ROW_H = 22
SDATA.ROW_GAP = 2
SDATA.BAR_H = 12
SDATA.HEALTH_H = 6
SDATA.WS_H = 3
SDATA.STRIPE_W = 3
SDATA.ICON_SIZE = 18
SDATA.SMALL_ICON = 15   -- INT layer: two status icons share the left slot
SDATA.COMBAT_MARK = 13  -- size of the crossed-swords combat mark
SDATA.NAME_W = 60
SDATA.SHORT_NAME_W = 44
SDATA.PAD = 6
SDATA.HEADER_H = 15
SDATA.DRAW_THROTTLE = 0.1
SDATA.UPTIME_SAMPLE = 1.0

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
-- guid -> ordered list of live battleground marks (see SDATA.BG_BUFFS), best
-- first. Rebuilt per reliable scan under the same contract as everything else
-- on this board: an ally the client cannot see reports no auras at all, and
-- reading that as "they dropped the flag" would blank the carrier every time
-- they ran past the tunnel. On `util` for the 200-local reason, like the rest.
util.bgState = {}
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
-- On SDATA rather than a file local, next to MELEE_CLASSES and for the same
-- reason: the settings page asks the same question of a class with no unit
-- behind it, and that call site sits above this line.
SDATA.MANA_CLASSES = {
    MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true,
    SHAMAN = true, PALADIN = true, HUNTER = true,
}
local MANA_CLASSES = SDATA.MANA_CLASSES
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
util.prevRollLate = {}    -- guid -> roll was already late last tick (roll-alert edge)
local rowFlash = {}       -- rowIndex -> GetTime() the flash ends

local rowPool = {}
local personalPool = {}   -- always-insecure rows for the elemental / My Shields
-- The two ticker accumulators used to be file locals; they live on the ticker
-- frame itself now (nothing else ever read them) because this chunk sits on
-- Lua's 200-local ceiling and a new feature needs the slots more than they do.
local testUntil = 0       -- test board lives until this GetTime()
local targeters = {}      -- [guid] = enemy NPCs currently targeting that unit
local nextTargeterScan = 0
local securePool          -- true if rows were created as secure unit buttons
local secureTokens = {}   -- rowIndex -> raw unit token (secure mode)
local secureDirty = false -- secure layout needs a rebuild once out of combat
local uptime              -- session table from Commander.RestoreSession

local root = CreateFrame("Frame", "CommanderPartyFramesFrame", UIParent)
root:SetPoint("LEFT", UIParent, "LEFT", 14, 40)
root:SetSize(214, SDATA.ROW_H)
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

-- Are we in a battleground? The battleground marks reserve their slots from
-- THIS rather than from the setting alone, which is the one place they break
-- the rule the combat mark states so carefully. The reason they may: those
-- auras cannot exist outside a battleground, so a slot held open in an arena
-- or a raid is width the health bar never gets back for a mark that can never
-- light. Zoning is the only thing that flips it, and zoning is out of combat,
-- so the relayout it triggers can never land mid-fight.
--
-- Guarded in two statements rather than the file's usual `Api and Api()`,
-- because `and` yields ONE value and the answer wanted here is the second.
function util.InBattleground()
    if not IsInInstance then return false end
    local _, kind = IsInInstance()
    return kind == "pvp"
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
-- The battleground marks' names, read out of the client's own spell data.
-- Unlike the ally-buff book this has nothing to do with the player's class or
-- spellbook — nobody LEARNS Berserking off the ground — so it resolves once
-- and is the same table on every board. Names, because that is what an aura
-- list gives us and what survives a rank; the id is only the key we look the
-- name up with.
function util.ResolveBGBook()
    wipe(SDATA.BG_BY_NAME)
    if not GetSpellInfo then return end
    for _, def in ipairs(SDATA.BG_BUFFS) do
        local n, _, icon = GetSpellInfo(def.id)
        if n then
            SDATA.BG_BY_NAME[n] = def
            -- The client's own art wins over the path written above, which is
            -- there so a mark still draws if the spell data ever goes quiet
            if icon then def.icon = icon end
        end
    end
end

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
    -- Mending's localized name and trained state, cached for the tracker.
    -- Every event it follows arrives from the combat log as a name and
    -- nothing else, and all three of its spell IDs (the cast, the aura it
    -- places, the heal it fires) share that one name — which is the whole
    -- reason a name is the right key here rather than an ID table.
    -- The book's low-health hot, if it named one. Resolved here rather than
    -- looked up per row per draw, and from the whole BOOK rather than from
    -- the tracked slots: whether you have given Renew a slot on the strip is
    -- a display choice, and it must not change whether the board can tell you
    -- that a dying ally has nothing rolling on them.
    util.lowHotDef = nil
    for _, def in ipairs(SDATA.STRIP_BOOKS[layer or ""] or {}) do
        if def.lowHot and def.known then util.lowHotDef = def end
    end
    util.pomName, util.pomKnown, util.pomDef = nil, false, nil
    if layer == "PWS" then
        for _, def in ipairs(SDATA.PRIEST_HOTS) do
            if def.key == "POM" then
                util.pomName = GetSpellInfo(def.baseId)
                util.pomKnown = def.known and util.pomName and true or false
                util.pomDef = def
            end
        end
    end
    -- A priest who cannot cast it cannot lose it. Respeccing or relogging
    -- into a class with no Mending must not leave a session in flight.
    if not util.pomKnown then util.PoMReset() end

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
    return SDATA.STRIPE_W + util.HeaderInset() + (cw > 0 and (cw + 5) or 0)
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
                    b:SetPoint("TOPLEFT", root, "TOPLEFT",
                        SDATA.STRIPE_W + util.HeaderInset() - 1,
                        -util.HeaderY(b:GetHeight() or 13))
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

    -- The mage utility cluster is OFF by default. Conjure, Consume, Mana Gem
    -- and Portals are all things you do BETWEEN games; on the banner they sat
    -- in front of the readout and pushed the segments that matter during one
    -- toward the truncation edge. Four buttons of sit-down convenience is a
    -- bad trade for that, so they are opt-in as a group and the two per-button
    -- flags below stay as filters within it. Bandage is not in the group: it
    -- is the one item you use mid-fight, and its Recently Bandaged lockout is
    -- shown nowhere else.
    local utilOn = DB("MageUtilityButtons", false) and true or false
    conjureBtn.wanted = utilOn
    consumeBtn.wanted = utilOn

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
        gemBtn.wanted = utilOn and DB("ShowGemButton", true)
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
        util.portalBtn.wanted = utilOn and DB("ShowPortalButton", true)
            and util.portalKnown or false
        if not util.portalKnown then util.portalPop:Hide() end
    end
    util.Layout()

end

-- ---------------------------------------------------------------------------
-- Banner switchers: a segment you can click for a popout of secure cast
-- buttons (the mage's armors, the paladin's auras and seals).
--
-- Every piece of this is shaped by one constraint: the popout carries
-- PROTECTED children, so its anchor family is protected too. That is why the
-- popout is anchored once to root — a Frame — rather than to the banner
-- texture it visually belongs under, and why it is moved by rewriting that
-- offset out of combat instead of re-anchoring at click time. Re-anchoring at
-- click time is what threw in the field.
-- ---------------------------------------------------------------------------
util.switchers = {}     -- the active layer's, in banner order

function util.EnsureSwitchers()
    local book = SDATA.SWITCHERS[layer or ""]
    if not book or #util.switchers > 0 then return end
    for _, def in ipairs(book) do
        local sw = { def = def, buttons = {} }
        sw.pop = CreateFrame("Frame", nil, UIParent)
        sw.pop:SetFrameStrata("DIALOG")
        sw.pop:SetSize(24, 24)
        sw.pop:SetPoint("TOPLEFT", root, "TOPLEFT", SDATA.STRIPE_W + 1, -(util.HeaderH() + 3))
        local bg = sw.pop:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(sw.pop)
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0, 0, 0, 0.75)
        sw.pop:Hide()
        util.switchers[#util.switchers + 1] = sw
    end
end

-- One secure cast button per line of this kind the character has trained. A
-- line whose superseding line is known stays out (Frost Armor once you have
-- Ice), which is the only reason `known` is gathered before the second pass.
function util.BindSwitcher(sw)
    if not (sw.pop and GetSpellInfo) then return end
    local known, shown = {}, 0
    for _, line in ipairs(sw.def.lines) do
        for _, id in ipairs(line.ids) do
            local n = GetSpellInfo(id)
            if (n and knownSpells[n]) or (IsSpellKnown and IsSpellKnown(id)) then
                known[line.key] = id
                break
            end
        end
    end
    for _, line in ipairs(sw.def.lines) do
        local bestId = known[line.key]
        if bestId and not (line.supersededBy and known[line.supersededBy]) then
            shown = shown + 1
            local b = sw.buttons[shown]
            if not b then
                b = CreateFrame("Button",
                    "CommanderPartyFrames" .. sw.def.key .. "Btn" .. shown,
                    sw.pop, "SecureActionButtonTemplate")
                b:SetSize(18, 18)
                b:SetPoint("LEFT", sw.pop, "LEFT", 3 + (shown - 1) * 21, 0)
                b:RegisterForClicks("AnyDown", "AnyUp")
                b.icon = b:CreateTexture(nil, "ARTWORK")
                b.icon:SetAllPoints(b)
                b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                util.StyleIcon(b.icon)
                local hl = b:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(b)
                hl:SetTexture("Interface\\Buttons\\WHITE8X8")
                hl:SetVertexColor(1, 1, 1, 0.25)
                b:SetScript("PostClick", function() SafeSetShown(sw.pop, false) end)
                sw.buttons[shown] = b
            end
            local name, _, icon = GetSpellInfo(bestId)
            b:SetAttribute("type", "spell")
            b:SetAttribute("spell", name)
            b.icon:SetTexture(icon)
            b:Show()
        end
    end
    for i = shown + 1, #sw.buttons do sw.buttons[i]:Hide() end
    sw.known = shown
    sw.pop:SetSize(math.max(shown, 1) * 21 + 3, 24)
end

function util.BindSwitchers()
    for _, sw in ipairs(util.switchers) do util.BindSwitcher(sw) end
end

-- Put each switcher's toggle over its segment and its popout under it. Called
-- per paint, after TruncSegs has decided where the segments landed; the
-- protected move only happens when the offset actually changes and only out
-- of combat, so the common case is a number compare.
--
-- A switcher with nothing to offer (one aura trained, or a truncated banner
-- that dropped its segment) gets no toggle: a click target over an icon that
-- opens an empty box is worse than no click target.
function util.PlaceSwitchers(segs)
    segs = segs or root.hdrSegs
    if not segs then return end
    for _, sw in ipairs(util.switchers) do
        local seg = segs[sw.def.seg]
        local live = seg and seg.icon:IsShown() and (sw.known or 0) > 1
        if live and not sw.btn then
            sw.btn = CreateFrame("Button", nil, root)
            sw.btn:SetSize(16, 16)
            sw.btn:SetPoint("CENTER", seg.icon, "CENTER", 0, 0)
            sw.btn:SetScript("OnClick", function()
                SafeSetShown(sw.pop, not sw.pop:IsShown())
            end)
            sw.btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
                GameTooltip:SetText(sw.def.label)
                GameTooltip:AddLine("Click to switch", 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end)
            sw.btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        if sw.btn then sw.btn:SetShown(live and true or false) end
        if not live then
            SafeSetShown(sw.pop, false)
        elseif sw._x ~= seg._x and seg._x and not InCombat() then
            -- Its own record of where it was last put, never the segment's:
            -- a deferred move must not leave the segment (a texture, free to
            -- move in combat) reported as placed when it is not.
            sw._x = seg._x
            sw.pop:ClearAllPoints()
            local ih = seg.icon:GetHeight() or util.HeaderIcon()
            sw.pop:SetPoint("TOPLEFT", root, "TOPLEFT", seg._x,
                -(util.HeaderY(ih) + ih + 3))
        end
    end
end

function util.HideSwitchers()
    for _, sw in ipairs(util.switchers) do
        if sw.btn then sw.btn:Hide() end
        if sw.pop then SafeSetShown(sw.pop, false) end
    end
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
    local scaled = { mageUtil, util.portalPop }
    for _, sw in ipairs(util.switchers) do scaled[#scaled + 1] = sw.pop end
    for _, f in ipairs(scaled) do
        if f and (f:GetScale() or 1) ~= s then f:SetScale(s) end
    end
    -- Stacking order is the other thing a child got free. Above the board's
    -- rows, below the HUD chrome's drag overlay (root + 20), so a banner
    -- button never steals the drag handle while the frame is unlocked.
    local want = (root:GetFrameLevel() or 1) + 5
    if (mageUtil:GetFrameLevel() or 0) ~= want then mageUtil:SetFrameLevel(want) end
end

-- ---------------------------------------------------------------------------
-- Header presentation
--
-- The banner was a fifteen-pixel strip of twelve-pixel icons in one font at
-- one size, which is the right answer for exactly one monitor. Everything it
-- draws now takes its measurements from here instead, and every default below
-- is the number that used to be hard-coded, so a board that never opens the
-- section is pixel-for-pixel the board it always was.
--
-- The faces are the four the CLIENT ships rather than an art path that can
-- move across patches -- the same reason every glyph on this header is drawn
-- from quads instead of loaded.
-- ---------------------------------------------------------------------------
SDATA.HEADER_FONTS = {
    DEFAULT = "Fonts\\FRIZQT__.TTF",
    NARROW  = "Fonts\\ARIALN.TTF",
    RUNE    = "Fonts\\SKURRI.TTF",
    ROMAN   = "Fonts\\MORPHEUS.TTF",
}
SDATA.HEADER_OUTLINES = { NONE = "", OUTLINE = "OUTLINE", THICK = "THICKOUTLINE" }
-- Panel tints, already mixed down to backdrop weight: this sits UNDER a
-- readout whose whole job is to be read, so a saturated panel is a worse
-- panel. CLASS is resolved per character in util.HeaderTint.
SDATA.HEADER_TINTS = {
    BLACK    = { 0, 0, 0 },
    CHARCOAL = { 0.13, 0.13, 0.14 },
    SLATE    = { 0.09, 0.13, 0.21 },
    BLOOD    = { 0.19, 0.05, 0.06 },
    FOREST   = { 0.06, 0.14, 0.09 },
}
SDATA.HEADER_CHROME = 12    -- the drawn size of every button on the right

function util.HeaderH()
    return math.max(8, tonumber(DB("HeaderHeight", SDATA.HEADER_H)) or SDATA.HEADER_H)
end

function util.HeaderIcon()
    return math.max(6, tonumber(DB("HeaderIconSize", 12)) or 12)
end

function util.HeaderGap()
    return math.max(0, tonumber(DB("HeaderSegmentGap", 8)) or 8)
end

function util.HeaderInset()
    return math.max(0, tonumber(DB("HeaderInset", 4)) or 4)
end

function util.ChromeScale()
    local v = tonumber(DB("HeaderChromeScale", 1)) or 1
    if v < 0.5 then v = 0.5 elseif v > 2.5 then v = 2.5 end
    return v
end

-- One slot of the right-hand rank, in the BOARD's pixels rather than the
-- button's own: every caller measures against root, and a scaled button's
-- own coordinates are not root's (see util.ChromeStyle).
function util.ChromeStep()
    return SDATA.HEADER_CHROME * util.ChromeScale() + 3
end

-- Centre something of height h in the strip, as the NEGATIVE y offset from
-- the board's top edge that every anchor here is written as. Clamped at zero
-- so a strip shorter than its contents hangs them from the top rather than
-- pushing them up off the board.
function util.HeaderY(h)
    local y = (util.HeaderH() - h) / 2
    return y > 0 and y or 0
end

function util.HeaderTint()
    local key = DB("HeaderBackdropTint", "BLACK")
    if key == "CLASS" then
        local _, class = UnitClass("player")
        local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        -- A class colour is chosen to be read AGAINST, not read THROUGH, so
        -- it goes on the panel at a third strength: enough to say whose board
        -- this is, nowhere near enough to fight the readout on top of it.
        if cc then return cc.r * 0.35, cc.g * 0.35, cc.b * 0.35 end
        return 0, 0, 0
    end
    local t = SDATA.HEADER_TINTS[key] or SDATA.HEADER_TINTS.BLACK
    return t[1], t[2], t[3]
end

function util.HeaderAlpha()
    local a = tonumber(DB("HeaderBackdropAlpha", 0.55)) or 0.55
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    return a
end

-- Face, size and outline for everything the banner writes.
function util.HeaderFont()
    local path = SDATA.HEADER_FONTS[DB("HeaderFont", "DEFAULT")]
        or SDATA.HEADER_FONTS.DEFAULT
    local size = math.max(6, tonumber(DB("HeaderFontSize", 10)) or 10)
    return path, size, SDATA.HEADER_OUTLINES[DB("HeaderFontOutline", "NONE")] or ""
end

-- The hairline along the banner's bottom edge: the alternative to a panel for
-- anyone who wants the strip separated from the rows without a slab of black
-- over the world. Same tint as the panel, lifted and opened up, because a
-- rule drawn in the panel's own colour against no panel is invisible.
function util.HeaderRule()
    if not root.headerRule then
        root.headerRule = root:CreateTexture(nil, "BACKGROUND", nil, 0)
        root.headerRule:SetTexture("Interface\\Buttons\\WHITE8X8")
        root.headerRule:SetHeight(1)
        util.StyleHeaderRule()
    end
    return root.headerRule
end

function util.StyleHeaderRule()
    local rule = root.headerRule
    if not rule then return end
    local r, g, b = util.HeaderTint()
    local a = util.HeaderAlpha() + 0.25
    rule:ClearAllPoints()
    rule:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -util.HeaderH())
    rule:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -util.HeaderH())
    rule:SetVertexColor(math.min(1, r + 0.35), math.min(1, g + 0.35),
        math.min(1, b + 0.35), a > 1 and 1 or a)
end

-- Scale and place one button on the right-hand rank. Each remembers what it
-- was last given rather than trusting a shared cache, so a button built after
-- the last settings change still gets styled on its first draw -- and this
-- runs at the draw rate, so the three fields are compared instead of a
-- formatted signature being built and thrown away ten times a second.
--
-- The division is the whole reason this is a function: SetPoint offsets are
-- read in the anchored frame's OWN coordinates, so a button at scale 2 asked
-- for -6 lands twelve of root's pixels away. Everything the caller passes is
-- in root's pixels, and the scale is divided back out here once.
function util.ChromeStyle(btn, slot)
    if not btn then return end
    local cs = util.ChromeScale()
    local y = util.HeaderY(SDATA.HEADER_CHROME * cs)
    if btn._hdrCS == cs and btn._hdrY == y and btn._hdrSlot == slot then return end
    btn._hdrCS, btn._hdrY, btn._hdrSlot = cs, y, slot
    btn:SetScale(cs)
    btn:ClearAllPoints()
    btn:SetPoint("TOPRIGHT", root, "TOPRIGHT",
        (-(SDATA.PAD - 3) - slot * util.ChromeStep()) / cs, -y / cs)
end

-- Push the presentation onto everything already built. Called from Apply,
-- because every piece of this header is constructed once and a settings
-- change would otherwise only reach a board nobody has drawn yet.
--
-- Nothing touched here is protected: the segments are textures and font
-- strings, and the three chrome buttons are plain Buttons parented to root
-- (they re-style themselves on the next draw, so they are not in this pass).
-- The popouts ARE protected, which is why they are the one thing that waits
-- for combat to drop.
function util.RestyleHeader()
    local sz, gap = util.HeaderIcon(), util.HeaderGap()
    local path, fsize, flags = util.HeaderFont()
    local segs = root.hdrSegs
    if segs then
        for i = 1, #segs do
            local seg = segs[i]
            seg.icon:SetSize(sz, sz)
            if path then seg.text:SetFont(path, fsize, flags) end
            if i > 1 then
                seg.icon:ClearAllPoints()
                seg.icon:SetPoint("LEFT", segs[i - 1].text, "RIGHT", gap, 0)
            end
        end
        -- PlaceSegs caches where it put the first one; both halves of that
        -- cache describe a layout that no longer exists.
        root._segX, root._segY = nil, nil
    end
    if root.headerBG then
        local r, g, b = util.HeaderTint()
        root.headerBG:SetHeight(util.HeaderH())
        root.headerBG:SetVertexColor(r, g, b, util.HeaderAlpha())
    end
    util.StyleHeaderRule()
    if not InCombat() then
        if util.portalPop then
            util.portalPop:ClearAllPoints()
            util.portalPop:SetPoint("TOPRIGHT", root, "TOPRIGHT",
                -(SDATA.PAD - 2), -(util.HeaderH() + 3))
        end
        -- Each switcher re-places itself against its own segment on the next
        -- draw; forgetting where it was is how that is asked for.
        for i = 1, #util.switchers do util.switchers[i]._x = nil end
    end
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
    local sz, gap = util.HeaderIcon(), util.HeaderGap()
    local path, fsize, flags = util.HeaderFont()
    for i = #segs + 1, want do
        local icon = root:CreateTexture(nil, "OVERLAY")
        icon:SetSize(sz, sz)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local text = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if path then text:SetFont(path, fsize, flags) end
        text:SetJustifyH("LEFT")
        if i > 1 then
            icon:SetPoint("LEFT", segs[i - 1].text, "RIGHT", gap, 0)
        else
            -- PlaceSegs owns the first segment's x and y and only re-anchors
            -- it when the cluster width or the strip's height changes, so a
            -- pool built after it last ran has to start from the offsets it
            -- settled on rather than from the defaults.
            icon:SetPoint("TOPLEFT", root, "TOPLEFT",
                root._segX or (SDATA.STRIPE_W + util.HeaderInset()),
                -(root._segY or util.HeaderY(sz)))
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
    local segY = util.HeaderY(util.HeaderIcon())
    if root._segX ~= segX or root._segY ~= segY then
        root._segX, root._segY = segX, segY
        local segs = util.EnsureSegs()
        segs[1].icon:ClearAllPoints()
        segs[1].icon:SetPoint("TOPLEFT", root, "TOPLEFT", segX, -segY)
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
    return s
end

-- The right-aligned Commander chrome is a hard wall, and the cluster shares
-- the left block, so a segment that would run under the gear is dropped along
-- with everything after it — a truncated banner beats an overlapping one.
-- Layers fill segments most-urgent-first, so what survives is what matters.
function util.TruncSegs(segX)
    local segs = root.hdrSegs
    if not segs then return end
    local chromeW, step = 0, util.ChromeStep()
    if blizz and blizz.btn and blizz.btn:IsShown() then chromeW = chromeW + step end
    if settingsBtn and settingsBtn:IsShown() then chromeW = chromeW + step end
    if near.btn and near.btn:IsShown() then chromeW = chromeW + step end
    local limit = FrameWidth() - (SDATA.PAD - 3) - chromeW
    local segW, segGap = util.HeaderIcon(), util.HeaderGap()
    -- segN is what the layer ASKED for; #segs is what it actually got. They
    -- diverge whenever a banner runs past MAX_SEGS, and walking segN over the
    -- pool is an index into nil.
    local n, x = math.min(util.segN, #segs), segX
    for i = 1, n do
        local s = segs[i]
        local tw = (s.text.GetStringWidth and s.text:GetStringWidth()) or 0
        local w = segW + 2 + tw
        if x + w > limit then n = i - 1; break end
        -- Where this segment actually landed. A switcher popout hangs under
        -- its own segment, and only this walk knows where that is.
        s._x = x
        x = x + w + segGap
    end
    for i = n + 1, #segs do
        segs[i].icon:Hide()
        segs[i].text:Hide()
    end
end

-- A cooldown as one banner segment: lit and bare when it is ready, dimmed
-- with the time left when it is not. The mage banner's armor ring is its own
-- special case; everything else reads better as the ability strip's grammar.
function util.SegLeft(icon, left)
    if left <= 0 then
        return util.Seg(icon, false, nil)
    end
    local txt = left >= 90 and string.format("%dm", math.floor(left / 60 + 0.5))
        or string.format("%d", math.floor(left + 0.5))
    return util.Seg(icon, true, txt)
end

function util.SegCooldown(name, icon, cd, now)
    local start, duration = GetSpellCooldown and GetSpellCooldown(name)
    local left = 0
    if start and duration and duration > 1.5 then left = start + duration - now end
    util.SegLeft(icon, left)
end

-- Commander_Production on the banner. The class cooldown run above is a
-- hand-picked handful of match-deciders; Production is EVERY cooldown you are
-- currently waiting on, sorted soonest-ready first, and with this on it takes
-- the run's slot in the readout — the same icon-and-countdown grammar, the
-- same truncation against the chrome wall, the utility cluster still leading
-- and the gear, the rows toggle and the refresh still closing the line. The
-- standalone Production frame carries on wherever it is parked; this is a
-- second view of its queue, not a move.
--
-- Asked at the draw rate, so the whole test is two lookups. False when the
-- option is off OR Production is absent or switched off at its own master
-- switch — either way the class cooldowns draw as they always did, because
-- a banner that went blank the day another module was disabled would be a
-- banner nobody could trust.
function util.ProductionOn()
    return DB("HeaderProduction", false) and CommanderProduction_Queue ~= nil
end

-- One segment per queue entry: dimmed with the time left while it cools,
-- lit and bare once it is READY (and fading on Production's own linger
-- clock, since the item carries the alpha its bar is drawn at). The time
-- left is computed here rather than read off the item: Production only
-- re-sorts while its own frame is on screen, and a number a tenth of a
-- second stale is fine but a segment for a cooldown that ended while that
-- frame was closed is not. Returns false when there is no queue to draw.
function util.SegProduction(now)
    local q, n = CommanderProduction_Queue()
    if not q then return false end
    for i = 1, n do
        local it = q[i]
        local entry = it.entry
        if entry then
            local icon = entry.texture or "Interface\\Icons\\INV_Misc_QuestionMark"
            if it.ready then
                local s = util.Seg(icon, false, nil)
                if s and it.alpha then s.icon:SetAlpha(it.alpha) end
            else
                local left = (entry.start or 0) + (entry.duration or 0) - now
                if left > 0 then util.SegLeft(icon, left) end
            end
        end
    end
    return true
end

-- The banner's whole cooldown run, shared by every layer that has one. The
-- book was filtered to trained spells at login and each layer owns its own
-- toggle (SDATA.BANNER_CD_KEY), so what was four identical loops is one.
-- With Production embedded its queue stands in for the run.
function util.SegCds(now)
    if util.ProductionOn() and util.SegProduction(now) then return end
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
-- The raid frames are the same shape one addon over: CompactRaidFrameContainer
-- (Blizzard_CompactRaidFrames, parent UIParent, a plain Frame) holds every
-- CompactUnitFrame, so hiding the container is again the whole job. It is
-- NOT under PartyFrame, so it needs naming on its own. Blizzard re-shows it
-- from CompactRaidFrameManager_UpdateContainerVisibility() on every roster
-- change, which the OnShow hook below absorbs. CompactRaidFrameManager (the
-- tab on the left edge) is deliberately left alone: it carries the raid
-- tools — ready check, world markers, tank assignment — and nothing on this
-- board replaces those.
--
-- Giving a frame back: PartyFrame's own OnShow re-derives its members, so a
-- plain Show() is right there. The raid container is different — Blizzard
-- decides its visibility from ShouldShowRaidFrames() and the manager's
-- Show/Hide toggle, and the roster may have changed while we sat on it (hid
-- in a raid, toggled back in a party). So its `restore` asks Blizzard's own
-- updater to recompute instead of showing blindly; that updater also refreshes
-- CompactPartyFrame, which is exactly the path Blizzard runs itself.
--
-- Everything here is gated on combat. The containers themselves are insecure,
-- but they parent secure buttons, and a settings toggle has no business
-- finding out exactly where the engine draws that line. A container Blizzard
-- raises mid-fight is left up and flagged dirty, so it drops with the
-- PLAYER_REGEN_ENABLED re-apply.
--
-- One chunk local, holding both state and functions: this file sits close to
-- Lua's 200-local cap (see the SDATA note at the top).
-- ---------------------------------------------------------------------------
blizz = {
    names = { "PartyFrame", "CompactRaidFrameContainer" },
    restore = {
        CompactRaidFrameContainer = function()
            if CompactRaidFrameManager_UpdateContainerVisibility and CompactRaidFrameManager then
                CompactRaidFrameManager_UpdateContainerVisibility()
                return true
            end
        end,
    },
    hooked = {}, hidByUs = {}, dirty = false,
}

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
                    if not blizz.Hidden() then return end
                    if InCombat() then blizz.dirty = true; return end
                    -- Marked as ours, or a frame Blizzard raised while the
                    -- toggle was on could never be given back
                    blizz.hidByUs[name] = true
                    self:Hide()
                end)
            end
            -- Strictly symmetric: hide only what is currently showing, and
            -- restore only what that hid. A frame already down when we got
            -- here stays down — it is not ours to reveal.
            if hide then
                if f:IsShown() then blizz.hidByUs[name] = true; f:Hide() end
            elseif blizz.hidByUs[name] then
                blizz.hidByUs[name] = nil
                local r = blizz.restore[name]
                if not (r and r()) then
                    f:Show()   -- PartyFrame's own OnShow re-initializes its members
                end
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
        and "|cff66ccffCommander Party Frames|r: default party and raid frames |cffff7f50hidden|r."
        or "|cff66ccffCommander Party Frames|r: default party and raid frames |cff33ff33shown|r.")
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
        GameTooltip:SetText(blizz.Hidden() and "Default party/raid frames: hidden"
            or "Default party/raid frames: shown")
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
    settingsBtn:SetSize(SDATA.HEADER_CHROME, SDATA.HEADER_CHROME)
    -- Provisional: util.ChromeStyle owns the real scale and placement, and
    -- reaches this button on the first draw after it is built.
    settingsBtn:SetPoint("TOPRIGHT", root, "TOPRIGHT", -(SDATA.PAD - 3), -1.5)
    -- The cog is DRAWN, not loaded. It used to be Interface\WorldMap\
    -- Gear_64Grey, which is Cataclysm-era world-map art: this client runs the
    -- retail-style UI framework, that folder no longer ships it, and a texture
    -- path that does not resolve draws nothing at all — leaving a button that
    -- was present, positioned and clickable but completely invisible. Every
    -- other piece of chrome on this header (the stacked-rows toggle beside it)
    -- already builds its glyph from SetColorTexture quads, which need no art
    -- file and so have no path to go stale. This one now matches.
    --
    -- A cog reads as a cog because of three things in this order: teeth
    -- around a rim, a solid body, and a HOLE through the middle. The first
    -- version had the first two and, in place of the third, a hub in the same
    -- grey as everything else — so the middle filled in solid and eight
    -- spokes radiated out of a bright blob. That is an asterisk, which is
    -- what a settings glyph must not be mistaken for.
    --
    -- Same four bars at 45-degree steps for eight teeth, slightly narrower so
    -- they stay countable; a body that merges their roots into one disc; and
    -- the axle punched dark on top of it. Nothing here is loaded from an art
    -- path, so nothing here can go stale the way the old
    -- Interface\WorldMap\Gear_64Grey did.
    settingsBtn.cog = {}
    for i = 1, 4 do
        local t = settingsBtn:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(0.8, 0.8, 0.8, 0.75)
        t:SetSize(2.2, 12)
        t:SetPoint("CENTER", settingsBtn, "CENTER", 0, 0)
        t:SetRotation(math.rad((i - 1) * 45))
        settingsBtn.cog[i] = t
    end
    -- The body, sized so its CORNERS tuck under the diagonal teeth rather
    -- than poking out between them — that overhang is what was left reading
    -- as a star. At 6.5 across in a 12px button the corners land just inside
    -- the diagonals and the eight teeth stand clear of a solid rim.
    settingsBtn.hub = settingsBtn:CreateTexture(nil, "ARTWORK")
    settingsBtn.hub:SetColorTexture(0.8, 0.8, 0.8, 0.85)
    settingsBtn.hub:SetSize(6.5, 6.5)
    settingsBtn.hub:SetPoint("CENTER", settingsBtn, "CENTER", 0, 0)
    -- The axle. Quads cannot cut a hole, so this is the header backdrop's own
    -- black painted back over the body — which is exactly what a hole looks
    -- like there, and still reads as one against the world when the backdrop
    -- is switched off.
    settingsBtn.bore = settingsBtn:CreateTexture(nil, "OVERLAY")
    settingsBtn.bore:SetColorTexture(0, 0, 0, 0.85)
    settingsBtn.bore:SetSize(3, 3)
    settingsBtn.bore:SetPoint("CENTER", settingsBtn, "CENTER", 0, 0)
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


-- The Nearby Raid control, third piece of chrome on the header and built the
-- same way as the other two: quads, no art path, so nothing here can go stale
-- the way a missing texture silently does (see the cog's note above).
--
-- The glyph is the two-arrow cycle mark — a shaft with a head at each end,
-- pointing opposite ways — because at twelve pixels a circular arrow is mush
-- and this one still reads as "swap these out". The BUTTON also reports the
-- auto-refresh state through its tint, so the setting is legible from the
-- board without opening anything: grey is manual, green is auto, amber means
-- a re-pick is made and waiting for the fight to end (Click-Cast only —
-- secure rows cannot be re-bound in combat).
function near.Arrow(btn, dir, y)
    -- dir is +1 for the head on the right, -1 for the head on the left
    local parts = {}
    local shaft = btn:CreateTexture(nil, "ARTWORK")
    shaft:SetSize(8, 1.6)
    shaft:SetPoint("CENTER", btn, "CENTER", -0.4 * dir, y)
    parts[#parts + 1] = shaft
    -- Two strokes meeting at the shaft's tip and opening back along it. A bar
    -- rotated 45 degrees is a diagonal; one above the shaft and one below make
    -- the arrowhead without ever needing a triangle.
    for i = 1, 2 do
        local t = btn:CreateTexture(nil, "ARTWORK")
        t:SetSize(1.5, 3.4)
        local up = (i == 1) and 1 or -1
        t:SetPoint("CENTER", btn, "CENTER", 2.7 * dir, y + 1.1 * up)
        t:SetRotation(math.rad(45 * dir * up))
        parts[#parts + 1] = t
    end
    return parts
end

function near.EnsureButton()
    if near.btn or not profile then return end
    local b = CreateFrame("Button", nil, root)
    b:SetSize(12, 12)
    b.glyph = {}
    for _, t in ipairs(near.Arrow(b, 1, 2.4)) do b.glyph[#b.glyph + 1] = t end
    for _, t in ipairs(near.Arrow(b, -1, -2.4)) do b.glyph[#b.glyph + 1] = t end
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.25)
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            CommanderPartyFramesDB.NearAuto = not DB("NearAuto", false)
            near.since = 0
            near.PaintButton()
            if Commander and Commander.Notify then
                Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
            end
            print(string.format("|cff66ccffCommander Party Frames|r: nearby auto-refresh %s.",
                DB("NearAuto", false) and "|cff33ff33on|r" or "|cffff8c26off|r"))
        elseif CommanderPartyFrames_NearRefresh then
            CommanderPartyFrames_NearRefresh(false)   -- by hand: no head start
        end
        -- The tooltip is open under the cursor while you click, and every
        -- line in it just changed. Re-run the handler rather than leaving a
        -- stale count and a stale auto state sitting there.
        local enter = self.GetScript and self:GetScript("OnEnter")
        if enter and GameTooltip:IsOwned(self) then enter(self) end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText("Nearby Raid")
        local n = #near.slots + (DB("IncludeSelf", true) and 1 or 0)
        GameTooltip:AddLine(string.format("%d of %d rows picked, %s.", n, near.Count(),
            near.exact and "measured in yards" or "ranked by range bands"),
            0.8, 0.8, 0.8, true)
        if near.pending then
            GameTooltip:AddLine("A new pick is waiting for the fight to end — Click-Cast rows cannot be re-bound in combat.",
                0.95, 0.75, 0.3, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffd100Left-click|r  pick again, sorted by distance", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(string.format("|cffffd100Right-click|r  auto-refresh: %s",
            DB("NearAuto", false)
                and string.format("|cff33ff33on|r, every %ds", DB("NearInterval", 3))
                or "|cffff8c26off|r"), 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    near.btn = b
    near.PaintButton()
end

function near.PaintButton()
    local b = near.btn
    if not b then return end
    local r, g, bl, a = 0.8, 0.8, 0.8, 0.75
    if near.pending then
        r, g, bl, a = 0.95, 0.75, 0.3, 0.95
    elseif DB("NearAuto", false) then
        r, g, bl, a = 0.35, 0.85, 0.45, 0.95
    end
    for i = 1, #b.glyph do b.glyph[i]:SetColorTexture(r, g, bl, a) end
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
        b:SetPoint("TOPRIGHT", root, "TOPRIGHT", -(SDATA.PAD - 2), -1)
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
        util.portalPop:SetPoint("TOPRIGHT", root, "TOPRIGHT", -(SDATA.PAD - 2), -(util.HeaderH() + 3))
        local ppbg = util.portalPop:CreateTexture(nil, "BACKGROUND")
        ppbg:SetAllPoints(util.portalPop)
        ppbg:SetTexture("Interface\\Buttons\\WHITE8X8")
        ppbg:SetVertexColor(0, 0, 0, 0.75)
        util.portalPop:Hide()
    end
    -- Banner switchers are NOT mage-only: the paladin banner has two of them.
    -- They self-gate on SDATA.SWITCHERS, so a layer without any builds none.
    util.EnsureSwitchers()
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
    local fc = util.fc
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
    -- Battleground marks: gated on the zone as well as the setting, because
    -- these auras cannot exist anywhere else and the flag's own entry is
    -- pruned by zoning rather than by an expiry (it has none).
    local bgOn = DB("ShowBGBuffs", true) and util.InBattleground()
    -- Forecast: the pending-damage / pending-healing read. Rebuilt from
    -- scratch each scan (the list is pooled, so "rebuilt" is one integer),
    -- because an aura that fell off has to stop counting immediately.
    --
    -- RELIABLE scans only, under the same contract as everything else on this
    -- pass: an out-of-range ally's aura list comes back short or empty, and
    -- rebuilding from that would blank their forecast and then restore it the
    -- moment they stepped back in. Left alone, the list they already have
    -- decays correctly on its own — every entry carries its own expiry.
    local fcOn = reliable and DB("Forecast", "BAR") ~= "OFF"
    if fcOn then
        local flist = fc.on[guid]
        if flist then flist.n = 0 end
    elseif DB("Forecast", "BAR") == "OFF" and fc.on[guid] then
        fc.on[guid] = nil
    end
    local armorFound, formFound, auraFound, sealFound
    wipe(scanAbsorbs)
    if buffOn then wipe(util.buffExp); wipe(util.buffDur); wipe(util.buffMine) end
    if bgOn then util.bgScan.n = 0 end
    if stripOn then wipe(strip.scan) end
    for i = 1, 40 do
        local aura = C_UnitAuras.GetBuffDataByIndex(unit, i, "HELPFUL")
        if not aura then break end
        if aura.name == PWS_NAME and not pwsExpire then
            pwsExpire = aura.expirationTime
            pwsSpellId = aura.spellId
            pwsMine = aura.sourceUnit and UnitIsUnit(aura.sourceUnit, "player") or false
            pwsIndex = i
        elseif bgOn and SDATA.BG_BY_NAME[aura.name] then
            -- ANY caster, always: nobody casts these on anybody. The flag is
            -- an aura the battleground puts on whoever clicked it and the
            -- powerups come off the ground, so "who put it there" is not a
            -- question with an answer, let alone a useful one.
            local bdef = SDATA.BG_BY_NAME[aura.name]
            local bs = util.bgScan
            local e = bs[bs.n + 1]
            if not e then e = {}; bs[bs.n + 1] = e end
            bs.n = bs.n + 1
            e.def, e.prio = bdef, bdef.prio
            e.icon = aura.icon or bdef.icon
            e.expire, e.duration = aura.expirationTime, aura.duration
        elseif buffOn and SDATA.BUFF_BY_NAME[aura.name] then
            -- Any caster's buff counts as covered, and the group version
            -- satisfies the same slot as the single (both map to one def).
            --
            -- ...except the blessings, which are the one family where "who
            -- cast it" is the whole question: two paladins may each hold a
            -- different blessing on the same target, so another paladin's
            -- Kings sitting in this list means nothing about whether YOUR
            -- blessing is on them. Rejected outright rather than recorded and
            -- filtered later, so nothing downstream can mistake it for cover.
            local bdef = SDATA.BUFF_BY_NAME[aura.name]
            local bkey = bdef.key
            if not util.buffExp[bkey] then
                local mine = (aura.sourceUnit and UnitIsUnit(aura.sourceUnit, "player")) or false
                if mine or not util.BuffMineOnly(bdef) then
                    util.buffExp[bkey] = aura.expirationTime or 0
                    util.buffDur[bkey] = aura.duration
                    util.buffMine[bkey] = mine
                end
            end
        elseif isPlayer and not armorFound and armorNames[aura.name] then
            armorFound = { icon = armorNames[aura.name], expire = aura.expirationTime,
                duration = aura.duration }
        end
        -- Pending healing: ANY caster's hot counts. The question this
        -- answers is "how much healing is already rolling on them" — a
        -- reason not to spend a global — and their other healer's Renew is
        -- exactly as good a reason as yours. (The ours-only strip a few
        -- lines down answers a different question: what did *I* put here.)
        if fcOn then
            util.NotePeriodicAura(guid, aura.name, aura.icon,
                aura.expirationTime, aura.duration, false)
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
        -- The Mending tracker's second channel. The combat log tells it what
        -- HAPPENED; the scan tells it what IS, which is where the charge
        -- count and the real expiry come from, and which lets a session that
        -- was already in flight across a reload be adopted rather than lost.
        -- `reliable` is load-bearing: an out-of-range ally's empty scan is
        -- not evidence of absence, and reading it as one would announce a
        -- loss every time the holder ran behind a pillar.
        if util.PoMOn() then
            util.NotePoMSeen(guid, strip.scan.POM, reliable, GetTime())
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
                slot.mine = util.buffMine[k] or false
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

    -- Battleground marks, under the same contract, with one difference that
    -- matters: the flag carries NO expiry, so nothing but a scan that could
    -- actually see them ever takes the banner off a row. That is the right
    -- way round — the whole point of the mark is the person who has run out
    -- of your sight with it — and the two things that end a carry without a
    -- scan are both already read straight off the unit at paint time: they
    -- died (the mark hides with every other one on a dead row), or you left
    -- the battleground (PLAYER_ENTERING_WORLD wipes the table).
    if bgOn then
        local bs = util.bgScan
        if bs.n > 0 then
            local rec = util.bgState[guid]
            if not rec then rec = {}; util.bgState[guid] = rec end
            for i = 1, bs.n do
                local e, slot = bs[i], rec[i]
                if not slot then slot = {}; rec[i] = slot end
                slot.key, slot.prio = e.def.key, e.prio
                slot.label, slot.icon = e.def.label, e.icon
                slot.expire, slot.duration = e.expire, e.duration
            end
            for i = bs.n + 1, #rec do rec[i] = nil end
            if bs.n > 1 then table.sort(rec, util.BGCompare) end
        elseif reliable then
            util.bgState[guid] = nil
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
        -- Pending damage: every dot ticking on them, whoever cast it
        if fcOn then
            util.NotePeriodicAura(guid, aura.name, aura.icon,
                aura.expirationTime, aura.duration, true)
        end
        -- Ability-bar lockout debuffs (Hypothermia / Forbearance) — chassis
        local lockKind = lockNames[aura.name]
        if lockKind == "hypo" then
            hypoExpire = aura.expirationTime or 0
        elseif lockKind == "forb" then
            forbExpire = aura.expirationTime or 0
        end
        if dispelOn and dispelCount < MAX_DISPEL_ICONS and not mutedNames[aura.name] then
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
    -- Prayer of Mending. Not an aura on a row but an object in flight, so
    -- every branch here only WRITES DOWN what happened — see the note at
    -- SDATA.POM_GRACE. Nothing is declared until util.PoMTick has waited out
    -- the bounce, which is why none of this can make a sound by itself.
    if util.PoMOn() and util.pomName then
        local pn, t = util.pomName, GetTime()
        if subevent == "UNIT_DIED" then
            -- Unsourced, so it cannot be filtered on the caster: the holder
            -- dying takes our Mending with them.
            util.NotePoMDeath(destGUID, t)
        elseif (subevent == "SPELL_DISPEL" or subevent == "SPELL_STOLEN") and a5 == pn then
            -- Also unsourced-by-us: the dispeller is on the other team, and
            -- the buff they took is the EXTRA spell (a5), not a2.
            util.NotePoMDispel(destGUID, t)
        elseif sourceGUID == playerGUID and a2 == pn then
            if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
                util.NotePoMApplied(destGUID, t)
            elseif subevent == "SPELL_AURA_REMOVED" then
                util.NotePoMRemoved(destGUID, t)
            elseif subevent == "SPELL_HEAL" then
                util.NotePoMHeal(destGUID, t)
            end
        end
    end
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
    -- Forecast learning. Every periodic tick and every completed heal on the
    -- log is a free measurement of what that spell is worth RIGHT NOW, with
    -- gear, talents, buffs and resistances already in it — which is the only
    -- way TBC will ever tell us. Cheap enough to run unconditionally: two
    -- string compares and, on a hit, one table store.
    --   PERIODIC payload: amount, overkill, school, resisted, blocked,
    --                     absorbed, critical  (a4 .. a10)
    --   HEAL payload:     amount, overhealing, absorbed, critical (a4 .. a7)
    -- Overhealing is deliberately NOT subtracted: what we are forecasting is
    -- the heal's SIZE, and it only overhealed because they were already full.
    if subevent == "SPELL_PERIODIC_DAMAGE" then
        util.NotePeriodic(destGUID, a2, a4, a10, true, GetTime())
    elseif subevent == "SPELL_PERIODIC_HEAL" then
        util.NotePeriodic(destGUID, a2, a4, a7, false, GetTime())
        util.NoteOverheal(destGUID, sourceGUID, a4, a5, GetTime())
    elseif subevent == "SPELL_HEAL" then
        util.NoteHeal(sourceGUID, a1, a2, a4, a7, GetTime())
        util.NoteOverheal(destGUID, sourceGUID, a4, a5, GetTime())
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
            -- READY carries no WORD on this board. The state still does all
            -- of its work — the pulsing stripe, the sort that floats a
            -- shieldless ally up — but spelling it out was the row saying in
            -- text what the ghosted shield icon beside it already says by
            -- being ghosted, in the one slot wide enough to hold a number
            -- that means something.
            r.state, r.mainText = "READY", ""
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
    -- Cleared before the early return, not after it: the test board reuses its
    -- row tables between passes, so a stale assignment left on one would put a
    -- blessing under a row that is no longer asking for one.
    r.blessWant, r.blessWantWhy, r.blessHave = nil, nil, nil
    local n = #SDATA.BUFF_ACTIVE
    if n == 0 or r.selfSpell then r.buffCount = 0; return end
    local rec = intState[r.guid]
    local rebuffAt = DB("IntRefreshAt", 300)
    r.buffs = r.buffs or {}
    local shown = 0
    for i = 1, n do
        local def = SDATA.BUFF_ACTIVE[i]
        -- The combined blessing slot resolves per ROW, not per registry entry:
        -- which blessing it watches is this ally's assignment, so the answer
        -- differs down the board while the layout stays one slot wide.
        --
        -- An ally carrying a DIFFERENT blessing of yours reads as missing, on
        -- purpose. The alternative — "covered, near enough" — is how you end a
        -- match having never noticed the healer took Might off a stray cast.
        -- What they are actually carrying is kept in r.blessHave so the
        -- tooltip can say so in words instead of the slot lying with colour.
        local want, wantWhy
        if def.combined then
            want, wantWhy = util.BlessFor(r)
            r.blessWant, r.blessWantWhy = want, wantWhy
            if rec then
                for _, b in ipairs(SDATA.CLASS_BUFFS.BLESS) do
                    local e = rec[b.key]
                    if e and not (e.expire and e.expire > 0 and e.expire <= now) then
                        r.blessHave = b
                        break
                    end
                end
            end
        end
        -- A buff nobody would cast here earns no slot at all: Intellect and
        -- Spirit are for mana users, Blessing of Might is for people who swing
        -- things, and a rogue's row should not carry a permanent dark reminder
        -- of a spell that does nothing for them. The combined slot answers the
        -- same question through its assignment: NONE, or nothing trained that
        -- suits them, and it spends no slot either. The width stays reserved
        -- by the layout, so the row keeps its shape with nothing to say here.
        if (not def.combined or want) and util.BuffApplies(def, r) then
            shown = shown + 1
            local slot = r.buffs[shown]
            if not slot then slot = {}; r.buffs[shown] = slot end
            local key = want and want.key or def.key
            local e = rec and rec[key]
            local left
            if e and e.expire and e.expire > 0 then
                left = e.expire - now
                if left <= 0 then rec[key], e, left = nil, nil, nil end
            end
            slot.def = def
            slot.want = want
            slot.icon = want and want.icon or def.icon
            slot.up = e and true or false
            -- expire 0 is a permanent aura (no readable clock): up, no sweep
            slot.expire = e and e.expire or nil
            slot.duration = (e and e.duration and e.duration > 0) and e.duration
                or (want or def).duration
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
-- Which instruments each Lifebloom display mode turns on. Two tables rather
-- than a string compare at four call sites, and the settings dropdown's
-- values are these keys.
SDATA.LB_DISPLAY_CLOCK = { CLOCK = true, BOTH = true }
SDATA.LB_DISPLAY_BAR   = { BAR = true, BOTH = true }

-- ---------------------------------------------------------------------------
-- Perimeter outlines: a timer drawn as a ring around an icon's own edge.
--
-- Every other clock on this board takes space from something — a sweep hides
-- the art it covers, a drain bar costs the row three pixels of height, a
-- number needs a corner. An icon's OUTLINE costs nothing but its own border,
-- which is why it is the right place for a second timer on an icon that
-- already has one: the Power Word: Shield slot is showing you the shield's
-- thirty seconds on its sweep, and the thing you actually need beside it is
-- whether you may cast it again — two clocks, one icon, no new width.
--
-- Five textures rather than four: the ring starts at TOP CENTRE and runs
-- clockwise, the way a clock face does, so the top edge is split into the
-- half it ends on and the half it starts on. Lengths are the only thing that
-- changes per paint; the anchors are fixed at layout.
-- A hairline, which is what the rest of this board calls one pixel: the
-- overheal ring and the forecast ticks are both drawn at exactly this width.
-- Two pixels on a fifteen-pixel slot is a border you read INSTEAD of the art
-- it surrounds, which is the wrong way round -- the ring is an annotation on
-- the icon, not a frame around it.
SDATA.OUTLINE_W = 1
SDATA.RING_LOCK = { 0.92, 0.22, 0.22 }   -- you cannot cast this here yet
SDATA.RING_CD   = { 0.98, 0.52, 0.20 }   -- the spell itself is still coming back
-- The longest the global cooldown can be. Haste only ever shortens it (toward
-- a one-second floor), so this is a ceiling rather than an equality, and it
-- is the BACKSTOP test in util.ReadSpellRings rather than the primary one --
-- the primary is that two spells reporting the identical window are both
-- reporting the global. Nothing either ring tracks has a real cooldown
-- anywhere near this short.
SDATA.GCD_MAX = 1.5

function util.MakeOutline(parent)
    local o = {}
    for i = 1, 5 do
        local t = parent:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:Hide()
        o[i] = t
    end
    return o
end

-- Fixed points, set once at layout: each segment grows from the corner it is
-- pinned to, in the direction the ring travels.
function util.AnchorOutline(o, icon)
    o[1]:ClearAllPoints(); o[1]:SetPoint("TOPLEFT", icon, "TOP", 0, 0)
    o[2]:ClearAllPoints(); o[2]:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
    o[3]:ClearAllPoints(); o[3]:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    o[4]:ClearAllPoints(); o[4]:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
    o[5]:ClearAllPoints(); o[5]:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
end

function util.HideOutline(o)
    for i = 1, 5 do o[i]:Hide() end
end

-- `frac` is what is LEFT, not what has elapsed: these are lockouts, and the
-- board's existing vocabulary for a lockout is a red bar that DRAINS (the
-- Weakened Soul strip, the Forbearance drain). A ring that filled up as it
-- came ready would be the same fact in the opposite direction on the same
-- row, which is worse than not drawing it.
function util.DrawOutline(o, size, frac, c)
    if not (size and size > 0) or not frac or frac <= 0 then
        util.HideOutline(o)
        return
    end
    local w = SDATA.OUTLINE_W
    if frac > 1 then frac = 1 end
    local left = frac * size * 4
    local half = size * 0.5
    for i = 1, 5 do
        local cap = (i == 1 or i == 5) and half or size
        local len = left < cap and left or cap
        left = left - len
        local t = o[i]
        -- Under half a pixel is not a ring segment, it is a dot on a corner
        if len > 0.5 then
            if i == 2 or i == 4 then t:SetSize(w, len) else t:SetSize(len, w) end
            t:SetVertexColor(c[1], c[2], c[3], 0.95)
            t:Show()
        else
            t:Hide()
        end
    end
end

-- Health fraction -> bar colour. Takes HEALTH, never the bar's fill ratio:
-- see the note at the call site for why those are not the same number.
function util.HealthTint(hp, out)
    local ramp = SDATA.HP_RAMP
    local h = hp or 1
    if h ~= h then h = 1 end          -- a NaN ratio must not paint a black bar
    if h < 0 then h = 0 elseif h > 1 then h = 1 end
    local lo = ramp[1]
    for i = 2, #ramp do
        local hi = ramp[i]
        if h <= hi[1] then
            local span = hi[1] - lo[1]
            local u = span > 0 and ((h - lo[1]) / span) or 0
            out = out or {}
            out[1] = lo[2] + (hi[2] - lo[2]) * u
            out[2] = lo[3] + (hi[3] - lo[3]) * u
            out[3] = lo[4] + (hi[4] - lo[4]) * u
            return out
        end
        lo = hi
    end
    out = out or {}
    out[1], out[2], out[3] = lo[2], lo[3], lo[4]
    return out
end
SDATA.HP_TINT = {}      -- reused scratch: this runs per row per draw

-- One colour for the roll, wherever it is drawn — the clock, the pips and the
-- bar all say the same thing at the same moment, which is the whole reason
-- three instruments are not three times the reading.
function util.RollTint(slot)
    if not slot then return SDATA.ROLL_SAFE end
    if slot.late then return SDATA.ROLL_LATE end
    if slot.bloom then return SDATA.ROLL_BLOOM end
    if slot.due then return SDATA.ROLL_DUE end
    return SDATA.ROLL_SAFE
end

-- Prayer of Mending's charge gauge. The pips are fuel, not a stack that grew,
-- so the tint is a function of what is LEFT: calm while there is plenty,
-- warning on the last one, because the last charge is the one that ends the
-- object and hands you back the global.
function util.ChargeTint(slot)
    local n = (slot and slot.stacks) or 0
    if n <= 1 then return SDATA.CHARGE_LAST end
    if n <= 3 then return SDATA.CHARGE_MID end
    return SDATA.CHARGE_FULL
end

-- ---------------------------------------------------------------------------
-- The Mending session. ONE at a time, because a priest owns one Mending at a
-- time, and it is an object that travels rather than an aura that sits. The
-- long note at SDATA.POM_GRACE is the argument for why this exists at all;
-- what follows is the machine.
--
-- That singleton is the one real assumption here, and it is worth saying what
-- happens if this client turns out to disagree with it. A second Mending
-- landing while one is live reads as a RECAST: the older session closes
-- SILENTLY and the newer one is tracked. So the failure mode is a missed
-- alert, never a false one — which is the right direction to fail in, because
-- an alert that cries bounce is an alert you stop hearing, and one that
-- occasionally stays quiet is merely an alert.
--
--   guid            who holds it right now (nil = no live session)
--   stacks/expire   what we believe about it, corroborated by the aura scan
--   pendingAt       armed the moment the aura left the holder: the deadline
--                   past which silence means it is genuinely gone. NOTHING is
--                   declared before this lapses — that wait IS the bounce test
--   pendingReason   what we would call the loss if the grace lapsed now
--   healAt          last charge consumption. A bounce and a spend BOTH open
--                   with one, which is exactly why the heal never decides
--                   between them and the grace always does
--   hopAt/hopGuid   the arrival flare; fromGuid is the departure ghost
--   flashGuid/Until/Reason   a finished session, waiting for its row to paint
-- ---------------------------------------------------------------------------
util.pom = { hops = 0 }

-- The whole feature's gate, and the only thing any of it is asked before it
-- does anything: the tracker, the pips, the hop and the alert all hang off
-- this one call. Priest board only, only once the spell is actually in the
-- book (a level-twelve priest has no Mending to lose), and only while the
-- setting says so — so switching Track Mending off is genuinely off, not a
-- board that keeps following the object with its mouth shut.
function util.PoMOn()
    if layer ~= "PWS" or not util.pomKnown then return false end
    if not DB("PoMTrack", true) then
        -- Switched off with one in flight. Drop the session rather than leave
        -- it armed: a pending grace resolved on the far side of the switch
        -- would announce a loss the moment tracking came back on, about an
        -- object that has been gone for ten minutes.
        if util.pom.guid then util.PoMReset() end
        return false
    end
    return true
end

-- Wipe the session outright. A new arena is not the old one's Mending still
-- in flight, and a roster wipe can strand it on a GUID that has left — in
-- both cases the honest answer is "we no longer know", which is not the same
-- as "it was lost" and must never make a sound.
function util.PoMReset()
    local p = util.pom
    p.guid, p.stacks, p.expire, p.duration = nil, 0, nil, nil
    p.pendingAt, p.pendingReason, p.healAt = nil, nil, nil
    p.dispelAt, p.deathAt, p.deathGuid = nil, nil, nil
    p.hopAt, p.hopGuid, p.fromGuid, p.castAt = nil, nil, nil, nil
    p.flashGuid, p.flashUntil, p.flashReason = nil, nil, nil
    p.hops = 0
end

-- Close the session and, if the reason earns one, hand the alert to the tick.
-- BOUNCE and RECAST close a session without anything having gone wrong, so
-- they return nil and the board stays quiet.
function util.PoMEnd(reason, now)
    local p = util.pom
    if not p.guid then return nil end
    local guid = p.guid
    local info = SDATA.POM_REASONS[reason]
    p.guid, p.stacks, p.expire, p.duration = nil, 0, nil, nil
    p.pendingAt, p.pendingReason, p.healAt = nil, nil, nil
    p.dispelAt, p.deathAt, p.deathGuid = nil, nil, nil
    p.castAt, p.hops = nil, 0
    if not (info and info.alert) then return nil end
    p.endedGuid, p.endedReason, p.endedAt = guid, reason, now
    return reason, guid
end

-- The aura landed on somebody. Three different things wear this shape, and
-- telling them apart is the difference between a useful board and a metronome:
--
--   a BOUNCE  the grace was armed and the object has reappeared. Whatever we
--             were about to call that loss, we were wrong — cancel it.
--   a RECAST  a live session, no pending loss, a new holder: you moved it
--             yourself, so nothing was lost and nothing should sound.
--   a CAST    no session at all. Five charges and thirty seconds.
--
-- The out-of-order case is real and worth the two lines it costs: the scan
-- and the log can deliver the new holder BEFORE the old one's removal, which
-- looks exactly like a recast. A bounce is always opened by a charge firing,
-- and a recast never is, so a recent heal breaks the tie.
function util.NotePoMApplied(guid, now, expire, duration, stacks)
    if not guid then return end
    local p = util.pom
    local bounced = false
    if p.pendingAt then
        bounced = true
        p.fromGuid = p.guid
        p.pendingAt, p.pendingReason = nil, nil
        p.hops = (p.hops or 0) + 1
    elseif p.guid and p.guid ~= guid then
        if p.healAt and (now - p.healAt) <= SDATA.POM_GRACE then
            bounced = true
            p.fromGuid = p.guid
            p.hops = (p.hops or 0) + 1
        else
            util.PoMEnd("RECAST", now)
        end
    end
    if not p.guid then
        p.castAt, p.hops, p.fromGuid = now, 0, nil
        p.stacks = stacks or SDATA.POM_CHARGES
    end
    if p.guid ~= guid then p.hopAt, p.hopGuid = now, guid end
    p.guid = guid
    p.duration = (duration and duration > 0) and duration or SDATA.POM_DURATION
    -- Which clock this is. A BOUNCE does not restart the thirty seconds --
    -- the object keeps the life it was cast with, which is the whole reason
    -- a long chain of hops can still time out mid-flight -- but any other
    -- re-application is you casting it again, and a recast onto the ally who
    -- already had it must not inherit the old expiry. Getting that backwards
    -- is a live Mending the watchdog reports as expired a second later.
    if expire and expire > 0 then
        p.expire = expire
    elseif bounced then
        p.expire = p.expire or (now + p.duration)
    else
        p.expire = now + p.duration
    end
    if stacks and stacks > 0 then p.stacks = stacks end
    p.lastSeen = now
end

-- A charge fired. Recorded, never acted on: a bounce opens with one of these
-- too, and acting here is precisely the mistake this whole file is avoiding.
function util.NotePoMHeal(guid, now)
    local p = util.pom
    if not p.guid then return end
    p.healAt = now
end

function util.NotePoMDispel(guid, now)
    local p = util.pom
    if p.guid and p.guid == guid then p.dispelAt = now end
end

function util.NotePoMDeath(guid, now)
    local p = util.pom
    if p.guid and p.guid == guid then p.deathAt, p.deathGuid = now, guid end
end

-- The aura left its holder. This is the ONE place a loss can begin, and it
-- declares nothing: it arms the grace and writes down what it would say if
-- the grace lapsed. Everything here is provisional on purpose.
function util.NotePoMRemoved(guid, now)
    local p = util.pom
    if not p.guid or p.guid ~= guid or p.pendingAt then return end
    local reason
    if p.dispelAt and (now - p.dispelAt) <= 0.5 then
        reason = "DISPELLED"
    elseif p.deathAt and p.deathGuid == guid and (now - p.deathAt) <= 1.0 then
        reason = "DIED"
    elseif p.expire and now >= (p.expire - 0.6) then
        -- Thirty seconds of a five-charge Mending is a long time to be wrong
        -- about, so the clock only gets to claim a loss when it has actually
        -- run out — not when it is merely close.
        reason = "EXPIRED"
    elseif p.healAt and (now - p.healAt) <= 0.5 then
        -- A charge fired and the aura went with it. If it bounced, the next
        -- half second says so and this is thrown away; if it does not, that
        -- was the fifth charge and the spell finished its job.
        reason = "SPENT"
    else
        reason = "LOST"
    end
    p.pendingAt, p.pendingReason = now + SDATA.POM_GRACE, reason
    p.fromGuid = guid
end

-- What the aura scan saw on one unit. A second, independent channel: it
-- corroborates presence (so a dropped combat-log event cannot strand a
-- session), supplies the charge count and the real expiry the log never
-- carries, and adopts a Mending that was already in flight across a reload.
--
-- `reliable` is the scan's own word for "I could actually have seen this" —
-- an out-of-range unit's empty scan is not evidence of absence, and treating
-- it as such would fire a loss every time the holder ran round a pillar.
function util.NotePoMSeen(guid, e, reliable, now)
    if not guid then return end
    local p = util.pom
    if e then
        if p.guid == guid then
            p.lastSeen = now
            if e.expire and e.expire > 0 then p.expire = e.expire end
            if e.duration and e.duration > 0 then p.duration = e.duration end
            if e.stacks and e.stacks > 0 then p.stacks = e.stacks end
        else
            util.NotePoMApplied(guid, now, e.expire, e.duration, e.stacks)
        end
    elseif reliable and p.guid == guid then
        util.NotePoMRemoved(guid, now)
    end
end

-- Once per draw. Resolves an armed grace, and watchdogs the case the combat
-- log cannot cover: a holder who walked out of log range with it still on
-- them. Returns the reason and the GUID when a session actually ended, so
-- the caller owns the sound and nothing in here has to know about audio.
function util.PoMTick(now)
    local p = util.pom
    if not p.guid then return nil end
    if p.pendingAt then
        if now < p.pendingAt then return nil end
        -- The grace lapsed with the object nowhere on the board. It did not
        -- bounce; it is gone, and pendingReason has been waiting to say why.
        return util.PoMEnd(p.pendingReason or "LOST", now)
    end
    if p.expire and now > (p.expire + 0.5) then
        -- No removal ever arrived. Either the holder is beyond the combat
        -- log or the event was dropped; either way thirty seconds is thirty
        -- seconds, and a session that outlives its own duration is a leak.
        return util.PoMEnd("EXPIRED", now)
    end
    return nil
end

function util.ResolveStrip(r, now)
    local rec = strip.state[r.guid]
    local n, soonest = 0, nil
    local refreshAt = DB(SDATA.STRIP_REFRESH_KEY[layer or ""] or "RenewRefreshAt", 4)
    -- The roll gets its OWN window. Sharing one with the twelve- and
    -- twenty-one-second hots is what made Lifebloom unreadable: four seconds
    -- of a seven-second buff is more than half its life, so the slot spent
    -- most of every cycle already amber and the amber stopped meaning
    -- anything. Its late threshold is separate again — that is the point
    -- past which you are not refreshing early, you are refreshing behind.
    -- Off means OFF: the roll goes back to being an ordinary strip entry,
    -- window included. Leaving its private window in force while the setting
    -- says "plain hot slot" would be the one thing worse than not having the
    -- feature — a board behaving differently from what the page says it does.
    local rollOn = DB("LBDisplay", "BOTH") ~= "OFF"
    local rollAt = DB("LBRefreshAt", 3)
    local lateAt = DB("LBLateAt", 1.5)
    r.strip = r.strip or {}
    r.roll, r.rollSlot, r.wsTint = nil, nil, nil
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
        slot.roll = (def.roll and rollOn) or false
        slot.maxStacks = def.maxStacks
        slot.charges = def.charges or false
        slot.late, slot.bloom = false, false
        slot.hop, slot.trail = 0, 0
        if h then
            n = n + 1
            local tl = h.expire and (h.expire - now) or math.huge
            slot.due = tl <= ((def.roll and rollOn) and rollAt or refreshAt)
            if def.roll and rollOn then
                slot.left = tl
                slot.late = tl <= lateAt
                -- At max stacks the window is a genuine fork rather than a
                -- reminder: refresh and keep rolling, or let it bloom for the
                -- burst. The slot says which situation it is; what to do
                -- about it is the druid's call, not the addon's.
                slot.bloom = slot.due and (slot.stacks or 0) >= (def.maxStacks or 3)
                r.roll, r.rollSlot = slot, i
            end
            if not soonest or tl < soonest then soonest = tl end
        end
    end
    -- Is our cheap rolling heal on them? Read straight off the ours-only
    -- record rather than off the visible slots, for the reason in the login
    -- resolve: untracking Renew hides its icon, it does not stop a dying
    -- ally from needing one. Expiry is checked here because the loop above
    -- only prunes the entries that actually have a slot.
    r.hotUp = false
    if util.lowHotDef and rec then
        local h = rec[util.lowHotDef.key]
        if h and h.expire and h.expire > now then r.hotUp = true end
    end
    if rec and not next(rec) then strip.state[r.guid] = nil end
    -- Mending's hop, lit on BOTH ends of it at once: a flare on the slot that
    -- just took the object and a fading ghost on the slot it left. Two rows
    -- lighting a beat apart is what makes a bounce read AS a bounce, instead
    -- of as a number that moved rows while you were watching the enemy team.
    -- It is also the only thing on this board that says "that was fine" —
    -- everything else Mending does now makes a noise.
    local p = util.pom
    if r.guid and p.hopAt and util.PoMOn() and DB("PoMTrail", true) then
        local f = 1 - (now - p.hopAt) / SDATA.POM_HOP_HOLD
        if f > 0 then
            for i = 1, #SDATA.STRIP_ACTIVE do
                local slot = r.strip[i]
                if slot and slot.charges then
                    if p.hopGuid == r.guid then slot.hop = f end
                    -- The ghost belongs to the row it LEFT, and only while
                    -- that row is genuinely empty: if the object came back to
                    -- them it is a live slot again and a trail behind it
                    -- would be the board contradicting itself.
                    if p.fromGuid == r.guid and not slot.up then slot.trail = f end
                end
            end
        end
    end
    r.stripCount = n
    r.stripSlots = #SDATA.STRIP_ACTIVE
    return n, soonest
end

-- Is anything on the strip due, each by ITS OWN window? Read as a separate
-- question from "how long has the soonest got", because since the roll got a
-- window of its own the two can disagree: a Lifebloom at four seconds is
-- inside the shared hot window and outside its own, and a row that turned
-- cyan while the Lifebloom slot was still green would be the board
-- contradicting itself in two places a druid reads at once.
function util.StripDue(r)
    if not r.strip then return false end
    for i = 1, (r.stripSlots or 0) do
        local slot = r.strip[i]
        if slot and slot.up and slot.due then return true end
    end
    return false
end

-- INT layer (Mage ally rows): these are party frames first, so the main bar
-- is plain HEALTH (lowest sorts first among the quiet rows). Buff upkeep is
-- deliberately icon-sized — Arcane Intellect state rides the left status
-- icon, an incoming priest shield rides the second — and only a removable
-- Curse escalates the whole row (purple, drain = curse remaining).
-- A group member started casting. TBC will not tell us who another player is
-- casting AT, so the target is read the way the game itself resolves one: the
-- caster's current target if it is friendly, and the caster themselves if it
-- is not (cast a heal with an enemy targeted and it lands on you). That is
-- exactly right for a healer playing off their target frame, and wrong for one
-- playing off mouseover or click-casting — a limit of the client, not a bug to
-- fix here, and the setting's tooltip says so rather than pretending otherwise.
-- What OUR OWN heal is worth, read off the spell's own tooltip. This is the
-- answer the learned numbers cannot give on their own, and the one the client
-- computes with everything already in it: spell power, healing talents, set
-- bonuses, and whatever trinket happens to be procced this second. Read fresh
-- on every cast rather than cached, precisely so a proc counts — it is one
-- tooltip parse per global, which is nothing.
--
-- Locale-tolerant by construction: rather than matching a sentence, it pulls
-- the numbers out of each line and takes the first ADJACENT PAIR that looks
-- like a heal range — both sizeable, ascending, and within a factor of three
-- of each other. "Heals a friendly target for 2494 to 2892" gives that pair;
-- a mana cost gives one number and no pair, and a hot's "1060 over 12 sec"
-- fails the ascending test. Regrowth carries both a range and a hot, and the
-- range comes first, which is the half a cast forecast is about.
function util.HealTip(spellId)
    -- Both methods checked, not just the setter: a client that cannot read
    -- back the lines it just set must cost us the tooltip estimate and leave
    -- the learned number standing, not throw out of the cast handler and take
    -- the whole inbound-heal read with it.
    if not (spellId and scanTip and scanTip.SetSpellByID and scanTip.NumLines) then
        return nil
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    if not pcall(scanTip.SetSpellByID, scanTip, spellId) then return nil end
    local lines = scanTip:NumLines()
    if type(lines) ~= "number" then return nil end
    for i = 2, lines do
        local fs = _G["CommanderPartyFramesScanTipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text then
            local prev
            for n in text:gmatch("%d[%d,]*") do
                local v = tonumber((n:gsub(",", "")))
                if prev and v and prev >= 10 and v >= prev and v <= prev * 3 then
                    return (prev + v) / 2
                end
                prev = v
            end
        end
    end
    return nil
end

-- What this caster's version of this heal lands for. For US the tooltip wins:
-- it is exact, it is right on the very first cast of a session, and it cannot
-- be dragged around by the thing that made the learned numbers wrong for a
-- healer's own casts — a heal landing on someone under Mortal Strike teaches
-- half a heal, and that is the TARGET's problem, not the spell's size.
--
-- For anyone else there is no tooltip to read (their gear is not ours), so
-- the learned value stands, by exact rank first and by name as the fallback.
function util.HealFor(srcGUID, spellId, name)
    local fc = util.fc
    if srcGUID == playerGUID then
        local tip = util.HealTip(spellId)
        if tip and tip > 0 then return tip end
    end
    return (spellId and fc.healAmt[srcGUID .. "\30" .. tostring(spellId)])
        or (name and fc.healAmt[srcGUID .. "\30" .. name])
        or (name and fc.healAny[name])
        or 0
end

function util.NoteCast(unit, spellId)
    local fc = util.fc
    if not (unit and UnitGUID and UnitCastingInfo) then return end
    local guid = UnitGUID(unit)
    -- Group members only, which already includes us: this is a read of the
    -- HEALING your side has in the air, not of everything anyone is casting.
    if not guid or not groupGuids[guid] then return end
    -- Ninth return is the spell id on this client. Taken positionally and
    -- then type-checked rather than trusted: that slot has moved between
    -- client generations, and a string landing in it must cost us the id,
    -- not the whole cast.
    local name, _, tex, _, endMs, _, _, _, tipId = UnitCastingInfo(unit)
    if not name or not fc.heal[name] then fc.casts[guid] = nil; return end
    -- The id from the EVENT is the reliable one; the tooltip's is the backstop
    spellId = spellId or (type(tipId) == "number" and tipId) or nil
    util.FlushHeals(GetTime())
    local tgt = unit .. "target"
    local dest
    if UnitExists and UnitExists(tgt) and UnitIsFriend and UnitIsFriend("player", tgt)
        and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost(tgt)) then
        dest = UnitGUID(tgt)
    end
    dest = dest or guid
    local c = fc.casts[guid]
    if not c then c = {}; fc.casts[guid] = c end
    c.dest, c.name, c.icon = dest, name, tex
    c.endTime = endMs and (endMs / 1000) or nil
    -- What THIS caster's version of this heal lands for, else nothing — a
    -- heal we have never watched land and cannot read a tooltip for is still
    -- worth knowing about, it just has no number yet.
    c.amt = util.HealFor(guid, spellId, name)
end

function util.ClearCast(unit)
    local fc = util.fc
    local guid = unit and UnitGUID and UnitGUID(unit)
    if guid then fc.casts[guid] = nil end
end

-- The breakdown's own heading. The blank spacer above it separates it from
-- the unit block — which only exists on the full setting, so it is only
-- written when there is something above it to be separated FROM. Leading
-- whitespace at the top of an otherwise empty tooltip reads as a bug.
function util.ForecastHeader()
    if (GameTooltip.NumLines and GameTooltip:NumLines() or 0) > 0 then
        GameTooltip:AddLine(" ")
    end
    GameTooltip:AddLine("Pending", 1, 0.82, 0)
end

-- The forecast, itemised, for the row tooltip. Reads exactly what the bar
-- read — same window, same learned amounts — so the two can never disagree.
function util.ForecastTooltip(guid)
    local fc = util.fc
    if not guid then return end
    local now = GetTime()
    local win = DB("ForecastWindow", 5)
    local list, any = fc.on[guid], false
    if list then
        for i = 1, list.n do
            local e = list[i]
            local rem = (e.expire and e.expire > 0) and (e.expire - now) or nil
            if rem and rem > 0 then
                local cap = (win > 0 and rem > win) and win or rem
                local ticks = math.ceil(cap / (e.interval or 3) - 0.001)
                local amt = ticks * util.TickValue(guid, e.name)
                if amt > 0 and ((e.dot and DB("ForecastDots", true))
                    or (not e.dot and DB("ForecastHots", true))) then
                    if not any then
                        util.ForecastHeader()
                        any = true
                    end
                    local txt = string.format("%s  (%d tick%s)", e.name, ticks,
                        ticks == 1 and "" or "s")
                    if e.dot then
                        GameTooltip:AddDoubleLine(txt, "-" .. FormatAmount(amt),
                            0.85, 0.85, 0.85, 1, 0.42, 0.38)
                    else
                        GameTooltip:AddDoubleLine(txt, "+" .. FormatAmount(amt),
                            0.85, 0.85, 0.85, 0.45, 1, 0.55)
                    end
                end
            end
        end
    end
    if DB("ForecastCasts", true) then
        for src, c in pairs(fc.casts) do
            if c.dest == guid and c.endTime and c.endTime > now then
                if not any then
                    util.ForecastHeader()
                    any = true
                end
                -- Who is casting it. Guarded rather than inlined: select()
                -- on a nil call errors, and a GUID the client cannot name
                -- must cost the tooltip a name, not the whole line.
                local who
                if GetPlayerInfoByGUID then
                    local ok, n = pcall(function() return select(6, GetPlayerInfoByGUID(src)) end)
                    if ok then who = n end
                end
                local txt = string.format("%s  (%.1fs)", c.name or "?", c.endTime - now)
                if who and who ~= "" then txt = who .. ": " .. txt end
                GameTooltip:AddDoubleLine(txt,
                    (c.amt and c.amt > 0) and ("+" .. FormatAmount(c.amt)) or "+?",
                    0.85, 0.85, 0.85, 0.7, 0.95, 0.8)
            end
        end
    end
end

-- `amount` is the heal's full size and `over` the part of it that spilled, so
-- the ratio is the share wasted. Clamped rather than trusted: the two come
-- from the same event but from different fields, and a ratio over one would
-- be a glow brighter than the palette allows.
function util.NoteOverheal(destGUID, srcGUID, amount, over, now)
    if not DB("OverhealGlow", true) then return end
    if not destGUID or type(amount) ~= "number" or type(over) ~= "number" then return end
    if amount <= 0 or over <= 0 then return end
    -- Yours only by default. Another healer's waste is real information (the
    -- target is capped, nobody needs to top them) but it is not YOUR global
    -- being thrown away, and conflating the two makes the cue mean less.
    if DB("OverhealMine", true) and srcGUID ~= playerGUID then return end
    local frac = math.min(1, over / amount)
    if frac < (DB("OverhealPct", 50) / 100) then return end
    local rec = util.overheal[destGUID]
    if not rec then rec = {}; util.overheal[destGUID] = rec end
    rec.until_ = now + DB("OverhealHold", 1)
    -- The LOUDEST recent waste wins while the hold lasts: a tick that spilled
    -- entirely should not be talked over by a big heal that spilled half.
    rec.frac = (rec.frac and rec.until_ > now) and math.max(rec.frac, frac) or frac
end

-- How hard this row is currently overhealing, 0 when it is not. Read per
-- paint, so the answer decays with the clock the way the glow does.
function util.OverhealAt(guid, now)
    -- Gated on the READ as well as the write. Off has to mean off now, not
    -- once the last recorded spill finishes fading — a setting that keeps
    -- drawing for another second after you clear it reads as a bug.
    if not DB("OverhealGlow", true) then return 0 end
    local rec = guid and util.overheal[guid]
    if not rec or not rec.until_ then return 0 end
    if rec.until_ <= now then util.overheal[guid] = nil; return 0 end
    local hold = DB("OverhealHold", 1)
    -- Fades out over the hold rather than blinking off, so a one-off waste
    -- reads as a pulse and a hot spilling every tick reads as a steady ring.
    local left = hold > 0 and math.min(1, (rec.until_ - now) / hold) or 1
    return (rec.frac or 0) * left
end

-- The row's three forecast numbers. Called per paint rather than per scan,
-- because the answer shrinks with the clock: a dot with two seconds left is
-- worth a tick, and it was worth four when it landed.
--
--   r.fcDot    damage still queued in what is ticking on them
--   r.fcHot    healing still rolling from hots, whoever cast them
--   r.fcCast   healing in the air from casts that have not landed yet
--   r.fcCastN  how many such casts (so an unlearned heal still reads as one)
--
-- The WINDOW is the setting that makes this usable rather than merely true.
-- A full Curse of Agony is 1600 damage over twenty-four seconds; almost none
-- of that is a reason to do anything right now. Capping every aura at the
-- next N seconds turns "what will eventually happen" into "what happens
-- before my next global matters", which is the actual question.
function util.Forecast(r, now)
    local fc = util.fc
    r.fcDot, r.fcHot, r.fcCast, r.fcCastN = nil, nil, nil, nil
    if not r.guid or r.selfSpell or r.dead then return end
    local mode = DB("Forecast", "BAR")
    if mode == "OFF" then return end
    local win = DB("ForecastWindow", 5)
    local dot, hot = 0, 0
    local list = fc.on[r.guid]
    if list then
        for i = 1, list.n do
            local e = list[i]
            -- An aura the client reports with no expiry — a permanent one, or
            -- a unit we cannot fully see — has no countable ticks left.
            local rem = (e.expire and e.expire > 0) and (e.expire - now) or nil
            if rem and rem > 0 then
                if win > 0 and rem > win then rem = win end
                local ticks = math.ceil(rem / (e.interval or 3) - 0.001)
                if ticks > 0 then
                    local amt = ticks * util.TickValue(r.guid, e.name)
                    if amt > 0 then
                        if e.dot then dot = dot + amt else hot = hot + amt end
                    end
                end
            end
        end
    end
    local cast, castN = 0, 0
    for src, c in pairs(fc.casts) do
        if not c.endTime or c.endTime <= now then
            -- Landed, or was interrupted with the event lost. Pruned here so
            -- a dropped UNIT_SPELLCAST_STOP can never strand a phantom heal.
            fc.casts[src] = nil
        elseif c.dest == r.guid and (win <= 0 or (c.endTime - now) <= win) then
            cast = cast + (c.amt or 0)
            castN = castN + 1
        end
    end
    -- Noise floor, as a share of the target's own health: two hundred points
    -- is a rounding error on a warrior and a real read on a mage, so the
    -- threshold has to be theirs rather than a flat number.
    local floor = (r.hpMax or 0) * (DB("ForecastMinPct", 2) / 100)
    if DB("ForecastDots", true) and dot > floor then r.fcDot = dot end
    if DB("ForecastHots", true) and hot > floor then r.fcHot = hot end
    if DB("ForecastCasts", true) and castN > 0 then
        r.fcCastN = castN
        if cast > floor then r.fcCast = cast end
    end
end

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
    -- No refresh threshold read here any more: which slots count as due is
    -- ResolveStrip's answer now (util.StripDue), because each entry can have
    -- a window of its own and the roll does.
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
    elseif util.StripDue(r) then
        -- Urgent rows sort by how long is actually left, not by health.
        -- Expiring while locked out is FADING rather than REFRESH: you can
        -- see it going and you cannot replace it.
        r.state = (lockLeft > 0) and "FADING" or "REFRESH"
        r.tLeft = soonest
        -- Tenths when the roll is the thing running out and it is inside the
        -- last three seconds: the row's big number is the most-read thing on
        -- the board, and rounding 2.4 up to "3s" there while the slot's own
        -- clock says 2.4 is the board disagreeing with itself again.
        if r.roll and r.roll.left and r.roll.left <= soonest + 0.001 and r.roll.left < 3 then
            r.mainText = string.format("%.1fs", math.max(0, r.roll.left))
        else
            r.mainText = string.format("%ds", math.max(0, math.ceil(soonest)))
        end
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

    -- The ROLL BAR. The druid board's drain strip has always been empty —
    -- there is no Weakened Soul and no Forbearance on a hot board — and it is
    -- exactly the instrument a rolling Lifebloom wants: a bar you read with
    -- the corner of your eye while looking somewhere else, rather than a
    -- radial sweep you have to focus on. It drains over the roll's own seven
    -- seconds and changes colour as the window opens, so "still fine",
    -- "refresh now" and "you are late" are three different things at a
    -- glance. Never claimed from a lockout: on the paladin board Forbearance
    -- is a harder fact than any hot, and this layer has no roll anyway.
    local rollBar = SDATA.LB_DISPLAY_BAR[DB("LBDisplay", "BOTH")]
    if rollBar and r.roll and r.roll.left and not r.wsLeft then
        r.wsLeft = math.max(0, r.roll.left)
        r.lockMax = r.roll.duration or 7
        r.wsTint = util.RollTint(r.roll)
    end

    -- Sort weight. A Rejuvenation about to fall off is one global to replace;
    -- a three-stack Lifebloom about to fall off is three, or the bloom you
    -- were holding. Off by default because it reorders a board people have
    -- learned to read, and on it simply halves the roll's sort key so it
    -- outranks a hot with the same seconds left rather than jumping the
    -- queue outright.
    if r.roll and r.roll.due and r.state == "REFRESH" and DB("LBPriority", false) then
        r.tLeft = math.min(r.tLeft or math.huge, (r.roll.left or 0) * 0.5)
    end

    ApplyAlertStates(r, now)
    return r
end

local function ResolveState(r, now)
    -- The forecast is chassis: pending dot damage, rolling hot healing and an
    -- inbound cast heal mean the same thing on every board, so it is resolved
    -- once here rather than in each layer's resolver. Ahead of them, because
    -- the layer resolvers are the ones that return early.
    util.Forecast(r, now)
    -- Overheal is chassis for the same reason, and it is the forecast's
    -- other half: one says what is about to be spent on this ally, the other
    -- says the last thing spent on them was thrown away.
    r.overheal = (not r.selfSpell) and util.OverhealAt(r.guid, now) or 0
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
    -- Is this ally a mana user? Purely a BUFF question — does Arcane
    -- Intellect / Divine Spirit / Blessing of Wisdom earn a slot on this row
    -- — and deliberately NOT the question the power strip asks. For a player
    -- it is a question of class (see MANA_CLASSES: a shapeshifted druid must
    -- not flap in and out of the buff strip every time it shifts); for a pet
    -- there is no class to ask, so it is the pet's own power bar, which also
    -- correctly excludes a hunter's focus and a shadowfiend's energy.
    -- What the STRIP draws is r.powerToken, read live a few lines below.
    local manaUser
    if owner then
        manaUser = (UnitPowerType and UnitPowerType(unit) == 0) or nil
    else
        manaUser = MANA_CLASSES[className or ""] or nil
    end
    local uname, urealm = UnitName(unit)
    local r = {
        guid = guid,
        unit = unit,
        name = uname or "?",
        -- Name plus realm when there is one: the identity a per-player blessing
        -- assignment is keyed by, and the only one that survives a session.
        -- GUIDs would too, but nobody can read one in a settings list.
        fullName = uname and (urealm and urealm ~= "" and (uname .. "-" .. urealm) or uname) or nil,
        petOwnerName = owner and UnitName(owner) or nil,
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
    -- The power strip: whatever this unit actually runs on, read live (the
    -- ticker repaints). Same contract, same clamp.
    --
    -- LIVE power type, not the class question manaUser answers. Those are two
    -- different questions and the file used to conflate them: "does Arcane
    -- Intellect apply to this row" must stay a class fact so a shapeshifted
    -- druid does not flap in and out of the buff strip, but "what is in this
    -- ally's bar right now" is exactly the thing that changes when they shift
    -- — a bear on rage is the whole reason to look at the strip.
    if UnitPower and UnitPowerMax and UnitPowerType then
        local ptype, ptoken = UnitPowerType(unit)
        ptype = ptype or 0
        local m, mMax = UnitPower(unit, ptype), UnitPowerMax(unit, ptype)
        if mMax and mMax > 0 then
            r.power = math.min(1, math.max(0, m / mMax))
            r.powerType = ptype
            r.powerToken = ptoken
        end
    end
    -- Their target's raid mark: watch the tank hold (or leave) skull
    if DB("ShowTargetMarks", true) and GetRaidTargetIndex then
        r.raidMark = GetRaidTargetIndex(unit .. "target")
    end
    -- Are they in combat? Two questions on one board, and both of them are
    -- about YOUR combat, not theirs: an ally who is fighting is a source of
    -- combat you can pick up with one heal (and combat is what a Sap cannot
    -- be opened on), and a board with no marks left on it is the board that
    -- says the drink you are about to sit down for will finish.
    --
    -- Read as a POSITIVE claim only — mark the ones who are fighting, never
    -- mark anyone as safe. UnitAffectingCombat answers off the unit's flags,
    -- and an ally too far out for the client to have the unit at all answers
    -- a quiet false; "in combat" is then still true whenever it is shown,
    -- while a drawn "out of combat" would have been a claim we cannot make.
    if DB("ShowCombat", true) and UnitAffectingCombat then
        r.inCombat = UnitAffectingCombat(unit) and true or false
    end
    -- What the battleground has made of them: the flag, and whichever ground
    -- powerup they picked up. Read out of the scan rather than off the unit —
    -- these are auras, and the aura pass is the only thing that has ever seen
    -- them — so the same positive-claim rule applies as everywhere else on
    -- this board: an ally too far out to scan wears the last thing we saw on
    -- them, and nobody is ever marked as NOT carrying.
    r.bgMarks = util.bgState[guid]
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
-- What hovering a click-cast row shows. Three answers, and none of them go
-- anywhere near the row's `unit` ATTRIBUTE — that is what makes @mouseover
-- macros work, it is set once out of combat in SetupSecureRows, and a tooltip
-- script cannot affect it. Turning the tooltip off costs you the tooltip and
-- nothing else.
--
--   FULL    the game's unit tooltip, with the board's own lines under it
--   EXTRAS  only the board's lines. The unit half is name, level, health and
--           a buff list — every one of which the row is already showing you,
--           which is the whole argument for this being the default.
--   OFF     nothing
local function BuildRowTooltip(self)
    local mode = DB("RowTooltip", "EXTRAS")
    if mode == "OFF" then return end
    if not self.unitToken or not UnitExists(self.unitToken) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    if mode == "FULL" then GameTooltip:SetUnit(self.unitToken) end
    -- The forecast's working: which dot, which hot, whose cast, and what each
    -- is worth. The bar answers "how much"; this answers "because of what",
    -- which is the half you need when the read looks wrong.
    if DB("ForecastTooltip", true) and DB("Forecast", "BAR") ~= "OFF" then
        util.ForecastTooltip(UnitGUID and UnitGUID(self.unitToken))
    end
    -- An empty tooltip is a grey box that follows the cursor for no reason.
    -- On the notes-only setting a quiet row genuinely has nothing to say, and
    -- saying nothing has to mean showing nothing.
    if (GameTooltip.NumLines and GameTooltip:NumLines() or 1) > 0 then
        GameTooltip:Show()
    else
        GameTooltip:Hide()
    end
end

-- Widget construction shared by ally rows (secure or plain) and the
-- personal-row pool (always plain)
local function BuildRowWidgets(row)
    row:SetSize(FrameWidth(), SDATA.ROW_H)

    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.stripe:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.stripe:SetWidth(SDATA.STRIPE_W)

    row.spellIcon = row:CreateTexture(nil, "ARTWORK")
    row.spellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.swipe = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
    if row.swipe.SetHideCountdownNumbers then row.swipe:SetHideCountdownNumbers(true) end
    util.TrackSweep(row.swipe)
    row.swipe:Hide()
    -- The shield slot's second clock. Its sweep is the shield's own thirty
    -- seconds; this ring is whether you may cast another one at this ally at
    -- all — their Weakened Soul, and the spell's cooldown if the client ever
    -- gives it one, whichever is longer. Two questions about one spell, on
    -- one icon, and the answer to the second used to live three pixels tall
    -- under the health bar where it competed with everything else.
    row.lockRing = util.MakeOutline(row)

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

    -- The blessing slot's assignment handle: a hit area over the combined
    -- blessing icon that opens "what should I be casting on them" as a menu,
    -- right where you are already looking. Pally Power's move, and the reason
    -- the assignment is worth having at all — a per-ally choice you can only
    -- reach through a settings page is a choice you make once and then live
    -- with, which is not what an arena wants.
    --
    -- OUT OF COMBAT ONLY, and that is a design decision rather than a caveat.
    -- An insecure frame over a secure row swallows every click in its own few
    -- pixels, so leaving this live in combat would quietly eat a click-cast
    -- binding at the exact moment it matters. Assignments are something you do
    -- at the gate; in combat the icon goes back to being an icon and every
    -- click on the row is your binding again. util.BlessMenuLive gates it.
    row.blessBtn = CreateFrame("Button", nil, row)
    row.blessBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.blessBtn.who = {}       -- refreshed per paint; never a live rowData ref
    -- Looked up through `util` at call time rather than bound here: these rows
    -- are built long after load, but the indirection means the handlers can
    -- live wherever they read best without a declaration-order trap.
    row.blessBtn:SetScript("OnClick", function(self, button) util.BlessSlotClick(self, button) end)
    row.blessBtn:SetScript("OnEnter", function(self) util.BlessSlotTooltip(self) end)
    row.blessBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.blessBtn:Hide()

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
        -- The ROLL slot's clock. A radial sweep is a fine way to say "there
        -- is time" and a useless way to say "there are two seconds": at
        -- fifteen pixels the last quarter of the arc is four pixels of
        -- movement, which is precisely the part of a Lifebloom that decides
        -- anything. The number takes the middle of the icon and the art
        -- becomes its background. Built on every slot so the roll can be any
        -- of them (the strip's order follows what you have tracked).
        h.clock = row:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        h.clock:SetJustifyH("CENTER")
        h.clock:Hide()
        -- Stack pips along the icon's bottom edge: three lights, so "am I at
        -- three" is answered by shape rather than by reading a digit. The
        -- digit remains for every other stacking aura on the strip.
        -- Mending's arrival flare: a square that starts at the icon's size
        -- and expands as it fades, which is the cheapest thing that reads as
        -- "it landed HERE" from the corner of your eye. Additive, so it
        -- brightens the art it sits on instead of covering it, and built on
        -- every slot because the strip's order follows what you have tracked.
        -- The strip slot's ring: the SPELL's cooldown, as opposed to the
        -- sweep, which is the aura's remaining duration. On Mending those are
        -- genuinely different facts — the object can be sitting on someone
        -- with twenty seconds left while you are still four seconds from
        -- being able to cast the next one.
        h.ring = util.MakeOutline(row)
        h.flare = row:CreateTexture(nil, "OVERLAY")
        h.flare:SetTexture("Interface\\Buttons\\WHITE8X8")
        if h.flare.SetBlendMode then h.flare:SetBlendMode("ADD") end
        h.flare:Hide()
        h.pips = {}
        for k = 1, SDATA.MAX_PIPS do
            local pip = row:CreateTexture(nil, "OVERLAY")
            pip:SetTexture("Interface\\Buttons\\WHITE8X8")
            pip:Hide()
            h.pips[k] = pip
        end
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
        t:SetSize(1, SDATA.BAR_H)
        t:SetPoint("TOPLEFT", n == 1 and row.bar or row.shieldSegs[n - 1], "TOPRIGHT", 0, 0)
        t:Hide()
        row.shieldSegs[n] = t
    end
    -- Forecast overlays. Created AFTER the shield segments and the fill, so
    -- within the same draw layer they sit on top of both (same-layer textures
    -- draw in creation order) — which is exactly what the pending-damage
    -- shade needs, since it eats into health the bar is already showing.
    --   fcHot    healing already rolling, chained past the absorbs like a
    --            segment: where the bar is going if nothing else happens
    --   fcCast   a heal in the air, chained past that in its own paler tint,
    --            so "rolling" and "someone is casting" stay tellable apart
    --   fcDot    queued dot damage, retreating LEFT from the fill's edge:
    --            the part of the bar that is already spoken for
    --   fcTickH / fcTickD  the same two answers as hairlines, for the mode
    --            that wants the projection without the paint
    row.fcHot = row:CreateTexture(nil, "ARTWORK")
    row.fcHot:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.fcHot:Hide()
    row.fcCast = row:CreateTexture(nil, "ARTWORK")
    row.fcCast:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.fcCast:Hide()
    row.fcDot = row:CreateTexture(nil, "ARTWORK")
    row.fcDot:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.fcDot:Hide()
    row.fcTickH = row:CreateTexture(nil, "OVERLAY")
    row.fcTickH:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.fcTickH:Hide()
    row.fcTickD = row:CreateTexture(nil, "OVERLAY")
    row.fcTickD:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.fcTickD:Hide()
    row.fcText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.fcText:SetJustifyH("CENTER")
    row.fcText:Hide()

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

    -- The combat mark: the client's OWN crossed swords, the quadrant of
    -- UI-StateIcon the stock player frame lights when you are in combat.
    -- Borrowed rather than drawn, and rather than picked out of the icon set,
    -- because it is the glyph the player already reads as "fighting" — it is
    -- on their own portrait every pull — and a mark you have to learn is a
    -- mark you check late. The board's own chrome is drawn from quads
    -- elsewhere; a diagonal is the one shape that technique cannot promise.
    row.combatMark = row:CreateTexture(nil, "OVERLAY")
    row.combatMark:SetTexture(SDATA.COMBAT_TEXTURE)
    local ct = SDATA.COMBAT_TEXCOORD
    row.combatMark:SetTexCoord(ct[1], ct[2], ct[3], ct[4])
    row.combatMark:Hide()

    -- The battleground marks, beside it and built from the same measurements:
    -- same size, same right-edge cluster, same stride. They are spell ICONS
    -- rather than a cut of the client's chrome, because unlike "in combat"
    -- there is no glyph the player already reads as "carrying the flag" —
    -- but the flag banner and the berserk spiral ARE the art they have been
    -- clicking off the ground since Warsong Gulch opened, so the icon is
    -- still the thing they know rather than a shape to learn.
    row.bgMarks = {}
    for n = 1, SDATA.MAX_BG_MARKS do
        local t = row:CreateTexture(nil, "OVERLAY")
        local bt = SDATA.BG_TEXCOORD
        t:SetTexCoord(bt[1], bt[2], bt[3], bt[4])
        t:Hide()
        row.bgMarks[n] = t
    end

    row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.left:SetJustifyH("LEFT")
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetJustifyH("RIGHT")

    -- Overheal ring: four hairlines just inside the row's edges. A RING and
    -- not a fill, because the row already spends its fill, its stripe and its
    -- bar colours on other things, and because healing spilling over the edge
    -- of a full bar is what the shape is meant to say. The left edge starts
    -- past the state stripe rather than over it — the stripe is a channel of
    -- its own and covering it would trade one answer for another.
    row.ohGlow = {}
    for n = 1, 4 do
        local t = row:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:Hide()
        row.ohGlow[n] = t
    end
    -- The low-health ring: the same hairline one pixel further in, in red,
    -- for an ally who wants a Renew and has none of ours on them.
    --
    -- Its OWN four textures rather than a second colour on the ring above,
    -- which is how this was first built. Sharing the frame meant the two had
    -- to take turns, and while either was showing there was no way — for the
    -- board or for the person reading it — to know what the other would have
    -- said. Four textures a row is a cheap price for two facts that can both
    -- be true at once and are never the same news.
    row.needGlow = {}
    for n = 1, 4 do
        local t = row:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:Hide()
        row.needGlow[n] = t
    end

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
    -- An ally row and a personal row are the same widget built by the same
    -- constructor, so nothing about the frame says which pool it came from.
    -- This does — which is what lets anything counting the ALLY board (the
    -- harness, for one) tell your own Ice Barrier row apart from a teammate.
    row.personal = true
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
    row.bg:SetPoint("TOPLEFT", row, "TOPLEFT", SDATA.STRIPE_W + 2, 0)
    row.bg:SetHeight(SDATA.ABILITY_H)
    row.bg:Hide()
    row.cells = {}
    for n = 1, SDATA.MAX_ABILITY_CELLS do
        local c = {}
        local x = SDATA.STRIPE_W + 3 + (n - 1) * (SDATA.ABILITY_H - 1)
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
    local rowH = compact and SDATA.PERSONAL_ROW_H or SDATA.ROW_H
    local barH = compact and SDATA.PERSONAL_BAR_H or SDATA.BAR_H
    local wsH = compact and SDATA.PERSONAL_WS_H or SDATA.WS_H
    -- The power strip's own height, so it can be a hairline under the health
    -- bar or a second bar in its own right. The row does not grow with it:
    -- the stack is centred in a fixed row (see barTop below), so a taller
    -- strip eats into the padding, not into Max Rows.
    -- Clamped to what is left after the main bar and the lockout drain: the
    -- stack is centred in a FIXED row height, so an unclamped strip would
    -- push the bars up out of their own row and into the one above.
    local healthH = math.max(1, math.min(DB("PowerBarHeight", SDATA.HEALTH_H), rowH - barH - wsH))
    -- Health is the main bar on every layer now; the underlay slot carries the
    -- ally's POWER — mana, rage, energy, focus, a pet's happiness — on every
    -- layer including the priest board, which used to spend the slot on
    -- nothing. Reserved from the SETTING alone, never from what this
    -- particular unit runs on: the row's geometry has to be identical for a
    -- rogue and a mage or the board jitters as the sort reorders it, and a
    -- secure row cannot be re-laid-out mid-combat at all.
    local showHealth = (not compact) and util.PowerMode() ~= "OFF"
    local showUnitIcon = not compact and (mode == "CLASS_ICON" or mode == "PORTRAIT"
        or mode == "ICON_NAME" or mode == "ICON_PORTRAIT" or mode == "SPEC"
        or mode == "SPEC_PORTRAIT")
    local showUnitIcon2 = not compact and (mode == "ICON_PORTRAIT" or mode == "SPEC_PORTRAIT")
    local showName = compact or (mode == "NAME" or mode == "ICON_NAME")

    row:SetSize(width, rowH)
    local x = SDATA.STRIPE_W + 3
    -- The row's anatomy, recorded as it is laid out, so the settings page can
    -- draw an honest diagram of where the width goes (CommanderPartyFrames_RowBlueprint)
    local bp = { slots = {} }
    local function Slot(kind, w, label)
        bp.slots[#bp.slots + 1] = { kind = kind, x = x, w = w, label = label }
    end

    -- The ally-buff strip leads the row. Slots are reserved from the SETTINGS,
    -- not from what is currently up, so the row's geometry is stable for a
    -- whole fight — which is also what keeps Click-Cast legal, since a secure
    -- row cannot be re-laid-out mid-combat.
    local buffSlots = (not compact and showIcon) and #SDATA.BUFF_ACTIVE or 0
    local blessSlot
    for n = 1, SDATA.MAX_BUFF_SLOTS do
        local b = row.buffs[n]
        if n <= buffSlots then
            b.icon:ClearAllPoints()
            b.icon:SetSize(SDATA.SMALL_ICON, SDATA.SMALL_ICON)
            b.icon:SetPoint("LEFT", row, "LEFT", x, 0)
            b.cd:ClearAllPoints()
            b.cd:SetAllPoints(b.icon)
            if SDATA.BUFF_ACTIVE[n] and SDATA.BUFF_ACTIVE[n].combined then blessSlot = b end
            Slot("buff", SDATA.SMALL_ICON, (SDATA.BUFF_ACTIVE[n] and SDATA.BUFF_ACTIVE[n].label) or "buff")
            x = x + SDATA.SMALL_ICON + 3
        else
            b.icon:Hide(); b.cd:Hide()
        end
    end
    -- The assignment hit area sits exactly on the combined blessing icon.
    -- Parked here rather than shown: whether it is LIVE is a combat question
    -- answered per paint, and layout only runs when the strip's shape changes.
    if row.blessBtn then
        row.blessBtn:ClearAllPoints()
        if blessSlot then
            row.blessBtn:SetAllPoints(blessSlot.icon)
        else
            row.blessBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.blessBtn:SetSize(SDATA.SMALL_ICON, SDATA.SMALL_ICON)
        end
        row.blessBtn.slot = blessSlot
    end

    -- The layer's OWN status slot, which is a different job from the buff
    -- strip above: the priest board's Power Word: Shield tracker, or a
    -- personal row's spell icon. The two buff layers have nothing left to put
    -- here now that their upkeep moved to the strip, so they spend no width.
    local ownSlot = showIcon and (compact or not SDATA.HEALTH_LAYERS[layer or ""])
    if ownSlot then
        local iconSize = compact and SDATA.PERSONAL_ICON or SDATA.ICON_SIZE
        row.spellIcon:ClearAllPoints()
        row.spellIcon:SetSize(iconSize, iconSize)
        row.spellIcon:SetPoint("LEFT", row, "LEFT", x, 0)
        row.spellIcon:Show()
        row.swipe:ClearAllPoints()
        row.swipe:SetAllPoints(row.spellIcon)
        util.AnchorOutline(row.lockRing, row.spellIcon)
        row._ringSize = iconSize
        Slot("own", iconSize, compact and "spell" or "shield")
        x = x + iconSize + 3
    else
        row.spellIcon:Hide()
        row.swipe:Hide()
        util.HideOutline(row.lockRing)
    end
    -- Second status slot: an incoming priest shield on the mage board, or
    -- Freeze on the elemental's compact row.
    if showIcon then
        if (layer == "INT" and not compact) or secondSlot then
            local slotSize = compact and SDATA.PERSONAL_ICON or SDATA.SMALL_ICON
            row.inShield:ClearAllPoints()
            row.inShield:SetSize(slotSize, slotSize)
            row.inShield:SetPoint("LEFT", row, "LEFT", x, 0)
            row.inShieldCd:ClearAllPoints()
            row.inShieldCd:SetAllPoints(row.inShield)
            Slot("inshield", slotSize, secondSlot and "freeze" or "incoming")
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
            h.icon:SetSize(SDATA.SMALL_ICON, SDATA.SMALL_ICON)
            h.icon:SetPoint("LEFT", row, "LEFT", x, 0)
            h.cd:ClearAllPoints()
            h.cd:SetAllPoints(h.icon)
            h.count:ClearAllPoints()
            h.count:SetPoint("BOTTOMRIGHT", h.icon, "BOTTOMRIGHT", 2, -1)
            -- The paint moves this anchor when pips are under it; a relayout
            -- has just put it back, so the memo of where it sits goes too.
            h._countPos = nil
            -- The clock sits ON the icon, nudged up by a pixel so the pip
            -- row along the bottom edge does not crowd the digits.
            h.clock:ClearAllPoints()
            h.clock:SetPoint("CENTER", h.icon, "CENTER", 0, 1)
            -- Pip width follows the slot's OWN pip count, so a five-charge
            -- Mending row and a three-stack Lifebloom row both fill the same
            -- fifteen pixels edge to edge instead of one of them trailing off
            -- the icon. Laid out for whatever this slot's def asks for; the
            -- rest are simply never shown.
            h.flare:ClearAllPoints()
            h.flare:SetPoint("CENTER", h.icon, "CENTER", 0, 0)
            util.AnchorOutline(h.ring, h.icon)
            local def = SDATA.STRIP_ACTIVE[n]
            local pipN = (def and def.maxStacks) or 3
            local pipW = math.max(1, math.floor((SDATA.SMALL_ICON - 2 - (pipN - 1)) / pipN))
            for k = 1, SDATA.MAX_PIPS do
                local pip = h.pips[k]
                pip:ClearAllPoints()
                pip:SetSize(pipW, 2)
                pip:SetPoint("BOTTOMLEFT", h.icon, "BOTTOMLEFT",
                    1 + (k - 1) * (pipW + 1), 1)
            end
            Slot("strip", SDATA.SMALL_ICON, (def and def.label) or "hot")
            x = x + SDATA.SMALL_ICON + 2
        else
            h.icon:Hide(); h.cd:Hide(); h.count:Hide(); h.clock:Hide()
            h.flare:Hide(); util.HideOutline(h.ring)
            for k = 1, SDATA.MAX_PIPS do h.pips[k]:Hide() end
        end
    end

    if showUnitIcon then
        row.unitIcon:ClearAllPoints()
        row.unitIcon:SetSize(SDATA.ICON_SIZE, SDATA.ICON_SIZE)
        row.unitIcon:SetPoint("LEFT", row, "LEFT", x, 0)
        row.unitIcon:Show()
        Slot("unit", SDATA.ICON_SIZE, (mode == "PORTRAIT") and "portrait" or ((mode == "SPEC" or mode == "SPEC_PORTRAIT") and "spec" or "class"))
        x = x + SDATA.ICON_SIZE + 3
    else
        row.unitIcon:Hide()
    end
    if showUnitIcon2 then
        row.unitIcon2:ClearAllPoints()
        row.unitIcon2:SetSize(SDATA.ICON_SIZE, SDATA.ICON_SIZE)
        row.unitIcon2:SetPoint("LEFT", row, "LEFT", x, 0)
        row.unitIcon2:Show()
        Slot("unit2", SDATA.ICON_SIZE, "portrait")
        x = x + SDATA.ICON_SIZE + 3
    else
        row.unitIcon2:Hide()
    end

    if showName then
        local nw = compact and SDATA.PERSONAL_NAME_W
            or ((mode == "ICON_NAME") and SDATA.SHORT_NAME_W or SDATA.NAME_W)
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", row, "LEFT", x, 0)
        row.name:SetWidth(nw)
        row.name:Show()
        Slot("name", nw, "name")
        x = x + nw + 3
    else
        row.name:Hide()
    end

    -- Reserve room at the right for the marks: what this ally IS right now
    -- that the bar cannot say. Two layouts. GRID (the default) stacks every
    -- mark into ONE seat, a two-by-two block with a fixed cell per meaning:
    -- their target's raid mark top-left, the crossed swords top-right, the
    -- flag bottom-left, the powerup bottom-right -- so four marks at once
    -- still read, and the seat costs 21 pixels instead of the 64 the old row
    -- of seats did. ROW is that old layout: one seat per mark, side by side.
    -- Either way every seat is reserved from the SETTING, never from what is
    -- up, so the bar never twitches mid-fight (and Click-Cast stays legal).
    local marksOn = not compact and DB("ShowTargetMarks", true)
    local combatOn = not compact and DB("ShowCombat", true)
    local bgWanted = (not compact) and DB("ShowBGBuffs", true)
    local grid = DB("MarkLayout", "GRID") == "GRID"
    local rightReserve = 0
    local bgSlots = 0
    row._markGrid = grid and true or false
    if grid then
        if marksOn or combatOn or bgWanted then
            local cell, seat = SDATA.MARK_CELL, SDATA.MARK_SEAT
            local right = -(SDATA.PAD - 2)
            local colR, colL = right - cell / 2, right - cell - 1 - cell / 2
            local rowT, rowB = cell / 2 + 0.5, -(cell / 2 + 0.5)
            rightReserve = seat + 3
            row.raidMark:ClearAllPoints()
            row.raidMark:SetSize(cell, cell)
            row.raidMark:SetPoint("CENTER", row, "RIGHT", colL, rowT)
            row.combatMark:ClearAllPoints()
            row.combatMark:SetSize(cell, cell)
            row.combatMark:SetPoint("CENTER", row, "RIGHT", colR, rowT)
            -- The battleground cells are part of the seat whether or not you
            -- are in one: the width is spent on the block, not per mark, so
            -- there is nothing to hand back by zoning out
            bgSlots = bgWanted and SDATA.MAX_BG_MARKS or 0
            local t1, t2 = row.bgMarks[1], row.bgMarks[2]
            t1:ClearAllPoints(); t1:SetSize(cell, cell); t1:SetPoint("CENTER", row, "RIGHT", colL, rowB)
            t2:ClearAllPoints(); t2:SetSize(cell, cell); t2:SetPoint("CENTER", row, "RIGHT", colR, rowB)
            for n = 3, SDATA.MAX_BG_MARKS do row.bgMarks[n]:Hide() end
        end
        if not marksOn then row.raidMark:Hide() end
        if not combatOn then row.combatMark:Hide() end
        if bgSlots == 0 then for n = 1, SDATA.MAX_BG_MARKS do row.bgMarks[n]:Hide() end end
    else
        rightReserve = marksOn and 16 or 0
        if marksOn then
            row.raidMark:ClearAllPoints()
            row.raidMark:SetSize(14, 14)
            row.raidMark:SetPoint("RIGHT", row, "RIGHT", -(SDATA.PAD - 2), 0)
        else
            row.raidMark:Hide()
        end
        -- And beside it, the combat mark, reserved from the SETTING like every
        -- other slot on this row: what it holds comes and goes with every pull,
        -- and a row that re-laid itself out for that would be a row whose bar
        -- twitched all fight -- and one Click-Cast could not touch in combat.
        if combatOn then
            row.combatMark:ClearAllPoints()
            row.combatMark:SetSize(SDATA.COMBAT_MARK, SDATA.COMBAT_MARK)
            row.combatMark:SetPoint("RIGHT", row, "RIGHT",
                -(SDATA.PAD - 2) - (marksOn and 16 or 0), 0)
            rightReserve = rightReserve + SDATA.COMBAT_MARK + 3
        else
            row.combatMark:Hide()
        end
        -- ...and beside THAT, the battleground marks. Reserved from the zone as
        -- well as the setting (see util.InBattleground): every other slot on this row
        -- holds itself open because what fills it comes and goes mid-fight, but
        -- these cannot light at all outside a battleground, and a permanent
        -- 32-pixel hole in the health bar of every arena row is not a trade the
        -- board should make on the player's behalf. Zoning is out of combat, so
        -- the relayout it costs is free.
        bgSlots = bgWanted and (util.InBattleground() or testUntil > 0) and SDATA.MAX_BG_MARKS or 0
        for n = 1, SDATA.MAX_BG_MARKS do
            local t = row.bgMarks[n]
            if n <= bgSlots then
                t:ClearAllPoints()
                t:SetSize(SDATA.COMBAT_MARK, SDATA.COMBAT_MARK)
                t:SetPoint("RIGHT", row, "RIGHT",
                    -(SDATA.PAD - 2) - (marksOn and 16 or 0) - (combatOn and (SDATA.COMBAT_MARK + 3) or 0)
                        - (n - 1) * (SDATA.COMBAT_MARK + 3), 0)
            else
                t:Hide()
            end
        end
        rightReserve = rightReserve + bgSlots * (SDATA.COMBAT_MARK + 3)
    end
    local barX = x
    local barW = width - barX - SDATA.PAD - rightReserve
    if barW < 40 then barW = 40 end
    -- Vertical stack: absorb bar on top, optional health, then WS drain
    local barTop = -(rowH - barH - (showHealth and healthH or 0) - wsH) / 2
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
        row.healthBar:SetSize(barW, healthH)
        y = y - healthH
    else
        row.healthBar:Hide()
    end
    row.wsBar:ClearAllPoints()
    row.wsBar:SetPoint("TOPLEFT", row, "TOPLEFT", barX, y)
    row.wsBar:SetSize(barW, wsH)

    -- The overheal ring, sized with the row. One pixel thick and one pixel in
    -- on three sides; on the left it clears the state stripe, so the ring
    -- frames the row's CONTENT and the stripe still reads as itself. Anchored
    -- rather than sized, so it follows the frame width without a second pass.
    for _, ring in ipairs({ { 1, row.ohGlow }, { 2, row.needGlow } }) do
        local ins, th, g = ring[1], 1, ring[2]
        g[1]:ClearAllPoints()
        g[1]:SetPoint("TOPLEFT", row, "TOPLEFT", SDATA.STRIPE_W + ins, -ins)
        g[1]:SetPoint("TOPRIGHT", row, "TOPRIGHT", -ins, -ins)
        g[1]:SetHeight(th)
        g[2]:ClearAllPoints()
        g[2]:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", SDATA.STRIPE_W + ins, ins)
        g[2]:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -ins, ins)
        g[2]:SetHeight(th)
        g[3]:ClearAllPoints()
        g[3]:SetPoint("TOPLEFT", g[1], "BOTTOMLEFT", 0, 0)
        g[3]:SetPoint("BOTTOMLEFT", g[2], "TOPLEFT", 0, 0)
        g[3]:SetWidth(th)
        g[4]:ClearAllPoints()
        g[4]:SetPoint("TOPRIGHT", g[1], "BOTTOMRIGHT", 0, 0)
        g[4]:SetPoint("BOTTOMRIGHT", g[2], "TOPRIGHT", 0, 0)
        g[4]:SetWidth(th)
    end

    row.left:ClearAllPoints()
    row.left:SetPoint("LEFT", row.barBG, "LEFT", 3, 0)
    row.right:ClearAllPoints()
    row.right:SetPoint("RIGHT", row.barBG, "RIGHT", -3, 0)
    -- The forecast number takes the bar's centre, the one span the state word
    -- (left) and the health percent (right) both leave alone.
    row.fcText:ClearAllPoints()
    row.fcText:SetPoint("CENTER", row.barBG, "CENTER", 0, 0)


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
    row._combatSlot = combatOn and true or false
    row._bgSlots = bgSlots
    row._wsH = wsH
    row._sig = sig
    bp.width, bp.rowH, bp.pad, bp.stripeW = width, rowH, SDATA.PAD, SDATA.STRIPE_W
    bp.barX, bp.barW, bp.barH = barX, barW, barH
    bp.healthH = showHealth and healthH or 0
    bp.grid = grid
    if grid then
        bp.seat = rightReserve > 0 and SDATA.MARK_SEAT or 0
        bp.cell = SDATA.MARK_CELL
        bp.marks, bp.combat, bp.bg, bp.bgPossible = 0, 0, 0, 0
        bp.seatMarks = marksOn and true or false
        bp.seatCombat = combatOn and true or false
        bp.seatBg = bgWanted and true or false
    else
        bp.seat = 0
        bp.marks = marksOn and 16 or 0
        bp.combat = combatOn and (SDATA.COMBAT_MARK + 3) or 0
        bp.bg = bgSlots * (SDATA.COMBAT_MARK + 3)
        -- What the battleground slots WOULD cost when zoning in, for a diagram
        -- drawn at the flight master
        bp.bgPossible = bgWanted and (SDATA.MAX_BG_MARKS * (SDATA.COMBAT_MARK + 3)) or 0
    end
    bp.markW, bp.markGap = SDATA.COMBAT_MARK, 3
    row._blueprint = bp
end

local function LayoutSig(width)
    return width .. "|" .. tostring(DB("ShowSpellIcon", true)) .. "|"
        .. tostring(DB("ShowCombat", true)) .. "|"
        .. tostring(DB("ShowBGBuffs", true)
            and (util.InBattleground() or testUntil > 0)) .. "|"
        .. DB("UnitDisplay", "CLASS_ICON")
        .. "|" .. tostring(DB("ShowDispels", false)) .. "|" .. DB("DispelMaxIcons", 3)
        .. "|" .. DB("DispelIconSize", 16)
        .. "|" .. util.PowerMode() .. "|" .. DB("PowerBarHeight", SDATA.HEALTH_H)
        .. "|" .. tostring(DB("ShowTargetMarks", true)) .. "|" .. DB("MarkLayout", "GRID")
        .. "|" .. DB("BarTexture", "FLAT") .. "|" .. SDATA.BUFF_SIG
end

-- The anatomy of an ally row under the CURRENT settings, for the settings
-- page's diagram. Laid out on a scratch row that never joins the board, with
-- the very same LayoutRow every live row goes through, so the diagram cannot
-- disagree with the plate: each slot's x and width, where the bar starts and
-- how wide it is, and what is reserved to its right (the target mark, the
-- combat mark, the battleground slots) -- the "blank space" that is really
-- three held-open seats.
-- (The scratch row lives in SDATA, not a chunk local: this file sits at Lua's
-- 200-local ceiling and one more `local` here fails the whole file to load.)
function CommanderPartyFrames_RowBlueprint()
    if not root then return nil end
    local previewRow = SDATA.previewRow
    if not previewRow then
        previewRow = CreateFrame("Frame", nil, root)
        BuildRowWidgets(previewRow)
        previewRow:Hide()
        -- Says what it is, so anything counting rows (the harness) can skip it
        previewRow.scratch = true
        SDATA.previewRow = previewRow
    end
    local width = FrameWidth()
    local ok = pcall(LayoutRow, previewRow, width, LayoutSig(width))
    previewRow:Hide()
    return ok and previewRow._blueprint or nil
end

-- Player rows stride taller when each carries an ability strip beneath it
local function RowStride()
    local s = SDATA.ROW_H + SDATA.ROW_GAP
    if DB("ShowAbilityBar", true) then s = s + SDATA.ABILITY_H + 1 end
    return s
end

-- Height the personal block takes above the ally board. Growing DOWN, `base`
-- pushes the ally rows past it; growing UP the ally board already starts at
-- the bottom and the personal block stacks on top of it, so base is unused.
local function PersonalStride()
    return SDATA.PERSONAL_ROW_H + SDATA.ROW_GAP
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
            -topOffset - (base or 0) - (index - 1) * RowStride() - SDATA.ROW_H - 1)
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
        util.HideOutline(row.lockRing)
        row.inShield:Hide(); row.inShieldCd:Hide()
        row.bar:Hide(); row.barBG:Hide(); row.healthBar:Hide(); row.wsBar:Hide()
        row.markTick:Hide(); row.raidMark:Hide()
        row.combatMark:Hide()
        for i = 1, SDATA.MAX_BG_MARKS do row.bgMarks[i]:Hide() end
        row.fcHot:Hide(); row.fcCast:Hide(); row.fcDot:Hide()
        row.fcTickH:Hide(); row.fcTickD:Hide(); row.fcText:Hide()
        for i = 1, SDATA.MAX_SHIELD_SEGS do row.shieldSegs[i]:Hide() end
        for i = 1, SDATA.MAX_STRIP_ICONS do
            local h = row.strip[i]
            h._exp = nil
            h.icon:Hide(); h.cd:Hide(); h.count:Hide(); h.clock:Hide()
            h.flare:Hide(); util.HideOutline(h.ring)
            for k = 1, SDATA.MAX_PIPS do h.pips[k]:Hide() end
        end
        row.left:SetText(""); row.right:SetText(""); row.glow:Hide(); row.flash:Hide()
        for i = 1, 4 do row.ohGlow[i]:Hide(); row.needGlow[i]:Hide() end
        row.tgtCount:Hide()
        row.stripe:SetAlpha(0)
        if row.blessBtn then row.blessBtn:Hide() end
        return
    end
    row:SetAlpha(r.outOfRange and util.RangeFadeAlpha() or 1)
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

    -- The blessing slot's assignment handle. Everything it needs is copied off
    -- the row data rather than referenced: rowData tables are recycled between
    -- passes, and a menu that read one a frame later would be assigning a
    -- blessing to whoever inherited the table.
    local bb = row.blessBtn
    if bb then
        local slot = bb.slot
        local live = slot and slot.icon:IsShown() and util.BlessMenuLive()
        if live then
            bb.assignKey = util.BlessAssignKey(r)
            bb.classKey = util.BlessClassKey(r)
            bb.rowName = r.isPet and (r.name .. " (pet)") or r.name
            bb.blessWant, bb.blessHave, bb.blessWhy = r.blessWant, r.blessHave, r.blessWantWhy
            local who = bb.who
            who.class, who.isPet, who.manaUser = r.class, r.isPet, r.manaUser
            bb:Show()
        else
            bb:Hide()
        end
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
            util.HideOutline(row.lockRing)
        elseif SDATA.STRIP_STATE_LAYERS[layer or ""] and not r.selfSpell then
            -- The druid and paladin boards have nothing to put here: their
            -- upkeep all lives on the strips. The priest board is NOT in this
            -- branch even though it has a strip — its own status slot is the
            -- Power Word: Shield tracker, which is the whole board.
            row.spellIcon:Hide(); row.swipe:Hide()
            util.HideOutline(row.lockRing)
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
            -- The elemental's portrait is not a spell you cast at anyone
            util.HideOutline(row.lockRing)
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
            -- One ring, both gates. "Can I shield this person" has two
            -- answers in TBC and they are asked together: their Weakened Soul
            -- has to be gone, and the spell has to be off cooldown (which it
            -- always is on this client — read anyway, because a ring that
            -- silently ignores a real cooldown is worse than no ring). The
            -- longer of the two is the honest wait, so that is what is drawn,
            -- and an empty ring means go.
            --
            -- Deliberately NOT the shield's own duration: that is what the
            -- sweep behind it already says. Two clocks on one icon are only
            -- worth the confusion when they answer different questions.
            if DB("ShieldLockRing", true) and not r.dead then
                local lockLeft = r.wsLeft or 0
                local lockDur = (r.lockMax and r.lockMax > 0)
                    and r.lockMax or SDATA.WEAKENED_SOUL_MAX
                if (util.pwsCdLeft or 0) > lockLeft then
                    lockLeft, lockDur = util.pwsCdLeft, util.pwsCdDur
                end
                if lockLeft > 0 and lockDur > 0 then
                    util.DrawOutline(row.lockRing, row._ringSize or SDATA.ICON_SIZE,
                        lockLeft / lockDur, SDATA.RING_LOCK)
                else
                    util.HideOutline(row.lockRing)
                end
            else
                util.HideOutline(row.lockRing)
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
                    h.clock:Hide()
                    for k = 1, SDATA.MAX_PIPS do h.pips[k]:Hide() end
                    util.GhostIcon(h.icon, e.icon)
                    -- The other end of a hop. This slot is empty and would
                    -- normally sit at the dark placeholder tint; for half a
                    -- second after the object leaves it fades DOWN to that
                    -- from something lit, so the row it went from and the row
                    -- it went to light a beat apart and the movement is
                    -- something you see rather than something you infer.
                    if (e.trail or 0) > 0 then
                        local g, f = SDATA.GHOST_TINT, e.trail
                        local c = util.ChargeTint(e)
                        if h.icon.SetDesaturated then h.icon:SetDesaturated(false) end
                        h.icon:SetVertexColor(
                            g[1] + (c[1] - g[1]) * f,
                            g[2] + (c[2] - g[2]) * f,
                            g[3] + (c[3] - g[3]) * f,
                            (g[4] or 1) + (1 - (g[4] or 1)) * f)
                    end
                    h.flare:Hide()
                else
                    h.icon:SetTexture(e.icon)
                    -- Inside the refresh window the slot itself says so. On
                    -- the two layers whose STATE reads the strip this only
                    -- agrees with the row colour; on the priest board, whose
                    -- state is its shield, the slot is the ONLY thing that can
                    -- tell you a Renew is about to drop — which is the job the
                    -- old right-edge Renew icon existed to do.
                    -- The roll wears its own three-state tint rather than
                    -- the strip's one amber, and pulses only once it is
                    -- actually LATE. A slot that pulses through the whole
                    -- refresh window pulses most of a seven-second buff's
                    -- life, which is how Lifebloom became invisible on this
                    -- strip in the first place — an alarm that is always on
                    -- is not an alarm.
                    local rollClock = e.roll and SDATA.LB_DISPLAY_CLOCK[DB("LBDisplay", "BOTH")]
                    if rollClock then
                        local c = util.RollTint(e)
                        if e.late and DB("RenewFlash", true) then
                            h.icon:SetVertexColor(c[1], c[2], c[3],
                                0.55 + 0.45 * math.abs(math.sin(now * 5)))
                        else
                            h.icon:SetVertexColor(c[1], c[2], c[3], 1)
                        end
                    elseif e.due and DB("RenewFlash", true) then
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
                    -- The roll's clock, in place of the sweep's last unreadable
                    -- quarter. Tenths under three seconds, because that is the
                    -- range where a tenth is the difference between a refresh
                    -- and a bloom; whole seconds above it, where it is not.
                    if rollClock and e.left then
                        local c = util.RollTint(e)
                        h.clock:SetTextColor(c[1], c[2], c[3])
                        if e.left < 3 then
                            h.clock:SetText(string.format("%.1f", math.max(0, e.left)))
                        else
                            h.clock:SetText(string.format("%d", math.ceil(e.left)))
                        end
                        h.clock:Show()
                        -- With a number on the icon the sweep is noise behind
                        -- it, and on the roll it was never the readable half
                        h.cd:Hide()
                    else
                        h.clock:Hide()
                    end
                    -- Stacks. The roll shows PIPS — three lights read as a
                    -- shape, and "am I at three" is the question you ask a
                    -- hundred times a fight. Everything else keeps the digit,
                    -- and only once it actually stacks: a "1" on every row is
                    -- noise.
                    --
                    -- Mending gets pips for the opposite reason. Its number
                    -- only ever goes DOWN, and what you want off it is not
                    -- "which number is this" but "how much of it is left" —
                    -- five lights emptying is that question answered as a
                    -- shape, and the tint reddens as the last charge nears.
                    local pips = 0
                    if rollClock and e.roll and DB("LBStackPips", true) then
                        pips = e.maxStacks or 3
                    elseif e.charges and DB("PoMPips", true) then
                        pips = e.maxStacks or 5
                    end
                    for k = 1, SDATA.MAX_PIPS do
                        local pip = h.pips[k]
                        if k <= pips then
                            if k <= (e.stacks or 0) then
                                local c = e.charges and util.ChargeTint(e)
                                    or util.RollTint(e)
                                pip:SetVertexColor(c[1], c[2], c[3], 1)
                            else
                                pip:SetVertexColor(0.25, 0.25, 0.28, 0.9)
                            end
                            pip:Show()
                        else
                            pip:Hide()
                        end
                    end
                    -- Arrival. Starts at the icon's own size and expands as
                    -- it fades, so the pull is the MOVEMENT rather than a
                    -- colour you then have to interpret. Sized every frame
                    -- from the decay, which is also how it puts itself away.
                    if (e.hop or 0) > 0 then
                        local f = e.hop
                        local grow = SDATA.SMALL_ICON * (1 + 0.85 * (1 - f))
                        local c = util.ChargeTint(e)
                        h.flare:SetSize(grow, grow)
                        h.flare:SetVertexColor(c[1], c[2], c[3], 0.5 * f)
                        h.flare:Show()
                    else
                        h.flare:Hide()
                    end
                    -- The digit, which now rides ALONGSIDE the pips rather
                    -- than instead of them. The lights answer "how much is
                    -- left" as a shape at a glance; the number answers "how
                    -- much exactly" when you actually look — two different
                    -- readings of the same fact, and on a five-charge object
                    -- both are worth having.
                    --
                    -- CHARGES only. Charges show their number all the way
                    -- down to one, because on a countdown the one is the
                    -- interesting value, and the pips and the digit are
                    -- answering different questions rather than competing.
                    --
                    -- The roll deliberately does not follow: Lifebloom's pips
                    -- REPLACED its digit on purpose, because "am I at three"
                    -- is a shape you read a hundred times a fight and a
                    -- number you would have to read. That is a decision the
                    -- druid board already made, and a five-charge object
                    -- wanting both is not a reason to reopen it.
                    local showCount = e.charges and (e.stacks or 0) >= 1
                        or (pips == 0 and (e.stacks or 0) > 1)
                    if showCount then
                        -- With pips along the bottom edge the digit has to
                        -- leave it, or the two draw on top of each other.
                        -- Re-anchored only when it actually moves.
                        local pos = pips > 0 and "TOP" or "BOTTOM"
                        if h._countPos ~= pos then
                            h._countPos = pos
                            h.count:ClearAllPoints()
                            if pos == "TOP" then
                                h.count:SetPoint("TOPRIGHT", h.icon, "TOPRIGHT", 2, 1)
                            else
                                h.count:SetPoint("BOTTOMRIGHT", h.icon, "BOTTOMRIGHT", 2, -1)
                            end
                        end
                        -- Tinted with the pips so the two never disagree: a
                        -- red last pip beside a white "1" would be the slot
                        -- saying the same thing in two moods.
                        if e.charges then
                            local c = util.ChargeTint(e)
                            h.count:SetTextColor(c[1], c[2], c[3])
                        else
                            h.count:SetTextColor(1, 1, 1)
                        end
                        h.count:SetText(e.stacks)
                        h.count:Show()
                    else
                        h.count:Hide()
                    end
                end
                -- The SPELL's cooldown, on every row's slot rather than only
                -- the one holding it — because "can I cast this at this
                -- person right now" is a question every row asks, and for a
                -- travelling object the answer is the same everywhere. A dark
                -- slot with a closing ring is Mending on cooldown; a dark
                -- slot with no ring is one you can cast here this instant.
                if e.charges and DB("PoMCooldownRing", true)
                    and (util.pomCdLeft or 0) > 0 and (util.pomCdDur or 0) > 0 then
                    util.DrawOutline(h.ring, SDATA.SMALL_ICON,
                        util.pomCdLeft / util.pomCdDur, SDATA.RING_CD)
                else
                    util.HideOutline(h.ring)
                end
            end
        end
    end
    for i = stripShown + 1, SDATA.MAX_STRIP_ICONS do
        local h = row.strip[i]
        h._exp = nil
        h.icon:Hide(); h.cd:Hide(); h.count:Hide(); h.clock:Hide()
        h.flare:Hide(); util.HideOutline(h.ring)
        for k = 1, SDATA.MAX_PIPS do h.pips[k]:Hide() end
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
            -- Health-coloured main bar. The colour rides r.health, NOT the
            -- fill ratio above, and the difference is the whole point.
            --
            -- On this board the fill is deliberately compressed to make room
            -- for the shield segments chained off its right edge: an ally at
            -- full health carrying a shield worth a fifth of their pool has a
            -- ratio of 1/1.2, because the track now has to hold 120% of a
            -- health bar. That is correct for the WIDTH -- the segments make
            -- the row up to full again -- and nonsense for the colour, which
            -- read 0.83 and dutifully darkened toward amber. Shielding a
            -- healthy teammate made them look hurt, which is the exact
            -- opposite of what you just did for them.
            local c = util.HealthTint(r.health or h, SDATA.HP_TINT)
            row.bar:SetVertexColor(c[1], c[2], c[3], 0.9)
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
    -- The chain's remaining room, kept past the loop: the forecast ghosts
    -- below extend the same run and have to respect the same budget.
    local budget = barW - (row.bar:IsShown() and (row.bar:GetWidth() or 0) or barW)
    if r.healthMain and r.segs and r.segScale and r.segScale > 0 and row.bar:IsShown() then
        -- The segments CHAIN off the fill's right edge, so the budget they
        -- share is whatever the fill left behind. Spending it down as they go
        -- means the run can never reach past the track even if the scale it
        -- was measured against turns out to be wrong.
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

    -- -----------------------------------------------------------------------
    -- FORECAST: what is already on its way, drawn where the answer belongs —
    -- on the bar that is going to move.
    --
    --   healing  chains off the absorb run in the same direction health
    --            grows, so a ghost reaching the end of the track means "they
    --            are going to be fine, spend your global elsewhere"
    --   damage   shades back INTO the fill from its right edge, so a row whose
    --            green is half eaten is a row already committed to that loss
    --
    -- Both are read at a glance and neither costs the row any width, which is
    -- why this is the default shape. Ticks reduce both to hairlines for a
    -- quieter board; Numbers spell them out for a board you would rather read
    -- than estimate; Net folds the two into whichever way the ally is
    -- actually heading.
    -- -----------------------------------------------------------------------
    local fcMode = DB("Forecast", "BAR")
    local fcScale = r.segScale or r.hpMax
    local fcOn = fcMode ~= "OFF" and r.healthMain and fcScale and fcScale > 0
        and row.bar:IsShown() and (r.fcDot or r.fcHot or r.fcCast)
    local fcNet = DB("ForecastNet", false)
    local fcHeal = (r.fcHot or 0) + (r.fcCast or 0)
    local fcHurt = r.fcDot or 0
    if fcOn and fcNet then
        -- Net: one direction only. Two ghosts pointing at each other is a sum
        -- the reader has to do; this does it for them.
        local net = fcHeal - fcHurt
        fcHeal, fcHurt = math.max(0, net), math.max(0, -net)
    end
    local drawBars = fcOn and (fcMode == "BAR" or fcMode == "BOTH")
    local drawTicks = fcOn and fcMode == "TICK"

    if drawBars then
        -- Rolling hots first, then the inbound cast past them: the cast is the
        -- part that has not happened yet and can still be cancelled or
        -- outrun, so it sits furthest from the fill. Net mode has already
        -- collapsed both into one figure, so it draws one ghost.
        local hotPts = fcNet and fcHeal or (r.fcHot or 0)
        local hotW = math.min(barW * (hotPts / fcScale), budget)
        local anchor = nSegs > 0 and row.shieldSegs[nSegs] or row.bar
        if hotW >= 1 then
            budget = budget - hotW
            row.fcHot:ClearAllPoints()
            row.fcHot:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 0, 0)
            row.fcHot:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 0, 0)
            row.fcHot:SetVertexColor(0.35, 0.85, 0.45, 0.45)
            row.fcHot:SetWidth(hotW)
            row.fcHot:Show()
            anchor = row.fcHot
        else
            row.fcHot:Hide()
        end
        local castW = (not fcNet) and r.fcCast
            and math.min(barW * (r.fcCast / fcScale), budget) or 0
        if castW >= 1 then
            row.fcCast:ClearAllPoints()
            row.fcCast:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 0, 0)
            row.fcCast:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 0, 0)
            row.fcCast:SetVertexColor(0.7, 0.95, 0.8, 0.5)
            row.fcCast:SetWidth(castW)
            row.fcCast:Show()
        else
            row.fcCast:Hide()
        end
        local hurtW = fcHurt > 0
            and math.min(barW * (fcHurt / fcScale), row.bar:GetWidth() or 0) or 0
        if hurtW >= 1 then
            row.fcDot:ClearAllPoints()
            row.fcDot:SetPoint("TOPRIGHT", row.bar, "TOPRIGHT", 0, 0)
            row.fcDot:SetPoint("BOTTOMRIGHT", row.bar, "BOTTOMRIGHT", 0, 0)
            row.fcDot:SetVertexColor(0.55, 0.05, 0.05, 0.55)
            row.fcDot:SetWidth(hurtW)
            row.fcDot:Show()
        else
            row.fcDot:Hide()
        end
    else
        row.fcHot:Hide(); row.fcCast:Hide(); row.fcDot:Hide()
    end

    if drawTicks then
        -- Where the bar ENDS UP, as a hairline each way. No fill, so a busy
        -- board keeps its colors and still answers the question.
        local fill = row.bar:GetWidth() or 0
        local segW = 0
        for i = 1, nSegs do segW = segW + (row.shieldSegs[i]:GetWidth() or 0) end
        local hx = fill + segW + math.min(barW * (fcHeal / fcScale), barW)
        local dx = fill - math.min(barW * (fcHurt / fcScale), fill)
        if fcHeal > 0 then
            row.fcTickH:ClearAllPoints()
            row.fcTickH:SetPoint("TOPLEFT", row.barBG, "TOPLEFT",
                math.max(0, math.min(barW - 1, hx)), 0)
            row.fcTickH:SetSize(1, row.barBG:GetHeight() or SDATA.BAR_H)
            row.fcTickH:SetVertexColor(0.5, 1, 0.6, 0.95)
            row.fcTickH:Show()
        else
            row.fcTickH:Hide()
        end
        if fcHurt > 0 then
            row.fcTickD:ClearAllPoints()
            row.fcTickD:SetPoint("TOPLEFT", row.barBG, "TOPLEFT",
                math.max(0, math.min(barW - 1, dx)), 0)
            row.fcTickD:SetSize(1, row.barBG:GetHeight() or SDATA.BAR_H)
            row.fcTickD:SetVertexColor(1, 0.35, 0.3, 0.95)
            row.fcTickD:Show()
        else
            row.fcTickD:Hide()
        end
    else
        row.fcTickH:Hide(); row.fcTickD:Hide()
    end

    if fcOn and (fcMode == "TEXT" or fcMode == "BOTH") then
        -- Numbers. Net is one signed figure; otherwise healing and damage are
        -- two, each in its own color, because "+3.1k and -2.4k" and "+700"
        -- are different situations and only one of them is quiet.
        if fcNet then
            -- A net of nothing has nothing to say, and "+0" is not nothing —
            -- it is a number the eye has to stop on and then discard.
            local net = fcHeal - fcHurt
            if math.abs(net) < 1 then
                row.fcText:SetText("")
            else
                row.fcText:SetText((net > 0 and "+" or "-") .. FormatAmount(math.abs(net)))
            end
            if net >= 0 then
                row.fcText:SetTextColor(0.45, 1, 0.55)
            else
                row.fcText:SetTextColor(1, 0.45, 0.4)
            end
        else
            local parts
            if fcHeal > 0 then
                parts = "|cff66ff88+" .. FormatAmount(fcHeal) .. "|r"
            end
            if fcHurt > 0 then
                local d = "|cffff6655-" .. FormatAmount(fcHurt) .. "|r"
                parts = parts and (parts .. " " .. d) or d
            end
            row.fcText:SetTextColor(1, 1, 1)
            row.fcText:SetText(parts or "")
        end
        row.fcText:Show()
    elseif fcMode ~= "OFF" and r.fcCastN and not fcOn then
        -- A heal is in the air whose size we have never measured. The number
        -- is unknown, the FACT is not, and "someone else has them" is most of
        -- what the number was for.
        row.fcText:SetTextColor(0.7, 0.95, 0.8)
        row.fcText:SetText("+?")
        row.fcText:Show()
    else
        row.fcText:Hide()
    end

    -- Underlay strip: the ally's POWER, whatever they run on. Tinted by
    -- resource by default — blue mana, red rage, yellow energy, orange focus,
    -- green happiness — because on a mixed board the color is the fastest
    -- read of what a row even is; Classic Blue paints every strip the one
    -- blue the board wore before, for anyone who wants the quieter bar.
    if not r.selfSpell and util.PowerOn(r) then
        local c = SDATA.POWER_COLOR_DEFAULT
        if DB("PowerBarColor", "TYPE") == "TYPE" then
            c = SDATA.POWER_COLORS[r.powerToken or ""] or c
        end
        row.healthBar:SetVertexColor(c[1], c[2], c[3], 0.9)
        row.healthBar:SetWidth(math.max(barW * math.min(1, math.max(0, r.power)), 1))
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

    -- Crossed blades: this ally is in combat. Which is to say — this is an
    -- ally you can take combat OFF: one heal on someone already fighting and
    -- you are in combat too, and a Sap does not open on a target in combat.
    -- Read the other way, a board with no blades on it is the one that says
    -- sit down, the drink will finish, and nobody here is about to pull.
    --
    -- Dim when they are out of your cast range: they are fighting, but not
    -- somewhere you can reach to join them, and a mark you cannot act on
    -- should not read like one you can. Self-shield rows sit this out — they
    -- are the same person as your own ally row, which already carries it.
    --
    -- Not dimmed TWICE, though: Range Fade dims the whole row on the same
    -- 40-yard answer, and 0.4 on top of that is a mark nobody can see. When the
    -- row is already carrying the news, the blades ride it at full strength.
    local combatOn = row._combatSlot and r.inCombat and not r.selfSpell
        and not r.dead
    if combatOn then
        local dim = r.outOfCastRange and not r.outOfRange
        row.combatMark:SetVertexColor(1, 1, 1, dim and 0.4 or 1)
        row.combatMark:Show()
    else
        row.combatMark:Hide()
    end

    -- The battleground marks, in the same cluster and read the same way: what
    -- this ally IS right now that the rest of the row cannot say. The flag
    -- first, always — a carrier with Berserking up is still, first, the
    -- carrier — then the best powerup they are holding.
    --
    -- Dimmed on the same rule as the blades, and for the same reason: a
    -- carrier you cannot reach is news, not a decision, and once Range Fade
    -- is already dimming the whole row they are not dimmed twice. Hidden on a
    -- dead row, which is also how a flag stops being drawn without a scan:
    -- dying drops it, and health reaches us from across the map.
    local bgShown = 0
    if (row._bgSlots or 0) > 0 and r.bgMarks and not r.selfSpell and not r.dead then
        local dim = r.outOfCastRange and not r.outOfRange
        if row._markGrid then
            -- Fixed cells: the flag is ALWAYS bottom-left and the powerup
            -- ALWAYS bottom-right, so which cell is lit says what it is
            -- before the icon is read. r.bgMarks is best-first, so the first
            -- non-flag entry is the powerup that matters.
            local flag, power
            for i = 1, #r.bgMarks do
                local m = r.bgMarks[i]
                if not (m.expire and m.expire > 0 and m.expire <= now) then
                    if m.prio == 1 then flag = flag or m else power = power or m end
                end
            end
            local cells = { flag, power }
            for i = 1, 2 do
                local t, m = row.bgMarks[i], cells[i]
                if m then
                    if t._icon ~= m.icon then t._icon = m.icon; t:SetTexture(m.icon) end
                    t:SetVertexColor(1, 1, 1, dim and 0.4 or 1)
                    t:Show()
                else
                    t:Hide()
                end
            end
            bgShown = 2
        else
            for i = 1, #r.bgMarks do
                local m = r.bgMarks[i]
                -- A powerup runs out on its own clock, and out of range that
                -- clock is the only thing that can end it. The flag has no
                -- expiry at all, so it never falls off this way.
                if not (m.expire and m.expire > 0 and m.expire <= now) then
                    bgShown = bgShown + 1
                    local t = row.bgMarks[bgShown]
                    -- Memoed: this runs at the draw rate, and the icon in a slot
                    -- changes about twice a match
                    if t._icon ~= m.icon then t._icon = m.icon; t:SetTexture(m.icon) end
                    t:SetVertexColor(1, 1, 1, dim and 0.4 or 1)
                    t:Show()
                    if bgShown >= row._bgSlots then break end
                end
            end
        end
    end
    for i = bgShown + 1, SDATA.MAX_BG_MARKS do row.bgMarks[i]:Hide() end

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
        row.markTick:SetSize(2, (row._wsH or SDATA.WS_H) + 4)
        row.markTick:Show()
    else
        row.markTick:Hide()
    end

    -- Recast-lockout drain: Weakened Soul on ally rows, the spell's own
    -- cooldown on self-spell rows (r.lockMax carries that spell's full CD) —
    -- and, on the druid board, the Lifebloom roll, which is the one thing
    -- this strip carries that you WANT to see full. A lockout is red because
    -- it is a problem; the roll takes its colour from how long is left, so
    -- the same strip reads "fine / refresh / late" without a second glance.
    if r.wsLeft and r.wsLeft > 0 then
        local lockMax = (r.lockMax and r.lockMax > 0) and r.lockMax or SDATA.WEAKENED_SOUL_MAX
        local t = r.wsTint
        row.wsBar:SetVertexColor(t and t[1] or 0.9, t and t[2] or 0.2, t and t[3] or 0.2, 0.9)
        row.wsBar:SetWidth(math.max((row._barW or 100) * math.min(r.wsLeft / lockMax, 1), 1))
        row.wsBar:Show()
    else
        row.wsBar:Hide()
    end

    -- The bar's left slot is the state word, and plenty of rows legitimately
    -- have nothing to say there -- a shield board with no shield up, a quiet
    -- cooldown row. A blank span over a health bar is a wasted answer, so it
    -- falls back to WHOSE bar this is, in class colour: the one thing that is
    -- always true of the row. Nothing else changes -- the percent on the right,
    -- the strip, the name slot all stay exactly as they were. Self-spell rows
    -- are left out: their r.name is the spell, not a person.
    if (r.mainText and r.mainText ~= "") or r.selfSpell then
        row.left:SetTextColor(1, 1, 1)
        row.left:SetText(r.mainText or "")
    else
        local cc = r.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[r.class]
        row.left:SetTextColor(cc and cc.r or 0.9, cc and cc.g or 0.9, cc and cc.b or 0.9)
        row.left:SetText(ShortName(r.name, 10))
    end
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
        -- The flash is red by default because every other thing that fires it
        -- is bad news. Mending's end is not always: a spent one did exactly
        -- what it was cast to do, and colouring that the same as a dispelled
        -- one would throw away the one bit of information the alert carries.
        local t = util.rowFlashTint[index]
        row.flash:SetVertexColor(t and t[1] or 1, t and t[2] or 0.2, t and t[3] or 0.2)
        row.flash:SetAlpha(0.55 * (flashEnd - now) / 0.9)
        row.flash:Show()
    else
        rowFlash[index] = nil
        util.rowFlashTint[index] = nil
        row.flash:Hide()
    end

    -- Overheal ring. Brightness rides the share that was wasted, so a heal
    -- that spilled a little is a hint and one that spilled entirely is a
    -- statement — and a hot ticking into a capped ally, which refreshes the
    -- hold every tick, sits there as a steady ring saying so. Pale green
    -- white: the same family as the forecast's healing ghost, because it is
    -- the same subject seen a second later.
    local oh = r.overheal or 0
    if oh > 0 then
        local a = math.min(0.9, 0.3 + 0.55 * oh)
        for i = 1, 4 do
            local t = row.ohGlow[i]
            t:SetVertexColor(0.55, 1, 0.68, a)
            t:Show()
        end
    else
        for i = 1, 4 do row.ohGlow[i]:Hide() end
    end

    -- The low-health ring, a hairline just inside it: this ally is far enough
    -- down to want our cheap rolling heal and has none of it on them.
    -- Independent of the ring above on purpose — they are different news,
    -- they can both be true at once, and neither gets to hide the other.
    local needAt = DB("RenewNeedAt", 85) / 100
    if DB("RenewNeedRing", true) and util.lowHotDef and r.healthMain
        and not r.hotUp and not r.dead and (r.health or 1) <= needAt then
        -- Faint at the threshold and deepening as they fall: a nudge about
        -- somebody who is merely low, not an alarm about somebody who is
        -- dying. By the time it is an emergency the bar colour and the sort
        -- are already saying so, far louder than a hairline can — and a
        -- binary would either nag at 85% or say nothing until too late.
        local depth = needAt > 0 and (1 - (r.health or 1) / needAt) or 0
        if depth < 0 then depth = 0 elseif depth > 1 then depth = 1 end
        local a = 0.20 + 0.45 * depth
        for i = 1, 4 do
            local t = row.needGlow[i]
            t:SetVertexColor(0.95, 0.25, 0.25, a)
            t:Show()
        end
    else
        for i = 1, 4 do row.needGlow[i]:Hide() end
    end
end

-- Expose Alert: fire when an ally we were shielding just lost our shield while
-- still alive (they need a reshield). Edge-triggered per GUID.
-- The roll's LATE warning. Deliberately not an alert on the refresh window:
-- a rolling Lifebloom enters its window every five seconds by design, and an
-- alarm that fires every five seconds is a metronome, not a warning. This
-- fires once per cycle at the point where you are no longer refreshing early
-- but refreshing behind — under LBLateAt, which defaults to a second and a
-- half, about one global plus travel. Miss it and the stacks are gone.
--
-- Edge-triggered per GUID, so holding the roll late does not re-fire, and a
-- refresh re-arms it for the next cycle.
-- On `util` rather than a chunk local: this file is ON Lua's 200-local
-- ceiling, so a new one here is a load error (see the note at the top).
function util.CheckRollAlert(r, index, now)
    if not (r.guid and layer == "HOT") then return end
    local late = (r.roll and r.roll.late) or false
    local was = util.prevRollLate[r.guid]
    util.prevRollLate[r.guid] = late
    if late and not was and not r.dead and DB("LBAlert", false) then
        rowFlash[index] = now + 0.9
        util.rowFlashTint[index] = nil
        if DB("LBAlertSound", false) then util.PlayAlert("LBLATE") end
    end
end

-- Play one alert's chosen sound, and the only route any of them take — so
-- "which noise was that" has exactly one answer per alert, and the settings
-- page can both name it and audition it.
--
-- Two channels tried in order: the SOUNDKIT constant (the sanctioned route,
-- but the table is client-version dependent), then the raw id it resolves to,
-- then the file path (stable across versions, for files that shipped). Each
-- is pcall'd and only a real success stops the chain, so an entry this client
-- is missing falls through to the channel it does have rather than going
-- quiet — and if it has neither, silence beats a Lua error mid-arena.
function util.PlayAlert(alertKey)
    local line = SDATA.ALERT_BY_KEY[alertKey]
    if not line then return end
    local dbKey = SDATA.ALERT_SOUND_KEY[alertKey]
    local choice = dbKey and DB(dbKey, line.default) or line.default
    local snd = SDATA.ALERT_SOUND_BY_KEY[choice]
        or SDATA.ALERT_SOUND_BY_KEY[line.default]
    if not snd or snd.silent then return end
    if snd.kit or snd.id then
        local id = (SOUNDKIT and snd.kit and SOUNDKIT[snd.kit]) or snd.id
        if id and PlaySound then
            local ok, played = pcall(PlaySound, id, "Master")
            if ok and played ~= false then return end
        end
    end
    if snd.file and PlaySoundFile then
        pcall(PlaySoundFile, snd.file, "Master")
    end
end

-- Mending's alert, and the one property that matters about it: it cannot
-- fire on a bounce. Not "rarely" and not "unless you are unlucky" — nothing
-- reaches this function while the object is still in flight, because a
-- re-application cancels the pending loss before the grace can lapse (see
-- SDATA.POM_GRACE). What arrives here is only ever the END of the object:
-- the fifth charge spent, the thirty seconds run out, a dispel, or a holder
-- who took it with them.
--
-- Run once per draw rather than once per row, because the sound belongs to
-- the OBJECT and the object's last holder may not be on the board at all —
-- they can die off a tight board or leave the group in the same instant that
-- ends the session, and "you lost your Mending" is not less true because the
-- person who had it is no longer drawn. The row flash is the opportunistic
-- half, and it is allowed to miss.
-- The two spell cooldowns the rings draw, read ONCE per draw rather than once
-- per row: both are facts about YOU, identical on every row that shows them,
-- and GetSpellCooldown is not free enough to call six times for one answer.
--
-- The GCD is filtered out deliberately. Every cast puts a second and a half
-- on every spell you own, and a ring that closed around every icon after
-- every global would be a strobe that means "you just cast something" — which
-- you already know, because you just cast it.
function util.ReadSpellRings(now)
    util.pomCdLeft, util.pomCdDur = 0, 0
    util.pwsCdLeft, util.pwsCdDur = 0, 0
    if not GetSpellCooldown then return end

    -- Read both first, raw, because the global cooldown is only identifiable
    -- by comparing two of them (see below).
    local pomStart, pomDur, pwsStart, pwsDur
    if util.PoMOn() and util.pomName then
        pomStart, pomDur = GetSpellCooldown(util.pomName)
    end
    if layer == "PWS" and PWS_NAME then
        pwsStart, pwsDur = GetSpellCooldown(PWS_NAME)
    end

    -- THE GLOBAL COOLDOWN IS NOT A COOLDOWN, and keeping it out of these
    -- rings is most of what makes them readable. While only the global is
    -- running, EVERY spell you own reports the same window through this API —
    -- the global's own start and duration — so a ring driven straight off it
    -- closes around every icon on the board after every single cast. That
    -- says "you just cast something", which you know, because you cast it.
    --
    -- Two tests, because neither is sound alone.
    --
    --   IDENTITY is the real one. Two different spells cannot coincidentally
    --   share a cooldown window: if Mending and Power Word: Shield report the
    --   same start AND the same duration, that window belongs to neither of
    --   them and is the global. This needs no magic number and survives a
    --   client whose global is not the length we expect — hasted down toward
    --   its one-second floor, or changed outright by a patch.
    --
    --   The DURATION BOUND is the backstop for when identity cannot answer:
    --   only one of the two spells is being read (a priest below Mending's
    --   level), or the other is on a real cooldown of its own so the two
    --   windows differ for an honest reason. Nothing either ring tracks has a
    --   real cooldown under two seconds, so anything at or below the global's
    --   longest possible length is the global.
    local gcd = pomStart and pwsStart and pomStart == pwsStart
        and pomDur == pwsDur and pomStart or nil
    local function real(start, dur)
        if not (start and dur) or start <= 0 or dur <= 0 then return 0, 0 end
        if gcd and start == gcd then return 0, 0 end
        if dur <= SDATA.GCD_MAX then return 0, 0 end
        local left = start + dur - now
        if left <= 0 then return 0, 0 end
        return left, dur
    end
    util.pomCdLeft, util.pomCdDur = real(pomStart, pomDur)
    util.pwsCdLeft, util.pwsCdDur = real(pwsStart, pwsDur)
end

function util.CheckPoMEnd(now)
    local reason, guid = util.PoMTick(now)
    if not reason or not DB("PoMAlert", true) then return end
    local p = util.pom
    p.flashGuid, p.flashReason, p.flashUntil = guid, reason, now + 0.9
    if DB("PoMAlertSound", true) then
        -- Two sounds, because the two outcomes are opposite instructions.
        -- SPENT means the spell finished its job and the cooldown is the only
        -- thing you are waiting on; every other reason means it was taken off
        -- you early and the recast is the next thing you do. They default to
        -- the two bell tolls — one instrument, two pitches — so Mending has a
        -- voice of its own rather than borrowing the raid-warning every other
        -- addon on the client is already using.
        util.PlayAlert(reason == "SPENT" and "POMSPENT" or "POMLOST")
    end
end

-- The flash half: the row that was holding it when it ended, tinted by why.
-- Spent once — a second row must not inherit a flash aimed at the first.
function util.CheckPoMAlert(r, index, now)
    local p = util.pom
    if not (p.flashGuid and p.flashUntil and now < p.flashUntil) then return end
    if r.guid ~= p.flashGuid then return end
    p.flashGuid = nil
    rowFlash[index] = now + 0.9
    local info = SDATA.POM_REASONS[p.flashReason or ""]
    util.rowFlashTint[index] = info and info.tint or nil
end

local function CheckExposeAlert(r, index, now)
    if not DB("ExposeAlert", false) then return end
    local has = r.shieldUp and r.mine or false
    local was = prevMyShield[r.guid]
    prevMyShield[r.guid] = has
    -- Ally boards skip the self row (you feel your own shield break); on a
    -- self board the whole point is your own shield breaking.
    if was and not has and not r.dead and (r.selfSpell or not r.isSelf) then
        rowFlash[index] = now + 0.9
        util.rowFlashTint[index] = nil
        if DB("ExposeAlertSound", false) then util.PlayAlert("EXPOSE") end
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
    if near.Active() then
        -- The pick is already bounded by its own count, so Max Rows does not
        -- clip it here. Secure attributes still only move out of combat, which
        -- is why a mid-fight re-pick sets secureDirty and waits: see
        -- CommanderPartyFrames_NearRefresh.
        near.Ensure()
        if DB("IncludeSelf", true) then
            out[#out + 1] = "player"
            addPet("pet")
        end
        for i = 1, #near.slots do
            out[#out + 1] = near.slots[i]
            addPet(near.PetOf(near.slots[i]))
        end
    elseif DB("Scope", "PARTY") == "RAID" and IsInRaid and IsInRaid() then
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
    local topOffset = showHeader and util.HeaderH() or 0
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
    local slots = DB("FixedHeight", false) and near.Max() or math.max(#secureTokens, 1)
    root:SetSize(width, topOffset + personalBase
        + math.max(slots * RowStride() - SDATA.ROW_GAP, SDATA.ROW_H))
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
    wipe(near.order)
    local seen = {}
    local function add(unit)
        if not UnitExists(unit) then return end
        local guid = UnitGUID(unit)
        if not guid or seen[guid] then return end
        seen[guid] = true
        out[#out + 1] = unit
        -- Where this unit sits in the roster as BUILT. Nearby mode draws in
        -- that order rather than by urgency (the pick IS the ordering there),
        -- and only this walk knows it.
        near.order[unit] = #out
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
    if near.Active() then
        -- Nearby Raid: the pick replaces the roster wholesale. Watch (Party /
        -- Raid) has nothing to say here — the whole point is that neither of
        -- those is what you want in a battleground.
        near.Ensure()
        for i = 1, #near.slots do
            add(near.slots[i])
            if pets then add(near.PetOf(near.slots[i])) end
        end
    elseif DB("Scope", "PARTY") == "RAID" and IsInRaid and IsInRaid() then
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

-- Nearby Raid's row order: the roster exactly as BuildRoster laid it out —
-- you, then the picked allies closest-first, each trailed by its pet. Anything
-- the roster did not stamp (it cannot happen on this path, but a nil index
-- would compare against a number and throw) sorts to the bottom by name.
function near.OrderSort(a, b)
    local ia = near.order[a.unit or ""] or math.huge
    local ib = near.order[b.unit or ""] or math.huge
    if ia ~= ib then return ia < ib end
    return (a.name or "") < (b.name or "")
end

-- Class, then distance: the board read as a class list, each class's members
-- closest-first. The class order is the suite's canon (SDATA.CLASS_SORT_RANK);
-- a pet groups under its owner's class and trails that class's players,
-- because it is still the row that gives way when the board is tight. The
-- distance is r.yards, stamped by util.StampYards just before the sort so a
-- comparison never asks the client for a position twice. Where the client
-- will not report positions (near.Yards says which), everyone in range ties
-- at one band and the tie goes to the name — the same way every pick on
-- this board breaks its ties, so two equal answers do not swap every tick.
-- (On util rather than a file local: the 200-local cap, see the SDATA note.)
function util.ClassSort(a, b)
    local ra = SDATA.CLASS_SORT_RANK[a.class or ""] or 99
    local rb = SDATA.CLASS_SORT_RANK[b.class or ""] or 99
    if ra ~= rb then return ra < rb end
    if (a.isPet or false) ~= (b.isPet or false) then return not a.isPet end
    local ya, yb = a.yards or math.huge, b.yards or math.huge
    if ya ~= yb then return ya < yb end
    return (a.name or "") < (b.name or "")
end

-- Every row's distance from you, for the class sort. Live rows ask near.Yards
-- (real yards when UnitPosition answers, one range band when it does not);
-- the test board's rows ride no unit, so they carry no distance and sort by
-- class then name, which is all a sample needs to show.
function util.StampYards(rows, live)
    for i = 1, #rows do
        local r = rows[i]
        r.yards = (live and type(r.unit) == "string") and near.Yards(r.unit) or nil
    end
end

-- Which order the sorted board draws in: FIXED (Nearby Raid's own pick order,
-- which the pins may not disturb), CLASS (class then distance), or URGENCY
-- (the board's original most-urgent-first sort). Nearby mode answers from its
-- own Row Order setting, because the pick is a different board with a
-- different question; everywhere else, and on the test board, it is Sort
-- Rows. Click-Cast never gets here: its roster order is fixed at bind time.
function util.SortMode(live)
    if live and near.Active() then
        local m = DB("NearSort", "DISTANCE")
        if m == "CLASS" then return "CLASS" end
        return m == "URGENCY" and "URGENCY" or "FIXED"
    end
    return DB("RowOrder", "URGENCY") == "CLASS" and "CLASS" or "URGENCY"
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
        root.headerBG:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
        root.headerBG:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
        -- Tint, opacity and height come from the settings on the way in and
        -- from util.RestyleHeader every time after: styling it here rather
        -- than on each pass keeps a draw-rate function free of work whose
        -- answer only changes when somebody moves a slider.
        local r, g, b = util.HeaderTint()
        root.headerBG:SetVertexColor(r, g, b, util.HeaderAlpha())
        root.headerBG:SetHeight(util.HeaderH())
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
    if showHeader and DB("HeaderRule", false) then
        util.HeaderRule():Show()
    elseif root.headerRule then
        root.headerRule:Hide()
    end
    if settingsBtn then
        settingsBtn:SetShown(showHeader and DB("ShowSettingsButton", true))
        -- Always slot zero: the gear is the rank's right-hand end.
        util.ChromeStyle(settingsBtn, 0)
    end
    if blizz.btn then
        -- Sits left of the gear, or takes its slot when the gear is off.
        -- Re-anchored only when that changes: this runs at the draw rate.
        util.ChromeStyle(blizz.btn, (settingsBtn and settingsBtn:IsShown()) and 1 or 0)
        blizz.btn:SetShown(showHeader)
    end
    if near.btn then
        -- Only while the feature is actually doing something: the flag is on
        -- AND we are in a raid. A button that refreshes nothing is chrome
        -- spent for no reason, and it would eat banner width to do it.
        local on = showHeader and near.Active() and DB("NearButton", true)
        near.btn:SetShown(on)
        if on then
            -- Third in the same right-to-left rank as the other two, and
            -- re-anchored only when that rank changes: this runs at the draw
            -- rate.
            local slot = 0
            if settingsBtn and settingsBtn:IsShown() then slot = slot + 1 end
            if blizz.btn and blizz.btn:IsShown() then slot = slot + 1 end
            util.ChromeStyle(near.btn, slot)
        end
    end
    if showHeader then
        if not root.header then
            root.header = root:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            root.header:SetPoint("TOPLEFT", root, "TOPLEFT", SDATA.STRIPE_W + 4, -1)
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
            end
            if mageUtil then SafeSetShown(mageUtil, true) end
            util.Paint(now)
            local segX = util.PlaceSegs()
            util.segN = 0
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
            -- 2) The survival pair, and only the pair: Ice Block and Cold
            -- Snap, filtered at login to what this mage actually trained, so
            -- an arcane mage never sees a Cold Snap slot. Everything else a
            -- mage presses reads better off its own action-bar swipe than
            -- off a 12px repeat up here (see SDATA.MAGE_BANNER_CDS).
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
            util.PlaceSwitchers(segs)
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
            local segs = util.EnsureSegs()
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
            util.PlaceSwitchers(segs)
            return
        end
        -- The bandage control is chassis, not a class layer — it rides the
        -- priest banner too (the class-layer branches above returned already)
        if mageUtil then SafeSetShown(mageUtil, true) end
        util.Paint(now)
        -- Everything below is the PRIEST banner. A layer with no banner of
        -- its own gets the utility cluster and the gear and nothing else,
        -- rather than somebody else's numbers — unless Production is
        -- embedded, in which case its queue is the whole readout.
        if layer ~= "PWS" then
            root.header:Hide()
            if util.ProductionOn() then
                util.EnsureSegs()
                local segX = util.PlaceSegs()
                util.segN = 0
                util.SegProduction(now)
                util.TruncSegs(segX)
            elseif root.hdrSegs then
                for _, s in ipairs(root.hdrSegs) do s.icon:Hide(); s.text:Hide() end
            end
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
        util.HideSwitchers()
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
    local fc = util.fc
    for _, t in ipairs({ shieldState, wsState, dispelState, intState, util.bgState, curseState, ccState, allyAbsorbs, specState, abilityState, lockState, targeters, strip.state, fc.on, fc.amtOn, fc.casts, util.overheal }) do
        for guid in pairs(t) do
            if type(guid) == "string" and guid:find("^cshieldtest") then t[guid] = nil end
        end
    end
end

-- The forecast, on the test board. Seeded into the SAME state the live path
-- fills — a learned tick size and a list of live periodics — rather than
-- stamped onto the rows as finished numbers, so the preview is drawn by the
-- real resolver and shows exactly what a real fight would.
--   row 1  a dot ticking hard: the ally who is not as healthy as the bar says
--   row 3  two hots rolling: the ally who does not need your global
--   row 5  a heal in the air from a teammate: the reason to spend it elsewhere
-- On `util` and not a chunk local: this file is ON Lua's 200-local
-- ceiling, so a new one here is a load error (see the note at the top).
function util.SeedTestForecast(now)
    local fc = util.fc
    local dotN = (GetSpellInfo and GetSpellInfo(172)) or "Corruption"
    local hotN = (GetSpellInfo and GetSpellInfo(139)) or "Renew"
    local hot2N = (GetSpellInfo and GetSpellInfo(774)) or "Rejuvenation"
    local healN = (GetSpellInfo and GetSpellInfo(2060)) or "Greater Heal"
    fc.kind[dotN] = fc.kind[dotN] or { dot = true, interval = 3, seeded = true }
    fc.kind[hotN] = fc.kind[hotN] or { dot = false, interval = 3, seeded = true }
    fc.kind[hot2N] = fc.kind[hot2N] or { dot = false, interval = 3, seeded = true }
    fc.amtOn["cshieldtest1\30" .. dotN] = 210
    fc.amtOn["cshieldtest3\30" .. hotN] = 160
    fc.amtOn["cshieldtest3\30" .. hot2N] = 140
    fc.on["cshieldtest1"] = { n = 1,
        { name = dotN, expire = now + 12, duration = 18, interval = 3, dot = true } }
    fc.on["cshieldtest3"] = { n = 2,
        { name = hotN, expire = now + 9, duration = 15, interval = 3, dot = false },
        { name = hot2N, expire = now + 6, duration = 12, interval = 3, dot = false } }
    fc.heal[healN] = true
    fc.casts["cshieldtestcaster"] = { dest = "cshieldtest5", name = healN,
        amt = 1900, endTime = now + 2.5 }
end

-- The overheal ring's preview, on the two rows where it reads as the two
-- things it has to say: one spilled half a heal (a hint), the other spilled
-- the whole of one (a statement). Held well past the preview's thirty
-- seconds so it does not fade out from under whoever is looking at it — the
-- fade is capped at full, so a deadline this far out simply reads as steady.
--
-- Its own function under its own guard: overheal and the forecast are two
-- features that happen to be about the same subject, and turning one off
-- must not silently take the other's preview with it.
function util.SeedTestOverheal(now)
    util.overheal["cshieldtest2"] = { until_ = now + 40, frac = 0.55 }
    util.overheal["cshieldtest6"] = { until_ = now + 40, frac = 1 }
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
        util.CheckRollAlert(r, shownPlayers + i, now)
        util.CheckPoMAlert(r, shownPlayers + i, now)
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
    -- Ahead of everything, and outside the board's visibility: an armed grace
    -- has to be resolved on time whether or not the rows are on screen, and a
    -- Combat Only board is hidden at exactly the moment you most want to know
    -- your Mending went.
    if util.PoMOn() then util.CheckPoMEnd(now) end
    util.ReadSpellRings(now)
    ScanTargeters(now)
    -- Buff-layer header tallies rebuild as this pass resolves rows
    if layer then intCurses, intCCs = 0, 0 end
    local showHeader = DB("ShowHeader", true)
    local topOffset = showHeader and util.HeaderH() or 0
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
                if r.guid then
                    CheckExposeAlert(r, i, now)
                    util.CheckRollAlert(r, i, now)
                    util.CheckPoMAlert(r, i, now)
                end
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
            local mainSlots = DB("FixedHeight", false) and near.Max()
                or math.max(#secureTokens, 1)
            local bodyH = mainSlots * RowStride() + personalBase - SDATA.ROW_GAP
            root:SetSize(width, topOffset + math.max(bodyH, SDATA.ROW_H))
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
                    dispelKey = tr.dispelKey, tgtKey = tr.tgtKey, manaUser = tr.manaUser,
                    power = tr.power, powerType = tr.powerType, powerToken = tr.powerToken,
                    raidMark = tr.raidMark, inCombat = tr.inCombat,
                    bgMarks = tr.bgMarks or util.bgState[tr.guid],
                    outOfCastRange = tr.outOfCastRange,
                    isPet = tr.isPet, petOwner = tr.petOwner }
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

    -- Nearby Raid draws in the order it PICKED, not by urgency: the pick is
    -- the answer to "who is near me", and a board that then re-ranks it every
    -- tick throws away the slot stability the pick exists to give. Urgency
    -- and the class order are still available there as a setting; outside
    -- nearby mode, Sort Rows decides between urgency (the board as it always
    -- was) and class-then-distance.
    local sortMode = util.SortMode(testUntil == 0)
    local nearFixed = sortMode == "FIXED"
    if sortMode == "CLASS" then
        util.StampYards(rowData, testUntil == 0)
        table.sort(rowData, util.ClassSort)
    else
        table.sort(rowData, nearFixed and near.OrderSort or SortRows)
    end
    -- Both pins reorder rows, which is exactly what the fixed order forbids —
    -- and in nearby mode you are already row one when Include Self is on.
    if not nearFixed then
        if DB("PinFocus", false) and UnitExists("focus") then
            local fg = UnitGUID("focus")
            if fg then PinToTop(function(r) return r.guid == fg end) end
        end
        if DB("SelfFirst", false) then PinToTop(function(r) return r.isSelf end) end
    end

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

    -- Nearby mode is bounded by its own count (plus the pets that ride their
    -- owners), never by Max Rows — which is the whole-raid control and would
    -- silently clip a pick of ten down to six.
    local maxRows = DB("MaxRows", 6)
    if testUntil == 0 and near.Active() then maxRows = math.max(#rosterUnits, 1) end
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
        util.CheckRollAlert(r, i, now)
        util.CheckPoMAlert(r, i, now)
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
    local bodyH = mainSlots * RowStride() + base - SDATA.ROW_GAP
    if not (InCombat() and root.IsProtected and root:IsProtected()) then
        root:SetSize(width, topOffset + math.max(bodyH, SDATA.ROW_H))
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
    -- Battleground marks in the preview. Seeded into the state table rather
    -- than onto the row samples because each layer builds its own set of
    -- those and these are chassis: the first two rows are common to all four
    -- boards, so one seed previews the pair on every one of them. The slots
    -- only exist here at all because the test board counts as a battleground
    -- for layout (see LayoutRow) — nothing else at the flight master does.
    do
        local function BGSample(id, expire)
            local def
            for _, d in ipairs(SDATA.BG_BUFFS) do if d.id == id then def = d end end
            if not def then return nil end
            return { key = def.key, prio = def.prio, label = def.label,
                icon = def.icon, expire = expire, duration = expire and 10 or nil }
        end
        -- Row one carries the flag AND has just taken Berserking: both slots
        -- filled, in priority order, which is the case the ordering exists for
        local flag, zerk = BGSample(23333), BGSample(23505, now + 7)
        if flag and zerk then util.bgState["cshieldtest1"] = { flag, zerk } end
        -- Row two is on the Restoration berry alone: one slot, one mark
        local resto = BGSample(23493, now + 5)
        if resto then util.bgState["cshieldtest2"] = { resto } end
    end
    wipe(testRows)
    -- Chassis, so it is seeded once for every layer's board below
    if DB("Forecast", "BAR") ~= "OFF" then util.SeedTestForecast(now) end
    if DB("OverhealGlow", true) then util.SeedTestOverheal(now) end

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
            { guid = "cshieldtest1", name = "Mage2", class = "MAGE", manaUser = true, health = 0.9, power = 0.55, powerType = 0, powerToken = "MANA", hpMax = 3800, inCombat = true, outOfCastRange = true },
            { guid = "cshieldtest2", name = "Priest", class = "PRIEST", manaUser = true, health = 0.85, power = 0.7, powerType = 0, powerToken = "MANA", hpMax = 4100 },
            { guid = "cshieldtest3", name = "Druid", class = "DRUID", manaUser = true, health = 0.6, power = 0.4, powerType = 0, powerToken = "MANA", hpMax = 4600 },
            { guid = "cshieldtest4", name = "Pally", class = "PALADIN", manaUser = true, health = 1.0, power = 0.92, powerType = 0, powerToken = "MANA", hpMax = 5200 },
            { guid = "cshieldtest5", name = "Tank", class = "WARRIOR", health = 0.42, power = 0.55, powerType = 1, powerToken = "RAGE", hpMax = 6200, raidMark = 8, inCombat = true },
            { guid = "cshieldtest6", name = "You", class = playerClass, isSelf = true, manaUser = true, health = 0.75, power = 0.8, powerType = 0, powerToken = "MANA", hpMax = 4000 },
        }
        -- The test board is a preview of the real thing, so its rows carry the
        -- identity the real resolver builds — otherwise the paladin's blessing
        -- slot would have nobody to assign a blessing TO, and the one control
        -- on the board you can actually click would be dead in the preview.
        for _, tr in ipairs(testRows) do tr.fullName = tr.name end
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
                petOwnerName = "Lock", fullName = "Felhunter",
                manaUser = true, health = 0.68, power = 0.35, powerType = 0, powerToken = "MANA", hpMax = 2900 }
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
        -- The roll's three readings, side by side, because the whole point of
        -- giving Lifebloom its own instruments is that these have to be
        -- tellable apart at a glance and the only way to know they are is to
        -- see them together:
        --   row 2  inside the window at ONE stack — a plain gold refresh
        --   row 4  inside the window at THREE — purple: refresh, or let it
        --          bloom, and that is a real fork rather than a reminder
        --   row 5  LATE, red and pulsing, with the bar nearly empty
        strip.state["cshieldtest2"] = {
            LIFEBLOOM = { expire = now + 2.5, duration = 7, icon = defs.LIFEBLOOM.icon, stacks = 1 },
        }
        strip.state["cshieldtest4"] = {
            REJUV = { expire = now + 8, duration = 12, icon = defs.REJUV.icon, stacks = 0 },
            LIFEBLOOM = { expire = now + 2.2, duration = 7, icon = defs.LIFEBLOOM.icon, stacks = 3 },
        }
        -- Rejuv only, healthy clock — and a roll on its last second
        strip.state["cshieldtest5"] = {
            REJUV = { expire = now + 11, duration = 12, icon = defs.REJUV.icon, stacks = 0 },
            LIFEBLOOM = { expire = now + 1.2, duration = 7, icon = defs.LIFEBLOOM.icon, stacks = 3 },
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
            { guid = "cshieldtest1", name = "Priest", class = "PRIEST", manaUser = true, health = 0.72, power = 0.6, powerType = 0, powerToken = "MANA", hpMax = 4100 },
            { guid = "cshieldtest2", name = "Rogue", class = "ROGUE", health = 0.66, power = 0.7, powerType = 3, powerToken = "ENERGY", hpMax = 4300, inCombat = true, outOfCastRange = true },
            { guid = "cshieldtest3", name = "Mage", class = "MAGE", manaUser = true, health = 0.9, power = 0.45, powerType = 0, powerToken = "MANA", hpMax = 3800 },
            { guid = "cshieldtest4", name = "Hunter", class = "HUNTER", manaUser = true, health = 0.83, power = 0.7, powerType = 0, powerToken = "MANA", hpMax = 4800 },
            { guid = "cshieldtest5", name = "Tank", class = "WARRIOR", health = 0.38, power = 0.62, powerType = 1, powerToken = "RAGE", hpMax = 6200, raidMark = 8, inCombat = true },
            { guid = "cshieldtest6", name = "Pally", class = "PALADIN", manaUser = true, health = 0.55, power = 0.5, powerType = 0, powerToken = "MANA", hpMax = 5200 },
            { guid = "cshieldtest7", name = "You", class = playerClass, isSelf = true, manaUser = true, health = 0.95, power = 0.8, powerType = 0, powerToken = "MANA", hpMax = 4400 },
        }
        -- The hunter's pet (Include Pets). Mark of the Wild lands on a pet
        -- whatever it runs on, so the buff slot applies even though a boar
        -- runs on focus rather than mana — and a hot of yours rolls on it
        -- like any ally.
        if DB("IncludePets", true) then
            strip.state["cshieldtest8"] = {
                REJUV = { expire = now + 5, duration = 12, icon = defs.REJUV.icon, stacks = 0 },
            }
            testRows[#testRows + 1] = { guid = "cshieldtest8", name = "Boar",
                class = "HUNTER", isPet = true, petOwner = "party4",
                power = 0.85, powerType = 2, powerToken = "FOCUS", health = 0.47, hpMax = 3300 }
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
            { guid = "cshieldtest1", name = "Priest", class = "PRIEST", manaUser = true, health = 0.88, power = 0.6, powerType = 0, powerToken = "MANA", hpMax = 4100 },
            { guid = "cshieldtest2", name = "Rogue", class = "ROGUE", health = 0.44, power = 0.35, powerType = 3, powerToken = "ENERGY", hpMax = 4300, inCombat = true, outOfCastRange = true },
            { guid = "cshieldtest3", name = "Mage", class = "MAGE", manaUser = true, health = 0.9, power = 0.45, powerType = 0, powerToken = "MANA", hpMax = 3800 },
            { guid = "cshieldtest4", name = "Hunter", class = "HUNTER", manaUser = true, health = 0.83, power = 0.7, powerType = 0, powerToken = "MANA", hpMax = 4800 },
            { guid = "cshieldtest5", name = "Tank", class = "WARRIOR", health = 0.31, power = 0.48, powerType = 1, powerToken = "RAGE", hpMax = 6200, raidMark = 8, inCombat = true },
            { guid = "cshieldtest6", name = "Druid", class = "DRUID", manaUser = true, health = 0.55, power = 0.5, powerType = 0, powerToken = "MANA", hpMax = 4600 },
            { guid = "cshieldtest7", name = "You", class = playerClass, isSelf = true, manaUser = true, health = 0.95, power = 0.8, powerType = 0, powerToken = "MANA", hpMax = 5200 },
        }
        -- The hunter's pet (Include Pets). Might applies to anything that
        -- swings, so a boar keeps that slot on focus rather than mana — and a
        -- Freedom of yours rides it like any ally row.
        if DB("IncludePets", true) then
            intState["cshieldtest8"] = { MIGHT = { expire = now + 400, duration = 600 } }
            strip.state["cshieldtest8"] = {
                FREEDOM = { expire = now + 6, duration = 10, icon = defs.FREEDOM.icon, stacks = 0 },
            }
            testRows[#testRows + 1] = { guid = "cshieldtest8", name = "Boar",
                class = "HUNTER", isPet = true, petOwner = "party4",
                power = 0.85, powerType = 2, powerToken = "FOCUS", health = 0.47, hpMax = 3300 }
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
        { guid = "cshieldtest1", name = "Tank", class = "WARRIOR", health = 0.42, power = 0.55, powerType = 1, powerToken = "RAGE", hpMax = 6200, raidMark = 8, inCombat = true },
        { guid = "cshieldtest2", name = "Rogue", class = "ROGUE", health = 0.78, power = 0.9, powerType = 3, powerToken = "ENERGY", hpMax = 4300, raidMark = 7, inCombat = true, outOfCastRange = true },
        { guid = "cshieldtest3", name = "Mage", class = "MAGE", manaUser = true, health = 1.0, power = 0.62, powerType = 0, powerToken = "MANA", hpMax = 3800 },  -- full: shields extend the scale
        { guid = "cshieldtest4", name = "Druid", class = "DRUID", manaUser = true, health = 0.6, power = 0.38, powerType = 0, powerToken = "MANA", hpMax = 4600 },
        { guid = "cshieldtest5", name = "Hunter", class = "HUNTER", health = 0.9, power = 0.8, powerType = 0, powerToken = "MANA", hpMax = 4800 },
        { guid = "cshieldtest6", name = "You", class = select(2, UnitClass("player")), isSelf = true, manaUser = true, health = 0.85, power = 0.7, powerType = 0, powerToken = "MANA", hpMax = 4000 },
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
            power = 0.6, powerType = 0, powerToken = "MANA", health = 0.55, hpMax = 3100 }
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
    if util.BlessCombined() then
        -- On this layer `tracked` stops being the interesting column: the
        -- blessings share one slot, so what decides each row is the
        -- ASSIGNMENT, and trained is the only per-blessing fact left.
        print(string.format("  |cffffd100one blessing slot|r, only-mine=%s, row menu=%s",
            tostring(DB("BlessMineOnly", true)), tostring(DB("BlessRowMenu", true))))
    end
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
                -- On the combined slot the label is the ASSIGNED blessing, and
                -- "missing" is worth qualifying: they may well be carrying a
                -- different one of yours, which is the whole reason the slot
                -- is dark rather than a mystery.
                local label = (slot.want and slot.want.label) or slot.def.label
                local note = (not slot.up and slot.why) and ("  (" .. slot.why .. ")") or ""
                if slot.want and not slot.up and r.blessHave then
                    note = "  (carrying your " .. r.blessHave.label .. ")"
                end
                print(string.format("    %-10s %-13s %s%s", r.name or "?",
                    label, state, note))
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
    print(string.format("  nearby: flag=%s  active=%s  count=%d  picked=%d  exact=%s  auto=%s  pending=%s",
        tostring(DB("NearMode", false)), tostring(near.Active()), near.Count(),
        #near.slots, tostring(near.exact), tostring(DB("NearAuto", false)),
        tostring(near.pending)))
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
    -- The forecast is the one feature on this board whose accuracy depends
    -- entirely on state you cannot see: what it has LEARNED. Printing the
    -- learned amounts is the only way to answer "why is this number wrong"
    -- in game — a spell with no measurement yet is worth zero by design, and
    -- that looks identical to a bug until you can see the table.
    local fc = util.fc
    local shapes, measured, live = 0, 0, 0
    for _ in pairs(fc.kind) do shapes = shapes + 1 end
    for _ in pairs(fc.amtAny) do measured = measured + 1 end
    local nowT = GetTime()
    for _, list in pairs(fc.on) do
        for i = 1, list.n do
            if list[i].expire and list[i].expire > nowT then live = live + 1 end
        end
    end
    local casting = 0
    for _, c in pairs(fc.casts) do
        if c.endTime and c.endTime > nowT then casting = casting + 1 end
    end
    print(string.format("  forecast=%s window=%s  shapes=%d  measured=%d  ticking=%d  casting=%d",
        DB("Forecast", "BAR"),
        (DB("ForecastWindow", 5) > 0) and (DB("ForecastWindow", 5) .. "s") or "full",
        shapes, measured, live, casting))
    for name, amt in pairs(fc.amtAny) do
        local shape = fc.kind[name]
        print(string.format("    %s: %s ~%d per tick every %ds",
            name, (shape and shape.dot) and "dot" or "hot",
            math.floor(amt + 0.5), (shape and shape.interval) or 3))
    end
    for name, amt in pairs(fc.healAny) do
        print(string.format("    %s: heal ~%d", name, math.floor(amt + 0.5)))
    end
    -- What OUR heals are worth off their own tooltips, which is what the cast
    -- forecast actually uses for us. Printed beside the learned numbers on
    -- purpose: if the two disagree wildly, one of them is telling you
    -- something (a target under Mortal Strike, or a rank you downrank with).
    if GetSpellInfo then
        for _, id in ipairs(SDATA.HEAL_SEED) do
            local n = GetSpellInfo(id)
            local tip = n and util.HealTip(id)
            if tip and tip > 0 then
                print(string.format("    %s (%d): tooltip ~%d", n, id,
                    math.floor(tip + 0.5)))
            end
        end
    end
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

-- ---------------------------------------------------------------------------
-- Nearby Raid: applying a pick.
--
-- Split from near.Pick because the pick is pure — it decides who belongs on
-- the board and touches nothing else — while APPLYING it has to reach both
-- boards, and only one of them is free to change mid-fight. So a re-pick made
-- in combat on the Click-Cast board is parked rather than lost: secureDirty is
-- already what PLAYER_REGEN_ENABLED watches, and the button goes amber to say
-- so instead of silently doing nothing.
-- ---------------------------------------------------------------------------
function CommanderPartyFrames_NearRefresh(sticky, quiet)
    if not near.Active() then
        if not quiet then
            print("|cff66ccffCommander Party Frames|r: Nearby Raid is "
                .. (DB("NearMode", false)
                    and "on, but you are not in a raid or battleground."
                    or "off — turn it on in the settings (|cffffd100/cpf|r)."))
        end
        return false
    end
    local changed = near.Pick(sticky and true or false)
    if changed and testUntil == 0 then
        if securePool then SetupSecureRows() end
        Draw()
    end
    if securePool then near.pending = secureDirty and true or false end
    near.PaintButton()
    return changed
end

-- The live nearby pick, read-only: the ordered unit tokens (never "player" —
-- your own row is Include Self's, and always the first), whether the distances
-- behind them are real yards, and whether the feature is even on right now.
function CommanderPartyFrames_NearPick(out)
    out = out or {}
    wipe(out)
    for i = 1, #near.slots do out[i] = near.slots[i] end
    return out, near.exact, near.Active()
end

-- /cpf near — re-pick and say what came back. Doubles as the diagnostic for
-- the one thing about this feature you cannot see by looking at it: whether
-- the distances are real yards or interact-distance bands.
function CommanderPartyFrames_Near()
    if not CommanderPartyFrames_NearRefresh(false) then return end
    print(string.format("|cff66ccffCommander Party Frames|r: nearby pick — %d of %d rows, %s%s.",
        #near.slots + (DB("IncludeSelf", true) and 1 or 0), near.Count(),
        near.exact and "|cff33ff33measured in yards|r"
            or "|cffff8c26ranked by range bands|r (the client is not reporting positions here)",
        DB("NearAuto", false) and string.format(", auto every %ds", DB("NearInterval", 3)) or ""))
    for i = 1, #near.slots do
        local u = near.slots[i]
        local yards = near.Yards(u)
        print(string.format("  %d. %s  %s%.0fy", i, UnitName(u) or u,
            near.exact and "" or "~", yards or 0))
    end
end

-- The ticker rides its own always-shown frame, NOT root: a board hidden by
-- Only Show Alerts must still notice absorb- and clock-driven transitions —
-- a shield chewed low by SPELL_ABSORBED fires no aura event, and "expiring
-- soon" is pure clock — so it can reappear the moment a row turns urgent.
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(self, elapsed)
    if not (profile and CommanderPartyFramesDB and CommanderPartyFramesDB.EnableShield) then return end
    self.sinceDraw = (self.sinceDraw or 0) + elapsed
    if self.sinceDraw >= SDATA.DRAW_THROTTLE then self.sinceDraw = 0; Draw() end
    self.sinceSample = (self.sinceSample or 0) + elapsed
    if self.sinceSample >= SDATA.UPTIME_SAMPLE then self.sinceSample = 0; SampleUptime(GetTime()) end
    -- Nearby Raid auto-refresh: the same sorted re-pick the button takes, on a
    -- timer. `sticky` is the only difference — an automatic pick lets whoever
    -- is already on the board keep their place against a marginally closer
    -- outsider, so the membership does not flicker between two equally correct
    -- answers. The ORDER is always live distance; a board that did not visibly
    -- re-sort here is what made this look broken in the first place.
    if near.Active() and DB("NearAuto", false) then
        self.sinceNear = (self.sinceNear or 0) + elapsed
        if self.sinceNear >= (tonumber(DB("NearInterval", 3)) or 3) then
            self.sinceNear = 0
            CommanderPartyFrames_NearRefresh(true, true)
        end
    end
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
        if not DB("OverhealGlow", true) then wipe(util.overheal) end
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
        -- Same reason, one storey up: the banner's strip, its panel and its
        -- popouts are all built once and never revisited by a redraw
        util.RestyleHeader()
        -- Nearby Raid's count, its flag and Include Self all decide the SHAPE
        -- of a pick, so a settings change invalidates the one we are holding
        near.Invalidate()
        near.PaintButton()
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
        wipe(util.bgState)
        wipe(curseState)
        wipe(ccState)
        wipe(allyAbsorbs)
        wipe(strip.state)
        util.PoMReset()
        -- The forecast's LIVE state goes; what it has LEARNED stays. The
        -- learned amounts are the expensive half (they cost a fight to
        -- gather) and none of them describe anyone currently on the board,
        -- so switching the module off and on again should not cost you them.
        wipe(util.fc.on)
        wipe(util.fc.casts)
        wipe(util.overheal)
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
-- Inbound-heal forecast: a group member's cast, from the frame it starts on.
-- pcall'd like the talent events below, so a client that never shipped one of
-- these leaves the rest of the board alone.
for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
                     "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED",
                     "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET" }) do
    pcall(events.RegisterEvent, events, e)
end
-- A respec changes which binding profile is live, so the secure rows have to
-- be rewritten. Soft-registered: a client without the event must not stop the
-- rest of the board from loading.
pcall(events.RegisterEvent, events, "CHARACTER_POINTS_CHANGED")
pcall(events.RegisterEvent, events, "PLAYER_TALENT_UPDATE")
pcall(events.RegisterEvent, events, "BAG_UPDATE_DELAYED")
-- arg2/arg3 are read by exactly one event: UNIT_SPELLCAST_START hands over
-- (unit, castGUID, spellID), and the spell ID is what tells the inbound-heal
-- forecast WHICH RANK is in the air — the difference between a downranked
-- filler and the real thing.
events:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
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
        -- Class-independent and read once: nothing here is ever learned or
        -- untrained, so it does not ride SPELLS_CHANGED with the book above
        util.ResolveBGBook()
        util.ResolveBindables()
        util.MigrateBinds()
        EnsureSettingsButton()
        blizz.EnsureButton()
        near.EnsureButton()
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
        -- The switcher popouts offer what you have TRAINED, so they are
        -- rebuilt exactly where every other trained-spell answer is: at login
        -- and on SPELLS_CHANGED. Not in BindMageUtilityButtons, which is
        -- gated on the mage's own cluster existing and so never ran for a
        -- paladin at all.
        util.EnsureSwitchers()
        util.BindSwitchers()
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
            for _, id in ipairs(MUTED_IDS) do
                local n = GetSpellInfo(id)
                if n then mutedNames[n] = true end
            end
            util.ResolveForecast()
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
    elseif event == "UNIT_SPELLCAST_START" then
        util.NoteCast(arg1, type(arg3) == "number" and arg3 or nil)
        if testUntil == 0 then Draw() end
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_SUCCEEDED"
        or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_FAILED_QUIET" then
        -- SUCCEEDED lands with the heal, so clearing here is not premature:
        -- the moment the cast completes its healing stops being "inbound" and
        -- starts being health the bar already shows.
        util.ClearCast(arg1)
        if testUntil == 0 then Draw() end
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
        if event == "PLAYER_ENTERING_WORLD" then
            util.enemyShadowUntil = 0
            -- Same reasoning: nothing that was ticking in the last arena is
            -- ticking in this one, and a roster change can strand a list on
            -- a GUID that has left. The learned amounts survive both.
            wipe(util.fc.on)
            wipe(util.fc.casts)
            wipe(util.overheal)
            -- Nothing was in flight when the loading screen started, and a
            -- session stranded across one would resolve into a loss you did
            -- not take. "We no longer know" is not the same as "it was lost",
            -- and only one of those is allowed to make a noise.
            util.PoMReset()
            -- The flag is the one mark on this board with no expiry of its
            -- own, so leaving the battleground is what ends it. Nobody from
            -- the last one is carrying anything into this zone.
            wipe(util.bgState)
            -- The spell data can still be cold at login; a battleground is
            -- the moment it stops being optional
            if not next(SDATA.BG_BY_NAME) then util.ResolveBGBook() end
        end
        -- A roster change can strand the nearby pick on someone who left, so
        -- it is invalidated here and re-taken by whichever of the two roster
        -- builders runs next (slot-preserving — the pick is not thrown away
        -- because one person quit). Entering a new world is the harder reset:
        -- nobody's old slot means anything in a battleground you just zoned
        -- into, so those go too and the next pick sorts from scratch.
        near.Invalidate()
        if event == "PLAYER_ENTERING_WORLD" then
            wipe(near.slots)
            wipe(near.held)
            near.stamp = 0
            near.pending = false
            near.PaintButton()
        end
        ScanGroup()
        if layer == "INT" then ScanSelfShields() end
        if securePool then SetupSecureRows() end
        if testUntil == 0 then Draw() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Left combat: safe to reconfigure secure rows/buttons queued mid-fight
        if securePool and secureDirty then SetupSecureRows() end
        if near.pending then near.pending = false; near.PaintButton() end
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
        -- The switcher popouts offer what you have TRAINED, so they are
        -- rebuilt exactly where every other trained-spell answer is: at login
        -- and on SPELLS_CHANGED. Not in BindMageUtilityButtons, which is
        -- gated on the mage's own cluster existing and so never ran for a
        -- paladin at all.
        util.EnsureSwitchers()
        util.BindSwitchers()
        BindMageUtilityButtons()
    end
end)
