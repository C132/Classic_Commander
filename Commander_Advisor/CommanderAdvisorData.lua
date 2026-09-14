-- Commander Advisor — the rulebook.
--
-- Pure data: no client API is touched here, so the engine harness can load it
-- under plain luajit. Everything the advisor can ever suggest is a RULE in
-- this file, and every rule is declarative — a spell (or item pattern), what
-- makes it pointless right now, and a ladder of TIERS each with the
-- conditions that earn it. The engine walks the ladder from the top and the
-- first rung whose conditions all hold is the tier the signal is raised at.
--
-- Conditions a rung may carry (all must hold — AND):
--   hp            player health fraction is AT OR BELOW this (scaled by Caution)
--   hpAbove       ... strictly above this (never scaled)
--   ttl           conservative seconds-to-die is at or below this (scaled)
--   combat        true / false — in combat or not
--   taking        true — hit by something in the last few seconds
--   melee         at least N distinct melee attackers on you right now
--   casters       at least N distinct spell attackers on you right now
--   attackers     at least N distinct attackers of any kind
--   enemyPlayers  at least N of those attackers are players
--   control       one of the control words below is on you
--   incomingCast  true (any hostile cast aimed at you) or a list of spell names
--   enemyClassNear a list of class tokens: a hostile player of one is in nameplate range
--   school        damage school word: most of the recent intake is this school
--   debuffType    "Magic" | "Curse" | "Disease" | "Poison" is on you
--   debuff        a named debuff is on you
--   aura          a named buff is on you;   notAura  a named buff is NOT on you
--   mana          mana fraction at or below;  petHp  pet health at or below
--   form          active stance/form name;  notForm  a list of forms you are NOT in
--   noForm        true — in no form at all (caster form)
--   shield        true — a shield is equipped
--   group         true / false — in a party or raid
--   pet           true — a pet is out
--   notCasting    true — not currently casting or channelling
--   notReady      a named spell is on cooldown (the backup-plan condition)
--   zone          a list of instance types: "arena", "pvp", "party", "raid", "none"
--
-- Control words: stunned, feared, silenced, rooted, snared, incapacitated,
-- disarmed, any.
--
-- Rule fields:
--   key        unique, stable — the saved per-rule mode is keyed by it
--   class      class token, or "ALL"
--   spell      a spell name, or a LIST of names (the first one you know is
--              the one named in the report; every one of them on a bar glows)
--   item       instead of spell: a Lua pattern matched against item names
--   petSpell   true — the spell lives in the pet's book (a macro casts it)
--   role       "maintain" (a buff to keep up), "react" (a defensive to press),
--              "cure" (something to remove), "escape"
--   family     for maintain rules: which buff family satisfies it (see FAMILIES)
--   blockedBy  debuff names on you that make the spell pointless right now
--   notWhile   buff names on you that mean it is already handled
--   requiresReady  spells that must be off cooldown for this to make sense
--   default    "AUTO" | "OFF" | "LOW" | "MEDIUM" | "HIGH" — the shipped mode
--   weight     tiebreak inside a tier: higher is listed (and glowed) first
--   tiers      the ladder, highest tier first
--   desc       one line for the settings page

CommanderAdvisor_Data = CommanderAdvisor_Data or {}
local D = CommanderAdvisor_Data

D.TIER_LOW, D.TIER_MEDIUM, D.TIER_HIGH = 1, 2, 3
D.TIER_NAMES = { "Low", "Medium", "High" }
D.MODES = { "AUTO", "OFF", "LOW", "MEDIUM", "HIGH" }

-- Damage school words -> the client's spellSchool bitmask
D.SCHOOL_MASK = {
    physical = 0x1, holy = 0x2, fire = 0x4, nature = 0x8,
    frost = 0x10, shadow = 0x20, arcane = 0x40,
}

-- Buff families: a maintain rule is satisfied by ANY member being on you.
-- Order inside a family is "best first" for the report's wording only.
D.FAMILIES = {
    PRIEST_INNER_FIRE   = { "Inner Fire" },
    PRIEST_FORTITUDE    = { "Prayer of Fortitude", "Power Word: Fortitude" },
    PRIEST_SPIRIT       = { "Prayer of Spirit", "Divine Spirit" },
    PRIEST_SHADOW_PROT  = { "Prayer of Shadow Protection", "Shadow Protection" },
    PRIEST_TOUCH        = { "Touch of Weakness" },
    PRIEST_SHADOWGUARD  = { "Shadowguard" },
    PRIEST_FEAR_WARD    = { "Fear Ward" },
    MAGE_ARMOR          = { "Molten Armor", "Mage Armor", "Ice Armor", "Frost Armor" },
    MAGE_INTELLECT      = { "Arcane Brilliance", "Arcane Intellect" },
    WARLOCK_ARMOR       = { "Fel Armor", "Demon Armor", "Demon Skin" },
    SHAMAN_SHIELD       = { "Earth Shield", "Water Shield", "Lightning Shield" },
    DRUID_MARK          = { "Gift of the Wild", "Mark of the Wild" },
    DRUID_THORNS        = { "Thorns" },
    PALADIN_BLESSING    = {
        "Greater Blessing of Kings", "Greater Blessing of Might", "Greater Blessing of Wisdom",
        "Greater Blessing of Salvation", "Greater Blessing of Light", "Greater Blessing of Sanctuary",
        "Blessing of Kings", "Blessing of Might", "Blessing of Wisdom",
        "Blessing of Salvation", "Blessing of Light", "Blessing of Sanctuary",
    },
    PALADIN_SEAL        = {
        "Seal of Righteousness", "Seal of the Crusader", "Seal of Justice", "Seal of Light",
        "Seal of Wisdom", "Seal of Command", "Seal of Blood", "Seal of Vengeance",
    },
    PALADIN_AURA        = {
        "Devotion Aura", "Retribution Aura", "Concentration Aura", "Sanctity Aura",
        "Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura", "Crusader Aura",
    },
    PALADIN_RF          = { "Righteous Fury" },
    HUNTER_ASPECT       = {
        "Aspect of the Hawk", "Aspect of the Viper", "Aspect of the Monkey", "Aspect of the Cheetah",
        "Aspect of the Pack", "Aspect of the Beast", "Aspect of the Wild",
    },
    HUNTER_TRUESHOT     = { "Trueshot Aura" },
    WARRIOR_SHOUT       = { "Commanding Shout", "Battle Shout" },
}

-- Fear effects an enemy can be seen CASTING at you. A ward or an immunity is
-- worth pressing while the bar is still filling; after that it is too late.
D.FEAR_CASTS = { "Fear", "Psychic Scream", "Howl of Terror", "Intimidating Shout", "Scare Beast", "Seduction" }
-- Classes that carry a fear: a ward or a totem is worth having up BEFORE
-- one of these is standing next to you
D.FEAR_CLASSES = { "WARLOCK", "PRIEST", "WARRIOR" }

-- Casts you can see coming, by school: a ward pressed while the bar is still
-- filling eats the bolt; pressed after, it eats the next one
D.FIRE_CASTS   = { "Fireball", "Pyroblast", "Scorch", "Flamestrike", "Immolate", "Searing Pain", "Soul Fire", "Incinerate", "Lava Burst", "Flame Shock" }
D.FROST_CASTS  = { "Frostbolt", "Frost Shock", "Blizzard", "Cone of Cold", "Ice Lance" }
D.SHADOW_CASTS = { "Shadow Bolt", "Mind Blast", "Mind Flay", "Shadow Word: Death", "Death Coil", "Shadowburn", "Drain Life", "Drain Soul", "Corruption", "Curse of Agony", "Vampiric Touch" }


-- Snares: the loss-of-control API reports stuns, fears, roots and silences,
-- and says nothing about a slow. These are read off your own debuffs.
D.SNARES = {
    "Hamstring", "Wing Clip", "Crippling Poison", "Frost Shock", "Chilled", "Cone of Cold",
    "Concussive Shot", "Earthbind", "Curse of Exhaustion", "Dazed", "Piercing Howl",
    "Frostbolt", "Slow", "Mind Flay", "Thunder Clap", "Frost Trap Aura", "Frostbrand Attack",
    "Deadly Throw", "Chains of Ice", "Frost Nova",
}
D.SNARE_SET = {}
for _, name in ipairs(D.SNARES) do D.SNARE_SET[name] = true end

local BEAR = { "Bear Form", "Dire Bear Form" }
local MOVE_FORMS = { "Cat Form", "Travel Form", "Bear Form", "Dire Bear Form" }

-- ---------------------------------------------------------------------------
-- The rules. Health fractions here are the SHIPPED thresholds; the Caution
-- setting scales them down (more conservative) or up. Where a rung says
-- taking=true the rule is only ever raised while something is actually
-- hitting you — a dented health bar on its own is not an emergency.
-- ---------------------------------------------------------------------------
D.RULES = {

    -- ===== Everyone =========================================================
    { key = "ALL_HEALTH_ITEM", class = "ALL", role = "react", weight = 60,
      item = "Healing Potion$|Healthstone$", default = "AUTO",
      desc = "A healing potion or healthstone on your bar, when your health is low and something is hitting you.",
      tiers = {
        { tier = 3, hp = 0.30, taking = true },
        { tier = 2, hp = 0.50, taking = true },
      } },
    { key = "ALL_PVP_TRINKET", class = "ALL", role = "escape", weight = 100,
      item = "^Medallion of the |^Insignia of the ", default = "AUTO",
      desc = "Your PvP trinket while you are stunned, feared, silenced or otherwise held — the one button that works when nothing else does.",
      tiers = {
        { tier = 3, control = "any", hp = 0.60 },
        { tier = 2, control = "any" },
      } },
    { key = "ALL_BANDAGE", class = "ALL", role = "react", weight = 5,
      item = "Bandage$", default = "AUTO", blockedBy = { "Recently Bandaged" },
      desc = "A bandage when you are hurt and nothing has hit you for a few seconds — a bandage under fire is a wasted bandage.",
      tiers = {
        { tier = 1, hp = 0.60, notTaking = true, notCasting = true },
      } },

    -- ===== Priest ===========================================================
    { key = "PRIEST_INNER_FIRE", class = "PRIEST", role = "maintain", family = "PRIEST_INNER_FIRE", weight = 30,
      spell = "Inner Fire", default = "AUTO",
      desc = "Inner Fire — armour you should never be without.",
      tiers = {
        { tier = 2, combat = true, melee = 1 },
        { tier = 1 },
      } },
    { key = "PRIEST_FORTITUDE", class = "PRIEST", role = "maintain", family = "PRIEST_FORTITUDE", weight = 28,
      spell = { "Power Word: Fortitude", "Prayer of Fortitude" }, default = "AUTO",
      desc = "Power Word: Fortitude on yourself.",
      tiers = {
        { tier = 2, combat = true, taking = true },
        { tier = 1 },
      } },
    { key = "PRIEST_SPIRIT", class = "PRIEST", role = "maintain", family = "PRIEST_SPIRIT", weight = 20,
      spell = { "Divine Spirit", "Prayer of Spirit" }, default = "AUTO",
      desc = "Divine Spirit on yourself, if you have trained it.",
      tiers = {
        { tier = 1, combat = false },
      } },
    { key = "PRIEST_SHADOW_PROT", class = "PRIEST", role = "maintain", family = "PRIEST_SHADOW_PROT", weight = 22,
      spell = { "Shadow Protection", "Prayer of Shadow Protection" }, default = "AUTO",
      desc = "Shadow Protection — raised only when shadow is being cast at you or is what is actually landing on you.",
      tiers = {
        { tier = 2, combat = true, school = "shadow" },
        { tier = 2, incomingCast = D.SHADOW_CASTS },
        { tier = 1, combat = false, school = "shadow" },
      } },
    { key = "PRIEST_TOUCH", class = "PRIEST", role = "maintain", family = "PRIEST_TOUCH", weight = 24,
      spell = "Touch of Weakness", default = "AUTO",
      desc = "Touch of Weakness (Forsaken) — blunts the next melee hit on you.",
      tiers = {
        { tier = 2, combat = true, melee = 1 },
        { tier = 1 },
      } },
    { key = "PRIEST_SHADOWGUARD", class = "PRIEST", role = "maintain", family = "PRIEST_SHADOWGUARD", weight = 24,
      spell = "Shadowguard", default = "AUTO",
      desc = "Shadowguard (Troll) — three charges of shadow damage back at whoever hits you.",
      tiers = {
        { tier = 2, combat = true, melee = 1 },
        { tier = 1 },
      } },
    { key = "PRIEST_FEAR_WARD", class = "PRIEST", role = "maintain", family = "PRIEST_FEAR_WARD", weight = 40,
      spell = "Fear Ward", default = "AUTO",
      desc = "Fear Ward on yourself: kept up in PvP, and shouted for when an enemy is casting a fear at you.",
      tiers = {
        { tier = 3, incomingCast = D.FEAR_CASTS },
        { tier = 2, enemyClassNear = D.FEAR_CLASSES, combat = true },
        { tier = 1, enemyClassNear = D.FEAR_CLASSES },
        { tier = 1, zone = { "arena", "pvp" } },
      } },
    { key = "PRIEST_PWS", class = "PRIEST", role = "react", weight = 90,
      spell = "Power Word: Shield", default = "AUTO",
      blockedBy = { "Weakened Soul" }, notWhile = { "Power Word: Shield" },
      desc = "Power Word: Shield on yourself while you are being hit and Weakened Soul is not on you.",
      tiers = {
        { tier = 3, hp = 0.40, taking = true },
        { tier = 3, ttl = 6, hpBelowCeiling = true },
        { tier = 2, hp = 0.75, taking = true },
        { tier = 1, combat = true, taking = true },
      } },
    { key = "PRIEST_RENEW", class = "PRIEST", role = "react", weight = 50,
      spell = "Renew", default = "AUTO", notWhileMine = { "Renew" },
      desc = "Renew on yourself when you are hurt and your own Renew is not already rolling.",
      tiers = {
        { tier = 2, hp = 0.60, taking = true },
        { tier = 1, hp = 0.80, combat = true },
        { tier = 1, hp = 0.60, combat = false },
      } },
    { key = "PRIEST_FLASH_HEAL", class = "PRIEST", role = "react", weight = 70,
      spell = { "Flash Heal", "Greater Heal", "Heal", "Lesser Heal" }, default = "AUTO",
      desc = "A direct heal on yourself when the shield is not enough — raised only when you are not already casting.",
      tiers = {
        { tier = 3, hp = 0.30, taking = true, notCasting = true },
        { tier = 2, hp = 0.50, taking = true, notCasting = true },
      } },
    { key = "PRIEST_DESPERATE", class = "PRIEST", role = "react", weight = 95,
      spell = "Desperate Prayer", default = "AUTO",
      desc = "Desperate Prayer — the instant, free heal for when it has gone wrong.",
      tiers = {
        { tier = 3, hp = 0.35, taking = true },
        { tier = 3, ttl = 5, hpBelowCeiling = true },
      } },
    { key = "PRIEST_PAIN_SUPP", class = "PRIEST", role = "react", weight = 96,
      spell = "Pain Suppression", default = "AUTO",
      desc = "Pain Suppression on yourself under real pressure.",
      tiers = {
        { tier = 3, hp = 0.40, taking = true },
        { tier = 3, ttl = 6, hpBelowCeiling = true },
      } },
    { key = "PRIEST_SCREAM", class = "PRIEST", role = "escape", weight = 80,
      spell = "Psychic Scream", default = "AUTO",
      desc = "Psychic Scream when melee are on you and you are losing.",
      tiers = {
        { tier = 3, hp = 0.35, melee = 1 },
        { tier = 2, hp = 0.65, melee = 2 },
        { tier = 2, hp = 0.50, melee = 1 },
      } },
    { key = "PRIEST_FADE", class = "PRIEST", role = "escape", weight = 20,
      spell = "Fade", default = "AUTO",
      desc = "Fade when something has turned on you in a group — hand the threat back.",
      tiers = {
        { tier = 2, group = true, attackers = 1, hp = 0.60, enemyPlayers = 0 },
        { tier = 1, group = true, attackers = 1, enemyPlayers = 0 },
      } },
    { key = "PRIEST_ELUNES", class = "PRIEST", role = "react", weight = 45,
      spell = "Elune's Grace", default = "AUTO", notWhile = { "Elune's Grace" },
      desc = "Elune's Grace (Night Elf) when melee or ranged attacks are landing on you.",
      tiers = {
        { tier = 2, melee = 1, hp = 0.70 },
        { tier = 1, melee = 1 },
      } },
    { key = "PRIEST_DISPEL", class = "PRIEST", role = "cure", weight = 35,
      spell = "Dispel Magic", default = "AUTO",
      desc = "Dispel Magic on yourself when a magic debuff is on you.",
      tiers = {
        { tier = 2, debuffType = "Magic", combat = true },
        { tier = 1, debuffType = "Magic" },
      } },
    { key = "PRIEST_DISEASE", class = "PRIEST", role = "cure", weight = 30,
      spell = { "Abolish Disease", "Cure Disease" }, default = "AUTO",
      desc = "Cure or Abolish Disease on yourself.",
      tiers = {
        { tier = 2, debuffType = "Disease", combat = true, hp = 0.70 },
        { tier = 1, debuffType = "Disease" },
      } },
    { key = "PRIEST_SYMBOL", class = "PRIEST", role = "react", weight = 10,
      spell = "Symbol of Hope", default = "AUTO",
      desc = "Symbol of Hope (Draenei) when the mana is running out mid-fight.",
      tiers = {
        { tier = 1, combat = true, mana = 0.20 },
      } },

    -- ===== Mage =============================================================
    { key = "MAGE_ARMOR", class = "MAGE", role = "maintain", family = "MAGE_ARMOR", weight = 30,
      spell = { "Molten Armor", "Mage Armor", "Ice Armor", "Frost Armor" }, default = "AUTO",
      desc = "An armor spell — any of the four.",
      tiers = {
        { tier = 2, combat = true, taking = true },
        { tier = 1 },
      } },
    { key = "MAGE_INTELLECT", class = "MAGE", role = "maintain", family = "MAGE_INTELLECT", weight = 20,
      spell = { "Arcane Intellect", "Arcane Brilliance" }, default = "AUTO",
      desc = "Arcane Intellect on yourself.",
      tiers = {
        { tier = 1, combat = false },
      } },
    { key = "MAGE_ICE_BLOCK", class = "MAGE", role = "react", weight = 100,
      spell = "Ice Block", default = "AUTO", blockedBy = { "Hypothermia" },
      desc = "Ice Block when you are about to die.",
      tiers = {
        { tier = 3, hp = 0.30, taking = true },
        { tier = 3, ttl = 5, hpBelowCeiling = true },
      } },
    { key = "MAGE_COLD_SNAP", class = "MAGE", role = "react", weight = 99,
      spell = "Cold Snap", default = "AUTO", notReady = "Ice Block",
      desc = "Cold Snap when you need a second Ice Block and the first is on cooldown.",
      tiers = {
        { tier = 3, hp = 0.30, taking = true },
      } },
    { key = "MAGE_ICE_BARRIER", class = "MAGE", role = "react", weight = 70,
      spell = "Ice Barrier", default = "AUTO", notWhile = { "Ice Barrier" },
      desc = "Ice Barrier whenever it is down in combat, louder while you are being hit.",
      tiers = {
        { tier = 3, hp = 0.40, taking = true },
        { tier = 2, taking = true },
        { tier = 1, combat = true },
      } },
    { key = "MAGE_MANA_SHIELD", class = "MAGE", role = "react", weight = 40,
      spell = "Mana Shield", default = "AUTO", notWhile = { "Mana Shield", "Ice Barrier" },
      desc = "Mana Shield when you are being hit and have mana to spend on staying alive.",
      tiers = {
        { tier = 2, hp = 0.50, taking = true, manaAbove = 0.30 },
        { tier = 1, hp = 0.75, taking = true, manaAbove = 0.50 },
      } },
    { key = "MAGE_FROST_NOVA", class = "MAGE", role = "escape", weight = 75,
      spell = "Frost Nova", default = "AUTO",
      desc = "Frost Nova when melee are on you.",
      tiers = {
        { tier = 3, hp = 0.35, melee = 1 },
        { tier = 2, hp = 0.70, melee = 1 },
        { tier = 2, melee = 2 },
        { tier = 1, melee = 1 },
      } },
    { key = "MAGE_BLINK", class = "MAGE", role = "escape", weight = 72,
      spell = "Blink", default = "AUTO",
      desc = "Blink out of a root, or away from a pack of melee.",
      tiers = {
        { tier = 2, control = "rooted" },
        { tier = 2, hp = 0.50, melee = 2 },
        { tier = 1, hp = 0.50, melee = 1 },
      } },
    { key = "MAGE_FIRE_WARD", class = "MAGE", role = "react", weight = 50,
      spell = "Fire Ward", default = "AUTO", notWhile = { "Fire Ward" },
      desc = "Fire Ward while a fire spell is being cast at you, or when fire is what is landing on you.",
      tiers = {
        { tier = 2, incomingCast = D.FIRE_CASTS },
        { tier = 2, school = "fire", taking = true },
      } },
    { key = "MAGE_FROST_WARD", class = "MAGE", role = "react", weight = 50,
      spell = "Frost Ward", default = "AUTO", notWhile = { "Frost Ward" },
      desc = "Frost Ward while a frost spell is being cast at you, or when frost is what is landing on you.",
      tiers = {
        { tier = 2, incomingCast = D.FROST_CASTS },
        { tier = 2, school = "frost", taking = true },
      } },
    { key = "MAGE_DECURSE", class = "MAGE", role = "cure", weight = 30,
      spell = "Remove Lesser Curse", default = "AUTO",
      desc = "Remove Lesser Curse on yourself.",
      tiers = {
        { tier = 2, debuffType = "Curse", combat = true },
        { tier = 1, debuffType = "Curse" },
      } },
    { key = "MAGE_INVIS", class = "MAGE", role = "escape", weight = 60,
      spell = "Invisibility", default = "AUTO",
      desc = "Invisibility when you have to leave a fight you are losing.",
      tiers = {
        { tier = 2, hp = 0.35, attackers = 1 },
      } },
    { key = "MAGE_EVOCATION", class = "MAGE", role = "react", weight = 10,
      spell = "Evocation", default = "AUTO",
      desc = "Evocation when the mana is gone and nothing is hitting you.",
      tiers = {
        { tier = 1, mana = 0.15, notTaking = true },
      } },

    -- ===== Warlock ==========================================================
    { key = "WARLOCK_ARMOR", class = "WARLOCK", role = "maintain", family = "WARLOCK_ARMOR", weight = 30,
      spell = { "Fel Armor", "Demon Armor", "Demon Skin" }, default = "AUTO",
      desc = "Demon Armor, Fel Armor or Demon Skin.",
      tiers = {
        { tier = 2, combat = true, taking = true },
        { tier = 1 },
      } },
    { key = "WARLOCK_DEATH_COIL", class = "WARLOCK", role = "react", weight = 85,
      spell = "Death Coil", default = "AUTO",
      desc = "Death Coil — a heal and three seconds of peace.",
      tiers = {
        { tier = 3, hp = 0.35, taking = true },
        { tier = 2, hp = 0.55, melee = 1 },
      } },
    { key = "WARLOCK_SHADOW_WARD", class = "WARLOCK", role = "react", weight = 50,
      spell = "Shadow Ward", default = "AUTO", notWhile = { "Shadow Ward" },
      desc = "Shadow Ward while a shadow spell is being cast at you, or when shadow is what is landing on you.",
      tiers = {
        { tier = 2, incomingCast = D.SHADOW_CASTS },
        { tier = 2, school = "shadow", taking = true },
      } },
    { key = "WARLOCK_FEAR", class = "WARLOCK", role = "escape", weight = 70,
      spell = "Fear", default = "AUTO",
      desc = "Fear the melee that is on you.",
      tiers = {
        { tier = 2, hp = 0.60, melee = 1 },
        { tier = 1, melee = 1 },
      } },
    { key = "WARLOCK_HOWL", class = "WARLOCK", role = "escape", weight = 80,
      spell = "Howl of Terror", default = "AUTO",
      desc = "Howl of Terror when more than one melee is on you.",
      tiers = {
        { tier = 3, hp = 0.35, melee = 1 },
        { tier = 2, hp = 0.65, melee = 2 },
      } },
    { key = "WARLOCK_DRAIN_LIFE", class = "WARLOCK", role = "react", weight = 40,
      spell = "Drain Life", default = "AUTO",
      desc = "Drain Life when you are hurt and have a target to drain.",
      tiers = {
        { tier = 2, hp = 0.50, taking = true, hasTarget = true, notCasting = true },
        { tier = 1, hp = 0.70, combat = true, hasTarget = true, notCasting = true },
      } },
    { key = "WARLOCK_SACRIFICE", class = "WARLOCK", role = "react", weight = 90,
      spell = "Sacrifice", petSpell = true, default = "AUTO",
      desc = "The Voidwalker's Sacrifice, when it is out and you are about to die.",
      tiers = {
        { tier = 3, hp = 0.35, taking = true, pet = true },
      } },
    { key = "WARLOCK_SOULSHATTER", class = "WARLOCK", role = "escape", weight = 20,
      spell = "Soulshatter", default = "AUTO",
      desc = "Soulshatter when something has turned on you in a group.",
      tiers = {
        { tier = 2, group = true, attackers = 1, hp = 0.60, enemyPlayers = 0 },
        { tier = 1, group = true, attackers = 1, enemyPlayers = 0 },
      } },

    -- ===== Shaman ===========================================================
    { key = "SHAMAN_SHIELD", class = "SHAMAN", role = "maintain", family = "SHAMAN_SHIELD", weight = 30,
      spell = { "Water Shield", "Lightning Shield", "Earth Shield" }, default = "AUTO",
      desc = "A shield — Lightning, Water or Earth — on yourself.",
      tiers = {
        { tier = 2, combat = true, taking = true },
        { tier = 1 },
      } },
    { key = "SHAMAN_HEAL", class = "SHAMAN", role = "react", weight = 70,
      spell = { "Lesser Healing Wave", "Healing Wave" }, default = "AUTO",
      desc = "A heal on yourself when you are losing the trade.",
      tiers = {
        { tier = 3, hp = 0.30, taking = true, notCasting = true },
        { tier = 2, hp = 0.50, taking = true, notCasting = true },
      } },
    { key = "SHAMAN_NS", class = "SHAMAN", role = "react", weight = 95,
      spell = "Nature's Swiftness", default = "AUTO", notWhile = { "Nature's Swiftness" },
      desc = "Nature's Swiftness for an instant heal when it is about to go wrong.",
      tiers = {
        { tier = 3, hp = 0.35, taking = true },
        { tier = 3, ttl = 6, hpBelowCeiling = true },
      } },
    { key = "SHAMAN_GROUNDING", class = "SHAMAN", role = "react", weight = 60,
      spell = "Grounding Totem", default = "AUTO",
      desc = "Grounding Totem when a caster is on you — louder when a cast is actually aimed at you.",
      tiers = {
        { tier = 2, incomingCast = true },
        { tier = 1, casters = 1 },
      } },
    { key = "SHAMAN_RAGE", class = "SHAMAN", role = "react", weight = 65,
      spell = "Shamanistic Rage", default = "AUTO", notWhile = { "Shamanistic Rage" },
      desc = "Shamanistic Rage under pressure — damage taken down, mana back.",
      tiers = {
        { tier = 3, hp = 0.35, taking = true },
        { tier = 2, hp = 0.60, taking = true },
      } },
    { key = "SHAMAN_STONECLAW", class = "SHAMAN", role = "escape", weight = 30,
      spell = "Stoneclaw Totem", default = "AUTO",
      desc = "Stoneclaw Totem when a pack of melee is on you.",
      tiers = {
        { tier = 1, melee = 2, enemyPlayers = 0 },
      } },
    { key = "SHAMAN_EARTHBIND", class = "SHAMAN", role = "escape", weight = 35,
      spell = "Earthbind Totem", default = "AUTO",
      desc = "Earthbind Totem to slow the melee that are on you.",
      tiers = {
        { tier = 2, hp = 0.50, melee = 1 },
        { tier = 1, melee = 1 },
      } },
    { key = "SHAMAN_TREMOR", class = "SHAMAN", role = "react", weight = 55,
      spell = "Tremor Totem", default = "AUTO",
      desc = "Tremor Totem while an enemy is casting a fear at you, or a fear-carrying class is close.",
      tiers = {
        { tier = 3, incomingCast = D.FEAR_CASTS },
        { tier = 1, enemyClassNear = D.FEAR_CLASSES, combat = true },
      } },
    { key = "SHAMAN_CURE_POISON", class = "SHAMAN", role = "cure", weight = 30,
      spell = { "Cure Poison", "Poison Cleansing Totem" }, default = "AUTO",
      desc = "Cure Poison on yourself.",
      tiers = {
        { tier = 2, debuffType = "Poison", combat = true, hp = 0.70 },
        { tier = 1, debuffType = "Poison" },
      } },
    { key = "SHAMAN_CURE_DISEASE", class = "SHAMAN", role = "cure", weight = 30,
      spell = { "Cure Disease", "Disease Cleansing Totem" }, default = "AUTO",
      desc = "Cure Disease on yourself.",
      tiers = {
        { tier = 2, debuffType = "Disease", combat = true, hp = 0.70 },
        { tier = 1, debuffType = "Disease" },
      } },
    { key = "SHAMAN_RESIST_TOTEM", class = "SHAMAN", role = "react", weight = 15,
      spell = { "Fire Resistance Totem", "Frost Resistance Totem", "Nature Resistance Totem" }, default = "AUTO",
      schoolBySpell = { ["Fire Resistance Totem"] = "fire", ["Frost Resistance Totem"] = "frost", ["Nature Resistance Totem"] = "nature" },
      desc = "A resistance totem for the school that is actually hurting you.",
      tiers = {
        { tier = 1, taking = true, combat = true },
      } },

    -- ===== Druid ============================================================
    { key = "DRUID_MARK", class = "DRUID", role = "maintain", family = "DRUID_MARK", weight = 28,
      spell = { "Mark of the Wild", "Gift of the Wild" }, default = "AUTO",
      desc = "Mark of the Wild on yourself.",
      tiers = {
        { tier = 1, combat = false, noForm = true },
      } },
    { key = "DRUID_THORNS", class = "DRUID", role = "maintain", family = "DRUID_THORNS", weight = 15,
      spell = "Thorns", default = "OFF",
      desc = "Thorns on yourself when melee are on you. Off by default — most druids would rather spend the global.",
      tiers = {
        { tier = 1, melee = 1, noForm = true },
      } },
    { key = "DRUID_BARKSKIN", class = "DRUID", role = "react", weight = 90,
      spell = "Barkskin", default = "AUTO", notWhile = { "Barkskin" },
      desc = "Barkskin under pressure — it works in every form.",
      tiers = {
        { tier = 3, hp = 0.40, taking = true },
        { tier = 2, hp = 0.65, taking = true },
      } },
    { key = "DRUID_REJUV", class = "DRUID", role = "react", weight = 50,
      spell = "Rejuvenation", default = "AUTO", notWhileMine = { "Rejuvenation" },
      desc = "Rejuvenation on yourself when hurt, in caster form.",
      tiers = {
        { tier = 2, hp = 0.60, taking = true, noForm = true },
        { tier = 1, hp = 0.80, combat = true, noForm = true },
        { tier = 1, hp = 0.60, combat = false, noForm = true },
      } },
    { key = "DRUID_REGROWTH", class = "DRUID", role = "react", weight = 70,
      spell = { "Regrowth", "Healing Touch" }, default = "AUTO",
      desc = "A direct heal on yourself in caster form when a hot is not enough.",
      tiers = {
        { tier = 3, hp = 0.30, taking = true, noForm = true, notCasting = true },
        { tier = 2, hp = 0.50, taking = true, noForm = true, notCasting = true },
      } },
    { key = "DRUID_NS", class = "DRUID", role = "react", weight = 95,
      spell = "Nature's Swiftness", default = "AUTO", notWhile = { "Nature's Swiftness" },
      desc = "Nature's Swiftness for an instant Healing Touch when it is about to go wrong.",
      tiers = {
        { tier = 3, hp = 0.35, taking = true, noForm = true },
      } },
    { key = "DRUID_BEAR", class = "DRUID", role = "react", weight = 85,
      spell = { "Dire Bear Form", "Bear Form" }, default = "AUTO",
      desc = "Bear when you are about to die in a squishier form.",
      tiers = {
        { tier = 3, hp = 0.30, taking = true, notForm = BEAR },
        { tier = 2, hp = 0.45, melee = 1, notForm = BEAR },
      } },
    { key = "DRUID_FRENZIED", class = "DRUID", role = "react", weight = 88,
      spell = "Frenzied Regeneration", default = "AUTO", notWhile = { "Frenzied Regeneration" },
      desc = "Frenzied Regeneration in bear form when the bar is low.",
      tiers = {
        { tier = 3, hp = 0.35, taking = true, form = BEAR },
        { tier = 2, hp = 0.55, taking = true, form = BEAR },
      } },
    { key = "DRUID_GRASP", class = "DRUID", role = "escape", weight = 60,
      spell = "Nature's Grasp", default = "AUTO", notWhile = { "Nature's Grasp" },
      desc = "Nature's Grasp when melee are on you in caster form.",
      tiers = {
        { tier = 2, hp = 0.70, melee = 1, noForm = true },
        { tier = 1, melee = 1, noForm = true },
      } },
    { key = "DRUID_SHIFT_ROOT", class = "DRUID", role = "escape", weight = 75,
      spell = MOVE_FORMS, default = "AUTO",
      desc = "Shift out of a root or a snare — a shapeshift breaks both.",
      tiers = {
        { tier = 2, control = "rooted" },
        { tier = 1, control = "snared" },
      } },
    { key = "DRUID_ROOTS", class = "DRUID", role = "escape", weight = 40,
      spell = "Entangling Roots", default = "AUTO",
      desc = "Entangling Roots on the melee that is on you, in caster form.",
      tiers = {
        { tier = 1, hp = 0.60, melee = 1, noForm = true, outdoors = true },
      } },
    { key = "DRUID_CURE_POISON", class = "DRUID", role = "cure", weight = 30,
      spell = { "Abolish Poison", "Cure Poison" }, default = "AUTO",
      desc = "Cure or Abolish Poison on yourself.",
      tiers = {
        { tier = 2, debuffType = "Poison", combat = true, hp = 0.70, noForm = true },
        { tier = 1, debuffType = "Poison", noForm = true },
      } },
    { key = "DRUID_DECURSE", class = "DRUID", role = "cure", weight = 30,
      spell = "Remove Curse", default = "AUTO",
      desc = "Remove Curse on yourself.",
      tiers = {
        { tier = 2, debuffType = "Curse", combat = true, noForm = true },
        { tier = 1, debuffType = "Curse", noForm = true },
      } },
    { key = "DRUID_INNERVATE", class = "DRUID", role = "react", weight = 10,
      spell = "Innervate", default = "AUTO",
      desc = "Innervate yourself when the mana is gone mid-fight.",
      tiers = {
        { tier = 1, combat = true, mana = 0.15, noForm = true },
      } },

    -- ===== Paladin ==========================================================
    { key = "PALADIN_BLESSING", class = "PALADIN", role = "maintain", family = "PALADIN_BLESSING", weight = 28,
      spell = { "Blessing of Kings", "Blessing of Might", "Blessing of Wisdom", "Blessing of Sanctuary",
                "Blessing of Light", "Blessing of Salvation" }, default = "AUTO",
      desc = "A blessing on yourself.",
      tiers = {
        { tier = 1 },
      } },
    { key = "PALADIN_SEAL", class = "PALADIN", role = "maintain", family = "PALADIN_SEAL", weight = 30,
      spell = { "Seal of Righteousness", "Seal of Command", "Seal of Blood", "Seal of Vengeance",
                "Seal of the Crusader", "Seal of Light", "Seal of Wisdom", "Seal of Justice" }, default = "AUTO",
      desc = "A seal, in combat, when none is up.",
      tiers = {
        { tier = 1, combat = true },
      } },
    { key = "PALADIN_AURA", class = "PALADIN", role = "maintain", family = "PALADIN_AURA", weight = 26,
      spell = { "Devotion Aura", "Retribution Aura", "Concentration Aura", "Sanctity Aura" }, default = "AUTO",
      desc = "An aura, when none is up.",
      tiers = {
        { tier = 1 },
      } },
    { key = "PALADIN_RF", class = "PALADIN", role = "maintain", family = "PALADIN_RF", weight = 10,
      spell = "Righteous Fury", default = "OFF",
      desc = "Righteous Fury. Off by default — only a tank wants to be reminded.",
      tiers = {
        { tier = 1, group = true },
      } },
    { key = "PALADIN_BUBBLE", class = "PALADIN", role = "react", weight = 100,
      spell = "Divine Shield", default = "AUTO", blockedBy = { "Forbearance" },
      desc = "Divine Shield when you are about to die.",
      tiers = {
        { tier = 3, hp = 0.30, taking = true },
        { tier = 3, ttl = 5, hpBelowCeiling = true },
      } },
    { key = "PALADIN_DIVINE_PROT", class = "PALADIN", role = "react", weight = 92,
      spell = "Divine Protection", default = "AUTO", blockedBy = { "Forbearance" },
      desc = "Divine Protection when you are about to die.",
      tiers = {
        { tier = 3, hp = 0.35, taking = true },
      } },
    { key = "PALADIN_LOH", class = "PALADIN", role = "react", weight = 98,
      spell = "Lay on Hands", default = "AUTO", blockedBy = { "Forbearance" },
      desc = "Lay on Hands on yourself at the very end.",
      tiers = {
        { tier = 3, hp = 0.20, taking = true },
      } },
    { key = "PALADIN_BOP", class = "PALADIN", role = "react", weight = 90,
      spell = "Blessing of Protection", default = "AUTO", blockedBy = { "Forbearance" }, notReady = "Divine Shield",
      desc = "Blessing of Protection on yourself against melee, when the bubble is on cooldown.",
      tiers = {
        { tier = 3, hp = 0.35, melee = 1 },
      } },
    { key = "PALADIN_HEAL", class = "PALADIN", role = "react", weight = 70,
      spell = { "Flash of Light", "Holy Light" }, default = "AUTO",
      desc = "A heal on yourself when you are losing the trade.",
      tiers = {
        { tier = 3, hp = 0.30, taking = true, notCasting = true },
        { tier = 2, hp = 0.50, taking = true, notCasting = true },
      } },
    { key = "PALADIN_HOJ", class = "PALADIN", role = "escape", weight = 60,
      spell = "Hammer of Justice", default = "AUTO",
      desc = "Hammer of Justice on the melee that is on you when you are losing.",
      tiers = {
        { tier = 2, hp = 0.50, melee = 1 },
      } },
    { key = "PALADIN_FREEDOM", class = "PALADIN", role = "escape", weight = 65,
      spell = "Blessing of Freedom", default = "AUTO", notWhile = { "Blessing of Freedom" },
      desc = "Blessing of Freedom when you are rooted or snared.",
      tiers = {
        { tier = 2, control = "rooted" },
        { tier = 1, control = "snared" },
      } },
    { key = "PALADIN_CLEANSE", class = "PALADIN", role = "cure", weight = 30,
      spell = { "Cleanse", "Purify" }, default = "AUTO",
      desc = "Cleanse or Purify on yourself.",
      tiers = {
        { tier = 2, debuffType = "Magic", combat = true },
        { tier = 1, debuffType = "Magic" },
        { tier = 1, debuffType = "Poison" },
        { tier = 1, debuffType = "Disease" },
      } },
    { key = "PALADIN_HOLY_SHIELD", class = "PALADIN", role = "react", weight = 55,
      spell = "Holy Shield", default = "AUTO", notWhile = { "Holy Shield" },
      desc = "Holy Shield with a shield equipped and melee on you.",
      tiers = {
        { tier = 2, melee = 1, shield = true },
      } },
    { key = "PALADIN_RESIST_AURA", class = "PALADIN", role = "react", weight = 15,
      spell = { "Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura" }, default = "AUTO",
      schoolBySpell = { ["Shadow Resistance Aura"] = "shadow", ["Frost Resistance Aura"] = "frost", ["Fire Resistance Aura"] = "fire" },
      desc = "A resistance aura for the school that is actually hurting you.",
      tiers = {
        { tier = 1, taking = true, combat = true },
      } },

    -- ===== Hunter ===========================================================
    { key = "HUNTER_ASPECT", class = "HUNTER", role = "maintain", family = "HUNTER_ASPECT", weight = 30,
      spell = { "Aspect of the Hawk", "Aspect of the Viper", "Aspect of the Monkey", "Aspect of the Cheetah" }, default = "AUTO",
      desc = "An aspect, when none is up.",
      tiers = {
        { tier = 2, combat = true },
        { tier = 1 },
      } },
    { key = "HUNTER_TRUESHOT", class = "HUNTER", role = "maintain", family = "HUNTER_TRUESHOT", weight = 20,
      spell = "Trueshot Aura", default = "AUTO",
      desc = "Trueshot Aura, if you have trained it.",
      tiers = {
        { tier = 1, combat = false },
      } },
    { key = "HUNTER_FEIGN", class = "HUNTER", role = "escape", weight = 95,
      spell = "Feign Death", default = "AUTO",
      desc = "Feign Death when it has gone wrong.",
      tiers = {
        { tier = 3, hp = 0.35, attackers = 1 },
        { tier = 2, hp = 0.50, melee = 1 },
      } },
    { key = "HUNTER_DETERRENCE", class = "HUNTER", role = "react", weight = 80,
      spell = "Deterrence", default = "AUTO", notWhile = { "Deterrence" },
      desc = "Deterrence with melee on you.",
      tiers = {
        { tier = 3, hp = 0.35, melee = 1 },
        { tier = 2, hp = 0.60, melee = 1 },
      } },
    { key = "HUNTER_MONKEY", class = "HUNTER", role = "react", weight = 50,
      spell = "Aspect of the Monkey", default = "AUTO", notWhile = { "Aspect of the Monkey" },
      desc = "Aspect of the Monkey when melee are on you and you are hurt.",
      tiers = {
        { tier = 1, hp = 0.60, melee = 1 },
      } },
    { key = "HUNTER_TRAP", class = "HUNTER", role = "escape", weight = 60,
      spell = "Freezing Trap", default = "AUTO",
      desc = "Freezing Trap under the melee that is on you.",
      tiers = {
        { tier = 2, hp = 0.50, melee = 1 },
        { tier = 1, melee = 1 },
      } },
    { key = "HUNTER_SCATTER", class = "HUNTER", role = "escape", weight = 65,
      spell = "Scatter Shot", default = "AUTO",
      desc = "Scatter Shot the melee that is on you.",
      tiers = {
        { tier = 2, hp = 0.50, melee = 1 },
      } },
    { key = "HUNTER_WING_CLIP", class = "HUNTER", role = "escape", weight = 40,
      spell = { "Wing Clip", "Concussive Shot" }, default = "AUTO",
      desc = "Wing Clip or Concussive Shot to get the melee off you.",
      tiers = {
        { tier = 1, hp = 0.80, melee = 1 },
      } },
    { key = "HUNTER_INTIMIDATION", class = "HUNTER", role = "escape", weight = 62,
      spell = "Intimidation", default = "AUTO",
      desc = "Intimidation — the pet stuns whatever is on you.",
      tiers = {
        { tier = 2, hp = 0.50, melee = 1, pet = true },
      } },
    { key = "HUNTER_DISENGAGE", class = "HUNTER", role = "escape", weight = 20,
      spell = "Disengage", default = "AUTO",
      desc = "Disengage when something has turned on you in a group.",
      tiers = {
        { tier = 1, group = true, melee = 1, enemyPlayers = 0 },
      } },
    { key = "HUNTER_MEND_PET", class = "HUNTER", role = "react", weight = 35,
      spell = "Mend Pet", default = "AUTO",
      desc = "Mend Pet when the pet is the one dying.",
      tiers = {
        { tier = 2, petHp = 0.30, pet = true },
        { tier = 1, petHp = 0.55, pet = true },
      } },

    -- ===== Rogue ============================================================
    { key = "ROGUE_EVASION", class = "ROGUE", role = "react", weight = 90,
      spell = "Evasion", default = "AUTO", notWhile = { "Evasion" },
      desc = "Evasion with melee on you.",
      tiers = {
        { tier = 3, hp = 0.35, melee = 1 },
        { tier = 2, hp = 0.65, melee = 1 },
      } },
    { key = "ROGUE_VANISH", class = "ROGUE", role = "escape", weight = 95,
      spell = "Vanish", default = "AUTO",
      desc = "Vanish when it has gone wrong.",
      tiers = {
        { tier = 3, hp = 0.30, attackers = 1 },
      } },
    { key = "ROGUE_CLOAK", class = "ROGUE", role = "react", weight = 85,
      spell = "Cloak of Shadows", default = "AUTO", notWhile = { "Cloak of Shadows" },
      desc = "Cloak of Shadows against magic on you or a caster working on you.",
      tiers = {
        { tier = 3, hp = 0.40, casters = 1 },
        { tier = 2, debuffType = "Magic", combat = true },
        { tier = 2, hp = 0.65, casters = 1 },
      } },
    { key = "ROGUE_BLIND", class = "ROGUE", role = "escape", weight = 80,
      spell = "Blind", default = "AUTO",
      desc = "Blind whatever is on you when you are losing.",
      tiers = {
        { tier = 3, hp = 0.35, attackers = 1 },
      } },
    { key = "ROGUE_GOUGE", class = "ROGUE", role = "escape", weight = 60,
      spell = "Gouge", default = "AUTO",
      desc = "Gouge the melee that is on you when you are losing.",
      tiers = {
        { tier = 2, hp = 0.50, melee = 1 },
      } },
    { key = "ROGUE_SPRINT", class = "ROGUE", role = "escape", weight = 40,
      spell = "Sprint", default = "AUTO", notWhile = { "Sprint" },
      desc = "Sprint out of a snare, or out of a fight you are losing.",
      tiers = {
        { tier = 1, control = "snared" },
        { tier = 1, hp = 0.35, attackers = 1 },
      } },
    { key = "ROGUE_KICK", class = "ROGUE", role = "react", weight = 55,
      spell = "Kick", default = "AUTO",
      desc = "Kick the cast that is aimed at you.",
      tiers = {
        { tier = 2, incomingCast = true },
      } },

    -- ===== Warrior ==========================================================
    { key = "WARRIOR_SHOUT", class = "WARRIOR", role = "maintain", family = "WARRIOR_SHOUT", weight = 20,
      spell = { "Commanding Shout", "Battle Shout" }, default = "AUTO",
      desc = "A shout, in combat, when none is up.",
      tiers = {
        { tier = 1, combat = true },
      } },
    { key = "WARRIOR_SHIELD_WALL", class = "WARRIOR", role = "react", weight = 100,
      spell = "Shield Wall", default = "AUTO", notWhile = { "Shield Wall" },
      desc = "Shield Wall in Defensive Stance with a shield, when you are about to die.",
      tiers = {
        { tier = 3, hp = 0.30, taking = true, form = "Defensive Stance", shield = true },
        { tier = 3, ttl = 5, hpBelowCeiling = true, form = "Defensive Stance", shield = true },
      } },
    { key = "WARRIOR_LAST_STAND", class = "WARRIOR", role = "react", weight = 96,
      spell = "Last Stand", default = "AUTO", notWhile = { "Last Stand" },
      desc = "Last Stand when you are about to die.",
      tiers = {
        { tier = 3, hp = 0.30, taking = true },
      } },
    { key = "WARRIOR_DEF_STANCE", class = "WARRIOR", role = "react", weight = 70,
      spell = "Defensive Stance", default = "AUTO",
      desc = "Defensive Stance when you are being hit hard outside it.",
      tiers = {
        { tier = 2, hp = 0.35, taking = true, notForm = { "Defensive Stance" } },
      } },
    { key = "WARRIOR_SHIELD_BLOCK", class = "WARRIOR", role = "react", weight = 60,
      spell = "Shield Block", default = "AUTO", notWhile = { "Shield Block" },
      desc = "Shield Block in Defensive Stance with a shield and melee on you.",
      tiers = {
        { tier = 2, hp = 0.60, melee = 1, form = "Defensive Stance", shield = true },
        { tier = 1, melee = 1, form = "Defensive Stance", shield = true },
      } },
    { key = "WARRIOR_REFLECT", class = "WARRIOR", role = "react", weight = 65,
      spell = "Spell Reflection", default = "AUTO", notWhile = { "Spell Reflection" },
      desc = "Spell Reflection with a shield, when a cast is aimed at you.",
      tiers = {
        { tier = 2, incomingCast = true, shield = true },
        { tier = 1, casters = 1, shield = true },
      } },
    { key = "WARRIOR_INTIMIDATE", class = "WARRIOR", role = "escape", weight = 80,
      spell = "Intimidating Shout", default = "AUTO",
      desc = "Intimidating Shout when melee are on you and you are losing.",
      tiers = {
        { tier = 3, hp = 0.30, melee = 1 },
        { tier = 2, hp = 0.55, melee = 2 },
      } },
    { key = "WARRIOR_RETALIATION", class = "WARRIOR", role = "react", weight = 30,
      spell = "Retaliation", default = "AUTO", notWhile = { "Retaliation" },
      desc = "Retaliation in Battle Stance when more than one melee is on you.",
      tiers = {
        { tier = 1, melee = 2, form = "Battle Stance" },
      } },
    { key = "WARRIOR_BERSERKER_RAGE", class = "WARRIOR", role = "react", weight = 75,
      spell = "Berserker Rage", default = "AUTO",
      desc = "Berserker Rage while an enemy is casting a fear at you.",
      tiers = {
        { tier = 3, incomingCast = D.FEAR_CASTS, form = "Berserker Stance" },
      } },
}

D.RULE_BY_KEY = {}
for _, rule in ipairs(D.RULES) do D.RULE_BY_KEY[rule.key] = rule end

-- The rules that apply to one class, in book order: everyone's first, then
-- the class's own.
function D.RulesForClass(classToken)
    local list = {}
    for _, rule in ipairs(D.RULES) do
        if rule.class == "ALL" or rule.class == classToken then
            list[#list + 1] = rule
        end
    end
    return list
end

-- Every buff name any family cares about, for the client's aura scan.
D.FAMILY_BY_BUFF = {}
for familyKey, names in pairs(D.FAMILIES) do
    for _, name in ipairs(names) do
        D.FAMILY_BY_BUFF[name] = D.FAMILY_BY_BUFF[name] or {}
        table.insert(D.FAMILY_BY_BUFF[name], familyKey)
    end
end
