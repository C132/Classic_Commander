-- Commander Dossier — the diminishing-returns canon for TBC 2.4.3.
--
-- SOURCED, NOT REMEMBERED. Every category and every spell id below was
-- checked against the addon ecosystem's DR library (wardz/DRList-1.0, its
-- `tbc` branch: categories, reset time, diminished durations and PvE list),
-- because this suite has already been burned once by generating static game
-- data from model memory — see the Paladin/Druid/Warlock corrections in the
-- Commander_Talents history. DECISIONS.md D2 has the full sourcing note.
--
-- Facts worth stating out loud because they are TBC-specific and surprising:
--   * Silences do NOT diminish in TBC. There is no silence category. Unstable
--     Affliction's silence appears only because it diminishes with ITSELF.
--   * Blind and Cyclone share `disorient` and do NOT share with fear.
--   * Kidney Shot diminishes with itself, not with the stun category.
--   * Against NPCs, only stuns (both kinds) and Kidney Shot diminish at all.
--   * Snares and dazes have no DR in this expansion.

CommanderDossierData = {}
local D = CommanderDossierData

-- Reset window. TBC's real reset is dynamic, roughly 15-20s from the moment
-- the effect FADES; the library pins it at the maximum because reading a
-- window as still-open when it has already reset is the safe error (you
-- expect less duration than you get), while the reverse loses games.
D.RESET_TIME = 20

-- A CC we watched land but never saw fade (the target ran out of combat-log
-- range) must not pin its window open forever. Longest relevant TBC CC is a
-- 50s PvE Polymorph; past this the window is treated as having faded when the
-- guard expired.
D.MAX_ACTIVE = 50

-- Successive durations: the Nth application lands at DIMINISH[N]. Beyond the
-- table the target is immune.
D.DIMINISH = { 1.00, 0.50, 0.25 }

-- Board order is tactical, not alphabetical: the categories that decide TBC
-- arena games sit at the top of every row.
D.Categories = {
    { key = "stun",                label = "Stun",         short = "STUN", pve = true },
    { key = "fear",                label = "Fear",         short = "FEAR" },
    { key = "incapacitate",        label = "Incapacitate", short = "INCAP" },
    { key = "root",                label = "Root",         short = "ROOT" },
    { key = "disorient",           label = "Blind",        short = "BLIND" },
    { key = "kidney_shot",         label = "Kidney Shot",  short = "KIDNEY", pve = true },
    { key = "scatter",             label = "Scatter",      short = "SCAT" },
    { key = "death_coil",          label = "Death Coil",   short = "COIL" },
    { key = "disarm",              label = "Disarm",       short = "DISARM" },
    { key = "random_stun",         label = "Proc Stun",    short = "P-STUN", pve = true },
    { key = "random_root",         label = "Proc Root",    short = "P-ROOT" },
    { key = "mind_control",        label = "Mind Control", short = "MC" },
    { key = "unstable_affliction", label = "UA Silence",   short = "UA" },
    { key = "chastise",            label = "Chastise",     short = "CHAS" },
    { key = "counterattack",       label = "Counterattack", short = "CTR" },
}

D.CategoryByKey = {}
for index, entry in ipairs(D.Categories) do
    entry.index = index
    D.CategoryByKey[entry.key] = entry
end

-- The description each category earns in a tooltip. "Shares with" is the only
-- thing a player actually needs from a DR list mid-game.
D.CategoryHelp = {
    stun            = "Every controlled stun shares this: Hammer of Justice, Cheap Shot, Bash, Pounce, Concussion Blow, Shadowfury, Intimidation, Charge and Intercept, War Stomp. Kidney Shot does NOT — it has its own.",
    fear            = "Fear, Howl of Terror, Psychic Scream, Intimidating Shout, Seduction, Scare Beast, Turn Evil. Blind is NOT a fear in TBC.",
    incapacitate    = "Polymorph, Sap, Gouge, Freezing Trap, Wyvern Sting, Hibernate, Repentance, Maim, Banish — and engineering bombs.",
    root            = "Frost Nova, Entangling Roots, Nature's Grasp, the Water Elemental's Freeze.",
    disorient       = "Blind and Cyclone share one category with each other and with nothing else.",
    kidney_shot     = "Kidney Shot diminishes only with itself, so it is free after a Cheap Shot. Diminishes on NPCs too.",
    scatter         = "Scatter Shot and Dragon's Breath.",
    death_coil      = "Death Coil diminishes only with itself.",
    disarm          = "Disarm and Riposte.",
    random_stun     = "Proc stuns: Impact, Blackout, Pyroclasm, Revenge, Seal of Justice, Celestial Focus, Stoneclaw, mace specialisation. Diminishes on NPCs too.",
    random_root     = "Proc roots: Frostbite, Entrapment, Improved Wing Clip, Improved Hamstring.",
    mind_control    = "Mind Control, and the Gnomish Mind Control Cap.",
    unstable_affliction= "The silence from dispelling Unstable Affliction. It is the ONLY silence in TBC with diminishing returns.",
    chastise        = "Chastise diminishes only with itself.",
    counterattack   = "Counterattack diminishes only with itself.",
}

-- Only these diminish against non-player targets.
D.PvECategories = { stun = true, random_stun = true, kidney_shot = true }

-- ---------------------------------------------------------------------------
-- spellId -> category. Ranks are listed individually because the combat log
-- reports the exact rank's id; the engine additionally matches by NAME so a
-- rank missing here still categorises correctly (names come from the client,
-- so that path is locale-safe as well).
-- ---------------------------------------------------------------------------

D.SpellCategory = {
    -- Controlled stuns
    [5211] = "stun", [6798] = "stun", [8983] = "stun",             -- Bash
    [9005] = "stun", [9823] = "stun", [9827] = "stun", [27006] = "stun", -- Pounce
    [24394] = "stun",                                               -- Intimidation
    [853] = "stun", [5588] = "stun", [5589] = "stun", [10308] = "stun", -- Hammer of Justice
    [1833] = "stun",                                                -- Cheap Shot
    [30283] = "stun", [30413] = "stun", [30414] = "stun",           -- Shadowfury
    [12809] = "stun",                                               -- Concussion Blow
    [7922] = "stun",                                                -- Charge Stun
    [20253] = "stun", [20614] = "stun", [20615] = "stun",           -- Intercept Stun
    [25273] = "stun", [25274] = "stun",
    [20549] = "stun",                                               -- War Stomp (racial)
    [13237] = "stun",                                               -- Goblin Mortar
    [835] = "stun",                                                 -- Tidal Charm

    -- Proc / non-controlled stuns
    [16922] = "random_stun",                                        -- Celestial Focus
    [19410] = "random_stun",                                        -- Improved Concussive Shot
    [12355] = "random_stun",                                        -- Impact
    [20170] = "random_stun",                                        -- Seal of Justice
    [15269] = "random_stun",                                        -- Blackout
    [18093] = "random_stun",                                        -- Pyroclasm
    [39796] = "random_stun",                                        -- Stoneclaw Stun
    [12798] = "random_stun",                                        -- Revenge Stun
    [5530] = "random_stun",                                         -- Mace Specialization
    [15283] = "random_stun",                                        -- Stunning Blow
    [56] = "random_stun",                                           -- Stun (weapon proc)
    [34510] = "random_stun",                                        -- Stormherald / Deep Thunder

    -- Fear
    [1513] = "fear", [14326] = "fear", [14327] = "fear",            -- Scare Beast
    [10326] = "fear",                                               -- Turn Evil
    [8122] = "fear", [8124] = "fear", [10888] = "fear", [10890] = "fear", -- Psychic Scream
    [5782] = "fear", [6213] = "fear", [6215] = "fear",              -- Fear
    [6358] = "fear",                                                -- Seduction
    [5484] = "fear", [17928] = "fear",                              -- Howl of Terror
    [5246] = "fear",                                                -- Intimidating Shout
    [5134] = "fear",                                                -- Flash Bomb

    -- Incapacitate
    [2637] = "incapacitate", [18657] = "incapacitate", [18658] = "incapacitate", -- Hibernate
    [22570] = "incapacitate",                                       -- Maim
    [3355] = "incapacitate", [14308] = "incapacitate", [14309] = "incapacitate", -- Freezing Trap Effect
    [19386] = "incapacitate", [24132] = "incapacitate",             -- Wyvern Sting
    [24133] = "incapacitate", [27068] = "incapacitate",
    [118] = "incapacitate", [12824] = "incapacitate",               -- Polymorph
    [12825] = "incapacitate", [12826] = "incapacitate",
    [28271] = "incapacitate", [28272] = "incapacitate",             -- Polymorph: Turtle / Pig
    [20066] = "incapacitate",                                       -- Repentance
    [6770] = "incapacitate", [2070] = "incapacitate", [11297] = "incapacitate", -- Sap
    [1776] = "incapacitate", [1777] = "incapacitate", [8629] = "incapacitate",  -- Gouge
    [11285] = "incapacitate", [11286] = "incapacitate", [38764] = "incapacitate",
    [710] = "incapacitate", [18647] = "incapacitate",               -- Banish
    [13327] = "incapacitate",                                       -- Reckless Charge
    -- Engineering bombs: arena-relevant in TBC, and they share the incap DR
    [4064] = "incapacitate", [4065] = "incapacitate", [4066] = "incapacitate",
    [4067] = "incapacitate", [4068] = "incapacitate", [4069] = "incapacitate",
    [12421] = "incapacitate", [12543] = "incapacitate", [12562] = "incapacitate",
    [19769] = "incapacitate", [19784] = "incapacitate",
    [30216] = "incapacitate", [30217] = "incapacitate", [30461] = "incapacitate",

    -- Disorient (Blind / Cyclone — their own pair)
    [2094] = "disorient",                                           -- Blind
    [33786] = "disorient",                                          -- Cyclone

    -- Controlled roots
    [339] = "root", [1062] = "root", [5195] = "root", [5196] = "root", -- Entangling Roots
    [9852] = "root", [9853] = "root", [26989] = "root",
    [19970] = "root", [19971] = "root", [19972] = "root",           -- Nature's Grasp
    [19973] = "root", [19974] = "root", [19975] = "root", [27010] = "root",
    [122] = "root", [865] = "root", [6131] = "root",                -- Frost Nova
    [10230] = "root", [27088] = "root",
    [33395] = "root",                                               -- Freeze (Water Elemental)
    [39965] = "root",                                               -- Frost Grenade

    -- Proc roots
    [19185] = "random_root",                                        -- Entrapment
    [19229] = "random_root",                                        -- Improved Wing Clip
    [12494] = "random_root",                                        -- Frostbite
    [23694] = "random_root",                                        -- Improved Hamstring

    -- Mind control
    [605] = "mind_control", [10911] = "mind_control", [10912] = "mind_control",
    [13181] = "mind_control",                                       -- Gnomish Mind Control Cap

    -- Disarm
    [676] = "disarm",                                               -- Disarm
    [14251] = "disarm",                                             -- Riposte

    -- Scatter
    [19503] = "scatter",                                            -- Scatter Shot
    [31661] = "scatter", [33041] = "scatter",                       -- Dragon's Breath
    [33042] = "scatter", [33043] = "scatter",

    -- Self-only categories
    [19306] = "counterattack", [20909] = "counterattack",
    [20910] = "counterattack", [27067] = "counterattack",
    [44041] = "chastise", [44043] = "chastise", [44044] = "chastise",
    [44045] = "chastise", [44046] = "chastise", [44047] = "chastise",
    [408] = "kidney_shot", [8643] = "kidney_shot",
    [31117] = "unstable_affliction",                                -- UA dispel silence
    [6789] = "death_coil", [17925] = "death_coil",
    [17926] = "death_coil", [27223] = "death_coil",
}

-- One representative id per category-bearing SPELL NAME, used at login to
-- build the name index (GetSpellInfo on each gives the client's localized
-- name). Deliberately one per spell, never per rank: every rank of a spell
-- shares its name, which is exactly what makes the fallback locale-safe.
D.NameSeeds = {
    5211, 9005, 24394, 853, 1833, 30283, 12809, 7922, 20253, 20549,
    16922, 19410, 12355, 20170, 15269, 18093, 39796, 12798,
    1513, 10326, 8122, 5782, 6358, 5484, 5246,
    2637, 22570, 3355, 19386, 118, 20066, 6770, 1776, 710,
    2094, 33786,
    339, 19975, 122, 33395,
    19185, 19229, 12494, 23694,
    605, 676, 14251, 19503, 31661,
    19306, 44041, 408, 31117, 6789,
}
