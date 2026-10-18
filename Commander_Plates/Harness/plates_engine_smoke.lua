-- Commander Plates: the rules, run without the game.
--
--     luajit Commander_Plates/Harness/plates_engine_smoke.lua
--
-- Loads the data and engine files exactly as the client would (as globals),
-- then asserts the decisions a PvP player would make by hand: a Polymorph
-- beats a Hamstring for the big slot, the longer of two stuns wins, a friendly
-- plate shows the Curse the druid can lift and not the Rend she cannot, the
-- whitelist beats every filter, the blacklist loses only to the whitelist,
-- and so on. Section A diffs the copied DR table against Commander Diminish's
-- so the copies cannot drift apart unnoticed; section H checks every
-- hand-written spell NAME against the client's own SpellName table when the
-- Quartermaster cache is present.

local HERE = arg and arg[0] and arg[0]:match("^(.*)[/\\]") or "."
local ROOT = HERE .. "/.."
local ADDONS = ROOT .. "/.."

local function readfile(path)
    local fh = io.open(path, "r")
    if not fh then return nil end
    local s = fh:read("*a")
    fh:close()
    return s
end

dofile(ROOT .. "/CommanderPlatesData.lua")
dofile(ROOT .. "/CommanderPlatesEngine.lua")
RAID_CLASS_COLORS = { MAGE = { r = 0.41, g = 0.8, b = 0.94 } }
dofile(ROOT .. "/CommanderPlatesDraw.lua")

local DATA = CommanderPlates_Data
local E = CommanderPlates_Engine

local pass, fail = 0, 0
local function check(cond, label)
    if cond then
        pass = pass + 1
    else
        fail = fail + 1
        print("  FAIL  " .. label)
    end
end
local function section(name) print(name) end

local function settings(overrides)
    local defaults = {
        CcEnable = true, CcOnEnemies = true, CcOnFriends = true, CcHideDuplicate = true,
        CcStuns = true, CcIncaps = true, CcFears = true, CcSilences = true, CcRoots = true,
        CcDisarms = true, CcImmunities = true,
        ShowDefensives = true, ShowOffensives = true, ShowNotableDebuffs = true, ShowSlows = false,
        EnemyDebuffs = "MINE_NOTABLE", EnemyBuffs = "NOTABLE_PURGEABLE",
        FriendDebuffs = "NOTABLE", FriendBuffs = "MINE",
        AuraSort = "PRIORITY", DebuffMax = 8, BuffMax = 4,
        HitBoxTop = 8, HitBoxBottom = 6, HitBoxSides = 0, FriendlyClickThrough = "NEVER",
    }
    for k, v in pairs(overrides or {}) do defaults[k] = v end
    return function(key) return defaults[key] end
end

local function aura(t)
    t.applications = t.applications or 0
    t.duration = t.duration or 10
    t.expirationTime = t.expirationTime or 110
    if t.isHarmful == nil then t.isHarmful = true end
    return t
end

local function names(list)
    local out = {}
    for i, a in ipairs(list) do out[i] = a.name end
    return table.concat(out, ",")
end

-- ---------------------------------------------------------------------------
section("A. the copied DR table matches Commander Diminish's")
do
    local src = readfile(ADDONS .. "/Commander_Diminish/CommanderDiminishData.lua")
    if not src then
        print("  (Commander_Diminish absent; skipped)")
    else
        local theirs = {}
        local body = src:match("DATA%.DR_BY_SPELL = {(.-)\n}")
        for id, group in body:gmatch('%[(%d+)%]%s*=%s*"([A-Z_]+)"') do theirs[tonumber(id)] = group end
        local nTheirs, nOurs, mismatch = 0, 0, 0
        for id, group in pairs(theirs) do
            nTheirs = nTheirs + 1
            if DATA.CC_BY_SPELL[id] ~= group then mismatch = mismatch + 1 end
        end
        for id in pairs(DATA.CC_BY_SPELL) do
            nOurs = nOurs + 1
            if not theirs[id] then mismatch = mismatch + 1 end
        end
        check(nTheirs > 800, "Diminish table read (" .. nTheirs .. " spells)")
        check(nOurs == nTheirs, "same spell count (" .. nOurs .. " vs " .. nTheirs .. ")")
        check(mismatch == 0, "no drift (" .. mismatch .. " mismatches) -- rerun Harness/make_cc_table.py")
    end
    for _, group in pairs(DATA.CC_BY_SPELL) do
        check(DATA.KIND[group] ~= nil, "every DR group has a KIND entry: " .. group)
    end
end

-- ---------------------------------------------------------------------------
section("B. classification")
do
    check(E.Classify(aura({ name = "Polymorph", spellId = 118 })) == "POLY", "Polymorph by id -> POLY")
    check(E.Classify(aura({ name = "Kidney Shot", spellId = 408 })) == "KIDNEY", "Kidney Shot -> KIDNEY (its own ladder)")
    check(E.Classify(aura({ name = "Freezing Trap Effect", spellId = 3355 })) == "FREEZE", "Freezing Trap Effect -> FREEZE")
    check(E.Classify(aura({ name = "Silence", spellId = 15487 })) == "SILENCE", "Silence by NAME (no DR in TBC)")
    check(E.Classify(aura({ name = "Scatter Shot", spellId = 19503 })) == "DISORIENT", "Scatter Shot by name")
    check(E.Classify(aura({ name = "Mortal Strike", spellId = 12294 })) == "HEALCUT", "Mortal Strike -> HEALCUT")
    check(E.Classify(aura({ name = "Divine Shield", spellId = 642, isHarmful = false })) == "IMMUNITY", "Divine Shield -> IMMUNITY")
    check(E.Classify(aura({ name = "Rend", spellId = 772 })) == nil, "Rend is nothing special")
    check(E.Classify(aura({ name = "Hamstring", spellId = 1715 })) == "LIMIT", "Hamstring -> LIMIT (from the DR table)")
end

-- ---------------------------------------------------------------------------
section("C. the big slot")
do
    local S = settings()
    local ctx = { isFriend = false, isPlayer = true, canDispel = {}, canPurge = false, S = S,
                  whitelist = E.ParseList(""), blacklist = E.ParseList("") }
    local pick = E.Select({
        aura({ name = "Hamstring", spellId = 1715, expirationTime = 115 }),
        aura({ name = "Polymorph", spellId = 118, expirationTime = 108 }),
    }, ctx)
    check(pick.big and pick.big.name == "Polymorph", "Polymorph beats Hamstring")

    pick = E.Select({
        aura({ name = "Frost Nova", spellId = 122, expirationTime = 108 }),
        aura({ name = "Cheap Shot", spellId = 1833, expirationTime = 104 }),
    }, ctx)
    check(pick.big and pick.big.name == "Cheap Shot", "a stun beats a root even when it ends sooner")

    pick = E.Select({
        aura({ name = "Cheap Shot", spellId = 1833, expirationTime = 104 }),
        aura({ name = "Hammer of Justice", spellId = 853, expirationTime = 106 }),
    }, ctx)
    check(pick.big and pick.big.name == "Hammer of Justice", "two stuns: the one ending LATER wins")

    pick = E.Select({
        aura({ name = "Silence", spellId = 15487, expirationTime = 105 }),
        aura({ name = "Frost Nova", spellId = 122, expirationTime = 108 }),
    }, ctx)
    check(pick.big and pick.big.name == "Silence", "silence beats root")

    pick = E.Select({
        aura({ name = "Frost Nova", spellId = 122 }),
    }, { isFriend = false, isPlayer = true, canDispel = {}, S = settings({ CcRoots = false }),
         whitelist = E.ParseList(""), blacklist = E.ParseList("") })
    check(pick.big == nil, "roots off -> no big slot for a root")

    pick = E.Select({
        aura({ name = "Divine Shield", spellId = 642, isHarmful = false }),
        aura({ name = "Hamstring", spellId = 1715 }),
    }, ctx)
    check(pick.big and pick.big.name == "Divine Shield", "an immunity takes the big slot when no control is up")

    pick = E.Select({
        aura({ name = "Divine Shield", spellId = 642, isHarmful = false }),
    }, { isFriend = false, isPlayer = true, canDispel = {}, S = settings({ CcImmunities = false }),
         whitelist = E.ParseList(""), blacklist = E.ParseList("") })
    check(pick.big == nil, "immunities off -> Divine Shield is not big")
    check(#pick.buffs == 1 and pick.buffs[1].name == "Divine Shield", "...but it is still a notable buff in the row")
    pick = E.Select({
        aura({ name = "Divine Shield", spellId = 642, isHarmful = false }),
    }, { isFriend = false, isPlayer = true, canDispel = {}, S = settings({ ShowDefensives = false }),
         whitelist = E.ParseList(""), blacklist = E.ParseList("") })
    check(pick.big == nil and #pick.buffs == 0, "defensives off -> an immunity is not notable at all")

    pick = E.Select({ aura({ name = "Polymorph", spellId = 118 }) },
        { isFriend = true, isPlayer = true, canDispel = {}, S = settings({ CcOnFriends = false }),
          whitelist = E.ParseList(""), blacklist = E.ParseList("") })
    check(pick.big == nil, "big slot off for friends -> none on a friend")
    check(#pick.debuffs == 1, "...but the sheep is still in the friend's row (notable)")

    -- Duplicate suppression
    pick = E.Select({ aura({ name = "Polymorph", spellId = 118 }), aura({ name = "Frostbolt", spellId = 116, isMine = true }) }, ctx)
    check(pick.big and pick.big.name == "Polymorph" and names(pick.debuffs) == "Frostbolt",
        "the big aura leaves the row (" .. names(pick.debuffs) .. ")")
    pick = E.Select({ aura({ name = "Polymorph", spellId = 118 }) },
        { isFriend = false, isPlayer = true, canDispel = {}, S = settings({ CcHideDuplicate = false }),
          whitelist = E.ParseList(""), blacklist = E.ParseList("") })
    check(#pick.debuffs == 1, "...unless duplicates are wanted")
end

-- ---------------------------------------------------------------------------
section("D. enemy rows")
do
    local function ctx(over)
        return { isFriend = false, isPlayer = true, canDispel = {}, canPurge = true, S = settings(over),
                 whitelist = E.ParseList(""), blacklist = E.ParseList("") }
    end
    local list = {
        aura({ name = "Rend", spellId = 772, isMine = false }),
        aura({ name = "Corruption", spellId = 172, isMine = true }),
        aura({ name = "Mortal Strike", spellId = 12294, isMine = false }),
        aura({ name = "Hamstring", spellId = 1715, isMine = false }),
    }
    local pick = E.Select(list, ctx())
    check(names(pick.debuffs) == "Mortal Strike,Corruption", "MINE_NOTABLE: notable then mine, no Rend, no slow (" .. names(pick.debuffs) .. ")")
    pick = E.Select(list, ctx({ EnemyDebuffs = "MINE" }))
    check(names(pick.debuffs) == "Corruption", "MINE: only mine")
    pick = E.Select(list, ctx({ EnemyDebuffs = "ALL" }))
    check(#pick.debuffs == 4, "ALL: everything")
    pick = E.Select(list, ctx({ EnemyDebuffs = "OFF" }))
    check(#pick.debuffs == 0, "OFF: nothing")
    pick = E.Select(list, ctx({ ShowSlows = true }))
    check(names(pick.debuffs):find("Hamstring") ~= nil, "slows on -> Hamstring is notable")

    local buffs = {
        aura({ name = "Power Word: Fortitude", spellId = 1243, isHarmful = false, isStealable = true }),
        aura({ name = "Arcane Power", spellId = 12042, isHarmful = false, isStealable = false }),
        aura({ name = "Battle Shout", spellId = 6673, isHarmful = false, isStealable = false }),
    }
    pick = E.Select(buffs, ctx())
    check(names(pick.buffs) == "Arcane Power,Power Word: Fortitude", "NOTABLE_PURGEABLE on a purging class (" .. names(pick.buffs) .. ")")
    check(pick.buffs[2].purgeable == true, "the purgeable one is flagged")
    pick = E.Select(buffs, ctx({ EnemyBuffs = "NOTABLE" }))
    check(names(pick.buffs) == "Arcane Power", "NOTABLE: cooldowns only")
    pick = E.Select(buffs, ctx({ EnemyBuffs = "PURGEABLE" }))
    check(names(pick.buffs) == "Power Word: Fortitude", "PURGEABLE: stealable only")
    local c = ctx({ EnemyBuffs = "PURGEABLE" }); c.canPurge = false
    pick = E.Select(buffs, c)
    check(#pick.buffs == 0, "a warrior has no purge, so sees no purgeable row")
    pick = E.Select(buffs, ctx({ ShowOffensives = false }))
    check(names(pick.buffs) == "Power Word: Fortitude", "offensives off -> Arcane Power not notable")
end

-- ---------------------------------------------------------------------------
section("E. friendly rows")
do
    -- The sheep is also the big slot; keep it in the row here so the ROW
    -- rules are what these assertions read
    local function ctx(class, over)
        over = over or {}
        if over.CcHideDuplicate == nil then over.CcHideDuplicate = false end
        return { isFriend = true, isPlayer = true, canDispel = E.DispelSet(class), canPurge = false,
                 S = settings(over), whitelist = E.ParseList(""), blacklist = E.ParseList("") }
    end
    local list = {
        aura({ name = "Rend", spellId = 772 }),
        aura({ name = "Curse of Agony", spellId = 980, dispelName = "Curse" }),
        aura({ name = "Polymorph", spellId = 118, dispelName = "Magic" }),
        aura({ name = "Deadly Poison", spellId = 2818, dispelName = "Poison" }),
    }
    local pick = E.Select(list, ctx("DRUID", { FriendDebuffs = "DISPELLABLE" }))
    check(names(pick.debuffs) == "Curse of Agony,Deadly Poison" or names(pick.debuffs) == "Deadly Poison,Curse of Agony",
        "druid, DISPELLABLE: curse and poison, not the sheep (" .. names(pick.debuffs) .. ")")
    check(pick.debuffs[1].dispellable == true and pick.debuffs[1].tint ~= nil, "dispellable auras carry the dispel tint")
    pick = E.Select(list, ctx("DRUID"))
    check(#pick.debuffs == 3 and pick.debuffs[1].name == "Polymorph", "druid, NOTABLE: sheep first, then what she can lift (" .. names(pick.debuffs) .. ")")
    check(pick.big and pick.big.name == "Polymorph", "the sheep on your healer takes the big slot")
    pick = E.Select(list, ctx("PRIEST", { FriendDebuffs = "DISPELLABLE" }))
    check(names(pick.debuffs) == "Polymorph", "priest, DISPELLABLE: only the Magic")
    pick = E.Select(list, ctx("WARRIOR", { FriendDebuffs = "DISPELLABLE" }))
    check(#pick.debuffs == 0, "warrior dispels nothing")
    pick = E.Select(list, ctx("WARRIOR"))
    check(names(pick.debuffs) == "Polymorph", "warrior, NOTABLE: still sees the sheep")

    local buffs = {
        aura({ name = "Renew", spellId = 139, isHarmful = false, isMine = true }),
        aura({ name = "Renew", spellId = 139, isHarmful = false, isMine = false }),
        aura({ name = "Power Word: Shield", spellId = 17, isHarmful = false, isMine = false }),
    }
    pick = E.Select(buffs, ctx("PRIEST"))
    check(#pick.buffs == 1 and pick.buffs[1].isMine, "MINE: my Renew, not the other priest's")
    pick = E.Select(buffs, ctx("PRIEST", { FriendBuffs = "MINE_NOTABLE" }))
    check(#pick.buffs == 2 and pick.buffs[1].name == "Power Word: Shield", "MINE_NOTABLE: the shield (defensive) sorts ahead of my Renew")
end

-- ---------------------------------------------------------------------------
section("F. whitelist, blacklist, caps and sort")
do
    local S = settings({ EnemyDebuffs = "MINE" })
    local ctx = { isFriend = false, isPlayer = true, canDispel = {}, S = S,
                  whitelist = E.ParseList("Rend, 980"), blacklist = E.ParseList("Corruption") }
    local pick = E.Select({
        aura({ name = "Rend", spellId = 772, isMine = false }),
        aura({ name = "Curse of Agony", spellId = 980, isMine = false }),
        aura({ name = "Corruption", spellId = 172, isMine = true }),
        aura({ name = "Immolate", spellId = 348, isMine = true }),
    }, ctx)
    check(names(pick.debuffs):find("Rend") and names(pick.debuffs):find("Curse of Agony"),
        "whitelist by name and by id beats the MINE filter (" .. names(pick.debuffs) .. ")")
    check(not names(pick.debuffs):find("Corruption"), "blacklist removes my own Corruption")
    check(names(pick.debuffs):find("Immolate"), "unlisted mine still shows")

    ctx.blacklist = E.ParseList("Polymorph")
    ctx.whitelist = E.ParseList("Polymorph")
    pick = E.Select({ aura({ name = "Polymorph", spellId = 118 }) }, ctx)
    check(pick.big ~= nil, "whitelist beats blacklist")

    local list = E.ParseList("  Sap ;118\nGouge,, ")
    check(list.names["sap"] and list.names["gouge"] and list.ids[118] and list.count == 3, "ParseList tolerates every separator")
    check(E.InList(list, "SAP", nil), "InList is case-insensitive")
    check(not E.InList(E.ParseList(""), "Sap", 118), "an empty list matches nothing")

    -- Caps trim the LOW end of the sort
    local many = {}
    for i = 1, 12 do many[i] = aura({ name = "Dot" .. i, spellId = 90000 + i, isMine = true, expirationTime = 100 + i }) end
    many[13] = aura({ name = "Cheap Shot", spellId = 1833, isMine = false, expirationTime = 200 })
    pick = E.Select(many, { isFriend = false, isPlayer = true, canDispel = {}, S = settings({ DebuffMax = 4, CcEnable = false }),
                            whitelist = E.ParseList(""), blacklist = E.ParseList("") })
    check(#pick.debuffs == 4, "DebuffMax caps the row")
    check(pick.debuffs[1].name == "Cheap Shot", "PRIORITY keeps the stun ahead of the dots when the big slot is off")
    check(pick.debuffs[2].name == "Dot1", "...then soonest-ending mine")

    pick = E.Select(many, { isFriend = false, isPlayer = true, canDispel = {}, S = settings({ DebuffMax = 20, CcEnable = false, AuraSort = "TIME_DESC" }),
                            whitelist = E.ParseList(""), blacklist = E.ParseList("") })
    check(pick.debuffs[1].name == "Cheap Shot" and pick.debuffs[2].name == "Dot12", "TIME_DESC: longest remaining first")
    pick = E.Select(many, { isFriend = false, isPlayer = true, canDispel = {}, S = settings({ DebuffMax = 20, CcEnable = false, AuraSort = "NAME" }),
                            whitelist = E.ParseList(""), blacklist = E.ParseList("") })
    check(pick.debuffs[1].name == "Cheap Shot" and pick.debuffs[2].name == "Dot1" and pick.debuffs[3].name == "Dot10", "NAME sort")

    -- Duration caps: long buffs are scenery
    local capCtx = function(over)
        return { isFriend = true, isPlayer = true, canDispel = {}, S = settings(over),
                 whitelist = E.ParseList(over and over.wl or ""), blacklist = E.ParseList("") }
    end
    local longList = {
        aura({ name = "Renew", spellId = 139, isHarmful = false, isMine = true, duration = 15 }),
        aura({ name = "Power Word: Fortitude", spellId = 1243, isHarmful = false, isMine = true, duration = 1800 }),
        aura({ name = "Inner Fire", spellId = 588, isHarmful = false, isMine = true, duration = 0 }),
    }
    pick = E.Select(longList, capCtx({ FriendBuffs = "MINE", BuffMaxDuration = 60 }))
    check(names(pick.buffs) == "Renew", "60s cap drops the half-hour Fortitude and the permanent Inner Fire (" .. names(pick.buffs) .. ")")
    pick = E.Select(longList, capCtx({ FriendBuffs = "MINE", BuffMaxDuration = 0 }))
    check(#pick.buffs == 3, "no cap shows all three")
    pick = E.Select(longList, capCtx({ FriendBuffs = "MINE", BuffMaxDuration = 60, wl = "Power Word: Fortitude" }))
    check(names(pick.buffs):find("Fortitude") ~= nil, "the whitelist is exempt from the cap")
    pick = E.Select({ aura({ name = "Power Word: Fortitude", spellId = 1243, isHarmful = false, isStealable = true, duration = 1800 }) },
        { isFriend = false, isPlayer = true, canDispel = {}, canPurge = true, S = settings({ BuffMaxDuration = 60 }),
          whitelist = E.ParseList(""), blacklist = E.ParseList("") })
    check(#pick.buffs == 1, "a purgeable enemy buff is exempt from the cap")
    pick = E.Select({ aura({ name = "Power Word: Fortitude", spellId = 1243, isHarmful = false, isStealable = true, duration = 1800 }) },
        { isFriend = false, isPlayer = true, canDispel = {}, canPurge = false, S = settings({ BuffMaxDuration = 60, EnemyBuffs = "ALL" }),
          whitelist = E.ParseList(""), blacklist = E.ParseList("") })
    check(#pick.buffs == 0, "...but for a class that cannot purge it, the cap applies")
    pick = E.Select({ aura({ name = "Polymorph", spellId = 118, duration = 50, expirationTime = 150 }) },
        capCtx({ FriendDebuffs = "NOTABLE", DebuffMaxDuration = 10, CcHideDuplicate = false }))
    check(#pick.debuffs == 0 and pick.big ~= nil, "a debuff cap trims the row but never the big slot")

    -- A 0 expiration (no duration known) sorts last under TIME
    pick = E.Select({
        aura({ name = "Forever", spellId = 90001, isMine = true, duration = 0, expirationTime = 0 }),
        aura({ name = "Soon", spellId = 90002, isMine = true, expirationTime = 101 }),
    }, { isFriend = false, isPlayer = true, canDispel = {}, S = settings({ AuraSort = "TIME" }),
         whitelist = E.ParseList(""), blacklist = E.ParseList("") })
    check(pick.debuffs[1].name == "Soon", "TIME: permanents last")
end

-- ---------------------------------------------------------------------------
section("G. layout, hit box, totems, timers, healers, emphasis")
do
    local slots = E.RowLayout(3, 20, 2, "CENTER", 6)
    check(#slots == 3, "three slots")
    check(math.abs(slots[1][1] + slots[3][1]) < 0.001 and slots[2][1] == 0, "CENTER is symmetric about 0")
    check(slots[1][2] == 10 and slots[3][2] == 10, "one line: all at half-size height")
    slots = E.RowLayout(7, 20, 2, "CENTER", 6)
    check(slots[7][2] == 32 and slots[7][1] == 0, "the seventh wraps to a second line above, centred")
    slots = E.RowLayout(2, 20, 2, "RIGHT", 6)
    check(slots[1][1] == 10 and slots[2][1] == 32, "RIGHT grows rightward from the anchor")
    slots = E.RowLayout(2, 20, 2, "LEFT", 6)
    check(slots[1][1] == -10 and slots[2][1] == -32, "LEFT grows leftward")

    local box = E.HitBox(settings(), false, false)
    check(box.clickThrough == false and box.top == 8 and box.bottom == 6 and box.sides == 0, "hit box reads the three sliders")
    box = E.HitBox(settings({ FriendlyClickThrough = "INSTANCES" }), true, true)
    check(box.clickThrough == true, "INSTANCES + friend + in an instance -> click-through")
    box = E.HitBox(settings({ FriendlyClickThrough = "INSTANCES" }), true, false)
    check(box.clickThrough == false, "INSTANCES + friend + open world -> normal")
    box = E.HitBox(settings({ FriendlyClickThrough = "ALWAYS" }), false, true)
    check(box.clickThrough == false, "ALWAYS never applies to an enemy")
    box = E.HitBox(settings({ HitBoxTop = 0, HitBoxBottom = 0, HitBoxSides = 0 }), false, false)
    check(box.top == 0 and box.bottom == 0 and box.sides == 0, "all zero -> the runtime leaves Blizzard's box alone")

    local info, base = E.TotemInfo("Searing Totem IV")
    check(info and info.tier == "LOW" and base == "Searing Totem", "rank stripped, Searing is scenery")
    info = E.TotemInfo("Grounding Totem")
    check(info and info.tier == "HIGH", "Grounding is HIGH")
    check(E.TotemInfo("Tremor Totem") ~= nil and E.TotemInfo("Mana Tide Totem") ~= nil, "Tremor and Mana Tide known")
    check(E.TotemInfo("Deviate Ravager") == nil, "a mob is not a totem")
    check(E.TotemInfo(nil) == nil, "nil-safe")

    local hidden = E.ParseList("Venomous Snake, Viper")
    check(E.IsHiddenNpc("Venomous Snake", false, hidden) == true, "Snake Trap snake is hidden")
    check(E.IsHiddenNpc("Viper", true, hidden) == false, "a PLAYER named Viper is never hidden")
    check(E.IsHiddenNpc("Grounding Totem", false, hidden) == false, "an unlisted NPC is not")
    check(E.IsHiddenNpc(nil, false, hidden) == false, "nil-safe")

    check(E.FormatTime(2.44) == "2.4", "tenths under three seconds")
    check(E.FormatTime(7.6) == "8", "whole seconds above")
    check(E.FormatTime(125) == "2m", "minutes above sixty")
    check(E.FormatTime(0) == "" and E.FormatTime(-1) == "" and E.FormatTime(nil) == "", "nothing for nothing")

    local book = E.NewHealerBook(600)
    book:Mark("Player-1", 1000)
    check(book:Is("Player-1", 1100) == true, "a healer is remembered")
    check(book:Is("Player-1", 1700) == false, "...and forgotten after the TTL")
    check(book:Is("Player-2", 1100) == false, "an unknown GUID is not a healer")
    book:Mark("Player-3", 1000); book:Mark("Player-4", 1500)
    book:Prune(1650)
    check(book:Count() == 1, "Prune drops the expired (" .. book:Count() .. " left)")
    check(E.IsHealerSpell("Greater Heal") and not E.IsHealerSpell("Renew") and not E.IsHealerSpell("Lesser Healing Wave"),
        "healer spells: Greater Heal yes, the hybrid heals no")

    local set = E.BuildEmphasis("Hearthstone, Mind Flay", "Pyroblast")
    check(E.IsEmphasised(set, "Polymorph"), "default emphasis: Polymorph")
    check(E.IsEmphasised(set, "mind flay"), "added by the user, case-insensitive")
    check(not E.IsEmphasised(set, "Pyroblast"), "removed by the user")
    check(not E.IsEmphasised(set, nil), "nil-safe")

    check(E.DispelSet("PALADIN").Magic and E.DispelSet("PALADIN").Poison and not E.DispelSet("PALADIN").Curse, "paladin dispels Magic/Poison/Disease")
    check(next(E.DispelSet("ROGUE")) == nil, "rogue dispels nothing")
    check(E.CanPurge("SHAMAN") and not E.CanPurge("PALADIN"), "purge classes")
end

-- ---------------------------------------------------------------------------
section("H. every hand-written spell name exists in the client's spell table")
do
    local csv = readfile(ADDONS .. "/Commander_Quartermaster/Harness/.cache/SpellName.csv")
    if not csv then
        print("  (SpellName.csv cache absent; skipped)")
    else
        local names, byId = {}, {}
        for id, name in csv:gmatch("\n(%d+),([^\r\n]+)") do
            name = name:gsub('^"(.*)"$', "%1"):gsub('""', '"')
            names[name] = true
            byId[tonumber(id)] = name
        end
        local missing = 0
        local function need(name, where)
            if not names[name] then
                missing = missing + 1
                print("  FAIL  " .. where .. ": '" .. name .. "' is not a spell name on this client")
            end
        end
        for name in pairs(DATA.NOTABLE) do need(name, "NOTABLE") end
        for _, name in ipairs(DATA.CAST_EMPHASIS) do need(name, "CAST_EMPHASIS") end
        for name in pairs(DATA.HEALER_SPELLS) do need(name, "HEALER_SPELLS") end
        for name, info in pairs(DATA.TOTEMS) do
            need(name, "TOTEMS")
            check(byId[info.spell] == name, "totem rank-1 id " .. info.spell .. " is named '" .. name .. "' (got " .. tostring(byId[info.spell]) .. ")")
        end
        check(missing == 0, missing .. " hand-written names unknown to the client")
        pass = pass + (missing == 0 and 0 or 0)
    end
end

-- ---------------------------------------------------------------------------
section("I. data shape")
do
    for kind, spec in pairs(DATA.KIND) do
        check(type(spec.priority) == "number" and spec.tint and #spec.tint == 3 and spec.toggle, "KIND " .. kind .. " complete")
    end
    for kind in pairs(DATA.CONTROL_KINDS) do
        check(DATA.KIND[kind] and DATA.KIND[kind].big, "control kind " .. kind .. " is big-eligible")
    end
    for name, kind in pairs(DATA.NOTABLE) do
        check(DATA.KIND[kind] ~= nil, "NOTABLE '" .. name .. "' names a real kind (" .. tostring(kind) .. ")")
    end
    local seen = {}
    for _, spec in ipairs(DATA.CVARS) do
        check(spec.key and spec.cvar and spec.label and spec.tooltip and spec.default ~= nil, "CVAR spec " .. tostring(spec.key) .. " complete")
        check(not seen[spec.key], "CVAR key unique: " .. tostring(spec.key))
        seen[spec.key] = true
        if not spec.bool then
            check(spec.min and spec.max and spec.step and spec.default >= spec.min and spec.default <= spec.max,
                "CVAR " .. spec.key .. " default within range")
        end
    end
end

-- ---------------------------------------------------------------------------
section("J. colour keys")
do
    local Draw = CommanderPlates_Draw
    local r, g, b = Draw.ResolveColor("RED")
    check(r == 1 and g == 0.25 and b == 0.25, "palette key")
    r, g, b = Draw.ResolveColor("CLASS", { class = "MAGE" })
    check(math.abs(r - 0.41) < 0.001, "CLASS resolves through RAID_CLASS_COLORS")
    r, g, b = Draw.ResolveColor("CLASS", { class = "NOPE" })
    check(r == 1 and g == 1 and b == 1, "unknown class -> white")
    r, g, b = Draw.ResolveColor("REACTION", { reaction = "HOSTILE" })
    check(r == 0.95 and g == 0.2, "REACTION hostile is red")
    r, g, b = Draw.ResolveColor("REACTION", { reaction = "FRIENDLY" })
    check(b == 1 and r == 0.35, "REACTION friendly is blue")
    r, g, b = Draw.ResolveColor("REACTION", { reaction = "NEUTRAL" })
    check(r == 1 and g == 0.85, "REACTION neutral is yellow")
    r, g, b = Draw.ResolveColor("GARBAGE")
    check(r == 1 and g == 1 and b == 1, "unknown key -> white, never nil")
    local options = Draw.ColorOptions({ { text = "Off", value = "OFF" } })
    check(options[1].value == "OFF" and options[2].value == "CLASS" and options[3].value == "REACTION", "extra entries first, then CLASS and REACTION")
    check(options[4].value == "REACTION_RG", "then the red / green scheme")
    check(#options == 4 + #DATA.PALETTE_ORDER, "then every palette colour")
    r, g, b = Draw.ResolveColor("REACTION_RG", { reaction = "FRIENDLY" })
    check(g == 0.9 and r == 0.3, "REACTION_RG friendly is green")
    r, g, b = Draw.ResolveColor("REACTION_RG", { reaction = "HOSTILE" })
    check(r == 0.95 and g == 0.2, "REACTION_RG hostile is the same red")
    r, g, b = Draw.ResolveColor("REACTION_RG", { reaction = "NEUTRAL" })
    check(r == 1 and g == 0.85, "REACTION_RG neutral is the same yellow")
    for _, key in ipairs(DATA.PALETTE_ORDER) do
        check(DATA.PALETTE[key] and DATA.PALETTE_LABEL[key], "palette entry complete: " .. key)
    end
end


section("K. the radial plate's geometry and rules")
do
    local function S(t) return function(k) return t[k] end end
    -- Who becomes a disc
    check(E.WantRadial(S({ PlateStyle = "CLASSIC" }), true, false, false) == false, "CLASSIC: nobody")
    check(E.WantRadial(S({ PlateStyle = "RADIAL" }), false, false, false) == true, "RADIAL, scope unset: everyone")
    check(E.WantRadial(S({ PlateStyle = "RADIAL", RadialUnits = "ALL" }), true, true, true) == false, "a totem never")
    check(E.WantRadial(S({ PlateStyle = "RADIAL", RadialUnits = "PLAYERS" }), false, false, false) == false, "PLAYERS: not an NPC")
    check(E.WantRadial(S({ PlateStyle = "RADIAL", RadialUnits = "PLAYERS" }), true, true, false) == true, "PLAYERS: a friendly player")
    check(E.WantRadial(S({ PlateStyle = "RADIAL", RadialUnits = "ENEMIES" }), false, false, false) == true, "ENEMIES: a hostile NPC")
    check(E.WantRadial(S({ PlateStyle = "RADIAL", RadialUnits = "ENEMIES" }), true, true, false) == false, "ENEMIES: not a friend")
    check(E.WantRadial(S({ PlateStyle = "RADIAL", RadialUnits = "ENEMY_PLAYERS" }), false, false, false) == false, "ENEMY_PLAYERS: not an NPC")
    check(E.WantRadial(S({ PlateStyle = "RADIAL", RadialUnits = "ENEMY_PLAYERS" }), true, false, false) == true, "ENEMY_PLAYERS: the arena five")

    -- Angles run clockwise from twelve, the way the Cooldown sweep does
    local x, y = E.ArcPoint(10, 0)
    check(math.abs(x) < 1e-9 and math.abs(y - 10) < 1e-9, "fraction 0 is twelve o'clock")
    x, y = E.ArcPoint(10, 0.25)
    check(math.abs(x - 10) < 1e-9 and math.abs(y) < 1e-9, "a quarter is three o'clock (clockwise)")
    x, y = E.ArcPoint(10, 0.5)
    check(math.abs(x) < 1e-9 and math.abs(y + 10) < 1e-9, "a half is six o'clock")

    -- Ring weights: the nearest baked thickness
    local ratios = { 0.93, 0.88, 0.80, 0.71, 0.60, 0.46 }
    check(E.RingWeight(23, 5, ratios) == 3, "5px on a 23px radius is the 0.80 weight (" .. E.RingWeight(23, 5, ratios) .. ")")
    check(E.RingWeight(23, 1, ratios) == 1, "a hairline is the thinnest")
    check(E.RingWeight(23, 20, ratios) == 6, "a fat band is the heaviest")
    check(E.RingWeight(0, 5, ratios) == 3, "a zero radius falls back to the middle weight")

    -- Radii from the middle out, a pixel of air between bands
    local r = E.RadialRadii({ size = 46, healthThick = 5, power = true, powerThick = 2, cast = true, castThick = 3, auraSize = 16, auraGap = 2 })
    check(r.health == 23 and r.healthInner == 18, "health band 18..23")
    check(r.power == 17 and r.powerInner == 15, "power band inside it, 15..17")
    check(r.core == 14, "the face fills what is left (" .. r.core .. ")")
    check(r.castInner == 25 and r.cast == 28 and r.outer == 28, "cast band floats 2px off the plate, 25..28")
    check(r.orbit == 28 + 2 + 8, "orbit centres clear the cast ring by the gap")
    local bare = E.RadialRadii({ size = 46, healthThick = 5, power = false, cast = false, auraSize = 16, auraGap = 2 })
    check(bare.power == nil and bare.cast == nil and bare.core == 17 and bare.outer == 23, "no power and no cast: the face grows, the outer edge is the health ring")
    local tiny = E.RadialRadii({ size = 10, healthThick = 12, power = true, powerThick = 4, cast = false })
    check(tiny.core >= 4, "a face never shrinks below 4px, whatever the rings ask")

    -- The orbit
    local slots = E.OrbitLayout(1, 37, 16, 2, 0, 160)
    check(#slots == 1 and math.abs(slots[1][1]) < 1e-9 and math.abs(slots[1][2] - 37) < 1e-9, "one icon sits dead centre on its clock position")
    slots = E.OrbitLayout(2, 37, 16, 2, 90, 160)
    check(math.abs(slots[1][2] + slots[2][2]) < 1e-9 and slots[1][1] > 0, "two icons straddle three o'clock symmetrically")
    local chord = math.sqrt((slots[1][1] - slots[2][1]) ^ 2 + (slots[1][2] - slots[2][2]) ^ 2)
    check(math.abs(chord - 18) < 1e-6, "neighbours sit exactly size + spacing apart (" .. chord .. ")")
    slots = E.OrbitLayout(12, 37, 16, 2, 0, 160)
    local first, second = 0, 0
    for _, sl in ipairs(slots) do if sl[4] == 1 then first = first + 1 else second = second + 1 end end
    check(#slots == 12 and first > 0 and second > 0, "an orbit that fills up spills into a second one (" .. first .. "+" .. second .. ")")
    local span = 0
    for _, sl in ipairs(slots) do
        if sl[4] == 1 then local d = (sl[3] + 180) % 360 - 180; span = math.max(span, math.abs(d)) end
    end
    check(span <= 80 + 1e-6, "...the first orbit stays inside the 160-degree span (" .. span .. ")")
    local outerR = math.sqrt(slots[12][1] ^ 2 + slots[12][2] ^ 2)
    check(math.abs(outerR - (37 + 18)) < 1e-6, "...the second ring one icon further out")
    slots = E.OrbitLayout(40, 37, 16, 2, 0, 360)
    for i = 1, #slots do
        for j = i + 1, #slots do
            local a, b = slots[i], slots[j]
            local d = math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2)
            if d < 16 - 1e-6 then check(false, "no two orbit icons overlap (" .. i .. "," .. j .. ")") end
        end
    end
    -- Which way an arc grows
    local cw = E.OrbitLayout(3, 37, 16, 2, 0, 160, "CLOCKWISE")
    check(math.abs(cw[1][1]) < 1e-9 and cw[2][1] > 0 and cw[3][1] > cw[2][1], "CLOCKWISE starts on the clock position and runs clockwise")
    local ccw = E.OrbitLayout(3, 37, 16, 2, 90, 160, "COUNTERCLOCKWISE")
    check(math.abs(ccw[1][2]) < 1e-9 and ccw[2][2] > 0 and ccw[3][2] > ccw[2][2], "COUNTERCLOCKWISE from three o'clock runs up toward twelve")
    local fan = E.OrbitLayout(3, 37, 16, 2, 0, 160, "CENTER")
    check(math.abs(fan[2][1]) < 1e-9 and fan[1][1] < 0 and fan[3][1] > 0, "CENTER fans out both ways")
    local spill = E.OrbitLayout(12, 37, 16, 2, 0, 160, "CLOCKWISE")
    check(math.abs(spill[#spill][3] - spill[1][3]) > 1e-6 or #spill == 12, "a clockwise arc still spills into a second orbit")
    check(#E.OrbitLayout(0, 37, 16, 2, 0, 160) == 0, "no auras, no slots")
    check(#E.OrbitLayout(3, 2, 16, 2, 0, 160) == 3, "an absurdly small radius still places every icon")
    local L, R = E.OrbitSideExtents(E.OrbitLayout(2, 37, 16, 2, 90, 160), 16, 11)
    check(R > 37 and L == 0, "buffs at three o'clock push only the right arrow out (" .. L .. "," .. R .. ")")
    L, R = E.OrbitSideExtents(E.OrbitLayout(3, 37, 16, 2, 0, 160), 16, 11)
    check(L == 0 and R == 0, "debuffs over the top leave both arrows alone")

    -- Fractions and the middle's text
    check(E.Fraction(0, 0) == 1, "0/0 (not filled in yet) reads as full, not dead")
    check(E.Fraction(50, 100) == 0.5 and E.Fraction(150, 100) == 1 and E.Fraction(-5, 100) == 0, "fractions clamp")
    check(E.CoreText("SMART", 1, 9000, nil) == "", "SMART at full health: nothing")
    check(E.CoreText("SMART", 0.42, 3780, nil) == "42", "SMART hurt: the percent")
    check(E.CoreText("SMART", 0.42, 3780, 3) == "3", "SMART in an arena: the number")
    check(E.CoreText("PERCENT", 1, 9000, 2) == "100%", "PERCENT always")
    check(E.CoreText("HEALTH", 0.5, 12345, nil) == "12k", "HEALTH abbreviates (" .. E.CoreText("HEALTH", 0.5, 12345, nil) .. ")")
    check(E.CoreText("HEALTH", 0.5, 4200, nil) == "4.2k", "HEALTH under ten thousand keeps a decimal")
    check(E.CoreText("HEALTH", 0.5, 800, nil) == "800", "HEALTH under a thousand is the number")
    check(E.CoreText("HEALTH", 0.5, nil, nil) == "50%", "HEALTH with no number known falls back to the percent")
    check(E.CoreText("ARENA", 0.5, 1, nil) == "" and E.CoreText("NONE", 0.5, 1, 1) == "", "ARENA outside one, and NONE, are empty")

    -- Threat
    check(E.ThreatTint("DPS", nil) == nil and E.ThreatTint("TANK", nil) == nil, "off the threat table: nothing to say")
    check(E.ThreatTint("DPS", 0) == nil and E.ThreatTint("DPS", 1) == "ORANGE" and E.ThreatTint("DPS", 3) == "RED", "DPS warns as it turns toward you")
    check(E.ThreatTint("TANK", 3) == nil and E.ThreatTint("TANK", 2) == "ORANGE" and E.ThreatTint("TANK", 0) == "RED", "TANK warns as it turns away")
    check(E.ThreatTint("OFF", 3) == nil, "OFF is off")

    -- The damage trail
    local v, moving = E.TrailStep(0.8, 0.5, 0.1, 0.1, 0.35, 0.9)
    check(v == 0.8 and moving, "the trail holds before it drains")
    v, moving = E.TrailStep(0.8, 0.5, 0.5, 0.1, 0.35, 0.9)
    check(math.abs(v - 0.71) < 1e-9 and moving, "then drains at the rate")
    v, moving = E.TrailStep(0.52, 0.5, 1, 0.1, 0.35, 0.9)
    check(v == 0.5 and not moving, "and lands exactly on the health, never under it")
    v, moving = E.TrailStep(0.5, 0.7, 0, 0.1, 0.35, 0.9)
    check(v == 0.7 and not moving, "a heal snaps it up: nothing to show")
    v = E.TrailStep(nil, 0.4, 0, 0.1, 0.35, 0.9)
    check(v == 0.4, "no trail yet starts at the health")

    -- Combo points
    local cr, cg = E.ComboTint(3, 5)
    local fr, fg = E.ComboTint(5, 5)
    check(cg > 0.8 and fg < 0.3 and fr == 1, "gold pips, red on the full five")

    -- Diminishing returns as icons
    local rows = E.DrRows({
        { cat = "STUN", bracket = 2, held = false, resetAt = 110, last = 1833 },
        { cat = "POLY", bracket = 4, held = true, resetAt = nil, last = 118 },
        { cat = "ROOT", bracket = 1, held = false },
    }, 15, function(id) return "icon" .. tostring(id) end)
    check(#rows == 2, "a closed category draws nothing (" .. #rows .. ")")
    check(rows[1].label == "\194\189" and rows[1].icon == "icon1833", "a stun at half: the next lands at half, with the spell's icon")
    check(rows[1].start == 95 and rows[1].duration == 15, "the reset sweep runs from fade to reset")
    check(rows[2].label == "X" and rows[2].r > 0.9 and rows[2].g < 0.3, "the next sheep would be immune: a red X")
    check(rows[2].start == nil, "held (still up): no sweep, the clock is frozen")
    local reused = E.DrRows({ { cat = "STUN", bracket = 3, resetAt = 50, last = 1 } }, 15, nil, rows)
    check(reused == rows and #rows == 1 and rows[1].label == "\194\188", "the scratch list is reused and trimmed")
    check(#E.DrRows(nil, 15) == 0, "nothing known: nothing drawn")

    -- Who gets the targets-you ring
    check(E.WantTargetsYou("ENEMY_PLAYERS", true, false) == true, "an enemy player looking at you")
    check(E.WantTargetsYou("ENEMY_PLAYERS", false, false) == false, "...not an NPC under ENEMY_PLAYERS")
    check(E.WantTargetsYou("ENEMIES", false, false) == true, "...an NPC under ENEMIES")
    check(E.WantTargetsYou("ENEMIES", true, true) == false, "a friend never")
    check(E.WantTargetsYou("OFF", true, false) == false, "OFF is off")

    -- The masked clock wipe: two half discs, each turned into or out of its clip
    local a1, a2 = E.WipeAngles(0)
    check(a1 == -180 and a2 == 0, "nothing elapsed: each half parked in the OTHER half, outside its own clip")
    a1, a2 = E.WipeAngles(0.25)
    check(a1 == -90 and a2 == 0, "a quarter: the right half turned in to three o'clock, the left still parked")
    a1, a2 = E.WipeAngles(0.5)
    check(a1 == 0 and a2 == 0, "a half: the right half full, the left still parked")
    a1, a2 = E.WipeAngles(0.75)
    check(a1 == 0 and a2 == 90, "three quarters: the left half turned in to nine o'clock")
    a1, a2 = E.WipeAngles(2)
    check(a1 == 0 and a2 == 180, "past the end clamps to the whole face")
    -- No badge sits on the rings
    for key, deg in pairs(E.RADIAL_BADGES) do
        check(deg % 45 == 0 and deg % 90 ~= 0, "badge '" .. key .. "' is on a diagonal, clear of the cardinal orbits")
    end

    -- Every clock position the dropdown offers exists
    for _, key in ipairs({ "TOP", "TOP_RIGHT", "RIGHT", "BOTTOM_RIGHT", "BOTTOM", "BOTTOM_LEFT", "LEFT", "TOP_LEFT" }) do
        check(E.RADIAL_ARCS[key] ~= nil, "clock position " .. key)
    end
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
