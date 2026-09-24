-- Commander Plates: the tables, as data.
--
-- Two halves again, and again only one of them was typed by hand.
--
-- The generated half (CC_BY_SPELL) is Commander Diminish's DR table copied
-- here by Harness/make_cc_table.py -- 884 spell ids across sixteen categories,
-- transcribed from the SERVER's own DR classifier over the CLIENT's own spell
-- tables by Commander Arena Frames' generator. It is the honest answer to
-- "is this debuff crowd control": every rank, the triggered auras nobody
-- trains (Freezing Trap Effect, Seduction's aura), and none of the categories
-- players routinely get wrong. Three addons hold a copy so each keeps working
-- with the others disabled; the smoke test diffs them.
--
-- The hand-written half is the PvP judgement the DR table cannot carry,
-- because it is not about diminishing returns at all: which BUFFS on an enemy
-- are worth a glance (Arcane Power, Recklessness, Divine Shield), which
-- debuffs matter beyond control (Mortal Strike, Viper Sting, Curse of
-- Tongues), which casts deserve a louder cast bar, which spells only a healer
-- casts, and what each shaman totem looks like. Those are keyed by aura NAME,
-- not id, on purpose: a TBC spell has one id per rank plus NPC copies, the
-- client hands an aura its name for free, and a name matches every rank at
-- once. The harness checks every name here against the client's own
-- SpellName table, so a typo is a red test rather than an aura that is never
-- recognised.

CommanderPlates_Data = CommanderPlates_Data or {}
local DATA = CommanderPlates_Data

-- ---------------------------------------------------------------------------
-- Kinds: everything an aura can be classified AS, and how loudly it is drawn.
--
-- priority   which one wins the single big "loose control" slot; higher wins,
--            ties go to the one expiring LATER (the one you will still be
--            sitting in after the other drops)
-- big        eligible for the big slot at all (a Mortal Strike is notable, it
--            is not control)
-- toggle     the setting that switches the whole kind off
-- tint       border / glow colour
-- ---------------------------------------------------------------------------
DATA.KIND = {
    STUN       = { label = "Stun",           priority = 100, big = true,  toggle = "CcStuns",       tint = { 1.00, 0.85, 0.20 } },
    KIDNEY     = { label = "Kidney Shot",    priority = 100, big = true,  toggle = "CcStuns",       tint = { 1.00, 0.85, 0.20 } },
    STUN_PROC  = { label = "Proc Stun",      priority =  95, big = true,  toggle = "CcStuns",       tint = { 1.00, 0.85, 0.20 } },
    POLY       = { label = "Incapacitate",   priority =  90, big = true,  toggle = "CcIncaps",      tint = { 0.60, 0.80, 1.00 } },
    FEAR       = { label = "Fear",           priority =  90, big = true,  toggle = "CcFears",       tint = { 0.75, 0.40, 1.00 } },
    CHARM      = { label = "Mind Control",   priority =  90, big = true,  toggle = "CcFears",       tint = { 0.75, 0.40, 1.00 } },
    HORROR     = { label = "Death Coil",     priority =  90, big = true,  toggle = "CcFears",       tint = { 0.75, 0.40, 1.00 } },
    BANISH     = { label = "Banish",         priority =  90, big = true,  toggle = "CcIncaps",      tint = { 0.60, 0.80, 1.00 } },
    SLEEP      = { label = "Sleep",          priority =  90, big = true,  toggle = "CcIncaps",      tint = { 0.60, 0.80, 1.00 } },
    BLIND      = { label = "Blind / Cyclone",priority =  90, big = true,  toggle = "CcIncaps",      tint = { 0.60, 0.80, 1.00 } },
    FREEZE     = { label = "Freezing Trap",  priority =  90, big = true,  toggle = "CcIncaps",      tint = { 0.60, 0.80, 1.00 } },
    DRAGONS    = { label = "Dragon's Breath",priority =  85, big = true,  toggle = "CcIncaps",      tint = { 0.60, 0.80, 1.00 } },
    DISORIENT  = { label = "Disorient",      priority =  85, big = true,  toggle = "CcIncaps",      tint = { 0.60, 0.80, 1.00 } },
    SILENCE    = { label = "Silence",        priority =  70, big = true,  toggle = "CcSilences",    tint = { 1.00, 0.45, 0.20 } },
    ROOT       = { label = "Root",           priority =  60, big = true,  toggle = "CcRoots",       tint = { 0.45, 0.90, 0.45 } },
    ROOT_PROC  = { label = "Proc Root",      priority =  60, big = true,  toggle = "CcRoots",       tint = { 0.45, 0.90, 0.45 } },
    DISARM     = { label = "Disarm",         priority =  50, big = true,  toggle = "CcDisarms",     tint = { 0.85, 0.85, 0.85 } },
    IMMUNITY   = { label = "Immunity",       priority =  40, big = true,  toggle = "ShowDefensives",tint = { 1.00, 1.00, 1.00 } },
    DEFENSIVE  = { label = "Defensive",      priority =  30, big = false, toggle = "ShowDefensives",tint = { 0.40, 0.75, 1.00 } },
    OFFENSIVE  = { label = "Offensive",      priority =  30, big = false, toggle = "ShowOffensives",tint = { 1.00, 0.30, 0.30 } },
    LIMIT      = { label = "Slow",           priority =  10, big = false, toggle = "ShowSlows",     tint = { 0.55, 0.75, 0.95 } },
    SLOW       = { label = "Slow",           priority =  10, big = false, toggle = "ShowSlows",     tint = { 0.55, 0.75, 0.95 } },
    HEALCUT    = { label = "Healing Reduced",priority =  25, big = false, toggle = "ShowNotableDebuffs", tint = { 0.90, 0.20, 0.20 } },
    CASTSLOW   = { label = "Casting Slowed", priority =  20, big = false, toggle = "ShowNotableDebuffs", tint = { 0.90, 0.50, 0.20 } },
    MANA       = { label = "Mana Drain",     priority =  20, big = false, toggle = "ShowNotableDebuffs", tint = { 0.30, 0.50, 1.00 } },
    MARK       = { label = "Notable",        priority =  15, big = false, toggle = "ShowNotableDebuffs", tint = { 0.80, 0.80, 0.50 } },
    DISPELWARN = { label = "Dispel Carefully",priority = 15, big = false, toggle = "ShowNotableDebuffs", tint = { 0.60, 0.20, 0.80 } },
}

-- Kinds that mean "the unit cannot act" -- what the big slot is FOR. An
-- IMMUNITY joins them in the big slot only while CcImmunities is on; in the
-- rows it is a defensive like any other.
DATA.CONTROL_KINDS = {
    STUN = true, KIDNEY = true, STUN_PROC = true, POLY = true, FEAR = true,
    CHARM = true, HORROR = true, BANISH = true, SLEEP = true, BLIND = true,
    FREEZE = true, DRAGONS = true, DISORIENT = true, SILENCE = true,
    ROOT = true, ROOT_PROC = true, DISARM = true,
}

-- BEGIN GENERATED (Harness/make_cc_table.py)
-- Copied from Commander_Diminish/CommanderDiminishData.lua DR_BY_SPELL
-- (client build 2.5.6.69546, 884 spells, 16 groups). Do not hand-edit.
DATA.CC_BY_SPELL = {
    -- BANISH (20)
    [710] = "BANISH", [8994] = "BANISH", [16045] = "BANISH", [16451] = "BANISH",
    [18647] = "BANISH", [27565] = "BANISH", [30231] = "BANISH", [30940] = "BANISH",
    [31797] = "BANISH", [35182] = "BANISH", [35673] = "BANISH", [37546] = "BANISH",
    [38009] = "BANISH", [38456] = "BANISH", [38505] = "BANISH", [38791] = "BANISH",
    [39622] = "BANISH", [40578] = "BANISH", [43528] = "BANISH", [44765] = "BANISH",
    -- BLIND (7)
    [2094] = "BLIND", [21060] = "BLIND", [26108] = "BLIND", [33786] = "BLIND",
    [34654] = "BLIND", [34694] = "BLIND", [41397] = "BLIND",
    -- CHARM (41)
    [605] = "CHARM", [1098] = "CHARM", [7645] = "CHARM", [8345] = "CHARM",
    [10911] = "CHARM", [10912] = "CHARM", [11446] = "CHARM", [11725] = "CHARM",
    [11726] = "CHARM", [12888] = "CHARM", [13181] = "CHARM", [14515] = "CHARM",
    [15859] = "CHARM", [16053] = "CHARM", [17405] = "CHARM", [19469] = "CHARM",
    [20604] = "CHARM", [20740] = "CHARM", [20882] = "CHARM", [24327] = "CHARM",
    [26740] = "CHARM", [29490] = "CHARM", [29546] = "CHARM", [30850] = "CHARM",
    [31865] = "CHARM", [32764] = "CHARM", [33502] = "CHARM", [35120] = "CHARM",
    [35280] = "CHARM", [36866] = "CHARM", [37122] = "CHARM", [37162] = "CHARM",
    [37221] = "CHARM", [37322] = "CHARM", [37323] = "CHARM", [38626] = "CHARM",
    [38915] = "CHARM", [41345] = "CHARM", [43550] = "CHARM", [44547] = "CHARM",
    [46427] = "CHARM",
    -- DISARM (33)
    [676] = "DISARM", [5259] = "DISARM", [6608] = "DISARM", [6713] = "DISARM",
    [8379] = "DISARM", [10851] = "DISARM", [11879] = "DISARM", [13534] = "DISARM",
    [14180] = "DISARM", [14251] = "DISARM", [15752] = "DISARM", [22419] = "DISARM",
    [22691] = "DISARM", [23365] = "DISARM", [25057] = "DISARM", [25655] = "DISARM",
    [27581] = "DISARM", [30013] = "DISARM", [31955] = "DISARM", [33126] = "DISARM",
    [34097] = "DISARM", [34099] = "DISARM", [35055] = "DISARM", [36207] = "DISARM",
    [36208] = "DISARM", [36209] = "DISARM", [36510] = "DISARM", [36887] = "DISARM",
    [39489] = "DISARM", [41054] = "DISARM", [41392] = "DISARM", [45205] = "DISARM",
    [45206] = "DISARM",
    -- DRAGONS (4)
    [31661] = "DRAGONS", [33041] = "DRAGONS", [33042] = "DRAGONS", [33043] = "DRAGONS",
    -- FEAR (116)
    [1513] = "FEAR", [2878] = "FEAR", [3109] = "FEAR", [5134] = "FEAR",
    [5246] = "FEAR", [5484] = "FEAR", [5627] = "FEAR", [5782] = "FEAR",
    [6213] = "FEAR", [6215] = "FEAR", [6358] = "FEAR", [6360] = "FEAR",
    [6605] = "FEAR", [7093] = "FEAR", [7399] = "FEAR", [7813] = "FEAR",
    [8122] = "FEAR", [8124] = "FEAR", [8225] = "FEAR", [8715] = "FEAR",
    [10326] = "FEAR", [10888] = "FEAR", [10890] = "FEAR", [11784] = "FEAR",
    [11785] = "FEAR", [12096] = "FEAR", [12542] = "FEAR", [13704] = "FEAR",
    [14100] = "FEAR", [14326] = "FEAR", [14327] = "FEAR", [16096] = "FEAR",
    [16508] = "FEAR", [17928] = "FEAR", [18431] = "FEAR", [19134] = "FEAR",
    [19408] = "FEAR", [20511] = "FEAR", [21330] = "FEAR", [21869] = "FEAR",
    [21898] = "FEAR", [22678] = "FEAR", [22686] = "FEAR", [22884] = "FEAR",
    [23275] = "FEAR", [25260] = "FEAR", [25815] = "FEAR", [26042] = "FEAR",
    [26044] = "FEAR", [26070] = "FEAR", [26580] = "FEAR", [26641] = "FEAR",
    [26661] = "FEAR", [27275] = "FEAR", [27610] = "FEAR", [27641] = "FEAR",
    [27990] = "FEAR", [28315] = "FEAR", [29168] = "FEAR", [29321] = "FEAR",
    [29419] = "FEAR", [29516] = "FEAR", [29544] = "FEAR", [29685] = "FEAR",
    [30002] = "FEAR", [30530] = "FEAR", [30584] = "FEAR", [30615] = "FEAR",
    [30752] = "FEAR", [31013] = "FEAR", [31358] = "FEAR", [31365] = "FEAR",
    [31404] = "FEAR", [31970] = "FEAR", [32040] = "FEAR", [32241] = "FEAR",
    [32421] = "FEAR", [33547] = "FEAR", [33789] = "FEAR", [33829] = "FEAR",
    [33924] = "FEAR", [34259] = "FEAR", [34322] = "FEAR", [35198] = "FEAR",
    [35474] = "FEAR", [36241] = "FEAR", [36274] = "FEAR", [36629] = "FEAR",
    [36661] = "FEAR", [36922] = "FEAR", [36950] = "FEAR", [37200] = "FEAR",
    [37939] = "FEAR", [38154] = "FEAR", [38258] = "FEAR", [38595] = "FEAR",
    [38660] = "FEAR", [38945] = "FEAR", [38946] = "FEAR", [39048] = "FEAR",
    [39119] = "FEAR", [39176] = "FEAR", [39210] = "FEAR", [39415] = "FEAR",
    [39427] = "FEAR", [40221] = "FEAR", [40454] = "FEAR", [40636] = "FEAR",
    [41150] = "FEAR", [41436] = "FEAR", [42690] = "FEAR", [43432] = "FEAR",
    [43590] = "FEAR", [44863] = "FEAR", [46561] = "FEAR", [351357] = "FEAR",
    -- FREEZE (13)
    [3355] = "FREEZE", [10255] = "FREEZE", [14308] = "FREEZE", [14309] = "FREEZE",
    [18798] = "FREEZE", [31932] = "FREEZE", [34973] = "FREEZE", [36527] = "FREEZE",
    [36911] = "FREEZE", [41590] = "FREEZE", [42161] = "FREEZE", [43448] = "FREEZE",
    [45476] = "FREEZE",
    -- HORROR (13)
    [6789] = "HORROR", [17925] = "HORROR", [17926] = "HORROR", [27223] = "HORROR",
    [30500] = "HORROR", [30741] = "HORROR", [32709] = "HORROR", [33130] = "HORROR",
    [34984] = "HORROR", [35954] = "HORROR", [38065] = "HORROR", [44142] = "HORROR",
    [50368] = "HORROR",
    -- KIDNEY (6)
    [408] = "KIDNEY", [8643] = "KIDNEY", [27615] = "KIDNEY", [30621] = "KIDNEY",
    [30832] = "KIDNEY", [34108] = "KIDNEY",
    -- LIMIT (5)
    [1715] = "LIMIT", [7372] = "LIMIT", [7373] = "LIMIT", [24428] = "LIMIT",
    [25212] = "LIMIT",
    -- POLY (116)
    [118] = "POLY", [228] = "POLY", [851] = "POLY", [1776] = "POLY",
    [1777] = "POLY", [2070] = "POLY", [4060] = "POLY", [4064] = "POLY",
    [4065] = "POLY", [4066] = "POLY", [4067] = "POLY", [4068] = "POLY",
    [4069] = "POLY", [6770] = "POLY", [8629] = "POLY", [10253] = "POLY",
    [11285] = "POLY", [11286] = "POLY", [11297] = "POLY", [11641] = "POLY",
    [12421] = "POLY", [12540] = "POLY", [12543] = "POLY", [12562] = "POLY",
    [12824] = "POLY", [12825] = "POLY", [12826] = "POLY", [13323] = "POLY",
    [13327] = "POLY", [13579] = "POLY", [13808] = "POLY", [14621] = "POLY",
    [15091] = "POLY", [15534] = "POLY", [15744] = "POLY", [16046] = "POLY",
    [16097] = "POLY", [16707] = "POLY", [16708] = "POLY", [16709] = "POLY",
    [17145] = "POLY", [17172] = "POLY", [17277] = "POLY", [17738] = "POLY",
    [18503] = "POLY", [19769] = "POLY", [19784] = "POLY", [20066] = "POLY",
    [22274] = "POLY", [22424] = "POLY", [22566] = "POLY", [22570] = "POLY",
    [23039] = "POLY", [23113] = "POLY", [23603] = "POLY", [24053] = "POLY",
    [24698] = "POLY", [24708] = "POLY", [24709] = "POLY", [24710] = "POLY",
    [24711] = "POLY", [24712] = "POLY", [24713] = "POLY", [24717] = "POLY",
    [24718] = "POLY", [24719] = "POLY", [24720] = "POLY", [24723] = "POLY",
    [24724] = "POLY", [24732] = "POLY", [24733] = "POLY", [24735] = "POLY",
    [24736] = "POLY", [24737] = "POLY", [24740] = "POLY", [24741] = "POLY",
    [26157] = "POLY", [26272] = "POLY", [26273] = "POLY", [26274] = "POLY",
    [27760] = "POLY", [28271] = "POLY", [28272] = "POLY", [29044] = "POLY",
    [29314] = "POLY", [29511] = "POLY", [29848] = "POLY", [30077] = "POLY",
    [30216] = "POLY", [30217] = "POLY", [30461] = "POLY", [30501] = "POLY",
    [30504] = "POLY", [30506] = "POLY", [30600] = "POLY", [30838] = "POLY",
    [30980] = "POLY", [32779] = "POLY", [32826] = "POLY", [33173] = "POLY",
    [34639] = "POLY", [34940] = "POLY", [36700] = "POLY", [36840] = "POLY",
    [36862] = "POLY", [38064] = "POLY", [38245] = "POLY", [38764] = "POLY",
    [38863] = "POLY", [38896] = "POLY", [40400] = "POLY", [41334] = "POLY",
    [43309] = "POLY", [46280] = "POLY", [46295] = "POLY", [46590] = "POLY",
    -- ROOT (150)
    [113] = "ROOT", [122] = "ROOT", [339] = "ROOT", [512] = "ROOT",
    [745] = "ROOT", [865] = "ROOT", [1062] = "ROOT", [3542] = "ROOT",
    [4962] = "ROOT", [5195] = "ROOT", [5196] = "ROOT", [5567] = "ROOT",
    [6131] = "ROOT", [6533] = "ROOT", [8142] = "ROOT", [8312] = "ROOT",
    [8346] = "ROOT", [8377] = "ROOT", [9852] = "ROOT", [9853] = "ROOT",
    [9915] = "ROOT", [10017] = "ROOT", [10230] = "ROOT", [10852] = "ROOT",
    [11264] = "ROOT", [11820] = "ROOT", [11831] = "ROOT", [11922] = "ROOT",
    [12023] = "ROOT", [12024] = "ROOT", [12252] = "ROOT", [12674] = "ROOT",
    [12747] = "ROOT", [12748] = "ROOT", [13099] = "ROOT", [13119] = "ROOT",
    [13138] = "ROOT", [13608] = "ROOT", [14030] = "ROOT", [14907] = "ROOT",
    [15063] = "ROOT", [15471] = "ROOT", [15474] = "ROOT", [15531] = "ROOT",
    [15532] = "ROOT", [15609] = "ROOT", [16469] = "ROOT", [16566] = "ROOT",
    [17333] = "ROOT", [19229] = "ROOT", [19306] = "ROOT", [19970] = "ROOT",
    [19971] = "ROOT", [19972] = "ROOT", [19973] = "ROOT", [19974] = "ROOT",
    [19975] = "ROOT", [20654] = "ROOT", [20699] = "ROOT", [20909] = "ROOT",
    [20910] = "ROOT", [21331] = "ROOT", [22127] = "ROOT", [22415] = "ROOT",
    [22519] = "ROOT", [22645] = "ROOT", [22744] = "ROOT", [22800] = "ROOT",
    [22924] = "ROOT", [22994] = "ROOT", [24110] = "ROOT", [24648] = "ROOT",
    [25999] = "ROOT", [26071] = "ROOT", [26989] = "ROOT", [27010] = "ROOT",
    [27067] = "ROOT", [27088] = "ROOT", [27868] = "ROOT", [28297] = "ROOT",
    [28858] = "ROOT", [28991] = "ROOT", [29849] = "ROOT", [29991] = "ROOT",
    [30094] = "ROOT", [31250] = "ROOT", [31287] = "ROOT", [31290] = "ROOT",
    [31409] = "ROOT", [31983] = "ROOT", [32173] = "ROOT", [32192] = "ROOT",
    [32365] = "ROOT", [32859] = "ROOT", [33395] = "ROOT", [33844] = "ROOT",
    [34326] = "ROOT", [34725] = "ROOT", [34740] = "ROOT", [34746] = "ROOT",
    [34779] = "ROOT", [34782] = "ROOT", [35107] = "ROOT", [35234] = "ROOT",
    [35247] = "ROOT", [35831] = "ROOT", [35963] = "ROOT", [36575] = "ROOT",
    [36786] = "ROOT", [36827] = "ROOT", [36989] = "ROOT", [37480] = "ROOT",
    [37823] = "ROOT", [38033] = "ROOT", [38035] = "ROOT", [38051] = "ROOT",
    [38316] = "ROOT", [38338] = "ROOT", [38661] = "ROOT", [38843] = "ROOT",
    [38900] = "ROOT", [38912] = "ROOT", [39035] = "ROOT", [39063] = "ROOT",
    [39584] = "ROOT", [39965] = "ROOT", [40082] = "ROOT", [40333] = "ROOT",
    [40363] = "ROOT", [40525] = "ROOT", [40590] = "ROOT", [40727] = "ROOT",
    [40875] = "ROOT", [41086] = "ROOT", [41580] = "ROOT", [43362] = "ROOT",
    [43426] = "ROOT", [43585] = "ROOT", [44041] = "ROOT", [44043] = "ROOT",
    [44044] = "ROOT", [44045] = "ROOT", [44046] = "ROOT", [44047] = "ROOT",
    [44177] = "ROOT", [45825] = "ROOT", [45905] = "ROOT", [46555] = "ROOT",
    [47168] = "ROOT", [50762] = "ROOT",
    -- ROOT_PROC (3)
    [12494] = "ROOT_PROC", [19185] = "ROOT_PROC", [23694] = "ROOT_PROC",
    -- SLEEP (40)
    [700] = "SLEEP", [1090] = "SLEEP", [2637] = "SLEEP", [3636] = "SLEEP",
    [7967] = "SLEEP", [8040] = "SLEEP", [8399] = "SLEEP", [8901] = "SLEEP",
    [8902] = "SLEEP", [9159] = "SLEEP", [12098] = "SLEEP", [15822] = "SLEEP",
    [15970] = "SLEEP", [16798] = "SLEEP", [18657] = "SLEEP", [18658] = "SLEEP",
    [19386] = "SLEEP", [20663] = "SLEEP", [20669] = "SLEEP", [20989] = "SLEEP",
    [24004] = "SLEEP", [24132] = "SLEEP", [24133] = "SLEEP", [24335] = "SLEEP",
    [24360] = "SLEEP", [27068] = "SLEEP", [28504] = "SLEEP", [29148] = "SLEEP",
    [29679] = "SLEEP", [31292] = "SLEEP", [31541] = "SLEEP", [34039] = "SLEEP",
    [34801] = "SLEEP", [36333] = "SLEEP", [36402] = "SLEEP", [37990] = "SLEEP",
    [38510] = "SLEEP", [38886] = "SLEEP", [41186] = "SLEEP", [41396] = "SLEEP",
    -- STUN (307)
    [45] = "STUN", [56] = "STUN", [835] = "STUN", [853] = "STUN",
    [1833] = "STUN", [2880] = "STUN", [3143] = "STUN", [3242] = "STUN",
    [3263] = "STUN", [3446] = "STUN", [3551] = "STUN", [3609] = "STUN",
    [3635] = "STUN", [5106] = "STUN", [5164] = "STUN", [5211] = "STUN",
    [5276] = "STUN", [5403] = "STUN", [5588] = "STUN", [5589] = "STUN",
    [5648] = "STUN", [5649] = "STUN", [5703] = "STUN", [5708] = "STUN",
    [5918] = "STUN", [6253] = "STUN", [6266] = "STUN", [6304] = "STUN",
    [6409] = "STUN", [6435] = "STUN", [6466] = "STUN", [6524] = "STUN",
    [6607] = "STUN", [6728] = "STUN", [6730] = "STUN", [6749] = "STUN",
    [6798] = "STUN", [6927] = "STUN", [6945] = "STUN", [6982] = "STUN",
    [7139] = "STUN", [7803] = "STUN", [7922] = "STUN", [7964] = "STUN",
    [8150] = "STUN", [8151] = "STUN", [8208] = "STUN", [8242] = "STUN",
    [8285] = "STUN", [8391] = "STUN", [8646] = "STUN", [8983] = "STUN",
    [9005] = "STUN", [9823] = "STUN", [9827] = "STUN", [10308] = "STUN",
    [10856] = "STUN", [11020] = "STUN", [11428] = "STUN", [11430] = "STUN",
    [11650] = "STUN", [11836] = "STUN", [11876] = "STUN", [12461] = "STUN",
    [12734] = "STUN", [12809] = "STUN", [13005] = "STUN", [13237] = "STUN",
    [13902] = "STUN", [13907] = "STUN", [14102] = "STUN", [14902] = "STUN",
    [15239] = "STUN", [15283] = "STUN", [15398] = "STUN", [15535] = "STUN",
    [15593] = "STUN", [15618] = "STUN", [15621] = "STUN", [15652] = "STUN",
    [15655] = "STUN", [15743] = "STUN", [15753] = "STUN", [15847] = "STUN",
    [15878] = "STUN", [16075] = "STUN", [16104] = "STUN", [16350] = "STUN",
    [16497] = "STUN", [16600] = "STUN", [16727] = "STUN", [16740] = "STUN",
    [16790] = "STUN", [16803] = "STUN", [16869] = "STUN", [17011] = "STUN",
    [17276] = "STUN", [17286] = "STUN", [17293] = "STUN", [17308] = "STUN",
    [17492] = "STUN", [17500] = "STUN", [18093] = "STUN", [18103] = "STUN",
    [18144] = "STUN", [18395] = "STUN", [18763] = "STUN", [18812] = "STUN",
    [19128] = "STUN", [19136] = "STUN", [19364] = "STUN", [19482] = "STUN",
    [19641] = "STUN", [19780] = "STUN", [19798] = "STUN", [20253] = "STUN",
    [20276] = "STUN", [20277] = "STUN", [20310] = "STUN", [20549] = "STUN",
    [20614] = "STUN", [20615] = "STUN", [20683] = "STUN", [20685] = "STUN",
    [21099] = "STUN", [21152] = "STUN", [21748] = "STUN", [21749] = "STUN",
    [21808] = "STUN", [21990] = "STUN", [22289] = "STUN", [22427] = "STUN",
    [22592] = "STUN", [22692] = "STUN", [22703] = "STUN", [22911] = "STUN",
    [23103] = "STUN", [23364] = "STUN", [23454] = "STUN", [23919] = "STUN",
    [24213] = "STUN", [24333] = "STUN", [24375] = "STUN", [24394] = "STUN",
    [24600] = "STUN", [24671] = "STUN", [25056] = "STUN", [25189] = "STUN",
    [25273] = "STUN", [25274] = "STUN", [25654] = "STUN", [25852] = "STUN",
    [26102] = "STUN", [27006] = "STUN", [27758] = "STUN", [27880] = "STUN",
    [28125] = "STUN", [28314] = "STUN", [28725] = "STUN", [29300] = "STUN",
    [29670] = "STUN", [29676] = "STUN", [29684] = "STUN", [29690] = "STUN",
    [29711] = "STUN", [29896] = "STUN", [30112] = "STUN", [30153] = "STUN",
    [30195] = "STUN", [30197] = "STUN", [30283] = "STUN", [30413] = "STUN",
    [30414] = "STUN", [30688] = "STUN", [30732] = "STUN", [30761] = "STUN",
    [30986] = "STUN", [31046] = "STUN", [31249] = "STUN", [31274] = "STUN",
    [31286] = "STUN", [31302] = "STUN", [31367] = "STUN", [31368] = "STUN",
    [31390] = "STUN", [31408] = "STUN", [31422] = "STUN", [31480] = "STUN",
    [31610] = "STUN", [31718] = "STUN", [31719] = "STUN", [31733] = "STUN",
    [31755] = "STUN", [31819] = "STUN", [31843] = "STUN", [31864] = "STUN",
    [31964] = "STUN", [31994] = "STUN", [32015] = "STUN", [32023] = "STUN",
    [32109] = "STUN", [32323] = "STUN", [32361] = "STUN", [32416] = "STUN",
    [32588] = "STUN", [32654] = "STUN", [32752] = "STUN", [32864] = "STUN",
    [32905] = "STUN", [33487] = "STUN", [33637] = "STUN", [33709] = "STUN",
    [33781] = "STUN", [33792] = "STUN", [33919] = "STUN", [34243] = "STUN",
    [34267] = "STUN", [34357] = "STUN", [34510] = "STUN", [34716] = "STUN",
    [34752] = "STUN", [34885] = "STUN", [35011] = "STUN", [35202] = "STUN",
    [35238] = "STUN", [35313] = "STUN", [35373] = "STUN", [35412] = "STUN",
    [35460] = "STUN", [35492] = "STUN", [35570] = "STUN", [35614] = "STUN",
    [35783] = "STUN", [35856] = "STUN", [36138] = "STUN", [36140] = "STUN",
    [36254] = "STUN", [36509] = "STUN", [36606] = "STUN", [36809] = "STUN",
    [36816] = "STUN", [36835] = "STUN", [36877] = "STUN", [36924] = "STUN",
    [36929] = "STUN", [37012] = "STUN", [37029] = "STUN", [37118] = "STUN",
    [37359] = "STUN", [37369] = "STUN", [37511] = "STUN", [37592] = "STUN",
    [37777] = "STUN", [37991] = "STUN", [38169] = "STUN", [38357] = "STUN",
    [38461] = "STUN", [38682] = "STUN", [38737] = "STUN", [38911] = "STUN",
    [39002] = "STUN", [39017] = "STUN", [39021] = "STUN", [39077] = "STUN",
    [39082] = "STUN", [39157] = "STUN", [39229] = "STUN", [39313] = "STUN",
    [39574] = "STUN", [39796] = "STUN", [39865] = "STUN", [40077] = "STUN",
    [40184] = "STUN", [40262] = "STUN", [40380] = "STUN", [40846] = "STUN",
    [40864] = "STUN", [40936] = "STUN", [41182] = "STUN", [41272] = "STUN",
    [41274] = "STUN", [41356] = "STUN", [41358] = "STUN", [41389] = "STUN",
    [41468] = "STUN", [41534] = "STUN", [43437] = "STUN", [43519] = "STUN",
    [44138] = "STUN", [44478] = "STUN", [44799] = "STUN", [45029] = "STUN",
    [45065] = "STUN", [45122] = "STUN", [45270] = "STUN", [46024] = "STUN",
    [46026] = "STUN", [46183] = "STUN", [46184] = "STUN", [46188] = "STUN",
    [46239] = "STUN", [46288] = "STUN", [46567] = "STUN", [46762] = "STUN",
    [50874] = "STUN", [50876] = "STUN", [385807] = "STUN",
    -- STUN_PROC (10)
    [5530] = "STUN_PROC", [12355] = "STUN_PROC", [12798] = "STUN_PROC", [15269] = "STUN_PROC",
    [16922] = "STUN_PROC", [19410] = "STUN_PROC", [20170] = "STUN_PROC", [22915] = "STUN_PROC",
    [28445] = "STUN_PROC", [44415] = "STUN_PROC",
}
-- END GENERATED

-- ---------------------------------------------------------------------------
-- The hand-written half. Aura NAMES, as this client spells them (enUS).
--
-- Silence and Scatter Shot are here rather than in the DR table because TBC
-- has no diminishing returns on either -- which is a fact about DR, not about
-- whether a silenced healer is worth a big icon.
-- ---------------------------------------------------------------------------
DATA.NOTABLE = {
    -- Control the DR table cannot know about
    ["Silence"]                     = "SILENCE",
    ["Counterspell - Silenced"]     = "SILENCE",
    ["Spell Lock"]                  = "SILENCE",
    ["Silencing Shot"]              = "SILENCE",
    ["Garrote - Silence"]           = "SILENCE",
    ["Kick - Silenced"]             = "SILENCE",
    ["Shield Bash - Silenced"]      = "SILENCE",
    ["Arcane Torrent"]              = "SILENCE",
    ["Scatter Shot"]                = "DISORIENT",

    -- Immunities and hard defensives: the moment to stop casting at someone
    ["Divine Shield"]               = "IMMUNITY",
    ["Ice Block"]                   = "IMMUNITY",
    ["Blessing of Protection"]      = "IMMUNITY",
    ["Cloak of Shadows"]            = "IMMUNITY",
    ["Spell Reflection"]            = "IMMUNITY",
    ["Deterrence"]                  = "IMMUNITY",
    ["Evasion"]                     = "IMMUNITY",
    ["Grounding Totem Effect"]      = "IMMUNITY",
    ["Banish"]                      = "BANISH",     -- also in the DR table; the name catches NPC copies

    -- Defensives worth a glance (yours to see on friends, theirs to burn through)
    ["Divine Protection"]           = "DEFENSIVE",
    ["Blessing of Freedom"]         = "DEFENSIVE",
    ["Fear Ward"]                   = "DEFENSIVE",
    ["Shield Wall"]                 = "DEFENSIVE",
    ["Last Stand"]                  = "DEFENSIVE",
    ["Pain Suppression"]            = "DEFENSIVE",
    ["Barkskin"]                    = "DEFENSIVE",
    ["Frenzied Regeneration"]       = "DEFENSIVE",
    ["Earth Shield"]                = "DEFENSIVE",
    ["Power Word: Shield"]          = "DEFENSIVE",
    ["Shamanistic Rage"]            = "DEFENSIVE",
    ["Nature's Grasp"]              = "DEFENSIVE",
    ["Nether Protection"]           = "DEFENSIVE",
    ["Stoneform"]                   = "DEFENSIVE",
    ["Will of the Forsaken"]        = "DEFENSIVE",
    ["Berserker Rage"]              = "DEFENSIVE",
    ["Retaliation"]                 = "DEFENSIVE",
    ["Shadowform"]                  = "DEFENSIVE",
    ["Lifebloom"]                   = "DEFENSIVE",

    -- Offensive cooldowns: the burst window, theirs or yours
    ["Arcane Power"]                = "OFFENSIVE",
    ["Presence of Mind"]            = "OFFENSIVE",
    ["Icy Veins"]                   = "OFFENSIVE",
    ["Combustion"]                  = "OFFENSIVE",
    ["Recklessness"]                = "OFFENSIVE",
    ["Death Wish"]                  = "OFFENSIVE",
    ["Sweeping Strikes"]            = "OFFENSIVE",
    ["Bloodlust"]                   = "OFFENSIVE",
    ["Heroism"]                     = "OFFENSIVE",
    ["Adrenaline Rush"]             = "OFFENSIVE",
    ["Blade Flurry"]                = "OFFENSIVE",
    ["Cold Blood"]                  = "OFFENSIVE",
    ["Power Infusion"]              = "OFFENSIVE",
    ["Inner Focus"]                 = "OFFENSIVE",
    ["Nature's Swiftness"]          = "OFFENSIVE",
    ["Elemental Mastery"]           = "OFFENSIVE",
    ["Avenging Wrath"]              = "OFFENSIVE",
    ["Divine Favor"]                = "OFFENSIVE",
    ["Divine Illumination"]         = "OFFENSIVE",
    ["Bestial Wrath"]               = "OFFENSIVE",
    ["The Beast Within"]            = "OFFENSIVE",
    ["Rapid Fire"]                  = "OFFENSIVE",
    ["Berserking"]                  = "OFFENSIVE",
    ["Blood Fury"]                  = "OFFENSIVE",
    ["Fel Domination"]              = "OFFENSIVE",
    ["Innervate"]                   = "OFFENSIVE",
    ["Evocation"]                   = "OFFENSIVE",
    ["Enrage"]                      = "OFFENSIVE",

    -- Debuffs beyond control that decide fights
    ["Mortal Strike"]               = "HEALCUT",
    ["Wound Poison"]                = "HEALCUT",
    ["Aimed Shot"]                  = "HEALCUT",
    ["Viper Sting"]                 = "MANA",
    ["Curse of Tongues"]            = "CASTSLOW",
    ["Mind-numbing Poison"]         = "CASTSLOW",
    ["Unstable Affliction"]         = "DISPELWARN",
    ["Vampiric Touch"]              = "DISPELWARN",
    ["Hunter's Mark"]               = "MARK",
    ["Faerie Fire"]                 = "MARK",
    ["Faerie Fire (Feral)"]         = "MARK",
    ["Judgement of Justice"]        = "MARK",
    ["Vindication"]                 = "MARK",
    ["Weakened Soul"]               = "MARK",
    ["Forbearance"]                 = "MARK",
    ["Hypothermia"]                 = "MARK",
    ["Recently Bandaged"]           = "MARK",

    -- Slows. Off by default; a battleground is nothing but slows.
    ["Crippling Poison"]            = "SLOW",
    ["Hamstring"]                   = "SLOW",
    ["Wing Clip"]                   = "SLOW",
    ["Piercing Howl"]               = "SLOW",
    ["Curse of Exhaustion"]         = "SLOW",
    ["Frost Shock"]                 = "SLOW",
    ["Frostbolt"]                   = "SLOW",
    ["Cone of Cold"]                = "SLOW",
    ["Earthbind"]                   = "SLOW",
    ["Concussive Shot"]             = "SLOW",
    ["Dazed"]                       = "SLOW",
    ["Slow"]                        = "SLOW",
    ["Mind Flay"]                   = "SLOW",
    ["Chilled"]                     = "SLOW",
}

-- ---------------------------------------------------------------------------
-- Casts worth a louder cast bar. Control that will land on somebody, the big
-- heals, and the two casts that end a mana bar.
-- ---------------------------------------------------------------------------
DATA.CAST_EMPHASIS = {
    "Polymorph", "Fear", "Cyclone", "Mind Control", "Seduction", "Entangling Roots",
    "Hibernate", "Banish", "Scare Beast", "Howl of Terror", "Wyvern Sting",
    "Greater Heal", "Flash Heal", "Prayer of Healing", "Holy Light", "Flash of Light",
    "Healing Wave", "Chain Heal", "Lesser Healing Wave", "Regrowth", "Healing Touch",
    "Resurrection", "Redemption", "Ancestral Spirit", "Rebirth",
    "Pyroblast", "Soul Fire", "Aimed Shot", "Drain Mana", "Mana Burn",
    "Hearthstone",
}

-- ---------------------------------------------------------------------------
-- Spells that mark their caster as a HEALER. There is no spec API for an
-- arbitrary enemy on this client, so the answer is inferred from the combat
-- log: one of these healing a friend of theirs is the tell. Names a hybrid
-- would also cast (Renew on a shadow priest, Lesser Healing Wave on an
-- enhancement shaman) are deliberately absent -- a false healer marker costs
-- more than a late one.
-- ---------------------------------------------------------------------------
DATA.HEALER_SPELLS = {
    ["Greater Heal"] = true, ["Flash Heal"] = true, ["Binding Heal"] = true,
    ["Circle of Healing"] = true, ["Prayer of Healing"] = true, ["Prayer of Mending"] = true,
    ["Holy Light"] = true, ["Flash of Light"] = true,
    ["Healing Wave"] = true, ["Chain Heal"] = true, ["Earth Shield"] = true,
    ["Regrowth"] = true, ["Healing Touch"] = true, ["Lifebloom"] = true, ["Swiftmend"] = true,
    ["Nature's Swiftness"] = true, ["Pain Suppression"] = true, ["Divine Illumination"] = true,
    ["Mana Tide Totem"] = true, ["Tree of Life"] = true,
}

-- ---------------------------------------------------------------------------
-- Shaman totems. A totem plate says "Searing Totem IV" over a sliver of health
-- bar; what a PvP player needs is the ICON, big, and only for the totems that
-- change what to do next. Keyed by the totem's name with any rank stripped;
-- the spell id is rank one, used only to fetch the icon.
--
-- HIGH: kill it now or play around it. LOW: scenery.
-- ---------------------------------------------------------------------------
DATA.TOTEMS = {
    ["Grounding Totem"]          = { spell = 8177,  tier = "HIGH" },
    ["Tremor Totem"]             = { spell = 8143,  tier = "HIGH" },
    ["Earthbind Totem"]          = { spell = 2484,  tier = "HIGH" },
    ["Windfury Totem"]           = { spell = 8512,  tier = "HIGH" },
    ["Mana Tide Totem"]          = { spell = 16190, tier = "HIGH" },
    ["Poison Cleansing Totem"]   = { spell = 8166,  tier = "HIGH" },
    ["Disease Cleansing Totem"]  = { spell = 8170,  tier = "HIGH" },
    ["Totem of Wrath"]           = { spell = 30706, tier = "HIGH" },
    ["Wrath of Air Totem"]       = { spell = 3738,  tier = "HIGH" },
    ["Fire Elemental Totem"]     = { spell = 2894,  tier = "HIGH" },
    ["Earth Elemental Totem"]    = { spell = 2062,  tier = "HIGH" },
    ["Tranquil Air Totem"]       = { spell = 25908, tier = "HIGH" },
    ["Searing Totem"]            = { spell = 3599,  tier = "LOW" },
    ["Fire Nova Totem"]          = { spell = 1535,  tier = "LOW" },
    ["Magma Totem"]              = { spell = 8190,  tier = "LOW" },
    ["Stoneclaw Totem"]          = { spell = 5730,  tier = "LOW" },
    ["Frost Resistance Totem"]   = { spell = 8181,  tier = "LOW" },
    ["Fire Resistance Totem"]    = { spell = 8184,  tier = "LOW" },
    ["Nature Resistance Totem"]  = { spell = 10595, tier = "LOW" },
    ["Grace of Air Totem"]       = { spell = 8835,  tier = "LOW" },
    ["Strength of Earth Totem"]  = { spell = 8075,  tier = "LOW" },
    ["Stoneskin Totem"]          = { spell = 8071,  tier = "LOW" },
    ["Mana Spring Totem"]        = { spell = 5675,  tier = "LOW" },
    ["Healing Stream Totem"]     = { spell = 5394,  tier = "LOW" },
    ["Sentry Totem"]             = { spell = 6495,  tier = "LOW" },
    ["Flametongue Totem"]        = { spell = 8227,  tier = "LOW" },
    ["Windwall Totem"]           = { spell = 15107, tier = "LOW" },
}

-- ---------------------------------------------------------------------------
-- Dispelling. Which debuff types each class can lift off a FRIEND, and which
-- classes can purge a magic buff off an ENEMY. Warlock is the felhunter's
-- Devour Magic; a warlock without one out simply sees no purge glow.
-- ---------------------------------------------------------------------------
DATA.CLASS_DISPEL = {
    PRIEST  = { Magic = true, Disease = true },
    PALADIN = { Magic = true, Poison = true, Disease = true },
    SHAMAN  = { Poison = true, Disease = true },
    DRUID   = { Curse = true, Poison = true },
    MAGE    = { Curse = true },
    WARLOCK = { Magic = true },
}
DATA.CLASS_PURGE = { PRIEST = true, SHAMAN = true, MAGE = true, WARLOCK = true }

DATA.DISPEL_TINT = {
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison  = { 0.00, 0.60, 0.00 },
}

-- The DR badge on the big icon, when Commander Diminish is loaded and has seen
-- this unit: what bracket the control that is up landed at.
DATA.BRACKET_LABEL = { "", "\194\189", "\194\188" }          -- "", 1/2, 1/4
DATA.BRACKET_TINT = { { 1, 1, 1 }, { 0.98, 0.86, 0.35 }, { 0.98, 0.55, 0.28 } }
DATA.NEXT_IMMUNE_LABEL = "X"

-- ---------------------------------------------------------------------------
-- Colours a control can name. A dropdown offers these keys plus CLASS (the
-- unit's class colour) and REACTION (hostile red / neutral yellow / friendly
-- blue), and Draw.ResolveColor turns a key into rgb for a given unit.
-- ---------------------------------------------------------------------------
DATA.PALETTE = {
    WHITE   = { 1.00, 1.00, 1.00 },
    RED     = { 1.00, 0.25, 0.25 },
    BLUE    = { 0.35, 0.60, 1.00 },
    GREEN   = { 0.30, 1.00, 0.30 },
    GOLD    = { 1.00, 0.82, 0.20 },
    PURPLE  = { 0.75, 0.40, 1.00 },
    MAGENTA = { 0.95, 0.25, 0.85 },
    CYAN    = { 0.30, 0.95, 0.95 },
    ORANGE  = { 1.00, 0.55, 0.15 },
}
DATA.PALETTE_ORDER = { "WHITE", "RED", "BLUE", "GREEN", "GOLD", "PURPLE", "MAGENTA", "CYAN", "ORANGE" }
DATA.PALETTE_LABEL = {
    WHITE = "White", RED = "Red", BLUE = "Blue", GREEN = "Green", GOLD = "Gold",
    PURPLE = "Purple", MAGENTA = "Magenta", CYAN = "Cyan", ORANGE = "Orange",
}
DATA.REACTION_TINT = {
    HOSTILE  = { 0.95, 0.20, 0.20 },
    NEUTRAL  = { 1.00, 0.85, 0.20 },
    FRIENDLY = { 0.35, 0.60, 1.00 },
}
-- The same by standing, with friends in green: the colours the game itself
-- uses for friendly NPC names and the old plates' friendly bars
DATA.REACTION_TINT_RG = {
    HOSTILE  = { 0.95, 0.20, 0.20 },
    NEUTRAL  = { 1.00, 0.85, 0.20 },
    FRIENDLY = { 0.30, 0.90, 0.35 },
}

DATA.FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
DATA.HEALER_ICON = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"   -- healer quadrant
DATA.HEALER_ICON_COORDS = { 0.75, 1, 0, 0.25 }
DATA.CLASS_ICON = "Interface\\TargetingFrame\\UI-Classes-Circles"
DATA.ARROW_ICON = "Interface\\CHATFRAME\\ChatFrameExpandArrow"

-- The Blizzard CVars a PvP profile cares about. Each has a DB key, a range,
-- and whether it is a bool. Read by the settings page AND by the engine, so a
-- CVar added here gets a control and an apply pass at once.
DATA.CVARS = {
    { key = "CvMaxDistance",        cvar = "nameplateMaxDistance",            min = 20,  max = 41,  step = 1,    default = 41,   label = "Nameplate Distance",
      tooltip = "How far away a nameplate is still drawn, in yards. TBC caps this at 41." },
    { key = "CvSelectedScale",      cvar = "nameplateSelectedScale",          min = 1.0, max = 1.6, step = 0.05, default = 1.15, label = "Target Scale",
      tooltip = "How much larger the plate of your current target is drawn than everyone else's." },
    { key = "CvMinScale",           cvar = "nameplateMinScale",               min = 0.5, max = 1.0, step = 0.05, default = 0.8,  label = "Distant Scale",
      tooltip = "How small a far-away plate is allowed to shrink." },
    { key = "CvMinAlpha",           cvar = "nameplateMinAlpha",               min = 0.2, max = 1.0, step = 0.05, default = 0.6,  label = "Distant Opacity",
      tooltip = "How faded a far-away plate is allowed to get." },
    { key = "CvNotSelectedAlpha",   cvar = "nameplateNotSelectedAlpha",       min = 0.2, max = 1.0, step = 0.05, default = 0.75, label = "Non-Target Opacity",
      tooltip = "Opacity of every plate that is NOT your target while you have one. Lower makes the target jump out." },
    { key = "CvOccludedAlpha",      cvar = "nameplateOccludedAlphaMult",      min = 0.0, max = 1.0, step = 0.05, default = 0.4,  label = "Behind-Wall Opacity",
      tooltip = "Extra fade applied to a plate whose unit is behind something." },
    { key = "CvOverlapV",           cvar = "nameplateOverlapV",               min = 0.3, max = 2.0, step = 0.05, default = 1.1,  label = "Stacking Gap (Vertical)",
      tooltip = "How closely stacked plates are allowed to sit vertically. Smaller packs more plates onto the screen." },
    { key = "CvOverlapH",           cvar = "nameplateOverlapH",               min = 0.3, max = 2.0, step = 0.05, default = 0.8,  label = "Stacking Gap (Horizontal)",
      tooltip = "How closely stacked plates are allowed to sit side by side." },
    { key = "CvTargetBehind",       cvar = "nameplateTargetBehindMaxDistance", min = 10, max = 60,  step = 1,    default = 40,   label = "Target Behind Camera",
      tooltip = "How far behind the camera your target's plate is still clamped onto the screen edge." },
    { key = "CvShowAll",            cvar = "nameplateShowAll",                bool = true, default = true,  label = "Always Show Nameplates",
      tooltip = "Draw plates for everyone in range rather than only in combat (the V key)." },
    { key = "CvFriendlyClassColor", cvar = "nameplateShowFriendlyClassColor", bool = true, default = true,  label = "Blizzard: Friendly Class Colour",
      tooltip = "Blizzard's own friendly class-colour flag. This module colours the bar itself whatever this says; keep it on so the two agree." },
    { key = "CvEnemyClassColor",    cvar = "nameplateShowClassColor",         bool = true, default = true,  label = "Blizzard: Enemy Class Colour",
      tooltip = "Blizzard's own enemy class-colour flag." },
    { key = "CvFriendlyNameOnly",   cvar = "nameplateShowOnlyNameForFriendlyPlayerUnits", bool = true, default = false, label = "Friendly Players: Name Only",
      tooltip = "Blizzard's name-only mode for friendly players. Must be OFF for a friendly player to have a health bar to colour." },
    -- Who gets a plate at all. Combat-locked by the client; applied at REGEN.
    { key = "CvEnemyPets",          cvar = "nameplateShowEnemyPets",          bool = true, default = true,  label = "Plates: Enemy Pets",
      tooltip = "Plates on enemy pets -- the felhunter about to Spell Lock you, the hunter pet to Scatter." },
    { key = "CvEnemyGuardians",     cvar = "nameplateShowEnemyGuardians",     bool = true, default = true,  label = "Plates: Enemy Guardians",
      tooltip = "Plates on enemy guardians -- water elementals, treants, elemental totems' summons." },
    { key = "CvEnemyTotems",        cvar = "nameplateShowEnemyTotems",        bool = true, default = true,  label = "Plates: Enemy Totems",
      tooltip = "Plates on enemy totems. Keep ON: the totem icon mode above needs a plate to draw on, and Grounding is the totem that decides fights." },
    { key = "CvFriendlyPets",       cvar = "nameplateShowFriendlyPets",       bool = true, default = false, label = "Plates: Friendly Pets",
      tooltip = "Plates on your team's pets. Off by default; they stand in front of the enemy you are trying to click." },
    { key = "CvFriendlyTotems",     cvar = "nameplateShowFriendlyTotems",     bool = true, default = false, label = "Plates: Friendly Totems",
      tooltip = "Plates on your team's totems. Off by default." },
    { key = "CvFriendlyNpcs",       cvar = "nameplateShowFriendlyNpcs",       bool = true, default = false, label = "Plates: Friendly NPCs",
      tooltip = "Plates on friendly NPCs -- guards, vendors, the battleground's own spirit healers. Off by default." },
    { key = "CvSelectedAlpha",      cvar = "nameplateSelectedAlpha",          min = 0.5, max = 1.0, step = 0.05, default = 1.0,  label = "Target Opacity",
      tooltip = "Opacity of your current target's plate." },
}
