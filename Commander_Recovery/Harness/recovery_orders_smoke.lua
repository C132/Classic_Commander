-- Commander Recovery + the REAL Commander Orders (luajit).
--
--     luajit Commander_Recovery/Harness/recovery_orders_smoke.lua
--     RECOVERY_RUNTIME=/tmp/mutant.lua RECOVERY_DB=/tmp/mutant_db.lua luajit ...   (mutation runs)
--
-- recovery_release_smoke.lua tests Recovery against a recording stand-in for
-- Orders. This one boots the real thing: Commander_Orders/Harness/orders_mock.lua
-- (the WoW client Orders' own harnesses share, with this build's map rows and
-- the real Commander_Events settings framework), every Orders file in TOC
-- order, and then Recovery's two files the way the client loads them --
-- after Orders' ADDON_LOADED, because Recovery lists Commander_Orders in its
-- OptionalDeps. Every boot is a fresh client, so a relog is two boots with
-- the saved variables carried between them.
--
-- What it proves (2.3.0, the corpse arrow handed to Orders):
--   A  a 2.2 player's "Corpse Run Order: off" becomes Orders' CorpseArrow
--      off at the first login, the old keys are dropped, and Orders' saved
--      variables gain nothing else
--   B  with Orders not loaded the choice is KEPT, and handed over at the
--      first login where Orders is there
--   C  a death and release in the open world: exactly one corpse waypoint
--      (Orders' own), no legacy order, the player's own pinned waypoint
--      untouched and the arrow handed back to it on resurrection;
--      Recovery's "follow the arrow" line once, a frame after the release
--   D  Feign Death: no casualty from Recovery, no corpse from Orders
--   E  a battleground death: Orders draws no corpse arrow, so Recovery says
--      nothing about one
--   F  Recovery's settings checkbox reads and writes Orders' setting

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then HERE = (os.getenv("PWD") or ".") .. "/" .. HERE end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local M = dofile(ADDONS .. "/Commander_Orders/Harness/orders_mock.lua")
local RECOVERY_DB = os.getenv("RECOVERY_DB") or (ADDONS .. "/Commander_Recovery/CommanderRecoveryDB.lua")
local RECOVERY_RUNTIME = os.getenv("RECOVERY_RUNTIME") or (ADDONS .. "/Commander_Recovery/CommanderRecovery.lua")

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail ~= nil and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end

local GOLDSHIRE = { 1429, 0.42, 0.655 }
local SKIP = { CommanderOrdersPins = true, CommanderOrdersUI = true }

-- The client's load order for an addon with OptionalDeps: Commander_Orders:
-- Orders' files and ADDON_LOADED first, then Recovery's files and its own
-- ADDON_LOADED, then PLAYER_LOGIN for everyone. Recovery's client calls the
-- Orders mock does not model are added before anything loads.
local loadErrors = {}
local function Boot(opts)
    opts = opts or {}
    loadErrors = {}
    local userBefore = opts.before
    opts.before = function(m, w)
        rawset(_G, "GetZoneText", function() return "Elwynn Forest" end)
        rawset(_G, "RepopMe", function() end)
        rawset(_G, "GetBattlefieldWinner", function() return nil end)
        rawset(_G, "ResurrectGetOfferer", function() return nil end)
        if userBefore then userBefore(m, w) end
    end
    opts.afterFiles = function()
        local hook = CreateFrame("Frame")
        hook:RegisterEvent("ADDON_LOADED")
        hook:SetScript("OnEvent", function(_, _, name)
            if name ~= "Commander_Orders" then return end
            for _, path in ipairs({ RECOVERY_DB, RECOVERY_RUNTIME }) do
                local chunk, err = loadfile(path)
                if not chunk then
                    loadErrors[#loadErrors + 1] = tostring(err)
                else
                    local ok, runErr = pcall(chunk)
                    if not ok then loadErrors[#loadErrors + 1] = tostring(runErr) end
                end
            end
            M.Fire("ADDON_LOADED", "Commander_Recovery")
        end)
    end
    opts.skipFiles = opts.skipFiles or SKIP
    local w = M.Boot(opts)
    M.Frame()
    return w
end

-- A saved variable as the client writes it and reads it back
local function Saved(name)
    local v = rawget(_G, name)
    if type(v) ~= "table" then return nil end
    return M.Deserialize(M.Serialize(v))
end

local function Printed(needle)
    local n = 0
    for _, line in ipairs(M.prints) do
        if tostring(line):find(needle, 1, true) then n = n + 1 end
    end
    return n
end

local function NoErrors(label)
    CHECK(#M.errors == 0, label .. ": no errors", M.errors[1])
    CHECK(#M.loadErrors == 0 and #loadErrors == 0, label .. ": no load errors", M.loadErrors[1] or loadErrors[1])
end

local function O() return rawget(_G, "CommanderOrders") end

local OLD_RECOVERY = {
    EnableRecovery = true, DeathReport = true, CorpseOrder = false, RecoverySound = true,
    AutoRelease = true, AutoReleaseArena = false, AutoReleaseDelay = 1,
    IssuedOrder = { mapID = 1429, x = 0.4199999999999999, y = 0.655 },
}

-- ===========================================================================
-- A. The migration, Orders present
-- ===========================================================================
do
    Boot({ player = GOLDSHIRE, saved = { CommanderRecoveryDB = OLD_RECOVERY } })
    NoErrors("A")
    CHECK(type(O()) == "table" and O().CorpseArrow() == false,
        "A: a 2.2 'Corpse Run Order: off' is Orders' CorpseArrow off after the first login")
    CHECK(CommanderOrdersDB and CommanderOrdersDB.CorpseArrow == false, "A: ...in Orders' own saved setting")
    CHECK(CommanderRecoveryDB.CorpseOrder == nil and CommanderRecoveryDB.IssuedOrder == nil,
        "A: Recovery's old keys are dropped")
    CHECK(CommanderRecoveryDB.AutoRelease == true and CommanderRecoveryDB.DeathReport == true,
        "A: everything else Recovery kept is untouched")
    CHECK(CommanderOrdersDB.Waypoint == nil, "A: Recovery wrote nothing else into Orders' saved variables")
    -- A second login changes nothing (the migration is idempotent)
    local orders, recovery = Saved("CommanderOrdersDB"), Saved("CommanderRecoveryDB")
    recovery.CorpseOrder = nil
    orders.CorpseArrow = true      -- the player turned it back on in Orders since
    Boot({ player = GOLDSHIRE, saved = { CommanderOrdersDB = orders, CommanderRecoveryDB = recovery } })
    CHECK(O().CorpseArrow() == true, "A: a later login leaves the player's own choice in Orders alone")
    NoErrors("A2")
    -- The default 2.2 player (the option on): nothing to hand over
    local onPlayer = {}
    for k, v in pairs(OLD_RECOVERY) do onPlayer[k] = v end
    onPlayer.CorpseOrder = true
    Boot({ player = GOLDSHIRE, saved = { CommanderRecoveryDB = onPlayer } })
    CHECK(O().CorpseArrow() == true and CommanderRecoveryDB.CorpseOrder == nil,
        "A: a 2.2 'Corpse Run Order: on' leaves Orders' corpse arrow on and drops the key")
    NoErrors("A3")
end

-- ===========================================================================
-- B. Orders not loaded at the first 2.3 login: the choice waits for it
-- ===========================================================================
do
    Boot({ player = GOLDSHIRE, files = {}, saved = { CommanderRecoveryDB = OLD_RECOVERY } })
    CHECK(O() == nil, "B: (Orders not loaded)")
    CHECK(CommanderRecoveryDB.CorpseOrder == false, "B: without Orders the old choice is kept, not lost")
    CHECK(CommanderRecoveryDB.IssuedOrder == nil, "B: the stale IssuedOrder goes anyway")
    NoErrors("B")
    local recovery = Saved("CommanderRecoveryDB")
    Boot({ player = GOLDSHIRE, saved = { CommanderRecoveryDB = recovery } })
    CHECK(O().CorpseArrow() == false and CommanderRecoveryDB.CorpseOrder == nil,
        "B: ...and handed to Orders at the first login where Orders is there")
    NoErrors("B2")
end

-- ===========================================================================
-- C. A corpse run in the open world
-- ===========================================================================
do
    Boot({ player = GOLDSHIRE })
    local mine = O().Add({ map = 1429, x = 0.48, y = 0.42, title = "My mark" })
    M.Advance(0.3)
    CHECK(mine ~= nil and O().Active() and O().Active().uid == mine, "C: (the player follows their own mark)")
    M.ClearLog()
    M.SetLife("DEAD")
    M.Fire("PLAYER_DEAD")
    CHECK(Printed("last unit lost in Elwynn Forest") == 1, "C: Recovery reports the casualty")
    M.SetCorpse(GOLDSHIRE[1], GOLDSHIRE[2], GOLDSHIRE[3])
    M.SetPlayer(1429, 0.30, 0.75)
    M.SetLife("GHOST")
    M.Fire("PLAYER_ALIVE")
    CHECK(Printed("follow the Commander Orders arrow") == 0, "C: nothing promised inside the release event")
    M.Advance(0.3)
    local corpses = O().List({ kind = "corpse" })
    CHECK(#corpses == 1 and corpses[1].source == "corpse", "C: exactly one corpse waypoint, Orders' own", #corpses)
    CHECK(#O().List({ source = "legacy" }) == 0, "C: no legacy order (Recovery issues none)")
    CHECK(#O().List() == 2, "C: the corpse and the player's mark, nothing else", #O().List())
    local active = O().Active()
    CHECK(active and active.kind == "corpse", "C: the ghost follows the corpse", active and active.kind)
    CHECK(O().Get(mine) ~= nil, "C: the player's own mark survives the death")
    CHECK(Printed("corpse located -- follow the Commander Orders arrow, soldier") == 1,
        "C: Recovery says follow the arrow, once, a frame after the release")
    M.Advance(2)
    CHECK(Printed("follow the Commander Orders arrow") == 1, "C: ...and only once")
    M.SetLife("ALIVE")
    M.Fire("PLAYER_UNGHOST")
    M.Advance(0.3)
    CHECK(#O().List({ kind = "corpse" }) == 0, "C: alive: the corpse waypoint is gone")
    active = O().Active()
    CHECK(active and active.uid == mine, "C: and the arrow is back on the player's mark", active and active.title)
    CHECK(Printed("unit recovered") == 1, "C: Recovery confirms the recovery")
    CHECK(Printed("order cleared") == 0, "C: no legacy 'order cleared' along the way")
    NoErrors("C")
end

-- ===========================================================================
-- D. Feign Death
-- ===========================================================================
do
    Boot({ player = GOLDSHIRE })
    M.ClearLog()
    M.SetLife("FEIGN")
    M.Fire("PLAYER_DEAD")
    M.Advance(0.3)
    CHECK(Printed("casualt") == 0 and Printed("unit lost") == 0, "D: Feign Death is no casualty")
    CHECK(#O().List({ kind = "corpse" }) == 0, "D: ...and no corpse")
    M.SetLife("ALIVE")
    M.Fire("PLAYER_ALIVE")
    CHECK(Printed("unit recovered") == 0, "D: getting up from it is no recovery")
    M.SetLife("DEAD")
    M.Fire("PLAYER_DEAD")
    CHECK(Printed("last unit lost in") == 1, "D: the next real death is still reported")
    NoErrors("D")
end

-- ===========================================================================
-- E. A battleground death: no corpse arrow, so no promise of one
-- ===========================================================================
do
    Boot({ player = GOLDSHIRE, before = function()
        rawset(_G, "C_DeathInfo", nil)
    end })
    rawset(_G, "C_DeathInfo", {
        GetCorpseMapPosition = function() return CreateVector2D(0.42, 0.655) end,
        GetSelfResurrectOptions = function() return {} end,
    })
    M.SetInstance("pvp")
    M.ClearLog()
    M.SetLife("DEAD")
    M.Fire("PLAYER_DEAD")
    M.SetLife("GHOST")
    M.Fire("PLAYER_ALIVE")
    M.Advance(0.5)
    CHECK(#O().List({ kind = "corpse" }) == 0, "E: Orders draws no corpse arrow in a battleground")
    CHECK(Printed("follow the Commander Orders arrow") == 0, "E: so Recovery promises none")
    M.SetLife("ALIVE")
    M.Fire("PLAYER_UNGHOST")
    M.SetInstance(nil)
    NoErrors("E")
end

-- ===========================================================================
-- F. The settings checkbox is Orders' CorpseArrow
-- ===========================================================================
do
    Boot({ player = GOLDSHIRE })
    local box, old
    for _, w in ipairs(M.W.widgets) do
        local text = w.Text and w.Text.__text
        if text == "Corpse Arrow (Commander Orders)" then box = w end
        if text == "Corpse Run Order" then old = w end
    end
    CHECK(box ~= nil and old == nil, "F: Recovery's page carries Corpse Arrow (Commander Orders), not Corpse Run Order")
    if box then
        box.GetChecked = function() return false end
        box.__scripts.OnClick(box)
        CHECK(O().CorpseArrow() == false and CommanderOrdersDB.CorpseArrow == false,
            "F: unticking it turns Orders' own setting off")
        box.GetChecked = function() return true end
        box.__scripts.OnClick(box)
        CHECK(O().CorpseArrow() == true, "F: ticking it turns it back on")
        CHECK(CommanderRecoveryDB.CorpseOrder == nil, "F: Recovery keeps no copy")
    end
    -- What Recovery's files wrote: its own globals only
    local mine = {}
    for _, w in ipairs(M.writes) do
        if w.name:find("Recovery", 1, true) or w.name:find("RECOVERY", 1, true) then mine[w.name] = true end
    end
    CHECK(mine.CommanderRecoveryDB and mine.COMMANDER_RECOVERY_EVENTS and mine.CommanderRecovery_Report
        and mine.CommanderRecovery_Test, "F: Recovery's globals are its own")
    NoErrors("F")
end

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
