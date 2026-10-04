-- Commander Tradecraft: the guide content.
--
-- Pure data, no client calls. Everything the engine and the window read about
-- a profession lives here: the trainer ranks, every recipe on the route with
-- its skill colours and reagents, the formulas that have to be bought and the
-- vendors that sell them, and the route itself as an ordered list of segments
-- with their alternatives.
--
-- Where the numbers come from (2026-09-17, client build 2.5.6.69795):
--   * recipe reagents and skill colours — the client's own SpellReagents and
--     SkillLineAbility tables (wago.tools, this exact build). The yellow
--     threshold is TrivialSkillLineRankLow and grey is ...High; green is the
--     midpoint, which is how the client colours the craft list.
--   * formula item ids, prices and reputation gates — ItemSparse, same build.
--   * vendors, trainers and their map coordinates — the CMaNGOS TBC world DB,
--     spawn points converted through this build's UiMapAssignment boxes.
--   * the route — Wowhead's TBC Classic Enchanting leveling guide (RenataKane,
--     2026-02-05), cross-checked against the numbers above. Its craft counts
--     carry roughly a ten percent safety margin over the skill-up model; the
--     engine models the remaining crafts itself and keeps the guide's count
--     as the reference figure.
--   * First Aid (2026-09-19): the same tables for thresholds, reagents and
--     placements (through Commander_Formulary's generator, which is where
--     the world-DB reading lives), and Wowhead's TBC Classic First Aid
--     leveling guide (Nodge, 2026-02-05) for the route and its counts.
--
-- Two ids never to confuse: 16207 is the Runed Arcanite ROD (a reagent of the
-- Fel Iron rod), 16243 is the FORMULA that teaches it. Likewise 25127 is
-- Lesser Mana Oil and 25130 is Brilliant; 28019 is Superior Wizard Oil and
-- 28016 is Superior Mana Oil. Every one of these was wrong from memory before
-- the tables were consulted.

CommanderTradecraft_Data = {}
local D = CommanderTradecraft_Data

-- ---------------------------------------------------------------------------
-- Professions
-- ---------------------------------------------------------------------------

-- ranks: the trainer ladder. `at` is the skill you need before the trainer
-- will teach the rank, `cap` is the new maximum. `outland` marks a rank only
-- taught past the Dark Portal. A rank that no trainer teaches says how it
-- IS obtained: `book` (an item to buy and read, with who sells it) or
-- `quest` (with who gives it); the guide window's banner reads these.
D.PROFESSIONS = {
    ENCHANTING = {
        key = "ENCHANTING",
        name = "Enchanting",
        skillLine = 333,
        -- The profession ability itself; GetSpellInfo on it gives the
        -- localised name the skill list uses, so the skill line can be found
        -- without a string match on English.
        abilitySpell = 7411,
        icon = "Interface\\Icons\\Trade_Engraving",
        -- Enchanting uses the CRAFT frame on this client, not the trade
        -- skill frame (it moved in Wrath).
        frame = "CRAFT",
        ranks = {
            { name = "Apprentice", spell = 7411, at = 0, cap = 75 },
            { name = "Journeyman", spell = 7412, at = 50, cap = 150 },
            { name = "Expert", spell = 7413, at = 125, cap = 225 },
            { name = "Artisan", spell = 13920, at = 200, cap = 300 },
            -- Master needs 275, not 300: the trainer will teach it before the
            -- Arcanite rod, and there is no reason to wait.
            { name = "Master", spell = 28029, at = 275, cap = 375, outland = true },
        },
        -- Where the Master rank is taught. Lower ranks are at every capital.
        masterTrainers = {
            { name = "Johan Barnes", where = "Honor Hold, Hellfire Peninsula", zone = "Hellfire Peninsula", x = 53.6, y = 66.1, faction = "Alliance" },
            { name = "Felannia", where = "Thrallmar, Hellfire Peninsula", zone = "Hellfire Peninsula", x = 52.3, y = 36.0, faction = "Horde" },
            { name = "High Enchanter Bardolan", where = "Lower City, Shattrath", zone = "Shattrath City", x = 43.4, y = 92.4 },
            { name = "Asarnan", where = "The Stormspire, Netherstorm", zone = "Netherstorm", x = 44.2, y = 33.7 },
        },
    },
    FIRSTAID = {
        key = "FIRSTAID",
        name = "First Aid",
        skillLine = 129,
        abilitySpell = 3273,
        icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
        -- First Aid is a TRADE SKILL profession: its window is the trade
        -- skill frame and its list is read with GetNumTradeSkills.
        frame = "TRADESKILL",
        -- Two ranks from a trainer, then a book, a quest and a book. The
        -- world DB has no trainer row for Expert, Artisan or Master, and the
        -- published guide agrees: Expert is "Expert First Aid - Under Wraps"
        -- from the manual vendors, Artisan is the Triage quest (the book
        -- "Artisan First Aid - Heal Thyself" exists in the item table and is
        -- sold by nobody), Master is "Master First Aid - Doctor in the
        -- House" from Burko or Aresella and needs 300, not 275.
        ranks = {
            { name = "Apprentice", spell = 3273, at = 0, cap = 75 },
            { name = "Journeyman", spell = 3274, at = 50, cap = 150 },
            { name = "Expert", spell = 7924, at = 125, cap = 225,
              book = { item = 16084, cost = 10000, vendors = { 2805, 13476 } } },
            { name = "Artisan", spell = 10846, at = 225, cap = 300,
              quest = { name = "Triage", givers = {
                  { name = "Doctor Gustaf VanHowzen", where = "Theramore Isle, Dustwallow Marsh", zone = "Dustwallow Marsh", x = 67.8, y = 49.0, faction = "Alliance" },
                  { name = "Doctor Gregory Victor", where = "Hammerfall, Arathi Highlands", zone = "Arathi Highlands", x = 73.4, y = 36.9, faction = "Horde" },
              } } },
            { name = "Master", spell = 27028, at = 300, cap = 375, outland = true,
              book = { item = 22012, cost = 50000, vendors = { 18990, 18991 } } },
        },
    },
}

-- ---------------------------------------------------------------------------
-- Items
-- ---------------------------------------------------------------------------

-- Names are fallbacks for before the client has the item cached; the window
-- prefers GetItemInfo. `note` is shown on the shopping list for anything that
-- cannot simply be bought off the auction house. `vendor` marks items sold
-- by ordinary trade-supply vendors, and `buy` is that vendor price in
-- copper (ItemSparse BuyPrice, this build) — the price the engine uses for
-- them, since nobody buys a Copper Rod off the auction house.
D.ITEMS = {
    -- Rods (the blank ones are Blacksmithing products)
    [6217] = { name = "Copper Rod", vendor = true, buy = 124, note = "Trade-supply vendors" },
    [6338] = { name = "Silver Rod", note = "Made by Blacksmiths — buy one from the Auction House" },
    [11128] = { name = "Golden Rod", note = "Made by Blacksmiths — buy one from the Auction House" },
    [11144] = { name = "Truesilver Rod", note = "Made by Blacksmiths — buy one from the Auction House" },
    [16206] = { name = "Arcanite Rod", note = "Made by Blacksmiths — buy one from the Auction House" },
    [25843] = { name = "Fel Iron Rod", note = "Made by Blacksmiths — buy one from the Auction House" },
    [25844] = { name = "Adamantite Rod", note = "Made by Blacksmiths — buy one from the Auction House" },
    -- The runed rods you make along the way (each is a reagent of the next)
    [6218] = { name = "Runed Copper Rod", made = true },
    [6339] = { name = "Runed Silver Rod", made = true },
    [11130] = { name = "Runed Golden Rod", made = true },
    [11145] = { name = "Runed Truesilver Rod", made = true },
    [16207] = { name = "Runed Arcanite Rod", made = true },
    [22461] = { name = "Runed Fel Iron Rod", made = true },
    [22462] = { name = "Runed Adamantite Rod", made = true },
    -- What the route makes to sell (named so a price search can ask for them
    -- before the client has ever seen one)
    [11288] = { name = "Greater Magic Wand" },
    [20747] = { name = "Lesser Mana Oil" },
    [22522] = { name = "Superior Wizard Oil" },
    -- Dusts, essences, shards
    [10940] = { name = "Strange Dust" },
    [10938] = { name = "Lesser Magic Essence" },
    [10939] = { name = "Greater Magic Essence" },
    [10998] = { name = "Lesser Astral Essence" },
    [11082] = { name = "Greater Astral Essence" },
    [11083] = { name = "Soul Dust" },
    [11137] = { name = "Vision Dust" },
    [11135] = { name = "Greater Mystic Essence" },
    [11174] = { name = "Lesser Nether Essence" },
    [11176] = { name = "Dream Dust" },
    [16204] = { name = "Illusion Dust" },
    [16203] = { name = "Greater Eternal Essence" },
    [14344] = { name = "Large Brilliant Shard" },
    [22445] = { name = "Arcane Dust" },
    [22446] = { name = "Greater Planar Essence" },
    [22449] = { name = "Large Prismatic Shard" },
    -- Everything else
    [4470] = { name = "Simple Wood", vendor = true, buy = 38, note = "Trade-supply vendors" },
    [5500] = { name = "Iridescent Pearl", note = "Drops from clams — Auction House" },
    [7971] = { name = "Black Pearl", note = "Drops from clams — Auction House" },
    [13926] = { name = "Golden Pearl", note = "Drops from clams — Auction House" },
    [8831] = { name = "Purple Lotus", note = "Herb — Auction House" },
    [8925] = { name = "Crystal Vial", vendor = true, buy = 2500, note = "Trade-supply and alchemy vendors" },
    [22792] = { name = "Nightmare Vine", note = "Outland herb — Auction House" },
    [18256] = { name = "Imbued Vial", vendor = true, buy = 20000, note = "Trade-supply vendors" },
    [23571] = { name = "Primal Might", note = "Alchemy transmute — Auction House" },
    -- Formulas
    [11039] = { name = "Formula: Enchant Cloak - Minor Agility", formula = true },
    [11101] = { name = "Formula: Enchant Bracer - Lesser Strength", formula = true },
    [20754] = { name = "Formula: Lesser Mana Oil", formula = true },
    [16217] = { name = "Formula: Enchant Shield - Greater Stamina", formula = true },
    [16224] = { name = "Formula: Enchant Cloak - Superior Defense", formula = true },
    [16243] = { name = "Formula: Runed Arcanite Rod", formula = true },
    [22563] = { name = "Formula: Superior Wizard Oil", formula = true },
    [25848] = { name = "Formula: Runed Adamantite Rod", formula = true },
    [22536] = { name = "Formula: Enchant Ring - Spellpower", formula = true },
    [22535] = { name = "Formula: Enchant Ring - Striking", formula = true },

    -- First Aid: the cloths (Auction House, or your own drops), what the
    -- route makes (bandages -- kept, not sold, but named so a price search
    -- can ask), the manuals, and the two rank books
    [2589] = { name = "Linen Cloth" },
    [2592] = { name = "Wool Cloth" },
    [4306] = { name = "Silk Cloth" },
    [4338] = { name = "Mageweave Cloth" },
    [14047] = { name = "Runecloth" },
    [21877] = { name = "Netherweave Cloth" },
    [1251] = { name = "Linen Bandage" },
    [2581] = { name = "Heavy Linen Bandage" },
    [3530] = { name = "Wool Bandage" },
    [3531] = { name = "Heavy Wool Bandage" },
    [6450] = { name = "Silk Bandage" },
    [6451] = { name = "Heavy Silk Bandage" },
    [8544] = { name = "Mageweave Bandage" },
    [8545] = { name = "Heavy Mageweave Bandage" },
    [14529] = { name = "Runecloth Bandage" },
    [14530] = { name = "Heavy Runecloth Bandage" },
    [21990] = { name = "Netherweave Bandage" },
    [21991] = { name = "Heavy Netherweave Bandage" },
    [16112] = { name = "Manual: Heavy Silk Bandage", formula = true },
    [16113] = { name = "Manual: Mageweave Bandage", formula = true },
    [21992] = { name = "Manual: Netherweave Bandage", formula = true },
    [21993] = { name = "Manual: Heavy Netherweave Bandage", formula = true },
    [16084] = { name = "Expert First Aid - Under Wraps", formula = true },
    [22012] = { name = "Master First Aid - Doctor in the House", formula = true },
}

-- ---------------------------------------------------------------------------
-- Zones
-- ---------------------------------------------------------------------------

-- uiMapIDs for the zone maps the vendors and trainers stand on (UiMap table,
-- this build), so a waypoint can be handed to Commander Orders without a name
-- lookup. A zone missing here gets a /way line by name instead (D17).
D.ZONES = {
    ["Arathi Highlands"] = 1417,
    ["Ashenvale"] = 1440,
    ["Dustwallow Marsh"] = 1445,
    ["Stonetalon Mountains"] = 1442,
    ["Tanaris"] = 1446,
    ["Moonglade"] = 1450,
    ["Silithus"] = 1451,
    ["Darnassus"] = 1457,
    ["Undercity"] = 1458,
    ["Hellfire Peninsula"] = 1944,
    ["The Exodar"] = 1947,
    ["Terokkar Forest"] = 1952,
    ["Netherstorm"] = 1953,
    ["Silvermoon City"] = 1954,
    ["Shattrath City"] = 1955,
}

-- ---------------------------------------------------------------------------
-- Vendors
-- ---------------------------------------------------------------------------

-- `faction` is who can trade with them; nil means both. Coordinates are on
-- the zone map named in `zone`.
D.VENDORS = {
    [3954] = { name = "Dalria", where = "Astranaar", zone = "Ashenvale", x = 35.0, y = 52.0, faction = "Alliance" },
    [12043] = { name = "Kulwia", where = "Sun Rock Retreat", zone = "Stonetalon Mountains", x = 45.4, y = 59.4, faction = "Horde" },
    [15419] = { name = "Kania", where = "Cenarion Hold", zone = "Silithus", x = 52.0, y = 39.6 },
    [4229] = { name = "Mythrin'dir", where = "Craftsmen's Terrace", zone = "Darnassus", x = 61.4, y = 18.8, faction = "Alliance" },
    [4561] = { name = "Daniel Bartlett", where = "The Magic Quarter", zone = "Undercity", x = 64.8, y = 38.2, faction = "Horde" },
    [12022] = { name = "Lorelae Wintersong", where = "Nighthaven", zone = "Moonglade", x = 48.2, y = 40.0 },
    [16722] = { name = "Egomis", where = "The Crystal Hall", zone = "The Exodar", x = 39.8, y = 39.8, faction = "Alliance" },
    [16635] = { name = "Lyna", where = "Walk of Elders", zone = "Silvermoon City", x = 70.0, y = 24.6, faction = "Horde" },
    [19663] = { name = "Madame Ruby", where = "Lower City", zone = "Shattrath City", x = 63.6, y = 70.0 },
    [19004] = { name = "Vodesiin", where = "Honor Hold", zone = "Hellfire Peninsula", x = 24.4, y = 38.8, faction = "Alliance" },
    [18960] = { name = "Rungor", where = "Stonebreaker Hold", zone = "Terokkar Forest", x = 48.8, y = 46.0, faction = "Horde" },
    [21643] = { name = "Alurmi", where = "Caverns of Time", zone = "Tanaris", x = 63.6, y = 57.6 },
    [20242] = { name = "Karaaz", where = "The Stormspire", zone = "Netherstorm", x = 43.6, y = 34.3 },
    -- First Aid: the two classic manual vendors (one per faction) and the
    -- two Hellfire ones. Placed from the world DB's spawn points through
    -- this build's UiMapAssignment, and agreeing with the published guide.
    [2805] = { name = "Deneb Walker", where = "Stromgarde Keep", zone = "Arathi Highlands", x = 27.0, y = 58.8, faction = "Alliance" },
    [13476] = { name = "Balai Lok'Wein", where = "Brackenwall Village", zone = "Dustwallow Marsh", x = 36.5, y = 30.4, faction = "Horde" },
    [18990] = { name = "Burko", where = "Temple of Telhamat", zone = "Hellfire Peninsula", x = 22.3, y = 39.4, faction = "Alliance" },
    [18991] = { name = "Aresella", where = "Falcon Watch", zone = "Hellfire Peninsula", x = 26.2, y = 62.1, faction = "Horde" },
}

-- ---------------------------------------------------------------------------
-- Recipes
-- ---------------------------------------------------------------------------

-- yellow / grey straight from SkillLineAbility; green is derived. `target`
-- is the equip location an enchant has to be cast on (nil for things that
-- make an item). `creates` is the item a non-enchant recipe produces.
-- `formula` is the item that teaches it when it is not trainer-taught.
local INVTYPE = {
    WRIST = "INVTYPE_WRIST", CLOAK = "INVTYPE_CLOAK", CHEST = "INVTYPE_CHEST",
    HAND = "INVTYPE_HAND", FEET = "INVTYPE_FEET", SHIELD = "INVTYPE_SHIELD",
    FINGER = "INVTYPE_FINGER",
}
D.INVTYPE = INVTYPE

local function R(id, name, yellow, grey, reagents, extra)
    local rec = { spell = id, name = name, yellow = yellow, grey = grey,
        green = math.floor((yellow + grey) / 2), reagents = reagents }
    if extra then
        for k, v in pairs(extra) do rec[k] = v end
    end
    return rec
end

local RECIPE_LIST = {
    -- Rods
    R(7421, "Runed Copper Rod", 5, 10, { { 6217, 1 }, { 10940, 1 }, { 10938, 1 } }, { creates = 6218 }),
    R(7795, "Runed Silver Rod", 130, 170, { { 6338, 1 }, { 10940, 6 }, { 10939, 3 }, { 6218, 1 } }, { creates = 6339 }),
    R(13628, "Runed Golden Rod", 175, 215, { { 11128, 1 }, { 5500, 1 }, { 11082, 2 }, { 11083, 2 }, { 6339, 1 } }, { creates = 11130 }),
    R(13702, "Runed Truesilver Rod", 220, 260, { { 11144, 1 }, { 7971, 1 }, { 11135, 2 }, { 11137, 2 }, { 11130, 1 } }, { creates = 11145 }),
    R(20051, "Runed Arcanite Rod", 305, 340, { { 16206, 1 }, { 13926, 1 }, { 16204, 10 }, { 16203, 4 }, { 11145, 1 }, { 14344, 2 } }, { creates = 16207, formula = 16243 }),
    R(32664, "Runed Fel Iron Rod", 310, 340, { { 25843, 1 }, { 16203, 4 }, { 14344, 6 }, { 16207, 1 } }, { creates = 22461 }),
    R(32665, "Runed Adamantite Rod", 360, 390, { { 25844, 1 }, { 22446, 8 }, { 22449, 8 }, { 23571, 1 }, { 22461, 1 } }, { creates = 22462, formula = 25848 }),
    -- Classic enchants
    R(7418, "Enchant Bracer - Minor Health", 70, 110, { { 10940, 1 } }, { target = INVTYPE.WRIST }),
    R(7457, "Enchant Bracer - Minor Stamina", 100, 140, { { 10940, 3 } }, { target = INVTYPE.WRIST }),
    R(14807, "Greater Magic Wand", 110, 150, { { 4470, 1 }, { 10939, 1 } }, { creates = 11288 }),
    R(13419, "Enchant Cloak - Minor Agility", 135, 175, { { 10998, 1 } }, { target = INVTYPE.CLOAK, formula = 11039 }),
    R(13378, "Enchant Shield - Minor Stamina", 130, 170, { { 10998, 1 }, { 10940, 2 } }, { target = INVTYPE.SHIELD }),
    R(13501, "Enchant Bracer - Lesser Stamina", 155, 195, { { 11083, 2 } }, { target = INVTYPE.WRIST }),
    R(13536, "Enchant Bracer - Lesser Strength", 165, 205, { { 11083, 2 } }, { target = INVTYPE.WRIST, formula = 11101 }),
    R(13640, "Enchant Chest - Greater Health", 180, 220, { { 11083, 3 } }, { target = INVTYPE.CHEST }),
    R(13661, "Enchant Bracer - Strength", 200, 240, { { 11137, 1 } }, { target = INVTYPE.WRIST }),
    R(13746, "Enchant Cloak - Greater Defense", 225, 265, { { 11137, 3 } }, { target = INVTYPE.CLOAK }),
    R(13815, "Enchant Gloves - Agility", 230, 270, { { 11174, 1 }, { 11137, 1 } }, { target = INVTYPE.HAND }),
    R(13836, "Enchant Boots - Stamina", 235, 275, { { 11137, 5 } }, { target = INVTYPE.FEET }),
    R(13858, "Enchant Chest - Superior Health", 240, 280, { { 11137, 6 } }, { target = INVTYPE.CHEST }),
    R(25127, "Lesser Mana Oil", 260, 280, { { 11176, 3 }, { 8831, 2 }, { 8925, 1 } }, { creates = 20747, formula = 20754 }),
    R(20017, "Enchant Shield - Greater Stamina", 285, 325, { { 11176, 10 } }, { target = INVTYPE.SHIELD, formula = 16217 }),
    R(20015, "Enchant Cloak - Superior Defense", 300, 335, { { 16204, 8 } }, { target = INVTYPE.CLOAK, formula = 16224 }),
    -- Outland
    R(27961, "Enchant Cloak - Major Armor", 320, 350, { { 22445, 8 } }, { target = INVTYPE.CLOAK }),
    R(34002, "Enchant Bracer - Assault", 310, 340, { { 22445, 6 } }, { target = INVTYPE.WRIST }),
    R(27899, "Enchant Bracer - Brawn", 315, 345, { { 22445, 6 } }, { target = INVTYPE.WRIST }),
    R(33990, "Enchant Chest - Major Spirit", 330, 360, { { 22446, 2 } }, { target = INVTYPE.CHEST }),
    R(28019, "Superior Wizard Oil", 340, 360, { { 22445, 3 }, { 22792, 1 }, { 18256, 1 } }, { creates = 22522, formula = 22563 }),
    R(33995, "Enchant Gloves - Major Strength", 350, 380, { { 22445, 12 }, { 22446, 1 } }, { target = INVTYPE.HAND }),
    R(27920, "Enchant Ring - Striking", 370, 400, { { 22449, 2 }, { 22445, 6 } }, { target = INVTYPE.FINGER, formula = 22535 }),
    R(27924, "Enchant Ring - Spellpower", 370, 400, { { 22449, 2 }, { 22446, 2 } }, { target = INVTYPE.FINGER, formula = 22536 }),
    -- First Aid. Every bandage is one or two of its cloth; nothing to
    -- target, so the Craft button is a bare /cast.
    R(3275, "Linen Bandage", 30, 60, { { 2589, 1 } }, { creates = 1251 }),
    R(3276, "Heavy Linen Bandage", 50, 100, { { 2589, 2 } }, { creates = 2581 }),
    R(3277, "Wool Bandage", 80, 150, { { 2592, 1 } }, { creates = 3530 }),
    R(3278, "Heavy Wool Bandage", 115, 185, { { 2592, 2 } }, { creates = 3531 }),
    R(7928, "Silk Bandage", 150, 210, { { 4306, 1 } }, { creates = 6450 }),
    R(7929, "Heavy Silk Bandage", 180, 240, { { 4306, 2 } }, { creates = 6451, formula = 16112 }),
    R(10840, "Mageweave Bandage", 210, 270, { { 4338, 1 } }, { creates = 8544, formula = 16113 }),
    R(10841, "Heavy Mageweave Bandage", 240, 300, { { 4338, 2 } }, { creates = 8545 }),
    R(18629, "Runecloth Bandage", 260, 320, { { 14047, 1 } }, { creates = 14529 }),
    R(18630, "Heavy Runecloth Bandage", 290, 350, { { 14047, 2 } }, { creates = 14530 }),
    R(27032, "Netherweave Bandage", 330, 390, { { 21877, 1 } }, { creates = 21990, formula = 21992 }),
    R(27033, "Heavy Netherweave Bandage", 360, 410, { { 21877, 2 } }, { creates = 21991, formula = 21993 }),
}

D.RECIPES = {}
for _, rec in ipairs(RECIPE_LIST) do
    D.RECIPES[rec.spell] = rec
end

-- Trainer-taught recipes and the skill the trainer wants before teaching
-- them (CMaNGOS npc_trainer_template, spell -> reqskillvalue). Anything on
-- the route that is not here is taught by a formula, except the two you are
-- handed with Apprentice Enchanting itself (the copper rod and Minor Health).
local TRAINER_LEARN = {
    [7421] = 0, [7418] = 0,
    [7457] = 50, [14807] = 70, [7795] = 100, [13378] = 105, [13501] = 130,
    [13628] = 150, [13640] = 160, [13661] = 180, [13702] = 200, [13746] = 205,
    [13815] = 210, [13836] = 215, [13858] = 220,
    [32664] = 300, [34002] = 300, [27899] = 305, [27961] = 310, [33990] = 320,
    [33995] = 340,
    -- First Aid (Linen Bandage comes with Apprentice First Aid itself)
    [3275] = 0, [3276] = 40, [3277] = 80, [3278] = 115, [7928] = 150,
    [10841] = 240, [18629] = 260, [18630] = 290,
}
for spell, at in pairs(TRAINER_LEARN) do
    if D.RECIPES[spell] then
        D.RECIPES[spell].learn = at
    end
end

-- ---------------------------------------------------------------------------
-- Formulas: what teaches what, where to buy it, what it costs
-- ---------------------------------------------------------------------------

-- cost in copper. rep = { faction = id, standing = index, label = text }
-- (standing indexes as the client counts them: 5 Honored, 6 Revered).
D.FORMULAS = {
    [11039] = { learns = 13419, at = 110, cost = 800, vendors = { 3954, 12043 } },
    [11101] = { learns = 13536, at = 140, cost = 2500, vendors = { 3954, 12043 } },
    [20754] = { learns = 25127, at = 250, cost = 10000, vendors = { 15419 } },
    [16217] = { learns = 20017, at = 265, cost = 12000, vendors = { 4229, 4561 } },
    [16224] = { learns = 20015, at = 285, cost = 20000, vendors = { 12022 } },
    [16243] = { learns = 20051, at = 290, cost = 22000, vendors = { 12022 } },
    [22563] = { learns = 28019, at = 340, cost = 70000, vendors = { 16722, 16635, 19663 } },
    [25848] = { learns = 32665, at = 350, cost = 100000, vendors = { 19004, 18960 } },
    [22536] = { learns = 27924, at = 360, cost = 100000, vendors = { 21643 },
        rep = { faction = 989, standing = 5, label = "Honored with Keepers of Time" } },
    [22535] = { learns = 27920, at = 360, cost = 100000, vendors = { 20242 },
        rep = { faction = 933, standing = 6, label = "Revered with The Consortium" } },
    -- First Aid manuals
    [16112] = { learns = 7929, at = 180, cost = 2200, vendors = { 2805, 13476 } },
    [16113] = { learns = 10840, at = 210, cost = 5000, vendors = { 2805, 13476 } },
    [21992] = { learns = 27032, at = 330, cost = 20000, vendors = { 18990, 18991 } },
    [21993] = { learns = 27033, at = 360, cost = 40000, vendors = { 18990, 18991 } },
}

-- ---------------------------------------------------------------------------
-- The route
-- ---------------------------------------------------------------------------

-- A guide is an ordered list of segments. Each segment covers a skill range
-- and offers one or more paths through it; the first path is the guide's
-- recommendation and any others are the alternatives it names. A path is an
-- ordered list of steps:
--   { kind = "craft", spell = id, from = n, to = n, count = n }
--       craft `spell` until skill reaches `to`; `count` is the guide's own
--       estimate of how many that takes, kept as the reference figure. It
--       is absent on the alternatives the guide only names, and the engine's
--       own model stands in.
--   { kind = "buy", item = formulaId }
--       buy the formula (vendors, price and rep gate come from FORMULAS)
--       and learn it. `at` on the formula is the skill it needs.
-- Trainer visits are not steps: the engine derives them from the rank table
-- and surfaces them as a banner whenever the next rank is trainable.

local function craft(spell, from, to, count)
    return { kind = "craft", spell = spell, from = from, to = to, count = count }
end
local function buy(item)
    return { kind = "buy", item = item }
end

D.GUIDES = {
    ENCHANTING = {
        key = "ENCHANTING",
        profession = "ENCHANTING",
        title = "Enchanting 1 – 375",
        credit = "Route after Wowhead's TBC Classic Enchanting guide (RenataKane)",
        tips = {
            "Disenchanting also gives skill-ups until 60 (yellow at 20, green at 40) if you have greens to spare.",
            "Enchants that target gear can be cast on your own equipped pieces over and over — the guide's Craft button does exactly that.",
            "Every runed rod is a reagent of the next one, so never sell or disenchant the rod you just made.",
        },
        segments = {
            {
                key = "1-2", from = 1, to = 2,
                paths = { { key = "main", label = "Runed Copper Rod", steps = { craft(7421, 1, 2, 1) } } },
            },
            {
                key = "2-90", from = 2, to = 90,
                paths = { { key = "main", label = "Enchant Bracer - Minor Health", steps = { craft(7418, 2, 90, 100) } } },
            },
            {
                key = "90-100", from = 90, to = 100,
                paths = { { key = "main", label = "Enchant Bracer - Minor Stamina", steps = { craft(7457, 90, 100, 10) } } },
            },
            {
                key = "100-101", from = 100, to = 101,
                paths = { { key = "main", label = "Runed Silver Rod", steps = { craft(7795, 100, 101, 1) } } },
            },
            {
                key = "101-110", from = 101, to = 110,
                paths = { { key = "main", label = "Greater Magic Wand", steps = { craft(14807, 101, 110, 9) } } },
            },
            {
                key = "110-135", from = 110, to = 135,
                paths = {
                    { key = "main", label = "Enchant Cloak - Minor Agility",
                      note = "Formula from a vendor (8 silver); one Lesser Astral Essence a cast.",
                      steps = { buy(11039), craft(13419, 110, 135, 25) } },
                    { key = "alt", label = "Enchant Shield - Minor Stamina",
                      note = "Trainer-taught, so no vendor trip — but it turns yellow at 130 instead of 135 and costs two Strange Dust more per cast.",
                      steps = { craft(13378, 110, 135) } },
                },
            },
            {
                key = "135-155", from = 135, to = 155,
                paths = { { key = "main", label = "Enchant Bracer - Lesser Stamina", steps = { craft(13501, 135, 155, 20) } } },
            },
            {
                key = "155-156", from = 155, to = 156,
                paths = { { key = "main", label = "Runed Golden Rod", steps = { craft(13628, 155, 156, 1) } } },
            },
            {
                key = "156-185", from = 156, to = 185,
                paths = {
                    { key = "main", label = "Enchant Bracer - Lesser Strength",
                      note = "Formula from a vendor (25 silver); the cheapest Soul Dust route.",
                      steps = { buy(11101), craft(13536, 156, 185, 35) } },
                    { key = "alt", label = "Lesser Stamina, then Chest - Greater Health",
                      note = "Both trainer-taught. Marginally more Soul Dust, no vendor trip.",
                      steps = { craft(13501, 156, 175), craft(13640, 175, 185) } },
                },
            },
            {
                key = "185-200", from = 185, to = 200,
                paths = { { key = "main", label = "Enchant Bracer - Strength", steps = { craft(13661, 185, 200, 15) } } },
            },
            {
                key = "200-201", from = 200, to = 201,
                paths = { { key = "main", label = "Runed Truesilver Rod", steps = { craft(13702, 200, 201, 1) } } },
            },
            {
                key = "201-220", from = 201, to = 220,
                paths = { { key = "main", label = "Enchant Bracer - Strength", steps = { craft(13661, 201, 220, 25) } } },
            },
            {
                key = "220-225", from = 220, to = 225,
                paths = { { key = "main", label = "Enchant Cloak - Greater Defense", steps = { craft(13746, 220, 225, 5) } } },
            },
            {
                key = "225-230", from = 225, to = 230,
                paths = { { key = "main", label = "Enchant Gloves - Agility", steps = { craft(13815, 225, 230, 5) } } },
            },
            {
                key = "230-235", from = 230, to = 235,
                paths = { { key = "main", label = "Enchant Boots - Stamina", steps = { craft(13836, 230, 235, 5) } } },
            },
            {
                key = "235-250", from = 235, to = 250,
                paths = { { key = "main", label = "Enchant Chest - Superior Health", steps = { craft(13858, 235, 250, 18) } } },
            },
            {
                key = "250-265", from = 250, to = 265,
                paths = { { key = "main", label = "Lesser Mana Oil",
                    note = "Formula from Kania in Cenarion Hold (1 gold). The oils sell.",
                    steps = { buy(20754), craft(25127, 250, 265, 17) } } },
            },
            {
                key = "265-285", from = 265, to = 285,
                paths = { { key = "main", label = "Enchant Shield - Greater Stamina",
                    note = "Formula from your capital's enchanting supplier (1 gold 20).",
                    steps = { buy(16217), craft(20017, 265, 285, 20) } } },
            },
            {
                key = "285-299", from = 285, to = 299,
                paths = { { key = "main", label = "Enchant Cloak - Superior Defense",
                    note = "Both Moonglade formulas in one trip: this one and the Arcanite rod's.",
                    steps = { buy(16224), buy(16243), craft(20015, 285, 299, 14) } } },
            },
            {
                key = "299-300", from = 299, to = 300,
                paths = { { key = "main", label = "Runed Arcanite Rod", steps = { craft(20051, 299, 300, 1) } } },
            },
            -- Outland. Master Enchanting first (the banner will say so).
            {
                key = "300-301", from = 300, to = 301,
                paths = { { key = "main", label = "Runed Fel Iron Rod", steps = { craft(32664, 300, 301, 1) } } },
            },
            {
                key = "301-320", from = 301, to = 320,
                paths = {
                    { key = "main", label = "Superior Defense, then Cloak - Major Armor",
                      note = "Cheapest when Illusion Dust is cheap: stay on Superior Defense to 317, then three Major Armor.",
                      steps = { craft(20015, 301, 317, 25), craft(27961, 317, 320, 3) } },
                    { key = "alt", label = "Bracer - Assault, Brawn, then Major Armor",
                      note = "All Arcane Dust, all trainer-taught. Better when Arcane Dust is cheap or you are out of Illusion Dust.",
                      steps = { craft(34002, 301, 305), craft(27899, 305, 315), craft(27961, 315, 320) } },
                },
            },
            {
                key = "320-340", from = 320, to = 340,
                paths = {
                    { key = "main", label = "Enchant Chest - Major Spirit",
                      note = "Two Greater Planar Essence a cast.",
                      steps = { craft(33990, 320, 340, 25) } },
                    { key = "alt", label = "Major Armor to 335, then Major Spirit",
                      note = "Take this when eight Arcane Dust is at least a quarter cheaper than two Greater Planar Essence.",
                      steps = { craft(27961, 320, 335), craft(33990, 335, 340) } },
                },
            },
            {
                key = "340-350", from = 340, to = 350,
                paths = { { key = "main", label = "Superior Wizard Oil",
                    note = "Formula from Madame Ruby in Shattrath, or your own capital in Outland (7 gold). The oils sell well.",
                    steps = { buy(22563), craft(28019, 340, 350, 15) } } },
            },
            {
                key = "350-351", from = 350, to = 351,
                paths = { { key = "main", label = "Runed Adamantite Rod",
                    note = "Formula from Vodesiin (Honor Hold) or Rungor (Stonebreaker Hold), 10 gold. Needs a Primal Might.",
                    steps = { buy(25848), craft(32665, 350, 351, 1) } } },
            },
            {
                key = "351-365", from = 351, to = 365,
                paths = {
                    { key = "main", label = "Enchant Gloves - Major Strength",
                      note = "Trainer-taught; twelve Arcane Dust and one Greater Planar Essence a cast.",
                      steps = { craft(33995, 351, 365, 20) } },
                    { key = "alt", label = "Enchant Ring - Striking",
                      note = "Needs Revered with The Consortium for the formula (Karaaz, the Stormspire). Cheaper per point if you have the rep.",
                      steps = { buy(22535), craft(27920, 351, 365) } },
                },
            },
            {
                key = "365-375", from = 365, to = 375,
                paths = { { key = "main", label = "Enchant Ring - Spellpower",
                    note = "Formula from Alurmi at the Caverns of Time — Honored with Keepers of Time (10 gold).",
                    steps = { buy(22536), craft(27924, 365, 375, 12) } } },
            },
        },
    },
    -- First Aid. One way through every segment: bandages are the only
    -- recipes worth a skill point (anti-venoms want venom sacs), so the
    -- route is the cloth ladder and its two vendor trips. The ranks that
    -- are not trainer-taught -- the Expert book at 125, Triage at 225, the
    -- Master book at 300 -- are the banner's, as every rank is.
    FIRSTAID = {
        key = "FIRSTAID",
        profession = "FIRSTAID",
        title = "First Aid 1 – 375",
        credit = "Route after Wowhead's TBC Classic First Aid guide (Nodge)",
        tips = {
            "Every bandage you make is worth keeping: a Heavy Runecloth Bandage heals 2000 and a Heavy Netherweave 3400, and they are what you will use in every battleground.",
            "The cloth is what the mobs you are already killing drop. Level First Aid as you go and it costs nothing.",
            "Both Arathi-tier manuals and the Expert book are on the same vendor — buy all three in one trip at 125.",
        },
        segments = {
            {
                key = "1-40", from = 1, to = 40,
                paths = { { key = "main", label = "Linen Bandage", steps = { craft(3275, 1, 40, 50) } } },
            },
            {
                key = "40-80", from = 40, to = 80,
                paths = { { key = "main", label = "Heavy Linen Bandage", steps = { craft(3276, 40, 80, 70) } } },
            },
            {
                key = "80-115", from = 80, to = 115,
                paths = { { key = "main", label = "Wool Bandage", steps = { craft(3277, 80, 115, 55) } } },
            },
            {
                key = "115-150", from = 115, to = 150,
                paths = { { key = "main", label = "Heavy Wool Bandage",
                    note = "Past 150 needs Expert First Aid - Under Wraps (the banner has the vendor). Buy the Heavy Silk and Mageweave manuals in the same trip; they are used at 180 and 210.",
                    steps = { buy(16112), buy(16113), craft(3278, 115, 150, 55) } } },
            },
            {
                key = "150-180", from = 150, to = 180,
                paths = { { key = "main", label = "Silk Bandage", steps = { craft(7928, 150, 180, 50) } } },
            },
            {
                key = "180-210", from = 180, to = 210,
                paths = { { key = "main", label = "Heavy Silk Bandage", steps = { craft(7929, 180, 210, 50) } } },
            },
            {
                key = "210-240", from = 210, to = 240,
                paths = { { key = "main", label = "Mageweave Bandage",
                    note = "Artisan First Aid is the Triage quest at 225 (the banner has the doctor); Mageweave carries you to 240 either side of it.",
                    steps = { craft(10840, 210, 240, 55) } } },
            },
            {
                key = "240-260", from = 240, to = 260,
                paths = { { key = "main", label = "Heavy Mageweave Bandage", steps = { craft(10841, 240, 260, 30) } } },
            },
            {
                key = "260-290", from = 260, to = 290,
                paths = { { key = "main", label = "Runecloth Bandage", steps = { craft(18629, 260, 290, 50) } } },
            },
            {
                key = "290-330", from = 290, to = 330,
                paths = { { key = "main", label = "Heavy Runecloth Bandage",
                    note = "Master First Aid - Doctor in the House at 300 (Burko or Aresella in Hellfire; the banner has them), then carry on with the same bandage to 330.",
                    steps = { craft(18630, 290, 330, 95) } } },
            },
            {
                key = "330-360", from = 330, to = 360,
                paths = { { key = "main", label = "Netherweave Bandage",
                    note = "Manual from Burko (Temple of Telhamat) or Aresella (Falcon Watch), 2 gold — the same vendor as the Master book and the Heavy Netherweave manual.",
                    steps = { buy(21992), craft(27032, 330, 360, 50) } } },
            },
            {
                key = "360-375", from = 360, to = 375,
                paths = { { key = "main", label = "Heavy Netherweave Bandage",
                    note = "Manual from the same Hellfire vendor, 4 gold.",
                    steps = { buy(21993), craft(27033, 360, 375, 20) } } },
            },
        },
    },
}

-- ---------------------------------------------------------------------------
-- Small lookups the window uses
-- ---------------------------------------------------------------------------

-- Which equipment slot ids an enchant of a given equip location can be cast
-- on, in the order to try them.
D.TARGET_SLOTS = {
    [INVTYPE.WRIST] = { 9 },
    [INVTYPE.CLOAK] = { 15 },
    [INVTYPE.CHEST] = { 5 },
    [INVTYPE.HAND] = { 10 },
    [INVTYPE.FEET] = { 8 },
    [INVTYPE.SHIELD] = { 17 },
    [INVTYPE.FINGER] = { 11, 12 },
}

-- Plain words for the equip location, for the "equip a ..." hint.
D.TARGET_WORDS = {
    [INVTYPE.WRIST] = "bracers",
    [INVTYPE.CLOAK] = "a cloak",
    [INVTYPE.CHEST] = "a chest piece",
    [INVTYPE.HAND] = "gloves",
    [INVTYPE.FEET] = "boots",
    [INVTYPE.SHIELD] = "a shield",
    [INVTYPE.FINGER] = "a ring",
}

-- Equip locations the client reports that count as a match for a target.
-- Robes are chests; a ring is a finger.
D.TARGET_ACCEPTS = {
    [INVTYPE.CHEST] = { INVTYPE_CHEST = true, INVTYPE_ROBE = true },
}
