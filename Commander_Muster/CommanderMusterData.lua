-- Commander Muster — the canon.
--
-- Constants only; no client calls, so the engine harness can load this file
-- under plain luajit. Everything numeric here is SOURCED, not remembered:
--
--   * The gear score formula is GearScoreLite's (Mirrikat45), with the TBC
--     corrections TacoTip (anzz1/TacoTip, gearscore.lua) made to it. The
--     original was written for Wrath and switches from its "B" curve to its
--     "A" curve at item level 120, which for TBC gear is a cliff: a Tier 4
--     piece at 120 scores MORE than a Tier 5 piece at 133. TacoTip keeps
--     epics on the B curve up to 168, rares to 148 and uncommons to 138, and
--     gives sub-100 epics their own curve, so the number is monotonic across
--     every item this expansion drops. That is the number TBC Classic players
--     have been reading for years, and matching it is the point — a score
--     nobody else can reproduce is a private opinion.
--   * The colour bands are TacoTip's TBC bracket (400 points a band) with
--     Blizzard's quality colours at the band starts.
--   * Slot weights are GearScore's own.

CommanderMusterData = CommanderMusterData or {}
local D = CommanderMusterData

D.SCALE = 1.8618          -- GearScore's global scale
D.BRACKET = 400           -- points per colour band on TBC (TacoTip); 1000 on Wrath
D.MAX_SCORE = D.BRACKET * 6 - 1

-- How much of an item's score each slot keeps. Two-handers carry both hands.
D.SLOT_MOD = {
    INVTYPE_HEAD           = 1.0000,
    INVTYPE_NECK           = 0.5625,
    INVTYPE_SHOULDER       = 0.7500,
    INVTYPE_CHEST          = 1.0000,
    INVTYPE_ROBE           = 1.0000,
    INVTYPE_WAIST          = 0.7500,
    INVTYPE_LEGS           = 1.0000,
    INVTYPE_FEET           = 0.7500,
    INVTYPE_WRIST          = 0.5625,
    INVTYPE_HAND           = 0.7500,
    INVTYPE_FINGER         = 0.5625,
    INVTYPE_TRINKET        = 0.5625,
    INVTYPE_CLOAK          = 0.5625,
    INVTYPE_WEAPON         = 1.0000,
    INVTYPE_2HWEAPON       = 2.0000,
    INVTYPE_WEAPONMAINHAND = 1.0000,
    INVTYPE_WEAPONOFFHAND  = 1.0000,
    INVTYPE_SHIELD         = 1.0000,
    INVTYPE_HOLDABLE       = 1.0000,
    INVTYPE_RANGED         = 0.3164,
    INVTYPE_RANGEDRIGHT    = 0.3164,
    INVTYPE_THROWN         = 0.3164,
    INVTYPE_RELIC          = 0.3164,
    INVTYPE_BODY           = 0,        -- shirt
    INVTYPE_TABARD         = 0,
}

-- (ilvl - A) / B, per quality, per curve. Which curve an item takes is
-- decided by CurveFor below.
D.CURVES = {
    A = {   -- Wrath's high-level curve; only reached by items TBC never drops
        [4] = { A = 91.4500, B = 0.6500 },
        [3] = { A = 81.3750, B = 0.8125 },
        [2] = { A = 73.0000, B = 1.0000 },
    },
    B = {   -- the curve every TBC item actually takes
        [4] = { A = 26.0000, B = 1.2000 },
        [3] = { A =  0.7500, B = 1.8000 },
        [2] = { A =  8.0000, B = 2.0000 },
        [1] = { A =  0.0000, B = 2.2500 },
    },
    C = {   -- epics under item level 100 (dungeon-set and pre-raid epics)
        [4] = { A =  0.2500, B = 1.6275 },
    },
}

-- Returns the curve key for a (quality, ilvl) pair. quality is the item's
-- rarity AFTER Normalize (2..4).
function D.CurveFor(quality, ilvl)
    if quality == 4 and ilvl < 100 then return "C" end
    if quality == 4 and ilvl < 168 then return "B" end
    if quality == 3 and ilvl < 148 then return "B" end
    if quality == 2 and ilvl < 138 then return "B" end
    if ilvl <= 120 then return "B" end
    return "A"
end

-- Rarity outside 2..4 is folded onto the curve with a multiplier: legendary
-- scores as an epic and a bit, white and grey as a green that barely counts.
-- Returns (curveQuality, qualityScale).
function D.Normalize(quality)
    if quality == 5 then return 4, 1.3 end
    if quality == 1 or quality == 0 then return 2, 0.005 end
    return quality, 1
end

-- Hunters: the ranged slot is the weapon and the melee slots are stat sticks.
D.HUNTER_MELEE_MOD = 0.3164
D.HUNTER_RANGED_MOD = 5.3224

-- Blizzard inventory slot ids. The shirt (4) and tabard (19) never count.
D.SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
D.SLOT_NAME = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest",
    [6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands",
    [11] = "Ring", [12] = "Ring", [13] = "Trinket", [14] = "Trinket", [15] = "Back",
    [16] = "Main hand", [17] = "Off hand", [18] = "Ranged", [19] = "Tabard",
}
D.SLOT_MAIN_HAND, D.SLOT_OFF_HAND, D.SLOT_RANGED = 16, 17, 18

-- Colour bands, one per BRACKET of score. Each channel is
--   base + (score - bandStart) * drift
-- so a score fades toward the next band's colour as it climbs. The base
-- colours are Blizzard's item-quality colours (grey, white, green, blue,
-- purple, orange); the drifts are TacoTip's, kept so the shades match what
-- players already have on screen.
D.BANDS = {
    { name = "Trash",     r = { 0.55,  0.00045 }, g = { 0.55,  0.00045 }, b = { 0.55,  0.00045 } },
    { name = "Common",    r = { 1.00, -0.00088 }, g = { 1.00,  0.00000 }, b = { 1.00, -0.00100 } },
    { name = "Uncommon",  r = { 0.12, -0.00012 }, g = { 1.00, -0.00050 }, b = { 0.00,  0.00100 } },
    { name = "Superior",  r = { 0.00,  0.00069 }, g = { 0.50, -0.00022 }, b = { 1.00, -0.00003 } },
    { name = "Epic",      r = { 0.69,  0.00025 }, g = { 0.28,  0.00019 }, b = { 0.97, -0.00096 } },
    { name = "Legendary", r = { 0.94,  0.00006 }, g = { 0.47, -0.00047 }, b = { 0.00,  0.00000 } },
}

-- Arena rating tiers, coloured like item quality so the eye reads them the
-- same way as the score beside them. The cut-offs are the Season 3/4 gear
-- gates (1850 for weapons, 2000 for shoulders in S3; 2200 for shoulders in
-- S4), which are the numbers this expansion's players actually talk about.
D.RATING_TIERS = {
    { min = 2200, r = 1.00, g = 0.50, b = 0.00 },
    { min = 2000, r = 0.64, g = 0.21, b = 0.93 },
    { min = 1850, r = 0.00, g = 0.44, b = 0.87 },
    { min = 1500, r = 0.12, g = 1.00, b = 0.00 },
    { min = 0,    r = 1.00, g = 1.00, b = 1.00 },
}

-- The three brackets, in the order they are printed
D.BRACKETS = { 2, 3, 5 }
