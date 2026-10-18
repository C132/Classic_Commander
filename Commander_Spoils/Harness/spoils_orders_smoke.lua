-- Commander Spoils + the REAL Commander Orders (luajit).
--
--     /opt/homebrew/bin/luajit Commander_Spoils/Harness/spoils_orders_smoke.lua
--     SPOILS_RUNTIME=/tmp/mutant.lua luajit ...        (a mutated CommanderSpoils.lua)
--
-- spoils_harness.lua drives "Go to Farm" against a recording stand-in for
-- Orders. This boots the real thing over the client mock Orders' own
-- harnesses share (Commander_Orders/Harness/orders_mock.lua: this build's map
-- rows, the real Commander_Events settings framework and Go button), loads
-- Spoils' three files after Orders as the client does (Spoils lists
-- Commander_Orders in its OptionalDeps), and checks what the player gets:
--   A  loads clean beside Orders; nothing written but Spoils' own globals
--   B  /cspoils back: ONE waypoint (Spoils, farm) at the farm's start, the
--      farm tint, the arrow on it, Orders' own "Waypoint set" line once and
--      nothing of Spoils'; a second press moves the same record
--   C  refusals in Orders' words: Orders switched off says Orders' one line
--      (with the farm's place and its [Go] link), Spoils adds none; no farm,
--      a farm with no position: Spoils' own honest sentence, nothing asked
--   D  Go to Farm on the settings page is Commander Orders' Go button:
--      click = GoTo under (Spoils, farm), lit "Going to Farm" while the arrow
--      goes there, greyed with no farm, Shift-click shares the readable
--      line, Ctrl-click copies the /way line
--   E  Orders absent: the /way line, never a dead press

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then HERE = (os.getenv("PWD") or ".") .. "/" .. HERE end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local M = dofile(ADDONS .. "/Commander_Orders/Harness/orders_mock.lua")

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail ~= nil and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end
local function EQ(got, want, label)
    CHECK(got == want, label, "got " .. tostring(got) .. ", want " .. tostring(want))
end
local function Section(name, fn)
    local ok, err = pcall(fn)
    CHECK(ok, name .. ": ran to the end", err)
end

local SKIP = { CommanderOrdersPins = true, CommanderOrdersUI = true }
local GOLDSHIRE = { 1429, 0.42, 0.655 }
local FILES = { "CommanderSpoilsDB.lua", "CommanderSpoilsEngine.lua",
    os.getenv("SPOILS_RUNTIME") and "RUNTIME" or "CommanderSpoils.lua" }

local function Boot(opts)
    opts = opts or {}
    local files = {}
    for _, f in ipairs(FILES) do files[#files + 1] = f end
    if os.getenv("SPOILS_RUNTIME") then
        -- the mock loads paths relative to the addon folder: a mutant is
        -- copied beside nothing, so load it by hand after the other two
        files[3] = nil
    end
    return M.Boot({
        player = opts.player or GOLDSHIRE,
        skipFiles = SKIP,
        files = opts.noOrders and {} or nil,
        addons = { { name = "Commander_Spoils", files = files } },
        afterFiles = function()
            local mutant = os.getenv("SPOILS_RUNTIME")
            if mutant then
                local chunk, err = loadfile(mutant)
                if not chunk then M.loadErrors[#M.loadErrors + 1] = tostring(err) else
                    local ok, runErr = pcall(chunk)
                    if not ok then M.loadErrors[#M.loadErrors + 1] = tostring(runErr) end
                end
            end
        end,
    })
end

local function O() return rawget(_G, "CommanderOrders") end
local function NoErrors(label)
    CHECK(#M.errors == 0, label .. ": no errors", M.errors[1])
    CHECK(#M.loadErrors == 0, label .. ": no load errors", M.loadErrors[1])
end
local function Count(needle)
    local n = 0
    for _, line in ipairs(M.prints) do
        if tostring(line):find(needle, 1, true) then n = n + 1 end
    end
    return n
end
local function FarmRecords()
    local out = {}
    for _, wp in ipairs(O().List({ source = "Spoils" })) do out[#out + 1] = wp end
    return out
end
local function Widget(text)
    for _, w in ipairs(M.W.widgets) do
        if rawget(w, "__text") == text and rawget(w, "_goOpts") then return w end
    end
    return nil
end

-- ===========================================================================
-- A  loads clean
-- ===========================================================================
Section("A", function()
    Boot()
    NoErrors("A")
    EQ(type(CommanderSpoils_BackToFarm), "function", "A: /cspoils back's function is there")
    EQ(type(CommanderSpoilsEngine.FarmSpot), "function", "A: the engine hands out the farm's spot")
    local allowed = {}
    for name in ([[CommanderSpoilsDB CommanderSpoilsData CommanderSpoilsEngine COMMANDER_SPOILS_EVENTS
        CommanderSpoils_Suppression CommanderSpoils_Ready CommanderSpoils_Toggle CommanderSpoils_Report
        CommanderSpoils_Wipe CommanderSpoils_ToggleFarm CommanderSpoils_BackToFarm CommanderSpoils_Test
        CommanderSpoils_PrintSize CommanderSpoils_RollNeed CommanderSpoils_RollGreed CommanderSpoils_RollPass
        CommanderSpoils_PassAll CommanderSpoils_CycleRoll]]):gmatch("[%w_]+") do allowed[name] = true end
    for _, w in ipairs(M.writes) do
        if w.phase == "addon:Commander_Spoils" then
            CHECK(allowed[w.name] or w.name:sub(1, 8) == "BINDING_" or w.name:sub(1, 6) == "SLASH_"
                or w.name:sub(1, 14) == "CommanderSpoil",
                "A: Spoils writes only its own globals", w.name)
        end
    end
end)

-- ===========================================================================
-- B  /cspoils back through the real GoTo
-- ===========================================================================
Section("B", function()
    Boot()
    CommanderSpoils_ToggleFarm()
    CHECK(CommanderSpoilsEngine.FarmActive(), "B: a farm started where you stand")
    local spot = CommanderSpoilsEngine.FarmSpot()
    CHECK(spot and spot.map == 1429, "B: ...on the map you stand on", spot and spot.map)
    M.SetPlayer(1429, 0.30, 0.40)        -- walked off to a vendor
    M.Frame()
    M.ClearLog()
    local ok, uid = CommanderSpoils_BackToFarm()
    M.Frame()
    EQ(ok, true, "B: Orders took it")
    local list = FarmRecords()
    EQ(#list, 1, "B: one waypoint")
    local wp = list[1]
    EQ(wp and wp.uid, uid, "B: ...the uid that came back")
    EQ(wp and wp.key, "farm", "B: owned as (Spoils, farm)")
    EQ(wp and wp.icon, "FARM", "B: in the farm tint")
    CHECK(wp and math.abs(wp.x - spot.x) < 1e-9 and math.abs(wp.y - spot.y) < 1e-9, "B: at the farm's start")
    EQ(wp and wp.title, spot.title, "B: titled after the farm")
    EQ(O().Active() and O().Active().uid, uid, "B: the arrow points back to the farm")
    CHECK(O().IsGoing("Spoils", "farm"), "B: Orders says the arrow is going to the farm")
    EQ(Count("Waypoint set: " .. spot.title), 1, "B: Orders' own \"Waypoint set\" line, once")
    EQ(Count("Commander Spoils"), 0, "B: ...and no line of Spoils' own")
    -- Again: the same record, not a twin
    local ok2, uid2 = CommanderSpoils_BackToFarm()
    EQ(ok2 and uid2, uid, "B: a second press is the same waypoint")
    EQ(#FarmRecords(), 1, "B: ...still one")
    CHECK(wp and wp.persistent == false, "B: session-only, a consumer mark")
    NoErrors("B")
end)

-- ===========================================================================
-- C  refusals
-- ===========================================================================
Section("C", function()
    Boot()
    M.ClearLog()
    local ok, why = CommanderSpoils_BackToFarm()
    EQ(why, "nofarm", "C: no farm, nothing asked")
    EQ(#O().List({ source = "Spoils" }), 0, "C: ...and nothing made")
    EQ(Count("no farm is running"), 1, "C: ...and Spoils says so in a sentence")
    CommanderSpoils_ToggleFarm()
    CommanderOrdersDB.EnableOrders = false
    M.ClearLog()
    ok, why = CommanderSpoils_BackToFarm()
    EQ(ok, false, "C: Orders switched off: no waypoint")
    EQ(why, "disabled", "C: ...Orders' reason code")
    EQ(#M.prints, 1, "C: ONE line", table.concat(M.prints, " / "))
    local line = M.prints[1] or ""
    CHECK(line:find(O().Reason("disabled"), 1, true) ~= nil, "C: ...in Orders' words", line)
    CHECK(line:find("Farm: ", 1, true) ~= nil, "C: ...naming the farm", line)
    CHECK(line:find("|Haddon:CommanderOrders:", 1, true) ~= nil, "C: ...with a [Go] link to it", line)
    EQ(Count("Commander Spoils"), 0, "C: ...and nothing of Spoils' own")
    CommanderOrdersDB.EnableOrders = true
    -- A farm with no map position (an instance)
    CommanderSpoils_ToggleFarm()
    M.SetNoPosition(true)
    CommanderSpoils_ToggleFarm()
    M.ClearLog()
    ok, why = CommanderSpoils_BackToFarm()
    EQ(why, "noposition", "C: a farm with no position refuses")
    EQ(#O().List({ source = "Spoils" }), 0, "C: ...asking Orders for nothing")
    M.SetNoPosition(false)
    NoErrors("C")
end)

-- ===========================================================================
-- D  Go to Farm on the settings page
-- ===========================================================================
Section("D", function()
    Boot()
    local go = Widget("Go to Farm")
    CHECK(go ~= nil, "D: the settings page has Go to Farm, Orders' Go button")
    if not go then return end
    EQ(go._goOpts.source, "Spoils", "D: source Spoils")
    EQ(go._goOpts.key, "farm", "D: key farm, the record /cspoils back moves")
    go:Refresh()
    CHECK(not go:IsEnabled(), "D: greyed with no farm running")
    M.Hover(go)
    local tip = table.concat(M.tooltip, "\n")
    CHECK(tip:find(O().Reason("nowhere"), 1, true) ~= nil, "D: ...the reason in its tooltip", tip)
    CommanderSpoils_ToggleFarm()
    local spot = CommanderSpoilsEngine.FarmSpot()
    M.SetPlayer(1429, 0.30, 0.40)
    go:Refresh()
    CHECK(go:IsEnabled(), "D: enabled once a farm with a place runs")
    for i = #M.tooltip, 1, -1 do M.tooltip[i] = nil end
    M.Hover(go)
    tip = table.concat(M.tooltip, "\n")
    CHECK(tip:find("Go to: " .. spot.title, 1, true) ~= nil, "D: its tooltip names where it goes", tip)
    CHECK(tip:find("Shift-click: share in chat. Ctrl-click: copy a /way line.", 1, true) ~= nil,
        "D: ...and the gestures", tip)
    -- (the settings page is not on screen in the mock: the button's own
    -- OnClick, as a click on the page would run it)
    local function Click() go.__scripts.OnClick(go, "LeftButton", false) end
    M.ClearLog()
    Click()
    M.Frame()
    local wp = O().R.Store():ByKey("Spoils", "farm")
    CHECK(wp ~= nil, "D: click = GoTo under (Spoils, farm)")
    EQ(O().Active() and O().Active().uid, wp and wp.uid, "D: ...the arrow on it")
    EQ(go.__text, "Going to Farm", "D: lit while the arrow goes there")
    -- the same record as /cspoils back
    local _, uid = CommanderSpoils_BackToFarm()
    EQ(uid, wp and wp.uid, "D: /cspoils back moves the same waypoint")
    -- Ctrl: the /way line in Orders' copy box
    M.SetModifier("CTRL", true)
    Click()
    M.SetModifier("CTRL", false)
    EQ(O().R.ArrowState().copyText, O().WayLineFor(spot.map, spot.x, spot.y, spot.title),
        "D: Ctrl-click: the /way line in the copy box")
    -- Shift: the readable line in chat (/say, solo)
    for i = #M.chat, 1, -1 do M.chat[i] = nil end
    M.SetModifier("SHIFT", true)
    Click()
    M.SetModifier("SHIFT", false)
    local said = M.chat[#M.chat]
    EQ(said and said.text, O().ChatText(spot.map, spot.x, spot.y, spot.title), "D: Shift-click: the readable line")
    EQ(said and said.chatType, "SAY", "D: ...in /say when solo")
    -- The arrow leaves: the button goes back to its words
    O().ClearArrow()
    M.Frame()
    go:Refresh()
    EQ(go.__text, "Go to Farm", "D: back to its words when the arrow leaves")
    NoErrors("D")
end)

-- ===========================================================================
-- E  Orders absent
-- ===========================================================================
Section("E", function()
    Boot({ noOrders = true })
    CHECK(rawget(_G, "CommanderOrders") == nil or type(CommanderOrders.GoTo) ~= "function", "E: (no Orders)")
    CommanderSpoils_ToggleFarm()
    local spot = CommanderSpoilsEngine.FarmSpot()
    M.ClearLog()
    local ok, why = CommanderSpoils_BackToFarm()
    EQ(why, "absent", "E: no Orders, no waypoint")
    local line = M.prints[#M.prints] or ""
    CHECK(line:find(string.format("/way #%d %.2f %.2f %s", spot.map, spot.x * 100, spot.y * 100, spot.title), 1, true),
        "E: ...but the /way line", line)
    NoErrors("E")
end)

-- Plain ASCII in what Spoils shows for the farm (suite D11)
Section("F", function()
    for _, file in ipairs({ "CommanderSpoils.lua", "CommanderSpoilsDB.lua", "CommanderSpoilsEngine.lua" }) do
        local f = io.open(ADDONS .. "/Commander_Spoils/" .. file, "r")
        local src = f:read("*a")
        f:close()
        for _, fn in ipairs({ "function CommanderSpoils_BackToFarm", "function E.FarmSpot", "local function GoButton" }) do
            local at = src:find(fn, 1, true)
            if at then
                local body = src:sub(at, (src:find("\nend\n", at, true) or #src))
                CHECK(not body:find("[\128-\255]"), "F: " .. fn .. " is plain ASCII (D11)")
            end
        end
    end
end)

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
