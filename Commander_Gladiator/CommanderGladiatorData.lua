-- Commander Gladiator: the cold data the match reads and never writes.
--
-- A little 3v3 arena that plays itself while you sit in queue, and lets you
-- reach in: pin an enemy for your team to kill, fire a big spell early. This
-- file is everything about it that is a NUMBER or a NAME: who the gladiators
-- are, what their buttons do, where they stand, how long a tick is. The
-- engine beside it holds every rule and no numbers; balance is tuned here
-- and only here, and the smoke test's section E is what says whether the
-- tuning held -- and its section G, what a hand on side A is then worth.
--
-- It is deliberately not an arena simulation. There is no mana, no cast bar,
-- no diminishing-returns table and no line of sight. What is left is the part
-- you can read from across the room: who is hitting whom, who is a sheep, who
-- is about to die.
--
-- The one idea in here:
--
--   An ability is ONE ROW. Basic attack or signature spell, it is a name, an
--   icon, a cooldown, a range, a `when` and a list of effects -- and, on one
--   spell of each spec, the mark `big` -- and the engine has no code that
--   knows any spell by name. Frostbolt is not a function; it is "DAMAGE,
--   then SLOW". Adding the other twenty-one specs is meant to be typing, and
--   the test for whether that stayed true is section A of the smoke, which
--   refuses any row that steps outside the two vocabularies below.

CommanderGladiator_Data = CommanderGladiator_Data or {}
local DATA = CommanderGladiator_Data

-- ---------------------------------------------------------------------------
-- The effect vocabulary
-- ---------------------------------------------------------------------------
-- Twelve kinds, and each lists the fields a row of that kind must carry (the
-- smoke checks every row against this, so a typo is a red test and not a
-- silent nil in the middle of a match). Every kind that leaves something on a
-- unit also carries `state`: the word the window draws it by.
--
--   DAMAGE         amount, now. Rolled for spread and crits.
--   HEAL           amount, now. Rolled the same way.
--   ABSORB         a shield of `amount` that soaks damage before health does.
--   DOT            `amount` of damage every `interval`, for `duration`.
--   HOT            the same, healing. An optional `bloom` is one more heal
--                  paid when it ends (to a bearer still alive to take it).
--   DISABLE        the target cannot act for `duration`. Flags say what sort:
--                    breakOnDamage  any health lost ends it         (a sheep)
--                    breakAfter=N   ends once N health is lost      (a fear)
--                    untouchable    cannot be hurt OR healed        (cyclone)
--                    runs           the target runs about           (a fear)
--                  No flag at all is a plain stun.
--   SLOW           move speed is multiplied by `factor`.
--   ROOT           no movement at all. Attacks are untouched.
--   MOVE           the CASTER goes to the target: mode "DASH" stops on the
--                  near side, "TELEPORT" lands behind it.
--   HEALING_TAKEN  heals on the target are multiplied by `factor`.
--   DAMAGE_TAKEN   damage to the target is multiplied by `factor`.
--   EMPOWER        on the CASTER: its next direct hit is multiplied by
--                  `factor`, and the hit spends it.
DATA.EFFECTS = {
    DAMAGE        = { "amount" },
    HEAL          = { "amount" },
    ABSORB        = { "amount", "duration", "state" },
    DOT           = { "amount", "interval", "duration", "state" },
    HOT           = { "amount", "interval", "duration", "state" },
    DISABLE       = { "duration", "state" },
    SLOW          = { "factor", "duration", "state" },
    ROOT          = { "duration", "state" },
    MOVE          = { "mode" },
    HEALING_TAKEN = { "factor", "duration", "state" },
    DAMAGE_TAKEN  = { "factor", "duration", "state" },
    EMPOWER       = { "factor", "duration", "state" },
}

-- Every word a unit can be asked about with unit:Is(word). The first four
-- are the disables -- at most one of those at a time -- and the window is
-- expected to draw at least the first eight.
DATA.STATES = {
    "sheeped", "feared", "stunned", "cycloned",
    "rooted", "slowed", "shielded", "suppressed",
    "wounded", "empowered", "afflicted", "mending",
}

-- ---------------------------------------------------------------------------
-- The targeting vocabulary
-- ---------------------------------------------------------------------------
-- A row's `when` names the one question the engine asks before pressing it.
-- Five questions cover all eighteen rows:
--
--   KILL_TARGET     the team's kill target, if it is in range and the press
--                   would do something.
--   OFF_TARGET      crowd control: an enemy who is NOT the kill target and
--                   can be disabled right now. The enemy healer if there is
--                   one to save it for -- the button is held while that
--                   healer is immune or already disabled -- and anybody else
--                   only when there is not.
--   MOST_HURT_ALLY  the ally missing the largest share of their health, in
--                   range, for whom the press would do something. A row may
--                   add `below` to hold the button for an emergency.
--   GAP_CLOSER      the kill target, but only while it is out of the unit's
--                   own attack range and inside this row's.
--   ENEMY_NEAR      the nearest enemy inside this row's range of the caster.
DATA.WHEN = {
    KILL_TARGET    = true,
    OFF_TARGET     = true,
    MOST_HURT_ALLY = true,
    GAP_CLOSER     = true,
    ENEMY_NEAR     = true,
}

-- ---------------------------------------------------------------------------
-- The floor
-- ---------------------------------------------------------------------------
-- Abstract units, not yards and not pixels: x runs 0..100 from side A's wall
-- to side B's, y runs 0..50 from the back of the diorama to the front. The
-- window scales it however it likes.
--
-- Side B's marks are side A's mirrored in x = 50 and nothing else, which is
-- half of what keeps a mirror match fair (the other half is the engine's
-- acting order). Melee stand in front, the healer at the back.
--
-- `tick` is the only clock there is: match:Step() is exactly this long, and
-- every duration in this file is a multiple of it.
DATA.ARENA = {
    minX = 0, maxX = 100,
    minY = 0, maxY = 50,
    tick = 0.1,
    start = {
        A = {
            MELEE  = { x = 38, y = 25 },
            RANGED = { x = 26, y = 13 },
            HEALER = { x = 18, y = 37 },
        },
        B = {
            MELEE  = { x = 62, y = 25 },
            RANGED = { x = 74, y = 13 },
            HEALER = { x = 82, y = 37 },
        },
    },
}

-- ---------------------------------------------------------------------------
-- The house rules
-- ---------------------------------------------------------------------------
-- The numbers that belong to the match rather than to any one gladiator.
DATA.RULES = {
    -- The breath a unit takes after pressing anything. It is what makes a
    -- match readable: one token does one thing, then another token does.
    beat = 1.0,
    -- Each unit's first press is delayed by a roll up to this long, so two
    -- matches do not open on the same tick in the same order.
    stagger = 1.0,
    -- Direct damage and direct heals land within this share of their
    -- written amount, and crit this often for this much. Without the crits
    -- a match is very nearly decided by the data alone and every seed tells
    -- the same story.
    variance   = 0.15,
    critChance = 0.20,
    critFactor = 1.5,
    -- After ANY disable ends, its victim cannot be disabled again for this
    -- long. It is the whole of the game's answer to chain crowd control.
    immunity = 5.0,
    -- Melee stop this share of their range short of the target (and casters
    -- this share of theirs), so a step by the target does not put it out of
    -- reach on the next tick.
    reach = 0.8,
    -- Casters and healers back away from an enemy melee inside this
    -- distance. It is the only thing that makes a slow or a root worth
    -- casting: neither matters to a target that never walks away. It sits
    -- just outside melee reach and inside Frost Nova's ring on purpose --
    -- any wider and a melee never catches anybody, any narrower than the
    -- ring and the mage would have walked off before the nova was worth it.
    kite = 9,
    -- A feared unit picks a new compass heading this often.
    fearTurn = 0.8,
    -- Dampening: healing and absorbs are whole until `dampenStart`, fall in
    -- a straight line to nothing at `dampenEnd`, and the bell goes at `cap`
    -- whatever is still standing. No healer presses a heal, a shield or a
    -- hot that dampening would leave nothing of.
    dampenStart = 20,
    dampenEnd   = 34,
    cap         = 90,
    -- A side with nothing left that can deal damage, facing a damage dealer
    -- who is still alive, is routed: the match still ends on the kill, but
    -- nothing heals that side any more and no new shield goes up on it (one
    -- already up soaks until it is spent), nobody presses a
    -- damage-taken buff on it, and every hit on it lands for this many
    -- times its amount. Taking the heals and the buff away is not enough by
    -- itself: with this at 1.0, over seeds 1 to 1000, the kill comes 7.3 s
    -- after the rout on average and 15.0 s at the worst, because one
    -- warlock needs ten seconds to shoot down a whole priest whoever is or
    -- is not healing her. Doubled, it is 4.3 s and 8.8 s on those seeds and
    -- 12.2 s at the worst of a hundred thousand, and section E of the smoke
    -- holds it under 5 and 14.
    routDamage  = 2.0,
}

-- ---------------------------------------------------------------------------
-- The gladiators
-- ---------------------------------------------------------------------------
-- Specs, not classes: `class` is only the token the window colours and
-- badges by. `range` is how close the unit wants to be to whatever it is
-- working on, and is the range of its basic attack. `spells` are in the
-- order they are tried, before the basic.
--
-- Icon paths are the client's own for these spells (Pain Suppression really
-- is spelled with one p in the file name).
--
-- `big = true` marks the ONE spell of a spec's two that the player's hand
-- may fire (the engine's Tap); the basic attack never carries it. Marking a
-- spell changes nothing about how a unit plays it by itself. The mark goes
-- on the spell whose moment is worth choosing, which so far has meant the
-- one that takes an enemy out of the fight or saves a life: Cheap Shot,
-- Polymorph and Pain Suppression on side A. Shadowstep and Frost Nova were
-- tried as the button when the controls were designed and dropped --
-- Shadowstep is the rogue's opener and is only ever right at once, and
-- Frost Nova is so seldom usable that the button sat dark and was tapped
-- for nothing. Side B's three are marked by the same reasoning and have
-- never been under a hand, since side B has none: Fear and Cyclone are its
-- crowd control; Mortal Strike is the warrior's, because Charge, like Frost
-- Nova, can only be pressed in the moments its target has got away.
--
-- THE NUMBERS ARE TUNED, and the smoke's section E is the tuning's receipt:
-- over 1000 seeds side A wins about half, a match runs about thirty seconds,
-- and every spell below is pressed in at least nine matches in ten. The
-- match they add up to is side A's control and two healing cooldowns against
-- side B's warrior, who hits like a cart and has to be kept off the mage.
--
-- Which enemy each side opens on is rolled, and it matters more than any
-- one number here: side A wins a little over three matches in five when side
-- B opens on the rogue and about one in three when it opens on the priest. That is
-- where the variety comes from -- the first kill decides about two matches
-- in three, not nineteen in twenty -- and it is also why the balance is an
-- average over openings and not a property of any one of them. It is still
-- sharp: fifty health on the warrior is worth about four points of win
-- rate. Change one number here and run the smoke before believing it.
DATA.SPECS = {
    ROGUE_SUBTLETY = {
        key = "ROGUE_SUBTLETY", name = "Subtlety Rogue", class = "ROGUE", role = "MELEE",
        health = 1100, speed = 16, range = 6,
        basic = {
            key = "HEMORRHAGE", name = "Hemorrhage",
            icon = "Interface\\Icons\\Spell_Shadow_LifeDrain",
            cooldown = 1.5, range = 6, when = "KILL_TARGET",
            effects = { { kind = "DAMAGE", amount = 120 } },
        },
        spells = {
            {
                key = "CHEAP_SHOT", big = true, name = "Cheap Shot",
                icon = "Interface\\Icons\\Ability_CheapShot",
                cooldown = 14, range = 6, when = "KILL_TARGET",
                effects = { { kind = "DISABLE", state = "stunned", duration = 2.5 } },
            },
            -- KILL_TARGET and not GAP_CLOSER: pressed whenever it is up, as
            -- the rogue's damage cooldown, and closing a gap is what it
            -- happens to do on the way. As a pure gap closer it went unused
            -- in a tenth of matches, because a rogue walks fast enough to
            -- arrive before its beat is over.
            {
                key = "SHADOWSTEP", name = "Shadowstep",
                icon = "Interface\\Icons\\Ability_Rogue_Shadowstep",
                cooldown = 10, range = 60, when = "KILL_TARGET",
                effects = {
                    { kind = "MOVE", mode = "TELEPORT" },
                    { kind = "EMPOWER", state = "empowered", factor = 2.0, duration = 6 },
                },
            },
        },
    },

    MAGE_FROST = {
        key = "MAGE_FROST", name = "Frost Mage", class = "MAGE", role = "RANGED",
        health = 1000, speed = 10, range = 40,
        basic = {
            key = "FROSTBOLT", name = "Frostbolt",
            icon = "Interface\\Icons\\Spell_Frost_FrostBolt02",
            cooldown = 2.0, range = 40, when = "KILL_TARGET",
            effects = {
                { kind = "DAMAGE", amount = 164 },
                { kind = "SLOW", state = "slowed", factor = 0.8, duration = 4 },
            },
        },
        spells = {
            {
                key = "POLYMORPH", big = true, name = "Polymorph",
                icon = "Interface\\Icons\\Spell_Nature_Polymorph",
                cooldown = 14, range = 70, when = "OFF_TARGET",
                effects = { { kind = "DISABLE", state = "sheeped", duration = 5, breakOnDamage = true } },
            },
            {
                key = "FROST_NOVA", name = "Frost Nova",
                icon = "Interface\\Icons\\Spell_Frost_FrostNova",
                cooldown = 12, range = 12, when = "ENEMY_NEAR", area = true,
                effects = { { kind = "ROOT", state = "rooted", duration = 3.5 } },
            },
        },
    },

    PRIEST_DISCIPLINE = {
        key = "PRIEST_DISCIPLINE", name = "Discipline Priest", class = "PRIEST", role = "HEALER",
        health = 900, speed = 10, range = 50,
        basic = {
            key = "FLASH_HEAL", name = "Flash Heal",
            icon = "Interface\\Icons\\Spell_Holy_FlashHeal",
            cooldown = 1.8, range = 50, when = "MOST_HURT_ALLY",
            effects = { { kind = "HEAL", amount = 140 } },
        },
        spells = {
            {
                key = "POWER_WORD_SHIELD", name = "Power Word: Shield",
                icon = "Interface\\Icons\\Spell_Holy_PowerWordShield",
                cooldown = 8, range = 50, when = "MOST_HURT_ALLY",
                effects = { { kind = "ABSORB", state = "shielded", amount = 184, duration = 10 } },
            },
            {
                key = "PAIN_SUPPRESSION", big = true, name = "Pain Suppression",
                icon = "Interface\\Icons\\Spell_Holy_PainSupression",
                cooldown = 30, range = 50, when = "MOST_HURT_ALLY", below = 0.5,
                effects = { { kind = "DAMAGE_TAKEN", state = "suppressed", factor = 0.4, duration = 5 } },
            },
        },
    },

    WARRIOR_ARMS = {
        key = "WARRIOR_ARMS", name = "Arms Warrior", class = "WARRIOR", role = "MELEE",
        health = 1500, speed = 14, range = 6,
        basic = {
            key = "WEAPON_SWING", name = "Weapon Swing",
            icon = "Interface\\Icons\\INV_Sword_04",
            cooldown = 1.8, range = 6, when = "KILL_TARGET",
            effects = { { kind = "DAMAGE", amount = 186 } },
        },
        spells = {
            {
                key = "CHARGE", name = "Charge",
                icon = "Interface\\Icons\\Ability_Warrior_Charge",
                cooldown = 12, range = 45, when = "GAP_CLOSER",
                effects = {
                    { kind = "MOVE", mode = "DASH" },
                    { kind = "DISABLE", state = "stunned", duration = 1 },
                },
            },
            {
                key = "MORTAL_STRIKE", big = true, name = "Mortal Strike",
                icon = "Interface\\Icons\\Ability_Warrior_SavageBlow",
                cooldown = 6, range = 6, when = "KILL_TARGET",
                effects = {
                    { kind = "DAMAGE", amount = 284 },
                    { kind = "HEALING_TAKEN", state = "wounded", factor = 0.5, duration = 4 },
                },
            },
        },
    },

    WARLOCK_AFFLICTION = {
        key = "WARLOCK_AFFLICTION", name = "Affliction Warlock", class = "WARLOCK", role = "RANGED",
        health = 900, speed = 10, range = 40,
        basic = {
            key = "SHADOW_BOLT", name = "Shadow Bolt",
            icon = "Interface\\Icons\\Spell_Shadow_ShadowBolt",
            cooldown = 2.2, range = 40, when = "KILL_TARGET",
            effects = { { kind = "DAMAGE", amount = 133 } },
        },
        spells = {
            {
                key = "CORRUPTION", name = "Corruption",
                icon = "Interface\\Icons\\Spell_Shadow_AbominationExplosion",
                cooldown = 3, range = 40, when = "KILL_TARGET",
                effects = { { kind = "DOT", state = "afflicted", amount = 38, interval = 1.5, duration = 12 } },
            },
            {
                key = "FEAR", big = true, name = "Fear",
                icon = "Interface\\Icons\\Spell_Shadow_Possession",
                cooldown = 14, range = 70, when = "OFF_TARGET",
                effects = { { kind = "DISABLE", state = "feared", duration = 4, breakAfter = 200, runs = true } },
            },
        },
    },

    DRUID_RESTORATION = {
        key = "DRUID_RESTORATION", name = "Restoration Druid", class = "DRUID", role = "HEALER",
        health = 900, speed = 10, range = 50,
        basic = {
            -- Both of her heals are hots, and a hot is not pressed onto
            -- itself, so how long they last is how long she stands with
            -- nothing to press while the ally under them is dying. They are
            -- short on purpose: four seconds and three, re-pressed about
            -- twice as often as the eight and six they were first written
            -- as, with the bloom and the tick trimmed to pay for it.
            key = "REJUVENATION", name = "Rejuvenation",
            icon = "Interface\\Icons\\Spell_Nature_Rejuvenation",
            cooldown = 1.5, range = 50, when = "MOST_HURT_ALLY",
            effects = { { kind = "HOT", state = "mending", amount = 36, interval = 1, duration = 4 } },
        },
        spells = {
            {
                key = "LIFEBLOOM", name = "Lifebloom",
                icon = "Interface\\Icons\\INV_Misc_Herb_Felblossom",
                cooldown = 3, range = 50, when = "MOST_HURT_ALLY",
                effects = { { kind = "HOT", state = "mending", amount = 27, interval = 1, duration = 3, bloom = 70 } },
            },
            {
                key = "CYCLONE", big = true, name = "Cyclone",
                icon = "Interface\\Icons\\Spell_Nature_EarthBind",
                cooldown = 14, range = 70, when = "OFF_TARGET",
                effects = { { kind = "DISABLE", state = "cycloned", duration = 3.5, untouchable = true } },
            },
        },
    },
}

-- ---------------------------------------------------------------------------
-- The two teams of stage one
-- ---------------------------------------------------------------------------
-- In slot order. The order decides who acts first within a side on a tick
-- and which hurt ally a healer takes when two are level; it does NOT decide
-- who is killed first. Everybody starts whole, and that tie is rolled for.
DATA.TEAMS = {
    A = { "ROGUE_SUBTLETY", "MAGE_FROST", "PRIEST_DISCIPLINE" },
    B = { "WARRIOR_ARMS", "WARLOCK_AFFLICTION", "DRUID_RESTORATION" },
}
